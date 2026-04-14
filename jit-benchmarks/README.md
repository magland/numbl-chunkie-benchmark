# JIT Benchmarks

A staged set of benchmarks for building up numbl's JIT to handle the kind
of tight scalar loop with tensor indexing that dominates the chunkie
`flagnear_rectangle` ptloop (see [reports/ex01_helmholtz_starfish.md](../reports/ex01_helmholtz_starfish.md)
and the [chunkie source](https://github.com/fastalgorithms/chunkie/blob/master/chunkie/%40chunker/flagnear_rectangle.m)).

**See [PERF_NOTES.md](PERF_NOTES.md) for the running technical reference
on what we've learned about the JIT and V8 — read this before changing
the JIT.**

There are two ambitious targets:

- **Stage 8** — flat-tensor BVH walker. Mirrors the ptloop pattern but
  uses only flat tensors (no struct-of-struct). Stages 1–7 add the
  individual JIT capabilities required to compile stage 8. **Done.**
- **Stage 14** — struct-of-struct BVH walker. A near-direct copy of
  chunkie's `flagnear_rectangle` outer loop, including struct array
  field access (`T.nodes(inode).chld`), vertical concatenation growth
  (`it = [it; i]`), and slice writes from whole-tensor sources. Stages
  9–13 add the individual JIT capabilities required to compile stage 14.
  When stage 14 JITs cleanly, the actual chunkie `flagnear_rectangle.m`
  should JIT cleanly too.

## The `assert_jit_compiled()` marker

Stages and tests use a special function `assert_jit_compiled()` placed
inside the loop body to assert that the surrounding loop got
JIT-compiled. The numbl JIT lowering elides the call when lowering
succeeds; if lowering bails the call survives to the interpreter and
throws (unless `--opt 0` is in effect). The MATLAB shim
[stages/assert_jit_compiled.m](stages/assert_jit_compiled.m) is a no-op
so the same script runs in both engines unmodified.

The runner detects the marker error and reports `BAIL` for that stage
instead of crashing the whole sweep.

## Layout

```
jit-benchmarks/
├── README.md           ← this file
├── run_stages.mjs      ← runner: matlab + numbl, captures JIT dump
└── stages/
    ├── assert_jit_compiled.m            (MATLAB shim, no-op)
    ├── stage_01_scalar_arith.m
    ├── stage_02_scalar_tensor_reads.m
    ├── stage_03_nested_with_compare.m
    ├── stage_04_scalar_write.m
    ├── stage_05_slice_read.m
    ├── stage_06_slice_write.m
    ├── stage_07_while_stack.m
    ├── stage_08_full_bvh_query.m       ← flat-tensor target (done)
    ├── stage_09_slice_write_var_src.m
    ├── stage_10_and_or_funccall.m
    ├── stage_11_concat_growth.m
    ├── stage_12_struct_field_read.m
    ├── stage_13_struct_array_chained.m
    ├── stage_14_chunkie_ptloop_struct.m  ← struct-of-struct target
    ├── stage_17_col_slice_write.m       ← multi-dim col slice write (ex02 driver)
    ├── stage_19_func_handle_call.m      ← function handle call target
    ├── stage_21_range_slice_read.m      ← range slice read on RHS (ex02 driver)
    ├── stage_22_struct_field_assign.m   ← struct field lvalue (ex02 driver)
    ├── stage_23_adap_inner.m            ← adapgausskerneval inner-loop target
    ├── stage_24_soft_bail_user_call.m   ← soft-bail UserCall → dispatch
    └── stage24_helper_bsxfun.m          ← (callee helper for stage 24)
```

Stages 17 / 21 / 22 / 23 target the remaining capability gaps that
make the Stokes benchmark ([reports/ex02_stokes_peanut.md](../reports/ex02_stokes_peanut.md))
run ~7.8× slower than matlab. Per the `forcesmooth` experiment, the
whole ~12s eval-phase gap is in chunkie's adaptive-quadrature path —
specifically the `chnk.adapgausskerneval.m` inner subdivision loop at
line 109 plus the `oneintp` helper it calls. Stage 23 is the
integration target mirroring that loop.

Each stage is a self-contained `.m` script that prints `BENCH:` and
`CHECK:` lines so the runner can compare timings and verify
cross-engine correctness.

## Running

```bash
node run_stages.mjs                # all stages
node run_stages.mjs stage_04       # one stage
node run_stages.mjs stage_04 stage_05
```

The runner executes each stage in MATLAB and in numbl, dumps the
JIT-generated JS via `--dump-js`, and reports a summary table with
timings, ratios, JIT-fired count and check status.

## What each stage adds

| Stage | New JIT capability | Mirrors in chunkie ptloop |
|---|---|---|
| 01 scalar_arith | (baseline) for-loop with scalar arithmetic and if/else | the outer loop machinery |
| 02 scalar_tensor_reads | scalar reads of preallocated tensors via 1D/2D/3D index | `pts(1, i)`, `bvhbounds(1, 1, inode)` |
| 03 nested_with_compare | nested for loops + compound `&&` | the box-containment test inside the leaf |
| 04 scalar_write | tensor scalar **write** `t(i) = v` | `isp(nnzero+nnew) = ...`, `istack(1) = 1` |
| 05 slice_read | column slice **read** `t(:, i)` | `pt = pts(:, i)`, `bvhtmp = bvhbounds(:, :, inode)` |
| 06 slice_write | range-slice **write** `t(a:b) = src(a:b)` | the growth path `isp(1:nn) = itemp` (where itemp is a range slice) |
| 07 while_stack | while loop driving an integer stack stored in a tensor | the BVH walk `while(is > 0, ...)` push/pop |
| 08 **full_bvh_query** | combines stages 4–7 in a stack-driven BVH traversal with hit accumulation and slice-write growth | the entire ptloop (flat-tensor surrogate) |
| 09 slice_write_var_src | slice write with a **whole-tensor** RHS: `dst(a:b) = src` | `isp(1:nn) = itemp` (where itemp is a plain Var) |
| 10 and_or_funccall | fold function-call form `and(a,b)` / `or(a,b)` to JS `&&` / `\|\|` (perf only — already lowers via IBuiltin path, ~3× slower than operator form) | `while(and(is > 0, ntry <= nnodes))` |
| 11 **concat_growth** | empty matrix init `it = []` + vertical concat growth `it = [it; i]` via `VConcatGrow` IR + `vconcatGrow1r` helper | the per-leaf "found" list |
| 12 struct_field_read | scalar `s.f` read where `s` is a struct with known field types | `chnkr.k`, `chnkr.nch`, `opts.rho` |
| 13 struct_array_chained | struct array indexing + chained Member: `T.nodes(i).chld` | the BVH children/xi access |
| 14 **chunkie_ptloop_struct** | combines stages 9–13 on top of 1–8: a near-direct copy of `flagnear_rectangle`'s outer for loop in struct-of-struct form | the entire ptloop (struct-of-struct, matches chunkie source) |
| 17 **col_slice_write** | multi-dim column slice write `dst(:, j) = src_tensor` via new `AssignIndexCol` IR + `setCol2r_h` helper | `vals(:, jj+1) = v2` in adapgausskerneval |
| 19 **func_handle_call** | function\_handle JIT type + FuncHandleCall IR + callFuncHandle helper with runtime return-type verification | `kern(srcinfo, targinfo)` in `adapgausskerneval` — the kernel function passed as a handle |
| 21 range_slice_read | range slice read on RHS `x = t(a:b)` (either materialize via `subarrayCopy1r` helper, or extend stage 5 alias to Range indices) | `r0 = all0(1:dim)`, `d0 = all0(dim+1:2*dim)` in `chnk.chunk_nearparam` Newton iteration |
| 22 struct_field_assign | Member lvalue `s.f = v` — new `AssignMember` IR + `structSetField_h` helper, plus empty→struct promotion for `s = []; s.f = ...` | `srcinfo.r = rint; srcinfo.d = dint; ...` in adapgausskerneval's `oneintp` |
| 23 **adap_inner** | integration target: the adapgausskerneval inner subdivision loop combining stages 17 + 19 (direct handle form). Full oneintp inlining additionally needs stages 21 + 22 | `chnk.adapgausskerneval.m:109-160` — dominates ex02 eval_vel + eval_pres |
| 24 **soft_bail_user_call** | when `lowerUserFuncCall` can't lower a callee's body (tensor arith, matrix multiply, bsxfun with handle arg, …), probe the return type once at JIT compile time and emit a `UserDispatchCall` that goes through `rt.dispatch` at runtime — outer loop still JITs. Skips callees that use caller-aware builtins (evalin/assignin/dbstack/…) where probing isn't safe. | `oneintp(...)`, `lege.exev(...)` — any user-function-in-a-loop pattern where the outer loop is JIT-friendly |

## Progress

`ratio` is `numbl / matlab`. See [PERF_NOTES.md](PERF_NOTES.md) for
per-stage details and the V8 findings behind the improvements.

| stage | matlab | numbl (initial) | numbl (current) | current ratio | status |
| --- | --- | --- | --- | --- | --- |
| stage_01_scalar_arith         |  57ms |  320ms |  300ms |  5.24x | jit |
| stage_02_scalar_tensor_reads  |  79ms | 1.311s |  204ms |  2.57x | jit |
| stage_03_nested_with_compare  |  46ms |  933ms |   97ms |  2.12x | jit |
| stage_04_scalar_write         |  29ms | 4.188s |   27ms |  0.93x | jit |
| stage_05_slice_read           | 101ms | 6.509s |   23ms |  0.22x | jit |
| stage_06_slice_write          |  97ms | 6.653s |   34ms |  0.35x | jit |
| stage_07_while_stack          |  36ms | 8.893s |   48ms |  1.32x | jit |
| stage_08_full_bvh_query       | 101ms | 7.532s |   58ms |  0.57x | jit |
| stage_09_slice_write_var_src  | 188ms |    —   |   53ms |  0.28x | jit |
| stage_10_and_or_funccall      | 147ms |  438ms |   19ms |  0.11x | jit |
| stage_11_concat_growth        | 103ms |    —   |  203ms |  1.93x | jit |
| stage_12_struct_field_read    | 203ms |    —   |   17ms |  0.08x | jit |
| stage_13_struct_array_chained | 155ms |    —   |   10ms |  0.07x | jit |
| stage_14_chunkie_ptloop_struct| 233ms |    —   |  118ms |  0.51x | jit |
| stage_19_func_handle_call    |  10ms |    —   |   38ms |  3.58x | jit |
| stage_17_col_slice_write     | 124ms |    —   |  107ms |  0.86x | jit |
| stage_21_range_slice_read    | 197ms |    —   |  312ms |  1.59x | jit |
| stage_22_struct_field_assign | 126ms |    —   |   23ms |  0.18x | jit |
| stage_23_adap_inner          | 634ms |    —   |  37.03s| 58.39x | jit |
| stage_24_soft_bail_user_call | 169ms |    —   |   21ms |  0.13x | jit |

Stage 23 JITs (the inner subdivision loop compiles as one loop fn),
but the ambitious ~1× matlab target is still distant: the anonymous
function-handle body runs in the interpreter, allocating a 2×1 tensor
per call. The chunkie version uses `kern.eval` (a bound method with a
jsFn closure) which is faster per-call than an anonymous lambda.
Narrowing the ratio further for this shape needs either:
  - soft-bail UserCall → interpreter dispatch fallback (keeps outer
    loop JIT'd even when the callee can't fully lower), or
  - deep tensor-arith lowering so `oneintp` itself JITs.

**Stages 1–14 and 19 are all JIT'ing.** Stages 4–6, 8, 9, 10, 12, 13, 14 beat
or match matlab (ratio ≤ 1×); stage 13 by ~15× and stage 12 by ~12×;
stage 10 by ~9×; stages 5 and 9 by ~3.5×. Stage 8, the flat-tensor BVH
walker, runs ~2× faster than matlab. Stage 11 lands at ~1.9× matlab
— per-iter allocation for tensor growth is the dominant cost and is
unavoidable given MATLAB growth semantics. Stage 14 — the full chunkie
`flagnear_rectangle` ptloop in struct-of-struct form — lands at
~0.5–0.9× matlab (run-to-run variance) on first compile, with the
faster-matlab bound coming from long warm runs. The gap vs stage 8 is
the per-iter cost of struct-array field access through
`RuntimeStruct.fields` Map lookups, not a JIT capability gap.

**Stage 14 JITs on the same commit as stage 13** — it's the integration
test, not a new capability. The actual chunkie `flagnear_rectangle.m`
should now JIT cleanly as well; run the ex01 Helmholtz starfish
benchmark to confirm.

## Capability staging plan (numbl side)

Each stage corresponds to a specific gap in
`numbl/src/numbl-core/interpreter/jit/jitLower.ts`:

**Note**: the table below reflects the state at stage 13 landing. Stages
13 and 14 are marked done; the stage 13 row describes the final design
(chained `Member(MethodCall, leaf)` pattern recognition, not the "row
alias" sketch that preceded it).

| Stage | Required jitLower change | Status |
|---|---|---|
| 04 scalar_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with **scalar** indices on a tensor base. Codegen `$h.set1r_h(...)` etc. | **done** |
| 05 slice_read | Handle `Expr: Colon` inside an `Index`/`FuncCall` base. Implemented as a "slice alias": `pt = pts(:, i)` doesn't allocate anything — it's recorded as a substitution rule, and subsequent reads `pt(k)` rewrite into direct scalar reads on the source tensor. No codegen changes needed. | **done** |
| 06 slice_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with a `Range` index. Codegen `$h.setRange1r_h(...)`. Also relax the codegen hoist pass to refresh hoisted aliases after every plain Assign to a hoisted tensor — required because the chunkie growth pattern reassigns the dst tensor inside the loop. | **done** |
| 07 while_stack | No new lowering needed. | **done** (free after stage 4) |
| 08 flat target | All of stages 04–07 must be in place. | **done** (entire flat-tensor BVH ptloop JITs as one loop) |
| 09 slice_write_var_src | Extend `tryLowerRangeAssign` to accept a plain `Ident` RHS of a real tensor. IR change: `AssignIndexRange.srcStart`/`srcEnd` become nullable — when null the codegen substitutes `1` and the source's hoisted length alias. Same `setRange1r_h` helper handles both shapes; no new helper needed. | **done** |
| 10 and_or_funccall | In `lowerExpr` case "FuncCall", recognize `and(a, b)` / `or(a, b)` / `not(a)` with simple numeric/boolean scalar args and synthesize a `Binary`/`Unary` JitExpr (`AndAnd`/`OrOr`/`Not`) instead of routing through the IBuiltin call path. Variable shadowing already handled by the env check above. Complex args fall through to IBuiltin (JS truthiness ≠ MATLAB complex truthiness). | **done** |
| 11 concat_growth | Empty matrix literal `[]` already lowers as `tensor[0x0]` via the existing `TensorLiteral` path. The vertical concat `[base; value]` where `base` is a real tensor and `value` is a numeric scalar gets a new `VConcatGrow` JitExpr tag that codegens to `$h.vconcatGrow1r(base, value)` — a per-iter allocate-and-copy helper returning a fresh `(k+1, 1)` tensor. Type unification at the loop join widens `tensor[0x0]` against `tensor[?x1]` to `tensor[?x?]` element-wise; the fixed-point iterator in `lowerFor` stabilizes after one re-pass. | **done** |
| 12 struct_field_read | Struct types were already tracked in the type env (`JitType.kind = "struct"` with `fields` map, propagated through `inferJitType`). Added a new `MemberRead` JitExpr tag. `lowerExpr` case `"Member"` recognizes `Ident(base).field` where base has a struct type with a known scalar numeric field and emits a `MemberRead`. Codegen walks the IR collecting unique `(baseName, fieldName)` pairs and hoists each as `var $base_field = base.fields.get("field")` at function entry, so per-iter reads are bare local loads. `RuntimeStruct.fields` is a `Map<string, RuntimeValue>` — hoisting amortizes the one-time `Map.get` cost across the whole loop. | **done** |
| 13 struct_array_chained | Add a `struct_array` JitType kind (with per-field `elemFields` inferred from runtime). Infer struct_array only for nested (struct-field) position to keep existing builtin dispatch unchanged. Recognize the parser shape `Member(MethodCall(Ident(T), "nodes", [i]), "leaf")` in `lowerExpr` and emit a new `StructArrayMemberRead` IR node. Codegen hoists `$T_nodes_elements = T.fields.get("nodes").elements` once per unique `(structVar, field)` pair; per-use reads do `$T_nodes_elements[Math.round(i) - 1].fields.get("leaf")`. Tensor-typed leaves reuse stage 6's existing per-Assign hoist refresh. Also fixes two pre-existing bugs that stage 13 surfaced: removing `lowerFunction`'s `number=0` output pre-init (which poisoned tensor outputs at loop joins) and promoting outputs-in-outer-env to loop-function inputs (so write-only locals survive zero-iter loops). | **done** |
| 14 struct ptloop target | Combines stages 09–13 on top of 04–07. Same shape as `flagnear_rectangle.m`. JITs as one loop function with one helper loop for the rect-init pre-loop — no new capability needed beyond stage 13. | **done** |
| 19 func_handle_call | Add `function_handle` to `JitType` union. In `lowerExpr` case `"FuncCall"`, detect when a variable has type `function_handle` and emit a new `FuncHandleCall` IR node instead of treating it as indexing. Return type is determined by **probing**: calling the function handle once at JIT compile time with representative argument values (actual env values for existing variables, synthesized values for loop iterators). Codegen emits `$h.callFuncHandle($rt, fn, expectedType, ...args)`. The helper verifies the actual return type at runtime on every call — on mismatch, throws `JitFuncHandleBailError` which `executeAndWriteBack` catches, warns, invalidates the cache entry, and returns `false` so the interpreter re-runs the loop. | **done** |
| 17 col_slice_write | New IR `AssignIndexCol { baseName, colIndex, srcBaseName }` for the shape `Index(Ident(dst), [Colon, scalar_j]) = Ident(src_tensor)` where both are real tensors and dst has statically-known 2-D shape. `tryLowerColAssign` pattern-matches in `lowerAssignLValue` before falling through to the range-assign path. New helper `setCol2r_h(dstData, dstRows, dstLen, col, srcData, srcLen)` bounds-checks j and calls `dstData.set(srcData.subarray(0, dstRows), (j-1)*dstRows)`. | **done** |
| 21 range_slice_read | In `lowerExpr` Index/FuncCall paths, recognize single-index Range on a real-tensor base and emit a new `RangeSliceRead` JitExpr. `end` keyword as the upper bound is special-cased to substitute the hoisted `.data.length` alias in codegen. Helper `subarrayCopy1r(srcData, srcLen, a, b)` allocates a fresh `(b-a+1, 1)` tensor via `makeTensor`. Alloc-per-iter is unavoidable without extending stage 5's slice-alias to Range indices; small slices are cheap in V8 young-gen. | **done** |
| 22 struct_field_assign | New IR `AssignMember { baseName, fieldName, value, needsPromote }`. In `lowerAssignLValue` add a `case "Member"` branch. Three base cases: (a) struct in env → mutate via `s.fields.set`; (b) `s = []` idiom or (c) write-only local → `needsPromote=true` emits `s = $h.structNew_h()` first. Plus: `$h.structUnshare_h(s)` clone-on-entry for any struct PARAM that is an `AssignMember` target, preserving MATLAB value semantics (caller unaffected by callee mutations). Stage 12 hoist refined to skip when the base is reassigned or member-written inside the body. | **done** |
| 23 adap_inner target | Combines stages 17 + 19 on top of 1–8. Inner loop JITs as one function. Full ambitious `oneintp` + adap inner lowering additionally needs (a) tensor arithmetic (matrix multiply, tensor-builtin calls with tensor returns) and (b) soft-bail UserCall→interpreter fallback so the outer loop JITs even when the callee doesn't fully lower. | **partial** (inner JIT fires; callee still interpreted) |
| 24 soft_bail_user_call | In `lowerUserFuncCall`, when the recursive `lowerFunction` call fails, probe the callee's return type via `rt.dispatch` with representative args and emit a new `UserDispatchCall` JitExpr instead of returning null. Codegen emits `$h.callUserFunc($rt, name, expectedType, …args)` with runtime return-type verification (reuses the `JitFuncHandleBailError` path). Pre-probe guard: walks the callee body AST looking for `evalin`/`assignin`/`dbstack`/`inputname`/`keyboard`/`input` — if any are present, skip the soft-bail and fall through to hard-bail (those builtins are caller-frame-sensitive and can't be probed at JIT compile time). | **done** |

Each capability lands in numbl together with a correctness test in
`~/src/numbl/numbl_test_scripts/` (typically `indexing/` for slice
shapes and `struct/` for member-access shapes), using
`assert_jit_compiled()` inside the loop body to assert the surrounding
loop actually compiles. After landing each, re-run the matching stage
and confirm the ratio collapses.

## Out of scope (for this benchmark)

- **`length()` / `isempty()` on tensors inside the JIT.** Already
  supported, just not inlined as cleanly as for scalars. Improving the
  inline form is incremental polish.
- **Multi-dim slice writes from a range-slice source** like
  `dst(:, j) = src(:, k)` in one statement. Stage 17 handles the
  `dst(:, j) = src_tensor` form used by adapgausskerneval/chunkerinterior,
  but a two-colon multi-dim variant isn't needed for the eval path.
- **Stepped ranges** in slice writes (`dst(a:2:b) = ...`).
- **Slice writes from a scalar fill** (`dst(a:b) = 5`).
- **Complex-tensor variants** of any of the above.
