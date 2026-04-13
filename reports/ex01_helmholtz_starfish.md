# Benchmark: ex01_helmholtz_starfish

- **Script:** `benchmarks/ex01_helmholtz_starfish.m`
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
| startup | 3.913s | 1.377s | 0.35x |
| execution | 4.850s | 10.22s | 2.11x |

Chunkie install time is excluded from both rows above (matlab: 2.772s, numbl: 994ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 94ms | 520ms | 5.55x |
| build_matrix | 3.200s | 5.557s | 1.74x |
| solve | 340ms | 387ms | 1.14x |
| interior | 323ms | 763ms | 2.36x |
| eval | 794ms | 2.946s | 3.71x |
| **sum** | 4.750s | 10.17s | 2.14x |

## Result checks

| name | matlab | numbl | rel_diff | status |
| --- | --- | --- | --- | --- |
| chnkr_k | 1.6000000000e+1 | 1.6000000000e+1 | 0.00e+0 | ok |
| chnkr_nch | 1.7200000000e+2 | 1.7200000000e+2 | 0.00e+0 | ok |
| chnkr_r_norm | 5.6620683446e+1 | 5.6620683446e+1 | 8.78e-16 | ok |
| num_exterior | 3.6110000000e+4 | 3.6110000000e+4 | 0.00e+0 | ok |
| rhs_norm | 5.2459508194e+1 | 5.2459508194e+1 | 0.00e+0 | ok |
| sol_norm | 3.9043848484e+1 | 3.9043848484e+1 | 9.28e-15 | ok |
| sysmat_fro | 3.4820462325e+1 | 3.4820462325e+1 | 9.49e-14 | ok |
| uscat_norm | 1.3300139312e+2 | 1.3300139312e+2 | 2.54e-14 | ok |
| utot_norm | 1.8774422457e+2 | 1.8774422457e+2 | 1.54e-14 | ok |
| zk | 3.6055512755e+1 | 3.6055512755e+1 | 0.00e+0 | ok |

Max relative difference: **9.49e-14** (`sysmat_fro`)
Mismatches above tolerance: **0**
