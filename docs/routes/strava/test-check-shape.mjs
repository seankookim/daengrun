#!/usr/bin/env node
// Observable-behaviour regression tests for check-shape.mjs.
// No Strava session, network, production data, or internal implementation hook
// is used: every assertion is made against the checker's JSON CLI output.

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const dir = dirname(fileURLToPath(import.meta.url));
const checker = join(dir, 'check-shape.mjs');
const scratch = mkdtempSync(join(tmpdir(), 'daengrun-shape-'));

function point(xM, yM, ele = 10) {
  const lat = 37.5 + yM / 111320;
  const lon = 127 + xM / (111320 * Math.cos(37.5 * Math.PI / 180));
  return { lat, lon, ele };
}

function path(vertices, spacingM = 100) {
  const points = [];
  for (let i = 0; i < vertices.length - 1; i++) {
    const [ax, ay] = vertices[i];
    const [bx, by] = vertices[i + 1];
    const distance = Math.hypot(bx - ax, by - ay);
    const steps = Math.max(1, Math.ceil(distance / spacingM));
    for (let step = i === 0 ? 0 : 1; step <= steps; step++) {
      const t = step / steps;
      points.push(point(ax + (bx - ax) * t, ay + (by - ay) * t));
    }
  }
  return points;
}

function writeGpx(name, points) {
  const file = join(scratch, name);
  const trkpts = points.map(({ lat, lon, ele }) =>
    `  <trkpt lat="${lat}" lon="${lon}"><ele>${ele}</ele></trkpt>`
  ).join('\n');
  writeFileSync(file, `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1"><trk><trkseg>
${trkpts}
</trkseg></trk></gpx>\n`);
  return file;
}

function check(file) {
  const result = spawnSync(process.execPath, [checker, '--json', file], { encoding: 'utf8' });
  const line = result.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1);
  assert.ok(line, `${basename(file)} produced no JSON output: ${result.stderr}`);
  return { status: result.status, value: JSON.parse(line) };
}

try {
  // Real Strava fixture with uneven vertex spacing. This caught the original
  // point-index bug: index separation is not distance along the route.
  const known = check(join(dir, '몽마르뜨_언덕_루프_1.59km.gpx'));
  assert.equal(known.status, 0, 'known Strava out-and-back must be measurable');
  assert.equal(known.value.shape, 'OUT-AND-BACK');
  assert.equal(known.value.measuredKm, 1.59);
  assert.ok(known.value.retracePct >= 60, `known retrace fell to ${known.value.retracePct}%`);

  // The return leg is 30 m away from the outbound leg. A lane-width, nearest-
  // point checker wrongly reported 0%; the 60 m point-to-segment corridor must
  // continue to recognize this common Seoul paired-path pattern.
  const parallel = check(writeGpx('parallel-out-and-back.gpx', path([
    [0, 0], [0, 1000], [30, 1000], [30, 0], [0, 0],
  ])));
  assert.equal(parallel.status, 0);
  assert.equal(parallel.value.shape, 'OUT-AND-BACK');
  assert.ok(parallel.value.retracePct >= 60, `parallel retrace was only ${parallel.value.retracePct}%`);

  // Happy path: a genuinely separate 500 m square must remain a clean loop.
  const loop = check(writeGpx('square-loop.gpx', path([
    [0, 0], [0, 500], [500, 500], [500, 0], [0, 0],
  ])));
  assert.equal(loop.status, 0);
  assert.equal(loop.value.shape, 'LOOP');
  assert.ok(loop.value.retracePct <= 20, `square loop retrace rose to ${loop.value.retracePct}%`);
  assert.ok(loop.value.closureM <= 1, `square loop closure was ${loop.value.closureM} m`);

  // Error path: stacked points used to pass as a perfect loop. It must fail
  // loudly and be marked unmeasurable rather than receiving a useful shape.
  const degenerate = check(writeGpx('degenerate.gpx', [point(0, 0), point(0, 0), point(0, 0)]));
  assert.notEqual(degenerate.status, 0);
  assert.equal(degenerate.value.shape, 'DEGENERATE');
  assert.equal(degenerate.value.measurable, false);

  console.log('check-shape regression tests passed (real OAB, parallel OAB, loop, degenerate)');
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
