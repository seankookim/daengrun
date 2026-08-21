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
--   ─── the REASON amendment (Sean: "ask why they stopped."), green then 758/0 ──────────────
--   ⚠ [codex r2 F7] these five WERE measured when they were run, and this header omitted them
--   while the REGISTRY row claimed them — the map jumped M15 → M22. A ledger that overstates
--   its own measurements is the one defect class this fleet cannot tolerate, so they are
--   written back here from the run logs rather than quietly dropped from the registry.
--   M16 answer_checkin's reason gate deleted (a reason on any answer)
--                                                                 → 757/1 RED=[L21]
--        (the red arrives as the TABLE's 23514, which is the belt L24 owns — the gate and the
--         constraint are both real and the pin names which one answered)
--   M17 the resolver stops copying the reason onto the fault row  → 757/1 RED=[L20] (과실행 사유 미복사)
--   M18 the guard trigger loses its reason-immutability terms     → 757/1 RED=[L22]
--   M19 booking_faults loses its whole-row write-once guard       → 757/1 RED=[L23]
--   M20 the reason-only-with-cannot_proceed CHECKs dropped        → 757/1 RED=[L24]
--   M21 quote_cancel_fee inlines a faithful COPY of the ladder    → 760/1 RED=[L27] alone,
--        with L25 measured GREEN under the copy — the whole argument for a source-level pin
--        (and, after r2 F7, for L27's executed drop-and-break rather than a substring match)
--   ─── the codex FIX-FIRST round (L28–L36 + L9/L14/L30 extensions), measured on the rebased
--       tree (green 769/0; each mutation alone, full harness, per-run _t dumped in-task) ───
--   M22 quote_cancel_fee's no-oracle raise neutralized              → 768/1 RED=[L26]
--   M23 answer_checkin regains the server-caller exemption (the
--       pre-CRIT-7 shape)                                           → 768/1 RED=[L28] — the red's
--       detail shows the full fabrication: answer accepted, persisted, fault row born humanless
--   M24 _checkin_custody loses the stamps arm                       → 768/1 RED=[L29] (양도장 미승격=no_show)
--   M25 the sweep's late_protocol_live_since gate deleted           → 768/1 RED=[L30]
--   M26 the waiver's arrival-evidence conditions deleted            → 768/1 RED=[L31] (면제=0 — the
--       timer strips the runner's 0066 entitlement, exactly HIGH-4's sentence)
--   M27 answer_checkin's left-protocol state gate deleted           → 768/1 RED=[L32]
--   M28 the §9c fee-truth trigger never attaches                    → 768/1 RED=[L33] (both arms:
--       forged 99999 survives, the past-ceiling stale 12450 survives)
--   M29 the backfill grace margin deleted                           → 768/1 RED=[L34]
--   M29b the backfill cause token reverts to 'ceiling'              → 767/2 RED=[L9, L34] — the
--       token is owned by both readers of the record, coherently
--   M30 the two DELETE guards never attach                          → 768/1 RED=[L36]
--   M31 booking_faults.stated_by loses NOT NULL                     → 768/1 RED=[L35]
--   ⚠ Two earlier readings of this round (766/3, 767/2 with phantom [L30, L12b] reds carrying
--   two DIFFERENT frozen now() values inside one _t) were cluster-contention braids — two
--   harness runs racing one postmaster, the exact shared-machine class harness.sh's header
--   records. Every number above is from a run whose _t was dumped by the same task on an
--   uncontended cluster. The round's two REAL collaterals, both fixed before landing: 113 K7
--   (the fee trigger repriced a fee-less km fixture → trigger narrowed to fee-carrying
--   cancels) and 99 S1 (a definer trigger function → made invoker, enforce_booking_transition's
--   shape).
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
  b20 uuid; b21 uuid; b24 uuid; v_txt text;
  b28 uuid; b29 uuid; b29b uuid; b30 uuid; b31 uuid; b32 uuid; b33 uuid; b33b uuid;
  b34 uuid; b34b uuid; b35 uuid;
  b31b uuid; b31f uuid; b3f uuid; b3o uuid; b29c uuid; b29d uuid;
  b37 uuid; b37h uuid; b39 uuid; b39b uuid; b39c uuid; b39d uuid; b40 uuid;
  ow37 uuid; dg37 uuid; lot37 uuid; ow37h uuid; dg37h uuid; lot37h uuid;
  v_exp timestamptz; v_exp2 timestamptz; v_km numeric; v_share int;
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
  -- [L30] the clock ships OFF (codex CRIT-1) — flag null ⇒ the sweep is a no-op
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The client has zero answer/fetch call sites at deploy; an armed sweep would void
  -- bookings on prompts that never rendered (FM2). This pin runs BEFORE the suite arms the
  -- flag, against a booking the armed sweep would certainly open.
  b30 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  begin
    v_bad := '';
    v_n := late_booking_sweep();
    if v_n is distinct from 0 then v_bad := v_bad || ' 꺼진 시계가 ' || v_n || '건 처리'; end if;
    if exists (select 1 from booking_checkins where booking_id = b30) then
      select bc.opened_at::text || '/v' || bc.version || '/res=' || coalesce(bc.resolution, '무')
        into v_txt from booking_checkins bc where bc.booking_id = b30;
      v_bad := v_bad || ' 꺼진 시계가 개시 [' || v_txt || ' flag=' || coalesce((select late_protocol_live_since::text from ops_flags), '무') || ']';
    end if;
    if v_bad = '' then
      call _pass('lb', 'L30 시계는 꺼진 채 출하 — late_protocol_live_since null ⇒ 스위프 0건·개시 없음 (ui5 스테이지2 출하 때 Sean이 켠다, CRIT-1)');
    else call _fail('lb', 'L30 꺼진 시계', v_bad); end if;
  exception when others then call _fail('lb', 'L30 꺼진 시계', sqlerrm); end;

  -- arm the clock for the rest of the suite (restored to the shipped default at the end)
  update ops_flags set late_protocol_live_since = now() - interval '1 day', updated_at = now();

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L3] the carve-out's FAULT arm — a recorded runner fault waives the 50%; an owner
  --      fault does not touch it (D4: the fee follows WHOSE failure it was)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- top-level actions, pin compares. b3 is a live future en-route booking — the control
  -- proves 0066's 50% still stands where no fault and no rot exist (105 E2's twin).
  -- ⚠ ONE FIXTURE PER ARM, and it is not a style choice: after r2 F2 a fault row cannot be
  -- deleted (booking_faults is write-once, whole row, DELETE included), so an insert/delete
  -- cycle on a single booking is no longer expressible — nor should it be, since the thing
  -- under test is a record of a human statement.
  b3  := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'runner_enroute');
  b3f := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'runner_enroute');
  b3o := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'runner_enroute');
  insert into booking_faults (booking_id, party, source, stated_by)
  values (b3f, 'runner', 'test_ops_statement', rr),
         (b3o, 'owner',  'test_ops_statement', oo);
  select f.fee into v_fee  from marketplace_cancel_fee(b3)  f;                  -- control: 12450
  select f.fee into v_fee2 from marketplace_cancel_fee(b3f) f;                  -- waived: 0
  select f.fee into v_fee3 from marketplace_cancel_fee(b3o) f;                  -- owner fault: 12450
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
    if v_res is distinct from 'ceiling_backfill' then v_bad := v_bad || ' b17 resolution=' || coalesce(v_res, '행 없음'); end if;
    select b.status::text into v_st from bookings b where b.id = b_4h;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' b_4h status=' || v_st; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b_4h;
    if v_res is distinct from 'ceiling_backfill' then v_bad := v_bad || ' b_4h resolution=' || coalesce(v_res, '행 없음'); end if;
    if exists (select 1 from booking_faults where booking_id in (b17, b_4h)) then v_bad := v_bad || ' 과실 기록됨'; end if;
    select count(*) into v_n from payments where booking_id in (b17, b_4h);
    if v_n is distinct from 0 then v_bad := v_bad || ' payments=' || v_n; end if;
    select count(*) into v_n from ledger_items where booking_id in (b17, b_4h);
    if v_n is distinct from 0 then v_bad := v_bad || ' ledger=' || v_n; end if;
    select count(*) into v_n from notifications where ref_id = b17 and title = '지연 예약이 정리됐어요';
    if v_n is distinct from 2 then v_bad := v_bad || ' b17 알림=' || v_n; end if;
    -- [codex HIGH-2] 0075 §K fires on the no_show write; with no km hold (these fixtures,
    -- and everything pre-cutover) km_release nets 0 and writes NOTHING — the release is a
    -- hold-unwind (slot-holds class), argued in 0117 §5; release mechanics are 113's pins.
    select count(*) into v_n from km_ledger where booking_id in (b17, b_4h);
    if v_n is distinct from 0 then v_bad := v_bad || ' km_ledger=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L9 실링 자기해소 = 상태 + 기록뿐 — 수수료도 청구도 원장도 과실도 km행도 없다 (0068의 법; 8/4 행 형상은 ceiling_backfill로)');
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
      -- 두 거절이 모두 참인 자리다 (체크인은 종결됐고, 그 종결이 부킹도 옮겼다). 창을 닫은
      -- 것의 이름이 더 구체적이므로 checkin_resolved 가 이긴다 — not_late_eligible 은 남의
      -- 경로가 부킹을 가져갔는데 체크인은 아직 열려 있는 경우(L32)의 이름이다.
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
    if v_res is distinct from 'superseded' then
      v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null')
             || ' [dl=' || (select bc2.deadline_at::text from booking_checkins bc2 where bc2.booking_id = b12b)
             || ' v' || (select bc2.version from booking_checkins bc2 where bc2.booking_id = b12b)
             || ' flag=' || coalesce((select late_protocol_live_since::text from ops_flags), '무') || ']';
    end if;
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
  -- [L20]–[L24] the REASON amendment (Sean 2026-08-21, verbatim: "ask why they stopped.")
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- One copy of the rule under test: the reason is taken at ANSWER time in the same
  -- statement as the answer, immutable with it, and the resolver copies it onto the fault
  -- row — so an emergency abort is distinguishable from a flake when §4.2 fee arms are
  -- someday priced against fault rows.

  -- [L20] stored with the statement, copied to the fault, rendered to the parties;
  --       and the no-reason statement stays legal (nullable — the surface asks, never mandates)
  b20 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b20);
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := answer_checkin(b20, 'owner', 'cannot_proceed', '개가 산책 중 다쳤어요');
    if v_js->>'owner_reason' is distinct from '개가 산책 중 다쳤어요'
      then v_bad := v_bad || ' fetch에 사유 없음=' || coalesce(v_js->>'owner_reason', 'null'); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    select bc.owner_reason into v_txt from booking_checkins bc where bc.booking_id = b20;
    if v_txt is distinct from '개가 산책 중 다쳤어요' then v_bad := v_bad || ' 체크인 사유=' || coalesce(v_txt, 'null'); end if;
    select f.reason into v_txt from booking_faults f where f.booking_id = b20 and f.party = 'owner';
    if v_txt is distinct from '개가 산책 중 다쳤어요' then v_bad := v_bad || ' 과실행 사유 미복사=' || coalesce(v_txt, 'null'); end if;
    -- the pre-amendment statement (L2's b2) carries a NULL reason — asked, not mandated
    select f.reason into v_txt from booking_faults f where f.booking_id = b2 and f.party = 'owner';
    if v_txt is not null then v_bad := v_bad || ' 무사유 진술에 사유=' || v_txt; end if;
    if v_bad = '' then
      call _pass('lb', 'L20 사유는 진술과 함께 저장·과실행으로 복사·당사자에게 렌더 — 무사유 진술도 여전히 합법 (Sean: "ask why they stopped")');
    else call _fail('lb', 'L20 사유 저장·복사·렌더', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L20 사유 저장·복사·렌더', sqlerrm);
  end;

  -- [L21] a reason is REFUSED on any non-cannot_proceed answer (0114's free-text class)
  b21 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b21);
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform answer_checkin(b21, 'owner', 'proceeding', '자유 텍스트');
      v_bad := v_bad || ' proceeding에 사유 수락';
    exception when others then
      if sqlerrm <> 'reason_not_applicable' then v_bad := v_bad || ' proceeding 거부 사유=' || sqlerrm; end if;
    end;
    begin
      perform answer_checkin(b21, 'owner', 'other_side_absent', '자유 텍스트');
      v_bad := v_bad || ' 고발에 사유 수락';
    exception when others then
      if sqlerrm <> 'reason_not_applicable' then v_bad := v_bad || ' 고발 거부 사유=' || sqlerrm; end if;
    end;
    -- the refusal is about the REASON, not the answer: the same answer without one is taken
    v_js := answer_checkin(b21, 'owner', 'proceeding');
    perform set_config('request.jwt.claim.sub', '', false);
    if v_js->>'owner_answer' is distinct from 'proceeding' then v_bad := v_bad || ' 무사유 진행이 거부됨'; end if;
    if v_bad = '' then
      call _pass('lb', 'L21 사유는 cannot_proceed에만 — proceeding·고발엔 reason_not_applicable, 같은 답의 무사유는 수락 (행복 경로 자유텍스트 금지, 0114류)');
    else call _fail('lb', 'L21 사유 게이트', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L21 사유 게이트', sqlerrm);
  end;

  -- [L22] the check-in reason is immutable with its answer (guard trigger arm)
  begin
    v_bad := '';
    begin
      update booking_checkins set owner_reason = '나중에 고친 사유', version = version + 1
       where booking_id = b20;
      v_bad := v_bad || ' 사유 개서가 통과';
    exception when others then
      if sqlerrm <> 'checkin_answer_immutable' then v_bad := v_bad || ' 개서 거부 사유=' || sqlerrm; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L22 체크인 사유 불변 — 답과 한 몸으로 가드 트리거가 개서를 거부 (postgres여도)');
    else call _fail('lb', 'L22 체크인 사유 불변', v_bad); end if;
  exception when others then call _fail('lb', 'L22 체크인 사유 불변', sqlerrm); end;

  -- [L23] the fault row is write-once, whole row — a recorded statement is never edited
  begin
    v_bad := '';
    begin
      update booking_faults set reason = '수정된 진술' where booking_id = b20;
      v_bad := v_bad || ' 과실행 개서가 통과';
    exception when others then
      if sqlerrm <> 'fault_immutable' then v_bad := v_bad || ' 과실 개서 거부 사유=' || sqlerrm; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L23 과실행은 행 전체 write-once — 진술의 정정은 미래의 소스 있는 새 기록이지 편집이 아니다');
    else call _fail('lb', 'L23 과실행 불변', v_bad); end if;
  exception when others then call _fail('lb', 'L23 과실행 불변', sqlerrm); end;

  -- [L24] the table itself refuses a reason without its statement (belt under the §6 gate)
  b24 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  begin
    v_bad := '';
    begin
      insert into booking_checkins (booking_id, opened_at, deadline_at,
                                    owner_answer, owner_at, owner_reason)
      values (b24, now(), now() + interval '30 minutes',
              'proceeding', now(), '행복 경로의 자유 텍스트');
      v_bad := v_bad || ' 제약이 통과시킴';
    exception when others then
      if sqlstate <> '23514' then v_bad := v_bad || ' 제약 위반 코드=' || sqlstate || '/' || sqlerrm; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L24 테이블 제약 벨트 — cannot_proceed 아닌 답에 사유가 붙은 행은 23514로 거부 (게이트 아래 CHECK)');
    else call _fail('lb', 'L24 사유 제약 벨트', v_bad); end if;
  exception when others then call _fail('lb', 'L24 사유 제약 벨트', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L25]–[L27] the quote window (Sean 2026-08-21: "Real quote API + words meanwhile",
  --             reversing 0066:89's no-client-quote posture)
  -- ══════════════════════════════════════════════════════════════════════════════════════

  -- [L25] parties read THE number — quote == marketplace_cancel_fee on the same fixtures,
  --       including the waived stale-enroute row and the live-enroute 50% row, both sides
  begin
    v_bad := '';
    select f.fee into v_fee from marketplace_cancel_fee(b19) f;        -- the rule, direct
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := quote_cancel_fee(b19);                                     -- the window, as owner
    if (v_js->>'fee')::int is distinct from v_fee or v_fee is distinct from 0
      then v_bad := v_bad || ' 묵은 인루트 quote=' || coalesce(v_js->>'fee', 'null') || ' 직접=' || v_fee; end if;
    if v_js->>'status' is distinct from 'runner_enroute' then v_bad := v_bad || ' status=' || coalesce(v_js->>'status', 'null'); end if;
    select f.fee into v_fee from marketplace_cancel_fee(b_fresh) f;
    v_js := quote_cancel_fee(b_fresh);
    if (v_js->>'fee')::int is distinct from v_fee or v_fee is distinct from 12450
      then v_bad := v_bad || ' 생생 인루트 quote=' || coalesce(v_js->>'fee', 'null') || ' 직접=' || v_fee; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := quote_cancel_fee(b_fresh);                                 -- the runner reads the same number
    perform set_config('request.jwt.claim.sub', '', false);
    if (v_js->>'fee')::int is distinct from 12450 then v_bad := v_bad || ' 러너 측 quote=' || coalesce(v_js->>'fee', 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L25 견적 창 = 사다리와 같은 수 — 면제된 묵은 인루트 0·생생한 인루트 12450, 보호자·러너 동수 (구현은 하나, 창은 게이트)');
    else call _fail('lb', 'L25 견적 동수', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L25 견적 동수', sqlerrm);
  end;

  -- [L26] no enumeration oracle — a FOREIGN booking answers exactly like a MISSING one
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oz::text, false);
    begin
      v_js := quote_cancel_fee(b_fresh);                               -- someone else's booking
      v_bad := v_bad || ' 무관자 견적 통과';
    exception when others then
      if sqlerrm <> 'not_found' then v_bad := v_bad || ' 무관자 사유=' || sqlerrm || ' (not_party는 존재 오라클)'; end if;
    end;
    begin
      v_js := quote_cancel_fee(gen_random_uuid());                     -- a booking that isn't
      v_bad := v_bad || ' 무존재 견적 통과';
    exception when others then
      if sqlerrm <> 'not_found' then v_bad := v_bad || ' 무존재 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then
      call _pass('lb', 'L26 열거 오라클 없음 — 남의 예약과 없는 예약이 같은 not_found (유효 id 확인 채널 봉쇄)');
    else call _fail('lb', 'L26 무오라클', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L26 무오라클', sqlerrm);
  end;

  -- [L27] the one-copy law at SOURCE level (N8's precedent): a faithfully-copied ladder
  --       would pass L25 right up until the two copies drift — so the delegation itself is
  --       pinned: quote_cancel_fee's body must reference marketplace_cancel_fee.
  begin
    v_bad := '';
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'quote_cancel_fee'
       and p.prosrc like '%marketplace_cancel_fee%';
    if v_n is distinct from 1 then v_bad := v_bad || ' 위임 소스 미확인 (사다리 사본?)'; end if;
    -- [codex r2 F7] …and a SUBSTRING is not a call: a comment, or a dead reference beside a
    -- copied ladder, satisfies the check above. So the delegation is EXECUTED: drop the ladder
    -- inside an unwound subtransaction and require the quote to break. A copy would keep
    -- answering — which is exactly the drift this pin exists to forbid.
    v_txt := '';
    begin
      drop function marketplace_cancel_fee(uuid);
      begin
        v_js := quote_cancel_fee(b_fresh);
        v_txt := '사다리 없이도 견적이 나왔다 (사본)';
      exception when others then
        if sqlstate = '42883' then v_txt := 'ok'; else v_txt := '다른 실패=' || sqlstate; end if;
      end;
      raise exception 'unwind152';           -- roll the DROP back, always
    exception when others then
      if sqlerrm <> 'unwind152' then v_bad := v_bad || ' 언와인드 경로=' || sqlerrm; end if;
    end;
    if v_txt <> 'ok' then v_bad := v_bad || ' 실행 위임 미확인: ' || v_txt; end if;
    -- the ladder is back (the whole suite after this line depends on it)
    select f.fee into v_fee from marketplace_cancel_fee(b_fresh) f;
    if v_fee is distinct from 12450 then v_bad := v_bad || ' 사다리 복원 실패=' || coalesce(v_fee::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L27 견적은 살아있는 위임이다 — 사다리를 드롭하면 견적이 42883으로 깨지고, 언와인드 뒤 복원된다 (문자열 일치가 아니라 실행으로, F7)');
    else call _fail('lb', 'L27 위임 실행 핀', v_bad); end if;
  exception when others then call _fail('lb', 'L27 위임 실행 핀', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L28]–[L36] the codex FIX-FIRST round (2026-08-21)
  -- ══════════════════════════════════════════════════════════════════════════════════════

  -- [L28] CRIT-7: an answer is a HUMAN statement — no JWT, no answer, no server exemption
  b28 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform open_checkin(b28);
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform answer_checkin(b28, 'owner', 'cannot_proceed', '서버가 지어낸 진술');
      v_bad := v_bad || ' 무인 진술이 수락됨';
    exception when others then
      if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' 거부 사유=' || sqlerrm; end if;
    end;
    if exists (select 1 from booking_checkins bc where bc.booking_id = b28 and bc.owner_answer is not null)
      then v_bad := v_bad || ' 답이 남음'; end if;
    if exists (select 1 from booking_faults where booking_id = b28) then v_bad := v_bad || ' 과실이 남음'; end if;
    if v_bad = '' then
      call _pass('lb', 'L28 무JWT 응답 거부 — 서버는 인간 진술을 지어낼 수 없다 (D5; 돈을 면제시키는 과실행의 위조 경로 봉쇄, CRIT-7)');
    else call _fail('lb', 'L28 무JWT 응답 거부', v_bad); end if;
  exception when others then call _fail('lb', 'L28 무JWT 응답 거부', sqlerrm); end;

  -- [L29] CRIT-3: the handoff STAMPS are the custody fact — status is only the fallback
  b29 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b29);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
   where id = b29;                                     -- stamps written, promotion request LOST
  b29b := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b29b);
  update bookings set owner_confirmed_handoff_at = now() where id = b29b;   -- ONE stamp ≠ custody
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := answer_checkin(b29, 'owner', 'cannot_proceed');
    v_js := answer_checkin(b29b, 'owner', 'cannot_proceed');
    perform set_config('request.jwt.claim.sub', '', false);
    select b.status::text into v_st from bookings b where b.id = b29;
    if v_st is distinct from 'incident_review'
      then v_bad := v_bad || ' 양도장 미승격=' || v_st || ' (no_show면 D3 위반 — 개는 이미 러너 손)'; end if;
    select b.status::text into v_st from bookings b where b.id = b29b;
    if v_st is distinct from 'no_show' then v_bad := v_bad || ' 한도장=' || v_st || ' (한쪽 도장은 커스터디가 아니다, 0089)'; end if;
    if v_bad = '' then
      call _pass('lb', 'L29 커스터디는 도장 우선 — 양측 인계 도장 + 승격 유실 = post(incident_review)·한쪽 도장만은 pre(no_show) (CRIT-3, 0116 정산 견적과 같은 눈)');
    else call _fail('lb', 'L29 도장 우선 커스터디', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L29 도장 우선 커스터디', sqlerrm);
  end;

  -- [L29b] codex r2 F7: fetch's custody classification, pinned SEPARATELY from the resolver's.
  -- Round 1's L29 read the outcome only through the resolver, so reverting fetch's copy alone
  -- stayed green. Here the surface is asked directly, BEFORE anything resolves.
  -- its OWN fixtures: b29/b29b are resolved by L29 above, and a resolved booking is 'out' —
  -- a fetch-side custody pin has to read a LIVE booking or it measures the terminal instead.
  b29c := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b29c);
  update bookings set owner_confirmed_handoff_at = now() where id = b29c;      -- one stamp
  b29d := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b29d);
  update bookings set owner_confirmed_handoff_at = now(),
                      runner_confirmed_handoff_at = now() where id = b29d;      -- both stamps
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := fetch_checkin(b29c);                       -- one stamp — not custody yet
    if v_js->>'custody' is distinct from 'pre' then v_bad := v_bad || ' 한도장 fetch custody=' || coalesce(v_js->>'custody', 'null'); end if;
    v_js := fetch_checkin(b29d);                       -- both stamps, status not yet promoted
    if v_js->>'custody' is distinct from 'post' then v_bad := v_bad || ' 양도장 fetch custody=' || coalesce(v_js->>'custody', 'null'); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then
      call _pass('lb', 'L29b fetch 자신의 커스터디 분류 — 한쪽 도장 pre·양쪽 도장 post(승격 전에도), 표면이 리졸버와 독립으로 답한다 (F7)');
    else call _fail('lb', 'L29b fetch 커스터디 분류', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L29b fetch 커스터디 분류', sqlerrm);
  end;

  -- [L31] HIGH-4: arrival evidence blocks the TIMER waiver; only a recorded fault waives then
  -- [codex r2 F7] SPLIT: round 1 asserted both evidence kinds in ONE pin, so deleting EITHER
  -- predicate left the other arm red and the pin could not name which fell. One fixture per
  -- predicate: b31 carries only arrived_at, b31b carries only the handoff stamps.
  b31 := t_av_booking(oo, dg, rt, rr, now() - interval '17 days', 5.0, 'runner_enroute');
  update bookings set arrived_at = now() - interval '17 days' + interval '20 minutes' where id = b31;
  begin
    v_bad := '';
    select f.fee into v_fee from marketplace_cancel_fee(b31) f;
    if v_fee is distinct from 12450
      then v_bad := v_bad || ' 도착 증거에도 면제=' || coalesce(v_fee::text, 'null') || ' (타이머가 러너의 0066 권리를 벗김)'; end if;
    -- the faulted twin is its own booking (fault rows are write-once — r2 F2)
    b31f := t_av_booking(oo, dg, rt, rr, now() - interval '17 days', 5.0, 'runner_enroute');
    update bookings set arrived_at = now() - interval '17 days' + interval '20 minutes' where id = b31f;
    insert into booking_faults (booking_id, party, source, stated_by)
    values (b31f, 'runner', 'test_ops_statement', rr);
    select f.fee into v_fee from marketplace_cancel_fee(b31f) f;
    if v_fee is distinct from 0 then v_bad := v_bad || ' 기록된 과실에도 미면제=' || coalesce(v_fee::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L31 arrived_at 증거가 있으면 타이머 면제 없음 (12450 유지) — 그때는 기록된 과실만이 면제한다 (0원) (HIGH-4)');
    else call _fail('lb', 'L31 arrived_at 증거 vs 타이머', v_bad); end if;
  exception when others then call _fail('lb', 'L31 arrived_at 증거 vs 타이머', sqlerrm); end;

  -- [L31b] the OTHER evidence kind, on its own fixture: handoff stamps with no arrived_at
  b31b := t_av_booking(oo, dg, rt, rr, now() - interval '17 days', 5.0, 'runner_enroute');
  update bookings set owner_confirmed_handoff_at = now() - interval '17 days' + interval '25 minutes',
                      runner_confirmed_handoff_at = now() - interval '17 days' + interval '25 minutes'
   where id = b31b;
  begin
    v_bad := '';
    select f.fee into v_fee from marketplace_cancel_fee(b31b) f;
    if v_fee is distinct from 12450
      then v_bad := v_bad || ' 인계 도장 증거에도 면제=' || coalesce(v_fee::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L31b 인계 도장 증거가 있으면 타이머 면제 없음 — arrived_at 이 없어도 (증거는 두 종류, 술어도 두 개, HIGH-4/F7)');
    else call _fail('lb', 'L31b 인계 도장 증거 vs 타이머', v_bad); end if;
  exception when others then call _fail('lb', 'L31b 인계 도장 증거 vs 타이머', sqlerrm); end;

  -- [L32] HIGH-8: the REAL cancel wins the race — the late genuine statement is refused
  --       loudly, never swallowed after persisting
  b32 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  perform open_checkin(b32);
  update bookings set status = 'cancelled_owner' where id = b32;   -- the real 50% cancel path's
                                                                   -- DB effect (fee derives §9c)
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform answer_checkin(b32, 'runner', 'cannot_proceed', '진짜 사정이 있었다');
      v_bad := v_bad || ' 떠난 예약에 답이 붙음';
    exception when others then
      if sqlerrm <> 'not_late_eligible' then v_bad := v_bad || ' 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if exists (select 1 from booking_checkins bc where bc.booking_id = b32 and bc.runner_answer is not null)
      then v_bad := v_bad || ' 답이 남음'; end if;
    update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
     where booking_id = b32;
    perform late_booking_sweep();
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b32;
    if v_res is distinct from 'superseded' then v_bad := v_bad || ' resolution=' || coalesce(v_res, 'null'); end if;
    if exists (select 1 from booking_faults where booking_id = b32) then v_bad := v_bad || ' 과실이 적힘'; end if;
    if (select b.status::text from bookings b where b.id = b32) is distinct from 'cancelled_owner'
      then v_bad := v_bad || ' 종단이 움직임'; end if;
    if v_bad = '' then
      call _pass('lb', 'L32 진짜 취소가 이긴 뒤의 진심 어린 진술 = not_late_eligible 로 시끄럽게 거부 — 삼켜지지 않는다; 체크인은 superseded (HIGH-8)');
    else call _fail('lb', 'L32 취소 후 응답 거부', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('lb', 'L32 취소 후 응답 거부', sqlerrm);
  end;

  -- [L33] HIGH-6: the written fee is the at-write-time fee — never the quoted one
  b33  := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'runner_enroute');
  b33b := t_av_booking(oo, dg, rt, rr, now() - interval '17 days',    5.0, 'runner_enroute');
  begin
    v_bad := '';
    update bookings set status = 'cancelled_owner', cancel_fee = 99999 where id = b33;   -- forged/stale quote
    select b.cancel_fee into v_n from bookings b where b.id = b33;
    if v_n is distinct from 12450 then v_bad := v_bad || ' 위조 견적이 남음=' || coalesce(v_n::text, 'null'); end if;
    -- T+2:59:59 quote landing after T+3h: the stale 12450 must store as the waived 0
    update bookings set status = 'cancelled_owner', cancel_fee = 12450 where id = b33b;
    select b.cancel_fee into v_n from bookings b where b.id = b33b;
    if v_n is distinct from 0 then v_bad := v_bad || ' 실링 넘은 견적이 남음=' || coalesce(v_n::text, 'null'); end if;
    -- [codex r2 F7] the CONFIRMED tiers, which round 1's en-route-only arms never touched:
    -- a <24h cancel stores 10% over any claim, and a ≥24h cancel stores 0 over any claim.
    b39c := t_av_booking(oo, dg, rt, rr, now() + interval '6 hours', 5.0, 'confirmed');
    update bookings set status = 'cancelled_owner', cancel_fee = 99999 where id = b39c;
    select b.cancel_fee into v_n from bookings b where b.id = b39c;
    if v_n is distinct from 2490 then v_bad := v_bad || ' 확정 24h내 저장=' || coalesce(v_n::text, 'null'); end if;
    b39d := t_av_booking(oo, dg, rt, rr, now() + interval '48 hours', 5.0, 'confirmed');
    update bookings set status = 'cancelled_owner', cancel_fee = 99999 where id = b39d;
    select b.cancel_fee into v_n from bookings b where b.id = b39d;
    if v_n is distinct from 0 then v_bad := v_bad || ' 확정 24h이전 저장=' || coalesce(v_n::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L33 기록되는 수수료 = 쓰는 시점의 사다리 값 — 인루트 위조 99999→12450·실링 넘긴 12450→0·확정 24h내 →2490·24h이전 →0 (§9c, 네 티어 전부, HIGH-6/F7)');
    else call _fail('lb', 'L33 수수료 진실 트리거', v_bad); end if;
  exception when others then call _fail('lb', 'L33 수수료 진실 트리거', sqlerrm); end;

  -- [L34] HIGH-9: a row-less booking is backfilled only past ceiling + a full grace margin
  b34  := t_av_booking(oo, dg, rt, rr, now() - interval '3 hours 10 minutes', 5.0, 'confirmed');
  b34b := t_av_booking(oo, dg, rt, rr, now() - interval '3 hours 40 minutes', 5.0, 'confirmed');
  begin
    v_bad := '';
    perform late_booking_sweep();
    if exists (select 1 from booking_checkins where booking_id = b34) then v_bad := v_bad || ' 마진 안에서 백필'; end if;
    if (select b.status::text from bookings b where b.id = b34) is distinct from 'confirmed'
      then v_bad := v_bad || ' 마진 안에서 종결'; end if;
    select bc.resolution into v_res from booking_checkins bc where bc.booking_id = b34b;
    if v_res is distinct from 'ceiling_backfill' then v_bad := v_bad || ' 마진 밖 백필=' || coalesce(v_res, '행 없음'); end if;
    if (select b.status::text from bookings b where b.id = b34b) is distinct from 'no_show'
      then v_bad := v_bad || ' 마진 밖 미종결'; end if;
    if v_bad = '' then
      call _pass('lb', 'L34 백필은 실링+그레이스 마진을 넘겨야 — 제공한 적 없는 창을 주장하지 않는다 (제3의 숫자 없이, HIGH-9)');
    else call _fail('lb', 'L34 백필 마진', v_bad); end if;
  exception when others then call _fail('lb', 'L34 백필 마진', sqlerrm); end;

  -- [L35] the constraint belts stand on their own (MEDIUM-10a / HIGH-15)
  b35 := t_av_booking(oo, dg, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  begin
    v_bad := '';
    begin
      insert into booking_faults (booking_id, party, source, stated_by) values (b35, 'runner', 'x', null);
      v_bad := v_bad || ' 무인 과실행 통과';
    exception when others then
      if sqlstate <> '23502' then v_bad := v_bad || ' 무인 코드=' || sqlstate; end if;
    end;
    begin
      insert into booking_checkins (booking_id, opened_at, deadline_at, owner_answer)
      values (b35, now(), now() + interval '30 minutes', 'cannot_proceed');
      v_bad := v_bad || ' 도장 없는 답 통과';
    exception when others then
      if sqlstate <> '23514' then v_bad := v_bad || ' 도장쌍 코드=' || sqlstate; end if;
    end;
    begin
      insert into booking_checkins (booking_id, opened_at, deadline_at, resolved_at)
      values (b35, now(), now(), now());
      v_bad := v_bad || ' 사유 없는 종결 통과';
    exception when others then
      if sqlstate <> '23514' then v_bad := v_bad || ' 종결쌍 코드=' || sqlstate; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L35 제약 벨트 자립 — stated_by NULL 23502·답/도장 쌍 23514·종결/사유 쌍 23514 (함수를 다 지워도 테이블이 거짓을 거부)');
    else call _fail('lb', 'L35 제약 벨트', v_bad); end if;
  exception when others then call _fail('lb', 'L35 제약 벨트', sqlerrm); end;

  -- [L36] rows are never deleted — the DELETE guards (MEDIUM-10)
  begin
    v_bad := '';
    begin
      delete from booking_checkins where booking_id = b2;
      v_bad := v_bad || ' 체크인 삭제 통과';
    exception when others then
      if sqlerrm <> 'checkin_immutable' then v_bad := v_bad || ' 체크인 삭제 사유=' || sqlerrm; end if;
    end;
    begin
      delete from booking_faults where booking_id = b2;
      v_bad := v_bad || ' 과실 삭제 통과';
    exception when others then
      if sqlerrm <> 'fault_immutable' then v_bad := v_bad || ' 과실 삭제 사유=' || sqlerrm; end if;
    end;
    if v_bad = '' then
      call _pass('lb', 'L36 프로토콜 기록은 지워지지 않는다 — 체크인·과실행 DELETE 는 트리거가 거부 (postgres여도; 불변성은 테이블 불변식, MEDIUM-10)');
    else call _fail('lb', 'L36 삭제 벨트', v_bad); end if;
  exception when others then call _fail('lb', 'L36 삭제 벨트', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L37] codex r2 F1 — the CLOCK may return km, but it may not extend km's LIFETIME
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Refuted round 1's "pure unwind": `_km_close_hold` (0075:353) also pushes an ALREADY EXPIRED
  -- lot to now()+72h — new spendable lifetime granted by a timer, 0068's forbidden direction.
  -- Both ways in one pin: the CLOCK-caused terminal returns quantity and leaves the expiry in
  -- the past; the HUMAN-caused terminal keeps 0075's grace (a person acted — the same class as
  -- the owner cancel that has always extended).
  ow37 := t_user('lb_ow37', 'owner'); dg37 := t_dog(ow37, '실링견');
  lot37 := km_grant(ow37, 10, 'recovery', 1);
  b37 := t_av_booking(ow37, dg37, rt, rr, now() - interval '17 days', 5.0, 'confirmed');
  perform km_reserve(b37);                              -- hold taken while the lot was valid…
  update km_lots set expires_at = now() - interval '1 day' where id = lot37;   -- …then it expired

  ow37h := t_user('lb_ow37h', 'owner'); dg37h := t_dog(ow37h, '진술견');
  lot37h := km_grant(ow37h, 10, 'recovery', 1);
  b37h := t_av_booking(ow37h, dg37h, rt, rr, now() - interval '40 minutes', 5.0, 'confirmed');
  perform km_reserve(b37h);
  update km_lots set expires_at = now() - interval '1 day' where id = lot37h;
  perform open_checkin(b37h);
  perform set_config('request.jwt.claim.sub', ow37h::text, false);
  v_js := answer_checkin(b37h, 'owner', 'cannot_proceed', '사람이 말한 종결');
  perform set_config('request.jwt.claim.sub', '', false);

  perform late_booking_sweep();                          -- the ceiling resolves b37

  begin
    v_bad := '';
    if (select b.status::text from bookings b where b.id = b37) is distinct from 'no_show'
      then v_bad := v_bad || ' 실링 미해소'; end if;
    -- quantity comes back — the unwind half still happens
    select km_remaining, expires_at into v_km, v_exp from km_lots where id = lot37;
    if v_km is distinct from 10 then v_bad := v_bad || ' km 미반환=' || coalesce(v_km::text, 'null'); end if;
    -- …but the lifetime does not
    if v_exp > now() then v_bad := v_bad || ' 시계가 수명을 연장함 (' || v_exp || ') — 0068 금지 방향'; end if;
    -- the human-stated terminal KEEPS 0075's grace: the suppression is targeted, not blanket
    select km_remaining, expires_at into v_km, v_exp2 from km_lots where id = lot37h;
    if v_km is distinct from 10 then v_bad := v_bad || ' 진술측 km 미반환=' || coalesce(v_km::text, 'null'); end if;
    if v_exp2 <= now() then v_bad := v_bad || ' 사람이 말했는데 0075 유예가 사라짐 (' || v_exp2 || ')'; end if;
    if v_bad = '' then
      call _pass('lb', 'L37 시계는 km을 돌려주되 수명을 늘리지 않는다 — 실링 종결은 만료를 과거로 남기고, 사람이 진술한 종결은 0075의 72h 유예를 그대로 받는다 (r2 F1)');
    else call _fail('lb', 'L37 시계와 km 수명', v_bad); end if;
  exception when others then call _fail('lb', 'L37 시계와 km 수명', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L39] codex r2 F3 — the MARKER travels with the FEE, and the marker is what pays
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The split brain's root: the fee was corrected by SQL while the tier marker was chosen by
  -- the edge's earlier quote, so a boundary-crossing cancel stored 10% with NO marker and the
  -- runner's half was never written. One ladder read now writes both. The final arm proves the
  -- marker actually reaches the money.
  b39  := t_av_booking(oo, dg, rt, rr, now() + interval '6 hours',  5.0, 'confirmed');
  b39b := t_av_booking(oo, dg, rt, rr, now() + interval '48 hours', 5.0, 'confirmed');
  begin
    v_bad := '';
    -- ⓐ <24h confirmed: the edge's stale ≥24h quote claims 0; the row must still carry the
    --    10% tier AND its marker (round 1 stored the fee and left cancel_reason null)
    update bookings set status = 'cancelled_owner', cancel_fee = 0 where id = b39;
    select b.cancel_fee, b.cancel_reason into v_n, v_txt from bookings b where b.id = b39;
    if v_n is distinct from 2490 then v_bad := v_bad || ' ⓐ fee=' || coalesce(v_n::text, 'null'); end if;
    if v_txt is distinct from 'owner_cancel_late' then v_bad := v_bad || ' ⓐ marker=' || coalesce(v_txt, 'null'); end if;
    -- ⓑ ≥24h confirmed: free, and NO marker — a tier that pays nobody must not look like one
    update bookings set status = 'cancelled_owner', cancel_fee = 2490 where id = b39b;
    select b.cancel_fee, b.cancel_reason into v_n, v_txt from bookings b where b.id = b39b;
    if v_n is distinct from 0 then v_bad := v_bad || ' ⓑ fee=' || coalesce(v_n::text, 'null'); end if;
    if v_txt is not null then v_bad := v_bad || ' ⓑ marker=' || v_txt; end if;
    -- ⓒ en-route: the tier is recorded even when the ceiling waived the amount to 0
    select b.cancel_reason into v_txt from bookings b where b.id = b33b;
    if v_txt is distinct from 'owner_cancel_enroute' then v_bad := v_bad || ' ⓒ 면제된 인루트 marker=' || coalesce(v_txt, 'null'); end if;
    -- ⓓ THE CONSEQUENCE: the stored marker is what the money reads. 0085 gates on it, so the
    --    runner's half exists for ⓐ and cannot exist for ⓑ — this is the half that was silently
    --    lost when the marker followed a dead quote.
    select sh.comp into v_share from record_late_cancel_share(b39) sh;
    if v_share is distinct from 1245 then v_bad := v_bad || ' ⓓ 러너 배분=' || coalesce(v_share::text, 'null'); end if;
    select sh.comp into v_share from record_late_cancel_share(b39b) sh;
    if v_share is distinct from 0 then v_bad := v_bad || ' ⓓ 무료 취소가 배분됨=' || coalesce(v_share::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L39 마커는 수수료와 함께 이동한다 — 한 번의 사다리 읽기가 둘 다 쓰고(24h내 2490/late·24h이전 0/무마커·면제된 인루트도 티어 기록), 그 마커가 러너 배분 1245를 실제로 연다 (r2 F3의 뿌리)');
    else call _fail('lb', 'L39 마커·수수료 동행', v_bad); end if;
  exception when others then call _fail('lb', 'L39 마커·수수료 동행', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L40] codex r2 F6 — a deliberate ops correction is not clobbered
  -- ══════════════════════════════════════════════════════════════════════════════════════
  b40 := t_av_booking(oo, dg, rt, rr, now() + interval '6 hours', 5.0, 'confirmed');
  begin
    v_bad := '';
    perform set_config('app.ops_cancel_fee_override', 'on', true);
    update bookings set status = 'cancelled_owner', cancel_fee = 777 where id = b40;
    perform set_config('app.ops_cancel_fee_override', '', true);
    select b.cancel_fee into v_n from bookings b where b.id = b40;
    if v_n is distinct from 777 then v_bad := v_bad || ' 운영 정정이 덮임=' || coalesce(v_n::text, 'null'); end if;
    -- and with the override OFF the same shape is corrected — the exemption is deliberate,
    -- not a hole that is always open
    b39c := t_av_booking(oo, dg, rt, rr, now() + interval '6 hours', 5.0, 'confirmed');
    update bookings set status = 'cancelled_owner', cancel_fee = 777 where id = b39c;
    select b.cancel_fee into v_n from bookings b where b.id = b39c;
    if v_n is distinct from 2490 then v_bad := v_bad || ' 무플래그인데 미정정=' || coalesce(v_n::text, 'null'); end if;
    if v_bad = '' then
      call _pass('lb', 'L40 의도된 운영 정정은 살아남는다 (app.ops_cancel_fee_override=on 한 트랜잭션) · 플래그 없으면 같은 문장도 사다리로 정정된다 (r2 F6)');
    else call _fail('lb', 'L40 운영 정정 면제', v_bad); end if;
  exception when others then
    perform set_config('app.ops_cancel_fee_override', '', true);
    call _fail('lb', 'L40 운영 정정 면제', sqlerrm);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [L14] the ACL/RLS catalog — who can execute what, and the tables are sealed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- anon: nowhere
    if has_function_privilege('anon', 'answer_checkin(uuid,text,text,text)', 'execute') then v_bad := v_bad || ' anon answer'; end if;
    if has_function_privilege('anon', 'fetch_checkin(uuid)', 'execute') then v_bad := v_bad || ' anon fetch'; end if;
    if has_function_privilege('anon', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' anon open'; end if;
    if has_function_privilege('anon', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' anon sweep'; end if;
    if has_function_privilege('anon', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' anon waived'; end if;
    if has_function_privilege('anon', 'marketplace_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' anon fee'; end if;
    if has_function_privilege('anon', 'quote_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' anon quote'; end if;
    -- authenticated: exactly the two party calls
    if not has_function_privilege('authenticated', 'answer_checkin(uuid,text,text,text)', 'execute') then v_bad := v_bad || ' auth¬answer'; end if;
    if not has_function_privilege('authenticated', 'fetch_checkin(uuid)', 'execute') then v_bad := v_bad || ' auth¬fetch'; end if;
    if not has_function_privilege('authenticated', 'quote_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' auth¬quote'; end if;
    if has_function_privilege('authenticated', 'marketplace_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' auth 사다리 직접'; end if;
    if has_function_privilege('authenticated', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' auth open'; end if;
    if has_function_privilege('authenticated', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' auth sweep'; end if;
    if has_function_privilege('authenticated', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' auth waived'; end if;
    if has_function_privilege('authenticated', '_resolve_checkin(uuid,text)', 'execute') then v_bad := v_bad || ' auth resolver'; end if;
    -- service_role: the fee path and the party calls, NEVER the clock
    if not has_function_privilege('service_role', 'marketplace_cancel_fee(uuid)', 'execute') then v_bad := v_bad || ' svc¬fee'; end if;
    if not has_function_privilege('service_role', 'enroute_cancel_fee_waived(uuid)', 'execute') then v_bad := v_bad || ' svc¬waived'; end if;
    if has_function_privilege('service_role', 'open_checkin(uuid)', 'execute') then v_bad := v_bad || ' svc open (제2의 시계)'; end if;
    if not has_function_privilege('service_role', 'late_booking_sweep()', 'execute') then v_bad := v_bad || ' svc¬sweep (스케줄러 폴백, MEDIUM-12)'; end if;
    if has_function_privilege('service_role', '_checkin_custody(booking_status,timestamptz,timestamptz)', 'execute') then v_bad := v_bad || ' svc custody'; end if;
    -- [codex r2 F2] ALL FOUR write verbs, all three client-reachable roles. Round 1 revoked
    -- only UPDATE/DELETE, leaving service_role able to INSERT a fabricated check-in (a fault
    -- row waives money) and TRUNCATE the protocol's ledger. The definer functions own writes.
    foreach v_txt in array array['anon', 'authenticated', 'service_role'] loop
      foreach v_res in array array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'] loop
        if has_table_privilege(v_txt, 'booking_checkins', v_res)
          then v_bad := v_bad || ' ' || v_txt || ' checkins ' || v_res; end if;
        if has_table_privilege(v_txt, 'booking_faults', v_res)
          then v_bad := v_bad || ' ' || v_txt || ' faults ' || v_res; end if;
      end loop;
    end loop;
    select count(*) into v_n from pg_proc p2 join pg_namespace n2 on n2.oid = p2.pronamespace
     where n2.nspname = 'public' and p2.proname = 'late_booking_sweep' and p2.prosrc like '%lock_timeout%';
    if v_n is distinct from 1 then v_bad := v_bad || ' 스위프 lock_timeout 없음 (MEDIUM-11)'; end if;
    if has_function_privilege('service_role', '_resolve_checkin(uuid,text)', 'execute') then v_bad := v_bad || ' svc resolver'; end if;
    -- the tables: RLS on, zero policies (fail-closed seal, ops_flags' shape)
    if not (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'booking_checkins') then v_bad := v_bad || ' checkins RLS off'; end if;
    if not (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'booking_faults') then v_bad := v_bad || ' faults RLS off'; end if;
    select count(*) into v_n from pg_policies where tablename in ('booking_checkins', 'booking_faults');
    if v_n is distinct from 0 then v_bad := v_bad || ' 정책=' || v_n; end if;
    if v_bad = '' then
      call _pass('lb', 'L14 표면 봉인 — anon 어디에도 없음·authenticated는 answer/fetch/quote만·open/resolver는 service_role조차 없음·스위프만 스케줄러 폴백·테이블 UPDATE/DELETE는 svc도 없음·RLS on 정책 0');
    else call _fail('lb', 'L14 표면 봉인', v_bad); end if;
  exception when others then call _fail('lb', 'L14 표면 봉인', sqlerrm); end;

  -- restore the shipped default: the clock leaves this suite exactly as it deploys — OFF
  update ops_flags set late_protocol_live_since = null, updated_at = now();
end $$;
