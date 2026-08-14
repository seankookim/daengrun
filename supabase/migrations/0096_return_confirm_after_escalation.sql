-- 0096 — 승격된 뒤에도 양측은 "개가 집에 왔다"고 말할 수 있어야 한다. 러너가 영구히 묶이지 않도록.
--
-- ═══ §0 THE DEFECT — a composition, not a bug in any one file ════════════════════════════
-- Three migrations, each individually correct and each implementing one of Sean's rulings,
-- compose into a runner who can never work again:
--   ① `0092`'s `runner_work_gate` blocks a runner from accepting work until BOTH return stamps
--      land.                          ← Sean: "dont let them make new runs until the dog is
--                                        confirmed by both sides"
--   ② `0089` removed the party force, so the runner cannot resolve it alone.
--                                      ← Sean: "the confirmation must happen with both parties
--                                        and never just the runner"
--   ③ `0083`'s 2h sweep escalates an unconfirmed return `active → incident_review`, and
--      `confirm_return_tx` (0083:990) is `if b.status <> 'active' then raise 'not_active'`.
-- So once the sweep fires, **neither party can stamp** — the exit ① names becomes unreachable by
-- the only people ② leaves able to reach it. The runner is permanently unable to earn, and
-- `sweep_run_end_recovery` notifies the two PARTIES and nobody else (§4).
--
-- No suite caught this because every pin is green: the property that fails spans three
-- migrations and no suite owns the composition. 119's R16 arm ⓒ actually ASSERTS the
-- `not_active` raise — correctly, for the world before `0092` existed. It is updated here (§6).
--
-- ═══ §1 REACHABILITY — this is armed now, not "before slice 3" ═══════════════════════════
-- An earlier writeup of mine said the gate needs `run_ended_at`, i.e. that it waits on the
-- run-end client slice. That is true of the gate's FIRST arm only. `0092:112-117`:
--     (b.run_ended_at is not null and b.status::text = 'active')
--     or b.status::text = 'incident_review'
-- The second arm gates on STATUS ALONE. Any marketplace booking reaching `incident_review` by
-- any route blocks its runner immediately, with no client change.
-- Measured on production 2026-08-14: the only `incident_review` booking is a CLUB booking, which
-- `0092` excludes by predicate — so zero runners are blocked, and **the club exclusion is the
-- only thing holding the line**, not the absence of a client. Meanwhile 2 marketplace bookings
-- sit in `runner_enroute` with runners assigned, and `0001:206` permits
-- `runner_enroute → incident_review`. Two real runners are one transition away.
--
-- ═══ §2 THE FIX, AND THE LINE IT REFUSES TO CROSS ════════════════════════════════════════
-- A party may stamp the return from `incident_review`. That is a CUSTODY fact — the dog is
-- home — and custody facts should never have been gated on a money state.
--
-- 🔴 **It does NOT settle, and it does NOT seal, from `incident_review`.**
--   · no `_settle_sealed_run` call            → money is untouched
--   · no `settlement_ready_at` write          → the seal means "money may move", and money may
--                                               not move out of `incident_review` (0083:1406)
--   · no status change                        → the case stays open for whoever adjudicates it
-- The runner is freed because `0092`'s gate reads the two STAMP COLUMNS, not the seal and not
-- the status (`0092:109` is a top-level `and`). So both stamps clear the gate even while the
-- booking sits in `incident_review` — which is the correct separation, not a workaround: **the
-- dog being home and the case being resolved are different facts.** That is the same
-- distinction `0089` drew between confirming and adjudicating, and `0094` drew between opening
-- and establishing. Third time today; it is the shape of this domain.
--
-- ⚠ **Money is another session's surface** under the fleet split (custody owns statuses/stamps;
-- money owns ledger tables and money functions). This file touches neither `settle_run_tx`,
-- `_settle_sealed_run`, `compute_owner_charge`, `ledger_items` nor `payments`. The one money
-- call inside `confirm_return_tx` is fenced by status, not removed.
--
-- ═══ §3 WHY THE SETTLE BRANCH IS FENCED BY STATUS RATHER THAN LEFT TO RAISE ══════════════
-- `_settle_sealed_run:900` already raises `not_active`, so a naive widening would "fail safe"
-- by letting it raise. It would not: the raise aborts the whole transaction and **the stamp is
-- lost with it** — the runner stays gated and the party is told their tap failed, which is the
-- defect wearing a different mask. So §5 gates the seal/settle branch on `active` explicitly.
-- Belt and braces: `_settle_sealed_run`'s own gate is untouched and still there.
--
-- ═══ §4 WHAT THIS FILE DELIBERATELY DOES NOT DO — the pager ══════════════════════════════
-- The obvious companion is "page ops when a runner is gated by an escalated booking". It is NOT
-- built here, and the reason is measured rather than aesthetic:
--   · `ops_recipients` has **ZERO ROWS in production** (queried 2026-08-14).
--   · `OPS_PROFILE_ID`, the one-release env fallback, is **unset** (`docs/pre-charging-
--     checklist.md:75`, `docs/launch-checklist.md:67`).
--   · So a pager shipped today would resolve to no recipient and `console.error` — and ⑫'s own
--     memo says an ops class whose remedy does not apply is WORSE than an unmonitored state,
--     because it manufactures the appearance of resolution. Sean's objection was the same:
--     a pager without an accountable responder is visible neglect.
-- What IS built is §7: a queryable detection function, so the state is FINDABLE without anyone
-- pretending it is watched. Routing it to a human needs a human to route it to — acknowledgment,
-- escalation, severity and response time are Sean's to decide, and they are surfaced, not
-- guessed. ⚠ Also note `notifyOps` lives in TypeScript (`_shared/ops.ts`) and is the only
-- consumer of `ops_recipients_for`; a SQL sweep that paged would either duplicate that routing
-- or need a pg_net dispatcher. That fork is left open rather than decided by default.
--
-- ═══ §5 STALE DOCTRINE THIS SUPERSEDES (comments in applied migrations are not edited) ════
-- `0083:1406-1412` and `0083:1444+` state: *"`incident_review` is a MONEY DEAD END:
-- `settle_run_tx`, `_settle_sealed_run`, `confirm_return_tx` and `force_return_tx` all require
-- `active`"*. After this file that sentence is **false for `confirm_return_tx` alone** — and
-- still true for the other three, which is the whole point: the money dead end is preserved
-- exactly, and only the custody stamp is let through. 0083 is applied and is not edited;
-- the supersession is recorded here and in suite 132's header.

-- ── §6 confirm_return_tx — EXTENDS 0083's version (0083:952, the only definition) ─────────
-- Built on `0083`'s body verbatim except for the two marked arms. Resolved by searching for
-- every `create or replace function confirm_return_tx` in the tree: 0083 is both first and
-- latest; 0084-0094 do not re-create it (0089 re-creates only `force_return_tx`).
create or replace function confirm_return_tx(
  p_booking uuid, p_side text, p_quote jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_both boolean; v_settled jsonb := null; v_stamped boolean := false;
  v_may_settle boolean;
begin
  if p_side not in ('runner', 'owner') then raise exception 'bad_side'; end if;
  -- A caller with an identity of its own is a CLIENT, and a client must never hand us a price.
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- party gate before state gate (unchanged from 0083).
  if v_uid is not null then
    if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
    if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  -- club exclusion stays ABOVE the status gate — 119 R14 pins that a club booking answers
  -- `club_out_of_scope` and not a status error, and the ordering is what makes that true.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  -- idempotence before the state gate: a booking already settled answers "done", never an error.
  if b.status = 'completed' then
    return jsonb_build_object('stamped', false, 'settled', true, 'unchanged', true);
  end if;

  -- [0096 §2] ─── THE CHANGED GATE ────────────────────────────────────────────────────────
  -- `incident_review` is admitted so the parties can always say the dog is home. Everything
  -- else is still refused: a cancelled or refunding booking has no custody left to confirm.
  if b.status not in ('active', 'incident_review') then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;
  -- [0096 §3] money remains `active`-only. Computed BEFORE the stamp so the rule reads in one
  -- place, and fenced explicitly rather than left to `_settle_sealed_run`'s own raise — that
  -- raise would abort this transaction and take the stamp with it (§3).
  v_may_settle := (b.status = 'active');

  -- ① the stamp (idempotent — a double tap is the same tap)
  if p_side = 'runner' and b.runner_confirmed_return_at is null then
    update bookings set runner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  elsif p_side = 'owner' and b.owner_confirmed_return_at is null then
    update bookings set owner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  end if;

  -- ② the seal — both stamps, or a force that already happened
  select (bk.runner_confirmed_return_at is not null and bk.owner_confirmed_return_at is not null)
         or bk.return_forced_by is not null
    into v_both
  from bookings bk where bk.id = p_booking;

  -- [0096 §2] the seal is part of the MONEY path, not the custody path: `settlement_ready_at`
  -- means "money may move". From `incident_review` money may not move, so nothing is sealed —
  -- which also keeps this row visible to `sweep_run_end_recovery`'s arm ⓑ semantics and out of
  -- arm ⓐ's sealed-but-unsettled alarm, and keeps 125 F4's DB-wide invariant intact
  -- (that invariant is about a seal without stamps; this writes stamps without a seal).
  if v_both and v_may_settle then
    if b.settlement_ready_at is null then
      update bookings set settlement_ready_at = v_now
       where id = p_booking and settlement_ready_at is null;
    end if;
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
  end if;

  return jsonb_build_object(
    'stamped', v_stamped,
    -- `sealed` reports the SEAL, not the pair. From `incident_review` both stamps can exist
    -- while nothing is sealed, and saying `sealed: true` there would tell a caller money is
    -- free to move when it is not. The pair is still observable via the two columns.
    'sealed', coalesce(v_both and v_may_settle, false),
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false),
    -- new, and the reason the call is worth making from a case-review screen: both parties have
    -- now said the dog is home, so the runner is no longer gated — even though the case is open.
    'both_confirmed', coalesce(v_both, false),
    'case_open', (b.status = 'incident_review'));
end $$;

revoke execute on function confirm_return_tx(uuid, text, jsonb) from public, anon;
grant execute on function confirm_return_tx(uuid, text, jsonb) to authenticated;

comment on function confirm_return_tx is
  '0096 (extends 0083 §6) — 인계 확인. `active`에서는 0083 그대로: 두 번째 스탬프가
settlement_ready_at을 찍고, 가격을 들고 온 서버 호출이면 같은 트랜잭션에서 정산한다.
🔴 `incident_review`에서도 스탬프는 받는다 — 개가 집에 왔다는 것은 커스터디 사실이고 돈 상태에
묶일 이유가 없다 — 그러나 **봉인도 정산도 하지 않는다**. 0092의 게이트는 스탬프 두 개를 읽으므로
이것만으로 러너는 풀리고, 케이스는 열린 채 남는다 (개가 집에 온 것과 사건이 해결된 것은 다른
사실이다). 나머지 세 함수(settle_run_tx·_settle_sealed_run·force_return_tx)의 active 전용
게이트는 그대로다 — 돈의 막다른 길은 보존되고 커스터디 스탬프만 통과한다.';

-- ── §7 detection: which runners are gated, and by what ────────────────────────────────────
-- Deliberately a QUERYABLE function, not a pager (§4). It answers the question an operator
-- would ask, and it names the remedy per row so the answer is actionable rather than merely
-- alarming — ⑫'s memo: an ops class must name a remedy that works on a marketplace booking.
-- `waiting_on`/`remedy` mirror `runner_work_gate`'s vocabulary rather than inventing a second.
create or replace function ops_gated_runners()
returns table (
  runner_id uuid,
  booking_id uuid,
  status text,
  gated_since timestamptz,
  waiting_on text,
  remedy text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.runner_id,
         b.id,
         b.status::text,
         coalesce(b.run_ended_at, b.updated_at, b.scheduled_at),
         case
           when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
             then 'both'
           when b.runner_confirmed_return_at is null then 'runner'
           else 'owner'
         end,
         -- The remedy is now REACHABLE BY THE PARTIES for both states, which is exactly what
         -- §6 changed. Before this file the `incident_review` row had no party-reachable remedy
         -- at all and the only honest value here would have been 'ops_force_return'.
         case b.status::text
           when 'incident_review' then 'either party may confirm_return_tx — allowed from incident_review since 0096; clears the gate without settling'
           else 'either party may confirm_return_tx as normal'
         end
    from bookings b
   where b.runner_id is not null
     and b.club_session_id is null
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and (
           (b.run_ended_at is not null and b.status::text = 'active')
           or b.status::text = 'incident_review'
         )
   order by coalesce(b.run_ended_at, b.updated_at, b.scheduled_at), b.id
$$;

revoke execute on function ops_gated_runners() from public, anon, authenticated;
grant  execute on function ops_gated_runners() to service_role;

comment on function ops_gated_runners is
  '0096 §7 — 지금 작업 게이트에 묶여 있는 러너 목록 (0092의 술어와 같은 모양, 두 번째 규칙을
만들지 않는다). 각 행이 remedy를 이름으로 갖는다: 0096 이후로는 incident_review에서도 당사자가
직접 풀 수 있다. ⚠ 이것은 PAGER가 아니라 질의 함수다 — ops_recipients는 프로덕션에서 0행이고
OPS_PROFILE_ID도 미설정이라, 오늘 푸시를 붙이면 아무에게도 가지 않는다. 받을 사람·확인 책임·
심각도·응답 시간은 Sean의 결정이다 (⑫ 메모: 적용되지 않는 remedy를 알리는 것은 감시하지 않는
것보다 나쁘다).';
