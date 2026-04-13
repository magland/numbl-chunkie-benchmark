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
    └── stage_19_func_handle_call.m      ← function handle call target
```

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
| 19 **func_handle_call** | function\_handle JIT type + FuncHandleCall IR + callFuncHandle helper with runtime return-type verification | `kern(srcinfo, targinfo)` in `adapgausskerneval` — the kernel function passed as a handle |

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
| stage_19_func_handle_call    |  10ms |    —   |   35ms |  3.54x | jit |

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
- **Multi-dim slice writes** like `dst(:, j) = src(:, k)`. Stage 6 only
  handles linear `dst(a:b) = src(c:d)`; multi-dim shapes aren't needed
  for the chunkie ptloop.
- **Stepped ranges** in slice writes (`dst(a:2:b) = ...`).
- **Slice writes from a scalar fill** (`dst(a:b) = 5`).
- **Complex-tensor variants** of any of the above.
