// Shared context for Edge Functions: service-role client + caller identity.
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const PRICING = {
  // ⚠ 두 기본요금은 서로 다른 돈이다 (Sean 2026-08-12 D2, 디커플링 확정 — 같은 이름 혼동 금지):
  //   ownerBaseFare  = 보호자가 내는 기본요금 (7,900 — 가격 체감 실험, 플랫폼이 차액 흡수)
  //   runnerCompBase = 러너 정산 공식의 기본값 (9,900 — 최저임금 2배 피치의 바닥, 절대 조용히 내리지 않는다)
  // 마진은 2km 23.4% → 10km 29.5%로 거리 의존 (검증 산식: 세션 로그 2026-08-12).
  // 하나를 다른 하나에 "맞추는" 수정은 버그가 아니라 사고다.
  ownerBaseFare: 7900,
  runnerCompBase: 9900,
  perKm: 3000,
  minFare: 9900, // 러너 gross 하한 (settle-run) — 러너 측 개념, runnerCompBase와 같은 세계

  addons: {
    river: 3000,
    homecare: 2000,
    snack: 2000,
    snap: 4000,
    livecam: 3900, // 라이브캠 — 프리미엄 (기본은 GPS+사진; 카메라 실장비는 추후, 수요 측정용 SKU)
  } as Record<string, number>,
};

export function admin(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function caller(req: Request, db: SupabaseClient): Promise<string> {
  const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const { data, error } = await db.auth.getUser(jwt);
  if (error || !data.user) throw new HttpError(401, "unauthorized");
  return data.user.id;
}

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export function handle(fn: (req: Request) => Promise<unknown>) {
  return async (req: Request): Promise<Response> => {
    try {
      const body = await fn(req);
      return Response.json(body ?? { ok: true });
    } catch (e) {
      if (e instanceof HttpError) return Response.json({ error: e.message }, { status: e.status });
      console.error(e);
      return Response.json({ error: "internal" }, { status: 500 });
    }
  };
}
