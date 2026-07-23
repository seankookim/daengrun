// Live API layer — replaces store.ts mocks screen by screen.
// Pattern: fetch → map to the app's existing types → screens fall back to mock on failure.
import { AddonKey, Booking, BookingStatus, dog as mockDog, lastRunTrace, RouteInfo, sampleRoutes, TracePoint } from '../store';
import { supabase } from './supabase';

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
  if (error) throw error;
  if (data?.error) throw new Error(data.error);
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
  picked_up: 'active',
  active: 'active',
  completed: 'completed',
  cancelled_owner: 'cancelled',
  cancelled_runner: 'cancelled',
};

export async function fetchMyBookings(): Promise<Booking[]> {
  const { data, error } = await supabase
    .from('bookings')
    .select('id, scheduled_at, km, pace_label, total_price, status, runner_id, routes(name), dogs(name)')
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
      runnerId: 'minjun', // 러너 확정 전 placeholder (sheet는 matched 전 게이트됨)
      runnerName: r.runner_id ? '러너' : '매칭 중',
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
