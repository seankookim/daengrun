-- ═══ 218 — 0187: per-category push preferences — 0187-N1…N6 · S1, tag `npf` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   · N1 a person who has never saved gets the DEFAULTS (all four true) and no row is created by
--     reading — the getter's absent-row arm, and the count that proves the row really is absent.
--   · N2 own row only: a second profile's row is invisible to a SELECT, unwritable by UPDATE and
--     un-INSERT-able, executed AS `authenticated` at the RLS boundary; and `get_notification_prefs`
--     answers the CALLER, never the other person, under the same JWT claim.
--   · N3 the upsert: it creates, it is idempotent in VALUE (only `updated_at` moves), a NULL
--     argument leaves that category alone so one switch can be saved on its own, and the returned
--     row IS the stored row.
--   · N4 a NULL uid refuses BY NAME (`not_signed_in`) on both RPCs, and writes nothing.
--   · N5 THE SEND PATH — the whole point of the slice. With a live Expo token, a `notifications`
--     INSERT either becomes a push or it does not, and the preference decides:
--       ‣ CONTROL: no prefs row ⇒ every category pushes (this is what proves the machinery runs —
--         a `notify_push` that threw would give 0 everywhere and read as 「suppressed」).
--       ‣ each of booking · chat · community · reward is silenced by ITS OWN column and by no
--         other column (the cross arms are what stop a one-flag implementation passing).
--       ‣ safety and system push with ALL FOUR columns false — not disableable.
--       ‣ `shop`, the enum value nothing writes, also pushes with all four false: an uncategorised
--         kind is never silently muted.
--       ‣ and in EVERY arm the `notifications` row is written — preferences gate the PUSH, never
--         the record, so the inbox is unchanged.
--   · N6 the chat discriminator is the SHIPPED one, measured through 0090's real trigger: a
--     `chat_messages` INSERT produces a row that maps to 'chat', it is silenced by `chat` while
--     `booking` is ON, and it is SENT by `chat` while `booking` is OFF. Behavioural on both sides,
--     so a title change in 0090 OR in 0187 reddens it — a source pin matching the literal could
--     not tell a changed title from a changed comment.
--   · S1 deployed shape: prosecdef · in-body search_path · ACL by value on all four functions ·
--     RLS on with exactly one self-scoped policy · and, in `notify_push`'s source WITH COMMENTS
--     STRIPPED, the category mapper called, the prefs table read, and the safety decision taken
--     BEFORE that read (a NO-SOURCE arm so an absent function fails loudly instead of silently —
--     `position(x in NULL)` is NULL and a bare IF on NULL does not fire).
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · The push itself. What is measured is 「the row was allowed to become a push」, never that
--     Expo delivered anything. A revoked OS permission, an expired token, a dead APNs cert are all
--     invisible here and always will be. ⚠ AMENDED 2026-09-22 (0204): this line used to say
--     「the row→HTTP step was taken」 and named `net._stub_calls`, which was true while
--     `notify_push` decided and posted in one statement. It no longer does — see the `[0204]` note
--     on `t_npf_probe` below. The step measured here is now row→outbox; outbox→HTTP is
--     `235_push_outbox_suite.sql`'s.
--   · That safety NEVER READS `notification_prefs`. The observable half (safety pushes with every
--     column false) is N5; 「does not touch the table at all」 is source-only and belongs to S1's
--     ordering arm. There is no way to observe a read that did not happen, so no pin claims it.
--   · The client's screen. `app/test/notification-prefs.test.cjs` pins the category→copy table;
--     no SQL pin can see a `.tsx` route module (the `check-device-clock` division).
--
-- ─── MUTATION MAP — measured 2026-09-21 in an md5-identical lab (`/tmp/dr-0187-lab`), every
--     plant assert-gated AND `&&`-chained to its run so an unlanded plant yields NO row at all,
--     the CONTROL observed first (1314 / 0). 「demoted」 = 0187's VERIFY raise turned into a notice
--     so the SUITE is what is measured; 「un-demoted」 = the shipped file, where VERIFY aborts the
--     apply before any suite runs. ───
--   (i)    the preference gate deleted from notify_push  → 1311/3: N5 (all four categories still
--          push) + N6 + S1; un-demoted ABORTS (NO-PREFS-READ · NO-SAFETY-CONJUNCT ·
--          SAFETY-NOT-BEFORE-THE-PREFS-READ).
--   (ii)   the prefs READ moved ahead of the safety decision, behaviour unchanged
--                                                        → 1313/1: S1 ALONE, by design: the ordering is a
--          belt that only text can see, and this is the row that proves it earns its place.
--   (iii)  the `v_cat <> 'safety'` conjunct deleted       → 1313/1: S1 alone (NO-SAFETY-CONJUNCT ·
--          SAFETY-NOT-BEFORE-THE-PREFS-READ); un-demoted ABORTS with both names. ⚠ N5 stays GREEN and that is
--          a fact about the code, not a blind pin: the `case` has no `'safety'` arm, so it answers
--          NULL and 「only an explicit false suppresses」 still SENDS. Defence in depth. (xii) is
--          the realistic two-layer version and it does redden N5.
--   (iv)   the chat arm removed from the mapper          → N5 (the cross arms: chat silenced by
--          the booking column and vice versa) + N6 (0090's own row maps to `booking`).
--   (v)    `is false` widened to `is not true`           → N5's CONTROL (an absent row now
--          silences everything) + N6's fixture + **`[ccf] P4` in suite 153** — a SHIPPED pin that
--          reads the Expo payload out of `net._stub_calls`. Worth recording: the fail-open rule is
--          load-bearing for somebody else's pin too, not only for this slice's.
--   (vi)   the uncategorised fallback muted (`else 'booking'`)
--                                                        → N5 (`shop` silenced with all four off).
--   (vii)  the RLS policy widened to `using (true)`      → 1312/2: N2 (the other profile's row
--          visible and writable) + S1; un-demoted ABORTS (POLICY-NOT-SELF).
--   (viii) `not_signed_in` deleted from the setter       → N4. ⚠ The refusal does not disappear —
--          the database's own NOT NULL on `profile_id` answers instead — so what the pin holds is
--          the NAME, which is the only thing the client can map to Korean.
--   (ix)   a NULL argument RESETS instead of leaving alone → N3 (the partial-save arm).
--   (x)    the getter granted to `anon`                  → 1311/3: **98 H9 + 99 S1** (the
--          schema-wide sweeps) + S1; un-demoted ABORTS (PUBLIC-OR-ANON-EXECUTE).
--   (xi)   the explicit `system` arm removed from the mapper
--                                                        → S1 alone. Behaviourally a NO-OP, because
--          the `else` already answers 'safety'; the arm is defence in depth against a later session
--          changing that fallback, and S1 is honestly its only possible witness.
--   (xii)  the guard deleted AND a `'safety'` arm added to the `case` — the shape a session adding
--          a safety column would actually produce
--                                                        → 1312/2: N5 (safety AND system silenced)
--          + S1; un-demoted ABORTS (NO-SAFETY-CONJUNCT).
--          ⚠ This one found a real weakness in S1 BEFORE the tightening: the ordering arm matched
--          the bare `'safety'` literal, which the new `case` arm satisfies, so S1 passed (1313/1,
--          N5 alone) on a function where safety had become disableable. S1 now also asserts the
--          CONJUNCT (`v_cat <> 'safety'`) — stated as a property, not as 「what (xii) broke」: the
--          send path must exclude the safety category from the preference lookup, and that
--          decision must precede the read. Re-measured after the repair, and (i)/(iii) re-measured
--          with it: the map above is the post-repair run, not the run that motivated it.
--   ⚠ THE FIRST TWO ATTEMPTS AT THIS BATTERY MEASURED NOTHING AND ARE RECORDED RATHER THAN
--     QUIETLY REPLACED. Run 1: the planter's `reset()` did `rmtree(tests)` + `copytree`, deleting
--     the live `.pgtest` PGDATA under a running postmaster — ten identical 「SHIM FAILED」 rows,
--     which is CLAUDE.md §「three ways a green means nothing」 ② exactly. Run 2: the lab sat under a
--     118-character path, so `harness.sh` fell back to a hashed `/tmp` socket dir that still held a
--     stale lock file from run 1 — the cluster restarted mid-suite and the CONTROL itself failed.
--     Both were caught by the standing rule 「a battery whose control fails measures nothing」; the
--     lab moved to a short, self-contained path and the control was re-observed clean first.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared explicitly in every arm. A leftover claim from an
--     earlier suite would make N4's 「no caller」 arm silently measure the wrong thing.
--  ② Every push measurement is a DELTA around one INSERT, never an absolute count: other suites in
--     this same database have already produced pushes for their own fixtures. [0204] The delta is
--     now taken over `push_outbox` — `t_npf_probe` scopes it to the notification's own id, the chat
--     probe to (recipient, title).
--  ③ The fixture profile holds a real `ExponentPushToken…` in `push_tokens`. Without it
--     `notify_push` returns before the enqueue for a reason that has nothing to do with
--     preferences, and every arm would read 0 — the fixture must contain the defect's precondition.
set client_min_messages = warning;

-- One INSERT, measured both ways: how many pushes it produced, and whether the row landed.
-- ⚠ [0204] `pushes` NOW COUNTS `push_outbox` ROWS, NOT `net._stub_calls`, AND NOT ONE PIN IN THIS
--   FILE CHANGES MEANING OR EXPECTED VALUE. `notify_push` used to decide AND post in one
--   statement; 0204 splits that into row → outbox (here, still inside `notify_push`, still under
--   every preference rule this file pins) and outbox → HTTP one tick later, because pg_net is
--   asynchronous and a deletion committing between the check and the send was never re-examined
--   (Codex B8). The preference decision — which is this file's entire subject — did not move;
--   only what happens after it. The second arrow is owned by `235_push_outbox_suite.sql`
--   (`0204-R1`…`R4`). Scoped to the notification's own id so a drained queue cannot be counted as
--   this probe's work.
create or replace function t_npf_probe(p_profile uuid, p_kind noti_kind, p_title text)
returns jsonb language plpgsql as $$
declare v1 int; v_row int; v_id uuid;
begin
  insert into notifications (profile_id, kind, title, body, ref_id)
       values (p_profile, p_kind, p_title, 'npf-probe', null)
    returning id into v_id;
  select count(*) into v1 from push_outbox where noti_id = v_id;
  select count(*) into v_row from notifications where id = v_id;
  return jsonb_build_object('pushes', v1, 'row', v_row);
end $$;

-- A chat nudge driven through 0090's REAL trigger, measured the same way.
create or replace function t_npf_chat_probe(p_thread uuid, p_sender uuid, p_to uuid)
returns jsonb language plpgsql as $$
declare v0 int; v1 int; v_row int; v_cat text;
begin
  -- 0090's anti-storm rule: one nudge per UNREAD state. Clear the unread ones or the second
  -- measurement in an arm silently writes nothing and reads as 「the preference suppressed it」.
  update notifications set read_at = now()
   where profile_id = p_to and title = '새 메시지' and read_at is null;
  -- [0204] the same substitution as `t_npf_probe` above, and for the same reason; here the
  -- notification's id is not in hand (0090's trigger writes it), so the delta is scoped to the
  -- recipient and the title instead.
  select count(*) into v0 from push_outbox where profile_id = p_to and title = '새 메시지';
  insert into chat_messages (thread_id, sender_id, body) values (p_thread, p_sender, 'npf 채팅');
  select count(*) into v1 from push_outbox where profile_id = p_to and title = '새 메시지';
  select count(*) into v_row from notifications
   where profile_id = p_to and title = '새 메시지' and read_at is null;
  select max(_noti_push_category(n.kind, n.title)) into v_cat from notifications n
   where n.profile_id = p_to and n.title = '새 메시지' and n.read_at is null;
  return jsonb_build_object('pushes', v1 - v0, 'row', v_row, 'cat', v_cat);
end $$;

-- Trap a raise so an arm records a NAME instead of aborting the block (the 0179 #14 class).
create or replace function t_npf_get() returns jsonb language plpgsql as $$
declare r record;
begin
  select * into r from get_notification_prefs();
  return jsonb_build_object('booking', r.booking, 'chat', r.chat, 'community', r.community,
                            'reward', r.reward, 'has_row', (r.updated_at is not null));
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_npf_set(p_b boolean, p_c boolean, p_m boolean, p_r boolean)
returns jsonb language plpgsql as $$
declare r record;
begin
  select * into r from set_notification_prefs(p_b, p_c, p_m, p_r);
  return jsonb_build_object('booking', r.booking, 'chat', r.chat, 'community', r.community,
                            'reward', r.reward, 'has_row', (r.updated_at is not null));
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

do $$
declare
  o uuid; o2 uuid; rn uuid; dg uuid; rt uuid; bk uuid; th uuid;
  v jsonb; v_bad text; v_msg text; v_n int; v_txt text; v_src text; v_ts timestamptz; v_ts2 timestamptz;
  v_state text; k text;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                        -- ①
  o  := t_user('npf_owner',  'owner');
  o2 := t_user('npf_other',  'owner');
  rn := t_user('npf_runner', 'runner');
  dg := t_dog(o, 'npf-dog'); rt := t_route('npf 코스');
  -- ③ the token is the defect's precondition: no token ⇒ no HTTP call ⇒ every arm reads 0
  insert into push_tokens (profile_id, token) values (o,  'ExponentPushToken[npf-owner]');
  insert into push_tokens (profile_id, token) values (o2, 'ExponentPushToken[npf-other]');

  -- ---------- [0187-N1] no row ⇒ the DEFAULTS, and reading creates nothing ----------
  begin
    v_bad := '';
    select count(*) into v_n from notification_prefs where profile_id = o;
    if v_n <> 0 then v_bad := v_bad || ' fixture: a row already exists (n=' || v_n || ')'; end if;
    perform set_config('request.jwt.claim.sub', o::text, true);
    v := t_npf_get();
    if v->>'raised' is not null then v_bad := v_bad || ' raised=' || (v->>'raised'); end if;
    if (v->>'booking')::boolean   is distinct from true then v_bad := v_bad || ' booking='   || coalesce(v->>'booking','NULL');   end if;
    if (v->>'chat')::boolean      is distinct from true then v_bad := v_bad || ' chat='      || coalesce(v->>'chat','NULL');      end if;
    if (v->>'community')::boolean is distinct from true then v_bad := v_bad || ' community=' || coalesce(v->>'community','NULL'); end if;
    if (v->>'reward')::boolean    is distinct from true then v_bad := v_bad || ' reward='    || coalesce(v->>'reward','NULL');    end if;
    if (v->>'has_row')::boolean   is distinct from false then v_bad := v_bad || ' updated_at is not NULL on an absent row'; end if;
    select count(*) into v_n from notification_prefs where profile_id = o;
    if v_n <> 0 then v_bad := v_bad || ' the READ created a row (n=' || v_n || ')'; end if;
    perform set_config('request.jwt.claim.sub', '', true);
    if v_bad = '' then call _pass('npf','0187-N1 저장한 적 없는 사람은 기본값 — 네 카테고리 모두 true, updated_at NULL, 읽기만으로는 행이 생기지 않는다');
    else v_msg := v_bad; call _fail('npf','0187-N1 defaults', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('npf','0187-N1 defaults', sqlerrm); end;

  -- ---------- [0187-N2] own row only, executed AS `authenticated` at the RLS boundary ----------
  -- The suite runs as the table OWNER, for whom RLS does not apply — so this arm is worthless
  -- unless the role actually switches. `current_user` is asserted after the switch for exactly
  -- that reason (144's ZZ001 idiom): a SET ROLE that silently failed would read as a clean pass.
  begin
    v_bad := '';
    -- both people have a saved row, and they DIFFER — a fixture where the two rows agree could
    -- not distinguish 「I read my row」 from 「I read theirs」
    insert into notification_prefs (profile_id, booking, chat, community, reward)
         values (o, true, false, true, false), (o2, false, true, false, true);
    perform set_config('request.jwt.claim.sub', o::text, true);
    execute 'set local role authenticated';
    if current_user <> 'authenticated' then v_bad := v_bad || ' SET ROLE did not take (current_user=' || current_user || ')'; end if;
    select count(*) into v_n from notification_prefs;
    if v_n <> 1 then v_bad := v_bad || ' visible rows=' || v_n || ' (expected exactly my own)'; end if;
    select count(*) into v_n from notification_prefs where profile_id = o2;
    if v_n <> 0 then v_bad := v_bad || ' the other profile''s row is VISIBLE'; end if;
    -- an UPDATE of their row writes nothing (RLS `using` filters it out — no error, zero rows)
    update notification_prefs set booking = true where profile_id = o2;
    get diagnostics v_n = row_count;
    if v_n <> 0 then v_bad := v_bad || ' UPDATE of the other row touched ' || v_n || ' rows'; end if;
    -- an INSERT for their profile_id is refused by the WITH CHECK (42501)
    v_state := 'no-error';
    begin execute format('insert into notification_prefs (profile_id, booking) values (%L, false)', o2);
    exception when others then v_state := sqlstate; end;
    if v_state <> '42501' then v_bad := v_bad || ' INSERT for the other profile: sqlstate=' || v_state || ' (only 42501 counts as a refusal)'; end if;
    -- the RPC answers the CALLER
    v := t_npf_get();
    if (v->>'chat')::boolean is distinct from false or (v->>'booking')::boolean is distinct from true
    then v_bad := v_bad || ' get() as authenticated returned ' || v::text || ' (expected my own row: booking=t chat=f)'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    delete from notification_prefs where profile_id in (o, o2);
    if v_bad = '' then call _pass('npf','0187-N2 본인 행만 — authenticated 로 실행: 남의 행은 SELECT 에 안 보이고, UPDATE 는 0행, INSERT 는 42501; RPC 는 호출자의 행을 답한다 (두 행의 값이 서로 다른 픽스처라 「내 행」과 「남의 행」이 구별된다)');
    else v_msg := v_bad; call _fail('npf','0187-N2 own row only', v_msg); end if;
  exception when others then execute 'reset role'; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('npf','0187-N2 own row only', sqlerrm); end;

  -- ---------- [0187-N3] the upsert: creates · idempotent in value · NULL leaves alone ----------
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', o::text, true);
    select count(*) into v_n from notification_prefs where profile_id = o;
    if v_n <> 0 then v_bad := v_bad || ' fixture: row present before the first save'; end if;
    -- first save: one switch off, the other three unspecified ⇒ they take the DEFAULT
    v := t_npf_set(false, null, null, null);
    if (v->>'booking')::boolean is distinct from false then v_bad := v_bad || ' create booking=' || coalesce(v->>'booking','NULL'); end if;
    if (v->>'chat')::boolean is distinct from true or (v->>'community')::boolean is distinct from true
       or (v->>'reward')::boolean is distinct from true
    then v_bad := v_bad || ' create left the unspecified columns at ' || v::text; end if;
    select count(*) into v_n from notification_prefs where profile_id = o;
    if v_n <> 1 then v_bad := v_bad || ' rows after create=' || v_n; end if;
    -- the RETURNED row is the STORED row
    select booking, updated_at into v_state, v_ts from notification_prefs where profile_id = o;
    if v_state is distinct from 'false' then v_bad := v_bad || ' stored booking=' || coalesce(v_state,'NULL'); end if;
    -- idempotent in VALUE: the same call again changes no boolean, and only `updated_at` moves
    v := t_npf_set(false, null, null, null);
    select booking::text || '/' || chat::text || '/' || community::text || '/' || reward::text, updated_at
      into v_txt, v_ts2 from notification_prefs where profile_id = o;
    if v_txt is distinct from 'false/true/true/true' then v_bad := v_bad || ' second identical save moved a value: ' || coalesce(v_txt,'NULL'); end if;
    if v_ts2 is null then v_bad := v_bad || ' updated_at went NULL'; end if;
    -- a NULL argument leaves that category alone — one switch saved on its own
    v := t_npf_set(null, false, null, null);
    select booking::text || '/' || chat::text || '/' || community::text || '/' || reward::text
      into v_txt from notification_prefs where profile_id = o;
    if v_txt is distinct from 'false/false/true/true'
    then v_bad := v_bad || ' partial save: ' || coalesce(v_txt,'NULL') || ' (a NULL argument must leave that column alone)'; end if;
    -- and the returned row agrees with what is stored
    if (v->>'booking')::boolean is distinct from false or (v->>'chat')::boolean is distinct from false
       or (v->>'community')::boolean is distinct from true or (v->>'reward')::boolean is distinct from true
    then v_bad := v_bad || ' partial save returned ' || v::text || ' (not the stored row)'; end if;
    -- turning everything back on
    v := t_npf_set(true, true, true, true);
    select booking::text || '/' || chat::text || '/' || community::text || '/' || reward::text
      into v_txt from notification_prefs where profile_id = o;
    if v_txt is distinct from 'true/true/true/true' then v_bad := v_bad || ' restore: ' || coalesce(v_txt,'NULL'); end if;
    perform set_config('request.jwt.claim.sub', '', true);
    delete from notification_prefs where profile_id = o;
    if v_bad = '' then call _pass('npf','0187-N3 upsert — 없으면 만들고(지정 안 한 칸은 기본값), 같은 값으로 다시 부르면 불리언은 그대로 updated_at 만 움직이고, NULL 인자는 그 칸을 건드리지 않는다 (스위치 하나만 저장); 반환 행 = 저장된 행');
    else v_msg := v_bad; call _fail('npf','0187-N3 upsert', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('npf','0187-N3 upsert', sqlerrm); end;

  -- ---------- [0187-N4] a NULL uid refuses BY NAME, and writes nothing ----------
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', '', true);
    select count(*) into v_n from notification_prefs;
    v := t_npf_get();
    if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' get(): ' || coalesce(v->>'raised', 'ACCEPTED — ' || v::text); end if;
    v := t_npf_set(false, false, false, false);
    if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' set(): ' || coalesce(v->>'raised', 'ACCEPTED — ' || v::text); end if;
    select count(*) - v_n into v_n from notification_prefs;
    if v_n <> 0 then v_bad := v_bad || ' a refusal wrote ' || v_n || ' rows'; end if;
    if v_bad = '' then call _pass('npf','0187-N4 로그인 없는 호출은 이름으로 거절 — 두 RPC 모두 not_signed_in, 아무것도 쓰지 않는다');
    else v_msg := v_bad; call _fail('npf','0187-N4 not_signed_in', v_msg); end if;
  exception when others then call _fail('npf','0187-N4 not_signed_in', sqlerrm); end;

  -- ---------- [0187-N5] THE SEND PATH ----------
  -- ② every number is a DELTA around one INSERT; other suites have already written stub calls.
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = o;

    -- CONTROL FIRST, and it is what makes every 0 below mean something: with NO prefs row, every
    -- category reaches the HTTP stub. A notify_push that threw (its `exception when others`
    -- swallows into a skipped push) would give 0 here too, and this arm is the only thing that
    -- tells those two worlds apart.
    foreach k in array array['booking','community','reward','safety','system','shop'] loop
      v := t_npf_probe(o, k::noti_kind, '알림');
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL(no row) ' || k || ' pushes=' || coalesce(v->>'pushes','NULL'); end if;
      if (v->>'row')::int is distinct from 1 then v_bad := v_bad || ' CONTROL ' || k || ' wrote no notifications row'; end if;
    end loop;
    v := t_npf_probe(o, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' CONTROL(no row) chat pushes=' || coalesce(v->>'pushes','NULL'); end if;

    -- ALL FOUR OFF: the four disableable categories go silent, and nothing else does.
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(false, false, false, false);
    perform set_config('request.jwt.claim.sub', '', true);
    foreach k in array array['booking','community','reward'] loop
      v := t_npf_probe(o, k::noti_kind, '알림');
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' all-off ' || k || ' STILL PUSHED (' || coalesce(v->>'pushes','NULL') || ')'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' all-off ' || k || ' lost the notifications ROW — preferences must gate the push, never the record'; end if;
    end loop;
    v := t_npf_probe(o, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 0 then v_bad := v_bad || ' all-off chat STILL PUSHED'; end if;
    if (v->>'row')::int is distinct from 1 then v_bad := v_bad || ' all-off chat lost the notifications ROW'; end if;
    -- …and the always-on ones are untouched by all four being false
    foreach k in array array['safety','system','shop'] loop
      v := t_npf_probe(o, k::noti_kind, '즉시 확인하세요');
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' all-off ' || k || ' was SILENCED (' || coalesce(v->>'pushes','NULL') || ') — safety/system are not disableable and an uncategorised kind is never muted'; end if;
    end loop;

    -- THE CROSS ARMS: each column silences its OWN category and no other. A one-flag
    -- implementation (or a mapper that collapses two categories) passes the all-off arm above and
    -- dies here — this is where the fixture sits in the zone where the rules DISAGREE.
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(false, true, true, true);   -- booking off only
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_probe(o, 'booking'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 0 then v_bad := v_bad || ' booking-off: booking pushed'; end if;
    v := t_npf_probe(o, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' booking-off: CHAT was silenced by the booking column'; end if;
    v := t_npf_probe(o, 'community'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' booking-off: community was silenced'; end if;
    v := t_npf_probe(o, 'reward'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' booking-off: reward was silenced'; end if;

    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(true, false, true, true);   -- chat off only
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_probe(o, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 0 then v_bad := v_bad || ' chat-off: the chat nudge pushed'; end if;
    v := t_npf_probe(o, 'booking'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' chat-off: ordinary booking was silenced by the chat column'; end if;

    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(true, true, false, true);   -- community off only
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_probe(o, 'community'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 0 then v_bad := v_bad || ' community-off: community pushed'; end if;
    v := t_npf_probe(o, 'booking'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' community-off: booking was silenced'; end if;

    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(true, true, true, false);   -- reward off only
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_probe(o, 'reward'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 0 then v_bad := v_bad || ' reward-off: reward pushed'; end if;
    v := t_npf_probe(o, 'community'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' reward-off: community was silenced'; end if;

    -- ANOTHER PERSON'S PREFERENCES ARE NOT MINE: o2 has no row and must keep getting everything
    -- while o is fully silenced. A gate that read the wrong profile_id passes every arm above.
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform t_npf_set(false, false, false, false);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_probe(o2, 'booking'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' the OTHER profile was silenced by MY preferences (' || coalesce(v->>'pushes','NULL') || ')'; end if;

    delete from notification_prefs where profile_id = o;
    if v_bad = '' then call _pass('npf','0187-N5 발송 경로 — 행이 없으면 전부 발송(컨트롤), 네 칸을 끄면 booking·chat·community·reward 만 조용해지고 safety·system·미분류 kind 는 그대로 나간다; 각 칸은 자기 카테고리만 끈다(교차 팔); 모든 팔에서 notifications 행은 남는다(선호는 푸시만 막는다); 남의 선호는 내 푸시를 막지 않는다');
    else v_msg := v_bad; call _fail('npf','0187-N5 send path', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('npf','0187-N5 send path', sqlerrm); end;

  -- ---------- [0187-N6] the chat discriminator, through 0090's REAL trigger ----------
  -- Not a source match on '새 메시지': that literal lives in 0090, in 0187 and in the client, and
  -- a grep cannot tell a changed title from a changed comment. This drives `chat_messages` and
  -- reads what the shipped trigger produced.
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = rn;
    bk := t_chg_bk(o, dg, rt, rn, 'confirmed', now() + interval '2 hours', 3.0, 7900, 9000, 0);
    insert into chat_threads (booking_id) values (bk) returning id into th;
    insert into push_tokens (profile_id, token) values (rn, 'ExponentPushToken[npf-runner]');

    -- the owner writes; the RUNNER is told (0090 N1), and that row must map to 'chat'
    v := t_npf_chat_probe(th, o, rn);
    if v->>'cat' is distinct from 'chat'
    then v_bad := v_bad || ' 0090''s own row maps to ' || coalesce(v->>'cat','NULL') || ' (expected chat — the two titles have drifted apart)'; end if;
    if (v->>'row')::int is distinct from 1 then v_bad := v_bad || ' fixture: 0090 wrote no nudge'; end if;
    if (v->>'pushes')::int is distinct from 1 then v_bad := v_bad || ' fixture: the nudge did not reach the stub (pushes=' || coalesce(v->>'pushes','NULL') || ')'; end if;

    -- chat OFF while booking is ON ⇒ the real nudge is silenced
    perform set_config('request.jwt.claim.sub', rn::text, true);
    perform t_npf_set(true, false, true, true);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_chat_probe(th, o, rn);
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' chat off / booking on: 0090''s nudge still pushed (' || coalesce(v->>'pushes','NULL') || ')'; end if;
    if (v->>'row')::int is distinct from 1 then v_bad := v_bad || ' chat off: the nudge ROW was lost'; end if;

    -- booking OFF while chat is ON ⇒ the real nudge is SENT (the arm that kills a mapper which
    -- files the chat nudge under booking: it passes the line above and fails this one)
    perform set_config('request.jwt.claim.sub', rn::text, true);
    perform t_npf_set(false, true, true, true);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_npf_chat_probe(th, o, rn);
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' booking off / chat on: 0090''s nudge was silenced (' || coalesce(v->>'pushes','NULL') || ') — the chat nudge is being read as a booking push'; end if;

    delete from notification_prefs where profile_id = rn;
    if v_bad = '' then call _pass('npf','0187-N6 채팅 판별은 0090 의 실제 트리거로 측정 — chat_messages INSERT 가 만든 행이 chat 으로 분류되고, chat 을 끄면(booking 은 켠 채) 조용해지며, booking 을 끄면(chat 은 켠 채) 나간다; 양쪽 모두 행동으로 재므로 0090 이든 0187 이든 제목이 바뀌면 빨개진다');
    else v_msg := v_bad; call _fail('npf','0187-N6 chat discriminator', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('npf','0187-N6 chat discriminator', sqlerrm); end;

  -- ---------- [0187-S1] the deployed shape ----------
  -- The VERIFY block in 0187 asserts the same properties at APPLY time. That protects them exactly
  -- until someone recreates a function in a LATER migration, which the VERIFY never sees — so the
  -- standing pin lives here as well, deliberately, and the two are not redundant.
  begin
    v_bad := '';
    -- definer + in-body search_path, by value
    select count(*) into v_n from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push','get_notification_prefs','set_notification_prefs')
       and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig);
    if v_n <> 3 then v_bad := v_bad || ' definer+search_path count=' || v_n || ' (expected 3)'; end if;
    -- ACL by value, both directions
    select string_agg(p.oid::regprocedure::text, ', ') into v_txt from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push','get_notification_prefs','set_notification_prefs','_noti_push_category')
       and (has_function_privilege('public', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
    if v_txt is not null then v_bad := v_bad || ' PUBLIC/anon can execute: ' || v_txt; end if;
    if has_function_privilege('authenticated', 'get_notification_prefs()', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot call get_notification_prefs'; end if;
    if has_function_privilege('authenticated', 'set_notification_prefs(boolean, boolean, boolean, boolean)', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot call set_notification_prefs'; end if;
    if has_function_privilege('authenticated', '_noti_push_category(noti_kind, text)', 'execute') is not false
    then v_bad := v_bad || ' authenticated can call the internal mapper'; end if;

    -- the trigger that makes any of this reachable — SHAPE is not STATE (the pg_get_triggerdef law)
    select count(*) into v_n from pg_trigger
     where tgrelid = 'notifications'::regclass and tgname = 'notifications_push'
       and not tgisinternal and tgenabled = 'O';
    if v_n <> 1 then v_bad := v_bad || ' notifications_push enabled-count=' || v_n || ' (tgenabled must be O)'; end if;

    -- RLS on, exactly one policy, self-scoped on BOTH sides
    if (select relrowsecurity from pg_class where oid = 'notification_prefs'::regclass) is not true
    then v_bad := v_bad || ' RLS is off on notification_prefs'; end if;
    select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'notification_prefs';
    if v_n <> 1 then v_bad := v_bad || ' policy count=' || v_n; end if;
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = 'notification_prefs'
       and coalesce(qual,'') ~ 'auth\.uid\(\)' and coalesce(with_check,'') ~ 'auth\.uid\(\)';
    if v_n <> 1 then v_bad := v_bad || ' the policy is not self-scoped on both USING and WITH CHECK'; end if;

    -- notify_push's SOURCE, COMMENTS STRIPPED (a comment explaining the gate would otherwise
    -- satisfy a check for the gate — the standing law), with a NO-SOURCE arm so an absent
    -- function fails LOUDLY: position(x in NULL) is NULL and a bare IF on NULL never fires.
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
    else
      if position('_noti_push_category' in v_src) = 0 then v_bad := v_bad || ' notify_push does not call the category mapper'; end if;
      if position('notification_prefs'  in v_src) = 0 then v_bad := v_bad || ' notify_push does not read notification_prefs'; end if;
      -- TWO arms, because the bare-literal one is satisfiable by a `'safety'` written anywhere
      -- earlier. Measured (M12): removing the guard AND giving the `case` its own `'safety'` arm
      -- keeps a `'safety'` literal ahead of the table name, so the ordering arm alone passed on a
      -- function where safety HAD become disableable. N5 caught it behaviourally; this arm is what
      -- makes S1 stand on its own. The property, stated without reference to that mutation: the
      -- send path must carry a conjunct that excludes the safety category from the preference
      -- lookup, and the safety decision must precede the read.
      if v_src !~ 'v_cat\s*<>\s*''safety'''
      then v_bad := v_bad || ' the safety-excluding conjunct is gone from the send path'; end if;
      if not (position('''safety''' in v_src) > 0
              and position('''safety''' in v_src) < position('notification_prefs' in v_src))
      then v_bad := v_bad || ' the safety decision is not taken BEFORE the prefs read (safety@'
                          || position('''safety''' in v_src) || ' prefs@' || position('notification_prefs' in v_src) || ')'; end if;
    end if;
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_noti_push_category';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_noti_push_category)';
    else
      if position('''system''' in v_src) = 0
      then v_bad := v_bad || ' the mapper no longer files ops escalations (system) under safety'; end if;
    end if;

    if v_bad = '' then call _pass('npf','0187-S1 배포 형상 — 세 definer 는 prosecdef + 본문 search_path=public, pg_temp 이고 PUBLIC/anon 실행 불가, authenticated 는 두 RPC 만 부를 수 있으며 내부 매퍼는 못 부른다; notifications_push 트리거는 tgenabled=O(정의가 아니라 상태); 테이블은 RLS 켜짐 + 정책 1개(USING·WITH CHECK 양쪽 auth.uid()); notify_push 소스(주석 제거)는 매퍼를 부르고 prefs 를 읽으며 safety 판정이 그 읽기보다 앞선다');
    else v_msg := v_bad; call _fail('npf','0187-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('npf','0187-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
