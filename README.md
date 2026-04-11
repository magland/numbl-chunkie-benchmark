# numbl-chunkie-benchmark

Side-by-side performance and correctness benchmarks for [chunkie](https://github.com/fastalgorithms/chunkie) running in MATLAB vs [numbl](https://github.com/flatironinstitute/numbl).

Each benchmark is a single `.m` script that runs unchanged in both engines and emits machine-parseable `BENCH:` (phase timings) and `CHECK:` (scalar result summaries) lines. The runner executes both engines, compares the output, and writes a markdown report.

## Layout

- `benchmarks/*.m` — benchmark scripts
- `run_benchmark.mjs` — runs both engines and writes a report
- `reports/*.md` — generated reports (checked in)

## Run

```bash
node run_benchmark.mjs                                  # defaults to ex01
node run_benchmark.mjs benchmarks/ex02_whatever.m
```

Exits non-zero if any `CHECK` value differs between MATLAB and numbl by more than `rtol = 1e-8`.

## Requirements

- `matlab` on `PATH` (invoked as `matlab -batch ...`)
- numbl checked out at `../numbl` (invoked as `npx tsx ../numbl/src/cli.ts run ...`)
- chunkie installed via `mip` in both engines (benchmarks call `mip load --install chunkie`).
  `mip` itself must be installed for MATLAB — see [mip.sh](https://mip.sh).
  Once both are installed, the chunkie sources `mip` loads live at:
  - MATLAB: `~/Documents/MATLAB/mip/packages/mip-org/core/chunkie`
  - numbl:  `~/.numbl/mip/packages/mip-org/core/chunkie`

## Authoring a benchmark

Each benchmark prints two kinds of lines that the runner parses:

```matlab
t0 = tic;
% ... work ...
fprintf('BENCH: phase=<name> t=%.6f\n', toc(t0));       % phase timing
fprintf('CHECK: name=<name> value=%.16e\n', norm(x));    % scalar result summary
```

Skip plotting or anything else that's not meaningful to time or compare.
