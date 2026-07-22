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

  const applied: Record<string, unknown> = {};

  if (drop.kind === "mini") {
    const c = drop.contents as { miles?: number; card?: string; gear?: string };
    if (c.miles) {
      await db.from("miles_ledger").insert({ profile_id: uid, delta: c.miles, reason: "drop", ref_id: drop_id });
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
      await db.from("miles_ledger").insert({ profile_id: uid, delta: 5000, reason: "pick_drop", ref_id: drop_id });
      applied.miles = 5000;
    } else {
      await db.from("gear_claims").insert({
        profile_id: uid, side: "runner", item: "기어 교환권", milestone: drop.run_count_at, status: "claimable",
      });
      applied.gear = "기어 교환권";
    }
  }

  await db.from("drops").update({
    opened_at: new Date().toISOString(),
    pick_choice: pick_choice ?? null,
  }).eq("id", drop_id);

  return { applied };
}));
