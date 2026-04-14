# Benchmark: ex02_stokes_peanut

- **Script:** `benchmarks/ex02_stokes_peanut.m`
- **Date:** 2026-04-14
- **Relative tolerance:** `1e-8`

## Environment

| | |
| --- | --- |
| platform | linux 6.12.74+deb13+1-amd64 (x64) |
| cpu | 13th Gen Intel(R) Core(TM) i7-1355U × 12 |
| memory | 41.9 GB |
| node | v24.14.1 |
| matlab | R2025b |
| numbl | v0.1.7 @ [`f14e698-dirty`](https://github.com/flatironinstitute/numbl/commit/f14e698) |

## Timing summary

| metric | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| startup | 3.890s | 1.053s | 0.27x |
| execution | 1.593s | 13.29s | 8.34x |

Chunkie install time is excluded from both rows above (matlab: 2.526s, numbl: 780ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 242ms | 161ms | 0.67x |
| build_matrix | 127ms | 388ms | 3.06x |
| solve | 40ms | 14ms | 0.36x |
| interior | 194ms | 985ms | 5.07x |
| eval_vel | 647ms | 6.935s | 10.72x |
| eval_pres | 340ms | 4.797s | 14.10x |
| **sum** | 1.590s | 13.28s | 8.35x |

## Result checks

| name | matlab | numbl | rel_diff | status |
| --- | --- | --- | --- | --- |
| chnkr_npt | 3.8400000000e+2 | 3.8400000000e+2 | 0.00e+0 | ok |
| num_interior | 2.1200000000e+3 | 2.1200000000e+3 | 0.00e+0 | ok |
| pres_norm | 4.6436554315e+1 | 4.6436554316e+1 | 9.29e-12 | ok |
| rhs_norm | 3.4440495882e+0 | 3.4440495882e+0 | 2.58e-16 | ok |
| sigma_norm | 4.1626603359e+1 | 4.1626603359e+1 | 3.97e-13 | ok |
| sysmat_fro | 4.0031295366e+1 | 4.0031295366e+1 | 3.02e-15 | ok |
| uu_norm | 1.5749178610e+1 | 1.5749178610e+1 | 3.90e-13 | ok |

Max relative difference: **9.29e-12** (`pres_norm`)
Mismatches above tolerance: **0**
