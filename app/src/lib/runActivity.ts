// 러닝 라이브 액티비티 제어 — 지연 로드 (위젯 확장이 없는 구 빌드에선 조용히 무시).
// iOS 16.2+ · 새 expo run:ios 빌드부터 동작.

export interface RunLAProps {
  dogName: string;
  km: string;
  targetKm: string;
  pace: string;
  elapsed: string;
  eventLine: string;
  // '' = no claim (gate/stale/unknown). Widget renders the labeled pill only when non-empty.
  paceState?: '' | 'good' | 'slow';
}

let instance: any = null;

export function startRunActivity(p: RunLAProps): void {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const RunActivity = require('../activities/RunActivity').default;
    instance = RunActivity.start(p, 'daengrun://runner/run');
  } catch (e) {
    console.warn('[LA] start:', (e as Error)?.message);
  }
}

export function updateRunActivity(p: RunLAProps): void {
  if (!instance) return;
  try { instance.update(p); } catch { /* no-op */ }
}

export function endRunActivity(p: RunLAProps): void {
  if (!instance) return;
  try { instance.end('immediate', p, new Date()); } catch { /* no-op */ }
  instance = null;
}
