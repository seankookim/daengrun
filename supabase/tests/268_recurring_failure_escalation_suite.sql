-- ═══ 268 — 0237: a recurring series that keeps failing reaches an operator — one ring per failure
-- ═══        EPISODE, recovery resets it, the ring can neither abort the tick nor be forged silent
-- ═══        0237-C1 · E1 · E2 · E3 · E4 · E5 · E6 · E7 · B1 · S1, tag `rfe`
--
-- Codex wave-4 s1 (high): a series that fails every tick is recorded (0227) and warned, the tick
-- succeeds, and nothing escalates. This file was RUN AGAINST 0232's body (0237 removed) before 0237
-- existed; what it measured there is in the REGISTRY row (short form: E1 red — six failing ticks, zero
-- ops rows).
--
-- THE PROPOSITIONS, each stated without reference to any mutation:
--   · C1 **AN OPERATOR CAN BE SEATED AT THE NEW DESK FROM THE PRODUCT.** A `payout_due` operator's
--        `ops_roster_set(<p>, 'recurring_generation_failed', true)` answers changed = true and the person
--        is then a recipient; a near-miss class name is `unknown_class`.
--   · E1 **A PERSISTENTLY FAILING SERIES RINGS THE ROSTER EXACTLY ONCE PER EPISODE.** A series whose rule
--        cannot be read fails six ticks in a row: after ticks 1–2 there is NO ring, after tick 3 exactly ONE
--        `system` row to the one seated operator (title constant, `ref_id` = the series, a body naming
--        nobody), and ticks 4–6 add none; the owner gets no ops row. The record reads episode 6, rung.
--   · E2 **A HEALTHY SERIES IS UNAFFECTED.** Beside it in the same six ticks, a healthy series mints
--        exactly one booking and its one 「반복 러닝 예약 생성」, has no failure row and no ring.
--   · E3 **RECOVERY RESETS THE EPISODE; A NEW FAILURE EPISODE RINGS AGAIN.** The rule is repaired → the
--        next tick MINTS the series' booking and the record reads episode 0, not rung; the rule breaks
--        again → two failing ticks add no ring, the third adds exactly one more (two in total), a fourth
--        adds none.
--   · E4 **A FAULT IN THE RING NEVER ABORTS THE TICK.** With the ring's own insert made to raise (a
--        planted trigger — asserted armed on a direct insert first) the series' third failing tick: the
--        call RETURNS, a healthy sibling in the same tick mints, the failure record reads episode 3 and
--        NOT rung, and no ring row exists; with the plant lifted the next failing tick rings once.
--   · E5 **A FAULT IN THE RECOVERY RESET NEVER COSTS THE MINT.** With the reset UPDATE made to raise
--        (planted, asserted armed) a series that failed once is repaired: the call returns and the series
--        holds exactly one booking and its notice; the record still reads episode 1 (the plant fired
--        inside the reset's own block and only there).
--   · E6 **NO CLIENT CAN FORGE THE RING SILENT.** Before a series reaches its third failure, three
--        signed-in clients — a stranger, the series' OWNER and the SEATED OPERATOR — each rewrite one of
--        their own rows through `noti self update` (0002, USING-only; the world production ships,
--        asserted: each UPDATE lands exactly one row) to kind `system`, the ring's title, `ref_id` = the
--        series, created 2000-01-01. The third failure still rings: the operator's REAL ring rows move by
--        exactly +1 and the record reads rung. (The operator's forged row is the residue 0233/0234's
--        notifications-keyed idiom named; this key has no such door.) Rolled back after measuring.
--   · E7 **AN EMPTY ROSTER PAGES NOBODY AND IS RETRIED.** Every `recurring_generation_failed` row off:
--        three failing ticks write no ring and the record stays NOT rung (episode 3); the operator is
--        re-seated → the next failing tick rings once; the one after adds none.
--   · B1 **THE WRITTEN TITLE IS LEDGERED** — in `_noti_ops_titles()`, `ops` category, not urgent;
--        measured on what the ring actually wrote.
--   · S1 **DEPLOYED SHAPE.** The ring is a definer with its in-body search_path that no client can
--        execute; comment-stripped, it names the class as a routing constant and reads NO notifications
--        row (its key is `escalated_at`); in the generator the ring call and the recovery reset each sit
--        in their OWN `begin … exception` block, the ring after the failure record and the reset after
--        the mint; the three episode columns exist; `ops_roster_set` names the class.
--
-- ─── GAPS (prose — the harness cannot reach these; no pin is written for them) ───
--   · Every tick here shares ONE `now()` (one DO block = one transaction), so `episode_started_at`'s
--     preservation across ticks (the `coalesce`) is not observable; E3 pins only that a reset clears it
--     and a new failure sets it. The ring's `for update` and the overlapping-tick residue (0237 §0e)
--     need two sessions.
--   · The WARNING lines (the ring's, an empty roster's, a failed ring's, a failed reset's) are log lines;
--     SQL cannot read its own warnings. The durable halves are the record's columns, pinned here.
--   · Nothing here pushes (`00_shim.sql` stubs `net.http_post`).
--   · Two conjuncts are NOT separately observable and are named rather than pinned: the reset's
--     `(episode_failures > 0 or escalated_at is not null)` only skips rewriting a row that is already
--     reset (deleting it changes no value anywhere), and the ring's `if not found then return 0` is
--     subsumed by the fail-closed `(…) is not true` test right below it (a missing row makes that
--     predicate NULL, which also returns 0). MEASURED (battery M15/M16): deleting the filter reddens no
--     BEHAVIOURAL pin — only S1's shape regex (which spells the statement) and 161 P4's digest; deleting
--     the early return reddens nothing at all. A fact about the code, not a blind pin.
--
-- ─── BATTERY (lab copies of this tree, control 1632/0 first; every plant asserted landed and
--     `&&`-gated to its run; 161 P4 = the generator digest, red on any generator byte) ───
--   M1  ring key: drop `escalated_at is null`            → 1628/4  E1 · E3 · E7 · S1
--   M2  ring: drop the `>= c_ring_at` threshold           → 1629/3  E1 · E3 · E6
--   M3  ring: never stamp escalated_at                    → 1627/5  E1 · E3 · E4 · E6 · E7
--   M4  ring: stamp even when nobody was paged            → 1631/1  E7
--   M5  reset matches nothing (`and false`)               → 1629/3  E3 · S1 · P4
--   M6  failure upsert stops counting (VERIFY arm off)    → 1625/7  E1 · E3 · E4 · E6 · E7 · B1 · P4
--   M6v same, VERIFY left in                              → apply ABORTED at 0237 VERIFY (measures the VERIFY)
--   M7  ring call not in its own block                    → 1629/3  E4 · S1 · P4
--   M8  reset not in its own block                        → 1629/3  E5 · S1 · P4
--   M9  one-shot keyed on notifications (0233/0234 idiom) → 1629/3  E6 · E3 · S1
--   M10 reset written as an upsert                        → 1628/4  E2 · S1 · 258 0227-V1 · P4
--   M11 reset keeps episode_started_at (VERIFY arms off)  → 1629/3  E3 · S1 · P4
--   M12 ring addressed to return_strand                   → 1626/6  E1 · E3 · E4 · E6 · E7 · S1
--   M13 ring `security invoker` (VERIFY arm off)          → 1631/1  S1
--   M13v same, VERIFY left in                             → apply ABORTED at 0237 VERIFY
--   M14 ring's revoke deleted (VERIFY arms off)           → 1629/3  S1 · 98 H9 · 99 S1 (anon-execute)
--   M15 reset's no-op filter deleted                      → 1630/2  S1 · P4 (named above)
--   M16 ring's not-found early return deleted             → 1632/0  (named above)
--   M17 reset loses `series_id = s.id`                    → 1628/4  E1 · E4 · S1 · P4
--   Pre-0237 reproduction (0237 removed, same suites): 1617/15 — E1 read rings {0,0,0,0,0,0}; 9 of this
--   file's 10 pins red (E2 green — a healthy series was never the defect).
--
-- ─── FIXTURE NOTES ───
--  ① The persistent fault is a MALFORMED RULE (`weekdays: ['x']` → 22P02 at the first statement of the
--     series' block): it fails every tick regardless of the minting window, which is the realistic shape
--     of 「fails forever」, and repairing the rule is a real recovery (the next tick mints).
--  ② Each phase's series is created UNPAUSED only for its phase and paused after, and every count is
--     scoped to this suite's series and owners — the generator is global (earlier suites' series run too).
--  ③ `recurring_generation_failed` is NEW, but 239 `0208-C1` seats a subject at EVERY allowlisted class,
--     so an earlier suite can leave an active row. This suite saves every active row of the class,
--     switches them off, and restores them at the end (265's fixture note ①).
--  ④ The two fault triggers and their table are dropped in statements of their own after the block.
--  ⑤ New columns are read through `to_jsonb(row)`, so on a tree without 0237 the pins FAIL by message
--     instead of the file dying at a missing column.
--  ⑥ F's dog sorts before H's (roles swapped if the random ids came out the other way), so H's mint in
--     tick 1 happens while F already holds an episode — E1 then also sees a reset that lost its
--     `series_id = s.id` key (it would zero F's episode and shift the ring to tick 4).
set client_min_messages = warning;

-- ---------- the fault plants (dropped at the end of this file) ----------
create table if not exists t_rfe_faults (series_id uuid not null, what text not null);
create or replace function t_rfe_fault_ring() returns trigger language plpgsql as $f$
begin
  if new.title = '반복 예약 생성 실패 — 확인 필요' and new.kind = 'system'
     and exists (select 1 from t_rfe_faults f where f.series_id = new.ref_id and f.what = 'ring') then
    raise exception 'rfe stand-in: the ring cannot be written (ring)' using errcode = 'insufficient_resources';
  end if;
  return new;
end $f$;
drop trigger if exists t_rfe_fault_ring on notifications;
create trigger t_rfe_fault_ring before insert on notifications for each row execute function t_rfe_fault_ring();
create or replace function t_rfe_fault_reset() returns trigger language plpgsql as $f$
begin
  if (to_jsonb(new)->>'episode_failures') = '0' and coalesce((to_jsonb(old)->>'episode_failures')::int, 0) > 0
     and exists (select 1 from t_rfe_faults f where f.series_id = new.series_id and f.what = 'reset') then
    raise exception 'rfe stand-in: the episode cannot be reset (reset)' using errcode = 'insufficient_resources';
  end if;
  return new;
end $f$;
do $$ begin
  if to_regclass('public.recurring_generation_failures') is not null then
    execute 'drop trigger if exists t_rfe_fault_reset on recurring_generation_failures';
    execute 'create trigger t_rfe_fault_reset before update on recurring_generation_failures
             for each row execute function t_rfe_fault_reset()';
  end if;
end $$;

-- one tick of the hourly generator: NULL, or what it raised
create or replace function t_rfe_tick() returns text language plpgsql as $$
begin
  perform generate_recurring_bookings();
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;

-- the ring's rows for a series (kind system, the ring's title, ref = the series)
create or replace function t_rfe_rings(p_series uuid) returns int language sql as $$
  select count(*)::int from notifications
   where ref_id = p_series and kind = 'system' and title = '반복 예약 생성 실패 — 확인 필요'
$$;

-- the failure record, whole row (⑤: no compile-time column reference)
create or replace function t_rfe_rec(p_series uuid) returns jsonb language sql as $$
  select to_jsonb(f) from recurring_generation_failures f where f.series_id = p_series
$$;

create or replace function t_rfe_series(p_owner uuid, p_dog uuid, p_rule jsonb) returns uuid
language sql as $$
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (p_owner, p_dog, p_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id
$$;

-- ops_roster_set as ONE caller
create or replace function t_rfe_seat_as(p_uid uuid, p_profile uuid, p_class text, p_active boolean)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select to_jsonb(x) into v from ops_roster_set(p_profile, p_class, p_active) x;
    perform set_config('request.jwt.claim.sub', '', true);
    return v;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_rfe_src(p_name text) returns text
language sql stable as $$
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

do $$
declare
  T constant text := '반복 예약 생성 실패 — 확인 필요';
  CLS constant text := 'recurring_generation_failed';
  opsP uuid; opsR uuid; sx uuid;
  oF uuid; oH uuid; oK uuid; oK2 uuid; oM uuid; oG uuid; oZ uuid;
  dF uuid; dH uuid; dK uuid; dK2 uuid; dM uuid; dG uuid; dZ uuid;
  sF uuid; sH uuid; sK uuid; sK2 uuid; sM uuid; sG uuid; sZ uuid; v_mine uuid[] := '{}';
  v_rule jsonb; v_bad_rule jsonb; v_tom int; v_saved uuid[];
  v jsonb; v_bad text; v_msg text; v_err text; v_errs text := ''; v_n int; v_n2 int; v_txt text;
  v_rings int[] := '{}'; v_body text; v_seated boolean := false; v_tmp_u uuid;
  r record; v_src text; v_oid oid;
  -- E3
  e3_err text; e3_mint int; e3_rec jsonb; e3_rings int[] := '{}'; e3_rec2 jsonb;
  -- E4
  e4_arm text; e4_err text; e4_rec jsonb; e4_rings int; e4_sib int; e4_err2 text; e4_rings2 int; e4_rec2 jsonb;
  -- E5
  e5_arm text; e5_err text; e5_book int; e5_note int; e5_rec jsonb;
  -- E6
  e6_err text; e6_upd_sx int; e6_upd_o int; e6_upd_op int; e6_before int; e6_after int; e6_rec jsonb;
  e6_n1 uuid; e6_n2 uuid; e6_n3 uuid; e6_pre12 int;
  -- E7
  e7_err text; e7_rings0 int; e7_rec0 jsonb; e7_rings1 int; e7_rings2 int; e7_rec1 jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  v_tom := (extract(dow from (now() at time zone 'Asia/Seoul'))::int + 1) % 7;
  -- tomorrow 12:00 KST: between 12 h and 36 h away — inside the 72 h window, past the 2 h floor
  v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_tom), 'time', '12:00');
  v_bad_rule := jsonb_build_object('weekdays', jsonb_build_array('x'), 'time', '12:00');   -- ① 22P02

  opsP := t_user('rfe_ops_pay', 'owner');
  opsR := t_user('rfe_ops_rec', 'owner');
  sx   := t_user('rfe_stranger', 'owner');
  oF := t_user('rfe_oF', 'owner'); dF := t_dog(oF, 'rfe견F');
  oH := t_user('rfe_oH', 'owner'); dH := t_dog(oH, 'rfe견H');
  -- ⑥ H must come AFTER F in the loop's own order (`order by dog_id, id`), so H's mint in tick 1 lands
  --   while F already holds an episode — the only order in which a reset that forgot its series key
  --   would be observable (E1). Swap the two owners' roles if the random ids came out the other way.
  if dH < dF then
    v_tmp_u := oF; oF := oH; oH := v_tmp_u;
    v_tmp_u := dF; dF := dH; dH := v_tmp_u;
  end if;
  oK := t_user('rfe_oK', 'owner'); dK := t_dog(oK, 'rfe견K');
  oK2 := t_user('rfe_oK2', 'owner'); dK2 := t_dog(oK2, 'rfe견K2');
  oM := t_user('rfe_oM', 'owner'); dM := t_dog(oM, 'rfe견M');
  oG := t_user('rfe_oG', 'owner'); dG := t_dog(oG, 'rfe견G');
  oZ := t_user('rfe_oZ', 'owner'); dZ := t_dog(oZ, 'rfe견Z');
  -- a card for every owner, so the no-card gate cannot be what stops a mint if charging is live
  insert into billing_keys (profile_id, billing_key, card)
  select p, 'bkey_rfe_' || left(p::text, 8), jsonb_build_object('brand', '신한', 'last4', '4242')
    from unnest(array[oF, oH, oK, oK2, oM, oG, oZ]) p;
  -- the console operator, bootstrapped by INSERT (0208 §0: the first operator is psql by construction)
  insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;
  -- ③ this suite's roster world, restored at the end
  select coalesce(array_agg(profile_id), '{}') into v_saved
    from ops_recipients where event_class = CLS and active;
  update ops_recipients set active = false where event_class = CLS and active;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-C1] the new class is seatable through the product's door
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if exists (select 1 from ops_recipients where event_class = CLS and active)
      then v_bad := v_bad || ' FIXTURE: the class still has an active row after neutralising'; end if;
    v := t_rfe_seat_as(opsP, opsR, CLS, true);
    if (v->>'changed') is distinct from 'true' then v_bad := v_bad || ' seat: ' || coalesce(v::text, 'NULL'); end if;
    if (select count(*) from ops_recipients_for(CLS) x where x = opsR) is distinct from 1::bigint
      then v_bad := v_bad || ' the seated operator is not a recipient'; end if;
    if (t_rfe_seat_as(opsP, opsR, 'recurring_generation_fail', true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' a near-miss class was not unknown_class'; end if;
    if v_bad = '' then call _pass('rfe','0237-C1 payout_due 운영자가 ops_roster_set으로 recurring_generation_failed 자리에 사람을 앉힐 수 있다(changed=true, 수신자가 됨); 비슷한 오타 클래스는 unknown_class');
    else v_msg := v_bad; call _fail('rfe','0237-C1 recurring_generation_failed seatable', v_msg); end if;
  exception when others then call _fail('rfe','0237-C1 recurring_generation_failed seatable', sqlerrm); end;
  -- every later pin needs ONE seated recipient; on a tree whose allowlist refuses the class (the
  -- pre-0237 reproduction) seat by INSERT, which the table accepts, so E1's zero means 「nothing rang」
  -- and not 「nobody was there to ring」
  if not exists (select 1 from ops_recipients where event_class = CLS and profile_id = opsR and active) then
    insert into ops_recipients (profile_id, event_class, active) values (opsR, CLS, true)
    on conflict (profile_id, event_class) do update set active = true;
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- PHASE 1 — F (malformed rule) and H (healthy), six ticks, then F repaired and broken again
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  sF := t_rfe_series(oF, dF, v_bad_rule);
  sH := t_rfe_series(oH, dH, v_rule);
  v_mine := v_mine || sF || sH;
  for i in 1..6 loop
    v_err := t_rfe_tick();
    if v_err is not null then v_errs := v_errs || ' tick' || i || ': ' || v_err; end if;
    v_rings := v_rings || t_rfe_rings(sF);
  end loop;

  -- [0237-E1] a persistently failing series rings exactly once per episode
  begin
    v_bad := '';
    select count(*)::int into v_n from ops_recipients_for(CLS);
    if v_n is distinct from 1 then v_bad := v_bad || ' FIXTURE: roster=' || v_n || ' (1 expected)'; end if;
    if v_errs <> '' then v_bad := v_bad || ' 🔴 a tick RAISED:' || v_errs; end if;
    if (dF < dH) is not true then v_bad := v_bad || ' FIXTURE: F is not before H in the loop order'; end if;
    if (t_rfe_rec(sF)->>'attempts')::int is distinct from 6
      then v_bad := v_bad || ' FIXTURE: F did not fail all six ticks (attempts=' || coalesce(t_rfe_rec(sF)->>'attempts', 'NULL') || ') — the pin has no subject'; end if;
    if v_rings is distinct from array[0,0,1,1,1,1]
      then v_bad := v_bad || ' 🔴 rings per tick=' || v_rings::text || ' (expected {0,0,1,1,1,1}: nothing before the third failure, one at it, none after)'; end if;
    select count(*)::int into v_n from notifications where ref_id = sF and kind = 'system' and title = T and profile_id = opsR;
    if v_n is distinct from 1 then v_bad := v_bad || ' the operator''s ring rows=' || v_n; end if;
    if exists (select 1 from notifications where ref_id = sF and title = T and profile_id <> opsR)
      then v_bad := v_bad || ' 🔴 someone other than the seated operator got the ring'; end if;
    select body into v_body from notifications where ref_id = sF and title = T limit 1;
    if v_body is null or position(sF::text in v_body) > 0 or position('rfe_oF' in v_body) > 0
       or position('rfe견F' in v_body) > 0
      then v_bad := v_bad || ' the body is missing or names something: ' || coalesce(v_body, 'NULL'); end if;
    if (t_rfe_rec(sF)->>'episode_failures')::int is distinct from 6 or (t_rfe_rec(sF)->>'escalated_at') is null
      then v_bad := v_bad || ' the record does not read episode 6, rung: ' || coalesce(t_rfe_rec(sF)::text, 'NULL'); end if;
    if v_bad = '' then call _pass('rfe','0237-E1 계속 실패하는 시리즈는 에피소드당 정확히 한 번 울린다 — 규칙을 읽을 수 없는 시리즈가 여섯 틱 연속 실패: 1·2틱 0행, 3틱에 앉은 운영자 1인에게 system 1행(고정 제목, ref_id = 시리즈, 본문은 아무것도 이름 짓지 않음), 4~6틱 추가 0; 보호자에게는 0; 기록은 에피소드 6·울림');
    else v_msg := v_bad; call _fail('rfe','0237-E1 one ring per failure episode', v_msg); end if;
  exception when others then call _fail('rfe','0237-E1 one ring per failure episode', sqlerrm); end;

  -- [0237-E2] a healthy series beside it is unaffected
  begin
    v_bad := '';
    if v_errs <> '' then v_bad := v_bad || ' a tick raised (E1 owns this):' || v_errs; end if;
    select count(*)::int into v_n from bookings where series_id = sH;
    if v_n is distinct from 1 then v_bad := v_bad || ' 🔴 the healthy series holds ' || v_n || ' bookings after six ticks (1 expected)'; end if;
    select count(*)::int into v_n from notifications where profile_id = oH and title = '반복 러닝 예약 생성';
    if v_n is distinct from 1 then v_bad := v_bad || ' its 반복 러닝 예약 생성 rows=' || v_n; end if;
    if t_rfe_rec(sH) is not null then v_bad := v_bad || ' 🔴 the healthy series has a failure row: ' || t_rfe_rec(sH)::text; end if;
    if exists (select 1 from notifications where ref_id = sH and kind = 'system')
      then v_bad := v_bad || ' 🔴 the healthy series rang the roster'; end if;
    if v_bad = '' then call _pass('rfe','0237-E2 건강한 시리즈는 영향이 없다 — 같은 여섯 틱에서 예약 정확히 1건과 「반복 러닝 예약 생성」 1행, 실패 행 없음, 운영 벨 없음');
    else v_msg := v_bad; call _fail('rfe','0237-E2 a healthy series is unaffected', v_msg); end if;
  exception when others then call _fail('rfe','0237-E2 a healthy series is unaffected', sqlerrm); end;

  -- [0237-E3] recovery resets the episode; a new failure episode rings again
  begin
    v_bad := ''; e3_err := null;
    update recurring_series set rule = v_rule where id = sF;              -- repaired
    e3_err := t_rfe_tick();
    select count(*)::int into e3_mint from bookings where series_id = sF;
    e3_rec := t_rfe_rec(sF);
    update recurring_series set rule = v_bad_rule where id = sF;          -- broken again
    for i in 1..4 loop
      v_err := t_rfe_tick();
      if v_err is not null then e3_err := coalesce(e3_err, '') || ' tick' || i || ': ' || v_err; end if;
      e3_rings := e3_rings || t_rfe_rings(sF);
      if i = 1 then e3_rec2 := t_rfe_rec(sF); end if;
    end loop;
    if e3_err is not null then v_bad := v_bad || ' 🔴 a tick raised: ' || e3_err; end if;
    if e3_mint is distinct from 1 then v_bad := v_bad || ' FIXTURE: the repaired series did not mint exactly one booking (' || coalesce(e3_mint::text, 'NULL') || ') — the pin has no subject'; end if;
    if (e3_rec->>'episode_failures')::int is distinct from 0 or (e3_rec->>'escalated_at') is not null
       or (e3_rec->>'episode_started_at') is not null
      then v_bad := v_bad || ' 🔴 a MINT did not reset the episode: ' || coalesce(e3_rec::text, 'NULL'); end if;
    if (e3_rec->>'attempts')::int is distinct from 6 then v_bad := v_bad || ' the lifetime count moved on a mint: ' || coalesce(e3_rec->>'attempts', 'NULL'); end if;
    if (e3_rec2->>'episode_failures')::int is distinct from 1 or (e3_rec2->>'episode_started_at') is null
      then v_bad := v_bad || ' the first failure after the mint did not start a new episode: ' || coalesce(e3_rec2::text, 'NULL'); end if;
    if e3_rings is distinct from array[1,1,2,2]
      then v_bad := v_bad || ' 🔴 rings per tick of the new episode=' || e3_rings::text || ' (expected {1,1,2,2}: a second ring at its third failure, none before or after)'; end if;
    if v_bad = '' then call _pass('rfe','0237-E3 회복은 에피소드를 되돌리고 새 실패 에피소드는 다시 울린다 — 규칙을 고치면 다음 틱이 예약을 발행하고 기록은 에피소드 0·안 울림·시작 시각 NULL(평생 횟수는 그대로), 다시 깨지면 첫 실패가 에피소드 1을 시작하고 두 틱은 추가 0, 세 번째에 정확히 1(총 2), 네 번째는 0');
    else v_msg := v_bad; call _fail('rfe','0237-E3 recovery resets the episode', v_msg); end if;
  exception when others then call _fail('rfe','0237-E3 recovery resets the episode', sqlerrm); end;
  update recurring_series set paused = true where id in (sF, sH);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-E4] a fault in the ring never aborts the tick
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    sK := t_rfe_series(oK, dK, v_bad_rule);
    v_mine := v_mine || sK;
    insert into t_rfe_faults values (sK, 'ring');
    -- CONTROL: the plant fires on a direct insert (a plant that never fires reads as 「contained」)
    e4_arm := null;
    begin
      insert into notifications (profile_id, kind, title, body, ref_id) values (opsR, 'system', T, 'rfe plant control', sK);
      e4_arm := 'NOT-ARMED';
      raise exception using errcode = 'P0001', message = 'rfe-arm-rollback';
    exception
      when insufficient_resources then e4_arm := 'armed';
      when others then if sqlerrm is distinct from 'rfe-arm-rollback' then e4_arm := 'ERR ' || sqlerrm; end if;
    end;
    for i in 1..2 loop perform t_rfe_tick(); end loop;
    -- the third failing tick — the ring raises inside it — with a healthy sibling due in the SAME tick
    sK2 := t_rfe_series(oK2, dK2, v_rule);
    v_mine := v_mine || sK2;
    e4_err := t_rfe_tick();
    e4_rec := t_rfe_rec(sK); e4_rings := t_rfe_rings(sK);
    select count(*)::int into e4_sib from bookings where series_id = sK2;
    delete from t_rfe_faults where series_id = sK and what = 'ring';
    e4_err2 := t_rfe_tick();
    e4_rings2 := t_rfe_rings(sK); e4_rec2 := t_rfe_rec(sK);

    if e4_arm is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the ring plant did not fire on a direct insert (' || coalesce(e4_arm, 'NULL') || ')'; end if;
    if e4_err is not null then v_bad := v_bad || ' 🔴 the tick RAISED — a failing ring took the whole tick: ' || e4_err; end if;
    if e4_sib is distinct from 1 then v_bad := v_bad || ' 🔴 the healthy sibling in the same tick holds ' || coalesce(e4_sib::text, 'NULL') || ' bookings (1 expected)'; end if;
    if (e4_rec->>'episode_failures')::int is distinct from 3 or (e4_rec->>'escalated_at') is not null
      then v_bad := v_bad || ' 🔴 the failure record under a failed ring is not episode 3 / NOT rung: ' || coalesce(e4_rec::text, 'NULL'); end if;
    if e4_rings is distinct from 0 then v_bad := v_bad || ' CONTROL: a ring row landed although its insert was faulted (' || coalesce(e4_rings::text, 'NULL') || ')'; end if;
    if e4_err2 is not null then v_bad := v_bad || ' the tick after the fault lifted raised: ' || e4_err2; end if;
    if e4_rings2 is distinct from 1 or (e4_rec2->>'escalated_at') is null
      then v_bad := v_bad || ' 🔴 once the fault lifted the next failing tick did not ring once (' || coalesce(e4_rings2::text, 'NULL') || ', ' || coalesce(e4_rec2::text, 'NULL') || ')'; end if;
    if v_bad = '' then call _pass('rfe','0237-E4 벨의 결함은 틱을 멈추지 않는다 — 벨 insert가 터지게 심은 상태(직접 insert로 무장 확인)에서 세 번째 실패 틱: 호출은 반환되고 같은 틱의 건강한 형제는 발행되며 실패 기록은 에피소드 3·안 울림, 벨 행 0; 심은 것을 치우면 다음 실패 틱이 정확히 1번 울린다');
    else v_msg := v_bad; call _fail('rfe','0237-E4 a ring fault never aborts the tick', v_msg); end if;
  exception when others then call _fail('rfe','0237-E4 a ring fault never aborts the tick', sqlerrm); end;
  update recurring_series set paused = true where id = any(v_mine);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-E5] a fault in the recovery reset never costs the mint
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    sM := t_rfe_series(oM, dM, v_bad_rule);
    v_mine := v_mine || sM;
    perform t_rfe_tick();                                   -- one failure: episode 1
    insert into t_rfe_faults values (sM, 'reset');
    e5_arm := null;
    begin
      execute 'update recurring_generation_failures set episode_failures = 0 where series_id = $1' using sM;
      e5_arm := 'NOT-ARMED';
      raise exception using errcode = 'P0001', message = 'rfe-arm-rollback';
    exception
      when insufficient_resources then e5_arm := 'armed';
      when others then if sqlerrm is distinct from 'rfe-arm-rollback' then e5_arm := 'ERR ' || sqlerrm; end if;
    end;
    update recurring_series set rule = v_rule where id = sM;  -- repaired: this tick mints
    e5_err := t_rfe_tick();
    select count(*)::int into e5_book from bookings where series_id = sM;
    select count(*)::int into e5_note from notifications where profile_id = oM and title = '반복 러닝 예약 생성';
    e5_rec := t_rfe_rec(sM);
    delete from t_rfe_faults where series_id = sM;

    if e5_arm is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the reset plant did not fire on a direct update (' || coalesce(e5_arm, 'NULL') || ')'; end if;
    if e5_err is not null then v_bad := v_bad || ' 🔴 the tick RAISED — a failing reset took the tick: ' || e5_err; end if;
    if e5_book is distinct from 1 or e5_note is distinct from 1
      then v_bad := v_bad || ' 🔴 the mint did not stand under a failing reset (bookings=' || coalesce(e5_book::text, 'NULL') || ' notices=' || coalesce(e5_note::text, 'NULL') || ')'; end if;
    if (e5_rec->>'episode_failures')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL: the record does not read episode 1 — the reset plant did not fire inside the generator, or no reset ran (' || coalesce(e5_rec::text, 'NULL') || ')'; end if;
    if v_bad = '' then call _pass('rfe','0237-E5 회복 리셋의 결함은 발행을 잃게 하지 않는다 — 리셋 UPDATE가 터지게 심은 상태(직접 update로 무장 확인)에서 한 번 실패한 시리즈를 고치면: 호출은 반환되고 예약 1건과 알림 1행이 남으며, 기록은 에피소드 1 그대로(심은 것이 리셋 자기 블록 안에서만 터졌다)');
    else v_msg := v_bad; call _fail('rfe','0237-E5 a reset fault never costs the mint', v_msg); end if;
  exception when others then call _fail('rfe','0237-E5 a reset fault never costs the mint', sqlerrm); end;
  update recurring_series set paused = true where id = any(v_mine);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-E6] no client can forge the ring silent (rolled back after measuring)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; e6_err := null;
    begin
      sG := t_rfe_series(oG, dG, v_bad_rule);
      perform t_rfe_tick(); perform t_rfe_tick();                  -- episode 2: not yet rung
      select t_rfe_rings(sG) into e6_pre12;
      -- each forger's OWN pre-existing row (written as the table owner, like any product row)
      insert into notifications (profile_id, kind, title, body) values (sx,   'booking', 'rfe e6 a', 'x') returning id into e6_n1;
      insert into notifications (profile_id, kind, title, body) values (oG,   'booking', 'rfe e6 b', 'x') returning id into e6_n2;
      insert into notifications (profile_id, kind, title, body) values (opsR, 'booking', 'rfe e6 c', 'x') returning id into e6_n3;
      -- as authenticated clients under RLS: kind system, the ring's title, the series, 2000-01-01
      perform set_config('request.jwt.claim.sub', sx::text, true);
      set local role authenticated;
      if current_user <> 'authenticated' then raise exception 'e6: role did not take'; end if;
      update notifications set kind = 'system', title = T, ref_id = sG, created_at = '2000-01-01' where id = e6_n1;
      get diagnostics e6_upd_sx = row_count;
      reset role;
      perform set_config('request.jwt.claim.sub', oG::text, true);
      set local role authenticated;
      update notifications set kind = 'system', title = T, ref_id = sG, created_at = '2000-01-01' where id = e6_n2;
      get diagnostics e6_upd_o = row_count;
      reset role;
      -- the SEATED operator — the residue 0233/0234's notifications-keyed idiom could not close
      perform set_config('request.jwt.claim.sub', opsR::text, true);
      set local role authenticated;
      update notifications set kind = 'system', title = T, ref_id = sG, created_at = '2000-01-01' where id = e6_n3;
      get diagnostics e6_upd_op = row_count;
      reset role;
      perform set_config('request.jwt.claim.sub', '', true);
      -- the operator's rows of this shape BEFORE the third failure (the forged one included)
      select count(*)::int into e6_before from notifications
       where ref_id = sG and kind = 'system' and title = T and profile_id = opsR;
      perform t_rfe_tick();                                         -- the third failure
      select count(*)::int into e6_after from notifications
       where ref_id = sG and kind = 'system' and title = T and profile_id = opsR;
      e6_rec := t_rfe_rec(sG);
      raise exception 'rfe_e6_rollback';
    exception when others then
      if sqlerrm is distinct from 'rfe_e6_rollback' then e6_err := sqlerrm; end if;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    if e6_err is not null then v_bad := v_bad || ' staging raised: ' || e6_err; end if;
    -- the fixture world starts where production starts: the forging door is OPEN
    if e6_upd_sx is distinct from 1 or e6_upd_o is distinct from 1 or e6_upd_op is distinct from 1
      then v_bad := v_bad || ' FIXTURE: a forging update did not land (' || coalesce(e6_upd_sx::text, 'NULL') || '/'
                   || coalesce(e6_upd_o::text, 'NULL') || '/' || coalesce(e6_upd_op::text, 'NULL') || ') — the pin would prove nothing'; end if;
    if e6_pre12 is distinct from 0 then v_bad := v_bad || ' FIXTURE: before the third failure the ring-shaped rows were '
                   || coalesce(e6_pre12::text, 'NULL') || ' — expected 0 (read BEFORE forging; the three forged rows land after)'; end if;
    if e6_before is distinct from 1 then v_bad := v_bad || ' FIXTURE: the operator''s forged row is not the one ring-shaped row before the tick (' || coalesce(e6_before::text, 'NULL') || ')'; end if;
    if (e6_after - e6_before) is distinct from 1
      then v_bad := v_bad || ' 🔴 the third failure rang the operator ' || coalesce((e6_after - e6_before)::text, 'NULL') || ' time(s) — expected exactly +1 beside the forged rows (0 = the ring was silenced, or nothing rings at all)'; end if;
    if (e6_rec->>'escalated_at') is null or (e6_rec->>'episode_failures')::int is distinct from 3
      then v_bad := v_bad || ' 🔴 the record does not read episode 3, rung: ' || coalesce(e6_rec::text, 'NULL'); end if;
    if v_bad = '' then call _pass('rfe','0237-E6 어떤 클라이언트도 벨을 위조해 끌 수 없다 — 세 번째 실패 전에 낯선 사람·시리즈 주인·앉은 운영자가 noti self update로 자기 행을 system·벨 제목·이 시리즈·2000-01-01로 바꿔도(각 1행 반영 확인) 세 번째 실패는 운영자의 진짜 벨을 정확히 +1 쓰고 기록은 울림 — 키가 서버 전용 escalated_at이라 0233/0234 관용구가 남긴 운영자 잔여 구멍도 없다 (측정 후 롤백)');
    else v_msg := v_bad; call _fail('rfe','0237-E6 a forged row cannot silence the ring', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('rfe','0237-E6 a forged row cannot silence the ring', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-E7] an empty roster pages nobody and is retried
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; e7_err := null;
    update ops_recipients set active = false where event_class = CLS and active;
    sZ := t_rfe_series(oZ, dZ, v_bad_rule);
    v_mine := v_mine || sZ;
    for i in 1..3 loop
      v_err := t_rfe_tick();
      if v_err is not null then e7_err := coalesce(e7_err, '') || ' tick' || i || ': ' || v_err; end if;
    end loop;
    e7_rings0 := t_rfe_rings(sZ); e7_rec0 := t_rfe_rec(sZ);
    update ops_recipients set active = true where event_class = CLS and profile_id = opsR;
    v_err := t_rfe_tick();
    if v_err is not null then e7_err := coalesce(e7_err, '') || ' tick4: ' || v_err; end if;
    e7_rings1 := t_rfe_rings(sZ); e7_rec1 := t_rfe_rec(sZ);
    v_err := t_rfe_tick();
    if v_err is not null then e7_err := coalesce(e7_err, '') || ' tick5: ' || v_err; end if;
    e7_rings2 := t_rfe_rings(sZ);

    if e7_err is not null then v_bad := v_bad || ' a tick raised: ' || e7_err; end if;
    if e7_rings0 is distinct from 0 then v_bad := v_bad || ' 🔴 an empty roster produced ' || coalesce(e7_rings0::text, 'NULL') || ' ring rows'; end if;
    if (e7_rec0->>'episode_failures')::int is distinct from 3 or (e7_rec0->>'escalated_at') is not null
      then v_bad := v_bad || ' 🔴 after three failures with nobody seated the record is not episode 3 / NOT rung — a page nobody got was recorded as sent: ' || coalesce(e7_rec0::text, 'NULL'); end if;
    if e7_rings1 is distinct from 1 or (e7_rec1->>'escalated_at') is null
      then v_bad := v_bad || ' 🔴 re-seated, the next failing tick did not ring once (' || coalesce(e7_rings1::text, 'NULL') || ')'; end if;
    if e7_rings2 is distinct from 1 then v_bad := v_bad || ' the tick after that rang again (' || coalesce(e7_rings2::text, 'NULL') || ')'; end if;
    if v_bad = '' then call _pass('rfe','0237-E7 명부가 비면 아무도 호출되지 않고 다시 시도된다 — 세 실패 틱 동안 벨 0행·기록은 에피소드 3·안 울림; 운영자를 다시 앉히면 다음 실패 틱에 정확히 1, 그다음 틱은 0');
    else v_msg := v_bad; call _fail('rfe','0237-E7 an empty roster is retried', v_msg); end if;
  exception when others then call _fail('rfe','0237-E7 an empty roster is retried', sqlerrm); end;
  update recurring_series set paused = true where id = any(v_mine);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-B1] the written title is ledgered, ops, not urgent
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(distinct title)::int into v_n from notifications where kind = 'system' and ref_id = any(v_mine);
    if v_n is distinct from 1 then v_bad := v_bad || ' FIXTURE: expected one distinct written title, got ' || v_n; end if;
    for r in select distinct title from notifications where kind = 'system' and ref_id = any(v_mine) loop
      if (r.title = any (_noti_ops_titles())) is not true then v_bad := v_bad || ' unledgered 「' || r.title || '」'; end if;
      if _noti_push_category('system', r.title) is distinct from 'ops' then v_bad := v_bad || ' 「' || r.title || '」 not ops'; end if;
      if (r.title = any (_noti_urgent_noti_titles())) is not false then v_bad := v_bad || ' 「' || r.title || '」 urgent'; end if;
    end loop;
    if v_bad = '' then call _pass('rfe','0237-B1 벨이 실제로 쓴 제목은 _noti_ops_titles에 있고 ops로 분류되며 긴급 계열이 아니다');
    else v_msg := v_bad; call _fail('rfe','0237-B1 title ledgered', v_msg); end if;
  exception when others then call _fail('rfe','0237-B1 title ledgered', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0237-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_oid := to_regprocedure('public._recurring_failure_escalate(uuid)');
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_recurring_failure_escalate)';
    else
      if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' the ring is not a definer'; end if;
      if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
        then v_bad := v_bad || ' the ring has no in-body search_path'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' anon can execute the ring'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' authenticated can execute the ring'; end if;
      v_src := t_rfe_src('_recurring_failure_escalate');
      if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(_recurring_failure_escalate)';
      else
        if (v_src ~ 'c_ops_class\s+constant text := ''recurring_generation_failed''') is not true then v_bad := v_bad || ' the ring is not the recurring_generation_failed class'; end if;
        if (v_src ~* 'from\s+notifications') is not false then v_bad := v_bad || ' 🔴 the ring READS notifications — a forgeable key'; end if;
        if (v_src ~ 'escalated_at is null') is not true then v_bad := v_bad || ' the ring does not key on escalated_at'; end if;
      end if;
    end if;
    v_src := t_rfe_src('generate_recurring_bookings');
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings)';
    else
      if (v_src ~ 'begin\s+perform _recurring_failure_escalate\(s\.id\);\s+exception when others then') is not true
        then v_bad := v_bad || ' the ring call is not alone in its own begin … exception block'; end if;
      if (position('perform _recurring_failure_escalate(s.id);' in v_src) > position('insert into recurring_generation_failures' in v_src)
          and position('insert into recurring_generation_failures' in v_src) > 0) is not true
        then v_bad := v_bad || ' the ring does not follow the failure record'; end if;
      if (v_src ~ 'begin\s+update recurring_generation_failures\s+set episode_failures = 0, episode_started_at = null, escalated_at = null\s+where series_id = s\.id\s+and \(episode_failures > 0 or escalated_at is not null\);\s+exception when others then') is not true
        then v_bad := v_bad || ' the recovery reset is not alone in its own begin … exception block'; end if;
      if (position('set episode_failures = 0' in v_src) > position('n := n + 1;' in v_src)
          and position('n := n + 1;' in v_src) > 0) is not true
        then v_bad := v_bad || ' the recovery reset does not follow the mint'; end if;
    end if;
    for v_txt in select unnest(array['episode_failures', 'episode_started_at', 'escalated_at']) loop
      if not exists (select 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'recurring_generation_failures' and column_name = v_txt)
        then v_bad := v_bad || ' NO-COLUMN(' || v_txt || ')'; end if;
    end loop;
    v_src := t_rfe_src('ops_roster_set');
    if (position('''recurring_generation_failed''' in coalesce(v_src, '')) > 0) is not true
      then v_bad := v_bad || ' ops_roster_set does not name the class'; end if;
    if v_bad = '' then call _pass('rfe','0237-S1 배포 형상 — 벨은 본문 search_path를 가진 definer이고 anon·authenticated 실행 불가; 주석 벗긴 소스에서 recurring_generation_failed 라우팅 상수, notifications를 읽지 않음(키는 escalated_at); 생성기에서 벨 호출과 회복 리셋이 각자 자기 begin … exception 블록에 홀로 있고 벨은 실패 기록 뒤·리셋은 발행 뒤; 에피소드 세 칸이 있고 ops_roster_set이 클래스를 안다');
    else v_msg := v_bad; call _fail('rfe','0237-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('rfe','0237-S1 deployed shape', sqlerrm); end;

  -- ② / ③ restore the shared world
  update recurring_series set paused = true where id = any(v_mine);
  update ops_recipients set active = false where event_class = CLS and profile_id = opsR;
  update ops_recipients set active = true where event_class = CLS and profile_id = any (v_saved);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ④ the plants go, whatever happened above
drop trigger if exists t_rfe_fault_ring on notifications;
do $$ begin
  if to_regclass('public.recurring_generation_failures') is not null then
    execute 'drop trigger if exists t_rfe_fault_reset on recurring_generation_failures';
  end if;
end $$;
drop function if exists t_rfe_fault_ring();
drop function if exists t_rfe_fault_reset();
drop table if exists t_rfe_faults;
