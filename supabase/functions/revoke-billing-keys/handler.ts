// 빌링키 폐기 — codex #4 의 아웃박스를 비운다.
//
// 카드를 교체하거나 계정을 삭제하면 우리 행은 사라지지만 **토스의 빌링키는 살아 있다**. 우리가
// 기록을 지웠다는 사실이 PG 를 멈추지 않는다 — 그래서 교체·삭제 시점에 0138 이 폐기 의무를
// 아웃박스에 적고, 이 워커가 그것을 실제 HTTP 호출로 갚는다.
//
// ⚠ 왜 DB 안에서 호출하지 않는가: 아웃바운드 HTTP 를 `billing_key_swap` 안에서 하면 프로필 행
//   락을 네트워크 왕복 동안 붙잡는다 — 0137 이 없애려던 결함을 그대로 되살린다. 사용자 요청
//   경로에서 하면 토스 타임아웃이 성공한 등록을 막거나 조용히 삼켜진다. 그래서 claim → call →
//   report 로 갈랐다 (charge dispatch 와 같은 내구 작업 패턴).
import { HttpError } from "../_shared/ctx.ts";
import { tossBillingRevoke } from "../_shared/toss.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const BATCH = 20;

export async function revokeBillingKeys(_req: Request, db: SupabaseClient): Promise<unknown> {
  const { data: claimed, error: cErr } = await db.rpc("claim_billing_key_revocations", { p_limit: BATCH });
  if (cErr) throw new HttpError(500, `claim failed: ${cErr.message}`);
  const rows = (claimed ?? []) as { id: string; billing_key: string }[];
  if (rows.length === 0) return { claimed: 0, revoked: 0, failed: 0 };

  let revoked = 0, failed = 0;
  for (const r of rows) {
    let ok = false;
    let err: string | null = null;
    try {
      const res = await tossBillingRevoke(r.billing_key);
      // ⚠ 404/이미 삭제됨은 성공으로 읽는다. 폐기의 목적은 「그 키로 결제할 수 없게 한다」이고,
      //   존재하지 않는 키는 그 상태를 이미 만족한다 — 재시도해도 영원히 404 이므로 pending 에
      //   남겨두면 8회를 태우고 abandoned 가 된다. 목적을 달성한 행을 실패로 적지 않는다.
      ok = res.ok || res.httpStatus === 404;
      if (!ok) err = `toss ${res.httpStatus}: ${String(res.body?.message ?? res.body?.code ?? "")}`.slice(0, 300);
    } catch (e) {
      // 던졌다 = 요청이 끝나지 않았다 (타임아웃/네트워크). 「거절」이 아니므로 pending 으로 남고
      // 다음 틱이 다시 집는다 — charge.ts 의 dispatched-pending 과 같은 판단.
      err = `unreachable: ${(e as Error).message}`.slice(0, 300);
    }
    const { error: rErr } = await db.rpc("report_billing_key_revocation",
      { p_id: r.id, p_ok: ok, p_error: err });
    if (rErr) throw new HttpError(500, `report failed: ${rErr.message}`);
    if (ok) revoked++; else failed++;
  }
  return { claimed: rows.length, revoked, failed };
}
