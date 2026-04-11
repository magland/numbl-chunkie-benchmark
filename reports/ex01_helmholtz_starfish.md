# Benchmark: ex01_helmholtz_starfish

- **Script:** `benchmarks/ex01_helmholtz_starfish.m`
- **Date:** 2026-04-11
- **Relative tolerance:** `1e-8`

## Environment

| | |
| --- | --- |
| platform | linux 6.12.74+deb13+1-amd64 (x64) |
| cpu | 13th Gen Intel(R) Core(TM) i7-1355U × 12 |
| memory | 41.9 GB |
| node | v24.14.1 |
| matlab | R2025b |
| numbl | v0.1.6 @ [`d6f7ea6`](https://github.com/flatironinstitute/numbl/commit/d6f7ea6) |

## Timing summary

| metric | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| startup | 3.913s | 1.043s | 0.27x |
| execution | 4.549s | 19.03s | 4.18x |

Chunkie install time is excluded from both rows above (matlab: 2.477s, numbl: 740ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 95ms | 463ms | 4.89x |
| build_matrix | 3.033s | 6.144s | 2.03x |
| solve | 279ms | 395ms | 1.42x |
| interior | 313ms | 1.491s | 4.77x |
| eval | 730ms | 10.50s | 14.39x |
| **sum** | 4.449s | 18.99s | 4.27x |

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
