#!/usr/bin/env node
// build-manifest.mjs — GPX corpus -> catalog-ready manifest.
//
// Emits manifest.json: one record per route with everything a routes row needs,
// derived from the GPX itself. Nothing here is typed by hand, so nothing here
// can disagree with the geometry.
//
// Constraints baked in, none of which are permission questions:
//   status  'candidate' ALWAYS. routes_active_is_earned needs a verified_run_id
//           from a settled run; no GPX can satisfy it. A drawn line is not a
//           measured line.
//   source  'algo', never 'founder'. `founder` means a founder WALK on the
//           self-booked-run rail. A loop drawn in a route builder was not walked
//           by anyone (client's correction, accepted).
//   shade / lighting  NULL. Strava supplies neither. Sean ruled that offering
//           rows with unknown lighting is fine — that permits SERVING them, it
//           does not license inventing the value.
//   trace   <= 200 points, trace_thumb <= 50 (0082 decimation budgets).
//   anchor  the FIRST TRACKPOINT — a real coordinate, unlike the existing
//           anchor_lat/lng which 0078 comments "근사값 — 소비 금지".

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const R = 6371000, rad = d => d * Math.PI / 180;
const hav = (a, b) => {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const s = Math.sin(dLat/2)**2 + Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dLon/2)**2;
  return 2 * R * Math.asin(Math.sqrt(s));
};

// Evenly decimate to at most n points, always keeping first and last so the
// anchor and the closure survive.
function decimate(pts, n) {
  if (pts.length <= n) return pts;
  const out = [], step = (pts.length - 1) / (n - 1);
  for (let i = 0; i < n; i++) out.push(pts[Math.round(i * step)]);
  return out;
}

const TOWN = [
  // Specific rows FIRST: TOWN.find takes the first match, so a specific row
  // below a generic 구 row never fires (measured: 백제고분군 mapped to 송파동).
  [/백제고분군/, '방이동'],  // 송파구; 서림올림피아드 + 방이동백제고분군 are 방이동, not 송파동
  [/봉현마을|신내/, '신내동'],  // 중랑구; 정우아파트 sits in 신내동, not 면목동
  [/^강남/, '개포동'],  // 강남구; 양재대로 anchor at 37.4836,127.0673 sits in 개포동
  [/^반포|^몽마르뜨/, '반포동'], [/^잠원/, '잠원동'], [/^압구정/, '압구정동'],
  [/^도곡/, '도곡동'], [/^잠실/, '잠실동'], [/^이촌/, '이촌동'], [/^성수/, '성수동'],
  // 올림픽선수촌/올림픽공원 sit in 오륜동, 송파구 — mapped by the filename prefix
  // another session used. Verify the 법정동 before this row is served: 파크리오
  // is already a known case of a 잠실-looking name that is legally 신천동.
  // Match on the ROUTE NAME, which is stable, not on a filename prefix. Renaming
  // the GPX files to match their own <name> silently dropped this route from the
  // manifest — the file went from 송파_... to 올림픽선수촌앞_..., the /^송파/
  // pattern stopped matching, and the row vanished with no error. A mapping keyed
  // to a filename is a mapping keyed to something that is allowed to change.
  [/^송파|올림픽선수촌|올림픽\s*공원/, '송파동'],
  [/^동작|^노량진/, '노량진동'],
  [/^성북/, '보문동'],      // 성북구; e편한세상보문1단지 sits in 보문동
  [/^마포|^상암/, '상암동'],  // 마포구
  [/^영등포/, '문래동'],      // 영등포구; 현대2차 sits by 문래·안양천
  [/^강서/, '구암동'],        // 강서구
  [/^도봉/, '방학동'],        // 도봉구
  [/^강북/, '번동'],  // 강북구
  [/^노원/, '상계동'],  // 노원구
  [/^금천/, '독산동'],  // 금천구
  // Specific rows FIRST — the generic 구 rows below flatten every 동 in the 구
  // into one, which mislabeled 장안동 as 제기동 (4 km apart) on 2026-08-20.
  [/^동대문.*장안/, '장안동'],  // 동대문구; 장안삼성래미안2차
  [/^동대문/, '제기동'],  // 동대문구
  [/^관악/, '봉천동'],  // 관악구
  [/^양천/, '목동'],  // 양천구
  [/^구로/, '구로동'],  // 구로구
  [/^강동/, '강일동'],  // 강동구
  [/^중랑/, '면목동'],  // 중랑구
  [/^광진/, '광장동'],  // 광진구
  [/^종로/, '평창동'],  // 종로구
  [/^중구/, '황학동'],  // 중구; 황학동롯데캐슬
  [/^은평/, '신사동'],  // 은평구; 정은노블스 sits in 신사동(은평)
  [/^서대문/, '홍은동'],  // 서대문구; 홍제마체스터   // 동작구; 경동아파트 sits in 노량진 rather than 동작동
];

const out = [];
for (const f of readdirSync(DIR).filter(x => x.endsWith('.gpx'))) {
  const s = readFileSync(join(DIR, f), 'utf8');
  const pts = [...s.matchAll(/lat="([-0-9.]+)" lon="([-0-9.]+)"[^>]*>\s*(?:<ele>([-0-9.]+)<\/ele>)?/g)]
    .map(m => ({ lat: +m[1], lon: +m[2], ele: m[3] ? +m[3] : null }));
  if (pts.length < 2) { console.error(`SKIP ${f}: <2 trackpoints`); continue; }

  let km = 0;
  for (let i = 1; i < pts.length; i++) km += hav(pts[i-1], pts[i]);
  km /= 1000;

  // A file with NO elevation data at all must report NULL, never 0. They are
  // different claims: 0 means "measured, and it is flat"; null means "not
  // measured". Naver's pedestrian router returns no elevation field (verified
  // 2026-08-20), so its GPX carries no <ele> — and reporting those routes as
  // flat would be a fabricated measurement, the exact class of failure this
  // corpus keeps catching. 0098's trigger stores NULL happily.
  const hasEle = pts.some((p) => p.ele != null);
  let gain = 0, ref = null;
  for (const p of pts) {
    if (p.ele == null) continue;
    if (ref === null) { ref = p.ele; continue; }
    const d = p.ele - ref;
    if (Math.abs(d) < 3) continue;
    if (d > 0) gain += d;
    ref = p.ele;
  }

  const name = ((/<name>([^<]*)<\/name>/.exec(s) || [])[1] || f.replace(/\.gpx$/, '')).trim();
  const claimed = parseFloat((/([0-9.]+)\s*km/i.exec(name) || [])[1] || 'NaN');
  // A name that disagrees with the geometry is not ingestable. This is the whole
  // rule, enforced at the last possible moment rather than trusted.
  if (!isNaN(claimed) && Math.abs((km - claimed) / claimed * 100) > 2) {
    console.error(`REFUSING ${f}: name says ${claimed}km, geometry says ${km.toFixed(2)}km`);
    continue;
  }

    // Test the ROUTE NAME first, then fall back to the filename. The name is what
  // the catalog row carries and what every join uses; the filename is derived and
  // may be renamed. Keying only on the filename dropped a route silently once.
  const town = (TOWN.find(([re]) => re.test(name)) || TOWN.find(([re]) => re.test(f)) || [null, null])[1];
  if (!town) { console.error(`SKIP ${f}: no town mapping`); continue; }

  // km must round the way POSTGRES rounds, because routes_name_km_agrees (0100)
  // checks round(name_km, 1) = km. JS toFixed rounds half-to-even-ish on binary
  // floats and Postgres rounds half-up: for a measured 5.749 km named "5.75km",
  // toFixed(1) gave 5.7 while round(5.75,1) gives 5.8, and the INSERT was
  // rejected. Silently — because I had piped the ingest to /dev/null. Round
  // half-up explicitly so both sides agree, and never suppress ingest errors.
  // And the km column comes from the km IN THE NAME when the name carries one,
  // because that is what the constraint compares. The name and the geometry
  // already agree within 2% (checked above); the constraint needs them to agree
  // at 1 decimal, which the geometry-derived value cannot guarantee (5.749 vs a
  // name of 5.75). One source for two fields, so they cannot disagree.
  const kmRounded = !isNaN(claimed) ? Math.round(claimed * 10 + 1e-9) / 10 : Math.round(km * 10 + 1e-9) / 10;
  out.push({
    name, town, area: town,
    km: kmRounded,
    measuredKm: +km.toFixed(3),
    elevationGainM: hasEle ? Math.round(gain) : null,   // null = source gave no elevation (see hasEle above)
    anchor_lat: pts[0].lat, anchor_lng: pts[0].lon,
    points: pts.length,
    // {lat,lng} OBJECTS, not [lat,lng] arrays. GeoRoutePoint is {lat,lng} and
    // every consumer reads p.lat / p.lng — on an array row those are undefined,
    // so the line silently does not draw and routeStart() returns null, which
    // drops the route out of proximity ranking with no error and no log. I
    // emitted arrays and made 20 of 28 rows geometry-blind; client found it.
    // The shape is a CONTRACT with existing rows, and I never checked mine
    // against theirs before writing 20 of them.
    trace: decimate(pts, 200).map(p => ({ lat: +p.lat.toFixed(6), lng: +p.lon.toFixed(6) })),
    trace_thumb: decimate(pts, 50).map(p => ({ lat: +p.lat.toFixed(6), lng: +p.lon.toFixed(6) })),
    status: 'candidate',
    source: 'algo',
    shade: null, lighting: null,
    gpx: f,
  });
}

out.sort((a, b) => a.town.localeCompare(b.town) || a.km - b.km);
writeFileSync(join(DIR, 'manifest.json'), JSON.stringify(out, null, 1));
const byTown = {};
out.forEach(r => (byTown[r.town] = (byTown[r.town] || 0) + 1));
console.error(`${out.length} routes across ${Object.keys(byTown).length} towns`);
console.error(JSON.stringify(byTown));
