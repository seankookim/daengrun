-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0201 — the ops memo stops being party-readable, and a LATE pair of stamps stops hiding a strand
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 232_strand_memo_and_late_stamps_suite.sql (tag `sml`) — 0201-M1 · M2 · L1 · G1 · S1
--
-- ═══ §0a WHAT THIS FILE IS — three of Codex's five REJECT findings, corrected FORWARD ═════════
-- `docs/reviews/2026-09-22-post-reset-codex-verdict.md`. **0193 and 0199 are NOT edited** (they
-- landed); 0002, 0083, 0089 and 0096 are not edited either. Findings 3 and 4 belong to `0202`
-- (`be/0202-bank-delivery-fixes`) and nothing here touches 0194/0195 or `delete_my_account_tx`.
--
--   **#1 (high)** `0193:525-532` — 「the private ops memo is directly readable by both parties」.
--     `ops_resolve_return_tx` copies `v_memo` into `bookings.return_force_reason`; `authenticated`
--     holds table-level SELECT on `bookings` (only `0111:174` narrows it, and only for INSERT) and
--     `bookings party read` (`0002:92`) scopes it to the two parties — so either party reads the
--     operator's private note straight out of PostgREST. 0199's fixed `note_public` and the sealed
--     `return_resolutions` journal protect the RPC and nothing else; 230 only tested the RPC.
--     §A re-declares the resolver so the party-readable column carries a FIXED TOKEN keyed by the
--     state the booking was rescued from, and the memo lives ONLY in the sealed journal. §B scrubs
--     the copies 0193 would already have written.
--
--   **#2 (high)** `0193:891-895` — 「late confirmations remove unpaid cases from ops escalation」.
--     Arm ⓑ-① escalates a zero-stamp return to `incident_review`; `confirm_return_tx` then accepts
--     BOTH late stamps and deliberately does not seal or settle (0096) — and arm ⓕ's candidate
--     predicate excludes the row precisely because both stamps now exist. With
--     `return_strand_minutes = 180`, two parties confirming after the two-hour timeout and before
--     the three-hour deadline buy themselves **no ops alert at all**: the run stays unsettled and
--     the runner stays work-gated (0092) forever, and nothing anywhere reports it. §D widens the
--     eligibility in BOTH the candidate query and the locked-row recheck: an UNSEALED
--     `incident_review` return is a strand regardless of how many stamps it carries.
--
--   **#5 (medium)** `resolve_return.ts:83-96` — 「pricing exposes another booking's run state
--     before authorization」. That is fixed in the EDGE (`transition-booking/index.ts` +
--     `resolve_return.ts`); §C is the one SQL object it needs — `ops_is_member`, so the
--     service-role client can answer 「is this verified caller on the roster」 BEFORE it reads a
--     booking or prices anything. The SQL gate inside `ops_resolve_return_tx` is UNCHANGED and is
--     still the rule; the edge check is a second, earlier refusal, not a replacement.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - 🔴 **`force_return_tx` WRITES FREE TEXT TO THE SAME COLUMN AND IS LEFT ALONE — named, not
--   missed.** Finding #1's SENTENCE («an operator's private note must not land in a party-readable
--   column») covers `0089:132` as well as `0193:525`, and the house law says to enumerate every
--   site a finding's sentence covers. Enumerated, and left, for three measured reasons: (a) it has
--   **zero callers** — `grep -rn force_return_tx` over `supabase/functions/`, `app/` and `scripts/`
--   returns only comments, the same measurement 0193 §0 made and re-made here; (b) its `p_reason`
--   is typed by the same person who chooses to call it from psql, so there is no product surface
--   feeding it a note written for operators; (c) re-declaring a second ~150-line body to change a
--   string nobody writes is blast radius bought for nothing. **If that function ever gains a
--   caller, this is its bill.** `0201-S1` does not pin it — a pin over `force_return_tx`'s current
--   shape would be a pin that fixes the bug in place.
-- - It does not change `return_force_evidence`, which still carries `from_status`, the two stamp
--   booleans and `resolved_by` and is likewise party-readable. That blob is 0083 §1's dispute
--   record («the row a dispute is read from»), none of it is free text an operator composed, and
--   the one arguable item — an ops profile UUID — is a decision about what a dispute record
--   contains rather than a memo leak. Recorded here so the next reader can see it was looked at.
-- - It does not pick `return_strand_minutes`. NULL still ships and still means arm ⓕ does nothing;
--   §D changes WHICH rows the arm considers, never whether it runs (Sean's queue item 23).
-- - It does not touch the sealed-but-unsettled row, `_settle_sealed_run`, any money arithmetic, or
--   0089's rule that no party stamp is ever forged.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON ════════════════════════════════════════════════════════
-- Re-declares TWO, both last declared in 0193: `ops_resolve_return_tx` (§C-b) and
-- `sweep_run_end_recovery` (§D). Creates TWO: `ops_is_member`, `_scrub_ops_return_reasons`.
-- Adds no column, no table, no enum, no policy, no trigger.
--
-- ⚠ **BOTH BODIES WERE COPIED BY SCRIPT FROM 0193's TEXT, NOT BY HAND** — 0193 §D's own discipline,
--   for its own reason (a hand copy of 550 lines is how a comment-level difference becomes a
--   behavioural one). Each anchor was asserted present EXACTLY ONCE before the edit and absent
--   after it, and `sweep_run_end_recovery`'s text from the literal line
--   `  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED` to `end $$;` is asserted **byte-for-byte equal to
--   0193's**, so arms ⓒ · ⓓ · ⓔ are provably untouched. The executable `for update skip locked`
--   count is still 5 (six in the raw text — the sixth is arm ⓒ's own prose, which is exactly why
--   every source check in this repo strips comments first).
--
-- ═══ §0d DOCTRINE ═══════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated in THIS file ·
-- party/ops gate before any read on the LOCKED row · `is distinct from` / `is not true`, never a
-- bare `IF` on a nullable predicate · comments stripped before every `prosrc` match · pins in
-- `232_strand_memo_and_late_stamps_suite.sql`.
--
-- ═══ §0e TWO SHIPPED PINS MOVE IN THIS SLICE, AND THEY MOVE FOR A TRUE REASON ═════════════════
-- Both asserted the defect, correctly, as of the day they were written:
--   · `224:342` (`0193-R1`) — 「`bookings.return_force_reason` equals the memo」. Now asserts the
--     FIXED TOKEN and that the memo is absent. `0201-M1` owns the new property.
--   · `230:318` (`0199-V5`) — the second of two CONTROL arms, 「the sentinel really is in
--     `bookings.return_force_reason`」, which existed so V5's absence arms were not standing over
--     an empty world. The journal control (arm ①) still does that job and is untouched; this arm
--     becomes its opposite — the memo must NOT be in the column — and names `0201-M1`.
-- Leaving either stale would have made the harness red for a true reason, which the house law
-- forbids: update the pin, say why, name the pin that owns the new property.
--
-- ═══ §0f DEPLOY ═════════════════════════════════════════════════════════════════════════════
--   1. `supabase db push`  — this file. 0193 and 0199 must already be applied.
--   2. `supabase functions deploy transition-booking`  — **STRICTLY AFTER** the push. The edge's
--      new pre-flight calls `ops_is_member`, which does not exist until step 1; an edge deployed
--      first answers every `resolve_return` with a 403 whose cause is a missing function rather
--      than a missing roster row. The reverse order fails CLOSED (nobody resolves anything), which
--      is the safe direction and still the wrong one.
--   3. Nothing else. No cron, no secret, no table, no client build. §B's scrub runs inside the
--      push and reports its count; on this deployment (production is at `0156`, 0193 has never been
--      applied) that count is **0**, and that zero is a measurement rather than a hope.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A ops_resolve_return_tx — the memo stays in the journal; the booking gets a TOKEN
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0193 §C-b's body, copied by script, with exactly ONE behavioural change: the UPDATE writes
-- `v_reason` — a fixed token the `case` picks from the state the row was rescued from — where it
-- used to write `v_memo`. Everything else (the server-only caller class, the ops gate ahead of the
-- lock, the state gates on the LOCKED row, the journal insert, `_settle_sealed_run`, the response)
-- is 0193's, unchanged.
--
-- 🔴 **WHY A TOKEN AND NOT A KOREAN SENTENCE.** `return_force_reason` is not display vocabulary and
-- must not become it: `grep -rn return_force_reason app/` is **0** and the standing STATUS_MAP law
-- says a client gates on raw server words and never prints them. 0199 already owns the one sentence
-- a party is shown (`note_public`, chosen SERVER-side from `from_status` so an un-rebuilt binary
-- cannot meet an unmapped key), and this column is the machine-readable sibling of that choice —
-- same key, different register. Putting a second Korean sentence here would create a second copy
-- of product copy that nobody wrote, reviewed or translated, in the column a party can read
-- directly.
--
-- ⚠ **THE `case` IS THREE-ARMED ON PURPOSE.** 0193's gate admits exactly `active` and
-- `incident_review` today; the `else` exists so a third state a later slice learns to rescue gets a
-- true token instead of NULL. A NULL there would be indistinguishable from 「this booking was never
-- adjudicated」 to every reader of the column, which is the one thing it must never say.
--
-- ⚠ The memo is still REQUIRED (`memo_required`) and still lands in `return_resolutions.memo`. The
-- finding is about WHERE it is readable, never about whether an operator must write one.
create or replace function ops_resolve_return_tx(
  p_booking uuid, p_quote jsonb default null, p_memo text default null, p_actor uuid default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_ops_class constant text := 'return_strand';
  b record;
  v_uid     uuid := auth.uid();
  v_now     timestamptz := now();
  v_memo    text;
  v_from    text;
  v_reason  text;
  v_settled jsonb := null;
  v_res     uuid;
begin
  -- ① SERVER ONLY (0089 §6's line, verbatim in substance).
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;
  -- ② THE OPS PARTY GATE, ahead of every state gate and ahead of the lock (0186 §C ①'s order and
  --    its membership test, reused rather than re-invented). `is not true`, so a NULL from any
  --    cause refuses instead of passing.
  if p_actor is null then raise exception 'ops_actor_required'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = p_actor)) is not true
  then raise exception 'not_ops'; end if;

  -- ③ arguments.
  if p_quote is null then raise exception 'quote_required'; end if;
  v_memo := nullif(btrim(coalesce(p_memo, '')), '');
  -- An adjudication with no sentence is just an assertion wearing a uniform (0089's words).
  if v_memo is null then raise exception 'memo_required'; end if;

  -- ④ THE LOCK.
  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ⑤ state gates on the LOCKED row. The club wall stays ABOVE the status gate, as 0096 §6 and
  --    0188 do, so a club booking is refused by its own name rather than by a status accident.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;
  if b.status = 'completed' then
    return jsonb_build_object('resolved', false, 'settled', true, 'unchanged', true);
  end if;
  -- The two states a STRAND can be in, and nothing else. `incident_review` is identified by the
  -- FACTS 0188 ⓑ-① leaves behind (a run that ended, no seal) and never by a free-text reason —
  -- a reason string is prose and this is a money gate.
  if b.status not in ('active', 'incident_review') then raise exception 'not_resolvable'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;
  -- A sealed row is arm ⓐ's subject and needs a pricing RE-DRIVE (0083 §0f), not an adjudication.
  -- Refused by name rather than half-handled — see §0b.
  if b.settlement_ready_at is not null then raise exception 'already_sealed'; end if;
  -- Both stamps present with no seal means `incident_review` with two late confirmations. The
  -- parties agree; there is nothing to adjudicate and nothing MISSING to record. That row is the
  -- other half of A2 and it is resolved the same way — through this door, because 0096 refuses to
  -- seal it — so it is deliberately NOT refused here. (Kept as an explicit note rather than a
  -- conjunct: the temptation to add `both_confirmed` as a refusal is exactly what would re-create
  -- codex's A2 for the case where both parties DID say the dog is home.)

  -- ⑥ THE ADJUDICATION. One UPDATE, because §C-a's trigger arm reads `new.return_forced_by` and
  --    `new.status` together: splitting it would refuse itself.
  v_from := b.status;
  v_reason := case v_from
                when 'active'          then 'ops_resolved:strand'
                when 'incident_review' then 'ops_resolved:review'
                else                        'ops_resolved'
              end;
  update bookings
     set status                = 'active',
         return_forced_by      = 'ops',
         return_forced_at      = v_now,
         return_force_reason   = v_reason,
         return_force_evidence = jsonb_build_object(
           'source', 'ops_resolve_return_tx',
           'from_status', v_from,
           'runner_stamped', (b.runner_confirmed_return_at is not null),
           'owner_stamped',  (b.owner_confirmed_return_at is not null),
           'resolved_by', p_actor,
           'resolved_at', v_now),
         settlement_ready_at   = v_now
   where id = p_booking;

  insert into return_resolutions (booking_id, resolved_by, from_status,
                                  runner_stamped, owner_stamped, memo)
  values (p_booking, p_actor, v_from,
          (b.runner_confirmed_return_at is not null),
          (b.owner_confirmed_return_at is not null), v_memo)
  returning id into v_res;

  -- ⑦ SETTLE THROUGH THE SAME DOOR THE SECOND STAMP USES. `_settle_sealed_run` is THE settlement
  --    primitive (0083 §6) and re-reads the frozen measurement under its own lock; nothing about
  --    money is computed, copied or decided here. Collection is the edge's half, exactly as it is
  --    for `confirm_return` (`_shared/charge.ts` → `collectAfterSettle`), so the two doors cannot
  --    drift.
  v_settled := _settle_sealed_run(p_booking, p_quote);

  raise notice 'ops_resolve_return_tx: booking % resolved from % by % — runner_stamped=% owner_stamped=%',
    p_booking, v_from, p_actor,
    (b.runner_confirmed_return_at is not null), (b.owner_confirmed_return_at is not null);

  return jsonb_build_object(
    'resolved', true,
    'resolution_id', v_res,
    'from_status', v_from,
    'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false),
    'runner_stamped', (b.runner_confirmed_return_at is not null),
    'owner_stamped', (b.owner_confirmed_return_at is not null));
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited (`check-definer-acl.mjs`'s class): `create or
-- replace` preserves an ACL only where the function already exists, and on an apply where it does
-- not this statement is a plain CREATE whose definer is born PUBLIC-executable (0116:636).
revoke execute on function ops_resolve_return_tx(uuid, jsonb, text, uuid) from public, anon, authenticated;
grant  execute on function ops_resolve_return_tx(uuid, jsonb, text, uuid) to service_role;

comment on function ops_resolve_return_tx is
  '0201 §A (codex 2026-09-22 #1) — 0193 §C-b의 본문을 스크립트로 복사하고 **한 줄만** 바꿨다:
운영 메모는 이제 봉인된 return_resolutions 저널에만 남고, 당사자가 읽을 수 있는
bookings.return_force_reason에는 **구조된 상태가 고르는 고정 토큰**만 쓴다
(active → ops_resolved:strand · incident_review → ops_resolved:review · 그 밖 → ops_resolved).
authenticated는 bookings에 테이블 SELECT를 갖고 0002:92가 그것을 당사자 두 명으로 좁히므로,
메모를 이 칸에 쓰면 PostgREST 한 줄로 양측이 그대로 읽는다 — 0199의 note_public도 저널 봉인도
그 두 번째 사본을 막지 못했다. 토큰이지 문장이 아닌 이유: 이 칸은 표시 어휘가 아니고(app/에서
참조 0건, STATUS_MAP 법), 당사자가 보는 한 문장은 0199가 이미 소유한다. 나머지는 전부 0193
그대로 — 서버 전용 호출자, 잠금보다 앞선 ops 명부 게이트, 잠긴 행 위의 상태 게이트, 저널,
_settle_sealed_run. 메모는 여전히 필수다(memo_required). 232 0201-M1·S1이 핀.';

-- The column's own comment is amended rather than left to contradict the code. 0083 §1 called it
-- 「the actor's stated reason」, which is still true of `force_return_tx` and is no longer true of
-- the ops resolver — and a column comment that is true of one writer and false of another is how
-- the next session writes a memo back into it in good faith.
comment on column bookings.return_force_reason is
  '0083 §1, amended by 0201 §A — the recorded reason for a return force. ⚠ TWO WRITERS, TWO
REGISTERS. `force_return_tx` (0089 §6) still writes the actor''s free text. `ops_resolve_return_tx`
(0193 §C-b, as re-declared by 0201 §A) writes a FIXED TOKEN keyed by the rescued-from state
(`ops_resolved:strand` | `ops_resolved:review` | `ops_resolved`) and **never the operator''s memo**,
because `authenticated` holds table SELECT on `bookings` and `0002:92` scopes it to the two parties:
anything written here is read by both of them. The memo lives in the sealed `return_resolutions`
journal (0193 §A); the one sentence a party is shown is `my_return_resolution.note_public` (0199 §A).
Recorded immutably either way — neither writer overwrites an existing force. 232 0201-M1 pins it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B _scrub_ops_return_reasons — the copies 0193 would already have written
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- A FUNCTION called once below, not an inline DO block, and the reason is 0193 §F's law rather than
-- style: a one-time block has already run by the time any suite connects, so no pin could ever
-- redden it and its green would license nothing. As a function the property is falsifiable — 232
-- `0201-M2` builds the pre-0201 shape and calls it.
--
-- 🔴 **IDENTIFIED BY THE JOURNAL JOIN, NEVER BY TEXT.** 「a reason that looks like a memo」 is not a
-- checkable property: an operator's sentence and a hand-typed `force_return_tx` reason are the same
-- kind of string. What IS checkable is provenance — `return_resolutions` has exactly one writer
-- (`ops_resolve_return_tx`), so a booking carrying a journal row is a booking this resolver
-- adjudicated, and that is the set. `force_return_tx`'s rows write no journal row and are therefore
-- outside the join BY CONSTRUCTION rather than by a filter someone has to remember.
--
-- ⚠ `distinct on` picks the LATEST journal row per booking. There is no uniqueness constraint on
--   `booking_id` (0193:144-155) and today the resolver short-circuits on a `completed` row so a
--   second row cannot appear — but an UPDATE … FROM over a one-to-many join picks an arbitrary
--   partner, and 「arbitrary」 is not a thing to leave in a repair that runs once.
-- ⚠ The final conjunct compares against the value about to be WRITTEN, so the scrub is idempotent
--   and a second run returns 0. It is deliberately not a text sniff of the memo: after the first
--   run the column holds the token, and 「is it already right」 is the honest question.
-- ⚠ **VACUOUS ON THIS DEPLOYMENT AND KEPT ANYWAY**, for 0193 §F's reason: production is at `0156`,
--   0193 has never been applied, so no row can match. It ships because the environment where it is
--   NOT vacuous is the one nobody is looking at — a staging or rebuilt database that applied 0193
--   and resolved a real strand before this file landed.
create or replace function _scrub_ops_return_reasons() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int := 0;
begin
  update bookings b
     set return_force_reason = x.token
    from (
      select distinct on (r.booking_id)
             r.booking_id,
             case r.from_status
               when 'active'          then 'ops_resolved:strand'
               when 'incident_review' then 'ops_resolved:review'
               else                        'ops_resolved'
             end as token
        from return_resolutions r
       order by r.booking_id, r.created_at desc
    ) x
   where x.booking_id = b.id
     and b.return_forced_by = 'ops'
     and b.return_force_reason is distinct from x.token;
  get diagnostics v_n = row_count;
  raise notice '_scrub_ops_return_reasons: % booking(s) had a 0193-written ops memo in return_force_reason; replaced with the rescued-from token (the journal keeps the memo)', v_n;
  return v_n;
end $$;

revoke execute on function _scrub_ops_return_reasons() from public, anon, authenticated;
grant  execute on function _scrub_ops_return_reasons() to service_role;

comment on function _scrub_ops_return_reasons is
  '0201 §B (codex 2026-09-22 #1의 나머지 절반): 0193이 이미 bookings.return_force_reason에 복사해
둔 운영 메모를 §A의 고정 토큰으로 덮는다. 대상은 **저널 조인**으로 식별한다 — return_resolutions의
기록자는 ops_resolve_return_tx 하나뿐이므로 저널 행이 있는 예약이 곧 그 해결기가 판정한 예약이고,
free text로 「메모처럼 보이는지」를 재는 것은 애초에 검사 가능한 성질이 아니다. force_return_tx가 쓴
사유는 저널 행이 없으므로 **구조적으로** 이 집합 밖이다(잊으면 안 되는 필터가 아니라). 마지막 조건은
쓰려는 값 자체와 비교하므로 멱등이다(두 번째 호출은 0). 저널의 memo는 건드리지 않는다 — 운영자의
감사 기록은 그대로 남아야 한다. 이 배포에서는 공허하다(프로덕션 0156, 0193 미적용); 공허하지 않은
환경은 아무도 보고 있지 않은 환경이다. 232 0201-M2가 핀.';

-- the one-time call. The count is reported rather than swallowed.
do $$
declare v_n int;
begin
  select _scrub_ops_return_reasons() into v_n;
  raise notice '0201 §B: one-time ops-memo scrub of bookings.return_force_reason — % row(s)', v_n;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C ops_is_member — so the edge can refuse BEFORE it reads a booking (codex #5)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `transition-booking` names `resolve_return` in `index.ts`'s party-gate exception, because an
-- operator is by definition not a party. 0193 argued that trade was a NARROWING, and the SQL half
-- of the argument is true — `ops_resolve_return_tx` refuses a non-operator before it reads a field.
-- The EDGE half was not: `index.ts:54` reads the booking and `resolve_return.ts:83` prices it, both
-- ahead of the only membership check there was. Measured by the reviewer with a targeted probe:
-- one stranger identity got **503** for an unpriceable run and **403 not_ops** for a priceable one,
-- which is an oracle for any booking id, and got privileged pricing work done for free on the way.
--
-- This function is the read the service-role client needs. There was none: `ops_recipients_for`
-- (0084 §E) returns a ROSTER — handing it to the edge means the edge learns who the operators are
-- to answer a question about itself — and `ops_me()` (0198 §A) is `auth.uid()`-based and therefore
-- answers NULL through `admin()`, which is the client every edge function holds.
--
-- 🔴 **WHY IT TAKES `p_actor` RATHER THAN READING `auth.uid()`, and why that is not an oracle.**
-- It is 0193 §C-b's own shape, for 0193 §C-b's own reason: the edge talks to the database as
-- `service_role`, so `auth.uid()` inside any RPC it calls is NULL. The protections are the same two,
-- and they are independent: **(a)** the caller-class gate — `auth.uid()` must be NULL *and*
-- `current_user` must be `service_role`/`postgres`, so an `authenticated` role calling this refuses
-- with `not_party` even if a grant were added by accident; **(b)** the ACL — `execute` is revoked
-- from `public`, `anon` and `authenticated` and granted to `service_role` alone, which is what makes
-- it unreachable from a phone at all (0101 §A's protection, and its warning: a grant to
-- `authenticated` here would turn it into an arbitrary-pair membership oracle).
--
-- ⚠ It answers `true`/`false` and raises only about its ARGUMENTS. A roster miss is an ordinary
--   answer, not an exception: the edge maps it to the same 403 the SQL gate produces, and a
--   function that raised `not_ops` here would make the edge's happy path go through a catch.
-- ⚠ `p_kind` is a real argument, not decoration — 0084 §E's classes are separate rosters and
--   `payout_due` membership must not open `return_strand`'s door. 232 `0201-G1` pins both directions.
create or replace function ops_is_member(p_kind text, p_actor uuid)
returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  -- ① SERVER ONLY. 0089 §6 / 0193 §C-b ①'s line, verbatim in substance.
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;
  -- ② the arguments. `ops_actor_required` is the same word `ops_resolve_return_tx` uses, so the
  --    edge's error map needs no second vocabulary.
  if p_actor is null then raise exception 'ops_actor_required'; end if;
  if coalesce(btrim(p_kind), '') = '' then raise exception 'ops_kind_required'; end if;
  -- ③ the roster, through 0084 §E's own window. `is true`, so a NULL from any cause answers NO.
  return (select exists (select 1 from ops_recipients_for(p_kind) as rc(profile_id)
                          where rc.profile_id = p_actor)) is true;
end $$;

revoke execute on function ops_is_member(text, uuid) from public, anon, authenticated;
grant  execute on function ops_is_member(text, uuid) to service_role;

comment on function ops_is_member is
  '0201 §C (codex 2026-09-22 #5): 엣지가 **예약을 읽거나 값을 매기기 전에** 「이 검증된 호출자가 이
명부에 있나」를 물을 수 있는 유일한 읽기. 없던 이유는 둘이다 — ops_recipients_for(0084 §E)는 명부
자체를 돌려주므로 자기 자신에 대한 질문의 답으로 주기엔 과하고, ops_me(0198 §A)는 auth.uid() 기반이라
service_role 클라이언트(admin())에서는 항상 NULL을 본다. p_actor를 받는 것은 0193 §C-b와 같은 이유이고
(엣지는 service_role로 말한다), 임의 쌍 오라클이 되지 않는 보호는 **서로 독립인 둘**이다: 호출자 클래스
게이트(auth.uid()가 NULL이고 current_user가 service_role/postgres여야 한다 — authenticated가 부르면
not_party)와 ACL(public·anon·authenticated 회수, service_role만 부여). 명부에 없으면 false를 돌려줄
뿐 예외가 아니다 — 여기서 not_ops를 던지면 엣지의 정상 경로가 catch를 지나게 된다. p_kind는 장식이
아니다: 0084 §E의 클래스는 서로 다른 명부이고 payout_due 소속이 return_strand의 문을 열어서는 안 된다.
SQL 안의 진짜 게이트(ops_resolve_return_tx ②)는 그대로다 — 이건 더 이른 거절이지 대체가 아니다.
232 0201-G1·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D sweep_run_end_recovery — an UNSEALED `incident_review` return is a strand, full stop
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0193 §D's body, copied by script (§0c), with exactly TWO edits — the same predicate, in the
-- candidate query and in the locked-row recheck, because arm ⓑ's law is that every candidate
-- predicate is re-asserted on the locked row and a fix applied to only one of them is a fix that
-- works until two ticks overlap.
--
-- 🔴 **THE SHAPE CODEX FOUND.** `bookings.settlement_ready_at is null` and
-- `status in ('active','incident_review')` were already conjuncts; the third one —
-- 「not both stamps」 — was written for the `active` case, where two stamps mean
-- `confirm_return_tx` sealed the row and there is nothing to report. In `incident_review` it means
-- the opposite: 0096 lets both late stamps LAND and deliberately refuses to seal, so 「both stamps,
-- no seal」 is exactly the state that can never settle by itself. The conjunct was excluding the
-- one shape that most needs an operator.
--
-- The edit is a disjunct rather than a deletion, deliberately: for an `active` row the old rule is
-- still the right rule.
--
--     candidate:  and (b.status = 'incident_review'
--                      or not (runner stamp and owner stamp))
--     recheck:    if (v_b.status is distinct from 'incident_review')
--                    and <both stamps> then continue;
--
-- ⚠ `is distinct from` in the recheck, not `<>`: a bare `IF` over a NULL predicate is silent, and
--   a silent recheck here means the arm falls through and TELLS somebody — the safe direction, but
--   for the wrong reason, and the pins that exist to notice 「something is missing」 are exactly the
--   pins that collapse on NULL.
-- ⚠ NOTHING ELSE MOVES. The deadline, the roster class, the one-shot notification guard, the batch
--   bound, the NULL-flag off switch and every other arm are 0193's. In particular a SEALED row is
--   still excluded by `settlement_ready_at is null` — a sealed-but-unsettled row is arm ⓐ's subject
--   and needs a pricing re-drive (0083 §0f), not an ops bell. 232 `0201-L1` pins both directions.
-- ⚠ **NAMED GAP, measured rather than reasoned:** the `active` half of the disjunct is not
--   separately observable in this harness. To see it you need an `active` booking with BOTH return
--   stamps and no seal — and there is no path to that state, because a client-class second stamp
--   on an `active` row seals it (0096 §6) and a server-class one without a price is now refused
--   (0193 §B). So `0201-L1` proves the `incident_review` arm ADMITS and that a sealed row is still
--   excluded; it does not prove the `active` arm is load-bearing, and saying so is the difference
--   between a gap and a pass.
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0188] arm ⓑ-②'s one-shot alarm: a return ONE side has confirmed and the other has not.
  -- A DISTINCT title from the escalation's 「귀가 확인이 필요해요」 so neither dedupe key can
  -- silence the other, and so the client can route them apart. `notification-route.ts` routes it
  -- (runner → /runner/return-seal · owner → the bid-scoped report) and
  -- `app/test/notification-route.test.cjs` reads THIS constant out of THIS file, so the two
  -- spellings cannot drift (the c_esc_title idiom, 0182).
  c_ret_title     constant text := '반환 확인이 멈춰 있어요';
  -- to the side that has NOT stamped …
  c_ret_body_ask  constant text := '러닝이 끝났는데 반환 확인이 아직이에요 — 앱에서 인계를 확인해주세요';
  -- … and to the side that HAS. Never the first sentence: telling someone to confirm what they
  -- already confirmed is a lie about their own action (0092 §6).
  c_ret_body_wait constant text := '내 반환 확인은 끝났고 상대방 확인을 기다리고 있어요 — 확인되면 정산이 마무리돼요';
  -- [0181] arm ⓒ: how long a one-sided handoff may sit with no ask row before the sweep re-sends
  -- the ask, and how far an ask row may PRECEDE the stamp it answers (the edge stamps with its
  -- own clock, the row is stamped by the database's) and still count as that stamp's ask.
  ASK_AFTER constant interval := interval '5 minutes';
  -- the edge's exact strings (`transition-booking/index.ts`, case confirm_handoff): `push.ts`
  -- routes the runner by EXACT title, and the inbox must show one ask, not two spellings of it.
  c_ask_title constant text := '인계 확인 요청';
  c_ask_body  constant text := '상대방이 인계를 확인했어요 — 확인해주세요';
  -- [0182] arm ⓓ: how long a handoff may stay one-sided — ask delivered or not — before both
  -- parties and the ops roster are told ONCE for this cycle. 30 min: the re-send (arm ⓒ) lands
  -- 5–15 min after the stamp, so the re-sent ask has had at least 15 min to be answered.
  ESCALATE_AFTER constant interval := interval '30 minutes';
  c_esc_title constant text := '인계 확인이 멈춰 있어요';
  c_esc_body  constant text := '인계 확인이 한쪽만 된 채 30분이 지났어요 — 담당자가 확인하고 있어요';
  c_ops_class constant text := 'handoff_unanswered';
  -- [0182] the statuses in which a pickup handoff is NOT underway — the same fourteen arm ⓒ's
  -- candidate query names literally (212 C8 anchors on that literal); this constant is what the
  -- re-checks and arm ⓓ use, and VERIFY / 213 D7 assert the two spellings are identical.
  c_dead constant booking_status[] := array['draft','quoted','payment_hold','matching','runner_pending',
                                            'picked_up','active','completed',
                                            'cancelled_owner','cancelled_runner','expired','no_show',
                                            'incident_review','refund_pending']::booking_status[];
  -- [0182] rows served per tick per arm (ⓒ, ⓓ): every row lock these arms take is held to
  -- commit, and a counterparty's confirm (a plain UPDATE, no NOWAIT) waits behind it — so the
  -- number held is bounded, the arms are idempotent, and the rest wait for the next tick, ten
  -- minutes away (cold review 0182 #6; late_booking_sweep's `limit 5` is the precedent, 0126:61).
  c_batch constant int := 50;
  v_b record; v_cp uuid; v_st timestamptz; v_ops int;
  v_cid uuid;   -- [0183] the cycle the locked row is in, minted on the spot if it has none (legacy)
  -- [0193 §D] arm ⓕ. A DURATION read from `ops_flags` at the top of the arm, not a constant: the
  -- number is Sean's ruling (queue item 23) and NULL — the shipped value — means the arm does
  -- nothing at all. The ops class is its own, not `payout_due`'s: the people who can END a strand
  -- (`ops_resolve_return_tx` gates on exactly this roster) are the people who should be told.
  c_strand_ops_class constant text := 'return_strand';
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  -- NO id and NO amount in the body (0084 §E: a wrong recipient id pushes the body verbatim to a
  -- stranger's lock screen). The booking id rides in `ref_id`, as 0155/0166/0182 do.
  c_strand_body  constant text := '러닝이 끝났는데 반환 확인이 끝나지 않은 예약이 있어요. 예약을 확인해 주세요.';
  v_strand_min int;
begin
  -- [0181] ONE tick at a time (0117's job-lock idiom; 0177 gave owner-la the same): arm ⓐ's
  -- one-shot alarm and arm ⓒ's re-send are both read-then-write on `notifications`, and two
  -- overlapping ticks would each see no row and each insert (audit M10's class). A TRY-lock, so
  -- a slow predecessor is skipped and never queued; transaction-scoped, so any raise below
  -- releases it with no unlock to forget. `90_race_check.sh` RL measures the skip with two
  -- processes; 212 C8 sees the lock held after the call.
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice 'sweep_run_end_recovery: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- [0182] the bounded wait (0117 MINOR-14, 0180 §A's value): ⓒ/ⓓ never wait (skip locked), but
  -- arm ⓑ's UPDATE can, and a sweep stalled there holds every row lock ⓒ already took.
  perform set_config('lock_timeout', '2000', true);
  -- ⓐ report every sealed-but-unsettled row. The runner is owed money on a booking whose
  -- settlement died; SQL cannot price it (see the header), so the honest output is a visible
  -- notice per row and a count, not a silent zero.
  for r in
    select b.id, b.owner_id, b.runner_id, b.settlement_ready_at
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.settlement_ready_at is not null
  loop
    raise notice 'sweep_run_end_recovery: booking % is sealed but unsettled since % — settlement needs the pricing path (0083 §0f)',
      r.id, r.settlement_ready_at;
    n := n + 1;
    -- …and after SEAL_ALARM_AFTER, a notice in a cron log is not enough: tell both parties, once.
    -- This alarm deliberately does NOT move the status. The row stays `active`, which is the only
    -- state from which `_settle_sealed_run` can still pay the runner — escalating it to
    -- `incident_review` would trade a slow settlement for an impossible one (see the header).
    -- One-shot by construction: a title that exists for this booking is an alarm already raised.
    if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
       and not exists (select 1 from notifications nt
                       where nt.ref_id = r.id and nt.title = '정산을 확인하고 있어요') then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.owner_id, 'booking', '정산을 확인하고 있어요',
              '인계는 확인됐는데 정산이 마무리되지 않았어요 — 담당자가 확인하고 있어요', r.id);
      if r.runner_id is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.runner_id, 'booking', '정산을 확인하고 있어요',
                '인계는 확인됐는데 정산이 마무리되지 않았어요 — 지급은 취소되지 않아요, 담당자가 확인하고 있어요', r.id);
      end if;
    end if;
  end loop;

  -- ⓑ [0188] THE RUN-END STRAND — narrowed, because what this arm does to a row is a MONEY DEAD
  -- END and this slice is the first thing in the product that can put a row in front of it.
  --
  -- 0083 wrote this arm while `end_run_tx` had ZERO callers, so it has never escalated a real
  -- marketplace 귀가. The run-end ceremony (⑪/⑫) gives it rows for the first time, and the
  -- composition is a defect measured before it shipped:
  --   ① the runner stops (`end_run_tx`) and stamps their own return on R6a seconds later;
  --   ② the owner is slower than STRAND_AFTER — at work, phone silent; two hours is not long;
  --   ③ this arm moves the booking `active → incident_review`;
  --   ④ the owner stamps that evening. 0096 lets the stamp LAND and deliberately does not seal;
  --   ⑤ `_settle_sealed_run` requires `active` (0083 §6) and `enforce_booking_transition` gives
  --      `incident_review` exactly one edge — `refund_pending` (0066:56) — so the run can NEVER
  --      settle. The runner walked the dog, brought it home, BOTH parties said so, and the only
  --      state the money could have moved from is gone.
  -- 0083's own header already refused this shape for SEALED rows ("an owner who simply did not
  -- tap confirm within 2 hours able to render the runner permanently unpayable"). The UNSEALED
  -- row acquires the identical property the moment 0096 makes a late stamp possible — and 0096
  -- landed after 0083, so neither file could see it alone.
  --
  -- ⚠ AND THE ESCALATION BUYS NOTHING IT WAS BOUGHT FOR. Its stated purpose is that `active` is
  -- LIVE to the runner-accept conflict guard, "so the runner's future bookings are blocked by a
  -- dog they returned two days ago". Both halves are false today:
  --   · the block is ⑫'s WORK GATE (0092), which reads the two stamp columns and ALSO catches
  --     `incident_review` (`0092:112-117`) — escalating frees no runner. Pinned: 219 0188-B3.
  --   · the accept-time conflict guard (`transition-booking/index.ts`) compares SCHEDULED
  --     WINDOWS within ±6h, so a two-day-old booking overlaps nothing it could block. READ from
  --     that source, NOT pinned here — it is TypeScript and this is SQL, and per the house law
  --     neither is evidence for the other.
  --
  -- SO: this arm escalates only a return NOBODY has confirmed — zero stamps, which is the state
  -- `incident_review` actually names (the dog is unaccounted for). A row where at least one party
  -- has said the dog is home keeps `active`, and therefore keeps its money path, and is ALARMED
  -- instead: both parties told once, no status move. That is arm ⓓ's own principle, three arms
  -- down and written by a later author for the same class of stuck two-sided confirmation —
  -- "what a stuck pickup handoff should become is a product decision (Sean's), not a clock's".
  --
  -- ⚠ NAMED RESIDUE, deliberately NOT closed here, and stated in FULL because the first draft of
  -- this paragraph named only half of it (cold review #7):
  --   ① a return NOBODY confirms still escalates at STRAND_AFTER, and is still a dead end if both
  --      parties stamp afterwards;
  --   ② AND THE ONE-STAMP ROW THIS ARM NOW PRESERVES HAS ITS OWN NEW TERMINAL. Runner stamps,
  --      owner never does: one notification at 2h, then permanent silence, `active` forever, the
  --      runner work-gated (0092) and unpaid. That is strictly better than the escalation it
  --      replaces — the money path SURVIVES, so a stamp on any later day still settles — but it
  --      is not bounded, and the honest word for the detection is HALF: `ops_gated_runners()`
  --      (0096 §7) lists the row, and the remedy it names, `force_return_tx`, **HAS NO CALLER
  --      ANYWHERE** — measured: `grep -rn force_return_tx` over `supabase/functions/`, `app/` and
  --      `scripts/` returns only two comment mentions in a deno test. No edge action, no ops
  --      console, no client. The only exit is a human typing SQL.
  -- Both need the same decision, and it is Sean's rather than a clock's (awaiting-sean §4): what,
  -- if anything, may a timer do with money. What this arm guarantees is smaller and checkable:
  -- **a run where at least one party has said the dog is home is never made unpayable by a
  -- clock.** An escalating alarm (rather than the one-shot) and an ops door for
  -- `force_return_tx` are the two follow-ups this creates.
  --
  -- ⚠ LOCK, THEN LOOK AGAIN — arm ⓒ's idiom (codex 0181 #3), applied here because the branch is
  -- now destructive and the race lands exactly on the defect being closed: a stamp committing
  -- between the candidate read and the UPDATE would escalate a row that had just become
  -- settleable. `skip locked` leaves a row a writer holds for the next tick rather than stalling
  -- a sweep that holds every lock arm ⓒ took (0180's lesson).
  -- ⚠ [cold review #3] THE CANDIDATE SET MUST DRAIN, and this arm is the first in the function
  -- whose rows do NOT leave it. 0183's arm ⓑ had neither `order by` nor `limit`, and that was safe
  -- there because every candidate was escalated and left the set by changing status. A ⓑ-② row
  -- never leaves: status stays `active`, `run_ended_at` stays set, `settlement_ready_at` stays
  -- null, and the one-shot check makes it silent on every later tick. Adding `limit c_batch` to a
  -- non-draining set with `order by b.id` — a v4 uuid, so an ARBITRARY but STABLE order — would
  -- select the same fifty lowest-uuid corpses every tick forever, and a new zero-stamp row sorting
  -- above them would never be escalated at all. Two changes, and they are independent:
  --   · `order by b.run_ended_at` — OLDEST FIRST, a meaningful order, so nothing can be
  --     permanently shadowed by rows that merely have smaller ids;
  --   · the alarmed rows are excluded from the CANDIDATE, not just skipped in the loop, which
  --     restores the drain: a row that has had its one-shot alarm is done with this arm.
  -- The same `not exists` still guards the insert under the lock (a candidate read is a snapshot).
  for r in
    select b.id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
      and not exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_ret_title)
    order by b.run_ended_at
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
             b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: strand % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- Every predicate of the candidate query, re-asserted on the LOCKED row.
      -- ⚠ [cold review #8] `club_session_id` is in this list because the comment SAID "every"
      -- and the first version omitted it — and 219's `0188-B4` pins this re-check by matching
      -- this exact string, so the pin would have inherited the gap. No live path re-parents a
      -- booking into a club session, so this is a comment made true rather than a hole closed;
      -- that distinction is the finding, and it is worth the one conjunct.
      if v_b.status <> 'active' or v_b.run_ended_at is null or v_b.settlement_ready_at is not null
         or v_b.club_session_id is not null then continue; end if;
      if v_b.run_ended_at >= now() - STRAND_AFTER then continue; end if;

      if v_b.runner_confirmed_return_at is not null or v_b.owner_confirmed_return_at is not null then
        -- ⓑ-② ONE SIDE HAS SAID THE DOG IS HOME. No status move, ever. Both parties told ONCE —
        -- one-shot by construction (arm ⓐ's idiom): a row with this title for this booking is an
        -- alarm already raised. The two bodies are NOT interchangeable: telling a party who has
        -- already stamped to "확인해주세요" is a lie about their own action (0092 §6's rule for
        -- `waiting_on`, which exists for exactly this sentence).
        if not exists (select 1 from notifications nt
                       where nt.ref_id = v_b.id and nt.title = c_ret_title) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.owner_id, 'booking', c_ret_title,
                  case when v_b.owner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                  v_b.id);
          if v_b.runner_id is not null then
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_b.runner_id, 'booking', c_ret_title,
                    case when v_b.runner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                    v_b.id);
          end if;
          raise notice 'sweep_run_end_recovery: booking % — 반환 확인이 한쪽만 된 채 % 경과: 양측 1회 통지, 상태 무이동 (0188 ⓑ-②)',
            v_b.id, STRAND_AFTER;
          n := n + 1;
        end if;
      else
        -- ⓑ-① NOBODY has confirmed the return. This is the state `incident_review` names, and
        -- 0083's escalation is reproduced here verbatim — same UPDATE, same two titles, same
        -- two bodies. A human has to look, and `ops_gated_runners` (0096 §7) is where they look.
        update bookings set status = 'incident_review' where id = v_b.id and status = 'active';
        -- [0193 §D, codex B5] `safety`, NOT `booking`. 0187's classifier files a booking row as
        -- disableable, so with 예약 알림 off this push — 「the dog is unaccounted for」 — was
        -- silenced. Classified at the WRITER, which is what codex asked for; §E's title entry is
        -- the belt that covers rows a pre-0193 tick already wrote as `booking`.
        -- ⚠ 0114:273-281 admits only kind='booking' from a booking PARTY. This is a definer owned
        -- by postgres, so no policy applies and `safety` is writable here — which is exactly why
        -- the client writers (api.ts) were left alone in 0189 and are still left alone.
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                  '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', v_b.id);
        end if;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;
  -- ⓕ [0193] THE STRAND IS FINALLY TOLD TO SOMEBODY WHO CAN END IT (codex A1's detection half).
  --
  -- 0188 arm ⓑ-② is correct and it is not enough: it tells the two PARTIES once and then goes
  -- silent forever, and the parties are precisely the people who are already not acting. 0188's own
  -- header names the residue in full — 「one notification at 2h, then permanent silence, `active`
  -- forever, the runner work-gated (0092) and unpaid」 — and calls an ops door the follow-up it
  -- creates. This is that door's bell; `ops_resolve_return_tx` (§C-b) is the door.
  --
  -- 🔴 **NULL MEANS THE ARM DOES NOTHING, AND THAT IS THE SHIPPED STATE.** `return_strand_minutes`
  -- is Sean's ruling (queue item 23) and a deadline nobody chose is worse than no deadline: it
  -- would page an operator on a cadence invented by whoever typed the migration. Read fresh each
  -- tick so the flip needs no redeploy, and `is null` short-circuits before a single booking is
  -- read.
  --
  -- ⚠ TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
  -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and that row is the
  -- WORSE one (0096 lets late stamps land and refuses to seal, so it cannot settle at all until an
  -- operator acts). It is identified by the FACTS it carries — a run that ended, no seal — never by
  -- a free-text reason, because a reason string is prose and this is the input to a money door.
  --
  -- ⚠ ONCE PER BOOKING, by arm ⓐ/ⓑ's idiom: a row with this title for this booking is a bell
  -- already rung, and the candidate query excludes it so the set DRAINS (cold review 0188 #3's
  -- lesson: a `limit` over a non-draining set shadows new rows forever). An EMPTY ROSTER writes
  -- nothing, so the arm retries every tick until somebody is provisioned — the same durable-PENDING
  -- shape as ⓓ/ⓔ, and the honest one: an escalation recorded as delivered when nobody received it
  -- is worse than an unmonitored state (0096 §4).
  select f.return_strand_minutes into v_strand_min from ops_flags f where f.id;
  if v_strand_min is not null then
    for r in
      select b.id
      from bookings b
      where b.club_session_id is null
        and b.status in ('active', 'incident_review')
        and b.run_ended_at is not null
        and b.settlement_ready_at is null
        and (b.status = 'incident_review'
             or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
        and b.run_ended_at < now() - make_interval(mins => v_strand_min)
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.title = c_strand_title)
      order by b.run_ended_at
      limit c_batch
    loop
      begin
        select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
               b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
          into v_b from bookings b where b.id = r.id for update skip locked;
        if not found then
          raise notice 'sweep_run_end_recovery: strand-ops % — row locked by a writer, left for the next tick', r.id;
          continue;
        end if;
        -- every predicate of the candidate query, re-asserted on the LOCKED row (arm ⓑ's law)
        if v_b.club_session_id is not null or v_b.run_ended_at is null
           or v_b.settlement_ready_at is not null then continue; end if;
        if v_b.status not in ('active', 'incident_review') then continue; end if;
        if (v_b.status is distinct from 'incident_review')
           and v_b.runner_confirmed_return_at is not null
           and v_b.owner_confirmed_return_at is not null then continue; end if;
        if v_b.run_ended_at >= now() - make_interval(mins => v_strand_min) then continue; end if;
        -- the candidate read was a snapshot; the one-shot guard is re-taken under the lock
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_strand_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_strand_title, c_strand_body, v_b.id
          from ops_recipients_for(c_strand_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — 반환이 %분 넘게 끝나지 않았다 (status=%, stamps=%/%): ops 수신자 %명 (%)',
          v_b.id, v_strand_min, v_b.status,
          (v_b.runner_confirmed_return_at is not null), (v_b.owner_confirmed_return_at is not null),
          v_ops,
          c_strand_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (다음 틱에 다시 시도)' else '' end;
        if v_ops > 0 then n := n + 1; end if;
      exception when others then
        raise notice 'sweep_run_end_recovery: strand-ops % — %', r.id, sqlerrm;
      end;
    end loop;
  end if;

  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED — backend audit M2's second half (the attack-INACTION one).
  -- `transition-booking`'s confirm_handoff stamps one side and then asks the OTHER side with a
  -- 「인계 확인 요청」 notification — the only thing in the product that asks. Since M2 a lost
  -- insert is a log line; nothing retried it, and no sweep looked for a handoff that was asked
  -- for and never answered because the ask never existed. This arm does: exactly one stamp set,
  -- the booking still able to reach `picked_up`, a runner to hand to, older than ASK_AFTER, and
  -- NO ask row for the counterparty created at or after that stamp (an earlier cycle's ask —
  -- stamps are reset on re-match, 0047:112 / index.ts:163 — does not count) ⇒ the ask is written
  -- ONCE, counted in the return, and named in a notice. The counterparty is the side that has
  -- NOT stamped: the party who stamped is never asked to confirm their own handoff.
  -- ⚠ STATUS IS A DENY-LIST, NOT AN ALLOW-LIST (the attack-INACTION law). A handoff is underway
  --   in exactly two statuses of 0066's map — `confirmed` and `runner_enroute`, the two from
  --   which `picked_up` is one edge away — and this arm names the OTHER fourteen rather than
  --   those two: before assignment there is no agreed handoff to confirm (a stamp there is a
  --   leftover; re-match resets it), after the pickup or in any end state there is nothing left
  --   to ask. So a status added to the enum lands in the sweep by default — re-sent, the failure
  --   this arm exists to close, and one spurious ask if it was in fact an end state (a wrong
  --   line in an inbox, visible) — and 212 C6 walks the enum so that new status reddens a pin
  --   until someone places it, instead of being decided by omission.
  -- ⚠ NO `club_session_id is null` here, unlike arms ⓐ/ⓑ. 0144:94 scoped THOSE for run-END
  --   reasons (a club run ends by the host's stop, not by `end_run_tx`). The PICKUP ask is the
  --   same edge action for both worlds — `club/session/[sid].tsx:665,708` call confirm_handoff
  --   exactly as `owner/meetup.tsx:252` does — so a club booking's lost ask is the same defect
  --   and is swept here; `runner_id is not null` already excludes an owner-handled club dog,
  --   which has no handoff to confirm.
  for r in
    select b.id, x.counterparty, x.stamped_at
    from bookings b
    -- the counterparty and the stamp are computed ONCE (lateral) and used by both the insert and
    -- the not-exists below — two copies of that `case` would be two places to drift (cold review)
    cross join lateral (
      select case when b.owner_confirmed_handoff_at is not null then b.runner_id else b.owner_id end as counterparty,
             coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) as stamped_at
    ) x
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and b.status not in ('draft', 'quoted', 'payment_hold', 'matching', 'runner_pending',        -- before assignment: no agreed handoff to confirm
                           'picked_up', 'active', 'completed',                                    -- past the pickup: nothing left to ask
                           'cancelled_owner', 'cancelled_runner', 'expired', 'no_show',          -- ended
                           'incident_review', 'refund_pending')
      and x.stamped_at < now() - ASK_AFTER
      -- ⚠ `nt.profile_id = x.counterparty` is load-bearing and easy to read as redundant: an ask
      --   row addressed to the OTHER party (the previous cycle's, inside the skew — re-match
      --   resets the stamps and leaves the row) must not silence this party's re-send. Measured
      --   by the cold review: without it the owner is NEVER asked in that shape. 212 C9 pins it.
      and not exists (
        select 1 from notifications nt
        where nt.ref_id = b.id
          and nt.title = c_ask_title
          and nt.profile_id = x.counterparty
          -- [0183] …and CARRYING THIS CYCLE'S IDENTITY. `handoff_cycle_id` is minted by the
          -- database (trigger _handoff_cycle) when a cycle starts — a first stamp, a runner change,
          -- a stamp reset — the edge writes it onto the ask it inserts, and `_notification_cycle_guard`
          -- refuses an ask whose id is not the booking's current one. A timestamp could not tell
          -- cycles apart (codex 0182 #1: a delayed old-cycle ask lands inside the new window); an
          -- id can. A row with no id (legacy) matches nothing here and is given one in the loop.
          and nt.handoff_cycle_id = b.handoff_cycle_id)
    order by b.id
    limit c_batch
  loop
    -- arm ⓑ's shape, for arm ⓑ's reason (0117:1222): one surprising row must not stop the sweep
    -- for every other. Measured — without this sub-block a single failing insert here rolled
    -- arm ⓑ's escalations back with it. Latent today (the runner conjunct and owner_id NOT NULL
    -- make the insert unable to fail), and that is one conjunct away from not latent.
    begin
      -- [0182] LOCK, THEN LOOK AGAIN (codex 0181 #3). The candidate query read a snapshot; a
      -- transition-booking write (the counterparty's confirm, a cancel, a re-match) can commit
      -- between that read and this insert, and the ask would then be obsolete — or addressed to
      -- the former runner. `for update skip locked`: a row a writer holds right now is left for
      -- the next tick (its outcome decides), never waited on (a sweep holding every dog lock it
      -- took must not stall — 0180's lesson). The row we DO get is re-evaluated on its locked,
      -- current version, and the insert happens while the lock is held, so no write can slip in.
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_cycle_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: ask % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      v_cp := case when v_b.owner_confirmed_handoff_at is not null then v_b.runner_id else v_b.owner_id end;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ASK_AFTER then continue; end if;
      -- [0183] THE LEGACY RULE, stated: a one-sided row with no cycle identity (it predates 0183 and
      -- the apply-time backfill somehow missed it, or a fixture) is given one by this touch — the
      -- trigger mints on any update of a stamped, id-less row — and every ask it already has
      -- (NULL id) cannot prove it belongs to this cycle, so the row is asked ONCE MORE: a
      -- duplicate push over a silent stall. The ask written below carries the id, so the next
      -- tick matches it.
      v_cid := v_b.handoff_cycle_id;
      if v_cid is null then
        update bookings set handoff_cycle_at = handoff_cycle_at where id = v_b.id returning handoff_cycle_id into v_cid;
        raise notice 'sweep_run_end_recovery: booking % had no handoff cycle identity — minted % (legacy row)', v_b.id, v_cid;
      end if;
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_ask_title and nt.profile_id = v_cp
                   and nt.handoff_cycle_id = v_cid) then
        continue;
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
      values (v_cp, 'booking', c_ask_title, c_ask_body, v_b.id, v_cid);
      raise notice 'sweep_run_end_recovery: booking % — 인계 확인 요청 re-sent to % (one-sided since %, no ask row this cycle)',
        v_b.id, v_cp, v_st;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: ask % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓓ [0182] THE DEADLINE (codex 0181 #2 — the attack-INACTION shape, again). After arm ⓒ's one
  -- re-send an unanswered handoff was excluded forever: arms ⓐ/ⓑ need run-end states, and
  -- `late_booking_sweep` is gated on `ops_flags.late_protocol_live_since` AND marketplace-only
  -- (0126:43,78-80). This arm is a bounded ONE-SHOT per cycle, for club and marketplace alike,
  -- reading no flag: ESCALATE_AFTER after the stamp, still one-sided, the parties are told (a
  -- `booking` row each — no '요청' in the title, so it routes to the report / calendar, never to
  -- a CTA that was already declined twice) and the ops roster is told (a redacted `system` row,
  -- 0155's shape; zero subscribers is the honest answer and is in the notice). NO status move —
  -- what a stuck pickup handoff should become is a product decision (Sean's), not a clock's.
  -- ONCE by a column, not by prose: `handoff_escalated_at` is the record and the dedupe key,
  -- reset by the cycle trigger so a NEW pairing can escalate again.
  for r in
    select b.id
    from bookings b
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
      and coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) < now() - ESCALATE_AFTER
      and b.handoff_escalated_at is null
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) or v_b.handoff_escalated_at is not null then continue; end if;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ESCALATE_AFTER then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_b.owner_id,  'booking', c_esc_title, c_esc_body, v_b.id),
             (v_b.runner_id, 'booking', c_esc_title, c_esc_body, v_b.id);
      -- the ops row carries NO identifier in its body (0084 §E: a wrong recipient id pushes a body
      -- verbatim to a stranger's lock screen); the booking id rides in ref_id, as 0155/0166 do.
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      -- [0183] TWO RECORDS, not one (codex 0182 #2): the parties' delivery is done here and once;
      -- the OPS delivery is recorded ONLY when a recipient actually got a row. An empty roster
      -- leaves `handoff_ops_alerted_at` NULL — a durable PENDING ops escalation that arm ⓔ retries
      -- every tick until somebody is provisioned, without telling the parties twice (0166's
      -- 「the stamp is conditioned on a delivery」 rule, applied to the half it fits).
      update bookings
         set handoff_escalated_at = now(),
             handoff_ops_alerted_at = case when v_ops > 0 then now() end
       where id = v_b.id;
      raise notice 'sweep_run_end_recovery: booking % — handoff one-sided since %, past %: both parties told, % ops recipient(s) for %',
        v_b.id, v_st, ESCALATE_AFTER, v_ops,
        c_ops_class || case when v_ops = 0 then ' — ops escalation PENDING until the roster is provisioned' else '' end;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: escalate % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓔ [0183] THE PENDING OPS ESCALATION (codex 0182 #2). Rows whose parties were told (ⓓ) while
  -- the ops roster was empty keep `handoff_ops_alerted_at` NULL; every tick tries the roster again
  -- for rows still one-sided and live, records the delivery only when a row was written, and never
  -- touches the parties. Locked and re-checked like ⓒ/ⓓ (cold review 0183 #6, measured: without
  -- the lock a confirm committing inside the loop still got ops paged about a handoff that had
  -- just finished — the row WAS escalated, but the page's whole content is 「still stuck」). The job
  -- lock serializes ticks. Bounded by `c_batch`; resets with the cycle (the trigger).
  for r in
    select b.id
    from bookings b
    where b.handoff_escalated_at is not null
      and b.handoff_ops_alerted_at is null
      and (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at, b.handoff_ops_alerted_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      if v_b.handoff_escalated_at is null or v_b.handoff_ops_alerted_at is not null then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then
        update bookings set handoff_ops_alerted_at = now() where id = v_b.id and handoff_ops_alerted_at is null;
        raise notice 'sweep_run_end_recovery: booking % — pending ops escalation delivered to % recipient(s)', v_b.id, v_ops;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: pending ops % — %', r.id, sqlerrm;
    end;
  end loop;

  return n;
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited — 0193 §D's own line, for the same reason.
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant  execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9 · 0181 ⓒ · 0182 ⓓ · 0183 ⓔ · 0188 ⓑ · 0193 ⓕ, 그리고 **0201 §D가 ⓕ의 자격만 넓혔다**
(codex 2026-09-22 #2): 봉인되지 않은 incident_review 반환은 스탬프가 몇 개든 좌초다. 0188 ⓑ-①이
0스탬프 반환을 incident_review로 올린 뒤 양측이 **늦게** 확인하면 0096은 스탬프는 받고 봉인은 하지
않는데, ⓕ의 예전 술어는 「스탬프 2개」라는 이유로 바로 그 행을 후보에서 빼고 있었다 — 즉 혼자서는
절대 정산될 수 없는 상태만 골라서 아무에게도 알리지 않았다. 후보 쿼리와 잠긴 행 재확인 **양쪽**을
고쳤고(한쪽만 고치면 두 틱이 겹칠 때까지만 맞다), active 행에 대해서는 예전 규칙이 그대로 옳으므로
삭제가 아니라 분기다. 마감(return_strand_minutes·NULL이면 무동작)·명부 클래스·1회 통지 가드·배치
상한·나머지 모든 팔은 0193 그대로이고, 봉인된 행은 여전히 settlement_ready_at is null이 제외한다
(그건 0083 §0f의 가격 재구동 몫). 232 0201-L1·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 232
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Apply-time source checks are protected exactly until somebody recreates the function (0131-G4's
-- lesson), so 232 owns the standing pins and this block owns 「the file that just ran did what it
-- says」. Comments are STRIPPED before every match: `prosrc` is source plus our own prose, and this
-- file explains every predicate it checks for — un-stripped, each arm would be satisfied by the
-- paragraph explaining it, and the better the explanation the more surely.
do $$
declare v_src text; v_bad text := '';
begin
  -- ── §A the resolver ────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx';
  if v_src is null then raise exception '0201 VERIFY: NO-SOURCE(ops_resolve_return_tx)'; end if;
  -- the ASSIGNMENT, not the word: a check for `v_reason` alone would be satisfied by a declaration
  -- that nothing uses, and a check for `return_force_reason` alone is satisfied by both worlds.
  if (v_src ~ 'return_force_reason\s*=\s*v_reason') is not true
    then v_bad := v_bad || ' 해결 RPC: 판정 사유 칸에 고정 토큰을 쓰지 않는다;'; end if;
  if (v_src ~ 'return_force_reason\s*=\s*(v_memo|p_memo)') is not false
    then v_bad := v_bad || ' 🔴 해결 RPC: 운영 메모가 당사자가 읽는 칸에 다시 실린다;'; end if;
  -- …and the memo must STILL reach the journal. A fix that simply deleted the memo everywhere
  -- would pass the two arms above and destroy the operator's audit trail.
  if (v_src ~ 'insert into return_resolutions') is not true
    then v_bad := v_bad || ' 해결 RPC: 저널을 쓰지 않는다;'; end if;
  if (v_src ~ '\mv_memo\M') is not true
    then v_bad := v_bad || ' 해결 RPC: 메모가 본문에서 사라졌다 (저널의 감사 기록이 빈다);'; end if;
  if (v_src ~ 'raise exception ''memo_required''') is not true
    then v_bad := v_bad || ' 해결 RPC: memo_required 거절이 없다;'; end if;
  -- 0193's own invariants, re-asserted because this file re-declared the function
  if not (position('ops_recipients_for(c_ops_class)' in v_src) > 0
          and position('ops_recipients_for(c_ops_class)' in v_src) < position('for update' in v_src))
    then v_bad := v_bad || ' 해결 RPC: ops 게이트가 잠금보다 뒤에 있다;'; end if;
  if (v_src ~ 'runner_confirmed_return_at = ') is true
    then v_bad := v_bad || ' 해결 RPC: 러너 스탬프를 위조한다;'; end if;
  if (v_src ~ 'owner_confirmed_return_at = ') is true
    then v_bad := v_bad || ' 해결 RPC: 보호자 스탬프를 위조한다;'; end if;
  if (v_src ~ '_settle_sealed_run') is not true
    then v_bad := v_bad || ' 해결 RPC: 정산 프리미티브를 쓰지 않는다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 해결 RPC: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute')
    then v_bad := v_bad || ' 해결 RPC가 authenticated에 열려 있다;'; end if;
  if not has_function_privilege('service_role', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute')
    then v_bad := v_bad || ' 해결 RPC를 service_role이 실행할 수 없다;'; end if;

  -- ── §B the scrub ───────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_scrub_ops_return_reasons';
  if v_src is null then raise exception '0201 VERIFY: NO-SOURCE(_scrub_ops_return_reasons)'; end if;
  if (v_src ~ 'from return_resolutions') is not true
    then v_bad := v_bad || ' 스크럽: 저널 조인이 없다 (텍스트로 고르고 있다);'; end if;
  if (v_src ~ 'return_forced_by = ''ops''') is not true
    then v_bad := v_bad || ' 스크럽: ops 마커 조건이 없다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = '_scrub_ops_return_reasons'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 스크럽: definer/search_path 형상 없음;'; end if;

  -- ── §C the membership read ─────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ops_is_member';
  if v_src is null then raise exception '0201 VERIFY: NO-SOURCE(ops_is_member)'; end if;
  -- the caller-class gate must be the FIRST thing, and it must be the conjunction: either half
  -- alone lets an authenticated caller through (v_uid null in a definer called by postgres) or
  -- refuses the edge (current_user service_role with a uid).
  if (v_src ~ 'v_uid is not null or current_user not in \(''service_role'', ''postgres''\)') is not true
    then v_bad := v_bad || ' 명부 조회: 서버 전용 호출자 게이트가 없다;'; end if;
  if (v_src ~ 'ops_recipients_for\(p_kind\)') is not true
    then v_bad := v_bad || ' 명부 조회: 0084의 창구를 쓰지 않는다 (두 번째 소속 구현);'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'ops_is_member'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 명부 조회: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.ops_is_member(text,uuid)', 'execute')
    then v_bad := v_bad || ' 🔴 명부 조회가 authenticated에 열려 있다 (임의 쌍 오라클);'; end if;
  if has_function_privilege('anon', 'public.ops_is_member(text,uuid)', 'execute')
    then v_bad := v_bad || ' 🔴 명부 조회가 anon에 열려 있다;'; end if;
  if not has_function_privilege('service_role', 'public.ops_is_member(text,uuid)', 'execute')
    then v_bad := v_bad || ' 명부 조회를 service_role이 실행할 수 없다 (엣지의 사전 거절이 죽는다);'; end if;

  -- ── §D the sweep ───────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_src is null then raise exception '0201 VERIFY: NO-SOURCE(sweep_run_end_recovery)'; end if;
  -- BOTH halves of the edit, each matched in a form the OTHER world cannot satisfy: the old
  -- candidate conjunct began `and not (`, the new disjunct begins `or not (` — so the two states
  -- are distinguishable, which a match on `not (b.runner_confirmed_return_at` alone would not be.
  if (v_src ~ 'and \(b\.status = ''incident_review''') is not true
    then v_bad := v_bad || ' 스윕 ⓕ: 후보 쿼리에 incident_review 분기가 없다;'; end if;
  if (v_src ~ 'or not \(b\.runner_confirmed_return_at is not null and b\.owner_confirmed_return_at is not null\)') is not true
    then v_bad := v_bad || ' 스윕 ⓕ: 후보 쿼리의 스탬프 조건이 분기가 아니다;'; end if;
  if (v_src ~ 'and not \(b\.runner_confirmed_return_at is not null and b\.owner_confirmed_return_at is not null\)') is not false
    then v_bad := v_bad || ' 🔴 스윕 ⓕ: 후보 쿼리에 옛 「스탬프 2개면 제외」 조건이 남아 있다;'; end if;
  if (v_src ~ 'if \(v_b\.status is distinct from ''incident_review''\)') is not true
    then v_bad := v_bad || ' 스윕 ⓕ: 잠긴 행 재확인이 후보 쿼리와 다르다;'; end if;
  if (v_src ~ 'if v_b\.runner_confirmed_return_at is not null\s+and v_b\.owner_confirmed_return_at is not null then continue') is not false
    then v_bad := v_bad || ' 🔴 스윕 ⓕ: 잠긴 행 재확인에 옛 조건이 남아 있다;'; end if;
  -- the seal is still what excludes arm ⓐ's subject — widening must not have eaten it
  if (v_src ~ 'and b\.settlement_ready_at is null') is not true
    then v_bad := v_bad || ' 스윕 ⓕ: 봉인 제외 조건이 사라졌다;'; end if;
  -- 0193/0188/0183/0181's arms must have survived the copy
  if (select count(*) from regexp_matches(v_src, '''safety''::noti_kind, ''귀가 확인이 필요해요''', 'g')) <> 2
    then v_bad := v_bad || ' 스윕: 귀가 승격이 safety로 쓰이지 않는다(2건이 아님);'; end if;
  if (select count(*) from regexp_matches(v_src, 'set status = ''incident_review''', 'g')) <> 1
    then v_bad := v_bad || ' 스윕: 0188의 승격 구문이 1개가 아니다;'; end if;
  if (v_src ~ 'return_strand_minutes') is not true then v_bad := v_bad || ' 스윕: 좌초 팔 없음;'; end if;
  if (v_src ~ 'c_strand_ops_class') is not true then v_bad := v_bad || ' 스윕: 좌초 ops 클래스 없음;'; end if;
  if (v_src ~ 'handoff_ops_alerted_at') is not true then v_bad := v_bad || ' 스윕: ⓔ 팔 유실;'; end if;
  if (v_src ~ 'pg_try_advisory_xact_lock') is not true then v_bad := v_bad || ' 스윕: 잡 락 유실;'; end if;
  if (select count(*) from regexp_matches(v_src, 'for update skip locked', 'g')) <> 5
    then v_bad := v_bad || ' 스윕: 행 락 수가 5가 아니다(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ);'; end if;
  if (v_src ~ '반환 확인이 멈춰 있어요') is not true then v_bad := v_bad || ' 스윕: ⓑ-② 알림 제목 유실;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 스윕: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.sweep_run_end_recovery()', 'execute')
    then v_bad := v_bad || ' 스윕이 authenticated에 열려 있다;'; end if;

  -- ── the journal is still SEALED (this file must not have unsealed what 0193 sealed) ────
  if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
    then v_bad := v_bad || ' return_resolutions에 RLS가 없다;'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
    then v_bad := v_bad || ' return_resolutions에 정책이 있다 (클라이언트 표면);'; end if;
  if has_table_privilege('authenticated', 'public.return_resolutions', 'select')
    then v_bad := v_bad || ' return_resolutions를 authenticated가 읽을 수 있다;'; end if;

  if v_bad <> '' then raise exception '0201 VERIFY failed:%', v_bad; end if;
  raise notice '0201 VERIFY ok — the memo stays in the journal, the strand arm sees late-stamped incident_review rows, and the edge has a membership read it can call first';
end $$;
