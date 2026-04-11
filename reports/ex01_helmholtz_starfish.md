# Benchmark: ex01_helmholtz_starfish

- **Script:** `benchmarks/ex01_helmholtz_starfish.m`
- **Date:** 2026-04-11
- **Relative tolerance:** `1e-8`

## Timing summary

| metric | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| startup | 3.813s | 994ms | 0.26x |
| execution | 4.549s | 20.74s | 4.56x |

Chunkie install time is excluded from both rows above (matlab: 2.513s, numbl: 800ms).

## Phase timings

| phase | matlab | numbl | ratio (nb/ml) |
| --- | --- | --- | --- |
| discretize | 94ms | 436ms | 4.65x |
| build_matrix | 3.023s | 7.846s | 2.59x |
| solve | 325ms | 387ms | 1.19x |
| interior | 299ms | 1.510s | 5.06x |
| eval | 714ms | 10.52s | 14.72x |
| **sum** | 4.455s | 20.69s | 4.65x |

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
