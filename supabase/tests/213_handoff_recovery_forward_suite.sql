-- ═══ 213 — 0182's four forward fixes — 0182-D1…D7, tag `cyc` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS (codex 0180+0181 REJECT/5, each re-measured):
--   · #1 an EARLIER pairing's 「인계 확인 요청」 to the same recipient does not answer this pairing's
--     stamp: `handoff_cycle_at` (database time of the runner change / stamp reset) bounds the match.
--   · #2 a handoff still one-sided 30 minutes after the stamp is escalated ONCE per cycle — both
--     parties and the ops roster told, the column stamped, no status move, club and marketplace,
--     no flag read.
--   · #3 arm ⓒ locks then looks again — source here; the behaviour is `90_race_check.sh` RL2.
--   · #4 individually valid counters whose sum overflows int4 reconcile beside a healthy tick.
--   · #5 (the sweep half) a club re-send carries the EDGE'S shape — booking ref + family title —
--     because the client resolver (`hig/club-handoff-route`) keys on the booking id.
--   · the trigger's semantics and that both new columns are server-owned.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE: arms ⓐ/ⓑ (119 · 133 · 163), arm ⓒ's other
--   properties (212), the reconciler's verdicts and split (181 · 211), the cron row (208).
--
-- ─── MUTATION MAP — measured 2026-09-18 on the final file (after the cold review's fixes), not predicted ───
--   Lab: an md5-identical copy of 0182 (+ tests), every plant `&&`-chained to its run, the control
--   observed first (1288 / 0). 「demoted」 = 0182's VERIFY raise turned into a notice so the SUITE
--   is what is measured; 「un-demoted」 = the shipped file, where the VERIFY aborts the apply.
--   (i-a)  the cycle bound dropped from ⓒ's candidate → D1 (owner-asks=1: the old ask masked) + D7;
--          un-demoted ABORTS (CYCLE-BOUND-MISSING-IN-CANDIDATE).
--   (i-b)  the cycle bound dropped from ⓒ's re-check  → D1 + D3 + D8 (first-tick-asks=49: the
--          re-check rejected one of the 50 candidates the bound would have excluded earlier — LIMIT
--          counts candidates, not sends); un-demoted ABORTS.
--   (ii)   a runner change no longer starts a cycle  → D2 (runner-change-did-not-stamp-now).
--   (iii)  a stamp reset no longer starts a cycle    → D2 (reset-kept-the-escalation-record).
--   (iv)   a new cycle keeps the escalation record   → D2 + D4 (new-cycle: owner-told=1).
--   (v)    the boundary taken from the statement     → D2 (boundary-moved-by-a-statement).
--   (vi)   ⓒ reads without a row lock                → D3 (row-locks=1) + RL2 (during=1: the sweep
--          asked while the runner's confirm was uncommitted); un-demoted ABORTS (ROW-LOCKS).
--   (vii)  ⓒ locks but does not look again          → D3 + D7 (c_dead 2/3 · runner re-check 1/2) —
--          source only: a confirm that lands between the candidate read and the lock is seen by
--          the lock itself (EvalPlanQual, measured by the cold review), so the re-check's
--          behaviour is the lock's; the arms pin its presence. NAMED GAP.
--   (viii) ESCALATE_AFTER 0                           → D4 (escalated-at-20-minutes) + 212 C1
--          (return-delta 4: ⓓ now counts C1's rows).
--   (ix)   the escalation not recorded               → D4 (record-not-set · escalated-twice ·
--          ops-told-2-times) + D7; un-demoted ABORTS.
--   (x)    ops not told                               → D4 (ops-not-told) + D7; un-demoted ABORTS.
--   (xi)   ⓓ scoped to marketplace rows              → D4 (club: parties-told=0/0) + D7 + 212 C8;
--          un-demoted ABORTS (CLUB-SCOPE-COUNT 3/2).
--   (xii)  ⓓ gated on the late-protocol flag         → D4 (nothing told, nothing recorded) + D7;
--          un-demoted ABORTS (FLAG-GATED).
--   (xiii) the balance sum back to int4              → D5 (the overflow tick `failed`, numbers not
--          kept, detail 「integer out of range」 — the per-tick boundary caught what 0180 let abort
--          the call); un-demoted ABORTS (BALANCE-SUM-NOT-BIGINT).
--   (xiv)  the per-tick boundary deleted             → D5 (deterministic: the call RAISED, the
--          sibling did not reconcile) + source arms; un-demoted ABORTS (PER-TICK-BOUNDARY 1/2).
--   (xv)   ⓓ moves the status (a clock-cancel)       → D4 (status-moved=no_show · the re-match
--          fixture refused `handoff_on_closed_booking`, named).
--   (xvi)  c_dead loses `completed`                  → D4 (completed:escalated) + D7 (the two
--          spellings differ); un-demoted ABORTS (DENY-LIST-DRIFT).
--   (xvii) the ops body carries the booking id       → D4 (ops-body-carries-an-id).
--   (xviii) ⓓ loses its status deny-list, both sites → D4 (all fourteen: draft…refund_pending
--          :escalated) + D7 (c_dead 1/3); un-demoted ABORTS. The cold review's #2.
--   (xix)  ⓓ loses its runner conjunct, both sites   → D7 only (runner 조건 1/2 · 재평가 1/2); the
--          behaviour is masked by ⓓ's own handler (the NULL-profile insert fails and the row
--          retries every tick) — source-pinned, NAMED GAP; un-demoted ABORTS.
--   (xx)   ⓒ unbounded again                          → D8 (first-tick-asks=52) + D7; un-demoted
--          ABORTS (BATCH-BOUND 1/2).
--   (xxi)  a transient fault becomes a permanent verdict → D5 (transient: the call did NOT
--          re-raise · tick=failed · after-transient failed/NULL); un-demoted ABORTS.
--   (xxii) lock_timeout deleted                      → D7 (lock_timeout 없음); un-demoted ABORTS.
--   Client side (`app/test/notification-route.test.cjs`, lab copy, control 34/0): the escalation
--   title left out of CLUB_PROBE_TITLES → 4 red; the client's spelling drifted → the 0182 drift
--   pin; the SWEEP's spelling drifted → the same pin; the title pushed into HANDOFF_TITLES (the
--   owner routed to the meetup CTA) → 3 red.
--   NAMED GAPS: (vii) and (xix) above; the two-tick SKIP is 212's RL; the two residues of #1 (a
--   delayed old-pairing ask, pre-0182 rows) are rescued by ⓓ at 30 minutes and pinned nowhere
--   narrower — 0182's header names them.
--
-- ─── FIXTURE NOTES ───
--  ① `t_ask_bk` / `t_asks` are 212's helpers (created there, still in the database here).
--  ② A re-match is modelled as the edge does it (`runner_accept`'s resetPatch, index.ts:163):
--     ONE update that changes runner_id and nulls both stamps — the trigger stamps the cycle at
--     transaction `now()`. Inside this one-transaction suite every `now()` is the same instant, so
--     「an ask of the new pairing」 is a row with the default created_at (= now() = cycle_at) and
--     「an ask of the old pairing」 is a row created minutes before it.
--  ③ The ops roster: one recipient subscribed to `handoff_unanswered` (RLS-sealed table, written
--     here as postgres). D4's last arm deletes it to measure the empty-roster case.
set client_min_messages = warning;

create or replace function t_esc(p_bk uuid, p_who uuid) returns int
language sql as $$
  select count(*)::int from notifications
  where ref_id = p_bk and profile_id = p_who and title = '인계 확인이 멈춰 있어요'
$$;

do $$
declare
  o uuid; r1 uuid; r2 uuid; d uuid; rt uuid; opsp uuid;
  bk1 uuid; bk1b uuid; bk2 uuid; bk4 uuid; bk4b uuid; bk4c uuid; bk4d uuid; bk6 uuid; bk uuid;
  v_club uuid; v_sess uuid; t5 uuid; t6 uuid;
  v_bad text; v_msg text; v_err text; v_note text := ''; v_n int; v_src text; v_oid oid; v_lit text; v_arr text;
  r record; v_cyc timestamptz; v_esc timestamptz; s booking_status; o8 uuid; r8 uuid; d8 uuid; i int; n1 int; n2 int;
begin
  o := t_user('cyc_owner', 'owner'); r1 := t_user('cyc_runner1', 'runner'); r2 := t_user('cyc_runner2', 'runner');
  d := t_dog(o, 'cyc-dog'); rt := t_route('cyc 코스');
  opsp := t_user('cyc_ops', 'owner');
  insert into ops_recipients (profile_id, event_class) values (opsp, 'handoff_unanswered');   -- ③
  begin perform sweep_run_end_recovery(); exception when others then null; end;              -- drain

  -- ---------- [0182-D1] the same OWNER recipient, a NEW runner, the old ask inside the skew ⇒ re-sent (codex #1) ----------
  v_bad := '';
  bk1 := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '9 minutes');                 -- r1 confirmed; the edge asked the owner…
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1, now() - interval '9 minutes');
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk1;   -- ② re-match
  select handoff_cycle_at into v_cyc from bookings where id = bk1;
  if v_cyc is null then v_bad := v_bad || ' cycle-not-stamped-on-re-match'; end if;
  update bookings set runner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk1;   -- r2 confirms; THEIR ask is lost
  perform sweep_run_end_recovery();
  if t_asks(bk1, o) <> 2 then v_bad := v_bad || ' owner-asks=' || t_asks(bk1, o) || ' (expected 2: the old pairing''s + the re-send; 1 = the old ask masked this pairing)'; end if;
  if t_asks(bk1, r1) <> 0 or t_asks(bk1, r2) <> 0 then v_bad := v_bad || ' a-runner-was-asked(' || t_asks(bk1, r1) || '/' || t_asks(bk1, r2) || ')'; end if;
  perform sweep_run_end_recovery();
  if t_asks(bk1, o) <> 2 then v_bad := v_bad || ' re-sent-twice(' || t_asks(bk1, o) || ')'; end if;
  -- the control: the NEW pairing's own ask exists (created at/after the cycle boundary) ⇒ nothing to re-send
  bk1b := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '9 minutes');
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1b, now() - interval '9 minutes');
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk1b;
  update bookings set runner_confirmed_handoff_at = now() - interval '6 minutes' where id = bk1b;
  -- [0183] the new pairing's edge ask carries the NEW cycle's id (what makes it this cycle's since
  -- 0183; the timestamp no longer decides) — suite-update law, 214 E1 owns the identity rule
  insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)           -- the new pairing's edge ask
  values (o, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk1b, (select handoff_cycle_id from bookings where id = bk1b));
  perform sweep_run_end_recovery();
  if t_asks(bk1b, o) <> 2 then v_bad := v_bad || ' control: owner-asks=' || t_asks(bk1b, o) || ' (expected 2: old + the new pairing''s own; 3 = re-sent despite the new ask)'; end if;
  if v_bad = '' then call _pass('cyc','0182-D1 같은 보호자 수신자·새 러너: 이전 짝의 요청 행(스큐 안)은 이 짝의 요청이 아니다 → 다시 보냄(1회); 새 짝의 요청이 사이클 경계 뒤에 있으면 안 보냄');
  else v_msg := v_bad; call _fail('cyc','0182-D1 cycle', v_msg); end if;

  -- ---------- [0182-D2] the trigger: what bumps a cycle, what does not, and that clients cannot write the records ----------
  v_bad := ''; v_note := '';
  bk2 := t_ask_bk(o, d, rt, r1, 'confirmed', 'none', interval '10 minutes');
  if (select handoff_cycle_at from bookings where id = bk2) is not null then v_bad := v_bad || ' insert-stamped-a-cycle'; end if;
  update bookings set km = 6.0 where id = bk2;
  if (select handoff_cycle_at from bookings where id = bk2) is not null then v_bad := v_bad || ' unrelated-update-bumped'; end if;
  update bookings set owner_confirmed_handoff_at = now() where id = bk2;                        -- a stamp SET is not a new cycle
  if (select handoff_cycle_at from bookings where id = bk2) is not null then v_bad := v_bad || ' stamp-set-bumped'; end if;
  update bookings set runner_id = r2 where id = bk2;                                             -- runner change ⇒ new cycle
  select handoff_cycle_at into v_cyc from bookings where id = bk2;
  if v_cyc is distinct from now() then v_bad := v_bad || ' runner-change-did-not-stamp-now(' || coalesce(v_cyc::text,'NULL') || ')'; end if;
  update bookings set handoff_escalated_at = now() - interval '1 hour' where id = bk2;           -- as the server: allowed
  update bookings set owner_confirmed_handoff_at = null where id = bk2;                          -- stamp RESET ⇒ new cycle, record cleared
  select handoff_cycle_at, handoff_escalated_at into v_cyc, v_esc from bookings where id = bk2;
  if v_cyc is distinct from now() then v_bad := v_bad || ' stamp-reset-did-not-stamp'; end if;
  if v_esc is not null then v_bad := v_bad || ' reset-kept-the-escalation-record(' || v_esc::text || ')'; end if;
  update bookings set handoff_cycle_at = '2000-01-01', handoff_escalated_at = '2000-01-01' where id = bk2;   -- even the server cannot MOVE the boundary; the record it may set
  select handoff_cycle_at, handoff_escalated_at into v_cyc, v_esc from bookings where id = bk2;
  if v_cyc is distinct from now() then v_bad := v_bad || ' boundary-moved-by-a-statement(' || coalesce(v_cyc::text,'NULL') || ')'; end if;
  if v_esc is distinct from '2000-01-01'::timestamptz then v_bad := v_bad || ' server-write-of-the-record-refused'; end if;
  -- a CLIENT write of the record does not land. Measured: it is 0058's `_guard_booking_cols` (which
  -- fires first, by name, and refuses EVERY direct client write to bookings) that raises — so this
  -- arm asserts the refusal AND names its source by the guard's own detail text; 0182's trigger
  -- deliberately carries no refusal arm of its own (it would be unreachable).
  v_err := null;
  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', o::text, true);
    update bookings set handoff_escalated_at = null where id = bk2;
    get diagnostics v_n = row_count;
    execute 'reset role';
    v_note := ' (client update touched ' || v_n || ' row(s) without raising)';
  exception when others then v_err := sqlerrm; end;
  execute 'reset role';
  if v_err is null then v_bad := v_bad || ' client-write-was-NOT-refused' || v_note;
  elsif v_err !~ 'booking_protected_columns' then v_bad := v_bad || ' client-write refused by something else: [' || v_err || ']'; end if;
  if (select handoff_escalated_at from bookings where id = bk2) is distinct from '2000-01-01'::timestamptz then v_bad := v_bad || ' a-client-changed-the-record'; end if;
  -- the refuser is 0058's blanket guard, not this slice's trigger: the trigger's source carries no raise
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = '_handoff_cycle_tg';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(trigger)';
  elsif (v_src ~ 'raise exception') is distinct from false then v_bad := v_bad || ' the-trigger-carries-an-unreachable-refusal'; end if;
  if (select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') ~ 'booking_protected_columns' from pg_proc where proname = '_guard_booking_cols') is distinct from true then v_bad := v_bad || ' 0058-guard-no-longer-refuses'; end if;
  select count(*) into v_n from pg_trigger where tgrelid = 'public.bookings'::regclass and tgname = '_handoff_cycle' and not tgisinternal and tgenabled = 'O';
  if v_n <> 1 then v_bad := v_bad || ' trigger-enabled=' || v_n; end if;
  if v_bad = '' then call _pass('cyc','0182-D2 트리거 — 러너 변경·스탬프 리셋은 사이클을 찍고 기록을 지운다; 삽입·무관한 갱신·스탬프 설정은 아니다; 경계는 어떤 문장으로도 못 옮기고, 클라이언트 쓰기는 0058 _guard_booking_cols가 막는다(booking_protected_columns; 이 트리거엔 raise 없음); tgenabled=O');
  else v_msg := v_bad; call _fail('cyc','0182-D2 trigger', v_msg); end if;

  -- ---------- [0182-D3] lock, then look again — source (the behaviour is 90_race_check.sh RL2) ----------
  v_bad := '';
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = 'sweep_run_end_recovery';
  if v_src is null then v_bad := ' NO-SOURCE';
  else
    -- [0183] arm ⓔ locks too; ≥ 2 keeps this file's property (ⓒ and ⓓ lock before they write) — 214 E6 pins 3
    select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
    if v_n < 2 then v_bad := v_bad || ' row-locks=' || v_n || '(ⓒ·ⓓ 최소 2개)'; end if;
    if (v_src ~ 'if not found then') is distinct from true then v_bad := v_bad || ' 잠긴 행 건너뛰기 없음'; end if;
    if (v_src ~ 'v_b\.status = any\(c_dead\)') is distinct from true then v_bad := v_bad || ' 잠근 행 재평가 없음'; end if;
    -- [0183] the re-check matches the ask by the cycle IDENTITY (`v_cid`), not by a timestamp bound
    if (v_src ~ 'nt\.handoff_cycle_id = v_cid\)') is distinct from true then v_bad := v_bad || ' 재평가에 사이클 정체성 매칭 없음'; end if;
    if (v_src ~ 'values \(v_cp, ''booking'', c_ask_title') is distinct from true then v_bad := v_bad || ' 삽입이 잠근 행의 상대가 아니다'; end if;
  end if;
  if v_bad = '' then call _pass('cyc','0182-D3 ⓒ는 후보를 잠그고(skip locked) 잠근 행에서 스탬프·러너·상태·나이·요청 행을 다시 본 뒤 그 행의 상대에게만 보낸다 (두 커넥션 행동은 RL2)');
  else v_msg := v_bad; call _fail('cyc','0182-D3 lock-then-look', v_msg); end if;

  -- ---------- [0182-D4] the deadline (codex #2): 30 minutes one-sided ⇒ told once, no status move, club too, no flag ----------
  v_bad := '';
  if (select f.late_protocol_live_since from ops_flags f) is not null then v_bad := v_bad || ' the-late-flag-is-ON-in-the-harness(this pin must run with it off)'; end if;
  bk4 := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '40 minutes');
  insert into notifications (profile_id, kind, title, body, ref_id)                            -- the ask WAS delivered; nobody acted
  values (r1, 'booking', '인계 확인 요청', '상대방이 인계를 확인했어요 — 확인해주세요', bk4);
  bk4b := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '20 minutes');                -- inside the bound
  insert into clubs (name, district, host_profile_id) values ('cyc 클럽', '반포동', r1) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point) values (v_club, r1, now() + interval '1 hour', 'cyc 집결지') returning id into v_sess;
  bk4c := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '40 minutes', v_sess);        -- a club booking, past the bound
  perform sweep_run_end_recovery();
  if t_esc(bk4, o) <> 1 or t_esc(bk4, r1) <> 1 then v_bad := v_bad || ' parties-told=' || t_esc(bk4, o) || '/' || t_esc(bk4, r1); end if;
  select * into r from notifications where ref_id = bk4 and profile_id = opsp limit 1;
  if r.id is null then v_bad := v_bad || ' ops-not-told';
  else
    if r.kind::text is distinct from 'system' then v_bad := v_bad || ' ops-kind=' || r.kind::text; end if;
    -- `is distinct from false`: `body` is nullable and a bare IF on a NULL regex is silent (the
    -- NULL-collapse law) — a NULL ops body must redden too
    if (r.body ~ '[0-9a-f]{8}-[0-9a-f]{4}') is distinct from false then v_bad := v_bad || ' ops-body-carries-an-id-or-is-NULL'; end if;
  end if;
  if (select handoff_escalated_at from bookings where id = bk4) is null then v_bad := v_bad || ' record-not-set'; end if;
  if (select status::text from bookings where id = bk4) <> 'confirmed' then v_bad := v_bad || ' status-moved=' || (select status::text from bookings where id = bk4); end if;
  if t_esc(bk4b, o) <> 0 or t_esc(bk4b, r1) <> 0 then v_bad := v_bad || ' escalated-at-20-minutes'; end if;
  if t_esc(bk4c, o) <> 1 or t_esc(bk4c, r1) <> 1 then v_bad := v_bad || ' club: parties-told=' || t_esc(bk4c, o) || '/' || t_esc(bk4c, r1); end if;
  perform sweep_run_end_recovery();                                                             -- once
  if t_esc(bk4, o) <> 1 or t_esc(bk4, r1) <> 1 then v_bad := v_bad || ' escalated-twice(' || t_esc(bk4, o) || '/' || t_esc(bk4, r1) || ')'; end if;
  select count(*) into v_n from notifications where ref_id = bk4 and profile_id = opsp;
  if v_n <> 1 then v_bad := v_bad || ' ops-told-' || v_n || '-times'; end if;
  -- a NEW cycle escalates again: re-match (record cleared), a fresh one-sided stamp past the bound.
  -- In a sub-block: a sweep that MOVED the status (a clock-cancel plant) makes this re-match refuse
  -- (`handoff_on_closed_booking`), and that must redden this pin by name, not crash the suite.
  begin
    update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk4;
    update bookings set owner_confirmed_handoff_at = now() - interval '40 minutes' where id = bk4;
    perform sweep_run_end_recovery();
  exception when others then v_bad := v_bad || ' new-cycle fixture/sweep RAISED [' || sqlerrm || '] (did the sweep move the status?)'; end;
  if t_esc(bk4, o) <> 2 then v_bad := v_bad || ' new-cycle: owner-told=' || t_esc(bk4, o) || ' (expected 2)'; end if;
  if t_esc(bk4, r2) <> 1 then v_bad := v_bad || ' new-cycle: new-runner-told=' || t_esc(bk4, r2); end if;
  -- an EMPTY roster: the parties are still told and THEIR record is set; [0183] the OPS record stays
  -- NULL (a pending ops escalation — 214 E4 owns the retry after provisioning). Suite-update law:
  -- 0182's version of this arm pinned the consumed escalation codex called out.
  delete from ops_recipients where profile_id = opsp;
  bk4d := t_ask_bk(o, d, rt, r1, 'confirmed', 'runner', interval '40 minutes');
  perform sweep_run_end_recovery();
  if t_esc(bk4d, o) <> 1 or t_esc(bk4d, r1) <> 1 then v_bad := v_bad || ' empty-roster: parties-told=' || t_esc(bk4d, o) || '/' || t_esc(bk4d, r1); end if;
  if (select handoff_escalated_at from bookings where id = bk4d) is null then v_bad := v_bad || ' empty-roster: record-not-set'; end if;
  if (select handoff_ops_alerted_at from bookings where id = bk4d) is not null then v_bad := v_bad || ' empty-roster: ops-record-set-with-nobody-told'; end if;
  -- ⓓ never touches a status in which no handoff is underway — the enum walked, 212 C6's shape for
  -- ⓒ; the cold review found ⓓ's deny-list deletable with a green suite (an owner who stamped and
  -- then CANCELLED would have been told the handoff was stuck). And no runner ⇒ nothing, no raise.
  for s in select unnest(enum_range(null::booking_status)) loop
    if s in ('confirmed', 'runner_enroute') then continue; end if;
    begin
      bk := t_ask_bk(o, d, rt, r1, s, 'owner', interval '40 minutes');
      perform sweep_run_end_recovery();
      if t_esc(bk, o) <> 0 or t_esc(bk, r1) <> 0 or (select handoff_escalated_at from bookings where id = bk) is not null then v_bad := v_bad || ' ' || s::text || ':escalated'; end if;
    exception when others then v_note := v_note || ' ' || s::text || '[' || left(sqlerrm, 40) || ']'; end;
  end loop;
  begin
    bk := t_ask_bk(o, d, rt, null, 'confirmed', 'owner', interval '40 minutes');
    perform sweep_run_end_recovery();
    if t_esc(bk, o) <> 0 or (select handoff_escalated_at from bookings where id = bk) is not null then v_bad := v_bad || ' no-runner:escalated'; end if;
    if exists (select 1 from notifications where ref_id = bk and title = '인계 확인이 멈춰 있어요') then v_bad := v_bad || ' no-runner:someone-told'; end if;
  exception when others then v_bad := v_bad || ' no-runner: RAISED [' || sqlerrm || ']'; end;
  if v_bad = '' then call _pass('cyc','0182-D4 한쪽만 확인한 채 40분 — 양측·ops(system, 본문에 id 없음)에 1회, 기록 컬럼 찍힘, 상태 그대로; 20분은 아직; 클럽도; 새 사이클이면 다시; 로스터가 비어도 양측은 듣는다; late 플래그 null인 채로; enum의 나머지 열넷·러너 없음은 40분이어도 안 건드린다' || case when v_note <> '' then ' ⚠ 픽스처 불가:' || v_note else '' end);
  else v_msg := v_bad; call _fail('cyc','0182-D4 deadline', v_msg); end if;

  -- ---------- [0182-D5] individually valid counters whose sum overflows int4 reconcile beside a healthy tick (codex #4) ----------
  v_bad := '';
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 4, 813001, now() - interval '1 minute') returning id into t5;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (813001, 200, '{"claimed":4,"revoked":1,"failed":1,"stale":1,"not_processing":1,"absent":0,"unreported":0}', false, now());
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 0, 813002, now() - interval '1 minute') returning id into t6;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (813002, 200, '{"claimed":0,"revoked":2147483647,"failed":1,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  v_err := null;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_err := sqlerrm; end;
  if v_err is not null then v_bad := v_bad || ' reconciler-RAISED [' || v_err || ']'; end if;
  select * into r from billing_key_dispatch_ticks where id = t6;
  if r.outcome is distinct from 'accepted' then v_bad := v_bad || ' overflow-tick outcome=' || coalesce(r.outcome,'NULL'); end if;
  if r.revoked_count is distinct from 2147483647 or r.failed_count is distinct from 1 then v_bad := v_bad || ' overflow-tick numbers-not-kept'; end if;
  if (r.detail ~ 'counters do not balance: claimed 0 <> revoked 2147483647') is distinct from true then v_bad := v_bad || ' overflow-tick detail=' || coalesce(left(r.detail,80),'NULL'); end if;
  select * into r from billing_key_dispatch_ticks where id = t5;
  if r.outcome is distinct from 'accepted' or r.detail is not null or r.revoked_count is distinct from 1 then v_bad := v_bad || ' healthy-tick outcome/detail/revoked=' || coalesce(r.outcome,'NULL') || '/' || coalesce(left(r.detail,40),'∅') || '/' || coalesce(r.revoked_count::text,'NULL'); end if;
  -- the per-tick boundary, two-sided (cold review 0182 #3): a TRANSIENT fault on the tick's UPDATE
  -- (a deadlock, stood in for by errcode 40P01) must leave the tick `sent` for the next tick — 0180's
  -- self-healing — while a DETERMINISTIC fault (P0001) is marked `failed` with the reason and the
  -- sibling still reconciles. A temporary trigger on the tick table stands in for both.
  create or replace function t_cyc_tick_fault() returns trigger language plpgsql as $f$
  begin
    -- only the main path's write (`accepted`) faults — the handler's own `failed` marking must land,
    -- as a real fault raised while READING an answer would leave it free to
    if new.id::text = current_setting('cyc.fault_tick', true) and new.outcome = 'accepted' then
      if current_setting('cyc.fault_kind', true) = 'transient' then
        raise exception 'deadlock detected (stand-in)' using errcode = '40P01';
      else
        raise exception 'a deterministic fault (stand-in)' using errcode = 'P0001';
      end if;
    end if;
    return new;
  end $f$;
  create trigger t_cyc_tick_fault before update on billing_key_dispatch_ticks for each row execute function t_cyc_tick_fault();
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, 813003, now() - interval '1 minute') returning id into t5;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (813003, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('cyc.fault_tick', t5::text, true); perform set_config('cyc.fault_kind', 'transient', true);
  v_err := null;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_err := sqlerrm; end;
  -- [0183] a transient fault no longer ABORTS the call (an abort killed the siblings' verdicts, the
  -- stale sweep and the prune) — it leaves the tick `sent` and the loop goes on. The property this
  -- arm holds (「not a permanent verdict; retried next tick」) is unchanged; 214 E5 owns the shape.
  if v_err is not null then v_bad := v_bad || ' transient: the call RAISED [' || v_err || '] (an abort is 0182''s shape; 0183 leaves the tick and continues)'; end if;
  if (select outcome from billing_key_dispatch_ticks where id = t5) is distinct from 'sent' then v_bad := v_bad || ' transient: tick=' || (select outcome from billing_key_dispatch_ticks where id = t5) || ' (expected sent — left for the next tick)'; end if;
  perform set_config('cyc.fault_tick', '', true);                                               -- the cause is gone
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' after-transient RAISED [' || sqlerrm || ']'; end;
  if (select outcome || '/' || coalesce(claimed_count::text,'NULL') from billing_key_dispatch_ticks where id = t5) is distinct from 'accepted/3' then v_bad := v_bad || ' after-transient: ' || (select outcome || '/' || coalesce(claimed_count::text,'NULL') from billing_key_dispatch_ticks where id = t5) || ' (expected accepted/3)'; end if;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, 813004, now() - interval '1 minute') returning id into t6;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (813004, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 1, 813005, now() - interval '1 minute') returning id into t5;   -- the sibling
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (813005, 200, '{"claimed":1,"revoked":1,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('cyc.fault_tick', t6::text, true); perform set_config('cyc.fault_kind', 'deterministic', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' deterministic: the call RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t6;
  if r.outcome is distinct from 'failed' or (r.detail ~ 'reconciler could not read this answer: a deterministic fault') is distinct from true then v_bad := v_bad || ' deterministic: ' || coalesce(r.outcome,'NULL') || '/' || coalesce(left(r.detail,60),'∅'); end if;
  if (select outcome from billing_key_dispatch_ticks where id = t5) is distinct from 'accepted' then v_bad := v_bad || ' deterministic: the sibling did not reconcile'; end if;
  perform set_config('cyc.fault_tick', '', true);
  drop trigger t_cyc_tick_fault on billing_key_dispatch_ticks; drop function t_cyc_tick_fault();
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = 'reconcile_billing_key_dispatch_ticks';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(reconciler)';
  else
    if (v_src ~ 'v_claimed::bigint <> v_revoked::bigint \+') is distinct from true then v_bad := v_bad || ' 합이 bigint가 아니다'; end if;
    -- [0183] the filter is INVERTED — a verdict only for named deterministic classes (22 · 23 · P0),
    -- everything else re-raised — so this arm now pins that inversion; 214 E5 owns the class rule.
    -- Suite-update law: the property (a transient fault must not become a verdict) is unchanged.
    if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' 판정을 22·23·P0에만 한정하는 필터 없음'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n <> 2 then v_bad := v_bad || ' 틱 단위 예외 팔 수=' || v_n || '(본문 파싱 + 틱 2개여야)'; end if;
    if (v_src ~ 'reconciler could not read this answer') is distinct from true then v_bad := v_bad || ' 읽지 못한 답을 이름 짓지 않는다'; end if;
  end if;
  if v_bad = '' then call _pass('cyc','0182-D5 각각은 유효하지만 합이 int4를 넘는 본문 — 호출은 살아 있고, 그 틱은 accepted + 「counters do not balance」, 옆의 건강한 틱도 정리됨; 합은 bigint; 틱 단위 경계 양면 — 일시적 오류(40P01)는 틱을 sent로 두고 다음 호출에 accepted[0183: 호출은 죽지 않는다], 결정적 오류(P0001)는 failed + 사유이고 옆 틱은 정리됨');
  else v_msg := v_bad; call _fail('cyc','0182-D5 overflow', v_msg); end if;

  -- ---------- [0182-D6] a club re-send carries the EDGE'S shape: booking ref + family title, never a session ref (codex #5, sweep half) ----------
  v_bad := '';
  bk6 := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '10 minutes', v_sess);
  perform sweep_run_end_recovery();
  select * into r from notifications where profile_id = r1 and ref_id = bk6 and title = '인계 확인 요청' limit 1;
  if r.id is null then v_bad := v_bad || ' no-ask-with-the-booking-ref';
  else
    if r.kind::text is distinct from 'booking' then v_bad := v_bad || ' kind=' || r.kind::text; end if;
    if r.body is distinct from '상대방이 인계를 확인했어요 — 확인해주세요' then v_bad := v_bad || ' body=' || coalesce(left(r.body,60),'NULL'); end if;
  end if;
  if exists (select 1 from notifications where profile_id = r1 and ref_id = v_sess and title = '인계 확인 요청') then v_bad := v_bad || ' a-session-ref-ask-was-written (the client resolver keys on the booking id)'; end if;
  if v_bad = '' then call _pass('cyc','0182-D6 클럽 예약의 다시 보낸 요청은 엣지와 같은 모양 — ref_id=예약, kind=booking, 제목은 패밀리; 세션 ref 행은 없다 (클라이언트 라우터가 예약 id로 club_session_id를 푼다)');
  else v_msg := v_bad; call _fail('cyc','0182-D6 club-shape', v_msg); end if;

  -- ---------- [0182-D7] deployed shape ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then v_bad := ' NO-FUNCTION(sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' sweep: definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' sweep: search_path 없음'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' sweep: 클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' sweep: service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep)';
    else
      -- [0183] the candidate matches the ask by the cycle IDENTITY, not by a timestamp bound
      if (v_src ~ 'nt\.handoff_cycle_id = b\.handoff_cycle_id\)') is distinct from true then v_bad := v_bad || ' 후보 질의에 사이클 정체성 매칭 없음'; end if;
      if (v_src ~ 'handoff_escalated_at = now\(\)') is distinct from true then v_bad := v_bad || ' 승격 기록 없음'; end if;
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is distinct from true then v_bad := v_bad || ' ops 로스터 안 부름'; end if;
      if (v_src ~ 'c_ops_class constant text := ''handoff_unanswered''') is distinct from true then v_bad := v_bad || ' ops 클래스 텍스트 다름'; end if;
      if (v_src ~ 'late_protocol_live_since') is distinct from false then v_bad := v_bad || ' late 플래그를 읽는다'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'set status', 'g');   -- exactly ⓑ's escalation; ⓒ/ⓓ move no status
      if v_n <> 1 then v_bad := v_bad || ' 상태 이동 문장 수=' || v_n || '(ⓑ의 1개여야 — ⓒ/ⓓ는 상태를 옮기지 않는다)'; end if;
      -- ⚠ [0193] 2 → 3 (arm ⓕ, the strand's ops bell, is marketplace-scoped like ⓐ/ⓑ — 0144:94's
      -- reason). The property this line owns is unchanged; 224 `0193-R4` owns the new arm's.
      select count(*) into v_n from regexp_matches(v_src, 'club_session_id is null', 'g');
      if v_n <> 3 then v_bad := v_bad || ' club 범위 조건 수=' || v_n || '(ⓐ/ⓑ/ⓕ 3개여야)'; end if;
      -- [0183] arm ⓔ (the pending ops escalation) adds a handler and a c_dead use; ≥ 3 keeps this
      -- file's property (ⓑ·ⓒ·ⓓ each catch their row and screen dead statuses) — 214 E6 pins 4
      select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
      if v_n < 3 then v_bad := v_bad || ' 행 단위 예외 팔 수=' || v_n || '(ⓑ·ⓒ·ⓓ 최소 3개)'; end if;
      select count(*) into v_n from regexp_matches(v_src, '= any\(c_dead\)', 'g');
      if v_n < 3 then v_bad := v_bad || ' c_dead 사용 수=' || v_n || '(ⓒ 재평가·ⓓ 후보·ⓓ 재평가 최소 3개)'; end if;
      -- [0183] arm ⓔ's candidate carries the runner conjunct too; ≥ 2 keeps this file's property, 214 E6 pins 3
      select count(*) into v_n from regexp_matches(v_src, 'b\.runner_id is not null', 'g');
      if v_n < 2 then v_bad := v_bad || ' runner 조건 수=' || v_n || '(ⓒ·ⓓ 후보 최소 2개)'; end if;
      -- [0183] arm ⓔ re-checks the runner too; ≥ 2 keeps this file's property — 214 E6 pins 3
      select count(*) into v_n from regexp_matches(v_src, 'v_b\.runner_id is null', 'g');
      if v_n < 2 then v_bad := v_bad || ' runner 재평가 수=' || v_n || '(최소 2개)'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
      if v_n < 2 then v_bad := v_bad || ' 배치 상한 수=' || v_n || '(ⓒ·ⓓ 최소 2개; [0183] ⓔ가 하나 더)'; end if;
      if (v_src ~ 'set_config\(''lock_timeout'', ''2000'', true\)') is distinct from true then v_bad := v_bad || ' lock_timeout 없음'; end if;
      -- ⚠ [0193] ANCHORED, and the anchor is the fix rather than the pattern. `b\.status` is a
      -- SUBSTRING of `v_b\.status`, so this extraction took the FIRST match in the body — and arm
      -- ⓕ (0193 §D) sits ahead of arm ⓒ and re-checks `v_b.status not in ('active',
      -- 'incident_review')` on its locked row. The pin then compared arm ⓕ's two-status re-check
      -- against `c_dead`'s fourteen and reported 「deny-list 두 철자가 다르다」 on a correct
      -- function. `\m` is a word boundary and `_` is a word character, so `v_b.` can no longer
      -- satisfy it — the `[^_]custody[^_]` law (CLAUDE.md), the same correction 214 `0183-E6`
      -- already had to make to its `b\.runner_id` arm, in the same function, for the same reason.
      v_lit := regexp_replace((regexp_match(v_src, '\mb\.status not in \(([^)]*)\)'))[1], '\s+', '', 'g');
      v_arr := regexp_replace((regexp_match(v_src, 'array\[([^\]]*)\]::booking_status\[\]'))[1], '\s+', '', 'g');
      if v_lit is null or v_arr is null or v_lit is distinct from v_arr then v_bad := v_bad || ' deny-list 두 철자가 다르다(' || coalesce(v_lit,'∅') || ' vs ' || coalesce(v_arr,'∅') || ')'; end if;
      if (v_src ~ '정산을 확인하고 있어요' and v_src ~ '귀가 확인이 필요해요') is distinct from true then v_bad := v_bad || ' 0083 팔 없음'; end if;
    end if;
  end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = '_handoff_cycle_tg';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(trigger)';
  elsif has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' trigger fn: 클라 실행 가능'; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.bookings'::regclass and not attisdropped and attname in ('handoff_cycle_at','handoff_escalated_at') and (atthasdef or attnotnull);
  if v_n <> 0 then v_bad := v_bad || ' 새 열에 기본값/not null=' || v_n; end if;
  if v_bad = '' then call _pass('cyc','0182-D7 배포 형태 — 스윕 definer·search_path·ACL, 사이클 경계·승격 기록·ops 클래스·플래그 없음·상태 이동 없음·club 제외 2곳·예외 팔 3개·deny-list 두 철자 동일·c_dead 3곳·runner 조건 2+2·배치 상한 2·lock_timeout; 트리거 함수 클라 실행 불가; 새 열 기본값 없음');
  else v_msg := v_bad; call _fail('cyc','0182-D7 shape', v_msg); end if;

  -- ---------- [0182-D8] ⓒ serves at most c_batch (50) rows a tick; the rest are served next tick, nothing lost ----------
  v_bad := '';
  o8 := t_user('cyc_owner8', 'owner'); r8 := t_user('cyc_runner8', 'runner'); d8 := t_dog(o8, 'cyc-dog-8');
  for i in 1..52 loop bk := t_ask_bk(o8, d8, rt, r8, 'confirmed', 'owner', interval '10 minutes'); end loop;
  perform sweep_run_end_recovery();
  select count(*) into n1 from notifications where profile_id = r8 and title = '인계 확인 요청';
  perform sweep_run_end_recovery();
  select count(*) into n2 from notifications where profile_id = r8 and title = '인계 확인 요청';
  if n1 <> 50 then v_bad := v_bad || ' first-tick-asks=' || n1 || ' (expected 50 = c_batch)'; end if;
  if n2 <> 52 then v_bad := v_bad || ' second-tick-asks=' || n2 || ' (expected 52 — nothing lost)'; end if;
  if v_bad = '' then call _pass('cyc','0182-D8 ⓒ는 한 틱에 c_batch(50)행까지만 — 52건 중 첫 틱 50, 둘째 틱 52 (잃는 건 없고, 잡는 행 락 수가 유계)');
  else v_msg := v_bad; call _fail('cyc','0182-D8 batch', v_msg); end if;
end $$;
