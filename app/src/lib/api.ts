// Live API layer — replaces store.ts mocks screen by screen.
// Pattern: fetch → map to the app's existing types → screens show loading/error/empty honestly (목업 폴백 금지).
import { FunctionsHttpError } from '@supabase/supabase-js';
import { AddonKey, Booking, BookingStatus, GeoRoutePoint, RouteInfo } from '../store';
// bookings.status 원시 enum — store의 BookingStatus(목록 배지 어휘)와 다른 어휘라 별칭으로 받는다
import type { BookingStatus as DbBookingStatus } from './payphase';
import { MEDIA_BUCKET } from './media';
import { supabase } from './supabase';

// 실시간 채널 3족(chat·bk·club-chat)은 geo.ts의 run 채널과 **같은** private+setAuth 경로를 쓴다 —
// setAuth 함정(소켓 토큰 미무장 = 조용한 실패)의 사본이 둘이면 하나는 반드시 낡는다.
import { armRealtime, hookTokenRefresh, REALTIME_PRIVATE } from './geo';
// Edge Function 오류 본문에서 실제 메시지 추출 ("non-2xx" 무의미 문구 대체)
async function fnError(error: unknown, data?: any): Promise<Error> {
  if (data?.error) return new Error(data.error);
  if (error instanceof FunctionsHttpError) {
    try {
      const body = await error.context.json();
      if (body?.error) return new Error(body.error);
    } catch { /* fallthrough */ }
  }
  return error instanceof Error ? error : new Error(String(error));
}

interface RouteRow {
  id: string;
  name: string;
  area: string;
  km: number;
  terrain: string | null;
  tags: string[] | null;
  features: { g: string; label: string }[] | null;
  // 0082 K1: 실좌표 [{lat,lng}]. trace_thumb(≤50점)는 목록용, trace(≤200점)는 상세용.
  trace: GeoRoutePoint[] | null;
  trace_thumb: GeoRoutePoint[] | null;
  checked_at: string | null;
  shade: RouteInfo['shade'];
  lighting: RouteInfo['lighting'];
  status: RouteInfo['status'];
  source: RouteInfo['source'];
  town: string | null;
  elevation_gain_m: number | null;
}

// 목록 셀렉트는 전체 trace를 절대 싣지 않는다 — 승격된 코스 하나가 수백 점이고, T1 임계(15-20 코스)에서
// 마운트마다 MB급이 된다. 상세만 fetchRouteById로 전체를 받는다.
// ⚠ elevation_gain_m 은 **두 셀렉트 모두**에 있다. 상세에서만 *그리지만*, 지도 시트의 DETAIL 단은
// fetchRoutes(목록)로 받은 행을 그대로 상세 본문에 넘긴다 — 목록에서 빼면 그 화면은 값을 못 받은 걸
// '측정 안 됨(—)'으로 렌더하게 되고, 그건 데이터가 아니라 우리 셀렉트에 대한 거짓말이다.
const ROUTE_LIST_COLS = 'id,name,area,km,terrain,tags,features,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m';
const ROUTE_FULL_COLS = 'id,name,area,km,terrain,tags,features,trace,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m';

/**
 * 트레이스 좌표를 `{lat,lng}` 한 모양으로 정규화한다.
 *
 * ⚠ 2026-08-14 프로덕션에서 **두 모양이 공존**하는 걸 측정했다: 원래 시드 8행은 계약대로
 * `{lat,lng}` 객체, Strava 인제스트로 들어온 20행은 `[lat,lng]` **배열**이었다.
 * `GeoRoutePoint`는 `{lat,lng}`이고 모든 소비처가 `p.lat`/`p.lng`를 읽으므로, 배열 행에서는
 * 전부 `undefined`가 된다 — 선이 안 그려지고, `routeStart()`가 null을 돌려줘서 그 20개는
 * **거리 랭킹에서 조용히 빠진다.** 에러도 안 나고 로그도 안 남는, 정확히 제일 나쁜 종류.
 *
 * 그래서 읽는 쪽에서 두 모양을 다 받는다: 데이터를 고치는 것과 별개로, 클라이언트가 한
 * 모양만 안다는 이유로 코스가 사라지면 안 된다. 좌표 위생(유한·한국 경계)은 route-pick의
 * `usable()`이 따로 본다 — 여기서는 **모양만** 맞춘다.
 */
function normalizeTrace(geo: unknown): GeoRoutePoint[] {
  if (!Array.isArray(geo) || geo.length === 0) return [];
  const out: GeoRoutePoint[] = [];
  for (const p of geo) {
    if (Array.isArray(p)) {
      // [lat, lng] — Strava 인제스트가 쓰는 모양
      if (p.length >= 2 && typeof p[0] === 'number' && typeof p[1] === 'number') out.push({ lat: p[0], lng: p[1] });
    } else if (p && typeof p === 'object') {
      const o = p as Record<string, unknown>;
      const lat = typeof o.lat === 'number' ? o.lat : typeof o.latitude === 'number' ? o.latitude : null;
      const lng = typeof o.lng === 'number' ? o.lng : typeof o.longitude === 'number' ? o.longitude : null;
      if (lat != null && lng != null) out.push({ lat, lng });
    }
  }
  return out;
}


/** 루프가 출발점으로 돌아오는가. Sean의 명시 요구(start=end)이고, 트레이스만으로 계산되므로
 *  컬럼도 마이그레이션도 필요 없다 — 코스가 재빌드되면 이 판정은 **스스로 풀린다**.
 *  실측: 28개 중 27개가 0m, `반포 서래섬 리버 루프`만 215m (빌더가 같은 질의의 2회차에서
 *  다른 GATE로 해석해 연 지점과 다른 곳에서 루프를 닫았다). 50m는 GPS 잡음과 실제 미폐합을
 *  가르는 선. */
const CLOSURE_MAX_M = 50;
function closureM(t: GeoRoutePoint[]): number | null {
  if (t.length < 2) return null;
  const R = 6371000, rad = Math.PI / 180, a = t[0], b = t[t.length - 1];
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}
/** 디스커버리에 내놓을 수 있는가. 상세/이력(fetchRouteById)은 이 게이트를 지나지 않는다 —
 *  이미 예약된 코스가 브리핑을 잃으면 안 되기 때문. status 게이트와 같은 자리, 같은 이유. */
export function isOfferable(r: RouteInfo): boolean {
  const c = closureM(r.trace);
  return c == null || c <= CLOSURE_MAX_M;
}

function toRouteInfo(r: RouteRow, geo: GeoRoutePoint[] | null): RouteInfo {
  return {
    id: r.id,
    name: r.name,
    area: r.area,
    km: Number(r.km),
    terrain: r.terrain ?? '',
    tags: r.tags ?? [],
    features: r.features ?? [],
    // ⚠ candidate 에는 점검일을 **보여주지 않는다**. 시드 데이터의 성수 4행은 런도 큐레이터도
    // 없이 checked_at 만 들고 있어서 '7.20 점검'으로 렌더됐고, 이제 그 행들에 선까지 그려지면서
    // (날짜 + 지도) 조합이 사용자에겐 '검증된 코스'로 읽힌다. 점검의 유일한 근거는 승격이므로,
    // 승격 전에는 날짜가 있어도 '점검 예정'이 정직한 값이다. (시더 리뷰 #3)
    checkedAt: r.status === 'candidate' ? '점검 예정' : fmtChecked(r.checked_at),
    desc: composeDesc(r),
    status: r.status,
    source: r.source ?? null,
    shade: r.shade ?? null,
    lighting: r.lighting ?? null,
    // 0098. NULL과 0은 **다른 사실**이고 프로덕션에 둘 다 있다(측정 28행 중 20행, 0m~63m).
    // NULL = 이 지오메트리에 대해 재지 않았다, 0 = 재봤더니 평지다. 합치면 평지가 사라진다.
    elevationGainM: r.elevation_gain_m ?? null,
    trace: normalizeTrace(geo),
  };
}

function fmtChecked(dateStr: string | null): string {
  if (!dateStr) return '점검 예정';
  const d = new Date(dateStr);
  return `${d.getMonth() + 1}.${d.getDate()} 점검`;
}

// routes에 desc 컬럼은 없다 (0001:139-152) — 실컬럼(terrain·features)만으로 한 줄을 조립한다.
// 목업 개인화 문구('초코의 페이스와 슬개골 메모에 잘 맞아요')는 근거가 없어 제거 — 없는 건 안 쓴다.
function composeDesc(r: RouteRow): string {
  const parts: string[] = [];
  const add = (v: string | null | undefined) => {
    const s = (v ?? '').trim();
    // 지형과 겹치는 라벨(흙길 70% ↔ 흙길)은 한 번만
    if (s && !parts.some((p) => p.includes(s) || s.includes(p))) parts.push(s);
  };
  add(r.terrain);
  (r.features ?? []).forEach((f) => add(f.label));
  return parts.length > 0 ? parts.slice(0, 3).join(' · ') : `${r.area}의 안심 코스`;
}

// 서버 코스 → 앱 RouteInfo. 목업 코스 조인 제거 (2026-08-06 정직성 배치):
//  · fit(적합도) — 실 스코어러가 없다. 목업 96%를 실측처럼 보이지 않도록 필드째 뺀다.
//    반환 타입의 Omit은 store.ts RouteInfo에서 fit이 사라지면 그대로 지우면 된다.
//  · trace — 실좌표가 없으면 빈 배열. 목업 폴리라인을 코스 모양이라고 그리지 않는다.
export async function fetchRoutes(town?: string | null): Promise<RouteInfo[]> {
  // 한 동네분을 읽는다: active 우선, 없으면 candidate (D-VIS 폴백, Sean 확정 A) —
  // 이 동네에 active가 0개면 candidate를 돌려준다. 파일럿이 예약을 만들 수 있어야 그 예약이
  // 코스를 활성화하는 런을 낳는다. 단 호출부는 이들을 **자동 선택하면 안 된다**: status가
  // RouteInfo에 실려 오는 이유가 그것이고, 서버(create-booking-hold)도 candidate_ack 없이는
  // 거절한다. 첫 코스가 활성화되는 순간 이 분기는 스스로 사라진다.
  //
  // 디스커버리 = active/candidate만. 0002의 `using (active)` 정책이 0082에서 `using (true)`로
  // 열렸으므로 가시성은 이제 쿼리의 책임이다 (상세·이력은 fetchRouteById가 전 상태를 읽는다).
  const forTown = async (t: string | null): Promise<RouteRow[]> => {
    for (const status of ['active', 'candidate'] as const) {
      let q = supabase.from('routes').select(ROUTE_LIST_COLS).eq('status', status);
      if (t) q = q.eq('town', t);
      const { data, error } = await q.order('km');
      if (error) throw error;
      const rows = (data ?? []) as RouteRow[];
      if (rows.length > 0) return rows;
    }
    return [];
  };

  // 미폐합 코스는 디스커버리에서 뺀다 — 출발점으로 돌아오지 않는 루프는 Sean의 요구를
  // 만족하지 않으므로 '아직 내놓을 코스'가 아니다. 재빌드되면 자동으로 다시 들어온다.
  const rows = await forTown(town ?? null);
  if (rows.length > 0 || !town) return rows.map((r) => toRouteInfo(r, r.trace_thumb)).filter(isOfferable);

  // ── 동네 어휘 폴백 (플랜 "Town vocabulary" — 명세돼 있었지만 만들어지지 않았던 팔) ──
  // `profiles.district`와 `routes.town`은 **서로 다른 어휘**다. 실측(2026-08-13):
  // district = {null, 반포동, 성수, 뚝섬, 서울숲} · town = {반포동, 성수동} — 겹치는 값은
  // 반포동 하나뿐이다. 즉 성수/뚝섬/서울숲에 사는 보호자는 성수동에 코스가 있는데도
  // **코스를 하나도 못 본다**. 그리고 빈 목록은 조용하지 않다: 화면이 "0개 코스의 만남 장소는
  // 정해져 있고…"라는, 0개에 대해 무언가를 주장하는 문장을 그린다.
  //
  // 여기서 동네 이름을 정규화하지 **않는다** — 뚝섬·서울숲이 성수동이라고 단정하는 것은 지리
  // 판정이고, 그건 코드가 지어낼 값이 아니다(캐노니컬 목록은 별도 스코프). 대신 플랜이 이미
  // 정한 팔을 그대로 판다: **필터를 풀고 전부 보여주되, 풀었다는 사실을 로그로 남긴다.**
  // 아무것도 없는 것보다 전부가 낫고, 조용한 0보다 시끄러운 폴백이 낫다.
  console.warn(`[routes] town '${town}' matched no routes — falling back to unfiltered (district/town vocabulary mismatch)`);
  const all = await forTown(null);
  return all.map((r) => toRouteInfo(r, r.trace_thumb)).filter(isOfferable);
}

// 상세·이력·러너 브리핑 전용 — **가시성과 무관하게 어떤 라이프사이클 상태든 읽는다.**
// 디스커버리 쿼리로 코스를 찾으면 예약된 candidate가 (다른 코스가 활성화되는 순간) 브리핑
// 페이지를 잃고, 정지된 코스는 이력에서 '찾을 수 없음'으로 렌더된다 — 어제 예약한 코스인데.
// 없는 행과 숨겨진 행은 다른 사실이므로 null과 예외를 구분해서 돌려준다.
export async function fetchRouteById(id: string): Promise<RouteInfo | null> {
  const { data, error } = await supabase
    .from('routes').select(ROUTE_FULL_COLS).eq('id', id).maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const r = data as RouteRow;
  return toRouteInfo(r, r.trace ?? r.trace_thumb);
}

// 코스 페이지 '우리 기록' — 이 코스에서 내가 (보호자 또는 러너로) 완주한 러닝의 실사진.
// 타인 사진은 RLS가 막는다 — 공개 갤러리는 v2 (러닝 후 공개 동의 UI와 함께).
export async function fetchMyRoutePhotos(routeId: string): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const uid = user.user.id;
  const { data: bks, error } = await supabase.from('bookings').select('id')
    .eq('route_id', routeId).eq('status', 'completed')
    .or(`owner_id.eq.${uid},runner_id.eq.${uid}`)
    .order('scheduled_at', { ascending: false }).limit(20);
  if (error) throw error;
  const ids = (bks ?? []).map((b: any) => b.id);
  if (ids.length === 0) return [];
  const { data: runs, error: rErr } = await supabase.from('runs').select('photos, booking_id').in('booking_id', ids);
  if (rErr) throw rErr;
  return (runs ?? []).flatMap((r: any) => (r.photos as string[]) ?? []).slice(0, 12);
}

// 내 동네 — 코스 스트립 로컬 우선 정렬용 (profiles.district)
export async function fetchMyDistrict(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('profiles').select('district').eq('id', user.user.id).maybeSingle();
  return data?.district ?? null;
}

// ---------- dog profile (실초코) ----------
// [정직 웨이브 2.5 · 감사 #34] ensureDog() 삭제 — 반려견이 없는 보호자가 결제하면 목업 초코
// (이름·품종·11kg·지어낸 슬개골 메모)를 dogs에 실제로 INSERT하던 자리다. 그 메모는 러너의
// 인계 화면까지 흘러갔다. 게다가 셀렉트에 owner_id 필터가 없어(.select('id').limit(1))
// 이중 역할 계정의 RLS에서 '남의 강아지 id'를 집어올 수 있었다. 없는 아이를 만들어 주는
// 대신 화면이 등록을 요구한다 (request.tsx pay() 게이트 → /owner/dog).
export interface DogProfile {
  id: string;
  name: string;
  breed: string | null;
  birthDate: string | null; // YYYY-MM-DD
  weightKg: number | null;
  neutered: boolean | null;
  memo: string | null;
  prefTags: string[];
  vaccines: string[]; // 접종 완료 백신 타입
  photoUrl: string | null;
  weeklyGoalKm: number;
  collar: string | null; // 칼라 컬러 키 (0033) — theme.collarColors 매핑
  // Owner's suggested MINIMUM pace, sec/km (pace-state-ui-plan §4). RAW and un-defaulted:
  // null means the key is absent, and only a CONFIRMED-absent key may coalesce to 480.
  // A failed fetch must stay unknown, so the defaulting lives in the UI, never here.
  paceSuggestSec: number | null;
}

function mapDog(d: any): DogProfile {
  return {
    id: d.id,
    name: d.name,
    breed: d.breed,
    birthDate: d.birth_date,
    weightKg: d.weight_kg != null ? Number(d.weight_kg) : null,
    neutered: d.neutered,
    memo: d.memo,
    prefTags: (d.preferences as any)?.tags ?? [],
    vaccines: ((d.vaccinations as any[]) ?? []).map((v) => v.type),
    photoUrl: d.photo_url,
    weeklyGoalKm: Number(d.weekly_goal_km ?? 15),
    collar: d.collar ?? null,
    paceSuggestSec: readPaceSuggest((d.preferences as any)?.paceSuggestSec),
  };
}

// jsonb is client-writable, so a stored value can be a string, junk, or absent.
// Non-numeric → null (unset), never a fabricated number. No clamping here: the band
// clamp is a DISPLAY concern (src/lib/pace.ts clampSuggest) and the server clamps
// again at run-start snapshot time — the client is not trusted on a signal path.
function readPaceSuggest(raw: unknown): number | null {
  if (raw == null) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

const DOG_SELECT = 'id, name, breed, birth_date, weight_kg, neutered, memo, preferences, vaccinations, photo_url, weekly_goal_km, collar';

// 다견 가구 지원 — 전체 목록
export async function fetchMyDogs(): Promise<DogProfile[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase.from('dogs').select(DOG_SELECT)
    .eq('owner_id', user.user.id).order('created_at', { ascending: true });
  if (error) throw error; // [적대 리뷰 P1] 실패를 삼키면 '개 없음'으로 둔갑 — 에러 브랜치가 죽는다
  return (data ?? []).map(mapDog);
}

export async function fetchMyDog(): Promise<DogProfile | null> {
  const dogs = await fetchMyDogs();
  return dogs[0] ?? null;
}

export async function addDog(name: string): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { data, error } = await supabase.from('dogs')
    .insert({ owner_id: user.user.id, name }).select('id').single();
  if (error) throw error;
  return data.id;
}

export async function updateMyDog(dogId: string, p: {
  name?: string; breed?: string; birth_date?: string | null; weight_kg?: number | null;
  neutered?: boolean; memo?: string; prefTags?: string[]; vaccines?: string[];
  collar?: string | null; // 칼라 컬러 (0033)
  paceSuggestSec?: number; // 권장 최소 페이스 sec/km (pace-state-ui-plan §4)
}): Promise<void> {
  const { prefTags, vaccines, paceSuggestSec, ...rest } = p;
  const patch: Record<string, unknown> = { ...rest };
  if (vaccines) patch.vaccinations = vaccines.map((type) => ({ type, at: null }));
  // ⚠ `preferences` is a jsonb DOCUMENT, and this write used to REPLACE it with `{tags}`.
  // The moment a second key lives in there (paceSuggestSec), every profile save would wipe
  // it. Read-then-merge: unknown keys written by any other surface survive untouched.
  // (Not an RMW race worth an RPC — a single owner editing their own dog's form.)
  if (prefTags || paceSuggestSec != null) {
    const { data: cur, error: readErr } = await supabase
      .from('dogs').select('preferences').eq('id', dogId).maybeSingle();
    if (readErr) throw readErr; // a swallowed read here silently truncates the document
    const existing = ((cur as any)?.preferences ?? {}) as Record<string, unknown>;
    const merged: Record<string, unknown> = { ...existing };
    if (prefTags) merged.tags = prefTags;
    if (paceSuggestSec != null) merged.paceSuggestSec = paceSuggestSec;
    patch.preferences = merged;
  }
  const { error } = await supabase.from('dogs').update(patch).eq('id', dogId);
  if (error) throw error;
}

// [0064] 강아지 사진은 PRIVATE media 버킷 — DB에는 경로만 저장, 화면이 서명 URL로 푼다.
// ?v= 는 교체 시 클라이언트 이미지 캐시 무효화용 (서명 시 쿼리는 떼고 서명 후 다시 붙인다).
export async function uploadDogPhoto(dogId: string, base64: string): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/dogs/${dogId}.jpg`;
  const { error } = await supabase.storage.from(MEDIA_BUCKET)
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg', upsert: true });
  if (error) throw error;
  const stored = `${path}?v=${Date.now()}`;
  const { error: e2 } = await supabase.from('dogs').update({ photo_url: stored }).eq('id', dogId);
  if (e2) throw e2;
  return stored;
}

// ---------- bookings (edge functions) ----------
export interface HoldResult { booking_id: string; hold_expires_at: string; total_price: number }

export async function createBookingHold(p: {
  dog_id: string;
  route_id?: string;
  address_id?: string;
  scheduled_at: string;
  km: number;
  pace_label?: string;
  addons: AddonKey[];
  // ── 선택 스냅샷 (0082 §C) — 분석 등급. 금액 경로가 읽지 않는다 ──
  // recommended_route_id = 앱이 스스로 골랐을 코스. 오버라이드는 나중에
  // `route_id is distinct from recommended_route_id`로 **서버가 파생**한다 — 클라가
  // '수동이었다'고 주장하는 라벨 위에 PR-0 킬 라인을 세우지 않기 위해서.
  recommended_route_id?: string;
  selection_origin?: 'auto' | 'carousel' | 'detail_cta' | 'quick_book';
  // 점검 전(candidate) 코스를 알고 골랐다는 확인. 서버가 이것 없이는 candidate를 거절한다.
  candidate_ack?: boolean;
  // 켜져 있던 제약 칩. 자동 배정이 '걸러진 집합 안에서' 골랐다면 origin은 auto지만 보호자는
  // 선호를 표현한 것이므로, 오버라이드율과 따로 읽혀야 한다.
  route_chips?: Record<string, boolean>;
}): Promise<HoldResult> {
  const { data, error } = await supabase.functions.invoke('create-booking-hold', { body: p });
  if (error || data?.error) throw await fnError(error, data);
  return data as HoldResult;
}

// ---------- 반복 예약 (0026) ----------
// 결제 완료된 첫 예약의 스냅샷으로 시리즈 생성 (서버 RPC — 멱등).
// 이후 매시 크론이 72h 창에서 다음 주 예약을 자동 생성 (같은 러너 우선, 가용성 재검증).
export async function createRecurringSeries(bookingId: string): Promise<string> {
  const { data, error } = await supabase.rpc('create_recurring_series', { p_booking: bookingId });
  if (error) throw error;
  return data as string;
}

// 해지 = paused (go-backable — 시리즈 이력 보존, 이미 생성된 예약은 그대로)
export async function pauseRecurringSeries(seriesId: string): Promise<void> {
  const { error } = await supabase.from('recurring_series').update({ paused: true }).eq('id', seriesId);
  if (error) throw error;
}

export async function confirmPayment(bookingId: string): Promise<void> {
  const { data, error } = await supabase.functions.invoke('transition-booking', {
    body: { booking_id: bookingId, action: 'payment_ok' },
  });
  if (error) throw error;
  if (data?.error) throw new Error(data.error);
}

// ---------- 토스페이먼츠 실결제 (payments-toss-plan.md §2) ----------
// CLIENT CONTRACT ONLY — both edge functions are built in a parallel lane. Nothing calls these
// while TOSS_ENABLED is false (src/lib/toss.ts). Written here so the widget scaffold compiles
// against a fixed shape and the server lane has one place to check its request/response against.
//
// The law both functions enforce and this file must never work around: 클라 금액 불신 원칙.
// The client's word is never evidence — amount/paymentKey/orderId are re-verified server-side
// against the intent row and against Toss's own confirm response. These wrappers pass data,
// they do not assert facts.

// STEP 1 — intent, created BEFORE money can move (§2-7). The server mints order_id and binds
// owner + booking + amount to it, so a crash between capture and our INSERT still has a local
// trace. The client never mints an order id.
export interface PaymentIntent {
  orderId: string;      // server-minted, unique per attempt
  amount: number;       // = bookings.total_price, server truth
  customerKey: string;  // profiles.toss_customer_key (random uuid — never the profile id)
  orderName: string;    // server-composed display string for the widget
}

export async function createPaymentIntent(bookingId: string): Promise<PaymentIntent> {
  const { data, error } = await supabase.functions.invoke('create-payment-intent', {
    body: { booking_id: bookingId },
  });
  if (error || data?.error) throw await fnError(error, data);
  return data as PaymentIntent;
}

// STEP 2 — confirm. Called only from the widget's success callback, with the values Toss handed
// the client. meta carries the post-capture side effects the server now owns (§2-5b): runner
// nomination and the weekly series are performed server-side, non-fatally, so an app killed
// right after capture cannot silently lose a paying user's chosen runner or repeat.
export interface ConfirmTossMeta {
  preferred_runner_id?: string | null;
  recurring?: boolean;
}

// POST confirm-payment
//   body { order_id, payment_key, amount, meta: { preferred_runner_id, recurring } }
//   200  { ok: true, booking_status: 'matching' }  — includes the idempotent re-call
//   4xx  { error: '<honest sentence, shown verbatim>' }
// Any post-capture failure (amount mismatch / hold expired / non-DONE) is auto-cancelled at
// Toss by the server inside the same request, and the error sentence says so — the screen
// prints it as-is (pay.tsx renders failReason verbatim; do not re-word it here).
export async function confirmToss(
  orderId: string,
  paymentKey: string,
  amount: number,
  meta: ConfirmTossMeta = {},
): Promise<void> {
  const { data, error } = await supabase.functions.invoke('confirm-payment', {
    body: { order_id: orderId, payment_key: paymentKey, amount, meta },
  });
  if (error || data?.error) throw await fnError(error, data);
}

// ---------- 결제 표면 (owner/pay) ----------
// 한 예약의 청구 진실. 클라이언트 재계산 금지 — 요금은 서버가 만든 숫자다(create-booking-hold).
// [M5] RLS는 러너에게도 자기 잡 예약을 보여준다 → owner_id가 내가 아니면 '부재'로 접는다:
//      러너가 bid로 딥링크해도 남의 청구서를 보지 못한다.
// [H3] 없는 bid·0행 = null (호출자가 not_found로 렌더) — throw(통신 실패)와 다른 사실이다.
// [M6] min_fare는 이 화면이 렌더하지 않는다 → 셀렉트하지 않는다 (안 쓸 진실은 읽지 않는다).
export interface BookingCharge {
  bookingId: string;
  status: DbBookingStatus;   // 원시 enum — 페이즈 파생은 src/lib/payphase.ts 하나뿐
  baseFare: number;
  distanceFare: number;
  addonFare: number;
  totalPrice: number;
  km: number;
  addons: { key: string; price: number }[]; // 실데이터 모양 (create-booking-hold:57) — label 컬럼은 없다 (C2)
  scheduledAt: string;
  dogName: string;
  routeName: string | null;
}

export async function fetchBookingCharge(bookingId: string): Promise<BookingCharge | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data, error } = await supabase.from('bookings')
    // ⚠ routes 임베드는 FK 를 **이름으로** 지정한다. 0082 가 bookings.recommended_route_id (PR-0 계측) 를
    // 추가한 뒤로 bookings→routes FK 가 둘이라 PostgREST 가 `routes(name)` 을 풀지 못한다 (PGRST201) —
    // 프로덕션에서 6일간 모든 예약 목록이 '불러오지 못했어요' 였다. 실측 2026-08-19.
    .select('base_fare, distance_fare, addon_fare, total_price, km, addons, status, scheduled_at, owner_id, dogs(name), routes!bookings_route_id_fkey(name)')
    .eq('id', bookingId).maybeSingle();
  // [리뷰 #3] 비정형 bid(uuid 아님)는 22P02로 온다 — 통신 실패가 아니라 '부재'다.
  // error로 던지면 영원히 실패할 재시도 버튼이 생긴다 (C1 죽은-버튼 법).
  if (error && (error as any).code === '22P02') return null;
  if (error) throw error;
  if (!data) return null;
  const b = data as any;
  if (b.owner_id !== user.user.id) return null; // 내 예약이 아니다 = 부재 (M5)
  return {
    bookingId,
    status: b.status,
    baseFare: Number(b.base_fare ?? 0),
    distanceFare: Number(b.distance_fare ?? 0),
    addonFare: Number(b.addon_fare ?? 0),
    totalPrice: Number(b.total_price ?? 0),
    km: Number(b.km ?? 0),
    addons: Array.isArray(b.addons)
      ? b.addons.map((a: any) => ({ key: String(a?.key ?? ''), price: Number(a?.price ?? 0) }))
      : [],
    scheduledAt: b.scheduled_at,
    dogName: b.dogs?.name ?? '반려견',
    routeName: b.routes?.name ?? null,
  };
}

// ---------- 청구·영수증 (post-pay charge slice · payments-toss-plan §0-bis/§0-ter) ----------
// The read face of 클라 금액 불신 원칙: every number below is a server-committed fact read back
// verbatim. The client never computes a charge, never derives a payment state, and never writes
// to `payments` (0071 ships exactly one policy — the owner reads their own rows; every write is
// refused by RLS). The one action here (retryCollect) asks an edge function to re-dispatch a
// charge the SERVER already minted — it carries no amount.
//
// 가격 비가시성(§0-bis): these are the "on demand" surfaces (설정 → 결제 관리, 예약 상세 →
// 결제 내역). Absence before settlement is the honest state — callers must not invent a row.

// my_billing_card() — 0-or-1 row, auth.uid()-scoped. The billing key itself never leaves the
// server; the client only ever learns brand/last4/linked_at.
export interface BillingCard {
  brand: string | null;
  last4: string | null;
  linkedAt: string | null;
}

export async function fetchMyBillingCard(): Promise<BillingCard | null> {
  const { data, error } = await supabase.rpc('my_billing_card');
  if (error) throw error; // 실패는 '카드 없음'이 아니다 — 화면이 두 사실을 갈라 말한다
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null; // 0행 = 등록된 카드 없음
  return {
    brand: (row as any).brand ?? null,
    last4: (row as any).last4 ?? null,
    linkedAt: (row as any).linked_at ?? null,
  };
}

// my_unsettled_charge() — DERIVED server-side (no cached collection_status column, repo law).
// True = 새 예약 잠김. The server's create-booking-hold gate is the real fence; this read only
// lets the screen say WHY before the user hits a 409.
export async function fetchUnsettledCharge(): Promise<boolean> {
  const { data, error } = await supabase.rpc('my_unsettled_charge');
  if (error) throw error;
  return data === true;
}

// payments 행 — 표시용 투영. `raw`는 통째로 노출하지 않는다: 화면이 실제로 말해야 하는 두 조각
// (카드 재연결 필요 여부, 거절 사유)만 꺼낸다.
export interface PaymentRecord {
  bookingId: string;
  orderId: string;
  amount: number;
  status: string;          // pending | confirmed | canceled | partial_canceled | failed | waived
  refundedAmount: number;
  createdAt: string;
  needsCardRelink: boolean; // raw.needs_card_relink — 일반 거절과 다른 상태 (§0-ter 에러 맵)
  // raw.review — 0084 §B가 `incident` 무청구에 찍는 검토 표식. 세 번째 조각을 꺼내는 이유:
  // 이게 없으면 **검토 중인 0원과 확정된 0원이 화면에서 같은 말**이 된다('청구 없음'). 사건이
  // 열려 있는데 보호자는 '없던 일'로 읽는다. raw를 통째로 열지 않고 불리언 하나만 꺼내는 것이
  // 이 투영의 규율(두 조각→세 조각)을 깨지 않는 유일한 방법이다.
  underReview: boolean;
  lastError: string | null; // raw.last_error — 거절을 이름으로 말하기 위한 한 줄
  dogName: string | null;
  scheduledAt: string | null;
}

const PAYMENT_COLS =
  'booking_id, order_id, amount, status, refunded_amount, raw, created_at, bookings!inner(owner_id, scheduled_at, dogs(name))';

// raw.last_error는 서버가 넣는 압축 에러 본문이다 — 문자열일 수도, 객체일 수도 있다.
// 모양을 모르면 지어내지 않고 한 줄로 접거나 null로 둔다 (없는 사유를 만들지 않는다).
function rawError(raw: any): string | null {
  const e = raw?.last_error;
  if (typeof e === 'string') return e.trim() || null;
  if (e && typeof e === 'object' && typeof e.message === 'string') return e.message.trim() || null;
  return null;
}

function toPaymentRecord(r: any): PaymentRecord {
  return {
    bookingId: r.booking_id,
    orderId: r.order_id,
    amount: Number(r.amount ?? 0),
    status: String(r.status),
    refundedAmount: Number(r.refunded_amount ?? 0),
    createdAt: r.created_at,
    needsCardRelink: r.raw?.needs_card_relink === true,
    // 해소는 `review_resolved_at`의 부재로 판정한다 (0084 §C와 같은 문장). 오늘 그 키를 쓰는
    // 코드는 없으므로 — 0072의 케이스 정산이 쓰게 될 자리다 — 표식이 있으면 곧 검토 중이다.
    underReview: r.raw?.review === 'incident_pending' && !r.raw?.review_resolved_at,
    lastError: rawError(r.raw),
    dogName: r.bookings?.dogs?.name ?? null,
    scheduledAt: r.bookings?.scheduled_at ?? null,
  };
}

// 설정 → 결제 관리의 영수증 목록. RLS가 이미 내 예약으로 좁히지만, owner_id 필터를 한 번 더
// 건다 — 듀얼 롤 계정에서 러너로 받은 예약의 청구서는 내 영수증이 아니다 (fetchBookingCharge M5와 같은 법).
export async function fetchMyPayments(limit = 30): Promise<PaymentRecord[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase.from('payments')
    .select(PAYMENT_COLS)
    .eq('bookings.owner_id', user.user.id)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []).map(toPaymentRecord);
}

// 예약 상세의 결제 내역 — 한 예약의 행만. 0행은 '아직 청구가 없다'는 사실이지 실패가 아니다.
export async function fetchBookingPayments(bookingId: string): Promise<PaymentRecord[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase.from('payments')
    .select(PAYMENT_COLS)
    .eq('booking_id', bookingId)
    .eq('bookings.owner_id', user.user.id)
    .order('created_at', { ascending: false });
  // 비정형 bid(uuid 아님)는 22P02 — 통신 실패가 아니라 '부재' (fetchBookingCharge 리뷰 #3과 같은 법)
  if (error && (error as any).code === '22P02') return [];
  if (error) throw error;
  return (data ?? []).map(toPaymentRecord);
}

// 수동 재청구 — 실패한 청구를 다시 쏘는 단 하나의 사용자 동작. 금액은 보내지 않는다:
// 서버가 이미 만든 payments 행(같은 order_id · 같은 멱등 키)을 다시 집행할 뿐이라
// 이 호출이 두 번 나가도 이중 청구가 될 수 없다 (§0-ter 재시도 래더).
// 성공 응답이 '수금 완료'를 뜻하지는 않는다 — 결과는 payments 행을 다시 읽어서 말한다.
export async function retryCollect(bookingId: string): Promise<void> {
  const { data, error } = await supabase.functions.invoke('collect-charges', {
    body: { booking_id: bookingId },
  });
  if (error || data?.error) throw await fnError(error, data);
}

// ---------- my bookings → UI Booking ----------
const DAYS = ['일', '월', '화', '수', '목', '금', '토'];

// KST 캘린더 주(월요일 00:00 시작) — '이번 주' 창을 리더보드(월요일 리셋)와 통일.
// 롤링 7일 창은 일요일 러닝이 다음 주 토요일까지 '이번 주'로 남아 랭킹과 어긋났다.
const KST_MS = 9 * 3_600_000;
function kstWeekStartMs(t = Date.now()): number {
  const k = new Date(t + KST_MS);
  const day = (k.getUTCDay() + 6) % 7; // 월=0
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate()) - day * 86400_000 - KST_MS;
}

// KST 캘린더 월(1일 00:00 시작) — '이번 달' 창. 주 시작과 동일한 고정 UTC+9 산술 (한국은 DST 없음).
function kstMonthStartMs(t = Date.now()): number {
  const k = new Date(t + KST_MS);
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), 1) - KST_MS;
}

// [감사 P2] 기기 로컬 타임존이 아니라 Asia/Seoul 고정 — 서버(club_generate_club_sessions)가 KST 고정이라
// 기기가 UTC(에뮬레이터)·해외면 세션/홀드/채팅/영수증 시각이 어긋났다. 오프셋 파트를 KST로 계산.
function kstParts(iso: string) {
  const d = new Date(iso);
  // en-CA(YYYY-MM-DD) + 24h 파트를 Asia/Seoul로 뽑아 라벨 재조립 (Intl 실패 시 로컬 폴백)
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: false, weekday: 'short',
    }).formatToParts(d);
    const g = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
    const mon = Number(g('month')); const day = Number(g('day'));
    let h = Number(g('hour')) % 24; const min = g('minute');
    // KST 요일 인덱스 (weekday short → DAYS 매핑)
    const wk = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(g('weekday'));
    const dateLabel = `${mon}월 ${day}일 (${DAYS[wk >= 0 ? wk : d.getDay()]})`;
    const timeLabel = `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${min}`;
    return { dateLabel, timeLabel };
  } catch {
    const h = d.getHours();
    return {
      dateLabel: `${d.getMonth() + 1}월 ${d.getDate()}일 (${DAYS[d.getDay()]})`,
      timeLabel: `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${String(d.getMinutes()).padStart(2, '0')}`,
    };
  }
}

const STATUS_MAP: Record<string, BookingStatus> = {
  payment_hold: 'pending',
  matching: 'pending',
  runner_pending: 'pending',
  confirmed: 'confirmed',
  runner_enroute: 'confirmed',
  picked_up: 'handoff', // 인계 완료 ≠ 러닝 중 — 라이브 UI는 active부터
  active: 'active',
  completed: 'completed',
  cancelled_owner: 'cancelled',
  cancelled_runner: 'cancelled',
  expired: 'cancelled',
  // 환불 진행 = 취소의 후속 단계 (0047: cancelled_owner → refund_pending). 폴백 'pending'으로 두면
  // '러너 응답 대기' 배지 + 죽은 러너 변경 버튼이 생긴다 — 취소로 정직하게. (no_show·incident_review는
  // 별도 표시 어휘가 필요해 보류 — 핸드오프 참조)
  refund_pending: 'cancelled',
};

// ---------- runner side ----------
// 러너 행 확보 — 정직한 비인증 기본값(applicant·미검증). 러너 모드 진입이 심사를 통과시키지 않는다.
// (K-3: 옛 부트스트랩은 tier='certified'/identity_verified=true를 즉시 박아 '통과한 적 없는 인증'을
//  통과로 보이게 했고, 그게 P0-2(클럽 위탁 탈취)를 공짜로 만들었다. 인증 승급은 서버 측 심사 몫 —
//  실 퍼널은 /runner/apply가 대체 예정. 루프 테스트에서 인증 러너가 필요하면 서버에서 tier를 올린다.)
export async function ensureRunner(): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;

  const { data: existing } = await supabase.from('runners').select('profile_id').eq('profile_id', uid).maybeSingle();
  if (existing) return;

  const { error } = await supabase.from('runners').insert({
    profile_id: uid,
    tier: 'applicant',
    funnel_step: 'info',
    avg_pace_sec_per_km: 420,
    identity_verified: false,
    online: true,
  });
  if (error) throw error;
  // 기본 가용시간: 매일 06:00–22:00 (편집은 가용시간 설정 화면)
  await supabase.from('runner_availability_rules').insert(
    [0, 1, 2, 3, 4, 5, 6].map((wd) => ({ runner_id: uid, weekday: wd, start_min: 360, end_min: 1320 })),
  );
  await supabase.from('runner_booking_rules').insert({ runner_id: uid });
}

export interface OpenRequest {
  bookingId: string;
  dogId: string | null;
  dogName: string;
  breed: string;
  weightKg: number;
  memo: string | null;
  when: string;
  km: number;
  paceLabel: string;
  payout: number; // 수수료 33% 제외 추정 (0059)
  directed?: boolean; // 지명 요청 여부
  repeatPrior?: number; // 이 강아지와 이미 함께한 완료 러닝 수 (단골)
  photoUrl: string | null;
  prefTags: string[];
  vaccines: string[];
  routeId: string | null;   // 코스 미리보기 링크 — 수락 전 코스를 알고 결정
  routeName: string | null;
}

function mapOpenRequest(r: any, directed: boolean, rate: number): OpenRequest {
  const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
  return {
    bookingId: r.id,
    dogId: r.dogs?.id ?? null,
    dogName: r.dogs?.name ?? '반려견',
    breed: r.dogs?.breed ?? '',
    weightKg: Number(r.dogs?.weight_kg ?? 0),
    memo: r.dogs?.memo ?? null,
    when: `${dateLabel} ${timeLabel}`,
    km: Number(r.km),
    paceLabel: r.pace_label ?? "보통 7'",
    payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)), // 실수수료 견적 (일괄 33%, 0059)
    directed,
    photoUrl: r.dogs?.photo_url ?? null,
    prefTags: (r.dogs?.preferences as any)?.tags ?? [],
    vaccines: ((r.dogs?.vaccinations as any[]) ?? []).map((v) => v.type),
    routeId: r.route_id ?? null,
    routeName: r.routes?.name ?? null,
  };
}

const REQ_SELECT = 'id, scheduled_at, km, pace_label, base_fare, distance_fare, addon_fare, route_id, routes(name), dogs(id, name, breed, weight_kg, memo, photo_url, preferences, vaccinations)';

// [0042 초크포인트 수리 — 실기기 발견 2026-08-03] 오픈 풀 읽기는 marketplace_open_requests 뷰가 유일한 창구.
// 0042가 0004의 광폭 정책("runners see open requests")을 폐기했는데 클라이언트는 계속 bookings를 직접 읽어
// RLS가 조용히 0행을 돌려줬다 — 러너에게 보호자의 오픈 요청이 영영 안 보이던 원인. 뷰는 플랫 컬럼이라 전용 매퍼.
function mapOpenRequestView(r: any, rate: number): OpenRequest {
  const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
  return {
    bookingId: r.id,
    dogId: r.dog_id ?? null,
    dogName: r.dog_name ?? '반려견',
    breed: r.breed ?? '',
    weightKg: Number(r.weight_kg ?? 0),
    memo: r.memo ?? null,
    when: `${dateLabel} ${timeLabel}`,
    km: Number(r.km),
    paceLabel: r.pace_label ?? "보통 7'",
    payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)), // 실수수료 견적 (일괄 33%, 0059)
    directed: false,
    photoUrl: r.photo_url ?? null,
    prefTags: (r.preferences as any)?.tags ?? [],
    vaccines: ((r.vaccinations as any[]) ?? []).map((v) => v.type),
    routeId: r.route_id ?? null,
    routeName: r.route_name ?? null,
  };
}

// 러너 인박스: 지명 요청(runner_pending, 나에게) + 오픈 요청(matching, 미배정)
// + 단골 감지: 함께 완주한 이력이 있는 강아지엔 repeatPrior (수락 결정이 쉬워진다)
// 내 수수료율 — 견적용 (일괄 33%, 0059 — 티어 연동 없음). 세션 캐시.
let _commissionRate: number | null = null;
async function myCommissionRate(): Promise<number> {
  if (_commissionRate != null) return _commissionRate;
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return 0.33;
  const { data } = await supabase.from('runners').select('commission_rate').eq('profile_id', user.user.id).maybeSingle();
  _commissionRate = Number(data?.commission_rate ?? 0.33);
  return _commissionRate;
}

export async function fetchRunnerInbox(): Promise<OpenRequest[]> {
  const rate = await myCommissionRate();
  const { data: user } = await supabase.auth.getUser();
  const [openRes, directedRes] = await Promise.all([
    // 오픈 풀 = 0042 초크포인트 뷰 (definer·컬럼 화이트리스트·클럽 부킹 구조 배제) — bookings 직읽기는 RLS 0행
    supabase.from('marketplace_open_requests').select('*').order('scheduled_at').limit(10),
    user.user
      ? supabase.from('bookings').select(REQ_SELECT).eq('status', 'runner_pending').eq('runner_id', user.user.id).order('scheduled_at').limit(10)
      : Promise.resolve({ data: [], error: null } as any),
  ]);
  // [내성] 한쪽 다리가 죽어도 다른 쪽은 산다 — 오픈 풀 에러가 지명 요청까지 지우던 것 방지
  if (openRes.error) console.warn('[inbox] open pool:', openRes.error.message ?? openRes.error);
  if (directedRes?.error) console.warn('[inbox] directed:', directedRes.error.message ?? directedRes.error);
  const directed = (directedRes.data ?? []).map((r: any) => mapOpenRequest(r, true, rate));
  const open = (openRes.data ?? []).map((r: any) => mapOpenRequestView(r, rate));
  const all = [...directed, ...open];

  const dogIds = [...new Set(all.map((r) => r.dogId).filter(Boolean))] as string[];
  if (user.user && dogIds.length > 0) {
    const { data: hist } = await supabase
      .from('bookings').select('dog_id')
      .eq('runner_id', user.user.id).eq('status', 'completed').in('dog_id', dogIds);
    const counts: Record<string, number> = {};
    (hist ?? []).forEach((h: any) => { counts[h.dog_id] = (counts[h.dog_id] ?? 0) + 1; });
    all.forEach((r) => { if (r.dogId && counts[r.dogId]) r.repeatPrior = counts[r.dogId]; });
  }
  return all;
}

export async function fetchOpenRequests(): Promise<OpenRequest[]> {
  const rate = await myCommissionRate();
  // [0042] 오픈 풀 = 초크포인트 뷰 — bookings 직읽기 은퇴 (위 fetchRunnerInbox와 동일한 수리)
  const { data, error } = await supabase
    .from('marketplace_open_requests')
    .select('*')
    .order('scheduled_at')
    .limit(10);
  if (error) throw error;
  return (data ?? []).map((r: any) => mapOpenRequestView(r, rate));
}

async function invokeTransition(bookingId: string, action: string, meta?: Record<string, unknown>): Promise<any> {
  const { data, error } = await supabase.functions.invoke('transition-booking', {
    body: { booking_id: bookingId, action, meta },
  });
  if (error || data?.error) throw await fnError(error, data);
  return data;
}

// ---------- directed matching ----------
export interface LiveRunner {
  profileId: string;
  name: string;
  district: string;
  tier: string;
  totalRuns: number;
  paceLabel: string;
  paceSec: number;
  respondRate: number | null;
  avatarUrl: string | null;
  bio: string | null;
}

export async function fetchCertifiedRunners(): Promise<LiveRunner[]> {
  const { data, error } = await supabase
    .from('runners')
    .select('profile_id, tier, bio, avg_pace_sec_per_km, total_runs, respond_rate_pct, profiles(name, district, avatar_url)')
    .neq('tier', 'applicant')
    .eq('online', true)
    .limit(10);
  if (error) throw error;
  return (data ?? []).map((r: any) => {
    const pace = r.avg_pace_sec_per_km ?? 420;
    return {
      profileId: r.profile_id,
      name: r.profiles?.name ?? '러너',
      district: r.profiles?.district ?? '',
      tier: r.tier === 'certified' ? '인증 러너' : r.tier === 'veteran' ? '베테랑' : '마스터',
      totalRuns: r.total_runs ?? 0,
      paceLabel: `${Math.floor(pace / 60)}'${String(pace % 60).padStart(2, '0')}"`,
      paceSec: pace,
      respondRate: r.respond_rate_pct,
      avatarUrl: r.profiles?.avatar_url ?? null,
      bio: r.bio ?? null,
    };
  });
}

// 이 예약에 실제로 갈 수 있는 러너만 (0054 RPC — 수락 게이트의 표시측 거울).
// fetchCertifiedRunners와 같은 카드 데이터. 서버가 겹치는 라이브 일정(확정~진행)이 있는 러너를
// 제외해서 준다 — 지명했는데 수락이 불가능한 러너가 목록에 뜨는 일을 원천 차단.
export async function fetchAvailableRunnersFor(bookingId: string): Promise<LiveRunner[]> {
  const { data, error } = await supabase.rpc('runners_available_for', { p_booking: bookingId });
  // 날토큰 대신 행동 지시로 — not_owner의 현실적 발화점은 권한 버그가 아니라 세션 만료(auth.uid()=null),
  // not_open은 러너 선택 단계가 아닌 부킹(서버 상태 게이트)
  if (error) {
    const raw = String(error.message ?? error);
    throw new Error(raw.includes('not_owner') ? '세션이 만료된 것 같아요 — 다시 로그인해주세요'
      : raw.includes('not_open') ? '이 예약은 지금 러너 선택 단계가 아니에요'
      : raw);
  }
  return (data ?? []).map((r: any) => {
    const pace = r.avg_pace_sec_per_km ?? 420;
    return {
      profileId: r.profile_id,
      name: r.name ?? '러너',
      district: r.district ?? '',
      tier: r.tier === 'certified' ? '인증 러너' : r.tier === 'veteran' ? '베테랑' : '마스터',
      totalRuns: r.total_runs ?? 0,
      paceLabel: `${Math.floor(pace / 60)}'${String(pace % 60).padStart(2, '0')}"`,
      paceSec: pace,
      respondRate: r.respond_rate_pct,
      avatarUrl: r.avatar_url ?? null,
      bio: r.bio ?? null,
    };
  });
}

// 가용 러너 — 온라인이면서 러닝 중(확정~진행)이 아닌 러너만 (0015 뷰).
// find-now 히어로 카운트/레이더용: 바쁜 러너에게 기대를 걸게 하지 않는다.
export async function fetchAvailableRunners(): Promise<LiveRunner[]> {
  const { data, error } = await supabase.from('available_runners').select('*').limit(10);
  if (error) throw error;
  return (data ?? []).map((r: any) => {
    const pace = r.avg_pace_sec_per_km ?? 420;
    return {
      profileId: r.profile_id,
      name: r.name ?? '러너',
      district: r.district ?? '',
      tier: r.tier === 'certified' ? '인증 러너' : r.tier === 'veteran' ? '베테랑' : '마스터',
      totalRuns: r.total_runs ?? 0,
      paceLabel: `${Math.floor(pace / 60)}'${String(pace % 60).padStart(2, '0')}"`,
      paceSec: pace,
      respondRate: r.respond_rate_pct,
      avatarUrl: r.avatar_url ?? null,
      bio: r.bio ?? null,
    };
  });
}

export const requestRunner = (bookingId: string, runnerId: string) =>
  invokeTransition(bookingId, 'request_runner', { runner_id: runnerId });

// 예약 상세 (인계 동기화용): 상태 + 양측 확인 타임스탬프 + 러너 도착
export interface BookingSync {
  status: string;
  ownerConfirmed: boolean;
  runnerConfirmed: boolean;
  // 러너 도착 = 서버 진실 (0060 bookings.arrived_at). 로컬 스테이지가 아니라 이 값이 정본이라
  // 리마운트해도 양측 화면이 '도착 이전'으로 되돌아가지 않는다. null = 아직 도착 보고 없음.
  arrivedAt: string | null;
}
export async function fetchBookingSync(id: string): Promise<BookingSync> {
  const { data, error } = await supabase
    .from('bookings')
    .select('status, owner_confirmed_handoff_at, runner_confirmed_handoff_at, arrived_at')
    .eq('id', id)
    .single();
  if (error) throw error;
  return {
    status: data.status,
    ownerConfirmed: !!data.owner_confirmed_handoff_at,
    runnerConfirmed: !!data.runner_confirmed_handoff_at,
    arrivedAt: data.arrived_at ?? null,
  };
}

// ---------- 픽업 실주소 (0060 definer RPC) ----------
// 러너 전용 창구. 서버가 '배정된 러너 + 라이브 창(진행 중이거나 24h 이내 확정)'일 때만 행을 준다 —
// 없는 예약과 남의 예약은 구별되지 않는다(열거 오라클 차단). gate_code_enc는 구조적으로 선택하지 않는다.
// 삼상태 법: 0행 = null(주소 미지정·창 밖 → 화면은 '미지정'을 그린다) / 에러 = throw(라우드 페일).
// 둘을 섞으면 통신 실패가 '주소 없음'으로 위장하고 러너는 영영 재시도 버튼을 못 본다.
// lat/lng joined the contract in 0065 (coordinates slice). They are NULL until the
// owner pins the address — the screen must branch on `lat`, not on row presence:
// row-with-NULL-coords is the honest dark state ("위치가 아직 지정되지 않았어요"),
// distinct from row-absent (unassigned/outside window) and from throw (real failure).
export interface PickupAddress {
  label: string;
  addr: string;
  detail: string | null;
  lat: number | null;
  lng: number | null;
}

export async function fetchBookingAddress(bookingId: string): Promise<PickupAddress | null> {
  // 인자는 반드시 `p_booking: bookingId` 형태 — 축약형 { p_booking }은 check-rpc 계약 검사의
  // 키 정규식(콜론 필수)에 잡히지 않아 게이트를 조용히 통과한다.
  const { data, error } = await supabase.rpc('booking_pickup_address', { p_booking: bookingId });
  // [적대 리뷰 P2] not_runner는 '전송 실패'가 아니라 '아직/여기선 볼 수 없다'는 부재 신호다.
  // 24시간 창 밖(먼 확정 예약)에서도 이게 뜨는데, throw하면 멀쩡한 예약에 빨간 실패 스트립이
  // 뜨고 러너는 크리티컬 스트립을 무시하도록 학습된다. 부재는 null, 진짜 실패만 throw.
  if (error) {
    if (/not_runner/.test(error.message ?? '')) return null;
    throw error;
  }
  const row = (data as any[] | null)?.[0];
  if (!row) return null;
  return {
    label: row.label, addr: row.addr, detail: row.detail ?? null,
    lat: row.lat != null ? Number(row.lat) : null,
    lng: row.lng != null ? Number(row.lng) : null,
  };
}

// 진행 중 예약 복원 — 인메모리 id가 리로드로 날아가도 화면이 서버에서 스스로 찾는다.
// 트랜잭션 화면(미트업/런)이 데모로 조용히 전락하는 것을 막는 핵심.
const IN_FLIGHT = ['confirmed', 'runner_enroute', 'picked_up', 'active'];

// 현재 예약 해석 — '가장 진행된' 예약 우선 (scheduled_at 최신순은 러닝 중에 내일 예약을
// 집어와 이벤트·정산이 엉뚱한 예약에 붙던 버그). active > picked_up > enroute > confirmed.
const FLIGHT_RANK: Record<string, number> = { active: 0, picked_up: 1, runner_enroute: 2, confirmed: 3 };
const pickCurrent = (rows: { id: string; status: string; scheduled_at: string }[] | null): string | null => {
  if (!rows || rows.length === 0) return null;
  return rows.sort((a, b) =>
    (FLIGHT_RANK[a.status] ?? 9) - (FLIGHT_RANK[b.status] ?? 9)
    || new Date(a.scheduled_at).getTime() - new Date(b.scheduled_at).getTime(),
  )[0].id;
};

export async function fetchCurrentOwnerBookingId(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data, error } = await supabase.from('bookings').select('id, status, scheduled_at')
    .eq('owner_id', user.user.id).in('status', IN_FLIGHT);
  if (error) throw error; // 정직 배치: 네트워크 실패가 '진행 중 없음'으로 위장하면 라이브 화면 재시도 스트립이 영원히 안 뜬다
  return pickCurrent(data as any);
}

export async function fetchCurrentRunnerJobId(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('bookings').select('id, status, scheduled_at')
    .eq('runner_id', user.user.id).in('status', IN_FLIGHT);
  return pickCurrent(data as any);
}

export const acceptBooking = (id: string) => invokeTransition(id, 'runner_accept');
// 지명 거절 — runner_decline: runner_pending → matching (러너 홈 티켓의 실거절 문)
export const declineBooking = (id: string) => invokeTransition(id, 'runner_decline');
// 취소 — 서버가 수수료(미매칭 0 / 24h 전 0 / 이후 10% / 이동 중 50%) 계산·상태 전이.
// [post-pay 2026-08-13] 반환에서 `refund`가 은퇴했다: 예약 시점에 잡아둔 돈이 없으므로
// 환불이라는 사건 자체가 없다 (§0-ter #5). 서버가 돌려주는 사실은 '이번에 청구될 수수료' 하나뿐.
export const cancelBooking = (id: string): Promise<{ cancel_fee: number }> =>
  invokeTransition(id, 'cancel_owner');
// side 필수 — 한 계정이 양측인 솔로 테스트에서 서버가 역할을 추측할 수 없음
export const confirmHandoff = (id: string, side: 'owner' | 'runner') =>
  invokeTransition(id, 'confirm_handoff', { side });
export const startRunServer = (id: string) => invokeTransition(id, 'start_run');

// ---------- 일정 변경 = 제안 (reschedule-as-proposal, 0016) ----------
// 확정 예약은 계약 — scheduled_at은 러너가 수락해야만 바뀐다. 원 시간 2h 전 레이지 만료.
export interface RescheduleInfo {
  bookingId: string; status: string; scheduledAtIso: string; km: number;
  dogName: string; runnerId: string | null; runnerName: string | null;
  proposedIso: string | null; dateLabel: string; timeLabel: string;
}

export async function fetchRescheduleInfo(bookingId: string): Promise<RescheduleInfo> {
  const { data, error } = await supabase.from('bookings')
    .select('id, scheduled_at, km, status, runner_id, reschedule_new_time, dogs(name), runners(profiles(name))')
    .eq('id', bookingId).single();
  if (error) throw error;
  const d = data as any;
  const { dateLabel, timeLabel } = kstParts(d.scheduled_at);
  return {
    bookingId: d.id, status: d.status, scheduledAtIso: d.scheduled_at, km: Number(d.km),
    dogName: d.dogs?.name ?? '반려견', runnerId: d.runner_id ?? null,
    runnerName: d.runners?.profiles?.name ?? null,
    proposedIso: d.reschedule_new_time ?? null, dateLabel, timeLabel,
  };
}

export const requestReschedule = (id: string, newTimeIso: string) =>
  invokeTransition(id, 'request_reschedule', { new_time: newTimeIso });
export const acceptReschedule = (id: string) => invokeTransition(id, 'accept_reschedule');
export const declineReschedule = (id: string) => invokeTransition(id, 'decline_reschedule');
export const withdrawReschedule = (id: string) => invokeTransition(id, 'withdraw_reschedule');

// 러너 인박스용 — 내게 온 변경 요청 (만료된 것은 클라이언트에서도 제외: 레이지 만료의 표시면)
export interface RescheduleRequest {
  bookingId: string; dogName: string; km: number;
  curDate: string; curTime: string; newDate: string; newTime: string;
}

export async function fetchRescheduleRequests(): Promise<RescheduleRequest[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase.from('bookings')
    .select('id, scheduled_at, km, reschedule_new_time, dogs(name)')
    .eq('runner_id', user.user.id).eq('status', 'confirmed').not('reschedule_new_time', 'is', null);
  if (error) throw error;
  return (data ?? [])
    .filter((b: any) => new Date(b.scheduled_at).getTime() - Date.now() > 2 * 3_600_000)
    .map((b: any) => {
      const cur = kstParts(b.scheduled_at);
      const nw = kstParts(b.reschedule_new_time);
      return {
        bookingId: b.id, dogName: b.dogs?.name ?? '반려견', km: Number(b.km),
        curDate: cur.dateLabel, curTime: cur.timeLabel, newDate: nw.dateLabel, newTime: nw.timeLabel,
      };
    });
}

export async function fetchBookingStatus(id: string): Promise<string> {
  const { data, error } = await supabase.from('bookings').select('status').eq('id', id).single();
  if (error) throw error;
  return data.status;
}

export interface SettleResult { net: number; gross: number; fee: number; guarantee: number; total_runs: number; drop: string | null }

export async function settleRun(p: {
  booking_id: string;
  end_reason: 'completed' | 'dog_condition' | 'owner_request' | 'runner_personal';
  actual_km: number;
  duration_sec: number;
  condition_note?: string;
}): Promise<SettleResult> {
  const { data, error } = await supabase.functions.invoke('settle-run', { body: p });
  if (error || data?.error) throw await fnError(error, data);
  return data as SettleResult;
}

// 러너의 확정/진행/완료 작업 목록 (캘린더 = 내 커밋먼트 뷰)
export interface RunnerJob {
  bookingId: string;
  when: string;
  dogName: string;
  km: number;
  payout: number;
  status: 'confirmed' | 'in_progress' | 'completed';
  rawStatus: string;
  routeId: string | null; // 완료 카드 미니 패치 매핑용
}

export async function fetchRunnerJobs(): Promise<RunnerJob[]> {
  const rate = await myCommissionRate();
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, base_fare, distance_fare, addon_fare, status, route_id, dogs(name)')
    .eq('runner_id', user.user.id)
    .in('status', ['confirmed', 'runner_enroute', 'picked_up', 'active', 'completed'])
    .order('scheduled_at', { ascending: false })
    .limit(20);
  if (error) throw error;

  // 완료 건은 견적이 아니라 원장 실 net (감사 ⑤ 수익 표시 잔여 해소).
  // 2-step 쿼리 — PostgREST 임베드 FK 모호성 회피 관례. 원장 행 없는 과거 건은 견적 폴백.
  const doneIds = (data ?? []).filter((r: any) => r.status === 'completed').map((r: any) => r.id);
  const netByBooking: Record<string, number> = {};
  if (doneIds.length > 0) {
    const { data: led, error: ledErr } = await supabase
      .from('ledger_items')
      .select('booking_id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee')
      .in('booking_id', doneIds);
    if (ledErr) console.warn('[jobs] ledger:', ledErr.message);
    (led ?? []).forEach((l: any) => {
      netByBooking[l.booking_id] =
        l.base + l.distance_pay + l.addon_pay + l.tip + (l.remaining_guarantee ?? 0) - l.platform_fee;
    });
  }

  return (data ?? []).map((r: any) => {
    const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
    return {
      bookingId: r.id,
      when: `${dateLabel} ${timeLabel}`,
      dogName: r.dogs?.name ?? '반려견',
      km: Number(r.km),
      // 완료 = 원장 실수령, 그 외 = 실수수료 견적 (일괄 33%, 0059)
      payout: netByBooking[r.id] ?? Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)),
      status: r.status === 'completed' ? 'completed' : r.status === 'confirmed' ? 'confirmed' : 'in_progress',
      rawStatus: r.status,
      routeId: r.route_id ?? null,
    };
  });
}

// ---------- 코스 패치 (2026-07-28 확정) — 파생 데이터, 마이그레이션 0 ----------
// 사다리: ×1 획득 → ×5 실버 → ×10 골드 → ×25 코스 마스터 (드랍 5/10 리듬과 동기).
// 골드/마스터 도달 시 포인트 보너스는 서버(settle_run_tx, 0025)가 지급 — 클라는 표시만.
export type PatchGrade = 'basic' | 'silver' | 'gold' | 'master';
export const patchGrade = (n: number): PatchGrade =>
  n >= 25 ? 'master' : n >= 10 ? 'gold' : n >= 5 ? 'silver' : 'basic';
export interface CoursePatch { routeId: string; name: string; km: number; count: number; grade: PatchGrade; firstAt: string | null }

// 내(보호자든 러너든 당사자) 완료 러닝을 코스별로 집계 — locked는 아직 못 달린 활성 코스
export async function fetchCoursePatches(): Promise<{ earned: CoursePatch[]; locked: { routeId: string; name: string; km: number }[] }> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return { earned: [], locked: [] };
  const uid = user.user.id;
  // runs!inner + end_reason='completed' (0028 ②): status='completed'는 조기 종료 정산도
  // 포함 — 패치는 '완주'만 센다. bookings↔runs는 unique FK 단일 경로라 임베드 모호성 없음.
  const [bkRes, rtRes] = await Promise.all([
    supabase.from('bookings').select('route_id, scheduled_at, runs!inner(end_reason)')
      .eq('status', 'completed').eq('runs.end_reason', 'completed')
      .not('route_id', 'is', null)
      .or(`owner_id.eq.${uid},runner_id.eq.${uid}`)
      .order('scheduled_at').limit(1000),
    // 0082 이후 상태 필터를 여기 두지 않는다. candidate는 active=false인데, 파일럿은 바로 그
    // candidate를 예약해서 활성화 런을 만든다 — active만 읽으면 그 완주로 얻은 패치가 아래
    // forEach에 영영 도달하지 못하고 조용히 사라진다(그리고 fetchRewardBeacon이 '다음 목표'를
    // 거짓으로 그린다). 은퇴/정지 코스도 마찬가지: 달린 기록은 코스가 은퇴했다고 없던 일이
    // 되지 않는다(기록 카드 원칙). 그래서 전 상태를 읽고 아래에서 갈라 쓴다 — earned는 상태
    // 무관, locked는 지금 갈 수 있는 코스(active)만. routes는 수십 행이고 0082에서 공개 읽기가
    // 열렸으므로 전량 조회가 싸다.
    supabase.from('routes').select('id, name, km, status'),
  ]);
  if (bkRes.error) throw bkRes.error;
  // routes 실패도 실패로 — 조용히 넘기면 earned/locked가 통째로 빈 배열이 되고,
  // 이 함수를 읽는 홈 비컨(fetchRewardBeacon)이 '다음 목표 없음'을 거짓으로 그린다.
  if (rtRes.error) throw rtRes.error;
  const counts: Record<string, { n: number; first: string }> = {};
  (bkRes.data ?? []).forEach((b: any) => {
    const c = (counts[b.route_id] ??= { n: 0, first: b.scheduled_at });
    c.n += 1;
  });
  const earned: CoursePatch[] = [];
  const locked: { routeId: string; name: string; km: number }[] = [];
  (rtRes.data ?? []).forEach((r: any) => {
    const c = counts[r.id];
    if (!c && r.status !== 'active') return; // 못 달린 candidate/정지/은퇴는 '잠금'으로도 걸지 않는다
    if (c) {
      earned.push({
        routeId: r.id, name: r.name, km: Number(r.km), count: c.n,
        grade: patchGrade(c.n), firstAt: kstParts(c.first).dateLabel,
      });
    } else locked.push({ routeId: r.id, name: r.name, km: Number(r.km) });
  });
  earned.sort((a, b) => b.count - a.count);
  return { earned, locked };
}

// 러너 공개 '달린 코스' (0023) — SECURITY DEFINER 집계 (방문자는 타인 bookings를 못 읽는다).
// 코스명·횟수만 노출. 프로필 스토어프런트 신뢰 신호: 장비 인증 옆의 경험 증명.
export async function fetchRunnerCourseHistory(profileId: string): Promise<CoursePatch[]> {
  const { data, error } = await supabase.rpc('runner_course_history', { p_runner: profileId });
  if (error) throw error;
  return (data ?? []).map((x: any) => ({
    routeId: x.route_id, name: x.route_name, km: Number(x.km),
    count: Number(x.runs), grade: patchGrade(Number(x.runs)), firstAt: null,
  }));
}

// 패치 획득/승급 팝 — 이 예약이 그 코스의 '최신 완주'이고 누적이 임계(1/5/10/25)에 방금 도달했을 때만.
// 앱 세션당 예약별 1회 (인메모리 — 과거 리포트 재방문 시 반복 팝 방지)
const _patchPopSeen = new Set<string>();
export async function fetchPatchPop(bookingId: string, routeId: string): Promise<CoursePatch | null> {
  if (_patchPopSeen.has(bookingId)) return null;
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const uid = user.user.id;
  const { data, error } = await supabase.from('bookings').select('id, runs!inner(end_reason)')
    .eq('route_id', routeId).eq('status', 'completed')
    .eq('runs.end_reason', 'completed') // 패치 팝도 '완주'만 (0028 ②)
    .or(`owner_id.eq.${uid},runner_id.eq.${uid}`)
    .order('scheduled_at', { ascending: false }).limit(30);
  if (error || !data || data.length === 0) return null;
  if (data[0].id !== bookingId) return null; // 최신 완주가 아니면 과거 리포트 — 팝 없음
  const n = data.length;
  if (![1, 5, 10, 25].includes(n)) return null;
  const { data: rt } = await supabase.from('routes').select('name, km').eq('id', routeId).maybeSingle();
  _patchPopSeen.add(bookingId);
  return { routeId, name: rt?.name ?? '코스', km: Number(rt?.km ?? 0), count: n, grade: patchGrade(n), firstAt: null };
}

// ② 실 스탬프 — 골드 실은 '찍히는 순간'이 있어야 도장이다: 영수증 첫 진입 1회만 애니, 재진입은 정지 상태.
// 앱 세션당 예약별 1회 (인메모리 — _patchPopSeen과 같은 문법. 서버 왕복 없음: 순수 표현 판정)
const _sealStampSeen = new Set<string>();
export function sealStampFresh(bookingId: string): boolean {
  if (_sealStampSeen.has(bookingId)) return false;
  _sealStampSeen.add(bookingId);
  return true;
}

// ═══════════ 리워드 ② 여권 도장 (2026-08-05) — 전부 파생, 마이그레이션 0 ═══════════
// 계약: 도장은 FOREVER를 지향한다 — 한번 참이 되면 영원히 참인 값만 도장이 된다.
//   · 잔액 마일스톤은 제외 (shop_spend가 깎으면 도장이 사라진다 = 도장이 아니다)
//   · '이번 주 연속'도 제외. 대신 역대 최장 연속 주를 쓴다 (최대값은 쉬어도 줄지 않는다)
// [감소 벡터 2종 — 알고 받아들인 것. 다음 편집자는 재감사하지 말 것]
//   ① 첫 자랑: feed_posts에 "feed delete own" 정책이 있다. 유일한 자랑 글을 지우면 count 1→0,
//      도장이 풀린다. 막으려면 획득 시점을 저장할 테이블 = 마이그레이션 (v1 범위 밖).
//   ② 코스 2/3: fetchCoursePatches는 active 코스만 센다. 운영이 코스를 비활성화하면
//      earned.length가 줄어 도장이 풀릴 수 있다 (랩이 '전 코스 개척'을 뺀 것과 같은 이유).
//   이 둘 때문에 화면 카피는 '지워지지 않아요'라고 단정하지 않는다 —
//   report.tsx 세리머니는 '기록이 남아 있는 한 도장은 그대로예요'로 말한다.
// 12칸의 인쇄 순서는 고정이다 — 여권의 한 면은 도장을 받았다고 재배치되지 않는다.
// 잉크 법(랩 확정): 바이올렛이 유일한 도장 잉크 · 코랄은 첫-family의 외곽링+도트로만 생존
//   (코랄은 절대 글자가 되지 않는다) · 골드는 영수증 몫 · 새 포일 0.
// 사다리는 색이 아니라 링 수로 오른다: 1링(첫 단) → 2링(마일스톤) → 3링(사다리 top).

export interface StampStats {
  runsDone: number;      // 완주 러닝 수 (bookings.status='completed' ∧ runs.end_reason='completed')
  courses: number;       // 개척한 코스 수 = fetchCoursePatches().earned.length
  clubAttended: number;  // 체크인한 '종료된' 클럽 세션 수
  maxWeekStreak: number; // 역대 최장 연속 주 (현재 연속이 아니다 — 기록은 decay하지 않는다)
  poopRuns: number;      // 응가 보너스가 붙은 '러닝' 수 (응가 횟수가 아니다 — 정산이 예약당 1행)
  shares: number;        // 내가 올린 피드 자랑 수
  reviews: number;       // 내가 쓴 후기 수
}

// KST 주 인덱스 — kstWeekStartMs(월요일 00:00)를 정수 주 번호로. 연속 주 = 인덱스가 1씩 이어지는 구간.
// (+KST_MS 로 되돌려 UTC 자정 정렬을 만든 뒤 주 길이로 나눈다 — 월요일끼리는 정확히 604800000ms 간격)
const kstWeekIndex = (t: number) => Math.round((kstWeekStartMs(t) + KST_MS) / 604_800_000);

// 역대 최장 연속 주. '현재 연속'이 아니라 최대값이라 유예 주(grace) 해킹이 필요 없다 —
// 쉬면 현재 연속은 끊기지만 기록은 남는다. 이것이 도장을 단조(monotonic)로 만드는 유일한 해석.
function maxWeekStreakOf(isoList: string[]): number {
  const weeks = [...new Set(isoList.map((iso) => kstWeekIndex(Date.parse(iso))).filter(Number.isFinite))]
    .sort((a, b) => a - b);
  let best = 0;
  let run = 0;
  for (let i = 0; i < weeks.length; i++) {
    run = i > 0 && weeks[i] === weeks[i - 1] + 1 ? run + 1 : 1;
    if (run > best) best = run;
  }
  return best;
}

// 도장 벽의 원천 수치. 전부 병렬, 하나라도 실패하면 throw —
// 로딩≠0 법: 호출부는 throw를 '아직 못 읽음'으로 다루고 벽에 0을 그리지 않는다.
export async function fetchStampStats(): Promise<StampStats> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('로그인이 필요해요');
  const uid = user.user.id;
  const mine = `owner_id.eq.${uid},runner_id.eq.${uid}`; // 보호자·러너 양역할 병합 (fetchCoursePatches와 동일 관례)

  const [runsRes, patches, clubRes, weekRes, poopRes, shareRes, reviewRes] = await Promise.all([
    // runs!inner + end_reason='completed' (0028 ②)가 정직 게이트다:
    // status='completed'만 세면 조기 종료 정산까지 '완주'로 계산돼 도장이 부풀어 오른다.
    // head:true 카운트 — 행 상한 없이 진짜 총수를 받는다.
    // [주의] 벽의 runsDone(여기, 정확한 카운트)과 팝의 runsDone(fetchStampPop, 1000행 창)은
    // 완주 1000회를 넘기면 갈라진다 — 임계가 25까지라 파일럿에선 무의미하다. 알고 두는 차이.
    supabase.from('bookings').select('id, runs!inner(end_reason)', { count: 'exact', head: true })
      .eq('status', 'completed').eq('runs.end_reason', 'completed').or(mine),
    fetchCoursePatches(), // 실패 시 스스로 throw — 여기서도 실패는 실패로 전파된다
    // ⚠ session_people의 RLS는 "people authed read" — 로그인한 누구에게나 열려 있다.
    // profile_id 필터는 성능 최적화가 아니라 정확성 요건이다: 빼면 남의 출석까지 세어 도장이 거짓이 된다.
    // 술어는 club_my_stats(0031)와 동일하고 p_club 스코프만 없다.
    supabase.from('session_people').select('id, club_sessions!inner(status)', { count: 'exact', head: true })
      .eq('profile_id', uid).eq('attendance', 'checked_in').eq('club_sessions.status', 'done'),
    // 연속 주 계산 원본 — 최근 1000건 창. 파일럿 규모에선 사실상 전량이고,
    // 넘어가면 '가장 오래된 주'가 잘린다 (최장 연속이 그 창 밖이면 과소 계상 — 부풀리지는 않는다).
    supabase.from('bookings').select('scheduled_at, runs!inner(end_reason)')
      .eq('status', 'completed').eq('runs.end_reason', 'completed').or(mine)
      .order('scheduled_at', { ascending: false }).limit(1000),
    // settle_run_tx는 응가 보너스를 예약당 정확히 1행(+30) 쓴다 → 이 수는 '러닝 수'다.
    // 카피는 반드시 '러닝 N회'라고 말해야 한다 ('응가 N번'은 거짓).
    supabase.from('miles_ledger').select('id', { count: 'exact', head: true })
      .eq('profile_id', uid).eq('reason', 'poop_bonus'),
    supabase.from('feed_posts').select('id', { count: 'exact', head: true }).eq('author_id', uid),
    // target_kind 필터 없음 — 의도적이다. '후기를 쓴다'가 마일스톤이고, 러너/보호자/반려견 중
    // 누구에 대한 후기든 그 행위는 같다. 그래서 라벨도 역할 중립('후기 1개')으로 쓴다.
    supabase.from('reviews').select('id', { count: 'exact', head: true }).eq('author_id', uid),
  ]);
  if (runsRes.error) throw runsRes.error;
  if (clubRes.error) throw clubRes.error;
  if (weekRes.error) throw weekRes.error;
  if (poopRes.error) throw poopRes.error;
  if (shareRes.error) throw shareRes.error;
  if (reviewRes.error) throw reviewRes.error;

  return {
    runsDone: runsRes.count ?? 0,
    courses: patches.earned.length,
    clubAttended: clubRes.count ?? 0,
    maxWeekStreak: maxWeekStreakOf((weekRes.data ?? []).map((b: any) => String(b.scheduled_at))),
    poopRuns: poopRes.count ?? 0,
    shares: shareRes.count ?? 0,
    reviews: reviewRes.count ?? 0,
  };
}

// 한 칸의 인쇄 사양. 화면(마이 도장면·컬렉션 부속서·런엔드 세리머니)은 전부 이 한 배열만 읽는다.
export interface StampInfo {
  key: string;
  earned: boolean;
  num: string;             // 도장 안 숫자 — Oswald (lineHeight 1.2배 명시 필수, BUG A)
  word: string;            // 도장 안 한글 ('완주'·'코스'·'클럽'·'연속'·'응가'·'자랑'·'후기')
  label: string;           // 도장 아래 이름 14pt ('첫 러닝')
  cond: string;            // 빈 칸의 획득 조건 14pt ('완주 5회')
  prog: string | null;     // 실진행 ('7 / 10 완주'). 임계 1이거나 이미 받았으면 null → 화면은 cond를 쓴다
  family: 'first' | 'ladder' | 'top';
  rings: 1 | 2 | 3;        // 사다리 깊이 = 링 수 (색이 아니라)
  coral: boolean;          // 첫-family만 코랄 외곽링 + 코랄 도트 (글자는 언제나 바이올렛)
  angle: number;           // 고정 기울기 — Math.random 금지. 기울기는 그 도장의 정체성이라 리렌더에도 같아야 한다
}

// 12칸 고정 인쇄 순서 (랩 Ⓐ① 정본). 임계: 완주 1/5/10/25 · 코스 2/3 · 클럽 1 · 연속 2주 · 응가 1/10 · 자랑 1 · 후기 1.
export function deriveStamps(s: StampStats): StampInfo[] {
  const cell = (
    key: string, num: string, word: string, label: string, cond: string,
    family: StampInfo['family'], rings: 1 | 2 | 3, angle: number,
    have: number, need: number, unit: string | null,
  ): StampInfo => ({
    key, num, word, label, cond, family, rings, angle,
    earned: have >= need,
    coral: family === 'first',
    // 진행 문구는 임계가 2 이상인 칸에서만 뜻이 있다 (1회짜리는 0/1을 그려봐야 조건문의 반복일 뿐)
    prog: have >= need || need < 2 || unit === null ? null : `${have} / ${need} ${unit}`,
  });
  return [
    cell('run1', '1', '완주', '첫 러닝', '완주 1회', 'first', 1, -11, s.runsDone, 1, null),
    cell('run5', '5', '완주', '5회 완주', '완주 5회', 'ladder', 2, 7, s.runsDone, 5, '완주'),
    cell('run10', '10', '완주', '10회 완주', '완주 10회', 'ladder', 2, -6, s.runsDone, 10, '완주'),
    cell('run25', '25', '완주', '25회 완주', '완주 25회', 'top', 3, 9, s.runsDone, 25, '완주'),
    cell('course2', '2', '코스', '코스 2개 개척', '코스 2개', 'ladder', 1, 6, s.courses, 2, '코스'),
    // 코스 3개가 천장이다: 시드 활성 코스가 4개라 '전 코스 개척'은 코스가 늘면 풀리는 도장 = 금지
    cell('course3', '3', '코스', '코스 3개 개척', '코스 3개', 'ladder', 2, -9, s.courses, 3, '코스'),
    cell('club1', '1', '클럽', '첫 클럽 출석', '클럽 출석 1회', 'first', 1, 10, s.clubAttended, 1, null),
    cell('streak2', '2', '연속', '연속 2주', '연속 2주', 'ladder', 1, -7, s.maxWeekStreak, 2, '주 연속'),
    cell('poop1', '1', '응가', '응가 도장', '응가 러닝 1회', 'ladder', 1, 5, s.poopRuns, 1, null),
    cell('poop10', '10', '응가', '응가 도장 ×10', '응가 러닝 10회', 'ladder', 2, -5, s.poopRuns, 10, '러닝'),
    cell('share1', '1', '자랑', '첫 자랑', '피드 자랑 1회', 'first', 1, 8, s.shares, 1, null),
    // 조건은 역할 중립 — reviews 카운트에 target_kind 필터가 없으므로 '러너 후기'는 거짓이 된다
    cell('review1', '1', '후기', '첫 후기', '후기 1개', 'first', 1, -8, s.reviews, 1, null),
  ];
}

// 이 러닝이 '방금 넘긴' 도장만 알린다 — 벽은 전부 보여주지만 세리머니는 새로 생긴 것만 말한다.
// 앱 세션당 예약별 1회 (_patchPopSeen과 같은 인메모리 문법 — 과거 리포트 재방문 시 반복 축하 금지).
// 두 게이트는 서로 독립이다: 각자 '실제로 내놓을 게 있을 때만' 소비하므로,
// 같은 effect에서 Promise.all로 함께 불러도 재방문 동작이 결정적이다 (둘 다 조용해진다).
const _stampPopSeen = new Set<string>();

// 절대 알리지 않는 것: 첫 클럽 출석 · 첫 자랑 · 첫 후기 · 연속 2주.
//   앞의 셋은 이 러닝이 아니라 다른 화면에서 벌어진 사건이고(런엔드가 주장하면 거짓말),
//   연속 주는 '이 러닝이 넘겼다'를 이 자리에서 싸고 정직하게 귀속시킬 수 없다.
//   그 침묵은 결함이 아니라 설계다 — 벽에는 어차피 다 찍혀 있다.
export async function fetchStampPop(bookingId: string): Promise<StampInfo[]> {
  if (_stampPopSeen.has(bookingId)) return [];
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const uid = user.user.id;

  // 내 완주 러닝 전체(최근 1000건) — fetchPatchPop의 '최신 완주' 가드와 같은 정신.
  const { data, error } = await supabase
    .from('bookings').select('id, route_id, runs!inner(end_reason)')
    .eq('status', 'completed').eq('runs.end_reason', 'completed')
    .or(`owner_id.eq.${uid},runner_id.eq.${uid}`)
    .order('scheduled_at', { ascending: false }).limit(1000);
  if (error || !data || data.length === 0) return [];
  // 이 예약이 최신 완주가 아니면 과거 리포트를 다시 연 것 — 세리머니 없음.
  // (조기 종료·미완주 예약은 애초에 이 목록에 없으므로 여기서 함께 걸러진다.)
  if (data[0].id !== bookingId) return [];

  const runsDone = data.length;
  const routeId: string | null = (data[0] as any).route_id ?? null;

  const [poopThis, poopAll, patches] = await Promise.all([
    // 이 러닝이 응가 보너스를 벌었나 (ref_id = 예약 id, 리워드 ①에서 검증된 관계)
    supabase.from('miles_ledger').select('id', { count: 'exact', head: true })
      .eq('ref_id', bookingId).eq('profile_id', uid).eq('reason', 'poop_bonus'),
    supabase.from('miles_ledger').select('id', { count: 'exact', head: true })
      .eq('profile_id', uid).eq('reason', 'poop_bonus'),
    // 코스 수는 벽과 같은 출처를 써야 한다 (활성 코스만 센다) — 실패하면 코스는 조용히 넘어간다
    routeId ? fetchCoursePatches().catch(() => null) : Promise.resolve(null),
  ]);

  const stats: StampStats = {
    runsDone,
    courses: patches ? patches.earned.length : 0,
    poopRuns: poopAll.count ?? 0,
    // 아래 셋은 이 함수가 절대 알리지 않는 항목이라 여기서 조회하지 않는다.
    // 이 값들은 함수 밖으로 나가지 않는다 (반환 배열엔 아래 keys에 든 칸만 실린다).
    clubAttended: 0, maxWeekStreak: 0, shares: 0, reviews: 0,
  };

  const keys: string[] = [];
  // 완주 사다리: 총수가 임계와 '정확히' 같을 때만 = 이 러닝이 그 칸을 넘긴 것
  if (runsDone === 1) keys.push('run1');
  else if (runsDone === 5) keys.push('run5');
  else if (runsDone === 10) keys.push('run10');
  else if (runsDone === 25) keys.push('run25');
  // 코스: 이 예약의 코스 누적이 1이면 이번이 그 코스의 첫 완주 → 코스 수가 방금 늘었다
  if (patches && routeId) {
    const mineRoute = patches.earned.find((c) => c.routeId === routeId);
    if (mineRoute && mineRoute.count === 1) {
      const n = patches.earned.length;
      if (n === 2) keys.push('course2');
      if (n === 3) keys.push('course3');
    }
  }
  // 응가: 이 러닝이 실제로 보너스를 벌었을 때만. 총수가 임계여도 이 러닝의 공이 아니면 침묵.
  // (조회 실패 시 count는 null → 0 → 침묵. 벽에는 그대로 찍혀 있으니 잃는 건 축하뿐이다.)
  if ((poopThis.count ?? 0) > 0) {
    const p = poopAll.count ?? 0;
    if (p === 1) keys.push('poop1');
    if (p === 10) keys.push('poop10');
  }
  if (keys.length === 0) return [];

  const out = deriveStamps(stats).filter((x) => keys.includes(x.key)); // 인쇄 순서 유지
  _stampPopSeen.add(bookingId); // 내놓을 게 있을 때만 소비 (fetchPatchPop과 같은 규칙)
  return out;
}

export const runnerEnroute = (id: string) => invokeTransition(id, 'enroute');

// 러너 도착 보고 — 서버가 arrived_at을 CAS로 찍고 보호자에게 '러너 도착' 알림을 정확히 1회 보낸다.
// 이미 찍혀 있으면 서버가 { unchanged: true }로 200을 준다 (재탭·재시도 = 멱등 성공).
// 호출부는 그 값을 그대로 받아 성공으로 처리해야 한다 — 재탭을 실패로 다루면 도착 후 인계가 잠긴다.
export async function runnerArrived(id: string): Promise<{ unchanged?: boolean }> {
  return invokeTransition(id, 'arrived');
}

// ---------- profile (identity layer) ----------
export interface MyProfile { id: string; name: string | null; handle: string | null; district: string | null; avatarUrl: string | null; email: string | null }

export async function fetchMyProfile(): Promise<MyProfile | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('profiles').select('name, handle, district, avatar_url').eq('id', user.user.id).maybeSingle();
  return {
    id: user.user.id,
    name: data?.name ?? user.user.email?.split('@')[0] ?? null,
    // [0074] null = 아직 아이디를 안 만들었다. 이름으로 대신 채우지 않는다 — 없는 값은 없는 값이다.
    handle: data?.handle ?? null,
    district: data?.district ?? null,
    avatarUrl: data?.avatar_url ?? null,
    email: user.user.email ?? null,
  };
}

export async function updateMyProfile(p: { name?: string; district?: string }): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('profiles').update(p).eq('id', user.user.id);
  if (error) throw error;
}

// ---------- 가용시간 (availability) ----------
export interface AvailRule { weekday: number; startMin: number; endMin: number }

export async function fetchRunnerAvailability(runnerId: string): Promise<AvailRule[]> {
  const { data, error } = await supabase
    .from('runner_availability_rules')
    .select('weekday, start_min, end_min')
    .eq('runner_id', runnerId)
    .order('weekday');
  if (error) throw error;
  return (data ?? []).map((r: any) => ({ weekday: r.weekday, startMin: r.start_min, endMin: r.end_min }));
}

export async function fetchMyAvailability(): Promise<AvailRule[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  return fetchRunnerAvailability(user.user.id);
}

// 전체 교체 저장 — 요일당 1구간 (다구간은 v2)
export async function saveMyAvailability(rules: AvailRule[]): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;
  const del = await supabase.from('runner_availability_rules').delete().eq('runner_id', uid);
  if (del.error) throw del.error;
  if (rules.length > 0) {
    const ins = await supabase.from('runner_availability_rules').insert(
      rules.map((r) => ({ runner_id: uid, weekday: r.weekday, start_min: r.startMin, end_min: r.endMin })),
    );
    if (ins.error) throw ins.error;
  }
}

// 슬롯 충돌 검사 — 서버 함수(규칙+확정예약+홀드+휴식버퍼)가 판정
export async function checkSlot(runnerId: string, startIso: string, endIso: string): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_slot_available', {
    p_runner: runnerId, p_start: startIso, p_end: endIso,
  });
  if (error) throw error;
  return !!data;
}

// Runner home status — real totals / online / tier (the truth behind the drop trail, the online
// toggle and the tier bar).
// tier is `string | null`: null means "not known yet" — signed out, or no `runners` row at all.
// It used to fall back to 'certified', which made the bib, kicker and footer read 인증 러너 for
// someone who had passed nothing. A data layer must not invent a capability the server never
// granted; the caller renders the unknown state (runner/home.tsx).
export interface MyRunnerStatus { totalRuns: number; totalKm: number; online: boolean; tier: string | null }

export async function fetchMyRunnerStatus(): Promise<MyRunnerStatus> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return { totalRuns: 0, totalKm: 0, online: false, tier: null };
  const { data } = await supabase.from('runners')
    .select('total_runs, total_km, online, tier').eq('profile_id', user.user.id).maybeSingle();
  return {
    totalRuns: data?.total_runs ?? 0,
    totalKm: Number(data?.total_km ?? 0),
    online: !!data?.online,
    tier: data?.tier ?? null,
  };
}

// 러너 인증 현황 — 인증 센터(/runner/apply)의 단일 진실. null = runners 행 없음(러너 미등록).
// Why this is separate from fetchMyRunnerStatus: that one returns a whole status object (totals,
// online) with tier possibly null, for a screen that still renders when there is no runners row.
// Here "no row" is itself the answer, so the whole record is null — 'not registered' must never
// be rendered as 'a certified runner with 0 runs'. (Both are honest now: the 'certified'
// fallback in fetchMyRunnerStatus was removed with the 0062 funnel slice.)
// 반환 필드는 전부 서버가 쓰는 실컬럼: tier(스토어프런트·오픈풀 게이트), total_runs/total_km(정산이 증가),
// commission_rate(settle-run이 그대로 읽는 정산 수수료율).
// funnel_step·identity_verified·education_modules_done은 의도적으로 뺐다 — 지금 값의 출처가
// ensureRunner()의 루프 테스트 부트스트랩(certified/true)이라, 그리면 없는 심사를 통과한 것처럼 보인다.
export interface MyRunnerCert { tier: string; totalRuns: number; totalKm: number; commissionRate: number }

export async function fetchMyRunnerCert(): Promise<MyRunnerCert | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data, error } = await supabase.from('runners')
    .select('tier, total_runs, total_km, commission_rate').eq('profile_id', user.user.id).maybeSingle();
  if (error) throw error;
  if (!data) return null;
  return {
    tier: String(data.tier),
    totalRuns: data.total_runs ?? 0,
    totalKm: Number(data.total_km ?? 0),
    commissionRate: Number(data.commission_rate ?? 0.33),
  };
}

// ---------- runner application funnel (0062) ----------
// The applicant's side of the certification funnel. `runner_applications` has no client policies
// at all, so these three RPCs are the only routes in or out; there is no `.from('runner_applications')`
// anywhere in this file by design.
//
// The projection is deliberately narrow (0062 §3.3): the ops fields (decided_by, decided_note) and
// the applicant's own contact details never cross it. reject_reason is the one decision field the
// applicant reads, and it is shown verbatim.
export interface RunnerApplication {
  id: string;
  // 'submitted' | 'under_review' | 'approved' | 'rejected' | 'withdrawn' — kept as a plain string
  // to match the server's text+check column (house convention since 0030; no client enum to drift).
  state: string;
  attemptNo: number;
  submittedAt: string;
  reviewedAt: string | null;
  decidedAt: string | null;
  rejectReason: string | null;
  isHardBar: boolean;
  // Server-computed: state in ('rejected','withdrawn') and not hard-barred and attempt_no < 3.
  // Never recompute this on the client — the cap and the bar are the server's to enforce.
  canReapply: boolean;
}

export interface RunnerApplicationForm {
  district: string;
  paceSecPerKm: number;
  maxDogWeightKg: number;
  serviceRadiusKm: number;
  specialties: string[];
  bio: string;
  runningExperience: string;
  dogExperience: string;
  // Either a KakaoTalk ID or a phone number is required (constraint runner_app_contact_present);
  // the form decides which, the server enforces that at least one arrived.
  contactKakao: string | null;
  contactPhone: string | null;
  contactWindow: string | null;
  consentTerms: boolean;
  consentPrivacy: boolean;
  consentIdCheck: boolean;
}

// Server tokens → behavior instructions, in the house style of fetchAvailableRunnersFor (:551).
// Every token here is a state of the caller's OWN application, so none of these strings leaks
// anything about another account. An unrecognized message is re-thrown as-is: swallowing it would
// paint a real failure (network, RLS, a check constraint) as a known, tidy funnel state.
function runnerApplyError(error: unknown): Error {
  const raw = String((error as any)?.message ?? error);
  if (raw.includes('not_signed_in')) return new Error('세션이 만료된 것 같아요 — 다시 로그인해주세요');
  if (raw.includes('already_applied')) return new Error('이미 접수된 지원서가 있어요');
  if (raw.includes('application_barred')) return new Error('이 계정으로는 다시 지원할 수 없어요 — 문의해주세요');
  if (raw.includes('already_certified')) return new Error('이미 인증된 러너예요');
  if (raw.includes('attempt_cap_reached')) return new Error('지원은 3번까지 할 수 있어요 — 문의해주세요');
  if (raw.includes('consent_required')) return new Error('필수 동의 항목을 확인해주세요');
  // One string for both, on purpose: runner_apply_withdraw raises a byte-identical `not_found` for
  // "no such id" and "not yours" (pin F6), and splitting the copy here would rebuild the
  // enumeration oracle the server just closed.
  if (raw.includes('not_found') || raw.includes('not_withdrawable')) {
    return new Error('지원서를 찾을 수 없거나 지금은 취소할 수 없어요');
  }
  return new Error(raw);
}

// Latest attempt only. null STRICTLY means "no application row ever" — it is never an error
// fallback. Anything that goes wrong throws, so the 인증 센터 can render 로딩 / 실패 / 미지원 as
// three different things (the loading ≠ empty law, one layer down).
export async function fetchMyRunnerApplication(): Promise<RunnerApplication | null> {
  const { data, error } = await supabase.rpc('runner_my_application', {});
  if (error) throw runnerApplyError(error);
  const row = (Array.isArray(data) ? data[0] : data) as any;
  if (!row) return null;
  return {
    id: String(row.id),
    state: String(row.state),
    attemptNo: row.attempt_no ?? 1,
    submittedAt: String(row.submitted_at),
    reviewedAt: row.reviewed_at ?? null,
    decidedAt: row.decided_at ?? null,
    rejectReason: row.reject_reason ?? null,
    isHardBar: !!row.is_hard_bar,
    canReapply: !!row.can_reapply,
  };
}

// Returns the new application id. The check constraints on runner_applications are the backstop for
// field ranges — the form validates the same ranges first, so a constraint violation reaching here
// is a bug, and it surfaces raw rather than being dressed up as a funnel state.
export async function submitRunnerApplication(form: RunnerApplicationForm): Promise<string> {
  const { data, error } = await supabase.rpc('runner_apply_submit', {
    p_district: form.district,
    p_pace: form.paceSecPerKm,
    p_max_weight: form.maxDogWeightKg,
    p_radius: form.serviceRadiusKm,
    p_specialties: form.specialties,
    p_bio: form.bio,
    p_running_exp: form.runningExperience,
    p_dog_exp: form.dogExperience,
    p_contact_kakao: form.contactKakao,
    p_contact_phone: form.contactPhone,
    p_contact_window: form.contactWindow,
    p_consent_terms: form.consentTerms,
    p_consent_privacy: form.consentPrivacy,
    p_consent_id_check: form.consentIdCheck,
  });
  if (error) throw runnerApplyError(error);
  return String(data);
}

// Only 'submitted' and 'under_review' can be withdrawn; the server decides that, not the screen.
export async function withdrawRunnerApplication(id: string): Promise<void> {
  const { error } = await supabase.rpc('runner_apply_withdraw', { p_application: id });
  if (error) throw runnerApplyError(error);
}

// 미트업 실컨텍스트 — 목업 김민준/초코 잔재 제거용 (양쪽 인계 화면의 진실)
export interface MeetupInfo {
  runnerName: string | null;
  dogName: string;
  dogBreed: string | null;
  dogWeightKg: number | null;
  dogMemo: string | null;
  dogPhotoUrl: string | null;
  routeName: string;
  // K7: 러너 지도가 코스 선을 그리려면 **어느 코스인지**를 알아야 한다. 트레이스 자체는 여기서
  // 싣지 않는다 — 목록/컨텍스트 셀렉트에 수백 점을 태우지 않는 것이 0082 K1의 규약이고,
  // 상세는 fetchRouteById(K2)가 라이프사이클 상태와 함께 돌려준다 (정지된 코스도 읽는다).
  routeId: string | null;
  km: number;
  paceLabel: string;
  when: string;
  // PRE-RUN pace suggestion for the 권장 caption (pace-state-ui-plan §3). RAW/un-defaulted —
  // null means unset. Distinct from `paceLabel`, which is the booking's MATCHING input
  // ("가볍게 8'+"); this is the per-dog quality floor. They never render on the same surface.
  // Once the run starts, `runs.pace_suggest_sec` (fetchRunMeta) supersedes this — the
  // snapshot is frozen so a mid-run pref edit cannot move the goalpost.
  paceSuggestSec: number | null;
}

export async function fetchMeetupInfo(bookingId: string): Promise<MeetupInfo> {
  const { data, error } = await supabase
    .from('bookings')
    // `preferences` rides the EXISTING dogs embed (no new join, so no PostgREST FK
    // ambiguity); the jsonb is unwrapped client-side rather than via `->>` in the select.
    .select('scheduled_at, km, pace_label, route_id, routes!bookings_route_id_fkey(name), dogs(name, breed, weight_kg, memo, photo_url, preferences), runners(profiles(name))')
    .eq('id', bookingId)
    .single();
  if (error) throw error;
  const d = data as any;
  const { dateLabel, timeLabel } = kstParts(d.scheduled_at);
  return {
    runnerName: d.runners?.profiles?.name ?? null,
    dogName: d.dogs?.name ?? '반려견',
    dogBreed: d.dogs?.breed ?? null,
    dogWeightKg: d.dogs?.weight_kg != null ? Number(d.dogs.weight_kg) : null,
    dogMemo: d.dogs?.memo ?? null,
    dogPhotoUrl: d.dogs?.photo_url ?? null,
    routeName: d.routes?.name ?? '코스 미지정',
    routeId: d.route_id ?? null,
    km: Number(d.km),
    paceLabel: d.pace_label ?? "보통 7'",
    when: `${dateLabel} ${timeLabel}`,
    paceSuggestSec: readPaceSuggest(d.dogs?.preferences?.paceSuggestSec),
  };
}

export async function setRunnerOnline(online: boolean): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('runners').update({ online }).eq('profile_id', user.user.id);
  if (error) throw error;
}

export async function fetchMyRunnerBio(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('runners').select('bio').eq('profile_id', user.user.id).maybeSingle();
  return data?.bio ?? null;
}

// 갤러리 사진 업로드 — avatars 버킷 {uid}/gallery/* + runners.photos 배열
export async function uploadRunnerPhoto(base64: string): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;
  const path = `${uid}/gallery/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  const { data: row } = await supabase.from('runners').select('photos').eq('profile_id', uid).single();
  const photos = [...(row?.photos ?? []), pub.publicUrl];
  const { error: e2 } = await supabase.from('runners').update({ photos }).eq('profile_id', uid);
  if (e2) throw e2;
  return photos;
}

export async function deleteRunnerPhoto(url: string): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;
  const { data: row } = await supabase.from('runners').select('photos').eq('profile_id', uid).single();
  const photos = (row?.photos ?? []).filter((p: string) => p !== url);
  const { error } = await supabase.from('runners').update({ photos }).eq('profile_id', uid);
  if (error) throw error;
  const storagePath = url.split('/avatars/')[1];
  if (storagePath) await supabase.storage.from('avatars').remove([storagePath]).then(() => {}, () => {});
  return photos;
}

// 러닝 사진 업로드 (러너, 종료 후) — runs.photos + [0064] PRIVATE media 버킷 {uid}/runs/{booking}/*
// runs.photos에는 경로가 들어간다 (레거시 행은 공개 URL 그대로) — 화면이 서명 URL로 푼다.
export async function uploadRunPhoto(bookingId: string, base64: string): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/runs/${bookingId}/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from(MEDIA_BUCKET)
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  // 원자 append (0018) — RMW 레이스 제거, 서버가 최신 photos 배열을 반환
  const { data: photos, error: e2 } = await supabase.rpc('append_run_photo', {
    p_booking: bookingId, p_url: path,
  });
  if (e2) throw e2;
  return (photos as string[] | null) ?? [];
}

// ---------- 러닝 이벤트 (응가 도장 등) — 러너 원탭 → 기록 + 보호자 즉시 알림 ----------
export type RunEventKind = 'poop' | 'snack' | 'water' | 'photo';

const EVENT_NOTI: Record<RunEventKind, (dog: string) => [string, string]> = {
  poop: (d) => ['응가 완료', `${d} 응가 성공! 러너가 응가 도장을 찍었어요`],
  snack: (d) => ['간식 타임', `${d}가 간식을 맛있게 먹었어요`],
  water: (d) => ['수분 보충', `${d}가 물을 마시고 있어요`],
  photo: (d) => ['새 사진 도착', `${d}의 러닝 사진이 추가됐어요 — 리포트에서 확인하세요`],
};

export async function addRunEvent(bookingId: string, kind: RunEventKind): Promise<void> {
  // 원자 append (0018) — 클라 read-modify-write는 연타 시 이벤트를 덮어써 응가 보너스가 증발했다
  const { error } = await supabase.rpc('append_run_event', {
    p_booking: bookingId, p_event: { kind, at: new Date().toISOString() },
  });
  if (error) throw error;
  const { data: bk } = await supabase.from('bookings').select('owner_id, dogs(name)').eq('id', bookingId).single();
  if (bk) {
    const [title, body] = EVENT_NOTI[kind]((bk as any).dogs?.name ?? '반려견');
    await supabase.from('notifications').insert({
      profile_id: (bk as any).owner_id, kind: 'booking', title, body, ref_id: bookingId,
    });
  }
}

// km 마일스톤 알림 — 실GPS 거리에서만 호출 (가짜 거리로 실알림 금지)
export async function notifyKmMilestone(bookingId: string, km: number): Promise<void> {
  const { data: bk } = await supabase.from('bookings').select('owner_id, dogs(name)').eq('id', bookingId).single();
  if (!bk) return;
  const dog = (bk as any).dogs?.name ?? '반려견';
  await supabase.from('notifications').insert({
    profile_id: (bk as any).owner_id, kind: 'booking',
    title: `${km}km 돌파`, body: `${dog}가 ${km}km를 달렸어요 — 실시간 지도에서 확인하세요`,
    ref_id: bookingId,
  });
}

// 러닝 트레이스 저장 (정산 후 러너가 기록 — runs runner update RLS)
export async function saveRunTrace(bookingId: string, trace: { lat: number; lng: number; t: number }[]): Promise<void> {
  const { error } = await supabase.from('runs').update({ trace }).eq('booking_id', bookingId);
  if (error) throw error;
}

// 1:1 트레이스 시드 — 재진입·앱 종료 후 재개 시 km이 0부터 다시 시작하지 않게 (클럽 hydrateFromServer와 동일 관용구).
// saveRunTrace는 배열 통째 덮어쓰기라(서버 append-merge 없음) 시드 없이 저장하면 기존 기록이 잘린다.
export async function fetchRunTrace(bookingId: string): Promise<{ lat: number; lng: number; t: number }[]> {
  const { data } = await supabase.from('runs').select('trace').eq('booking_id', bookingId).maybeSingle();
  return ((data as any)?.trace ?? []) as { lat: number; lng: number; t: number }[];
}

// 이 러닝의 개인 기록 순위 — 내 완료 러닝 안에서 (RLS상 타인 비교는 서버 집계 함수로, 추후 리더보드)
export interface RunStandings { nth: number; total: number; kmRank: number; paceRank: number | null }

export async function fetchRunStandings(bookingId: string): Promise<RunStandings | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase
    .from('bookings')
    .select('id, scheduled_at, runs(actual_km, avg_pace_sec_per_km)')
    .eq('owner_id', user.user.id).eq('status', 'completed')
    .order('scheduled_at');
  const rows = (data ?? [])
    .map((b: any) => {
      const r = Array.isArray(b.runs) ? b.runs[0] : b.runs;
      return r ? { id: b.id, km: Number(r.actual_km ?? 0), pace: r.avg_pace_sec_per_km as number | null } : null;
    })
    .filter(Boolean) as { id: string; km: number; pace: number | null }[];
  const idx = rows.findIndex((r) => r.id === bookingId);
  if (idx < 0) return null;
  const me = rows[idx];
  const kmRank = rows.filter((r) => r.km > me.km).length + 1;
  const paceRank = me.pace != null
    ? rows.filter((r) => r.pace != null && r.pace < me.pace!).length + 1
    : null;
  return { nth: idx + 1, total: rows.length, kmRank, paceRank };
}

// 러너 자기소개 (스토어프런트) — runners.bio
export async function updateRunnerBio(bio: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('runners').update({ bio }).eq('profile_id', user.user.id);
  if (error) throw error;
}

// ---------- 러너 공개 프로필 (스토어프런트) ----------
export interface RunnerPublicProfile {
  profileId: string;
  name: string;
  district: string;
  avatarUrl: string | null;
  tier: string;
  bio: string | null;
  specialties: string[];
  totalRuns: number;
  totalKm: number;
  paceLabel: string;
  paceSec: number; // 실측 s/km (없으면 420 폴백) — 라벨 역파싱은 최대 59초 손실이라 원값을 준다
  respondRate: number | null;
  trainerCertified: boolean;
  online: boolean;
  photos: string[];
  availability: { weekday: number; startMin: number; endMin: number }[];
  reviews: { rating: number | null; note: string | null; tags: string[]; when: string }[];
  avgRating: number | null;
}

export async function fetchRunnerProfile(profileId: string): Promise<RunnerPublicProfile> {
  const { data: r, error } = await supabase
    .from('runners')
    .select('profile_id, tier, bio, specialties, photos, avg_pace_sec_per_km, total_runs, total_km, respond_rate_pct, trainer_certified, online, profiles(name, district, avatar_url)')
    .eq('profile_id', profileId)
    .single();
  if (error) throw error;
  const rr = r as any;
  // 가용시간·리뷰는 실패해도 프로필은 뜬다
  const [availRes, revRes] = await Promise.all([
    supabase.from('runner_availability_rules').select('weekday, start_min, end_min').eq('runner_id', profileId).then((x) => x, () => ({ data: null } as any)),
    supabase.from('reviews').select('rating, note, tags, created_at').eq('target_id', profileId).eq('target_kind', 'runner').eq('visibility', 'public').order('created_at', { ascending: false }).limit(5).then((x) => x, () => ({ data: null } as any)),
  ]);
  const pace = rr.avg_pace_sec_per_km ?? 420;
  const reviews = (revRes.data ?? []).map((v: any) => {
    const { dateLabel } = kstParts(v.created_at);
    return { rating: v.rating, note: v.note, tags: v.tags ?? [], when: dateLabel };
  });
  const rated = reviews.filter((v: any) => v.rating != null);
  return {
    profileId: rr.profile_id,
    name: rr.profiles?.name ?? '러너',
    district: rr.profiles?.district ?? '',
    avatarUrl: rr.profiles?.avatar_url ?? null,
    tier: rr.tier === 'certified' ? '인증 러너' : rr.tier === 'veteran' ? '베테랑' : rr.tier === 'master' ? '마스터' : '지원자',
    bio: rr.bio ?? null,
    specialties: rr.specialties ?? [],
    totalRuns: rr.total_runs ?? 0,
    totalKm: Number(rr.total_km ?? 0),
    paceLabel: `${Math.floor(pace / 60)}'${String(pace % 60).padStart(2, '0')}"`,
    paceSec: pace,
    respondRate: rr.respond_rate_pct,
    trainerCertified: !!rr.trainer_certified,
    online: !!rr.online,
    photos: rr.photos ?? [],
    availability: (availRes.data ?? []).map((a: any) => ({ weekday: a.weekday, startMin: a.start_min, endMin: a.end_min })),
    reviews,
    avgRating: rated.length > 0 ? Math.round(rated.reduce((s: number, v: any) => s + v.rating, 0) / rated.length * 10) / 10 : null,
  };
}

// ---------- 러너 장비 (loadout, 0019) — 슬롯제 · 사진이 곧 인증 ----------
// kind당 1슬롯 (DB unique). verified는 photo_url 존재와 동치 — DB 체크 제약이 강제.
// 매칭 기여는 인증 슬롯당 +1, 최대 +2 (핵심 점수 불변 — 장비는 신뢰 신호이지 승부축이 아니다).
export type GearKind = 'leash' | 'apparel' | 'water' | 'treats' | 'bodycam';
export interface GearItem {
  id: string;
  runnerId: string;
  kind: GearKind;
  label: string;
  photoUrl: string | null;
  verified: boolean;
}
export const GEAR_KINDS: GearKind[] = ['leash', 'apparel', 'water', 'treats', 'bodycam'];
// icon = lucide name (emoji glyphs retired 2026-08-11 — "no emojis. no cheap.")
export const GEAR_META: Record<GearKind, { icon: string; name: string; hint: string }> = {
  leash: { icon: 'Cable', name: '리드줄', hint: '러닝 전용 리드줄' },
  apparel: { icon: 'Shirt', name: '러닝 장비', hint: '러닝복 · 러닝화' },
  water: { icon: 'Droplet', name: '급수', hint: '아이용 물병 · 급수기' },
  treats: { icon: 'Bone', name: '간식', hint: '보상용 간식 파우치' },
  bodycam: { icon: 'Video', name: '바디캠', hint: '러닝 중 영상 기록' },
};

const mapGear = (g: any): GearItem => ({
  id: g.id, runnerId: g.runner_id, kind: g.kind, label: g.label,
  photoUrl: g.photo_url ?? null, verified: !!g.verified_at,
});

export async function fetchGear(runnerId: string): Promise<GearItem[]> {
  const { data, error } = await supabase.from('runner_gear').select('*').eq('runner_id', runnerId);
  if (error) throw error;
  return (data ?? []).map(mapGear);
}

// 매칭 카드용 배치 조회 — 러너별 그룹핑 (N+1 금지)
export async function fetchGearFor(runnerIds: string[]): Promise<Record<string, GearItem[]>> {
  if (runnerIds.length === 0) return {};
  const { data, error } = await supabase.from('runner_gear').select('*').in('runner_id', runnerIds);
  if (error) throw error;
  const out: Record<string, GearItem[]> = {};
  (data ?? []).forEach((g: any) => { (out[g.runner_id] ??= []).push(mapGear(g)); });
  return out;
}

// 슬롯 등록/사진 교체 — 사진이 있어야만 verified_at (없으면 미인증 슬롯)
export async function upsertGear(kind: GearKind, base64?: string): Promise<GearItem> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;
  let photoUrl: string | null = null;
  if (base64) {
    const path = `${uid}/gear/${kind}-${Date.now()}.jpg`; // 타임스탬프 — 교체 시 CDN 캐시 회피
    const { error } = await supabase.storage.from('avatars')
      .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
    if (error) throw error;
    const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
    photoUrl = pub.publicUrl;
  }
  const { data, error } = await supabase.from('runner_gear').upsert({
    runner_id: uid, kind, label: GEAR_META[kind].name,
    photo_url: photoUrl, verified_at: photoUrl ? new Date().toISOString() : null,
  }, { onConflict: 'runner_id,kind' }).select('*').single();
  if (error) throw error;
  return mapGear(data);
}

export async function deleteGear(kind: GearKind): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('runner_gear').delete()
    .eq('runner_id', user.user.id).eq('kind', kind);
  if (error) throw error;
}

// base64 → bytes (Hermes atob 유무와 무관하게 동작)
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64ToBytes(b64: string): Uint8Array {
  const clean = b64.replace(/[^A-Za-z0-9+/]/g, '');
  const len = Math.floor(clean.length * 3 / 4);
  const out = new Uint8Array(len);
  let o = 0;
  for (let i = 0; i + 3 < clean.length + 1; i += 4) {
    const n = (B64.indexOf(clean[i]) << 18) | (B64.indexOf(clean[i + 1]) << 12)
      | ((B64.indexOf(clean[i + 2]) & 63) << 6) | (B64.indexOf(clean[i + 3]) & 63);
    if (o < len) out[o++] = (n >> 16) & 255;
    if (o < len && clean[i + 2] !== undefined) out[o++] = (n >> 8) & 255;
    if (o < len && clean[i + 3] !== undefined) out[o++] = n & 255;
  }
  return out;
}

// 사진 업로드 → 공개 URL → profiles.avatar_url 저장. 캐시 무효화용 ?v= 부착.
export async function uploadAvatar(base64: string): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/avatar.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg', upsert: true });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  const url = `${pub.publicUrl}?v=${Date.now()}`;
  const { error: e2 } = await supabase.from('profiles').update({ avatar_url: url }).eq('id', user.user.id);
  if (e2) throw e2;
  return url;
}

// ---------- 체력 리포트 (fitness hub) ----------
export interface FitnessWeek { label: string; km: number }
export interface FitnessRecent { bookingId: string; when: string; km: number; durationSec: number }
export interface Fitness {
  dogId: string | null;
  dogName: string;
  dogPhotoUrl: string | null;
  goalKm: number;
  fitnessAge: number | null;
  ageYears: number | null; // 생일 기준 실나이 (생일 없거나 비정상이면 null — 목업 나이 상수 금지)
  weekKm: number;       // 최근 7일
  weekRuns: number;
  avgPaceSec: number | null;
  streakDays: number;   // 러닝 있는 연속 일수 (오늘 또는 어제부터 역산)
  runDays: boolean[];   // KST 월~일 — 이번 주 러닝 있는 요일 (홈 히어로 요일 스탬프)
  // 체력 나이 미측정 사유 — 정직한 레시피 카피용 ('나이 그대로'를 측정값처럼 보여주지 않는다)
  fitnessGate: null | { reason: 'birth' } | { reason: 'runs'; left: number };
  weeks: FitnessWeek[]; // 최근 8주 (과거→현재)
  recent: FitnessRecent[];
}

export async function fetchFitness(): Promise<Fitness> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const [dogRes, runRes] = await Promise.all([
    // [Sean 2026-08-11] `.limit(1)` 무순서 = 앱과 다른 개를 골랐다. fetchMyDogs는 created_at 오름차순이고
    // 앱 전체의 '내 아이'는 그 첫 행(fetchMyDog)이다. 여기만 정렬 없이 한 행을 집었으므로, 다견 가구에서
    // 홈은 A를 말하고 체력 카드는 B를 계산했다. 실제 증상: 초코에 생일이 있는데도 '체력 나이 측정 전' —
    // 생일 없는 둘째(dd)가 뽑혀 fitnessGate='birth'로 떨어졌다. 정렬을 fetchMyDogs와 일치시켜 봉함한다.
    // (다견 가구의 '어느 아이를 볼지' 선택 자체는 별개 기능 — 여기서는 두 리졸버의 불일치만 없앤다.)
    supabase.from('dogs').select('id, name, weekly_goal_km, fitness_age, birth_date, photo_url')
      .eq('owner_id', user.user.id).order('created_at', { ascending: true }).limit(1),
    supabase.from('bookings')
      .select('id, scheduled_at, runs(actual_km, duration_sec)')
      .eq('owner_id', user.user.id).eq('status', 'completed')
      .order('scheduled_at', { ascending: false }).limit(120),
  ]);
  // 조회 실패를 성공 모양(0km·0회·스트릭 0)으로 위장하지 않는다 — 로딩 ≠ 실패 ≠ 진짜 0.
  // 호출부는 .catch로 실패 상태를 따로 그린다 (빈 주차와 구분).
  if (dogRes.error) throw dogRes.error;
  if (runRes.error) throw runRes.error;
  const d = dogRes.data?.[0];
  const rows = (runRes.data ?? [])
    .map((b: any) => {
      const r = Array.isArray(b.runs) ? b.runs[0] : b.runs;
      return r ? { bookingId: b.id, at: new Date(b.scheduled_at), km: Number(r.actual_km ?? 0), dur: r.duration_sec ?? 0 } : null;
    })
    .filter(Boolean) as { bookingId: string; at: Date; km: number; dur: number }[];

  const now = Date.now();
  const weekStart = kstWeekStartMs(now); // KST 월요일 — 리더보드·러너 주간과 동일 창
  const thisWeek = rows.filter((r) => r.at.getTime() >= weekStart);
  const weekKm = Math.round(thisWeek.reduce((s, r) => s + r.km, 0) * 10) / 10;
  const totKm = thisWeek.reduce((s, r) => s + r.km, 0);
  const totSec = thisWeek.reduce((s, r) => s + r.dur, 0);
  const avgPaceSec = totKm > 0.05 ? Math.round(totSec / totKm) : null;

  // 8주 버킷
  const weeks: FitnessWeek[] = [];
  for (let w = 7; w >= 0; w--) {
    const start = weekStart - w * 7 * 86400_000;
    const end = start + 7 * 86400_000;
    const km = rows.filter((r) => r.at.getTime() >= start && r.at.getTime() < end).reduce((s, r) => s + r.km, 0);
    weeks.push({ label: w === 0 ? '이번 주' : `${w}주 전`, km: Math.round(km * 10) / 10 });
  }

  // 스트릭: 러닝이 있는 날짜의 연속성 (오늘 비어도 어제부터 이어지면 유지)
  const days = new Set(rows.map((r) => Math.floor((r.at.getTime() + 9 * 3_600_000) / 86400_000)));
  const today = Math.floor((now + 9 * 3_600_000) / 86400_000);
  let streakDays = 0;
  let cursor = days.has(today) ? today : today - 1;
  while (days.has(cursor)) { streakDays++; cursor--; }

  const recent = rows.slice(0, 10).map((r) => {
    const { dateLabel, timeLabel } = kstParts(r.at.toISOString());
    return { bookingId: r.bookingId, when: `${dateLabel} ${timeLabel}`, km: r.km, durationSec: r.dur };
  });

  // 체력 나이 v1 (베타 휴리스틱) — 실제 나이 − 활동 보정(최근 4주 주간 평균/목표 비율 + 스트릭).
  // 수의 검증 산식으로 교체 예정. 측정 조건 2가지 (없으면 null + gate 사유):
  //   ① 생일 등록 (없으면 나이 자체를 모른다)
  //   ② 최근 28일 완주 ≥2회 — 0회면 계산값 = 등록 나이 그대로라 '측정'이 아니다 (정직 게이트, 2026-07-28)
  let fitnessAge: number | null = null;
  let fitnessGate: Fitness['fitnessGate'] = null;
  const recent28 = rows.filter((r) => r.at.getTime() >= now - 28 * 86400_000);
  // 실나이 — 생일이 있고 정상 범위(0~25살)일 때만. 없으면 null (홈 ▼칩은 이 값만 쓴다).
  const rawAgeYears = d?.birth_date ? (now - new Date(d.birth_date).getTime()) / (365.25 * 86400_000) : null;
  const ageYears = rawAgeYears != null && rawAgeYears > 0 && rawAgeYears <= 25 ? Math.round(rawAgeYears * 10) / 10 : null;
  if (!d?.birth_date) {
    fitnessGate = { reason: 'birth' };
  } else if (recent28.length < 2) {
    fitnessGate = { reason: 'runs', left: 2 - recent28.length };
  } else if (rawAgeYears != null && rawAgeYears > 0 && rawAgeYears <= 25) { // 미래/비정상 생일은 측정 불가
    const last28Km = recent28.reduce((s, r) => s + r.km, 0);
    const goal = Number(d.weekly_goal_km ?? 15);
    const ratio = goal > 0 ? Math.min(last28Km / 4 / goal, 1.5) : 0;
    const calc = Math.max(0.5, Math.round((rawAgeYears - 1.8 * ratio - 0.05 * Math.min(streakDays, 14)) * 10) / 10);
    fitnessAge = calc;
    if (d.fitness_age == null || Math.abs(Number(d.fitness_age) - calc) >= 0.1) {
      supabase.from('dogs').update({ fitness_age: calc }).eq('id', d.id).then(() => {}, () => {});
    }
  } else {
    fitnessGate = { reason: 'birth' }; // 비정상 생일도 생일 문제로 안내
  }

  // 요일 스탬프 — 이번 주(KST 월~일) 러닝이 있었던 요일
  const runDays = Array.from({ length: 7 }, () => false);
  thisWeek.forEach((r) => {
    const idx = Math.floor((r.at.getTime() - weekStart) / 86400_000);
    if (idx >= 0 && idx < 7) runDays[idx] = true;
  });

  return {
    dogId: d?.id ?? null,
    dogName: d?.name ?? '반려견',
    dogPhotoUrl: d?.photo_url ?? null,
    goalKm: Number(d?.weekly_goal_km ?? 15),
    fitnessAge,
    ageYears,
    weekKm, weekRuns: thisWeek.length, avgPaceSec, streakDays, weeks, recent, runDays, fitnessGate,
  };
}

export async function updateDogGoal(dogId: string, km: number): Promise<void> {
  const { error } = await supabase.from('dogs').update({ weekly_goal_km: km }).eq('id', dogId);
  if (error) throw error;
}

// ---------- 최근 순간 — 완료 러닝의 실사진만 (runs.photos, 러너가 담아온 순간) ----------
// 홈 생기 패스의 데이터원. 사진이 없으면 빈 배열 — 섹션 자체를 숨긴다 (스톡/가짜 금지).
export interface Moment { bookingId: string; url: string; when: string; km: number }

export async function fetchRecentMoments(limit = 12): Promise<Moment[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, runs(actual_km, photos)')
    .eq('owner_id', user.user.id).eq('status', 'completed')
    .order('scheduled_at', { ascending: false }).limit(30);
  if (error) throw error;
  const out: Moment[] = [];
  for (const b of (data ?? []) as any[]) {
    const r = Array.isArray(b.runs) ? b.runs[0] : b.runs; // unique FK — 어느 형태든 안전하게
    const photos: string[] = r?.photos ?? [];
    if (photos.length === 0) continue;
    const { dateLabel } = kstParts(b.scheduled_at);
    for (const url of photos) {
      out.push({ bookingId: b.id, url, when: dateLabel, km: Math.round(Number(r?.actual_km ?? 0) * 10) / 10 });
      if (out.length >= limit) return out;
    }
  }
  return out;
}

// ---------- runner identity & money (tabula rasa) ----------
export async function fetchMyName(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('profiles').select('name').eq('id', user.user.id).maybeSingle();
  return data?.name ?? user.user.email?.split('@')[0] ?? null;
}

export interface RunnerWeekStats { net: number; runs: number; km: number }

export async function fetchRunnerWeekStats(): Promise<RunnerWeekStats> {
  const since = new Date(kstWeekStartMs()).toISOString(); // KST 월요일 시작 — 리더보드와 동일 창
  const { data, error } = await supabase
    .from('ledger_items')
    .select('base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee, booking_id')
    .gte('created_at', since);
  if (error) throw error;
  const rows = data ?? [];
  const net = rows.reduce((s, l: any) => s + l.base + l.distance_pay + l.addon_pay + l.tip + (l.remaining_guarantee ?? 0) - l.platform_fee, 0);
  // runs = ledger rows that have an actual runs row. En-route cancel compensation (0080
  // record_enroute_cancel_comp) writes a ledger row for a run that never happened — its money
  // belongs in net, but counting it as a run would show "N runs" including a 0km phantom.
  let km = 0;
  let runCount = rows.length;
  const ids = rows.map((l: any) => l.booking_id);
  if (ids.length > 0) {
    const { data: runsD } = await supabase.from('runs').select('booking_id, actual_km').in('booking_id', ids);
    km = (runsD ?? []).reduce((s, r: any) => s + Number(r.actual_km ?? 0), 0);
    if (runsD) {
      const ran = new Set(runsD.map((r: any) => r.booking_id));
      runCount = rows.filter((l: any) => ran.has(l.booking_id)).length;
    }
  }
  return { net, runs: runCount, km: Math.round(km * 10) / 10 };
}

// 이번 달 실수령 — 주간(fetchRunnerWeekStats)과 동일한 net 식, 창만 KST 월 1일 00:00.
// 월 단위라 행수 유계(파일럿 ≤수십) — 2000행 캡 리스크는 누적(=my_ledger_total RPC)에만 해당;
// 월이 캡에 접근하면 invoker RPC로 승격 (핸드오프 §9 스케치).
export async function fetchLedgerMonth(): Promise<number> {
  const since = new Date(kstMonthStartMs()).toISOString();
  const { data, error } = await supabase
    .from('ledger_items')
    .select('base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee')
    .gte('created_at', since);
  if (error) throw error;
  const rows = data ?? [];
  return rows.reduce((s, l: any) => s + l.base + l.distance_pay + l.addon_pay + l.tip + (l.remaining_guarantee ?? 0) - l.platform_fee, 0);
}

// 정산 예정 누적 — 서버 집계 RPC (0027). 2000행 클라 합산 상한 은퇴 (초과 시 잔액이 조용히 줄던 거짓)
export async function fetchLedgerTotal(): Promise<number> {
  const { data, error } = await supabase.rpc('my_ledger_total');
  if (error) throw error;
  return Number(data ?? 0);
}

export interface LiveLedgerItem {
  id: string;
  when: string;
  dogName: string;
  km: number;
  base: number;
  distancePay: number;
  addonPay: number;
  tip: number;
  guarantee: number;
  fee: number;
  net: number;
}

export async function fetchLedger(): Promise<LiveLedgerItem[]> {
  const { data, error } = await supabase
    .from('ledger_items')
    .select('id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee, created_at, bookings(km, dogs(name))')
    .order('created_at', { ascending: false })
    .limit(30);
  if (error) throw error;
  return (data ?? []).map((l: any) => {
    const { dateLabel } = kstParts(l.created_at);
    const net = l.base + l.distance_pay + l.addon_pay + l.tip + l.remaining_guarantee - l.platform_fee;
    return {
      id: l.id,
      when: dateLabel,
      dogName: l.bookings?.dogs?.name ?? '반려견',
      km: Number(l.bookings?.km ?? 0),
      base: l.base,
      distancePay: l.distance_pay,
      addonPay: l.addon_pay,
      tip: l.tip,
      guarantee: l.remaining_guarantee,
      fee: l.platform_fee,
      net,
    };
  });
}

// ---------- chat (Realtime) ----------
export interface ChatMsg { id: number; mine: boolean; body: string; mediaUrl: string | null; when: string }

function mapMsg(m: any, uid?: string | null): ChatMsg {
  const d = new Date(m.created_at);
  const h = d.getHours();
  return {
    id: m.id,
    mine: m.sender_id === uid,
    body: m.body ?? '',
    mediaUrl: m.media_path ?? null,
    when: `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${String(d.getMinutes()).padStart(2, '0')}`,
  };
}

// 예약당 스레드 1개 — 없으면 생성 (동시 생성 레이스 시 재조회)
export async function ensureThread(bookingId: string): Promise<string> {
  const { data: existing } = await supabase.from('chat_threads').select('id').eq('booking_id', bookingId).maybeSingle();
  if (existing) return existing.id;
  const { data, error } = await supabase.from('chat_threads').insert({ booking_id: bookingId }).select('id').single();
  if (error) {
    const { data: again } = await supabase.from('chat_threads').select('id').eq('booking_id', bookingId).maybeSingle();
    if (again) return again.id;
    throw error;
  }
  return data.id;
}

export async function fetchMessages(threadId: string): Promise<ChatMsg[]> {
  const { data: user } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('chat_messages')
    .select('id, sender_id, body, media_path, created_at')
    .eq('thread_id', threadId)
    .order('created_at')
    .limit(100);
  if (error) throw error;
  return (data ?? []).map((m: any) => mapMsg(m, user.user?.id));
}

export async function sendChatMessage(threadId: string, body: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('chat_messages').insert({ thread_id: threadId, sender_id: user.user.id, body });
  if (error) throw error;
}

// 사진 메시지 — [0064] PRIVATE media 버킷 {uid}/chat/{thread}/* + kind 'photo'
// media_path엔 경로 저장 — 스토리지 정책이 chat_messages RLS(스레드 당사자)로 읽기를 위임한다.
export async function sendChatPhoto(threadId: string, base64: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/chat/${threadId}/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from(MEDIA_BUCKET)
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  const { error: e2 } = await supabase.from('chat_messages').insert({
    thread_id: threadId, sender_id: user.user.id, kind: 'photo', media_path: path, body: null,
  });
  if (e2) throw e2;
}

// 새 메시지 실시간 구독 — 해제 함수 반환
export function subscribeMessages(threadId: string, uid: string | null, onMsg: (m: ChatMsg) => void): () => void {
  // P0-1 후속(0108): chat 채널은 postgres_changes 전용이라 브로드캐스트 노출은 없었지만,
  // 프로젝트 전역 private_only 가 켜지는 순간 public 채널은 **전부** 죽는다. 서버 정책(0108)이
  // 이 토픽족을 인가하므로 private 으로 요청하고, 구독 전에 소켓을 무장시킨다.
  hookTokenRefresh();
  const ch = supabase
    .channel(`chat-${threadId}`, REALTIME_PRIVATE)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `thread_id=eq.${threadId}` },
      (payload) => onMsg(mapMsg(payload.new, uid)))
    ;
  // 무장 → 구독 순서. 그 사이 도착한 변경은 화면의 폴백 폴링이 잡는다(각 소비처가 폴링을 유지한다).
  let dropped = false;
  void armRealtime().then(() => { if (!dropped) ch.subscribe(); });
  return () => { dropped = true; supabase.removeChannel(ch); };
}

// 예약 상태 실시간 구독 — 폴링을 대체 (폴백 폴링은 화면이 유지)
// 레이더(찾는 중) 화면용 — 상태 + 수락 러너 이름만 가볍게
export async function fetchBookingBrief(id: string): Promise<{ status: string; runnerName: string | null }> {
  const { data, error } = await supabase.from('bookings')
    .select('status, runners(profiles(name))').eq('id', id).single();
  if (error) throw error;
  const d = data as any;
  return { status: d.status, runnerName: d.runners?.profiles?.name ?? null };
}

// 커뮤니티 '러너 후기' 탭 — 최근 공개 후기 + 러너 이름 (2-step, 임베드 FK명 의존 없음)
export interface PublicReview { runnerName: string; rating: number | null; note: string | null; tags: string[]; when: string }
export async function fetchRecentReviews(): Promise<PublicReview[]> {
  const { data, error } = await supabase.from('reviews')
    .select('rating, note, tags, created_at, target_id')
    .eq('target_kind', 'runner').eq('visibility', 'public')
    .order('created_at', { ascending: false }).limit(20);
  if (error) throw error;
  const rows = data ?? [];
  const ids = [...new Set(rows.map((r: any) => r.target_id))];
  const names: Record<string, string> = {};
  if (ids.length) {
    const { data: ps } = await supabase.from('profiles').select('id, name').in('id', ids);
    for (const pr of ps ?? []) names[pr.id] = pr.name;
  }
  return rows.map((r: any) => ({
    runnerName: names[r.target_id] ?? '러너',
    rating: r.rating, note: r.note, tags: r.tags ?? [],
    when: new Date(r.created_at).toLocaleDateString('ko-KR', { month: 'short', day: 'numeric' }),
  }));
}

export function subscribeBooking(bookingId: string, onChange: () => void): () => void {
  // P0-1 후속(0108): bk 채널은 postgres_changes 전용이라 브로드캐스트 노출은 없었지만,
  // 프로젝트 전역 private_only 가 켜지는 순간 public 채널은 **전부** 죽는다. 서버 정책(0108)이
  // 이 토픽족을 인가하므로 private 으로 요청하고, 구독 전에 소켓을 무장시킨다.
  hookTokenRefresh();
  const ch = supabase
    .channel(`bk-${bookingId}`, REALTIME_PRIVATE)
    .on('postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'bookings', filter: `id=eq.${bookingId}` },
      () => onChange())
    ;
  // 무장 → 구독 순서. 그 사이 도착한 변경은 화면의 폴백 폴링이 잡는다(각 소비처가 폴링을 유지한다).
  let dropped = false;
  void armRealtime().then(() => { if (!dropped) ch.subscribe(); });
  return () => { dropped = true; supabase.removeChannel(ch); };
}

// 채팅 컨텍스트 — 상대 이름 + 예약 라벨
export interface ChatContext { threadId: string; peerName: string; label: string }

export async function openChatForBooking(bookingId: string): Promise<ChatContext> {
  const { data: user } = await supabase.auth.getUser();
  const uid = user.user?.id;
  const { data: bk, error } = await supabase
    .from('bookings')
    .select('owner_id, runner_id, scheduled_at, km, dogs(name), routes!bookings_route_id_fkey(name)')
    .eq('id', bookingId)
    .single();
  if (error) throw error;
  const b = bk as any;
  const iAmOwner = b.owner_id === uid;
  const peerId = iAmOwner ? b.runner_id : b.owner_id;
  let peerName = iAmOwner ? '러너 (매칭 전)' : '보호자';
  if (peerId) {
    const { data: p } = await supabase.from('profiles').select('name').eq('id', peerId).maybeSingle();
    if (p?.name) peerName = iAmOwner ? `${p.name} 러너` : `${p.name} 보호자님`;
  }
  const { dateLabel, timeLabel } = kstParts(b.scheduled_at);
  const threadId = await ensureThread(bookingId);
  return {
    threadId,
    peerName,
    // ⚠ 코스 이름 뒤에 km 을 붙이지 않는다. routes.name 은 이미 자기 km 토큰을 갖고 있고 (0100 이
    // 참을 보증), 그 뒤에 booking.km 을 또 붙이면 "잠수교 강바람 3km 5km" 가 된다 — 실측 렌더.
    // 코스가 없을 때만 예약 km 이 유일한 길이 정보라 그때만 붙인다.
    label: `${dateLabel} ${timeLabel} · ${b.dogs?.name ?? '반려견'} · ${b.routes?.name ?? `코스 미지정 · ${b.km}km`}`,
  };
}

// ---------- 안심 센터 (SOS·긴급 연락처) ----------
export interface EmContact { id: string; name: string; phone: string }

export async function fetchEmergencyContacts(): Promise<EmContact[]> {
  const { data, error } = await supabase.from('emergency_contacts').select('id, name, phone').order('name');
  if (error) throw error;
  return data ?? [];
}

export async function addEmergencyContact(name: string, phone: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('emergency_contacts').insert({ profile_id: user.user.id, name, phone });
  if (error) throw error;
}

export async function deleteEmergencyContact(id: string): Promise<void> {
  const { error } = await supabase.from('emergency_contacts').delete().eq('id', id);
  if (error) throw error;
}

// SOS — 진행 중 예약의 상대방에게 즉시 알림 (푸시 도입 전엔 인앱 알림 + 실시간)
export async function sendSOS(role: 'owner' | 'runner'): Promise<string | null> {
  const bookingId = role === 'runner' ? await fetchCurrentRunnerJobId() : await fetchCurrentOwnerBookingId();
  if (!bookingId) return null;
  const { data: bk } = await supabase.from('bookings').select('owner_id, runner_id').eq('id', bookingId).single();
  if (!bk) return null;
  const target = role === 'owner' ? (bk as any).runner_id : (bk as any).owner_id;
  if (!target) return null;
  const { error } = await supabase.from('notifications').insert({
    profile_id: target, kind: 'booking',
    title: 'SOS', body: '상대방이 긴급 도움을 요청했어요 — 즉시 연락해주세요',
    ref_id: bookingId,
  });
  if (error) throw error;
  return bookingId;
}

// 러닝 중단 요청 — 보호자 → 담당 러너. **채팅은 푸시를 만들지 않는다**: notifications INSERT만
// 0024의 트리거(notifications → pg_net → Expo Push)를 탄다. 그래서 중단 요청은 채팅(기록·증거)과
// 알림(도달)을 **둘 다** 쓴다. 새 마이그레이션 없음 — 0009 'noti party insert' 정책이 이미
// 예약 당사자의 상대방 앞 booking 알림을 허용하고, sendSOS가 그 경로를 프로덕션에서 쓰고 있다.
// 제목은 상수다: push.ts의 라우팅이 완전 일치로 판정한다 (부분 일치는 '도착' 사고의 원인).
export const RUN_STOP_TITLE = '러닝 중단 요청';
// 반환값: 알림 행을 **넣었는지**. 도달했는지가 아니다 — 0024의 트리거는 푸시 오류를 의도적으로
// 삼키므로(0024:19,39) 앱은 배달을 알 방법이 없다. 호출부 카피는 이 구분을 지켜야 한다.
export async function notifyRunStop(bookingId: string, reason: string): Promise<boolean> {
  // [적대 리뷰 2026-08-11] 조회 에러를 버리고 있었다 — 조회가 실패해도 '보냈다'로 읽혔다.
  const { data: bk, error: lookupErr } = await supabase
    .from('bookings').select('owner_id, runner_id').eq('id', bookingId).single();
  if (lookupErr) throw lookupErr;
  const target = (bk as any)?.runner_id;
  if (!target) return false;   // 담당 러너가 없으면 보낼 상대가 없다 — 성공이 아니라 '못 보냄'이다
  const { error } = await supabase.from('notifications').insert({
    profile_id: target, kind: 'booking',
    title: RUN_STOP_TITLE, body: `보호자가 러닝 중단을 요청했어요 — 사유: ${reason}`,
    ref_id: bookingId,
  });
  if (error) throw error;
  return true;
}

// ---------- 리워드 (드랍·기어) ----------
export interface DropRow {
  id: string; kind: string; runCountAt: number;
  contents: { miles?: number; card?: string; gear?: string };
  pickChoice: string | null; openedAt: string | null; when: string;
}

export async function fetchDrops(): Promise<DropRow[]> {
  const { data, error } = await supabase
    .from('drops').select('id, kind, run_count_at, contents, pick_choice, opened_at, created_at')
    .order('created_at', { ascending: false }).limit(20);
  if (error) throw error;
  return (data ?? []).map((d: any) => {
    const { dateLabel } = kstParts(d.created_at);
    return { id: d.id, kind: d.kind, runCountAt: d.run_count_at, contents: d.contents ?? {}, pickChoice: d.pick_choice, openedAt: d.opened_at, when: dateLabel };
  });
}

export async function openDrop(dropId: string, pickChoice?: string): Promise<Record<string, unknown>> {
  const { data, error } = await supabase.functions.invoke('open-drop', { body: { drop_id: dropId, pick_choice: pickChoice } });
  if (error || data?.error) throw await fnError(error, data);
  return data;
}

// 활성 부스트 (픽 드랍 보상, 24h) — 표시용 라벨. 없으면 null (없는 데이터는 그리지 않는다)
export async function fetchActiveBoostLabel(): Promise<string | null> {
  const { data, error } = await supabase.from('boosts')
    .select('ends_at').gt('ends_at', new Date().toISOString())
    .order('ends_at', { ascending: false }).limit(1);
  if (error) throw error;
  if (!data?.[0]) return null;
  const { dateLabel, timeLabel } = kstParts(data[0].ends_at);
  return `${dateLabel} ${timeLabel}`;
}

export interface GearClaim { id: string; item: string; milestone: number; status: string }

export async function fetchGearClaims(): Promise<GearClaim[]> {
  const { data, error } = await supabase.from('gear_claims').select('id, item, milestone, status').order('milestone');
  if (error) throw error;
  return data ?? [];
}

// ---------- 주소 (픽업 장소) ----------
// lat/lng joined in the 0065 coordinates slice. Written ONLY by the pin picker
// (user-confirmed pin is the coordinate truth — never silently geocoded) via
// setAddressPin; both NULL until then. Server CHECK addresses_latlng_shape
// rejects half-pairs and out-of-Korea values — the client clamps first, but a
// rejected write must still surface as a visible failure (honesty law).
export interface Addr {
  id: string; label: string; addr: string; detail: string | null; isDefault: boolean;
  lat: number | null; lng: number | null;
}

export async function fetchAddresses(): Promise<Addr[]> {
  const { data, error } = await supabase.from('addresses')
    .select('id, label, addr, detail, is_default, lat, lng').order('created_at');
  if (error) throw error;
  return (data ?? []).map((a: any) => ({
    id: a.id, label: a.label, addr: a.addr, detail: a.detail, isDefault: a.is_default,
    lat: a.lat != null ? Number(a.lat) : null,
    lng: a.lng != null ? Number(a.lng) : null,
  }));
}

// Returns the new row id so the add flow can route straight into the pin picker
// (the picker is the second half of saving an address, not a separate errand).
export async function addAddress(p: { label: string; addr: string; detail?: string }): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const existing = await fetchAddresses();
  const { data, error } = await supabase.from('addresses').insert({
    owner_id: user.user.id, label: p.label, addr: p.addr, detail: p.detail ?? null,
    is_default: existing.length === 0, // 첫 주소 자동 기본
  }).select('id').single();
  if (error) throw error;
  return (data as any).id as string;
}

// Pin write — direct table update under owner RLS (0002: "addresses owner all").
// No RPC needed: the owner may only reach their own rows, and the CHECK carries
// the shape law server-side.
export async function setAddressPin(id: string, lat: number, lng: number): Promise<void> {
  const { error } = await supabase.from('addresses')
    .update({ lat, lng }).eq('id', id);
  if (error) throw error;
}

// Owner-side pickup coords for the meetup plate — two owner-RLS selects
// (own booking's address_id → own address row), no new server surface.
// null = booking has no address assigned; row with NULL lat = address exists
// but is unpinned (plate shows the "위치 지정하기" CTA with this addressId).
// [D15 2026-08-12] label/addr/detail 추가 — 보호자 미트업이 **자기가 쓴 픽업 메모**를 보여줘야 한다.
// 지금까지 이 문장은 러너만 봤다 (runner/meetup.tsx가 booking_pickup_address로 읽는다). 보호자는
// 자기가 뭘 적어 보냈는지 인계 화면에서 확인할 방법이 없었다 — 고칠 수 있는 사람만 못 보는 상태였다.
// 새 서버 표면은 없다: 보호자가 자기 주소를 owner RLS로 읽는 기존 경로에 컬럼만 더한다.
// gate_code_enc는 여기서도 구조적으로 선택하지 않는다 (0060 독트린).
export interface OwnerPickup {
  addressId: string; lat: number | null; lng: number | null;
  label: string; addr: string; detail: string | null;
}

export async function fetchOwnerPickupCoords(bookingId: string): Promise<OwnerPickup | null> {
  const { data: b, error: be } = await supabase.from('bookings')
    .select('address_id').eq('id', bookingId).maybeSingle();
  if (be) throw be;
  if (!b?.address_id) return null;
  const { data: a, error: ae } = await supabase.from('addresses')
    .select('id, lat, lng, label, addr, detail').eq('id', b.address_id).maybeSingle();
  if (ae) throw ae;
  if (!a) return null;
  return {
    addressId: a.id,
    lat: a.lat != null ? Number(a.lat) : null,
    lng: a.lng != null ? Number(a.lng) : null,
    label: a.label, addr: a.addr, detail: a.detail ?? null,
  };
}

export async function setDefaultAddress(id: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  await supabase.from('addresses').update({ is_default: false }).eq('owner_id', user.user.id);
  const { error } = await supabase.from('addresses').update({ is_default: true }).eq('id', id);
  if (error) throw error;
}

export async function deleteAddress(id: string): Promise<void> {
  const { error } = await supabase.from('addresses').delete().eq('id', id);
  if (error) throw error;
}

// 픽업 메모(addresses.detail) 수정 — 배정된 러너가 읽는 그 문장이다 (booking_pickup_address).
// ⚠ 여긴 일부러 `.from('addresses').update(...)`가 아니다. 0073 §1: `addresses`의 RLS는 **행**
// 단위이고 이 저장소엔 이 테이블에 대한 컬럼 grant가 한 줄도 없다 — 클라가 보내는 페이로드의
// TypeScript 타입은 보안 경계가 아니다. 그리고 진짜 위험은 테넌시가 아니라 정합성이다:
// addresses 행은 bookings.address_id가 가리키므로, addr를 고치면서 lat/lng를 남기면 **인계 화면에
// 거짓으로 핀이 박힌 주소**가 만들어진다. 그래서 컬럼 하나짜리 데피너 하나만 연다.
// 서버가 트림·빈문자열→NULL·60자 상한을 강제하므로 클라는 원문을 그대로 보낸다 (검증 이중화 금지 —
// 두 곳에서 자르면 두 규칙이 갈라진다). 상한만 입력 UI가 maxLength로 미리 알려준다.
export async function updateAddressDetail(id: string, detail: string): Promise<void> {
  const { error } = await supabase.rpc('owner_update_address_detail', {
    p_address: id,
    p_detail: detail,
  });
  if (error) {
    // 서버 문장을 사람 말로 한 번만 접는다. not_owner는 '없는 주소'와 '남의 주소'가 같은 문장이라
    // (열거 오라클 차단) 클라도 구별해서 말하지 않는다.
    if (error.message.includes('detail_too_long')) throw new Error('메모는 60자까지 쓸 수 있어요');
    if (error.message.includes('not_owner')) throw new Error('이 주소를 수정할 수 없어요');
    throw error;
  }
}

// 계정 아이디(@handle) 설정 — 0074. 인스타 문법: 소문자·3~20자·[a-z0-9_.].
// 서버가 유일한 검증자다 (set_my_handle) — 클라는 형식을 흉내내지 않고 서버 문장을 사람 말로 옮긴다.
// 두 곳에서 자르면 두 규칙이 갈라진다는 0073의 교훈 그대로.
export async function setMyHandle(handle: string): Promise<string> {
  const { data, error } = await supabase.rpc('set_my_handle', { p_handle: handle });
  if (error) {
    const m = error.message;
    if (m.includes('handle_taken')) throw new Error('이미 사용 중인 아이디예요');
    if (m.includes('handle_length')) throw new Error('아이디는 3~20자로 만들어주세요');
    if (m.includes('handle_charset')) throw new Error('영문 소문자·숫자·밑줄(_)·점(.)만 쓸 수 있어요');
    if (m.includes('handle_dots')) throw new Error('점(.)으로 시작하거나 끝날 수 없고, 연달아 쓸 수 없어요');
    if (m.includes('handle_reserved')) throw new Error('사용할 수 없는 아이디예요');
    if (m.includes('handle_required')) throw new Error('아이디를 입력해주세요');
    throw error;
  }
  return data as string;
}

// ---------- 동네 피드 (옵트인 러닝 자랑) ----------
export interface FeedPost {
  id: string;
  authorName: string;
  // [0074] 인스타처럼 **아이디**가 1급 신원이다. null = 아직 안 만든 사람 → 화면이 이름으로 폴백한다.
  authorHandle: string | null;
  authorAvatar: string | null;
  body: string | null;
  photoUrl: string | null;
  meta: { dogName?: string; km?: number; durationSec?: number; badges?: string[]; trace?: { x: number; y: number }[];
    collar?: string; // 칼라 컬러 키 (0033) — 런 카드 트레이스가 강아지 색으로
    club?: string; sessionId?: string; teams?: number; dogs?: number; sessionAt?: string }; // 클럽 리캡 자동 포스트 (0031)
  when: string;
  likes: number;
  likedByMe: boolean;
  mine: boolean;
  commentCount: number;
}

export interface FeedComment { id: number; authorName: string; authorAvatar: string | null; body: string; when: string; mine: boolean }

export async function fetchComments(postId: string): Promise<FeedComment[]> {
  const { data: user } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('feed_comments')
    .select('id, author_id, body, created_at, profiles!feed_comments_author_id_fkey(name, avatar_url)')
    .eq('post_id', postId)
    .order('created_at')
    .limit(50);
  if (error) throw error;
  return (data ?? []).map((c: any) => {
    const { dateLabel } = kstParts(c.created_at);
    return {
      id: c.id,
      authorName: c.profiles?.name ?? '이웃',
      authorAvatar: c.profiles?.avatar_url ?? null,
      body: c.body,
      when: dateLabel,
      mine: c.author_id === user.user?.id,
    };
  });
}

export async function addComment(postId: string, body: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { error } = await supabase.from('feed_comments').insert({ post_id: postId, author_id: user.user.id, body });
  if (error) throw error;
}

// ---------- 하이클럽 (0030, P-A S1) — 반포동 파일럿 ----------
export const CLUB_WAIVER_VERSION = '2026-07-29';
export interface ClubNextSession {
  id: string; scheduledAt: string; when: string; meetupPoint: string; status: string;
  capacity: number; rsvpCount: number; joined: boolean;
  // [0051] 위탁 문의 사실들 — db push 전 원격에선 undefined (그땐 문을 기존대로 그린다)
  format?: 'owner_only' | 'delegated_only' | 'mixed';
  routeName?: string | null; routeKm?: number | null; fare?: number | null;
}
export interface ClubOverview {
  id: string; name: string; district: string; status: 'collecting' | 'active';
  photoUrl: string | null; description: string | null; hostName: string | null;
  isHost: boolean; isMember: boolean; memberCount: number; interestCount: number; myInterest: boolean;
  nextSession: ClubNextSession | null;
}

const withWhen = (ns: any): ClubNextSession | null => {
  if (!ns) return null;
  const { dateLabel, timeLabel } = kstParts(ns.scheduledAt);
  return { ...ns, when: `${dateLabel} ${timeLabel}` };
};

export async function fetchClubOverview(district = '반포동'): Promise<ClubOverview | null> {
  const { data, error } = await supabase.rpc('club_overview', { p_district: district });
  if (error) throw error;
  if (!data) return null;
  return { ...data, nextSession: withWhen(data.nextSession) } as ClubOverview;
}

// 클럽 검색 (0031) — 드롭다운
export interface ClubSearchHit { id: string; name: string; district: string; status: string; photoUrl: string | null; memberCount: number; interestCount: number; nextAt: string | null }
export async function searchClubs(q: string): Promise<ClubSearchHit[]> {
  const { data, error } = await supabase.rpc('club_search', { p_q: q });
  if (error) throw error;
  return (data ?? []) as ClubSearchHit[];
}
export async function requestDistrictClub(district: string): Promise<string> {
  const { data, error } = await supabase.rpc('club_request_district', { p_district: district });
  if (error) throw error;
  return data as string;
}
export async function fetchClubMyStats(clubId: string): Promise<{ attended: number; streak: number }> {
  const { data, error } = await supabase.rpc('club_my_stats', { p_club: clubId });
  if (error) throw error;
  return data as { attended: number; streak: number };
}
export async function fetchClubHostStats(clubId: string): Promise<{ sessions: number; totalTeams: number; returning: number }> {
  const { data, error } = await supabase.rpc('club_host_stats', { p_club: clubId });
  if (error) throw error;
  return data as { sessions: number; totalTeams: number; returning: number };
}

export interface SessionPerson { name: string; avatarUrl: string | null; role: string; attendance: string; dogName: string | null; isMe?: boolean }
export interface ClubSessionDetail {
  id: string; clubId: string; scheduledAt: string; when: string; meetupPoint: string;
  status: string; capacity: number; hostName: string | null; isHost: boolean;
  joined: boolean; myAttendance: string | null; dogCount: number; nextSessionId: string | null;
  people: SessionPerson[];
  // [0052 §2] people는 당사자에게만 채워진다 (무관자는 []) — 인원수만 항상 온다.
  // db push 전 원격에선 undefined (그땐 people.length로 폴백)
  peopleCount?: number;
}

export async function fetchClubSession(sessionId: string): Promise<ClubSessionDetail | null> {
  const { data, error } = await supabase.rpc('club_session_detail', { p_session: sessionId });
  if (error) throw error;
  if (!data) return null;
  const { dateLabel, timeLabel } = kstParts(data.scheduledAt);
  return { ...data, when: `${dateLabel} ${timeLabel}` } as ClubSessionDetail;
}

const clubRpc = async (fn: string, args: Record<string, unknown>): Promise<any> => {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) {
    // [감사 1] feature_disabled는 전 클럽 액션 공통 게이트 (_club_require_v2) — 한 곳에서 번역
    if (error.message?.includes('feature_disabled')) {
      throw new Error('위탁 기능이 아직 열리지 않았어요 — 허용목록 계정인지 확인해주세요');
    }
    throw error;
  }
  return data;
};
export const registerClubInterest = (clubId: string) => clubRpc('club_register_interest', { p_club: clubId, p_wants: 'attend' }) as Promise<void>;
export const claimClubHost = (clubId: string) => clubRpc('club_claim_host', { p_club: clubId }) as Promise<void>;
export const createClubSession = (
  clubId: string, scheduledAtIso: string, meetupPoint: string, capacity = 12,
  routeId: string | null = null, format: 'owner_only' | 'delegated_only' | 'mixed' = 'owner_only',
) =>
  clubRpc('club_create_session', { p_club: clubId, p_scheduled_at: scheduledAtIso, p_meetup_point: meetupPoint, p_route: routeId, p_capacity: capacity, p_format: format }) as Promise<string>;
export const rsvpClubSession = (sessionId: string, dogId: string | null) =>
  clubRpc('session_rsvp', { p_session: sessionId, p_dog: dogId, p_waiver: CLUB_WAIVER_VERSION }) as Promise<void>;
export const cancelClubRsvp = (sessionId: string) => clubRpc('session_cancel_rsvp', { p_session: sessionId }) as Promise<void>;
export const checkinClubSession = (sessionId: string) => clubRpc('session_checkin', { p_session: sessionId }) as Promise<void>;
export const finishClubSession = (sessionId: string) => clubRpc('club_finish_session', { p_session: sessionId }) as Promise<void>;

// ---------- 위탁 (P-C → R1~R6 백엔드 완결판, 0037~0050) ----------
// 플랩 어휘 10종 (정본 = delegation-master-lab): PENDING/HOLDING/CLEARED/BOARDED/RUNNING/RETURNS/SETTLED/OUTSIDE/REFUND/REFUSED
export type FlapState =
  | 'PENDING' | 'HOLDING' | 'CLEARED' | 'BOARDED' | 'RUNNING'
  | 'RETURNS' | 'SETTLED' | 'OUTSIDE' | 'REFUND' | 'REFUSED';
export interface DelegationRunner { profileId: string; name: string; tier: string; cap: number; assigned: number; checkedIn: boolean; isMe: boolean }
// 서버 프로젝션 v4 (0048 club_dog_ui_state) — 클라이언트는 문자열을 지어내지 않는다
export interface DogUiState {
  primaryStage: string; secondaryBadges: string[]; blockingIssues: string[];
  primaryIssue: string | null; requiredActors: string[]; severity: 'info' | 'warn' | 'critical';
  allowedActions: string[];
}
export interface DelegationDog {
  sdId: string; dogId: string; dogName: string; collar: string | null; ownerName: string;
  isMine: boolean; approval: 'pending' | 'approved' | 'rejected' | 'auto' | 'withdrawn';
  serviceState: string | null; completionOutcome: string | null; terminationType: string | null;
  chargeState: string | null; holdStatus: string | null; holdExpiresAt: string | null; refundState: string | null;
  bookingId: string | null; bookingStatus: string | null; runnerId: string | null; runnerName: string | null;
  ownerConfirmed: boolean | null; runnerConfirmed: boolean | null; custodyWithRunner: boolean; checkedOut: boolean;
  // [R2] 커스터디·정산 축
  custodyPhase: string | null; custodianType: string | null; custodianProfileId: string | null; custodianExternal: string | null;
  ownerReturnConfirmed: boolean; runnerReturnConfirmed: boolean;
  payoutState: string | null; payoutHold: string | null; payoutHoldReason: string | null;
  pendingTransfer: {
    toType: 'runner' | 'clinic' | 'authority'; toProfile: string | null; toExternal: string | null;
    reason: string | null; by: string; at: string;
  } | null;
  returnOverrideKind: string | null;
  // [R3] 배정 축 (proposedRunner*는 호스트·피제안 러너에게만 옴 — 러너 프라이버시)
  assignmentState: 'unassigned' | 'proposed' | 'accepted' | 'declined' | 'replacement_needed' | null;
  objectionUsed: boolean | null; reviewNeeded: boolean | null;
  proposedRunnerId: string | null; proposedRunnerName: string | null; proposalExpiresAt: string | null;
  // [0052 §1] 이 아이의 미해소 인시던트 id — 케이스 딥링크의 서버 원천 (클라가 dog→케이스를 추측하지 않는다).
  // db push 전 원격에선 undefined (그땐 링크 없이 문구만)
  openIncidentId?: string | null;
  ui: DogUiState | null;
  flap: FlapState;
}
export interface SessionViability {
  format: string; attendanceOk: boolean; paidDogs: number; presentRunners: number; coverageOk: boolean; viable: boolean;
}
export interface DelegationBoard {
  session: {
    id: string; clubId: string; scheduledAt: string; when: string; meetupPoint: string; format: string; status: string;
    routeName: string | null; routeKm: number | null; fare: number | null; delegatedCapacity: number;
    reservedCount: number; approvedCount: number; pendingCount: number; isHost: boolean; checkinOpen: boolean;
    viability: SessionViability | null; openIncidents: number; unassignedIncidents: number;
  };
  runners: DelegationRunner[];
  me: { committed: boolean; runnerCap: number; checkedIn: boolean };
  dogs: DelegationDog[];
}
// 플랩 판정 — 커스터디 우선 (커스터디 국면이 서비스 축보다 먼저 말한다). 원천 필드에서만.
// 구(0039) 호출부 호환: 커스터디 필드가 없으면 서비스/결제 축만으로 판정.
export function flapOf(d: {
  approval: string; bookingStatus: string | null;
  chargeState?: string | null; holdStatus?: string | null; refundState?: string | null;
  custodyPhase?: string | null; custodianType?: string | null;
}): FlapState {
  // ① 커스터디 우선
  if (d.custodianType === 'clinic' || d.custodianType === 'authority') return 'OUTSIDE';
  if (d.custodyPhase === 'return_pending' || d.custodyPhase === 'transfer_pending') return 'RETURNS';
  // ② 예외 축
  if (d.refundState === 'pending' || d.refundState === 'failed') return 'REFUND';
  if (d.approval === 'rejected' || d.approval === 'withdrawn') return 'REFUSED';
  if (d.approval === 'pending') return 'PENDING';
  // ③ 승인 후 결제 전 = HOLDING (20분 홀드)
  if (d.chargeState != null && d.chargeState !== 'paid') return 'HOLDING';
  // ④ 서비스 축
  switch (d.bookingStatus) {
    case 'picked_up': return 'BOARDED';   // 인계 완료 = 보험 시작
    case 'active': return 'RUNNING';
    case 'completed': return d.custodyPhase != null && d.custodyPhase !== 'resolved' ? 'RETURNS' : 'SETTLED'; // 정산≠반환
    case 'refund_pending': case 'cancelled_runner': case 'expired': return 'REFUND';
    default: return 'CLEARED';            // 결제 완료 — 배정 대기/확정
  }
}
export async function fetchDelegationBoard(sessionId: string): Promise<DelegationBoard | null> {
  const data = await clubRpc('club_delegation_board', { p_session: sessionId });
  if (!data) return null;
  const { dateLabel, timeLabel } = kstParts(data.session.scheduledAt);
  return {
    ...data,
    session: { ...data.session, when: `${dateLabel} ${timeLabel}` },
    dogs: (data.dogs ?? []).map((d: any) => ({ ...d, flap: flapOf(d) })),
  } as DelegationBoard;
}
// [R4] 위탁 동의 — 서버가 불변 문서 v1로 박제 (본인도 수정 불가, 재동의 = 새 행)
export interface DelegationConsent {
  custodyAck: true;                 // 인계→양측 반환 확인까지 러너가 보호 책임자
  emergencyContact: string;         // 필수
  pickupName?: string | null;
  vetLimitKrw?: number | null;      // 미지정 시 서버 기본값 (club_config vet_limit_krw)
  photoConsent?: boolean;
}
export const delegateDog = (sessionId: string, dogId: string, consent: DelegationConsent) =>
  clubRpc('session_delegate_dog', { p_session: sessionId, p_dog: dogId, p_consent: consent }) as Promise<string>;
// [R1] 결제 (모의 PG) — 멱등키 필수
// [0053 §1/감사 9] 배정 방식 동의를 서버에 박제 — p_method_consent(distinct from true → method_consent_required).
// 기본 true는 기존 호출부 호환용(구 2인자 서명 유지) — 실동의는 O5 결제 시트의 methodOk 체크에서 수집해 넘긴다.
export const payDelegation = (sdId: string, idemKey: string, methodConsent = true) =>
  clubRpc('session_pay_delegation', { p_session_dog: sdId, p_idem_key: idemKey, p_method_consent: methodConsent }) as Promise<string>;
// [0053 §3a/감사 11a] 이 부킹의 러닝 사진 공개가 허용되는지 — 위탁 부킹의 최신 photo_consent 게이트(위탁 아니면 true).
export const runPhotoAllowed = (bookingId: string) =>
  clubRpc('club_run_photo_allowed', { p_booking: bookingId }) as Promise<boolean>;
// [R4] 취소 — 서버 사다리(무료→10%→20%) 판정, 인시던트 열림 시 차단
export const cancelDelegation = (sdId: string) =>
  clubRpc('session_cancel_delegation', { p_session_dog: sdId }) as Promise<void>;
// [R2] 반환 양측 확인 — 명시적 side (혼자 테스트 시 문법 대칭, 0046)
export const confirmReturn = (sdId: string, side: 'owner' | 'runner') =>
  clubRpc('session_confirm_return', { p_session_dog: sdId, p_side: side }) as Promise<unknown>;
// [R2] 커스터디 대리 기록 — 증인 증빙 필수, 자기 대리 금지 (0045)
export const custodyOverride = (sdId: string, side: 'owner' | 'runner', kind: 'assisted' | 'witness', artifact: unknown) =>
  clubRpc('session_custody_override', { p_session_dog: sdId, p_side: side, p_kind: kind, p_artifact: artifact }) as Promise<void>;
// [0069 C4/H5] 호스트 강제 종결 — 러닝이 끝나지 않은 위탁견(picked_up/active)의 유일한 출구.
// 반환을 날조하지 않는다: 부킹만 incident_review로 내려가고, 진실은 열리는 S2 케이스가 나른다.
// 반환 값 = 케이스 id (호스트가 곧바로 인수해야 세션이 닫힌다 — club_finish_session이 강제).
export const hostForceResolve = (sdId: string, reason: string, artifact: unknown) =>
  clubRpc('session_host_force_resolve', {
    p_session_dog: sdId, p_reason: reason, p_artifact: artifact,
  }) as Promise<string>;
// [R2] 이양 — 러너→러너(수락 필요) · clinic/authority(즉시·미드런은 원자 인시던트 경로)
export const transferInitiate = (
  sdId: string, toType: 'runner' | 'clinic' | 'authority',
  opts: { toProfile?: string; toExternal?: string; reason?: string } = {},
) =>
  clubRpc('session_transfer_initiate', {
    p_session_dog: sdId, p_to_type: toType,
    p_to_profile: opts.toProfile ?? null, p_to_external: opts.toExternal ?? null, p_reason: opts.reason ?? null,
  }) as Promise<void>;
export const transferAccept = (sdId: string, artifact: unknown = null) =>
  clubRpc('session_transfer_accept', { p_session_dog: sdId, p_artifact: artifact }) as Promise<void>;
export const transferCancel = (sdId: string) =>
  clubRpc('session_transfer_cancel', { p_session_dog: sdId }) as Promise<void>;
// [R2] 커스터디 이벤트 이력 — seq 순만 신뢰 (당사자 게이트)
export interface CustodyEvent {
  seq: number; eventType: string; fromType: string | null; fromProfileId: string | null;
  toType: string | null; toProfileId: string | null; toExternal: string | null;
  confirmationKind: string | null; occurredAt: string; reason: string | null; incidentId: string | null;
}
export const fetchCustodyEvents = (sdId: string) =>
  clubRpc('club_dog_custody_events', { p_session_dog: sdId }) as Promise<CustodyEvent[]>;
// [R2/R6] 인시던트 — 케이스 오너 지정·해소 (해소 = 자기 케이스 보류만 해제)
export interface ClubIncident {
  id: string; severity: string; state: string; summary: string;
  caseOwner: string | null; openedAt: string; resolvedAt: string | null;
}
export const fetchSessionIncidents = (sessionId: string) =>
  clubRpc('club_session_incidents', { p_session: sessionId }) as Promise<ClubIncident[]>;
export const incidentAssign = (incidentId: string, owner: string | null = null) =>
  clubRpc('club_incident_assign', { p_incident: incidentId, p_owner: owner }) as Promise<void>;
export const incidentResolve = (incidentId: string, note: string | null = null) =>
  clubRpc('club_incident_resolve', { p_incident: incidentId, p_note: note }) as Promise<void>;
// [R2] 릴리스 수동 트리거 — 허용목록 계정 전용 (운영은 pg_cron)
export const debugReleasePayouts = () =>
  clubRpc('club_debug_release_payouts', {}) as Promise<number>;
// [R3] Model A 배정 — 제안(5분 시효)/응답/이의
export const proposeDog = (sdId: string, runnerId: string) =>
  clubRpc('session_propose_dog', { p_session_dog: sdId, p_runner: runnerId }) as Promise<void>;
export const respondProposal = (sdId: string, accept: boolean, reason?: string) =>
  clubRpc('session_proposal_respond', { p_session_dog: sdId, p_accept: accept, p_reason: reason ?? null }) as Promise<void>;
// [R3] 보호자 이의 — kind 필수 (0047 최종 시그니처): preference = T-20까지·1회·사유 필수 / safety = 인계 전까지 무제한.
// wantRefund true = 전액 환불로 이탈, false = 배정 해제 후 재배정 (자리는 유지)
export const ownerObjection = (sdId: string, kind: 'preference' | 'safety', reason: string, wantRefund = false) =>
  clubRpc('session_owner_objection', { p_session_dog: sdId, p_kind: kind, p_reason: reason, p_want_refund: wantRefund }) as Promise<void>;
// [R3] 제안 취소 (호스트) — 수락 전만
export const proposalRevoke = (sdId: string) =>
  clubRpc('session_proposal_revoke', { p_session_dog: sdId }) as Promise<void>;
// [R3] 배정 철회 (호스트) — 인계 전만 → replacement_needed, 상습 철회는 이벤트로 추적
export const assignmentRevoke = (sdId: string, reason: string | null = null) =>
  clubRpc('session_assignment_revoke', { p_session_dog: sdId, p_reason: reason }) as Promise<void>;
export const approveDelegation = (sdId: string, approve: boolean) =>
  clubRpc('session_approve_dog', { p_session_dog: sdId, p_approve: approve }) as Promise<string | null>;
// [R4·감사 P0] 재검토 판정 — approved+review_needed 행은 session_approve_dog가 아니라 이 함수다 (0048)
export const reviewDelegation = (sdId: string, approve: boolean) =>
  clubRpc('session_review_dog', { p_session_dog: sdId, p_approve: approve }) as Promise<void>;
export const assignDelegation = (sdId: string, runnerId: string) =>
  clubRpc('session_assign_dog', { p_session_dog: sdId, p_runner: runnerId }) as Promise<void>;
export const commitAsHandler = (sessionId: string) =>
  clubRpc('session_runner_commit', { p_session: sessionId }) as Promise<number>;
export const withdrawAsHandler = (sessionId: string) =>
  clubRpc('session_runner_withdraw', { p_session: sessionId }) as Promise<number>;
export const cancelClubSession = (sessionId: string) =>
  clubRpc('club_cancel_session', { p_session: sessionId }) as Promise<number>;
export const startDelegatedRuns = (sessionId: string) =>
  clubRpc('club_start_delegated_runs', { p_session: sessionId }) as Promise<string[]>;
export const saveClubRunTrace = (sessionId: string, trace: { lat: number; lng: number; t: number }[]) =>
  clubRpc('club_save_run_trace', { p_session: sessionId, p_trace: trace }) as Promise<number>;

// [R5] 세션 셸 (0049) — 접근 단일 판정 · 로스터 (전화 규칙 B — 반환된 번호는 전부 열람 로그, UI가 이를 고지한다)
export type ShellAccess = 'host' | 'full' | 'limited' | 'none'; // "신청은 사적 공간의 문이 아니다"
export const fetchShellAccess = (sessionId: string) =>
  clubRpc('club_my_shell_access', { p_session: sessionId }) as Promise<ShellAccess>;
export interface RosterPerson {
  profileId: string; name: string; avatarUrl: string | null;
  role: string | null;              // host/handling_runner/runner_attending/owner_attending — null = 위탁 보호자(부재 참가)
  attendance: string | null; runnerCap: number | null;
  isHost: boolean; isBackup: boolean; isMe: boolean;
  phone: string | null;             // 규칙 B로 보일 때만 — 서버가 로그 후 반환
  phoneVia: 'direct' | 'host';
}
export interface RosterDogDetail {
  memo: string | null; weightKg: number | null; breed: string | null;
  emergencyContact: string | null; pickupName: string | null; vetLimitKrw: number | null;
}
export interface RosterDog {
  sdId: string; dogName: string; collar: string | null; custody: string | null;
  ownerName: string | null; isMine: boolean;
  detail: RosterDogDetail | null;   // 호스트·본인·담당 러너에게만
  chargeLabel: string | null;       // 호스트 읽기 전용
}
export interface SessionRoster {
  access: ShellAccess;
  people: RosterPerson[];
  dogs: RosterDog[];                // limited = 자기 기록만 (서버가 거른다)
  capacityMeter: { reserved: number; capacity: number; viability: SessionViability } | null; // 호스트만
}
export const fetchSessionRoster = (sessionId: string) =>
  clubRpc('club_session_roster', { p_session: sessionId }) as Promise<SessionRoster>;

// [R5] 세션 채팅 (0049) — RLS 직접 접근 = 리얼타임 구독 경로. 그룹(full/host) + 호스트 창구(1:1).
// 호스트 창구 스레드 키 = recipient_profile_id(신청자). 수정 불가, 삭제는 본인 5분 RPC만.
export interface ClubChatMsg {
  id: number; senderId: string; senderName: string;
  audience: 'group' | 'host_channel'; recipientProfileId: string | null;
  kind: 'text' | 'photo' | 'system'; body: string | null; mediaPath: string | null;
  flagged: boolean; deleted: boolean; mine: boolean; createdAt: string; when: string;
  counterpartId: string | null; // 호스트 창구 상대 (mine이면 수신자, 아니면 발신자) — 그룹은 null
}
export const fetchChatWritable = (sessionId: string) =>
  clubRpc('club_my_chat_writable', { p_session: sessionId }) as Promise<boolean>;
export async function fetchClubChat(sessionId: string): Promise<{ uid: string | null; msgs: ClubChatMsg[] }> {
  const { data: user } = await supabase.auth.getUser();
  const uid = user.user?.id ?? null;
  // [감사 P2] 최신 300건 (asc+limit은 '가장 오래된 300건'이라 넘치면 새 메시지가 영영 안 보였다)
  const { data, error } = await supabase.from('club_chat_messages')
    .select('id, sender_id, audience, recipient_profile_id, kind, body, media_path, flagged, deleted_at, created_at')
    .eq('session_id', sessionId).order('id', { ascending: false }).limit(300);
  if (error) throw error;
  const rows = (data ?? []).reverse();
  // 이름은 2-step (임베드 FK명 의존 없음 — fetchRecentReviews 선례)
  const ids = [...new Set(rows.map((r: any) => r.sender_id))];
  const names: Record<string, string> = {};
  if (ids.length) {
    const { data: ps } = await supabase.from('profiles').select('id, name').in('id', ids);
    for (const p of ps ?? []) names[p.id] = p.name;
  }
  return {
    uid,
    msgs: rows.map((r: any): ClubChatMsg => {
      const mine = r.sender_id === uid;
      const { timeLabel } = kstParts(r.created_at);
      return {
        id: r.id, senderId: r.sender_id, senderName: names[r.sender_id] ?? '참가자',
        audience: r.audience, recipientProfileId: r.recipient_profile_id,
        kind: r.kind, body: r.body, mediaPath: r.media_path,
        flagged: r.flagged, deleted: r.deleted_at != null, mine,
        createdAt: r.created_at, when: timeLabel,
        counterpartId: r.audience === 'host_channel' ? (mine ? r.recipient_profile_id : r.sender_id) : null,
      };
    }),
  };
}
// 전송 — 그룹: recipient 없음 · 호스트 창구: 신청자는 recipient=본인, 호스트는 recipient=신청자 (RLS가 판정)
export async function sendClubChat(
  sessionId: string, body: string,
  opts: { audience?: 'group' | 'host_channel'; recipient?: string | null } = {},
): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const audience = opts.audience ?? 'group';
  const { error } = await supabase.from('club_chat_messages').insert({
    session_id: sessionId, sender_id: user.user.id, audience,
    recipient_profile_id: audience === 'host_channel' ? (opts.recipient ?? user.user.id) : null,
    kind: 'text', body,
  });
  if (error) throw error;
}
// 사진 메시지 — [0064] PRIVATE media 버킷 {uid}/clubchat/{session}/* + kind 'photo'
// media_path엔 경로 저장 — 스토리지 정책이 club_chat_messages RLS(메시지 가시성)로 읽기를 위임한다.
export async function sendClubChatPhoto(
  sessionId: string, base64: string,
  opts: { audience?: 'group' | 'host_channel'; recipient?: string | null } = {},
): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/clubchat/${sessionId}/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from(MEDIA_BUCKET)
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  const audience = opts.audience ?? 'group';
  const { error: e2 } = await supabase.from('club_chat_messages').insert({
    session_id: sessionId, sender_id: user.user.id, audience,
    recipient_profile_id: audience === 'host_channel' ? (opts.recipient ?? user.user.id) : null,
    kind: 'photo', body: null, media_path: path,
  });
  if (e2) throw e2;
}
export function subscribeClubChat(sessionId: string, onInsert: () => void): () => void {
  // P0-1 후속(0108): club-chat 채널은 postgres_changes 전용이라 브로드캐스트 노출은 없었지만,
  // 프로젝트 전역 private_only 가 켜지는 순간 public 채널은 **전부** 죽는다. 서버 정책(0108)이
  // 이 토픽족을 인가하므로 private 으로 요청하고, 구독 전에 소켓을 무장시킨다.
  hookTokenRefresh();
  const ch = supabase
    .channel(`club-chat-${sessionId}`, REALTIME_PRIVATE)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'club_chat_messages', filter: `session_id=eq.${sessionId}` },
      () => onInsert())
    ;
  // 무장 → 구독 순서. 그 사이 도착한 변경은 화면의 폴백 폴링이 잡는다(각 소비처가 폴링을 유지한다).
  let dropped = false;
  void armRealtime().then(() => { if (!dropped) ch.subscribe(); });
  return () => { dropped = true; supabase.removeChannel(ch); };
}
// [감사 11] 삭제가 사진 원본을 스토리지에 남기던 것 — 말풍선만 지워지고 공개 URL은 살아 있었다.
// RPC(본인 5분 내만)가 성공한 뒤에만 원본을 지운다. 원본 정리는 베스트에포트 —
// 스토리지가 실패해도 삭제 자체는 이미 끝난 사실이라 되돌리지 않는다.
export async function clubChatDelete(messageId: number): Promise<void> {
  const { data: row } = await supabase.from('club_chat_messages')
    .select('media_path').eq('id', messageId).maybeSingle();
  await clubRpc('club_chat_delete', { p_message: messageId });
  const media = (row as any)?.media_path as string | null | undefined;
  if (!media) return;
  if (!/^https?:/.test(media)) {
    // [0064] 새 형식: media 버킷의 경로. 잔존해도 스토리지 정책이 deleted_at으로 읽기를 봉인한다.
    try { await supabase.storage.from(MEDIA_BUCKET).remove([media.split('?')[0]]); } catch { /* 원본 잔존은 로그 없이 넘긴다 */ }
    return;
  }
  const at = media.indexOf('/avatars/');
  if (at >= 0) {
    const path = media.slice(at + '/avatars/'.length).split('?')[0];
    if (path) {
      try { await supabase.storage.from('avatars').remove([path]); } catch { /* 원본 잔존은 로그 없이 넘긴다 */ }
    }
  }
}
export const clubChatReport = (messageId: number, reason: string | null = null) =>
  clubRpc('club_chat_report', { p_message: messageId, p_reason: reason }) as Promise<void>;

// [R6] 인시던트 개설/SOS/증거/열람 (0050) — 케이스 당사자 게이트, 강아지 대상 ⇒ 지급 보류(ended 포함)
export interface IncidentEvidence { kind: 'photo' | 'text' | 'location' | 'document'; payload: any; by: string; byName: string; at: string; when: string }
export interface IncidentDetail {
  id: string; severity: string; state: string; summary: string;
  openedBy: string; openedByName: string; caseOwner: string | null; caseOwnerName: string | null;
  openedAt: string; resolvedAt: string | null; myId: string | null;
  // [0052 §7] 호스트·백업 호스트 판정은 서버가 한다 — db push 전 원격에선 undefined
  isHost?: boolean;
  subjects: { type: string; id: string }[];
  evidence: IncidentEvidence[];
}
export async function fetchIncidentDetail(incidentId: string): Promise<IncidentDetail> {
  const { data: user } = await supabase.auth.getUser();
  const raw = await clubRpc('club_incident_detail', { p_incident: incidentId });
  // 이름 2-step (RPC는 uuid만 준다)
  const ids = [...new Set([raw.openedBy, raw.caseOwner, ...(raw.evidence ?? []).map((e: any) => e.by)].filter(Boolean))];
  const names: Record<string, string> = {};
  if (ids.length) {
    const { data: ps } = await supabase.from('profiles').select('id, name').in('id', ids);
    for (const p of ps ?? []) names[p.id] = p.name;
  }
  return {
    ...raw,
    myId: user.user?.id ?? null,
    openedByName: names[raw.openedBy] ?? '참가자',
    caseOwnerName: raw.caseOwner ? names[raw.caseOwner] ?? '참가자' : null,
    evidence: (raw.evidence ?? []).map((e: any) => ({
      ...e, byName: names[e.by] ?? '참가자', when: kstParts(e.at).timeLabel,
    })),
  } as IncidentDetail;
}
export const incidentOpen = (
  sessionId: string, severity: 'S1' | 'S2' | 'S3', summary: string,
  opts: { dog?: string | null; booking?: string | null; location?: unknown } = {},
) =>
  clubRpc('club_incident_open', {
    p_session: sessionId, p_severity: severity, p_summary: summary,
    p_dog: opts.dog ?? null, p_booking: opts.booking ?? null, p_location: opts.location ?? null,
  }) as Promise<string>;
export const clubSos = (sessionId: string, location: unknown = null) =>
  clubRpc('club_sos', { p_session: sessionId, p_location: location }) as Promise<string>; // S1 슈가 — 최소 입력 최대 팬아웃
export const incidentEvidenceAdd = (incidentId: string, kind: 'photo' | 'text' | 'location' | 'document', payload: unknown) =>
  clubRpc('club_incident_evidence_add', { p_incident: incidentId, p_kind: kind, p_payload: payload }) as Promise<void>;

// [0072] 케이스 정산 — incident_review에 멈춘 부킹의 유일한 상업적 출구.
// 견적은 서버가 계산한다 (부킹이 기록한 요금 구성 + 실측 거리 + 러너 수수료율에서 파생 —
// 클라가 금액을 만들지 않는다). 호출자는 세 결말 중 하나만 고른다.
export type SettleOutcome = 'refund_full' | 'settle_measured' | 'pay_full';
export interface SettleQuote {
  refund: number; runnerGross: number; runnerFee: number; runnerNet: number;
  measuredKm: number; tookCustody: boolean; basis: string;
}
export const incidentSettleQuote = async (bookingId: string, outcome: SettleOutcome): Promise<SettleQuote> => {
  const raw = await clubRpc('club_incident_settle_quote', { p_booking: bookingId, p_outcome: outcome }) as any;
  const r = Array.isArray(raw) ? raw[0] : raw;
  return {
    refund: Number(r?.refund ?? 0), runnerGross: Number(r?.runner_gross ?? 0),
    runnerFee: Number(r?.runner_fee ?? 0), runnerNet: Number(r?.runner_net ?? 0),
    measuredKm: Number(r?.measured_km ?? 0), tookCustody: !!r?.took_custody,
    basis: String(r?.basis ?? ''),
  };
};
export const incidentSettle = (incidentId: string, bookingId: string, outcome: SettleOutcome, note: string | null = null) =>
  clubRpc('club_incident_settle', {
    p_incident: incidentId, p_booking: bookingId, p_outcome: outcome, p_note: note,
  }) as Promise<{ refund: number; runnerGross: number; runnerNet: number; rule: string }>;

// 클럽 러닝 종료용 — runs는 당사자 읽기 가능 (0002). 경과 시간은 실측으로 계산한다 (가짜 숫자 금지)
export async function fetchRunStartedAt(bookingId: string): Promise<string | null> {
  const { data } = await supabase.from('runs').select('started_at').eq('booking_id', bookingId).maybeSingle();
  return (data as any)?.started_at ?? null;
}

// Marketplace live surfaces need BOTH facts in one round trip (pace-state-ui-plan §1/§3):
// `started_at` is the only honest elapsed clock (a per-mount clock fabricates a 0'52" pace
// for an owner who opens the screen at km 2.3), and `pace_suggest_sec` is the run-start
// SNAPSHOT of the owner's suggestion — frozen so a mid-run pref edit cannot move the
// goalpost. `fetchRunStartedAt` above stays for the club run screen, which has neither.
export interface RunMeta { startedAt: string | null; paceSuggestSec: number | null }

// ⚠ 0079 PRE-PUSH TOLERANCE — `runs.pace_suggest_sec` does not exist until the LA slice's
// migration lands, and PostgREST hard-errors (42703) on an unknown column, which would take
// the elapsed clock down with it. So an undefined-column error falls back to a started_at-only
// retry with a null suggestion (caption absent — §6's "unset ≠ known", never a fabricated 480).
// REMOVE this fallback once 0079 is pushed; keeping it would hide a real schema regression.
const isUndefinedColumn = (e: any): boolean =>
  e?.code === '42703' || /does not exist/i.test(String(e?.message ?? ''));

export async function fetchRunMeta(bookingId: string): Promise<RunMeta> {
  const { data, error } = await supabase.from('runs')
    .select('started_at, pace_suggest_sec').eq('booking_id', bookingId).maybeSingle();
  if (!error) {
    return {
      startedAt: (data as any)?.started_at ?? null,
      paceSuggestSec: readPaceSuggest((data as any)?.pace_suggest_sec),
    };
  }
  if (!isUndefinedColumn(error)) return { startedAt: null, paceSuggestSec: null };
  return { startedAt: await fetchRunStartedAt(bookingId), paceSuggestSec: null };
}

// [R5] 크리티컬 ack (0049) — 제목 레지스트리 팬아웃, 확인 전까지 배너로 따라온다 (30분 뒤 호스트 에스컬레이션)
export interface ClubAck { id: string; title: string; body: string | null; refId: string | null; createdAt: string }
export const fetchMyAcks = () => clubRpc('club_my_acks', {}) as Promise<ClubAck[]>;
export const ackClub = (ackId: string) => clubRpc('club_ack', { p_ack: ackId }) as Promise<void>;

// 클럽 사진 (호스트) — avatars 버킷의 본인 폴더 (스토리지 정책상 uid 폴더만 쓰기 가능)
export async function uploadClubPhoto(clubId: string, base64: string): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/club-${clubId}.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg', upsert: true });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  const url = `${pub.publicUrl}?v=${Date.now()}`;
  const { error: e2 } = await supabase.from('clubs').update({ photo_url: url }).eq('id', clubId);
  if (e2) throw e2;
  return url;
}

// 자유 포스트 — 완료된 러닝을 요구하지 않는다 (Sean 2026-08-12: "let's not restrict what the users
// will be uploading"). booking_id 없이 글·사진만 올라간다. 서버(0074 feed_claim_gate)가 이걸 허용하고,
// 하네스 F1이 그 허용을 핀으로 박아 다음 세션이 조용히 되돌리지 못하게 막는다.
// ⚠ meta는 비운다: km/durationSec/trace 중 하나라도 실으면 게이트가 예약을 요구한다. 그게 정확히
// 의도한 선이다 — 자랑은 누구나, 기록은 달린 사람만.
export async function createFreePost(body: string, photoBase64?: string | null): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('로그인이 필요해요');
  const text = body.trim();
  if (!text && !photoBase64) throw new Error('사진이나 글 중 하나는 있어야 해요');

  let photoPath: string | null = null;
  if (photoBase64) {
    // 채팅 사진과 같은 PRIVATE 버킷 경로 관례 (0064) — DB엔 경로만, 화면이 서명 URL로 푼다.
    photoPath = `${user.user.id}/feed/${Date.now()}.jpg`;
    const { error } = await supabase.storage.from(MEDIA_BUCKET)
      .upload(photoPath, b64ToBytes(photoBase64), { contentType: 'image/jpeg' });
    if (error) throw error;
  }

  const { error } = await supabase.from('feed_posts').insert({
    author_id: user.user.id,
    booking_id: null,
    body: text || null,
    photo_url: photoPath,
    meta: {},
  });
  if (error) throw error;
}

export async function shareRunToFeed(bookingId: string, body?: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const report = await fetchRunReport(bookingId);
  if (!report.run) throw new Error('완료된 러닝만 공유할 수 있어요');
  const standings = await fetchRunStandings(bookingId).catch(() => null);
  // 칼라 컬러 동봉 (0033) — 피드 런 카드 트레이스가 강아지의 색으로
  const { data: bkDog } = await supabase.from('bookings').select('dogs(collar)').eq('id', bookingId).maybeSingle();
  const collar: string | null = (bkDog as any)?.dogs?.collar ?? null;
  const badges: string[] = [];
  if (standings && standings.total > 1) {
    if (standings.kmRank === 1) badges.push('★ 역대 최장 거리');
    if (standings.paceRank === 1) badges.push('★ 역대 최고 페이스');
  }
  // 트레이스 동봉 (2026-07-29) — 사진 없는 포스트가 '밋밋한 텍스트'가 아니라 런 카드가 되게.
  // 정규화 0..1 + ≤40포인트 서브샘플 (meta jsonb 소형 유지)
  let trace: { x: number; y: number }[] | undefined;
  const raw = report.run.trace;
  if (raw.length > 1) {
    const lats = raw.map((p) => p.lat);
    const lngs = raw.map((p) => p.lng);
    const dLat = Math.max(Math.max(...lats) - Math.min(...lats), 1e-6);
    const dLng = Math.max(Math.max(...lngs) - Math.min(...lngs), 1e-6);
    const step = Math.max(1, Math.ceil(raw.length / 40));
    trace = raw.filter((_, i) => i % step === 0 || i === raw.length - 1).map((p) => ({
      x: Math.round(((p.lng - Math.min(...lngs)) / dLng) * 1000) / 1000,
      y: Math.round((1 - (p.lat - Math.min(...lats)) / dLat) * 1000) / 1000,
    }));
  }
  const { error } = await supabase.from('feed_posts').insert({
    author_id: user.user.id,
    booking_id: bookingId,
    body: body ?? null,
    photo_url: report.run.photos[0] ?? null,
    meta: { dogName: report.dogName, km: report.run.actualKm, durationSec: report.run.durationSec, badges, trace, ...(collar ? { collar } : {}) },
  });
  if (error) {
    if (error.code === '23505') throw new Error('이미 피드에 공유한 러닝이에요');
    throw error;
  }
}

export async function fetchFeed(): Promise<FeedPost[]> {
  const { data: user } = await supabase.auth.getUser();
  const uid = user.user?.id;
  const { data, error } = await supabase
    .from('feed_posts')
    .select('id, author_id, body, photo_url, meta, created_at, profiles!feed_posts_author_id_fkey(name, handle, avatar_url), feed_likes(profile_id), feed_comments(count)')
    .order('created_at', { ascending: false })
    .limit(30);
  if (error) throw error;
  return (data ?? []).map((p: any) => {
    const { dateLabel, timeLabel } = kstParts(p.created_at);
    const likes: { profile_id: string }[] = p.feed_likes ?? [];
    return {
      id: p.id,
      authorName: p.profiles?.name ?? '이웃',
      authorHandle: p.profiles?.handle ?? null,
      authorAvatar: p.profiles?.avatar_url ?? null,
      body: p.body,
      photoUrl: p.photo_url,
      meta: p.meta ?? {},
      when: `${dateLabel} ${timeLabel}`,
      likes: likes.length,
      likedByMe: !!uid && likes.some((l) => l.profile_id === uid),
      mine: p.author_id === uid,
      commentCount: p.feed_comments?.[0]?.count ?? 0,
    };
  });
}

export async function toggleFeedLike(postId: string, liked: boolean): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  if (liked) {
    await supabase.from('feed_likes').delete().eq('post_id', postId).eq('profile_id', user.user.id);
  } else {
    await supabase.from('feed_likes').insert({ post_id: postId, profile_id: user.user.id }).then((r) => {
      if (r.error && r.error.code !== '23505') throw r.error;
    });
  }
}

export async function deleteFeedPost(postId: string): Promise<void> {
  const { error } = await supabase.from('feed_posts').delete().eq('id', postId);
  if (error) throw error;
}

// Booking ids I already shared to the feed (feed_posts.booking_id is unique per run).
// The composer uses this to mark runs "공유 완료" honestly instead of offering a share
// that can only fail with 23505.
export async function fetchMySharedBookingIds(): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase
    .from('feed_posts')
    .select('booking_id')
    .eq('author_id', user.user.id)
    .not('booking_id', 'is', null);
  if (error) throw error;
  return (data ?? []).map((r: any) => r.booking_id as string);
}

// ---------- 하이 포인트 + 리더보드 (통합 인센티브 경제) ----------
export interface MilesInfo { balance: number; recent: { delta: number; reason: string; when: string }[] }

const MILE_REASON: Record<string, string> = {
  run_complete: '러닝 완주', poop_bonus: '응가 도장 보너스', drop: '드랍 보상', shop_spend: '샵 사용',
  patch_gold: '골드 패치 승급', patch_master: '코스 마스터 달성', // 0025 패치 승급 보너스
  pick_drop: '픽 드랍 보상', weekly_top_dog: '주간 TOP3 · 강아지', weekly_top_runner: '주간 TOP3 · 러너',
};

export async function fetchMiles(): Promise<MilesInfo> {
  // 잔액 = 서버 집계 RPC (0027) — 2000행 클라 합산 상한 은퇴. 내역은 최근 10행만 내려받는다.
  const [bal, rows] = await Promise.all([
    supabase.rpc('my_miles_balance'),
    supabase.from('miles_ledger').select('delta, reason, created_at')
      .order('created_at', { ascending: false }).limit(10),
  ]);
  if (bal.error) throw bal.error;
  if (rows.error) throw rows.error;
  return {
    balance: Number(bal.data ?? 0),
    recent: (rows.data ?? []).map((r: any) => {
      const { dateLabel } = kstParts(r.created_at);
      return { delta: r.delta, reason: MILE_REASON[r.reason] ?? r.reason, when: dateLabel };
    }),
  };
}

// ---------- 러닝 1건의 적립 (리워드 ① — 버는 순간을 보이게) ----------
// 정산(settle_run_tx/0028)이 이 예약에 쓰는 인센티브 행:
//   run_complete +50 (양측) · poop_bonus +30 (양측) · patch_gold +200 · patch_master +500.
// [주의] ref_id는 다형(polymorphic) 컬럼이다 — open-drop 엣지 함수는 reason 'drop'/'pick_drop'을
// ref_id = drop_id 로 쓴다. booking id 와 drop id 가 부딪힐 확률은 uuid-v4라 무시할 수준이지만,
// '이 러닝이 번 것'이라는 뜻을 쿼리에 명시하려고 정산 reason 화이트리스트로 좁힌다.
// RLS "miles self read"(0002)가 profile_id = auth.uid()로 이미 행을 좁히지만, 0027 독트린대로
// where 절에도 uid를 건다 (이중 안전장치 — RLS가 진짜 방어선이고 이건 그 위의 한 겹).
// 0행 = 아직 정산 전이거나 조기 종료(v_is_full 게이트가 한 줄도 안 쓴다) → null 을 돌려
// 화면이 섹션 자체를 그리지 않게 한다 (없는 적립을 0으로 그리는 건 거짓말).
export interface RunEarning { total: number; lines: { reason: string; label: string; delta: number }[] }

const SETTLE_REASONS = ['run_complete', 'poop_bonus', 'patch_gold', 'patch_master'];

export async function fetchRunEarning(bookingId: string): Promise<RunEarning | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null; // 로그인 없음 = 그릴 적립도 없음 (fetchCoursePatches와 같은 문법)
  const { data, error } = await supabase
    .from('miles_ledger')
    .select('delta, reason')
    .eq('ref_id', bookingId)
    .eq('profile_id', user.user.id)
    .in('reason', SETTLE_REASONS)
    .order('id');
  if (error) throw error; // 실패는 실패로 — 호출부는 catch해서 '못 불러옴'(미표시)으로 둔다, 0이 아니다
  const rows = data ?? [];
  if (rows.length === 0) return null;
  const lines = rows.map((r: any) => ({
    reason: String(r.reason),
    label: MILE_REASON[r.reason] ?? String(r.reason),
    delta: Number(r.delta),
  }));
  return { total: lines.reduce((sum, l) => sum + l.delta, 0), lines };
}

// ---------- 홈 비컨 (리워드 ① — 실잔액 + 다음 패치까지) ----------
// 실데이터만: 잔액은 서버 집계(0027), 다음 목표는 내 최다 완주 코스의 사다리(5/10/25) 잔여.
// claimable 같은 '받을 게 있다' 류의 거짓 신호는 금지 — 여기선 아예 만들지 않는다.
export interface BeaconInfo { balance: number; next: { name: string; count: number; toNext: number } | null }

export async function fetchRewardBeacon(): Promise<BeaconInfo> {
  const [bal, patches] = await Promise.all([
    supabase.rpc('my_miles_balance'),
    fetchCoursePatches(),
  ]);
  if (bal.error) throw bal.error;
  // [director] '다음 패치까지'의 정직한 해석 = 가장 가까운 승급 (최다 완주 코스가 아니라).
  // count 4(실버까지 1회)가 count 11(마스터까지 14회)을 이긴다 — 카피와 선택 기준이 일치해야 한다.
  // 동률이면 count 높은 쪽 (더 진행된 코스). 마스터(25) 도달 코스는 다음 목표가 없으므로 제외.
  const candidates = patches.earned
    .map((c) => {
      const tier = [5, 10, 25].find((t) => t > c.count);
      return tier === undefined ? null : { name: c.name, count: c.count, toNext: tier - c.count };
    })
    .filter((c): c is { name: string; count: number; toNext: number } => c !== null)
    .sort((a, b) => a.toNext - b.toNext || b.count - a.count);
  return {
    balance: Number(bal.data ?? 0),
    // 전 코스 마스터 또는 완주 코스 없음 → 다음 목표 없음 (지어내지 않는다)
    next: candidates[0] ?? null,
  };
}

export interface BoardRow { name: string; photoUrl: string | null; km: number; runs: number; delta?: number | null }

// 홈 티커용 — 지난주 대비 랭크 델타 포함 (0022). 미배포 시 델타 없는 기존 보드로 정직 폴백
// (▲▼은 실델타가 있을 때만 그린다 — '없는 데이터는 그리지 않는다')
export async function fetchDogBoardDelta(): Promise<BoardRow[]> {
  const { data, error } = await supabase.rpc('leaderboard_dogs_weekly_delta');
  if (error) {
    const { data: fb, error: e2 } = await supabase.rpc('leaderboard_dogs_weekly');
    if (e2) throw e2;
    // delta: undefined = '델타를 모름'(구 RPC) — null('신규 진입')과 구분해 NEW 오표기 방지
    return (fb ?? []).map((x: any) => ({ name: x.dog_name, photoUrl: x.photo_url, km: Number(x.km), runs: Number(x.runs) }));
  }
  return (data ?? []).map((x: any) => ({
    name: x.dog_name, photoUrl: x.photo_url, km: Number(x.km), runs: Number(x.runs),
    delta: x.delta == null ? null : Number(x.delta),
  }));
}

export async function fetchLeaderboards(): Promise<{ dogs: BoardRow[]; runners: BoardRow[] }> {
  const [d, r] = await Promise.all([
    supabase.rpc('leaderboard_dogs_weekly'),
    supabase.rpc('leaderboard_runners_weekly'),
  ]);
  if (d.error) throw d.error;
  if (r.error) throw r.error;
  return {
    dogs: (d.data ?? []).map((x: any) => ({ name: x.dog_name, photoUrl: x.photo_url, km: Number(x.km), runs: Number(x.runs) })),
    runners: (r.data ?? []).map((x: any) => ({ name: x.runner_name, photoUrl: x.avatar_url, km: Number(x.km), runs: Number(x.runs) })),
  };
}

// ---------- notifications (읽기 — 실시간 배달은 Realtime 세션에서) ----------
export interface LiveNoti { id: string; title: string; body: string | null; when: string; dateLabel: string; timeLabel: string; unread: boolean; kind: string; refId: string | null }

export async function fetchNotifications(): Promise<LiveNoti[]> {
  const { data, error } = await supabase
    .from('notifications')
    .select('id, title, body, created_at, read_at, kind, ref_id')
    .order('created_at', { ascending: false })
    .limit(20);
  if (error) throw error;
  return (data ?? []).map((n: any) => {
    const { dateLabel, timeLabel } = kstParts(n.created_at);
    // dateLabel/timeLabel 분리 노출 (2026-07-29) — 알림 타임라인의 날짜 그룹핑용
    return { id: n.id, title: n.title, body: n.body, when: `${dateLabel} ${timeLabel}`, dateLabel, timeLabel, unread: !n.read_at, kind: n.kind, refId: n.ref_id };
  });
}

// ---------- 러닝 리포트 (보호자) ----------
export interface RunReport {
  dogName: string; routeName: string; routeArea: string; when: string;
  runnerName: string | null;
  runnerProfileId: string | null;
  routeId: string | null;
  plannedKm: number; paceLabel: string; status: string;
  // NO `price`, deliberately. It carried `bookings.total_price` — the FROZEN PLANNED total —
  // and report.tsx rendered it under the label 결제 금액, which is not what the owner was
  // charged for any early-ended run (compute_owner_charge bills `least(actual, km)`, and
  // `runner_personal` drops base + addons). Removed rather than corrected: §0-bis puts the
  // post-run moment on the record card, never the charge, and the real amount lives in the
  // `payments` rows that /payments reads. Do not re-add a price here to "complete" the type —
  // a screen that has the number will eventually print it.
  run: null | {
    actualKm: number; durationSec: number; paceSecPerKm: number | null;
    endReason: string | null; conditionNote: string | null; photos: string[];
    events: { kind: string; at: string }[];
    trace: { lat: number; lng: number; t: number }[];
  };
}

export async function fetchRunReport(bookingId: string): Promise<RunReport> {
  const { data, error } = await supabase
    .from('bookings')
    .select('scheduled_at, km, pace_label, status, runner_id, route_id, routes!bookings_route_id_fkey(name, area), dogs(name), runners(profiles(name)), runs(actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note, photos, events, trace)')
    .eq('id', bookingId)
    .single();
  if (error) throw error;
  const d = data as any;
  const { dateLabel, timeLabel } = kstParts(d.scheduled_at);
  const raw = Array.isArray(d.runs) ? d.runs[0] : d.runs; // unique FK — 어느 형태든 안전하게
  return {
    dogName: d.dogs?.name ?? '반려견',
    routeName: d.routes?.name ?? '코스 미지정',
    routeArea: d.routes?.area ?? '',
    when: `${dateLabel} ${timeLabel}`,
    runnerName: d.runners?.profiles?.name ?? null,
    runnerProfileId: d.runner_id ?? null,
    routeId: d.route_id ?? null,
    plannedKm: Number(d.km),
    paceLabel: d.pace_label ?? "보통 7'",
    status: d.status,
    run: raw
      ? {
          actualKm: Number(raw.actual_km ?? 0),
          durationSec: raw.duration_sec ?? 0,
          paceSecPerKm: raw.avg_pace_sec_per_km,
          endReason: raw.end_reason,
          conditionNote: raw.condition_note,
          photos: raw.photos ?? [],
          events: raw.events ?? [],
          trace: raw.trace ?? [],
        }
      : null,
  };
}

// 미읽음 알림 수 — 벨 도트의 실근거. head:true라 행은 안 실어오고 count만 받는다.
// RLS가 내 알림으로 자기 범위화 + read_at IS NULL 부분 인덱스가 서빙.
export async function fetchUnreadCount(): Promise<number> {
  const { count, error } = await supabase
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .is('read_at', null);
  if (error) throw error;
  return count ?? 0;
}

export async function markAllNotificationsRead(): Promise<void> {
  const { error } = await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .is('read_at', null);
  if (error) throw error;
}

// 예약의 routeId는 서버 route_id 그대로 — 코스 미지정이면 null (목업 'seoulforest-loop' 박제 제거).
export async function fetchMyBookings(): Promise<Booking[]> {  // [리뷰 F11] Booking.routeId가 이미 string | null — Omit 잔재 정리
  const { data: user } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('bookings')
    // club_session_id: 클럽 위탁 예약을 화면이 구분하기 위한 것 — 마켓플레이스 취소 사다리
    // (0066)가 적용되지 않는 예약이라 취소 버튼이 클럽 출구로 가야 한다 (cancel_owner가 거부)
    .select('id, scheduled_at, km, pace_label, total_price, status, runner_id, owner_id, series_id, route_id, club_session_id, routes!bookings_route_id_fkey(name), dogs(name, collar), runners(profiles(name))')
    // 결제 미완 유령(draft/quoted/payment_hold)은 일정이 아니다 — '매칭 중'으로 위장 금지
    .not('status', 'in', '(draft,quoted,payment_hold)')
    // 듀얼 롤 계정에서 러너로 받은 예약이 '내 일정'에 섞이던 문제 — 보호자 소유만
    .eq('owner_id', user.user?.id ?? '')
    .order('scheduled_at', { ascending: false })
    .limit(20);
  if (error) throw error;

  return (data ?? []).map((r: any) => {
    const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
    const routeName = r.routes?.name ?? '코스 미지정';
    return {
      id: r.id,
      dateLabel,
      timeLabel,
      scheduledAt: r.scheduled_at, // 원본 ISO — D-day·정렬용 (라벨은 위 kstParts 산출물)
      dogName: r.dogs?.name ?? '반려견',
      dogCollar: r.dogs?.collar ?? null, // 칼라 컬러 (0033)
      runnerId: r.runner_id ?? '', // 실 러너 uuid (매칭 전 ''). 목업 상수 'minjun' 박제 제거 — 가짜 데이터 금지
      runnerName: r.runner_id ? (r.runners?.profiles?.name ?? '러너') : '매칭 중',
      routeId: r.route_id ?? null, // 실 코스 uuid (미지정이면 null)
      routeName,
      km: Number(r.km),
      paceLabel: r.pace_label ?? "보통 7'",
      price: r.total_price,
      status: STATUS_MAP[r.status] ?? 'pending',
      rawStatus: r.status, // 서버 원상태 — 표시 어휘(6종)가 뭉갠 구분(runner_enroute 등)을 게이트가 쓴다
      recurring: !!r.series_id, // ⟳ 매주 필 실화 (0026)
      seriesId: r.series_id ?? null,
      live: true,
      matched: !!r.runner_id,
      runnerProfileId: r.runner_id ?? null,
      clubSessionId: r.club_session_id ?? null,
    };
  });
}

// ---------- 클럽 수요 보드 (0032, P-B) — 듀얼: 러너 티켓·스트립 + 보호자 진행 링·동네 리그 ----------
export interface DemandMine {
  clubId: string; name: string; district: string; status: 'collecting' | 'active';
  interestCount: number; threshold: number; myInterest: boolean; isHost: boolean;
}
export interface LeagueRow {
  clubId: string; name: string; district: string; status: 'collecting' | 'active';
  sessionsMonth: number; teamsMonth: number; interestCount: number; mine: boolean;
}
export interface DemandBoard { district: string; mine: DemandMine | null; league: LeagueRow[] }

export async function fetchClubDemandBoard(): Promise<DemandBoard> {
  const { data, error } = await supabase.rpc('club_demand_board');
  if (error) throw error;
  return (data ?? { district: '', mine: null, league: [] }) as DemandBoard;
}

// ---------- 클럽 정기 시리즈 (0035, P-B) — 매주 반복 자동 개설 ----------
export interface ClubSeries { id: string; weekday: number; time: string; status: string; meetupPoint: string | null; isHost: boolean }
export async function fetchClubSeries(clubId: string): Promise<ClubSeries[]> {
  const { data, error } = await supabase.rpc('club_series_of', { p_club: clubId });
  if (error) throw error;
  return (data ?? []) as ClubSeries[];
}
// [감사 P1] p_route·p_format 미전달로 자동 생성 세션이 전부 owner_only·무코스가 되던 결함 — 첫 세션과 동일하게 전파
export const startClubSeries = (
  clubId: string, weekday: number, time: string, meetup: string, capacity = 12,
  routeId: string | null = null, format: 'owner_only' | 'delegated_only' | 'mixed' = 'owner_only',
) =>
  clubRpc('club_series_start', {
    p_club: clubId, p_weekday: weekday, p_time: time, p_meetup: meetup, p_capacity: capacity,
    p_route: routeId, p_format: format,
  }) as Promise<string>;
export const pauseClubSeries = (seriesId: string) =>
  clubRpc('club_series_pause', { p_series: seriesId }) as Promise<void>;

// ---------- owner Live Activity token registration (0063) ----------
// The ActivityKit push token is PER-ACTIVITY (one lock-screen banner instance), not per-device —
// a different animal from the Expo token in push.ts/push_tokens (0024). Registered so the 0063
// server pipeline (trace trigger · stale sweep · completion trigger) can drive the owner's lock
// screen over APNs while the app is suspended. Called only by ownerActivity.ts.
export async function ownerLaRegister(
  bookingId: string, activityId: string, token: string, env: 'development' | 'production',
): Promise<void> {
  const { error } = await supabase.rpc('owner_la_register', {
    p_booking: bookingId, p_activity_id: activityId, p_token: token, p_env: env,
  });
  if (error) throw error;
}

export async function ownerLaUnregister(bookingId: string): Promise<void> {
  const { error } = await supabase.rpc('owner_la_unregister', { p_booking: bookingId });
  if (error) throw error;
}
