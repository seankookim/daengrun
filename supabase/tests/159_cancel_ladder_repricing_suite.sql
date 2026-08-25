-- ═══ 159: cancel ladder repricing (0124) — console rulings #11 + #13 ═══
-- L1 free-24h beats acceptance · L2 unconnected is free anytime · L3 the post-accept rung is
-- UNTOUCHED (the guard pin) · L4 late_cancel has no consumer (structural). Every pin names its
-- proposition; mutations in the 0124 REGISTRY row name the same observables.
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oA uuid; oB uuid; oC uuid; dA uuid; dB uuid; dC uuid; rt uuid;
  v_club uuid; s_far uuid; s_near uuid; sdA uuid; sdB uuid; sdC uuid;
  bA uuid; bB uuid; bC uuid;
  v_total int; v_bad text; v_cnt int; v_fee int; v_txt text;
begin
  -- ── seed: one far session (48h out) and one near session (90min out) ──
  hh := t_user('lad_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr := t_user('lad_rr', 'runner');
  oA := t_user('lad_oA', 'owner'); dA := t_dog(oA, '사다리A');
  oB := t_user('lad_oB', 'owner'); dB := t_dog(oB, '사다리B');
  oC := t_user('lad_oC', 'owner'); dC := t_dog(oC, '사다리C');
  rt := t_route('사다리 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('사다리동');
  perform club_claim_host(v_club);
  s_far  := club_create_session(v_club, now() + interval '48 hours', '사다리 집결지', rt, 8, 'mixed');
  s_near := club_create_session(v_club, now() + interval '90 minutes', '사다리 집결지', rt, 8, 'mixed');
  -- Check-in is start-windowed (checkin_window raised for the 48h session, measured) AND
  -- assignment requires it (runner_not_checked_in raised without it, also measured) — so the
  -- near session checks in and the far one cannot, which is the same fact L1's manufactured
  -- state documents: assignment ≥24h out is unreachable in today's flows.
  perform session_runner_commit(s_far);
  perform session_runner_commit(s_near); perform session_checkin(s_near);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(s_far);
  perform session_runner_commit(s_near); perform session_checkin(s_near);

  -- A: far session, runner ACCEPTED (the #11 case)
  perform set_config('request.jwt.claim.sub', oA::text, false);
  sdA := session_delegate_dog(s_far, dA, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdA, true);
  perform set_config('request.jwt.claim.sub', oA::text, false);
  bA := session_pay_delegation(sdA, 'idem-lad-a', true);
  -- ⚠ SCOPE, stated (v5 unstated-scope law): "accepted ≥24h out" is UNREACHABLE via today's
  -- flows — session_assign_dog raised assign_window on this very fixture (measured, first
  -- run). #11 prices a state that spec-v2's early-pick layer will create; until then the
  -- hoist is dormant. This pin therefore MANUFACTURES the state as postgres and owns the
  -- LADDER ARM's behavior ("IF confirmed+runner exists ≥24h out, cancel is free"), not the
  -- flow's reachability — when the pick layer opens, its own suite owns the real path.
  update bookings set status = 'confirmed', runner_id = rr where id = bA;

  -- B: near session, NEVER accepted (the #13 case)
  perform set_config('request.jwt.claim.sub', oB::text, false);
  sdB := session_delegate_dog(s_near, dB, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdB, true);
  perform set_config('request.jwt.claim.sub', oB::text, false);
  bB := session_pay_delegation(sdB, 'idem-lad-b', true);

  -- C: near session, runner ACCEPTED (the unchanged-rung guard)
  perform set_config('request.jwt.claim.sub', oC::text, false);
  sdC := session_delegate_dog(s_near, dC, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdC, true);
  perform set_config('request.jwt.claim.sub', oC::text, false);
  bC := session_pay_delegation(sdC, 'idem-lad-c', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sdC, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_proposal_respond(sdC, true);

  -- ── L1 (#11): an ACCEPTED delegation cancelled ≥24h out is FREE — the free window outranks
  -- post-acceptance; the runner is released; the release notification claims NO compensation
  -- (there is none to claim — edit ② is the honesty half of this pin).
  perform set_config('request.jwt.claim.sub', oA::text, false);
  perform session_cancel_delegation(sdA);
  v_bad := '';
  if coalesce((select cancel_fee from bookings where id = bA), 0) <> 0
    then v_bad := ' fee=' || (select cancel_fee from bookings where id = bA); end if;
  if exists (select 1 from club_fee_items where booking_id = bA)
    then v_bad := v_bad || ' fee-items-exist'; end if;
  if (select runner_id from bookings where id = bA) is not null
    then v_bad := v_bad || ' runner-not-released'; end if;
  if not exists (select 1 from assignment_events where session_dog_id = sdA and event = 'revoked')
    then v_bad := v_bad || ' no-revoke-event'; end if;
  if not exists (select 1 from notifications where profile_id = oA and ref_id = bA
                 and body like '%취소 수수료는 없어요%')
    then v_bad := v_bad || ' owner-noti-wrong'; end if;
  if exists (select 1 from notifications where profile_id = rr and ref_id = s_far
             and body like '%보상 기록%')
    then v_bad := v_bad || ' comp-lie-shipped'; end if;
  if v_bad <> '' then call _fail('lad','L1 #11 자유창이 수락을 이긴다', v_bad);
                 else call _pass('lad','L1 #11 자유창이 수락을 이긴다 — 무료·해제·정직한 알림'); end if;

  -- ── L2 (#13): a NEVER-accepted delegation cancelled INSIDE the late window is FREE —
  -- 「연결은 우리 일」; the old 10% (then half) runnerless charge is gone.
  perform set_config('request.jwt.claim.sub', oB::text, false);
  perform session_cancel_delegation(sdB);
  v_bad := '';
  if coalesce((select cancel_fee from bookings where id = bB), 0) <> 0
    then v_bad := ' fee=' || (select cancel_fee from bookings where id = bB); end if;
  if exists (select 1 from club_fee_items where booking_id = bB)
    then v_bad := v_bad || ' fee-items-exist'; end if;
  if not exists (select 1 from notifications where profile_id = oB and ref_id = bB
                 and body like '%취소 수수료는 없어요%')
    then v_bad := v_bad || ' owner-noti-wrong'; end if;
  if v_bad <> '' then call _fail('lad','L2 #13 미연결=무료', v_bad);
                 else call _pass('lad','L2 #13 미연결=무료 — 늦어도 러너가 없었으면 0원'); end if;

  -- ── L3 guard: the post-acceptance rung is UNTOUCHED — accepted + <24h still charges the
  -- ruled 20%, splits both fee items (platform + supply: ruling B's non-runnerless split), and
  -- the runner's release notification legitimately claims the compensation record.
  select total_price into v_total from bookings where id = bC;
  perform set_config('request.jwt.claim.sub', oC::text, false);
  perform session_cancel_delegation(sdC);
  v_fee := round(v_total * club_cfg_required('cancel_post_accept_pct') / 100.0)::int;
  v_bad := '';
  if (select cancel_fee from bookings where id = bC) is distinct from v_fee
    then v_bad := ' fee=' || coalesce((select cancel_fee from bookings where id = bC)::text,'∅')
                  || ' expect=' || v_fee; end if;
  select count(*) into v_cnt from club_fee_items where booking_id = bC;
  if v_cnt <> 2 then v_bad := v_bad || ' items=' || v_cnt; end if;
  if not exists (select 1 from notifications where profile_id = rr and ref_id = s_near
                 and body like '%보상 기록이 남았어요%')
    then v_bad := v_bad || ' comp-noti-missing'; end if;
  if v_bad <> '' then call _fail('lad','L3 수락 후 렁 불변', v_bad);
                 else call _pass('lad','L3 수락 후 렁 불변 — 20%·두 몫·보상 알림'); end if;

  -- ── L4 structural: the ladder names its arms — 'unconnected_free' exists, 'late_cancel'
  -- has NO consumer left in this function (deliberate fact, pinned so a future edit that
  -- quietly resurrects the rung announces itself).
  select prosrc into v_txt from pg_proc where proname = 'session_cancel_delegation';
  v_bad := '';
  if v_txt not like '%''unconnected_free''%' then v_bad := ' no-unconnected-arm'; end if;
  -- match the ASSIGNMENT, not the word: prosrc includes comments, and 0124's own header
  -- names the retired rung (measured red on the comment, first run — the M2 class inverted).
  if v_txt ~ 'v_rule\s*:=\s*''late_cancel''' then v_bad := v_bad || ' late-rung-back'; end if;
  if v_bad <> '' then call _fail('lad','L4 사다리 구조', v_bad);
                 else call _pass('lad','L4 사다리 구조 — unconnected_free 있음·late_cancel 소비자 없음'); end if;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
