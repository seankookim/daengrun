-- ═══ 237 — 0206: the ops console's missing doors ═══════════════════════════════════════════════
-- ═══        0206-R1 · R2 · R3 · H1 · H2 · G1 · S1, tag `ocv`                               ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · R1 **PARTY BEFORE READ, on `ops_stranded_returns()`.** A runner, a signed-in stranger, an
--        INACTIVE `return_strand` row, a `payout_due`-only operator and a `handoff_unanswered`-only
--        operator all get `not_ops` — and they get it **identically whether or not a stranded
--        return exists**, which is measured by calling every one of them BEFORE this suite builds
--        a single strand and again after the sweep has belled three. No caller at all ⇒
--        `not_signed_in`. An ACTIVE `return_strand` operator passes (the control without which
--        the pin is satisfied by refusing everyone).
--        🔴 AND `ops_me().kinds` AGREES WITH THE DOOR IN BOTH DIRECTIONS. The client draws the
--        반환 좌초 section only when `kinds` carries `return_strand` (0206 §0b — the console's
--        `_layout` gate is `payout_due`'s and this slice does not widen it), so a `kinds` that can
--        disagree with this door is a dead button either way it fails. Both directions matter: a
--        `kinds` hard-wired full and one hard-wired empty each satisfy exactly one of them.
--   · R2 🔴 **THE LIST IS THE SWEEP'S OWN CANDIDATE SET.** On one shared fixture, with
--        `return_strand_minutes` set and `sweep_run_end_recovery()` actually TICKED, the set of
--        this suite's bookings that the sweep BELLED (「반환 좌초 — 확인 필요」) is **equal** to the
--        set `ops_stranded_returns()` returns. Not 「equivalent to a copy of the predicate」 — the
--        comparison is against the deployed sweep's own output, so a divergence in either
--        direction reddens. Both sets are non-empty (the fixture is not vacuous) and the four
--        rows that must be in NEITHER are named individually.
--   · R3 **THE FACTS ARE THE ROW'S.** For each admitted booking: the two stamps are reported as
--        they stand, `run_ended_at` is the row's, `minutes_stranded` matches it, `status` is the
--        RAW server word, `notified_at` is the bell's instant (not NULL once belled, NULL before),
--        `strand_minutes` is `ops_flags`' current value, and the dog / owner / runner names are
--        the real ones. ⚠ Includes the divergence row 0201's codex #2 was about: an
--        `incident_review` return carrying BOTH stamps and no seal is ADMITTED — the pre-0201
--        predicate excluded exactly that row.
--        AND the list carries NO money and no contact field, asserted as the FUNCTION'S OWN KEY
--        SET (`to_jsonb(x)`) rather than as a substring scan of the serialised row — the first
--        version WAS that scan and it reddened on correct code, because a uuid's hex spells
--        `fee`. The key set cannot be forged by a value, and a column ADDED later reddens.
--   · H1 **PARTY BEFORE READ, on `ops_stalled_handoffs()`, and the rosters are SEPARATE.** Same
--        five refused shapes plus the mirror one — a `return_strand`-only operator is refused
--        HERE and a `handoff_unanswered`-only operator is refused by §A — which is 0084 §E's
--        「different classes are different rosters」 (0201 §C's law) as a measurement. `kinds`
--        agreement, both directions, for `handoff_unanswered`.
--   · H2 🔴 **A STALLED HANDOFF APPEARS AND LEAVES.** A one-sided handoff older than the sweep's
--        ESCALATE_AFTER appears in the list **after the sweep escalates it** (not before — the
--        `handoff_escalated_at is not null` conjunct), carries the right side's stamp,
--        `escalated_at` and `ops_alerted_at`; then the counterparty's confirm makes it LEAVE,
--        while a sibling row escalated in the same tick STAYS (the control without which
--        「it left」 is indistinguishable from 「the list emptied」). A row escalated and then moved
--        to a dead status also leaves (the deny-list conjunct).
--   · G1 **THE GEAR BELL RINGS EXACTLY ONCE, AND ONLY ON A CLAIM THAT LANDED.** Before the claim:
--        zero rows. After it: exactly one `system` row per ACTIVE `payout_due` recipient, titled
--        「굿즈 수령 신청 — 확인 필요」, `ref_id` = the claim id, body carrying NO identifier. A
--        SECOND call (`already_claimed`) adds none. A REFUSED claim — `not_claim_owner` on
--        somebody else's row, `bad_postal` on the caller's own — writes none at all. The roster is
--        non-empty in the fixture (without that control the count 「equals the roster size」 is
--        satisfied by writing nothing to nobody).
--   · S1 **DEPLOYED SHAPE.** Three definers, in-body `search_path`, ACL by EFFECTIVE privilege in
--        both directions, both lists take ZERO arguments, and the comment-STRIPPED source showing:
--        each list's ops gate ahead of its read, each list's roster constant, arm ⓕ's two-state
--        clause and deadline carried textually, 0183's deny-list carried, and `claim_gear_tx`'s
--        bell BELOW both the idempotent early return and the asserted write. The strand title and
--        the deny-list are matched against the DEPLOYED sweep as well, so a copy here cannot drift
--        from the original. NO-FUNCTION / NO-SOURCE arms fail loudly, because `position(… in NULL)`
--        is NULL and every bare `IF` over it is silent.
--
-- ─── FIXTURE NOTES ───
--  ① Every set and every count in this file is SCOPED to this suite's own bookings, claims and
--     profiles. `bookings`, `notifications`, `gear_claims` and the `return_strand` /
--     `handoff_unanswered` / `payout_due` rosters are all shared with a dozen other suites in the
--     same database, so a global figure would measure the harness rather than this slice (229's
--     note ①, 232's note on `t_sml_bells`).
--  ② The world is built as the table owner (the harness default) so statuses and dates can be set
--     freely; every ASSERTION about the product goes through the function with
--     `request.jwt.claim.sub` set, which is how a real caller arrives.
--  ③ `request.jwt.claim.sub` is cleared EXPLICITLY for the no-caller arms — a leftover claim makes
--     `not_signed_in` unreachable and the arm then passes for the wrong reason.
--  ④ 🔴 **THIS SUITE TICKS `sweep_run_end_recovery()` FOR REAL, FIVE TIMES.** That is the whole
--     point of R2 (a copy of the predicate compared against itself proves nothing), and it has a
--     cost worth naming: the sweep is global and batched (`limit 50` per arm), so with enough
--     OTHER suites' strands sitting ahead of mine in `order by run_ended_at` a single tick could
--     shadow my rows. Five ticks is 250 candidate slots and the set DRAINS (a belled row is
--     excluded next tick), and R2's membership arms name my three rows individually — so a
--     shadowed fixture fails LOUDLY instead of quietly comparing two empty sets.
--     ⚠ It also means this suite must stay LAST in `harness.sh`'s manifest: ticking the sweep
--     mutates rows other suites built, and a suite that ran after it would be reading a world this
--     one moved. 232 already ticks it repeatedly for the same reason.
--  ⑤ `ops_flags.return_strand_minutes` ships NULL and NULL means arm ⓕ is inert. This file sets it
--     to 120 for the measurement and RESTORES NULL at the end — the shipped value, and the one
--     232's own note ③ depends on.
--  ⑥ 0188 arm ⓑ-① moves a zero-stamp strand `active → incident_review` at STRAND_AFTER (2h) — in
--     the SAME tick, before arm ⓕ runs. So the fixture's 200-minute no-stamp row is `incident_review`
--     by the time the list reads it, and R3 asserts its status is one of the two the predicate
--     admits rather than pinning a value the sweep is free to move. That is the product behaving,
--     not the suite being vague.
--
-- ─── MUTATION MAP — MEASURED, NEVER PREDICTED ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant CHAIN-GATED to
-- its harness run (`plant.py && harness.sh`) so a failed plant yields NO ROW rather than a green
-- one, control observed clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------

-- A marketplace return in a named shape. Built through `t_active_booking` (status `active` + a
-- `runs` row) and then aged — the run row moves with the booking, because a frozen stop whose
-- `runs.ended_at` disagrees with `bookings.run_ended_at` is not a state the product makes (232's
-- `t_sml_age` idiom).
create or replace function t_ocv_ret(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                     p_ago interval, p_runner_stamp boolean, p_owner_stamp boolean,
                                     p_incident boolean, p_sealed boolean, p_club uuid default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_active_booking(p_owner, p_runner, p_dog, p_route);
  update runs set ended_at = now() - p_ago where booking_id = v;
  update bookings
     set run_ended_at = now() - p_ago,
         club_session_id = p_club,
         runner_confirmed_return_at = case when p_runner_stamp then now() - p_ago + interval '1 minute' end,
         owner_confirmed_return_at  = case when p_owner_stamp  then now() - p_ago + interval '2 minutes' end,
         settlement_ready_at        = case when p_sealed       then now() - p_ago + interval '3 minutes' end
   where id = v;
  -- `active → incident_review` is an edge the 0066 map allows, so this is the product's own way in
  if p_incident then update bookings set status = 'incident_review' where id = v; end if;
  return v;
end $$;

-- A booking sitting in a ONE-SIDED pickup handoff. Inserted directly at `confirmed` because the
-- transition trigger is `before update OF status` and `active → confirmed` is not an edge; the
-- handoff-cycle trigger mints the cycle id on INSERT and FORCES `handoff_escalated_at` NULL, which
-- is exactly what H2 needs — the escalation must come from the SWEEP, not from the fixture.
create or replace function t_ocv_handoff(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                         p_ago interval, p_owner_side boolean)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare,
    owner_confirmed_handoff_at, runner_confirmed_handoff_at)
  values (p_owner, p_dog, p_runner, p_route, 'confirmed', now() - p_ago, 5.0,
          9900, 15000, 0, 24900, 9900,
          case when p_owner_side then now() - p_ago end,
          case when p_owner_side then null else now() - p_ago end)
  returning id into v;
  return v;
end $$;

-- `ops_stranded_returns()` as ONE caller sees it, keyed by booking id so membership is a `?` test.
-- Reports the rows OR the raise, never both and never a swallowed success.
create or replace function t_ocv_strand_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.booking_id::text, jsonb_build_object(
             'dog', x.dog_name, 'owner', x.owner_name, 'runner', x.runner_name,
             'status', x.status, 'ended', x.run_ended_at,
             'rstamp', x.runner_stamped, 'ostamp', x.owner_stamped,
             'mins', x.minutes_stranded, 'deadline', x.strand_minutes,
             'notified', x.notified_at)), '{}'::jsonb)
      into v from ops_stranded_returns() x;
    return jsonb_build_object('rows', v, 'n', (select count(*)::int from jsonb_object_keys(v)));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- The SAME read, serialised with `to_jsonb(x)` so the answer carries the FUNCTION'S OWN column
-- names and values rather than the names the helper above chose. R3's disclosure scan uses this
-- one: a scan over a re-keyed projection would be measuring the helper's whitelist, and a column
-- ADDED to the function later would be invisible to it — which is the fixture-testing failure this
-- house keeps meeting.
create or replace function t_ocv_strand_raw(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from ops_stranded_returns() x;
    return jsonb_build_object('rows', v);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_ocv_handoffs_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_object_agg(x.booking_id::text, jsonb_build_object(
             'dog', x.dog_name, 'owner', x.owner_name, 'runner', x.runner_name,
             'status', x.status, 'scheduled', x.scheduled_at,
             'ostamp', x.owner_stamped, 'rstamp', x.runner_stamped,
             'stamped_at', x.stamped_at, 'mins', x.minutes_stalled,
             'escalated', x.escalated_at, 'alerted', x.ops_alerted_at)), '{}'::jsonb)
      into v from ops_stalled_handoffs() x;
    return jsonb_build_object('rows', v, 'n', (select count(*)::int from jsonb_object_keys(v)));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- `ops_me()` as one caller sees it — R1/H1's `kinds` oracle. 0198 §A owns the function; this is a
-- read of it, and 229 owns its correctness.
create or replace function t_ocv_me(p_uid uuid) returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from ops_me();
    return jsonb_build_object('is_ops', r.is_ops, 'kinds', to_jsonb(r.kinds));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_ocv_claim(p_owner uuid, p_item text) returns uuid language sql as $$
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (p_owner, 'runner', p_item, 10, 'claimable') returning id
$$;

create or replace function t_ocv_claim_as(p_uid uuid, p_claim uuid,
  p_recipient text, p_phone text, p_a1 text, p_a2 text, p_postal text)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from claim_gear_tx(p_claim, p_recipient, p_phone, p_a1, p_a2, p_postal);
    return jsonb_build_object('status', r.status, 'already', r.already_claimed);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- How many rows with this title point at this ref — to ONE recipient, or to everybody when
-- `p_profile` is NULL. ⚠ The rosters are SHARED, so the global form is only ever used against a
-- ref THIS suite created (232's `t_sml_bells` note, same trap).
create or replace function t_ocv_bells(p_ref uuid, p_title text, p_profile uuid default null)
returns int language sql as $$
  select count(*)::int from notifications
   where ref_id = p_ref and title = p_title
     and (p_profile is null or profile_id = p_profile)
$$;

do $$
declare
  opsRet  uuid;  -- active return_strand operator        — §A's admitted caller
  opsHnd  uuid;  -- active handoff_unanswered operator   — §B's admitted caller
  opsPay  uuid;  -- active payout_due ONLY               — refused by BOTH (separate rosters)
  opsOff  uuid;  -- return_strand, active = false        — refused by §A
  outsdr  uuid;  -- an ordinary owner, no ops row at all
  o       uuid;
  rn      uuid;  -- the runner in every booking here
  gr      uuid;  -- the runner who owns the gear claims
  dgS uuid; dgO uuid; dgI uuid; dgH uuid; rt uuid;
  cid uuid; sid uuid;                       -- a club + session, for the out-of-scope control
  bS uuid; bOne uuid; bIncBoth uuid;        -- the three the sweep must bell
  bBoth uuid; bYoung uuid; bSealed uuid; bClub uuid;   -- the four it must not
  hA uuid; hB uuid; hDead uuid; hYoung uuid;
  clA uuid; clB uuid; clC uuid;
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  c_gear_title   constant text := '굿즈 수령 신청 — 확인 필요';
  v jsonb; v2 jsonb; vme jsonb;
  v_bad text := '';
  v_msg text;
  v_src text;
  v_sweep text;
  v_oid oid;
  v_n int;
  v_roster int;
  v_belled uuid[];
  v_listed uuid[];
  v_row jsonb;
  v_txt text;
  fn text;
  caller text;
  callers text[];
  b uuid;
  i int;
  needle text;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③

  opsRet := t_user('ocv_ops_ret',  'owner');
  opsHnd := t_user('ocv_ops_hnd',  'owner');
  opsPay := t_user('ocv_ops_pay',  'owner');
  opsOff := t_user('ocv_ops_off',  'owner');
  outsdr := t_user('ocv_outsider', 'owner');
  o      := t_user('ocv_owner',    'owner');
  rn     := t_user('ocv_runner',   'runner');
  gr     := t_user('ocv_gearman',  'runner');
  dgS := t_dog(o, 'ocv-보리'); dgO := t_dog(o, 'ocv-초코');
  dgI := t_dog(o, 'ocv-단추'); dgH := t_dog(o, 'ocv-나무');
  rt := t_route('ocv 코스');

  insert into ops_recipients (profile_id, event_class, active) values
    (opsRet, 'return_strand',      true),
    (opsHnd, 'handoff_unanswered', true),
    (opsPay, 'payout_due',         true),
    (opsOff, 'return_strand',      false);

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-R1] party before read, on the strand list — AND the word does not depend on the world
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ This half runs BEFORE a single strand exists. The second half runs after the sweep has
  --   belled three of them. A gate that ran AFTER the read would be free to answer differently in
  --   the two worlds; the point of measuring both is that it does not.
  v_bad := '';
  callers := array[outsdr::text, rn::text, o::text, opsPay::text, opsHnd::text, opsOff::text];
  foreach caller in array callers loop
    v := t_ocv_strand_as(caller::uuid);
    if v->>'raised' is distinct from 'not_ops'
      then v_bad := v_bad || ' [빈 세계] ' || left(caller,8) || ': ' || coalesce(v->>'raised', 'ADMITTED n=' || coalesce(v->>'n','?')); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③
  v := t_ocv_strand_as(null);
  if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' [빈 세계] 무기명: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  -- the control: the real operator is ADMITTED even with nothing to show (an empty list is an
  -- answer and must not be a refusal — without this arm the loop above is satisfied by a function
  -- that refuses everybody).
  v := t_ocv_strand_as(opsRet);
  if v->>'raised' is not null
    then v_bad := v_bad || ' [빈 세계] 대조: 현역 return_strand 운영자가 거절됨: ' || (v->>'raised'); end if;

  -- ── the fixture ──────────────────────────────────────────────────────────────────────────
  -- Nets of the predicate, laid out so each row sits where two candidate rules DISAGREE:
  --   bS       active · 200m · NO stamps          → arm ⓑ-① moves it to incident_review, ⓕ bells it
  --   bOne     active · 200m · runner stamp only  → ⓕ bells it (not BOTH stamps)
  --   bIncBoth incident_review · 200m · BOTH      → ⓕ bells it. 🔴 the pre-0201 predicate did NOT
  --   bBoth    active · 200m · BOTH stamps        → NOT a candidate (the `not both` half still bites)
  --   bYoung   active · 10m  · NO stamps          → NOT a candidate (the deadline)
  --   bSealed  active · 200m · sealed             → NOT a candidate (settlement_ready_at)
  --   bClub    active · 200m · a club session     → NOT a candidate (club is out of scope)
  bS       := t_ocv_ret(o, rn, dgS, rt, interval '200 minutes', false, false, false, false);
  bOne     := t_ocv_ret(o, rn, dgO, rt, interval '205 minutes', true,  false, false, false);
  bIncBoth := t_ocv_ret(o, rn, dgI, rt, interval '210 minutes', true,  true,  true,  false);
  bBoth    := t_ocv_ret(o, rn, dgS, rt, interval '215 minutes', true,  true,  false, false);
  bYoung   := t_ocv_ret(o, rn, dgO, rt, interval '10 minutes',  false, false, false, false);
  bSealed  := t_ocv_ret(o, rn, dgI, rt, interval '220 minutes', false, false, false, true);
  insert into clubs (name, district, status, host_profile_id)
  values ('ocv클럽', '성수동', 'active', o) returning id into cid;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
  values (cid, o, now() - interval '4 hours', 'ocv 집결지') returning id into sid;
  bClub    := t_ocv_ret(o, rn, dgS, rt, interval '225 minutes', false, false, false, false, sid);

  -- the handoff world (H2). Two escalate, one is too young to escalate, one will die.
  hA     := t_ocv_handoff(o, rn, dgH, rt, interval '90 minutes', true);   -- owner stamped
  hB     := t_ocv_handoff(o, rn, dgH, rt, interval '80 minutes', false);  -- runner stamped
  hDead  := t_ocv_handoff(o, rn, dgH, rt, interval '70 minutes', true);
  hYoung := t_ocv_handoff(o, rn, dgH, rt, interval '3 minutes',  true);

  -- ⚠ ⑤ the deadline. NULL is the shipped value and means arm ⓕ does nothing at all.
  update ops_flags set return_strand_minutes = 120, updated_at = now() where id;
  -- ⚠ ④ five ticks, because the sweep is global and batched and the set DRAINS.
  for i in 1..5 loop perform sweep_run_end_recovery(); end loop;

  -- the second half of R1: the same six callers, the same word, in a world that now has strands
  foreach caller in array callers loop
    v := t_ocv_strand_as(caller::uuid);
    if v->>'raised' is distinct from 'not_ops'
      then v_bad := v_bad || ' [좌초 있는 세계] ' || left(caller,8) || ': ' || coalesce(v->>'raised', 'ADMITTED n=' || coalesce(v->>'n','?')); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③
  v := t_ocv_strand_as(null);
  if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' [좌초 있는 세계] 무기명: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  -- and the control that makes the two worlds genuinely different: the operator now SEES rows.
  v := t_ocv_strand_as(opsRet);
  if v->>'raised' is not null then
    v_bad := v_bad || ' 대조: 현역 운영자가 거절됨: ' || (v->>'raised');
  elsif (v->'rows' ? bS::text) is not true then
    v_bad := v_bad || ' 대조: 두 세계가 같다 — 좌초를 만들었는데 목록이 비어 있다';
  end if;

  -- 🔴 `kinds` agrees with the door, BOTH directions. The client draws the section on `kinds`.
  foreach caller in array array[opsRet::text, opsHnd::text, opsPay::text, opsOff::text,
                                outsdr::text, rn::text, o::text] loop
    vme := t_ocv_me(caller::uuid);
    v   := t_ocv_strand_as(caller::uuid);
    if vme->>'raised' is not null then
      v_bad := v_bad || ' ops_me가 거절됨(' || left(caller,8) || '): ' || (vme->>'raised'); continue;
    end if;
    if (vme->'kinds' @> '["return_strand"]'::jsonb) is true then
      if v->>'raised' is not null
        then v_bad := v_bad || ' kinds에 return_strand가 있는데 문이 거절(' || left(caller,8) || '): ' || (v->>'raised'); end if;
    else
      if v->>'raised' is distinct from 'not_ops'
        then v_bad := v_bad || ' kinds에 return_strand가 없는데 문이 통과(' || left(caller,8) || '): ' || coalesce(v->>'raised','ADMITTED'); end if;
    end if;
  end loop;

  if v_bad = '' then call _pass('ocv','0206-R1 ops_stranded_returns는 읽기보다 게이트가 먼저다 — 러너·외부인·비활성 return_strand·payout_due 전용·handoff_unanswered 전용이 전부 not_ops이고 **좌초가 하나도 없는 세계와 셋이 있는 세계에서 같은 낱말**이며(두 세계가 실제로 다르다는 대조 포함), 무기명은 not_signed_in, 현역 운영자는 빈 목록도 거절이 아니라 답으로 받는다; ops_me().kinds와 이 문은 양방향으로 일치한다(클라가 섹션을 그리는 근거가 죽은 버튼이 되지 않는다)');
  else v_msg := v_bad; call _fail('ocv','0206-R1 좌초 목록 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-R2] the list IS the sweep's candidate set — compared against the SWEEP'S OWN OUTPUT
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- A predicate compared against a copy of itself proves nothing. The sweep ran; the rows it
  -- BELLED are its candidate set made observable, and that is what this arm compares to.
  v_bad := '';
  select coalesce(array_agg(t.bid order by t.bid), '{}'::uuid[]) into v_belled
    from unnest(array[bS, bOne, bIncBoth, bBoth, bYoung, bSealed, bClub]) as t(bid)
   where exists (select 1 from notifications nt where nt.ref_id = t.bid and nt.title = c_strand_title);

  v := t_ocv_strand_as(opsRet);
  if v->>'raised' is not null then
    v_bad := v_bad || ' 운영자가 거절됨: ' || (v->>'raised');
  else
    select coalesce(array_agg(t.bid order by t.bid), '{}'::uuid[]) into v_listed
      from unnest(array[bS, bOne, bIncBoth, bBoth, bYoung, bSealed, bClub]) as t(bid)
     where (v->'rows' ? t.bid::text) is true;

    -- ⚠ the fixture must not be vacuous in EITHER direction: two empty sets are equal.
    if array_length(v_belled, 1) is distinct from 3 then
      v_bad := v_bad || ' 스윕이 종을 울린 행이 3개가 아니다 (' || coalesce(array_length(v_belled,1),0)::text
            || ') — 배치에 가려졌거나 술어가 바뀌었다: ' || coalesce(v_belled::text,'{}');
    end if;
    if v_belled is distinct from v_listed then
      v_bad := v_bad || ' 🔴 스윕의 후보 집합과 목록이 다르다 — 종:' || coalesce(v_belled::text,'{}')
            || ' 목록:' || coalesce(v_listed::text,'{}');
    end if;
    -- and each side named individually, so a failure says WHICH row rather than 「두 집합이 다르다」
    foreach b in array array[bS, bOne, bIncBoth] loop
      if (v->'rows' ? b::text) is not true
        then v_bad := v_bad || ' 좌초인데 목록에 없다: ' || left(b::text,8); end if;
      if t_ocv_bells(b, c_strand_title) < 1
        then v_bad := v_bad || ' 좌초인데 스윕이 종을 안 울렸다: ' || left(b::text,8); end if;
    end loop;
    foreach b in array array[bBoth, bYoung, bSealed, bClub] loop
      if (v->'rows' ? b::text) is true
        then v_bad := v_bad || ' 좌초가 아닌데 목록에 있다: ' || left(b::text,8); end if;
      if t_ocv_bells(b, c_strand_title) <> 0
        then v_bad := v_bad || ' 좌초가 아닌데 스윕이 종을 울렸다: ' || left(b::text,8); end if;
    end loop;
  end if;

  if v_bad = '' then call _pass('ocv','0206-R2 좌초 목록은 스윕 팔 ⓕ의 후보 집합 그 자체 — 술어의 복사본이 아니라 **실제로 틱을 돌린 스윕이 종을 울린 행들**과 집합이 같다(양쪽 모두 비어 있지 않고, 들어와야 할 셋과 빠져야 할 넷을 각각 이름으로 확인: 양쪽 스탬프 active·마감 전·봉인·클럽)');
  else v_msg := v_bad; call _fail('ocv','0206-R2 스윕 후보 집합 일치', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-R3] the facts are the ROW's — and the row carries no money and no contact field
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_ocv_strand_as(opsRet);
  if v->>'raised' is not null then
    v_bad := v_bad || ' 운영자가 거절됨: ' || (v->>'raised');
  else
    -- bOne: exactly one stamp, the runner's, and the status is still `active` (arm ⓑ-② moves
    -- nothing). The dog and both party names are the real ones.
    v_row := v->'rows'->(bOne::text);
    if v_row is null then v_bad := v_bad || ' bOne이 목록에 없다';
    else
      if (v_row->>'rstamp')::boolean is not true  then v_bad := v_bad || ' bOne 러너 스탬프=' || coalesce(v_row->>'rstamp','NULL'); end if;
      if (v_row->>'ostamp')::boolean is not false then v_bad := v_bad || ' bOne 보호자 스탬프=' || coalesce(v_row->>'ostamp','NULL'); end if;
      if v_row->>'status' is distinct from 'active' then v_bad := v_bad || ' bOne status=' || coalesce(v_row->>'status','NULL'); end if;
      if v_row->>'dog'    is distinct from 'ocv-초코'  then v_bad := v_bad || ' bOne 개 이름=' || coalesce(v_row->>'dog','NULL'); end if;
      if v_row->>'owner'  is distinct from 'ocv_owner'  then v_bad := v_bad || ' bOne 보호자 이름=' || coalesce(v_row->>'owner','NULL'); end if;
      if v_row->>'runner' is distinct from 'ocv_runner' then v_bad := v_bad || ' bOne 러너 이름=' || coalesce(v_row->>'runner','NULL'); end if;
      if (v_row->>'deadline')::int is distinct from 120 then v_bad := v_bad || ' bOne 마감=' || coalesce(v_row->>'deadline','NULL'); end if;
      -- the bell has rung, so its instant is a fact and not a NULL
      if v_row->>'notified' is null then v_bad := v_bad || ' bOne notified_at이 NULL인데 종은 울렸다'; end if;
      -- minutes_stranded is the ROW's, not a constant: 205 minutes ago, ±2 for the clock
      if abs((v_row->>'mins')::int - 205) > 2 then v_bad := v_bad || ' bOne 경과 분=' || coalesce(v_row->>'mins','NULL'); end if;
      -- and `ended` agrees with the number
      if (v_row->>'ended') is null then v_bad := v_bad || ' bOne run_ended_at이 NULL'; end if;
    end if;

    -- 🔴 bIncBoth: the 0201 codex #2 row. BOTH stamps, unsealed, `incident_review` — admitted.
    v_row := v->'rows'->(bIncBoth::text);
    if v_row is null then v_bad := v_bad || ' 🔴 bIncBoth(양쪽 스탬프 + incident_review + 미봉인)가 목록에 없다 — 0201 codex #2 이전 술어로 돌아갔다';
    else
      if (v_row->>'rstamp')::boolean is not true then v_bad := v_bad || ' bIncBoth 러너 스탬프=' || coalesce(v_row->>'rstamp','NULL'); end if;
      if (v_row->>'ostamp')::boolean is not true then v_bad := v_bad || ' bIncBoth 보호자 스탬프=' || coalesce(v_row->>'ostamp','NULL'); end if;
      if v_row->>'status' is distinct from 'incident_review' then v_bad := v_bad || ' bIncBoth status=' || coalesce(v_row->>'status','NULL'); end if;
    end if;

    -- ⑥ bS: the sweep is free to have moved it, and it must still be one of the two the
    --    predicate admits — pinning `active` here would pin the suite's fixture, not the rule.
    v_row := v->'rows'->(bS::text);
    if v_row is null then v_bad := v_bad || ' bS가 목록에 없다';
    elsif v_row->>'status' not in ('active', 'incident_review')
      then v_bad := v_bad || ' bS status=' || coalesce(v_row->>'status','NULL'); end if;

    -- ── what the row may carry, asserted on the FUNCTION'S OWN COLUMN NAMES ──────────────────
    -- `to_jsonb(x)` so the keys are the function's, not the names the helper above chose: a scan
    -- over a re-keyed projection would measure the helper's whitelist, and a column ADDED to the
    -- function later would be invisible to it.
    --
    -- 🔴 **THE KEY SET, NOT A SUBSTRING SCAN OF THE SERIALISED ROW — AND THE FIRST VERSION OF THIS
    --    ARM WAS THE SUBSTRING SCAN, WHICH REDDENED ON A CORRECT FUNCTION.** Measured 2026-09-22:
    --    it searched `lower(to_jsonb(x)::text)` for `fee`/`phone`/`account`/… and fired
    --    「좌초 목록에 fee 가 실렸다」 because a **uuid's hex spells `fee`**. That is this house's
    --    crude-detector trap in miniature — a pattern that matches in both the disclosing and the
    --    non-disclosing world is uninformative, and here it was worse than uninformative because
    --    it accused correct code. The key set cannot collide with a value: it is exactly the
    --    columns the function declares, so ADDING one reddens and no hex string can forge one.
    --    The needle scan is kept, narrowed to the KEYS, so a money column that arrives under a
    --    name this whitelist has not been updated for still says WHICH word it was.
    v2 := t_ocv_strand_raw(opsRet);
    if v2->>'raised' is not null then v_bad := v_bad || ' raw 읽기가 거절됨: ' || (v2->>'raised');
    elsif jsonb_array_length(v2->'rows') < 1 then v_bad := v_bad || ' 대조: raw 목록이 비어 있어 훑을 것이 없다';
    else
      select coalesce(string_agg(k, ',' order by k), '') into v_txt
        from jsonb_object_keys(v2->'rows'->0) as t(k);
      if v_txt is distinct from
         'booking_id,dog_name,minutes_stranded,notified_at,owner_name,owner_stamped,'
         || 'run_ended_at,runner_name,runner_stamped,status,strand_minutes'
        then v_bad := v_bad || ' 🔴 좌초 목록의 칸이 바뀌었다: ' || coalesce(v_txt,'NULL'); end if;
      foreach needle in array array['fare','price','fee','net_won','phone','address','account','memo'] loop
        if (position(needle in v_txt) > 0)
          then v_bad := v_bad || ' 🔴 좌초 목록에 ' || needle || ' 칸이 실렸다'; end if;
      end loop;
    end if;
  end if;

  if v_bad = '' then call _pass('ocv','0206-R3 좌초 목록의 사실은 그 행의 것이다 — 스탬프 두 칸·원문 status·종료 시각·경과 분·현재 마감·종 시각·개와 양측의 실제 이름이 전부 행에서 나오고, **양쪽 스탬프를 가진 미봉인 incident_review 반환이 들어온다**(0201 codex #2가 고친 바로 그 행); 직렬화한 답 전체를 훑어도 요금·수수료·순액·전화·주소·계좌·메모는 없다');
  else v_msg := v_bad; call _fail('ocv','0206-R3 좌초 목록의 사실', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-H1] party before read on the handoff list — and the two rosters are SEPARATE
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  foreach caller in array array[outsdr::text, rn::text, o::text, opsPay::text, opsRet::text, opsOff::text] loop
    v := t_ocv_handoffs_as(caller::uuid);
    if v->>'raised' is distinct from 'not_ops'
      then v_bad := v_bad || ' ' || left(caller,8) || ': ' || coalesce(v->>'raised', 'ADMITTED n=' || coalesce(v->>'n','?')); end if;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③
  v := t_ocv_handoffs_as(null);
  if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' 무기명: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  -- the control
  v := t_ocv_handoffs_as(opsHnd);
  if v->>'raised' is not null
    then v_bad := v_bad || ' 대조: 현역 handoff_unanswered 운영자가 거절됨: ' || (v->>'raised'); end if;

  -- 🔴 THE MIRROR, which is the arm that shows these are two rosters and not one ops bit: the
  --    return_strand operator is refused HERE and the handoff operator is refused THERE. Either
  --    one alone is satisfied by a single shared 「is this person ops」 predicate.
  v := t_ocv_handoffs_as(opsRet);
  if v->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 🔴 return_strand 운영자가 인계 목록을 읽는다: ' || coalesce(v->>'raised','ADMITTED'); end if;
  v := t_ocv_strand_as(opsHnd);
  if v->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 🔴 handoff_unanswered 운영자가 좌초 목록을 읽는다: ' || coalesce(v->>'raised','ADMITTED'); end if;

  -- `kinds` agreement for this desk, both directions
  foreach caller in array array[opsHnd::text, opsRet::text, opsPay::text, outsdr::text, rn::text] loop
    vme := t_ocv_me(caller::uuid);
    v   := t_ocv_handoffs_as(caller::uuid);
    if vme->>'raised' is not null then
      v_bad := v_bad || ' ops_me가 거절됨(' || left(caller,8) || '): ' || (vme->>'raised'); continue;
    end if;
    if (vme->'kinds' @> '["handoff_unanswered"]'::jsonb) is true then
      if v->>'raised' is not null
        then v_bad := v_bad || ' kinds에 handoff_unanswered가 있는데 문이 거절(' || left(caller,8) || '): ' || (v->>'raised'); end if;
    else
      if v->>'raised' is distinct from 'not_ops'
        then v_bad := v_bad || ' kinds에 handoff_unanswered가 없는데 문이 통과(' || left(caller,8) || '): ' || coalesce(v->>'raised','ADMITTED'); end if;
    end if;
  end loop;

  if v_bad = '' then call _pass('ocv','0206-H1 ops_stalled_handoffs도 읽기보다 게이트가 먼저다 — 러너·외부인·payout_due·비활성이 전부 not_ops, 무기명은 not_signed_in, 현역 handoff_unanswered 운영자는 통과; **그리고 두 명부는 서로 다른 명부다** — return_strand 운영자는 인계 목록에서, handoff_unanswered 운영자는 좌초 목록에서 각각 거절된다(0084 §E·0201 §C). ops_me().kinds와 양방향 일치');
  else v_msg := v_bad; call _fail('ocv','0206-H1 인계 목록 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-H2] a stalled handoff appears when the sweep escalates it, and LEAVES when confirmed
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_ocv_handoffs_as(opsHnd);
  if v->>'raised' is not null then
    v_bad := v_bad || ' 운영자가 거절됨: ' || (v->>'raised');
  else
    -- appears: escalated by the sweep, carrying the right side's stamp and both records
    v_row := v->'rows'->(hA::text);
    if v_row is null then v_bad := v_bad || ' 승격된 hA가 목록에 없다';
    else
      if (v_row->>'ostamp')::boolean is not true  then v_bad := v_bad || ' hA 보호자 스탬프=' || coalesce(v_row->>'ostamp','NULL'); end if;
      if (v_row->>'rstamp')::boolean is not false then v_bad := v_bad || ' hA 러너 스탬프=' || coalesce(v_row->>'rstamp','NULL'); end if;
      if v_row->>'escalated' is null then v_bad := v_bad || ' hA escalated_at이 NULL인데 목록에 있다'; end if;
      -- the roster is provisioned in this fixture, so 0183's PENDING state is NOT the one we are in
      if v_row->>'alerted' is null then v_bad := v_bad || ' hA ops_alerted_at이 NULL — 명부가 있는데 PENDING으로 남았다'; end if;
      if abs((v_row->>'mins')::int - 90) > 2 then v_bad := v_bad || ' hA 경과 분=' || coalesce(v_row->>'mins','NULL'); end if;
      if v_row->>'status' is distinct from 'confirmed' then v_bad := v_bad || ' hA status=' || coalesce(v_row->>'status','NULL'); end if;
      if v_row->>'dog' is distinct from 'ocv-나무' then v_bad := v_bad || ' hA 개 이름=' || coalesce(v_row->>'dog','NULL'); end if;
    end if;
    -- the sibling, stamped on the OTHER side — the control for the departure below
    if (v->'rows' ? hB::text) is not true then v_bad := v_bad || ' 승격된 hB가 목록에 없다'; end if;
    -- never escalated (3 minutes old): the `handoff_escalated_at is not null` conjunct
    if (v->'rows' ? hYoung::text) is true then v_bad := v_bad || ' 승격된 적 없는 hYoung이 목록에 있다'; end if;
  end if;

  -- 🔴 THE DEPARTURE. The counterparty confirms; the row must leave, and hB must stay — without
  --    the sibling, 「hA left」 and 「the list emptied」 are the same observation.
  update bookings set runner_confirmed_handoff_at = now() where id = hA;
  -- and a row that dies rather than resolves also leaves (the deny-list conjunct)
  update bookings set status = 'cancelled_owner' where id = hDead;
  v2 := t_ocv_handoffs_as(opsHnd);
  if v2->>'raised' is not null then
    v_bad := v_bad || ' 두 번째 읽기가 거절됨: ' || (v2->>'raised');
  else
    if (v2->'rows' ? hA::text) is true then v_bad := v_bad || ' 🔴 양쪽이 확인했는데 hA가 목록에 남아 있다'; end if;
    if (v2->'rows' ? hB::text) is not true then v_bad := v_bad || ' 대조: 건드리지 않은 hB까지 사라졌다 — 목록이 비어버린 것이지 hA가 나간 것이 아니다'; end if;
    if (v2->'rows' ? hDead::text) is true then v_bad := v_bad || ' 종료된 상태(cancelled_owner)인 hDead가 목록에 남아 있다'; end if;
    -- the escalation RECORD survives the confirm — the row left the list, nothing was erased
    select count(*)::int into v_n from bookings where id = hA and handoff_escalated_at is not null;
    if v_n is distinct from 1 then v_bad := v_bad || ' hA의 handoff_escalated_at이 지워졌다 (n=' || v_n::text || ')'; end if;
  end if;

  if v_bad = '' then call _pass('ocv','0206-H2 멈춘 인계는 **스윕이 승격한 뒤에** 목록에 나타나고(3분짜리 미승격 행은 안 나온다) 어느 쪽이 찍었는지·승격 시각·ops 전달 시각·경과 분을 행에서 그대로 싣는다; 상대가 확인하면 목록에서 빠지되 건드리지 않은 형제 행은 남는다(빈 목록과 구별하는 대조), 종료 상태로 간 행도 빠지며(부정 목록), 승격 기록 자체는 지워지지 않는다');
  else v_msg := v_bad; call _fail('ocv','0206-H2 인계 목록의 출입', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-G1] the gear bell rings exactly once, and only for a claim that LANDED
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  clA := t_ocv_claim(gr, 'ocv 러너 조끼');
  clB := t_ocv_claim(gr, 'ocv 러너 모자');
  clC := t_ocv_claim(o,  'ocv 남의 것');
  -- the roster size is read from the table, not assumed — and asserted non-empty, without which
  -- 「the bell count equals the roster」 is satisfied by writing nothing to nobody.
  select count(*)::int into v_roster from ops_recipients
   where event_class = 'payout_due' and active;
  if v_roster < 1 then v_bad := v_bad || ' 대조: payout_due 명부가 비어 있다 — 「정확히 한 번」이 공허하게 참이 된다'; end if;

  -- before: silence
  if t_ocv_bells(clA, c_gear_title) <> 0 then v_bad := v_bad || ' 신청 전인데 종이 울려 있다'; end if;

  v := t_ocv_claim_as(gr, clA, '김운영', '010-1234-5678', '성수동 1-2', '3층', '04779');
  if v->>'raised' is not null then v_bad := v_bad || ' 정상 신청이 거절됨: ' || (v->>'raised');
  else
    if v->>'status' is distinct from 'claimed' then v_bad := v_bad || ' 신청 후 status=' || coalesce(v->>'status','NULL'); end if;
    if t_ocv_bells(clA, c_gear_title) is distinct from v_roster
      then v_bad := v_bad || ' 종 수=' || t_ocv_bells(clA, c_gear_title)::text || ' 명부=' || v_roster::text; end if;
    if t_ocv_bells(clA, c_gear_title, opsPay) is distinct from 1
      then v_bad := v_bad || ' payout_due 운영자에게 간 종=' || t_ocv_bells(clA, c_gear_title, opsPay)::text; end if;
    -- the kind is `system` and the ref is the CLAIM, not the profile
    select count(*)::int into v_n from notifications
     where ref_id = clA and title = c_gear_title and kind = 'system';
    if v_n is distinct from v_roster then v_bad := v_bad || ' kind=system인 종=' || v_n::text; end if;
    -- 0084 §E: an ops body is pushed verbatim to a lock screen, so it names nobody
    select count(*)::int into v_n from notifications
     where ref_id = clA and title = c_gear_title
       and (body like '%' || clA::text || '%' or body like '%' || gr::text || '%' or body like '%김운영%');
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 ops 종 본문에 식별자가 실렸다 (n=' || v_n::text || ')'; end if;
  end if;

  -- a SECOND call on the same claim is `already_claimed` — no second bell
  v := t_ocv_claim_as(gr, clA, '김운영', '010-1234-5678', '성수동 1-2', '3층', '04779');
  if v->>'raised' is not null then v_bad := v_bad || ' 재신청이 예외로 죽었다: ' || (v->>'raised');
  else
    if (v->>'already')::boolean is not true then v_bad := v_bad || ' 재신청 already=' || coalesce(v->>'already','NULL'); end if;
    if t_ocv_bells(clA, c_gear_title) is distinct from v_roster
      then v_bad := v_bad || ' 🔴 재신청이 종을 또 울렸다: ' || t_ocv_bells(clA, c_gear_title)::text; end if;
  end if;

  -- REFUSALS write nothing. Two different refusals, because one is a PARTY gate (above the state
  -- read) and one is the FORM (below it) — a bell placed between them would pass a single arm.
  v := t_ocv_claim_as(gr, clC, '김운영', '010-1234-5678', '성수동 1-2', null, '04779');
  if v->>'raised' is distinct from 'not_claim_owner'
    then v_bad := v_bad || ' 남의 교환권: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if t_ocv_bells(clC, c_gear_title) <> 0 then v_bad := v_bad || ' 🔴 거절된 신청(not_claim_owner)이 종을 울렸다'; end if;

  v := t_ocv_claim_as(gr, clB, '김운영', '010-1234-5678', '성수동 1-2', null, '4779');
  if v->>'raised' is distinct from 'bad_postal'
    then v_bad := v_bad || ' 잘못된 우편번호: ' || coalesce(v->>'raised','ACCEPTED'); end if;
  if t_ocv_bells(clB, c_gear_title) <> 0 then v_bad := v_bad || ' 🔴 거절된 신청(bad_postal)이 종을 울렸다'; end if;
  -- and the row itself is untouched by the refusal (the control that the refusal really refused)
  select count(*)::int into v_n from gear_claims where id = clB and status = 'claimable';
  if v_n is distinct from 1 then v_bad := v_bad || ' 대조: 거절된 교환권의 상태가 움직였다'; end if;

  if v_bad = '' then call _pass('ocv','0206-G1 굿즈 수령 신청이 운영 명부에 종을 **정확히 한 번** 울린다 — 신청 전 0건, 신청 후 활성 payout_due 수신자 수만큼(명부가 비어 있지 않다는 대조 포함), kind=system·ref_id=교환권 id·본문에 식별자 없음(0084 §E); 재신청(already_claimed)은 한 건도 더하지 않고, 파티 게이트 거절(not_claim_owner)도 양식 거절(bad_postal)도 한 건도 쓰지 않으며 거절된 행의 상태는 그대로다');
  else v_msg := v_bad; call _fail('ocv','0206-G1 굿즈 종', v_msg); end if;

  -- ⑤ restore the shipped value before anything else reads it.
  update ops_flags set return_strand_minutes = null, updated_at = now() where id;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0206-S1] deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ These arms and 0206 §D's VERIFY are DIFFERENT ARTIFACTS: that one aborts an apply that
  --   lands wrong, this one reddens when a LATER file undoes something (0131-G4's law).
  -- ⚠ Every arm asserts an EXACT boolean. `position(… in NULL)` is NULL and plpgsql does not take
  --   an `IF` on NULL, so a bare `IF` would be SILENT for exactly the missing function these arms
  --   exist to notice — and NO-FUNCTION / NO-SOURCE fail loudly rather than skipping.
  v_bad := '';
  foreach fn in array array['ops_stranded_returns()', 'ops_stalled_handoffs()',
                            'claim_gear_tx(uuid,text,text,text,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':definer가 아니다'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') = 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':본문 search_path'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC 실행권'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':anon 실행권'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':authenticated 실행권 없음'; end if;
  end loop;

  -- neither list takes an argument: there is no parameter by which to point one at a third party
  foreach fn in array array['ops_stranded_returns()', 'ops_stalled_handoffs()'] loop
    if (select pronargs from pg_proc where oid = to_regprocedure(fn)) is distinct from 0
      then v_bad := v_bad || ' ' || fn || ':인자가 생겼다'; end if;
    if (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'public' and p.proname = split_part(fn, '(', 1)) is distinct from 1
      then v_bad := v_bad || ' ' || fn || ':오버로드가 생겼다'; end if;
  end loop;

  -- the DEPLOYED sweep, comment-stripped — the original both lists were copied from
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_sweep
    from pg_proc where oid = to_regprocedure('sweep_run_end_recovery()');
  if v_sweep is null then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)'; end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_stranded_returns()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_stranded_returns)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 좌초:ops 게이트가 없다'; end if;
    -- ⚠ A NAMED GAP rather than a pass: a `raise` unwinds the whole function whatever order the
    --   statements are in, so a gate moved BELOW the read is byte-identical to a caller and no
    --   fixture can separate the two worlds. This textual arm and 0206 §D's twin are the only
    --   available detectors, which is exactly why they exist (229 (iii)'s shape).
    if (position('raise exception ''not_ops''' in v_src) < position('from bookings b' in v_src)) is not true
      then v_bad := v_bad || ' 좌초:게이트가 읽기보다 뒤에 있다'; end if;
    if (v_src ~ 'c_ops_class\s+constant text := ''return_strand''') is not true
      then v_bad := v_bad || ' 좌초:명부 클래스가 return_strand가 아니다'; end if;
    if (v_src ~ 'b\.settlement_ready_at is null') is not true
      then v_bad := v_bad || ' 좌초:봉인 제외 절이 없다'; end if;
    if (v_src ~ 'b\.status = ''incident_review''\s*or not \(b\.runner_confirmed_return_at is not null and b\.owner_confirmed_return_at is not null\)') is not true
      then v_bad := v_bad || ' 좌초:0201 두 상태 절이 없다'; end if;
    if (v_src ~ 'make_interval\(mins => v_min\)') is not true
      then v_bad := v_bad || ' 좌초:마감 절이 없다'; end if;
    -- no `limit`: a truncated ops list makes an operator clear a subset and believe the queue is empty
    if (v_src ~ '\mlimit\M') is true then v_bad := v_bad || ' 좌초:limit이 생겼다'; end if;
    -- the title it keys `notified_at` on is the SWEEP'S, matched against the deployed sweep
    if v_sweep is not null and (position('''반환 좌초 — 확인 필요''' in v_sweep) > 0) is not true
      then v_bad := v_bad || ' 스윕:좌초 제목이 움직였다'; end if;
    if (position('''반환 좌초 — 확인 필요''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 좌초:제목이 스윕의 것이 아니다'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_stalled_handoffs()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_stalled_handoffs)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 인계:ops 게이트가 없다'; end if;
    if (position('raise exception ''not_ops''' in v_src) < position('from bookings b' in v_src)) is not true
      then v_bad := v_bad || ' 인계:게이트가 읽기보다 뒤에 있다'; end if;
    if (v_src ~ 'c_ops_class\s+constant text := ''handoff_unanswered''') is not true
      then v_bad := v_bad || ' 인계:명부 클래스가 handoff_unanswered가 아니다'; end if;
    if (v_src ~ 'b\.handoff_escalated_at is not null') is not true
      then v_bad := v_bad || ' 인계:승격 절이 없다'; end if;
    if (v_src ~ '\(b\.owner_confirmed_handoff_at is null\) <> \(b\.runner_confirmed_handoff_at is null\)') is not true
      then v_bad := v_bad || ' 인계:한쪽만 확인 절이 없다'; end if;
    if (v_src ~ 'not \(b\.status = any\(c_dead\)\)') is not true
      then v_bad := v_bad || ' 인계:status가 부정 목록이 아니다'; end if;
    if v_sweep is not null and (position('''refund_pending''' in v_sweep) > 0) is not true
      then v_bad := v_bad || ' 스윕:c_dead가 움직였다'; end if;
    if (position('''refund_pending''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 인계:부정 목록이 짧다'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('claim_gear_tx(uuid,text,text,text,text,text)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
  else
    if (position('''굿즈 수령 신청 — 확인 필요''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 굿즈:ops 종이 없다'; end if;
    if (position('raise exception ''not_claim_owner''' in v_src) < position('not_claimable' in v_src)) is not true
      then v_bad := v_bad || ' 굿즈:파티 게이트가 상태 게이트 뒤로 갔다'; end if;
    -- ⚠ the anchor is the early return's PREDICATE, not the word `already_claimed`: that word is
    --   a RETURNS-TABLE column name and `prosrc` carries only the BODY, so an arm keyed on it
    --   would compare `0 < n` — TRUE — and pass wherever the bell sat. Measured before trusting it.
    if (position('v_status in (''claimed'', ''shipped'')' in v_src) > 0) is not true
      then v_bad := v_bad || ' 굿즈:멱등 조기 반환이 없다'; end if;
    if (position('v_status in (''claimed'', ''shipped'')' in v_src)
        < position('insert into notifications' in v_src)) is not true
      then v_bad := v_bad || ' 굿즈:종이 멱등 조기 반환보다 위에 있다'; end if;
    if (position('raise exception ''claim_race''' in v_src)
        < position('insert into notifications' in v_src)) is not true
      then v_bad := v_bad || ' 굿즈:종이 쓰기 단언보다 위에 있다'; end if;
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' 굿즈:종이 명부 창구를 지나지 않는다'; end if;
  end if;

  -- the roster table is still SEALED (0084 §E): RLS on, zero policies. Both lists are definers
  -- precisely because nothing may read that table directly, and a policy appearing here would
  -- make the staff roster client-readable while every pin above stayed green.
  if (select relrowsecurity from pg_class where oid = 'ops_recipients'::regclass) is not true
    then v_bad := v_bad || ' ops_recipients의 RLS가 꺼졌다'; end if;
  if (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'ops_recipients')
     is distinct from 0
    then v_bad := v_bad || ' ops_recipients에 정책이 생겼다'; end if;

  if v_bad = '' then call _pass('ocv','0206-S1 배포 형상 세 객체 — 전부 definer에 본문 search_path가 정확히 일치하고 ACL이 유효 권한으로 양방향이며, 두 목록은 인자 0개·오버로드 없음(제3자를 가리킬 파라미터가 없다); 주석 벗긴 소스에서 각 목록의 ops 게이트가 읽기보다 앞이고 명부 상수가 제 것이며 좌초는 0201 두 상태 절·마감을 글자 그대로 갖고 limit이 없고 제목이 **배포된 스윕의 것**과 같으며, 인계는 0183 부정 목록을 그대로 갖고 그 목록도 스윕의 것과 대조되고, 굿즈 종은 멱등 조기 반환과 쓰기 단언 **아래**에 있으면서 명부 창구를 지난다; ops_recipients는 여전히 RLS on/정책 0개. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
  else v_msg := v_bad; call _fail('ocv','0206-S1 배포 형상', v_msg); end if;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
