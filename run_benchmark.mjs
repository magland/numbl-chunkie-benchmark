#!/usr/bin/env node
// Run a chunkie benchmark in MATLAB and numbl, compare results,
// and write a markdown report to reports/<name>.md.
//
// Usage: node run_benchmark.mjs [benchmarks/ex01_helmholtz_starfish.m]

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const run = promisify(execFile);
const NUMBL_CLI = path.resolve('../numbl/src/cli.ts');
const DEFAULT_SCRIPT = 'benchmarks/ex01_helmholtz_starfish.m';
const RTOL = 1e-8;
const PHASE_ORDER = ['discretize', 'build_matrix', 'solve', 'interior', 'eval'];
const META_PHASES = new Set(['chunkie_load', 'execution']);

async function timed(cmd, args) {
  const t0 = process.hrtime.bigint();
  const { stdout, stderr } = await run(cmd, args, { maxBuffer: 64 << 20 });
  const wall = Number(process.hrtime.bigint() - t0) / 1e9;
  return { stdout, stderr, wall };
}

function parse(out) {
  const phases = {},
    meta = {},
    checks = {};
  for (const line of out.split('\n')) {
    let m;
    if ((m = line.match(/^BENCH:\s*phase=(\S+)\s+t=(\S+)/))) {
      const v = +m[2];
      if (META_PHASES.has(m[1])) meta[m[1]] = v;
      else phases[m[1]] = v;
    } else if ((m = line.match(/^CHECK:\s*name=(\S+)\s+value=(\S+)/))) {
      checks[m[1]] = +m[2];
    }
  }
  return { phases, meta, checks };
}

const fmtT = (t) =>
  t == null
    ? '-'
    : t >= 10
      ? `${t.toFixed(2)}s`
      : t >= 1
        ? `${t.toFixed(3)}s`
        : `${(t * 1000).toFixed(0)}ms`;

function mdTable(headers, rows) {
  return [
    '| ' + headers.join(' | ') + ' |',
    '| ' + headers.map(() => '---').join(' | ') + ' |',
    ...rows.map((r) => '| ' + r.join(' | ') + ' |'),
  ].join('\n');
}

function summaryRow(label, ml, nb) {
  const ratio = ml != null && nb != null && ml > 0 ? (nb / ml).toFixed(2) + 'x' : '-';
  return [label, fmtT(ml), fmtT(nb), ratio];
}

function phaseRows(ml, nb) {
  const extras = Object.keys({ ...ml, ...nb }).filter((k) => !PHASE_ORDER.includes(k));
  const names = [...PHASE_ORDER, ...extras].filter((n) => n in ml || n in nb);
  const rows = names.map((n) => [
    n,
    fmtT(ml[n]),
    fmtT(nb[n]),
    ml[n] != null && nb[n] != null ? (nb[n] / ml[n]).toFixed(2) + 'x' : '-',
  ]);
  const sum = (o) => Object.values(o).reduce((a, b) => a + b, 0);
  const mlS = sum(ml),
    nbS = sum(nb);
  rows.push(['**sum**', fmtT(mlS), fmtT(nbS), mlS && nbS ? (nbS / mlS).toFixed(2) + 'x' : '-']);
  return rows;
}

function checkRows(ml, nb, rtol) {
  const names = [...new Set([...Object.keys(ml), ...Object.keys(nb)])].sort();
  let maxRel = 0,
    worst = null,
    fail = 0;
  const rows = names.map((n) => {
    const a = ml[n],
      b = nb[n];
    if (a == null || b == null) return [n, a ?? '-', b ?? '-', '-', 'missing'];
    const rel = Math.abs(a - b) / Math.max(Math.abs(a), Math.abs(b), 1e-300);
    if (rel > maxRel) ((maxRel = rel), (worst = n));
    const ok = rel <= rtol;
    if (!ok) fail++;
    return [n, a.toExponential(10), b.toExponential(10), rel.toExponential(2), ok ? 'ok' : '**MISMATCH**'];
  });
  return { rows, maxRel, worst, fail };
}

async function checkNumblNativeAddon() {
  const { stdout } = await run('npx', ['tsx', NUMBL_CLI, 'info'], { maxBuffer: 1 << 20 });
  const info = JSON.parse(stdout.trim().split('\n').pop());
  if (!info.nativeAddon) {
    const numblDir = path.dirname(path.dirname(NUMBL_CLI));
    throw new Error(
      `numbl native addon is not loaded (expected at: ${info.nativeAddonPath || 'unknown'}). ` +
        `Build it with: (cd ${numblDir} && npx tsx src/cli.ts build-addon)`
    );
  }
  return info;
}

async function main() {
  const scriptArg = process.argv[2] || DEFAULT_SCRIPT;
  const scriptPath = path.resolve(scriptArg);
  const name = path.basename(scriptPath, '.m');

  console.log(`script: ${scriptArg}`);
  const info = await checkNumblNativeAddon();
  console.log(`numbl native addon: ${info.nativeAddonPath}`);
  console.log('running matlab...');
  const ml = await timed('matlab', ['-batch', `run('${scriptPath}')`]);
  console.log(`  wall: ${ml.wall.toFixed(2)}s`);
  console.log('running numbl...');
  const nb = await timed('npx', ['tsx', NUMBL_CLI, 'run', scriptPath]);
  console.log(`  wall: ${nb.wall.toFixed(2)}s`);

  const mlP = parse(ml.stdout + '\n' + ml.stderr);
  const nbP = parse(nb.stdout + '\n' + nb.stderr);
  const phases = phaseRows(mlP.phases, nbP.phases);
  const checks = checkRows(mlP.checks, nbP.checks, RTOL);

  // Startup = wall time - chunkie install - script execution. The script's
  // `execution` phase starts after `mip load`, so this subtraction cleanly
  // isolates the engine startup overhead without attributing chunkie install
  // time to it.
  const mlStartup = ml.wall - (mlP.meta.chunkie_load ?? 0) - (mlP.meta.execution ?? 0);
  const nbStartup = nb.wall - (nbP.meta.chunkie_load ?? 0) - (nbP.meta.execution ?? 0);
  const summary = [
    summaryRow('startup', mlStartup, nbStartup),
    summaryRow('execution', mlP.meta.execution, nbP.meta.execution),
  ];

  const chunkieNote =
    mlP.meta.chunkie_load != null && nbP.meta.chunkie_load != null
      ? `Chunkie install time is excluded from both rows above (matlab: ${fmtT(mlP.meta.chunkie_load)}, numbl: ${fmtT(nbP.meta.chunkie_load)}).`
      : '';

  const md = `# Benchmark: ${name}

- **Script:** \`${scriptArg}\`
- **Date:** ${new Date().toISOString().slice(0, 10)}
- **Relative tolerance:** \`${RTOL}\`

## Timing summary

${mdTable(['metric', 'matlab', 'numbl', 'ratio (nb/ml)'], summary)}

${chunkieNote}

## Phase timings

${mdTable(['phase', 'matlab', 'numbl', 'ratio (nb/ml)'], phases)}

## Result checks

${mdTable(['name', 'matlab', 'numbl', 'rel_diff', 'status'], checks.rows)}

Max relative difference: **${checks.maxRel.toExponential(2)}**${checks.worst ? ` (\`${checks.worst}\`)` : ''}
Mismatches above tolerance: **${checks.fail}**
`;

  await mkdir('reports', { recursive: true });
  const reportPath = `reports/${name}.md`;
  await writeFile(reportPath, md);
  console.log(`wrote ${reportPath}  (mismatches: ${checks.fail})`);
  process.exit(checks.fail > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
