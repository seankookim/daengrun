#!/usr/bin/env node
// Audit the current dog-route catalog boundary.
//
// GPX files are retained as research history, so their presence does not make
// them current candidates. candidate-status.psv is the explicit boundary:
// only rows marked candidate are allowed into the dog-route set.
//
// Default mode enforces the candidate gate. --strict additionally requires
// every saved GPX, including historical/review rows, to have complete retained
// source facts and a filename derived from its independent measurement.

import { readFileSync, readdirSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const dir = dirname(fileURLToPath(import.meta.url));
const strict = process.argv.includes('--strict');
const MAX_KM = 5;
const MIN_KM = 2;
const MAX_CLOSURE_M = 25;
const FORBIDDEN_QUERY = /지하(?:보도|통로|철)|역\s*연결|역\s*\d+\s*번?\s*출구|(?:subway\s*)?station\s*exit/iu;
const INCOMPLETE = /NOT RECORDED|UNKNOWN|remaining quer(?:y|ies)/iu;

function readPsv(file, columns) {
  const lines = readFileSync(join(dir, file), 'utf8').trim().split(/\r?\n/);
  const header = lines.shift().split('|');
  if (header.join('|') !== columns.join('|')) {
    throw new Error(`${file}: unexpected header\n  got: ${header.join('|')}\n  want: ${columns.join('|')}`);
  }
  return lines.filter(Boolean).map((line, index) => {
    const values = line.split('|');
    if (values.length !== columns.length) {
      throw new Error(`${file}:${index + 2}: expected ${columns.length} fields, got ${values.length}`);
    }
    return Object.fromEntries(columns.map((column, i) => [column, values[i]]));
  });
}

const statusRows = readPsv('candidate-status.psv', ['strava_id', 'status', 'dog_access', 'reason']);
const manifestRows = readPsv('manifest.psv', [
  'name', 'strava_id', 'measured_km', 'strava_km', 'gain_m_recomputed',
  'gain_m_strava', 'points', 'surface_mix', 'retrace_%', 'shape',
  'start_query', 'waypoint_queries',
]);

const failures = [];
const warnings = [];
const statusById = new Map();
const manifestById = new Map();

for (const row of statusRows) {
  if (statusById.has(row.strava_id)) failures.push(`duplicate status row: ${row.strava_id}`);
  if (!['candidate', 'review', 'superseded'].includes(row.status)) {
    failures.push(`${row.strava_id}: invalid status ${row.status}`);
  }
  if (!['surface-verified', 'unverified', 'blocked'].includes(row.dog_access)) {
    failures.push(`${row.strava_id}: invalid dog_access ${row.dog_access}`);
  }
  statusById.set(row.strava_id, row);
}
for (const row of manifestRows) {
  if (manifestById.has(row.strava_id)) failures.push(`duplicate manifest row: ${row.strava_id}`);
  manifestById.set(row.strava_id, row);
}

const gpxFiles = readdirSync(dir).filter((name) => name.endsWith('.gpx')).sort();
const gpxById = new Map();

for (const name of gpxFiles) {
  const file = join(dir, name);
  const xml = readFileSync(file, 'utf8');
  const id = /strava\.com\/routes\/(\d+)/.exec(xml)?.[1];
  if (!id) {
    failures.push(`${name}: no Strava route ID in GPX metadata`);
    continue;
  }
  if (gpxById.has(id)) failures.push(`${name}: duplicate GPX route ID ${id}`);
  gpxById.set(id, name);

  if (!/<copyright\s+author="OpenStreetMap contributors"/.test(xml)) {
    failures.push(`${name}: missing OpenStreetMap contributor attribution`);
  }

  const checked = spawnSync(process.execPath, [join(dir, 'check-shape.mjs'), '--json', file], {
    encoding: 'utf8',
  });
  const output = checked.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1);
  let geometry;
  try { geometry = JSON.parse(output); }
  catch { failures.push(`${name}: independent geometry check did not return JSON`); continue; }
  if (checked.status !== 0 || !geometry.measurable) {
    failures.push(`${name}: geometry is not independently measurable`);
    continue;
  }

  const status = statusById.get(id);
  if (!status) {
    failures.push(`${name}: missing candidate-status.psv row`);
    continue;
  }
  const manifest = manifestById.get(id);

  if (!manifest) {
    const message = `${name}: missing manifest.psv row`;
    if (status.status === 'candidate' || strict) failures.push(message);
    else warnings.push(message);
  } else {
    for (const field of [
      'measured_km', 'strava_km', 'gain_m_recomputed', 'gain_m_strava',
      'points', 'retrace_%',
    ]) {
      if (!manifest[field].trim() || !Number.isFinite(Number(manifest[field]))) {
        failures.push(`${name}: manifest ${field} is not numeric: ${manifest[field]}`);
      }
    }
    if (Math.abs(Number(manifest.measured_km) - geometry.measuredKm) > 0.01) {
      failures.push(`${name}: manifest measured_km ${manifest.measured_km} != GPX ${geometry.measuredKm}`);
    }
    if (Number(manifest.points) !== geometry.points) {
      failures.push(`${name}: manifest points ${manifest.points} != GPX ${geometry.points}`);
    }
    if (Number(manifest.gain_m_recomputed) !== geometry.gainM) {
      failures.push(`${name}: manifest recomputed gain ${manifest.gain_m_recomputed} != GPX ${geometry.gainM}`);
    }
    if (Math.abs(Number(manifest['retrace_%']) - geometry.retracePct) > 0.1) {
      failures.push(`${name}: manifest retrace ${manifest['retrace_%']} != GPX ${geometry.retracePct}`);
    }
    if (manifest.shape !== geometry.shape) {
      failures.push(`${name}: manifest shape ${manifest.shape} != GPX ${geometry.shape}`);
    }
    if (!INCOMPLETE.test(manifest.surface_mix)) {
      const surfacePcts = [...manifest.surface_mix.matchAll(/([0-9]+)%/g)]
        .map((match) => Number(match[1]));
      if (surfacePcts.length !== 3 || surfacePcts.reduce((sum, value) => sum + value, 0) !== 100) {
        failures.push(`${name}: surface_mix is not a complete three-part 100% mix: ${manifest.surface_mix}`);
      }
    }
    if (strict) {
      for (const field of ['surface_mix', 'start_query', 'waypoint_queries']) {
        if (!manifest[field].trim() || INCOMPLETE.test(manifest[field])) {
          failures.push(`${name}: ${field} is incomplete: ${manifest[field] || '(empty)'}`);
        }
      }
    }
  }

  if (status.status === 'candidate' || strict) {
    const fileKm = /_([0-9]+(?:\.[0-9]+)?)km\.gpx$/.exec(name)?.[1];
    if (!fileKm || Math.abs(Number(fileKm) - geometry.measuredKm) > 0.01) {
      failures.push(`${name}: filename is not derived from independent measured distance ${geometry.measuredKm} km`);
    }
  }

  if (status.status !== 'candidate') continue;
  if (status.dog_access !== 'surface-verified') {
    failures.push(`${name}: candidate dog access is ${status.dog_access}, not surface-verified`);
  }
  if (!(geometry.measuredKm >= MIN_KM && geometry.measuredKm < MAX_KM)) {
    failures.push(`${name}: candidate distance ${geometry.measuredKm} km is outside [${MIN_KM}, ${MAX_KM})`);
  }
  if (geometry.closureM > MAX_CLOSURE_M) {
    failures.push(`${name}: candidate closure ${geometry.closureM} m exceeds ${MAX_CLOSURE_M} m`);
  }
  if (manifest) {
    for (const field of ['surface_mix', 'start_query', 'waypoint_queries']) {
      if (!manifest[field].trim() || INCOMPLETE.test(manifest[field])) {
        failures.push(`${name}: candidate ${field} is incomplete: ${manifest[field] || '(empty)'}`);
      }
    }
    const queries = `${manifest.start_query}; ${manifest.waypoint_queries}`;
    if (FORBIDDEN_QUERY.test(queries)) {
      failures.push(`${name}: candidate queries mention a subway/station underground risk`);
    }
  }
}

for (const [id] of statusById) {
  if (!gpxById.has(id)) failures.push(`${id}: status row has no GPX file`);
}
for (const [id] of manifestById) {
  if (!gpxById.has(id)) failures.push(`${id}: manifest row has no GPX file`);
  if (!statusById.has(id)) failures.push(`${id}: manifest row has no status row`);
}

const counts = statusRows.reduce((out, row) => {
  out[row.status] = (out[row.status] || 0) + 1;
  return out;
}, {});
console.log(`GPX ${gpxFiles.length} · candidate ${counts.candidate || 0} · review ${counts.review || 0} · superseded ${counts.superseded || 0}`);
for (const warning of warnings) console.log(`WARN ${warning}`);
for (const failure of failures) console.error(`FAIL ${failure}`);
if (failures.length) process.exit(1);
console.log(strict ? 'STRICT AUDIT PASSED' : 'CANDIDATE AUDIT PASSED');
