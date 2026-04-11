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
    └── stage_14_chunkie_ptloop_struct.m  ← struct-of-struct target
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
| 11 concat_growth | empty matrix init `it = []` + vertical concat growth `it = [it; i]` | the per-leaf "found" list |
| 12 struct_field_read | scalar `s.f` read where `s` is a struct with known field types | `chnkr.k`, `chnkr.nch`, `opts.rho` |
| 13 struct_array_chained | struct array indexing + chained Member: `T.nodes(i).chld` | the BVH children/xi access |
| 14 **chunkie_ptloop_struct** | combines stages 9–13 on top of 1–8: a near-direct copy of `flagnear_rectangle`'s outer for loop in struct-of-struct form | the entire ptloop (struct-of-struct, matches chunkie source) |

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
| stage_09_slice_write_var_src  |  95ms |    —   |    —   |    —   | **BAIL** |
| stage_10_and_or_funccall      | 147ms |    —   |  438ms |  2.99x | jit (perf gap) |
| stage_11_concat_growth        | 103ms |    —   |    —   |    —   | **BAIL** |
| stage_12_struct_field_read    | 219ms |    —   |    —   |    —   | **BAIL** |
| stage_13_struct_array_chained | 151ms |    —   |    —   |    —   | **BAIL** |
| stage_14_chunkie_ptloop_struct| 132ms |    —   |    —   |    —   | **BAIL** |

**Stages 1–8 are all JIT'ing.** Stages 4–6 and 8 beat matlab (ratio < 1×);
stage 5 by ~4.5×. Stage 8, the flat-tensor BVH walker, runs ~1.7× faster
than matlab.

**Stages 9–14 are the work-in-progress lineup** for getting the actual
chunkie ptloop (struct-of-struct flavor) to JIT. Each one is currently
failing the `assert_jit_compiled()` marker (or, for stage 10, lowering
through a slow IBuiltin path). Once stages 9–13 land individually,
stage 14 should JIT as a single loop function — and the chunkie
`flagnear_rectangle.m` should follow.

## Capability staging plan (numbl side)

Each stage corresponds to a specific gap in
`numbl/src/numbl-core/interpreter/jit/jitLower.ts`:

| Stage | Required jitLower change | Status |
|---|---|---|
| 04 scalar_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with **scalar** indices on a tensor base. Codegen `$h.set1r_h(...)` etc. | **done** |
| 05 slice_read | Handle `Expr: Colon` inside an `Index`/`FuncCall` base. Implemented as a "slice alias": `pt = pts(:, i)` doesn't allocate anything — it's recorded as a substitution rule, and subsequent reads `pt(k)` rewrite into direct scalar reads on the source tensor. No codegen changes needed. | **done** |
| 06 slice_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with a `Range` index. Codegen `$h.setRange1r_h(...)`. Also relax the codegen hoist pass to refresh hoisted aliases after every plain Assign to a hoisted tensor — required because the chunkie growth pattern reassigns the dst tensor inside the loop. | **done** |
| 07 while_stack | No new lowering needed. | **done** (free after stage 4) |
| 08 flat target | All of stages 04–07 must be in place. | **done** (entire flat-tensor BVH ptloop JITs as one loop) |
| 09 slice_write_var_src | Extend `tryLowerRangeAssign` (or add a sibling) to accept an Ident or FuncCall RHS that resolves to a real-tensor variable. Emit a helper call that copies the entire source's data into the dst range with a runtime length check. | todo |
| 10 and_or_funccall | In `lowerExpr` case "FuncCall", recognize `and(a, b)` / `or(a, b)` (and possibly `not(a)`) with scalar args and synthesize a `Binary` JitExpr with `BinaryOperation.AndAnd` / `OrOr` instead of routing through the IBuiltin call path. **Perf optimization only — current path lowers but emits `$h.ib_and(...)` per iter.** | todo |
| 11 concat_growth | Lower the empty matrix literal `[]` as a tensor `tensor[0x0]` and the vertical concat literal `[a; b]` (where `a` is a tensor and `b` is a scalar/tensor) into a helper that allocates a fresh tensor and copies. Type unification at the loop join must understand that `tensor[0x0]` widens to `tensor[?x1]` once concat fires. | todo |
| 12 struct_field_read | Track struct types in the type env including their field types. Add a `tag: "MemberRead"` JitExpr (or extend Index) and lower scalar `s.f` reads as JS property loads. The struct must be created outside the loop (loop-invariant) so the field's runtime offset is stable. | todo |
| 13 struct_array_chained | Add a `struct_array` JitType. Lower struct array indexing `s_array(i)` as a "row alias" (analogous to slice aliases) that doesn't materialize a Row struct. Chained `Member(Index(Member(T, nodes), [i]), chld)` substitutes through to a direct field-storage read at the leaf. | todo |
| 14 struct ptloop target | Combines stages 09–13 on top of 04–07. Same shape as `flagnear_rectangle.m`. | todo |

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
