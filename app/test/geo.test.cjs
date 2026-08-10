// geo.ts 실컴파일 산출물 직접 테스트 (재타이핑 사본 아님)
const { distM, acceptFix, smoothTrace, mergeFixes, getOneShotPosition } = require('./geo.build.cjs');
let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('✅ ' + name); }
  else { fail++; console.log('❌ ' + name + (detail ? ' — ' + detail : '')); }
};

// ── distM ──
const cityHall = { lat: 37.5665, lng: 126.978, t: 0 };
const gangnam = { lat: 37.4979, lng: 127.0276, t: 0 };
const d1 = distM(cityHall, gangnam);
t('distM 시청→강남 ≈ 8.9km', d1 > 8500 && d1 < 9300, '=' + Math.round(d1));
t('distM 동일점 = 0', distM(cityHall, cityHall) === 0);
const p5m = { lat: 37.5665 + 5 / 111320, lng: 126.978, t: 0 };
const d5 = distM(cityHall, p5m);
t('distM 5m 북쪽 ≈ 5m', d5 > 4.9 && d5 < 5.1, '=' + d5.toFixed(3));

// ── acceptFix ──
const base = { lat: 37.5665, lng: 126.978, t: 1000000, acc: 5 };
t('acceptFix: 첫 픽스(정확도 양호) 수락', acceptFix(null, base) === true);
t('acceptFix: 정확도 26m 거부', acceptFix(null, { ...base, acc: 26 }) === false);
t('acceptFix: 정확도 정확히 25m 수락 (경계)', acceptFix(null, { ...base, acc: 25 }) === true);
t('acceptFix: 정확도 없음(acc undefined) 수락', acceptFix(null, { lat: 1, lng: 1, t: 0 }) === true);
// 2초 뒤 10m 이동 = 5m/s → 수락
const walk = { lat: 37.5665 + 10 / 111320, lng: 126.978, t: 1002000, acc: 5 };
t('acceptFix: 5m/s 정상 이동 수락', acceptFix(base, walk) === true);
// 2초 뒤 100m = 50m/s → 거부
const tp = { lat: 37.5665 + 100 / 111320, lng: 126.978, t: 1002000, acc: 5 };
t('acceptFix: 50m/s 순간이동 거부', acceptFix(base, tp) === false);
// 정확히 10m/s (2초 20m) → 수락 (>10만 거부)
const edge = { lat: 37.5665 + 19.99 / 111320, lng: 126.978, t: 1002000, acc: 5 };
t('acceptFix: ~10m/s 경계 수락', acceptFix(base, edge) === true);
// 같은 타임스탬프 → 거부 (0으로 나누기 방어)
t('acceptFix: dt=0 거부', acceptFix(base, { ...walk, t: 1000000 }) === false);
// 시간 역행 → 거부
t('acceptFix: 시간 역행 거부', acceptFix(base, { ...walk, t: 999000 }) === false);

// ── smoothTrace ──
const line = (n) => Array.from({ length: n }, (_, i) => ({ latitude: 37.5 + i * 0.001, longitude: 127.0 + i * 0.001 }));
t('smoothTrace: 0점 통과', smoothTrace([]).length === 0);
t('smoothTrace: 1점 통과', smoothTrace(line(1)).length === 1);
t('smoothTrace: 2점 통과 (보간 없음)', smoothTrace(line(2)).length === 2);
const s10 = smoothTrace(line(10));
t('smoothTrace: 길이 = 1+(n-1)*6', s10.length === 1 + 9 * 6, '=' + s10.length);
t('smoothTrace: 시작점 보존', s10[0].latitude === 37.5 && s10[0].longitude === 127.0);
const last = s10[s10.length - 1];
t('smoothTrace: 끝점 보존', Math.abs(last.latitude - 37.509) < 1e-9 && Math.abs(last.longitude - 127.009) < 1e-9,
  JSON.stringify(last));
t('smoothTrace: NaN 없음', s10.every((p) => Number.isFinite(p.latitude) && Number.isFinite(p.longitude)));
// 직선 입력 → 직선 유지 (콜리니어)
const collinear = s10.every((p) => Math.abs((p.latitude - 37.5) - (p.longitude - 127.0)) < 1e-9);
t('smoothTrace: 직선 입력은 직선 유지', collinear);
// 원본 픽스가 전부 출력에 포함 (통과 보간)
const containsAll = line(10).every((orig) => s10.some((p) => Math.abs(p.latitude - orig.latitude) < 1e-9 && Math.abs(p.longitude - orig.longitude) < 1e-9));
t('smoothTrace: 원본 픽스 전부 통과', containsAll);
// 지그재그 입력 바운딩 (오버슈트 한도 — 셀 크기의 30% 이내)
const zig = Array.from({ length: 20 }, (_, i) => ({ latitude: 37.5 + (i % 2) * 0.001, longitude: 127.0 + i * 0.0005 }));
const sz = smoothTrace(zig);
const inBounds = sz.every((p) => p.latitude > 37.5 - 0.0003 && p.latitude < 37.501 + 0.0003);
t('smoothTrace: 지그재그 오버슈트 한도', inBounds);
// 성능: 1000픽스(약 1h 러닝) 스무딩 < 50ms
const big = line(1000);
const t0 = Date.now();
smoothTrace(big);
const ms = Date.now() - t0;
t('smoothTrace: 1000픽스 성능 < 50ms', ms < 50, ms + 'ms');

// ── mergeFixes (백그라운드 배치 병합 — 2026-08-08) ──
// 이 함수가 km을 만든다. km은 곧 돈이다 (settle-run: km * 3000). 배달 방식이 숫자를 바꾸면 안 된다.
const T0 = 1_700_000_000_000;
// 북쪽으로 초당 2.5m (개와 함께 뛰는 속도) — 1초 간격 픽스 생성기.
// 2.0m/s를 쓰면 1초 구간이 정확히 2m라 노이즈 게이트(d > 2)에 전부 걸린다 — 실제로도 그렇다.
const walkPts = (n, { start = T0, stepMs = 1000, mps = 2.5, acc = 5, lat0 = 37.5, lng0 = 127.0 } = {}) =>
  Array.from({ length: n }, (_, i) => ({
    lat: lat0 + (i * mps * (stepMs / 1000)) / 111320,
    lng: lng0,
    t: start + i * stepMs,
    acc,
  }));

{
  const r = mergeFixes([], []);
  t('mergeFixes: 빈 입력 → 빈 트레이스·km 0', r.trace.length === 0 && r.addedKm === 0);
}
{
  const pts = walkPts(5);
  const shuffled = [pts[3], pts[0], pts[4], pts[1], pts[2]];
  const inOrder = mergeFixes([], pts);
  const outOfOrder = mergeFixes([], shuffled);
  t('mergeFixes: 순서 뒤섞인 배치 → t 오름차순 정렬 후 동일 km',
    outOfOrder.trace.length === inOrder.trace.length
    && Math.abs(outOfOrder.addedKm - inOrder.addedKm) < 1e-12
    && outOfOrder.trace.every((p, i) => p.t === inOrder.trace[i].t),
    `${outOfOrder.trace.length} vs ${inOrder.trace.length}`);
}
{
  const existing = mergeFixes([], walkPts(5)).trace;
  // 늦게 도착한 배치가 전부 마지막 픽스보다 과거 — 트레이스가 자라지 않고 km도 0
  const late = walkPts(3, { start: T0 - 10_000 });
  const r = mergeFixes(existing, late);
  t('mergeFixes: 전부 과거인 늦은 배치 → 성장 없음·km 0',
    r.trace.length === existing.length && r.addedKm === 0);
}
{
  const existing = mergeFixes([], walkPts(3)).trace;
  const dup = existing[existing.length - 1];
  const r = mergeFixes(existing, [{ ...dup }]);
  t('mergeFixes: 마지막 픽스와 완전 동일 → 버림', r.trace.length === existing.length && r.addedKm === 0);
}
{
  const a = { lat: 37.5, lng: 127.0, t: T0, acc: 5 };
  const b = { lat: 37.5 + 1 / 111320, lng: 127.0, t: T0 + 400, acc: 5 }; // 400ms 뒤
  const r = mergeFixes([], [a, b]);
  t('mergeFixes: 400ms 간격 두 번째 픽스 → 1초 규칙으로 버림', r.trace.length === 1);
}
{
  // 경계: 포그라운드 마지막 픽스와 백그라운드 첫 픽스가 같은 초(t 차 <1000ms) — 하나만 남는다
  const existing = [{ lat: 37.5, lng: 127.0, t: T0 + 250, acc: 5 }];
  const batch = [{ lat: 37.5 + 2 / 111320, lng: 127.0, t: T0 + 900, acc: 5 }];
  const r = mergeFixes(existing, batch);
  t('mergeFixes: 같은 초의 포그라운드·백그라운드 픽스 → 하나만 생존', r.trace.length === 1 && r.addedKm === 0);
  // 정확히 1000ms 차이는 살아남는다 (서버의 초 단위 단조와 동일 경계)
  const r2 = mergeFixes(existing, [{ lat: 37.5 + 5 / 111320, lng: 127.0, t: T0 + 1250, acc: 5 }]);
  t('mergeFixes: 정확히 1000ms 간격은 수락 (경계)', r2.trace.length === 2 && r2.addedKm > 0);
}
{
  // 9m/s = acceptFix(10m/s)는 통과, 정산 게이트(8m/s)는 불통 — 트레이스엔 남고 km엔 안 센다
  const a = { lat: 37.5, lng: 127.0, t: T0, acc: 5 };
  const b = { lat: 37.5 + 9 / 111320, lng: 127.0, t: T0 + 1000, acc: 5 };
  const r = mergeFixes([], [a, b]);
  t('mergeFixes: 9m/s 구간 → 트레이스엔 남고 km엔 안 센다 (8m/s 정산 게이트)',
    r.trace.length === 2 && r.addedKm === 0, 'km=' + r.addedKm);
  const c = { lat: 37.5 + 7 / 111320, lng: 127.0, t: T0 + 1000, acc: 5 };
  const r2 = mergeFixes([], [a, c]);
  t('mergeFixes: 7m/s 구간은 km에 센다', r2.trace.length === 2 && r2.addedKm > 0);
}
{
  const pts = walkPts(4);
  const bad = { ...pts[2], acc: 26 };
  const r = mergeFixes([], [pts[0], pts[1], bad, pts[3]]);
  t('mergeFixes: 배치 안의 정확도 26m 픽스 → 버림', r.trace.length === 3 && r.trace.every((p) => p.t !== bad.t));
}
{
  // ⚑ 이 케이스가 핵심이다: 60분 러닝을 30개 배치로 받든 한 점씩 받든 km이 같아야 한다.
  // 다르면 화면에 뜨는 돈이 배달 타이밍에 따라 달라진다.
  const pts = walkPts(1800); // 1Hz × 30분, 초당 2.5m
  const oneByOne = pts.reduce((acc, p) => {
    const r = mergeFixes(acc.trace, [p]);
    return { trace: r.trace, km: acc.km + r.addedKm };
  }, { trace: [], km: 0 });
  let batched = { trace: [], km: 0 };
  for (let i = 0; i < 30; i++) {
    const r = mergeFixes(batched.trace, pts.slice(i * 60, (i + 1) * 60));
    batched = { trace: r.trace, km: batched.km + r.addedKm };
  }
  t('mergeFixes: 30개 배치 vs 한 점씩 → km 완전 동일 (돈이다)',
    Math.abs(batched.km - oneByOne.km) < 1e-9 && batched.trace.length === oneByOne.trace.length,
    `${batched.km.toFixed(6)} vs ${oneByOne.km.toFixed(6)}`);
  t('mergeFixes: 30분 1Hz 실측 km 타당 (4.5km ± 0.05)',
    Math.abs(batched.km - 4.4975) < 0.05, '=' + batched.km.toFixed(3));
}
{
  const batch = walkPts(20);
  const first = mergeFixes([], batch);
  const again = mergeFixes(first.trace, batch); // 같은 배치 재전송 (백그라운드 중복 배달)
  t('mergeFixes: 멱등 — 같은 배치 두 번 → 트레이스·km 불변',
    again.trace.length === first.trace.length && again.addedKm === 0);
}
{
  const existing = mergeFixes([], walkPts(5)).trace;
  const before = existing.slice();
  mergeFixes(existing, walkPts(5, { start: T0 + 5000 }));
  t('mergeFixes: 순수 함수 — 입력 배열을 변형하지 않는다',
    existing.length === before.length && existing.every((p, i) => p.t === before[i].t));
}

// ── getOneShotPosition (0065 picker center chain) ──
// In this node environment expo-location is external/absent, so the helper must
// resolve null — never throw, never hang. null = "try the next center", the
// contract the picker's fallback chain depends on.
(async () => {
  let oneShot;
  try { oneShot = await getOneShotPosition(); } catch (e) { oneShot = 'threw:' + e; }
  t('getOneShotPosition: 네이티브 모듈 없는 환경 → null (throw 금지)', oneShot === null,
    String(oneShot));
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail > 0 ? 1 : 0);
})();
