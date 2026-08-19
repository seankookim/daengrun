-- ═══ 150 account-deletion suite — 0115 pins (App Store 5.1.1(v) · PIPA 제37조) ═══
-- Contract: docs/contracts/account-deletion-contract.md §D (pins), §H (review log).
-- Style: sibling of 105-148 — `_pass('acd',…)`/`_fail('acd',…)`. Clear `request.jwt.claim.sub`
--   before `set local role` (129's law). Assert by EXECUTING, never by reading a grant catalog
--   (147 M5's law: a privilege listing is not proof that a write is refused).
--
-- ─── WHAT THIS SUITE IS ACTUALLY GUARDING ──────────────────────────────────────────────────
-- `profiles.id → auth.users(id) ON DELETE CASCADE` made `auth.admin.deleteUser(uid)` a 33-path
-- cascade that destroyed money, consent evidence, custody chains and an access audit log — and
-- ABORTED for anyone who had ever booked. 0115 drops that edge, which converts every silent
-- cascade into an explicit, named delete list. The pins below hold both halves: that the delete
-- list deletes exactly what it says (P1's whole-schema count diff), and that the explicit list
-- has not itself become a new cascade source (N6).
--
-- 🔴 **THE `%access_log` WILDCARD IN N6, AND ITS REASON, VERBATIM FROM THE CONTRACT** — because
-- the next person to read this file is the one who will simplify it:
--     The unbuilt 위치정보 이용·제공 사실 확인자료 ledger (위치정보법 제16조, ≥ 6 months) will be
--     named something like `location_access_log`, and **the natural shape for it is not
--     `profile_id references profiles` — it is `address_id references addresses on delete
--     cascade`**, copied from the one existing house precedent for an access ledger,
--     `gate_code_access_log` (0001:130-136). A wildcard that only inspects `profiles` edges
--     would wave it straight through. The wildcard + the recursive closure + `addresses` being
--     reachable from the delete list are THREE THINGS THAT MUST ALL HOLD for that ledger to be
--     caught — otherwise the next person simplifies one of the three.
--
-- ⚠ **N6 IS ROOTED AT WHAT IS ACTUALLY DELETED, NOT AT `profiles` — a correction to §D.N6 as
-- written, and it is the F4 defect one level deeper.** The contract's algorithm names `profiles`
-- in the root set with a literal two-name exemption {club_acks, runner_applications}. MEASURED
-- on this schema, that form is RED ON A CORRECT IMPLEMENTATION: it flags eight retention tables
-- through `profiles > dogs > session_dogs > {payment_attempts, delegation_consents,
-- dog_custody_events, dog_run_segments, assignment_events, club_fee_items}` and
-- `profiles > addresses > gate_code_access_log` — every one of them via `dogs` or `addresses`,
-- which this design KEEPS+ANONYMISES and never deletes. The real exemption was never two
-- children; it is two intermediate PARENTS. So arm 1 roots the closure at `auth.users` ∪ the
-- RPC's own ④ delete list (**re-derived from `prosrc`, not copied**, so the pin tracks the
-- function body), and `profiles` enters that closure automatically the instant anyone re-adds a
-- CASCADE FK from `profiles.id` into `auth.users` — a tripwire on 0115's own load-bearing change.
-- Arm 2 then carries what the two-name exemption was really protecting and arm 1 cannot express:
-- **no retention table may make its survival depend on the `profiles` row surviving.** Two arms,
-- because "profiles is never deleted" is a property of one function's body and the schema does
-- not know it.
--
-- ⚠ **STORAGE, AND A HARNESS GAP STATED RATHER THAN PAPERED OVER (N8).** Production's
-- `storage.objects` carries a `BEFORE DELETE STATEMENT` trigger `protect_objects_delete →
-- storage.protect_delete()` which raises 42501 even for `service_role` unless
-- `storage.allow_delete_query` is set — so a definer RPC **cannot** delete a storage object, and
-- a `delete from storage.objects` inside the transaction would raise mid-flight and roll back a
-- half-done deletion. **`00_shim.sql` has `storage.objects` but NOT that trigger**, so the
-- harness is strictly MORE PERMISSIVE than production here: a naive implementation that swept
-- storage in SQL would pass locally and fail in production. Adding the trigger to the shim was
-- considered and NOT taken: `104_private_media_suite.sql` M14 pins that a client DELETE on
-- someone else's object is a silent 0-row no-op ("no oracle"), and a statement-level BEFORE
-- DELETE trigger fires before row filtering, so the trigger would convert that shipped pin's
-- measured property into a raise — a drive-by rewrite of another suite's meaning for a reason
-- unrelated to this slice. N8 therefore pins the fact from the FUNCTION SOURCE (no storage write
-- exists in `delete_my_account_tx`) and the live behaviour is a §E.4 probe item.
--
-- ─── MUTATION map ───
--   M1 ← put `addresses` back into the RPC's ④ delete list  → N6-1 (addresses becomes a root and
--        reaches gate_code_access_log), P1 (count diff), N7 (address orphan), and the NO ACTION
--        abort (bookings/gear_claims/recurring_series into addresses) reddens P1/P2 outright
--   M2 ← drop the `club_custody` token from the state gate  → N2-b (the arm the review was
--        bought with: a runner holding another owner's dog deletes), N2-set
--   M3 ← add a fake `on delete cascade` FK from a retention table to profiles → N6-2
--   M4 ← remove `p.deleted_at is null` from `available_runners` → N5-b
--   M5 ← drop the in-body `set search_path` from delete_my_account_tx → 98 H1
--
--   ✔ MUTATION-PROVEN, 2026-08-20, full harness by absolute path in this worktree.
--     **Baseline before 0115 = 666/0. Green with 0115 + this suite = 693/0** (+27 pins).
--       M1  `addresses` back into ④                → **686/7, red = [N6-1, N4, N4-a, N7, N8,
--           P1, P2]**. N6-1 names the path statically (`addresses > gate_code_access_log`); the
--           other six die on `23503 bookings_address_id_fkey` — i.e. F2's abort happens FIRST and
--           MASKS F1's destruction at runtime, which is exactly why the static arm has to exist.
--       M2  `club_custody` token deleted            → **691/2, red = [N2-b, N2-set]**. N2-b's
--           detail line is the review's own finding verbatim: *"지금 남의 개를 맡고 있는 러너가
--           삭제됐다"*.
--       M3  fake `ledger_items.x → profiles on delete cascade` in a later migration
--                                                   → **692/1, red = [N6-2]**, naming the
--           constraint. Note it does NOT redden N6-1, and that is correct: nothing deletes
--           `profiles`, so the closure cannot see it — which is the entire reason arm 2 exists.
--       M4  the view's `p.deleted_at is null` removed → **692/1, red = [N5]**.
--           ⚠⚠ **M4 FIRST SCORED 693/0 — THE PIN WAS GREEN WITH THE FIX DELETED**, the same
--           failure 147's header records. ③ sets `online = false` as BELT, so the view was
--           excluding the tombstone through `where r.online` and never consulting `deleted_at`
--           at all. Fixed by putting `online` back to true after the tombstone (see N5(b)) —
--           which is not a contrivance, it is the precise scenario the contract's "a tombstone
--           must not depend on a mutable boolean the runner-side code also writes" describes.
--           **A belt that is checked first makes the braces untestable.**
--       M5  in-body `set search_path` dropped        → **692/1, red = [98 H1]** — the schema-wide
--           definer sweep, not a pin in this file, which is the correct owner.
--     Restore → 693/0.
--
--   ✔ AND ONE MUTATION THAT CONFIRMS THE CONTRACT'S FORWARD-LOOKING CLAIM RATHER THAN MY CODE.
--     §B.3 says the unbuilt 위치정보 ledger is caught only if THREE things all hold. Measured:
--       M3b  `create table location_access_log (address_id … on delete cascade)` alone
--                                                   → **693/0, GREEN — and correctly so**:
--            `addresses` is KEEP+ANON, so nothing deletes that ledger.
--       M3c  the same table PLUS M1                  → **686/7**, and N6-1 names BOTH
--            `gate_code_access_log (addresses > gate_code_access_log)` AND
--            `location_access_log (addresses > location_access_log)`.
--     So the wildcard, the recursion, and `addresses` being reachable from the delete list are
--     load-bearing TOGETHER and none of the three may be simplified away. A table that does not
--     exist yet was caught by a pin written before it.

set client_min_messages = warning;

-- ═══ fixtures ══════════════════════════════════════════════════════════════════════════════
-- A user rich enough that the count diff MEANS something: booking + run (settled) + chat +
-- review + address + gate_code_access_log against that address + dog + session_dogs +
-- payment_attempts through it + push token + feed post + miles + an unopened drop.
create or replace function t_acd_rich(p_tag text, out o uuid, out r uuid, out d uuid,
                                      out v_addr uuid, out bk uuid, out sd uuid)
language plpgsql as $$
declare v_rt uuid; v_club uuid; v_sess uuid; v_thread uuid;
begin
  o := t_user('acd_' || p_tag || '_o', 'owner');
  r := t_user('acd_' || p_tag || '_r', 'runner');
  d := t_dog(o, '나비');
  v_rt := t_route('acd 코스 ' || p_tag);

  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng, is_default)
  values (o, '집', '서울 서초구 반포동 1', '101호', 'GATE-ENC-XYZ', 37.5045, 127.0114, true)
  returning id into v_addr;
  -- the audit log row whose destruction F1 measured (1 row → 0) when `addresses` was DELETEd
  insert into gate_code_access_log (address_id, runner_id) values (v_addr, r);

  -- a completed + settled booking: 전자상거래법 record, must survive byte-identical
  bk := t_active_booking(o, r, d, v_rt, now() - interval '2 days');
  update bookings set address_id = v_addr where id = bk;
  perform t_settle(bk, 'dog_condition');

  -- chat on that booking (KEEP+ANON: the author pointer stays, the body is NOT nulled)
  insert into chat_threads (booking_id) values (bk) returning id into v_thread;
  insert into chat_messages (thread_id, sender_id, body, kind)
  values (v_thread, o, '안녕하세요 잘 부탁드려요', 'text');

  -- a review the owner authored about the runner — the rating belongs to its SUBJECT
  insert into reviews (booking_id, author_id, target_kind, target_id, rating, tags, note, visibility)
  values (bk, o, 'runner', r, 5, '{친절}', '좋았어요', 'public');

  -- club session_dogs → payment_attempts: the money path the cascade used to reach
  insert into clubs (name, district, host_profile_id) values ('acd 클럽 ' || p_tag, '반포동', r)
    returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
  values (v_club, r, now() - interval '3 days', '반포 집결지', 'done') returning id into v_sess;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                            custody, checked_in_at, checked_out_at)
  values (v_sess, d, o, o, 'owner_handled', now() - interval '3 days', now() - interval '3 days')
    returning id into sd;
  insert into payment_attempts (session_dog_id, booking_id, kind, idempotency_key, result)
  values (sd, bk, 'charge', 'acd-' || p_tag, 'ok');

  -- deletable surface
  insert into push_tokens (profile_id, token) values (o, 'expo-tok-' || p_tag);
  insert into feed_posts (author_id, booking_id, body) values (o, bk, '오늘의 러닝');
  insert into miles_ledger (profile_id, delta, reason) values (o, 700, 'welcome');
  insert into drops (runner_id, kind, run_count_at, contents)
  values (r, 'mini', 1, '{"miles": 100}'::jsonb);
  -- storage objects: the RPC must not touch a single one (the sweep is the edge function's job)
  insert into storage.objects (bucket_id, name) values ('avatars', o::text || '/avatar.jpg');
  insert into storage.objects (bucket_id, name) values ('media', o::text || '/dogs/' || d::text || '.jpg');
  insert into storage.objects (bucket_id, name) values ('media', o::text || '/chat/x/1.jpg');
end $$;

-- A booking in an arbitrary status. Default `completed` — a status the state gate does NOT
-- refuse — so one arm can be isolated from the others (an `active` booking trips active_booking
-- first, and the gate is ordered).
-- ⚠ INSERTED at the target status, never UPDATEd into it: `enforce_booking_transition` (0002's
-- BEFORE UPDATE OF status trigger) refuses `completed -> draft` and most other jumps, so the
-- eleven-status loop cannot be written as an update.
create or replace function t_acd_parked(p_owner uuid, p_runner uuid, p_dog uuid,
                                        p_status booking_status default 'completed') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_status, now() - interval '1 day', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  return v;
end $$;

-- refuse-token probe: returns the raised token, or '' when the deletion succeeded
create or replace function t_acd_try(p_uid uuid) returns text
language plpgsql as $$
begin
  perform delete_my_account_tx(p_uid);
  return '';
exception when others then
  return sqlerrm;
end $$;

do $$
declare
  v_bad text; v_msg text; v_n int; v_n2 int; v_tok text; v_txt text;
  o uuid; r uuid; d uuid; v_addr uuid; bk uuid; bk2 uuid; sd uuid;
  u uuid; u2 uuid; cp uuid; cl uuid; cs uuid; th uuid; res jsonb;
  v_before jsonb; v_after jsonb; v_diff text; v_roots text[]; v_expected jsonb;
  v_statuses text[] := array['draft','quoted','payment_hold','matching','runner_pending',
    'confirmed','runner_enroute','picked_up','active','incident_review','refund_pending'];
  v_tokens text[] := array['active_booking','active_run','unsettled_run','unsettled_payment',
    'unpaid_payout','km_balance','open_incident','active_recurring','club_host_duty',
    'club_custody','club_assignment'];
begin

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N1 — the uid is a PARAMETER, and no client can reach the function to name a victim.
-- The edge function takes the uid from the JWT and never from the body (Deno test 1); on the
-- SQL side the wall is the missing EXECUTE grant, executed rather than read off a catalog.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_n1_a', 'owner');
  u := t_user('acd_n1_b', 'owner');
  select count(*) into v_n from pg_proc where proname = 'delete_my_account_tx'
     and pronargs = 1 and proargtypes[0] = 'uuid'::regtype;
  if v_n <> 1 then v_bad := v_bad || ' 함수 시그니처가 (uuid) 하나가 아니다 — 본문 override 여지'; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', o::text, true);
  begin
    execute format('select delete_my_account_tx(%L)', u);
    v_bad := v_bad || ' A가 B의 계정을 지웠다 — authenticated가 EXECUTE를 들고 있다';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' 권한이 아닌 다른 이유로 막혔다: ' || sqlerrm; end;
  execute 'reset role';
  if v_bad = '' then
    call _pass('acd','N1 A는 B를 지울 수 없다 — 함수는 (p_uid uuid) 하나뿐이고 authenticated는 EXECUTE가 없다 (uid는 엣지 함수의 JWT에서만 온다)');
  else call _fail('acd','N1 A는 B를 지울 수 없다', v_bad); end if;
exception when others then execute 'reset role'; call _fail('acd','N1 A는 B를 지울 수 없다', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N2 — ELEVEN state-gate arms, not nine. Every refusal is a state the user can clear.
-- ══════════════════════════════════════════════════════════════════════════════════════════

-- N2-1 active_booking, each of the eleven live statuses
begin
  v_bad := '';
  foreach v_txt in array v_statuses loop
    o := t_user('acd_ab_' || v_txt, 'owner');
    r := t_user('acd_abr_' || v_txt, 'runner');
    d := t_dog(o, '초코');
    bk := t_acd_parked(o, r, d, v_txt::booking_status);
    v_tok := t_acd_try(o);
    if v_tok <> 'active_booking' then
      v_bad := v_bad || ' [' || v_txt || '→' || coalesce(nullif(v_tok,''),'삭제됨') || ']'; end if;
  end loop;
  if v_bad = '' then
    call _pass('acd','N2-1 active_booking — 살아 있는 11개 상태 전부에서 거절 (양측: owner_id·runner_id)');
  else call _fail('acd','N2-1 active_booking 11개 상태', v_bad); end if;
exception when others then call _fail('acd','N2-1 active_booking 11개 상태', sqlerrm);
end;

-- N2-2 active_run / N2-3 unsettled_run — isolated on a PARKED booking so the arm under test is
-- the only one that can fire (an `active` booking would trip active_booking first).
begin
  v_bad := '';
  o := t_user('acd_ar_o', 'owner'); r := t_user('acd_ar_r', 'runner'); d := t_dog(o, '초코');
  bk := t_acd_parked(o, r, d);
  insert into runs (booking_id, started_at) values (bk, now() - interval '1 hour');
  v_tok := t_acd_try(o);
  if v_tok <> 'active_run' then v_bad := v_bad || ' active_run 대신 ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update runs set ended_at = now() where booking_id = bk;
  v_tok := t_acd_try(o);
  if v_tok <> 'unsettled_run' then v_bad := v_bad || ' / unsettled_run 대신 ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update runs set settled_at = now() where booking_id = bk;
  v_tok := t_acd_try(o);
  if v_tok <> '' then v_bad := v_bad || ' / 정산 뒤에도 거절: ' || v_tok; end if;
  if v_bad = '' then
    call _pass('acd','N2-2/3 active_run · unsettled_run — 끝나지 않은 러닝과 정산 안 된 러닝이 각각 거절, 정산되면 통과');
  else call _fail('acd','N2-2/3 active_run · unsettled_run', v_bad); end if;
exception when others then call _fail('acd','N2-2/3 active_run · unsettled_run', sqlerrm);
end;

-- N2-4 unsettled_payment
begin
  v_bad := '';
  o := t_user('acd_up_o', 'owner'); r := t_user('acd_up_r', 'runner'); d := t_dog(o, '초코');
  bk := t_acd_parked(o, r, d);
  insert into payments (booking_id, order_id, amount, status) values (bk, 'acd-up', 24900, 'pending');
  v_tok := t_acd_try(o);
  if v_tok <> 'unsettled_payment' then v_bad := ' ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update payments set status = 'confirmed', payment_key = 'pk' where booking_id = bk;
  v_tok := t_acd_try(o);
  if v_tok <> '' then v_bad := v_bad || ' / confirmed 뒤에도 거절: ' || v_tok; end if;
  if v_bad = '' then
    call _pass('acd','N2-4 unsettled_payment — 종결되지 않은 결제는 거절 (터미널 집합의 여집합으로 작성 — 새 status는 기본이 거절)');
  else call _fail('acd','N2-4 unsettled_payment', v_bad); end if;
exception when others then call _fail('acd','N2-4 unsettled_payment', sqlerrm);
end;

-- N2-5 unpaid_payout — and it is what gates `bank_accounts` deletion in ④
begin
  v_bad := '';
  r := t_user('acd_po_r', 'runner');
  insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net)
  values (r, current_date - 7, current_date, 100000, 3300, 96700);
  insert into bank_accounts (runner_id, bank, account_enc, holder)
  values (r, '카카오뱅크', 'ENC-ACCOUNT', '홍길동');
  v_tok := t_acd_try(r);
  if v_tok <> 'unpaid_payout' then v_bad := ' ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  if exists (select 1 from bank_accounts where runner_id = r) then null;
    else v_bad := v_bad || ' / 거절했는데 bank_accounts가 이미 지워졌다 — ④가 게이트보다 먼저 돌았다'; end if;
  update payouts set paid_at = now(), status = 'paid' where runner_id = r;
  v_tok := t_acd_try(r);
  if v_tok <> '' then v_bad := v_bad || ' / 지급 뒤에도 거절: ' || v_tok; end if;
  if exists (select 1 from bank_accounts where runner_id = r) then
    v_bad := v_bad || ' / 🔴 bank_accounts가 살아남았다 — account_enc가 전 절차를 통과한 F9 그대로'; end if;
  if v_bad = '' then
    call _pass('acd','N2-5 unpaid_payout — 미지급 정산이 있으면 거절하고 bank_accounts는 그대로, 지급 뒤에야 계정과 함께 삭제 (F9 순서)');
  else call _fail('acd','N2-5 unpaid_payout', v_bad); end if;
exception when others then call _fail('acd','N2-5 unpaid_payout', sqlerrm);
end;

-- N2-6 km_balance — the replacement for the RESTRICT 0115 §A removed
begin
  v_bad := '';
  o := t_user('acd_km_o', 'owner');
  insert into km_lots (profile_id, bucket, source, km_total, km_remaining, won_paid)
  values (o, 'paid', 'purchase', 20, 12.5, 30000);
  v_tok := t_acd_try(o);
  if v_tok <> 'km_balance' then v_bad := ' ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update km_lots set km_remaining = 0 where profile_id = o;
  v_tok := t_acd_try(o);
  if v_tok <> '' then v_bad := v_bad || ' / 소진 뒤에도 거절: ' || v_tok; end if;
  -- and the row itself is KEPT — the ledger survives the account
  if not exists (select 1 from km_lots where profile_id = o) then
    v_bad := v_bad || ' / km_lots 행이 사라졌다 — 원장은 보존이다'; end if;
  if v_bad = '' then
    call _pass('acd','N2-6 km_balance — 0075:105의 close-out 게이트가 RESTRICT에서 토큰으로 이전 (잔액>0 거절 · 0이면 통과 · 로트 행은 보존)');
  else call _fail('acd','N2-6 km_balance', v_bad); end if;
exception when others then call _fail('acd','N2-6 km_balance', sqlerrm);
end;

-- N2-7 open_incident — both families
begin
  v_bad := '';
  o := t_user('acd_inc_o', 'owner'); r := t_user('acd_inc_r', 'runner'); d := t_dog(o, '초코');
  bk := t_acd_parked(o, r, d);
  insert into incidents (booking_id, reporter_id, kind) values (bk, o, 'other');
  v_tok := t_acd_try(o);
  if v_tok <> 'open_incident' then v_bad := ' incidents: ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update incidents set resolved_at = now() where booking_id = bk;
  v_tok := t_acd_try(o);
  if v_tok <> '' then v_bad := v_bad || ' / 해결 뒤에도 거절: ' || v_tok; end if;
  -- club side
  u := t_user('acd_inc_h', 'runner');
  insert into clubs (name, district, host_profile_id) values ('acd 사고 클럽', '반포동', u) returning id into cl;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
  values (cl, u, now() - interval '2 days', '집결지', 'done') returning id into cs;
  u2 := t_user('acd_inc_op', 'owner');
  insert into club_incidents (session_id, severity, opened_by, case_owner, summary)
  values (cs, 'S2', u2, u2, '요약');
  v_tok := t_acd_try(u2);
  if v_tok <> 'open_incident' then v_bad := v_bad || ' / club_incidents: ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  if v_bad = '' then
    call _pass('acd','N2-7 open_incident — incidents(신고자·예약 당사자)와 club_incidents(opened_by·case_owner) 양쪽 미해결이 거절');
  else call _fail('acd','N2-7 open_incident', v_bad); end if;
exception when others then call _fail('acd','N2-7 open_incident', sqlerrm);
end;

-- N2-a (F13) active_recurring — PAUSE is the remedy, because delete is not a verb the client
-- holds (0111:192 revoked client delete, 0111:193 granted `update (paused)` only).
begin
  v_bad := '';
  o := t_user('acd_rec_o', 'owner'); d := t_dog(o, '초코');
  insert into recurring_series (owner_id, rule, dog_id, paused) values (o, '{}'::jsonb, d, false);
  v_tok := t_acd_try(o);
  if v_tok <> 'active_recurring' then v_bad := ' ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update recurring_series set paused = true where owner_id = o;
  v_tok := t_acd_try(o);
  if v_tok <> '' then v_bad := v_bad || ' / 일시정지 뒤에도 거절: ' || v_tok; end if;
  if not exists (select 1 from recurring_series where owner_id = o) then
    v_bad := v_bad || ' / 정기 러닝 행이 삭제됐다 — F13: 이 행은 KEEP이다'; end if;
  if v_bad = '' then
    call _pass('acd','N2-a active_recurring (F13) — paused=false가 곧 "켜져 있음"이고 일시정지가 remedy, 행은 KEPT (0111:193이 유일한 동사)');
  else call _fail('acd','N2-a active_recurring (F13)', v_bad); end if;
exception when others then call _fail('acd','N2-a active_recurring (F13)', sqlerrm);
end;

-- N2-d (F3) club_host_duty — THREE separate arms, because a single-column implementation
-- passes a single-column pin.
begin
  v_bad := '';
  foreach v_txt in array array['host_profile_id','backup_host_profile_id','original_host_profile_id'] loop
    u := t_user('acd_hd_' || left(v_txt, 6), 'runner');
    u2 := t_user('acd_hdx_' || left(v_txt, 6), 'runner');
    insert into clubs (name, district, host_profile_id) values ('acd 호스트 ' || v_txt, '반포동', u2)
      returning id into cl;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
    values (cl, u2, now() + interval '3 days', '집결지', 'open') returning id into cs;
    execute format('update club_sessions set %I = %L where id = %L', v_txt, u, cs);
    v_tok := t_acd_try(u);
    if v_tok <> 'club_host_duty' then
      v_bad := v_bad || ' [' || v_txt || '→' || coalesce(nullif(v_tok,''),'삭제됨') || ']'; end if;
    update club_sessions set status = 'cancelled' where id = cs;
    v_tok := t_acd_try(u);
    if v_tok <> '' then v_bad := v_bad || ' [' || v_txt || ' 종료 뒤에도 거절: ' || v_tok || ']'; end if;
  end loop;
  if v_bad = '' then
    call _pass('acd','N2-d club_host_duty (F3) — host·backup_host·original_host 세 컬럼 각각이 살아 있는 세션에서 거절 (백업 호스트는 세션이 기대고 있는 사람, 원 호스트는 에스컬레이션의 낙하지점)');
  else call _fail('acd','N2-d club_host_duty (F3) 세 컬럼', v_bad); end if;
exception when others then call _fail('acd','N2-d club_host_duty (F3) 세 컬럼', sqlerrm);
end;

-- N2-b (F3) 🔴 club_custody — THE ARM THE REVIEW WAS BOUGHT WITH.
-- The reviewer seeded a runner HOLDING ANOTHER OWNER'S DOG AT THAT MOMENT and ran the nine-token
-- gate: ALL NINE PASSED. The account deleted while the dog was out, and the responsible party
-- for a live dog became a tombstone with no push token and no phone. The club path has custody
-- WITHOUT a bookings row (session_dogs.booking_id is nullable, 0030:86 "위탁견만"), so nothing
-- in the booking family could ever have caught it.
begin
  v_bad := '';
  o := t_user('acd_cust_o', 'owner');      -- some OTHER owner
  r := t_user('acd_cust_r', 'runner');     -- the departing runner, holding that owner's dog
  d := t_dog(o, '보리');
  u2 := t_user('acd_cust_h', 'runner');
  insert into clubs (name, district, host_profile_id) values ('acd 인계 클럽', '반포동', u2) returning id into cl;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status, format,
                             delegated_dog_capacity)
  values (cl, u2, now() - interval '1 hour', '집결지', 'open', 'delegated_only', 3) returning id into cs;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                            custody, checked_in_at, checked_out_at)
  values (cs, d, o, r, 'runner_delegated', now() - interval '30 minutes', null) returning id into sd;
  -- the session is not the thing holding it: the runner has no host duty and no assignment here
  v_tok := t_acd_try(r);
  if v_tok <> 'club_custody' then
    v_bad := ' 🔴 지금 남의 개를 맡고 있는 러너가 ' || coalesce(nullif(v_tok,''),'삭제됐다') || ' — F3 그대로 재현'; end if;
  -- The other two columns of the same arm. ⚠ MEASURED FACT worth recording rather than working
  -- around silently: `custodian_profile_id` and `current_runner_profile_id` are DERIVED — the
  -- `club_v1_axes_sync` BEFORE INSERT OR UPDATE trigger overwrites both from
  -- `_club_compute_axes(new)` on every write, so they cannot be set independently through the
  -- normal path (a plain update setting custodian = r came back with custodian = responsible,
  -- measured). The gate reads all three anyway, and it must: the derivation is one function that
  -- can change, and the day `current_runner` legitimately differs from `responsible` — a
  -- mid-session transfer — is exactly the day a dog is in the least accounted-for state. So the
  -- values are PLANTED with the derivation trigger off, which is establishing the DATA the gate
  -- reads, never the property under test.
  execute 'alter table session_dogs disable trigger club_v1_axes_sync';
  update session_dogs set responsible_profile_id = o, custodian_profile_id = r,
                          current_runner_profile_id = null where id = sd;
  execute 'alter table session_dogs enable trigger club_v1_axes_sync';
  v_tok := t_acd_try(r);
  if v_tok <> 'club_custody' then v_bad := v_bad || ' / custodian_profile_id 미감지: ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  execute 'alter table session_dogs disable trigger club_v1_axes_sync';
  update session_dogs set custodian_profile_id = null, current_runner_profile_id = r where id = sd;
  execute 'alter table session_dogs enable trigger club_v1_axes_sync';
  v_tok := t_acd_try(r);
  if v_tok <> 'club_custody' then v_bad := v_bad || ' / current_runner_profile_id 미감지: ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  -- mutation-verify the remedy: check the dog out and the deletion proceeds
  update session_dogs set checked_out_at = now() where id = sd;
  v_tok := t_acd_try(r);
  if v_tok <> '' then v_bad := v_bad || ' / 인계를 마쳤는데도 거절: ' || v_tok; end if;
  if not exists (select 1 from session_dogs where id = sd) then
    v_bad := v_bad || ' / session_dogs가 사라졌다 — 커스터디 증거는 KEEP이다'; end if;
  if v_bad = '' then
    call _pass('acd','N2-b club_custody (F3) 🔴 — 지금 개를 맡고 있는 사람은 못 나간다: responsible·custodian·current_runner 세 컬럼 각각, checked_out_at is null. 인계를 마치면 통과하고 session_dogs 행은 증거로 남는다');
  else call _fail('acd','N2-b club_custody (F3)', v_bad); end if;
exception when others then call _fail('acd','N2-b club_custody (F3)', sqlerrm);
end;

-- N2-c (F3) club_assignment — committed on a FUTURE session refuses; withdrawn, or a past
-- session, does not.
begin
  v_bad := '';
  r := t_user('acd_asg_r', 'runner'); u2 := t_user('acd_asg_h', 'runner');
  insert into clubs (name, district, host_profile_id) values ('acd 배정 클럽', '반포동', u2) returning id into cl;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
  values (cl, u2, now() + interval '4 days', '집결지', 'open') returning id into cs;
  insert into session_runner_assignments (session_id, runner_profile_id, status)
  values (cs, r, 'committed');
  v_tok := t_acd_try(r);
  if v_tok <> 'club_assignment' then v_bad := ' ' || coalesce(nullif(v_tok,''),'삭제됨'); end if;
  update session_runner_assignments set status = 'withdrawn' where session_id = cs and runner_profile_id = r;
  v_tok := t_acd_try(r);
  if v_tok <> '' then v_bad := v_bad || ' / 철회 뒤에도 거절: ' || v_tok; end if;
  -- past session, committed → must NOT refuse
  r := t_user('acd_asg_r2', 'runner');
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
  values (cl, u2, now() - interval '4 days', '집결지', 'open') returning id into cs;
  insert into session_runner_assignments (session_id, runner_profile_id, status)
  values (cs, r, 'committed');
  v_tok := t_acd_try(r);
  if v_tok <> '' then v_bad := v_bad || ' / 지난 세션의 확정 배정이 거절했다: ' || v_tok; end if;
  if v_bad = '' then
    call _pass('acd','N2-c club_assignment (F3) — 앞으로의 세션에 확정(committed) 배정이면 거절, 철회하거나 지난 세션이면 통과');
  else call _fail('acd','N2-c club_assignment (F3)', v_bad); end if;
exception when others then call _fail('acd','N2-c club_assignment (F3)', sqlerrm);
end;

-- N2-e (F11) 🔵 THE NEGATIVE THAT GUARDS A DECISION RATHER THAN A BUG.
-- There is NO `miles_balance` token and none should be added. 하이 포인트 is a non-transferable
-- promotional balance with no cash-out path, so forfeiting it creates no 잔여 재산 to settle and
-- no 환급 duty — the disclosure in the confirm sheet IS the protection. `km_balance` keeps its
-- gate for the opposite reason and the difference is one column: km_lots.won_paid is real ₩ the
-- customer handed us. Miles are issued BY us FOR free; km is bought FROM us WITH cash.
begin
  v_bad := '';
  -- ⚠ a runner, not an owner: drops.runner_id references `runners`, not `profiles`
  o := t_user('acd_miles_o', 'runner');
  insert into miles_ledger (profile_id, delta, reason) values (o, 3200, 'welcome');
  insert into drops (runner_id, kind, run_count_at, contents, opened_at)
  values (o, 'mini', 1, '{"miles": 100}'::jsonb, null);           -- unopened → forfeit
  insert into drops (runner_id, kind, run_count_at, contents, opened_at)
  values (o, 'mini', 2, '{"miles": 50}'::jsonb, now());           -- opened → KEPT
  res := delete_my_account_tx(o);
  if not (res->>'ok')::boolean then v_bad := ' 마일리지 잔액이 삭제를 막았다'; end if;
  if (res#>>'{forfeited,miles}')::int <> 3200 then
    v_bad := v_bad || ' / forfeited_miles=' || coalesce(res#>>'{forfeited,miles}','∅') || ' (기대 3200)'; end if;
  if (res#>>'{forfeited,drops}')::int <> 1 then
    v_bad := v_bad || ' / forfeited_drops=' || coalesce(res#>>'{forfeited,drops}','∅') || ' (기대 1 — 미개봉만)'; end if;
  select count(*) into v_n from drops where runner_id = o;
  if v_n <> 1 then v_bad := v_bad || ' / 개봉된 드랍이 남지 않았다 (rows=' || v_n || ') — contents가 miles_ledger 적립의 설명이다'; end if;
  if not exists (select 1 from miles_ledger where profile_id = o) then
    v_bad := v_bad || ' / miles_ledger가 지워졌다 — 소멸은 잔액에 대한 사실이지 원장을 지울 면허가 아니다'; end if;
  -- ⚠ comments stripped, same lesson as N6-1: the function's own header SAYS "there is no
  -- miles_balance token", and a pin that reads prose as behaviour is a pin you can argue with by
  -- writing a comment. Match the raise, not the word.
  if regexp_replace((select prosrc from pg_proc where proname = 'delete_my_account_tx'),
                    '--[^' || chr(10) || ']*', '', 'g') ~ 'raise exception ''miles_balance''' then
    v_bad := v_bad || ' / 🔵 miles_balance 토큰이 생겼다 — F11의 비대칭(§C.1.b ②)과 먼저 논쟁할 것'; end if;
  if v_bad = '' then
    call _pass('acd','N2-e 마일리지 소멸 (F11 🔵) — miles_balance 토큰은 없고 잔액이 있어도 삭제된다. 미개봉 드랍만 소멸·개봉 드랍과 원장은 보존·소멸량은 로그에 기록');
  else call _fail('acd','N2-e 마일리지 소멸 (F11 🔵)', v_bad); end if;
exception when others then call _fail('acd','N2-e 마일리지 소멸 (F11 🔵)', sqlerrm);
end;

-- N2-set — the token set in the SQL is exactly eleven, and they are the eleven the client must
-- carry copy for. A token with no copy is a dead-end refusal and an Apple rejection risk (§B.1);
-- a copy entry with no token is a lie. ui2 owns the other half of this equality.
begin
  v_bad := '';
  select prosrc into v_txt from pg_proc where proname = 'delete_my_account_tx';
  foreach v_tok in array v_tokens loop
    if position('raise exception ''' || v_tok || '''' in v_txt) = 0 then
      v_bad := v_bad || ' 누락:' || v_tok; end if;
  end loop;
  select count(*) into v_n from (
    select (regexp_matches(v_txt, 'raise exception ''([a-z_]+)''', 'g'))[1] as t) s
   where t <> 'not_authenticated';
  if v_n <> 11 then v_bad := v_bad || ' / raise 토큰 수=' || v_n || ' (기대 11 + not_authenticated)'; end if;
  if v_bad = '' then
    call _pass('acd','N2-set 상태 게이트는 정확히 11개 토큰 — 클라이언트 카피 11줄과 같은 집합 (토큰 하나가 늘거나 줄면 여기서 터진다)');
  else call _fail('acd','N2-set 11개 토큰 집합', v_bad); end if;
exception when others then call _fail('acd','N2-set 11개 토큰 집합', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N3 — anon and authenticated are both refused at the function itself (the edge function's 401
-- is the other arm, pinned in Deno). §A.5's lesson: a read path can be closed by something
-- other than the wall you are looking at, so both are executed.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_n3_o', 'owner');
  foreach v_txt in array array['anon','authenticated'] loop
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role ' || v_txt;
    if current_user <> v_txt then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001'; end if;
    begin
      execute format('select delete_my_account_tx(%L)', o);
      v_bad := v_bad || ' ' || v_txt || '이 함수를 실행했다';
    exception when insufficient_privilege then null;
      when others then v_bad := v_bad || ' ' || v_txt || ': 권한이 아닌 이유로 막혔다 — ' || sqlerrm; end;
    execute 'reset role';
  end loop;
  if v_bad = '' then
    call _pass('acd','N3 anon·authenticated 둘 다 함수에서 42501 — EXECUTE는 service_role만 (uid가 파라미터이므로 클라가 들면 피해자를 지목할 수 있다)');
  else call _fail('acd','N3 anon·authenticated 거절', v_bad); end if;
exception when others then execute 'reset role'; call _fail('acd','N3 anon·authenticated 거절', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N4 (F12) — no definer breaks on a tombstone. EXECUTED, not read. The first draft's list was
-- wrong in two ways: it said "the four _owner_la_* triggers" and there are THREE, and it omitted
-- `notify_chat_message` entirely.
-- ⚠ WHAT COUNTS AS A FAILURE HERE, stated because it is easy to get backwards: a `P0001` raise is
-- a BUSINESS refusal (`not_signed_in`, `not_owner`, `not_found`) — these functions are party- and
-- state-gated, and refusing is them working. What this pin hunts is every OTHER sqlstate: a null
-- concat, an undefined column, a lookup that assumed a live profile — the ways a definer breaks
-- when the profile it joins has become a tombstone. So P0001 is accepted and anything else is a
-- failure, reported WITH its sqlstate so a real defect is never mistaken for a gate.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('n4') f;
  cp := r;                                  -- the counterparty who keeps writing
  select id into th from chat_threads where booking_id = bk;   -- t_acd_rich already opened it
  perform delete_my_account_tx(o);          -- tombstone the owner
  -- a booking the tombstone owns, parked where a legal transition exists, for the LA triggers.
  -- ⚠ Seeded AFTER the tombstone on purpose: `confirmed` is one of the eleven gate statuses, so
  -- seeding it first would (correctly) refuse the deletion on `active_booking`. What the LA
  -- triggers have to survive is a booking whose OWNER ROW IS ALREADY A TOMBSTONE, which is
  -- exactly what this is.
  bk2 := t_acd_parked(o, r, d, 'confirmed');
  perform set_config('request.jwt.claim.sub', r::text, true);   -- a live counterparty is calling

  begin perform _club_delegation_board_impl(gen_random_uuid(), 'host'); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' _club_delegation_board_impl[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform club_demand_board(); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' club_demand_board[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform club_overview('반포동'); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' club_overview[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform club_session_detail(gen_random_uuid()); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' club_session_detail[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform club_session_roster(gen_random_uuid()); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' club_session_roster[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform * from incident_contact(bk); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' incident_contact[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform * from leaderboard_runners_weekly(); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' leaderboard_runners_weekly[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform * from runners_available_for(bk); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' runners_available_for[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform owner_la_sweep_stale(); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' owner_la_sweep_stale[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform session_propose_dog(sd, r); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' session_propose_dog[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform session_proposal_respond(sd, false, 'no'); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' session_proposal_respond[' || sqlstate || ']:' || sqlerrm; end if; end;
  begin perform runner_app_approve(gen_random_uuid(), 'ops', 'note'); exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' runner_app_approve[' || sqlstate || ']:' || sqlerrm; end if; end;
  -- set_my_handle AS THE TOMBSTONE: it must not break. Whether it succeeds is not this pin's
  -- business (a tombstone has no session to call it from — the JWT is gone with auth.users);
  -- that it does not raise a null-concat on a nulled handle is.
  begin
    perform set_config('request.jwt.claim.sub', o::text, true);
    perform set_my_handle('acd_tomb_handle');
  exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' set_my_handle[' || sqlstate || ']:' || sqlerrm; end if; end;
  perform set_config('request.jwt.claim.sub', '', true);
  -- the THREE _owner_la_* triggers, reached through their triggering writes on a booking whose
  -- owner is now a tombstone (confirmed → cancelled_owner is in the transition map)
  begin
    update bookings set status = 'cancelled_owner' where id = bk2;      -- _owner_la_booking_tg
    update bookings set run_ended_at = now() where id = bk2;            -- _owner_la_run_end_tg
    update runs set trace = '[]'::jsonb where booking_id = bk;          -- _owner_la_trace_tg
  exception when others then v_bad := v_bad || ' _owner_la_*_tg[' || sqlstate || ']:' || sqlerrm; end;
  if v_bad = '' then
    call _pass('acd','N4 툼스톤 위에서 definer 17종 전부 실행 — 아무것도 raise하지 않고 null-name 쓰레기도 없다 (F12: _owner_la_* 는 넷이 아니라 셋)');
  else call _fail('acd','N4 definer 17종 툼스톤 내성', left(v_bad, 400)); end if;
exception when others then call _fail('acd','N4 definer 17종 툼스톤 내성', sqlerrm);
end;

-- N4-a (F12) — notify_chat_message gets its own arm AND its own assertion. It is reachable
-- AFTER deletion because the tombstone's thread stays open and the counterparty keeps writing
-- into it. profiles.name is NOT NULL and is set to '탈퇴한 사용자', so the coalesce never fires
-- and the correct push is exactly "탈퇴한 사용자님이 메시지를 보냈어요". Pinning the string is
-- what stops a future "null the name" refactor from producing '상대방님이…' or a null-concat.
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('n4a') f;
  select id into th from chat_threads where booking_id = bk;
  perform delete_my_account_tx(o);
  delete from notifications where profile_id = r and title = '새 메시지';
  insert into chat_messages (thread_id, sender_id, body, kind) values (th, o, '마지막 인사', 'text');
  select body into v_txt from notifications
   where profile_id = r and title = '새 메시지' order by created_at desc limit 1;
  if coalesce(v_txt, '') <> '탈퇴한 사용자님이 메시지를 보냈어요' then
    v_bad := ' body=' || coalesce(v_txt, '∅'); end if;
  if v_bad = '' then
    call _pass('acd','N4-a notify_chat_message — 툼스톤이 보낸 메시지의 푸시는 정확히 "탈퇴한 사용자님이 메시지를 보냈어요" (name이 NOT NULL이라 coalesce가 절대 안 탄다 — 구조로 우아하게 망가지지, 운으로가 아니다)');
  else call _fail('acd','N4-a notify_chat_message 푸시 문구', v_bad); end if;
exception when others then call _fail('acd','N4-a notify_chat_message 푸시 문구', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N5 (F7/F8) — the counterparty is unharmed, and the tombstone is VISIBLE-BUT-REDACTED.
-- Four arms, because the reviewer's execution showed the first draft failed two of them in
-- OPPOSITE directions: the storefront still listed the tombstoned runner (a definer view never
-- consults RLS — 0112 §0b), and the naive policy fix made a kept review's author invisible.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('n5') f;
  update runners set online = true, tier = 'certified' where profile_id = r;
  cp := t_user('acd_n5_cp', 'owner');       -- the counterparty who must still see things
  perform delete_my_account_tx(r);          -- tombstone the RUNNER

  -- (a) chat still renders for the other party, body intact
  select count(*) into v_n from chat_messages m join chat_threads t on t.id = m.thread_id
   where t.booking_id = bk and m.body is not null;
  if v_n < 1 then v_bad := v_bad || ' (a) 스레드가 비었다 — 본문은 지우지 않는다'; end if;

  -- (b) the storefront does NOT list the tombstone. Pinned AT THE VIEW: a pin written against
  --     `profiles public runner read` would be GREEN ON A LEAKING IMPLEMENTATION, because a
  --     definer view never consults RLS (0112 §0b).
  --     🔴 `online` IS PUT BACK TO TRUE FIRST, AND THAT LINE IS THE WHOLE PIN. ③ sets
  --     `online = false` as BELT, so with it left alone the view excludes this runner through
  --     `where r.online` and `deleted_at is null` is never consulted — MEASURED: mutation M4
  --     (delete the view's `deleted_at` clause) scored 693/0, i.e. **the pin was green with the
  --     fix removed**, the exact failure 147's header describes. Forcing `online` back to true
  --     is not artificial: the contract's reason for keeping `deleted_at` as the mechanism is
  --     precisely that `online` is "a mutable boolean the runner-side code also writes", and
  --     runner-side code writing it is what this line simulates. With it, `deleted_at` is the
  --     only thing that can hide the tombstone, so the pin measures the migration.
  update runners set online = true where profile_id = r;
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', cp::text, true);
  execute format('select count(*) from available_runners where profile_id = %L', r) into v_n;
  if v_n <> 0 then v_bad := v_bad || ' (b) available_runners에 툼스톤이 남아 있다 (rows=' || v_n || ')'; end if;
  -- (c) the counterparty CAN still read the name — this is the arm that fails if anyone adds
  --     `deleted_at is null` to `profiles public runner read`
  execute format('select name from profiles where id = %L', r) into v_txt;
  if coalesce(v_txt, '∅') <> '탈퇴한 사용자' then
    v_bad := v_bad || ' (c) 상대가 읽은 이름=' || coalesce(v_txt, '∅') || ' — 빈 작성자는 정직하지도 5.1.1(v) 안전하지도 않다'; end if;
  execute format('select count(*) from profiles where id = %L and handle is null and avatar_url is null and district is null', r) into v_n;
  if v_n <> 1 then v_bad := v_bad || ' (c) 나머지 네 컬럼이 안 비워졌다'; end if;
  begin
    execute format('select phone from profiles where id = %L', r) into v_txt;
    v_bad := v_bad || ' (c) phone이 읽혔다 — 컬럼 그랜트 밖이어야 한다';
  exception when insufficient_privilege then null; when others then null; end;
  begin
    execute format('select toss_customer_key from profiles where id = %L', r) into v_txt;
    v_bad := v_bad || ' (c) toss_customer_key가 읽혔다';
  exception when insufficient_privilege then null; when others then null; end;
  execute 'reset role';
  -- anon gets nothing (the policy is `to authenticated`, and anon holds no column grant)
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  begin
    execute format('select count(*) from profiles where id = %L', r) into v_n;
    if v_n <> 0 then v_bad := v_bad || ' (c) anon이 툼스톤을 ' || v_n || '행 읽었다'; end if;
  exception when insufficient_privilege then null; end;
  execute 'reset role';

  -- (d) a kept review authored by / about a tombstone still resolves, and the subject's rating
  --     is unchanged
  select count(*) into v_n from reviews where target_id = r and rating = 5;
  if v_n <> 1 then v_bad := v_bad || ' (d) 리뷰가 사라졌거나 평점이 바뀌었다'; end if;

  -- marketplace_open_requests: asked, not assumed. It projects bookings+dogs and carries no
  -- profile column at all, and a tombstone cannot appear in it for a second reason —
  -- `active_booking` refuses while any booking is `matching`, the only status that view selects.
  select count(*) into v_n from information_schema.columns
   where table_name = 'marketplace_open_requests' and column_name in ('owner_id','name','handle','avatar_url');
  if v_n <> 0 then v_bad := v_bad || ' marketplace_open_requests가 프로필 컬럼을 투영하기 시작했다 — 이제 여기도 deleted_at을 봐야 한다'; end if;

  if v_bad = '' then
    call _pass('acd','N5 (F7/F8) 상대는 다치지 않고 툼스톤은 보이되 가려진다 — 스레드 생존 · available_runners 0행(뷰에서 차단) · 상대는 "탈퇴한 사용자"를 읽고 phone/toss는 못 읽고 anon은 0행 · 리뷰와 평점 보존');
  else call _fail('acd','N5 툼스톤 가시성 4-arm', v_bad); end if;
exception when others then execute 'reset role'; call _fail('acd','N5 툼스톤 가시성 4-arm', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N6 — the watchdog, two arms. See the header for why arm 1 is rooted at what is ACTUALLY
-- deleted rather than at `profiles`, and why arm 2 cannot be folded into it.
-- The root set is RE-DERIVED FROM prosrc, so putting a table back into ④ moves this pin.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  -- ⚠ COMMENTS ARE STRIPPED FIRST, and finding that out is itself the pin working. The first
  -- version matched `delete from ([a-z_]+)` against raw prosrc and picked up `addresses` — from
  -- the ③ comment that says "this statement REPLACES the `delete from addresses` the reviewer
  -- executed". The pin went red on a correct implementation, for the same reason F1 went red on
  -- a wrong one: `addresses > gate_code_access_log`. A watchdog that reads a function's prose as
  -- its behaviour is a watchdog that can be argued with by writing a comment.
  select array_agg(distinct m[1]) into v_roots
    from pg_proc p, regexp_matches(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
                                   'delete from ([a-z_]+)', 'g') m
   where p.proname = 'delete_my_account_tx';
  if coalesce(array_length(v_roots, 1), 0) < 20 then
    v_bad := v_bad || ' ④ 삭제 목록을 prosrc에서 못 뽑았다 (n=' || coalesce(array_length(v_roots,1),0) || ')'; end if;
  v_roots := v_roots || array['auth.users'];

  with recursive edge as (
    select confrelid::regclass::text as parent, conrelid::regclass::text as child
      from pg_constraint where contype = 'f' and confdeltype in ('c','n')
  ), closure(t, path) as (
    select x, x from unnest(v_roots) x
    union
    select e.child, c.path || ' > ' || e.child from closure c join edge e on e.parent = c.t
     where position(' ' || e.child || ' ' in ' ' || c.path || ' ') = 0
  )
  select string_agg(distinct t || ' (' || path || ')', ' · ') into v_txt
    from closure
   where t in ('ledger_items','payments','payouts','payment_attempts','club_fee_items','km_ledger',
               'km_lots','miles_ledger','gear_claims','bookings','delegation_consents','club_acks',
               'runner_applications','dog_custody_events','dog_run_segments','assignment_events',
               'session_dogs','gate_code_access_log','club_phone_access_log','incidents',
               'club_incidents','club_incident_evidence','runs')
      or t like '%access\_log';
  if v_txt is not null then
    v_bad := v_bad || ' 🔴 삭제되는 테이블에서 보존 테이블에 CASCADE/SET NULL로 닿는다: ' || left(v_txt, 300); end if;
  if v_bad = '' then
    call _pass('acd','N6-1 재귀 폐포 — 실제로 지워지는 테이블(auth.users ∪ prosrc에서 뽑은 ④ 목록)에서 어떤 보존 테이블·%access_log에도 CASCADE/SET NULL로 닿지 않는다. 명시적 삭제 목록도 캐스케이드 원천이다');
  else call _fail('acd','N6-1 재귀 폐포 (④는 캐스케이드 원천이다)', v_bad); end if;
exception when others then call _fail('acd','N6-1 재귀 폐포 (④는 캐스케이드 원천이다)', sqlerrm);
end;

begin
  select string_agg(conrelid::regclass::text || '.' || conname || ' [' || confdeltype::text || ']', ' · ')
    into v_txt
    from pg_constraint
   where contype = 'f' and confdeltype in ('c','n')
     and confrelid in ('profiles'::regclass, 'auth.users'::regclass)
     and (conrelid::regclass::text in
          ('ledger_items','payments','payouts','payment_attempts','club_fee_items','km_ledger',
           'km_lots','miles_ledger','gear_claims','bookings','delegation_consents','club_acks',
           'runner_applications','dog_custody_events','dog_run_segments','assignment_events',
           'session_dogs','gate_code_access_log','club_phone_access_log','incidents',
           'club_incidents','club_incident_evidence','runs')
          or conrelid::regclass::text like '%access\_log')
     and conrelid::regclass::text not in ('club_acks','runner_applications');
  if v_txt is null then
    call _pass('acd','N6-2 직접 간선 — 보존 테이블은 profiles/auth.users에 CASCADE·SET NULL로 매달리지 않는다. 면제는 {club_acks, runner_applications} 두 이름뿐이고 술어가 아니다 (세 번째가 들어오려면 논증이 필요하다). 아직 없는 위치정보 원장이 `profile_id references profiles on delete cascade`로 태어나면 여기서 터진다');
  else call _fail('acd','N6-2 직접 간선 (보존 테이블은 profiles 생존에 기대면 안 된다)', left(v_txt, 300)); end if;
exception when others then call _fail('acd','N6-2 직접 간선 (보존 테이블은 profiles 생존에 기대면 안 된다)', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N7 — no orphan, on BOTH keys. The `addresses` half is the direct pin on F1/F2: putting
-- `addresses` back into ④ turns this red (it did: gate_code_access_log 1 row → 0).
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('n7') f;
  perform delete_my_account_tx(o);
  if not exists (select 1 from addresses where id = v_addr) then
    v_bad := v_bad || ' addresses 행이 사라졌다'; end if;
  select count(*) into v_n from gate_code_access_log g
   left join addresses a on a.id = g.address_id where a.id is null;
  if v_n > 0 then v_bad := v_bad || ' gate_code_access_log 고아 ' || v_n || '행 (F1이 실측한 1→0 그대로)'; end if;
  select count(*) into v_n from bookings b left join addresses a on a.id = b.address_id
   where b.address_id is not null and a.id is null;
  if v_n > 0 then v_bad := v_bad || ' bookings.address_id 고아 ' || v_n; end if;
  select count(*) into v_n from gear_claims g left join addresses a on a.id = g.shipped_to
   where g.shipped_to is not null and a.id is null;
  if v_n > 0 then v_bad := v_bad || ' gear_claims.shipped_to 고아 ' || v_n; end if;
  select count(*) into v_n from recurring_series s left join addresses a on a.id = s.address_id
   where s.address_id is not null and a.id is null;
  if v_n > 0 then v_bad := v_bad || ' recurring_series.address_id 고아 ' || v_n; end if;
  select count(*) into v_n from bookings b left join profiles p on p.id = b.owner_id where p.id is null;
  if v_n > 0 then v_bad := v_bad || ' bookings.owner_id 고아 ' || v_n; end if;
  select count(*) into v_n from reviews rv left join profiles p on p.id = rv.author_id where p.id is null;
  if v_n > 0 then v_bad := v_bad || ' reviews.author_id 고아 ' || v_n; end if;
  if v_bad = '' then
    call _pass('acd','N7 고아 없음 — 삭제 뒤에도 profiles.id와 addresses.id를 가리키는 모든 보존 행이 해석된다 (주소는 아무것도 가리키지 않고 아무도 식별하지 않지만, 누가 언제 문을 열었는지는 여전히 풀린다)');
  else call _fail('acd','N7 고아 없음 (profiles.id · addresses.id)', v_bad); end if;
exception when others then call _fail('acd','N7 고아 없음 (profiles.id · addresses.id)', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- N8 — storage.objects is never deleted by SQL. See the header for why this is a source pin and
-- not an executed one: the shim has no `protect_delete` trigger, and adding it would rewrite
-- 104 M14's measured property. In production the trigger raises 42501 even for service_role,
-- which would roll back a HALF-DONE deletion mid-transaction.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select prosrc into v_txt from pg_proc where proname = 'delete_my_account_tx';
  if v_txt ~* 'delete\s+from\s+storage\.' then v_bad := v_bad || ' delete from storage.* 가 함수 안에 있다'; end if;
  if v_txt ~* '(update|insert\s+into)\s+storage\.' then v_bad := v_bad || ' storage.* 쓰기가 함수 안에 있다'; end if;
  -- and the positive control: the RPC leaves every object of the deleted user in place, because
  -- removing them is the edge function's job through the Storage API
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('n8') f;
  select count(*) into v_n from storage.objects where name like o::text || '/%';
  perform delete_my_account_tx(o);
  select count(*) into v_n2 from storage.objects where name like o::text || '/%';
  if v_n2 <> v_n then v_bad := v_bad || ' RPC가 스토리지 오브젝트를 ' || (v_n - v_n2) || '개 지웠다'; end if;
  if v_bad = '' then
    call _pass('acd','N8 storage는 SQL로 지우지 않는다 — 함수 본문에 storage.* 쓰기가 없고 삭제 후에도 오브젝트 수가 그대로 (운영의 protect_delete는 service_role에도 42501을 던져 반쯤 끝난 삭제를 롤백시킨다 · 심에는 그 트리거가 없다는 사실은 헤더에 기록)');
  else call _fail('acd','N8 storage는 SQL로 지우지 않는다', v_bad); end if;
exception when others then call _fail('acd','N8 storage는 SQL로 지우지 않는다', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P1 — a rich user deletes end to end and THE WHOLE-SCHEMA ROW-COUNT DIFF IS EXACTLY THE
-- EXPECTED SET. The count-diff form is the reviewer's own instrument and it is what turned
-- F1/F2 from an argument into a measurement — keep the SHAPE, not just the intent.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('p1') f;

  select jsonb_object_agg(t, n) into v_before from (
    select c.relname::text as t,
           (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname),
                                                false, true, '')))[1]::text::bigint as n
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind = 'r' and c.relname not like '\_%') s;

  res := delete_my_account_tx(o);

  select jsonb_object_agg(t, n) into v_after from (
    select c.relname::text as t,
           (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', c.relname),
                                                false, true, '')))[1]::text::bigint as n
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind = 'r' and c.relname not like '\_%') s;

  -- expected: exactly the tables ④ actually deleted from (per the function's own report) at
  -- their reported counts, plus one new account_deletions row. Anything else is a surprise.
  select string_agg(k || ': ' || (v_before->>k) || '→' || (v_after->>k), ' · ') into v_diff
    from jsonb_object_keys(v_before) k
   where (v_before->>k) is distinct from (v_after->>k)
     and not (k = 'account_deletions'
              and (v_after->>k)::bigint - (v_before->>k)::bigint = 1)
     and not (coalesce((res#>>array['deleted', k])::int, 0) > 0
              and (v_before->>k)::bigint - (v_after->>k)::bigint = (res#>>array['deleted', k])::int);
  if v_diff is not null then v_bad := v_bad || ' 예상 밖 행수 변화: ' || left(v_diff, 300); end if;

  -- the retention set specifically, table by table
  foreach v_txt in array array['ledger_items','payments','payouts','payment_attempts',
      'club_fee_items','km_ledger','km_lots','miles_ledger','gear_claims','bookings',
      'delegation_consents','club_acks','runner_applications','dog_custody_events',
      'dog_run_segments','assignment_events','session_dogs','gate_code_access_log',
      'club_phone_access_log','incidents','club_incidents','club_incident_evidence','runs',
      'chat_messages','reviews','addresses','dogs'] loop
    if (v_before->>v_txt) is distinct from (v_after->>v_txt) then
      v_bad := v_bad || ' 🔴 보존 테이블 ' || v_txt || ' 가 ' || (v_before->>v_txt) || '→' || (v_after->>v_txt); end if;
  end loop;

  -- the auth row can now go, and the tombstone stays. THIS IS THE DIRECT PIN ON §A's DROP:
  -- with profiles_id_fkey still in place this delete would cascade the whole 33-path graph.
  delete from auth.users where id = o;
  if not exists (select 1 from profiles where id = o and deleted_at is not null) then
    v_bad := v_bad || ' 🔴 auth.users 삭제가 profiles를 데려갔다 — profiles_id_fkey가 살아 있다'; end if;
  if not exists (select 1 from bookings where id = bk) then
    v_bad := v_bad || ' 🔴 예약이 사라졌다 (전자상거래법 제6조)'; end if;
  if not exists (select 1 from payment_attempts where booking_id = bk) then
    v_bad := v_bad || ' 🔴 payment_attempts가 사라졌다'; end if;

  if v_bad = '' then
    call _pass('acd','P1 풍부한 사용자가 끝까지 삭제되고 전 스키마 행수 차이는 ④가 보고한 집합 그대로 — 보존 테이블 27종 무변화, auth.users를 지워도 툼스톤과 예약·결제 시도가 남는다 (0115 §A의 FK 드롭에 대한 직접 핀)');
  else call _fail('acd','P1 전 스키마 행수 차이', left(v_bad, 400)); end if;
exception when others then call _fail('acd','P1 전 스키마 행수 차이', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P2 — the tombstone is actually a tombstone, on all four tables (+ bank_accounts absent).
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  select f.o, f.r, f.d, f.v_addr, f.bk, f.sd into o, r, d, v_addr, bk, sd from t_acd_rich('p2') f;
  insert into runner_applications (profile_id, district, avg_pace_sec_per_km, max_dog_weight_kg,
    bio, running_experience, dog_experience, contact_kakao, contact_phone, contact_window,
    consent_terms, consent_privacy, consent_id_check)
  values (o, '반포동', 330, 20, '열 글자가 넘는 자기소개입니다', '십 년째 달리고 있습니다',
          '강아지를 오래 키웠습니다', 'kakao_id_123', '01012345678', '평일 저녁', true, true, true);
  insert into bank_accounts (runner_id, bank, account_enc, holder) values (r, '카카오뱅크', 'ENC-XYZ', '홍길동');
  select created_at into v_txt from runner_applications where profile_id = o;
  perform delete_my_account_tx(o);

  -- profiles
  select count(*) into v_n from profiles
   where id = o and name = '탈퇴한 사용자' and handle is null and phone is null
     and avatar_url is null and district is null and deleted_at is not null
     and toss_customer_key is not null;
  if v_n <> 1 then v_bad := v_bad || ' profiles 툼스톤 불완전 (toss_customer_key는 KEEP)'; end if;

  -- addresses (F1/F2) — assert the PAIR, not one side: addresses_latlng_shape would have
  -- rejected a half-redaction outright
  select count(*) into v_n from addresses
   where id = v_addr and gate_code_enc is null and detail is null
     and lat is null and lng is null and is_default = false
     and addr = '삭제된 주소' and label = '삭제된 주소';
  if v_n <> 1 then v_bad := v_bad || ' addresses 레닥션 불완전 (lat/lng는 쌍으로)'; end if;
  if exists (select 1 from addresses where id = v_addr and addr like '%반포동%') then
    v_bad := v_bad || ' 🔴 원래 주소 문자열이 남았다'; end if;

  -- dogs (F16) — name UNCHANGED
  select count(*) into v_n from dogs where id = d and photo_url is null and memo is null and name = '나비';
  if v_n <> 1 then v_bad := v_bad || ' dogs: photo_url/memo가 안 지워졌거나 name이 바뀌었다 (다견 보호자의 세 계약이 한 문자열로 뭉개진다 — §C.1.b ③과 논쟁할 것)'; end if;

  -- runner_applications (F10)
  select count(*) into v_n from runner_applications
   where profile_id = o and contact_phone is null and contact_window is null
     and contact_kakao = '[탈퇴]' and bio = '탈퇴로 삭제된 항목입니다'
     and running_experience = '탈퇴로 삭제된 항목입니다' and dog_experience = '탈퇴로 삭제된 항목입니다'
     and consent_terms and consent_privacy and consent_id_check and created_at::text = v_txt;
  if v_n <> 1 then v_bad := v_bad || ' runner_applications 레닥션/동의 증거 불완전'; end if;
  -- the mutation arm that documents the NOT NULL/CHECK reality instead of leaving it as prose
  begin
    update runner_applications set bio = null where profile_id = o;
    v_bad := v_bad || ' 🔴 bio = null이 통과했다 — 0062:70-72의 NOT NULL/CHECK가 사라졌다';
  exception when not_null_violation then null; when check_violation then null;
    when others then v_bad := v_bad || ' bio=null이 예상 밖 이유로 막혔다: ' || sqlerrm; end;

  -- bank_accounts (F9) — assert ABSENCE explicitly. This is the row whose account_enc survived
  -- the reviewer's entire run, because nothing in ③ looks at this table.
  perform delete_my_account_tx(r);
  if exists (select 1 from bank_accounts where runner_id = r) then
    v_bad := v_bad || ' 🔴 bank_accounts가 남았다 — account_enc(암호화된 계좌)와 실명 holder가 그대로'; end if;

  if v_bad = '' then
    call _pass('acd','P2 네 테이블 모두 진짜 툼스톤 — profiles(이름 대체·나머지 null·toss_customer_key 보존) · addresses(gate_code_enc/detail null·lat·lng 쌍으로 null·상수 플레이스홀더) · dogs(사진/메모만, 이름은 그대로) · runner_applications(연락·서술만 가리고 동의 3종과 시각은 그대로, bio=null은 실제로 raise한다) · bank_accounts는 사라진다');
  else call _fail('acd','P2 네 테이블 툼스톤 + bank_accounts 부재', left(v_bad, 400)); end if;
exception when others then call _fail('acd','P2 네 테이블 툼스톤 + bank_accounts 부재', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P4 — the handle is freed. Works only because profiles_handle_lower_uniq is PARTIAL
-- (`where handle is not null`) — MEASURED.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_h_o', 'owner');
  update profiles set handle = 'acd_taken' where id = o;
  perform delete_my_account_tx(o);
  u := t_user('acd_h_new', 'owner');
  perform set_config('request.jwt.claim.sub', u::text, true);
  begin
    v_txt := set_my_handle('acd_taken');
  exception when others then v_bad := v_bad || ' 새 사용자가 옛 핸들을 못 가져갔다: ' || sqlerrm; end;
  perform set_config('request.jwt.claim.sub', '', true);
  if not exists (select 1 from profiles where id = u and lower(handle) = 'acd_taken') then
    v_bad := v_bad || ' 핸들이 넘어가지 않았다'; end if;
  if v_bad = '' then
    call _pass('acd','P4 핸들 해방 — 툼스톤의 handle이 null이 되어 다음 사용자가 set_my_handle로 가져간다 (부분 유니크 인덱스라서 가능)');
  else call _fail('acd','P4 핸들 해방', v_bad); end if;
exception when others then call _fail('acd','P4 핸들 해방', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P5 — re-signup is a NEW account, and the tombstone is not adopted.
-- ⚠ The harness shim has `auth.users` but no `auth.identities`, so the Kakao-identity half of
-- the mechanism (identities.user_id → auth.users CASCADE, so the provider link dies with the
-- auth row and the next signInWithOAuth mints a fresh uid) CANNOT be executed here. What IS
-- executed is the half that this migration owns and that the identity half rests on: the auth
-- row can be deleted at all, the tombstone survives it, and a new auth user with a fresh id does
-- not inherit anything. Production has exactly ONE kakao identity, so the identity arm is the
-- least-exercised path in the whole contract and is verified live in §E.4 / on device.
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_p5_o', 'owner');
  update profiles set handle = 'acd_p5_handle' where id = o;
  perform delete_my_account_tx(o);
  delete from auth.users where id = o;
  if exists (select 1 from auth.users where id = o) then v_bad := v_bad || ' auth 행이 안 지워졌다'; end if;
  if not exists (select 1 from profiles where id = o and deleted_at is not null) then
    v_bad := v_bad || ' 🔴 툼스톤이 auth 삭제에 딸려갔다'; end if;
  u := t_user('acd_p5_new', 'owner');
  if u = o then v_bad := v_bad || ' 새 uid가 옛 uid와 같다'; end if;
  if exists (select 1 from profiles where id = u and deleted_at is not null) then
    v_bad := v_bad || ' 새 계정이 툼스톤을 물려받았다'; end if;
  if exists (select 1 from pg_constraint where conname = 'profiles_id_fkey' and conrelid = 'profiles'::regclass) then
    v_bad := v_bad || ' 🔴 profiles_id_fkey가 되살아났다 — 33개 캐스케이드 경로가 다시 열렸다'; end if;
  if v_bad = '' then
    call _pass('acd','P5 재가입은 새 계정 — auth 행은 지워지고 툼스톤은 살아남으며 새 uid는 아무것도 물려받지 않는다 (⚠ 카카오 identity 캐스케이드 반쪽은 심에 auth.identities가 없어 여기서 실행 불가 — §E.4 라이브 프로브 항목)');
  else call _fail('acd','P5 재가입은 새 계정', v_bad); end if;
exception when others then call _fail('acd','P5 재가입은 새 계정', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P6 — idempotent, and the retry path works (F15). The `already: true` short-circuit is
-- LOAD-BEARING, not defensive: it is the whole `auth_delete_failed` retry.
-- Plus the §G-6 arm: an auth.users row with NO profiles row (production has one — 11 vs 10).
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_p6_o', 'owner');
  res := delete_my_account_tx(o);
  if not (res->>'tombstoned')::boolean then v_bad := v_bad || ' 첫 호출이 툼스톤을 안 만들었다'; end if;
  res := delete_my_account_tx(o);
  if coalesce((res->>'already')::boolean, false) is not true then
    v_bad := v_bad || ' 두 번째 호출이 already:true가 아니다 — 재시도가 SQL 반쪽을 다시 돈다'; end if;
  if (res->>'log_id') is null then
    v_bad := v_bad || ' 재시도가 log_id를 안 돌려줬다 — 엣지 함수가 auth_deleted를 어느 행에 쓸지 모른다'; end if;
  select count(*) into v_n from account_deletions where profile_id = o;
  if v_n <> 1 then v_bad := v_bad || ' account_deletions 행이 ' || v_n || '개 (기대 1)'; end if;
  -- §G-6: an auth user with no profile
  u := gen_random_uuid();
  insert into auth.users (id, email) values (u, 'acd_noprofile@test.local');
  res := delete_my_account_tx(u);
  if not (res->>'ok')::boolean or coalesce((res->>'already')::boolean, false) is not true then
    v_bad := v_bad || ' 프로필 없는 auth 사용자가 ok/already로 안 끝났다'; end if;
  if coalesce((res->>'tombstoned')::boolean, true) is not false then
    v_bad := v_bad || ' 프로필이 없는데 tombstoned=true라고 했다'; end if;
  if v_bad = '' then
    call _pass('acd','P6 멱등 + 재시도 (F15) — 두 번째 호출은 already:true에 log_id를 달아 돌아오고 로그 행은 하나뿐, 프로필 없는 auth 사용자(운영 11 vs 10)도 깨끗이 끝난다');
  else call _fail('acd','P6 멱등 + 재시도 (F15)', v_bad); end if;
exception when others then call _fail('acd','P6 멱등 + 재시도 (F15)', sqlerrm);
end;

-- ══════════════════════════════════════════════════════════════════════════════════════════
-- P7 — the log is written, including the forfeits, and `auth_deleted` is NOT claimed by the RPC.
-- The transaction commits before the auth call is even attempted, so a value written here would
-- be a claim about the future (F15).
-- ══════════════════════════════════════════════════════════════════════════════════════════
begin
  v_bad := '';
  o := t_user('acd_p7_o', 'runner');   -- drops.runner_id → runners
  insert into miles_ledger (profile_id, delta, reason) values (o, 1200, 'welcome');
  insert into miles_ledger (profile_id, delta, reason) values (o, -200, 'spend');
  insert into drops (runner_id, kind, run_count_at, contents) values (o, 'mini', 1, '{"miles": 10}'::jsonb);
  insert into drops (runner_id, kind, run_count_at, contents) values (o, 'mini', 2, '{"miles": 10}'::jsonb);
  insert into push_tokens (profile_id, token) values (o, 'p7-tok');
  res := delete_my_account_tx(o);
  select count(*) into v_n from account_deletions
   where profile_id = o and completed_at is not null and auth_deleted is null
     and forfeited_miles = 1000 and forfeited_drops = 2
     and (counts->>'push_tokens')::int = 1;
  if v_n <> 1 then
    select 'row=' || coalesce((select row_to_json(a)::text from account_deletions a where a.profile_id = o), '∅')
      into v_msg;
    v_bad := v_bad || ' ' || left(v_msg, 300); end if;
  if (res->>'log_id')::uuid is distinct from (select id from account_deletions where profile_id = o) then
    v_bad := v_bad || ' / 반환 log_id가 실제 행과 다르다'; end if;
  if v_bad = '' then
    call _pass('acd','P7 로그 — counts·completed_at·forfeited_miles(1000=1200-200)·forfeited_drops(2)가 기록되고 auth_deleted는 NULL이다 (트랜잭션은 auth 삭제를 시도하기도 전에 커밋한다 — 여기 쓰인 값은 미래에 대한 주장일 뿐이다. 엣지 함수가 step 5 뒤에 쓴다)');
  else call _fail('acd','P7 로그 + 소멸량 + auth_deleted 미기재', v_bad); end if;
exception when others then call _fail('acd','P7 로그 + 소멸량 + auth_deleted 미기재', sqlerrm);
end;

end $$;
