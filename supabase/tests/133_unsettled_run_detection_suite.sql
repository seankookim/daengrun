-- ═══ 133 unsettled-run detection suite — 0097 pins (the alarm 0096 removed) ═══
--
-- ═══ WHY ════════════════════════════════════════════════════════════════════════════════
-- `0096` un-deadlocked a runner blocked by an escalated booking. Correct — but it turned a LOUD
-- failure (gated AND unpaid) into a QUIET one (un-gated, still unpaid), because `0083 §0h` —
-- `incident_review` has no marketplace money exit — was never fixed and is money's slice.
-- A runner back at work surfaces nothing. `0097` makes the quiet case visible.
--
-- 🔴 U1 IS THE PIN THAT DEFINES THIS FILE, and it is the one a future reader will want to
--    "simplify" into a column on `ops_gated_runners`. It cannot be one: that function requires a
--    MISSING stamp, and the quiet case starts the instant both stamps land — i.e. the instant its
--    row disappears. U1 measures exactly that handoff: one booking, gated → confirmed → gone from
--    the gate function → present in this one. If someone merges the two, U1 goes red.
--
-- Style: sibling of 119/125/128/130/132 — `_pass('usr',…)`/`_fail('usr',…)`, one begin…exception
--   per case, `_fail` args pre-computed into v_msg (the 110 header law).
-- ⚠ No pin here asserts a money AMOUNT — every money claim is presence/absence, which is also
--   what keeps this suite out of money's surface entirely.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   U1 ← 0097: key the predicate on the STAMPS (i.e. make it a column on `ops_gated_runners`'s
--        population) — the quiet case then becomes invisible at exactly the moment it starts,
--        which is the whole defect this file exists for                          → RED
--   U2 ← 0097: drop `and not exists (select 1 from ledger_items …)` — a booking paid through
--        0081's `record_enroute_cancel_comp` (which writes a ledger row for a CANCELLED booking)
--        is reported as unpaid. Ledger-presence is not a settlement anchor, but its absence is
--        what proves nothing paid the runner                                     → RED
--        · or drop `r.settled_at is null` — a settled run is reported as unpaid   → RED
--   U3 ← 0097: drop `b.club_session_id is null` — every club booking reports as stranded while
--        `club_release_payouts` is handling it perfectly well                     → RED
--   U4 ← 0097: collapse `why` to a constant — an operator cannot tell the KNOWN DEAD END
--        (needs money's slice) from an ordinary pending settlement (retryable), and is sent to
--        the wrong remedy. ⑫'s memo: a signal whose remedy does not apply is worse than none
--                                                                                 → RED
--   U5 ← 0097: grant to authenticated (it lists every runner's unpaid work), or let the function
--        write anything at all — it is `stable` and detection-only by contract     → RED
--   U6 ← add ANY database routine outside `settle_run_tx` that moves a booking to `completed`
--        (a bulk ops correction, a cancellation that "completes", a club bridge) — 0097's
--        `status <> 'completed'` exclusion silently stops seeing real unpaid runners  → RED
--        · or drop `settle_run_tx`'s `and status = 'active'` atomic claim              → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-14, from the worktree. Method: revert applied
--     to `0097` in place, WHOLE harness run (the database is dropped and recreated each run),
--     then restored from a pristine copy and re-verified by md5 + a green run.
--     Pristine `0097` md5 `9bf913b9b877be120274bed0a8961b6b`; green is **556/0** (555/0 before U6).
--       R1 the predicate keyed on the stamps — i.e. **exactly the "column on
--          `ops_gated_runners`" shape that was proposed** → 554/1, red = [U1] alone, detail
--          `🔴 확인되자마자 조용해졌다 (게이트의 컬럼이었다면 이렇게 사라진다)`. The quiet case
--          going invisible at the instant it begins, measured rather than argued. This is the
--          mutation that justifies the whole file being separate from 0096 §7.
--       R2 `and not exists (select 1 from ledger_items …)` deleted → 554/1, red = [U2] alone,
--          detail `원장으로 지급된 예약이 미지급으로 보고됐다` — a booking paid through 0081's
--          comp path reported as unpaid, i.e. the alert crying wolf about a runner who was paid.
--       R3 a FIFTH WRITER added (`ops_force_complete`, a plausible future bulk ops correction that
--          completes a stuck booking without settling) → 555/1, red = [U6] alone, and the detail
--          NAMES it: `settle_run_tx 밖에서 completed로 옮기는 루틴=ops_force_complete`. The
--          tripwire reports which routine broke the premise, not merely that something did.
--     U3/U4/U5 are not machine-proven as primaries. Each is named above with the single revert
--     that would redden it; U3 and U4 both carry positive controls in-pin (strip the club link
--     and the row returns; the two `why` values must differ from each other), and U5's grant
--     matrix is the 116 C21 idiom proven under that suite. Recorded as inherited, not fresh.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A marketplace booking whose run ENDED and which nothing has paid for.
create or replace function t_usr_ended(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                       p_ago interval default interval '3 hours')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '5 hours', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '5 hours', '[]'::jsonb);
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform end_run_tx(v, 3.2, 1800, 'completed', null, null);
  perform set_config('request.jwt.claim.sub', '', false);
  update bookings set run_ended_at = now() - p_ago where id = v;
  update runs set ended_at = now() - p_ago where booking_id = v;
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  b1 uuid; b2 uuid; b3 uuid; v_club uuid; v_sess uuid;
  v_bad text := ''; v_msg text; v_n int; v_txt text; v_js jsonb;
begin
  oo := t_user('usr_oo', 'owner');
  rr := t_user('usr_rr', 'runner'); rz := t_user('usr_rz', 'runner');
  dg := t_dog(oo, '미지급견'); rt := t_route('미지급 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U1] 🔴 THE HANDOFF — the quiet case begins exactly where the gate function ends
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b1 := t_usr_ended(oo, dg, rt, rr);
    perform sweep_run_end_recovery();          -- the real janitor escalates it
    if (select b.status::text from bookings b where b.id = b1) <> 'incident_review'
      then v_bad := v_bad || ' 픽스처가 승격되지 않았다'; end if;

    -- ⓐ while unconfirmed: the GATE sees it (loud — the runner cannot work)
    if not exists (select 1 from ops_gated_runners() g where g.booking_id = b1)
      then v_bad := v_bad || ' 게이트가 미확인 승격 행을 못 봤다'; end if;
    -- …and it is ALREADY unpaid, so this function sees it too — the two overlap here
    if not exists (select 1 from ops_unsettled_runs() u where u.booking_id = b1)
      then v_bad := v_bad || ' 미지급 탐지가 승격 행을 못 봤다'; end if;

    -- ⓑ both parties confirm (0096's fix) — the runner is freed
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform confirm_return_tx(b1, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b1, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓒ 🔴 THE HANDOFF: the gate function drops the row — this is the moment the case goes quiet
    if exists (select 1 from ops_gated_runners() g where g.booking_id = b1)
      then v_bad := v_bad || ' 확인 뒤에도 게이트에 남아있다 (0096이 안 풀었다)'; end if;
    -- …and THIS function must still hold it. If it were a column on the gate function, the row
    -- would be gone and the runner would be silently unpaid — the exact defect 0097 exists for.
    if not exists (select 1 from ops_unsettled_runs() u where u.booking_id = b1)
      then v_bad := v_bad || ' 🔴 확인되자마자 조용해졌다 (게이트의 컬럼이었다면 이렇게 사라진다)'; end if;
    select u.both_confirmed, u.escalated, u.why into v_js, v_txt, v_msg
      from (select both_confirmed::text::jsonb as both_confirmed, escalated::text as escalated, why
              from ops_unsettled_runs() where booking_id = b1) u;
    if coalesce(v_js::text,'') <> 'true' then v_bad := v_bad || ' both_confirmed가 참이 아니다'; end if;
    if v_txt is distinct from 'true' then v_bad := v_bad || ' escalated가 참이 아니다'; end if;
    -- and the runner really is free — the two facts coexist, which is the point
    if coalesce((runner_work_gate(rr)->>'gated')::boolean, true)
      then v_bad := v_bad || ' 러너가 아직 묶여 있다'; end if;

    if v_bad = ''
      then call _pass('usr','U1 인계 지점 — 승격·미확인 동안에는 게이트와 미지급 탐지가 둘 다 잡고, 양측이 확인하는 순간 게이트에서는 사라지지만(러너는 풀린다) 미지급 탐지에는 남는다. 🔴 이것이 ops_gated_runners의 컬럼이 될 수 없는 이유다 — 조용한 경우는 그 행이 사라지는 바로 그 순간 시작된다');
    else v_msg := v_bad; call _fail('usr','U1 인계 지점', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('usr','U1 인계 지점', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U2] paid is paid — by either route
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Two independent ways a runner can have been paid, and both must silence this. The second is
  -- the subtle one: 0081 writes a ledger row for a CANCELLED booking, so ledger-presence is not a
  -- settlement anchor (REGISTRY says so) — but its ABSENCE is what proves nothing paid them.
  begin
    v_bad := '';
    -- ⓐ a normally settled run never appears
    b2 := t_usr_ended(oo, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform confirm_return_tx(b2, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b2, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform _settle_sealed_run(b2, jsonb_build_object(
      'base',9900,'distance_pay',9600,'addon_pay',0,'guarantee',0,'fee',3900));
    if (select r.settled_at from runs r where r.booking_id = b2) is null
      then v_bad := v_bad || ' 픽스처: 정산되지 않았다 (U2가 무의미해진다)'; end if;
    if exists (select 1 from ops_unsettled_runs() u where u.booking_id = b2)
      then v_bad := v_bad || ' 정산된 러닝이 미지급으로 보고됐다'; end if;

    -- ⓑ paid only through a ledger row (0081's comp shape) — also not "unpaid"
    b3 := t_usr_ended(oo, dg, rt, rz);
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                              remaining_guarantee, platform_fee)
    values (rz, b3, 9900, 0, 0, 0, 0, 1980);
    if exists (select 1 from ops_unsettled_runs() u where u.booking_id = b3)
      then v_bad := v_bad || ' 원장으로 지급된 예약이 미지급으로 보고됐다'; end if;

    -- ⓒ positive control: a genuinely unpaid one IS reported (else ⓐ/ⓑ pass vacuously)
    b3 := t_usr_ended(oo, dg, rt, rz);
    if not exists (select 1 from ops_unsettled_runs() u where u.booking_id = b3)
      then v_bad := v_bad || ' 양성 대조 실패: 진짜 미지급이 보고되지 않았다'; end if;
    -- and a run that never ENDED is not "work done" — nothing is owed yet
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (oo, dg, rz, rt, 'active', now() - interval '20 minutes', 5.0, 9900, 15000, 0, 24900, 9900)
    returning id into b2;
    insert into runs (booking_id, started_at, trace) values (b2, now() - interval '20 minutes', '[]'::jsonb);
    if exists (select 1 from ops_unsettled_runs() u where u.booking_id = b2)
      then v_bad := v_bad || ' 아직 안 끝난 러닝이 미지급으로 보고됐다'; end if;

    if v_bad = ''
      then call _pass('usr','U2 지급된 것은 지급된 것 — 정산된 러닝도, 원장으로만 지급된 예약(0081 comp 형상)도 보고되지 않고, 진짜 미지급은 보고되며(양성 대조), 아직 끝나지 않은 러닝은 애초에 대상이 아니다');
    else v_msg := v_bad; call _fail('usr','U2 지급된 것은 지급된 것', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('usr','U2 지급된 것은 지급된 것', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U3] clubs pay through their own machine and must not be reported as stranded
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    insert into clubs (name, district) values ('미지급 클럽', '반포') returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, oo, now() - interval '5 hours', '{"lat":37.51,"lng":127.01}'::jsonb)
    returning id into v_sess;
    b2 := t_usr_ended(oo, dg, rt, rr);
    update bookings set club_session_id = v_sess where id = b2;
    if exists (select 1 from ops_unsettled_runs() u where u.booking_id = b2)
      then v_bad := v_bad || ' 클럽 예약이 미지급으로 보고됐다 (club_release_payouts가 처리한다)'; end if;
    -- positive control: strip the club link and it reappears
    update bookings set club_session_id = null where id = b2;
    if not exists (select 1 from ops_unsettled_runs() u where u.booking_id = b2)
      then v_bad := v_bad || ' 양성 대조 실패: 마켓 예약이 되어도 안 보인다'; end if;

    if v_bad = ''
      then call _pass('usr','U3 클럽 제외 — 클럽 예약은 자체 지급 기계가 있으므로 미지급으로 보고하지 않고, 클럽 링크를 떼면 다시 나타난다 (양성 대조)');
    else v_msg := v_bad; call _fail('usr','U3 클럽 제외', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('usr','U3 클럽 제외', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U4] the reason distinguishes the DEAD END from an ordinary pending settlement
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⑫'s memo: an ops signal whose remedy does not apply is worse than an unmonitored state. The
  -- two rows below need different humans doing different things, and a constant `why` would send
  -- both to the wrong one.
  begin
    v_bad := '';
    -- ⓐ the KNOWN DEAD END — escalated, needs money's slice, not self-serve
    b2 := t_usr_ended(oo, dg, rt, rr);
    perform sweep_run_end_recovery();
    select u.why into v_msg from ops_unsettled_runs() u where u.booking_id = b2;
    if coalesce(v_msg,'') not like '%0083 §0h%'
      then v_bad := v_bad || ' 승격 행의 사유가 막다른 길을 지목하지 않는다=' || coalesce(v_msg,'∅'); end if;
    if coalesce(v_msg,'') not like '%NOT self-serve%'
      then v_bad := v_bad || ' 승격 행이 자력 해결 가능한 것처럼 읽힌다'; end if;

    -- ⓑ an ORDINARY unconfirmed one — not a dead end, becomes the gate's problem if it escalates
    b3 := t_usr_ended(oo, dg, rt, rz, interval '10 minutes');
    select u.why into v_txt from ops_unsettled_runs() u where u.booking_id = b3;
    if coalesce(v_txt,'') like '%0083 §0h%'
      then v_bad := v_bad || ' 평범한 미확인 행이 막다른 길로 보고됐다'; end if;
    if v_txt is not distinct from v_msg
      then v_bad := v_bad || ' 두 사유가 같다 (운영자가 구분할 수 없다)'; end if;

    if v_bad = ''
      then call _pass('usr','U4 사유는 remedy를 가른다 — 승격된 행은 0083 §0h의 막다른 길(자력 불가, money 슬라이스 필요)로, 평범한 미확인 행은 그렇지 않은 것으로 서로 다르게 보고된다 (구분되지 않으면 운영자를 틀린 곳으로 보낸다)');
    else v_msg := v_bad; call _fail('usr','U4 사유는 remedy를 가른다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('usr','U4 사유는 remedy를 가른다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U5] server-only, and it writes nothing
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if has_function_privilege('authenticated', 'ops_unsettled_runs()', 'execute')
      then v_bad := v_bad || ' authenticated에 열렸다 (모든 러너의 미지급 내역이다)'; end if;
    if has_function_privilege('anon', 'ops_unsettled_runs()', 'execute')
      then v_bad := v_bad || ' anon에 열렸다'; end if;
    if not has_function_privilege('service_role', 'ops_unsettled_runs()', 'execute')
      then v_bad := v_bad || ' service_role에서 막혔다'; end if;
    -- definer + pinned search_path (98 H1's law, asserted locally too)
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'ops_unsettled_runs'
           and p.prosecdef and 'search_path=public, pg_temp' = any(p.proconfig)) <> 1
      then v_bad := v_bad || ' definer/search_path 미설정'; end if;
    -- 🔴 detection-only by contract: `stable` (so it CANNOT write) and money is untouched by it
    if (select p.provolatile from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'ops_unsettled_runs') <> 's'
      then v_bad := v_bad || ' stable이 아니다 (쓰기가 가능해진다 — 탐지 전용 계약 위반)'; end if;
    select count(*) into v_n from ledger_items;
    perform count(*) from ops_unsettled_runs();
    if (select count(*) from ledger_items) <> v_n
      then v_bad := v_bad || ' 조회가 원장을 바꿨다'; end if;

    if v_bad = ''
      then call _pass('usr','U5 서버 전용·쓰기 없음 — service_role만 실행하고(anon·authenticated 거부), definer+search_path 고정이며, stable이라 애초에 쓸 수 없고 조회가 원장을 건드리지 않는다 (탐지 전용 계약: 지급 경로는 money의 슬라이스다)');
    else v_msg := v_bad; call _fail('usr','U5 서버 전용·쓰기 없음', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('usr','U5 서버 전용·쓰기 없음', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [U6] 🔴 THE EXCLUSION'S PREMISE — `completed` implies settled, and stays that way
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `ops_unsettled_runs` excludes `status = 'completed'`, and an EXCLUSION is where a detector's
  -- blind spots live: if anything could ever reach `completed` without settling, this function
  -- would silently miss an unpaid runner — the exact failure mode 0097 exists to prevent, hiding
  -- inside 0097 itself.
  --
  -- Today it is safe BY CONSTRUCTION, and the construction is worth stating: every
  -- `update bookings set status = 'completed'` in the repo lives inside a `settle_run_tx` version
  -- (0020 → 0025 → 0028 → 0083, the same function re-created four times) and every one is
  -- guarded `where id = p_booking and status = 'active'` — the atomic claim that settles. So
  -- `completed` cannot be reached except by settling.
  --
  -- ⚠ THIS PIN EXISTS BECAUSE THAT IS A FACT ABOUT TODAY'S CODE, NOT A CONSTRAINT. Nothing in
  -- the schema forbids a future migration from adding a fifth writer — a bulk ops correction, a
  -- cancellation path that "completes" a booking, a club bridge — and the moment one does,
  -- 0097 goes quiet about real unpaid runners while staying green. Found by money reviewing
  -- 0097 and verified by them against production (0 such rows); recorded as a PIN rather than as
  -- a verified-once fact in a review thread, because a fact in a thread protects nobody in a
  -- month. A schema-wide tripwire is the only shape that survives the next migration.
  --
  -- ⚠ AND IT IS PINNED AS A RULE, NOT AS A ROW COUNT — measured, then corrected. My first draft
  -- asserted the DB-wide row invariant ("no completed booking with an ended run and no ledger").
  -- It went RED at 9 rows, and every one was a TEST FIXTURE: suites 103/109/118/128/132 and this
  -- one fabricate `completed` bookings with a direct `update`, which is exactly what fixtures are
  -- for. So that assertion is unrunnable here — permanently red for a true reason that is not
  -- about the product, which this repo's own header law calls the worst kind of red.
  -- The DATA is measured where it means something (production: 0 such rows, money 2026-08-14).
  -- What the harness can own is the RULE, and it is the rule that actually breaks: a FIFTH
  -- WRITER. So ⓐ sweeps the catalogue instead of the rows.
  begin
    v_bad := '';
    -- ⓐ the catalogue sweep: no database routine other than `settle_run_tx` may move a booking
    --    to `completed`. This is fixture-independent (a suite's anonymous DO block never enters
    --    pg_proc) and it catches the thing that would actually silence 0097 —
    --    someone adding a bulk ops correction, a cancellation that "completes", a club bridge.
    select count(*) into v_n
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname <> 'settle_run_tx'
       -- ⚠ `t_%` is the suite-fixture convention and is excluded DELIBERATELY, having verified
       -- the boundary rather than assumed it: no migration anywhere defines a `t_`-prefixed
       -- function (grepped), so the prefix cannot shadow a product routine. Without this the
       -- sweep reports 118's `t_settled_run`, which fabricates a completed booking on purpose.
       and p.proname not like 't\_%'
       and p.prosrc ~* 'update\s+bookings\s+set\s+status\s*=\s*''completed''';
    if v_n <> 0 then
      select string_agg(p.proname, ', ') into v_txt
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname <> 'settle_run_tx'
         and p.proname not like 't\_%'
         and p.prosrc ~* 'update\s+bookings\s+set\s+status\s*=\s*''completed''';
      v_bad := v_bad || ' settle_run_tx 밖에서 completed로 옮기는 루틴=' || coalesce(v_txt,'?')
            || ' (0097의 제외가 구멍이 된다)';
    end if;

    -- ⓑ and the construction that makes ⓐ true is itself asserted: `settle_run_tx` must still
    --    claim atomically from `active`. If a future version drops that guard, ⓐ can start
    --    passing vacuously for a while before real rows appear — so the mechanism is pinned too,
    --    not just its current effect.
    if (select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'settle_run_tx' order by p.oid desc limit 1)
       not like '%status = ''active''%'
      then v_bad := v_bad || ' settle_run_tx가 active에서만 completed로 claim하지 않는다 (제외의 전제가 무너졌다)'; end if;

    -- ⓒ positive control on the sweep METHOD: the same regex must FIND `settle_run_tx` itself.
    --    Without this, a typo'd pattern matches nothing, ⓐ counts zero, and the pin passes
    --    vacuously forever — which is how a tripwire becomes decoration.
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = 'settle_run_tx'
                      and p.prosrc ~* 'update\s+bookings\s+set\s+status\s*=\s*''completed''')
      then v_bad := v_bad || ' 양성 대조 실패: 패턴이 settle_run_tx조차 못 찾는다 (ⓐ가 공허하게 통과한다)'; end if;

    if v_bad = ''
      then call _pass('usr','U6 제외의 전제 — completed는 정산을 함의한다. 카탈로그 전역에서 settle_run_tx 말고는 어떤 루틴도 예약을 completed로 옮기지 않고(다섯 번째 writer가 생기면 0097이 조용해진다), settle_run_tx는 여전히 active에서만 원자적으로 claim한다 (패턴 양성 대조 포함). ⚠ 행 수준 불변식은 여기서 잡을 수 없다 — 스위트들이 픽스처로 completed를 직접 만든다. 그 데이터는 프로덕션에서 측정한다');
    else v_msg := v_bad; call _fail('usr','U6 제외의 전제', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('usr','U6 제외의 전제', v_msg);
  end;
end $$;
