-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 239 — 0208: the ops roster gets a door, and the door is not an oracle
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Tag `orx`. Pins 0208-G1 · R1 · L1 · C1 · P1 · S1.
--
-- ─── WHAT EACH PIN ESTABLISHES, WITHOUT REFERENCE TO ANY MUTATION ───
--  · **0208-G1** — all three doors take the `ops_recipients_for('payout_due')` gate BEFORE they
--        look at an argument, so a stranger naming a profile that EXISTS and a stranger naming a
--        uuid that does not get the IDENTICAL word, and a stranger passing an invented class gets
--        `not_ops` rather than `unknown_class`. A signed-out caller gets `not_signed_in`, which is
--        a different fact. Controls: the same calls made by a real operator SUCCEED (so `not_ops`
--        measures the gate and not a broken function), and the stranger's refused write left NO
--        row and NO journal row behind.
--  · **0208-R1** — a set SEATS someone (row + exactly one journal row whose four columns are the
--        change), a repeat of the same value is a no-op (`changed=false`, journal delta 0), and a
--        deactivation KEEPS the row with `active=false` — the roster still lists it while
--        `ops_recipients_for` does not, which are two different true sentences. `created_at` does
--        not move across a deactivate/re-activate cycle. Plus the four argument refusals by name.
--  · **0208-L1** — with exactly one active `payout_due` row, turning it off raises `last_operator`
--        and the row is UNCHANGED; the same holds when the caller is that operator (the self
--        case, same token, because it is the same rule). Seating a second operator makes the
--        first deactivation SUCCEED — the control that proves the guard counts rather than
--        refusing every deactivation — and deactivating a NON-`payout_due` class while being the
--        only console operator is allowed, which is the guard's scope.
--  · **0208-C1** — the class allowlist as a SET: every one of the thirteen (fourteen since 0234, fifteen since 0237) names is accepted and
--        appears on the roster, two invented names are refused BY NAME with no row and no journal
--        row written, and a null class is refused the same way.
--  · **0208-P1** — the lookup answers with THREE COLUMNS, asserted by `pg_proc.proargnames` (a
--        column set, not a value — a value pin is green whenever no fixture carries a phone), and
--        a planted phone number appears nowhere in a real result. Ten is the cap, `%` and `_` are
--        literal, a tombstoned profile is not a candidate, and a one-character query is refused.
--  · **0208-S1** — the deployed shape of the three functions and the journal table, with the
--        source arms read from COMMENT-STRIPPED `prosrc` and a crude control beside them.
--
-- ─── NAMED GAPS (facts about the system, written as prose because no pin can reach them) ───
--  · 🔴 **The roster can still be emptied without passing `last_operator`.**
--    `delete_my_account_tx` (0115:590) deletes a profile's `ops_recipients` rows directly, and
--    `ops_recipients` is in 0115 §F's ④ delete list BY NAME. That path is correct — a deleted
--    person must not stay on call — and it is outside 0208. `0208-L1`'s green must not be read as
--    「the console can never lock everyone out」; it says 「an operator's TAP cannot do it」.
--  · **The FIRST operator still comes from psql, by construction.** Every door requires an
--    existing active `payout_due` operator, so there is no call sequence that bootstraps one, and
--    no pin here can assert otherwise. 0208 §0 states it; this is the reminder that the suite
--    seats its own operator by INSERT, exactly as Sean did on 2026-09-22.
--  · **`unknown_class` is a UI allowlist and NOT a schema constraint.** A row written by psql
--    with any string at all is still accepted by `ops_recipients` (0084 §E deliberately has no
--    CHECK) and is still LISTED by `ops_roster()`. `0208-C1` pins the door's vocabulary; nothing
--    here pins the column's, and nothing should.
--  · **The class list in `c_classes` below is a deliberate SECOND COPY of the migration's.** That
--    is the pin: both were derived from the emitters (0208 §0c enumerates them and cites the five
--    SQL literals and the eight `OpsEventClass` members), and a name silently dropped from one
--    reddens here. It is not independent evidence that the list is RIGHT — only that the two
--    agree. Whether a class belongs on it is settled by reading `_shared/ops.ts`, not by this file.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (`orx_*` profiles) rather than borrowing 229's or 217's.
--     A pin that inherits another suite's setup is testing that setup (`175 V2`'s law).
--  ② 🔴 **`ops_recipients` IS SHARED STATE AND ELEVEN OTHER SUITES SEAT `payout_due` OPERATORS
--     IN IT** (217 · 221 · 223 · 225 · 226 · 229 · 230 · 224 …). `0208-L1`'s property is about a
--     world with exactly ONE active console operator, which this database does not have. So L1
--     SAVES every other active `payout_due` row, deactivates them, measures, and RESTORES them —
--     with a CONTROL on both ends (the world really is down to one; the world really came back).
--     Reading a `last_operator` on a world that merely happened to be empty would be the
--     fixture-agreement failure this house has met three times.
--  ③ Every journal assertion is a DELTA the pin CAUSED (count read first), never an absolute.
--  ④ The helpers below call each door through `set_config('request.jwt.claim.sub', …)` and
--     return `{'raised': sqlerrm}` on a refusal. A refusal therefore rolls its own subtransaction
--     back, which is exactly what the 「no row was written」 arms need to be able to observe.
--
-- ─── MUTATION MAP — measured against these exact files ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`).
set client_min_messages = warning;

-- ---------- suite-local callers ④ ----------
-- Each returns `{'raised': …}` on a refusal, so an arm can compare the WORD rather than catching
-- a death. `p_uid is null` means signed out.
create or replace function t_orx_roster_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.profile_id, x.event_class), '[]'::jsonb)
    into v from ops_roster() x;
  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
exception when others then
  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_orx_set_as(p_uid uuid, p_profile uuid, p_class text, p_active boolean)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  select to_jsonb(x) into v from ops_roster_set(p_profile, p_class, p_active) x;
  perform set_config('request.jwt.claim.sub', '', false);
  return coalesce(v, '{}'::jsonb);
exception when others then
  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_orx_lookup_as(p_uid uuid, p_q text) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from ops_profile_lookup(p_q) x;
  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
exception when others then
  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- a named profile whose display name is exactly `p_display` (t_user's name doubles as an email
-- local part, so the ascii handle and the Korean display name are set separately)
create or replace function t_orx_person(p_handle text, p_display text) returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := t_user(p_handle, 'owner');
  update profiles set name = p_display where id = v;
  return v;
end $$;

do $$
declare
  ox  uuid;                      -- the rostered console operator (bootstrapped by INSERT, §0)
  oy  uuid;                      -- a second console operator (L1's control)
  sx  uuid;                      -- a stranger: signed in, holds no ops row
  pz  uuid;                      -- R1's subject
  pc  uuid;                      -- C1's subject
  pg1 uuid; pg2 uuid;            -- G1's subjects: one that exists, one uuid that does not
  pph uuid;                      -- P1: the profile carrying a planted phone
  pu1 uuid; pu2 uuid;            -- P1: the `_`-literal pair
  pt1 uuid; pt2 uuid;            -- P1: the tombstone pair
  pdel uuid;                     -- R1: a tombstoned profile
  -- §0c's list, second copy ON PURPOSE (see NAMED GAPS)
  c_classes constant text[] := array[
    'payout_due', 'return_strand', 'handoff_unanswered', 'billing_key_revocation_abandoned',
    'club_fee_mint_failed', 'payment_manual_cancel', 'charge_ladder_exhausted',
    'charge_dispatch_stale', 'settled_without_payment', 'enroute_comp_failed',
    'late_comp_failed', 'incident_waive_pending', 'payment_marker_lost',
    -- [0234 §C] the fourteenth: open_incident_tx's ops bell. This list's property — it AGREES with the
    -- migration's (NAMED GAP ④) — would otherwise have gone quietly false; 265 `0234-C1` owns seating it.
    'incident_opened',
    -- [0237 §C] the fifteenth: the recurring generator's failure-episode ring (_recurring_failure_escalate).
    -- Same property — this copy AGREES with the migration's; 268 `0237-C1` owns seating it.
    'recurring_generation_failed'
  ];
  c_phone constant text := '01099998888';
  v_bad text := ''; v_msg text; v_js jsonb; v_js2 jsonb; v_n int; v_n2 int;
  v_j0 int; v_src text; v_raw text; v_oid oid; v_names text[]; v_cls text;
  v_saved uuid[]; v_saved2 uuid[]; v_ts timestamptz; v_ts2 timestamptz; v_i int;
begin
  perform set_config('request.jwt.claim.sub', '', false);

  ox   := t_orx_person('orx_ox', '명부운영자');
  oy   := t_orx_person('orx_oy', '명부둘째');
  sx   := t_orx_person('orx_sx', '명부남');
  pz   := t_orx_person('orx_pz', '명부대상');
  pc   := t_orx_person('orx_pc', '명부클래스');
  pg1  := t_orx_person('orx_pg1', '명부존재');
  pdel := t_orx_person('orx_pdel', '명부탈퇴');
  pg2  := gen_random_uuid();                 -- a uuid no profile carries
  update profiles set deleted_at = now() where id = pdel;

  -- §0's bootstrap, by INSERT, because no door can seat the first operator
  insert into ops_recipients (profile_id, event_class, active) values (ox, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-G1] THE GATE IS FIRST, AND THE DOOR IS NOT AN ORACLE
  -- 🔴 The pair that matters is 「a profile that exists」 vs 「a uuid that does not」 from ONE
  --    stranger identity. If the two answers differ by a single word, the refusal is a
  --    membership probe over every uuid in the product — which is exactly what 0084 §E sealed
  --    this table to prevent.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_j0 from ops_roster_changes;

    -- ── CONTROL: the real operator gets through all three doors. Without this every `not_ops`
    --    below is indistinguishable from 「the function is broken」.
    v_js := t_orx_roster_as(ox);
    if v_js ? 'raised' then v_bad := v_bad || ' 대조: 운영자가 명부를 못 읽었다=' || (v_js->>'raised'); end if;
    if coalesce((v_js->>'n')::int, 0) < 1
      then v_bad := v_bad || ' 대조: 운영자가 읽은 명부가 비었다 (자기 행조차 없다)'; end if;
    v_js := t_orx_lookup_as(ox, '명부존재');
    if v_js ? 'raised' then v_bad := v_bad || ' 대조: 운영자가 조회를 못 했다=' || (v_js->>'raised'); end if;
    if coalesce((v_js->>'n')::int, -1) is distinct from 1
      then v_bad := v_bad || ' 대조: 운영자 조회 행 수=' || coalesce(v_js->>'n', '?'); end if;

    -- ── the stranger, on all three doors
    v_js := t_orx_roster_as(sx);
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 명부 읽기: 남이 받은 말=' || coalesce(v_js::text, '(null)'); end if;

    -- 🔴 THE PAIR. Same stranger, same class, same boolean — only the target differs.
    v_js  := t_orx_set_as(sx, pg1, 'payout_due', true);
    v_js2 := t_orx_set_as(sx, pg2, 'payout_due', true);
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 쓰기(존재하는 대상): 남이 받은 말=' || coalesce(v_js::text, '(null)'); end if;
    if (v_js2->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 쓰기(없는 uuid): 남이 받은 말=' || coalesce(v_js2::text, '(null)'); end if;
    if (v_js->>'raised') is distinct from (v_js2->>'raised')
      then v_bad := v_bad || ' 🔴 두 대상이 다른 말을 들었다 — 명부가 신탁이 된다 [' ||
        coalesce(v_js->>'raised', '(null)') || '] vs [' || coalesce(v_js2->>'raised', '(null)') || ']'; end if;

    -- the gate is before the ARGUMENT check too: an invented class from a stranger is `not_ops`
    v_js := t_orx_set_as(sx, pg1, 'not_a_class_at_all', true);
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 🔴 남이 unknown_class를 들었다 (인자 검사가 게이트보다 앞이다)=' ||
        coalesce(v_js::text, '(null)'); end if;
    v_js := t_orx_set_as(sx, null, 'payout_due', true);
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 🔴 남이 no_profile을 들었다=' || coalesce(v_js::text, '(null)'); end if;

    -- lookup: a name that exists and gibberish must be the same word, and a too-short query too
    v_js  := t_orx_lookup_as(sx, '명부존재');
    v_js2 := t_orx_lookup_as(sx, 'zzzz아무도아닌이름');
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 조회(있는 이름): 남이 받은 말=' || coalesce(v_js::text, '(null)'); end if;
    if (v_js->>'raised') is distinct from (v_js2->>'raised')
      then v_bad := v_bad || ' 🔴 조회가 이름의 존재를 흘린다'; end if;
    v_js := t_orx_lookup_as(sx, '명');
    if (v_js->>'raised') is distinct from 'not_ops'
      then v_bad := v_bad || ' 🔴 남이 short_query를 들었다=' || coalesce(v_js::text, '(null)'); end if;

    -- ── signed out is a DIFFERENT fact from 「not an operator」
    if (t_orx_roster_as(null)->>'raised') is distinct from 'not_signed_in'
      then v_bad := v_bad || ' 로그아웃 명부 읽기의 말이 not_signed_in이 아니다'; end if;
    if (t_orx_set_as(null, pg1, 'payout_due', true)->>'raised') is distinct from 'not_signed_in'
      then v_bad := v_bad || ' 로그아웃 쓰기의 말이 not_signed_in이 아니다'; end if;
    if (t_orx_lookup_as(null, '명부존재')->>'raised') is distinct from 'not_signed_in'
      then v_bad := v_bad || ' 로그아웃 조회의 말이 not_signed_in이 아니다'; end if;

    -- ── 「before any read」 also means 「before any WRITE」: nothing landed
    if (select exists (select 1 from ops_recipients r where r.profile_id = pg1)) is not false
      then v_bad := v_bad || ' 🔴 남의 쓰기가 행을 남겼다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 0
      then v_bad := v_bad || ' 🔴 남의 쓰기가 장부에 행을 남겼다 (델타=' || (v_n - v_j0) || ')'; end if;

    if v_bad = ''
      then call _pass('orx','0208-G1 세 문 모두 게이트가 인자보다 먼저 — 남(sx)은 존재하는 프로필을 대도, 프로필이 없는 uuid를 대도, 없는 클래스를 대도, 널을 대도 **똑같이 not_ops**를 듣고(그 차이 자체가 uuid 신탁이 된다), 조회도 있는 이름과 없는 이름과 한 글자 질의에 같은 말을 한다; 로그아웃은 not_signed_in으로 다른 사실이고; 같은 호출을 진짜 운영자가 하면 셋 다 성공한다(대조 — not_ops가 게이트이지 고장이 아니라는 증거); 거절된 쓰기는 행도 장부 행도 남기지 않았다');
    else v_msg := v_bad; call _fail('orx','0208-G1 게이트 우선·비신탁', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-G1 게이트 우선·비신탁', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-R1] SEATING, RE-ASSERTING AND UNSEATING — AND THE JOURNAL IS A CHANGE LOG
  -- ③ every journal number below is a delta this pin caused, measured from a baseline read first.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_j0 from ops_roster_changes;

    -- ① SEAT
    v_js := t_orx_set_as(ox, pz, 'return_strand', true);
    if v_js ? 'raised' then v_bad := v_bad || ' 앉히기가 거절됐다=' || (v_js->>'raised');
    else
      if (v_js->>'changed')::boolean is not true
        then v_bad := v_bad || ' 앉히기가 changed=false로 왔다'; end if;
      if (v_js->>'active')::boolean is not true
        then v_bad := v_bad || ' 앉히기가 active=false로 왔다'; end if;
    end if;
    if (select r.active from ops_recipients r
         where r.profile_id = pz and r.event_class = 'return_strand') is not true
      then v_bad := v_bad || ' 행이 없거나 active가 아니다'; end if;
    select r.created_at into v_ts from ops_recipients r
     where r.profile_id = pz and r.event_class = 'return_strand';

    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 1
      then v_bad := v_bad || ' 🔴 앉히기의 장부 델타=' || (v_n - v_j0) || ' (1이어야)'; end if;
    -- the journal row IS the change, in all four columns
    if (select count(*)::int from ops_roster_changes c
         where c.actor = ox and c.profile = pz and c.class = 'return_strand' and c.active) is distinct from 1
      then v_bad := v_bad || ' 장부 행의 네 칸이 이 변경이 아니다'; end if;

    -- the roster shows it
    v_js := t_orx_roster_as(ox);
    select count(*)::int into v_n2 from jsonb_array_elements(v_js->'rows') e
     where (e->>'profile_id')::uuid = pz and e->>'event_class' = 'return_strand'
       and (e->>'active')::boolean and e->>'name' = '명부대상';
    if v_n2 is distinct from 1
      then v_bad := v_bad || ' 명부가 새 행을 이름과 함께 보여주지 않는다 (=' || v_n2 || ')'; end if;

    -- ② RE-ASSERT the same value: a no-op, and the journal does NOT grow
    select count(*)::int into v_j0 from ops_roster_changes;
    v_js := t_orx_set_as(ox, pz, 'return_strand', true);
    if v_js ? 'raised' then v_bad := v_bad || ' 같은 값 재설정이 거절됐다=' || (v_js->>'raised');
    elsif (v_js->>'changed')::boolean is not false
      then v_bad := v_bad || ' 🔴 같은 값 재설정이 changed=true로 왔다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 0
      then v_bad := v_bad || ' 🔴 변경 없는 호출이 장부에 행을 남겼다 (델타=' || (v_n - v_j0) || ')'; end if;

    -- ③ UNSEAT: the row SURVIVES with active=false (0084 — who used to be on call is an audit
    --    fact), the roster still lists it, and the routing window no longer does. Two doors, two
    --    different true sentences.
    select count(*)::int into v_j0 from ops_roster_changes;
    v_js := t_orx_set_as(ox, pz, 'return_strand', false);
    if v_js ? 'raised' then v_bad := v_bad || ' 내리기가 거절됐다=' || (v_js->>'raised');
    elsif (v_js->>'changed')::boolean is not true
      then v_bad := v_bad || ' 내리기가 changed=false로 왔다'; end if;
    if (select exists (select 1 from ops_recipients r
                       where r.profile_id = pz and r.event_class = 'return_strand')) is not true
      then v_bad := v_bad || ' 🔴 내리기가 행을 지웠다 (0084: 행은 남아야 한다)'; end if;
    if (select r.active from ops_recipients r
         where r.profile_id = pz and r.event_class = 'return_strand') is not false
      then v_bad := v_bad || ' 내린 행의 active가 false가 아니다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 1
      then v_bad := v_bad || ' 내리기의 장부 델타=' || (v_n - v_j0); end if;
    if (select count(*)::int from ops_roster_changes c
         where c.actor = ox and c.profile = pz and c.class = 'return_strand' and not c.active)
        is distinct from 1
      then v_bad := v_bad || ' 장부가 내린 사실(active=false)을 적지 않았다'; end if;

    v_js := t_orx_roster_as(ox);
    select count(*)::int into v_n2 from jsonb_array_elements(v_js->'rows') e
     where (e->>'profile_id')::uuid = pz and e->>'event_class' = 'return_strand'
       and (e->>'active')::boolean is false;
    if v_n2 is distinct from 1
      then v_bad := v_bad || ' 🔴 명부가 비활성 행을 숨긴다 (전 당번을 다시 앉히려면 uuid를 다시 쳐야 한다)'; end if;
    if (select exists (select 1 from ops_recipients_for('return_strand') as rc(profile_id)
                       where rc.profile_id = pz)) is not false
      then v_bad := v_bad || ' 대조: 라우팅 창구가 비활성 행을 여전히 돌려준다'; end if;

    -- ④ RE-SEAT: `created_at` must not move (ops_recipients_for orders the bell by it)
    v_js := t_orx_set_as(ox, pz, 'return_strand', true);
    if v_js ? 'raised' then v_bad := v_bad || ' 재개가 거절됐다=' || (v_js->>'raised'); end if;
    select r.created_at into v_ts2 from ops_recipients r
     where r.profile_id = pz and r.event_class = 'return_strand';
    if v_ts2 is distinct from v_ts
      then v_bad := v_bad || ' 🔴 재개가 created_at을 움직였다 (통지 순서와 최초 당번 시각이 바뀐다)'; end if;

    -- ⑤ the argument refusals, BY NAME, from a real operator (past the gate)
    if (t_orx_set_as(ox, pg2, 'payout_due', true)->>'raised') is distinct from 'no_profile'
      then v_bad := v_bad || ' 없는 uuid가 no_profile이 아니다'; end if;
    if (t_orx_set_as(ox, null, 'payout_due', true)->>'raised') is distinct from 'no_profile'
      then v_bad := v_bad || ' 널 프로필이 no_profile이 아니다'; end if;
    if (t_orx_set_as(ox, pdel, 'payout_due', true)->>'raised') is distinct from 'no_profile'
      then v_bad := v_bad || ' 🔴 탈퇴한 프로필을 당번으로 앉힐 수 있다'; end if;
    if (t_orx_set_as(ox, pz, 'payout_due', null)->>'raised') is distinct from 'bad_active'
      then v_bad := v_bad || ' 널 boolean이 bad_active가 아니다'; end if;

    if v_bad = ''
      then call _pass('orx','0208-R1 앉히기·재확인·내리기와 변경 장부 — 앉히면 행이 생기고 장부 델타가 **정확히 1**이며 그 행의 네 칸(행위자·대상·클래스·결과 상태)이 이 변경이고 명부가 이름과 함께 보여준다; 같은 값을 다시 쓰면 changed=false이고 장부는 **자라지 않는다**; 내리면 행은 **지워지지 않고** active=false로 남아 명부에는 보이고 라우팅 창구(ops_recipients_for)에는 안 보인다(두 문장이 다 참이다); 다시 올려도 created_at은 움직이지 않는다(통지 순서·최초 당번 시각); 없는 uuid·널·탈퇴 프로필은 no_profile, 널 boolean은 bad_active — 모두 이름으로');
    else v_msg := v_bad; call _fail('orx','0208-R1 앉히기·내리기·장부 델타', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-R1 앉히기·내리기·장부 델타', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-C1] THE CLASS ALLOWLIST IS A SET, AND AN INVENTED NAME IS REFUSED BY NAME
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_j0 from ops_roster_changes;

    foreach v_cls in array c_classes loop
      v_js := t_orx_set_as(ox, pc, v_cls, true);
      if v_js ? 'raised'
        then v_bad := v_bad || ' 허용목록의 [' || v_cls || ']가 거절됐다=' || (v_js->>'raised'); end if;
    end loop;

    -- every one of them is on the roster, and NOTHING ELSE is
    v_js := t_orx_roster_as(ox);
    select count(*)::int into v_n from jsonb_array_elements(v_js->'rows') e
     where (e->>'profile_id')::uuid = pc;
    if v_n is distinct from array_length(c_classes, 1)
      then v_bad := v_bad || ' 대상의 명부 행 수=' || v_n || ' (' || array_length(c_classes, 1) || '이어야)'; end if;
    select count(*)::int into v_n2 from jsonb_array_elements(v_js->'rows') e
     where (e->>'profile_id')::uuid = pc and (e->>'event_class' = any(c_classes)) is not true;
    if v_n2 is distinct from 0
      then v_bad := v_bad || ' 🔴 목록 밖 클래스가 앉혀졌다 (=' || v_n2 || ')'; end if;

    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from array_length(c_classes, 1)
      then v_bad := v_bad || ' 장부 델타=' || (v_n - v_j0) || ' (클래스 수만큼이어야)'; end if;

    -- ── two invented names, refused BY NAME with nothing written
    select count(*)::int into v_j0 from ops_roster_changes;
    if (t_orx_set_as(ox, pc, 'payout_dues', true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' 오타 클래스가 unknown_class가 아니다 (당번인 줄 아는 사람이 생긴다)'; end if;
    if (t_orx_set_as(ox, pc, 'not_a_class_at_all', true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' 지어낸 클래스가 unknown_class가 아니다'; end if;
    if (t_orx_set_as(ox, pc, null, true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' 널 클래스가 unknown_class가 아니다'; end if;
    if (t_orx_set_as(ox, pc, '', true)->>'raised') is distinct from 'unknown_class'
      then v_bad := v_bad || ' 빈 클래스가 unknown_class가 아니다'; end if;
    if (select exists (select 1 from ops_recipients r
                       where r.profile_id = pc
                         and r.event_class in ('payout_dues', 'not_a_class_at_all', ''))) is not false
      then v_bad := v_bad || ' 🔴 거절된 클래스의 행이 남았다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 0
      then v_bad := v_bad || ' 🔴 거절된 클래스가 장부 행을 남겼다 (델타=' || (v_n - v_j0) || ')'; end if;

    if v_bad = ''
      then call _pass('orx','0208-C1 클래스 허용목록은 **집합**이다 — 방출자에서 뽑은 열다섯 이름(SQL 방출자 일곱 — 0234가 incident_opened, 0237이 recurring_generation_failed 추가 — + _shared/ops.ts의 OpsEventClass 여덟) 전부가 받아들여져 명부에 그대로 앉고 장부 델타가 정확히 그 수이며 목록 밖 값은 하나도 앉지 않는다; payout_dues 같은 **오타**와 지어낸 이름과 널과 빈 문자열은 모두 unknown_class로 이름 지어 거절되고 행도 장부 행도 남기지 않는다(구독자의 오타는 0084 §E의 안전 논증이 덮지 않는 실패 — 당번인 줄 알고 아무것도 못 받는 사람)');
    else v_msg := v_bad; call _fail('orx','0208-C1 클래스 허용목록', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-C1 클래스 허용목록', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-P1] THE LOOKUP IS THREE COLUMNS, TEN ROWS, AND NO PHONE
  -- 🔴 The column-set arm is `pg_proc.proargnames` and not a value read, because a value pin is
  --    green whenever no fixture happens to carry the field — which is how a widening ships.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- fixtures: 12 sharing a prefix, a `_`-literal pair, a tombstone pair, a phone carrier
    for v_i in 1..12 loop
      perform t_orx_person('orx_ls' || lpad(v_i::text, 2, '0'), '명단검색' || lpad(v_i::text, 2, '0'));
    end loop;
    pu1 := t_orx_person('orx_pu1', '명단밑_줄');
    pu2 := t_orx_person('orx_pu2', '명단밑X줄');
    pt1 := t_orx_person('orx_pt1', '명단퇴산사람');
    pt2 := t_orx_person('orx_pt2', '명단퇴장사람');
    update profiles set deleted_at = now() where id = pt2;
    pph := t_orx_person('orx_pph', '명단전화');
    update profiles set phone = c_phone where id = pph;

    -- ── THE COLUMN SET, by name (§0e)
    select p.proargnames into v_names from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_profile_lookup';
    if v_names is distinct from array['p_query', 'id', 'name', 'role']
      then v_bad := v_bad || ' 🔴 조회 창구의 열 집합=' || coalesce(v_names::text, '(null)') ||
        ' (p_query·id·name·role 이어야 — 전화·이메일·handle·district는 없다)'; end if;

    -- ── the phone really is in the database (CONTROL: an absence measured over a world that
    --    never held the thing is worth zero — 0151 N1/N2's law)
    if (select p.phone from profiles p where p.id = pph) is distinct from c_phone
      then v_bad := v_bad || ' 대조: 픽스처에 전화번호가 심기지 않았다 (부재 팔이 무의미)'; end if;
    v_js := t_orx_lookup_as(ox, '명단전화');
    if coalesce((v_js->>'n')::int, -1) is distinct from 1
      then v_bad := v_bad || ' 전화 보유자 조회 행 수=' || coalesce(v_js->>'n', '?'); end if;
    if (position(c_phone in coalesce(v_js::text, '')) > 0) is not false
      then v_bad := v_bad || ' 🔴 조회 결과에 전화번호가 실렸다'; end if;
    if (v_js->'rows'->0->>'id')::uuid is distinct from pph
      then v_bad := v_bad || ' 조회가 다른 사람을 돌려줬다'; end if;
    if (v_js->'rows'->0->>'role') is distinct from 'owner'
      then v_bad := v_bad || ' 조회의 role 칸이 비었거나 다르다=' ||
        coalesce(v_js->'rows'->0->>'role', '(null)'); end if;

    -- ── TEN is the cap: twelve match, ten come back
    if (select count(*)::int from profiles p where p.name like '명단검색%' and p.deleted_at is null)
        is distinct from 12
      then v_bad := v_bad || ' 대조: 접두사 픽스처가 12명이 아니다'; end if;
    v_js := t_orx_lookup_as(ox, '명단검색');
    if coalesce((v_js->>'n')::int, -1) is distinct from 10
      then v_bad := v_bad || ' 🔴 12명 중 돌아온 행 수=' || coalesce(v_js->>'n', '?') || ' (10이어야)'; end if;

    -- ── `%` is LITERAL: a search box that dumps the product is the failure this escape prevents
    v_js := t_orx_lookup_as(ox, '%%');
    if coalesce((v_js->>'n')::int, -1) is distinct from 0
      then v_bad := v_bad || ' 🔴 %% 질의가 행을 돌려줬다 (덤프) =' || coalesce(v_js->>'n', '?'); end if;
    -- CONTROL: the same door with a real prefix answers, so the 0 above is the escape and not a
    -- broken function
    if coalesce((t_orx_lookup_as(ox, '명단')->>'n')::int, 0) < 1
      then v_bad := v_bad || ' 대조: 진짜 접두사도 0행이다 (%% 팔이 무의미)'; end if;

    -- ── `_` is LITERAL too: `명단밑_` must find the underscore and not the X
    v_js := t_orx_lookup_as(ox, '명단밑_');
    if coalesce((v_js->>'n')::int, -1) is distinct from 1
      then v_bad := v_bad || ' 🔴 밑줄 질의 행 수=' || coalesce(v_js->>'n', '?') || ' (1이어야)'; end if;
    if (v_js->'rows'->0->>'id')::uuid is distinct from pu1
      then v_bad := v_bad || ' 🔴 밑줄이 한 글자 와일드카드로 동작한다'; end if;

    -- ── a tombstone is not a candidate
    v_js := t_orx_lookup_as(ox, '명단퇴');
    if coalesce((v_js->>'n')::int, -1) is distinct from 1
      then v_bad := v_bad || ' 탈퇴 쌍 조회 행 수=' || coalesce(v_js->>'n', '?') || ' (1이어야)'; end if;
    if (v_js->'rows'->0->>'id')::uuid is distinct from pt1
      then v_bad := v_bad || ' 🔴 탈퇴한 프로필이 후보로 나왔다'; end if;

    -- ── one character is not a lookup
    if (t_orx_lookup_as(ox, '명')->>'raised') is distinct from 'short_query'
      then v_bad := v_bad || ' 한 글자 질의가 short_query가 아니다'; end if;
    if (t_orx_lookup_as(ox, '   ')->>'raised') is distinct from 'short_query'
      then v_bad := v_bad || ' 공백 질의가 short_query가 아니다'; end if;
    if (t_orx_lookup_as(ox, null)->>'raised') is distinct from 'short_query'
      then v_bad := v_bad || ' 널 질의가 short_query가 아니다'; end if;

    if v_bad = ''
      then call _pass('orx','0208-P1 조회 창구는 **세 칸·열 행·전화 없음** — 열 집합을 pg_proc.proargnames로 못박는다(값으로 보면 마침 전화번호 없는 픽스처에서 늘 초록이므로); 실제로 전화번호를 심어 두고(대조) 그 사람을 찾아도 결과 어디에도 번호가 없고 id·name·role만 온다; 12명이 맞는 접두사에 10행만 오고(답하기를 거절하는 지점이지 페이지가 아니다); %는 리터럴이라 %% 질의는 0행인데 진짜 접두사는 행이 있고(대조), _도 리터럴이라 명단밑_는 밑줄 하나만 찾고 X는 못 찾는다; 탈퇴 프로필은 후보가 아니고; 한 글자·공백·널은 short_query');
    else v_msg := v_bad; call _fail('orx','0208-P1 조회 창구의 좁음', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-P1 조회 창구의 좁음', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-L1] THE LAST CONSOLE OPERATOR CANNOT BE TURNED OFF — BY ANYONE, INCLUDING THEMSELVES
  -- ② The world is SHARED: eleven suites seat `payout_due` operators. This pin manufactures the
  --   one-operator world explicitly, with a control on both ends, and restores it.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ② save + neutralise every OTHER active console operator
    select coalesce(array_agg(r.profile_id), '{}'::uuid[]) into v_saved
      from ops_recipients r
     where r.event_class = 'payout_due' and r.active and r.profile_id <> ox;
    update ops_recipients set active = false
     where event_class = 'payout_due' and profile_id = any(v_saved);

    -- CONTROL ①: the world really is down to exactly one. Without this arm a `last_operator`
    -- would be green on a world that merely happened to look right.
    select count(*)::int into v_n from ops_recipients r
     where r.event_class = 'payout_due' and r.active;
    if v_n is distinct from 1
      then v_bad := v_bad || ' 대조: 활성 콘솔 운영자 수=' || v_n || ' (1이어야 — 이 핀의 전제)'; end if;

    -- ── the SELF case: the only operator turning themselves off
    select count(*)::int into v_j0 from ops_roster_changes;
    v_js := t_orx_set_as(ox, ox, 'payout_due', false);
    if (v_js->>'raised') is distinct from 'last_operator'
      then v_bad := v_bad || ' 자기 자신을 끄는 마지막 운영자가 받은 말=' || coalesce(v_js::text, '(null)'); end if;
    if (select r.active from ops_recipients r
         where r.profile_id = ox and r.event_class = 'payout_due') is not true
      then v_bad := v_bad || ' 🔴 거절됐는데 행이 바뀌었다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 0
      then v_bad := v_bad || ' 🔴 거절이 장부 행을 남겼다 (델타=' || (v_n - v_j0) || ')'; end if;

    -- ── a real deactivation that is NOT the last row is still refused when it IS the last one:
    --    turning OFF an already-off row changes nothing and must NOT be refused
    v_js := t_orx_set_as(ox, pz, 'payout_due', false);
    if v_js ? 'raised'
      then v_bad := v_bad || ' 🔴 이미 꺼진(없는) 행을 끄는 것이 거절됐다=' || (v_js->>'raised'); end if;

    -- ── CONTROL ②: seat a SECOND operator and the same deactivation SUCCEEDS. This is what makes
    --    the pin about the COUNT rather than about refusing every deactivation.
    v_js := t_orx_set_as(ox, oy, 'payout_due', true);
    if v_js ? 'raised' then v_bad := v_bad || ' 둘째 운영자를 앉히지 못했다=' || (v_js->>'raised'); end if;
    select count(*)::int into v_j0 from ops_roster_changes;
    v_js := t_orx_set_as(ox, ox, 'payout_due', false);
    if v_js ? 'raised'
      then v_bad := v_bad || ' 🔴 둘일 때도 자기를 못 내린다=' || (v_js->>'raised'); end if;
    if (select r.active from ops_recipients r
         where r.profile_id = ox and r.event_class = 'payout_due') is not false
      then v_bad := v_bad || ' 둘일 때의 내리기가 행에 반영되지 않았다'; end if;
    select count(*)::int into v_n from ops_roster_changes;
    if (v_n - v_j0) is distinct from 1
      then v_bad := v_bad || ' 성공한 내리기의 장부 델타=' || (v_n - v_j0); end if;

    -- ── now `oy` is the last one. ANOTHER caller cannot turn them off either — same token, and
    --    this arm is the non-self half of the same rule.
    if (t_orx_set_as(oy, oy, 'payout_due', false)->>'raised') is distinct from 'last_operator'
      then v_bad := v_bad || ' 마지막이 된 둘째를 본인이 끄는 것이 거절되지 않았다'; end if;

    -- ── SCOPE: the guard is `payout_due` only. `oy` is the only console operator and may still
    --    leave `return_strand` — emptying that class is a state 0084 §E documents as honest.
    --    ⚠ `return_strand` is shared too (224 · 230 · 236 seat it, and R1 above re-seated `pz`),
    --    so the same save/neutralise/restore the console class got is applied here — otherwise
    --    this arm would be 「a row was turned off」, which proves nothing about being the LAST one.
    select coalesce(array_agg(r.profile_id), '{}'::uuid[]) into v_saved2
      from ops_recipients r
     where r.event_class = 'return_strand' and r.active and r.profile_id <> oy;
    update ops_recipients set active = false
     where event_class = 'return_strand' and profile_id = any(v_saved2);
    v_js := t_orx_set_as(oy, oy, 'return_strand', true);
    if v_js ? 'raised' then v_bad := v_bad || ' 둘째를 return_strand에 앉히지 못했다=' || (v_js->>'raised'); end if;
    if (select count(*)::int from ops_recipients r
         where r.event_class = 'return_strand' and r.active) is distinct from 1
      then v_bad := v_bad || ' 대조: return_strand 활성 행이 1이 아니다 (범위 팔의 전제)'; end if;
    v_js := t_orx_set_as(oy, oy, 'return_strand', false);
    if v_js ? 'raised'
      then v_bad := v_bad || ' 🔴 payout_due 아닌 클래스의 마지막 행이 막혔다 (가드가 넓다)=' ||
        (v_js->>'raised'); end if;
    update ops_recipients set active = true
     where event_class = 'return_strand' and profile_id = any(v_saved2);

    -- ── RESTORE the world (②). The fixture rows are mine; the saved ones are other suites'.
    update ops_recipients set active = true
     where event_class = 'payout_due' and profile_id = ox;
    update ops_recipients set active = false
     where event_class = 'payout_due' and profile_id = oy;
    update ops_recipients set active = true
     where event_class = 'payout_due' and profile_id = any(v_saved);
    -- CONTROL ③: the restore landed. A pin that leaves the world broken is a pin that breaks
    -- whatever runs next, and 「it was restored」 is a claim like any other.
    select count(*)::int into v_n from ops_recipients r
     where r.event_class = 'payout_due' and r.active and r.profile_id = any(v_saved);
    if v_n is distinct from coalesce(array_length(v_saved, 1), 0)
      then v_bad := v_bad || ' 🔴 복원 실패: 되살린 다른 스위트의 운영자 수=' || v_n ||
        ' / ' || coalesce(array_length(v_saved, 1), 0); end if;
    select count(*)::int into v_n from ops_recipients r
     where r.event_class = 'return_strand' and r.active and r.profile_id = any(v_saved2);
    if v_n is distinct from coalesce(array_length(v_saved2, 1), 0)
      then v_bad := v_bad || ' 🔴 복원 실패: 되살린 return_strand 행 수=' || v_n ||
        ' / ' || coalesce(array_length(v_saved2, 1), 0); end if;
    if (select r.active from ops_recipients r
         where r.profile_id = ox and r.event_class = 'payout_due') is not true
      then v_bad := v_bad || ' 🔴 복원 실패: 이 스위트의 운영자가 꺼진 채다'; end if;

    if v_bad = ''
      then call _pass('orx','0208-L1 마지막 콘솔 운영자는 끌 수 없다 — 활성 payout_due 행이 하나뿐인 세계를 **명시적으로 만들어**(다른 열한 스위트가 같은 표를 쓰므로; 전제를 대조로 확인) 그 하나를 본인이 끄면 last_operator이고 행은 그대로이며 장부도 자라지 않는다; **둘째를 앉히면 같은 내리기가 성공한다**(대조 — 이 가드는 수를 세지 모든 내리기를 막지 않는다) 그리고 마지막이 된 둘째도 같은 토큰으로 거절된다(자기를 끄는 경우는 같은 규칙의 한 경우일 뿐, 두 번째 구현이 아니다); 이미 꺼진 행을 끄는 것은 거절하지 않고; **payout_due에만 건다** — 유일한 콘솔 운영자가 return_strand의 마지막 행은 내릴 수 있다(0084 §E가 정직한 답이라고 적어 둔 상태다); 세계는 복원됐고 그 복원도 대조로 확인했다');
    else v_msg := v_bad; call _fail('orx','0208-L1 마지막 운영자 가드', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-L1 마지막 운영자 가드', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0208-S1] THE DEPLOYED SHAPE — three definers, one sealed journal, and the gate in front
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach v_cls in array array['ops_roster', 'ops_roster_set', 'ops_profile_lookup'] loop
      select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = v_cls;
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || v_cls || ')'; continue; end if;
      -- the NULL-ACL arm FIRST: a definer born PUBLIC-executable has a NULL `proacl`, and every
      -- `has_function_privilege` arm below is TRUE in that world (0116:636's class)
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' 🔴 ' || v_cls || ': ACL이 NULL이다 (PUBLIC 실행으로 태어났다)'; end if;
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' ' || v_cls || ': definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
            from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' ' || v_cls || ': 본문 search_path 없음'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' ' || v_cls || ': anon에 열려 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' ' || v_cls || ': authenticated가 실행할 수 없다 (콘솔이 부른다)'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = ''
        then v_bad := v_bad || ' NO-SOURCE(' || v_cls || ')'; continue; end if;
      -- comments STRIPPED: 0208 argues the gate at length INSIDE these bodies, so an un-stripped
      -- match is satisfied by the prose rather than by the code
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      if (position('ops_recipients_for(c_ops_class)' in v_src) > 0) is not true
        then v_bad := v_bad || ' 🔴 ' || v_cls || ': 게이트가 없다'; end if;
      if (v_src ~ 'raise exception ''not_ops''') is not true
        then v_bad := v_bad || ' ' || v_cls || ': not_ops 거절이 없다'; end if;
      if (v_src ~ 'raise exception ''not_signed_in''') is not true
        then v_bad := v_bad || ' ' || v_cls || ': not_signed_in 거절이 없다'; end if;
      -- CRUDE CONTROL: the raw source DOES carry the word, so a stripper that blanked the whole
      -- body would not read as a clean pass
      if (v_raw ~ 'ops_recipients_for') is not true
        then v_bad := v_bad || ' 대조: ' || v_cls || '의 원본에 ops_recipients_for가 없다 (주석 제거 팔이 무의미)'; end if;
    end loop;

    -- ── ops_roster: the gate precedes the roster read, and inactive rows are NOT filtered out
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_roster';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_roster)';
    else
      if position('ops_recipients_for(c_ops_class)' in v_src)
           >= position('from ops_recipients r' in v_src)
        then v_bad := v_bad || ' 🔴 명부 읽기: 게이트가 읽기보다 뒤에 있다'; end if;
      if (v_src ~ 'from ops_recipients r[^_]') is not true
        then v_bad := v_bad || ' 명부 읽기: 명부 테이블을 읽지 않는다'; end if;
      if (v_src ~ 'where\s+r\.active') is not false
        then v_bad := v_bad || ' 🔴 명부 읽기가 비활성 행을 걸러낸다 (전 당번이 보이지 않는다)'; end if;
    end if;

    -- ── ops_roster_set: the gate precedes the first read, the allowlist names every class, the
    --    last-operator guard is scoped and present, and the journal is written
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_roster_set';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_roster_set)';
    else
      if position('ops_recipients_for(c_ops_class)' in v_src) >= position('from profiles p' in v_src)
        then v_bad := v_bad || ' 🔴 쓰기: 게이트가 프로필 읽기보다 뒤에 있다'; end if;
      foreach v_cls in array c_classes loop
        if (position('''' || v_cls || '''' in v_src) > 0) is not true
          then v_bad := v_bad || ' 🔴 허용목록에 [' || v_cls || ']가 없다'; end if;
      end loop;
      if (v_src ~ 'raise exception ''last_operator''') is not true
        then v_bad := v_bad || ' 🔴 마지막 운영자 거절이 없다'; end if;
      if (v_src ~ 'p_event_class\s*=\s*c_ops_class') is not true
        then v_bad := v_bad || ' 🔴 마지막 운영자 가드가 payout_due로 좁혀져 있지 않다'; end if;
      if (v_src ~ 'for update') is not true
        then v_bad := v_bad || ' 🔴 대상 행을 잠그지 않는다 (두 터미널이 동시에 마지막 둘을 끈다)'; end if;
      if (v_src ~ 'insert into ops_roster_changes') is not true
        then v_bad := v_bad || ' 🔴 장부 기록이 없다'; end if;
      -- the upsert must name the constraint. An inference spec `on conflict (profile_id, …)` is an
      -- EXPRESSION context and collides with this function's own `returns table` OUT parameters —
      -- measured as a runtime death on this suite's first run, invisible to a gate-only pin.
      if (v_src ~ 'on conflict on constraint ops_recipients_pkey') is not true
        then v_bad := v_bad || ' 🔴 upsert가 제약 이름을 쓰지 않는다 (추론 스펙은 OUT 파라미터와 충돌해 런타임에 죽는다)'; end if;
      if (v_src ~ 'raise exception ''unknown_class''') is not true
        then v_bad := v_bad || ' unknown_class 거절이 없다'; end if;
      if (v_src ~ 'delete from ops_recipients') is not false
        then v_bad := v_bad || ' 🔴 내리기가 행을 지운다 (0084: 전 당번은 감사 사실이다)'; end if;
      -- `created_at` must not be in the ON CONFLICT update (notification order · first-on-call)
      if (v_src ~ 'do update set[^;]*created_at') is not false
        then v_bad := v_bad || ' 🔴 on conflict가 created_at을 덮어쓴다'; end if;
    end if;

    -- ── ops_profile_lookup: gate first, narrow, escaped, capped, tombstone-free
    select prosrc into v_raw from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_profile_lookup';
    v_src := regexp_replace(coalesce(v_raw, ''), '--[^' || chr(10) || ']*', '', 'g');
    if v_raw is null then v_bad := v_bad || ' NO-SOURCE(ops_profile_lookup)';
    else
      if position('ops_recipients_for(c_ops_class)' in v_src) >= position('from profiles p' in v_src)
        then v_bad := v_bad || ' 🔴 조회: 게이트가 프로필 읽기보다 뒤에 있다'; end if;
      if (v_src ~ '\mp\.phone\M') is not false
        then v_bad := v_bad || ' 🔴 조회가 전화번호를 읽는다'; end if;
      if (v_src ~ '\mp\.handle\M') is not false
        then v_bad := v_bad || ' 🔴 조회가 handle을 읽는다'; end if;
      if (v_src ~ '\mp\.district\M') is not false
        then v_bad := v_bad || ' 🔴 조회가 district를 읽는다'; end if;
      if (v_src ~ '\mp\.avatar_url\M') is not false
        then v_bad := v_bad || ' 🔴 조회가 avatar_url을 읽는다'; end if;
      if (v_src ~ 'deleted_at is null') is not true
        then v_bad := v_bad || ' 🔴 조회가 탈퇴 프로필을 거르지 않는다'; end if;
      if (v_src ~ 'escape') is not true
        then v_bad := v_bad || ' 🔴 조회가 와일드카드를 리터럴화하지 않는다 (검색창이 덤프가 된다)'; end if;
      if (v_src ~ 'limit c_limit') is not true
        then v_bad := v_bad || ' 조회에 상한이 없다'; end if;
      if (v_src ~ 'raise exception ''short_query''') is not true
        then v_bad := v_bad || ' short_query 거절이 없다'; end if;
      if (v_src ~ 'order by p\.name') is not true
        then v_bad := v_bad || ' 조회 결과의 순서가 이름순이 아니다'; end if;
    end if;

    -- ── the journal table is sealed, and carries NO foreign key (audit facts outlive profiles)
    if (select relrowsecurity from pg_class where oid = 'ops_roster_changes'::regclass) is not true
      then v_bad := v_bad || ' 장부에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_roster_changes')
      then v_bad := v_bad || ' 장부에 정책이 있다 (클라이언트 표면)'; end if;
    if has_table_privilege('authenticated', 'public.ops_roster_changes', 'select') is not false
      then v_bad := v_bad || ' 장부가 authenticated에 열려 있다'; end if;
    if has_table_privilege('anon', 'public.ops_roster_changes', 'select') is not false
      then v_bad := v_bad || ' 장부가 anon에 열려 있다'; end if;
    if (select count(*)::int from pg_constraint
         where conrelid = 'ops_roster_changes'::regclass and contype = 'f') is distinct from 0
      then v_bad := v_bad || ' 🔴 장부에 외래키가 생겼다 (cascade는 감사 사실을 지우고 restrict는 탈퇴를 막는다 — 0186 §A·0194 §D)'; end if;
    if (select count(*)::int from information_schema.columns
         where table_schema = 'public' and table_name = 'ops_roster_changes'
           and column_name in ('actor', 'profile', 'class', 'active', 'at')) is distinct from 5
      then v_bad := v_bad || ' 장부의 다섯 칸(actor·profile·class·active·at)이 다 있지 않다'; end if;

    -- ── 0084 §E's seal on `ops_recipients` itself. ⚠ THE SEAL IS 「RLS on, ZERO policies」 AND NOT
    --    「no grant」: supabase's default privileges grant `all on tables` to anon/authenticated
    --    for every table postgres creates (the shim mirrors production at `00_shim.sql:128`), so
    --    a grant arm here would be a FALSE arm that has never been true. 120 G1 and 229 read it
    --    the same way.
    if (select relrowsecurity from pg_class where oid = 'ops_recipients'::regclass) is not true
      then v_bad := v_bad || ' 🔴 ops_recipients의 RLS가 꺼졌다'; end if;
    if (select count(*)::int from pg_policies
         where schemaname = 'public' and tablename = 'ops_recipients') is distinct from 0
      then v_bad := v_bad || ' 🔴 ops_recipients에 정책이 생겼다 (0208은 문을 더하지 표면을 열지 않는다)'; end if;

    -- ── the lookup's column set, again, where a later recreation would be seen
    select p.proargnames into v_names from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_profile_lookup';
    if v_names is distinct from array['p_query', 'id', 'name', 'role']
      then v_bad := v_bad || ' 🔴 조회 창구의 열 집합=' || coalesce(v_names::text, '(null)'); end if;

    if v_bad = ''
      then call _pass('orx','0208-S1 배포 형상 — 세 함수 모두 definer에 본문 search_path를 갖고 ACL이 NULL이 아니며(PUBLIC으로 태어나지 않았다) anon에는 닫히고 authenticated에는 열리고, 주석 벗긴 소스에서 게이트가 **읽기보다 앞**에 있다(명부는 ops_recipients 읽기보다, 나머지 둘은 profiles 읽기보다); 명부는 비활성 행을 거르지 않고; 쓰기는 열다섯 클래스를 다 들고 있고 마지막 운영자 거절이 payout_due로 좁혀져 있고 대상 행을 잠그고 장부를 쓰고 행을 지우지 않고 on conflict에서 created_at을 덮지 않으며; 조회는 phone·handle·district·avatar를 읽지 않고 탈퇴를 거르고 escape·상한·이름순을 갖고 열 집합이 정확히 p_query·id·name·role이다; 장부는 봉인이고 외래키가 없고 다섯 칸이 있으며; ops_recipients의 0084 §E 봉인(RLS on·정책 0)은 그대로다. 원본 소스 크루드 대조와 NO-FUNCTION·NO-SOURCE 팔 포함');
    else v_msg := v_bad; call _fail('orx','0208-S1 배포 형상', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('orx','0208-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
