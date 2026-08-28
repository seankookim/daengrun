// Generates the pack-map runner marker PNGs (`app/assets/pack-runner*.png`).
//
// WHY A GENERATOR AND NOT A CHECKED-IN BINARY. Naver markers take a `require`d PNG
// (`NaverMapMarkerOverlay` image type 2), which is the ONE marker path this repo already ships
// and has seen on a device (`route-anchor.png`, 28x28 RGBA, owner/live.tsx). The custom-React-view
// marker (type 5) is documented as "많이 생성될 시 성능에 굉장히 영향" and needs `collapsable={false}`
// on iOS new arch — an untested path for a screen nobody can device-verify tonight. So the glyph
// is a PNG. Keeping the GENERATOR in the repo makes the asset reviewable as geometry rather than
// as opaque bytes, and re-runnable if the colours move.
//
// Pure Node (zlib only) — no image dependency is added to the app.
//
//   node scripts/gen-pack-runner-icon.mjs preview   # ASCII silhouette, no files written
//   node scripts/gen-pack-runner-icon.mjs           # writes the two PNGs
import zlib from 'node:zlib';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ---- geometry: a running figure facing right, expressed in a 0..1 square ----
const HEAD = { x: 0.600, y: 0.150, r: 0.093 };
// Each limb is a polyline of capsules with a half-thickness.
const LIMBS = [
  { pts: [[0.560, 0.288], [0.480, 0.430], [0.430, 0.545]], t: 0.080 }, // torso, leaning forward
  { pts: [[0.548, 0.332], [0.700, 0.398], [0.788, 0.302]], t: 0.053 }, // front arm, bent forward
  { pts: [[0.528, 0.348], [0.362, 0.402], [0.252, 0.362]], t: 0.053 }, // back arm, bent behind
  { pts: [[0.430, 0.545], [0.590, 0.660], [0.665, 0.845]], t: 0.068 }, // front leg, driving down
  { pts: [[0.430, 0.545], [0.300, 0.690], [0.170, 0.735]], t: 0.062 }, // back leg, trailing
  { pts: [[0.665, 0.845], [0.760, 0.860]], t: 0.045 },                 // front foot
  { pts: [[0.170, 0.735], [0.135, 0.640]], t: 0.042 },                 // back foot, toe up
];

// White ring width. The glyph sits on live map tiles whose colour we do not control, so the
// silhouette alone is not legible — the halo is what makes it readable over a park, a river and
// a road without inventing a background plate.
const HALO = 0.052;

function sdSegment(px, py, ax, ay, bx, by) {
  const pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
  const h = Math.max(0, Math.min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)));
  const dx = pax - bax * h, dy = pay - bay * h;
  return Math.sqrt(dx * dx + dy * dy);
}

/** Signed distance to the figure; < 0 is inside. */
function sdf(x, y) {
  let d = Math.hypot(x - HEAD.x, y - HEAD.y) - HEAD.r;
  for (const l of LIMBS) {
    for (let i = 0; i < l.pts.length - 1; i++) {
      const [ax, ay] = l.pts[i];
      const [bx, by] = l.pts[i + 1];
      d = Math.min(d, sdSegment(x, y, ax, ay, bx, by) - l.t);
    }
  }
  return d;
}

function render(size, rgb) {
  const N = 4; // supersamples per axis — the edges are antialiased, not stair-stepped
  const px = Buffer.alloc(size * size * 4, 0);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let fill = 0, halo = 0;
      for (let sy = 0; sy < N; sy++) {
        for (let sx = 0; sx < N; sx++) {
          const d = sdf((x + (sx + 0.5) / N) / size, (y + (sy + 0.5) / N) / size);
          if (d < 0) fill++;
          if (d < HALO) halo++;
        }
      }
      const aF = fill / (N * N);
      const aH = halo / (N * N);
      if (aH <= 0) continue;
      // straight (un-premultiplied) RGBA: white halo under the solid-colour figure
      const mix = (c) => Math.round(Math.max(0, Math.min(255, (c * aF + 255 * (aH - aF)) / aH)));
      const i = (y * size + x) * 4;
      px[i] = mix(rgb[0]);
      px[i + 1] = mix(rgb[1]);
      px[i + 2] = mix(rgb[2]);
      px[i + 3] = Math.round(aH * 255);
    }
  }
  return px;
}

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

function png(size, px) {
  const stride = size * 4 + 1;
  const raw = Buffer.alloc(size * stride);
  for (let y = 0; y < size; y++) {
    raw[y * stride] = 0; // filter type 0 (None)
    px.copy(raw, y * stride + 1, y * size * 4, (y + 1) * size * 4);
  }
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const c = Buffer.alloc(4);
    c.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // colour type: RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

if (process.argv[2] === 'preview') {
  const size = 46;
  let out = '';
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = sdf((x + 0.5) / size, (y + 0.5) / size);
      out += d < 0 ? '#' : d < HALO ? '.' : ' ';
    }
    out += '\n';
  }
  process.stdout.write(out);
  process.exit(0);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const assets = path.join(here, '..', 'assets');
// Colours are the theme's, spelled here because this script cannot import a TS module.
// pack-runner    = lilac.accent   #6C5CE7 — the club world's accent (DESIGN.md §2/§5)
// pack-runner-me = colors.voltDeep #7FA818 — this app's LIVE/personal colour (RULING 9)
for (const [name, rgb] of [
  ['pack-runner.png', [0x6c, 0x5c, 0xe7]],
  ['pack-runner-me.png', [0x7f, 0xa8, 0x18]],
]) {
  const buf = png(96, render(96, rgb));
  fs.writeFileSync(path.join(assets, name), buf);
  console.log(name, buf.length, 'bytes');
}
