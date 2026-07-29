#!/bin/bash
# geo.ts 실컴파일 테스트 — 재타이핑 사본이 아니라 실제 소스를 esbuild로 번들해 검증
set -eu
cd "$(dirname "$0")"
cp ../src/lib/geo.ts ./geo.src.ts
cat > ./supabase-stub.ts <<'STUB'
export const supabase: any = { channel: () => ({ subscribe: () => {}, send: async () => {}, on: () => ({ subscribe: () => ({}) }) }), removeChannel: () => {} };
STUB
sed -i.bak "s|from './supabase'|from './supabase-stub'|" geo.src.ts
npx esbuild geo.src.ts --bundle --platform=node --format=cjs --outfile=geo.build.cjs >/dev/null
node geo.test.cjs
rm -f geo.src.ts geo.src.ts.bak supabase-stub.ts geo.build.cjs
