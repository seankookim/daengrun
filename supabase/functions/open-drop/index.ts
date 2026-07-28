// 드랍 오픈 — 보급 상자 열기 / 픽 드랍 선택 적용.
// input: { drop_id, pick_choice? }  (pick 드랍은 choice 필수: boost | miles | gear)
import { admin, caller, handle, HttpError } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const { drop_id, pick_choice } = await req.json();
  if (!drop_id) throw new HttpError(400, "missing drop_id");

  const { data: drop } = await db.from("drops").select("*").eq("id", drop_id).single();
  if (!drop) throw new HttpError(404, "drop not found");
  if (drop.runner_id !== uid) throw new HttpError(403, "not yours");
  if (drop.opened_at) throw new HttpError(409, "already opened");

  // 원자 선점 — 읽기 후 쓰기 사이의 동시 오픈이 마일을 이중 적립하던 레이스.
  // opened_at이 아직 null인 경우에만 스탬프: 두 번째 요청은 여기서 멈춘다.
  const { data: claimed, error: clErr } = await db.from("drops")
    .update({ opened_at: new Date().toISOString(), pick_choice: pick_choice ?? null })
    .eq("id", drop_id).is("opened_at", null).select("id");
  if (clErr) throw new HttpError(409, clErr.message);
  if (!claimed || claimed.length === 0) throw new HttpError(409, "already opened");

  const applied: Record<string, unknown> = {};

  if (drop.kind === "mini") {
    const c = drop.contents as { miles?: number; card?: string; gear?: string };
    if (c.miles) {
      const { error: e1 } = await db.from("miles_ledger").insert({ profile_id: uid, delta: c.miles, reason: "drop", ref_id: drop_id });
      if (e1) throw new HttpError(500, `마일 적립 실패 — 관리자 확인: ${e1.message}`);
      applied.miles = c.miles;
    }
    if (c.card) {
      await db.from("cards_owned").upsert(
        { profile_id: uid, card_key: `drop-${drop.run_count_at}`, tier: "레어" },
        { onConflict: "profile_id,card_key" },
      );
      applied.card = c.card;
    }
    if (c.gear) {
      await db.from("gear_claims").insert({
        profile_id: uid, side: "runner", item: c.gear, milestone: drop.run_count_at, status: "claimable",
      });
      applied.gear = c.gear;
    }
  } else {
    // pick 드랍 — 선택 하나 적용 (선택 데이터 = 러너 동기 시그널)
    if (!["boost", "miles", "gear"].includes(pick_choice)) throw new HttpError(400, "pick_choice required");
    if (pick_choice === "boost") {
      const ends = new Date(Date.now() + 24 * 3_600_000);
      await db.from("boosts").insert({ runner_id: uid, ends_at: ends.toISOString() });
      applied.boost_until = ends.toISOString();
    } else if (pick_choice === "miles") {
      const { error: e2 } = await db.from("miles_ledger").insert({ profile_id: uid, delta: 5000, reason: "pick_drop", ref_id: drop_id });
      if (e2) throw new HttpError(500, `마일 적립 실패 — 관리자 확인: ${e2.message}`);
      applied.miles = 5000;
    } else {
      await db.from("gear_claims").insert({
        profile_id: uid, side: "runner", item: "기어 교환권", milestone: drop.run_count_at, status: "claimable",
      });
      applied.gear = "기어 교환권";
    }
  }

  // opened_at 스탬프는 상단 원자 선점에서 이미 완료

  return { applied };
}));
