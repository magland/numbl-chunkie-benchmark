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

## Progress

`ratio` is `numbl / matlab`. See [PERF_NOTES.md](PERF_NOTES.md) for
per-stage details and the V8 findings behind the improvements.

| stage | matlab | numbl (initial) | numbl (current) | current ratio | jit fires? |
| --- | --- | --- | --- | --- | --- |
| stage_01_scalar_arith        |  58ms |  320ms |  286ms |  4.94x | yes |
| stage_02_scalar_tensor_reads |  72ms | 1.311s |  195ms |  2.71x | yes |
| stage_03_nested_with_compare |  54ms |  933ms |  105ms |  1.94x | yes |
| stage_04_scalar_write        |  25ms | 4.188s |   29ms |  1.17x | yes |
| stage_05_slice_read          |  92ms | 6.509s |   24ms |  0.26x | yes |
| stage_06_slice_write         |  97ms | 6.653s | 7.176s | 73.73x | **no** |
| stage_07_while_stack         |  32ms | 8.893s |   43ms |  1.33x | yes |
| stage_08_full_bvh_query      | 101ms | 7.532s | 7.679s | 76.09x | sub-loops yes, outer no |

Stages 4, 5, and 7 are all within 35% of matlab; stage 5 actually
**beats matlab by ~4×** (slice reads substitute directly into scalar reads
on the base tensor — no per-iter allocation, V8 hits the same fast path
as stages 2-3). Stages 6 and 8 still need slice-write JIT support.

## Capability staging plan (numbl side)

Each stage corresponds to a specific gap in
`numbl/src/numbl-core/interpreter/jit/jitLower.ts`:

| Stage | Required jitLower change | Status |
|---|---|---|
| 04 scalar_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with **scalar** indices on a tensor base. Codegen `$h.set1r_h(...)` etc. | **done** |
| 05 slice_read | Handle `Expr: Colon` inside an `Index`/`FuncCall` base. Implemented as a "slice alias": `pt = pts(:, i)` doesn't allocate anything — it's recorded as a substitution rule, and subsequent reads `pt(k)` rewrite into direct scalar reads on the source tensor. No codegen changes needed. | **done** |
| 06 slice_write | Handle `Stmt: AssignLValue` whose lvalue is `Index` with at least one `Range`/`Colon`. Codegen `$h.setSlice(...)`. | todo |
| 07 while_stack | No new lowering needed. | **done** (free after stage 4) |
| 08 full target | All of the above must be in place. | sub-loops JIT; outer bails on slice write |

Each capability lands in numbl together with a correctness test in
`~/src/numbl/numbl_test_scripts/indexing/` (or similar). After landing
each, re-run the matching stage and confirm the ratio collapses.

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
