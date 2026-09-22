-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0206 — the ops console's MISSING DOORS: the two lists behind the two ops bells, and one bell
--        that was never rung
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 237_ops_console_v2_suite.sql (tag `ocv`) — 0206-R1 · R2 · R3 · H1 · H2 · G1 · S1
--
-- DEPLOY: `supabase db push` + a client build. NO edge function changes, no cron, no secret.
--   ⚠ `resolve_return` (the edge action this slice finally gives a caller) is ALREADY DEPLOYED —
--     0193 §C-b built it and 0201 §C hardened it. Nothing in `supabase/functions/` changes here.
--
-- ─── §0 WHAT IS MISSING, MEASURED ON TRUNK `fde88a1` BEFORE A LINE WAS WRITTEN ──────────────────
-- 0198 put the PAYOUT loop on a phone. The two other things the ops roster is paged about are
-- still psql-only, and one of them is not paged about at all:
--
--   ① **A STRANDED RETURN HAS A DOOR AND NO HANDLE.** `resolve_return` (transition-booking,
--      0193 §C-b + 0201 §C — a full Korean refusal map, roster-gated ahead of the booking read)
--      has ZERO callers: `grep -rn "resolve_return" app/` returns nothing. So the bell
--      `sweep_run_end_recovery` arm ⓕ rings (「반환 좌초 — 확인 필요」, 0193 §D) summons an
--      operator to a psql prompt — which is precisely the shape 0198 §0 was written to remove,
--      one desk over. And the operator has no LIST: the bell carries a `ref_id` and nothing else,
--      by design (0084 §E — an ops body carries no identifier), so 「which returns are stranded」
--      had no answer at all short of reading `bookings` by hand. §A.
--
--   ② **A STALLED HANDOFF HAS A BELL AND NO LIST EITHER.** 0183 arm ⓓ/ⓔ escalates a one-sided
--      pickup handoff to the `handoff_unanswered` roster and records it in
--      `handoff_escalated_at` / `handoff_ops_alerted_at`. Nothing reads those columns for an
--      operator; `fetchHandoffEscalation` (api.ts:1333) reads them for ONE booking, as a PARTY.
--      §B.
--
--   ③ **A GEAR CLAIM PAGES NOBODY.** 0195 §0 says so in its own header — 「notifications
--      untouched」 — and `ops_gear_claims_pending()` (0195 §C) is a list an operator has to think
--      to open. Every other ops queue in this product has a bell; this one had a list and
--      silence, so a box sits unposted until somebody happens to look. §C.
--
-- ⚠ **WHAT THIS FILE DELIBERATELY DOES NOT ADD**, enumerated so the omissions read as decisions:
--   · no new ACTION on a stalled handoff. 0183's own header says what a stuck pickup handoff
--     should BECOME is a product decision (Sean's), not a clock's — and the same sentence covers
--     an operator's button. §B is a READ. The tools that already exist (0185's) stay the tools.
--   · no second implementation of the strand predicate. §A's is arm ⓕ's, conjunct for conjunct,
--     with the two differences named at the function and pinned by `0206-R2` against the sweep's
--     own output rather than against a copy of the text.
--   · no widening of `ops_me()`. Its `pronargs = 0` is 0198 §0d's structural defence and 229
--     `0198-S1` pins it; this file does not touch that function.
--
-- ─── §0b WHICH ROSTER GATES WHICH LIST, AND WHY IT IS NOT `payout_due` FOR EITHER ───────────────
-- 0084 §E's classes are SEPARATE rosters and 0201 §C restates that as law for `ops_is_member`:
-- 「payout_due 소속이 return_strand의 문을 열어서는 안 된다」. Applied here:
--
--   `ops_stranded_returns()`  → **`return_strand`**, because that is the roster
--       `ops_resolve_return_tx` (0193 §C-b) gates on. A list gated on `payout_due` would show an
--       operator rows whose only action refuses them by name — 0198 §0d's dead-button failure in
--       a new costume, and worse here, because the refusal arrives after they have read a
--       stranded owner's and runner's names.
--   `ops_stalled_handoffs()`  → **`handoff_unanswered`**, the roster 0183 arm ⓓ/ⓔ actually pages.
--       The people who were TOLD are the people who may look. There is no action behind this
--       list, so the alternative argument (「gate the read on the action's roster」) has no subject
--       — the roster that receives the escalation is the only honest choice left.
--   `claim_gear_tx`'s new bell → **`payout_due`**, because that is the class
--       `ops_gear_claims_pending` / `ops_mark_gear_shipped` already gate on (0195 §0f). A bell
--       delivered to people the list refuses is the same dead button read from the other end.
--
-- ⚠ **A CONSEQUENCE THAT IS A LIMITATION RATHER THAN A DEFECT, STATED HERE SO IT IS NOT
--   REDISCOVERED:** `app/app/ops/_layout.tsx` gates the whole `/ops/*` group on
--   `ops_me().is_ops`, which is `payout_due` (0198 §0d). So an operator holding ONLY
--   `return_strand` cannot reach `/ops/returns` even though `ops_stranded_returns()` would admit
--   them. That gate is 0198's and widening it would widen the entry to the BANK-ACCOUNT desk,
--   which is not this slice's call to make. The client instead draws each new section only when
--   `ops_me().kinds` carries that section's class — so nothing is a dead button — and
--   `0206-R1`/`0206-H1` pin the agreement between `kinds` and each door in BOTH directions, which
--   is what keeps that client-side decision from drifting into a lie.
--
-- ─── §0c WHAT THE TWO LISTS DISCLOSE, AND WHY IT IS NOT 0186 §B's RULE BEING BROKEN ─────────────
-- Both carry the DOG's name and BOTH PARTIES' display names. 0186 §B refuses to carry a name
-- beside a payable amount because one grant mistake would then disclose the PAIR (money +
-- destination). Neither function here carries money: no fare, no fee, no net, no bank field, no
-- phone, no address, and no operator memo (0193:446 — the memo is an internal audit note and 230
-- `0199-V5` pins that it never reaches a phone).
--   · The operator's task on a strand is 「work out what actually happened to this dog and write
--     down what you confirmed」 — `ops_resolve_return_tx` REQUIRES a memo (`memo_required`) and a
--     memo about 「booking 6f2a…」 is not a record anybody can audit later.
--   · The gate is the same gate. A caller who can reach §A can already reach
--     `ops_resolve_return_tx`, which SEALS and SETTLES the booking. Names add no reachability.
--   · A club booking is out of scope for §A by the predicate (arm ⓕ's `club_session_id is null`),
--     so no club member's name can arrive through it at all.
-- ⚠ `status` is carried RAW (`active` | `incident_review`) because the client must GATE on the
--   server word and print a mapped sentence — the standing STATUS_MAP law. It is never rendered.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A ops_stranded_returns — the rows behind the 「반환 좌초 — 확인 필요」 bell
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **THE PREDICATE IS `sweep_run_end_recovery` ARM ⓕ's, CONJUNCT FOR CONJUNCT** (0201:734-745,
--   which is 0193 §D's as amended by codex 2026-09-22 #2). Two differences, both deliberate, both
--   named here rather than left to be spotted:
--
--   (1) **NO `not exists (… title = 좌초)` ONE-SHOT GUARD — INVERTED INTO THE ADMISSION.** In the
--       sweep that clause makes the candidate set DRAIN (a bell already rung is not rung again).
--       In a LIST it would hide exactly the rows an operator was paged about, which is the only
--       reason they opened the screen. So the belled rows are ADMITTED, and the bell's instant
--       rides as `notified_at` — a fact the operator needs (「how long has this been sitting」),
--       and NULL for a row the sweep has not reached yet rather than coalesced to anything.
--
--   (2) **NO `limit`.** 0198 §B's argument, unchanged: a truncated batch-selection surface makes
--       an operator resolve a subset while believing the queue is clear. The set is bounded by
--       「unsealed returns past the deadline」, which is bounded by how far behind we are.
--
--   ⚠ And one structural consequence of the deadline being a FLAG. `ops_flags.return_strand_minutes`
--     ships NULL and NULL means arm ⓕ does nothing (0193 §A · Sean's queue item 23 set it to 180
--     on 2026-09-22). With NULL, 「would consider」 is the EMPTY set — so the admission is
--     `(deadline is set AND past it) OR (a bell exists)`: with the arm switched off the list shows
--     exactly the rows an operator was already paged about and invents no deadline of its own.
--     A read that picked its own number would page nobody and still show rows, which is the
--     「a deadline nobody chose」 failure 0201:714-718 argues against, one door over.
create or replace function ops_stranded_returns()
returns table (
  booking_id        uuid,
  dog_name          text,
  owner_name        text,
  runner_name       text,
  status            text,
  run_ended_at      timestamptz,
  runner_stamped    boolean,
  owner_stamped     boolean,
  minutes_stranded  int,
  strand_minutes    int,
  notified_at       timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- the SAME class `ops_resolve_return_tx` (0193 §C-b / 0201 §A) gates on, and the same one arm ⓕ
  -- delivers to. §0b says why it is not `payout_due`.
  c_ops_class   constant text := 'return_strand';
  -- arm ⓕ's title, verbatim (0193:656). It is the dedupe key there and the `notified_at` key here;
  -- 237 `0206-S1` asserts the two spellings against the deployed sweep so they cannot part.
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  v_uid uuid := auth.uid();
  v_min int;
begin
  -- ① PARTY GATE FIRST — before any read of anybody's booking. There is no argument to check
  --    afterwards (this function takes none, for the same structural reason `ops_me` takes none:
  --    there is no parameter by which to point it at a third party's booking).
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  -- ② the deadline, read FRESH exactly as arm ⓕ reads it (0201:732), so a flip needs no redeploy
  --    and the list and the sweep never disagree about which number is current.
  select f.return_strand_minutes into v_min from ops_flags f where f.id;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         b.run_ended_at,
         (b.runner_confirmed_return_at is not null),
         (b.owner_confirmed_return_at is not null),
         floor(extract(epoch from (now() - b.run_ended_at)) / 60)::int,
         v_min,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id and nt.title = c_strand_title)
    from bookings b
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── arm ⓕ's candidate predicate (0201:737-742), conjunct for conjunct ──────────────────────
   where b.club_session_id is null
     and b.status in ('active', 'incident_review')
     and b.run_ended_at is not null
     and b.settlement_ready_at is null
     -- TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
     -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and 0096 lets late
     -- stamps land there without sealing — so an unsealed `incident_review` return is a strand
     -- regardless of how many stamps it carries (0201's codex #2).
     and (b.status = 'incident_review'
          or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
   -- ── the two documented differences (1) and (2) above ────────────────────────────────────────
     and ((v_min is not null and b.run_ended_at < now() - make_interval(mins => v_min))
          or exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_strand_title))
   order by b.run_ended_at, b.id;
end $$;
revoke execute on function ops_stranded_returns() from public, anon;
grant  execute on function ops_stranded_returns() to authenticated;

comment on function ops_stranded_returns is
  '0206 §A: 좌초된 반환 목록 — sweep_run_end_recovery 팔 ⓕ가 울리는 「반환 좌초 — 확인 필요」 종
뒤에 있던 **없던 목록**. 종은 ref_id 하나만 싣고(0084 §E) 클라에는 resolve_return을 부르는 곳이
하나도 없었다(트렁크 fde88a1에서 측정: app/ 전체에 resolve_return 참조 0건) — 즉 운영자는 psql로
불려갔다.
게이트는 **return_strand**이고 payout_due가 아니다: 그것이 ops_resolve_return_tx가 쓰는 명부이며,
payout_due로 잠그면 이름을 다 읽힌 뒤에 문이 not_ops로 거절하는 죽은 버튼이 된다(0206 §0b).
술어는 팔 ⓕ(0201:737-742)의 것을 **조항 그대로** 쓴다. 다른 점은 둘뿐이고 일부러다 — (1) 「이미
울린 종」 제외절이 뒤집혀 **포함**이 된다(목록의 존재 이유가 그 행들이다; 종 시각은 notified_at로
싣고 아직 안 울린 행은 NULL, 근사치로 채우지 않는다), (2) limit이 없다(잘린 목록은 운영자가 일부만
정리하고 큐가 비었다고 믿게 만든다 — 0198 §B와 같은 논거). 마감은 ops_flags에서 매번 새로 읽는다;
NULL(출하 기본값)이면 팔 ⓕ가 아무것도 안 하므로 목록도 **이미 종이 울린 행만** 보인다 — 읽기가
제 마음대로 숫자를 고르면 아무도 호출받지 않은 행을 보여주게 된다.
싣는 것: 예약 id · 개 이름 · 보호자/러너 표시 이름 · 원문 status(매핑 안 한 서버 낱말, 화면은
여기에 게이트만 건다) · 종료 시각 · 양측 스탬프 유무 · 좌초 경과 분 · 현재 마감 분 · 종 시각.
싣지 않는 것: 요금·순액·수수료 어느 칸도, 계좌, 전화, 주소, 그리고 운영 메모(0193:446 — 메모는
감사용이고 폰에 가지 않는다, 230 0199-V5가 핀). 237 0206-R1·R2·R3·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ops_stalled_handoffs — the rows behind the 「인계 확인 멈춤 — 확인 필요」 bell
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **A READ AND ONLY A READ.** 0183 arm ⓓ's header: 「NO status move — what a stuck pickup
--   handoff should become is a product decision (Sean's), not a clock's」. An operator button here
--   would be that same decision taken by whoever wrote this file. The list exists so the bell has
--   somewhere to land; the tools that already exist stay the tools.
--
-- ⚠ **THE PREDICATE IS 0183 arm ⓔ's RE-CHECK (0183:461-465), which is the strongest form of
--   「still stuck」 the sweep itself uses** — and it is the right one to copy rather than arm ⓓ's
--   CANDIDATE query, because ⓓ's extra conjuncts (`handoff_escalated_at is null`, the
--   ESCALATE_AFTER clock) are about 「has this been escalated YET」, and this list is about 「is it
--   still stuck NOW」. An escalated row that resolved must leave the list, and `0206-H2` measures
--   exactly that departure.
--
-- ⚠ **STATUS IS A DENY-LIST, NOT AN ALLOW-LIST**, and `c_dead` is 0183's fourteen literally
--   (0201:485-489, the constant arm ⓓ/ⓔ use). The attack-INACTION law: a status added to the enum
--   lands in this list by default — a spurious row in an ops queue is visible and cheap, while a
--   silently missing one is the failure this file exists to remove. 213 D7 / 212 C8 already anchor
--   the sweep's two spellings against each other; `0206-S1` anchors THIS third copy against the
--   deployed sweep's, so the three cannot part.
create or replace function ops_stalled_handoffs()
returns table (
  booking_id        uuid,
  dog_name          text,
  owner_name        text,
  runner_name       text,
  status            text,
  scheduled_at      timestamptz,
  owner_stamped     boolean,
  runner_stamped    boolean,
  stamped_at        timestamptz,
  minutes_stalled   int,
  escalated_at      timestamptz,
  ops_alerted_at    timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'handoff_unanswered';
  -- 0183 arm ⓓ/ⓔ's `c_dead`, literally (0201:485-489).
  c_dead constant booking_status[] := array['draft','quoted','payment_hold','matching','runner_pending',
                                            'picked_up','active','completed',
                                            'cancelled_owner','cancelled_runner','expired','no_show',
                                            'incident_review','refund_pending']::booking_status[];
  v_uid uuid := auth.uid();
begin
  -- ① PARTY GATE FIRST — before any read. Same shape and same ordering as §A.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         b.scheduled_at,
         (b.owner_confirmed_handoff_at is not null),
         (b.runner_confirmed_handoff_at is not null),
         x.stamped_at,
         floor(extract(epoch from (now() - x.stamped_at)) / 60)::int,
         b.handoff_escalated_at,
         -- 🔴 NULL here with `escalated_at` set is NOT an absence of information — it is 0183's
         --    durable PENDING state: the parties were told while the ops roster was empty, and
         --    arm ⓔ retries every tick. The client must say so in words rather than draw a blank
         --    (api.ts:1333 already records that reading for the party-facing screen).
         b.handoff_ops_alerted_at
    from bookings b
    cross join lateral (
      select coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) as stamped_at
    ) x
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── 0183 arm ⓔ's predicate (0183:461-465) ──────────────────────────────────────────────────
   where b.handoff_escalated_at is not null
     and (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
     and b.runner_id is not null
     and not (b.status = any(c_dead))
   order by b.handoff_escalated_at, b.id;
end $$;
revoke execute on function ops_stalled_handoffs() from public, anon;
grant  execute on function ops_stalled_handoffs() to authenticated;

comment on function ops_stalled_handoffs is
  '0206 §B: 한쪽만 확인한 채 멈춘 인계 목록 — 0183 팔 ⓓ/ⓔ가 handoff_unanswered 명부에 울리는
「인계 확인 멈춤 — 확인 필요」 종 뒤에 있던 **없던 목록**. handoff_escalated_at /
handoff_ops_alerted_at 을 운영자 쪽에서 읽는 곳이 하나도 없었다(api.ts:1333은 **당사자** 한 명이
자기 예약 하나를 읽는 경로다).
**읽기이고 읽기뿐이다.** 0183 팔 ⓓ의 헤더 그대로 — 멈춘 인계가 무엇이 되어야 하는지는 시계가
아니라 제품 결정(Sean)이고, 여기 버튼을 다는 것은 그 결정을 이 파일이 대신 내리는 일이다.
게이트는 **handoff_unanswered** — 승격을 실제로 받는 명부. 술어는 팔 ⓔ의 재확인(0183:461-465)을
쓴다(팔 ⓓ의 후보 쿼리가 아니라): ⓓ의 추가 조항은 「아직 승격 안 했나」를 묻고 이 목록은 「지금도
멈춰 있나」를 묻는다. 해결된 행은 목록에서 빠져야 하고 237 0206-H2가 그 이탈을 잰다.
status는 **부정 목록**이다(c_dead 열넷, 0183의 것 그대로): enum에 값이 생기면 기본값으로 이 목록에
들어온다 — 운영 큐의 가짜 행은 보이고 싸지만, 조용히 빠진 행은 이 파일이 없애려는 실패 그 자체다.
ops_alerted_at이 NULL인데 escalated_at이 있으면 정보가 없는 게 아니라 0183의 **PENDING**이다 —
명부가 비어 있던 승격이고 팔 ⓔ가 틱마다 다시 시도한다. 화면은 이것을 말로 적어야 한다.
싣는 것: 예약 id · 개 이름 · 양측 표시 이름 · 원문 status · 예정 시각 · 어느 쪽이 찍었나 · 그 스탬프
시각과 경과 분 · 승격 시각 · ops 전달 시각. 싣지 않는 것: 돈 어느 칸도, 전화, 주소.
237 0206-H1·H2·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C claim_gear_tx — the claim finally rings a bell
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 **RE-DECLARED FROM 0195 §B's BODY, WHICH IS THE LATEST — MEASURED, NOT ASSUMED.**
--    `grep -n "function claim_gear_tx" supabase/migrations/*.sql` on trunk `fde88a1` returns
--    0195:181 and nothing else; 0202 touched `ops_gear_claims_pending` and
--    `ops_mark_gear_shipped` (its §B③/§B④) and did NOT re-declare this one. Steps ①–⑧ below are
--    0195's verbatim; the only addition is ⑦b.
--
-- ⚠ **THE ACL IS RESTATED IN THIS FILE, and that is a house law rather than a courtesy.** A
--   `create or replace` preserves an ACL only where the function ALREADY exists; on an apply where
--   it does not (a partial prior apply, a rebuilt environment) this statement is a plain CREATE
--   and the definer is born PUBLIC-executable (0116:636). `check-definer-acl.mjs` refuses exactly
--   this shape when the ACL is absent.
--
-- ⚠ **WHERE THE BELL SITS IS THE WHOLE IDEMPOTENCY ARGUMENT.** It is AFTER ⑦'s asserted write and
--   therefore BELOW ④'s `already_claimed` early return — so a runner re-tapping the button writes
--   no second row, and a claim that REFUSES (not_claim_owner, not_claimable, bad_postal, …) writes
--   none at all, because every one of those paths has already left the function. There is no
--   `not exists` dedupe guard beside it and that omission is deliberate: if an operator ever
--   repairs a row back to `claimable` and the runner claims again, that IS a new box to post and
--   the roster SHOULD hear about it. A guard would have silently swallowed the one case where the
--   bell matters most. 237 `0206-G1` measures the property (exactly one row after two calls, none
--   after a refusal) rather than the guard.
--
-- ⚠ **THE BODY CARRIES NO IDENTIFIER** — 0084 §E: an ops row's body is pushed verbatim to a lock
--   screen, and a wrong recipient id then discloses it to a stranger. The claim id rides in
--   `ref_id`, exactly as 0183:428 and 0193:920 do it, and the client routes on that.
create or replace function claim_gear_tx(
  p_claim_id uuid,
  p_recipient text,
  p_phone text,
  p_address1 text,
  p_address2 text,
  p_postal text
) returns table (
  claim_id        uuid,
  status          text,
  claimed_at      timestamptz,
  already_claimed boolean,
  carrier         text,
  tracking        text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  -- the class `ops_gear_claims_pending` / `ops_mark_gear_shipped` gate on (0195 §0f) — the people
  -- who can actually open the list this bell points at. §0b.
  c_ops_class constant text := 'payout_due';
  c_ops_title constant text := '굿즈 수령 신청 — 확인 필요';
  c_ops_body  constant text := '굿즈 수령 신청이 들어왔어요. 배송 대기 목록을 확인해 주세요.';
  v_uid       uuid := auth.uid();
  v_owner     uuid;
  v_status    text;
  v_claimed   timestamptz;
  v_carrier   text;
  v_tracking  text;
  v_recipient text;
  v_phone     text;
  v_addr1     text;
  v_addr2     text;
  v_postal    text;
  v_n         int;
  v_ops       int;
begin
  -- ① THE LOCK, and the owner is the ONLY thing read from it.
  if v_uid is null       then raise exception 'not_signed_in';   end if;
  if p_claim_id is null  then raise exception 'claim_not_found'; end if;
  select g.profile_id into v_owner from gear_claims g where g.id = p_claim_id for update;
  if not found then raise exception 'claim_not_found'; end if;

  -- ② PARTY GATE on the locked row, ahead of every state gate and ahead of the form.
  --    `is distinct from` rather than `<>`: a NULL owner must refuse, not disappear.
  if v_owner is distinct from v_uid then raise exception 'not_claim_owner'; end if;

  -- ③ only now is the state readable. Same locked row, same transaction.
  select g.status::text, g.claimed_at, g.delivery_carrier, g.delivery_tracking
    into v_status, v_claimed, v_carrier, v_tracking
    from gear_claims g where g.id = p_claim_id;

  -- ④ IDEMPOTENCY, before the form is judged (0195 §0e). Writes nothing, raises nothing, and
  --    reports the row as it stands — including a carrier, if ops has already posted it.
  if v_status in ('claimed', 'shipped') then
    return query select p_claim_id, v_status, v_claimed, true, v_carrier, v_tracking;
    return;
  end if;

  -- ⑤ state gate. The only remaining values are `locked` and `claimable`; `locked` is the refusal
  --    a runner can act on. Written positively so an unexpected value refuses rather than passes.
  if v_status is distinct from 'claimable' then raise exception 'not_claimable'; end if;

  -- ⑥ the form. Phone is reduced to its digits because that is what a courier dials and what an
  --    operator must be able to compare — 010-1234-5678 and 01012345678 are the same number, and
  --    storing both spellings makes a duplicate look like two people.
  v_recipient := btrim(coalesce(p_recipient, ''));
  v_addr1     := btrim(coalesce(p_address1, ''));
  v_addr2     := nullif(btrim(coalesce(p_address2, '')), '');
  v_phone     := regexp_replace(coalesce(p_phone,  ''), '[^0-9]', '', 'g');
  v_postal    := regexp_replace(coalesce(p_postal, ''), '[^0-9]', '', 'g');
  if v_recipient = ''                 then raise exception 'bad_recipient'; end if;
  if length(v_phone) not between 10 and 11 then raise exception 'bad_phone'; end if;
  if v_addr1 = ''                     then raise exception 'bad_address';   end if;
  if v_postal !~ '^[0-9]{5}$'         then raise exception 'bad_postal';    end if;

  -- ⑦ the write. `status = 'claimable'` is restated in the WHERE although the row is locked, and
  --    the count is ASSERTED rather than assumed — 0186 §C's `mark_lost` idiom. A claim that
  --    reports success while writing nothing is the exact failure 0195 exists to remove.
  update gear_claims g
     set status       = 'claimed',
         claimed_at   = now(),
         delivery     = jsonb_build_object(
                          'recipient', v_recipient,
                          'phone',     v_phone,
                          'address1',  v_addr1,
                          'address2',  v_addr2,
                          'postal',    v_postal)
   where g.id = p_claim_id and g.status = 'claimable';
  get diagnostics v_n = row_count;
  if v_n is distinct from 1 then raise exception 'claim_race'; end if;

  -- ⑦b [0206 §C] THE BELL. Reached only from the one path that actually moved a row to `claimed`
  --     (see the header): after ⑦'s asserted write, below ④'s early return, below every raise.
  --     An EMPTY ROSTER writes nothing and is the honest answer — the claim still succeeded and
  --     `ops_gear_claims_pending()` still lists it, so the box is not lost, only unannounced. The
  --     count is put in a NOTICE rather than swallowed, exactly as 0183:442 and 0193:772 do it.
  insert into notifications (profile_id, kind, title, body, ref_id)
  select rc.profile_id, 'system'::noti_kind, c_ops_title, c_ops_body, p_claim_id
    from ops_recipients_for(c_ops_class) as rc(profile_id);
  get diagnostics v_ops = row_count;
  raise notice 'claim_gear_tx: claim % — 수령 신청 접수: ops 수신자 %명 (%)',
    p_claim_id, v_ops,
    c_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (신청 자체는 접수됨)' else '' end;

  -- ⑧ the answer is READ BACK from the written row, never composed from the inputs. The client
  --    re-renders from this, so anything it reports must be what the table actually holds.
  return query
    select g.id, g.status::text, g.claimed_at, false, g.delivery_carrier, g.delivery_tracking
      from gear_claims g where g.id = p_claim_id;
end $$;
revoke execute on function claim_gear_tx(uuid, text, text, text, text, text) from public, anon;
grant  execute on function claim_gear_tx(uuid, text, text, text, text, text) to authenticated;

comment on function claim_gear_tx is
  '0195 §B + **0206 §C**: 러너가 자기 굿즈 교환권을 수령 신청한다. 한 트랜잭션, definer. 순서는
잠금 → 파티 게이트(not_claim_owner) → 상태 읽기 → 이미 신청함(already_claimed 플랫 필드, 예외
아님) → 상태 게이트(not_claimable) → 양식 검증(bad_recipient/bad_phone/bad_address/bad_postal) →
쓰기 → **ops 종** → 되읽기.
**파티 게이트가 상태를 읽기 전에 온다** — 남의 교환권 id를 넣은 사람은 그 교환권이 어떤 상태인지
배우지 못한다. 멱등성: 같은 주인이 같은 행을 두 번 신청하면 already_claimed=true로 현재 행을
그대로 돌려주고 아무것도 쓰지 않는다(0195 §0e). shipped도 같은 쪽이다.
[0206 §C] 종이 하나 늘었다 — payout_due 명부에 kind=system, 제목 「굿즈 수령 신청 — 확인 필요」,
ref_id=교환권 id. 0195 §0는 「notifications untouched」였고 그래서 이 큐만 종 없이 목록만 있었다:
운영자가 마침 들여다볼 때까지 상자가 안 나간다. 자리는 ⑦ 쓰기 **뒤**이므로 ④ 조기 반환보다
아래이고 모든 raise보다 아래다 — 재탭도, 거절된 신청도 행을 쓰지 않는다. 중복 방지 절은 일부러
없다: 운영자가 행을 claimable로 되돌려 다시 신청되면 그건 **새로 부칠 상자**이고 명부는 들어야
한다. 본문에는 식별자가 없다(0084 §E — ops 본문은 잠금화면에 그대로 뜬다); 명부가 비면 아무것도
안 쓰고 NOTICE로 그렇게 말한다. 226 0195-C1~C5 + 237 0206-G1·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D VERIFY — this apply fails rather than ships a half-built gate
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ These arms and `237_ops_console_v2_suite.sql` are DIFFERENT ARTIFACTS and neither is evidence
--   for the other: this aborts a production apply that lands wrong; the suite reddens when a LATER
--   file undoes something (0131-G4's law — a property checked only at apply is protected exactly
--   until someone recreates the function).
-- ⚠ Source matching strips comments FIRST. This file documents its own guards at length, and a
--   check that the gate is CALLED would otherwise be satisfied by the paragraph EXPLAINING it —
--   the better the explanation, the more certainly green (the comment-matching law).
-- ⚠ Every arm asserts an EXACT boolean (`is not true` / `is distinct from`). A bare `IF` over a
--   NULL predicate is silent, and every arm here exists to notice something MISSING — which is
--   precisely the state that makes `prosrc` NULL.
do $verify$
declare
  v_bad text := '';
  v_oid oid;
  v_src text;
  v_sweep text;
  fn    text;
  fns   text[] := array['ops_stranded_returns()', 'ops_stalled_handoffs()',
                        'claim_gear_tx(uuid,text,text,text,text,text)'];
begin
  foreach fn in array fns loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') = 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':SEARCH-PATH'; end if;
    -- A definer born PUBLIC-executable is the worst shape this repo can produce (0116:636), and
    -- `create or replace` preserves an ACL only where the function ALREADY exists. Both directions.
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC-EXEC'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':ANON-EXEC'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':NO-AUTHENTICATED'; end if;
  end loop;

  -- §0b's structural claim: neither list takes an argument, so neither can be pointed at a third
  -- party's booking. A future `ops_stranded_returns(p_booking uuid)` aborts the apply here.
  foreach fn in array array['ops_stranded_returns()', 'ops_stalled_handoffs()'] loop
    if (select pronargs from pg_proc where oid = to_regprocedure(fn)) is distinct from 0
      then v_bad := v_bad || ' ' || fn || ':TAKES-ARGUMENTS'; end if;
  end loop;

  -- the deployed sweep, comment-stripped — the source of truth both lists are copied FROM
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_sweep
    from pg_proc where oid = to_regprocedure('sweep_run_end_recovery()');
  if v_sweep is null then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)'; end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_stranded_returns()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_stranded_returns)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' strand:NO-OPS-GATE'; end if;
    if (position('raise exception ''not_ops''' in v_src)
        < position('from bookings b' in v_src)) is not true
      then v_bad := v_bad || ' strand:GATE-AFTER-READ'; end if;
    if (v_src ~ 'c_ops_class\s+constant text := ''return_strand''') is not true
      then v_bad := v_bad || ' strand:WRONG-ROSTER'; end if;
    -- arm ⓕ's predicate, carried textually. Not 「equivalent」 — the same clause, so a future edit
    -- to one is visible against the other.
    if (v_src ~ 'b\.settlement_ready_at is null') is not true
      then v_bad := v_bad || ' strand:NO-UNSEALED-CLAUSE'; end if;
    if (v_src ~ 'b\.status = ''incident_review''\s*or not \(b\.runner_confirmed_return_at is not null and b\.owner_confirmed_return_at is not null\)') is not true
      then v_bad := v_bad || ' strand:NOT-0201-TWO-STATE-CLAUSE'; end if;
    if (v_src ~ 'make_interval\(mins => v_min\)') is not true
      then v_bad := v_bad || ' strand:NO-DEADLINE'; end if;
    -- and the title it keys `notified_at` on is the SWEEP'S, not a second spelling
    if v_sweep is not null and (position('''반환 좌초 — 확인 필요''' in v_sweep) > 0) is not true
      then v_bad := v_bad || ' sweep:STRAND-TITLE-MOVED'; end if;
    if (position('''반환 좌초 — 확인 필요''' in v_src) > 0) is not true
      then v_bad := v_bad || ' strand:TITLE-NOT-THE-SWEEPS'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_stalled_handoffs()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_stalled_handoffs)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' handoff:NO-OPS-GATE'; end if;
    if (position('raise exception ''not_ops''' in v_src)
        < position('from bookings b' in v_src)) is not true
      then v_bad := v_bad || ' handoff:GATE-AFTER-READ'; end if;
    if (v_src ~ 'c_ops_class\s+constant text := ''handoff_unanswered''') is not true
      then v_bad := v_bad || ' handoff:WRONG-ROSTER'; end if;
    if (v_src ~ 'b\.handoff_escalated_at is not null') is not true
      then v_bad := v_bad || ' handoff:NO-ESCALATED-CLAUSE'; end if;
    if (v_src ~ '\(b\.owner_confirmed_handoff_at is null\) <> \(b\.runner_confirmed_handoff_at is null\)') is not true
      then v_bad := v_bad || ' handoff:NO-ONE-SIDED-CLAUSE'; end if;
    -- the deny-list is 0183's fourteen, and the two spellings are compared against the DEPLOYED
    -- sweep rather than against a constant in this file (which would compare it to itself).
    if (v_src ~ 'not \(b\.status = any\(c_dead\)\)') is not true
      then v_bad := v_bad || ' handoff:STATUS-NOT-A-DENY-LIST'; end if;
    if v_sweep is not null and (position('''refund_pending''' in v_sweep) > 0) is not true
      then v_bad := v_bad || ' sweep:DEAD-LIST-MOVED'; end if;
    if (position('''refund_pending''' in v_src) > 0) is not true
      then v_bad := v_bad || ' handoff:DEAD-LIST-INCOMPLETE'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('claim_gear_tx(uuid,text,text,text,text,text)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
  else
    if (position('''굿즈 수령 신청 — 확인 필요''' in v_src) > 0) is not true
      then v_bad := v_bad || ' gear:NO-OPS-BELL'; end if;
    -- 0195's party gate still ahead of the state read (nothing about this slice may soften it)
    if (position('raise exception ''not_claim_owner''' in v_src)
        < position('not_claimable' in v_src)) is not true
      then v_bad := v_bad || ' gear:PARTY-GATE-MOVED'; end if;
    -- 🔴 the bell is BELOW the idempotent early return and BELOW the asserted write. If it ever
    --    rises above either, a re-tap or a refused claim pages the roster.
    -- ⚠ The anchor is the early return's PREDICATE, not the word `already_claimed` — that word is
    --   a RETURNS-TABLE column name and `prosrc` carries only the BODY, so an arm keyed on it
    --   would compare `0 < n`, which is TRUE, and pass no matter where the bell sat. Measured
    --   before this arm was trusted: 0195's body never spells it.
    if (position('v_status in (''claimed'', ''shipped'')' in v_src) > 0) is not true
      then v_bad := v_bad || ' gear:NO-IDEMPOTENT-RETURN'; end if;
    if (position('v_status in (''claimed'', ''shipped'')' in v_src)
        < position('insert into notifications' in v_src)) is not true
      then v_bad := v_bad || ' gear:BELL-ABOVE-IDEMPOTENT-RETURN'; end if;
    if (position('raise exception ''claim_race''' in v_src)
        < position('insert into notifications' in v_src)) is not true
      then v_bad := v_bad || ' gear:BELL-ABOVE-WRITE-ASSERT'; end if;
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' gear:BELL-NOT-THROUGH-ROSTER-WINDOW'; end if;
  end if;

  if v_bad <> '' then raise exception '0206 §D VERIFY:%', v_bad; end if;
end $verify$;
