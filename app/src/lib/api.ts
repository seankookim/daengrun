// Live API layer — replaces store.ts mocks screen by screen.
// Pattern: fetch → map to the app's existing types → screens fall back to mock on failure.
import { FunctionsHttpError } from '@supabase/supabase-js';
import { AddonKey, Booking, BookingStatus, dog as mockDog, lastRunTrace, RouteInfo, sampleRoutes, TracePoint } from '../store';
import { supabase } from './supabase';

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
  trace: TracePoint[] | null;
  checked_at: string | null;
}

function fmtChecked(dateStr: string | null): string {
  if (!dateStr) return '점검 예정';
  const d = new Date(dateStr);
  return `${d.getMonth() + 1}.${d.getDate()} 점검`;
}

// 서버 코스 → 앱 RouteInfo. 트레이스가 비면 목업 트레이스 재사용 (실좌표는 Phase 3).
export async function fetchRoutes(): Promise<RouteInfo[]> {
  const { data, error } = await supabase
    .from('routes')
    .select('id,name,area,km,terrain,tags,features,trace,checked_at')
    .eq('active', true)
    .order('km');
  if (error) throw error;

  return (data as RouteRow[]).map((r) => {
    const mockTwin = sampleRoutes.find((m) => m.name === r.name);
    return {
      id: r.id,
      name: r.name,
      area: r.area,
      km: Number(r.km),
      terrain: r.terrain ?? '',
      tags: r.tags ?? [],
      features: r.features ?? [],
      fit: mockTwin?.fit ?? 80, // 적합도 계산은 매칭 엔진 몫 (Phase 3)
      checkedAt: fmtChecked(r.checked_at),
      desc: mockTwin?.desc ?? `${r.area}의 안심 코스`,
      trace: r.trace && r.trace.length > 0 ? r.trace : mockTwin?.trace ?? lastRunTrace,
    };
  });
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

// ---------- dogs ----------
// 유저의 첫 반려견 확보 (없으면 목업 초코 프로필로 생성 — 실 프로필 위저드는 후속)
export async function ensureDog(): Promise<string> {
  const { data: existing, error } = await supabase.from('dogs').select('id').limit(1);
  if (error) throw error;
  if (existing && existing.length > 0) return existing[0].id;

  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const { data: created, error: cErr } = await supabase.from('dogs').insert({
    owner_id: user.user.id,
    name: mockDog.name,
    breed: mockDog.breed,
    weight_kg: mockDog.weightKg,
    memo: mockDog.memo,
    weekly_goal_km: mockDog.weeklyGoalKm,
    // fitness_age 시드 금지 — 생일 없이 목업 1.8살이 실측처럼 표시되던 정직성 버그
  }).select('id').single();
  if (cErr) throw cErr;
  return created.id;
}

// ---------- dog profile (실초코) ----------
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
  };
}

const DOG_SELECT = 'id, name, breed, birth_date, weight_kg, neutered, memo, preferences, vaccinations, photo_url, weekly_goal_km';

// 다견 가구 지원 — 전체 목록
export async function fetchMyDogs(): Promise<DogProfile[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data } = await supabase.from('dogs').select(DOG_SELECT)
    .eq('owner_id', user.user.id).order('created_at', { ascending: true });
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
}): Promise<void> {
  const { prefTags, vaccines, ...rest } = p;
  const patch: Record<string, unknown> = { ...rest };
  if (prefTags) patch.preferences = { tags: prefTags };
  if (vaccines) patch.vaccinations = vaccines.map((type) => ({ type, at: null }));
  const { error } = await supabase.from('dogs').update(patch).eq('id', dogId);
  if (error) throw error;
}

export async function uploadDogPhoto(dogId: string, base64: string): Promise<string> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/dogs/${dogId}.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg', upsert: true });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  const url = `${pub.publicUrl}?v=${Date.now()}`;
  const { error: e2 } = await supabase.from('dogs').update({ photo_url: url }).eq('id', dogId);
  if (e2) throw e2;
  return url;
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
}): Promise<HoldResult> {
  const { data, error } = await supabase.functions.invoke('create-booking-hold', { body: p });
  if (error || data?.error) throw await fnError(error, data);
  return data as HoldResult;
}

export async function confirmPayment(bookingId: string): Promise<void> {
  const { data, error } = await supabase.functions.invoke('transition-booking', {
    body: { booking_id: bookingId, action: 'payment_ok' },
  });
  if (error) throw error;
  if (data?.error) throw new Error(data.error);
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

function kstParts(iso: string) {
  const d = new Date(iso);
  const dateLabel = `${d.getMonth() + 1}월 ${d.getDate()}일 (${DAYS[d.getDay()]})`;
  const h = d.getHours();
  const timeLabel = `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${String(d.getMinutes()).padStart(2, '0')}`;
  return { dateLabel, timeLabel };
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
};

// ---------- runner side ----------
// 러너 행 확보 — 루프 테스트용으로 즉시 'certified' (실 퍼널은 /runner/apply가 대체 예정)
export async function ensureRunner(): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const uid = user.user.id;

  const { data: existing } = await supabase.from('runners').select('profile_id').eq('profile_id', uid).maybeSingle();
  if (existing) return;

  const { error } = await supabase.from('runners').insert({
    profile_id: uid,
    tier: 'certified',
    funnel_step: 'certified',
    avg_pace_sec_per_km: 420,
    identity_verified: true, // TODO: 실 KYC 후 false 기본으로
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
  payout: number; // 수수료 20% 제외 추정
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
    payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)), // 티어 실수수료 (일괄 20% 은퇴)
    directed,
    photoUrl: r.dogs?.photo_url ?? null,
    prefTags: (r.dogs?.preferences as any)?.tags ?? [],
    vaccines: ((r.dogs?.vaccinations as any[]) ?? []).map((v) => v.type),
    routeId: r.route_id ?? null,
    routeName: r.routes?.name ?? null,
  };
}

const REQ_SELECT = 'id, scheduled_at, km, pace_label, base_fare, distance_fare, addon_fare, route_id, routes(name), dogs(id, name, breed, weight_kg, memo, photo_url, preferences, vaccinations)';

// 러너 인박스: 지명 요청(runner_pending, 나에게) + 오픈 요청(matching, 미배정)
// + 단골 감지: 함께 완주한 이력이 있는 강아지엔 repeatPrior (수락 결정이 쉬워진다)
// 내 수수료율 — 견적용 (티어: 인증 20% / 베테랑 18% / 마스터 15%). 세션 캐시.
let _commissionRate: number | null = null;
async function myCommissionRate(): Promise<number> {
  if (_commissionRate != null) return _commissionRate;
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return 0.2;
  const { data } = await supabase.from('runners').select('commission_rate').eq('profile_id', user.user.id).maybeSingle();
  _commissionRate = Number(data?.commission_rate ?? 0.2);
  return _commissionRate;
}

export async function fetchRunnerInbox(): Promise<OpenRequest[]> {
  const rate = await myCommissionRate();
  const { data: user } = await supabase.auth.getUser();
  const [openRes, directedRes] = await Promise.all([
    supabase.from('bookings').select(REQ_SELECT).eq('status', 'matching').is('runner_id', null).order('scheduled_at').limit(10),
    user.user
      ? supabase.from('bookings').select(REQ_SELECT).eq('status', 'runner_pending').eq('runner_id', user.user.id).order('scheduled_at').limit(10)
      : Promise.resolve({ data: [], error: null } as any),
  ]);
  if (openRes.error) throw openRes.error;
  const directed = (directedRes.data ?? []).map((r: any) => mapOpenRequest(r, true, rate));
  const open = (openRes.data ?? []).map((r: any) => mapOpenRequest(r, false, rate));
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
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, pace_label, base_fare, distance_fare, addon_fare, route_id, routes(name), dogs(name, breed, weight_kg, memo)')
    .eq('status', 'matching')
    .is('runner_id', null)
    .order('scheduled_at')
    .limit(10);
  if (error) throw error;
  return (data ?? []).map((r: any) => {
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
      payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)), // 티어 실수수료 (일괄 20% 은퇴)
      photoUrl: r.dogs?.photo_url ?? null,
      prefTags: (r.dogs?.preferences as any)?.tags ?? [],
      vaccines: [] as string[],
      routeId: r.route_id ?? null,
      routeName: r.routes?.name ?? null,
    };
  });
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

// 예약 상세 (인계 동기화용): 상태 + 양측 확인 타임스탬프
export interface BookingSync {
  status: string;
  ownerConfirmed: boolean;
  runnerConfirmed: boolean;
}
export async function fetchBookingSync(id: string): Promise<BookingSync> {
  const { data, error } = await supabase
    .from('bookings')
    .select('status, owner_confirmed_handoff_at, runner_confirmed_handoff_at')
    .eq('id', id)
    .single();
  if (error) throw error;
  return {
    status: data.status,
    ownerConfirmed: !!data.owner_confirmed_handoff_at,
    runnerConfirmed: !!data.runner_confirmed_handoff_at,
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
  const { data } = await supabase.from('bookings').select('id, status, scheduled_at')
    .eq('owner_id', user.user.id).in('status', IN_FLIGHT);
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
// 취소 — 서버가 수수료(24h 전 무료/이후 10%) 계산·상태 전이. { cancel_fee, refund } 반환
export const cancelBooking = (id: string): Promise<{ cancel_fee: number; refund: number }> =>
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
  return (data ?? []).map((r: any) => {
    const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
    return {
      bookingId: r.id,
      when: `${dateLabel} ${timeLabel}`,
      dogName: r.dogs?.name ?? '반려견',
      km: Number(r.km),
      payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * (1 - rate)), // 티어 실수수료 (일괄 20% 은퇴)
      status: r.status === 'completed' ? 'completed' : r.status === 'confirmed' ? 'confirmed' : 'in_progress',
      rawStatus: r.status,
      routeId: r.route_id ?? null,
    };
  });
}

// ---------- 코스 패치 (2026-07-28 확정) — 파생 데이터, 마이그레이션 0 ----------
// 사다리: ×1 획득 → ×5 실버 → ×10 골드 → ×25 코스 마스터 (드랍 5/10 리듬과 동기).
// v1은 순수 코스메틱 — 골드/마스터 포인트 보너스는 v2 서버(settle-run) 몫.
export type PatchGrade = 'basic' | 'silver' | 'gold' | 'master';
export const patchGrade = (n: number): PatchGrade =>
  n >= 25 ? 'master' : n >= 10 ? 'gold' : n >= 5 ? 'silver' : 'basic';
export interface CoursePatch { routeId: string; name: string; km: number; count: number; grade: PatchGrade; firstAt: string | null }

// 내(보호자든 러너든 당사자) 완료 러닝을 코스별로 집계 — locked는 아직 못 달린 활성 코스
export async function fetchCoursePatches(): Promise<{ earned: CoursePatch[]; locked: { routeId: string; name: string; km: number }[] }> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return { earned: [], locked: [] };
  const uid = user.user.id;
  const [bkRes, rtRes] = await Promise.all([
    supabase.from('bookings').select('route_id, scheduled_at')
      .eq('status', 'completed').not('route_id', 'is', null)
      .or(`owner_id.eq.${uid},runner_id.eq.${uid}`)
      .order('scheduled_at').limit(1000),
    supabase.from('routes').select('id, name, km').eq('active', true),
  ]);
  if (bkRes.error) throw bkRes.error;
  const counts: Record<string, { n: number; first: string }> = {};
  (bkRes.data ?? []).forEach((b: any) => {
    const c = (counts[b.route_id] ??= { n: 0, first: b.scheduled_at });
    c.n += 1;
  });
  const earned: CoursePatch[] = [];
  const locked: { routeId: string; name: string; km: number }[] = [];
  (rtRes.data ?? []).forEach((r: any) => {
    const c = counts[r.id];
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

// 패치 획득/승급 팝 — 이 예약이 그 코스의 '최신 완주'이고 누적이 임계(1/5/10/25)에 방금 도달했을 때만.
// 앱 세션당 예약별 1회 (인메모리 — 과거 리포트 재방문 시 반복 팝 방지)
const _patchPopSeen = new Set<string>();
export async function fetchPatchPop(bookingId: string, routeId: string): Promise<CoursePatch | null> {
  if (_patchPopSeen.has(bookingId)) return null;
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const uid = user.user.id;
  const { data, error } = await supabase.from('bookings').select('id')
    .eq('route_id', routeId).eq('status', 'completed')
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

export const runnerEnroute = (id: string) => invokeTransition(id, 'enroute');

// ---------- profile (identity layer) ----------
export interface MyProfile { id: string; name: string | null; district: string | null; avatarUrl: string | null; email: string | null }

export async function fetchMyProfile(): Promise<MyProfile | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('profiles').select('name, district, avatar_url').eq('id', user.user.id).maybeSingle();
  return {
    id: user.user.id,
    name: data?.name ?? user.user.email?.split('@')[0] ?? null,
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

// 러너 홈 상태 — 실누적/온라인/티어 (드랍 트레일·온라인 토글·티어 진행바의 진실)
export interface MyRunnerStatus { totalRuns: number; totalKm: number; online: boolean; tier: string }

export async function fetchMyRunnerStatus(): Promise<MyRunnerStatus> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return { totalRuns: 0, totalKm: 0, online: false, tier: 'certified' };
  const { data } = await supabase.from('runners')
    .select('total_runs, total_km, online, tier').eq('profile_id', user.user.id).maybeSingle();
  return {
    totalRuns: data?.total_runs ?? 0,
    totalKm: Number(data?.total_km ?? 0),
    online: !!data?.online,
    tier: data?.tier ?? 'certified',
  };
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
  km: number;
  paceLabel: string;
  when: string;
}

export async function fetchMeetupInfo(bookingId: string): Promise<MeetupInfo> {
  const { data, error } = await supabase
    .from('bookings')
    .select('scheduled_at, km, pace_label, routes(name), dogs(name, breed, weight_kg, memo, photo_url), runners(profiles(name))')
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
    km: Number(d.km),
    paceLabel: d.pace_label ?? "보통 7'",
    when: `${dateLabel} ${timeLabel}`,
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

// 러닝 사진 업로드 (러너, 종료 후) — runs.photos + avatars 버킷 {uid}/runs/{booking}/*
export async function uploadRunPhoto(bookingId: string, base64: string): Promise<string[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/runs/${bookingId}/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  // 원자 append (0018) — RMW 레이스 제거, 서버가 최신 photos 배열을 반환
  const { data: photos, error: e2 } = await supabase.rpc('append_run_photo', {
    p_booking: bookingId, p_url: pub.publicUrl,
  });
  if (e2) throw e2;
  return (photos as string[] | null) ?? [];
}

// ---------- 러닝 이벤트 (응가 도장 등) — 러너 원탭 → 기록 + 보호자 즉시 알림 ----------
export type RunEventKind = 'poop' | 'snack' | 'water' | 'photo';

const EVENT_NOTI: Record<RunEventKind, (dog: string) => [string, string]> = {
  poop: (d) => ['응가 완료 💩', `${d} 응가 성공! 러너가 응가 도장을 찍었어요`],
  snack: (d) => ['간식 타임 🍖', `${d}가 간식을 맛있게 먹었어요`],
  water: (d) => ['수분 보충 💧', `${d}가 물을 마시고 있어요`],
  photo: (d) => ['새 사진 도착 📷', `${d}의 러닝 사진이 추가됐어요 — 리포트에서 확인하세요`],
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
    title: `${km}km 돌파 🏃`, body: `${dog}가 ${km}km를 달렸어요 — 실시간 지도에서 확인하세요`,
    ref_id: bookingId,
  });
}

// 러닝 트레이스 저장 (정산 후 러너가 기록 — runs runner update RLS)
export async function saveRunTrace(bookingId: string, trace: { lat: number; lng: number; t: number }[]): Promise<void> {
  const { error } = await supabase.from('runs').update({ trace }).eq('booking_id', bookingId);
  if (error) throw error;
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
export const GEAR_META: Record<GearKind, { glyph: string; name: string; hint: string }> = {
  leash: { glyph: '🦮', name: '리드줄', hint: '러닝 전용 리드줄' },
  apparel: { glyph: '🎽', name: '러닝 장비', hint: '러닝복 · 러닝화' },
  water: { glyph: '💧', name: '급수', hint: '아이용 물병 · 급수기' },
  treats: { glyph: '🦴', name: '간식', hint: '보상용 간식 파우치' },
  bodycam: { glyph: '📹', name: '바디캠', hint: '러닝 중 영상 기록' },
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
    supabase.from('dogs').select('id, name, weekly_goal_km, fitness_age, birth_date, photo_url').eq('owner_id', user.user.id).limit(1),
    supabase.from('bookings')
      .select('id, scheduled_at, runs(actual_km, duration_sec)')
      .eq('owner_id', user.user.id).eq('status', 'completed')
      .order('scheduled_at', { ascending: false }).limit(120),
  ]);
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
  if (!d?.birth_date) {
    fitnessGate = { reason: 'birth' };
  } else if (recent28.length < 2) {
    fitnessGate = { reason: 'runs', left: 2 - recent28.length };
  } else {
    const ageYears = (now - new Date(d.birth_date).getTime()) / (365.25 * 86400_000);
    if (ageYears > 0 && ageYears <= 25) { // 미래/비정상 생일은 측정 불가
      const last28Km = recent28.reduce((s, r) => s + r.km, 0);
      const goal = Number(d.weekly_goal_km ?? 15);
      const ratio = goal > 0 ? Math.min(last28Km / 4 / goal, 1.5) : 0;
      const calc = Math.max(0.5, Math.round((ageYears - 1.8 * ratio - 0.05 * Math.min(streakDays, 14)) * 10) / 10);
      fitnessAge = calc;
      if (d.fitness_age == null || Math.abs(Number(d.fitness_age) - calc) >= 0.1) {
        supabase.from('dogs').update({ fitness_age: calc }).eq('id', d.id).then(() => {}, () => {});
      }
    } else {
      fitnessGate = { reason: 'birth' }; // 비정상 생일도 생일 문제로 안내
    }
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
  let km = 0;
  const ids = rows.map((l: any) => l.booking_id);
  if (ids.length > 0) {
    const { data: runsD } = await supabase.from('runs').select('actual_km').in('booking_id', ids);
    km = (runsD ?? []).reduce((s, r: any) => s + Number(r.actual_km ?? 0), 0);
  }
  return { net, runs: rows.length, km: Math.round(km * 10) / 10 };
}

// 정산 예정 누적 — 원장 전체 net 합 (표시 리스트 30행 캡과 분리; 30행 합이 '정산 예정'으로 보이던 버그)
export async function fetchLedgerTotal(): Promise<number> {
  const { data, error } = await supabase
    .from('ledger_items')
    .select('base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee')
    .limit(2000); // 파일럿 상한 — 실서비스 전 서버 집계로 (백로그)
  if (error) throw error;
  return (data ?? []).reduce((s2, l: any) =>
    s2 + l.base + l.distance_pay + l.addon_pay + l.tip + (l.remaining_guarantee ?? 0) - l.platform_fee, 0);
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

// 사진 메시지 — avatars 버킷 {uid}/chat/{thread}/* + kind 'photo'
export async function sendChatPhoto(threadId: string, base64: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const path = `${user.user.id}/chat/${threadId}/${Date.now()}.jpg`;
  const { error } = await supabase.storage.from('avatars')
    .upload(path, b64ToBytes(base64), { contentType: 'image/jpeg' });
  if (error) throw error;
  const { data: pub } = supabase.storage.from('avatars').getPublicUrl(path);
  const { error: e2 } = await supabase.from('chat_messages').insert({
    thread_id: threadId, sender_id: user.user.id, kind: 'photo', media_path: pub.publicUrl, body: null,
  });
  if (e2) throw e2;
}

// 새 메시지 실시간 구독 — 해제 함수 반환
export function subscribeMessages(threadId: string, uid: string | null, onMsg: (m: ChatMsg) => void): () => void {
  const ch = supabase
    .channel(`chat-${threadId}`)
    .on('postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `thread_id=eq.${threadId}` },
      (payload) => onMsg(mapMsg(payload.new, uid)))
    .subscribe();
  return () => { supabase.removeChannel(ch); };
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
  const ch = supabase
    .channel(`bk-${bookingId}`)
    .on('postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'bookings', filter: `id=eq.${bookingId}` },
      () => onChange())
    .subscribe();
  return () => { supabase.removeChannel(ch); };
}

// 채팅 컨텍스트 — 상대 이름 + 예약 라벨
export interface ChatContext { threadId: string; peerName: string; label: string }

export async function openChatForBooking(bookingId: string): Promise<ChatContext> {
  const { data: user } = await supabase.auth.getUser();
  const uid = user.user?.id;
  const { data: bk, error } = await supabase
    .from('bookings')
    .select('owner_id, runner_id, scheduled_at, km, dogs(name), routes(name)')
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
    label: `${dateLabel} ${timeLabel} · ${b.dogs?.name ?? '반려견'} · ${b.routes?.name ?? '코스 미지정'} ${b.km}km`,
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
    title: '🚨 SOS', body: '상대방이 긴급 도움을 요청했어요 — 즉시 연락해주세요',
    ref_id: bookingId,
  });
  if (error) throw error;
  return bookingId;
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

export interface GearClaim { id: string; item: string; milestone: number; status: string }

export async function fetchGearClaims(): Promise<GearClaim[]> {
  const { data, error } = await supabase.from('gear_claims').select('id, item, milestone, status').order('milestone');
  if (error) throw error;
  return data ?? [];
}

// ---------- 주소 (픽업 장소) ----------
export interface Addr { id: string; label: string; addr: string; detail: string | null; isDefault: boolean }

export async function fetchAddresses(): Promise<Addr[]> {
  const { data, error } = await supabase.from('addresses')
    .select('id, label, addr, detail, is_default').order('created_at');
  if (error) throw error;
  return (data ?? []).map((a: any) => ({ id: a.id, label: a.label, addr: a.addr, detail: a.detail, isDefault: a.is_default }));
}

export async function addAddress(p: { label: string; addr: string; detail?: string }): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const existing = await fetchAddresses();
  const { error } = await supabase.from('addresses').insert({
    owner_id: user.user.id, label: p.label, addr: p.addr, detail: p.detail ?? null,
    is_default: existing.length === 0, // 첫 주소 자동 기본
  });
  if (error) throw error;
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

// ---------- 동네 피드 (옵트인 러닝 자랑) ----------
export interface FeedPost {
  id: string;
  authorName: string;
  authorAvatar: string | null;
  body: string | null;
  photoUrl: string | null;
  meta: { dogName?: string; km?: number; durationSec?: number; badges?: string[] };
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

export async function shareRunToFeed(bookingId: string, body?: string): Promise<void> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) throw new Error('not signed in');
  const report = await fetchRunReport(bookingId);
  if (!report.run) throw new Error('완료된 러닝만 공유할 수 있어요');
  const standings = await fetchRunStandings(bookingId).catch(() => null);
  const badges: string[] = [];
  if (standings && standings.total > 1) {
    if (standings.kmRank === 1) badges.push('🏆 역대 최장 거리');
    if (standings.paceRank === 1) badges.push('⚡ 역대 최고 페이스');
  }
  const { error } = await supabase.from('feed_posts').insert({
    author_id: user.user.id,
    booking_id: bookingId,
    body: body ?? null,
    photo_url: report.run.photos[0] ?? null,
    meta: { dogName: report.dogName, km: report.run.actualKm, durationSec: report.run.durationSec, badges },
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
    .select('id, author_id, body, photo_url, meta, created_at, profiles!feed_posts_author_id_fkey(name, avatar_url), feed_likes(profile_id), feed_comments(count)')
    .order('created_at', { ascending: false })
    .limit(30);
  if (error) throw error;
  return (data ?? []).map((p: any) => {
    const { dateLabel, timeLabel } = kstParts(p.created_at);
    const likes: { profile_id: string }[] = p.feed_likes ?? [];
    return {
      id: p.id,
      authorName: p.profiles?.name ?? '이웃',
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

// ---------- 하이 포인트 + 리더보드 (통합 인센티브 경제) ----------
export interface MilesInfo { balance: number; recent: { delta: number; reason: string; when: string }[] }

const MILE_REASON: Record<string, string> = {
  run_complete: '러닝 완주', poop_bonus: '응가 도장 보너스', drop: '드랍 보상', shop_spend: '샵 사용',
};

export async function fetchMiles(): Promise<MilesInfo> {
  // 잔액 = 원장 전체 합 (최근 50행 합은 오래된 적립이 창밖으로 밀리면 잔액이 줄어드는 가짜)
  const { data, error } = await supabase
    .from('miles_ledger')
    .select('delta, reason, created_at')
    .order('created_at', { ascending: false })
    .limit(2000); // 파일럿 규모 상한 — 실서비스 전 서버 집계 RPC로 교체 (백로그)
  if (error) throw error;
  const rows = data ?? [];
  return {
    balance: rows.reduce((s, r: any) => s + r.delta, 0),
    recent: rows.slice(0, 10).map((r: any) => {
      const { dateLabel } = kstParts(r.created_at);
      return { delta: r.delta, reason: MILE_REASON[r.reason] ?? r.reason, when: dateLabel };
    }),
  };
}

export interface BoardRow { name: string; photoUrl: string | null; km: number; runs: number }

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
export interface LiveNoti { id: string; title: string; body: string | null; when: string; unread: boolean; kind: string; refId: string | null }

export async function fetchNotifications(): Promise<LiveNoti[]> {
  const { data, error } = await supabase
    .from('notifications')
    .select('id, title, body, created_at, read_at, kind, ref_id')
    .order('created_at', { ascending: false })
    .limit(20);
  if (error) throw error;
  return (data ?? []).map((n: any) => {
    const { dateLabel, timeLabel } = kstParts(n.created_at);
    return { id: n.id, title: n.title, body: n.body, when: `${dateLabel} ${timeLabel}`, unread: !n.read_at, kind: n.kind, refId: n.ref_id };
  });
}

// ---------- 러닝 리포트 (보호자) ----------
export interface RunReport {
  dogName: string; routeName: string; routeArea: string; when: string;
  runnerName: string | null;
  runnerProfileId: string | null;
  routeId: string | null;
  plannedKm: number; paceLabel: string; price: number; status: string;
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
    .select('scheduled_at, km, pace_label, total_price, status, runner_id, route_id, routes(name, area), dogs(name), runners(profiles(name)), runs(actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note, photos, events, trace)')
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
    price: d.total_price,
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

export async function markAllNotificationsRead(): Promise<void> {
  const { error } = await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .is('read_at', null);
  if (error) throw error;
}

export async function fetchMyBookings(): Promise<Booking[]> {
  const { data: user } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, pace_label, total_price, status, runner_id, owner_id, routes(name), dogs(name), runners(profiles(name))')
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
    const mockTwin = sampleRoutes.find((m) => m.name === routeName);
    return {
      id: r.id,
      dateLabel,
      timeLabel,
      dogName: r.dogs?.name ?? '반려견',
      runnerId: 'minjun', // sheet mock-lookup용 (live는 sheet에서 별도 처리)
      runnerName: r.runner_id ? (r.runners?.profiles?.name ?? '러너') : '매칭 중',
      routeId: mockTwin?.id ?? 'seoulforest-loop',
      routeName,
      km: Number(r.km),
      paceLabel: r.pace_label ?? "보통 7'",
      price: r.total_price,
      status: STATUS_MAP[r.status] ?? 'pending',
      live: true,
      matched: !!r.runner_id,
      runnerProfileId: r.runner_id ?? null,
    };
  });
}
