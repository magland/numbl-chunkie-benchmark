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
| numbl | v0.1.6 @ [`a9714b0-dirty`](https://github.com/flatironinstitute/numbl/commit/a9714b0) |

## Timing summary

| metric | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| startup | 3.465s | 964ms | 0.28x |
| execution | 5.199s | 13.50s | 2.60x |

Chunkie install time is excluded from both rows above (matlab: 2.336s, numbl: 702ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 126ms | 422ms | 3.35x |
| build_matrix | 3.495s | 5.987s | 1.71x |
| solve | 298ms | 343ms | 1.15x |
| interior | 357ms | 677ms | 1.90x |
| eval | 813ms | 6.036s | 7.42x |
| **sum** | 5.089s | 13.46s | 2.65x |

## Result checks

| name | matlab | numbl | rel_diff | status |
| --- | --- | --- | --- | --- |
| chnkr_k | 1.6000000000e+1 | 1.6000000000e+1 | 0.00e+0 | ok |
| chnkr_nch | 1.7200000000e+2 | 1.7200000000e+2 | 0.00e+0 | ok |
| chnkr_r_norm | 5.6620683446e+1 | 5.6620683446e+1 | 8.78e-16 | ok |
| num_exterior | 3.6110000000e+4 | 3.6110000000e+4 | 0.00e+0 | ok |
| rhs_norm | 5.2459508194e+1 | 5.2459508194e+1 | 0.00e+0 | ok |
| sol_norm | 3.9043848484e+1 | 3.9043848641e+1 | 4.01e-9 | ok |
| sysmat_fro | 3.4820462325e+1 | 3.4820462342e+1 | 5.12e-10 | ok |
| uscat_norm | 1.3300139312e+2 | 1.3300139354e+2 | 3.18e-9 | ok |
| utot_norm | 1.8774422457e+2 | 1.8774422499e+2 | 2.25e-9 | ok |
| zk | 3.6055512755e+1 | 3.6055512755e+1 | 0.00e+0 | ok |

Max relative difference: **4.01e-9** (`sol_norm`)
Mismatches above tolerance: **0**
