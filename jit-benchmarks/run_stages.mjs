#!/usr/bin/env node
// Run each jit-benchmark stage in MATLAB and numbl, compare timings, and
// report which stages JIT successfully in numbl.
//
// For numbl runs, we pass --dump-js so we can verify the JIT actually fired
// for the timed loop. The dump file is parsed for each stage.
//
// Usage: node run_stages.mjs                  # run all stages
//        node run_stages.mjs stage_05         # run a single stage
//        node run_stages.mjs stage_05 stage_06

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

const run = promisify(execFile);

const NUMBL_CLI = path.resolve('../../numbl/src/cli.ts');
const STAGES_DIR = path.resolve('stages');
const RTOL = 1e-12;

// ── Helpers ─────────────────────────────────────────────────────────────

async function listStages(filter) {
  const entries = await readdir(STAGES_DIR);
  const stages = entries
    .filter((f) => f.startsWith('stage_') && f.endsWith('.m'))
    .sort();
  if (!filter || filter.length === 0) return stages;
  return stages.filter((s) => filter.some((f) => s.includes(f)));
}

function parse(out) {
  const phases = {};
  const checks = {};
  for (const line of out.split('\n')) {
    let m;
    if ((m = line.match(/^BENCH:\s*phase=(\S+)\s+t=(\S+)/))) phases[m[1]] = +m[2];
    else if ((m = line.match(/^CHECK:\s*name=(\S+)\s+value=(\S+)/)))
      checks[m[1]] = +m[2];
  }
  return { phases, checks };
}

const fmtT = (t) =>
  t == null
    ? '-'
    : t >= 10
      ? `${t.toFixed(2)}s`
      : t >= 1
        ? `${t.toFixed(3)}s`
        : `${(t * 1000).toFixed(0)}ms`;

async function timed(cmd, args) {
  const t0 = process.hrtime.bigint();
  const { stdout, stderr } = await run(cmd, args, { maxBuffer: 64 << 20 });
  const wall = Number(process.hrtime.bigint() - t0) / 1e9;
  return { stdout, stderr, wall };
}

// Count JIT entries from the dump file. Returns { entries: string[] }.
async function readJitDump(file) {
  let txt;
  try {
    txt = await readFile(file, 'utf8');
  } catch {
    return { entries: [] };
  }
  const entries = [];
  for (const line of txt.split('\n')) {
    const m = line.match(/^\/\/ JIT:\s*(.+)$/);
    if (m) entries.push(m[1].trim());
  }
  return { entries };
}

// ── Per-stage runner ────────────────────────────────────────────────────

async function runStage(stageFile) {
  const stagePath = path.join(STAGES_DIR, stageFile);
  const stageName = path.basename(stageFile, '.m');

  // MATLAB
  const ml = await timed('matlab', ['-batch', `run('${stagePath}')`]);
  const mlP = parse(ml.stdout);

  // numbl with --dump-js
  const tmpDir = await mkdtemp(path.join(tmpdir(), 'jitbench-'));
  const dumpFile = path.join(tmpDir, `${stageName}.js`);
  let nb, nbP, jit;
  try {
    nb = await timed('npx', [
      'tsx',
      NUMBL_CLI,
      'run',
      stagePath,
      '--dump-js',
      dumpFile,
    ]);
    nbP = parse(nb.stdout);
    jit = await readJitDump(dumpFile);
  } finally {
    await rm(tmpDir, { recursive: true, force: true });
  }

  // Compare checks
  const checkNames = [
    ...new Set([...Object.keys(mlP.checks), ...Object.keys(nbP.checks)]),
  ].sort();
  let maxRel = 0;
  let mismatches = 0;
  for (const n of checkNames) {
    const a = mlP.checks[n];
    const b = nbP.checks[n];
    if (a == null || b == null) {
      mismatches++;
      continue;
    }
    const rel = Math.abs(a - b) / Math.max(Math.abs(a), Math.abs(b), 1e-300);
    if (rel > maxRel) maxRel = rel;
    if (rel > RTOL) mismatches++;
  }

  // Phase timings — there should be exactly one phase per stage
  const phaseKey = Object.keys(mlP.phases)[0] ?? Object.keys(nbP.phases)[0];
  const tMl = phaseKey ? mlP.phases[phaseKey] : null;
  const tNb = phaseKey ? nbP.phases[phaseKey] : null;
  const ratio = tMl && tNb ? tNb / tMl : null;

  return {
    stage: stageName,
    tMl,
    tNb,
    ratio,
    jitCount: jit.entries.length,
    jitEntries: jit.entries,
    mismatches,
    maxRel,
  };
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const filter = process.argv.slice(2);
  const stages = await listStages(filter);
  if (stages.length === 0) {
    console.error('no matching stages');
    process.exit(1);
  }

  const results = [];
  for (const s of stages) {
    process.stdout.write(`running ${s} ... `);
    try {
      const r = await runStage(s);
      results.push(r);
      const status = r.mismatches > 0 ? 'CHECK_FAIL' : r.jitCount > 0 ? 'jit' : 'no-jit';
      process.stdout.write(
        `matlab=${fmtT(r.tMl)}  numbl=${fmtT(r.tNb)}  ratio=${r.ratio ? r.ratio.toFixed(2) + 'x' : '-'}  ${status}\n`
      );
    } catch (e) {
      process.stdout.write(`ERROR\n`);
      console.error(e.message ?? e);
    }
  }

  // Summary table
  console.log('\n## Stage timing summary');
  const head = ['stage', 'matlab', 'numbl', 'ratio (nb/ml)', 'jit fns', 'check'];
  console.log('| ' + head.join(' | ') + ' |');
  console.log('| ' + head.map(() => '---').join(' | ') + ' |');
  for (const r of results) {
    console.log(
      '| ' +
        [
          r.stage,
          fmtT(r.tMl),
          fmtT(r.tNb),
          r.ratio ? r.ratio.toFixed(2) + 'x' : '-',
          String(r.jitCount),
          r.mismatches > 0 ? `**FAIL** (rel=${r.maxRel.toExponential(2)})` : 'ok',
        ].join(' | ') +
        ' |'
    );
  }

  // Print JIT entries for each stage so we can see what fired
  console.log('\n## JIT-compiled functions per stage');
  for (const r of results) {
    console.log(`\n### ${r.stage}`);
    if (r.jitEntries.length === 0) {
      console.log('  (none)');
    } else {
      for (const e of r.jitEntries) console.log('  ' + e);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
