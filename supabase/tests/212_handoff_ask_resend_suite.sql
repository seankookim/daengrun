-- ═══ 212 — 0181's arm ⓒ: the lost 「인계 확인 요청」 is re-sent — 0181-C1…C8, tag `ask` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   · a handoff one side confirmed, whose ask to the OTHER side never existed, gets that ask from
--     `sweep_run_end_recovery` after five minutes — once, to the counterparty (never the party
--     who stamped), with the edge's exact title/body/kind, counted in the return.
--   · an ask that exists is not re-sent; an ask from an EARLIER cycle does not count as this
--     stamp's ([0183] cycles are told apart by `handoff_cycle_id`, not by age — the fixtures here
--     carry the id where they model the new edge, and none where they model an earlier cycle);
--     an ask addressed to the OTHER party does not count as this party's (C9).
--   · a booking in any status but the two where a handoff is underway (`confirmed` ·
--     `runner_enroute`) is never touched — every other status in the enum is walked, so a status
--     added to the enum and to neither side reddens C6 instead of being decided by omission;
--     both stamps ⇒ nothing; no runner ⇒ nothing.
--   · a CLUB booking is swept (the pickup ask is the same edge action in both worlds).
--   · the sweep runs under a transaction-scoped TRY job lock taken before any arm (C8 sees it
--     held; `90_race_check.sh` RL measures the two-tick skip with two processes).
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE:
--   · arms ⓐ/ⓑ (119 · 132 · 133 · 163 own them; the body is 0083's verbatim there) and the cron
--     row (208).
--   · the notice text — plpgsql cannot read its own notices; the RETURN delta is what C1 pins.
--   · the two-tick skip as behaviour — RL, two processes; here only the lock's presence (C8).
--
-- ─── MUTATION MAP — measured 2026-09-18 (re-run after the cold review's fixes), not predicted ───
--   Lab: an md5-identical copy of 0181 (+ tests, + functions for the deno side), every plant
--   `&&`-chained to its run, the control observed first (1279 / 0; deno 13 / 0 for this file).
--   「demoted」 = 0181's VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where the VERIFY aborts the apply before any suite runs.
--   (i)    the job lock deleted                        → C8 (잡 락 없음 · not held after the call) + RL
--          (ret=1 during=1: the second tick WROTE while the first held); un-demoted the apply
--          ABORTS (JOB-LOCK-MISSING).
--   (ii)   the not-exists deleted (asked every tick)   → C1 (re-sent-twice 2/2 · return-delta 0)
--          + C3 (2 rows beside the edge's) + C4 (within-skew 2) + C8.
--   (iii)  the counterparty inverted (the stamper asked) → C1 + C2 + C4 + C5 + C7 + C9 + RL (after=0).
--   (iv)   `completed` dropped from the deny-list      → C6 (completed:asked) + C8; un-demoted ABORTS.
--   (v)    the deny-list rewritten as the live allow-list → C8 ONLY; un-demoted ABORTS. Behaviour is
--          identical today — the one source-only plant, and meant to be: the allow-list's failure
--          arms only when a status is ADDED, which is exactly when nobody re-runs a battery.
--   (vi)   ASK_AFTER 0                                 → C5 (asked-at-2-minutes).
--   (vii)  ASK_SKEW 0                                  → C4 (within-skew: 2).
--   (viii) the sweep's title ≠ the edge's              → C1 + C2 + C4 + C5 + C7 + C8 + C9 + RL (t_asks
--          counts the edge's title: nothing arrives under it); un-demoted ABORTS; the deno drift
--          pin reddens from its side too (12/1).
--   (ix)   `club_session_id is null` added to arm ⓒ   → C7 + C8 (club 범위 조건 수=3); un-demoted ABORTS.
--   (x)    `runner_id is not null` deleted             → C8 only — the per-row handler CATCHES the
--          NULL-profile insert, so the runner-less row gets no ask and nothing raises (C6 green);
--          un-demoted ABORTS (RUNNER-CONJUNCT-MISSING).
--   (x+xiv) …and the handler deleted too              → C6 (no-runner: the sweep RAISED — NULL
--          profile_id) + C8. ⚠ The measured value of the handler: without it one runner-less row
--          aborts the WHOLE sweep, arms ⓐ/ⓑ included.
--   (xi)   the created_at conjunct deleted (any ask ever counts) → C4 (previous-cycle: 1).
--   (xii)  the EDGE's title changed (deno lab)        → deno `[0181]` red (12/1), SQL side green by
--          construction — the drift pin is the only thing that sees this direction.
--   (xiii) `nt.profile_id = x.counterparty` deleted    → C9 (both directions: owner-asks=0 ·
--          runner-asks=0) + C8; un-demoted ABORTS (ASK-NOT-MATCHED-BY-COUNTERPARTY). The cold
--          review's HIGH: before C9 existed this plant left 1278/0.
--   (xiv)  arm ⓒ's per-row exception arm deleted     → C8 (행 단위 예외 팔 수=1); un-demoted ABORTS.
--          Source-only alone (the insert cannot fail today); (x+xiv) is its behaviour.
--   (xv)   exactly-one-stamp loosened to either-stamp → C6 (both-stamps:asked) + C8; un-demoted ABORTS.
--   (xvi)  the job lock moved after arm ⓐ            → C8 only (잡 락이 첫 팔 뒤); un-demoted ABORTS.
--          RL's fixture cannot see ordering — recorded as C8's, not RL's.
--   NAMED GAP: the two-tick SKIP is measured only by RL (two processes); C8's lock arm proves the
--   lock is taken, not that a second session yields. The sweep's notice text is unpinned.
-- ─── FIXTURE NOTES ───
--  ① The sweep is GLOBAL and its return counts arms ⓐ/ⓑ over whatever earlier suites left, so a
--     drain call runs before the fixtures and C1 pins the DELTA between two back-to-back calls
--     (the second sends nothing) rather than an absolute count.
--  ② A booking is inserted directly at its status with one stamp already `p_age` old — the
--     product shape after the edge's `set(stamp)` and a lost `notify()`. `scheduled_at` is an hour
--     ahead so nothing about the late protocol applies.
--  ③ The ask row the edge would have written is modelled by its exact insert
--     (`index.ts:80-81`: profile_id · kind 'booking' · title · body · ref_id).
set client_min_messages = warning;

create or replace function t_ask_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid, p_status booking_status,
                                    p_side text, p_age interval, p_club uuid default null) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at, club_session_id)
  values (p_owner, p_dog, p_runner, p_route, p_status, now() + interval '1 hour', 5.0,
          9900, 15000, 0, 24900, 9900,
          case when p_side in ('owner', 'both') then now() - p_age end,
          case when p_side in ('runner', 'both') then now() - p_age end,
          p_club)
  returning id into v;
  return v;
end $$;

create or replace function t_asks(p_bk uuid, p_who uuid) returns int
language sql as $$
  select count(*)::int from notifications
  where ref_id = p_bk and profile_id = p_who and title = '인계 확인 요청'
$$;

do $$
declare
  o uuid; rr uuid; d uuid; rt uuid; o2 uuid; d2 uuid;
  bk1 uuid; bk1b uuid; bk2 uuid; bk3 uuid; bk4 uuid; bk4b uuid; bk5 uuid; bk7 uuid; bk9 uuid; bk9b uuid; bk uuid;
  v_club uuid; v_sess uuid;
  n1 int; n2 int; v_n int; v_bad text; v_msg text; v_src text; v_oid oid; v_key bigint; v_lock int; v_arm int;
  s booking_status; v_note text := '';
  r record;
begin
  o := t_user('ask_owner', 'owner'); rr := t_user('ask_runner', 'runner'); d := t_dog(o, 'ask-dog'); rt := t_route('ask 코스');
  o2 := t_user('ask_owner2', 'owner'); d2 := t_dog(o2, 'ask-dog-2');
  -- ① drain: whatever earlier suites left for arms ⓐ/ⓑ is settled before any count is read
  begin perform sweep_run_end_recovery(); exception when others then null; end;

  -- ---------- [0181-C1] a missing ask is re-sent ONCE, to the runner, with the edge's strings, and counted ----------
  v_bad := '';
  bk1  := t_ask_bk(o, d, rt, rr, 'confirmed',      'owner', interval '10 minutes');
  bk1b := t_ask_bk(o, d, rt, rr, 'runner_enroute', 'owner', interval '10 minutes');
  if t_asks(bk1, rr) <> 0 or t_asks(bk1b, rr) <> 0 then v_bad := v_bad || ' an-ask-existed-before-the-sweep'; end if;
  begin n1 := sweep_run_end_recovery(); exception when others then n1 := -1; v_bad := v_bad || ' sweep-RAISED [' || sqlerrm || ']'; end;
  if t_asks(bk1, rr) <> 1 then v_bad := v_bad || ' confirmed: asks-to-runner=' || t_asks(bk1, rr); end if;
  if t_asks(bk1b, rr) <> 1 then v_bad := v_bad || ' runner_enroute: asks-to-runner=' || t_asks(bk1b, rr); end if;
  if t_asks(bk1, o) <> 0 then v_bad := v_bad || ' the-OWNER-who-stamped-was-asked(' || t_asks(bk1, o) || ')'; end if;
  select * into r from notifications where ref_id = bk1 and profile_id = rr and title = '인계 확인 요청' limit 1;
  if r.kind::text is distinct from 'booking' then v_bad := v_bad || ' kind=' || coalesce(r.kind::text,'NULL'); end if;
  if r.body is distinct from '상대방이 인계를 확인했어요 — 확인해주세요' then v_bad := v_bad || ' body=' || coalesce(left(r.body,60),'NULL'); end if;
  -- once: the row it wrote is the row it looks for
  begin n2 := sweep_run_end_recovery(); exception when others then n2 := -1; v_bad := v_bad || ' second-sweep-RAISED [' || sqlerrm || ']'; end;
  if t_asks(bk1, rr) <> 1 or t_asks(bk1b, rr) <> 1 then v_bad := v_bad || ' re-sent-twice(' || t_asks(bk1, rr) || '/' || t_asks(bk1b, rr) || ')'; end if;
  -- counted: the first call's return exceeds the second's by exactly the two asks it sent (①)
  if (n1 - n2) is distinct from 2 then v_bad := v_bad || ' return-delta=' || coalesce((n1 - n2)::text,'NULL') || ' (expected 2)'; end if;
  if v_bad = '' then call _pass('ask','0181-C1 한쪽(보호자)만 확인하고 알림 행이 없는 예약 — confirmed·runner_enroute 둘 다 러너에게 「인계 확인 요청」이 1회 다시 가고(찍은 보호자에겐 안 감), 제목·본문·kind가 엣지와 같고, 반환값에 센다; 두 번째 스윕은 다시 보내지 않는다');
  else v_msg := v_bad; call _fail('ask','0181-C1 resend-once', v_msg); end if;

  -- ---------- [0181-C2] the runner stamped ⇒ the OWNER is asked, the runner is not ----------
  v_bad := '';
  bk2 := t_ask_bk(o2, d2, rt, rr, 'confirmed', 'runner', interval '10 minutes');
  perform sweep_run_end_recovery();
  if t_asks(bk2, o2) <> 1 then v_bad := v_bad || ' asks-to-owner=' || t_asks(bk2, o2); end if;
  if t_asks(bk2, rr) <> 0 then v_bad := v_bad || ' the-RUNNER-who-stamped-was-asked(' || t_asks(bk2, rr) || ')'; end if;
  if v_bad = '' then call _pass('ask','0181-C2 러너만 확인한 예약 — 보호자에게 가고 찍은 러너에겐 안 간다 (상대방 = 아직 안 찍은 쪽)');
  else v_msg := v_bad; call _fail('ask','0181-C2 counterparty', v_msg); end if;

  -- ---------- [0181-C3] a present ask is NOT re-sent ----------
  v_bad := '';
  bk3 := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '10 minutes');
  -- [0183] the edge's row names the booking's cycle (bookings.handoff_cycle_id, minted on insert by
  -- the cycle trigger); an ask without it is LEGACY and no longer counts as this cycle's — 214 E2
  -- owns that rule. Suite-update law: this fixture models the new edge.
  insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)      -- ③ the edge's row
  values (rr, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk3, (select handoff_cycle_id from bookings where id = bk3));
  perform sweep_run_end_recovery();
  if t_asks(bk3, rr) <> 1 then v_bad := v_bad || ' asks-to-runner=' || t_asks(bk3, rr) || ' (the edge''s row was there; expected exactly 1)'; end if;
  if v_bad = '' then call _pass('ask','0181-C3 엣지의 알림 행이 이미 있으면 다시 보내지 않는다 (1행 그대로)');
  else v_msg := v_bad; call _fail('ask','0181-C3 present-ask', v_msg); end if;

  -- ---------- [0181-C4] an EARLIER cycle's ask does not count; one inside the skew does ----------
  v_bad := '';
  bk4 := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '10 minutes');
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)              -- a previous cycle: 20 min before this stamp
  values (rr, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk4, now() - interval '30 minutes');
  bk4b := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '10 minutes');
  -- [0183] this cycle's own ask (it carries the cycle id); the 30-min-old row above carries NONE —
  -- since 0183 that, not its age, is what makes it another cycle's
  insert into notifications (profile_id, kind, title, body, ref_id, created_at, handoff_cycle_id)   -- clock skew: 4 min before this stamp, THIS cycle
  values (rr, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk4b, now() - interval '14 minutes', (select handoff_cycle_id from bookings where id = bk4b));
  perform sweep_run_end_recovery();
  if t_asks(bk4, rr) <> 2 then v_bad := v_bad || ' previous-cycle: asks=' || t_asks(bk4, rr) || ' (expected 2 — the old ask does not answer this stamp)'; end if;
  if t_asks(bk4b, rr) <> 1 then v_bad := v_bad || ' within-skew: asks=' || t_asks(bk4b, rr) || ' (expected 1 — a slightly earlier row is this stamp''s ask)'; end if;
  if v_bad = '' then call _pass('ask','0181-C4 이전 사이클의 알림 행(사이클 id 없음)은 이 스탬프의 요청이 아니다 → 다시 보냄; 이 사이클의 id를 지닌 행은 요청으로 친다 → 안 보냄 [0183: 시각이 아니라 id로 가른다]');
  else v_msg := v_bad; call _fail('ask','0181-C4 earlier-cycle', v_msg); end if;

  -- ---------- [0181-C5] the timing gate: not before five minutes ----------
  v_bad := '';
  bk5 := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '2 minutes');
  perform sweep_run_end_recovery();
  if t_asks(bk5, rr) <> 0 then v_bad := v_bad || ' asked-at-2-minutes(' || t_asks(bk5, rr) || ')'; end if;
  update bookings set owner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk5;
  perform sweep_run_end_recovery();
  if t_asks(bk5, rr) <> 1 then v_bad := v_bad || ' not-asked-at-6-minutes(' || t_asks(bk5, rr) || ')'; end if;
  if v_bad = '' then call _pass('ask','0181-C5 찍은 지 2분엔 안 보내고 6분엔 보낸다 (ASK_AFTER 5분)');
  else v_msg := v_bad; call _fail('ask','0181-C5 timing', v_msg); end if;

  -- ---------- [0181-C6] every status that cannot reach picked_up is never touched; both stamps ⇒ nothing; no runner ⇒ nothing ----------
  v_bad := '';
  for s in select unnest(enum_range(null::booking_status)) loop
    if s in ('confirmed', 'runner_enroute') then continue; end if;   -- the live pair, C1's subject
    begin
      bk := t_ask_bk(o, d, rt, rr, s, 'owner', interval '10 minutes');
      perform sweep_run_end_recovery();
      if t_asks(bk, rr) <> 0 or t_asks(bk, o) <> 0 then v_bad := v_bad || ' ' || s::text || ':asked(' || t_asks(bk, rr) || '/' || t_asks(bk, o) || ')'; end if;
    exception when others then
      -- a status the fixture cannot even insert with a stamp is unreachable for the sweep too;
      -- recorded, not red — but it is NOT evidence about that status (see the pass line)
      v_note := v_note || ' ' || s::text || '[insert refused: ' || left(sqlerrm, 40) || ']';
    end;
  end loop;
  begin
    bk := t_ask_bk(o, d, rt, rr, 'confirmed', 'both', interval '10 minutes');
    perform sweep_run_end_recovery();
    if t_asks(bk, rr) <> 0 or t_asks(bk, o) <> 0 then v_bad := v_bad || ' both-stamps:asked'; end if;
  exception when others then v_bad := v_bad || ' both-stamps-fixture: [' || sqlerrm || ']'; end;
  begin
    bk := t_ask_bk(o, d, rt, null, 'confirmed', 'owner', interval '10 minutes');
    perform sweep_run_end_recovery();
    if t_asks(bk, o) <> 0 then v_bad := v_bad || ' no-runner:owner-asked'; end if;
    if exists (select 1 from notifications where ref_id = bk and title = '인계 확인 요청') then v_bad := v_bad || ' no-runner:someone-asked'; end if;
  exception when others then v_bad := v_bad || ' no-runner: sweep-or-fixture RAISED [' || sqlerrm || ']'; end;
  if v_bad = '' then call _pass('ask','0181-C6 enum의 나머지 열넷(배정 전 다섯·picked_up·active·completed·취소 둘·만료·no_show·incident_review·refund_pending) 한쪽 스탬프가 있어도 안 건드린다; 양쪽 스탬프 ⇒ 없음; 러너 없음 ⇒ 없음, raise 없음' || case when v_note <> '' then ' ⚠ 픽스처 불가:' || v_note else '' end);
  else v_msg := v_bad; call _fail('ask','0181-C6 never-touched', v_msg); end if;

  -- ---------- [0181-C7] a CLUB booking is swept — the pickup ask is the same edge action in both worlds ----------
  v_bad := '';
  begin
    insert into clubs (name, district, host_profile_id) values ('ask 클럽', '반포동', rr) returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (v_club, rr, now() + interval '1 hour', 'ask 집결지') returning id into v_sess;
    bk7 := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '10 minutes', v_sess);
    perform sweep_run_end_recovery();
    if t_asks(bk7, rr) <> 1 then v_bad := v_bad || ' club: asks-to-runner=' || t_asks(bk7, rr); end if;
    if t_asks(bk7, o) <> 0 then v_bad := v_bad || ' club: owner-asked'; end if;
  exception when others then v_bad := v_bad || ' club fixture/sweep RAISED [' || sqlerrm || ']'; end;
  if v_bad = '' then call _pass('ask','0181-C7 클럽 세션 예약도 쓸린다 — 러너에게 1회, 보호자에겐 없음 (ⓐ/ⓑ의 club 제외는 런 종료의 것, 인계 요청은 양쪽 세계가 같은 엣지)');
  else v_msg := v_bad; call _fail('ask','0181-C7 club', v_msg); end if;

  -- ---------- [0181-C9] an ask addressed to the OTHER party does not silence the counterparty's re-send (the profile_id conjunct) ----------
  -- the shape the cold review measured: owner stamps → the edge asks the runner → a re-match resets
  -- both stamps and leaves that row → the runner stamps first → THAT ask is the lost one. The old
  -- row is inside the skew and carries the right title and booking; only its profile_id says it is
  -- not the owner's ask. Without the conjunct the owner is never asked (measured: 0 candidates).
  v_bad := '';
  bk9 := t_ask_bk(o2, d2, rt, rr, 'confirmed', 'runner', interval '10 minutes');           -- the runner stamped: the OWNER is owed the ask
  -- [0183] both wrong-party rows carry THIS cycle's id, so the only thing that makes them not the
  -- counterparty's ask is the recipient — the property this pin exists for
  insert into notifications (profile_id, kind, title, body, ref_id, created_at, handoff_cycle_id)
  values (rr, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk9, now() - interval '8 minutes', (select handoff_cycle_id from bookings where id = bk9));   -- an ask to the RUNNER, this cycle
  bk9b := t_ask_bk(o, d, rt, rr, 'confirmed', 'owner', interval '10 minutes');            -- the mirror: the owner stamped, an ask to the OWNER exists
  insert into notifications (profile_id, kind, title, body, ref_id, created_at, handoff_cycle_id)
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk9b, now() - interval '8 minutes', (select handoff_cycle_id from bookings where id = bk9b));
  perform sweep_run_end_recovery();
  if t_asks(bk9, o2) <> 1 then v_bad := v_bad || ' runner-stamped: owner-asks=' || t_asks(bk9, o2) || ' (an ask to the runner is not the owner''s ask)'; end if;
  if t_asks(bk9b, rr) <> 1 then v_bad := v_bad || ' owner-stamped: runner-asks=' || t_asks(bk9b, rr) || ' (an ask to the owner is not the runner''s ask)'; end if;
  if v_bad = '' then call _pass('ask','0181-C9 상대가 아닌 쪽에게 간 알림 행(스큐 안, 같은 제목·예약)은 상대의 요청이 아니다 — 러너가 찍었으면 보호자에게, 보호자가 찍었으면 러너에게 여전히 간다 (profile_id 조건)');
  else v_msg := v_bad; call _fail('ask','0181-C9 other-party-ask', v_msg); end if;

  -- ---------- [0181-C8] deployed shape: definer/search_path/ACL, the job lock before any arm and HELD after the call, the deny-list, the title ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then v_bad := ' NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL 기본값'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      v_lock := position('pg_try_advisory_xact_lock(hashtextextended(''sweep_run_end_recovery'', 0))' in v_src);
      v_arm  := position('for r in' in v_src);
      if (v_lock > 0) is distinct from true then v_bad := v_bad || ' 잡 락 없음'; end if;
      if (v_lock > 0 and v_arm > 0 and v_lock < v_arm) is distinct from true then v_bad := v_bad || ' 잡 락이 첫 팔 뒤'; end if;
      if (v_src ~ 'pg_advisory_unlock') is distinct from false then v_bad := v_bad || ' 세션 unlock 있음'; end if;
      if (v_src ~ 'c_ask_title constant text := ''인계 확인 요청''') is distinct from true then v_bad := v_bad || ' 제목이 엣지와 다르다'; end if;
      if (v_src ~ 'nt\.title = c_ask_title') is distinct from true then v_bad := v_bad || ' 제목으로 매칭하지 않는다'; end if;
      if (v_src ~ 'nt\.profile_id = x\.counterparty') is distinct from true then v_bad := v_bad || ' 상대 profile_id로 매칭하지 않는다'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
      -- [0182] arm ⓓ adds a third handler; ≥ 2 keeps THIS file's property (ⓑ and ⓒ each catch their
      -- own row) — 213 D7 pins the exact count. Suite-update law: the pin moved with the behaviour.
      if v_n < 2 then v_bad := v_bad || ' 행 단위 예외 팔 수=' || v_n || '(ⓑ·ⓒ 최소 2개)'; end if;
      if (v_src ~ '\(b\.owner_confirmed_handoff_at is null\) <> \(b\.runner_confirmed_handoff_at is null\)') is distinct from true then v_bad := v_bad || ' 정확히-한쪽 술어 없음'; end if;
      if (v_src ~ 'b\.status not in \(''draft''' and v_src ~ '''matching''' and v_src ~ '''runner_pending''' and v_src ~ '''picked_up''' and v_src ~ '''completed''' and v_src ~ '''incident_review''' and v_src ~ '''refund_pending''' and v_src ~ '''no_show''') is distinct from true then v_bad := v_bad || ' deny-list에 빠진 상태 있음'; end if;
      if (v_src ~ 'b\.status in \(''confirmed''') is distinct from false then v_bad := v_bad || ' 라이브 allow-list 있음'; end if;
      if (v_src ~ 'b\.runner_id is not null') is distinct from true then v_bad := v_bad || ' runner 조건 없음'; end if;
      -- ⚠ [0193] 2 → 3. Arm ⓕ (0193 §D, the strand's ops bell) is marketplace-scoped for arms
      -- ⓐ/ⓑ's reason — a club run ends by the host's stop, not by `end_run_tx` (0144:94) — so it
      -- carries the conjunct too. What this line owns is unchanged: 「the run-end arms are
      -- marketplace-only and arm ⓒ deliberately is not」. Updated in 0193 rather than left to fail
      -- for a true reason (the house law); 224 `0193-R4` owns the new arm's own property.
      select count(*) into v_n from regexp_matches(v_src, 'club_session_id is null', 'g');
      if v_n is distinct from 3 then v_bad := v_bad || ' club 범위 조건 수=' || v_n || '(ⓐ/ⓑ/ⓕ의 3개여야)'; end if;
    end if;
  end if;
  -- the job lock is a TRANSACTION lock and this block is one transaction: still held after the calls above
  v_key := hashtextextended('sweep_run_end_recovery', 0);
  select count(*) into v_n from pg_locks l where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1 and l.classid = ((v_key >> 32) & 4294967295)::oid and l.objid = (v_key & 4294967295)::oid;
  if v_n < 1 then v_bad := v_bad || ' job-lock-not-held-after-the-call(' || v_n || ')'; end if;
  if v_bad = '' then call _pass('ask','0181-C8 배포 형태 — definer·search_path·ACL(service_role만); try 잡 락이 첫 팔 앞에 있고 호출 뒤에도 잡혀 있다(xact); 세션 unlock 없음; 제목·상대 profile_id 매칭·정확히-한쪽·종결 deny-list·runner 조건; ⓒ에 ⓑ와 같은 행 단위 예외 팔; club 제외는 ⓐ/ⓑ 두 곳만');
  else v_msg := v_bad; call _fail('ask','0181-C8 shape', v_msg); end if;
end $$;
