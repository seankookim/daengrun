-- ═══ 220 — 0189: an urgent BOOKING notification is not disableable · a tombstone gets no push ═══
--           0189-U1 · U2 · T1 · T2 · S1, tag `urg`
--
-- Codex REJECT/2 on 0187, both HIGH, fixed forward. THE PROPOSITIONS THIS FILE OWNS:
--   · U1 the three REAL client payloads — the exact (kind, title) tuples `sendSOS`,
--     `openBookingIncident` and `notifyRunStop` write — still reach the send boundary with ALL FOUR
--     preference columns false; the ordinary booking payloads from the same file (`addRunEvent`'s
--     응가 완료, `notifyKmMilestone`'s 3km 돌파) do NOT, which is the control that stops 「classify
--     everything as safety」 passing; and in every arm the `notifications` ROW is still written.
--     The family is kind-agnostic, so the same titles under `community` also send.
--   · U2 the match is EXACT EQUALITY. Four near misses — a trailing space, a leading space, a
--     longer title containing the real one, and a PREFIX of the real one — are all ordinary
--     booking rows and are silenced by `booking = false`. `notification-route.ts:45` records why
--     this matters: partial matching is what caused the 「도착」 routing incident.
--   · T1 THE TOMBSTONE, both ways round. A profile tombstoned by the real
--     `delete_my_account_tx` that then re-registers a token (the `auth_delete_pending` chain —
--     0115:227-234 skips the SQL half on every retry, so the new token survives forever) receives
--     ZERO pushes, for `booking` AND for `safety`; a live profile in the same block still receives
--     both, which is the control; and the `notifications` ROW is written in all four cases,
--     because this slice withholds a device push and destroys no evidence.
--   · T2 THE BELT: as `authenticated`, a tombstoned owner's `push_tokens` INSERT and UPDATE are
--     refused by name (`account_deleted`); a live owner's succeed (control); and a tombstoned
--     owner can still DELETE its own token, which is the one cleanup path a stranded account has.
--   · S1 deployed shape: the definers, their in-body `search_path`, ACL by value, the trigger's
--     `tgenabled` (STATE, never `pg_get_triggerdef`'s shape), and — in source WITH COMMENTS
--     STRIPPED, with NO-SOURCE arms — the live-recipient conjunct taken BEFORE the category
--     decision, the urgent family consulted ABOVE every disableable arm, and 0187's own two
--     properties restated because 0189 recreates both functions.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins) ───
--   · Delivery. `00_shim.sql` stubs `net.http_post` into `net._stub_calls`; what is measured is
--     「the row→HTTP step was taken」, never that Expo delivered anything.
--   · That the CLIENT still writes these three titles. SQL cannot read a `.ts` file —
--     `app/test/notification-prefs.test.cjs` reads `api.ts` and this migration as text, comments
--     stripped, and asserts the three values agree in BOTH directions. A rename on either side
--     is silent here and loud there. Neither gate is evidence for the other.
--   · That a tombstoned-but-auth-pending account cannot become a party to a NEW booking. That is
--     0115's surface; named in 0189 §0b as the one residual path by which a live counterparty's
--     SOS could target a tombstone.
--
-- ─── MUTATION MAP — measured 2026-09-21 in an md5-identical lab (`/tmp/dr-0189-lab`, both gates:
--     the harness AND `app/test/notification-prefs.test.cjs`), every plant assert-gated AND
--     `&&`-chained so an unlanded plant yields NO row, CONTROL observed first (harness 1319/0,
--     cjs 44/0) and re-observed clean after the one pin repair below. 「demoted」 = 0189's VERIFY
--     raise turned into a notice so the SUITE is what is measured; 「un-demoted」 = the shipped
--     file, where VERIFY aborts the apply before any suite runs. ───
--   (i)   the urgent-title arm deleted (0187's exact defect, back)  → 1317/2: U1 + S1
--   (ii)  the arm KEPT but moved below the disableable booking arm  → 1317/2: U1 + S1. Reads as
--         present to any grep for the function name; only the ORDER arm can see it.
--   (iii) exact equality relaxed to a PREFIX match                  → 1318/1: U2 ('SOS ' and
--         'SOS 요청' became urgent — the 「도착」 class, reproduced)
--   (iv)  the `deleted_at is null` conjunct deleted                 → 1317/2: T1 (all three kinds
--         pushed to a tombstone) + S1
--   (v)   the live-recipient lookup moved one line DOWN, still unconditional
--                                                                   → 1318/1: S1 ALONE. It is
--         behaviourally identical, which is the point: the ORDER is a belt only text can see.
--   (vb)  the live-recipient lookup moved INSIDE the non-safety branch — THE REAL BYPASS
--                                                                   → 1317/2: T1 (safety, system
--         and SOS all reached the tombstone) + S1. ⚠ (v) alone did NOT produce this, and saying so
--         matters: a battery row that reddens S1 only can hide the fact that the behavioural
--         property was never attacked. This plant is what closes that.
--   (vi)  the belt's predicate deleted (`if false`)                 → 1317/2: T2 + S1
--   (vii) the belt raises for EVERYBODY (`if true`)                 → the harness DIES at suite
--         218, whose fixture writes tokens for LIVE profiles; with 218 unregistered in the lab it
--         dies at 220's own fixture instead. Caught loudly three different ways — but T2's LIVE
--         CONTROL arm is never REACHED, so it is not what catches it. Recorded honestly rather
--         than claimed.
--   (viib) the belt refuses every UPDATE, by the same name, for everybody — the narrower plant
--         that isolates that one arm                                → 1318/1: **T2's live control
--         ALONE** (`CONTROL: a LIVE owner was refused an UPDATE: P0001/account_deleted`). The
--         control can fail, and this is the measurement that says so.
--   (viii) the belt's trigger never created                         → 1316/3: T1 + T2 + S1
--   (ix)  the family widened by one ('응가 완료' added)             → 1317/2: U1's CONTROL (an
--         ordinary payload became unmutable) + U2's count arm; cjs 42/2 as well.
--   ── the DRIFT GATE's own controls (cjs only; a new detector must be shown to fail) ──
--   (c1)  renamed on the CLIENT only (writer + mirror move)         → cjs 41/3
--   (c2)  renamed on the SERVER only                                → cjs 42/2 (both directions)
--   (c3)  the writer reverts to an inline literal — `sendSOS`'s shape before this slice
--                                                                   → cjs 43/1
--   (c4)  the title kept ONLY in the migration's PROSE, removed from the array — the
--         comment-quoting class, and the one thing an un-stripped read waves through
--                                                                   → cjs 41/3
--   UN-DEMOTED, the shipped file: (i) (ii) (iv) (v) (vb) (vi) (viii) each ABORT the apply at
--   0189's VERIFY with the matching name.
--   ⚠ ONE PIN REPAIR CAME OUT OF THIS BATTERY, and it is a repair to the REPORT rather than to
--   the property: under (vi) T2 died with `duplicate key value violates unique constraint
--   "push_tokens_pkey"` — the disarmed belt let the earlier INSERT succeed, the later fixture
--   INSERT collided, and the block's exception handler discarded the `v_bad` that already named
--   exactly which boundary had accepted a tombstoned write. A `delete` now precedes that fixture.
--   Stated without reference to the mutation: a pin must name the boundary that failed, not the
--   next statement to trip over it. The control was re-observed clean afterwards and (vi) re-run.
--
-- ─── FIXTURE NOTES ───
--  ① Every push measurement is a DELTA around one INSERT, never an absolute count: other suites in
--     this database have already written to `net._stub_calls`.
--  ② The fixture profiles hold a real `ExponentPushToken…`. Without it `notify_push` returns before
--     the HTTP call for a reason that has nothing to do with this slice, and every arm reads 0 —
--     a fixture must contain the defect's precondition (0151's measured lesson).
--  ③ T1's tombstone is made by the REAL `delete_my_account_tx`, not by stamping `deleted_at` by
--     hand, so the fixture starts where production starts. The re-registration then has to be made
--     with 0189's own belt trigger temporarily disabled — which is not a cheat but the ONLY honest
--     way to model the token this finding is actually about: one written by a client build that
--     predates 0189, or written in the window before it deployed. The belt's own behaviour is T2's
--     job, and the two must not borrow each other's green.
--  ④ `request.jwt.claim.sub` is set and cleared explicitly around every arm.
set client_min_messages = warning;

-- One INSERT, measured both ways: stub calls produced, and whether the row landed.
create or replace function t_urg_probe(p_profile uuid, p_kind noti_kind, p_title text)
returns jsonb language plpgsql as $$
declare v0 int; v1 int; v_row int; v_id uuid;
begin
  select count(*) into v0 from net._stub_calls;
  insert into notifications (profile_id, kind, title, body, ref_id)
       values (p_profile, p_kind, p_title, 'urg-probe', null)
    returning id into v_id;
  select count(*) into v1 from net._stub_calls;
  select count(*) into v_row from notifications where id = v_id;
  return jsonb_build_object('pushes', v1 - v0, 'row', v_row);
end $$;

-- A push_tokens write attempted AS a given role, with the failure NAMED rather than swallowed.
create or replace function t_urg_token_write(p_uid uuid, p_token text, p_update boolean)
returns text language plpgsql as $$
begin
  if p_update then
    execute format('update push_tokens set token = %L where profile_id = %L', p_token, p_uid);
  else
    execute format('insert into push_tokens (profile_id, token) values (%L, %L)', p_uid, p_token);
  end if;
  return 'accepted';
exception when others then
  return sqlstate || '/' || sqlerrm;
end $$;

do $$
declare
  o uuid; live uuid; tomb uuid; dead2 uuid;
  v jsonb; v_bad text; v_msg text; v_n int; v_src text; v_res jsonb; v_out text;
  t text; k text;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ④
  o    := t_user('urg_owner', 'owner');
  live := t_user('urg_live',  'owner');
  insert into push_tokens (profile_id, token) values (o,    'ExponentPushToken[urg-owner]');
  insert into push_tokens (profile_id, token) values (live, 'ExponentPushToken[urg-live]');

  -- ---------- [0189-U1] the three REAL client payloads survive `booking = false` ----------
  -- These are not invented strings: they are `SOS_TITLE`, `INCIDENT_NOTI_TITLE` and
  -- `RUN_STOP_TITLE` as `api.ts:3548 / :3741 / :3811` write them, all with kind='booking' because
  -- 0114:273-281 admits nothing else from a booking party.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform set_notification_prefs(false, false, false, false);
    perform set_config('request.jwt.claim.sub', '', true);

    foreach t in array array['SOS', '사고 신고 접수', '러닝 중단 요청'] loop
      v := t_urg_probe(o, 'booking'::noti_kind, t);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' [' || t || '] SILENCED by booking=false (pushes='
                          || coalesce(v->>'pushes', 'NULL') || ')'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' [' || t || '] lost the notifications ROW'; end if;
      -- kind-agnostic: the family is not gated on `booking`, so a future writer's choice of kind
      -- cannot mute it
      v := t_urg_probe(o, 'community'::noti_kind, t);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' [' || t || '] silenced under kind=community (the family must be '
                          || 'kind-agnostic)'; end if;
    end loop;

    -- THE CONTROL, and it is the arm that stops 「classify everything as safety」 passing: the
    -- ORDINARY payloads from the very same client file must still be silenced.
    foreach t in array array['응가 완료', '간식 타임', '수분 보충', '새 사진 도착', '3km 돌파'] loop
      v := t_urg_probe(o, 'booking'::noti_kind, t);
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' CONTROL [' || t || '] still pushed — booking=false must silence the '
                          || 'ordinary client payloads'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL [' || t || '] lost the notifications ROW'; end if;
    end loop;
    -- and the chat nudge still belongs to `chat`, not to the urgent family
    v := t_urg_probe(o, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' the chat nudge escaped chat=false into the urgent family'; end if;

    if v_bad = '' then call _pass('urg','0189-U1 클라이언트가 쓰는 긴급 3종(SOS · 사고 신고 접수 · 러닝 중단 요청)은 네 칸을 모두 꺼도 발송된다 — 0114:273-281 때문에 셋 다 kind=booking 으로 도착하고, 0187 단독이면 booking=false 가 SOS 를 침묵시켰다; kind 와 무관하게 긴급이고; 같은 파일의 평범한 알림 5종과 채팅 넛지는 그대로 꺼진다(컨트롤); 모든 팔에서 notifications 행은 남는다');
    else v_msg := v_bad; call _fail('urg','0189-U1 urgent titles', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('urg','0189-U1 urgent titles', sqlerrm); end;

  -- ---------- [0189-U2] EXACT equality — four near misses are ordinary booking rows ----------
  -- `notification-route.ts:44-45` records the reason in the shipped comment: partial matching is
  -- what produced the 「도착」 incident. A prefix/substring rule here would make any title
  -- CONTAINING 'SOS' unmutable, which is a different and worse bug than the one being fixed.
  begin
    v_bad := '';
    foreach t in array array['SOS ', ' SOS', 'SOS 요청', '러닝 중단', '사고 신고', 'sos'] loop
      v := t_urg_probe(o, 'booking'::noti_kind, t);
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' near-miss [' || t || '] was treated as urgent (pushes='
                          || coalesce(v->>'pushes', 'NULL') || ') — the match must be exact'; end if;
    end loop;
    -- and the array is the family, not a set someone widened to get a green
    -- ⚠ [0193 §E] 3 → 4. The fourth member is 「귀가 확인이 필요해요」, 0188 arm ⓑ-①'s zero-stamp
    -- escalation — a SERVER-written title, which is why 0189 could describe this array as 「the
    -- three titles a CLIENT writes」 and 0193 cannot. Codex B5: 0187 filed it as a disableable
    -- booking row, so 예약 알림 off silenced 「the dog is unaccounted for」. 0193 classifies it at
    -- the WRITER (kind='safety') and this entry is the belt for rows already written as `booking`.
    -- Updated here rather than left to fail for a true reason (the house law); the NEW property —
    -- the real escalation pushes with 예약 알림 off — is owned by 224 `0193-B5`.
    if array_length(_noti_urgent_noti_titles(), 1) is distinct from 4
    then v_bad := v_bad || ' the urgent family no longer holds exactly 4 titles (n='
                        || coalesce(array_length(_noti_urgent_noti_titles(), 1)::text, 'NULL') || ')'; end if;
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform set_notification_prefs(true, true, true, true);
    perform set_config('request.jwt.claim.sub', '', true);
    if v_bad = '' then call _pass('urg','0189-U2 완전 일치만 긴급이다 — 뒤 공백·앞 공백·긴 제목·접두사·부분 문자열·소문자 여섯 가지 근접 실패는 전부 평범한 booking 행이고 booking=false 에 꺼진다 (부분 일치는 「도착」 사고의 원인, notification-route.ts:44); 목록은 정확히 4개 — 0193 §E가 0188 ⓑ-①의 서버 발신 제목 「귀가 확인이 필요해요」를 더했다(그 제목의 새 성질은 224 0193-B5가 소유)');
    else v_msg := v_bad; call _fail('urg','0189-U2 exact match', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('urg','0189-U2 exact match', sqlerrm); end;

  -- ---------- [0189-T1] a tombstone gets no push, not even a safety one ----------
  -- ③ The tombstone is made by the REAL `delete_my_account_tx`; the re-registration is made with
  -- 0189's belt temporarily disabled, because the token this finding is about is one written by a
  -- build that predates 0189. The belt itself is T2's job.
  begin
    v_bad := '';
    tomb := t_user('urg_tomb', 'owner');
    insert into push_tokens (profile_id, token) values (tomb, 'ExponentPushToken[urg-tomb-pre]');
    v_res := delete_my_account_tx(tomb);
    if (v_res->>'tombstoned')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: delete_my_account_tx did not tombstone (' || v_res::text || ')'; end if;
    select count(*) into v_n from profiles where id = tomb and deleted_at is not null;
    if v_n <> 1 then v_bad := v_bad || ' fixture: deleted_at not set'; end if;
    select count(*) into v_n from push_tokens where profile_id = tomb;
    if v_n <> 0 then v_bad := v_bad || ' fixture: ④ did not delete the token (n=' || v_n || ')'; end if;

    -- the re-registration `push.ts:194-201` performs on the next launch (0115:227-234 means a
    -- retry never removes it again)
    alter table push_tokens disable trigger push_tokens_live_owner;
    insert into push_tokens (profile_id, token) values (tomb, 'ExponentPushToken[urg-tomb-again]');
    alter table push_tokens enable trigger push_tokens_live_owner;
    select count(*) into v_n from push_tokens where profile_id = tomb;
    if v_n <> 1 then v_bad := v_bad || ' fixture: the re-registration did not land'; end if;

    -- BOTH kinds, because the conjunct is taken ahead of the category decision
    foreach k in array array['booking', 'safety', 'system'] loop
      v := t_urg_probe(tomb, k::noti_kind, '즉시 확인하세요');
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' tombstone STILL PUSHED for kind=' || k || ' (pushes='
                          || coalesce(v->>'pushes', 'NULL') || ')'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' tombstone lost the notifications ROW for kind=' || k
                          || ' — the record must survive; only the device push is withheld'; end if;
    end loop;
    -- and an urgent title is refused too: a tombstone has no identity to rescue (0189 §0b)
    v := t_urg_probe(tomb, 'booking'::noti_kind, 'SOS');
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' tombstone still received an SOS push'; end if;

    -- THE CONTROL, in the same block and with no preferences saved: a LIVE profile gets all of it.
    -- Without this arm every 0 above would also be produced by a broken trigger or a dead stub.
    foreach k in array array['booking', 'safety'] loop
      v := t_urg_probe(live, k::noti_kind, '즉시 확인하세요');
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL: the LIVE profile was silenced for kind=' || k
                          || ' (pushes=' || coalesce(v->>'pushes', 'NULL') || ')'; end if;
    end loop;
    v := t_urg_probe(live, 'booking'::noti_kind, 'SOS');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' CONTROL: the LIVE profile did not get its SOS'; end if;

    if v_bad = '' then call _pass('urg','0189-T1 툼스톤에는 푸시가 안 간다 — 진짜 delete_my_account_tx 로 탈퇴시키고(④가 토큰을 지운다), 0189 이전 빌드처럼 토큰을 다시 등록해도 booking·safety·system·SOS 전부 0회; 같은 블록의 살아 있는 프로필은 전부 받는다(컨트롤); 네 경우 모두 notifications 행은 남는다 — 이 슬라이스는 기기 푸시만 막고 증거를 지우지 않는다');
    else v_msg := v_bad; call _fail('urg','0189-T1 tombstoned push', v_msg); end if;
  exception when others then
    begin alter table push_tokens enable trigger push_tokens_live_owner; exception when others then null; end;
    call _fail('urg','0189-T1 tombstoned push', sqlerrm); end;

  -- ---------- [0189-T2] the belt: a tombstone cannot WRITE a token ----------
  -- Executed AS `authenticated` at the real boundary. `current_user` is asserted after the switch
  -- (144's ZZ001 idiom): a SET ROLE that silently failed would make every refusal below read as a
  -- security pass when it was really the superuser being refused for some other reason.
  begin
    v_bad := '';
    dead2 := t_user('urg_tomb2', 'owner');
    v_res := delete_my_account_tx(dead2);
    if (v_res->>'tombstoned')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: second tombstone not made'; end if;

    perform set_config('request.jwt.claim.sub', dead2::text, true);
    execute 'set local role authenticated';
    if current_user <> 'authenticated'
    then v_bad := v_bad || ' SET ROLE did not take (current_user=' || current_user || ')'; end if;
    v_out := t_urg_token_write(dead2, 'ExponentPushToken[urg-refused]', false);
    if v_out not like '%account_deleted%'
    then v_bad := v_bad || ' tombstoned INSERT: ' || v_out || ' (expected account_deleted)'; end if;
    execute 'reset role';
    select count(*) into v_n from push_tokens where profile_id = dead2;
    if v_n <> 0 then v_bad := v_bad || ' a refused INSERT still wrote a row'; end if;

    -- UPDATE is refused too — an existing row must not be revived by a tombstone.
    -- ⚠ The DELETE below is load-bearing for the PIN rather than for the product, and the battery
    -- is what taught it: with the belt disarmed the INSERT above SUCCEEDS, this fixture INSERT then
    -- hit `push_tokens_pkey`, the block jumped to its exception handler and reported a duplicate
    -- key — discarding the accumulated `v_bad` that already said exactly which boundary had
    -- accepted a tombstoned write. The property is unchanged; what changes is that T2 now REPORTS
    -- ITS OWN DIAGNOSIS instead of a downstream collision. (Stated without reference to that
    -- mutation: a pin must name the boundary that failed, not the next statement to trip over it.)
    delete from push_tokens where profile_id = dead2;
    alter table push_tokens disable trigger push_tokens_live_owner;
    insert into push_tokens (profile_id, token) values (dead2, 'ExponentPushToken[urg-old]');
    alter table push_tokens enable trigger push_tokens_live_owner;
    perform set_config('request.jwt.claim.sub', dead2::text, true);
    execute 'set local role authenticated';
    v_out := t_urg_token_write(dead2, 'ExponentPushToken[urg-new]', true);
    if v_out not like '%account_deleted%'
    then v_bad := v_bad || ' tombstoned UPDATE: ' || v_out || ' (expected account_deleted)'; end if;
    -- …but DELETE is deliberately left open: it is the one cleanup path a stranded account has
    delete from push_tokens where profile_id = dead2;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_bad := v_bad || ' a tombstone could not DELETE its own token (rows=' || v_n || ')'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);

    -- THE CONTROL: a LIVE owner writes and rewrites its own token through the same boundary. A
    -- trigger that raised for everybody would satisfy every arm above and fail exactly here.
    perform set_config('request.jwt.claim.sub', live::text, true);
    execute 'set local role authenticated';
    v_out := t_urg_token_write(live, 'ExponentPushToken[urg-live-2]', true);
    if v_out is distinct from 'accepted'
    then v_bad := v_bad || ' CONTROL: a LIVE owner was refused an UPDATE: ' || v_out; end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    select count(*) into v_n from push_tokens
     where profile_id = live and token = 'ExponentPushToken[urg-live-2]';
    if v_n <> 1 then v_bad := v_bad || ' CONTROL: the live owner''s UPDATE did not land'; end if;

    if v_bad = '' then call _pass('urg','0189-T2 벨트 — authenticated 로 실행: 툼스톤의 push_tokens INSERT·UPDATE 는 account_deleted 로 이름 붙여 거절되고 아무것도 안 쓰이지만, 자기 토큰 DELETE 는 열려 있다(막다른 계정의 유일한 청소 경로); 살아 있는 소유자는 같은 경계를 그대로 통과한다(컨트롤 — 모두에게 raise 하는 트리거는 여기서만 죽는다)');
    else v_msg := v_bad; call _fail('urg','0189-T2 token belt', v_msg); end if;
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    begin alter table push_tokens enable trigger push_tokens_live_owner; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', true);
    call _fail('urg','0189-T2 token belt', sqlerrm); end;

  -- ---------- [0189-S1] the deployed shape ----------
  begin
    v_bad := '';
    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname in ('notify_push', '_push_token_live_owner')
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) <> 2
    then v_bad := v_bad || ' definer+search_path count is not 2'; end if;
    select string_agg(p.oid::regprocedure::text, ', ') into v_src from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push', '_push_token_live_owner', '_noti_push_category',
                         '_noti_urgent_noti_titles')
       and (has_function_privilege('public', p.oid, 'execute')
         or has_function_privilege('anon',   p.oid, 'execute'));
    if v_src is not null then v_bad := v_bad || ' PUBLIC/anon can execute: ' || v_src; end if;
    if has_function_privilege('authenticated', '_noti_urgent_noti_titles()', 'execute') is not false
    then v_bad := v_bad || ' authenticated can call the urgent-title list'; end if;

    -- the belt's trigger: STATE, not shape (pg_get_triggerdef renders a DISABLED trigger
    -- identically — the standing law, and this suite itself disables it twice)
    if (select count(*) from pg_trigger
         where tgrelid = 'push_tokens'::regclass and tgname = 'push_tokens_live_owner'
           and not tgisinternal and tgenabled = 'O') <> 1
    then v_bad := v_bad || ' push_tokens_live_owner is missing or not tgenabled=O'; end if;
    -- 0187's trigger is still the one that starts all of this
    if (select count(*) from pg_trigger
         where tgrelid = 'notifications'::regclass and tgname = 'notifications_push'
           and not tgisinternal and tgenabled = 'O') <> 1
    then v_bad := v_bad || ' notifications_push is missing or not tgenabled=O'; end if;

    -- notify_push's SOURCE, COMMENTS STRIPPED, with a NO-SOURCE arm: `position(x in NULL)` is NULL
    -- and a bare IF on NULL never fires, so an absent function must fail LOUDLY.
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
    else
      if position('deleted_at is null' in v_src) = 0
      then v_bad := v_bad || ' the live-recipient conjunct is gone from the send path'; end if;
      if not (position('deleted_at is null' in v_src) > 0
              and position('deleted_at is null' in v_src) < position('_noti_push_category' in v_src))
      then v_bad := v_bad || ' the live-recipient conjunct is not taken BEFORE the category '
                          || '(live@' || position('deleted_at is null' in v_src)
                          || ' category@' || position('_noti_push_category' in v_src) || ')'; end if;
      -- 0187's two properties, restated because 0189 recreates this function
      if v_src !~ 'v_cat\s*<>\s*''safety'''
      then v_bad := v_bad || ' the safety-excluding conjunct is gone from the send path'; end if;
      if not (position('''safety''' in v_src) > 0
              and position('''safety''' in v_src) < position('notification_prefs' in v_src))
      then v_bad := v_bad || ' the safety decision is not taken BEFORE the prefs read'; end if;
    end if;

    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_noti_push_category';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_noti_push_category)';
    else
      if position('_noti_urgent_noti_titles' in v_src) = 0
      then v_bad := v_bad || ' the mapper does not consult the urgent-title family'; end if;
      if not (position('_noti_urgent_noti_titles' in v_src) > 0
              and position('_noti_urgent_noti_titles' in v_src) < position('''chat''' in v_src))
      then v_bad := v_bad || ' the urgent family is consulted BELOW a disableable arm'; end if;
      if position('''system''' in v_src) = 0
      then v_bad := v_bad || ' the mapper no longer files ops escalations (system) under safety'; end if;
    end if;

    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_push_token_live_owner';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_push_token_live_owner)';
    else
      if position('deleted_at is not null' in v_src) = 0
      then v_bad := v_bad || ' the belt no longer tests deleted_at'; end if;
      if position('account_deleted' in v_src) = 0
      then v_bad := v_bad || ' the belt no longer raises account_deleted by name'; end if;
    end if;

    if v_bad = '' then call _pass('urg','0189-S1 배포 형상 — 두 definer 는 prosecdef + 본문 search_path=public, pg_temp 이고 네 함수 모두 PUBLIC/anon 실행 불가(긴급 목록은 authenticated 도 못 부른다); push_tokens_live_owner 와 notifications_push 는 tgenabled=O(정의가 아니라 상태); notify_push 소스(주석 제거)는 live-recipient 조건을 카테고리 판정보다 먼저 두고 0187 의 두 성질을 그대로 유지하며, 매퍼는 긴급 목록을 모든 비활성화 가능 팔보다 위에서 읽고, 벨트는 deleted_at 을 보고 account_deleted 로 이름 붙여 거절한다');
    else v_msg := v_bad; call _fail('urg','0189-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('urg','0189-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
