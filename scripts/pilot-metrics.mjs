// 파일럿 지표 — PMF 게이트를 **실행 가능한 정의**로 만든다.
//
//   node scripts/pilot-metrics.mjs
//   node scripts/pilot-metrics.mjs --window 30      재예약 관찰 창 (기본 30일)
//   node scripts/pilot-metrics.mjs --json           기계 판독용
//
// 왜 있는가: CLAUDE.md와 launch-checklist가 확장의 조건을 "M1 재예약 60%"라고 못박아 두었는데,
// 그 숫자를 계산하는 코드가 저장소 어디에도 없었다. 게이트는 있고 게이지가 없었다.
// 필요: 리포 루트 .env 의 SUPABASE_SERVICE_ROLE_KEY (읽기만 한다 — 아무것도 쓰지 않는다).
//
// ── 이 스크립트가 지키는 세 가지 정직 규칙 ────────────────────────────────────────
// 1. **빈 코호트는 0%가 아니라 —.** 아직 아무도 자격이 없을 때 "0%"를 찍으면 그건 실패로 읽힌다.
//    사실은 '측정 불가'다. 분모가 0이면 퍼센트를 만들지 않는다.
// 2. **관찰 창이 안 닫힌 사람은 분모에 넣지 않는다.** 첫 러닝이 어제인 보호자를 '재예약 안 함'으로
//    세면 코호트가 어릴수록 수치가 낮게 나온다 — 시간이 지나면 저절로 오르는 가짜 추세가 생긴다.
//    창이 닫힌 사람만 분모, 아직 창 안인 사람은 따로 센다.
// 3. **테스트 계정은 실적이 아니다.** @daengrun.test · club_test_accounts · 시드 러너를 배제하고,
//    배제한 수를 함께 출력한다 (조용한 필터는 조작과 구분되지 않는다).

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const argv = process.argv.slice(2);
const JSON_OUT = argv.includes('--json');
const WINDOW_DAYS = Number(argv[argv.indexOf('--window') + 1]) || 30;

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
if (!URL_ || !SERVICE) {
  console.error('리포 루트 .env 에 SUPABASE_SERVICE_ROLE_KEY 가 필요해요 (읽기 전용으로 씁니다)');
  process.exit(1);
}

// PostgREST는 기본 1000행에서 조용히 자른다 — 잘린 채로 계산하면 **틀린 퍼센트를 자신 있게** 찍는다.
// 페이지를 끝까지 돈다 (적대 리뷰 2026-08-11).
const q = async (path, page = 1000) => {
  const out = [];
  for (let from = 0; ; from += page) {
    const sep = path.includes('?') ? '&' : '?';
    const res = await fetch(`${URL_}/rest/v1/${path}${sep}limit=${page}&offset=${from}`, {
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
    });
    if (!res.ok) { console.error(`query failed: ${path} → ${res.status} ${await res.text()}`); process.exit(1); }
    const rows = await res.json();
    out.push(...rows);
    if (rows.length < page) return out;
  }
};

// ---------- 무엇이 '진짜 예약'인가 ----------
// draft/quoted는 아직 의사가 아니다 (장바구니). payment_hold부터가 '이 사람이 실제로 잡으려 했다'.
// 취소·만료도 재예약 의사로는 센다 — 두 번째로 시도했다는 사실 자체가 M1이 묻는 것이기 때문이다.
// [적대 리뷰 교정] 이전 주석은 '취소·만료도 센다'고 적어놓고 `expired`를 빼먹었다 — 그리고 넣는 것도
// 틀렸을 것이다: expired는 draft/quoted에서도 오므로(0001:200) '두 번째로 시도했다'의 증거가 못 된다.
// 현재 상태만으로는 '결제 홀드까지 갔다가 만료된 건'을 구분할 수 없다. 그래서 expired는 **뺀다**,
// 그리고 그 사실을 여기 적는다 (재예약율을 과소 추정하는 쪽 = 안전한 쪽).
// 취소·노쇼·환불은 센다: M1이 묻는 것은 '다시 오려 했는가'이지 '두 번째가 성공했는가'가 아니다.
const INTENT = new Set([
  'payment_hold', 'matching', 'runner_pending', 'confirmed', 'runner_enroute',
  'picked_up', 'active', 'completed', 'cancelled_owner', 'cancelled_runner',
  'no_show', 'incident_review', 'refund_pending',
]);

const main = async () => {
  const [bookings, profiles, testRows, runners] = await Promise.all([
    q('bookings?select=id,owner_id,runner_id,status,created_at,scheduled_at&order=created_at.asc'),
    q('profiles?select=id,name,role'),
    q('club_test_accounts?select=profile_id'),
    q('runners?select=profile_id'),
  ]);
  // auth.users로 이메일 확인 (테스트 계정 규약: @daengrun.test)
  // 이메일 규약 필터가 **조용히 꺼지면** 테스트 예약이 실적으로 섞인다 — 실패하면 멈춘다.
  const users = await (async () => {
    const res = await fetch(`${URL_}/auth/v1/admin/users?per_page=1000`, {
      headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
    });
    if (!res.ok) {
      console.error(`auth admin 조회 실패 (${res.status}) — 이메일 기반 테스트 계정 필터를 쓸 수 없어요.`);
      console.error('필터가 반쯤 켜진 채로 계산하면 테스트 예약이 실적에 섞여요. 중단합니다.');
      process.exit(1);
    }
    const j = await res.json();
    return j.users ?? j ?? [];
  })();

  const emailOf = new Map(users.map((u) => [u.id, (u.email ?? '').toLowerCase()]));
  const testIds = new Set(testRows.map((r) => r.profile_id));
  const isTest = (pid) => {
    const e = emailOf.get(pid) ?? '';
    return testIds.has(pid) || e.endsWith('@daengrun.test') || e.endsWith('@test.local') || e.startsWith('e2e-');
  };

  const now = Date.now();
  const windowMs = WINDOW_DAYS * 24 * 60 * 60 * 1000;

  // 보호자별로 모은다
  const byOwner = new Map();
  let excluded = 0;
  const excludedBy = new Map();   // 누구를 걸렀는지 보여준다 — 조용한 필터는 조작과 구분되지 않는다
  for (const b of bookings) {
    if (!b.owner_id) continue;
    if (isTest(b.owner_id)) {
      excluded += 1;
      const k = emailOf.get(b.owner_id) ?? b.owner_id;
      excludedBy.set(k, (excludedBy.get(k) ?? 0) + 1);
      continue;
    }
    if (!INTENT.has(b.status)) continue;
    if (!byOwner.has(b.owner_id)) byOwner.set(b.owner_id, []);
    byOwner.get(b.owner_id).push(b);
  }

  // ---------- M1 재예약 ----------
  // 자격: 첫 **완료된** 러닝이 있고, 그로부터 관찰 창이 이미 닫힌 보호자.
  // 성공: 그 완료 시점 이후 창 안에 **또 예약했다** (INTENT 상태 아무거나).
  let eligible = 0, rebooked = 0, sameRunner = 0, stillOpen = 0, noCompleted = 0;
  const detail = [];
  for (const [owner, list] of byOwner) {
    // [적대 리뷰] `completed`만 보면, 나중에 분쟁으로 incident_review로 옮겨간 예약은 '완료된 첫
    // 러닝'에서 사라진다 — 러닝은 실제로 일어났는데 코호트에서 빠진다. 둘 다 첫 러닝으로 센다.
    const firstDone = list.find((b) => b.status === 'completed' || b.status === 'incident_review');
    if (!firstDone) { noCompleted += 1; continue; }
    const t0 = new Date(firstDone.created_at).getTime();
    const closed = now - t0 >= windowMs;
    const later = list.filter((b) => b.id !== firstDone.id
      && new Date(b.created_at).getTime() > t0
      && new Date(b.created_at).getTime() - t0 <= windowMs);
    if (!closed) {
      stillOpen += 1;
      // 창이 안 닫혔어도 이미 재예약했으면 그건 확정된 사실이다 — 따로 보여준다
      detail.push({ owner, state: later.length ? 'rebooked_in_open_window' : 'window_open', later: later.length });
      continue;
    }
    eligible += 1;
    if (later.length > 0) {
      rebooked += 1;
      if (later.some((b) => b.runner_id && b.runner_id === firstDone.runner_id)) sameRunner += 1;
    }
    detail.push({ owner, state: later.length ? 'rebooked' : 'lapsed', later: later.length });
  }

  const pct = (n, d) => (d === 0 ? null : Math.round((n / d) * 1000) / 10);
  const m1 = pct(rebooked, eligible);
  const m1Same = pct(sameRunner, eligible);

  const out = {
    generatedAt: new Date(now).toISOString(),
    windowDays: WINDOW_DAYS,
    gate: { metric: 'M1 rebooking', target: 60 },
    cohort: {
      eligible, rebooked, sameRunner,
      stillInWindow: stillOpen, ownersWithNoCompletedRun: noCompleted,
      testBookingsExcluded: excluded,
      testBookingsExcludedBy: Object.fromEntries(excludedBy),
    },
    m1RebookPct: m1, m1SameRunnerPct: m1Same,
    verdict: m1 === null ? 'NOT_MEASURABLE' : m1 >= 60 ? 'PASS' : 'BELOW_GATE',
  };

  if (JSON_OUT) { console.log(JSON.stringify(out, null, 2)); return; }

  const show = (v) => (v === null ? '—' : `${v}%`);
  console.log('\n═══ 파일럿 지표 — M1 재예약 게이트 ═══');
  console.log(`관찰 창: ${WINDOW_DAYS}일 · 기준: CLAUDE.md PMF 게이트 60%\n`);
  console.log(`  자격 보호자 (창이 닫힌 사람)        ${eligible}`);
  console.log(`  그중 재예약                          ${rebooked}`);
  console.log(`  그중 같은 러너로 재예약              ${sameRunner}`);
  console.log('  ─────────────────────────────────────');
  console.log(`  M1 재예약율                          ${show(m1)}   (게이트 60%)`);
  console.log(`  M1 같은 러너 재예약율                ${show(m1Same)}`);
  console.log('');
  console.log(`  아직 창 안 (분모 제외)               ${stillOpen}`);
  console.log(`  완료 러닝이 아직 없는 보호자         ${noCompleted}`);
  console.log(`  배제한 테스트 예약                   ${excluded}`);
  for (const [who, n] of excludedBy) console.log(`      └ ${who}: ${n}건`);
  console.log('');
  if (m1 === null) {
    console.log('  판정: 측정 불가 — 관찰 창이 닫힌 보호자가 아직 없어요.');
    console.log('        이건 0%가 아니에요. 숫자가 생기려면 첫 러닝 후 ' + WINDOW_DAYS + '일이 지나야 해요.');
    if (byOwner.size === 0 && excluded > 0) {
      // 정확히: '집계 대상 상태의 비-테스트 예약이 0건'. 모든 원시 행이 테스트라는 뜻은 아니다.
      console.log(`        집계 대상 상태의 예약 중 테스트 계정이 아닌 것이 0건이에요 (전체 ${bookings.length}행 중 ${excluded}건이 테스트).`);
      console.log('        이 게이지가 숫자를 내려면 필요한 건 코드가 아니라 사람이에요.');
    }
  } else {
    console.log(`  판정: ${m1 >= 60 ? '게이트 통과' : '게이트 미달'} (${show(m1)} vs 60%)`);
  }
  console.log('');
};

main().catch((e) => { console.error(e); process.exit(1); });
