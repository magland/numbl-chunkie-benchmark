# JIT Benchmarks

A staged set of benchmarks for building up numbl's JIT to handle the kind
of tight scalar loop with tensor indexing that dominates the chunkie
`flagnear_rectangle` ptloop (see [reports/ex01_helmholtz_starfish.md](../reports/ex01_helmholtz_starfish.md)
and the [chunkie source](https://github.com/fastalgorithms/chunkie/blob/master/chunkie/%40chunker/flagnear_rectangle.m)).

**See [PERF_NOTES.md](PERF_NOTES.md) for the running technical reference
on what we've learned about the JIT and V8 — read this before changing
the JIT.**

The ambitious target is **stage 8**, a stack-driven BVH-style traversal
that mirrors the chunkie ptloop pattern but uses only flat tensors (no
struct-of-struct). Stages 1–7 incrementally add the individual JIT
capabilities required to compile stage 8.

## Layout

```
jit-benchmarks/
├── README.md           ← this file
├── run_stages.mjs      ← runner: matlab + numbl, captures JIT dump
└── stages/
    ├── stage_01_scalar_arith.m
    ├── stage_02_scalar_tensor_reads.m
    ├── stage_03_nested_with_compare.m
    ├── stage_04_scalar_write.m
    ├── stage_05_slice_read.m
    ├── stage_06_slice_write.m
    ├── stage_07_while_stack.m
    └── stage_08_full_bvh_query.m
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
| 06 slice_write | range-slice **write** `t(a:b) = src(a:b)` | the growth path `isp(1:nn) = itemp` |
| 07 while_stack | while loop driving an integer stack stored in a tensor | the BVH walk `while(is > 0, ...)` push/pop |
| 08 **full_bvh_query** | combines stages 4–7 in a stack-driven BVH traversal with hit accumulation and slice-write growth | the entire ptloop |

## Baseline (before JIT additions)

Last measured 2026-04-11 on the dev machine. `ratio` is `numbl / matlab`.

| stage | matlab | numbl | ratio | jit fired |
| --- | --- | --- | --- | --- |
| stage_01_scalar_arith        |  54ms |  320ms |   5.91x | yes |
| stage_02_scalar_tensor_reads |  68ms | 1.267s |  18.74x | yes |
| stage_03_nested_with_compare |  45ms |  933ms |  20.75x | yes |
| stage_04_scalar_write        |  29ms | 4.188s | 146.67x | **no** |
| stage_05_slice_read          |  95ms | 6.509s |  68.63x | **no** |
| stage_06_slice_write         |  91ms | 6.653s |  72.83x | **no** |
| stage_07_while_stack         |  35ms | 8.893s | 255.17x | **no** |
| stage_08_full_bvh_query      |  98ms | 7.532s |  77.24x | **no** |

Two takeaways:

1. **Stage 4 is the cliff.** The moment we introduce `t(i) = v`, the
   loop fails JIT lowering and falls all the way back to the
   AST-walking interpreter. Per-element cost jumps roughly 20× → 150×.
2. **Stages 1–3 already JIT, but are still 6–20× slower than MATLAB.**
   Even when JIT works, the generated JS has overhead that MATLAB's JIT
   doesn't pay. There's headroom on the JIT *codegen quality* angle
   too, separate from the *coverage* angle that stages 4–8 target.

## Capability staging plan (numbl side)

Each stage corresponds to a specific gap in
`numbl/src/numbl-core/interpreter/jit/jitLower.ts`:

| Stage | Required jitLower change |
|---|---|
| 04 scalar_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with **scalar** indices on a tensor base. Codegen `$h.set1(t, i, v)` / `$h.set2(t, r, c, v)` helpers. |
| 05 slice_read | Handle `Expr: Colon` and `Expr: Range`. Allow `Index` with mixed scalar + colon/range indices. Result type is a small tensor with shape inferred from base shape. Codegen `$h.slice2(t, ":", i)` etc. |
| 06 slice_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with at least one `Range`/`Colon`. Codegen `$h.setSlice(...)`. |
| 07 while_stack | No new lowering — but stages 04 and 05 must already work, since the stack uses scalar push/pop on a tensor. |
| 08 full target | All of the above must be in place. Stage 8 should JIT cleanly once stages 4–7 do. |

Each capability lands in numbl together with a corresponding test in
`~/src/numbl/numbl_test_scripts/jit/`. After landing each, re-run the
matching stage and confirm the ratio collapses.

## Out of scope (for this benchmark)

- **Struct-of-struct field access** (`T.nodes(inode).chld`). The actual
  chunkie ptloop has this; we're explicitly avoiding it here so the
  benchmark focuses on the tight tensor-indexing loop. A second
  benchmark suite can target struct field access separately.
- **`length()` / `isempty()` on tensors inside the JIT.** Already
  supported, just not inlined as cleanly as for scalars. Improving the
  inline form is incremental polish.
- **Vertical concatenation `[a; b]` for growable arrays.** Mirrored
  here by the explicit grow-and-copy pattern in stage 6, which is
  closer to how the chunkie code actually scales (it doesn't really
  rely on `[]` growth in the hot path either — it's the `isp(...) =
  it` slice writes that matter).
