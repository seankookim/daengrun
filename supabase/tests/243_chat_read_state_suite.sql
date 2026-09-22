-- ═══ 243 — 0212: chat gets a READ STATE (unread count · monotonic mark-read · read receipt)
-- ═══        0212-M1 · U1 · U2 · G1 · R1 · S1, tag `crd`
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · M1 **A READ POSITION NEVER MOVES BACKWARDS, AND IT DOES MOVE FORWARD.** Three arms and the
--        first two are the controls that make the third mean something: a first call on a thread
--        with no row CREATES one (0 → 1, a delta this suite caused); a stored position in the PAST
--        is advanced by a call and the RETURNED value equals the value that is now STORED; a
--        stored position in the FUTURE is left exactly where it was — and the call still reports
--        the stored truth rather than the value it tried to write. Without the backwards arm, 「the
--        write happened」 and 「the write happened monotonically」 are the same observation.
--   · U1 **THE COUNT IS THE OTHER PARTY'S NEWER MESSAGES, COUNTED — never the caller's own, never
--        a total.** 🔴 The fixture sits where the rules DISAGREE: the owner has sent messages too,
--        so 「peer messages」 (3) · 「all messages」 (5) · 「my messages」 (2) are three different
--        numbers and only one of them is right. Marking read drops the owner to 0 while the
--        RUNNER's number is unchanged in the same tick — the control that the drop is attributable
--        to the mark and not to time passing. Then the owner sends TWO MORE messages AFTER their
--        own read position, which is the one place where excluding the caller's own messages and
--        including them differ by a number the owner can see (0 vs 2), and the count stays 0 until
--        the RUNNER speaks.
--   · U2 **THE LIST IS THE THREADS THE CALLER COULD REPLY IN, and a zero is not an absence.** One
--        owner holds three threads: a `confirmed` one with messages, a `cancelled_owner` one with
--        messages, and a `confirmed` one with none. The cancelled thread is ABSENT — and its
--        messages are counted directly first, so 「absent」 is distinguishable from 「there was
--        nothing to report」. The quiet thread IS returned, with 0 and a NULL last_message_at,
--        because a measured zero and a thread this read says nothing about are different facts.
--        🔴 The fixture is in the zone where `is_booking_party` and `is_booking_party_active`
--        disagree (they agree on `confirmed`), so a suite whose only fixture was confirmed would
--        be green under either predicate.
--   · G1 **THE PARTY GATE IS FIRST, AND IT IS NOT AN EXISTENCE ORACLE.** For BOTH thread-taking
--        functions: a stranger gets `not_party` for a real thread and the IDENTICAL word for a
--        uuid no thread has; anonymous gets `not_authenticated` from all three functions; the
--        party succeeds (the control that the refusals are about identity and not about a broken
--        function). 🔴 And the gate precedes the WRITE, measured rather than read: after every
--        refused call the thread's `chat_reads` row count is still 0, and the owner's one call
--        takes it to 1.
--   · R1 **THE RECEIPT IS THE COUNTERPART'S TIME AND ONLY THE COUNTERPART'S.** Before anyone
--        reads, both parties get exactly one row holding NULL. After the OWNER reads, the runner
--        sees the owner's time and the owner still sees NULL — two different answers from one
--        thread, which is what makes it the counterpart's rather than 「some time」. With both
--        parties' positions stored at DIFFERENT values, each caller reads the OTHER's, so neither
--        answer could be produced by returning the caller's own row. And a booking with no runner
--        yet answers one row of NULL — never a reader who does not exist.
--   · S1 **DEPLOYED SHAPE.** The table's RLS, its SELECT-only policy set, its grants in BOTH
--        directions, its columns and its primary key; three definers with `prosecdef` and the
--        in-body `search_path`; ACLs by value both ways; `my_chat_unread` with ZERO input
--        arguments (the gate there is an ABSENCE — a `p_profile` added later reddens no
--        behavioural arm where caller and subject are one person, 0203 E4's law); and the three
--        bodies with COMMENTS STRIPPED, each with a NO-SOURCE arm so an absent function fails
--        LOUDLY, plus a TWO-SIDED control that the stripper actually ran.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · The RLS policy 「chat reads self」 as a POLICY. The harness runs as `postgres`, and the write
--     privileges this file's §A revokes are the layer that actually stops a client; S1 asserts the
--     policy's SHAPE (one SELECT policy, zero write policies) and the grant matrix by value, which
--     is what a catalog can see. Executing the policy would need a `set role authenticated` arm
--     whose refusal is indistinguishable from the missing grant — two layers, one observation.
--   · Concurrency. `greatest` in the on-conflict arm is what makes the write order-independent;
--     the harness is one session and cannot produce two commits racing. The property is asserted
--     by the arm that a stored FUTURE position survives a call, which is the same inequality seen
--     from the outside.
--   · The client screens. `app/test/chat-read.test.cjs` pins the badge/receipt rules; no SQL pin
--     can see a `.tsx` route module.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper, and cleared again at the end
--     of the DO block: a leftover claim would make a 「no caller」 arm silently measure the wrong
--     thing (218 ①'s rule).
--  ② 🔴 EVERY MESSAGE CARRIES AN EXPLICIT `created_at`, AND THAT IS LOAD-BEARING. `now()` is
--     transaction-start time and this whole suite is one transaction, so messages inserted with
--     the column default would ALL share one timestamp — the same timestamp `chat_mark_read`
--     writes. Every `created_at > last_read_at` comparison would then be false and the suite would
--     sit exactly in the degenerate zone where a correct implementation and a broken one give the
--     same answer. Times are written as offsets around `now()`: a message 「before the read」 is
--     `now() - Ns`, a message that 「arrived after it」 is `now() + Ns`.
--  ③ Where a stored read position has to be somewhere `chat_mark_read` would not put it (the
--     past, the future, or a second party's), the row is written DIRECTLY as `postgres`. That is
--     a fixture, not a product path — the product has exactly one writer and §S1 asserts it.
set client_min_messages = warning;

-- A booking + its chat thread, on an existing pair. `p_status` is the whole point: the live-set
-- arm needs a status the reply predicate refuses.
create or replace function t_crd_thread(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                        p_status booking_status,
                                        out bk uuid, out th uuid)
language plpgsql as $$
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, p_status, now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bk;
  insert into chat_threads (booking_id) values (bk) returning id into th;
end $$;

create or replace function t_crd_world(p_tag text, p_status booking_status,
                                       out o uuid, out r uuid, out d uuid, out rt uuid,
                                       out bk uuid, out th uuid)
language plpgsql as $$
begin
  o  := t_user('crd_' || p_tag || '_o', 'owner');
  r  := t_user('crd_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'crd-' || p_tag);
  rt := t_route('crd 코스 ' || p_tag);
  select w.bk, w.th into bk, th from t_crd_thread(o, r, d, rt, p_status) w;
end $$;

-- ② the explicit clock.
create or replace function t_crd_msg(p_thread uuid, p_sender uuid, p_body text, p_at timestamptz)
returns bigint language sql as $$
  insert into chat_messages (thread_id, sender_id, body, created_at)
  values (p_thread, p_sender, p_body, p_at)
  returning id
$$;

-- What the product's ONE writer does, as a named caller. `p_uid` NULL = anonymous.
create or replace function t_crd_mark(p_uid uuid, p_thread uuid) returns jsonb
language plpgsql as $$
declare v timestamptz;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select m.last_read_at into v from chat_mark_read(p_thread) m;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_crd_receipt(p_uid uuid, p_thread uuid) returns jsonb
language plpgsql as $$
declare v timestamptz; v_rows int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  -- `count(*)` and `max(...)` over the whole result, so 「exactly one row」 and 「the value」 are
  -- one observation: a function that returned zero rows would report rows = 0 here rather than
  -- being indistinguishable from one row of NULL.
  select count(*)::int, max(s.last_read_at) into v_rows, v from chat_thread_read_state(p_thread) s;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('rows', v_rows, 'at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- One booking's row out of the caller's whole list. `found` distinguishes 「absent」 from 「zero」.
create or replace function t_crd_unread(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select jsonb_build_object('found', true, 'n', u.unread_count,
                            'last', u.last_message_at, 'thread', u.thread_id)
    into v
    from my_chat_unread() u
   where u.booking_id = p_booking;
  perform set_config('request.jwt.claim.sub', '', true);
  return coalesce(v, jsonb_build_object('found', false));
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- The whole list, as a sorted array of booking ids plus its length.
create or replace function t_crd_list(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb; v_n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select count(*)::int, coalesce(jsonb_agg(x.booking_id order by x.booking_id), '[]'::jsonb)
    into v_n, v
    from (select u.booking_id from my_chat_unread() u) x;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('n', v_n, 'ids', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- ③ the stored row, read as postgres — the fact the RPC's answer is compared against.
create or replace function t_crd_stored(p_thread uuid, p_uid uuid) returns timestamptz
language sql as $$
  select c.last_read_at from chat_reads c where c.thread_id = p_thread and c.profile_id = p_uid
$$;

create or replace function t_crd_rows(p_thread uuid) returns int
language sql as $$ select count(*)::int from chat_reads c where c.thread_id = p_thread $$;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid; bk uuid; th uuid;
  o2 uuid; r2 uuid; d2 uuid; rt2 uuid;
  bk_live uuid; th_live uuid; bk_dead uuid; th_dead uuid; bk_quiet uuid; th_quiet uuid;
  bk_match uuid; th_match uuid;
  stranger uuid;
  v jsonb; v2 jsonb; v_bad text; v_msg text; v_n int; v_src text; v_raw text;
  t0 timestamptz; t_planted timestamptz; t_owner timestamptz; t_runner timestamptz;
  v_before int; v_after int;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
  t0 := now();

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-M1] the read position moves forward and never backwards
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.d, w.rt, w.bk, w.th into o, r, d, rt, bk, th from t_crd_world('m1', 'confirmed') w;

    -- arm A — the control that a call WRITES AT ALL. Zero rows before, one after; the delta is
    -- this suite's, not a state it found lying around.
    v_before := t_crd_rows(th);
    v := t_crd_mark(o, th);
    v_after := t_crd_rows(th);
    if v ? 'raised' then v_bad := v_bad || ' 첫 호출이 거절됐다: ' || (v->>'raised'); end if;
    if v_before is distinct from 0 then v_bad := v_bad || ' 픽스처가 이미 읽음 행을 갖고 있었다'; end if;
    if v_after is distinct from 1 then v_bad := v_bad || ' 첫 호출이 행을 만들지 않았다 (after=' || coalesce(v_after::text,'∅') || ')'; end if;
    if (v->>'at')::timestamptz is distinct from t_crd_stored(th, o)
    then v_bad := v_bad || ' 반환값이 저장값과 다르다 (첫 호출)'; end if;

    -- arm B — a position in the PAST is advanced.
    t_planted := t0 - interval '1 day';
    update chat_reads set last_read_at = t_planted where thread_id = th and profile_id = o;   -- ③
    v := t_crd_mark(o, th);
    if v ? 'raised' then v_bad := v_bad || ' 과거 위치에서의 호출이 거절됐다: ' || (v->>'raised'); end if;
    if (t_crd_stored(th, o) > t_planted) is not true
    then v_bad := v_bad || ' 과거 위치가 앞으로 나아가지 않았다'; end if;
    if (v->>'at')::timestamptz is distinct from t_crd_stored(th, o)
    then v_bad := v_bad || ' 반환값이 저장값과 다르다 (전진)'; end if;

    -- arm C — a position in the FUTURE survives the call, and the call reports the STORED truth.
    -- 🔴 This is the arm the whole pin exists for: without it, 「the write happened」 and 「the
    --    write happened monotonically」 are one observation.
    t_planted := t0 + interval '1 day';
    update chat_reads set last_read_at = t_planted where thread_id = th and profile_id = o;   -- ③
    v := t_crd_mark(o, th);
    if v ? 'raised' then v_bad := v_bad || ' 미래 위치에서의 호출이 거절됐다: ' || (v->>'raised'); end if;
    if t_crd_stored(th, o) is distinct from t_planted
    then v_bad := v_bad || ' 읽음 위치가 뒤로 밀렸다 (저장=' || coalesce(t_crd_stored(th, o)::text,'∅') || ')'; end if;
    if (v->>'at')::timestamptz is distinct from t_planted
    then v_bad := v_bad || ' 호출이 저장된 사실이 아니라 쓰려던 값을 보고했다'; end if;
    if t_crd_rows(th) is distinct from 1 then v_bad := v_bad || ' 같은 (스레드, 사람)에 행이 둘 생겼다'; end if;

    if v_bad = '' then call _pass('crd','0212-M1 읽음 위치는 앞으로만 간다 — 첫 호출이 행을 만들고(0→1 델타), 과거에 심어 둔 위치는 전진하며, **미래에 심어 둔 위치는 그대로 남는다**(뒤로 밀리면 이미 읽은 메시지가 다시 안 읽음이 된다 = 과거에 대한 거짓말). 세 팔 모두 반환값 = 저장값 — 호출은 쓰려던 값이 아니라 저장된 사실을 보고한다');
    else v_msg := v_bad; call _fail('crd','0212-M1 mark_read monotonic', v_msg); end if;
  exception when others then call _fail('crd','0212-M1 mark_read monotonic', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-U1] the count is the OTHER party's newer messages — counted, never estimated
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.d, w.rt, w.bk, w.th into o, r, d, rt, bk, th from t_crd_world('u1', 'confirmed') w;

    -- ② three peer messages and TWO of the caller's own, interleaved, all before any read.
    --    peer=3 · all=5 · mine=2 — three different numbers, so the fixture cannot be satisfied
    --    by a rule that counts the wrong set.
    perform t_crd_msg(th, r, 'r-1', t0 - interval '300 seconds');
    perform t_crd_msg(th, o, 'o-1', t0 - interval '270 seconds');
    perform t_crd_msg(th, r, 'r-2', t0 - interval '240 seconds');
    perform t_crd_msg(th, o, 'o-2', t0 - interval '210 seconds');
    perform t_crd_msg(th, r, 'r-3', t0 - interval '180 seconds');

    v := t_crd_unread(o, bk);
    if (v->>'found')::boolean is not true then v_bad := v_bad || ' 보호자 목록에 이 예약이 없다'; end if;
    if (v->>'n')::int is distinct from 3
    then v_bad := v_bad || ' 보호자 미확인=' || coalesce(v->>'n','∅') || ' (러너가 보낸 3이어야 한다; 5는 내 것까지 센 것, 2는 내 것만 센 것)'; end if;
    if (v->>'last')::timestamptz is distinct from t0 - interval '180 seconds'
    then v_bad := v_bad || ' last_message_at이 실제 최신 행이 아니다'; end if;

    v := t_crd_unread(r, bk);
    if (v->>'n')::int is distinct from 2
    then v_bad := v_bad || ' 러너 미확인=' || coalesce(v->>'n','∅') || ' (보호자가 보낸 2여야 한다)'; end if;

    -- the owner reads. `chat_mark_read` writes now() = t0, which is after every message above.
    v := t_crd_mark(o, th);
    if v ? 'raised' then v_bad := v_bad || ' 보호자 읽음 표시가 거절됐다'; end if;
    v  := t_crd_unread(o, bk);
    v2 := t_crd_unread(r, bk);
    if (v->>'n')::int is distinct from 0 then v_bad := v_bad || ' 읽음 표시 뒤에도 보호자 미확인이 0이 아니다'; end if;
    -- the control: the same tick, the other party's number did NOT move.
    if (v2->>'n')::int is distinct from 2
    then v_bad := v_bad || ' 보호자의 읽음이 러너의 숫자까지 지웠다 (' || coalesce(v2->>'n','∅') || ')'; end if;

    -- 🔴 the divergence zone for the own-message exclusion: the CALLER's own messages, newer than
    --    the caller's own read position. Including them would read 2 where the truth is 0.
    perform t_crd_msg(th, o, 'o-3', t0 + interval '60 seconds');
    perform t_crd_msg(th, o, 'o-4', t0 + interval '120 seconds');
    v  := t_crd_unread(o, bk);
    v2 := t_crd_unread(r, bk);
    if (v->>'n')::int is distinct from 0
    then v_bad := v_bad || ' 내가 보낸 메시지가 나에게 미확인으로 잡힌다 (' || coalesce(v->>'n','∅') || ')'; end if;
    if (v2->>'n')::int is distinct from 4
    then v_bad := v_bad || ' 러너 미확인이 4가 아니다 (' || coalesce(v2->>'n','∅') || ')'; end if;

    -- and the counterpart speaking is what moves it off zero.
    perform t_crd_msg(th, r, 'r-4', t0 + interval '180 seconds');
    v := t_crd_unread(o, bk);
    if (v->>'n')::int is distinct from 1
    then v_bad := v_bad || ' 상대가 말한 뒤에도 보호자 미확인이 1이 아니다 (' || coalesce(v->>'n','∅') || ')'; end if;
    if (v->>'last')::timestamptz is distinct from t0 + interval '180 seconds'
    then v_bad := v_bad || ' last_message_at이 최신 행을 따라오지 않는다'; end if;

    if v_bad = '' then call _pass('crd','0212-U1 미확인 수 = **상대가 보낸, 내 읽음 위치보다 새로운** 메시지의 행 수 — 픽스처는 세 규칙이 서로 다른 답을 내는 자리에 있다(상대 3 · 전체 5 · 내 것 2). 읽음 표시는 보호자를 0으로 내리고 **같은 틱에서 러너의 2는 움직이지 않는다**(그 0이 시간이 아니라 표시 때문임을 붙들어 두는 대조); 그 뒤 보호자가 자기 읽음 위치보다 **뒤에** 두 건을 보내도 0은 0이고(내 것을 세면 2가 나오는 유일한 자리), 상대가 말하자 1이 된다. last_message_at은 언제나 실제 최신 행의 시각');
    else v_msg := v_bad; call _fail('crd','0212-U1 unread counts only the peer', v_msg); end if;
  exception when others then call _fail('crd','0212-U1 unread counts only the peer', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-U2] the live set, and 「zero」 ≠ 「absent」
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o2  := t_user('crd_u2_o', 'owner');
    r2  := t_user('crd_u2_r', 'runner');
    d2  := t_dog(o2, 'crd-u2');
    rt2 := t_route('crd 코스 u2');
    stranger := t_user('crd_u2_x', 'owner');

    select w.bk, w.th into bk_live,  th_live  from t_crd_thread(o2, r2, d2, rt2, 'confirmed') w;
    -- 🔴 `cancelled_owner` is the divergence zone: `is_booking_party` admits it, the reply
    --    predicate `is_booking_party_active` does not (0114's header names why — cancelled_owner
    --    is reachable directly from a pre-acceptance state).
    select w.bk, w.th into bk_dead,  th_dead  from t_crd_thread(o2, r2, d2, rt2, 'cancelled_owner') w;
    select w.bk, w.th into bk_quiet, th_quiet from t_crd_thread(o2, r2, d2, rt2, 'confirmed') w;

    perform t_crd_msg(th_live, r2, 'live-1', t0 - interval '120 seconds');
    perform t_crd_msg(th_live, r2, 'live-2', t0 - interval '60 seconds');
    perform t_crd_msg(th_dead, r2, 'dead-1', t0 - interval '120 seconds');
    perform t_crd_msg(th_dead, r2, 'dead-2', t0 - interval '60 seconds');

    -- the attribution arm: the cancelled thread HAS messages, so its absence below is a decision
    -- rather than an empty world.
    select count(*)::int into v_n from chat_messages m where m.thread_id = th_dead;
    if v_n is distinct from 2 then v_bad := v_bad || ' 취소된 스레드에 애초에 메시지가 없다 — 아래의 부재가 아무것도 뜻하지 않는다'; end if;

    v := t_crd_list(o2);
    if (v->>'n')::int is distinct from 2
    then v_bad := v_bad || ' 목록 길이가 2가 아니다 (' || coalesce(v->>'n','∅') || ')'; end if;
    if ((v->'ids') @> to_jsonb(array[bk_live, bk_quiet])) is not true
    then v_bad := v_bad || ' confirmed 스레드 둘이 목록에 다 있지 않다'; end if;
    if ((v->'ids') ? bk_dead::text) is not false
    then v_bad := v_bad || ' 🔴 취소된 예약의 스레드가 목록에 있다 — 답할 수 없는 방에 배지를 단다'; end if;

    v := t_crd_unread(o2, bk_live);
    if (v->>'found')::boolean is not true or (v->>'n')::int is distinct from 2
    then v_bad := v_bad || ' live 스레드가 2로 안 잡힌다'; end if;

    v := t_crd_unread(o2, bk_dead);
    if (v->>'found')::boolean is not false
    then v_bad := v_bad || ' 취소된 스레드가 조회된다'; end if;

    -- 🔴 「zero」 and 「absent」 are different answers and both must be reachable.
    v := t_crd_unread(o2, bk_quiet);
    if (v->>'found')::boolean is not true
    then v_bad := v_bad || ' 말이 오간 적 없는 live 스레드가 목록에서 빠졌다 — 0과 부재가 같은 답이 된다'; end if;
    if (v->>'n')::int is distinct from 0 then v_bad := v_bad || ' 조용한 스레드가 0이 아니다'; end if;
    if v->>'last' is not null then v_bad := v_bad || ' 말이 없는데 last_message_at이 있다'; end if;

    -- and the stranger sees none of the three.
    v := t_crd_list(stranger);
    if (((v->'ids') ? bk_live::text) or ((v->'ids') ? bk_quiet::text) or ((v->'ids') ? bk_dead::text))
       is not false
    then v_bad := v_bad || ' 낯선 사람이 남의 스레드를 본다'; end if;

    -- anonymous is refused rather than shown an empty list (an empty list is a claim).
    v := t_crd_list(null);
    if coalesce(v->>'raised','') not like '%not_authenticated%'
    then v_bad := v_bad || ' 무기명 호출이 not_authenticated가 아니다 (' || coalesce(v::text,'∅') || ')'; end if;

    if v_bad = '' then call _pass('crd','0212-U2 목록 = **답할 수 있는 방**(is_booking_party_active — 스레드 INSERT·메시지 전송을 재는 그 술어)이고, 0은 부재가 아니다. 한 보호자의 세 스레드: confirmed+메시지는 2로 들어오고, **cancelled_owner+메시지는 빠지며**(그 스레드에 메시지가 2건 있다는 선행 대조 — 부재가 빈 세계가 아니다; 두 술어가 갈라지는 자리다), 말이 없는 confirmed는 **0과 NULL로 들어온다**(측정된 0과 이 읽기가 아무 말도 안 한 스레드는 다른 사실이다). 낯선 사람은 셋 다 못 보고 무기명은 not_authenticated');
    else v_msg := v_bad; call _fail('crd','0212-U2 the live set', v_msg); end if;
  exception when others then call _fail('crd','0212-U2 the live set', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-G1] the party gate is first, and it is not an existence oracle
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.d, w.rt, w.bk, w.th into o, r, d, rt, bk, th from t_crd_world('g1', 'confirmed') w;
    stranger := t_user('crd_g1_x', 'owner');

    -- 🔴 the WRITE has not happened yet, and must not happen below.
    if t_crd_rows(th) is distinct from 0 then v_bad := v_bad || ' 픽스처가 이미 읽음 행을 갖고 있다'; end if;

    v  := t_crd_mark(stranger, th);
    v2 := t_crd_mark(stranger, gen_random_uuid());
    if coalesce(v->>'raised','') not like '%not_party%'  then v_bad := v_bad || ' 낯선 사람의 mark_read가 not_party가 아니다'; end if;
    if (v->>'raised') is distinct from (v2->>'raised')
    then v_bad := v_bad || ' 존재하는 스레드와 없는 스레드가 다른 말을 듣는다 (' || coalesce(v->>'raised','∅') || ' / ' || coalesce(v2->>'raised','∅') || ')'; end if;

    v  := t_crd_receipt(stranger, th);
    v2 := t_crd_receipt(stranger, gen_random_uuid());
    if coalesce(v->>'raised','') not like '%not_party%'  then v_bad := v_bad || ' 낯선 사람의 receipt가 not_party가 아니다'; end if;
    if (v->>'raised') is distinct from (v2->>'raised')
    then v_bad := v_bad || ' receipt가 존재 오라클이 된다'; end if;

    -- the runner is a party and must NOT be refused — the control that not_party is about
    -- identity rather than about the function being broken for everybody.
    v := t_crd_receipt(r, th);
    if v ? 'raised' then v_bad := v_bad || ' 러너(당사자)가 receipt에서 거절됐다: ' || (v->>'raised'); end if;

    v := t_crd_mark(null, th);
    if coalesce(v->>'raised','') not like '%not_authenticated%' then v_bad := v_bad || ' 무기명 mark_read가 not_authenticated가 아니다'; end if;
    v := t_crd_receipt(null, th);
    if coalesce(v->>'raised','') not like '%not_authenticated%' then v_bad := v_bad || ' 무기명 receipt가 not_authenticated가 아니다'; end if;

    -- 🔴 GATE BEFORE THE WRITE, measured: nothing above wrote a row.
    if t_crd_rows(th) is distinct from 0
    then v_bad := v_bad || ' 🔴 거절된 호출이 읽음 행을 남겼다 — 게이트가 쓰기보다 뒤에 있다 (' || t_crd_rows(th)::text || ')'; end if;

    -- the control that the write IS reachable.
    v := t_crd_mark(o, th);
    if v ? 'raised' then v_bad := v_bad || ' 당사자의 mark_read가 거절됐다'; end if;
    if t_crd_rows(th) is distinct from 1 then v_bad := v_bad || ' 당사자의 호출이 행을 만들지 않았다'; end if;

    if v_bad = '' then call _pass('crd','0212-G1 당사자 게이트가 먼저고, 존재 오라클이 아니다 — 낯선 사람은 실재 스레드와 없는 uuid에 **같은 낱말**(not_party)을 듣고, 무기명은 세 함수 모두 not_authenticated이며, 러너(당사자)는 통과한다(거절이 신원의 문제임을 붙드는 대조). 🔴 거절된 호출들 뒤에도 chat_reads 행은 0이고 당사자의 한 번이 1로 만든다 — 게이트가 쓰기보다 **앞**이라는 것은 읽은 사실이 아니라 잰 사실이다');
    else v_msg := v_bad; call _fail('crd','0212-G1 party gate first', v_msg); end if;
  exception when others then call _fail('crd','0212-G1 party gate first', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-R1] the receipt is the COUNTERPART's time and only the counterpart's
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.d, w.rt, w.bk, w.th into o, r, d, rt, bk, th from t_crd_world('r1', 'confirmed') w;

    -- nobody has read: exactly one row, NULL, for both parties.
    v  := t_crd_receipt(o, th);
    v2 := t_crd_receipt(r, th);
    if (v->>'rows')::int is distinct from 1 or (v2->>'rows')::int is distinct from 1
    then v_bad := v_bad || ' 아무도 안 읽었을 때 행이 정확히 1이 아니다'; end if;
    if v->>'at' is not null or v2->>'at' is not null
    then v_bad := v_bad || ' 아무도 안 읽었는데 시각이 나온다'; end if;

    -- the OWNER reads. Now the two parties must get DIFFERENT answers from one thread.
    perform t_crd_mark(o, th);
    t_owner := t_crd_stored(th, o);
    v  := t_crd_receipt(r, th);
    v2 := t_crd_receipt(o, th);
    if (v->>'at')::timestamptz is distinct from t_owner
    then v_bad := v_bad || ' 러너가 보호자의 읽음 시각을 못 본다'; end if;
    -- 🔴 the arm that makes it the counterpart's: returning the CALLER's own row would put the
    --    owner's own time here instead of NULL.
    if v2->>'at' is not null
    then v_bad := v_bad || ' 🔴 보호자가 **자기 자신의** 읽음 시각을 영수증으로 받는다'; end if;

    -- both stored, at DIFFERENT values — so neither answer can be 「some time in this thread」.
    t_runner := t0 + interval '1 hour';
    insert into chat_reads (thread_id, profile_id, last_read_at) values (th, r, t_runner)      -- ③
      on conflict (thread_id, profile_id) do update set last_read_at = excluded.last_read_at;
    if t_runner = t_owner then v_bad := v_bad || ' 두 위치가 같아서 아래 두 팔이 구별되지 않는다'; end if;
    v  := t_crd_receipt(o, th);
    v2 := t_crd_receipt(r, th);
    if (v->>'at')::timestamptz is distinct from t_runner
    then v_bad := v_bad || ' 보호자가 러너의 시각을 못 본다'; end if;
    if (v2->>'at')::timestamptz is distinct from t_owner
    then v_bad := v_bad || ' 러너가 보호자의 시각을 못 본다 (둘 다 저장된 뒤)'; end if;

    -- a booking with no runner yet has no counterpart — one row of NULL, never an invented reader.
    select w.bk, w.th into bk_match, th_match from t_crd_thread(o, null, d, rt, 'matching') w;
    insert into chat_reads (thread_id, profile_id, last_read_at) values (th_match, o, t0)      -- ③
      on conflict (thread_id, profile_id) do update set last_read_at = excluded.last_read_at;
    v := t_crd_receipt(o, th_match);
    if (v->>'rows')::int is distinct from 1 then v_bad := v_bad || ' 매칭 중 예약의 영수증이 정확히 1행이 아니다'; end if;
    if v->>'at' is not null
    then v_bad := v_bad || ' 러너가 없는데 읽은 사람이 있다고 말한다 (자기 행을 상대 것으로 돌려줬다)'; end if;

    if v_bad = '' then call _pass('crd','0212-R1 영수증은 **상대의** 시각이고 상대의 것뿐이다 — 아무도 안 읽었으면 두 당사자 모두 1행 NULL; 보호자가 읽으면 러너는 그 시각을 보고 **보호자는 여전히 NULL을 본다**(한 스레드에서 두 답이 갈리는 것이 「상대의 것」의 뜻이다); 둘 다 서로 다른 값으로 저장되면 각자 **상대의** 값을 읽는다(어느 답도 호출자 자신의 행으로는 만들어지지 않는다); 러너가 아직 없는 예약은 1행 NULL — 없는 독자를 지어내지 않는다');
    else v_msg := v_bad; call _fail('crd','0212-R1 the receipt is the counterpart''s', v_msg); end if;
  exception when others then call _fail('crd','0212-R1 the receipt is the counterpart''s', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0212-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';

    -- the table
    if to_regclass('public.chat_reads') is null then v_bad := v_bad || ' chat_reads가 없다';
    else
      if (select relrowsecurity from pg_class where oid = 'public.chat_reads'::regclass) is not true
      then v_bad := v_bad || ' RLS가 꺼져 있다'; end if;
      select count(*)::int into v_n from pg_policies
       where schemaname = 'public' and tablename = 'chat_reads' and cmd <> 'SELECT';
      if v_n is distinct from 0 then v_bad := v_bad || ' 쓰기 정책이 생겼다 (' || v_n || ')'; end if;
      select count(*)::int into v_n from pg_policies
       where schemaname = 'public' and tablename = 'chat_reads' and cmd = 'SELECT';
      if v_n is distinct from 1 then v_bad := v_bad || ' SELECT 정책 수가 1이 아니다 (' || v_n || ')'; end if;
      -- grants BOTH ways: the negative alone is satisfied by a table nobody can touch at all.
      if has_table_privilege('authenticated', 'public.chat_reads', 'select') is not true
      then v_bad := v_bad || ' authenticated가 자기 행도 못 읽는다'; end if;
      if (has_table_privilege('authenticated', 'public.chat_reads', 'insert')
       or has_table_privilege('authenticated', 'public.chat_reads', 'update')
       or has_table_privilege('authenticated', 'public.chat_reads', 'delete'))
      then v_bad := v_bad || ' 클라이언트가 직접 쓸 수 있다'; end if;
      if has_table_privilege('anon', 'public.chat_reads', 'select')
      then v_bad := v_bad || ' anon이 읽을 수 있다'; end if;
      if (select count(*) from information_schema.columns
           where table_schema = 'public' and table_name = 'chat_reads') is distinct from 3
      then v_bad := v_bad || ' 칸 수가 3이 아니다'; end if;
      -- the primary key IS the uniqueness this table's whole meaning rests on
      if (select array_agg(a.attname::text order by a.attname)
            from pg_constraint c join lateral unnest(c.conkey) k(att) on true
            join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.att
           where c.conrelid = 'public.chat_reads'::regclass and c.contype = 'p')
         is distinct from array['profile_id','thread_id']
      then v_bad := v_bad || ' 기본키가 (thread_id, profile_id)가 아니다'; end if;
    end if;

    -- the three definers
    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname in ('chat_mark_read', 'my_chat_unread', 'chat_thread_read_state')
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig))
       is distinct from 3
    then v_bad := v_bad || ' definer 셋의 prosecdef/본문 search_path 형상이 깨졌다'; end if;

    if exists (select 1 from pg_proc p
                where p.pronamespace = 'public'::regnamespace
                  and p.proname in ('chat_mark_read', 'my_chat_unread', 'chat_thread_read_state')
                  and (has_function_privilege('public', p.oid, 'execute')
                    or has_function_privilege('anon',   p.oid, 'execute')))
    then v_bad := v_bad || ' PUBLIC/anon이 실행할 수 있다'; end if;
    if has_function_privilege('authenticated', 'chat_mark_read(uuid)',          'execute') is not true
     or has_function_privilege('authenticated', 'my_chat_unread()',             'execute') is not true
     or has_function_privilege('authenticated', 'chat_thread_read_state(uuid)', 'execute') is not true
    then v_bad := v_bad || ' authenticated가 셋 중 하나를 못 부른다'; end if;

    -- 🔴 the gate on the unread read is an ABSENCE, not a clause.
    if (select pronargs from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'my_chat_unread') is distinct from 0
    then v_bad := v_bad || ' my_chat_unread가 인자를 가졌다 — 게이트가 부재에서 조항으로 바뀌었다'; end if;

    -- the bodies, COMMENTS STRIPPED
    select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
      into v_raw, v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_mark_read)';
    else
      -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `NULL-collapse` appears ONLY in this body's
      --    prose. If it survives stripping, the arms below are matching documentation.
      if (position('NULL-collapse' in v_raw) > 0) is not true
      then v_bad := v_bad || ' 주석 대조 문자열이 원본에 없다 — 스트리퍼 대조가 공허해졌다'; end if;
      if (position('NULL-collapse' in v_src) > 0) is not false
      then v_bad := v_bad || ' 주석이 벗겨지지 않았다 — 아래 팔들은 구현이 아니라 산문을 재고 있다'; end if;
      if (position('is_booking_party(' in v_src) > 0
          and position('is_booking_party(' in v_src) < position('insert into chat_reads' in v_src))
         is not true
      then v_bad := v_bad || ' mark_read의 당사자 게이트가 사라졌거나 쓰기 뒤로 갔다'; end if;
      if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
      then v_bad := v_bad || ' 단조 증가 보장(greatest)이 사라졌다'; end if;
    end if;

    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'my_chat_unread';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_chat_unread)';
    else
      if (position('is_booking_party_active(' in v_src) > 0) is not true
      then v_bad := v_bad || ' 목록이 답할 수 있는 방의 술어를 더 이상 쓰지 않는다'; end if;
      if (v_src ~ 'sender_id\s+is\s+distinct\s+from') is not true
      then v_bad := v_bad || ' 내 메시지 제외가 사라졌다'; end if;
    end if;

    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_thread_read_state';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_thread_read_state)';
    else
      if (position('is_booking_party(' in v_src) > 0
          and position('is_booking_party(' in v_src) < position('from chat_reads' in v_src))
         is not true
      then v_bad := v_bad || ' 영수증의 당사자 게이트가 사라졌거나 읽기 뒤로 갔다'; end if;
      if (position('profile_id = v_other' in v_src) > 0) is not true
      then v_bad := v_bad || ' 영수증이 상대의 행을 읽지 않는다'; end if;
    end if;

    if v_bad = '' then call _pass('crd','0212-S1 배포 형상 — chat_reads는 RLS on·SELECT 정책 **1개**·쓰기 정책 **0개**이고 authenticated는 읽기만(쓰기 3종 없음), anon은 아무것도 없으며 칸 3·기본키 (thread_id, profile_id); definer 셋은 prosecdef + 본문 search_path이고 PUBLIC/anon 실행 불가·authenticated 실행 가능(양방향); **my_chat_unread의 입력 인자는 0개**(게이트가 조항이 아니라 부재라서, 여기가 아니면 p_profile이 생겨도 아무 행동 팔도 안 빨개진다); 세 본문은 주석을 벗긴 뒤 매칭하고 각자 NO-SOURCE 팔을 갖는다 + 스트리퍼가 실제로 돌았다는 **양방향** 대조');
    else v_msg := v_bad; call _fail('crd','0212-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('crd','0212-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
