-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 152 — 0117 late-booking protocol stage 2: the clock, the resolver, fault, the 0066 carve-out
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract under test: docs/plans/2026-08-21-late-booking-protocol.md §12, under Sean's
-- D1–D5 rulings and the two product numbers (grace 30 min / ceiling 3 h — 2026-08-21,
-- verbatim). House law observed throughout: pins written BOTH ways; fixtures and every write
-- that more than one pin depends on live at TOP LEVEL, outside every exception block (151's
-- recorded lesson); times are now()-relative (100_wave3 header law); expected money values
-- are LITERALS against t_av_booking's fixed total_price 24900 (105's law) — 50% → 12450.
-- No suite runs after this one; fixtures leak nowhere.
--
-- The knobs stay at their PRODUCTION literals for every pin except where injection is itself
-- the thing being tested (L0) or the ceiling must move under an already-open check-in (L10) —
-- expiry is produced by AGING deadline_at directly (a version-stepped update the guard
-- trigger permits on an unresolved row), never by shrinking the knobs under every pin, so
-- the suite exercises the same arithmetic production runs.
--
-- ─── MUTATION MAP — MEASURED 2026-08-21, not predicted. Method: each mutation applied alone
--     to an otherwise-intact tree, FULL harness re-run, file restored via `git checkout`.
--     Green baseline for every run: 752/0. M5 and M9 were re-measured after a fixture
--     restructure (three single-consumer fixture actions moved inside their pins, b15's open
--     guarded — no assertion changed); their FIRST runs aborted the whole suite at a
--     top-level fixture line, which is itself recorded below because it is the failure mode
--     the restructure exists to prevent. All other mutations were measured against the
--     pre-restructure suite, whose success-path world is byte-identical. ──────────────────
--   M1 sweep arms ⓑⓒ lose `club_session_id is null` + open_checkin loses its
--      club_out_of_scope belt (one doctrine: club excluded)      → 751/1 RED=[L1] (클럽 예약 개시)
--   M2 marketplace_cancel_fee: en-route arm back to unconditional
--      `round(b.total_price * 0.5)` (waiver consult deleted)     → 750/2 RED=[L3, L9b]
--   M3 waiver loses the booking_faults EXISTS arm                → 751/1 RED=[L3]
--   M4 waiver loses the past-ceiling EXISTS arm                  → 751/1 RED=[L9b]
--      (M3/M4 red DISJOINT pins — the two arms are separately load-bearing)
--   M5 resolver custody split collapsed (terminal always
--      'no_show')                                                → 750/2 RED=[L12, L12c]
--      L12 arrives as `invalid booking transition: picked_up -> no_show` — 0066 §1's trigger
--      is the belt the pin predicted; L12c shows the isolated sweep arm leaving the row
--      untouched (status=picked_up, resolution=null). First run: suite ABORT at b12's
--      then-top-level answer — why that answer now lives inside the pin.
--   M6 answer_checkin loses the 'proceeding' past-ceiling gate   → 751/1 RED=[L10] (answer_immutable —
--      the wrongly-accepted proceeding then collides with the terminal statement)
--   M7 guard trigger never attached                              → 750/2 RED=[L7, L13]
--      L13 is honest collateral: with the trigger gone L7's retraction un-resolves b2, and
--      L13's re-resolve then moves what should have been immovable. Two pins, one corrupted
--      world, both name it.
--   M8 resolver loses BOTH already-resolved belts (early return
--      + CAS predicates)                                         → 751/1 RED=[L13] (checkin_resolution_immutable
--      — the trigger, belt #4, catches the CAS-less overwrite exactly as designed)
--   M9 late_ceiling() literal '3 hours' → '1 hour'               → 746/6 RED=[L0, L1, L6a, L10, L15, L18]
--      the knob is load-bearing in six independent places (literal pin, open bound, renewal
--      bound, the open refusal, b15's guarded world, the fetch surface) — the point of
--      naming it once. First run: suite ABORT at b10's then-top-level open.
--   M10 renewal loses its bound (`least(…)` → now()+grace)       → 751/1 RED=[L15] (갱신 마감 arm)
--   M11 open_checkin loses its bound (same edit)                 → 751/1 RED=[L15] (개시 마감 arm)
--      (M10/M11 share the pin; the detail string names which arm — distinct evidence)
--   M14 fault follows the TERMINAL instead of the statement
--      (the D5 inversion)                                        → 748/4 RED=[L5, L6, L9, L12c]
--      every no-fault arm reddens at once: silence, the expired proceedings, the ceiling and
--      the post-custody dark case all refuse a fault row nobody stated.
--   M15 no-row fetch answer reverted to the bare {open:false}
--      (coordinator amendment, 2026-08-21; green then 753/0)     → 752/1 RED=[L19] alone
--   Race-file mutations (measured with the same method, recorded in 90_race_check.sh):
--      confirm_return_tx head FOR UPDATE deleted → 752/0 GREEN (the control that corrected
--      RF's belt attribution) · _settle_sealed_run completed-idempotence arm deleted →
--      751/1 RED=[119 R9] (that arm belongs to the sequential pin, not the race).
--   Absence-of-money pins (L9's no-payments/no-ledger/no-cancel_fee arms) have no deletable
--   fix line — the fix IS that no charging code exists (0068's law); M14 proves the sibling
--   no-fault arms are not vacuous, and 105/121's positive controls prove the money writers
--   still fire where they should.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

do $$
declare
  oo uuid; rr uuid; oz uuid; hh uuid; dg uuid; rt uuid;
  v_club uuid; v_s uuid;
  b_arm uuid; b_in uuid; b_club uuid; b_picked uuid; b17 uuid; b_4h uuid;
  b_fresh uuid; b3 uuid; b2 uuid; b5 uuid; b6 uuid;
  b12 uuid; b12b uuid; b12c uuid; b10 uuid; b15 uuid; b19 uuid;
  v_bad text := ''; v_js jsonb; v_fee int; v_fee2 int; v_fee3 int; v_fee4 int; v_status text;
  v_n int; v_ver int; v_ts timestamptz; v_dl timestamptz; v_res text; v_st text;
  v_note text := '';
begin
  -- ─────────────────────────────── shared seed (top level) ───────────────────────────────
  oo := t_user('lb_oo', 'owner');  rr := t_user('lb_rr', 'runner');
  oz := t_user('lb_oz', 'owner');  hh := t_user('lb_hh', 'runner');
  dg := t_dog(oo, '지연견');       rt := t_route('지연 코스');

  -- a minimal club world for the exclusion pin — one host, one session, one direct booking
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('지연동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '지연 집결지', rt, 8, 'mixed');
  perform set_config('request.jwt.claim.sub', '', false);

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L0] the knobs: production literals ARE the ruling, and the harness can inject
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if late_grace()   is distinct from interval '30 minutes' then v_bad := v_bad || ' grace=' || late_grace(); end if;
    if late_ceiling() is distinct from interval '3 hours'    then v_bad := v_bad || ' ceiling=' || late_ceiling(); end if;
    perform set_config('app.late_grace', '7 minutes', true);
    if late_grace() is distinct from interval '7 minutes' then v_bad := v_bad || ' 주입 무시됨'; end if;
    perform set_config('app.late_grace', '', true);
    if late_grace() is distinct from interval '30 minutes' then v_bad := v_bad || ' 주입 해제 실패'; end if;
    if v_bad = '' then
      call _pass('lb', 'L0 그레이스 30분·실링 3시간 리터럴 (Sean 2026-08-21 원문) + GUC 주입은 하네스만');
    else call _fail('lb', 'L0 그레이스/실링 리터럴', v_bad); end if;
  exception when others then call _fail('lb', 'L0 그레이스/실링 리터럴', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L3] the carve-out's FAULT arm — a recorded runner fault waives the 50%; an owner
  --      fault does not touch it (D4: the fee follows WHOSE failure it was)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- top-level actions, pin compares. b3 is a live future en-route booking — the control
  -- proves 0066's 50% still stands where no fault and no rot exist (105 E2's twin).
  b3 := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'runner_enroute');
  select f.fee into v_fee from marketplace_cancel_fee(b3) f;                    -- control: 12450
  insert into booking_faults (booking_id, party, source, stated_by)
  values (b3, 'runner', 'test_ops_statement', rr);
  select f.fee into v_fee2 from marketplace_cancel_fee(b3) f;                   -- waived: 0
  delete from booking_faults where booking_id = b3;
  insert into booking_faults (booking_id, party, source, stated_by)
  values (b3, 'owner', 'test_ops_statement', oo);
  select f.fee into v_fee3 from marketplace_cancel_fee(b3) f;                   -- owner fault: 12450
  delete from booking_faults where booking_id = b3;
  begin
    v_bad := '';
    if v_fee  is distinct from 12450 then v_bad := v_bad || ' 무과실 통제=' || coalesce(v_fee::text, 'null'); end if;
    if v_fee2 is distinct from 0     then v_bad := v_bad || ' 러너 과실 미면제=' || coalesce(v_fee2::text, 'null'); end if;
    if v_fee3 is distinct from 12450 then v_bad := v_bad || ' 보호자 과실이 면제됨=' || coalesce(v_fee3::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L3 인루트 50% 면제 — 기록된 러너 과실이면 0, 무과실·보호자 과실이면 12450 유지 (D4/FM7)');
    else call _fail('lb', 'L3 인루트 50% 러너-과실 면제', v_bad); end if;
  exception when others then call _fail('lb', 'L3 인루트 50% 러너-과실 면제', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L9b] the carve-out's CEILING arm — the 2026-08-04 row's exit, BEFORE any sweep runs
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b17 is Sean's live row's exact shape: runner_enroute, 17 days stale, born before the
  -- protocol (no check-in row, no fault row). The quote must be 0 on scheduled_at alone —
  -- the honest fallback needs no protocol state. The fresh twin proves the arm still prices
  -- a live departure at 50%.
  b17    := t_av_booking(oo, dg, rt, rr, now() - interval '17 days', 5.0, 'runner_enroute');
  b_fresh := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, 'runner_enroute');
  begin
    v_bad := '';
    select f.fee, f.status into v_fee, v_status from marketplace_cancel_fee(b17) f;
    if v_fee is distinct from 0 then v_bad := v_bad || ' 17일 묵은 행 fee=' || coalesce(v_fee::text, 'null'); end if;
    if v_status is distinct from 'runner_enroute' then v_bad := v_bad || ' status=' || coalesce(v_status, 'null'); end if;
    select f.fee into v_fee2 from marketplace_cancel_fee(b_fresh) f;
    if v_fee2 is distinct from 12450 then v_bad := v_bad || ' 생생한 인루트 fee=' || coalesce(v_fee2::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L9b 실링 경과 인루트 취소 = 0원 (8/4 행의 출구 — 프로토콜 이전 예약도 scheduled_at만으로) · 정상 인루트는 12450 유지');
    else call _fail('lb', 'L9b 실링 면제 + 생생한 인루트 보존', v_bad); end if;
  exception when others then call _fail('lb', 'L9b 실링 면제 + 생생한 인루트 보존', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- arming world + sweep #1 (top level — L1 and L9 both read its effects)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b_arm    := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  b_in     := t_av_booking(oo, dg, rt, rr, now() - interval '10 minutes', 5.0, 'confirmed');
  b_picked := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'picked_up');
  b_4h     := t_av_booking(oo, dg, rt, rr, now() - interval '4 hours',    5.0, 'confirmed');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values (oo, dg, rr, rt, 'confirmed', now() - interval '40 minutes', 5.0,
          9900, 15000, 0, 24900, 9900, v_s)
  returning id into b_club;

  perform late_booking_sweep();

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L1] arming — past grace opens, inside grace / club / post-custody never do
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select bc.deadline_at, bc.version into v_dl, v_ver
      from booking_checkins bc where bc.booking_id = b_arm;
    if v_dl is null then v_bad := v_bad || ' 40분 지연 미개시';
    else
      if v_dl is distinct from now() + interval '30 minutes' then v_bad := v_bad || ' 마감 산식=' || v_dl; end if;
      if v_dl > late_ceiling_at(now() - interval '40 minutes') then v_bad := v_bad || ' 마감이 실링 초과'; end if;
      if v_ver is distinct from 0 then v_bad := v_bad || ' version=' || v_ver; end if;
    end if;
    if exists (select 1 from booking_checkins where booking_id = b_in)     then v_bad := v_bad || ' 그레이스 내 개시'; end if;
    if exists (select 1 from booking_checkins where booking_id = b_club)   then v_bad := v_bad || ' 클럽 예약 개시'; end if;
    if exists (select 1 from booking_checkins where booking_id = b_picked) then v_bad := v_bad || ' 인계 후 개시'; end if;
    select count(*) into v_n from notifications
     where ref_id = b_arm and title = '예약 시간이 지났어요' and profile_id in (oo, rr);
    if v_n is distinct from 2 then v_bad := v_bad || ' 양측 알림=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L1 그레이스 30분 경과에만 체크인 개시 (경계 마감 = min(now+grace, 실링)) · 그레이스 내·클럽·인계 후는 절대 아님 · 양측 알림 1회');
    else call _fail('lb', 'L1 체크인 개시 조건', v_bad); end if;
  exception when others then call _fail('lb', 'L1 체크인 개시 조건', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L9] the ceiling self-resolution — a STATUS and a record, never money, never fault
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0068's law, pinned: the same sweep that armed b_arm resolved b17 (no protocol row — one
  -- was created to carry the record) and b_4h (confirmed, 4h stale) to no_show, and wrote
  -- NOTHING money-shaped and NOTHING fault-shaped anywhere.
  begin
    v_bad := '';
    select b.status::text, b.cancel_fee into v_st, v_n from bookings b where b.id = b17;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' b17 status=' || v_st; end if;
    if v_n is not null then v_bad := v_bad || ' b17 cancel_fee=' || v_n; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b17;
    if v_res is distinct from 'ceiling' then v_bad := v_bad || ' b17 resolution=' || coalesce(v_res, '행 없음'); end if;
    select b.status::text into v_st from bookings b where b.id = b_4h;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' b_4h status=' || v_st; end if;
    if exists (select 1 from booking_faults where booking_id in (b17, b_4h)) then v_bad := v_bad || ' 과실 기록됨'; end if;
    select count(*) into v_n from payments where booking_id in (b17, b_4h);
    if v_n is distinct from 0 then v_bad := v_bad || ' payments=' || v_n; end if;
    select count(*) into v_n from ledger_items where booking_id in (b17, b_4h);
    if v_n is distinct from 0 then v_bad := v_bad || ' ledger=' || v_n; end if;
    select count(*) into v_n from notifications where ref_id = b17 and title = '지연 예약이 정리됐어요';
    if v_n is distinct from 2 then v_bad := v_bad || ' b17 알림=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L9 실링 자기해소 = 상태 + 기록뿐 — 수수료도 청구도 원장도 과실도 없다 (0068의 법; 8/4 행 형상 포함)');
    else call _fail('lb', 'L9 실링 자기해소 무과금', v_bad); end if;
  exception when others then call _fail('lb', 'L9 실링 자기해소 무과금', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b2: the cannot_proceed path (top-level actions; L2/L7/L13 read)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b2 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b2);

  -- [L8] party gates, before the real answer lands
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oz::text, false);
    begin
      perform answer_checkin(b2, 'owner', 'proceeding');
      v_bad := v_bad || ' 무관자가 보호자 응답';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 무관자 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform answer_checkin(b2, 'owner', 'proceeding');
      v_bad := v_bad || ' 러너가 보호자 측 응답';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 교차 측 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform answer_checkin(b2, 'owner', 'maybe_later');
      v_bad := v_bad || ' 임의 답변 수락';
    exception when others then
      if sqlerrm <> 'bad_answer' then v_bad := v_bad || ' 답변 검증 사유=' || sqlerrm; end if;
    end;
    begin
      perform answer_checkin(b2, 'ops', 'proceeding');
      v_bad := v_bad || ' 임의 측 수락';
    exception when others then
      if sqlerrm <> 'bad_side' then v_bad := v_bad || ' 측 검증 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then
      call _pass('lb', 'L8 응답 게이트 — 무관자·교차 측 not_party, 어휘 밖 답변 bad_answer, 측 검증 bad_side');
    else call _fail('lb', 'L8 응답 게이트', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L8 응답 게이트', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_js := answer_checkin(b2, 'owner', 'cannot_proceed');
  perform set_config('request.jwt.claim.sub', '', false);

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L2] a side's own cannot_proceed = immediate terminal + THEIR fault + no money (D4/D5)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select b.status::text, b.cancel_fee into v_st, v_n from bookings b where b.id = b2;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' status=' || v_st; end if;
    if v_n is not null then v_bad := v_bad || ' cancel_fee=' || v_n; end if;
    select bc.resolution, bc.version, bc.owner_at into v_res, v_ver, v_ts
      from booking_checkins bc where bc.booking_id = b2;
    if v_res is distinct from 'cannot_proceed' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if v_ver is distinct from 2 then v_bad := v_bad || ' version=' || v_ver; end if;
    if v_ts is distinct from now() then v_bad := v_bad || ' owner_at≠서버 now()'; end if;
    select count(*) into v_n from booking_faults
     where booking_id = b2 and party = 'owner' and stated_by = oo and source = 'checkin_cannot_proceed';
    if v_n is distinct from 1 then v_bad := v_bad || ' 보호자 과실행=' || v_n; end if;
    select count(*) into v_n from booking_faults where booking_id = b2;
    if v_n is distinct from 1 then v_bad := v_bad || ' 과실행 총=' || v_n; end if;
    select count(*) into v_n from notifications where ref_id = b2 and title = '지연 예약이 정리됐어요';
    if v_n is distinct from 2 then v_bad := v_bad || ' 알림=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L2 cannot_proceed = 본인 진술 즉시 종결 — no_show + 진술한 측의 과실행 1개(stated_by=본인) + 서버 타임스탬프 + 돈은 무이동');
    else call _fail('lb', 'L2 cannot_proceed 즉시 종결', v_bad); end if;
  exception when others then call _fail('lb', 'L2 cannot_proceed 즉시 종결', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L7] immutability — replay idempotent, retraction refused, the trigger is a real belt
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select bc.owner_at, bc.version into v_ts, v_ver from booking_checkins bc where bc.booking_id = b2;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := answer_checkin(b2, 'owner', 'cannot_proceed');            -- replay: same side, same answer
    perform set_config('request.jwt.claim.sub', '', false);
    if (select bc.owner_at from booking_checkins bc where bc.booking_id = b2) is distinct from v_ts
      then v_bad := v_bad || ' 재전송이 타임스탬프를 움직임'; end if;
    if (select bc.version from booking_checkins bc where bc.booking_id = b2) is distinct from v_ver
      then v_bad := v_bad || ' 재전송이 version을 움직임'; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform answer_checkin(b2, 'runner', 'proceeding');             -- late response vs resolution (FM8)
      v_bad := v_bad || ' 종결 후 응답 수락';
    exception when others then
      if sqlerrm <> 'checkin_resolved' then v_bad := v_bad || ' 종결 후 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      update booking_checkins set owner_answer = 'proceeding', version = version + 1 where booking_id = b2;
      v_bad := v_bad || ' 답변 철회가 통과';
    exception when others then
      if sqlerrm <> 'checkin_answer_immutable' then v_bad := v_bad || ' 철회 사유=' || sqlerrm; end if;
    end;
    begin
      update booking_checkins set resolved_at = null, resolution = null, version = version + 1 where booking_id = b2;
      v_bad := v_bad || ' 종결 해제가 통과';
    exception when others then
      if sqlerrm <> 'checkin_resolution_immutable' then v_bad := v_bad || ' 종결 해제 사유=' || sqlerrm; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L7 불변성 — 같은 답 재전송은 무변화 멱등, 종결 후 응답은 checkin_resolved, 직접 UPDATE 철회·재종결은 트리거가 거부 (postgres여도)');
    else call _fail('lb', 'L7 불변성', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L7 불변성', sqlerrm);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L13] already-resolved back-off — the CAS's single-connection face
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select bc.version into v_ver from booking_checkins bc where bc.booking_id = b2;
    select count(*) into v_n from notifications where ref_id = b2 and title = '지연 예약이 정리됐어요';
    perform _resolve_checkin(b2, 'deadline');                          -- must back off silently
    if (select bc.version from booking_checkins bc where bc.booking_id = b2) is distinct from v_ver
      then v_bad := v_bad || ' 재해소가 version을 움직임'; end if;
    if (select bc.resolution from booking_checkins bc where bc.booking_id = b2) is distinct from 'cannot_proceed'
      then v_bad := v_bad || ' resolution 변경'; end if;
    if (select count(*) from booking_faults where booking_id = b2) is distinct from 1
      then v_bad := v_bad || ' 과실행 증식'; end if;
    if (select count(*) from notifications where ref_id = b2 and title = '지연 예약이 정리됐어요') is distinct from v_n
      then v_bad := v_bad || ' 알림 증식'; end if;
    if v_bad = '' then
      call _pass('lb', 'L13 종결 후 재해소는 무소음 후퇴 — version·resolution·과실·알림 전부 그대로 (CAS 단일 커넥션 면)');
    else call _fail('lb', 'L13 재해소 후퇴', v_bad); end if;
  exception when others then call _fail('lb', 'L13 재해소 후퇴', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b5: accusation + silence (top-level actions; L5 reads)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b5 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b5);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_js := answer_checkin(b5, 'owner', 'other_side_absent');
  perform set_config('request.jwt.claim.sub', '', false);
  -- the accusation must NOT resolve early — the silent side keeps the whole window (D5)
  select bc.resolved_at into v_ts from booking_checkins bc where bc.booking_id = b5;
  update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
   where booking_id = b5;                                              -- age it (guard permits: unresolved + stepped)
  perform late_booking_sweep();

  begin
    v_bad := '';
    if v_ts is not null then v_bad := v_bad || ' 고발이 조기 종결시킴'; end if;
    select b.status::text, b.cancel_fee into v_st, v_n from bookings b where b.id = b5;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' status=' || v_st; end if;
    if v_n is not null then v_bad := v_bad || ' cancel_fee=' || v_n; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b5;
    if v_res is distinct from 'void' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if exists (select 1 from booking_faults where booking_id = b5) then v_bad := v_bad || ' 침묵에 과실이 적힘'; end if;
    if v_bad = '' then
      call _pass('lb', 'L5 고발+침묵 = void — 마감까지 기다리고, 종결은 무수수료·무과실 (§12 행3 그대로: 고발은 증거가 아니다, D5)');
    else call _fail('lb', 'L5 고발+침묵 void', v_bad); end if;
  exception when others then call _fail('lb', 'L5 고발+침묵 void', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b6: both proceed, then nothing starts (FM3 — top-level actions; L6 reads)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b6 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b6);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_js := answer_checkin(b6, 'owner', 'proceeding');
  perform set_config('request.jwt.claim.sub', rr::text, false);
  v_js := answer_checkin(b6, 'runner', 'proceeding');
  perform set_config('request.jwt.claim.sub', '', false);

  begin
    v_bad := '';
    select bc.resolved_at, bc.version, bc.deadline_at into v_ts, v_ver, v_dl
      from booking_checkins bc where bc.booking_id = b6;
    if v_ts is not null then v_bad := v_bad || ' 양측 진행이 종결시킴'; end if;
    if v_ver is distinct from 3 then v_bad := v_bad || ' version=' || v_ver || ' (개시0+답2+갱신1=3 기대)'; end if;
    if v_dl is distinct from now() + interval '30 minutes' then v_bad := v_bad || ' 갱신 마감=' || v_dl; end if;
    if (select b.status::text from bookings b where b.id = b6) is distinct from 'confirmed'
      then v_bad := v_bad || ' 상태가 움직임'; end if;
    if v_bad = '' then
      call _pass('lb', 'L6a 양측 진행 = 유한 마감 갱신, 종결 아님 (§12 행1) — 부킹 상태 무이동');
    else call _fail('lb', 'L6a 양측 진행 갱신', v_bad); end if;
  exception when others then call _fail('lb', 'L6a 양측 진행 갱신', sqlerrm); end;

  update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
   where booking_id = b6;                                              -- ...and then both vanish
  perform late_booking_sweep();

  begin
    v_bad := '';
    select b.status::text into v_st from bookings b where b.id = b6;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' status=' || v_st; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b6;
    if v_res is distinct from 'void' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if exists (select 1 from booking_faults where booking_id = b6) then v_bad := v_bad || ' 과실이 적힘'; end if;
    if v_bad = '' then
      call _pass('lb', 'L6 FM3 제2 감시선 — 진행 확답 뒤 아무 일도 없으면 갱신 마감에서 void (무수수료·무과실; 스위프는 절대 갱신하지 않는다)');
    else call _fail('lb', 'L6 FM3 제2 감시선', v_bad); end if;
  exception when others then call _fail('lb', 'L6 FM3 제2 감시선', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b12 / b12c / b12b: the custody split (D3) and supersession (FM8)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b12 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b12);
  update bookings set status = 'picked_up' where id = b12;             -- custody advanced mid-protocol

  begin
    v_bad := '';
    -- the answer lives INSIDE the pin on purpose: b12 feeds no other pin, and a resolver
    -- mutation that raises here (the first M5 run aborted the whole suite at this line as
    -- `invalid booking transition: picked_up -> no_show`) must become THIS pin's named red,
    -- not a suite-wide blackout. 151's top-level law covers shared state only.
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := answer_checkin(b12, 'owner', 'cannot_proceed');
    perform set_config('request.jwt.claim.sub', '', false);
    select b.status::text into v_st from bookings b where b.id = b12;
    if v_st is distinct from 'incident_review' then v_bad := v_bad || ' status=' || v_st || ' (no_show는 인계 후 불법 — D3)'; end if;
    select count(*) into v_n from booking_faults where booking_id = b12 and party = 'owner';
    if v_n is distinct from 1 then v_bad := v_bad || ' 진술 측 과실행=' || v_n; end if;
    select count(*) into v_n from notifications
     where ref_id = b12 and title = '확인이 필요해요' and kind = 'safety';
    if v_n is distinct from 2 then v_bad := v_bad || ' 안전 알림=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L12 인계 후 cannot_proceed → incident_review (락 아래서 재독한 커스터디가 종단을 고른다, FM6/D3) + 진술 측 과실 + 안전 알림');
    else call _fail('lb', 'L12 인계 후 커스터디 분기', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L12 인계 후 커스터디 분기', sqlerrm);
  end;

  b12c := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b12c);
  update bookings set status = 'picked_up' where id = b12c;
  update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
   where booking_id = b12c;
  perform late_booking_sweep();

  begin
    v_bad := '';
    select b.status::text into v_st from bookings b where b.id = b12c;
    if v_st is distinct from 'incident_review' then v_bad := v_bad || ' status=' || v_st; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b12c;
    if v_res is distinct from 'void' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if exists (select 1 from booking_faults where booking_id = b12c) then v_bad := v_bad || ' 침묵에 과실'; end if;
    if v_bad = '' then
      call _pass('lb', 'L12c 인계 후 양측 침묵 = incident_review·무과실 (개는 넘어갔는데 프로토콜이 어두워졌다 — §12 행3/4 post 칸, D1)');
    else call _fail('lb', 'L12c 인계 후 침묵', v_bad); end if;
  exception when others then call _fail('lb', 'L12c 인계 후 침묵', sqlerrm); end;

  b12b := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b12b);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_js := answer_checkin(b12b, 'owner', 'other_side_absent');
  perform set_config('request.jwt.claim.sub', '', false);
  update bookings set status = 'cancelled_owner', cancel_fee = 0 where id = b12b;   -- another path owned it
  update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
   where booking_id = b12b;
  perform late_booking_sweep();

  begin
    v_bad := '';
    select b.status::text into v_st from bookings b where b.id = b12b;
    if v_st is distinct from 'cancelled_owner' then v_bad := v_bad || ' 종단을 덮어씀=' || v_st; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b12b;
    if v_res is distinct from 'superseded' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if exists (select 1 from booking_faults where booking_id = b12b) then v_bad := v_bad || ' 과실'; end if;
    if exists (select 1 from notifications where ref_id = b12b and title = '지연 예약이 정리됐어요')
      then v_bad := v_bad || ' 이중 알림'; end if;
    if v_bad = '' then
      call _pass('lb', 'L12b 동시 취소가 이긴 체크인 = superseded — 상태·돈·과실·알림 무접촉 (제안된 행동은 체크인과 함께 만료, FM8)');
    else call _fail('lb', 'L12b superseded', v_bad); end if;
  exception when others then call _fail('lb', 'L12b superseded', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b10: past the ceiling the protocol offers only terminals (§4.3 / FM4)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b10 := t_av_booking(oo, dg, rt, rr, now() - interval '2 hours 50 minutes', 5.0, 'confirmed');
  begin
    v_bad := '';
    -- open under the DEFAULT ceiling, inside the pin (b10 feeds no other pin): a knob
    -- mutation that makes this open refuse (M9's first run aborted the suite here) reds
    -- this pin by name instead of killing the report.
    perform open_checkin(b10);
    perform set_config('app.late_ceiling', '2 hours', true);           -- then the clock crosses it
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform answer_checkin(b10, 'owner', 'proceeding');
      v_bad := v_bad || ' 실링 뒤 진행이 수락됨';
    exception when others then
      if sqlerrm <> 'checkin_past_ceiling' then v_bad := v_bad || ' 진행 거부 사유=' || sqlerrm; end if;
    end;
    v_js := fetch_checkin(b10);
    if (v_js->>'past_ceiling')::boolean is distinct from true then v_bad := v_bad || ' past_ceiling 미표시'; end if;
    v_js := answer_checkin(b10, 'owner', 'cannot_proceed');            -- terminals stay open
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.status::text from bookings b where b.id = b10) is distinct from 'no_show'
      then v_bad := v_bad || ' 종단 진술이 막힘'; end if;
    if v_bad = '' then
      call _pass('lb', 'L10 실링 뒤엔 종단만 — 두 번의 탭이 17일 예약을 살릴 수 없다 (proceeding 거부·past_ceiling 표면 전달·cannot_proceed는 수락, FM4/§4.3)');
    else call _fail('lb', 'L10 실링 뒤 진행 거부', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L10 실링 뒤 진행 거부', sqlerrm);
  end;
  perform set_config('app.late_ceiling', '', true);                    -- restore the ruling

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b15: the deadline is BOUNDED by the ceiling, at open and at renewal
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- b15 is read by BOTH L15 and L18, so its world is built at top level (151's law) but the
  -- open is GUARDED: a knob mutation that makes it refuse must red the two consumers by name
  -- rather than abort the suite before the report prints (M9's first measured run did exactly
  -- that, one fixture earlier).
  b15 := t_av_booking(oo, dg, rt, rr, now() - interval '2 hours 50 minutes', 5.0, 'confirmed');
  begin
    perform open_checkin(b15);
  exception when others then v_note := ' b15 개시 실패=' || sqlerrm;
  end;
  begin
    v_bad := v_note;
    select bc.deadline_at into v_dl from booking_checkins bc where bc.booking_id = b15;
    if v_dl is distinct from late_ceiling_at(now() - interval '2 hours 50 minutes')
      then v_bad := v_bad || ' 개시 마감=' || coalesce(v_dl::text, '행 없음') || ' (실링=now+10m 기대)'; end if;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := answer_checkin(b15, 'owner', 'proceeding');
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := answer_checkin(b15, 'runner', 'proceeding');
    perform set_config('request.jwt.claim.sub', '', false);
    select bc.deadline_at, bc.resolved_at into v_dl, v_ts from booking_checkins bc where bc.booking_id = b15;
    if v_dl is distinct from late_ceiling_at(now() - interval '2 hours 50 minutes')
      then v_bad := v_bad || ' 갱신 마감=' || coalesce(v_dl::text, '행 없음') || ' (30분이 아니라 실링에 캡)'; end if;
    if v_ts is not null then v_bad := v_bad || ' 갱신이 종결시킴'; end if;
    if v_bad = '' then
      call _pass('lb', 'L15 마감은 언제나 유계 — 개시도 갱신도 min(…, scheduled+실링)에 캡 (§12 BOUNDED, FM3/FM4의 산술적 반)');
    else call _fail('lb', 'L15 마감 유계', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L15 마감 유계', sqlerrm);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L18] fetch_checkin — the render read
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := fetch_checkin(b15);
    if (v_js->>'open')::boolean is distinct from true then v_bad := v_bad || ' open≠true'; end if;
    if v_js->>'custody' is distinct from 'pre' then v_bad := v_bad || ' custody=' || coalesce(v_js->>'custody', 'null'); end if;
    if (v_js->>'past_ceiling')::boolean is distinct from false then v_bad := v_bad || ' past_ceiling 오탐'; end if;
    if v_js->>'server_now' is null then v_bad := v_bad || ' server_now 없음'; end if;
    if v_js->>'owner_answer' is distinct from 'proceeding' then v_bad := v_bad || ' owner_answer=' || coalesce(v_js->>'owner_answer', 'null'); end if;
    v_js := fetch_checkin(b_fresh);                                    -- no protocol row yet
    if (v_js->>'open')::boolean is distinct from false then v_bad := v_bad || ' 무행 부킹 open≠false'; end if;
    perform set_config('request.jwt.claim.sub', oz::text, false);
    begin
      v_js := fetch_checkin(b15);
      v_bad := v_bad || ' 무관자 읽기 통과';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 무관자 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then
      call _pass('lb', 'L18 fetch_checkin — 당사자만, 개시 전 {open:false}, past_ceiling·server_now 동봉 (클라는 실링 상수도 자기 시계도 모른다)');
    else call _fail('lb', 'L18 fetch_checkin', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L18 fetch_checkin', sqlerrm);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L19] the NO-ROW answer still carries the derived trio (coordinator amendment 2026-08-21)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- No protocol row is the NORMAL state of every pre-protocol booking — the Aug-4 shape §9
  -- waives on scheduled_at alone. A bare {open:false} would strand the client fee-quote
  -- mirror without past_ceiling/server_now and force it back onto a client clock (FM2/FM6).
  -- b19 is created HERE, after the suite's last sweep, so it has no row by construction.
  b19 := t_av_booking(oo, dg, rt, rr, now() - interval '17 days', 5.0, 'runner_enroute');
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := fetch_checkin(b19);                                        -- 17일 묵은 무행 부킹
    if (v_js->>'open')::boolean is distinct from false then v_bad := v_bad || ' open≠false'; end if;
    if (v_js->>'past_ceiling')::boolean is distinct from true then v_bad := v_bad || ' 무행인데 past_ceiling 미표시'; end if;
    if v_js->>'custody' is distinct from 'pre' then v_bad := v_bad || ' custody=' || coalesce(v_js->>'custody', 'null'); end if;
    if v_js->>'server_now' is null then v_bad := v_bad || ' server_now 없음'; end if;
    v_js := fetch_checkin(b_fresh);                                    -- 젊은 무행 부킹 (양방향 쌍)
    if (v_js->>'past_ceiling')::boolean is distinct from false then v_bad := v_bad || ' 젊은 무행에 past_ceiling 오탐'; end if;
    if v_js->>'server_now' is null then v_bad := v_bad || ' 젊은 무행 server_now 없음'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then
      call _pass('lb', 'L19 무행 응답도 파생 3종 동봉 — 프로토콜 이전(8/4 형상) 부킹의 past_ceiling=true·젊은 부킹 false·custody·server_now (클라 시계 복귀 금지, FM2/FM6)');
    else call _fail('lb', 'L19 무행 파생 3종', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L19 무행 파생 3종', sqlerrm);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L14] the ACL/RLS catalog — who can execute what, and the tables are sealed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- anon: nowhere
    if has_function_privilege('anon', 'answer_checkin(uuid,text,text)', 'execute') then v_bad := v_bad || ' anon answer'; end if;
    if has_function_privilege('anon', 'fetch_checkin(uuid)', 'execute') then v_bad := v_bad || ' anon fetch'; end if;
    if has_function_privilege('anon', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' anon open'; end if;
    if has_function_privilege('anon', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' anon sweep'; end if;
    if has_function_privilege('anon', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' anon waived'; end if;
    if has_function_privilege('anon', 'marketplace_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' anon fee'; end if;
    -- authenticated: exactly the two party calls
    if not has_function_privilege('authenticated', 'answer_checkin(uuid,text,text)', 'execute') then v_bad := v_bad || ' auth¬answer'; end if;
    if not has_function_privilege('authenticated', 'fetch_checkin(uuid)', 'execute') then v_bad := v_bad || ' auth¬fetch'; end if;
    if has_function_privilege('authenticated', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' auth open'; end if;
    if has_function_privilege('authenticated', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' auth sweep'; end if;
    if has_function_privilege('authenticated', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' auth waived'; end if;
    if has_function_privilege('authenticated', '_resolve_checkin(uuid,text)', 'execute') then v_bad := v_bad || ' auth resolver'; end if;
    -- service_role: the fee path and the party calls, NEVER the clock
    if not has_function_privilege('service_role', 'marketplace_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' svc¬fee'; end if;
    if not has_function_privilege('service_role', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' svc¬waived'; end if;
    if has_function_privilege('service_role', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' svc open (제2의 시계)'; end if;
    if has_function_privilege('service_role', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' svc sweep'; end if;
    if has_function_privilege('service_role', '_resolve_checkin(uuid,text)', 'execute') then v_bad := v_bad || ' svc resolver'; end if;
    -- the tables: RLS on, zero policies (fail-closed seal, ops_flags' shape)
    if not (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'booking_checkins') then v_bad := v_bad || ' checkins RLS off'; end if;
    if not (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'booking_faults') then v_bad := v_bad || ' faults RLS off'; end if;
    select count(*) into v_n from pg_policies where tablename in ('booking_checkins', 'booking_faults');
    if v_n is distinct from 0 then v_bad := v_bad || ' 정책=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L14 표면 봉인 — anon 어디에도 없음·authenticated는 answer/fetch만·시계(open/sweep/resolver)는 service_role조차 없음·두 테이블 RLS on 정책 0');
    else call _fail('lb', 'L14 표면 봉인', v_bad); end if;
  exception when others then call _fail('lb', 'L14 표면 봉인', sqlerrm); end;
end $$;
