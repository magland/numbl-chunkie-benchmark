# Benchmark: ex01_helmholtz_starfish

- **Script:** `benchmarks/ex01_helmholtz_starfish.m`
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
| startup | 4.015s | 1.394s | 0.35x |
| execution | 4.994s | 10.66s | 2.13x |

Chunkie install time is excluded from both rows above (matlab: 2.961s, numbl: 893ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 98ms | 543ms | 5.52x |
| build_matrix | 3.245s | 5.995s | 1.85x |
| solve | 339ms | 462ms | 1.36x |
| interior | 387ms | 717ms | 1.85x |
| eval | 833ms | 2.907s | 3.49x |
| **sum** | 4.903s | 10.62s | 2.17x |

## Result checks

| name | matlab | numbl | rel_diff | status |
| --- | --- | --- | --- | --- |
| chnkr_k | 1.6000000000e+1 | 1.6000000000e+1 | 0.00e+0 | ok |
| chnkr_nch | 1.7200000000e+2 | 1.7200000000e+2 | 0.00e+0 | ok |
| chnkr_r_norm | 5.6620683446e+1 | 5.6620683446e+1 | 8.78e-16 | ok |
| num_exterior | 3.6110000000e+4 | 3.6110000000e+4 | 0.00e+0 | ok |
| rhs_norm | 5.2459508194e+1 | 5.2459508194e+1 | 0.00e+0 | ok |
| sol_norm | 3.9043848484e+1 | 3.9043848485e+1 | 2.32e-11 | ok |
| sysmat_fro | 3.4820462325e+1 | 3.4820462324e+1 | 1.48e-11 | ok |
| uscat_norm | 1.3300139312e+2 | 1.3300139312e+2 | 8.46e-13 | ok |
| utot_norm | 1.8774422457e+2 | 1.8774422457e+2 | 2.97e-13 | ok |
| zk | 3.6055512755e+1 | 3.6055512755e+1 | 0.00e+0 | ok |

Max relative difference: **2.32e-11** (`sol_norm`)
Mismatches above tolerance: **0**
