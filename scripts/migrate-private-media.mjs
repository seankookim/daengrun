// 0064 원샷 백필 — 공개 avatars 버킷의 강아지·러닝·채팅 사진을 프라이빗 media 버킷으로 이송.
//
//   node scripts/migrate-private-media.mjs           # 드라이런: 무엇을 옮길지 출력만
//   node scripts/migrate-private-media.mjs --yes     # 복사 + DB 경로 재작성 (원본은 남긴다)
//   node scripts/migrate-private-media.mjs --yes --purge  # 위 + 검증된 원본을 avatars에서 삭제
//
// 안전 설계 (반쯤 옮겨진 상태 = 최악이므로):
//   · 오브젝트 단위: media로 복사 성공 → 해당 행 DB 재작성. 둘 중 하나라도 실패하면 그 행은
//     기존 공개 URL 그대로 남는다 (avatars가 계속 서빙 — 404 없음).
//   · 원본 삭제는 별도 --purge 패스에서만, media 사본 존재를 재확인한 뒤 수행.
//   · 멱등: 이미 경로(비 http)인 행은 건너뛴다. 재실행 안전.
//   · feed_posts.photo_url은 runs.photos와 같은 오브젝트를 가리킨다 — 같은 실행에서 같은
//     경로로 재작성되므로 원본 삭제 전에 항상 정리된다.
//
// 대상 (0064 분할 결정과 동일):
//   dogs.photo_url · runs.photos[] · chat_messages.media_path · club_chat_messages.media_path
//   · feed_posts.photo_url (러닝 사진의 피드 사본)
// 비대상 (의도적 공개 유지): profiles.avatar_url · runners.photos · runner_gear.photo_url
//   · clubs.photo_url
//
// 필요: 루트 .env 의 SUPABASE_SERVICE_ROLE_KEY.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

function loadEnv(path) {
  try {
    return Object.fromEntries(
      readFileSync(path, 'utf8').split('\n')
        .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
        .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
    );
  } catch { return {}; }
}
const env = { ...loadEnv(join(ROOT, 'app/.env')), ...loadEnv(join(ROOT, '.env')), ...process.env };
const URL_ = env.EXPO_PUBLIC_SUPABASE_URL;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !SERVICE) { console.error('루트 .env 에 SUPABASE_SERVICE_ROLE_KEY 필요'); process.exit(1); }

const APPLY = process.argv.includes('--yes');
const PURGE = process.argv.includes('--purge');
const H = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` };

// 공개 avatars URL → 스토리지 경로 (해당 없으면 null). 쿼리스트링(?v=)은 버린다.
// 이 스크립트가 옮기는 프리픽스만 인정 — gallery/gear/avatar/club-* 는 공개 유지라 제외.
const PRIVATE_PREFIX = /^[0-9a-f-]{36}\/(dogs|runs|chat|clubchat)\//;
function toPath(url) {
  if (typeof url !== 'string' || !/^https?:/.test(url)) return null;
  const at = url.indexOf('/avatars/');
  if (at < 0) return null;
  const path = url.slice(at + '/avatars/'.length).split('?')[0];
  return PRIVATE_PREFIX.test(path) ? path : null;
}

async function rest(pathq, init = {}) {
  const res = await fetch(`${URL_}/rest/v1/${pathq}`, { ...init, headers: { ...H, 'Content-Type': 'application/json', ...init.headers } });
  if (!res.ok) throw new Error(`${pathq}: ${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

const moved = new Set();   // avatars paths whose media copy is confirmed (purge candidates)
let copied = 0, rewritten = 0, skipped = 0, failed = 0;

async function copyToMedia(path) {
  if (moved.has(path)) return true;
  // 이미 사본이 있으면 통과 (멱등)
  const head = await fetch(`${URL_}/storage/v1/object/media/${path}`, { headers: H });
  if (head.ok) { head.body?.cancel?.(); moved.add(path); return true; }
  const src = await fetch(`${URL_}/storage/v1/object/avatars/${path}`, { headers: H });
  if (!src.ok) { console.log(`  ✗ 원본 없음 avatars/${path} (${src.status}) — 행 유지`); failed++; return false; }
  const bytes = Buffer.from(await src.arrayBuffer());
  const up = await fetch(`${URL_}/storage/v1/object/media/${path}`, {
    method: 'POST',
    headers: { ...H, 'Content-Type': src.headers.get('content-type') ?? 'image/jpeg', 'x-upsert': 'true' },
    body: bytes,
  });
  if (!up.ok) { console.log(`  ✗ 복사 실패 media/${path}: ${up.status} ${await up.text()}`); failed++; return false; }
  moved.add(path); copied++;
  return true;
}

async function migrateColumn(table, idCol, col) {
  const rows = await rest(`${table}?select=${idCol},${col}&${col}=like.http%25`);
  console.log(`${table}.${col}: 공개 URL ${rows.length}행`);
  for (const row of rows) {
    const path = toPath(row[col]);
    if (!path) { skipped++; continue; }  // 이송 대상 프리픽스가 아님 (공개 유지 콘텐츠)
    if (!APPLY) { console.log(`  → ${path}`); continue; }
    if (!(await copyToMedia(path))) continue;
    await rest(`${table}?${idCol}=eq.${row[idCol]}`, { method: 'PATCH', body: JSON.stringify({ [col]: path }) });
    rewritten++;
  }
}

async function migrateRunsPhotos() {
  const rows = await rest('runs?select=id,photos&photos=not.eq.{}');
  const targets = rows.filter((r) => (r.photos ?? []).some((u) => toPath(u)));
  console.log(`runs.photos: 공개 URL 포함 ${targets.length}행`);
  for (const row of targets) {
    const next = [];
    let ok = true;
    for (const u of row.photos) {
      const path = toPath(u);
      if (!path) { next.push(u); continue; }
      if (!APPLY) { console.log(`  → ${path}`); next.push(u); continue; }
      if (await copyToMedia(path)) next.push(path);
      else { next.push(u); ok = false; }  // 실패 원소는 공개 URL로 남긴다 — 404 금지
    }
    if (APPLY) {
      await rest(`runs?id=eq.${row.id}`, { method: 'PATCH', body: JSON.stringify({ photos: next }) });
      if (ok) rewritten++;
    }
  }
}

console.log(`${APPLY ? '실행' : '드라이런'} — avatars → media 이송 (프리픽스: dogs/ runs/ chat/ clubchat/)`);
await migrateColumn('dogs', 'id', 'photo_url');
await migrateRunsPhotos();
await migrateColumn('chat_messages', 'id', 'media_path');
await migrateColumn('club_chat_messages', 'id', 'media_path');
await migrateColumn('feed_posts', 'id', 'photo_url');   // runs와 같은 오브젝트 — 같은 경로로 재작성

// [adversarial P1] Purge candidates are re-derived from the DB, NOT from `moved`.
// `moved` only fills when THIS run copies something, and migrateColumn only selects rows whose
// value still starts with http. So the documented two-step shape (`--yes`, then later
// `--yes --purge`) found zero http rows on the second pass, left `moved` empty, deleted nothing,
// and exited 0 — every legacy photo stayed world-readable in `avatars` while the run reported
// success. Re-deriving from bare paths already written to the DB makes purge idempotent and
// correct whether it runs in the same invocation or a later one.
async function purgeTargets() {
  const out = new Set();
  const take = (v) => { if (typeof v === 'string' && !/^https?:/.test(v) && PRIVATE_PREFIX.test(v)) out.add(v); };
  for (const [t, c] of [['dogs', 'photo_url'], ['chat_messages', 'media_path'],
                        ['club_chat_messages', 'media_path'], ['feed_posts', 'photo_url']]) {
    for (const row of await rest(`${t}?select=${c}&${c}=not.is.null`)) take(row[c]);
  }
  for (const row of await rest('runs?select=photos&photos=not.eq.{}')) (row.photos ?? []).forEach(take);
  return out;
}

if (APPLY && PURGE) {
  const targets = await purgeTargets();
  for (const p of moved) targets.add(p);   // belt-and-braces for the single-invocation shape
  console.log(`원본 삭제 (--purge): ${targets.size}개 — media 사본 재확인 후 삭제`);
  for (const path of targets) {
    const chk = await fetch(`${URL_}/storage/v1/object/media/${path}`, { headers: H });
    chk.body?.cancel?.();
    if (!chk.ok) { console.log(`  ✗ media 사본 확인 실패 — avatars/${path} 보존`); continue; }
    const del = await fetch(`${URL_}/storage/v1/object/avatars/${path}`, { method: 'DELETE', headers: H });
    if (!del.ok && del.status !== 404) console.log(`  ✗ 삭제 실패 avatars/${path}: ${del.status}`);
  }
}

console.log(`완료 — 복사 ${copied} · DB 재작성 ${rewritten} · 대상 외 ${skipped} · 실패 ${failed}${APPLY ? '' : ' (드라이런: 변경 없음)'}`);
if (failed > 0) process.exit(2);
