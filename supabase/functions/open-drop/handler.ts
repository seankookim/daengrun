// 드랍 오픈 — 보급 상자 열기 / 픽 드랍 선택 적용.
// input:  { drop_id, pick_choice? }  (pick 드랍은 choice 필수: boost | miles | gear)
// output: { applied: {...} }, and on a post-CAS writer failure additionally
//         { failed: ["miles"|"card"|"gear"|"boost_until", ...], error: <Korean sentence> }
//
// Split out of index.ts for the same reason confirm-payment (0076) and settle-run were: while
// `Deno.serve` runs at module top level no test can import this code. That is not a tidy-up here —
// this 68-line file carried H1, H2 and M3 of the 2026-09-17 backend audit with **no test suite at
// all** (L5), and the suite that now exists (`_test/open-drop.test.ts`) needs an injectable db.
// The logic below is unchanged except for the three findings named in the blocks that follow.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError } from "../_shared/ctx.ts";

/** What a pick drop may choose. Consulted BEFORE the consuming CAS — see the M3 block. */
const PICK_CHOICES = ["boost", "miles", "gear"];

/**
 * `applied` key → the word a runner reads. The failure sentence names the REWARD, never our column:
 * 「boost_until 보상이 적용되지 않았어요」 tells a person nothing they can act on.
 */
const REWARD_LABEL: Record<string, string> = {
  miles: "하이 포인트",
  card: "카드",
  gear: "기어",
  boost_until: "부스트",
};

export async function openDrop(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  // A malformed or absent body is the CALLER's mistake, so it must not wear our 500 (backend audit
  // 2026-09-17 · M1). Unguarded, `req.json()` threw a SyntaxError straight past this function into
  // `handle()`'s catch-all and answered `500 internal` — a sentence that says our server broke when
  // nothing did, and one that sends the caller retrying a request that can never succeed. Same
  // guarded-parse idiom as `collect-charges/handler.ts:79` and `register-billing-key/handler.ts:295`.
  const { drop_id, pick_choice } = await req.json().catch(() => {
    throw new HttpError(400, "bad_body");
  }) ?? {};
  if (!drop_id) throw new HttpError(400, "missing drop_id");

  const { data: drop } = await db.from("drops").select("*").eq("id", drop_id).single();
  if (!drop) throw new HttpError(404, "drop not found");
  if (drop.runner_id !== uid) throw new HttpError(403, "not yours");
  if (drop.opened_at) throw new HttpError(409, "already opened");

  // ═══ [M3] THE WHITELIST STANDS ABOVE THE CAS, AND THE ORDER IS THE WHOLE FIX ═════════════════
  // It used to sit inside the pick branch, ~30 lines BELOW the update that stamps `opened_at`. So a
  // pick drop opened with a missing or bogus choice ran the CAS first, and the CAS wrote
  // `pick_choice: null` into a row the database has a CHECK for — `drops_pick_opened_has_choice`.
  // The caller therefore got a 409 carrying the raw constraint name, which `rewards.tsx:83` printed
  // verbatim into a Korean alert: 「violates check constraint "drops_pick_opened_has_choice"」.
  //
  // ⚠ And the damage was not only the sentence. The refusal arrived AFTER the write attempt, which
  // is the one ordering this drop can least afford — `opened_at` is frozen by `0106 §3` and cannot
  // be un-stamped, so a validation that runs late is a validation that can cost the reward it was
  // meant to protect. Validate, then consume.
  if (drop.kind !== "mini" && !PICK_CHOICES.includes(pick_choice)) {
    throw new HttpError(400, "pick_choice required");
  }

  // 원자 선점 — 읽기 후 쓰기 사이의 동시 오픈이 마일을 이중 적립하던 레이스.
  // opened_at이 아직 null인 경우에만 스탬프: 두 번째 요청은 여기서 멈춘다.
  //
  // ⚠ [H2 · NOT FIXED HERE, AND A READER MUST NOT MISTAKE H1's FIX FOR IT] This CAS **consumes the
  // drop before anything has paid it**. Every writer below runs after the stamp, `0106 §3` freezes
  // `opened_at`, and no sweep looks for a stamped drop with no reward — so a writer that fails has
  // destroyed a reward that nothing will ever come back for. H1's fix below makes that loss VISIBLE
  // (an honest `failed` list, a log line, and no receipt for a write that did not land); it does not
  // make it RECOVERABLE. The real fix is one `open_drop_tx` SECURITY DEFINER doing the stamp and the
  // rewards in a single transaction — the `settle_run_tx` shape — which is a migration and needs the
  // adversarial cycle, so it is deliberately out of this edge-only slice's scope.
  const { data: claimed, error: clErr } = await db.from("drops")
    .update({ opened_at: new Date().toISOString(), pick_choice: pick_choice ?? null })
    .eq("id", drop_id).is("opened_at", null).select("id");
  if (clErr) throw new HttpError(409, clErr.message);
  if (!claimed || claimed.length === 0) throw new HttpError(409, "already opened");

  const applied: Record<string, unknown> = {};
  const failed: string[] = [];

  // ═══ [H1] A KEY REACHES `applied` ONLY WHEN ITS WRITE LANDED ═════════════════════════════════
  // Four of the five writers below never bound `error` at all, and `applied.card` / `applied.gear` /
  // `applied.boost_until` were set regardless. The response was therefore a RECEIPT FOR REWARDS
  // NOBODY HAD CHECKED WERE WRITTEN — the exact shape this repo's honesty law forbids, made worse
  // by the CAS above having already spent the drop. Idiom: `cancel_owner.ts:197-202`.
  const record = (key: string, value: unknown, error: { message: string } | null | undefined) => {
    if (error) {
      failed.push(key);
      console.error(
        `[open-drop] drop=${drop_id} runner=${uid} ${key} write FAILED: ${error.message}`,
      );
      return;
    }
    applied[key] = value;
  };

  if (drop.kind === "mini") {
    const c = drop.contents as { miles?: number; card?: string; gear?: string };
    if (c.miles) {
      const { error } = await db.from("miles_ledger")
        .insert({ profile_id: uid, delta: c.miles, reason: "drop", ref_id: drop_id });
      record("miles", c.miles, error);
    }
    if (c.card) {
      const { error } = await db.from("cards_owned").upsert(
        { profile_id: uid, card_key: `drop-${drop.run_count_at}`, tier: "레어" },
        { onConflict: "profile_id,card_key" },
      );
      record("card", c.card, error);
    }
    if (c.gear) {
      const { error } = await db.from("gear_claims").insert({
        profile_id: uid, side: "runner", item: c.gear, milestone: drop.run_count_at, status: "claimable",
      });
      record("gear", c.gear, error);
    }
  } else {
    // pick 드랍 — 선택 하나 적용 (선택 데이터 = 러너 동기 시그널). 화이트리스트는 CAS 위에서 이미 통과.
    if (pick_choice === "boost") {
      const ends = new Date(Date.now() + 24 * 3_600_000).toISOString();
      const { error } = await db.from("boosts").insert({ runner_id: uid, ends_at: ends });
      record("boost_until", ends, error);
    } else if (pick_choice === "miles") {
      const { error } = await db.from("miles_ledger")
        .insert({ profile_id: uid, delta: 5000, reason: "pick_drop", ref_id: drop_id });
      record("miles", 5000, error);
    } else {
      const { error } = await db.from("gear_claims").insert({
        profile_id: uid, side: "runner", item: "기어 교환권", milestone: drop.run_count_at, status: "claimable",
      });
      record("gear", "기어 교환권", error);
    }
  }

  // opened_at 스탬프는 상단 원자 선점에서 이미 완료
  if (failed.length === 0) return { applied };

  // ═══ A PARTIAL OPEN IS REPORTED AS A PARTIAL OPEN ════════════════════════════════════════════
  // One log line naming the drop, because this is the only durable trace: no sweep looks for a
  // stamped drop with a missing reward (H2), so an operator who is not told here is not told at all.
  console.error(
    `[open-drop] drop=${drop_id} runner=${uid} CONSUMED but ${failed.length} reward(s) NOT written ` +
      `(${failed.join(", ")}) — opened_at is frozen (0106 §3) and nothing will retry this`,
  );

  // ⚠ WHY THERE IS AN `error` BESIDE `applied` IN A 200, and it is deliberate rather than sloppy.
  // The honest answer has to carry BOTH halves: what genuinely landed (so a runner who won three
  // things and lost one is not told they lost all four) and the fact that something did not. A
  // thrown 4xx/5xx would discard `applied`; a bare 200 would let `rewards.tsx:80` render
  // 「드랍 오픈!」 over an empty parts list as 「보상이 적용됐어요」 — a celebration for nothing.
  // `api.ts` checks `data?.error` at EVERY invoke site (`:3770` here) precisely so a function can
  // say "this 200 is not a success" — the same 200-with-an-outcome shape `collect-charges` uses for
  // its batch rows — so this reaches the existing client as 「오픈 실패」 + this sentence, with no
  // client change required. A client that later wants to render the partial can read `applied` and
  // `failed`, which is why they are still here.
  const labels = failed.map((k) => REWARD_LABEL[k] ?? k).join(" · ");
  return {
    applied,
    failed,
    error: `드랍은 열렸지만 ${labels} 보상이 적용되지 않았어요 — 관리자 확인이 필요해요`,
  };
}
