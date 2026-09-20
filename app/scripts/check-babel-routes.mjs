// Metro (Babel) is stricter than tsc in one place that bit us on 2026-09-21: a screen imported the
// interface `ReturnSeal` as a VALUE import beside its own `export default function ReturnSeal` —
// tsc accepts a type and a value sharing a name, Babel's TS plugin does not, and the JS bundle
// failed at xcodebuild while tsc, the checks and npm test were all green. This gate transforms every
// route and lib module with babel-preset-expo (what Metro uses) so that class fails here, in seconds.
import { transformAsync } from '@babel/core';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const preset = require.resolve('babel-preset-expo');
const roots = ['app', 'src'];
const files = [];
const walk = (d) => {
  for (const name of readdirSync(d)) {
    const p = join(d, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.(tsx?|jsx?)$/.test(name) && !/\.d\.ts$/.test(name)) files.push(p);
  }
};
roots.forEach(walk);

let failed = 0;
for (const f of files) {
  try {
    await transformAsync(readFileSync(f, 'utf8'), { filename: f, presets: [preset], babelrc: false, configFile: false, sourceType: 'module', ast: false, code: false, caller: { name: 'metro', platform: 'ios', supportsStaticESM: false } });
  } catch (e) {
    failed++;
    console.error(`✖ ${relative(process.cwd(), f)}: ${String(e.message).split('\n')[0]}`);
  }
}
if (failed) { console.error(`✖ Babel refused ${failed} of ${files.length} modules — the bundle would fail at xcodebuild`); process.exit(1); }
console.log(`✅ Babel transforms ${files.length} modules under app/ and src/ (Metro-strict duplicate-binding check)`);
