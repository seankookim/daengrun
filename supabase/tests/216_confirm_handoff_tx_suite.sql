-- ═══ 216 — 0185: the stamp and the promotion in one locked transaction · a late answer wakes a no_response tick — 0185-G1…G5 · H1 · S1, tag `chx` ═══
--
-- THE PROPOSITIONS THIS FILE OWNS (codex re-review of 0184, REJECT/2):
--   · G1 one call = one statement: the stamp lands, the promotion rides the SAME statement when the
--     locked row shows both stamps, the returned row is the row as written; a re-tap keeps the
--     first stamp and mints no cycle; after the handoff a re-tap is silent.
--   · G2 the party gate is taken on the LOCKED row: a re-match that committed first makes the old
--     runner `not_party` — nothing written; strangers, side mismatches, a bad side, no caller, no row.
--   · G3 two confirmations from different cycles never promote (the belt): a counterparty stamp
--     older than `handoff_cycle_at` is cleared and that party re-asked; equality is not staleness.
--   · G4 the status gate: picked_up/active ⇒ unchanged and silent; every other non-eligible status
--     in the enum ⇒ `wrong_status`, nothing written.
--   · G5 THE FINDING AT THE CUSTODY TRIGGER: a club booking re-matched before the old runner's
--     confirm reaches the lock records NO custody; the new pairing's own two confirmations record
--     custody once, for the runner on the row; the runner who left never appears as custodian.
--   · H1 #2: a `no_response` tick whose late answer meets a persistent unnamed fault goes back to
--     `sent` (detail and resolved_at cleared), is counted by `stuck_unreadable`, stays `sent` past
--     retention and the TTL, and reconciles once the fault clears; controls for the readable late
--     answer (accepted), the named fault (failed), and the never-observed row past the TTL.
--   · S1 deployed shape (definer/ACL/search_path, the lock before the gate before the write, one
--     promotion statement, the boundary conjuncts; the reconciler's woken arm and both CAS'd writes).
--
-- ─── MUTATION MAP — measured 2026-09-18, not predicted (numbers in the REGISTRY row) ───
--   Lab: an md5-identical copy of `supabase/` (0185 + 216 + 90_race_check.sh + the edge + its deno
--   file), every plant `&&`-chained to its run and asserted to have landed, the control observed
--   first (1307 / 0; deno 22 / 0 for the edge file). 「demoted」 = 0185's VERIFY raise turned into a
--   notice so the SUITE is what is measured; 「un-demoted」 = the shipped file, where the VERIFY
--   aborts the apply before any suite runs.
--   (i)   the party gate deleted from the locked read     → RW (state confirmed/true/1: the old
--         runner's stamp on the new pairing) + G5 (old-runner: accepted) + G2 + S1; un-demoted
--         ABORTS (PARTY-GATE-NOT-BEFORE-THE-WRITE · PARTY-GATE-BEFORE-THE-LOCK).
--   (ii)  the promotion as a SECOND id-only statement after the stamp, same transaction, still
--         under the lock                                  → S1 only (승격이 도장 문장에 없음) — by
--         design: the LOCK carries the property (every behavioural pin and RW stay green); the
--         one-statement shape is the belt, and the belt is pinned by text alone. Un-demoted ABORTS.
--   (iii) the row lock deleted                            → RW (state picked_up/true/1 — the finding
--         itself: the old runner's stamp AND picked_up on the re-matched pairing) + S1; every
--         single-session pin stays green (measured: 1305/2) — which is why RW exists. Un-demoted
--         ABORTS (NO-ROW-LOCK · PARTY-GATE-BEFORE-THE-LOCK — the order arm fires on absence too
--         since the cold review's fix; measured twice, the second battery on the final files).
--   (iv)  the cycle-boundary conjuncts deleted            → G3 (PROMOTED-ON-ANOTHER-PAIRING'S-STAMP,
--         the stale stamp kept, the owner not re-asked, no fresh cycle) + S1; un-demoted ABORTS.
--   (v)   the status gate deleted                         → G4 (every non-eligible status: the
--         database's own `handoff_on_closed_booking` guard answers instead of `wrong_status` —
--         the named refusal is what the pin holds); un-demoted ABORTS (NO-STATUS-GATE).
--   (vi)  a re-tap overwrites the runner's stamp          → G1 (re-tap-moved-the-stamp, both
--         statuses). No VERIFY arm: the suite alone owns this rule.
--   (vii) 0184's arm back (observation recorded, the no_response verdict kept)
--                                                         → H1 (after-fault: no_response, the
--         obsolete verdict kept, stuck_unreadable 0) + S1; un-demoted ABORTS.
--   (viii) the CAS deleted from the unnamed-fault arm     → RV/42883 (state sent/3/true/false — the
--         completed verdict overwritten) + S1 (CAS 1/2); un-demoted ABORTS.
--   (ix)  the CAS deleted from the failed write           → RV/22003 (state failed/3/true/true) + S1
--         (CAS 1/2); un-demoted ABORTS.
--   (x)   the promotion on ONE stamp                      → G1 + G2 + G3 + G5 + S1; un-demoted
--         ABORTS (PROMOTION-NOT-BOTH-STAMPS).
--   Deno (the edge file, control 22/0): (a) the promotion as a separate `set({status:'picked_up'})`
--   after the rpc → 2 red (the promoted pin: a PATCH; the arm-scoped source pin); (b) 「인계 완료」
--   told to the SNAPSHOT parties → 1 red; (c) an unknown refusal answers 200 → 1 red (fails
--   closed); (d) a bookings read after the rpc decides the cycle → 4 red; (e) the ask recipient
--   from the snapshot → 1 red; (f) the arm asks whenever it did not promote, falling back to the
--   owner → 1 red (already handed off ⇒ silence).
--   Cold-reader EXECUTED review (Opus, its own copy, 69 tool calls, 9 plants incl. the 125 exemption
--   removed → F5 red): no code defect; two pin-construction findings taken: the lock-order arms
--   read 「0 < x」 on a LOCKLESS source (position() = 0) — now `> 0 and …`; G4's non-eligible arms
--   sit where 0117's `booking_handoff_stamp_guard` already refuses the stamp — the gate adds the
--   NAME (`wrong_status` → the edge's Korean 409), and the pass string says so. Also taken: `both`
--   on the no-op return reads the row; the failed write counts by row_count. Recorded, unchanged
--   from 0184 (the edge's behaviour, not this slice's): a double-tap before the counterparty
--   confirms writes two identical asks (the sweep dedupes its own re-sends only); the pre-switch
--   party gate still answers the stale snapshot's 403 in English for the NEW runner in the mirror
--   window (refusal-only, transient).
--   NAMED GAPS: the reassignment-between-stamp-and-promotion of the verdict cannot happen inside
--   one statement, so its two remaining orders are what is pinned (before the lock: G2/G5/RW;
--   after the commit: 0048's `already_handed_off` on a picked_up row, read, not pinned here). The
--   concurrent-verdict CAS is invisible to one session (the row the loop reads is the row it
--   writes) — RV is its only behavioural pin. `custodian_*` on session_dogs is the assignment
--   projection (0040), so G5 measures physical custody by the outbound event and `checked_in_at`.
--
-- ─── FIXTURE NOTES ───
--  ① `t_ask_bk` / `t_asks` are 212's helpers. `t_chx_call` wraps the RPC so a raise becomes
--     {raised: <name>} instead of aborting the block (the 0179 #14 class).
--  ② `request.jwt.claim.sub` is cleared for this block: the RPC takes `coalesce(auth.uid(), p_uid)`,
--     and a leftover session claim would silently replace every `p_uid` below.
--  ③ A stamp 「older than the boundary」 is made by writing the stamp in the past and THEN changing
--     the runner (the trigger stamps `handoff_cycle_at = now()`); within one transaction `now()` is
--     constant, so a stamp written after a change is at the boundary, never past it — G3's control.
--  ④ The fault stand-in is 214/215's: a temporary trigger raising a chosen SQLSTATE on the tick's
--     `accepted` write. 「the answer deleted」 = the `net._http_response` row removed by hand;
--     「the TTL passed」 = `sent_at` moved 7 hours back.
set client_min_messages = warning;

create or replace function t_chx_call(p_bk uuid, p_uid uuid, p_side text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  begin
    v := confirm_handoff_tx(p_bk, p_uid, p_side);
  exception when others then
    v := jsonb_build_object('raised', sqlerrm);
  end;
  return v;
end $$;

create or replace function t_chx_custody(p_bk uuid) returns int
language sql as $$
  select count(*)::int from dog_custody_events e join session_dogs sd on sd.id = e.session_dog_id
  where sd.booking_id = p_bk and e.event_type = 'outbound'
$$;

do $$
declare
  o uuid; r1 uuid; r2 uuid; x uuid; d uuid; d5 uuid; rt uuid; bk uuid; bk2 uuid; v_club uuid; v_sess uuid; v_sd uuid;
  v jsonb; r record; s booking_status; v_a uuid; v_b uuid; v_cyc uuid; v_at timestamptz; v_stamp timestamptz;
  t1 uuid; t2 uuid; t3 uuid; t4 uuid; v_req int; v_n int; v_n0 int; v_oid oid; v_src text;
  v_bad text; v_msg text; v_note text;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                          -- ②
  o := t_user('chx_owner', 'owner'); r1 := t_user('chx_runner1', 'runner'); r2 := t_user('chx_runner2', 'runner');
  x := t_user('chx_stranger', 'owner'); d := t_dog(o, 'chx-dog'); d5 := t_dog(o, 'chx-dog-5'); rt := t_route('chx 코스');
  begin perform sweep_run_end_recovery(); exception when others then null; end;

  -- ---------- [0185-G1] one call, one statement: stamp, promotion, the returned row; a re-tap keeps the stamp ----------
  v_bad := '';
  foreach s in array array['confirmed', 'runner_enroute']::booking_status[] loop
    bk := t_ask_bk(o, d, rt, r1, s, 'none', interval '0');
    v := t_chx_call(bk, r1, 'runner');
    select * into r from bookings where id = bk;
    if v->>'raised' is not null then v_bad := v_bad || ' ' || s || ': raised=' || (v->>'raised'); end if;
    if (v->>'promoted')::boolean is distinct from false or (v->>'both')::boolean is distinct from false or (v->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' ' || s || ': one-sided-returned promoted=' || coalesce(v->>'promoted', 'NULL') || ' both=' || coalesce(v->>'both', 'NULL'); end if;
    if (v->>'ask_to')::uuid is distinct from o then v_bad := v_bad || ' ' || s || ': ask_to=' || coalesce(v->>'ask_to', 'NULL') || ' (expected the owner)'; end if;
    if r.runner_confirmed_handoff_at is null or r.owner_confirmed_handoff_at is not null then v_bad := v_bad || ' ' || s || ': stamps=' || (r.owner_confirmed_handoff_at is not null)::int || '/' || (r.runner_confirmed_handoff_at is not null)::int || ' (expected 0/1)'; end if;
    if r.status is distinct from s then v_bad := v_bad || ' ' || s || ': status-moved-to ' || r.status; end if;
    if r.handoff_cycle_id is null or (v->>'handoff_cycle_id')::uuid is distinct from r.handoff_cycle_id then v_bad := v_bad || ' ' || s || ': returned-cycle=' || coalesce(v->>'handoff_cycle_id', 'NULL') || ' row=' || coalesce(r.handoff_cycle_id::text, 'NULL'); end if;
    if (v->>'owner_id')::uuid is distinct from o or (v->>'runner_id')::uuid is distinct from r1 or v->>'status' is distinct from s::text then v_bad := v_bad || ' ' || s || ': returned-row-is-not-the-row'; end if;
    v_cyc := r.handoff_cycle_id;
    -- the same side again: the FIRST stamp is kept (sweep ⓒ's and ⓓ's clocks read it), no new cycle
    update bookings set runner_confirmed_handoff_at = now() - interval '3 minutes' where id = bk;
    v := t_chx_call(bk, r1, 'runner');
    select * into r from bookings where id = bk;
    if r.runner_confirmed_handoff_at is distinct from now() - interval '3 minutes' then v_bad := v_bad || ' ' || s || ': re-tap-moved-the-stamp'; end if;
    if r.handoff_cycle_id is distinct from v_cyc then v_bad := v_bad || ' ' || s || ': re-tap-minted-a-cycle'; end if;
    if (v->>'promoted')::boolean is distinct from false or (v->>'ask_to')::uuid is distinct from o then v_bad := v_bad || ' ' || s || ': re-tap-returned promoted=' || coalesce(v->>'promoted', 'NULL') || ' ask_to=' || coalesce(v->>'ask_to', 'NULL'); end if;
    -- the owner confirms: the promotion rides the owner's stamp, in the same statement
    v := t_chx_call(bk, o, 'owner');
    select * into r from bookings where id = bk;
    if v->>'raised' is not null then v_bad := v_bad || ' ' || s || ': owner-raised=' || (v->>'raised'); end if;
    if (v->>'promoted')::boolean is distinct from true or (v->>'both')::boolean is distinct from true or v->>'ask_to' is not null then v_bad := v_bad || ' ' || s || ': promotion-returned promoted=' || coalesce(v->>'promoted', 'NULL') || ' both=' || coalesce(v->>'both', 'NULL') || ' ask_to=' || coalesce(v->>'ask_to', 'NULL'); end if;
    if r.status is distinct from 'picked_up' or r.owner_confirmed_handoff_at is null or r.runner_confirmed_handoff_at is null then v_bad := v_bad || ' ' || s || ': after-both status=' || r.status || ' stamps=' || (r.owner_confirmed_handoff_at is not null)::int || '/' || (r.runner_confirmed_handoff_at is not null)::int; end if;
    if v->>'status' is distinct from 'picked_up' or (v->>'handoff_cycle_id')::uuid is distinct from v_cyc or r.handoff_cycle_id is distinct from v_cyc then v_bad := v_bad || ' ' || s || ': a-promotion-is-not-a-new-cycle (returned ' || coalesce(v->>'status', 'NULL') || '/' || coalesce(v->>'handoff_cycle_id', 'NULL') || ')'; end if;
    -- after the handoff a re-tap is silent: nothing written, nobody to ask
    v_stamp := r.runner_confirmed_handoff_at;
    v := t_chx_call(bk, r1, 'runner');
    select * into r from bookings where id = bk;
    if (v->>'unchanged')::boolean is distinct from true or (v->>'promoted')::boolean is distinct from false or (v->>'both')::boolean is distinct from true or v->>'ask_to' is not null then v_bad := v_bad || ' ' || s || ': post-handoff-re-tap returned ' || v::text; end if;
    if r.runner_confirmed_handoff_at is distinct from v_stamp or r.status is distinct from 'picked_up' then v_bad := v_bad || ' ' || s || ': post-handoff-re-tap-wrote'; end if;
  end loop;
  if v_bad = '' then call _pass('chx','0185-G1 한 호출 = 한 문장: 도장이 찍히고, 잠긴 행에 양쪽 도장이면 같은 문장에서 picked_up; 반환 행 = 쓰인 행(사이클 id 포함); 같은 쪽 재탭은 첫 도장을 지키고 사이클을 안 만든다; 인계 뒤 재탭은 무동작 (confirmed·runner_enroute)');
  else v_msg := v_bad; call _fail('chx','0185-G1 one-statement', v_msg); end if;

  -- ---------- [0185-G2] the party gate on the LOCKED row — the mirror order, strangers, mismatches ----------
  v_bad := '';
  bk := t_ask_bk(o, d, rt, r1, 'confirmed', 'none', interval '0');
  v := t_chx_call(bk, r1, 'runner');                                                              -- r1 confirms (cycle A)
  select handoff_cycle_id into v_a from bookings where id = bk;
  -- the host re-matches to r2 FIRST (0048's exact shape: runner replaced, both stamps void) …
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk;
  select handoff_cycle_id into v_b from bookings where id = bk;
  if v_b is not distinct from v_a then v_bad := v_bad || ' fixture: the re-match minted no cycle'; end if;
  -- … and r1's confirm reaches the lock after it: a stranger to this row now
  v := t_chx_call(bk, r1, 'runner');
  select * into r from bookings where id = bk;
  if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' old-runner: ' || coalesce(v->>'raised', 'no raise — ' || v::text); end if;
  if r.runner_confirmed_handoff_at is not null or r.owner_confirmed_handoff_at is not null or r.status is distinct from 'confirmed' or r.runner_id is distinct from r2 or r.handoff_cycle_id is distinct from v_b then v_bad := v_bad || ' old-runner-wrote: stamps=' || (r.owner_confirmed_handoff_at is not null)::int || '/' || (r.runner_confirmed_handoff_at is not null)::int || ' status=' || r.status || ' cycle-moved=' || (r.handoff_cycle_id is distinct from v_b)::text; end if;
  v := t_chx_call(bk, x, 'runner');  if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' stranger-as-runner: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(bk, x, 'owner');   if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' stranger-as-owner: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(bk, o, 'runner');  if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' owner-as-runner: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(bk, r2, 'owner');  if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' runner-as-owner: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(bk, r2, 'x');      if v->>'raised' is distinct from 'bad_side' then v_bad := v_bad || ' bad-side: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(bk, null, 'runner'); if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' no-caller: ' || coalesce(v->>'raised', 'accepted'); end if;
  v := t_chx_call(gen_random_uuid(), r2, 'runner'); if v->>'raised' is distinct from 'not_found' then v_bad := v_bad || ' no-row: ' || coalesce(v->>'raised', 'accepted'); end if;
  select * into r from bookings where id = bk;
  if r.runner_confirmed_handoff_at is not null or r.owner_confirmed_handoff_at is not null then v_bad := v_bad || ' a-refusal-wrote-a-stamp'; end if;
  -- the current pairing confirms on its own: r2 then the owner ⇒ picked_up with r2
  v := t_chx_call(bk, r2, 'runner');
  if v->>'raised' is not null or (v->>'ask_to')::uuid is distinct from o then v_bad := v_bad || ' new-runner: ' || v::text; end if;
  v := t_chx_call(bk, o, 'owner');
  select * into r from bookings where id = bk;
  if (v->>'promoted')::boolean is distinct from true or (v->>'runner_id')::uuid is distinct from r2 or r.status is distinct from 'picked_up' or r.runner_id is distinct from r2 then v_bad := v_bad || ' new-pairing: ' || v::text || ' status=' || r.status; end if;
  if v_bad = '' then call _pass('chx','0185-G2 파티 게이트는 잠긴 행에서: 재배정이 먼저 커밋되면 옛 러너의 확인은 not_party — 도장·상태·사이클 무변; 남·역할 불일치·잘못된 side·호출자 없음·없는 행 모두 이름으로 거절, 아무것도 안 쓴다; 새 짝은 스스로 picked_up');
  else v_msg := v_bad; call _fail('chx','0185-G2 locked-gate', v_msg); end if;

  -- ---------- [0185-G3] two confirmations from different cycles never promote — the belt, and its control ----------
  v_bad := '';
  bk := t_ask_bk(o, d, rt, r1, 'confirmed', 'none', interval '0');
  update bookings set owner_confirmed_handoff_at = now() - interval '10 minutes' where id = bk;   -- the owner confirmed r1 (cycle A) ③
  select handoff_cycle_id into v_a from bookings where id = bk;
  update bookings set runner_id = r2 where id = bk;   -- a runner change that KEEPS the stamp: no shipped pre-handoff path does this (all void both); the class is what the belt is for
  select handoff_cycle_id, handoff_cycle_at into v_b, v_at from bookings where id = bk;
  if v_b is not distinct from v_a or v_at is null then v_bad := v_bad || ' fixture: the runner change minted nothing'; end if;
  if (select owner_confirmed_handoff_at < v_at from bookings where id = bk) is distinct from true then v_bad := v_bad || ' fixture: the owner stamp is not older than the boundary'; end if;
  v := t_chx_call(bk, r2, 'runner');
  select * into r from bookings where id = bk;
  if v->>'raised' is not null then v_bad := v_bad || ' raised=' || (v->>'raised'); end if;
  if (v->>'promoted')::boolean is distinct from false or r.status is distinct from 'confirmed' then v_bad := v_bad || ' PROMOTED-ON-ANOTHER-PAIRING''S-STAMP (returned ' || coalesce(v->>'promoted', 'NULL') || ', status ' || r.status || ')'; end if;
  if r.owner_confirmed_handoff_at is not null then v_bad := v_bad || ' the-stale-owner-stamp-was-kept (a row with two stamps and no promotion sits forever)'; end if;
  if r.runner_confirmed_handoff_at is null then v_bad := v_bad || ' the-runner-stamp-did-not-land'; end if;
  if (v->>'both')::boolean is distinct from false or (v->>'ask_to')::uuid is distinct from o then v_bad := v_bad || ' the-owner-is-not-re-asked (both=' || coalesce(v->>'both', 'NULL') || ' ask_to=' || coalesce(v->>'ask_to', 'NULL') || ')'; end if;
  if (v->>'handoff_cycle_id')::uuid is distinct from r.handoff_cycle_id then v_bad := v_bad || ' returned-cycle-is-not-the-row''s'; end if;
  if r.handoff_cycle_id is not distinct from v_b then v_bad := v_bad || ' clearing-the-stale-stamp-started-no-fresh-cycle'; end if;
  -- the owner confirms THIS pairing ⇒ promoted
  v := t_chx_call(bk, o, 'owner');
  select * into r from bookings where id = bk;
  if (v->>'promoted')::boolean is distinct from true or r.status is distinct from 'picked_up' then v_bad := v_bad || ' this-pairing-not-promoted: ' || v::text; end if;
  -- the control: a stamp AT the boundary (born with the owner's stamp: stamp = boundary = now()) is this cycle's
  bk2 := t_ask_bk(o, d, rt, r1, 'confirmed', 'owner', interval '0');
  if (select owner_confirmed_handoff_at = handoff_cycle_at from bookings where id = bk2) is distinct from true then v_bad := v_bad || ' control-fixture: stamp<>boundary'; end if;
  v := t_chx_call(bk2, r1, 'runner');
  if (v->>'promoted')::boolean is distinct from true or (select status from bookings where id = bk2) is distinct from 'picked_up' then v_bad := v_bad || ' control: a-stamp-at-the-boundary-read-as-stale: ' || v::text; end if;
  if v_bad = '' then call _pass('chx','0185-G3 다른 사이클의 두 확인은 절대 picked_up이 아니다: 경계(handoff_cycle_at)보다 오래된 상대 도장은 지워지고 그쪽에 다시 묻는다(새 사이클); 이 짝이 확인하면 picked_up; 경계와 같은 시각의 도장은 이 사이클의 것');
  else v_msg := v_bad; call _fail('chx','0185-G3 cycle-boundary', v_msg); end if;

  -- ---------- [0185-G4] the status gate: handed off ⇒ silent; anything else non-eligible ⇒ wrong_status, nothing written ----------
  v_bad := ''; v_note := '';
  for s in select unnest(enum_range(null::booking_status)) loop
    continue when s in ('confirmed', 'runner_enroute');
    bk := t_ask_bk(o, d, rt, r1, s, 'owner', interval '0');                                        -- the OTHER side already confirmed
    v := t_chx_call(bk, r1, 'runner');
    select * into r from bookings where id = bk;
    if s in ('picked_up', 'active') then
      -- one stamp on the row: `both` reports the ROW (false) — the call is a silent no-op either way
      if v->>'raised' is not null or (v->>'unchanged')::boolean is distinct from true or (v->>'both')::boolean is distinct from false or (v->>'promoted')::boolean is distinct from false or v->>'ask_to' is not null then v_bad := v_bad || ' ' || s || ': ' || v::text; end if;
      if r.runner_confirmed_handoff_at is not null then v_bad := v_bad || ' ' || s || ': a-stamp-was-written-after-the-handoff'; end if;
      -- the handed-off row as the product leaves it (both stamps): both=true, still silent, still nothing written
      bk2 := t_ask_bk(o, d, rt, r1, s, 'both', interval '0');
      v_stamp := (select runner_confirmed_handoff_at from bookings where id = bk2);
      v := t_chx_call(bk2, r1, 'runner');
      if v->>'raised' is not null or (v->>'unchanged')::boolean is distinct from true or (v->>'both')::boolean is distinct from true or v->>'ask_to' is not null then v_bad := v_bad || ' ' || s || '/both: ' || v::text; end if;
      if (select runner_confirmed_handoff_at from bookings where id = bk2) is distinct from v_stamp then v_bad := v_bad || ' ' || s || '/both: re-tap-moved-the-stamp'; end if;
    else
      if v->>'raised' is distinct from 'wrong_status' then v_bad := v_bad || ' ' || s || ': ' || coalesce(v->>'raised', 'accepted — ' || v::text); end if;
      if r.runner_confirmed_handoff_at is not null then v_bad := v_bad || ' ' || s || ': a-refusal-wrote-a-stamp'; end if;
    end if;
    if r.status is distinct from s then v_bad := v_bad || ' ' || s || ': status-moved-to ' || r.status; end if;
    v_note := v_note || ' ' || s;
  end loop;
  if v_bad = '' then call _pass('chx','0185-G4 상태 게이트: picked_up·active는 무동작(도장 안 씀, 묻지 않음; both는 행 그대로 — 한 도장이면 false, 두 도장이면 true); 그 밖의 비적격 상태 전부 wrong_status로 거절, 아무것도 안 쓴다 — 「안 쓴다」의 공동 소유자는 0117의 booking_handoff_stamp_guard(비적격 상태의 도장을 거절); 이 게이트가 더하는 것은 이름(wrong_status → 엣지의 한국어 409) —' || v_note);
  else v_msg := v_bad; call _fail('chx','0185-G4 status-gate', v_msg); end if;

  -- ---------- [0185-G5] THE FINDING AT THE CUSTODY TRIGGER: no custody without this pairing's two confirmations ----------
  v_bad := '';
  insert into clubs (name, district, host_profile_id) values ('chx 클럽', '반포동', r1) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point) values (v_club, r1, now() + interval '1 hour', 'chx 집결지') returning id into v_sess;
  bk := t_ask_bk(o, d5, rt, r1, 'confirmed', 'owner', interval '0', v_sess);                     -- the owner confirmed r1
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody, approval, booking_id)
  values (v_sess, d5, o, r1, 'runner_delegated', 'approved', bk) returning id into v_sd;
  -- the host re-assigns to r2 (0048's shape); r1's confirm reaches the lock after that commit
  update bookings set runner_id = r2, owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = bk;
  v := t_chx_call(bk, r1, 'runner');
  select * into r from bookings where id = bk;
  if v->>'raised' is distinct from 'not_party' then v_bad := v_bad || ' old-runner: ' || coalesce(v->>'raised', 'accepted — ' || v::text); end if;
  if r.status is distinct from 'confirmed' then v_bad := v_bad || ' status=' || r.status || ' (a pairing nobody confirmed reached ' || r.status || ')'; end if;
  if t_chx_custody(bk) <> 0 then v_bad := v_bad || ' CUSTODY-RECORDED-WITHOUT-CONFIRMATION(' || t_chx_custody(bk) || ')'; end if;
  -- (`custodian_*` on session_dogs is the ASSIGNMENT projection — 0040's axes already say 「runner」
  --  for an approved delegation with a runner, and `custody_phase` defaults to 'with_custodian' —
  --  so physical custody is only visible in the outbound custody EVENT and `checked_in_at`, which
  --  0045's trigger writes on `picked_up`: those are what must be absent here)
  if (select checked_in_at from session_dogs where id = v_sd) is not null then v_bad := v_bad || ' the-dog-was-checked-in-with-neither-confirmation'; end if;
  if (select custodian_profile_id from session_dogs where id = v_sd) is not distinct from r2 then v_bad := v_bad || ' the-new-runner-is-custodian-with-neither-confirmation'; end if;
  -- the new pairing's own handoff: two confirmations ⇒ picked_up ⇒ custody, once, for r2
  v := t_chx_call(bk, o, 'owner');
  if v->>'raised' is not null or (v->>'ask_to')::uuid is distinct from r2 then v_bad := v_bad || ' owner-confirm: ' || v::text; end if;
  v := t_chx_call(bk, r2, 'runner');
  select * into r from bookings where id = bk;
  if (v->>'promoted')::boolean is distinct from true or r.status is distinct from 'picked_up' then v_bad := v_bad || ' new-pairing-not-promoted: ' || v::text || ' status=' || r.status; end if;
  if t_chx_custody(bk) <> 1 then v_bad := v_bad || ' custody-events=' || t_chx_custody(bk) || ' (expected exactly 1)'; end if;
  if (select checked_in_at from session_dogs where id = v_sd) is null then v_bad := v_bad || ' the-genuine-handoff-did-not-check-the-dog-in'; end if;
  if (select to_profile_id from dog_custody_events e join session_dogs sd on sd.id = e.session_dog_id where sd.booking_id = bk and e.event_type = 'outbound' limit 1) is distinct from r2 then v_bad := v_bad || ' the-outbound-event-names-' || coalesce((select to_profile_id::text from dog_custody_events e join session_dogs sd on sd.id = e.session_dog_id where sd.booking_id = bk and e.event_type = 'outbound' limit 1), 'nobody') || '-not-r2'; end if;
  if (select custodian_type from session_dogs where id = v_sd) is distinct from 'runner' or (select custodian_profile_id from session_dogs where id = v_sd) is distinct from r2 or (select custody_phase from session_dogs where id = v_sd) is distinct from 'with_custodian' then v_bad := v_bad || ' custodian=' || coalesce((select custodian_profile_id::text from session_dogs where id = v_sd), 'NULL') || '/' || coalesce((select custody_phase from session_dogs where id = v_sd), 'NULL'); end if;
  if exists (select 1 from dog_custody_events e join session_dogs sd on sd.id = e.session_dog_id where sd.booking_id = bk and e.to_profile_id = r1) then v_bad := v_bad || ' the-runner-who-left-is-recorded-as-custodian'; end if;
  if v_bad = '' then call _pass('chx','0185-G5 커스터디 트리거에서 본 결론: 락 전에 재배정된 클럽 예약에 옛 러너의 확인은 not_party — picked_up 없음, 커스터디 이벤트 0, 새 러너는 보관자가 아니다; 새 짝의 두 확인이 picked_up ⇒ 아웃바운드 커스터디 정확히 1건, 보관자 = 행의 러너; 떠난 러너는 어디에도 없다');
  else v_msg := v_bad; call _fail('chx','0185-G5 custody', v_msg); end if;

  -- ---------- [0185-H1] a late answer on a no_response tick, met by a persistent unnamed fault ----------
  v_bad := '';
  create or replace function t_chx_tick_fault() returns trigger language plpgsql as $f$
  begin
    if new.id::text = current_setting('chx.fault_tick', true) and new.outcome = 'accepted' then
      raise exception 'stand-in fault %', current_setting('chx.fault_code', true) using errcode = current_setting('chx.fault_code', true);
    end if;
    return new;
  end $f$;
  create trigger t_chx_tick_fault before update on billing_key_dispatch_ticks for each row execute function t_chx_tick_fault();
  select stuck_unreadable into v_n0 from billing_key_dispatch_health;
  -- sent, never answered ⇒ no_response (0150's third state)
  select 816000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 816000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 3, v_req, now() - interval '5 minutes') returning id into t1;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-0 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'no_response' or r.resolved_at is null or (r.detail ~ 'no pg_net response') is distinct from true then v_bad := v_bad || ' fixture: ' || coalesce(r.outcome, 'NULL') || ' (expected no_response)'; end if;
  -- the late answer arrives; the read meets a persistent unnamed fault
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('chx.fault_tick', t1::text, true); perform set_config('chx.fault_code', '42883', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-1 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'sent' then v_bad := v_bad || ' after-fault: outcome=' || coalesce(r.outcome, 'NULL') || ' (a tick that WAS answered still blames the transport)'; end if;
  if r.detail is not null or r.resolved_at is not null then v_bad := v_bad || ' after-fault: the obsolete verdict was kept (detail=' || coalesce(left(r.detail, 30), '∅') || ', resolved=' || (r.resolved_at is not null)::text || ')'; end if;
  if r.response_observed_at is null or (r.reconcile_error ~ '^42883: ') is distinct from true then v_bad := v_bad || ' after-fault: observation/error=' || coalesce(r.response_observed_at::text, 'NULL') || '/' || coalesce(left(r.reconcile_error, 20), 'NULL'); end if;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from v_n0 + 1 then v_bad := v_bad || ' after-fault: stuck_unreadable=' || coalesce(v_n::text, 'NULL') || ' (expected ' || v_n0 + 1 || ' — the woken row must be counted)'; end if;
  -- the answer is deleted (retention) and the TTL passes: still sent, still counted, never no_response again
  delete from net._http_response where id = v_req;
  update billing_key_dispatch_ticks set sent_at = now() - interval '7 hours' where id = t1;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-2 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'sent' or r.reconcile_error is null then v_bad := v_bad || ' after-deletion+TTL: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(left(r.reconcile_error, 20), 'NULL'); end if;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from v_n0 + 1 then v_bad := v_bad || ' after-deletion+TTL: stuck_unreadable=' || coalesce(v_n::text, 'NULL'); end if;
  -- the answer is back and the fault clears: the verdict, at last
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('chx.fault_tick', '', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' call-3 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t1;
  if r.outcome is distinct from 'accepted' or r.claimed_count is distinct from 3 or r.reconcile_error is not null or r.resolved_at is null or r.response_observed_at is null then v_bad := v_bad || ' after-clear: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(r.claimed_count::text, 'NULL') || '/' || coalesce(r.reconcile_error, '∅') || ' (expected accepted/3, no error, resolved, observation kept)'; end if;
  select stuck_unreadable into v_n from billing_key_dispatch_health;
  if v_n is distinct from v_n0 then v_bad := v_bad || ' after-clear: stuck_unreadable=' || coalesce(v_n::text, 'NULL') || ' (expected ' || v_n0 || ')'; end if;
  -- controls: (a) a late answer READ without a fault is a verdict straight from no_response (0150's path, unchanged)
  select 816000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 816000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 2, v_req, now() - interval '5 minutes') returning id into t2;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' a-0 RAISED [' || sqlerrm || ']'; end;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":2,"revoked":2,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' a-1 RAISED [' || sqlerrm || ']'; end;
  select * into r from billing_key_dispatch_ticks where id = t2;
  if r.outcome is distinct from 'accepted' or r.claimed_count is distinct from 2 or (r.detail ~ 'no pg_net response') is not distinct from true then v_bad := v_bad || ' control-a: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(r.claimed_count::text, 'NULL') || '/' || coalesce(left(r.detail, 30), '∅'); end if;
  -- (b) a late answer met by a NAMED fault (22003) is `failed` with the reason — the no_response verdict is replaced, not kept
  select 816000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 816000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at) values ('sent', 2, v_req, now() - interval '5 minutes') returning id into t3;
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' b-0 RAISED [' || sqlerrm || ']'; end;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":2,"revoked":2,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  perform set_config('chx.fault_tick', t3::text, true); perform set_config('chx.fault_code', '22003', true);
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' b-1 RAISED [' || sqlerrm || ']'; end;
  perform set_config('chx.fault_tick', '', true);
  select * into r from billing_key_dispatch_ticks where id = t3;
  if r.outcome is distinct from 'failed' or (r.detail ~ 'could not read this answer') is distinct from true or r.resolved_at is null or r.reconcile_error is not null then v_bad := v_bad || ' control-b: ' || coalesce(r.outcome, 'NULL') || '/' || coalesce(left(r.detail, 40), '∅') || '/' || coalesce(r.reconcile_error, '∅'); end if;
  -- (c) a no_response row past the TTL, never observed, answered late is NOT re-read (0150's cutoff still holds for it)
  select 816000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 816000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at, detail, resolved_at) values ('no_response', 1, v_req, now() - interval '7 hours', 'no pg_net response within 00:02:00', now() - interval '6 hours') returning id into t4;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":1,"revoked":1,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  begin perform reconcile_billing_key_dispatch_ticks(); exception when others then v_bad := v_bad || ' c RAISED [' || sqlerrm || ']'; end;
  if (select outcome from billing_key_dispatch_ticks where id = t4) is distinct from 'no_response' then v_bad := v_bad || ' control-c: a never-observed no_response row past the TTL was re-read (' || (select outcome from billing_key_dispatch_ticks where id = t4) || ')'; end if;
  drop trigger t_chx_tick_fault on billing_key_dispatch_ticks; drop function t_chx_tick_fault();
  if v_bad = '' then call _pass('chx','0185-H1 no_response 틱에 늦은 답 + 지속되는 이름 없는 오류(42883) ⇒ sent로 깨어난다(낡은 detail·resolved_at 지움, 관찰·오류 기록, stuck_unreadable +1); 답이 지워지고 TTL이 지나도 sent·계수 유지; 답이 돌아오고 오류가 걷히면 accepted/3; 대조: 오류 없는 늦은 답은 곧장 accepted, 이름 있는 오류(22003)는 failed, 관찰 없는 TTL 지난 no_response는 안 읽는다(0150)');
  else v_msg := v_bad; call _fail('chx','0185-H1 late-answer', v_msg); end if;

  -- ---------- [0185-S1] deployed shape ----------
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'confirm_handoff_tx';
  if v_oid is null then v_bad := ' A:NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:search_path 없음'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' A:service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' A:NO-SOURCE';
    else
      if (v_src ~ 'from bookings where id = p_booking for update;') is distinct from true then v_bad := v_bad || ' A:행 락 없음'; end if;
      if (position('for update;' in v_src) > 0 and position('raise exception ''not_party''' in v_src) > 0 and position('for update;' in v_src) < position('raise exception ''not_party''' in v_src) and position('raise exception ''not_party''' in v_src) < position('update bookings' in v_src)) is distinct from true then v_bad := v_bad || ' A:순서(락→파티→쓰기) 아님'; end if;
      if (v_src ~ 'update bookings\s+set owner_confirmed_handoff_at[^;]*runner_confirmed_handoff_at[^;]*status\s+= ''picked_up''::booking_status\s+where id = p_booking\s+returning') is distinct from true then v_bad := v_bad || ' A:승격이 도장 문장에 없음'; end if;
      select count(*) into v_n from regexp_matches(v_src, '''picked_up''::booking_status', 'g');
      if v_n is distinct from 1 then v_bad := v_bad || ' A:picked_up 쓰기 ' || v_n || '개(1 기대)'; end if;
      select count(*) into v_n from regexp_matches(v_src, '>= b\.handoff_cycle_at, true\)', 'g');
      if v_n is distinct from 2 then v_bad := v_bad || ' A:경계 conjunct ' || v_n || '/2'; end if;
      if (v_src ~ 'v_promote\s+:= v_both and b\.runner_id is not null') is distinct from true then v_bad := v_bad || ' A:승격 조건 아님'; end if;
      if (v_src ~ 'coalesce\(auth\.uid\(\), p_uid\)') is distinct from true then v_bad := v_bad || ' A:auth.uid()가 p_uid를 이기지 않음'; end if;
    end if;
  end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then v_bad := v_bad || ' B:NO-FUNCTION';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:definer 아님'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
    else
      if (v_src ~ 'set outcome              = ''sent'',\s+detail               = case when outcome = ''no_response'' then null else detail end,\s+resolved_at          = case when outcome = ''no_response'' then null else resolved_at end,') is distinct from true then v_bad := v_bad || ' B:no_response를 깨우는 팔 없음'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'where id = r\.tick_id\s+and outcome in \(''sent'', ''no_response''\);', 'g');
      if v_n is distinct from 2 then v_bad := v_bad || ' B:예외 팔 CAS ' || v_n || '/2'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'response_observed_at = coalesce\(response_observed_at, now\(\)\)', 'g');
      if v_n is distinct from 3 then v_bad := v_bad || ' B:관찰 스탬프 ' || v_n || '/3'; end if;
      if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' B:판정 필터 없음'; end if;
    end if;
  end if;
  select count(*) into v_n from pg_trigger where tgrelid = 'public.bookings'::regclass and tgname in ('_handoff_cycle', 'booking_transition', 'club_custody_transition_v2') and not tgisinternal and tgenabled = 'O';
  if v_n is distinct from 3 then v_bad := v_bad || ' bookings 트리거 ' || v_n || '/3 enabled'; end if;
  if v_bad = '' then call _pass('chx','0185-S1 배포 형상: confirm_handoff_tx definer·pg_temp·service_role 전용, 락→파티 게이트→쓰기 순서, 승격은 도장 문장 안에 1회, 경계 conjunct 2, auth.uid() 우선; 리컨실러의 깨우는 팔 + 두 예외 쓰기 CAS + 0184 팔 유지; 세 트리거 enabled');
  else v_msg := v_bad; call _fail('chx','0185-S1 shape', v_msg); end if;
end $$;

drop function if exists t_chx_call(uuid, uuid, text);
drop function if exists t_chx_custody(uuid);
