# JIT perf notes

A running set of findings from optimizing numbl's loop JIT against the
chunkie ptloop pattern (`flagnear_rectangle`'s per-point BVH walk). The
goal is to make tight scalar loops with tensor indexing run within a
small factor of MATLAB's JIT.

This document is the **permanent reference** for what's been changed in
numbl, why, and what we've learned about V8 along the way. Read it
before changing the JIT — most "obvious" speedups are not actually wins,
and several non-obvious things (like how `jitHelpers` is constructed)
are hidden cliffs.

## Architecture: how numbl's JIT works today

`numbl run` executes a parsed AST in an interpreter. When the
interpreter encounters a `for` or `while` statement, `tryJitFor` /
`tryJitWhile` ([`src/numbl-core/interpreter/jit/jitLoop.ts`](../../numbl/src/numbl-core/interpreter/jit/jitLoop.ts))
attempts to compile the loop into a JS function and run it. If
compilation succeeds the JS function is cached keyed by `(file:offset,
input types)` and reused on subsequent invocations. If compilation
fails — because the body uses a feature the lowering doesn't yet
support — the cache stores a sentinel and the loop runs interpreted from
then on.

The pipeline:

1. **Loop analysis** — [`jitLoopAnalysis.ts`](../../numbl/src/numbl-core/interpreter/jit/jitLoopAnalysis.ts)
   walks the AST collecting `inputs` (variables read from outer scope)
   and `outputs` (variables assigned in the body).
2. **Lowering** — [`jitLower.ts`](../../numbl/src/numbl-core/interpreter/jit/jitLower.ts)
   walks the AST again, propagating types through statements and
   expressions, and produces a typed JIT IR. Bails to `null` on any
   unsupported construct (whole-loop fallback to interpreter).
3. **Codegen** — [`jitCodegen.ts`](../../numbl/src/numbl-core/interpreter/jit/jitCodegen.ts)
   walks the IR producing JS source. Produces a function body string
   that gets wrapped in `new Function("$h", "$rt", ...inputs, body)`.
4. **Execution + writeback** — `executeAndWriteBack` calls the compiled
   function and stores the returned values back into `interp.env`.

The compiled function receives `$h` (the helpers object) and `$rt` (the
runtime, used for line tracking). Helper calls are emitted as
`$h.idx2r_h(...)` and the like. The output set is collected into a
return array which the runtime writes back to the interpreter env.

## Methodology: the standalone JS bisection trick

Most of the perf wins came from this exact loop:

1. Generate the JIT JS via `numbl run script.m --dump-js out.js` and
   read what's actually being emitted.
2. Copy the inner loop body into a standalone `.mjs` file with hand-rolled
   data setup. **Run that with `node`.** This is the benchmark
   apples-to-apples — no numbl runtime, no setup overhead, no network,
   just V8 executing the JS we generated.
3. Make small variations (delete SetLocs, swap helper for inline,
   change return shape, …) and measure. The diff between two close
   variants tells you exactly what V8 cares about.

The key insight: **before changing the codegen, prove the new code is
faster by writing it by hand and running it under bare V8**. This
turned several "this should help" guesses into measured wins or
measured no-ops.

The standalone tests are throwaway — they live under `/tmp/` in the
running session. Don't bother saving them; the patterns recur and you'll
write the next one in two minutes.

## Findings about V8 (what the JIT must produce)

These are general rules learned the hard way during this work. They are
not assumptions — each was verified with a standalone test.

### 1. Helpers object hidden class is everything

If the `$h` object is in V8 dictionary mode (because it was mutated
after construction), every `$h.foo(...)` call inside a hot loop pays a
hash-table lookup and V8 stops inlining the helper. **Single
biggest perf cliff in the whole JIT.** Mutating jitHelpers via
`Object.assign` after the initial construction, or via `h[name] = fn`
in a register hook, causes this.

The fix: build the per-runtime `$h` snapshot in **one object-literal
expression** via `{ ...source, ...extras }`. Even if the source is in
dictionary mode, the spread produces a fresh object with a clean
hidden class, and V8 inlines per-call accesses through it cleanly.

Verified standalone: 232ms (clean spread) vs **831ms** (post-spread
mutation). The same loop body, just a different `$h`.

→ See [`buildPerRuntimeJitHelpers`](../../numbl/src/numbl-core/interpreter/jit/jitHelpers.ts)
and the call from [`executeCode.ts:324`](../../numbl/src/numbl-core/executeCode.ts#L324).

### 2. Helper functions inline IF they're monomorphic AND the call site is hot AND the args are scalar

V8 inlines small monomorphic helper functions into hot callers. Our
`idx2r(base, ri, ci)` helpers are short enough to qualify, but the
inlining is most effective when:

- The helper takes **scalar arguments** (numbers, not objects). `idx2r(base, ...)` reads `base.shape[0]` per call, which is a property load — much slower than passing `rows` as a scalar arg.
- The arguments are **type-stable** across calls. Mixing tensor types breaks the inline cache.
- The helper doesn't allocate. The original `idxN` allocated a `[1, 1, i]` array per call (40M+ allocs in stage 2). Specialized variants per arity avoid this entirely.

Practical conclusion: for each indexing pattern, prefer a specialized
helper that takes pre-extracted scalar args (`data, len, rows, ri, ci`)
over a general helper that takes a `base` object and re-derives them
each call. The codegen lifts the per-tensor reads to local aliases
once at the top of the loop function — see `_hoistedAliases` in
[`jitCodegen.ts`](../../numbl/src/numbl-core/interpreter/jit/jitCodegen.ts).

Verified standalone:
- General helper (`idx2r(base, r, c)`): ~144ms
- Hoisted helper (`idx2r_h(data, len, rows, r, c)`): ~75ms
- Pure inline (no helper): ~61ms

The hoisted helper is within 23% of the inlined form, and the codegen
stays clean.

### 3. Live-out variables at function exit pessimize register allocation

Returning a 10-element array containing all loop locals (because they're
all "outputs" that get written back to interp.env) makes V8 keep all 10
locals materializable at the function exit point. V8 stops keeping them
in registers across iterations because they could in principle be
observed at exit. Net effect: ~3× slowdown vs. returning only the 2-3
locals that are actually needed.

Fix: filter the loop's output set to only variables that are
**actually live after the loop**. Implementation needs three pieces:

- An input variable (was in outer scope before the loop) — always live.
- The loop iteration variable — MATLAB exposes its final value.
- Any variable read by a sibling stmt running after the loop in the
  enclosing block.

We compute the third by threading sibling-tail info from `execStmts` /
the script-body driver onto `interp._postSiblings` /
`interp._postSiblingsIdx`, then walking it with `collectReadsFromSiblings`
in [`jitLoopAnalysis.ts`](../../numbl/src/numbl-core/interpreter/jit/jitLoopAnalysis.ts).
`tryJitLoop` then filters the output set down to the intersection.

Verified standalone:
- Return all 10 inner-loop locals as array: 207ms
- Return `[i, j, nhit, checksum]` only: 82ms
- Return `{ nhit, checksum }`: 78ms

The shape (array vs object) is mostly noise. **The only thing that
matters is the number of distinct locals named in the return.**

### 4. SetLoc inside a hot loop is essentially free

Each JIT'd statement gets prefixed with a `SetLoc` IR node that codegen
emits as `$rt.$file = "..."; $rt.$line = N;`. With 4 such writes per
inner iter × 80M iters = 320M writes, you'd think this is expensive. It
isn't — V8 hoists same-string assignments and constant-line numbers are
cheap stores. **Verified by deleting all SetLocs entirely:** stage 1
went from 320ms to 320ms. No measurable change. **Don't waste time
optimizing SetLoc.**

The only reason to keep SetLoc is correct line numbers in error
messages. Leave it alone.

### 5. The verbose `(a > b ? 1 : 0) !== 0 && ...` chain is mostly free too

V8 constant-folds the chain into a normal short-circuit `&&` of
booleans. Cleaning up `emitTruthiness` to recursively emit JS-boolean
form for comparisons inside conditions makes the dump readable but
doesn't move the timer measurably. We did the cleanup anyway because
it makes the dump auditable, not because it was a perf win.

### 6. `(i - 1) | 0` for index conversion is faster than `Math.round(i) - 1`

Trivially true but worth stating: in tight loops where indices are
always integers, `| 0` avoids a `Math.round` call (which V8 cannot
inline as cleanly because of the fp-rounding semantics). The trade-off
is that fractional indices truncate instead of round, but the JIT only
sees integer-typed indices in practice so this doesn't matter.

### 7. Bounds checking via `(idx >>> 0) >= len` is one comparison

`idx >>> 0` reinterprets as unsigned, so any negative `idx` becomes a
huge positive number that fails the `< len` test. One branch instead of
two (`idx < 0 || idx >= len`). Both are fast in V8, but the one-branch
form is cleaner and matches the pattern V8's own typed array bounds
checks use.

## Things we considered and rejected

- **Eliding bounds checks entirely**: would silently turn out-of-bounds
  reads into NaN propagation instead of MATLAB-faithful errors. Not worth
  the speed gain (~10%), and the fast unsigned bounds check costs almost
  nothing anyway.
- **Always-inline indexing at the call site** instead of helpers: cleaner
  for the inner loop but produces much larger generated JS, hurts JIT
  warmup, and gives only a small win over a properly hoisted helper. The
  user explicitly preferred specialized helpers, and the benchmark
  confirms this is fine.
- **Per-call shape constant baking** (`idx2r_rows2(data, len, r, c)`):
  too many specializations. The hoisted-helper form (passing `rows` as a
  scalar arg from a hoisted local) is monomorphic per call site and
  almost as fast.
- **Disabling SetLoc**: doesn't help, see finding 4.

## What changed in numbl in this round of work

In commit order:

| Commit | What | Effect on stage(s) |
|---|---|---|
| `34d107a` Fix `--dump-js` double-printing JIT compilations | Cosmetic dedup of dump file. The `cli.ts onJitCompile` callback was appending each compile to the dump file AND `finalizeDumpFile` was writing the same content from `result.generatedJS`. | Cosmetic only. Made the runner's "jit fns" column accurate. |
| `db20187` JIT: specialized fast helpers for real-tensor scalar reads | Add `idx1r/idx2r/idx3r` helpers with `\| 0` index conversion, no `isTensor` check, no `imag` check, no per-call array allocation. Codegen emits these when the call site can prove the base is a real tensor. | stage 02: 1.31s → 670ms (1.93x). stage 03: 933ms → 670ms (1.39x). |
| `1a30b64` JIT: build per-runtime helpers via spread for stable hidden class | `buildPerRuntimeJitHelpers` now constructs the result via a single spread literal `{ ...jitHelpers, ... }` so V8 sees a fresh hidden class. `jitLoop.ts` was also passing the global `jitHelpers` instead of `rt.jitHelpers` — fixed to match what `jit/index.ts` already did for function-level JIT. | stage 02: 670ms → 227ms (2.95x). stage 03: 670ms → 241ms (2.78x). |
| `d6f7ea6` JIT: hoist tensor base reads, clean conditionals, prune dead loop outputs | (1) Add `idx{1,2,3}r_h` helpers taking pre-extracted (data, len, dim sizes) args, and hoist per-tensor reads to local aliases at function entry. (2) Recursively emit JS-boolean form inside conditions in `emitTruthiness`. (3) Filter the loop output set with sibling-tail liveness via new `collectReadsFromSiblings` + `_postSiblings` plumbing. | stage 02: 227ms → 194ms (1.17x). stage 03: 241ms → 98ms (2.46x). |
| `cb2eb8b` JIT: scalar tensor write via hoisted `unshare` | (1) New `set{1,2,3}r_h` helpers mirroring `idx{1,2,3}r_h`. (2) New `unshare(t)` helper that returns `t` if `_rc <= 1` else a fresh copy. (3) New `AssignIndex` JIT IR node. (4) `lowerAssignLValue` handles `t(i)=v` with 1-3 scalar indices on real tensors. (5) Codegen's hoist pass was loosened so write-target tensor params go through `unshare` once at function entry and then hoist data/len/shape like the read-only case. | stage 04: 4188ms → 31ms (**135×**, ratio 0.98× matlab). stage 07: 8893ms → 44ms (**202×**, ratio 1.20× matlab — it auto-JIT'd because while-stack only needed scalar push/pop). |
| _stage-5_ JIT: colon-slice reads via "slice alias" substitution | (1) New `SliceAlias` type in lowerCtx: a map from MATLAB local → `{ baseName, template, sliceShape }` where `template` is per-dim `{kind: "colon"} \| {kind: "expr", expr}`. No RuntimeTensor is materialized for the slice. (2) `tryLowerAsSliceBind` recognizes `name = base(:, i, ...)` (both Index and FuncCall forms — the parser produces FuncCall when it can't disambiguate), captures each non-literal scalar index into a tmp local to freeze bind-time values (MATLAB semantics), and emits the tmp Assigns only. (3) Index reads of aliased names substitute back into a direct scalar read on the base tensor, which flows through the existing hoisted `idx{1,2,3}r_h` fast path. (4) Slice aliases are lexically scoped — snapshot/restore in lowerFor/While/If so aliases don't leak across branches or past loop exits. (5) Codegen needed zero changes: slice-bind emits plain Assigns and slice-reads emit plain Index JitExprs. | stage 05: **6552ms → 22ms (~300×, ratio 0.25× matlab — 4× faster than matlab)**. Stage 08 outer driver still bails (needs slice writes), but its sub-loops that are pure scalar-in-body now lower cleanly. |

## Cumulative results vs. the original baseline

Before any work this session vs. after the stage-5 work. matlab numbers
are run-to-run noise (~10% spread).

| stage | matlab | numbl before | numbl after | speedup | ratio (nb/ml) |
|---|---|---|---|---|---|
| stage_01_scalar_arith | ~58ms | ~320ms | ~286ms | 1.12× | 4.94× |
| stage_02_scalar_tensor_reads | ~72ms | ~1311ms | ~195ms | **6.72×** | 2.71× |
| stage_03_nested_with_compare | ~54ms | ~933ms | ~105ms | **8.89×** | 1.94× |
| stage_04_scalar_write | ~25ms | ~4188ms | **~29ms** | **144×** | **1.17×** |
| stage_05_slice_read | ~92ms | ~6509ms | **~24ms** | **271×** | **0.26×** |
| stage_06_slice_write | ~97ms | ~6881ms | (still no JIT — bails on `t(a:b)=v`) | — | — |
| stage_07_while_stack | ~32ms | ~8893ms | **~43ms** | **207×** | **1.33×** |
| stage_08_full_bvh_query | ~101ms | ~7532ms | (2 sub-loops JIT, outer bails on slice write) | — | — |

**Stage 5 is the current record: 0.26× matlab (4× faster).** The slice-alias
approach turns `pt = pts(:, i); pxi = pt(1); pyi = pt(2)` into two
direct hoisted scalar reads on `pts`, with zero runtime allocation. V8
then hits the same fast path that stages 2–3 converged on, and closes
the matlab gap entirely.

**Stage 7 was a free win from stage 4.** It uses the while-loop push/pop
pattern on an integer stack tensor, which only needs scalar indexed
read and scalar indexed write — both of which stage 4 enables. No
stage-7-specific changes were needed; it auto-JIT'd as soon as scalar
writes landed.

**Stage 8 is still only partially JIT'd.** Two of its inner sub-loops
(the BVH-walk sibling-traversal loops) compile cleanly and the outer
driver now slices cleanly too via stage 5, but the outer driver still
bails because the grow-and-copy path uses slice-write (`out_pt(1:nout_max)
= tmp_pt(1:nout_max)`). Once stage 6 lands, stage 8 should collapse as
well.

**Stage 1 is at the V8 ceiling.** Verified by hand-writing the exact
generated JS and timing it under bare `node`: pure JS = 342ms, our JIT
= 320ms. The 5× gap to MATLAB is a V8-vs-MATLAB-JIT comparison, not
something the numbl codegen can fix without a fundamentally different
backend.

**Stages 2 and 3 have ~2× headroom left.** Pure inline was 61ms vs our
helper-based 98ms on stage 3. Closing this would require either
inlining at the call site (which the user wants to avoid for codegen
cleanness) or convincing V8 to bake the hoisted-rows constant. Not
worth pursuing until stages 4-8 land.

## What's next: stages 6, 8 (JIT coverage)

Stages 4, 5, and 7 are done. What's left:

- **stage 6** — `AssignLValue: Index(range...)`. Slice-write helper
  like `setSlice1r_h(dst, srcData, srcOff, len, dstStart)`. The
  obvious implementation path is a range-range copy (`Float64Array.set`
  with a subarray view), but the common chunkie pattern is `isp(1:nn) =
  itemp` with a range-range where the src is another tensor, not a
  range expression. Handle at least:
  * `dst(a:b) = src(a:b)` (range slice write from a range slice read)
  * `dst(:, i) = src(:, j)` (column-colon write from column-colon read
    — same shape)
  For now, skip the `Expr: Range` form entirely except as the inside of
  an `Index` — range expressions as first-class tensor values are out of scope.
- **stage 8** — combines stages 4-7 in the BVH walker. The two sub-loops
  already JIT and the query's outer slice read (`pt = pts(:, i)`) now
  works via stage 5. The outer driver still bails on the grow-and-copy
  slice-write path (`out_pt(1:nout_max) = tmp_pt(1:nout_max)`), which
  is the core of what stage 6 must add. Should JIT cleanly once stage 6
  lands.

Each of these lands with a corresponding correctness test in
`numbl/numbl_test_scripts/indexing/` plus a re-measurement of the
matching jit-benchmark stage.

## What was learned landing stage 5

- **Slice-alias substitution beats materialization.** The original plan
  was to lower `pt = pts(:, i)` as a helper call producing a small
  RuntimeTensor (`$h.slice2(pts, ":", i)`) and then do scalar reads on
  that tensor. That would work but pay an allocation + a tensor object
  property load per access. Substitution has zero per-iter cost — it
  produces exactly the same JS as if the user had hand-written
  `pts(1, i)` directly.
- **The parser produces FuncCall, not Index, for RHS `t(...)`.**
  When `t` is a variable the parser can't always tell; for the LHS of an
  AssignLValue it commits to Index, but for an expression RHS it
  typically produces FuncCall. `tryLowerAsSliceBind` accepts both shapes
  and normalizes. This caught me out — my first run dumped zero JIT for
  stage 5 because I was only matching `Index`. Debug trick: throwing a
  quick `parseMFile` test into `/tmp` with a heredoc and dumping
  `mainBody` is fastest way to see what form the parser uses.
- **Tmp capture for non-literal indices is cheap but necessary.** The
  MATLAB semantic is that `pt = pts(:, i)` freezes the value of `i` at
  the bind site, so later reassignments of `i` don't affect later
  `pt(k)` reads. The substitution form needs to preserve that. Every
  non-literal scalar index gets captured into a `_slice_<name>_d<dim>`
  local at the bind site, and the template references the captured
  local. For a typical pattern where the scalar index is just the loop
  variable, this is a trivial `_slice_pt_d1 = i` that V8 inlines away.
- **Slice aliases need to be lexically scoped.** Without a
  snapshot/restore in lowerFor/lowerWhile/lowerIf, an alias created
  inside one branch of an `if` would leak to post-if code and produce
  wrong codegen when the branch didn't actually execute. The snapshot
  discipline follows the existing `envBefore` pattern so it's trivial
  to keep right.
- **The existing output-set liveness filter handles slice aliases
  correctly.** Slice-aliased names get "assigned" in the pre-lowering
  analyzer, but the liveOut filter removes them if they're not read
  post-loop. Since the lowering itself doesn't add the name to
  `assignedVars` (only its `_slice_` slots do), the check at the end of
  `lowerFunction` passes naturally when the alias is purely loop-local
  and bails cleanly when the alias name escapes the loop (requiring
  materialization we don't do).

## Dead code removed

`numbl_test_scripts/jit/` (along with the `test:jit` npm script,
`parseJitAnnotations` in cli.ts, and the `%!jit` annotation matcher)
was removed. Background: the directory housed 13 tests that used line-
number-based `%!jit funcName@lineNumber` directives to assert that a
specific call site actually JIT'd. Every edit shifted the line numbers
and 9 of 13 tests were already stale before this work. The annotation
system was also limited to function-call shapes and couldn't express
loop JIT at all. With the removal:

- Correctness tests live in their natural home (e.g. the stage-4
  scalar-write test moved to `numbl_test_scripts/indexing/
  test_loop_indexed_assign.m`) and run as part of the normal
  `run_all.sh` suite.
- JIT-fires verification happens via the benchmark runner, which
  dumps the JIT function list per stage and compares numbl vs.
  MATLAB output on every run.

## What was learned landing stage 4 (earlier session)

The design went exactly as `git log -p` shows. A few notes in case the
same pattern comes up for stages 5-6:

- The unshare-once-at-entry strategy is cheap because `$h.unshare(t)`
  is a single branch on `_rc <= 1` in the fast path. V8 inlines it.
  Measured stage-4 ratio is 0.98× matlab — we actually beat matlab,
  which is the first time that's happened in this benchmark.
- The loop analyzer already treats an `Index` lvalue base as both
  assigned and referenced (`walkLValue` in jitLoopAnalysis.ts). That
  means a write-target tensor automatically ends up in both the input
  set (so the JIT function takes it as a param) and the output set
  (so the writeback path returns the unshared reference). No extra
  analyzer work was needed.
- The hoist pass needed a new "write target" code path distinct from
  the read-only path: the old condition `!outputSet.has(name) &&
  !localSet.has(name)` excluded both plain reassignments (`t = t+1`,
  which correctly can't be hoisted) AND scalar-indexed writes (which
  can be, via unshare). Splitting `outputSet.has(name) &&
  isWriteTarget` from plain `localSet.has(name)` is what makes the
  new path work.
- The JIT cache key already includes `input types`, and the tensor
  type doesn't change across iters (same shape, same isComplex). So
  a single lowering is enough — we don't need re-specialization when
  the refcount changes.

## Current branch state (for resuming after compaction)

- numbl: `main` at `950d413` pre-stage-5; this session adds a stage-5
  commit that lands slice-alias lowering and a new
  `test_loop_slice_read.m` correctness test.
- numbl-chunkie-benchmark: `main` at `be1ca40` pre-stage-5; this session
  adds a stage-5 commit that updates PERF_NOTES.md and README.md.

The numbl commits made so far for the loop JIT work, in order:
- `34d107a` Fix --dump-js double-printing JIT compilations
- `db20187` JIT: specialized fast helpers for real-tensor scalar reads
- `1a30b64` JIT: build per-runtime helpers via spread for stable hidden class
- `d6f7ea6` JIT: hoist tensor base reads, clean conditionals, prune dead loop outputs
- `cb2eb8b` JIT: scalar tensor write via hoisted unshare (**stage 4**)
- `950d413` Remove obsolete numbl_test_scripts/jit/ and %!jit annotation matcher
- `9318236` JIT: slice reads via alias substitution (**stage 5**)

The benchmark commits:
- `52ffa21` Add jit-benchmarks suite for staged loop-JIT improvements
- `a8f95d0` PERF_NOTES: add stage 4 implementation guide and branch state
- `be1ca40` PERF_NOTES + README: stage 4 landed (scalar tensor write)
- `(new)`   PERF_NOTES + README: stage 5 landed (slice reads)

## Cheat sheet for the next session

- The fastest way to find a perf bug: dump the JIT JS, paste it into a
  standalone `.mjs`, run it under `node`. If standalone is fast and
  numbl is slow, the bug is in how the helpers/runtime are wired up,
  not in the codegen itself.
- The fastest way to test "is this V8 trick a win": write the diff
  in two adjacent functions in one `.mjs`, time both. **Do this before
  modifying the codegen.**
- The runner [`run_stages.mjs`](run_stages.mjs) caches nothing and prints
  a clean summary. Use `node run_stages.mjs stage_03` to focus on one.
- `--dump-js out.js` writes the JIT JS each compile fires. The file is
  rewritten at the end of `numbl run` from `result.generatedJS`. As of
  the dedup fix, each compile appears exactly once.
- All the helpers are in [`jitHelpers.ts`](../../numbl/src/numbl-core/interpreter/jit/jitHelpers.ts).
  When adding a new helper family, register it in **both** the inline
  helper export AND the destructured list at the bottom.
- When adding a new codegen feature, run `numbl_test_scripts/control_flow`,
  `numbl_test_scripts/indexing`, and `numbl_test_scripts/arithmetic` to
  catch regressions. The `numbl_test_scripts/jit` suite has the
  pre-existing failures noted above — same failures = no new
  regression.
