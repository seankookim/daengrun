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

/**
 * A client bound to the CALLER's JWT — the 0077 caller doctrine (`0077_recurring_guard.sql`'s
 * header is the law; `confirm-payment/handler.ts` carried the first copy and keeps it). A
 * client-gated RPC — one whose party gate is `auth.uid()` — is called through THIS client and
 * never through `admin()`: with the service key `auth.uid()` is NULL, so the RPC's `not_signed_in`
 * gate fires, or — where the migration revoked service_role outright, as 0176 does — the call is
 * refused 42501 before the body runs. Either way the wiring is wrong, and neither is the caller's
 * fault; this helper is how a handler makes it right.
 */
export function callerBoundClient(req: Request): SupabaseClient {
  const authz = req.headers.get("Authorization");
  if (!authz) throw new HttpError(401, "no caller token"); // caller() should have said 401 first
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authz } } },
  );
}

export class HttpError extends Error {
  /**
   * `code` is set ONLY by `internalError()` below. It rides beside a stable `error` token so a 500
   * can be told apart from another 500 in a log or a support thread without the body ever carrying
   * the underlying database sentence.
   *
   * `detail` (0191) is the id of the ROW a refusal is about — the club session a dog is out on,
   * the booking that is still live. It exists because a token alone makes a client describe a
   * destination in prose instead of linking to it (`awaiting-sean.md` §0-unvicies, and
   * `0115:388-392`, which records the measurement that stopped it being added then: this class's
   * error arm built the body with exactly ONE key and is imported by 24 edge functions).
   *
   * ⚠ IT IS AN ID, NEVER A SENTENCE. The token stays in `message` and stays bare, because that is
   * what clients match on; `detail` is additive, optional, and read by nobody who does not ask
   * for it. A Postgres error sentence must never be routed here — that is what `internalError()`
   * is for, and the reason is the same one it states: the operator needs that text and the
   * customer cannot act on it.
   */
  constructor(
    public status: number,
    message: string,
    public code?: string,
    public detail?: string,
  ) { super(message); }
}

/**
 * A 500 whose body says nothing about the database (backend audit 2026-09-17 · L1).
 *
 * The sites this replaces did `throw new HttpError(500, pgErr.message)`, which put raw Postgres
 * text — column names, constraint names, occasionally a row's own values — into a Korean app's
 * alert box. The operator needs that text; the customer cannot act on it and should never see it.
 * So the full message goes to the server log (where an operator already reads every other failure
 * on these paths) and the caller gets `{ error: "internal", code }`.
 *
 * ⚠ `error` is deliberately the SAME token `handle()`'s catch-all already returns for an
 * unhandled throw, so this introduces no new vocabulary to the client: `api.ts`'s `fnError`
 * surfaces `data.error` verbatim and has always been able to receive `internal`. `code` is the
 * only new field, it is additive, and no client reads it today — it exists so two different 500s
 * in one function are distinguishable in a log line and in a bug report.
 *
 * ⚠ This is for 500s ONLY. A 4xx whose text a client keys copy on (`confirm_required`,
 * `auth_delete_pending`, the delete-account state tokens, settle-run's Korean raise map) must
 * never be routed through here — those tokens ARE the contract.
 */
export function internalError(e: unknown, code: string): HttpError {
  // A PostgrestError is a plain object, not an Error — read both shapes rather than printing
  // `[object Object]` into the one place the cause was supposed to survive.
  const msg = e instanceof Error
    ? e.message
    : (e && typeof e === "object" && "message" in e)
    ? String((e as { message: unknown }).message)
    : String(e);
  console.error(`[internal:${code}] ${msg}`);
  return new HttpError(500, "internal", code);
}

export function handle(fn: (req: Request) => Promise<unknown>) {
  return async (req: Request): Promise<Response> => {
    try {
      const body = await fn(req);
      return Response.json(body ?? { ok: true });
    } catch (e) {
      if (e instanceof HttpError) {
        // 🔴 CONDITIONAL, KEY BY KEY — this is the error contract of 24 edge functions and every
        // caller that set neither `code` nor `detail` keeps the body it has always had, byte for
        // byte. A body that grew an `detail: undefined` (or a `null`) would be a new shape on
        // every one of those functions in exchange for nothing.
        // ⚠ The spread is TRUTHINESS-gated, not `!== undefined`, and that is load-bearing rather
        // than idiomatic: `delete_my_account_tx` emits `''` when it refuses and could not name
        // the blocking row (plpgsql refuses a null RAISE option, and the id is read by a second
        // statement that a concurrent commit can outrun — 0191 §0c). An empty detail means "there
        // is a blocker and I cannot name it", so it must arrive as NO KEY rather than as an empty
        // string the client would have to special-case into a dead button.
        return Response.json(
          {
            error: e.message,
            ...(e.code ? { code: e.code } : {}),
            ...(e.detail ? { detail: e.detail } : {}),
          },
          { status: e.status },
        );
      }
      console.error(e);
      return Response.json({ error: "internal" }, { status: 500 });
    }
  };
}
