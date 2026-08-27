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

export async function revokeBillingKeys(req: Request, db: SupabaseClient): Promise<unknown> {
  // 🔴 [0141 · codex #2] 이 함수는 요청을 통째로 무시했다. `collect-charges` 처럼
  //    `--no-verify-jwt` 로 배포하면 **인증 없는 관리자 권한 배치 엔드포인트**가 된다 —
  //    서비스 롤 클라이언트로 아웃박스를 읽고 PG 에 삭제를 쏘는 엔드포인트를 누구나 부를 수
  //    있다는 뜻이다. collect-charges 의 게이트를 그대로 가져온다.
  //    ⚠ 미설정 시크릿이 누구도 인증하지 못하게 하는 줄이 핵심이다 (그 파일의 주석 그대로):
  //      이 줄이 없으면 `null === null` 이 잘못된 배포를 열린 문으로 바꾼다.
  const cronKey = req.headers.get("X-Cron-Key");
  const expected = Deno.env.get("CRON_COLLECT_KEY");
  if (!expected) throw new HttpError(503, "폐기 배치가 설정되지 않았어요");
  if (cronKey !== expected) throw new HttpError(401, "unauthorized");

  const { data: claimed, error: cErr } = await db.rpc("claim_billing_key_revocations", { p_limit: BATCH });
  if (cErr) throw new HttpError(500, `claim failed: ${cErr.message}`);
  const rows = (claimed ?? []) as { id: string; billing_key: string; claim_token: string }[];
  if (rows.length === 0) return { claimed: 0, revoked: 0, failed: 0, stale: 0 };

  let revoked = 0, failed = 0, stale = 0;
  for (const r of rows) {
    let ok = false;
    let err: string | null = null;
    try {
      const res = await tossBillingRevoke(r.billing_key);
      // 🔴 404 는 더 이상 성공이 아니다. 첫 버전은 「존재하지 않는 키는 이미 목적을 달성한
      //    상태」라고 읽었고, 그 추론 자체는 타당했다 — **전제가 틀렸을 뿐이다.** URL 이 틀려서
      //    토스가 404(`NOT_FOUND_HTTP_METHOD`)를 주고 있었고, 그래서 아웃박스는 100% 깨끗하게
      //    비워지면서 단 하나의 키도 삭제하지 않았다. 성공 탐지기가 실패 상태와 일치했다.
      //
      // ⚠ 그리고 토스 문서는 **이미 삭제된 키의 응답을 규정하지 않는다** (에러표에 404 행 자체가
      //   없고, `NOT_FOUND_BILLING_KEY` 라는 코드는 존재하지 않는다 — 문서 원문 확인). 규정되지
      //   않은 상태를 성공으로 읽는 것은 측정이 아니라 희망이다. 그래서 2xx 만 성공이고, 404 는
      //   실패로 적혀 재시도되고, 8회 뒤 `abandoned` 로 남아 **사람이 보게 된다**.
      //   살아 있는 자격증명을 조용히 「지웠다」고 적는 것보다, 못 지웠다고 시끄럽게 적는 편이 낫다.
      ok = res.ok;
      if (!ok) {
        err = `toss ${res.httpStatus}: ${String(res.body?.message ?? res.body?.code ?? "")}`.slice(0, 300);
        // 404 를 특별히 이름 붙여 남긴다: 이 값이 무더기로 쌓이면 그건 「이미 지워진 키들」이
        // 아니라 **경로가 틀렸다**는 신호다. 첫 버그가 정확히 그 모양이었기 때문에, 다음에
        // 같은 일이 생기면 last_error 가 스스로 말하게 해 둔다.
        if (res.httpStatus === 404) err = `toss 404 (endpoint or key absent — CHECK THE URL): ${err}`;
      }
    } catch (e) {
      // 던졌다 = 요청이 끝나지 않았다 (타임아웃/네트워크). 「거절」이 아니므로 pending 으로 남고
      // 다음 틱이 다시 집는다 — charge.ts 의 dispatched-pending 과 같은 판단.
      err = `unreachable: ${(e as Error).message}`.slice(0, 300);
    }
    // [0141 §C] The claim token is a compare-and-set: if our lease expired and another worker
    // took the row, our report is DISCARDED rather than applied late over a newer result. A
    // false return is not an error — it means we lost the row, and saying so is the honest read.
    const { data: applied, error: rErr } = await db.rpc("report_billing_key_revocation",
      { p_id: r.id, p_ok: ok, p_error: err, p_token: r.claim_token });
    if (rErr) throw new HttpError(500, `report failed: ${rErr.message}`);
    if (applied === false) { stale++; continue; }
    if (ok) revoked++; else failed++;
  }
  return { claimed: rows.length, revoked, failed, stale };
}
