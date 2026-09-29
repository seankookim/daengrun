-- ═══ 266 — 0235: 0228's covering test agrees with 0223's clamp, and its thread scope is pinned
-- ═══        0235-F1 · F2 · C1 · C2 · T1 · T2 · S1, tag `ccc`
--
-- Source: R1 executing review of d0b6b6c..0ee30fa (docs/reviews/2026-09-26-r1-claude-executing-
-- review.md on cloud/doc-truth), server findings s1 (medium) and s2 (low). F1 and F2 were written
-- BEFORE 0235 and measured RED on trunk 0ee30fa's bodies (0228 §A/§B); T1 and S1's thread arm pin
-- a property trunk already has but nothing asserted on purpose. C1, C2 and T2 were added by the
-- fixer round after the R2 executing review of 0235 itself (finding 1): 0235's first draft
-- (`and now() > v_at` alone) released the nudge over a counterpart message that COMMITTED DURING
-- the read — measured with two real sessions (0235 §0d ②). C1/C2 were written in the same edit as
-- the `or m.created_at <= clock_timestamp()` arm, and measured RED on the first draft's bodies by
-- planting them back in a lab copy (the clock arm removed from §A → C1 red; from §B → C2 red).
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation:
--
--   · F1 **A READ THAT ACKNOWLEDGES A FORWARD-DATED COUNTERPART MESSAGE COVERS IT.** A runner
--        message dated 30 days ahead (a row a pre-0225 client could write; 0225 §0e leaves such
--        rows in place) sits in the thread. Acknowledging it with `chat_mark_read_to` stores now()
--        (0223 §0d ③, observed) AND releases the owner's 「새 메시지」 nudge; the next runner
--        message then writes a second nudge row. 🔴 The clamp is not a blanket release: an
--        acknowledgement of an OLDER message while the forward-dated one exists keeps the nudge
--        (the forward-dated message has not been drawn). Attribution: a twin thread with the same
--        older message and NO forward-dated one releases on the same older acknowledgement — so
--        the hold is caused by the forward-dated row.
--   · F2 **0212's LEGACY WRITER IS NOT BLOCKED BY A FORWARD-DATED COUNTERPART MESSAGE.**
--        `chat_mark_read(p_thread)` reads 「up to now」; with a 30-days-ahead runner message in the
--        thread it releases the nudge and the next message writes a second row.
--   · C1 **§A: A COUNTERPART MESSAGE THAT COMMITTED WHILE THE READ RAN STILL HOLDS THE NUDGE, EVEN
--        WHEN THE READ ACKNOWLEDGES A FORWARD-DATED ROW.** F1's fixture plus one runner message
--        dated clock_timestamp() inside the pin's transaction — i.e. after the reading
--        transaction's start (t0 = now()) and before the reading statement — which is exactly the
--        state two real sessions produce when a message commits during the read (0235 §0d ②).
--        Acknowledging the forward-dated row stores t0 and leaves the nudge unread (F1 shows the
--        same acknowledgement releases without that message — the attribution).
--   · C2 **§B: THE SAME, THROUGH THE LEGACY WRITER.** F2's fixture plus one clock_timestamp()-dated
--        runner message: chat_mark_read stores t0 and the nudge stays unread (F2 is the twin
--        without it, which releases).
--   · T1 **A NEWER COUNTERPART MESSAGE IN THE READER'S OTHER BOOKING'S THREAD DOES NOT HOLD THIS
--        BOOKING'S NUDGE.** Same owner and runner, two bookings; booking B's runner message is
--        NEWER than the booking-A message the owner acknowledges. The A-nudge is released; the
--        B-nudge (present and unread before the read) stays unread.
--   · T2 **§B, THE SAME THREAD SCOPE.** Booking B's thread holds a clock_timestamp()-dated runner
--        message (one that WOULD hold under C2's rule); the legacy read of booking A's thread
--        releases the A-nudge and leaves the B-nudge unread.
--   · S1 **DEPLOYED SHAPE.** Both writers: prosecdef, in-body search_path, argument lists, ACL both
--        ways. In the COMMENT-STRIPPED body, the COVERING SUBQUERY alone (the text inside the
--        parentheses after `not exists` in the release statement, matched by depth) carries the
--        thread scope `m.thread_id = p_thread`, the sender exclusion, `m.created_at > v_at` AND
--        the clamp group `(now() > v_at or m.created_at <= clock_timestamp())`, and the release
--        sits below the party gate. Scoped to the subquery because §A's acknowledged-message
--        lookup also says `m.thread_id = p_thread` (the reason 0228 VERIFY ④ could not see s2), and
--        because a clamp conjunct moved OUTSIDE the subquery inverts the fix while a statement-wide
--        match still finds it (R2 finding 4, mutation outerclampA). NO-SOURCE arm per function and
--        a two-sided stripper control.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — named gaps, not pins) ───
--   · (Retired gap.) The first draft of this file named §B's thread scope 「not behaviourally
--     observable」, because `now() > v_at` alone was false for every §B row. The clock arm made §B's
--     covering subquery non-empty again for rows in (v_at, clock_timestamp()], so T2 now observes it.
--   · §B's `now() > v_at` DISJUNCT HAS NO BEHAVIOURAL DOOR. In §B v_at = greatest(stored, now()) ≥
--     now(), so that disjunct is false for every row and the group reduces to its clock arm there.
--     Measured: dropping it from §B alone (VERIFY demoted) reddens S1 ONLY. Not a blind pin — the
--     product cannot produce a §B state where it matters; it is kept so both bodies read alike.
--   · The two-session race itself (0235 §0d ②): one session cannot interleave two commits. C1/C2
--     pin the STATE that race produces (a counterpart row dated after the read's transaction start
--     and before its statement); the two-session measurement lives in 0235 §0d ② and the REGISTRY
--     row, not here. The commit-order race 0228 §0d ① is unchanged and likewise prose.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper and cleared again at the end.
--  ② Messages are inserted as `postgres` with EXPLICIT `created_at` values (0225's stamp leaves a
--     non-RLS writer's value alone — the only way to reproduce a pre-0225 client's forward date).
--     The DO block is one transaction, so now() = t0 throughout. Nudge rows are written by the
--     REAL `chat_messages_notify` trigger; no pin inserts a `새 메시지` row by hand.
--  ③ C1/C2/T2's 「committed during the read」 row is dated `clock_timestamp()` at its insert, which
--     each pin asserts is strictly after t0 (else the fixture would sit in the zone where the old
--     and new rules AGREE, and the pin could not see the difference).
set client_min_messages = warning;

create or replace function t_ccc_thread(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                        out bk uuid, out th uuid)
language plpgsql as $$
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bk;
  insert into chat_threads (booking_id) values (bk) returning id into th;
end $$;

create or replace function t_ccc_msg(p_thread uuid, p_sender uuid, p_body text, p_at timestamptz)
returns bigint language sql as $$
  insert into chat_messages (thread_id, sender_id, body, created_at)
  values (p_thread, p_sender, p_body, p_at)
  returning id
$$;

create or replace function t_ccc_mark_to(p_uid uuid, p_thread uuid, p_msg bigint) returns jsonb
language plpgsql as $$
declare v timestamptz;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select m.last_read_at into v from chat_mark_read_to(p_thread, p_msg) m;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_ccc_mark_legacy(p_uid uuid, p_thread uuid) returns jsonb
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

-- 「새 메시지」 rows addressed to p_uid for booking p_bk — all of them, or only the unread ones.
create or replace function t_ccc_nudges(p_uid uuid, p_bk uuid, p_unread_only boolean) returns int
language sql as $$
  select count(*)::int from notifications n
   where n.profile_id = p_uid and n.ref_id = p_bk and n.title = '새 메시지'
     and (not p_unread_only or n.read_at is null)
$$;

create or replace function t_ccc_stored(p_thread uuid, p_uid uuid) returns timestamptz
language sql as $$
  select c.last_read_at from chat_reads c where c.thread_id = p_thread and c.profile_id = p_uid
$$;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid;
  bk uuid; th uuid; bk2 uuid; th2 uuid;
  m1 bigint; m_fut bigint; m_tw bigint; m_cc bigint; v_m text; v_open int; v_i int; v_depth int; v_ch text; v_sub text;
  v jsonb; v_bad text; v_msg text;
  v_src text; v_raw text; v_rel text; v_fn text;
  t0 timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
  t0 := now();

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-F1] chat_mark_read_to: acknowledging a forward-dated counterpart message covers it
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_f1_o', 'owner');
    r  := t_user('ccc_f1_r', 'runner');
    d  := t_dog(o, 'ccc-f1');
    rt := t_route('ccc route f1');
    select w.bk, w.th into bk,  th  from t_ccc_thread(o, r, d, rt) w;
    select w.bk, w.th into bk2, th2 from t_ccc_thread(o, r, d, rt) w;                       -- the twin

    m1    := t_ccc_msg(th, r, 'r-1',          t0 - interval '300 seconds');
    m_fut := t_ccc_msg(th, r, 'from-a-month', t0 + interval '30 days');        -- ② a pre-0225 row
    if t_ccc_nudges(o, bk, false) is distinct from 1 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: the two runner messages did not leave exactly one unread nudge (the trigger or 0090''s dedupe is not in force)'; end if;
    if (select m.created_at from chat_messages m where m.id = m_fut) is distinct from t0 + interval '30 days'
    then v_bad := v_bad || ' fixture: the forward-dated row did not keep its date (nothing below would be measured)'; end if;

    -- 🔴 the clamp is not a blanket release: an OLDER acknowledgement keeps the nudge …
    v := t_ccc_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' the older acknowledgement was refused: ' || (v->>'raised'); end if;
    if t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 acknowledging r-1 released the nudge while the forward-dated message (undrawn) exists — the clamp became a blanket release'; end if;
    -- … and the twin without the forward-dated row releases on the same acknowledgement (attribution).
    m_tw := t_ccc_msg(th2, r, 'r-1', t0 - interval '300 seconds');
    if t_ccc_nudges(o, bk2, true) is distinct from 1
    then v_bad := v_bad || ' twin fixture: no unread nudge'; end if;
    v := t_ccc_mark_to(o, th2, m_tw);
    if v ? 'raised' then v_bad := v_bad || ' twin: the acknowledgement was refused: ' || (v->>'raised'); end if;
    if t_ccc_nudges(o, bk2, true) is distinct from 0
    then v_bad := v_bad || ' twin: without the forward-dated row the same acknowledgement did not release — the hold above is not attributable to that row'; end if;

    -- 🔴 the property: acknowledging the forward-dated message covers it.
    v := t_ccc_mark_to(o, th, m_fut);
    if v ? 'raised' then v_bad := v_bad || ' acknowledging the forward-dated message was refused: ' || (v->>'raised'); end if;
    if t_ccc_stored(th, o) is distinct from t0
    then v_bad := v_bad || ' the stored position is not now() (0223''s clamp changed: stored=' || coalesce(t_ccc_stored(th, o)::text,'∅') || ')'; end if;
    if t_ccc_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 acknowledging the forward-dated message left the nudge unread (unread=' || coalesce(t_ccc_nudges(o, bk, true)::text,'∅') || ', must be 0) — the covering test disagrees with 0223''s clamp'; end if;
    -- … and the next message pushes again.
    perform t_ccc_msg(th, r, 'r-2', t0);
    if t_ccc_nudges(o, bk, false) is distinct from 2 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the message after the read wrote no new nudge (rows=' || coalesce(t_ccc_nudges(o, bk, false)::text,'∅') || ', must be 2 with 1 unread)'; end if;

    if v_bad = '' then call _pass('ccc','0235-F1 chat_mark_read_to: acknowledging a forward-dated counterpart message (30 days ahead, a pre-0225 row) stores now() and releases the nudge (unread 1→0), and the next runner message writes a second row (1→2). 🔴 Acknowledging an OLDER message while it exists keeps the nudge (the clamp is not a blanket release), and a twin with the same older message and no forward-dated row releases on the same acknowledgement — the hold is attributable to that row');
    else v_msg := v_bad; call _fail('ccc','0235-F1 forward-dated counterpart message is covered by its acknowledgement', v_msg); end if;
  exception when others then call _fail('ccc','0235-F1 forward-dated counterpart message is covered by its acknowledgement', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-F2] chat_mark_read (0212, legacy): a forward-dated counterpart message does not block it
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_f2_o', 'owner');
    r  := t_user('ccc_f2_r', 'runner');
    d  := t_dog(o, 'ccc-f2');
    rt := t_route('ccc route f2');
    select w.bk, w.th into bk, th from t_ccc_thread(o, r, d, rt) w;
    perform t_ccc_msg(th, r, 'r-1',          t0 - interval '300 seconds');
    perform t_ccc_msg(th, r, 'from-a-month', t0 + interval '30 days');
    if t_ccc_nudges(o, bk, false) is distinct from 1 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: not exactly one unread nudge before the read'; end if;

    v := t_ccc_mark_legacy(o, th);
    if v ? 'raised' then v_bad := v_bad || ' the legacy read was refused: ' || (v->>'raised'); end if;
    if t_ccc_stored(th, o) is distinct from t0
    then v_bad := v_bad || ' the legacy position is not now() (0212''s semantics changed)'; end if;
    if t_ccc_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 0212''s chat_mark_read left the nudge unread with a forward-dated counterpart message in the thread'; end if;
    perform t_ccc_msg(th, r, 'r-2', t0);
    if t_ccc_nudges(o, bk, false) is distinct from 2 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the message after the legacy read wrote no new nudge'; end if;

    if v_bad = '' then call _pass('ccc','0235-F2 0212''s legacy chat_mark_read is not blocked by a forward-dated counterpart message — with a runner message dated 30 days ahead it stores now(), releases the nudge (1→0) and the next runner message writes a second row (1→2)');
    else v_msg := v_bad; call _fail('ccc','0235-F2 legacy writer with a forward-dated message', v_msg); end if;
  exception when others then call _fail('ccc','0235-F2 legacy writer with a forward-dated message', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-C1] §A: a message that committed during the read still holds, beside a forward-dated row
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_c1_o', 'owner');
    r  := t_user('ccc_c1_r', 'runner');
    d  := t_dog(o, 'ccc-c1');
    rt := t_route('ccc route c1');
    select w.bk, w.th into bk, th from t_ccc_thread(o, r, d, rt) w;
    perform t_ccc_msg(th, r, 'r-1', t0 - interval '300 seconds');
    m_fut := t_ccc_msg(th, r, 'from-a-month', t0 + interval '30 days');
    m_cc  := t_ccc_msg(th, r, 'during-the-read', clock_timestamp());                           -- ③
    if (select m.created_at > t0 and m.created_at < t0 + interval '1 hour' from chat_messages m where m.id = m_cc) is not true
    then v_bad := v_bad || ' fixture: the during-the-read row is not dated strictly after t0 (the pin would sit where the old and new rules agree)'; end if;
    if t_ccc_nudges(o, bk, false) is distinct from 1 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: not exactly one unread nudge before the read (the during-the-read message must be deduped, as in the race)'; end if;

    v := t_ccc_mark_to(o, th, m_fut);
    if v ? 'raised' then v_bad := v_bad || ' acknowledging the forward-dated message was refused: ' || (v->>'raised'); end if;
    if t_ccc_stored(th, o) is distinct from t0
    then v_bad := v_bad || ' the stored position is not t0 (stored=' || coalesce(t_ccc_stored(th, o)::text,'∅') || ')'; end if;
    if t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the read released the nudge over a counterpart message dated after the read began (unread=' || coalesce(t_ccc_nudges(o, bk, true)::text,'∅') || ', must be 1) — that message would be left unread with no push'; end if;

    if v_bad = '' then call _pass('ccc','0235-C1 chat_mark_read_to: beside F1''s forward-dated row, a runner message dated after the reading transaction began (clock_timestamp(), > t0 asserted — the state a message committing during the read produces) keeps the nudge unread (1) when the read acknowledges the forward-dated row and stores t0; F1 is the twin without it, which releases');
    else v_msg := v_bad; call _fail('ccc','0235-C1 message committed during the read holds (§A)', v_msg); end if;
  exception when others then call _fail('ccc','0235-C1 message committed during the read holds (§A)', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-C2] §B: the same through 0212's legacy writer
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_c2_o', 'owner');
    r  := t_user('ccc_c2_r', 'runner');
    d  := t_dog(o, 'ccc-c2');
    rt := t_route('ccc route c2');
    select w.bk, w.th into bk, th from t_ccc_thread(o, r, d, rt) w;
    perform t_ccc_msg(th, r, 'r-1', t0 - interval '300 seconds');
    perform t_ccc_msg(th, r, 'from-a-month', t0 + interval '30 days');
    m_cc := t_ccc_msg(th, r, 'during-the-read', clock_timestamp());                            -- ③
    if (select m.created_at > t0 and m.created_at < t0 + interval '1 hour' from chat_messages m where m.id = m_cc) is not true
    then v_bad := v_bad || ' fixture: the during-the-read row is not dated strictly after t0'; end if;
    if t_ccc_nudges(o, bk, false) is distinct from 1 or t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: not exactly one unread nudge before the read'; end if;

    v := t_ccc_mark_legacy(o, th);
    if v ? 'raised' then v_bad := v_bad || ' the legacy read was refused: ' || (v->>'raised'); end if;
    if t_ccc_stored(th, o) is distinct from t0
    then v_bad := v_bad || ' the legacy position is not t0'; end if;
    if t_ccc_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 0212''s chat_mark_read released the nudge over a counterpart message dated after the read began (unread=' || coalesce(t_ccc_nudges(o, bk, true)::text,'∅') || ', must be 1)'; end if;

    if v_bad = '' then call _pass('ccc','0235-C2 0212''s legacy chat_mark_read: beside F2''s forward-dated row, a runner message dated after the reading transaction began (clock_timestamp(), > t0 asserted) keeps the nudge unread (1) while the read stores t0; F2 is the twin without it, which releases');
    else v_msg := v_bad; call _fail('ccc','0235-C2 message committed during the read holds (§B)', v_msg); end if;
  exception when others then call _fail('ccc','0235-C2 message committed during the read holds (§B)', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-T1] a newer counterpart message in the reader's OTHER booking's thread does not hold
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_t1_o', 'owner');
    r  := t_user('ccc_t1_r', 'runner');
    d  := t_dog(o, 'ccc-t1');
    rt := t_route('ccc route t1');
    select w.bk, w.th into bk,  th  from t_ccc_thread(o, r, d, rt) w;                       -- booking A
    select w.bk, w.th into bk2, th2 from t_ccc_thread(o, r, d, rt) w;                       -- booking B
    m1 := t_ccc_msg(th,  r, 'a-1', t0 - interval '300 seconds');
    perform t_ccc_msg(th2, r, 'b-1', t0 - interval '100 seconds');      -- NEWER, same runner, thread B
    if t_ccc_nudges(o, bk, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner A-nudge'; end if;
    if t_ccc_nudges(o, bk2, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner B-nudge'; end if;

    v := t_ccc_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' the read was refused: ' || (v->>'raised'); end if;
    if t_ccc_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 a newer counterpart message in the owner''s OTHER booking''s thread held this booking''s nudge'; end if;
    if t_ccc_nudges(o, bk2, true) is distinct from 1
    then v_bad := v_bad || ' the other booking''s nudge was released by this booking''s read'; end if;

    if v_bad = '' then call _pass('ccc','0235-T1 the covering test is scoped to THIS thread — the owner''s booking-B thread holds a runner message NEWER than the booking-A message they acknowledge; the A-nudge is released (1→0) and the B-nudge stays unread (1), both observed present before the read');
    else v_msg := v_bad; call _fail('ccc','0235-T1 other thread does not hold the nudge', v_msg); end if;
  exception when others then call _fail('ccc','0235-T1 other thread does not hold the nudge', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-T2] §B: a during-the-read message in the reader's OTHER booking's thread does not hold
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('ccc_t2_o', 'owner');
    r  := t_user('ccc_t2_r', 'runner');
    d  := t_dog(o, 'ccc-t2');
    rt := t_route('ccc route t2');
    select w.bk, w.th into bk,  th  from t_ccc_thread(o, r, d, rt) w;                       -- booking A
    select w.bk, w.th into bk2, th2 from t_ccc_thread(o, r, d, rt) w;                       -- booking B
    perform t_ccc_msg(th, r, 'a-1', t0 - interval '300 seconds');
    m_cc := t_ccc_msg(th2, r, 'b-during-the-read', clock_timestamp());                       -- ③
    if (select m.created_at > t0 and m.created_at < t0 + interval '1 hour' from chat_messages m where m.id = m_cc) is not true
    then v_bad := v_bad || ' fixture: the booking-B row is not dated strictly after t0 (it would hold nothing even unscoped)'; end if;
    if t_ccc_nudges(o, bk, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner A-nudge'; end if;
    if t_ccc_nudges(o, bk2, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner B-nudge'; end if;

    v := t_ccc_mark_legacy(o, th);
    if v ? 'raised' then v_bad := v_bad || ' the legacy read was refused: ' || (v->>'raised'); end if;
    if t_ccc_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 a during-the-read counterpart message in the owner''s OTHER booking''s thread held this booking''s nudge through the legacy writer'; end if;
    if t_ccc_nudges(o, bk2, true) is distinct from 1
    then v_bad := v_bad || ' the other booking''s nudge was released by this booking''s read'; end if;

    if v_bad = '' then call _pass('ccc','0235-T2 chat_mark_read''s covering test is scoped to THIS thread — the owner''s booking-B thread holds a runner message dated after the read began (the kind C2 shows DOES hold in its own thread); the legacy read of booking A releases the A-nudge (1→0) and leaves the B-nudge unread (1)');
    else v_msg := v_bad; call _fail('ccc','0235-T2 other thread does not hold the nudge (§B)', v_msg); end if;
  exception when others then call _fail('ccc','0235-T2 other thread does not hold the nudge (§B)', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0235-S1] deployed shape, both writers, release statement scoped
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname in ('chat_mark_read_to', 'chat_mark_read')
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 2
    then v_bad := v_bad || ' prosecdef / in-body search_path shape broken (or a function is absent)'; end if;
    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
       is distinct from 'p_thread uuid, p_up_to_message_id bigint'
    then v_bad := v_bad || ' chat_mark_read_to arguments changed'; end if;
    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read')
       is distinct from 'p_thread uuid'
    then v_bad := v_bad || ' chat_mark_read arguments changed'; end if;
    if (has_function_privilege('public', 'chat_mark_read_to(uuid,bigint)', 'execute')
     or has_function_privilege('anon',   'chat_mark_read_to(uuid,bigint)', 'execute')
     or has_function_privilege('public', 'chat_mark_read(uuid)', 'execute')
     or has_function_privilege('anon',   'chat_mark_read(uuid)', 'execute')) is not false
    then v_bad := v_bad || ' PUBLIC/anon can execute a writer'; end if;
    if (has_function_privilege('authenticated', 'chat_mark_read_to(uuid,bigint)', 'execute')
        and has_function_privilege('authenticated', 'chat_mark_read(uuid)', 'execute')) is not true
    then v_bad := v_bad || ' authenticated cannot call a writer'; end if;

    foreach v_fn in array array['chat_mark_read_to', 'chat_mark_read'] loop
      select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
        into v_raw, v_src
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_fn;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || v_fn || ')'; continue; end if;
      -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `CLAMP-CONSISTENT COVER` appears ONLY in the
      --    0235 comment inside each body; if it survives stripping, the arms below read prose.
      if (position('CLAMP-CONSISTENT COVER' in v_raw) > 0) is not true
      then v_bad := v_bad || ' ' || v_fn || ': the comment-control string is absent from the raw body (0235''s body is not deployed, or the control is vacuous)'; end if;
      if (position('CLAMP-CONSISTENT COVER' in v_src) > 0) is not false
      then v_bad := v_bad || ' ' || v_fn || ': comments were not stripped'; end if;
      if (position('is_booking_party(' in v_src) > 0
          and position('update notifications' in v_src) > position('is_booking_party(' in v_src))
         is not true
      then v_bad := v_bad || ' ' || v_fn || ': the release is gone or sits above the party gate'; end if;
      -- The RELEASE STATEMENT, then the COVERING SUBQUERY inside it (the `(` after `not exists` to
      -- its matching `)`, by depth). §A's acknowledged-message lookup also scopes by thread, so a
      -- whole-body match would be satisfied by that lookup (the reason s2 was invisible); a clamp
      -- conjunct outside the subquery inverts the fix and a statement-wide match still finds it.
      v_rel := split_part(substr(v_src, position('update notifications' in v_src)), 'return query', 1);
      if (position('update notifications' in v_src) > 0) is not true
      then v_bad := v_bad || ' ' || v_fn || ': no release statement'; v_rel := ''; end if;
      v_sub := '';
      v_m := substring(v_rel from 'not\s+exists\s*\(');
      if v_m is not null then
        v_open := position(v_m in v_rel) + length(v_m) - 1;
        v_depth := 0;
        for v_i in v_open .. length(v_rel) loop
          v_ch := substr(v_rel, v_i, 1);
          if v_ch = '(' then v_depth := v_depth + 1;
          elsif v_ch = ')' then
            v_depth := v_depth - 1;
            if v_depth = 0 then v_sub := substr(v_rel, v_open + 1, v_i - v_open - 1); exit; end if;
          end if;
        end loop;
      end if;
      if (v_sub ~ '^\s*select\s+1\s+from\s+chat_messages\s+m\s') is not true
      then v_bad := v_bad || ' ' || v_fn || ': the covering subquery is gone (or its parentheses do not balance)'; end if;
      if (v_sub ~ 'm\.thread_id\s*=\s*p_thread') is not true
      then v_bad := v_bad || ' ' || v_fn || ': 🔴 the covering subquery is not scoped to this thread'; end if;
      if (v_sub ~ 'm\.sender_id\s+is\s+distinct\s+from\s+v_uid') is not true
      then v_bad := v_bad || ' ' || v_fn || ': the covering subquery lost the sender exclusion'; end if;
      if (v_sub ~ 'm\.created_at\s*>\s*v_at') is not true
      then v_bad := v_bad || ' ' || v_fn || ': the covering subquery lost m.created_at > v_at'; end if;
      if (v_sub ~ '\(\s*now\(\)\s*>\s*v_at\s+or\s+m\.created_at\s*<=\s*clock_timestamp\(\)\s*\)') is not true
      then v_bad := v_bad || ' ' || v_fn || ': 🔴 the covering subquery lost the clamp group (now() > v_at or m.created_at <= clock_timestamp())'; end if;
    end loop;

    if v_bad = '' then call _pass('ccc','0235-S1 deployed shape — chat_mark_read_to and chat_mark_read are prosecdef + in-body search_path with the clients'' argument lists; PUBLIC/anon cannot execute either, authenticated can; in each COMMENT-STRIPPED body the release statement sits below the party gate and its covering subquery — read INSIDE its own parentheses, matched by depth — carries m.thread_id = p_thread, the sender exclusion, m.created_at > v_at and the clamp group (now() > v_at or m.created_at <= clock_timestamp()). NO-SOURCE arm per function + a two-sided stripper control');
    else v_msg := v_bad; call _fail('ccc','0235-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('ccc','0235-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
end $$;
