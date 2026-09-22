-- ═══ 235 — 0204: the push leaves through an outbox, re-checked at dispatch ════════════════════
-- ═══        0204-Q1·Q2 · R1…R4 · A1…A3 · D1 · L1 · C1 · S1, tag `pox`                      ═══
--
-- Codex finding B8 (`docs/reviews/2026-09-22-0188-0189-0190-codex-verdict.md:17`), recorded
-- 2026-09-22 and carried unbuilt through two reviews. `notify_push` checked the recipient was live
-- and then handed an ASYNCHRONOUS `net.http_post` to pg_net in the same statement; a deletion
-- committing in between was never re-examined.
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · Q1 A notification for a live recipient holding an Expo token produces EXACTLY ONE
--        `push_outbox` row carrying the same payload 0024/0187/0189 posted — token, title, body,
--        `data.kind`, `data.ref_id` — pending, `attempts = 0`, uncancelled, linked to the
--        notification; and **NOTHING IS POSTED** by the write itself. The `notifications` row is
--        written, as it always was.
--   · Q2 Every classification rule 0187 and 0189 added still decides the ENQUEUE, at the new
--        boundary: with all four preference columns false an ordinary `booking` title produces NO
--        row (control) while `SOS` produces one, and an already-tombstoned recipient produces none
--        for any kind. This pin does not re-prove 220's propositions; it proves they survived the
--        move.
--   · R1 `push_outbox_dispatch()` posts exactly ONE HTTP call per pending row, with the queued
--        payload, and marks the row `dispatched_at` / `attempts = 1` / `last_error` NULL. A second
--        tick posts NOTHING and returns 0 — a dispatched row is not a candidate.
--   · R2 🔴 **THE FINDING.** A recipient tombstoned BETWEEN enqueue and dispatch is not posted to:
--        the row is CANCELLED and named `recipient_not_dispatchable`, never `dispatched`. CONTROL
--        in the same batch: a live recipient's row, enqueued in the same breath, IS posted.
--   · R3 The same recheck's second question. A token REPLACED between enqueue and dispatch, and a
--        token DELETED between enqueue and dispatch, are both refused and named; a row whose token
--        did not move is posted in the same tick (control).
--   · R4 A cancelled row is skipped ENTIRELY — not posted, not marked dispatched, and its
--        `attempts` does not move, because it is not a candidate rather than a candidate that
--        failed.
--   · A1 `attempts` counts DISPATCH ATTEMPTS, not failures: it rises by one on a successful tick
--        as well, from whatever it was.
--   · A2 The bound. A row at the attempt ceiling is never dispatched and never touched; the same
--        row one below the ceiling is (control). That pair is what makes the ceiling a bound
--        rather than a number in a declare block.
--   · A3 The failure path, exercised: with the pg_net stub raising, a tick leaves the row pending
--        with `attempts` raised and the error recorded; at the ceiling it stops retrying and says
--        `gave_up`. See FIXTURE NOTE ③ — this is the one arm that edits the shim.
--   · D1 `delete_my_account_tx` cancels the caller's UNDISPATCHED rows, in its own transaction,
--        naming `account_deleted`, and reports the count. An ALREADY-DISPATCHED row of the same
--        person is untouched — it is a record of something that happened.
--   · L1 The job lock, in SOURCE with comments stripped: a TRY xact lock keyed on the function's
--        own name, taken BEFORE the candidate read, with NO `pg_advisory_unlock` anywhere.
--   · C1 The cron job `push-outbox-dispatch` is registered and active, read back from `cron.job`
--        by all three literals. 0204's VERIFY asserts this at APPLY; this is the standing half,
--        because a property checked only at apply is protected exactly until someone recreates it.
--   · S1 Deployed shape: the queue is sealed (RLS on, zero policies, no client privilege of any
--        kind including TRUNCATE/TRIGGER/REFERENCES); the three definers carry `prosecdef` + an
--        in-body `search_path` and are unreachable by PUBLIC/anon/authenticated; `notify_push`
--        ENQUEUES and no longer calls `net.http_post` at all; and `delete_my_account_tx`'s LIVE
--        body still carries 0138/0190/0191/0202's four landings after 0204 re-declared it.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins) ───
--   · 🔴 **That B8 is CLOSED.** It is NARROWED. `push_outbox_dispatch` re-checks inside its own
--     transaction and then calls `net.http_post`, which is still asynchronous — a deletion
--     committing between that recheck and pg_net's worker firing is still unobserved. 0204 §0c
--     says so; no pin here can say otherwise, because the residual lives in pg_net.
--   · Delivery. `00_shim.sql` stubs `net.http_post` into `net._stub_calls`; what is measured is
--     「the outbox → HTTP step was taken」, never that Expo delivered anything.
--   · The LATENCY the slice costs (0204 §0d: up to one tick, ~59s worst case). A suite runs in one
--     transaction-free psql session and calls the dispatcher directly; it structurally cannot
--     observe a cron cadence. C1 pins the SCHEDULE STRING, which is the closest artifact there is,
--     and the cost itself is a product decision in the migration header, not a pin.
--   · That two overlapping ticks SKIP. An advisory lock is re-entrant within a session, so a
--     second call from this connection acquires it again and runs. That property needs two
--     processes and lives in `90_race_check.sh` arm `RQ`. L1 is the source half; neither is
--     evidence for the other.
--
-- ─── FIXTURE NOTES ───
--  ① Every push measurement is scoped BY TOKEN, never taken as a global `count(*)` delta: suites
--     before this one have already written to `net._stub_calls`, and the dispatcher drains the
--     WHOLE queue including their rows.
--  ② R2's tombstone is stamped ON `profiles.deleted_at` BY HAND, and that is the only honest way
--     to reach the state the finding is about. Calling `delete_my_account_tx` would ALSO delete
--     the token and cancel the row (§D), so the arm could not distinguish 「the dispatch-time
--     recheck worked」 from 「the cancel worked」 — two different guards borrowing one green. The
--     hand-stamp reproduces exactly what MVCC produces: a pending row written by a transaction
--     whose snapshot showed the profile live, and a tombstone that committed after it. D1 owns
--     the real-deletion path and uses the real function.
--  ③ A3 replaces `net.http_post` with a raising version for the length of one arm. The shim IS the
--     harness's model of pg_net, and a pg_net that fails is a state production reaches; there is
--     no other way to execute the `exception` branch. The restore runs on the happy path, in the
--     arm's exception handler, AND as a standalone statement at the end of this file — three
--     guards, because suites are not transactional here (`psql -f`, autocommit) and a stub left
--     broken would be read by every later suite as its own failure. This suite is registered LAST
--     in `harness.sh` for the same reason.
--  ④ `request.jwt.claim.sub` is not used: nothing in this slice reads `auth.uid()`. The one role
--     switch is S1's client-privilege sweep, which is metadata only.
set client_min_messages = warning;

-- The payload the dispatcher actually produced for one token, scoped so a drained backlog cannot
-- be mistaken for this arm's work (FIXTURE NOTE ①).
create or replace function t_pox_posts(p_token text) returns int
language sql as $$
  select count(*)::int from net._stub_calls where body->>'to' = p_token
$$;

-- The queue row for one notification, as jsonb, so an arm can assert several columns at once and
-- REPORT what it saw rather than that something was wrong.
create or replace function t_pox_row(p_noti uuid) returns jsonb
language sql as $$
  select coalesce(to_jsonb(o), '{}'::jsonb) from push_outbox o where o.noti_id = p_noti
$$;

-- One notification INSERT, measured at BOTH boundaries: queue rows produced, HTTP calls produced
-- (which must be zero — the whole point of the slice), and whether the record landed.
create or replace function t_pox_probe(p_profile uuid, p_kind noti_kind, p_title text, p_token text)
returns jsonb language plpgsql as $$
declare v_q0 int; v_q1 int; v_h0 int; v_h1 int; v_row int; v_id uuid;
begin
  select count(*) into v_q0 from push_outbox where profile_id = p_profile and title = p_title;
  v_h0 := t_pox_posts(p_token);
  insert into notifications (profile_id, kind, title, body, ref_id)
       values (p_profile, p_kind, p_title, 'pox-probe', null)
    returning id into v_id;
  select count(*) into v_q1 from push_outbox where profile_id = p_profile and title = p_title;
  v_h1 := t_pox_posts(p_token);
  select count(*) into v_row from notifications where id = v_id;
  return jsonb_build_object('queued', v_q1 - v_q0, 'posted', v_h1 - v_h0,
                            'row', v_row, 'noti', v_id);
end $$;

-- ③ the pg_net stub, broken and restored. Two named functions rather than inline SQL so the
-- restore is one call that can be made from three places and cannot drift between them.
create or replace function t_pox_break_http() returns void language plpgsql as $$
begin
  execute $q$
    create or replace function net.http_post(url text, headers jsonb default '{}'::jsonb,
                                             body jsonb default '{}'::jsonb)
    returns bigint language plpgsql as $b$
    begin raise exception 'pox_stub_down'; end $b$
  $q$;
end $$;

create or replace function t_pox_fix_http() returns void language plpgsql as $$
begin
  -- byte-for-byte 00_shim.sql:50-56
  execute $q$
    create or replace function net.http_post(url text, headers jsonb default '{}'::jsonb,
                                             body jsonb default '{}'::jsonb)
    returns bigint language plpgsql as $b$
    declare v_id bigint;
    begin
      insert into net._stub_calls (url, body) values (url, body) returning id into v_id;
      return v_id;
    end $b$
  $q$;
end $$;

do $$
declare
  live uuid; tomb uuid; moved uuid; gone uuid; ctl uuid; del uuid;
  v jsonb; v_row jsonb; v_res jsonb;
  v_bad text := ''; v_msg text; v_n int; v_src text; v_id uuid; v_id2 uuid; k text;
  T_LIVE  constant text := 'ExponentPushToken[pox-live]';
  T_TOMB  constant text := 'ExponentPushToken[pox-tomb]';
  T_MOVED constant text := 'ExponentPushToken[pox-moved]';
  T_NEW   constant text := 'ExponentPushToken[pox-moved-new]';
  T_GONE  constant text := 'ExponentPushToken[pox-gone]';
  T_CTL   constant text := 'ExponentPushToken[pox-ctl]';
  T_DEL   constant text := 'ExponentPushToken[pox-del]';
begin
  live := t_user('pox_live', 'owner');
  insert into push_tokens (profile_id, token) values (live, T_LIVE);

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-Q1] the enqueue — one row, the same payload, and NOTHING posted
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v := t_pox_probe(live, 'safety'::noti_kind, '즉시 확인하세요', T_LIVE);
    if (v->>'queued')::int is distinct from 1
    then v_bad := v_bad || ' the notification did not enqueue exactly one row (queued='
                        || coalesce(v->>'queued', 'NULL') || ')'; end if;
    -- 🔴 the half that IS the slice: the writing transaction posts nothing at all
    if (v->>'posted')::int is distinct from 0
    then v_bad := v_bad || ' 🔴 the WRITE still posted (posted=' || coalesce(v->>'posted', 'NULL')
                        || ') — notify_push is calling net.http_post and B8''s window is open'; end if;
    if (v->>'row')::int is distinct from 1
    then v_bad := v_bad || ' the notifications ROW did not survive'; end if;

    v_id := (v->>'noti')::uuid;
    v_row := t_pox_row(v_id);
    if v_row->>'token'   is distinct from T_LIVE           then v_bad := v_bad || ' token='   || coalesce(v_row->>'token','NULL'); end if;
    if v_row->>'title'   is distinct from '즉시 확인하세요' then v_bad := v_bad || ' title='   || coalesce(v_row->>'title','NULL'); end if;
    if v_row->>'body'    is distinct from 'pox-probe'      then v_bad := v_bad || ' body='    || coalesce(v_row->>'body','NULL'); end if;
    if v_row->>'kind'    is distinct from 'safety'         then v_bad := v_bad || ' kind='    || coalesce(v_row->>'kind','NULL'); end if;
    if v_row#>>'{data,kind}' is distinct from 'safety'     then v_bad := v_bad || ' data.kind=' || coalesce(v_row#>>'{data,kind}','NULL'); end if;
    if not (v_row ? 'data') or not ((v_row->'data') ? 'ref_id')
    then v_bad := v_bad || ' data has no ref_id key — the Expo payload lost a field the client routes on'; end if;
    if v_row->>'profile_id' is distinct from live::text    then v_bad := v_bad || ' profile_id mismatch'; end if;
    if v_row->>'dispatched_at' is not null                 then v_bad := v_bad || ' born dispatched'; end if;
    if v_row->>'cancelled_at'  is not null                 then v_bad := v_bad || ' born cancelled'; end if;
    if (v_row->>'attempts')::int is distinct from 0        then v_bad := v_bad || ' born with attempts=' || coalesce(v_row->>'attempts','NULL'); end if;

    if v_bad = '' then call _pass('pox','0204-Q1 알림 한 건이 push_outbox 행 하나를 만들고 그 순간에는 아무것도 발송되지 않는다 — 0024/0187/0189 가 net.http_post 로 보내던 네 필드(to·title·body·data{kind,ref_id})가 그대로 큐에 실리고, 행은 미발송·미취소·attempts 0 으로 태어나며 notifications 행은 그대로 남는다. 발송은 §C 의 일이다');
    else v_msg := v_bad; call _fail('pox','0204-Q1 enqueue', v_msg); end if;
  exception when others then call _fail('pox','0204-Q1 enqueue', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-Q2] the 0187/0189 rules still decide the ENQUEUE — they moved, they did not go
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 220 owns those rules; this arm owns 「they survived being moved to a different boundary」.
  begin
    v_bad := '';
    ctl := t_user('pox_prefs', 'owner');
    insert into push_tokens (profile_id, token) values (ctl, T_CTL);
    insert into notification_prefs (profile_id, booking, chat, community, reward)
    values (ctl, false, false, false, false)
    on conflict (profile_id) do update set booking = false, chat = false,
                                           community = false, reward = false;

    -- CONTROL FIRST: an ordinary booking title with booking=false must NOT enqueue. Without it,
    -- 「SOS enqueued」 is equally consistent with 「this fixture enqueues everything」.
    v := t_pox_probe(ctl, 'booking'::noti_kind, '응가 완료', T_CTL);
    if (v->>'queued')::int is distinct from 0
    then v_bad := v_bad || ' CONTROL: an ordinary booking notification enqueued under booking=false'; end if;
    if (v->>'row')::int is distinct from 1
    then v_bad := v_bad || ' CONTROL: the silenced notification lost its ROW'; end if;

    v := t_pox_probe(ctl, 'booking'::noti_kind, 'SOS', T_CTL);
    if (v->>'queued')::int is distinct from 1
    then v_bad := v_bad || ' 🔴 SOS did not enqueue under booking=false — 0189 §A''s urgent family '
                        || 'did not survive the move to the outbox'; end if;

    -- and the enqueue-time tombstone fast path, which 0189 §B owns and 0204 §B keeps verbatim
    tomb := t_user('pox_tomb_q2', 'owner');
    insert into push_tokens (profile_id, token) values (tomb, T_TOMB);
    v_res := delete_my_account_tx(tomb);
    if (v_res->>'tombstoned')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: delete_my_account_tx did not tombstone (' || v_res::text || ')'; end if;
    foreach k in array array['booking', 'safety', 'system'] loop
      v := t_pox_probe(tomb, k::noti_kind, '즉시 확인하세요', T_TOMB);
      if (v->>'queued')::int is distinct from 0
      then v_bad := v_bad || ' a tombstone ENQUEUED for kind=' || k; end if;
    end loop;

    if v_bad = '' then call _pass('pox','0204-Q2 분류 규칙은 경계만 옮겼을 뿐 그대로다 — 네 칸이 모두 false 인 수신자에게 평범한 booking 알림은 큐에 실리지 않고(대조) SOS 는 실리며, 이미 툼스톤인 수신자는 booking·safety·system 어느 것도 실리지 않는다(0189 §B ① 의 빠른 경로). 220 의 명제를 다시 증명하는 게 아니라 그것들이 이동을 견뎠음을 증명한다');
    else v_msg := v_bad; call _fail('pox','0204-Q2 classification survived the move', v_msg); end if;
  exception when others then call _fail('pox','0204-Q2 classification survived the move', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-R1] the dispatch — exactly one post per row, marked, and idempotent
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- drain everything queued so far (including other suites'), so this arm's numbers are its own
    perform push_outbox_dispatch();

    v := t_pox_probe(live, 'safety'::noti_kind, 'R1 하나', T_LIVE);
    v_id := (v->>'noti')::uuid;
    v := t_pox_probe(live, 'safety'::noti_kind, 'R1 둘', T_LIVE);
    v_id2 := (v->>'noti')::uuid;

    v_n := t_pox_posts(T_LIVE);
    if push_outbox_dispatch() < 2
    then v_bad := v_bad || ' the tick reported fewer than the 2 rows it had to send'; end if;
    if t_pox_posts(T_LIVE) - v_n is distinct from 2
    then v_bad := v_bad || ' the tick posted ' || (t_pox_posts(T_LIVE) - v_n) || ' times for 2 rows'; end if;

    foreach k in array array[v_id::text, v_id2::text] loop
      v_row := t_pox_row(k::uuid);
      if v_row->>'dispatched_at' is null
      then v_bad := v_bad || ' a sent row was not marked dispatched'; end if;
      if (v_row->>'attempts')::int is distinct from 1
      then v_bad := v_bad || ' attempts=' || coalesce(v_row->>'attempts','NULL') || ' after one tick'; end if;
      if v_row->>'last_error' is not null
      then v_bad := v_bad || ' a successful send left last_error=' || (v_row->>'last_error'); end if;
      if v_row->>'cancelled_at' is not null
      then v_bad := v_bad || ' a successful send was also cancelled'; end if;
    end loop;

    -- the payload reached the stub intact
    if not exists (select 1 from net._stub_calls
                    where body->>'to' = T_LIVE and body->>'title' = 'R1 하나'
                      and body->>'sound' = 'default' and body#>>'{data,kind}' = 'safety')
    then v_bad := v_bad || ' the posted payload is not the queued one'; end if;

    -- IDEMPOTENT: a dispatched row is not a candidate
    v_n := t_pox_posts(T_LIVE);
    if push_outbox_dispatch() is distinct from 0
    then v_bad := v_bad || ' the second tick claimed to send something'; end if;
    if t_pox_posts(T_LIVE) - v_n is distinct from 0
    then v_bad := v_bad || ' 🔴 the second tick POSTED again — a dispatched row is still a candidate'; end if;
    v_row := t_pox_row(v_id);
    if (v_row->>'attempts')::int is distinct from 1
    then v_bad := v_bad || ' the second tick re-counted an attempt on a dispatched row'; end if;

    if v_bad = '' then call _pass('pox','0204-R1 틱 하나가 대기 행마다 정확히 한 번 발송하고 표시한다 — 두 행이면 두 번, 큐에 실린 페이로드 그대로(to·title·sound·data.kind), dispatched_at·attempts=1·last_error NULL·미취소; 그리고 두 번째 틱은 0 을 돌려주고 아무것도 보내지 않으며 attempts 도 다시 세지 않는다(발송된 행은 후보가 아니다)');
    else v_msg := v_bad; call _fail('pox','0204-R1 dispatch', v_msg); end if;
  exception when others then call _fail('pox','0204-R1 dispatch', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-R2] 🔴 THE FINDING — tombstoned BETWEEN enqueue and dispatch
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- FIXTURE NOTE ② is load-bearing here: the tombstone is stamped BY HAND so this arm measures the
  -- DISPATCH-TIME RECHECK and nothing else. `delete_my_account_tx` would also delete the token and
  -- cancel the row, and the arm would then be green with the recheck deleted.
  begin
    v_bad := '';
    moved := t_user('pox_r2_tomb', 'owner');
    insert into push_tokens (profile_id, token) values (moved, T_MOVED);

    perform push_outbox_dispatch();                      -- clean slate for the counters below
    v := t_pox_probe(moved, 'safety'::noti_kind, 'R2 죽은 뒤', T_MOVED);
    v_id := (v->>'noti')::uuid;
    if (v->>'queued')::int is distinct from 1
    then v_bad := v_bad || ' fixture: the row was not enqueued while the profile was LIVE'; end if;
    -- CONTROL, enqueued in the same breath and never tombstoned
    v := t_pox_probe(live, 'safety'::noti_kind, 'R2 산 사람', T_LIVE);
    v_id2 := (v->>'noti')::uuid;

    -- …and only now does the deletion commit. This is the state MVCC produces when the writing
    -- transaction's snapshot showed the profile alive.
    update profiles set deleted_at = now() where id = moved;

    v_n := t_pox_posts(T_MOVED);
    perform push_outbox_dispatch();
    if t_pox_posts(T_MOVED) - v_n is distinct from 0
    then v_bad := v_bad || ' 🔴 THE TOMBSTONE WAS PUSHED TO — the dispatcher did not re-check the '
                        || 'recipient (posts=' || (t_pox_posts(T_MOVED) - v_n) || ')'; end if;
    v_row := t_pox_row(v_id);
    if v_row->>'dispatched_at' is not null
    then v_bad := v_bad || ' the tombstone''s row is marked dispatched'; end if;
    if v_row->>'cancelled_at' is null
    then v_bad := v_bad || ' the refused row was left pending — it will be re-examined forever'; end if;
    if v_row->>'last_error' is distinct from 'recipient_not_dispatchable'
    then v_bad := v_bad || ' the refusal is not named (last_error='
                        || coalesce(v_row->>'last_error','NULL') || ')'; end if;

    -- THE CONTROL: without it, every 0 above is equally consistent with a dead dispatcher
    v_row := t_pox_row(v_id2);
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' CONTROL: the LIVE recipient''s row in the same tick was not sent'; end if;
    if v_row->>'cancelled_at' is not null
    then v_bad := v_bad || ' CONTROL: the LIVE recipient''s row was cancelled'; end if;

    if v_bad = '' then call _pass('pox','0204-R2 인큐와 발송 사이에 탈퇴한 수신자에게는 발송되지 않는다 (Codex B8) — 살아 있을 때 큐에 실린 행이, 그 뒤 profiles.deleted_at 이 찍히자 발송 직전 재확인에서 거절되고 recipient_not_dispatchable 로 이름 붙어 취소된다(대기로 남지 않는다); 같은 틱의 살아 있는 수신자 행은 그대로 발송된다(대조 — 없으면 위의 0 들은 죽은 디스패처와 구분되지 않는다). 툼스톤은 손으로 찍는다: 진짜 탈퇴는 토큰도 지우고 행도 취소해서 두 가드가 서로의 초록을 빌리게 된다(픽스처 노트 ②)');
    else v_msg := v_bad; call _fail('pox','0204-R2 tombstoned between enqueue and dispatch', v_msg); end if;
  exception when others then call _fail('pox','0204-R2 tombstoned between enqueue and dispatch', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-R3] the recheck's second question — the token moved, or went
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    gone := t_user('pox_r3_gone', 'owner');
    insert into push_tokens (profile_id, token) values (gone, T_GONE);
    del  := t_user('pox_r3_move', 'owner');
    insert into push_tokens (profile_id, token) values (del, T_DEL);

    perform push_outbox_dispatch();
    v := t_pox_probe(gone, 'safety'::noti_kind, 'R3 사라진 토큰', T_GONE);
    v_id := (v->>'noti')::uuid;
    v := t_pox_probe(del, 'safety'::noti_kind, 'R3 바뀐 토큰', T_DEL);
    v_id2 := (v->>'noti')::uuid;
    -- CONTROL: a live recipient whose token does not move, in the same tick
    v := t_pox_probe(live, 'safety'::noti_kind, 'R3 대조', T_LIVE);
    ctl := (v->>'noti')::uuid;

    delete from push_tokens where profile_id = gone;                       -- signed out
    update push_tokens set token = T_NEW where profile_id = del;           -- new device

    v_n := t_pox_posts(T_GONE) + t_pox_posts(T_DEL) + t_pox_posts(T_NEW);
    perform push_outbox_dispatch();
    if t_pox_posts(T_GONE) + t_pox_posts(T_DEL) + t_pox_posts(T_NEW) - v_n is distinct from 0
    then v_bad := v_bad || ' 🔴 a row was posted to a token that no longer belongs to its recipient'; end if;

    foreach k in array array[v_id::text, v_id2::text] loop
      v_row := t_pox_row(k::uuid);
      if v_row->>'dispatched_at' is not null
      then v_bad := v_bad || ' a stale-token row is marked dispatched'; end if;
      if v_row->>'cancelled_at' is null
      then v_bad := v_bad || ' a stale-token row was left pending'; end if;
      if v_row->>'last_error' is distinct from 'recipient_not_dispatchable'
      then v_bad := v_bad || ' the stale-token refusal is not named ('
                          || coalesce(v_row->>'last_error','NULL') || ')'; end if;
    end loop;

    v_row := t_pox_row(ctl);
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' CONTROL: the unchanged token''s row was not sent in the same tick'; end if;

    if v_bad = '' then call _pass('pox','0204-R3 인큐와 발송 사이에 토큰이 바뀌거나 사라지면 그 행은 나가지 않는다 — 로그아웃(행 삭제)도, 새 기기(값 교체)도 둘 다 recipient_not_dispatchable 로 취소되고 옛 토큰으로도 새 토큰으로도 발송되지 않는다; 같은 틱에서 토큰이 그대로인 수신자는 받는다(대조). 0189 §C 는 툼스톤의 토큰 쓰기를 막을 뿐 평범한 재등록은 막지 않는다 — 이미 주소가 적힌 행이 그 주소보다 오래 살면 안 된다');
    else v_msg := v_bad; call _fail('pox','0204-R3 stale token', v_msg); end if;
  exception when others then call _fail('pox','0204-R3 stale token', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-R4] a cancelled row is not a failed candidate — it is not a candidate
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform push_outbox_dispatch();
    v := t_pox_probe(live, 'safety'::noti_kind, 'R4 취소됨', T_LIVE);
    v_id := (v->>'noti')::uuid;
    update push_outbox set cancelled_at = now(), last_error = 'pox_hand_cancel'
     where noti_id = v_id;

    v_n := t_pox_posts(T_LIVE);
    perform push_outbox_dispatch();
    v_row := t_pox_row(v_id);
    if t_pox_posts(T_LIVE) - v_n is distinct from 0
    then v_bad := v_bad || ' 🔴 a cancelled row was posted'; end if;
    if v_row->>'dispatched_at' is not null
    then v_bad := v_bad || ' a cancelled row was marked dispatched'; end if;
    if (v_row->>'attempts')::int is distinct from 0
    then v_bad := v_bad || ' a cancelled row was counted as an attempt (attempts='
                        || coalesce(v_row->>'attempts','NULL') || ') — it entered the candidate set'; end if;
    if v_row->>'last_error' is distinct from 'pox_hand_cancel'
    then v_bad := v_bad || ' the cancel reason was overwritten'; end if;

    if v_bad = '' then call _pass('pox','0204-R4 취소된 행은 후보 집합에 들어가지도 않는다 — 발송 0, dispatched_at 미설정, 그리고 **attempts 가 움직이지 않는다**(움직였다면 후보로 들어와 거절된 것이고, 그건 다른 이야기다); 취소 사유도 덮이지 않는다');
    else v_msg := v_bad; call _fail('pox','0204-R4 cancelled rows are skipped', v_msg); end if;
  exception when others then call _fail('pox','0204-R4 cancelled rows are skipped', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-A1/A2] attempts counts ATTEMPTS, and the ceiling is a bound
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform push_outbox_dispatch();

    -- A1: a SUCCESSFUL tick still raises the counter, from wherever it was. If attempts only
    -- counted failures, a row whose failure happens BEFORE the counter (an error in the recheck,
    -- a backend killed mid-loop) would retry forever and the ceiling would never be reached.
    v := t_pox_probe(live, 'safety'::noti_kind, 'A1 시도 계수', T_LIVE);
    v_id := (v->>'noti')::uuid;
    update push_outbox set attempts = 2 where noti_id = v_id;
    perform push_outbox_dispatch();
    v_row := t_pox_row(v_id);
    if (v_row->>'attempts')::int is distinct from 3
    then v_bad := v_bad || ' A1: a successful tick left attempts='
                        || coalesce(v_row->>'attempts','NULL') || ', expected 3'; end if;
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' A1: the row below the ceiling was not sent'; end if;

    -- A2: the ceiling. A row AT it is never a candidate; the same row one BELOW it is (control),
    -- and that pair is what makes 5 a bound rather than a number in a declare block.
    v := t_pox_probe(live, 'safety'::noti_kind, 'A2 천장', T_LIVE);
    v_id := (v->>'noti')::uuid;
    update push_outbox set attempts = 5 where noti_id = v_id;
    v := t_pox_probe(live, 'safety'::noti_kind, 'A2 천장 아래', T_LIVE);
    v_id2 := (v->>'noti')::uuid;
    update push_outbox set attempts = 4 where noti_id = v_id2;

    v_n := t_pox_posts(T_LIVE);
    perform push_outbox_dispatch();
    if t_pox_posts(T_LIVE) - v_n is distinct from 1
    then v_bad := v_bad || ' A2: the tick posted ' || (t_pox_posts(T_LIVE) - v_n)
                        || ' times, expected exactly 1 (the row below the ceiling)'; end if;
    v_row := t_pox_row(v_id);
    if v_row->>'dispatched_at' is not null
    then v_bad := v_bad || ' 🔴 A2: a row AT the ceiling was dispatched — there is no bound'; end if;
    if (v_row->>'attempts')::int is distinct from 5
    then v_bad := v_bad || ' A2: a row at the ceiling was touched (attempts='
                        || coalesce(v_row->>'attempts','NULL') || ')'; end if;
    v_row := t_pox_row(v_id2);
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' CONTROL: the row one BELOW the ceiling was not sent — the predicate '
                        || 'excludes more than the ceiling'; end if;

    if v_bad = '' then call _pass('pox','0204-A1/A2 attempts 는 실패가 아니라 **시도** 를 센다(성공한 틱도 2→3 으로 올린다 — 재확인 자체가 터지는 행도 한도에 걸려야 하기 때문), 그리고 천장은 진짜 한도다: attempts=5 행은 발송되지도 건드려지지도 않고 attempts=4 행은 같은 틱에 나간다(대조 — 없으면 후보 술어가 천장보다 넓게 막고 있어도 초록이다)');
    else v_msg := v_bad; call _fail('pox','0204-A1/A2 attempts and the ceiling', v_msg); end if;
  exception when others then call _fail('pox','0204-A1/A2 attempts and the ceiling', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-A3] the failure path — the one arm that edits the shim (FIXTURE NOTE ③)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform push_outbox_dispatch();
    v := t_pox_probe(live, 'safety'::noti_kind, 'A3 실패', T_LIVE);
    v_id  := (v->>'noti')::uuid;
    v := t_pox_probe(live, 'safety'::noti_kind, 'A3 포기', T_LIVE);
    v_id2 := (v->>'noti')::uuid;
    update push_outbox set attempts = 4 where noti_id = v_id2;   -- one attempt from the ceiling

    perform t_pox_break_http();
    perform push_outbox_dispatch();
    perform t_pox_fix_http();

    -- ⓐ a failure below the ceiling: counted, recorded, STILL PENDING (the next tick retries)
    v_row := t_pox_row(v_id);
    if (v_row->>'attempts')::int is distinct from 1
    then v_bad := v_bad || ' a failed send did not count an attempt (attempts='
                        || coalesce(v_row->>'attempts','NULL') || ') — it would retry forever'; end if;
    if v_row->>'dispatched_at' is not null
    then v_bad := v_bad || ' 🔴 a row whose post RAISED is marked dispatched'; end if;
    if v_row->>'cancelled_at' is not null
    then v_bad := v_bad || ' a single failure gave up immediately'; end if;
    if coalesce(v_row->>'last_error', '') not like '%pox_stub_down%'
    then v_bad := v_bad || ' the failure was not recorded (last_error='
                        || coalesce(v_row->>'last_error','NULL') || ')'; end if;
    if coalesce(v_row->>'last_error', '') like 'gave_up%'
    then v_bad := v_bad || ' a first failure was reported as a give-up'; end if;

    -- ⓑ a failure AT the ceiling: it stops, and it says so by name
    v_row := t_pox_row(v_id2);
    if (v_row->>'attempts')::int is distinct from 5
    then v_bad := v_bad || ' the ceiling row''s attempt was not counted'; end if;
    if v_row->>'cancelled_at' is null
    then v_bad := v_bad || ' 🔴 the ceiling was reached and the row is still pending'; end if;
    if coalesce(v_row->>'last_error', '') not like 'gave_up:%'
    then v_bad := v_bad || ' the give-up is not named (last_error='
                        || coalesce(v_row->>'last_error','NULL') || ')'; end if;

    -- ⓒ and the stub really is back — otherwise every later suite reads a broken pg_net as its own
    v_n := t_pox_posts(T_LIVE);
    perform push_outbox_dispatch();
    if t_pox_posts(T_LIVE) - v_n < 1
    then v_bad := v_bad || ' the restored stub does not post — the retry of ⓐ did not land'; end if;
    v_row := t_pox_row(v_id);
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' the row that failed once was not retried on the next tick'; end if;
    if v_row->>'last_error' is not null
    then v_bad := v_bad || ' a successful retry did not clear last_error'; end if;

    if v_bad = '' then call _pass('pox','0204-A3 발송이 터지는 경로 — pg_net 스텁을 예외를 던지는 것으로 바꿔 실행: 천장 아래 행은 attempts 가 오르고 사유가 기록되며 **대기 상태로 남아** 다음 틱에 재시도돼 성공하고 last_error 가 지워진다; 천장에 닿은 행은 gave_up 으로 이름 붙어 취소된다. 스텁 복원은 정상 경로·예외 처리기·파일 끝 세 곳에서 한다(픽스처 노트 ③ — 스위트는 autocommit 이라 망가진 스텁은 이후 모든 스위트의 「자기 실패」로 읽힌다)');
    else v_msg := v_bad; call _fail('pox','0204-A3 the failure path', v_msg); end if;
  exception when others then
    begin perform t_pox_fix_http(); exception when others then null; end;
    call _fail('pox','0204-A3 the failure path', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-D1] the deletion cancels its own pending queue, in its own transaction
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ THIS PIN ASSERTS THE MARKER, NOT THE ABSENCE OF A PUSH, and that is deliberate. With §C's
  --   recheck present a pending row for a tombstone produces no push either way, so 「nothing was
  --   sent」 would be green with §D deleted — a pin that cannot distinguish the fix from its
  --   absence. What §D alone produces is the CANCEL AT COMMIT, with a reason, without waiting for
  --   a tick. That is what is measured here.
  begin
    v_bad := '';
    del := t_user('pox_del', 'owner');
    insert into push_tokens (profile_id, token) values (del, 'ExponentPushToken[pox-del2]');
    perform push_outbox_dispatch();

    -- one pending row …
    v := t_pox_probe(del, 'safety'::noti_kind, 'D1 대기 중', 'ExponentPushToken[pox-del2]');
    v_id := (v->>'noti')::uuid;
    -- … and one ALREADY SENT row, which must be left exactly as it is
    v := t_pox_probe(del, 'safety'::noti_kind, 'D1 이미 나간 것', 'ExponentPushToken[pox-del2]');
    v_id2 := (v->>'noti')::uuid;
    update push_outbox set dispatched_at = now(), attempts = 1 where noti_id = v_id2;

    v_res := delete_my_account_tx(del);
    if (v_res->>'tombstoned')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: the deletion was refused (' || left(v_res::text, 160) || ')'; end if;

    v_row := t_pox_row(v_id);
    if v_row->>'cancelled_at' is null
    then v_bad := v_bad || ' 🔴 a pending push survived the account deletion uncancelled'; end if;
    if v_row->>'last_error' is distinct from 'account_deleted'
    then v_bad := v_bad || ' the cancel is not named account_deleted (last_error='
                        || coalesce(v_row->>'last_error','NULL') || ')'; end if;
    if v_row->>'dispatched_at' is not null
    then v_bad := v_bad || ' the cancelled row was marked dispatched'; end if;

    -- CONTROL: the record of what already happened is not rewritten
    v_row := t_pox_row(v_id2);
    if v_row->>'cancelled_at' is not null
    then v_bad := v_bad || ' CONTROL: an ALREADY-DISPATCHED row was cancelled retroactively — '
                        || 'the queue is a record as well as a queue'; end if;
    if v_row->>'dispatched_at' is null
    then v_bad := v_bad || ' CONTROL: the dispatched row lost its mark'; end if;

    -- and the deletion REPORTS it, so an operator reading the receipt can see the queue was recalled
    if (v_res#>>array['deleted','push_outbox_cancelled'])::int is distinct from 1
    then v_bad := v_bad || ' the deletion receipt does not report the cancelled queue ('
                        || coalesce(v_res#>>array['deleted','push_outbox_cancelled'], 'absent') || ')'; end if;

    if v_bad = '' then call _pass('pox','0204-D1 탈퇴는 자기 대기 큐를 같은 트랜잭션에서 취소한다 — 아직 안 나간 행은 cancelled_at + account_deleted 로 표시되고, 이미 나간 행은 손대지 않으며(대조 — 큐는 기록이기도 하다), 탈퇴 영수증이 취소 건수를 보고한다. **푸시가 안 갔다** 가 아니라 **표시** 를 단언한다: §C 의 재확인이 있으면 푸시는 어느 쪽이든 안 가므로, 부재를 단언하는 핀은 §D 를 지워도 초록이다');
    else v_msg := v_bad; call _fail('pox','0204-D1 deletion cancels the queue', v_msg); end if;
  exception when others then call _fail('pox','0204-D1 deletion cancels the queue', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-L1] the job lock, in SOURCE — the skip itself needs two processes (90_race_check RQ)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- comments stripped, and a NO-SOURCE arm: `position(x in NULL)` is NULL and a bare IF on NULL
    -- never fires, so an absent function must fail LOUDLY rather than silently.
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = 'push_outbox_dispatch';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(push_outbox_dispatch)';
    else
      if position('pg_try_advisory_xact_lock(hashtextextended(''push_outbox_dispatch'', 0))' in v_src) = 0
      then v_bad := v_bad || ' the TRY xact job lock keyed on the function''s own name is gone'; end if;
      if not (position('pg_try_advisory_xact_lock' in v_src) > 0
              and position('pg_try_advisory_xact_lock' in v_src) < position('from push_outbox o' in v_src))
      then v_bad := v_bad || ' the job lock is not taken BEFORE the candidate read'; end if;
      if (v_src ~ 'pg_advisory_unlock') is distinct from false
      then v_bad := v_bad || ' a session unlock is present — an early release re-opens the window'; end if;
      if (v_src ~ 'pg_advisory_xact_lock\(') is distinct from false
      then v_bad := v_bad || ' the lock QUEUES (pg_advisory_xact_lock, not the TRY form) — a slow '
                          || 'predecessor would pile every minute''s tick behind it'; end if;
      -- and the recheck sits before the post, which no behavioural arm can see as an ORDER
      if not (position('pr.deleted_at is null' in v_src) > 0
              and position('pr.deleted_at is null' in v_src) < position('net.http_post' in v_src))
      then v_bad := v_bad || ' the recipient recheck is not taken BEFORE the post'; end if;
      if position('pt.token = r.token' in v_src) = 0
      then v_bad := v_bad || ' the token identity is not re-checked at dispatch'; end if;
    end if;
    -- the CRUDE control (the standing rule: run the crudest version beside a new detector). The
    -- raw source must contain the lock too — if the strip ever eats the body, the arms above would
    -- pass on an empty string.
    if position('pg_try_advisory_xact_lock' in
                (select p.prosrc from pg_proc p
                  where p.pronamespace = 'public'::regnamespace
                    and p.proname = 'push_outbox_dispatch')) = 0
    then v_bad := v_bad || ' CRUDE: the raw source has no advisory lock at all'; end if;

    if v_bad = '' then call _pass('pox','0204-L1 잡 락의 형태 — 주석을 벗긴 소스에서 함수 자기 이름으로 잠그는 TRY xact 락이 첫 후보를 읽기 전에 잡히고, 세션 언락은 어디에도 없으며(이른 해제는 닫으려던 창을 다시 연다), 대기형 pg_advisory_xact_lock 도 아니다; 수신자 재확인은 발송보다 앞이고 토큰 동일성도 다시 본다. 크루드 대조 포함. **건너뜀 자체는 두 프로세스가 필요하다** — 같은 세션에서는 자문 락이 재진입 가능하므로 90_race_check.sh RQ 가 소유한다');
    else v_msg := v_bad; call _fail('pox','0204-L1 the job lock', v_msg); end if;
  exception when others then call _fail('pox','0204-L1 the job lock', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-C1] the cron job, read back from cron.job — the STANDING half of 0204's VERIFY
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n
      from cron.job
     where jobname  = 'push-outbox-dispatch'
       and active
       and schedule = '* * * * *'
       and command  = 'select push_outbox_dispatch()';
    if v_n is distinct from 1
    then v_bad := v_bad || ' expected exactly one active push-outbox-dispatch row matching all '
                        || 'three literals, found ' || coalesce(v_n::text, 'NULL'); end if;
    -- the control that stops this passing on a registry that contains everything
    if exists (select 1 from cron.job where jobname = 'push-outbox-dispatch-not-a-real-job')
    then v_bad := v_bad || ' CONTROL: cron.job answers for a name nobody registered'; end if;

    if v_bad = '' then call _pass('pox','0204-C1 크론 잡이 실제로 등록돼 있다 — jobname·schedule·command 세 리터럴 전부로 cron.job 에서 되읽는다. 0204 의 VERIFY 는 적용 시점에 같은 것을 보지만, 적용 시점에만 검사된 성질은 누군가 그 객체를 다시 만드는 순간까지만 보호된다. 등록이 실패하면 모든 푸시가 조용히 멈추므로 이건 notice 가 아니라 abort 다');
    else v_msg := v_bad; call _fail('pox','0204-C1 the cron job', v_msg); end if;
  exception when others then call _fail('pox','0204-C1 the cron job', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0204-S1] deployed shape — the seal, the definers, and the four landings 0204 had to carry
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (select c.relrowsecurity from pg_class c where c.oid = 'push_outbox'::regclass) is not true
    then v_bad := v_bad || ' push_outbox has RLS OFF — policies are inert on a table with it off, '
                        || 'and the client roles hold default-privilege grants'; end if;
    if (select count(*) from pg_policy where polrelid = 'push_outbox'::regclass) <> 0
    then v_bad := v_bad || ' push_outbox has policies — it is meant to be reachable by nothing'; end if;
    select coalesce(string_agg(g || ':' || p, ' '), '') into v_msg
      from unnest(array['anon','authenticated']) g,
           unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES']) p
     where has_table_privilege(g, 'push_outbox', p);
    if v_msg <> '' then v_bad := v_bad || ' a client role holds table privileges: ' || v_msg; end if;

    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname in ('notify_push', 'push_outbox_dispatch', 'delete_my_account_tx')
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) <> 3
    then v_bad := v_bad || ' definer+search_path count is not 3'; end if;
    select string_agg(p.oid::regprocedure::text, ', ') into v_src from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push', 'push_outbox_dispatch', 'delete_my_account_tx')
       and (has_function_privilege('public', p.oid, 'execute')
         or has_function_privilege('anon',   p.oid, 'execute')
         or has_function_privilege('authenticated', p.oid, 'execute'));
    if v_src is not null then v_bad := v_bad || ' a client role can execute: ' || v_src; end if;
    if has_function_privilege('service_role', 'push_outbox_dispatch()', 'execute') is not true
    then v_bad := v_bad || ' service_role cannot run the dispatcher — the cron job is dead'; end if;

    -- the trigger that starts all of this is still the one 0024 created, and ENABLED (state, never
    -- pg_get_triggerdef's shape — the standing law)
    if (select count(*) from pg_trigger
         where tgrelid = 'notifications'::regclass and tgname = 'notifications_push'
           and not tgisinternal and tgenabled = 'O') <> 1
    then v_bad := v_bad || ' notifications_push is missing or not tgenabled=O'; end if;

    -- notify_push's source, comments stripped, with a NO-SOURCE arm
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
    else
      if position('insert into push_outbox' in v_src) = 0
      then v_bad := v_bad || ' notify_push does not enqueue'; end if;
      if position('net.http_post' in v_src) <> 0
      then v_bad := v_bad || ' 🔴 notify_push still posts directly — B8''s window is back'; end if;
    end if;

    -- 🔴 the four landings 0204 §D had to carry forward on a body it copied from the CATALOG
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = 'delete_my_account_tx';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
    else
      if position('update push_outbox' in v_src) = 0
      then v_bad := v_bad || ' [0204 §D] the deletion does not cancel the queue'; end if;
      if position('enqueue_billing_key_revocation' in v_src) = 0
      then v_bad := v_bad || ' [0138 §F] the billing-key revocation enqueue was lost in the copy'; end if;
      if position('paid_payout_id is null' in v_src) = 0
      then v_bad := v_bad || ' [0190 §B] the paid-marker retention predicate was lost in the copy'; end if;
      if position('{"redacted": true}' in v_src) = 0
      then v_bad := v_bad || ' [0202 §B②] the gear_claims delivery redaction was lost in the copy'; end if;
      v_n := (length(v_src) - length(replace(v_src, 'using detail = coalesce(v_block_id::text', '')))
             / length('using detail = coalesce(v_block_id::text');
      if v_n is distinct from 9
      then v_bad := v_bad || ' [0191 §A] the detail arms are ' || coalesce(v_n::text, 'NULL')
                          || ', expected 9 — the copy carried a loss forward'; end if;
    end if;

    if v_bad = '' then call _pass('pox','0204-S1 배포 형상 — push_outbox 는 RLS ON·정책 0개·anon/authenticated 가 일곱 동사 중 하나도 못 가지는 봉인이고(TRUNCATE·TRIGGER·REFERENCES 포함 — 이것들은 RLS 가 못 막는다), 세 definer 는 prosecdef + 본문 search_path 에 클라이언트 실행 불가이며 service_role 은 디스패처를 부를 수 있고(못 부르면 크론이 죽는다), notifications_push 는 tgenabled=O, notify_push 는 인큐만 하고 net.http_post 를 **전혀** 부르지 않는다; 그리고 카탈로그에서 복사해 온 delete_my_account_tx 본문에 0138·0190·0191(9개, 세어서)·0202 네 착륙이 전부 남아 있다');
    else v_msg := v_bad; call _fail('pox','0204-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('pox','0204-S1 deployed shape', sqlerrm); end;
end $$;

-- FIXTURE NOTE ③'s third guard: a standalone restore, so a `do` block that died before its own
-- handler could run still leaves pg_net's stub as `00_shim.sql` wrote it. Idempotent by design.
select t_pox_fix_http();
