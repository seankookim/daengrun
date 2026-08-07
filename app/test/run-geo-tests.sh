#!/bin/bash
# Compile-and-run test for geo.ts: bundles the REAL source with esbuild rather than a retyped
# copy, so the math these cases pin is the math that ships. That distance becomes money
# (settle-run pays km * 3000), so this runner must never be left red.
set -eu
cd "$(dirname "$0")"
cp ../src/lib/geo.ts ./geo.src.ts
cat > ./supabase-stub.ts <<'STUB'
export const supabase: any = { channel: () => ({ subscribe: () => {}, send: async () => {}, on: () => ({ subscribe: () => ({}) }) }), removeChannel: () => {} };
STUB
sed -i.bak "s|from './supabase'|from './supabase-stub'|" geo.src.ts
# Native modules are lazy-required inside try/catch at runtime, but esbuild resolves them
# statically anyway and then chokes on react-native's Flow syntax. Marking them external keeps
# the bundle to geo.ts's own logic, which is all these cases exercise.
npx esbuild geo.src.ts --bundle --platform=node --format=cjs --outfile=geo.build.cjs \
  --external:expo-location --external:expo-task-manager \
  --external:@mj-studio/react-native-naver-map >/dev/null
node geo.test.cjs
rm -f geo.src.ts geo.src.ts.bak supabase-stub.ts geo.build.cjs
