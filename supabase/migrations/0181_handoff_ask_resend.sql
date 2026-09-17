-- ═══ 0181: the lost 「인계 확인 요청」 is re-sent by the sweep — backend audit M2, second half ═══
--
-- M2 (docs/reviews/2026-09-17-backend-honesty-audit.md:74) had two halves. The first landed on
-- the edge: `transition-booking`'s `notify()` binds and logs its insert error instead of
-- discarding it (index.ts:61-88, deno `[M2]` pins). The second half is this file: a lost
-- 「인계 확인 요청」 — the ONLY thing that asks the second party to confirm the handoff — was a
-- log line and nothing more. Nothing retried it, and no sweep looked for a handoff that one side
-- confirmed and the other was never asked about. The booking sits in a state no transition list
-- can reach (the attack-INACTION shape), and BOTH live screens stay pointed at it — `api.ts`'s
-- IN_FLIGHT treats `confirmed`/`runner_enroute` as the current booking, so the owner and the
-- runner each sit on a meetup screen waiting for a tap the other was never asked for. ⚠ NOT
-- through 「⑫'s work gate」 as `index.ts:68` said: `_runner_work_gate_blocking` (0092:100-118)
-- reads the RETURN stamps and `run_ended_at`, never a pickup stamp (cold review 0181 #8; the
-- edge's comment is corrected in this slice). The recovery belongs to the sweep that already
-- owns 「a handoff nobody finished」: `sweep_run_end_recovery` (0083 §9), which gains arm ⓒ.
--
-- ═══ WHAT CHANGES ═══
-- `sweep_run_end_recovery()` is 0083's body VERBATIM (arms ⓐ and ⓑ untouched, byte-for-byte —
-- 0144 scoped both to marketplace rows and that stays) plus three marked additions:
--   · a TRY job lock at the top (`pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0))`)
--     — arm ⓐ's one-shot and arm ⓒ's re-send are read-then-write on `notifications`, and two
--     overlapping ticks would each see no row and each insert (audit M10's class; 0177 closed it
--     for owner-la with this idiom). A held lock means SKIP THIS TICK and return 0, never queue —
--     0117:1202-1206's rule. Transaction-scoped: any raise below releases it.
--   · arm ⓒ: for every booking with EXACTLY ONE handoff stamp, a runner, a status in which a
--     handoff is underway (0066's map: `confirmed` · `runner_enroute` — written as a DENY-list of
--     the other fourteen, per the attack-INACTION law), the stamp older than 5 minutes, and NO
--     「인계 확인 요청」 row for
--     the counterparty created at or after that stamp: insert the ask — same title, body and
--     `kind` as the edge's, so `push.ts` routes it to /runner/meetup by exact title and the inbox
--     shows one ask — count it, and say so in a notice. Once by construction: the row it writes
--     is the row the predicate looks for.
--   · the ask's strings as constants, so 212 and the deno drift pin can name the one place the
--     sweep spells them.
-- ⚠ TWO TIMES, both chosen here and both stated: ASK_AFTER = 5 minutes (a pickup happens in
--   person; a counterparty who has not tapped five minutes after the first stamp and has no ask
--   row was never asked — with the cron at 8-58/10 the re-send lands 5–15 minutes after the
--   stamp) and ASK_SKEW = 10 minutes (the stamp is the edge's clock, the ask row's `created_at`
--   is the database's; an ask row up to ten minutes OLDER than the stamp still counts as that
--   stamp's ask, so clock drift produces at worst a duplicate ask, never a missing one).
-- ⚠ CLUB ROWS ARE SWEPT BY ⓒ, unlike ⓐ/ⓑ: the pickup ask is the same edge action for both
--   worlds (`club/session/[sid].tsx:665,708`), and 0144's exclusion was about how a club RUN
--   ends, not how a handoff is asked for. `runner_id is not null` excludes an owner-handled dog.
--   ⚠ For a club row the PUSH ROUTE is the edge's existing imperfection, not a new one: `push.ts`
--   sends the runner to /runner/meetup and the owner to /owner/meetup, whose confirm CTAs are
--   gated on `stage === 'arrived'` (runner/meetup.tsx:646 · owner/meetup.tsx:560), a stage the
--   club screen never sets (it does not call runnerArrived), while the club confirm buttons live
--   at club/session/[sid].tsx:659/708. The inbox row is real and the title is the one the edge
--   already writes for a club handoff; the club-aware route is a client slice's, named here
--   rather than found in an incident (cold review 0181 #4).
-- ⚠ A solo-test booking (owner_id = runner_id) is asked to confirm its own handoff — exactly
--   what index.ts:363 does today; kept identical on purpose so the drift pin means one thing.
-- ⚠ NAMED GAP: after ⓒ's one ask, a pickup handoff nobody answers has NO escalation —
--   `late_booking_sweep` ⓑ (0117:1234) is flag-gated and marketplace-only, and arm ⓑ of this file
--   escalates the RETURN side only. Not a regression (0181 makes the world strictly better);
--   recorded so it is not read as closed.
-- ⚠ Cost: a merge anti-join over two seq scans, 0.39 ms at 668 bookings / 1448 notifications
--   (cold review); the one-stamp predicate is not sargable — a partial index on it is the lever
--   if `bookings` grows, and `notifications.ref_id` has no index at all.
-- ⚠ NO EDGE CHANGE. The sweep matches on the title the edge already writes; the deno pin in
--   `_test/transition_booking_actions_test.ts` (`[0181]`) reads both files and reddens if the two
--   spellings ever part. The cron registration (0177 §B, `8-58/10 * * * *`) is untouched — a
--   `create or replace` keeps the command; 208 pins the row.
-- ⚠ `create or replace` of a definer FIRST DEFINED IN 0083, so the ACL is restated below
--   (check-definer-acl law). Suites 119 · 132 · 133 · 163 · 208 pin the sweep's other arms and
--   the cron row and are unmoved (measured); 212 owns arm ⓒ and the job lock, `90_race_check.sh`
--   RL owns the two-tick skip.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 212's header and the REGISTRY row.

create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0181] arm ⓒ: how long a one-sided handoff may sit with no ask row before the sweep re-sends
  -- the ask, and how far an ask row may PRECEDE the stamp it answers (the edge stamps with its
  -- own clock, the row is stamped by the database's) and still count as that stamp's ask.
  ASK_AFTER constant interval := interval '5 minutes';
  ASK_SKEW  constant interval := interval '10 minutes';
  -- the edge's exact strings (`transition-booking/index.ts`, case confirm_handoff): `push.ts`
  -- routes the runner by EXACT title, and the inbox must show one ask, not two spellings of it.
  c_ask_title constant text := '인계 확인 요청';
  c_ask_body  constant text := '상대방이 인계를 확인했어요 — 확인해주세요';
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

  -- ⓑ escalate a stranded 귀가 — the booking must never be able to stay active forever. NOTE the
  -- `settlement_ready_at is null` predicate: this arm is for the return NOBODY CONFIRMED, and
  -- only for it. A sealed row is money that can still move and is handled by ⓐ (see the header).
  for r in
    select b.id, b.owner_id, b.runner_id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
  loop
    begin
      update bookings set status = 'incident_review' where id = r.id and status = 'active';
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.owner_id, 'booking', '귀가 확인이 필요해요',
              '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', r.id);
      if r.runner_id is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.runner_id, 'booking', '귀가 확인이 필요해요',
                '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', r.id);
      end if;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;

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
          and nt.created_at >= x.stamped_at - ASK_SKEW)
    order by b.id
  loop
    -- arm ⓑ's shape, for arm ⓑ's reason (0117:1222): one surprising row must not stop the sweep
    -- for every other. Measured — without this sub-block a single failing insert here rolled
    -- arm ⓑ's escalations back with it. Latent today (the runner conjunct and owner_id NOT NULL
    -- make the insert unable to fail), and that is one conjunct away from not latent.
    begin
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.counterparty, 'booking', c_ask_title, c_ask_body, r.id);
      raise notice 'sweep_run_end_recovery: booking % — 인계 확인 요청 re-sent to % (one-sided since %, no ask row)',
        r.id, r.counterparty, r.stamped_at;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: ask % — %', r.id, sqlerrm;
    end;
  end loop;

  return n;
end $$;
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9: 귀가 청소부 두 팔 — ⓐ settlement_ready_at은 찍혔는데 정산이 안 된 행을 NOTICE로
드러내고, 6시간이 지나면 양측에 1회 알린다(상태는 절대 옮기지 않는다: active여야 아직 지급할 수
있다. 러너 지급 기준이 end_reason에 따라 달라져 가격 계산이 TS에 있으므로 크론이 정산할 수는 없다
— 재구동은 0080 §K의 pg_net 디스패처 형태로 후속, §0f). ⓑ 아무도 인계를 확인하지 않은
채(settlement_ready_at is null) 종료 2시간이 지난 예약만 incident_review로 승격(0047:40의 합법
간선) — 부킹이 영원히 active면 러너의 다음 예약이 막힌다. 씰이 찍힌 행은 절대 승격하지 않는다:
incident_review는 돈의 막다른 길(→refund_pending만 허용, 상업적 출구인 club_incident_settle은
클럽 전용)이라 승격하면 러너가 영구 미지급이 된다 — §0h. 승격은 정산이 아니다. 양측에 통지
+ [0181] ⓒ 한쪽만 인계 확인을 찍었고 5분이 지나도록 상대에게 「인계 확인 요청」 알림 행이 없으면(엣지의 insert가 유실된 경우) 스윕이 같은 제목·본문으로 1회 다시 보낸다 — 아직 picked_up에 닿을 수 있는 상태만, 클럽 포함, 찍은 쪽이 아니라 상대에게. 틱은 한 번에 하나(try 잡 락, 겹치면 건너뜀)';

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 212 ═══
do $$
declare
  v_oid oid; v_src text; v_bad text := ''; v_n int; v_lock int; v_arm int;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then raise exception '0181 VERIFY FAILED: NO-FUNCTION(sweep_run_end_recovery)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-is-default)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE';
  else
    v_lock := position('pg_try_advisory_xact_lock(hashtextextended(''sweep_run_end_recovery'', 0))' in v_src);
    v_arm  := position('for r in' in v_src);
    if (v_lock > 0) is distinct from true then v_bad := v_bad || ' JOB-LOCK-MISSING'; end if;
    if (v_lock > 0 and v_arm > 0 and v_lock < v_arm) is distinct from true then v_bad := v_bad || ' JOB-LOCK-AFTER-THE-FIRST-ARM'; end if;
    if (v_src ~ 'pg_advisory_unlock') is distinct from false then v_bad := v_bad || ' SESSION-UNLOCK-PRESENT'; end if;
    if (v_src ~ 'c_ask_title constant text := ''인계 확인 요청''') is distinct from true then v_bad := v_bad || ' ASK-TITLE-NOT-THE-EDGE''S'; end if;
    if (v_src ~ 'nt\.title = c_ask_title') is distinct from true then v_bad := v_bad || ' ASK-NOT-MATCHED-BY-TITLE'; end if;
    if (v_src ~ 'nt\.profile_id = x\.counterparty') is distinct from true then v_bad := v_bad || ' ASK-NOT-MATCHED-BY-COUNTERPARTY(an ask to the OTHER party would silence the re-send)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' PER-ROW-HANDLERS(' || v_n || '/2 — arm ⓒ must catch its own row like ⓑ)'; end if;
    if (v_src ~ '\(b\.owner_confirmed_handoff_at is null\) <> \(b\.runner_confirmed_handoff_at is null\)') is distinct from true then v_bad := v_bad || ' EXACTLY-ONE-STAMP-PREDICATE-MISSING'; end if;
    if (v_src ~ 'b\.status not in \(''draft''' and v_src ~ '''matching''' and v_src ~ '''runner_pending''' and v_src ~ '''picked_up''' and v_src ~ '''completed''' and v_src ~ '''incident_review''' and v_src ~ '''refund_pending''') is distinct from true then v_bad := v_bad || ' DENY-LIST-MISSING-A-STATUS'; end if;
    if (v_src ~ 'b\.status in \(''confirmed''') is distinct from false then v_bad := v_bad || ' LIVE-ALLOW-LIST-PRESENT(the attack-INACTION law prefers the deny-list)'; end if;
    if (v_src ~ 'b\.runner_id is not null') is distinct from true then v_bad := v_bad || ' RUNNER-CONJUNCT-MISSING'; end if;
    -- arms ⓐ/ⓑ keep their marketplace scope (0144:94); arm ⓒ deliberately has none
    select count(*) into v_n from regexp_matches(v_src, 'club_session_id is null', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' CLUB-SCOPE-COUNT(' || v_n || '/2)'; end if;
    if (v_src ~ '정산을 확인하고 있어요' and v_src ~ '귀가 확인이 필요해요') is distinct from true then v_bad := v_bad || ' 0083-ARMS-MISSING'; end if;
  end if;
  if v_bad <> '' then raise exception '0181 VERIFY FAILED:%', v_bad; end if;
end $$;
