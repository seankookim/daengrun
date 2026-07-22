// Live API layer — replaces store.ts mocks screen by screen.
// Pattern: fetch → map to the app's existing types → screens fall back to mock on failure.
import { lastRunTrace, RouteInfo, sampleRoutes, TracePoint } from '../store';
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
