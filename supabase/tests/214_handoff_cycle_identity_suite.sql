-- ═══ 214 — 0183: cycle identity · pending ops escalation · verdicts only for named errors — 0183-E1…E6, tag `hcy` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS (codex re-review of 0182, REJECT/3):
--   · #1 an ask names the handoff cycle it belongs to (`handoff_cycle_id`, minted by the database);
--     an ask naming a cycle the booking has left is REFUSED at insert; the sweep matches by id, so a
--     delayed old-cycle ask cannot suppress the new cycle's re-send; an ask with no id (legacy) never
--     counts and the row is asked once more.
--   · #2 party delivery and ops delivery are two records: an empty roster leaves the ops escalation
--     PENDING and later ticks deliver it exactly once, without telling the parties again.
--   · #3 the reconciler marks a tick `failed` only on classes 22 · 23 · P0; 53 and 58 (and 40)
--     re-raise, the tick stays `sent` and reconciles once the cause is gone.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE: 0182's other properties (213), arm ⓒ's (212), the
--   race arms (RL/RL2), the client's route for the escalation title (app/test).
-- ⚠ NAMED GAPS: the apply-time BACKFILL is unreachable by this harness (migrations apply on an
--   empty `bookings`, so 0183's UPDATE touches no row and VERIFY's arm is vacuous); E2's legacy
--   touch is the runtime belt and is measured. And the cycle id is readable by the booking's own
--   parties, so the guard authenticates the CYCLE, not the writer — a party could hand-write an
--   ask carrying it (`noti party insert`), as they could already suppress by title before 0183.
--
-- ─── MUTATION MAP — measured 2026-09-18 on the final file (after the cold review's fixes), not predicted ───
--   Lab: an md5-identical copy of 0183 (+ tests, + functions and app/src for the deno side), every
--   plant `&&`-chained to its run, the control observed first (1294 / 0; deno 16 / 0 for the edge
--   file). 「demoted」 = 0183's VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where the VERIFY aborts the apply before any suite runs.
--   (i)    ⓒ's candidate matches by timestamp again  → E6 (후보 id 매칭 없음 · 시각 매칭이 남아 있다)
--          + 213 D7/D8; un-demoted ABORTS.
--   (ii)   ⓒ's re-check matches by timestamp again   → E1 + E2 (the legacy ask masks) + E6 + 213
--          D1/D3/D8; un-demoted ABORTS.
--   (iii)  the guard no longer refuses a stale cycle → E1 (delayed-old-cycle-ask-ACCEPTED) + E3.
--   (iii-b) the guard trigger not created            → E1 + E3; un-demoted ABORTS (GUARD-NOT-ENABLED).
--   (v)    a stamped insert mints nothing           → E1 + E3 + E6 (one-sided rows without an id) +
--          212 C3/C4 (their edge-ask fixtures resolve to NULL and stop counting).
--   (vi)   a first stamp / a legacy touch mints nothing → E2 (the sweep did not mint) + E3 + E6.
--   (vii)  a re-match / a reset keeps the identity  → E1 (re-match-did-not-mint) + E3.
--   (viii) the ops record set regardless of delivery (0182 again) → E4 + E6 + 213 D4; un-demoted
--          ABORTS. Codex's #2.
--   (ix)   arm ⓔ deleted                             → E4 (after-provisioning ops-rows=0) + E6;
--          un-demoted ABORTS.
--   (x)    ⓔ delivers but never records             → E4 (fourth-tick ops-rows=2); un-demoted ABORTS.
--   (xi)   ⓔ tells the owner again                  → E4 (parties-told-again) + 213 D4.
--   (xii)  ⓔ's CANDIDATE no longer requires one-sided → 1294 / 0, NOTHING — because ⓔ re-checks
--          one-sidedness on the locked row (cold review #6's fix), the candidate's conjunct alone is
--          not load-bearing. Not a blind pin: (xii-b) both sites removed → E4
--          (confirmed-before-provisioning: ops-told=1). The re-check owns the property.
--   (xiii) 0182's transient allow-list back         → E5 + 213 D5; un-demoted ABORTS. Codex's #3.
--   (xiv)  everything becomes a verdict              → E5 + 213 D5.
--   (xv)   nothing becomes a verdict                 → E5 (22003/P0001 stay `sent`) + 213 D5.
--   (xvi)  an unnamed fault ABORTS the call (0183's own first draft, cold review #3) → E5 (the
--          call RAISED · the sibling did not reconcile · the prune never ran) + 213 D5;
--          un-demoted ABORTS (UNNAMED-FAULT-ABORTS-THE-CALL).
--   (xvii) the re-send carries no identity          → E1 + E2 + E6 + 212 C1 + 213 D1/D8 (asked every
--          tick); un-demoted ABORTS.
--   (xviii) a legacy row is never given an identity → E2 + E6. ⚠ Un-demoted the apply does NOT abort
--          — the VERIFY's arm matches the `returning … into v_cid` TEXT, which the plant leaves
--          behind an `if false`; E2 is the owner, a behavioural pin. A source arm cannot see a
--          condition; recorded.
--   (xix)  the parse handler swallows every class again (cold review #2) → E5 (source arm); the
--          behaviour is unreachable — the cast site cannot be faulted from outside; un-demoted ABORTS.
--   (xx)   no_response no longer skips answered ticks → E5 (42883/…: the faulty tick became
--          no_response — a lie beside its answer); un-demoted ABORTS.
--   (xxi)  ⓔ neither locks nor looks again (cold review #6) → E6 (행 락 3 · c_dead 5 · runner 3);
--          un-demoted ABORTS. Behaviour: the review measured a confirm inside the loop still paging
--          ops without the lock; not re-measured here (two sessions inside a loop — RL-class).
--   (xxii) the guard no longer checks WHICH booking (cold review #4) → E3 (ANOTHER-bookings-current-
--          id-was-ACCEPTED); un-demoted ABORTS (GUARD-DOES-NOT-CHECK-WHICH-BOOKING).
--   Deno (the edge file, control 16/0): the ask sent without the id → 2 red (`[0183]`); the
--   post-stamp re-read no longer selecting the id → red at TYPE-CHECK (TS2339) before any pin
--   runs; the ask sourced from the STALE pre-stamp snapshot (cold review #5) → 1 red (`[0183]
--   … read after the stamp`) — the fixture now leaves the agreement zone.
--   Not planted: the backfill (unreachable — the harness applies on an empty table; VERIFY's arm
--   is vacuous; E2's legacy touch is the measured belt); `_guard_booking_cols` (0058's).
-- ─── FIXTURE NOTES ───
--  ① `t_ask_bk` (212) inserts a row WITH a stamp, so `_handoff_cycle_ins` mints its identity at
--     birth; an edge ask is modelled by the new edge's insert (title · booking · counterparty ·
--     the booking's current `handoff_cycle_id`); a LEGACY ask by the same row with NULL.
--  ② A row that predates 0183 and was somehow missed by the backfill is modelled by disabling the
--     cycle trigger for one statement and nulling the id (E2) — a state the trigger otherwise makes
--     unreachable, which is why the fixture has to reach around it.
--  ③ The reconciler's fault stand-in is a temporary trigger on the tick table that raises with an
--     errcode taken from a setting, only on the main path's `accepted` write (213 D5's shape).
set client_min_messages = warning;

do $$
declare
  o uuid; r1 uuid; r2 uuid; d uuid; rt uuid; opsp uuid;
  bk1 uuid; bk1b uuid; bk2 uuid; bk2b uuid; bk2c uuid; bk3 uuid; bk3b uuid; bk4 uuid; bk4b uuid; bk uuid;
  t5 uuid; t6 uuid; t7 uuid; v_req int; v_stale uuid; v_old uuid;
  v_a uuid; v_b uuid; v_c uuid; v_bad text; v_msg text; v_err text; v_n int; v_src text; v_oid oid;
  r record;
begin
  o := t_user('hcy_owner', 'owner'); r1 := t_user('hcy_runner1', 'runner'); r2 := t_user('hcy_runner2', 'runner');
  d := t_dog(o, 'hcy-dog'); rt := t_route('hcy 코스'); opsp := t_user('hcy_ops', 'owner');
  delete from ops_recipients where event_class = 'handoff_unanswered';                       -- E4 starts from an empty roster
  begin perform sweep_run_end_recovery(); exception when others then null; end;              -- drain

  -- ---------- [0183-E1] a DELAYED old-cycle ask is refused; the new cycle is re-sent; the new cycle's own ask is honoured ----------
  v_bad := '';
  bk1 := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '9 minutes');                 -- cycle A, born with r1's stamp
  select handoff_cycle_id into v_a from bookings where id = bk1;
  if v_a is null then v_bad := v_bad || ' cycle-A-not-minted-on-insert'; end if;
  insert into notifications (profile_id, kind, title, body, ref_id, created_at, handoff_cycle_id)  -- the edge's ask of cycle A, delivered
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1, now() - interval '9 minutes', v_a);
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk1;   -- re-match: cycle B
  select handoff_cycle_id into v_b from bookings where id = bk1;
  if v_b is null or v_b = v_a then v_bad := v_bad || ' re-match-did-not-mint-a-new-cycle'; end if;
  update bookings set runner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk1;   -- r2 confirms; THEIR ask is lost
  -- the DELAYED old-cycle ask arrives NOW (dated after the re-match), naming cycle A: refused
  begin
    insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
    values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1, v_a);
    v_bad := v_bad || ' delayed-old-cycle-ask-ACCEPTED';
  exception when others then
    if sqlerrm !~ 'stale_handoff_cycle' then v_bad := v_bad || ' guard raised something else: [' || sqlerrm || ']'; end if;
  end;
  perform sweep_run_end_recovery();
  if t_asks(bk1, o) <> 2 then v_bad := v_bad || ' owner-asks=' || t_asks(bk1, o) || ' (expected 2: cycle A''s + the re-send)'; end if;
  select count(*) into v_n from notifications where ref_id = bk1 and profile_id = o and title = '인계 확인 요청' and handoff_cycle_id = v_b;
  if v_n <> 1 then v_bad := v_bad || ' re-send-carries-cycle-B=' || v_n; end if;
  perform sweep_run_end_recovery();
  if t_asks(bk1, o) <> 2 then v_bad := v_bad || ' re-sent-twice(' || t_asks(bk1, o) || ')'; end if;
  -- the control: the NEW cycle's own ask (id B) exists ⇒ nothing to re-send
  bk1b := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '9 minutes');
  select handoff_cycle_id into v_a from bookings where id = bk1b;
  insert into notifications (profile_id, kind, title, body, ref_id, created_at, handoff_cycle_id)
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1b, now() - interval '9 minutes', v_a);
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk1b;
  select handoff_cycle_id into v_b from bookings where id = bk1b;
  update bookings set runner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk1b;
  insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)               -- cycle B's own edge ask
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1b, v_b);
  perform sweep_run_end_recovery();
  if t_asks(bk1b, o) <> 2 then v_bad := v_bad || ' control: owner-asks=' || t_asks(bk1b, o) || ' (expected 2: A''s + B''s own; 3 = re-sent despite B''s ask)'; end if;
  if v_bad = '' then call _pass('hcy','0183-E1 재배정 뒤에 늦게 도착한 이전 사이클(A)의 요청은 삽입에서 거절되고(stale_handoff_cycle), 새 사이클(B)의 요청이 B의 id를 지니고 1회 다시 간다; B 자신의 요청이 있으면 안 보낸다');
  else v_msg := v_bad; call _fail('hcy','0183-E1 delayed-old-cycle', v_msg); end if;

  -- ---------- [0183-E2] the LEGACY rule: an ask with no cycle id never counts; the row is asked once more, never twice ----------
  v_bad := '';
  bk2 := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '10 minutes');                 -- born identified
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)                -- a legacy ask (pre-0183 / the old edge): NULL id, inside 0182's old window
  values (r1, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk2, now() - interval '8 minutes');
  perform sweep_run_end_recovery();
  if t_asks(bk2, r1) <> 2 then v_bad := v_bad || ' legacy-ask: runner-asks=' || t_asks(bk2, r1) || ' (expected 2: the legacy one + one re-send)'; end if;
  perform sweep_run_end_recovery();
  if t_asks(bk2, r1) <> 2 then v_bad := v_bad || ' legacy-ask: re-sent-twice(' || t_asks(bk2, r1) || ')'; end if;
  -- the pre-migration RE-MATCH with the same owner recipient (codex's regression): a legacy ask to the
  -- owner, then a re-match and the new runner's stamp — the legacy ask carries no id, so it cannot mask
  bk2b := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '9 minutes');
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk2b, now() - interval '9 minutes');
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk2b;
  update bookings set runner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk2b;
  perform sweep_run_end_recovery();
  if t_asks(bk2b, o) <> 2 then v_bad := v_bad || ' pre-migration re-match: owner-asks=' || t_asks(bk2b, o) || ' (expected 2)'; end if;
  -- a row the backfill somehow missed (② — the trigger disabled for one statement): the sweep mints an
  -- identity on meeting it, asks once with it, and never again
  bk2c := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '10 minutes');
  alter table bookings disable trigger _handoff_cycle;
  update bookings set handoff_cycle_id = null where id = bk2c;
  alter table bookings enable trigger _handoff_cycle;
  if (select handoff_cycle_id from bookings where id = bk2c) is not null then v_bad := v_bad || ' fixture: could not null the identity'; end if;
  perform sweep_run_end_recovery();
  select handoff_cycle_id into v_c from bookings where id = bk2c;
  if v_c is null then v_bad := v_bad || ' legacy-row: the sweep did not mint an identity'; end if;
  select count(*) into v_n from notifications where ref_id = bk2c and profile_id = r1 and title = '인계 확인 요청' and handoff_cycle_id = v_c;
  if v_n <> 1 then v_bad := v_bad || ' legacy-row: ask-with-the-minted-id=' || v_n; end if;
  perform sweep_run_end_recovery();
  if t_asks(bk2c, r1) <> 1 then v_bad := v_bad || ' legacy-row: asked-again(' || t_asks(bk2c, r1) || ')'; end if;
  if v_bad = '' then call _pass('hcy','0183-E2 레거시 규칙 — 사이클 id 없는 요청 행은 이 사이클의 것이 아니다: 한 번 더 보내고(중복 푸시), 두 번은 아니다; 이전 재배정(같은 보호자 수신자)도 같은 규칙; 백필을 놓친 행은 스윕이 만나는 순간 id를 발급한다');
  else v_msg := v_bad; call _fail('hcy','0183-E2 legacy', v_msg); end if;

  -- ---------- [0183-E3] the trigger mints on every cycle start and keeps otherwise; the guard refuses a mismatch and passes NULL/match; all enabled ----------
  v_bad := '';
  bk3 := t_ask_bk(o, d, rt, r1, 'confirmed', 'none', interval '10 minutes');
  if (select handoff_cycle_id from bookings where id = bk3) is not null then v_bad := v_bad || ' no-stamp-insert-minted'; end if;
  update bookings set owner_confirmed_handoff_at = now() where id = bk3;                        -- a FIRST stamp mints
  select handoff_cycle_id into v_a from bookings where id = bk3;
  if v_a is null then v_bad := v_bad || ' first-stamp-did-not-mint'; end if;
  update bookings set km = 6.0 where id = bk3;                                                   -- unrelated: keeps
  if (select handoff_cycle_id from bookings where id = bk3) is distinct from v_a then v_bad := v_bad || ' unrelated-update-changed-the-identity'; end if;
  update bookings set handoff_cycle_id = gen_random_uuid() where id = bk3;                       -- a statement cannot move it
  if (select handoff_cycle_id from bookings where id = bk3) is distinct from v_a then v_bad := v_bad || ' a-statement-moved-the-identity'; end if;
  update bookings set handoff_escalated_at = now(), handoff_ops_alerted_at = now() where id = bk3;   -- the server's records
  update bookings set runner_id = r2 where id = bk3;                                             -- runner change: new identity, records cleared
  select handoff_cycle_id into v_b from bookings where id = bk3;
  if v_b is null or v_b = v_a then v_bad := v_bad || ' runner-change-did-not-mint'; end if;
  if (select handoff_escalated_at is not null or handoff_ops_alerted_at is not null from bookings where id = bk3) then v_bad := v_bad || ' runner-change-kept-a-record'; end if;
  update bookings set handoff_escalated_at = now(), handoff_ops_alerted_at = now() where id = bk3;
  update bookings set owner_confirmed_handoff_at = null where id = bk3;                          -- stamp reset: new identity, records cleared
  select handoff_cycle_id into v_c from bookings where id = bk3;
  if v_c is null or v_c = v_b then v_bad := v_bad || ' stamp-reset-did-not-mint'; end if;
  if (select handoff_escalated_at is not null or handoff_ops_alerted_at is not null from bookings where id = bk3) then v_bad := v_bad || ' stamp-reset-kept-a-record'; end if;
  -- the guard
  begin
    insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id) values (r1, 'booking', '인계 확인 요청', 'x', bk3, gen_random_uuid());
    v_bad := v_bad || ' guard: a-foreign-cycle-id-was-ACCEPTED';
  exception when others then if sqlerrm !~ 'stale_handoff_cycle' then v_bad := v_bad || ' guard raised something else: [' || sqlerrm || ']'; end if; end;
  begin
    insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id) values (r1, 'booking', '인계 확인 요청', 'x', bk3, v_c);
  exception when others then v_bad := v_bad || ' guard: the CURRENT id was refused [' || sqlerrm || ']'; end;
  -- ANOTHER live booking's current id: a real cycle, the wrong booking — the guard must check WHICH
  -- booking the ask names (cold review 0183 #4: without `b.id = new.ref_id` this passed and the
  -- whole suite stayed green)
  bk3b := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '1 minute');
  begin
    insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
    values (r1, 'booking', '인계 확인 요청', 'x', bk3, (select handoff_cycle_id from bookings where id = bk3b));
    v_bad := v_bad || ' guard: ANOTHER-bookings-current-id-was-ACCEPTED';
  exception when others then if sqlerrm !~ 'stale_handoff_cycle' then v_bad := v_bad || ' guard raised something else for another booking''s id: [' || sqlerrm || ']'; end if; end;
  begin
    insert into notifications (profile_id, kind, title, body, ref_id) values (r1, 'booking', '무슨 알림', 'x', bk3);
  exception when others then v_bad := v_bad || ' guard: a NULL id was refused [' || sqlerrm || ']'; end;
  select count(*) into v_n from pg_trigger where not tgisinternal and tgenabled = 'O'
     and ((tgrelid = 'public.bookings'::regclass and tgname in ('_handoff_cycle', '_handoff_cycle_ins')) or (tgrelid = 'public.notifications'::regclass and tgname = '_notification_cycle_guard'));
  if v_n <> 3 then v_bad := v_bad || ' triggers-enabled=' || v_n || '/3'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = '_notification_cycle_guard';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(guard)';
  elsif (v_src ~ 'b\.id = new\.ref_id and b\.handoff_cycle_id = new\.handoff_cycle_id') is distinct from true then v_bad := v_bad || ' 가드가 어느 예약인지 안 본다(소스)'; end if;
  if v_bad = '' then call _pass('hcy','0183-E3 트리거 — 스탬프 없는 삽입은 id 없음, 첫 스탬프·러너 변경·스탬프 리셋은 새 id(기록 두 개 초기화), 무관한 갱신과 어떤 문장도 id를 못 옮긴다; 가드 — 다른 사이클 id도, 다른 예약의 현재 id도 거절, 현재 id와 NULL은 통과; 트리거 셋 tgenabled=O');
  else v_msg := v_bad; call _fail('hcy','0183-E3 trigger+guard', v_msg); end if;

  -- ---------- [0183-E4] an empty roster leaves the ops escalation PENDING; provisioning delivers it exactly once; the parties are never told again ----------
  v_bad := '';
  bk4 := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '40 minutes');
  insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)                -- the ask was delivered; nobody acted
  values (r1, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk4, (select handoff_cycle_id from bookings where id = bk4));
  perform sweep_run_end_recovery();                                                              -- roster EMPTY
  if t_esc(bk4, o) <> 1 or t_esc(bk4, r1) <> 1 then v_bad := v_bad || ' parties-told=' || t_esc(bk4, o) || '/' || t_esc(bk4, r1); end if;
  if (select handoff_escalated_at from bookings where id = bk4) is null then v_bad := v_bad || ' party-record-not-set'; end if;
  if (select handoff_ops_alerted_at from bookings where id = bk4) is not null then v_bad := v_bad || ' ops-record-set-with-nobody-told'; end if;
  perform sweep_run_end_recovery();                                                              -- still empty: pending stays pending, parties untouched
  if t_esc(bk4, o) <> 1 or t_esc(bk4, r1) <> 1 then v_bad := v_bad || ' pending: parties-told-again(' || t_esc(bk4, o) || '/' || t_esc(bk4, r1) || ')'; end if;
  if (select handoff_ops_alerted_at from bookings where id = bk4) is not null then v_bad := v_bad || ' pending: ops-record-set-while-empty'; end if;
  insert into ops_recipients (profile_id, event_class) values (opsp, 'handoff_unanswered');       -- provisioned
  perform sweep_run_end_recovery();
  select count(*) into v_n from notifications where profile_id = opsp and ref_id = bk4 and kind = 'system';
  if v_n <> 1 then v_bad := v_bad || ' after-provisioning: ops-rows=' || v_n || ' (expected exactly 1)'; end if;
  if (select handoff_ops_alerted_at from bookings where id = bk4) is null then v_bad := v_bad || ' after-provisioning: ops-record-not-set'; end if;
  if t_esc(bk4, o) <> 1 or t_esc(bk4, r1) <> 1 then v_bad := v_bad || ' after-provisioning: parties-told-again(' || t_esc(bk4, o) || '/' || t_esc(bk4, r1) || ')'; end if;
  perform sweep_run_end_recovery();
  select count(*) into v_n from notifications where profile_id = opsp and ref_id = bk4 and kind = 'system';
  if v_n <> 1 then v_bad := v_bad || ' fourth-tick: ops-rows=' || v_n; end if;
  -- a pending row that got CONFIRMED before provisioning is not delivered to ops (nothing is stuck any more)
  delete from ops_recipients where profile_id = opsp;
  bk4b := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '40 minutes');
  perform sweep_run_end_recovery();                                                              -- escalated, ops pending
  update bookings set runner_confirmed_handoff_at = now() where id = bk4b;                        -- both stamps now
  insert into ops_recipients (profile_id, event_class) values (opsp, 'handoff_unanswered');
  perform sweep_run_end_recovery();
  select count(*) into v_n from notifications where profile_id = opsp and ref_id = bk4b and kind = 'system';
  if v_n <> 0 then v_bad := v_bad || ' confirmed-before-provisioning: ops-told=' || v_n; end if;
  -- a NEW cycle resets both records and escalates again (the roster present now delivers directly)
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk4;
  if (select handoff_escalated_at is not null or handoff_ops_alerted_at is not null from bookings where id = bk4) then v_bad := v_bad || ' new-cycle: a-record-survived'; end if;
  update bookings set owner_confirmed_handoff_at = now() - interval '40 minutes' where id = bk4;
  perform sweep_run_end_recovery();
  if t_esc(bk4, o) <> 2 then v_bad := v_bad || ' new-cycle: owner-told=' || t_esc(bk4, o) || ' (expected 2)'; end if;
  select count(*) into v_n from notifications where profile_id = opsp and ref_id = bk4 and kind = 'system';
  if v_n <> 2 then v_bad := v_bad || ' new-cycle: ops-rows=' || v_n || ' (expected 2)'; end if;
  if (select handoff_ops_alerted_at from bookings where id = bk4) is null then v_bad := v_bad || ' new-cycle: ops-record-not-set'; end if;
  delete from ops_recipients where profile_id = opsp;
  if v_bad = '' then call _pass('hcy','0183-E4 로스터가 비면 양측만 듣고 ops 승격은 PENDING(기록 NULL); 틱을 거듭해도 양측은 다시 안 듣는다; 구독 뒤 정확히 1회 전달·기록; 그 뒤 틱은 추가 없음; 구독 전에 확인이 끝난 행은 전달하지 않는다; 새 사이클은 두 기록을 지우고 다시 승격한다');
  else v_msg := v_bad; call _fail('hcy','0183-E4 ops-pending', v_msg); end if;

  -- ---------- [0183-E5] the reconciler never aborts: unnamed classes leave the tick `sent` (the sibling, the stale sweep and the prune still run); 22 · 23 · P0 are verdicts ----------
  v_bad := '';
  create or replace function t_hcy_tick_fault() returns trigger language plpgsql as $f$
  begin
    if new.id::text = current_setting('hcy.fault_tick', true) and new.outcome = 'accepted' then
      raise exception 'stand-in fault %', current_setting('hcy.fault_code', true) using errcode = current_setting('hcy.fault_code', true);
    end if;
    return new;
  end $f$;
  create trigger t_hcy_tick_fault before update on billing_key_dispatch_ticks for each row execute function t_hcy_tick_fault();
  -- a 40-day-old accepted row: the prune must still reach it whatever a sibling's fault is
  insert into billing_key_dispatch_ticks (outcome, due_count, sent_at, resolved_at) values ('accepted', 1, now() - interval '40 days', now() - interval '40 days') returning id into v_old;
  for r in select * from (values ('53200', 'retry'), ('58030', 'retry'), ('40P01', 'retry'), ('42883', 'retry'), ('22003', 'verdict'), ('P0001', 'verdict')) as x(code, kind) loop
    select 814000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 814000;
    -- the faulty tick, sent 5 minutes ago (past the no_response bound) WITH its answer on disk
    insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, v_req, now() - interval '5 minutes') returning id into t5;
    insert into net._http_response (id, status_code, content, timed_out, created)
    values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
    -- its healthy sibling
    insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 1, v_req + 500, now() - interval '1 minute') returning id into t6;
    insert into net._http_response (id, status_code, content, timed_out, created)
    values (v_req + 500, 200, '{"claimed":1,"revoked":1,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
    perform set_config('hcy.fault_tick', t5::text, true); perform set_config('hcy.fault_code', r.code, true);
    v_err := null;
    begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_err := sqlerrm; end;
    if v_err is not null then v_bad := v_bad || ' ' || r.code || ': the call RAISED [' || v_err || '] (an abort kills the siblings, the stale sweep and the prune)'; end if;
    if (select outcome from billing_key_dispatch_ticks where id = t6) is distinct from 'accepted' then v_bad := v_bad || ' ' || r.code || ': the sibling did not reconcile'; end if;
    if r.kind = 'retry' then
      if (select outcome from billing_key_dispatch_ticks where id = t5) is distinct from 'sent' then v_bad := v_bad || ' ' || r.code || ': tick=' || (select outcome from billing_key_dispatch_ticks where id = t5) || ' (expected sent — left as it is; no_response would be a lie, it HAS an answer)'; end if;
      perform set_config('hcy.fault_tick', '', true);                                          -- the cause is gone
      begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' ' || r.code || ': after-recovery RAISED [' || sqlerrm || ']'; end;
      if (select outcome || '/' || coalesce(claimed_count::text, 'NULL') from billing_key_dispatch_ticks where id = t5) is distinct from 'accepted/3' then v_bad := v_bad || ' ' || r.code || ': after-recovery ' || (select outcome || '/' || coalesce(claimed_count::text, 'NULL') from billing_key_dispatch_ticks where id = t5); end if;
    else
      if (select outcome from billing_key_dispatch_ticks where id = t5) is distinct from 'failed' or (select detail ~ ('reconciler could not read this answer: stand-in fault ' || r.code) from billing_key_dispatch_ticks where id = t5) is distinct from true then v_bad := v_bad || ' ' || r.code || ': ' || (select coalesce(outcome, 'NULL') || '/' || coalesce(left(detail, 60), '∅') from billing_key_dispatch_ticks where id = t5); end if;
      perform set_config('hcy.fault_tick', '', true);
    end if;
  end loop;
  -- the prune ran despite the faults (the old row is gone), and a sent tick with NO answer past the bound is still declared no_response
  if exists (select 1 from billing_key_dispatch_ticks where id = v_old) then v_bad := v_bad || ' the-prune-never-ran'; end if;
  select 814000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 814000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 1, v_req, now() - interval '5 minutes') returning id into t7;   -- no answer row
  perform set_config('hcy.fault_tick', '', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' control RAISED [' || sqlerrm || ']'; end;
  if (select outcome from billing_key_dispatch_ticks where id = t7) is distinct from 'no_response' then v_bad := v_bad || ' control: an unanswered stale tick is ' || (select outcome from billing_key_dispatch_ticks where id = t7) || ' (expected no_response — the exclusion must not blind the arm)'; end if;
  drop trigger t_hcy_tick_fault on billing_key_dispatch_ticks; drop function t_hcy_tick_fault();
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = 'reconcile_billing_key_dispatch_ticks';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(reconciler)';
  else
    if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' 판정은 22·23·P0에만이라는 필터 없음'; end if;
    if (v_src ~ 'not in \(''22'', ''23'', ''P0''\) then raise;') is distinct from false then v_bad := v_bad || ' 이름 없는 오류가 호출을 죽인다(raise)'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) in \(''22'', ''23'', ''P0''\) then v_body := null; else raise; end if;') is distinct from true then v_bad := v_bad || ' 본문 파싱 팔이 모든 클래스를 삼킨다'; end if;
    if (v_src ~ 'and not exists \(select 1 from net\._http_response h where h\.id = request_id\)') is distinct from true then v_bad := v_bad || ' no_response 팔이 답 있는 틱을 가린다'; end if;
  end if;
  if v_bad = '' then call _pass('hcy','0183-E5 53200·58030·40P01·42883 — 호출은 죽지 않고, 그 틱은 sent로 남고(답이 있으니 no_response도 아니다), 옆 틱은 같은 호출에 정리되고, 프룬도 돈다; 원인이 사라지면 accepted/3; 22003·P0001만 failed + 사유; 답 없는 오래된 틱은 여전히 no_response; 소스 — 판정 필터·본문 파싱 분류·no_response 제외');
  else v_msg := v_bad; call _fail('hcy','0183-E5 sqlstate-classes', v_msg); end if;

  -- ---------- [0183-E6] deployed shape ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then v_bad := ' NO-FUNCTION(sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' sweep: definer 아님'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' sweep: 클라 실행 가능'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep)';
    else
      if (v_src ~ 'nt\.handoff_cycle_id = b\.handoff_cycle_id\)') is distinct from true then v_bad := v_bad || ' 후보 id 매칭 없음'; end if;
      if (v_src ~ 'nt\.handoff_cycle_id = v_cid\)') is distinct from true then v_bad := v_bad || ' 재평가 id 매칭 없음'; end if;
      if (v_src ~ 'ASK_SKEW|handoff_cycle_at, ''-infinity''') is distinct from false then v_bad := v_bad || ' 시각 매칭이 남아 있다'; end if;
      if (v_src ~ 'returning handoff_cycle_id into v_cid') is distinct from true then v_bad := v_bad || ' 레거시 행 id 발급 없음'; end if;
      if (v_src ~ 'values \(v_cp, ''booking'', c_ask_title, c_ask_body, v_b\.id, v_cid\)') is distinct from true then v_bad := v_bad || ' 재전송이 id를 안 지닌다'; end if;
      if (v_src ~ 'handoff_ops_alerted_at = case when v_ops > 0 then now\(\) end') is distinct from true then v_bad := v_bad || ' ops 기록이 전달에 조건부가 아니다'; end if;
      if (v_src ~ 'and b\.handoff_ops_alerted_at is null') is distinct from true then v_bad := v_bad || ' pending ops 팔 없음'; end if;
      -- ⚠ [0193] 4 → 5. Arm ⓕ (0193 §D) catches its own row the same way: one poisoned booking
      -- must not silence the bell for every other stranded one (0116 B3 / 0182's shape). The
      -- property this line owns — 「every arm that writes catches its own row」 — is unchanged.
      select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
      if v_n <> 5 then v_bad := v_bad || ' 예외 팔 수=' || v_n || '(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ 5개여야)'; end if;
      select count(*) into v_n from regexp_matches(v_src, '= any\(c_dead\)', 'g');
      if v_n <> 5 then v_bad := v_bad || ' c_dead 사용 수=' || v_n || '(5개여야 — ⓒ 재평가, ⓓ 후보·재평가, ⓔ 후보·재평가)'; end if;
      -- [0188] 3 → 4. Arm ⓑ (the run-end strand) is now BOUNDED and LOCKED like ⓒ/ⓓ/ⓔ: 0188
      -- narrowed its escalation to zero-stamp rows, and since that branch is destructive the
      -- candidate read can no longer be trusted un-locked (a stamp committing between the read
      -- and the UPDATE would escalate a row that had just become settleable — the exact defect
      -- 0188 exists to close). Updated rather than left stale per the house law: the pinned
      -- behaviour legitimately changed. THE NEW PROPERTY ITSELF is owned by 219 `0188-B4`
      -- (the lock and re-check are present and arm ⓑ moves no row that carries a stamp); what
      -- these two lines own is unchanged — "every arm that writes is bounded and locked".
      -- ⚠ [0193] 4 → 5 on both counts. Arm ⓕ (0193 §D — an unfinished return past
      -- `ops_flags.return_strand_minutes` is reported to the `return_strand` ops roster) is the
      -- fifth arm that writes, and it is bounded and locked exactly like the other four. Updated
      -- in that slice rather than left stale, per the house law; THE NEW ARM ITSELF is owned by
      -- 224 `0193-R4`, and what these two lines own is unchanged — 「every arm that writes is
      -- bounded and locked」.
      select count(*) into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
      if v_n <> 5 then v_bad := v_bad || ' 배치 상한 수=' || v_n || '(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ 5개여야)'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
      if v_n <> 5 then v_bad := v_bad || ' 행 락 수=' || v_n || '(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ 5개여야)'; end if;
      -- ⚠ [0188] ANCHORED, and the anchor is the fix rather than the count. `b\.runner_id` is a
      -- SUBSTRING of `v_b\.runner_id`, so this arm silently counted the re-evaluation lines too
      -- and read 5 the moment 0188 added an arm that re-checks `v_b.runner_id` twice. `\m` is a
      -- word boundary and `_` is a word character, so `v_b.` can no longer satisfy it — the
      -- `[^_]custody[^_]` law (CLAUDE.md), applied to the pin that met it. The count stays 3
      -- because the CANDIDATE queries are still ⓒ/ⓓ/ⓔ's three: arm ⓑ carries no runner
      -- conjunct in its candidate (a 1:1 booking at `active` always has a runner) and re-checks
      -- `v_b.runner_id` only to decide whether to notify.
      select count(*) into v_n from regexp_matches(v_src, '\mb\.runner_id is not null', 'g');
      if v_n <> 3 then v_bad := v_bad || ' runner 조건 수=' || v_n || '(ⓒ·ⓓ·ⓔ 후보 3개여야)'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'v_b\.runner_id is null', 'g');
      if v_n <> 3 then v_bad := v_bad || ' runner 재평가 수=' || v_n || '(ⓒ·ⓓ·ⓔ 3개여야)'; end if;
    end if;
  end if;
  -- scoped like the backfill: a live one-sided row always has an id (born with it, or minted on its first touch)
  select count(*) into v_n from bookings where handoff_cycle_id is null and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null) and status in ('confirmed', 'runner_enroute');
  if v_n <> 0 then v_bad := v_bad || ' 라이브 한쪽 스탬프인데 id 없는 행=' || v_n; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.bookings'::regclass and not attisdropped and attname in ('handoff_cycle_id', 'handoff_ops_alerted_at') and (atthasdef or attnotnull);
  if v_n <> 0 then v_bad := v_bad || ' 새 열에 기본값/not null=' || v_n; end if;
  if v_bad = '' then call _pass('hcy','0183-E6 배포 형태 — 후보·재평가 모두 사이클 id로 매칭(시각 매칭 없음), 레거시 행 발급, 재전송이 id를 지님, ops 기록은 전달 조건부, pending 팔, 예외 팔 4·c_dead 5·배치 4·행 락 4·runner 3 [0188: ⓑ도 경계·락을 갖춘다]; 라이브 한쪽 스탬프면 id 있음; 새 열 기본값 없음');
  else v_msg := v_bad; call _fail('hcy','0183-E6 shape', v_msg); end if;
end $$;
