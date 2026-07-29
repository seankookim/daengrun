// geo.ts 실컴파일 산출물 직접 테스트 (재타이핑 사본 아님)
const { distM, acceptFix, smoothTrace } = require('./geo.build.cjs');
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

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
