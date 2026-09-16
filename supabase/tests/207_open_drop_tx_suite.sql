-- ═══ 207 — 0176's `open_drop_tx` — 0176-O1…O7, tag `odt` ═════════════════════════════════════
--
-- THE PROPOSITION THIS FILE OWNS: a drop is consumed only in a transaction that also pays it, and
-- refusals arrive in the doctrine's order — party before state, choice before consumption.
-- Backend honesty audit 2026-09-17 **H2** (the edge stamps `opened_at` with a consuming CAS and
-- pays afterwards, so one failed writer burns the drop for good under 0106 §3) and **M3** (the
-- choice validated after the CAS). 0176 is the fix; this file is its battery.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE, because a second copy would be manufactured coverage:
--   · 141 D1…D20 — the seal on `drops` / `gear_claims` (client writes refused, columns frozen,
--     `opened_at` once). 0176 does not touch it. 141 keeps owning it; its D19 sweep now carries a
--     ONE-entry allowlist for this function, reason written there, with a liveness arm.
--   · 10 D1/D2 — that `settle_run_tx` still mints. Nothing here mints; every drop is inserted as
--     the owner, exactly as 141 seeds its own.
--   · the edge handler `open-drop/index.ts` — not called here and not changed by 0176.
--
-- ─── MUTATION MAP (plants `&&`-chained to their run, against a COPY of the tree; CONTROL = the
--     VERIFY demoted to a notice with NO plant, observed clean first) — measured sets are in the
--     REGISTRY row and the commit message, NOT here, so a later pin cannot stale this block.
--   (i)   the party gate deleted            ⇒ un-demoted: APPLY ABORTS at 0176's VERIFY
--                                             (PARTY-GATE-AFTER-CAS / TOKENS-MISSING) — measures
--                                             the VERIFY, not this file (0131-G4's distinction);
--                                             demoted: O1 + O6 red, O2…O5 green.
--   (ii)  the choice check moved AFTER the CAS ⇒ demoted: O2 + O6 red (O2 by name: a refused
--                                             choice consumed the pick drop).
--   (iii) the reward block wrapped in `exception when others then null` — the H2 shape rebuilt
--                                             inside the function ⇒ demoted: O5 + O6 red; O3/O4
--                                             stay GREEN (the happy path still pays), which is what
--                                             makes O5 a measurement of atomicity and not of paying.
--   (iv)  a SECOND authenticated definer reading drops ⇒ 141 D19 red ALONE (the allowlist is one
--                                             signature, not a class).
--   (v)   the allowlisted entry DEAD (grant removed) ⇒ D19's liveness arm by name + O6 + the
--                                             permission cascade on O1…O5.
--   (vi)  the `drop_pays_nothing` arm deleted ⇒ un-demoted: APPLY ABORTS (TOKENS-MISSING);
--                                             demoted: O7 + O6 red.
--   PLANTS THAT REDDEN NOTHING, worked out rather than patched (the mutation-reddens-nothing law;
--   measured by the cold reader in its own copy, re-stated here so no later session reads a green
--   as coverage of them):
--     · the role claim removed from ① ⇒ 0 red — see ① (a gap about the SEAL, owned by 141).
--     · the `for update` deleted ⇒ 0 red, and a live two-connection race against that build still
--       paid exactly once: the CAS predicate re-evaluates under the UPDATE's own row lock. The race
--       is NOT pinned here (`90_race_check.sh` is single-purpose) — NAMED GAP.
--     · the explicit `already_opened` gate deleted ⇒ 0 red — the CAS belt raises the identical
--       token, so O3's second-tap arm cannot tell the two apart. Not a blind pin; one door.
--   The cold reader also measured, beyond this file's pins: every one of the five reward writers
--   failing in turn rolls the CAS back (O5 pins only the gear writer); O5's trigger removed ⇒ O5
--   ALONE red (its control is not vacuous); the `contents.options` conjunct deleted ⇒ O2 ALONE red.
--
-- ─── FIXTURE NOTES THAT ARE LOAD-BEARING ─────────────────────────────────────────────────────
--  ① Every call goes through the PRODUCTION door: `request.jwt.claim.sub` = the runner,
--     `request.jwt.claim.role` = 'authenticated', `set local role authenticated` — so 0106 §3 judges
--     the definer at the SERVICE tier (141 D19b), as PostgREST would. ⚠ NAMED GAP (cold review,
--     measured): deleting the role claim reddens NOTHING. Not a blind pin — at BOTH tiers the
--     trigger permits exactly what this function does (one `opened_at` stamp with `pick_choice` in
--     the same statement, no frozen column touched), and a second stamp is refused by the
--     function's OWN gate before the trigger is consulted. So this file proves nothing about the
--     seal admitting exactly one stamp at either tier; 141 D10/D12/D19b own that property. The
--     claim stays because it is the production door and costs nothing. Both claims are cleared at
--     the end.
--  ② `set local role` inside a sub-block is undone by that sub-block's rollback, so a refused
--     call leaves the session as postgres; the `reset role` after every block is belt.
--  ③ O5 injects the failing writer as a TRIGGER on `gear_claims`, created as the owner (0106
--     revoked TRIGGER from service_role, not from the owner). It is an EXECUTED fault, not a
--     source plant: the function under test is byte-identical to trunk's. The miles insert
--     PRECEDES the gear insert inside the function, so a surviving miles row would be exactly the
--     half-applied state H2 describes, and a surviving `opened_at` the burned drop. The trigger
--     and its function are dropped in the same pin, unconditionally.
--  ④ Counts are scoped by `ref_id` / `milestone` / the runner, never suite-wide: earlier suites
--     leave ledger rows behind, and the property here is per-drop.
set client_min_messages = warning;

do $$
declare
  v_a uuid; v_b uuid;
  d_open uuid; d_full uuid; d_pick_b uuid; d_pick_m uuid; d_pick_g uuid; d_narrow uuid;
  d_fail uuid; d_theirs uuid; d_zero uuid;
  v_bad text; v_msg text; v_j jsonb; v_n int; v_t timestamptz; v_pc text;
  v_src text; v_acl text; v_oid oid;
  v_boosts0 int; v_miles_b0 int;
begin
  -- ---------- shared seed, as the owner, no JWT claims (141's shape) ----------
  v_a := gen_random_uuid(); v_b := gen_random_uuid();
  insert into auth.users(id,email) values (v_a,'odt-a@t'),(v_b,'odt-b@t');
  insert into profiles(id,role,name) values (v_a,'runner','ODT-a'),(v_b,'runner','ODT-b');
  insert into runners(profile_id) values (v_a),(v_b);
  insert into drops(runner_id,kind,run_count_at,contents,opened_at)
    values (v_a,'mini',5,'{"miles":700}', now() - interval '1 day') returning id into d_open;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'mini',15,'{"miles":600,"card":"드랍 카드","gear":"기어 교환권"}') returning id into d_full;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',10,'{"options":["boost","miles","gear"]}') returning id into d_pick_b;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',20,'{"options":["boost","miles","gear"]}') returning id into d_pick_m;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',25,'{"options":["boost","miles","gear"]}') returning id into d_pick_g;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',30,'{"options":["boost","miles"]}') returning id into d_narrow;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'mini',35,'{"miles":500,"gear":"기어 교환권"}') returning id into d_fail;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_b,'mini',5,'{"miles":800}') returning id into d_theirs;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'mini',40,'{"miles":0}') returning id into d_zero;         -- pays nothing (O7)
  select count(*) into v_boosts0  from boosts       where runner_id  = v_a;
  select count(*) into v_miles_b0 from miles_ledger where profile_id = v_b;

  -- the production door (①): from here on every call carries a client JWT role
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  -- ---------- [0176-O1] party gate BEFORE state gate ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_b::text, true);
  begin
    set local role authenticated;
    perform open_drop_tx(d_open, null);                 -- B on A's OPENED drop
    v_bad := ' 남의 열린 드랍이 열렸다';
  exception when others then
    if sqlerrm <> 'not_drop_owner' then v_bad := ' 열린 남의 드랍에 party 거절이 아니라 [' || sqlerrm || ']이 왔다 (상태가 먼저 샌다)'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    perform open_drop_tx(d_full, null);                 -- B on A's UNOPENED drop
    v_bad := v_bad || ' 남의 안 열린 드랍이 열렸다';
  exception when others then
    if sqlerrm <> 'not_drop_owner' then v_bad := v_bad || ' 안 열린 남의 드랍: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  select opened_at into v_t from drops where id = d_full;
  if v_t is not null then v_bad := v_bad || ' 남이 건드린 뒤 opened_at이 찍혔다'; end if;
  select count(*) into v_n from miles_ledger where profile_id = v_b;
  if v_n <> v_miles_b0 then v_bad := v_bad || ' 남의 원장에 행이 생겼다'; end if;
  select count(*) into v_n from miles_ledger where ref_id = d_full;
  if v_n <> 0 then v_bad := v_bad || ' d_full 참조 원장 행 ' || v_n; end if;
  perform set_config('request.jwt.claim.sub', '', true);   -- no subject at all
  begin
    set local role authenticated;
    perform open_drop_tx(d_full, null);
    v_bad := v_bad || ' 로그인 없이 열렸다';
  exception when others then
    if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' 무주체: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', v_a::text, true);
  begin
    set local role authenticated;
    perform open_drop_tx(gen_random_uuid(), null);      -- the owner, on a row that does not exist
    v_bad := v_bad || ' 없는 드랍이 열렸다';
  exception when others then
    if sqlerrm <> 'drop_not_found' then v_bad := v_bad || ' 없는 id: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    perform open_drop_tx(null, null);
    v_bad := v_bad || ' NULL id가 열렸다';
  exception when others then
    if sqlerrm <> 'drop_not_found' then v_bad := v_bad || ' NULL id: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('odt','0176-O1 party 게이트가 state 게이트보다 먼저 — 남의 열린 드랍도 not_drop_owner(already_opened가 아니다), 안 열린 남의 드랍은 그대로, 무주체 not_signed_in, 없는/NULL id drop_not_found');
  else v_msg := v_bad; call _fail('odt','0176-O1 party-before-state', v_msg); end if;

  -- ---------- [0176-O2] the choice is judged BEFORE anything is consumed (M3, and H2 through the door) ----------
  v_bad := '';
  begin
    set local role authenticated;
    perform open_drop_tx(d_pick_b, 'cards');            -- outside the whitelist
    v_bad := ' 화이트리스트 밖 선택이 통과했다';
  exception when others then
    if sqlerrm <> 'bad_pick_choice' then v_bad := ' 잘못된 선택: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    perform open_drop_tx(d_pick_b, null);               -- a pick with no choice
    v_bad := v_bad || ' 선택 없는 픽이 통과했다';
  exception when others then
    if sqlerrm <> 'bad_pick_choice' then v_bad := v_bad || ' 선택 없음: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    perform open_drop_tx(d_narrow, 'gear');             -- valid word, not among THIS drop's options
    v_bad := v_bad || ' 민팅되지 않은 선택지가 통과했다';
  exception when others then
    if sqlerrm <> 'bad_pick_choice' then v_bad := v_bad || ' 미제공 선택지: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    perform open_drop_tx(d_full, 'miles');              -- a mini takes no choice
    v_bad := v_bad || ' 미니에 선택이 통과했다';
  exception when others then
    if sqlerrm <> 'bad_pick_choice' then v_bad := v_bad || ' 미니+선택: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  select opened_at, pick_choice into v_t, v_pc from drops where id = d_pick_b;
  if v_t is not null or v_pc is not null then v_bad := v_bad || ' 거절된 시도가 픽 드랍을 소모했다 (opened_at=' || coalesce(v_t::text,'null') || ' choice=' || coalesce(v_pc,'null') || ')'; end if;
  select opened_at into v_t from drops where id = d_narrow;
  if v_t is not null then v_bad := v_bad || ' 거절된 시도가 d_narrow를 소모했다'; end if;
  select opened_at into v_t from drops where id = d_full;
  if v_t is not null then v_bad := v_bad || ' 거절된 시도가 미니를 소모했다'; end if;
  select count(*) into v_n from boosts where runner_id = v_a;
  if v_n <> v_boosts0 then v_bad := v_bad || ' 거절 뒤 부스트 행 +' || (v_n - v_boosts0); end if;
  select count(*) into v_n from miles_ledger where ref_id in (d_pick_b, d_narrow, d_full);
  if v_n <> 0 then v_bad := v_bad || ' 거절 뒤 원장 행 ' || v_n; end if;
  -- and THEN the same drop opens, which is the whole point: nothing was burned
  begin
    set local role authenticated;
    v_j := open_drop_tx(d_pick_b, 'boost');
  exception when others then
    v_bad := v_bad || ' 거절 뒤 정상 선택이 실패했다 [' || sqlerrm || ']'; v_j := null;
  end;
  reset role;
  if v_j is null or (v_j ? 'boost_until') is distinct from true then v_bad := v_bad || ' applied에 boost_until이 없다 ' || coalesce(v_j::text,'null');
  elsif (v_j - 'boost_until') <> '{}'::jsonb then v_bad := v_bad || ' applied에 다른 키가 있다 ' || v_j::text; end if;
  select count(*) into v_n from boosts where runner_id = v_a
     and ends_at between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute';
  if v_n <> 1 then v_bad := v_bad || ' 24h 부스트 행이 ' || v_n || '개'; end if;
  select opened_at, pick_choice into v_t, v_pc from drops where id = d_pick_b;
  if v_t is null or v_pc is distinct from 'boost' then v_bad := v_bad || ' 정상 오픈 뒤 스탬프/선택이 틀리다 (choice=' || coalesce(v_pc,'null') || ')'; end if;
  if v_bad = '' then call _pass('odt','0176-O2 선택은 소모 전에 판정 — 화이트리스트 밖·없음·미제공·미니+선택 전부 bad_pick_choice, opened_at NULL 그대로·부스트/원장 0행, 그 뒤 boost 정상 오픈(24h 행 1개·applied {boost_until}만)');
  else v_msg := v_bad; call _fail('odt','0176-O2 choice-before-CAS', v_msg); end if;

  -- ---------- [0176-O3] a mini pays all three in ONE call, once; the second tap refuses and pays nothing ----------
  v_bad := '';
  begin
    set local role authenticated;
    v_j := open_drop_tx(d_full, null);
  exception when others then
    v_bad := ' 미니 오픈이 실패했다 [' || sqlerrm || ']'; v_j := null;
  end;
  reset role;
  if v_j is distinct from '{"miles":600,"card":"드랍 카드","gear":"기어 교환권"}'::jsonb then v_bad := v_bad || ' applied=' || coalesce(v_j::text,'null'); end if;
  select count(*) into v_n from miles_ledger where profile_id = v_a and ref_id = d_full and delta = 600 and reason = 'drop';
  if v_n <> 1 then v_bad := v_bad || ' 마일 원장 행(600/drop) ' || v_n || '개'; end if;
  select count(*) into v_n from cards_owned where profile_id = v_a and card_key = 'drop-15' and tier = '레어';
  if v_n <> 1 then v_bad := v_bad || ' 카드 행(drop-15/레어) ' || v_n || '개'; end if;
  select count(*) into v_n from gear_claims where profile_id = v_a and side = 'runner' and item = '기어 교환권' and milestone = 15 and status = 'claimable';
  if v_n <> 1 then v_bad := v_bad || ' 기어 청구 행(15/claimable) ' || v_n || '개'; end if;
  select opened_at, pick_choice into v_t, v_pc from drops where id = d_full;
  if v_t is null then v_bad := v_bad || ' opened_at이 안 찍혔다'; end if;
  if v_pc is not null then v_bad := v_bad || ' 미니에 pick_choice가 찍혔다'; end if;
  begin
    set local role authenticated;
    perform open_drop_tx(d_full, null);                 -- the second tap
    v_bad := v_bad || ' 두 번째 오픈이 통과했다';
  exception when others then
    if sqlerrm <> 'already_opened' then v_bad := v_bad || ' 두 번째 오픈: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  select count(*) into v_n from miles_ledger where ref_id = d_full;
  if v_n <> 1 then v_bad := v_bad || ' 두 번째 탭 뒤 원장 행 ' || v_n; end if;
  select count(*) into v_n from gear_claims where profile_id = v_a and milestone = 15;
  if v_n <> 1 then v_bad := v_bad || ' 두 번째 탭 뒤 기어 행 ' || v_n; end if;
  if v_bad = '' then call _pass('odt','0176-O3 미니: 마일 600(drop)·카드 drop-15 레어·기어 교환권 claimable 각 1행, applied가 정확히 그 셋, 두 번째 탭은 already_opened + 행 그대로 (이중 지급 없음)');
  else v_msg := v_bad; call _fail('odt','0176-O3 mini-pays-once', v_msg); end if;

  -- ---------- [0176-O4] pick arms: miles pays 5,000 (pick_drop), gear pays a claim; pick_choice freezes with the stamp ----------
  v_bad := '';
  begin
    set local role authenticated;
    v_j := open_drop_tx(d_pick_m, 'miles');
  exception when others then
    v_bad := ' 픽 miles 오픈 실패 [' || sqlerrm || ']'; v_j := null;
  end;
  reset role;
  if v_j is distinct from '{"miles":5000}'::jsonb then v_bad := v_bad || ' miles applied=' || coalesce(v_j::text,'null'); end if;
  select count(*) into v_n from miles_ledger where profile_id = v_a and ref_id = d_pick_m and delta = 5000 and reason = 'pick_drop';
  if v_n <> 1 then v_bad := v_bad || ' 5000/pick_drop 원장 행 ' || v_n || '개'; end if;
  select pick_choice into v_pc from drops where id = d_pick_m;
  if v_pc is distinct from 'miles' then v_bad := v_bad || ' pick_choice=' || coalesce(v_pc,'null'); end if;
  begin
    set local role authenticated;
    v_j := open_drop_tx(d_pick_g, 'gear');
  exception when others then
    v_bad := v_bad || ' 픽 gear 오픈 실패 [' || sqlerrm || ']'; v_j := null;
  end;
  reset role;
  if v_j is distinct from '{"gear":"기어 교환권"}'::jsonb then v_bad := v_bad || ' gear applied=' || coalesce(v_j::text,'null'); end if;
  select count(*) into v_n from gear_claims where profile_id = v_a and item = '기어 교환권' and milestone = 25 and status = 'claimable';
  if v_n <> 1 then v_bad := v_bad || ' 기어 청구 행(25) ' || v_n || '개'; end if;
  select count(*) into v_n from miles_ledger where ref_id = d_pick_g;
  if v_n <> 0 then v_bad := v_bad || ' gear 픽에 마일 행 ' || v_n; end if;
  if v_bad = '' then call _pass('odt','0176-O4 픽: miles → 5,000(pick_drop) 1행·applied {miles:5000}, gear → 기어 교환권 claimable 1행·applied {gear}·마일 0행, pick_choice 저장');
  else v_msg := v_bad; call _fail('odt','0176-O4 pick-arms', v_msg); end if;

  -- ---------- [0176-O5] a failing reward write rolls the CAS back — the drop is NOT consumed (H2 itself) ----------
  v_bad := '';
  create function _odt_planted_writer_fails() returns trigger language plpgsql as $f$
    begin raise exception 'odt_planted_writer_failure'; end $f$;
  create trigger _odt_planted_writer_fails_tg before insert on gear_claims
    for each row execute function _odt_planted_writer_fails();
  begin
    set local role authenticated;
    perform open_drop_tx(d_fail, null);
    v_bad := ' 기어 쓰기가 실패하도록 심었는데 오픈이 통과했다 (트리거가 안 붙었거나 예외가 삼켜졌다)';
  exception when others then
    -- CONTROL: the raise must be the planted one, or this pin measured something else entirely
    if sqlerrm <> 'odt_planted_writer_failure' then v_bad := ' 심은 실패가 아닌 이유로 멈췄다 [' || sqlerrm || ']'; end if;
  end;
  reset role;
  drop trigger _odt_planted_writer_fails_tg on gear_claims;
  drop function _odt_planted_writer_fails();
  select opened_at into v_t from drops where id = d_fail;
  if v_t is not null then v_bad := v_bad || ' 보상이 실패했는데 opened_at이 찍혔다 (드랍이 소모됐다 — H2 그대로)'; end if;
  select count(*) into v_n from miles_ledger where ref_id = d_fail;
  if v_n <> 0 then v_bad := v_bad || ' 기어 실패 뒤 마일 행이 남았다 ' || v_n || ' (반쪽 적용)'; end if;
  select count(*) into v_n from gear_claims where profile_id = v_a and milestone = 35;
  if v_n <> 0 then v_bad := v_bad || ' 실패한 기어 행이 남았다 ' || v_n; end if;
  -- and the same drop still opens, fully, once the writer works again
  begin
    set local role authenticated;
    v_j := open_drop_tx(d_fail, null);
  exception when others then
    v_bad := v_bad || ' 트리거 제거 뒤 오픈이 실패했다 [' || sqlerrm || ']'; v_j := null;
  end;
  reset role;
  if v_j is distinct from '{"miles":500,"gear":"기어 교환권"}'::jsonb then v_bad := v_bad || ' 재오픈 applied=' || coalesce(v_j::text,'null'); end if;
  select count(*) into v_n from miles_ledger where ref_id = d_fail and delta = 500 and reason = 'drop';
  if v_n <> 1 then v_bad := v_bad || ' 재오픈 마일 행 ' || v_n; end if;
  select count(*) into v_n from gear_claims where profile_id = v_a and milestone = 35 and status = 'claimable';
  if v_n <> 1 then v_bad := v_bad || ' 재오픈 기어 행 ' || v_n; end if;
  select opened_at into v_t from drops where id = d_fail;
  if v_t is null then v_bad := v_bad || ' 재오픈 뒤 opened_at이 없다'; end if;
  if v_bad = '' then call _pass('odt','0176-O5 보상 쓰기 하나가 실패하면 CAS까지 되돌아간다 — opened_at NULL·마일 0행·기어 0행, 실패 원인은 심은 그것(control), 고친 뒤 같은 드랍이 온전히 열린다');
  else v_msg := v_bad; call _fail('odt','0176-O5 atomicity', v_msg); end if;

  -- ---------- [0176-O6] deployed shape: definer · in-body search_path · ACL by value · source ORDER (comments stripped) · no swallowing handler ----------
  -- The facts 0176's VERIFY asserts at apply time, re-asserted as a PIN so a later `create or
  -- replace` that drops one of them reddens the suite and not only the next apply (0131-G4).
  v_bad := '';
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'open_drop_tx'
     and pg_get_function_identity_arguments(p.oid) = 'p_drop_id uuid, p_pick_choice text';
  if v_oid is null then v_bad := ' NO-FUNCTION(open_drop_tx(uuid,text))';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL이 기본값(PUBLIC 실행)'; end if;
    select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
    if (coalesce(v_acl, '') ~ '(^|,)=[^/]*X') is distinct from false then v_bad := v_bad || ' PUBLIC 실행 항목'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' authenticated 실행 불가 (141 D19 허용 항목이 죽었다)'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' service_role 실행 가능 (주체 없는 호출자)'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      if (position('not_drop_owner' in v_src) > 0 and position('bad_pick_choice' in v_src) > 0 and position('drop_pays_nothing' in v_src) > 0 and position('update drops' in v_src) > 0) is distinct from true then v_bad := v_bad || ' 토큰/CAS 누락'; end if;
      if (position('not_drop_owner' in v_src) < position('update drops' in v_src)) is distinct from true then v_bad := v_bad || ' party 게이트가 CAS 뒤'; end if;
      if (position('bad_pick_choice' in v_src) < position('update drops' in v_src)) is distinct from true then v_bad := v_bad || ' 선택 판정이 CAS 뒤'; end if;
      if (v_src ~* 'exception\s+when\s+others') is distinct from false then v_bad := v_bad || ' 삼키는 핸들러 (원자성 깨짐)'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('odt','0176-O6 배포 형태 — definer·본문 search_path·ACL(PUBLIC/anon/service_role ✗, authenticated ✓)·주석 제거 소스에서 party·선택 판정이 CAS 앞·삼키는 핸들러 없음');
  else v_msg := v_bad; call _fail('odt','0176-O6 deployed-shape', v_msg); end if;

  -- ---------- [0176-O7] a drop that would pay NOTHING is refused, not consumed (H2 by INACTION — cold review #3) ----------
  -- 0106's CHECK admits `{"miles":0}` on a mini and no minter produces it (0020/0025/0028/0083/0169
  -- all mint 500..1199); the edge's `if (c.miles)` would stamp it and return `{}` — a success receipt
  -- for nothing. The first arm is a FIXTURE PRECONDITION: if the CHECK ever refuses this row the
  -- pin's subject is gone and the green must not be read as coverage.
  v_bad := '';
  if _drop_contents_ok('mini', '{"miles":0}'::jsonb) is distinct from true then v_bad := ' 전제가 틀렸다: 0106 CHECK가 miles 0 미니를 거부한다 (핀의 대상이 없다)'; end if;
  begin
    set local role authenticated;
    perform open_drop_tx(d_zero, null);
    v_bad := v_bad || ' 아무것도 안 주는 드랍이 열렸다';
  exception when others then
    if sqlerrm <> 'drop_pays_nothing' then v_bad := v_bad || ' 빈 드랍: [' || sqlerrm || ']'; end if;
  end;
  reset role;
  select opened_at into v_t from drops where id = d_zero;
  if v_t is not null then v_bad := v_bad || ' 빈 드랍이 소모됐다 (opened_at 찍힘)'; end if;
  select count(*) into v_n from miles_ledger where ref_id = d_zero;
  if v_n <> 0 then v_bad := v_bad || ' 빈 드랍에 원장 행 ' || v_n; end if;
  if v_bad = '' then call _pass('odt','0176-O7 보상이 없는 드랍은 소모되지 않고 drop_pays_nothing으로 거절된다 — opened_at NULL·원장 0행 (0106 CHECK가 miles 0을 허용함을 먼저 확인)');
  else v_msg := v_bad; call _fail('odt','0176-O7 pays-nothing', v_msg); end if;

  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
