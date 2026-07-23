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
    fitness_age: mockDog.fitnessAge,
  }).select('id').single();
  if (cErr) throw cErr;
  return created.id;
}

// ---------- bookings (edge functions) ----------
export interface HoldResult { booking_id: string; hold_expires_at: string; total_price: number }

export async function createBookingHold(p: {
  dog_id: string;
  route_id?: string;
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
  dogName: string;
  breed: string;
  weightKg: number;
  memo: string | null;
  when: string;
  km: number;
  paceLabel: string;
  payout: number; // 수수료 20% 제외 추정
  directed?: boolean; // 지명 요청 여부
}

function mapOpenRequest(r: any, directed: boolean): OpenRequest {
  const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
  return {
    bookingId: r.id,
    dogName: r.dogs?.name ?? '반려견',
    breed: r.dogs?.breed ?? '',
    weightKg: Number(r.dogs?.weight_kg ?? 0),
    memo: r.dogs?.memo ?? null,
    when: `${dateLabel} ${timeLabel}`,
    km: Number(r.km),
    paceLabel: r.pace_label ?? "보통 7'",
    payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * 0.8),
    directed,
  };
}

const REQ_SELECT = 'id, scheduled_at, km, pace_label, base_fare, distance_fare, addon_fare, dogs(name, breed, weight_kg, memo)';

// 러너 인박스: 지명 요청(runner_pending, 나에게) + 오픈 요청(matching, 미배정)
export async function fetchRunnerInbox(): Promise<OpenRequest[]> {
  const { data: user } = await supabase.auth.getUser();
  const [openRes, directedRes] = await Promise.all([
    supabase.from('bookings').select(REQ_SELECT).eq('status', 'matching').is('runner_id', null).order('scheduled_at').limit(10),
    user.user
      ? supabase.from('bookings').select(REQ_SELECT).eq('status', 'runner_pending').eq('runner_id', user.user.id).order('scheduled_at').limit(10)
      : Promise.resolve({ data: [], error: null } as any),
  ]);
  if (openRes.error) throw openRes.error;
  const directed = (directedRes.data ?? []).map((r: any) => mapOpenRequest(r, true));
  const open = (openRes.data ?? []).map((r: any) => mapOpenRequest(r, false));
  return [...directed, ...open];
}

export async function fetchOpenRequests(): Promise<OpenRequest[]> {
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, pace_label, base_fare, distance_fare, addon_fare, dogs(name, breed, weight_kg, memo)')
    .eq('status', 'matching')
    .is('runner_id', null)
    .order('scheduled_at')
    .limit(10);
  if (error) throw error;
  return (data ?? []).map((r: any) => {
    const { dateLabel, timeLabel } = kstParts(r.scheduled_at);
    return {
      bookingId: r.id,
      dogName: r.dogs?.name ?? '반려견',
      breed: r.dogs?.breed ?? '',
      weightKg: Number(r.dogs?.weight_kg ?? 0),
      memo: r.dogs?.memo ?? null,
      when: `${dateLabel} ${timeLabel}`,
      km: Number(r.km),
      paceLabel: r.pace_label ?? "보통 7'",
      payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * 0.8),
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
}

export async function fetchCertifiedRunners(): Promise<LiveRunner[]> {
  const { data, error } = await supabase
    .from('runners')
    .select('profile_id, tier, avg_pace_sec_per_km, total_runs, respond_rate_pct, profiles(name, district)')
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

export async function fetchCurrentOwnerBookingId(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('bookings').select('id')
    .eq('owner_id', user.user.id).in('status', IN_FLIGHT)
    .order('scheduled_at', { ascending: false }).limit(1);
  return data?.[0]?.id ?? null;
}

export async function fetchCurrentRunnerJobId(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('bookings').select('id')
    .eq('runner_id', user.user.id).in('status', IN_FLIGHT)
    .order('scheduled_at', { ascending: false }).limit(1);
  return data?.[0]?.id ?? null;
}

export const acceptBooking = (id: string) => invokeTransition(id, 'runner_accept');
// side 필수 — 한 계정이 양측인 솔로 테스트에서 서버가 역할을 추측할 수 없음
export const confirmHandoff = (id: string, side: 'owner' | 'runner') =>
  invokeTransition(id, 'confirm_handoff', { side });
export const startRunServer = (id: string) => invokeTransition(id, 'start_run');

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
}

export async function fetchRunnerJobs(): Promise<RunnerJob[]> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return [];
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, base_fare, distance_fare, addon_fare, status, dogs(name)')
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
      payout: Math.round((r.base_fare + r.distance_fare + r.addon_fare) * 0.8),
      status: r.status === 'completed' ? 'completed' : r.status === 'confirmed' ? 'confirmed' : 'in_progress',
      rawStatus: r.status,
    };
  });
}

export const runnerEnroute = (id: string) => invokeTransition(id, 'enroute');

// ---------- runner identity & money (tabula rasa) ----------
export async function fetchMyName(): Promise<string | null> {
  const { data: user } = await supabase.auth.getUser();
  if (!user.user) return null;
  const { data } = await supabase.from('profiles').select('name').eq('id', user.user.id).maybeSingle();
  return data?.name ?? user.user.email?.split('@')[0] ?? null;
}

export interface RunnerWeekStats { net: number; runs: number; km: number }

export async function fetchRunnerWeekStats(): Promise<RunnerWeekStats> {
  const since = new Date(Date.now() - 7 * 86400_000).toISOString();
  const { data, error } = await supabase
    .from('ledger_items')
    .select('base, distance_pay, addon_pay, tip, platform_fee, booking_id')
    .gte('created_at', since);
  if (error) throw error;
  const rows = data ?? [];
  const net = rows.reduce((s, l: any) => s + l.base + l.distance_pay + l.addon_pay + l.tip - l.platform_fee, 0);
  let km = 0;
  const ids = rows.map((l: any) => l.booking_id);
  if (ids.length > 0) {
    const { data: runsD } = await supabase.from('runs').select('actual_km').in('booking_id', ids);
    km = (runsD ?? []).reduce((s, r: any) => s + Number(r.actual_km ?? 0), 0);
  }
  return { net, runs: rows.length, km: Math.round(km * 10) / 10 };
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
  dogName: string; routeName: string; when: string;
  plannedKm: number; paceLabel: string; price: number; status: string;
  run: null | {
    actualKm: number; durationSec: number; paceSecPerKm: number | null;
    endReason: string | null; conditionNote: string | null;
  };
}

export async function fetchRunReport(bookingId: string): Promise<RunReport> {
  const { data, error } = await supabase
    .from('bookings')
    .select('scheduled_at, km, pace_label, total_price, status, routes(name), dogs(name), runs(actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note)')
    .eq('id', bookingId)
    .single();
  if (error) throw error;
  const d = data as any;
  const { dateLabel, timeLabel } = kstParts(d.scheduled_at);
  const raw = Array.isArray(d.runs) ? d.runs[0] : d.runs; // unique FK — 어느 형태든 안전하게
  return {
    dogName: d.dogs?.name ?? '반려견',
    routeName: d.routes?.name ?? '코스 미지정',
    when: `${dateLabel} ${timeLabel}`,
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
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, pace_label, total_price, status, runner_id, routes(name), dogs(name), runners(profiles(name))')
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
    };
  });
}
