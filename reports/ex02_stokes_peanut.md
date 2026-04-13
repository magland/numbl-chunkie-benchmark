# Benchmark: ex02_stokes_peanut

- **Script:** `benchmarks/ex02_stokes_peanut.m`
- **Date:** 2026-04-13
- **Relative tolerance:** `1e-8`

## Environment

| | |
| --- | --- |
| platform | linux 6.12.74+deb13+1-amd64 (x64) |
| cpu | 13th Gen Intel(R) Core(TM) i7-1355U × 12 |
| memory | 41.9 GB |
| node | v24.14.1 |
| matlab | R2025b |
| numbl | v0.1.7 @ [`c9a419e`](https://github.com/flatironinstitute/numbl/commit/c9a419e) |

## Timing summary

| metric | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| startup | 3.936s | 1.132s | 0.29x |
| execution | 2.299s | 14.28s | 6.21x |

Chunkie install time is excluded from both rows above (matlab: 2.666s, numbl: 855ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 290ms | 165ms | 0.57x |
| build_matrix | 127ms | 406ms | 3.19x |
| solve | 37ms | 11ms | 0.31x |
| interior | 308ms | 993ms | 3.23x |
| eval_vel | 1.197s | 7.623s | 6.37x |
| eval_pres | 337ms | 5.077s | 15.05x |
| **sum** | 2.296s | 14.27s | 6.22x |

## Result checks

| name | matlab | numbl | rel_diff | status |
| --- | --- | --- | --- | --- |
| chnkr_npt | 3.8400000000e+2 | 3.8400000000e+2 | 0.00e+0 | ok |
| num_interior | 2.1110000000e+3 | 2.1190000000e+3 | 3.78e-3 | **MISMATCH** |
| pres_norm | 1.7528633505e+2 | 3.4858140880e+2 | 4.97e-1 | **MISMATCH** |
| rhs_norm | 3.4440495882e+0 | 3.4440495882e+0 | 2.58e-16 | ok |
| sigma_norm | 6.2152264471e+1 | 5.7336605331e+1 | 7.75e-2 | **MISMATCH** |
| sysmat_fro | 3.9391786943e+1 | 3.9789655417e+1 | 1.00e-2 | **MISMATCH** |
| uu_norm | 1.4310838414e+1 | 1.4494996372e+1 | 1.27e-2 | **MISMATCH** |

Max relative difference: **4.97e-1** (`pres_norm`)
Mismatches above tolerance: **5**
