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

## Cumulative results vs. the original baseline

Before any work this session vs. after `d6f7ea6`. matlab numbers
are run-to-run noise (~10% spread).

| stage | matlab | numbl before | numbl after | speedup | ratio (nb/ml) |
|---|---|---|---|---|---|
| stage_01_scalar_arith | ~57ms | ~320ms | ~287ms | 1.12× | 5.07× |
| stage_02_scalar_tensor_reads | ~70ms | ~1311ms | ~194ms | **6.76×** | 2.90× |
| stage_03_nested_with_compare | ~50ms | ~933ms | ~98ms | **9.52×** | 1.79× |
| stage_04_scalar_write | ~30ms | ~4188ms | (still no JIT — bails on `t(i)=v`) | — | — |
| stage_05_slice_read | ~95ms | ~6509ms | (still no JIT — bails on `t(:,i)`) | — | — |
| stage_06_slice_write | ~91ms | ~6653ms | (still no JIT — bails on `t(a:b)=v`) | — | — |
| stage_07_while_stack | ~35ms | ~8893ms | (still no JIT — bails on `t(i)=v` inside while) | — | — |
| stage_08_full_bvh_query | ~98ms | ~7532ms | (still no JIT — bails on every feature above) | — | — |

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

## What's next: stages 4-8 (JIT coverage)

The interpreter-side fallback for stages 4-8 is between 60× and 250×
slower than MATLAB. These are the JIT-coverage gaps that need to be
filled in `jitLower.ts`:

- **stage 4** — `Stmt: AssignLValue` whose lvalue is `Index` with
  scalar indices on a tensor base. Need a `set1r_h / set2r_h / set3r_h`
  helper family mirroring the read helpers.
- **stage 5** — `Expr: Colon` and `Expr: Range`, plus `Index` with
  mixed scalar+colon/range indices producing a small tensor. Codegen
  needs slice-read helpers (`slice2r_h(data, ..., kind)` or similar).
- **stage 6** — `AssignLValue: Index(range...)`. Slice-write helper.
- **stage 7** — should "just work" once stage 4 lands; the body uses
  scalar push/pop on a stack tensor.
- **stage 8** — combines all of stages 4-7 in the BVH walker. Should
  JIT cleanly once 4-6 land.

Each of these will land with a corresponding test in
`numbl/numbl_test_scripts/jit/`, plus a re-measurement of the
matching jit-benchmark stage. The stage runner already verifies
correctness against MATLAB on every run.

## Pre-existing JIT test failures (not from this work)

`numbl_test_scripts/jit/` has 9 pre-existing failures on `main` from
before this work. They're all `%!jit` annotation mismatches where the
expected line number drifted from the actual. Verified by `git stash`-ing
the perf changes and re-running — same failures. **Not regressions.**

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
