#!/usr/bin/env node
// build-artifact.mjs — produce the PUBLISHED-ARTIFACT page from the local one.
//
//   node build-artifact.mjs > route-bench.artifact.html
//
// WHY THIS FILE EXISTS IN THE REPO. The artifact used to be assembled from three
// fragments living in /tmp. The scratchpad was wiped and the entire build was
// gone — a deliverable whose source is in a temp directory is a deliverable you
// can publish once. Everything needed is now in git.
//
// The two pages differ in exactly three ways, and only three:
//   1. DATA — the local page does fetch('routes.json'); the artifact inlines it,
//      because an Artifact's CSP blocks every external request including its own
//      relative fetches once published.
//   2. MAP — the local page loads the Naver SDK; the artifact CANNOT (same CSP,
//      and it fails silently rather than erroring), so it draws a compacted OSM
//      street basemap that travels with the page.
//   3. config.js — a local-only key file, gitignored, never in the artifact.
// Everything else — measurements, verdicts, GPX replace — is shared source.

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const routes = JSON.parse(readFileSync(join(DIR, 'routes.json'), 'utf8'));

// basemaps, matched to route names the same way everything else is
const BASE_DIR = join(DIR, '..', '..', 'geo', '_base');
const norm = (s) => s.replace(/\.json$/, '').replace(/[^0-9A-Za-z가-힣.]/g, '');
const files = readdirSync(BASE_DIR).filter((f) => f.endsWith('.json') && !f.startsWith('raw-'));
const base = {};
for (const r of routes) {
  const f = files.find((x) => norm(x) === norm(r.name));
  if (f) base[r.name] = JSON.parse(readFileSync(join(BASE_DIR, f), 'utf8'));
}

let html = readFileSync(join(DIR, 'index.html'), 'utf8');

// 1. drop the doctype/head wrapper — the artifact host supplies its own
html = html.replace(/^[\s\S]*?<title>/, '<title>').replace(/<\/head>[\s\S]*?<body>/, '').replace(/<\/body>[\s\S]*$/, '');
// 2. drop the local key file
html = html.replace(/<script src="config\.js"[^>]*><\/script>\s*/, '');
// 3. Naver pane -> inline SVG basemap under the route shape
html = html.replace(/<div class="viewbox" style="margin-bottom:16px">[\s\S]*?<\/div>\s*<\/div>/, '');
html = html.replace('<title>Route Bench — local</title>', '<title>Route Bench</title>');

// 4. inline the data, and give drawMap a street basemap to draw under the line
const inject = `
const ROUTES = ${JSON.stringify(routes)};
const BASE = ${JSON.stringify(base)};
// Street geometry travels WITH the page, delta-encoded as integers against a
// per-route origin (~30 KB/route, from 736 KB raw). Classes: 2 major, 1 minor,
// 0 path, 'w' water polygon, 'p' park polygon.
function drawBase(pr, name){
  const b = BASE[name]; if(!b) return '';
  const [oLa,oLo] = b.o;
  const ST = { 2:{w:2.1,o:.50}, 1:{w:1.15,o:.34}, 0:{w:.7,o:.22} };
  let roads='', water='', parks='';
  for(const [cls,flat] of b.w){
    let d='';
    for(let i=0;i<flat.length;i+=2){
      const q = pr.pt([oLa+flat[i]/1e5, oLo+flat[i+1]/1e5]);
      d += (i?'L':'M') + q[0].toFixed(1) + ' ' + q[1].toFixed(1);
    }
    if(cls==='w') water += '<path d="'+d+'Z" fill="var(--accent)" opacity=".10"/>';
    else if(cls==='p') parks += '<path d="'+d+'Z" fill="var(--sage)" opacity=".13"/>';
    else { const s=ST[cls]; if(!s) continue;
      roads += '<path d="'+d+'" fill="none" stroke="var(--ink-3)" stroke-width="'+s.w+'" opacity="'+s.o+'" stroke-linecap="round"/>'; }
  }
  return parks+water+roads;
}
`;
html = html.replace(/let ROUTES = \[\];/, inject.trim());
// drawMap takes the route name so it can lay the basemap down first
html = html.replace('function drawMap(t,m,name){', 'function drawMap(t,m,name){');
html = html.replace("$('svgMap').innerHTML =\n    `<path", "$('svgMap').innerHTML =\n    drawBase(pr, name)+\n    `<path");
// no fetch, no Naver: boot straight from the inlined data
// Anchoring on end-of-string left the fetch in place — the artifact would have
// made a request its own CSP blocks, and failed to boot. Match the whole
// then/catch chain instead, and assert below that no fetch survives.
html = html.replace(/fetch\('routes\.json'\)[\s\S]*?\}\)\.catch\([\s\S]*?\}\);/,
`$('tCount').textContent=ROUTES.length;
$('tTowns').textContent=new Set(ROUTES.map(r=>r.town)).size;
$('tKm').textContent=ROUTES.reduce((s,r)=>s+r.km,0).toFixed(0);
buildList(); render(ROUTES[0]); if(typeof paintTally==='function') paintTally();`);
html = html.replace(/naverDraw\(r\);/g, '');
html = html.replace(/function naverDraw[\s\S]*?\n\}/, 'function naverDraw(){}');
html = html.replace(/function bootNaver[\s\S]*?\n\}/, 'function bootNaver(){}');

// The artifact must be fully self-contained: an Artifact's CSP blocks every
// external request, including a relative fetch, and the failure is silent.
if (/fetch\s*\(/.test(html)) {
  console.error('REFUSING: a fetch() survived into the artifact — it would fail silently under CSP');
  process.exit(1);
}
if (/naver\./.test(html)) {
  console.error('REFUSING: a Naver SDK reference survived into the artifact');
  process.exit(1);
}
process.stdout.write(html);
console.error(`${routes.length} routes · ${Object.keys(base).length} basemaps · ${(html.length/1024).toFixed(0)} KB`);
