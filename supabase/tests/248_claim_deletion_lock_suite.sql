-- ═══ 248 — 0217: a gear claim cannot resume behind the tombstone
-- ═══        0217-A1 · B1 · C1 · D1 · E1 · S1, tag `tomb` (+ R1 in 248_claim_deletion_race.sh)
-- ═══        (helpers are `t_cdl_*`; the `_t` tag is `tomb` because suite 180 already owns `cdl`)
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation (the
-- mid-battery law): a pin written while staring at a mutation asserts what that mutation broke
-- rather than the property the guard exists to hold.
--
--   · A1 **A TOMBSTONED CALLER CANNOT CLAIM.** After the REAL deletion (`delete_my_account_tx`,
--        the only writer of `profiles.deleted_at` — 0202 §B⑤) a `claimable` row the deletion left
--        untouched answers `profile_deleted` to its owner, for the row's own id AND for NULL (the
--        gate precedes the NULL-id arm), the row is byte-identical afterwards (still `claimable`,
--        `delivery` still NULL — 0217 §0d: the address-less row stays TRUE of itself), and no ops
--        bell rang. CONTROL on an identical fixture: a live runner's claim goes through.
--   · B1 **THE OPS QUEUE DOES NOT HAND OUT AN ADDRESS WRITTEN BEHIND A TOMBSTONE.** The fixture is
--        the hole's END STATE built by hand — a claimed row with all five fields live, whose owner's
--        `deleted_at` is then stamped DIRECTLY, bypassing 0202 §B②'s redaction. The marker rule
--        cannot see this row (nothing says `redacted`); only the join can. Its id and each of the
--        five strings are absent from the whole payload. CONTROLS: a live runner's claim is listed
--        with its fields, and 0202's marker exclusion still fires for a live profile's redacted row
--        (the two exclusions cover different failures — 0217 §B).
--   · C1 **SHIP REFUSES A TOMBSTONED OWNER'S CLAIM, BY 0202's NAME, WRITING NOTHING.** The same
--        hand-built row answers `claim_redacted`; status, carrier and tracking are untouched.
--        0202's gate ORDER survives: a tombstoned owner's `shipped` row still answers
--        `already_shipped`, their `claimable` row still answers `not_claimed`. CONTROL: a live
--        runner's claim ships and carries the carrier and tracking it was given.
--   · D1 **THE NON-DELETED PATH IS 0214's, BELL INCLUDED.** A live runner claims → `claimed`, the
--        five fields are read back from the row, the ops bell reached EXACTLY the active
--        `payout_due` roster (count == `ops_recipients_for`, and ≥ 1 — the fixture seeds one), the
--        re-claim is `already_claimed = true` and rings NO second bell. This is the positive control
--        every other pin's refusal is measured against — without it 「refuse everyone」 is green.
--   · E1 **NO ORACLE, ON EITHER SIDE OF THE TOMBSTONE.** A live stranger: foreign id == missing
--        uuid == `not_claim_owner` (0214's word, unchanged). A tombstoned stranger: foreign id ==
--        missing uuid == their OWN id == `profile_deleted` — the answer is a function of the caller
--        alone and carries nothing about the row. Both refusals moved no row.
--   · S1 **DEPLOYED SHAPE**, comments stripped: in `claim_gear_tx` the profile read is one
--        statement with its `for share`, that lock PRECEDES the first `for update` (the claim row —
--        deletion's own order, 0217 §0b), and `profile_deleted` precedes both the ownership refusal
--        and the claim read; 0214's scoping and its `claim_not_found` absence are inherited. Both
--        ops readers join `profiles` and read `deleted_at` (pending: `is null` exclusion; ship:
--        an exact boolean in the same `for update of g` statement, the join side unlocked). All
--        three: definer, in-body search_path, anon revoked, authenticated granted. NO-FUNCTION /
--        NO-SOURCE are red, never silent.
--   · R1 (`248_claim_deletion_race.sh`, two psql processes) **THE LOCK ITSELF.** Deletion held open
--        across `pg_sleep(2)` while a claim arrives at 0.6 s: the claim waits at the profile row and
--        refuses `profile_deleted` once the tombstone commits; the row is still `claimable` with
--        `delivery` NULL. ⚠ This is the ONLY arm that reads the lock. Every pin in this file is
--        single-session and is green under a plain, lock-free read of `deleted_at` (M1b below).
--
-- ─── REPRODUCTION ON TRUNK'S BODY (MEASURED, before the fix — Codex's finding is READ) ───
--   This suite run against trunk `792a16d` with `0217_claim_deletion_lock.sql` ABSENT → **1487/6**:
--   A1 red 「탈퇴한 사람의 신청이 ACCEPTED:claimed」 — the tombstoned runner's claim was ACCEPTED and
--   the row now carries {"phone": "01021700217", "postal": "06590", …} behind the tombstone · B1 red
--   — the ops list carries the claim id and all five strings · C1 red 「ACCEPTED:shipped」 — the box
--   ships with a carrier and tracking · E1 red — the tombstoned stranger's OWN id answers
--   ACCEPTED:claimed while a foreign id answers not_claim_owner · S1 red (every profile arm absent)
--   · R1 red 「tomb=t row=claimed/false refused=0」 — the in-flight claim committed its address
--   before the tombstone did. D1 green (the live path was never the defect). With 0217: 1493/0.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins) ───
--   · The 「claim first, deletion second」 interleaving (0217 §0b's second bullet: deletion's
--     redaction statement sees the just-committed address). The race script holds DELETION open,
--     not the claim; holding the claim open would need `claim_gear_tx` to sleep, which it cannot.
--     The property rests on 0202 §B② (pinned by 233 `0202-B1`) plus READ COMMITTED's per-statement
--     snapshot in a VOLATILE plpgsql body — READ, from the PostgreSQL contract, not observed.
--   · Whether a second signed-in device's cached JWT can still reach `claim_gear_tx` after
--     `auth.admin.deleteUser`. That is a property of GoTrue's token lifetime; the server answer to
--     such a call is what A1 measures.
--
-- ─── BATTERY (MEASURED 2026-09-25; control 1493/0 FIRST; every plant asserted by `plant.py` and
--     `&&`-chained to the harness so an unlanded plant yields NO row; each mutation run twice —
--     VERIFY intact, then VERIFY disarmed — because an apply abort measures the VERIFY, not us) ───
--   M1a  the profile lock AND the refusal deleted (0214's body)
--                          → intact: APPLY ABORTS at 0217 VERIFY · disarmed: 1489/4 A1 · E1 · S1 · R1
--   M1b  `for share` removed, the refusal KEPT — a plain, lock-free read of `deleted_at`
--                          → intact: APPLY ABORTS · disarmed: **1491/2 S1 · R1**
--        🔴 every single-session pin (A1 B1 C1 D1 E1) is GREEN under M1b. The race arm is the only
--        behavioural witness to the lock; that measurement is why 248_claim_deletion_race.sh exists.
--   M2   pending's `p.deleted_at is null` deleted (join kept)
--                          → intact: APPLY ABORTS · disarmed: 1491/2 B1 · S1
--   M3   ship's `v_tombstone is not false` deleted
--                          → intact: APPLY ABORTS · disarmed: 1491/2 C1 · S1
--   M4   lock ORDER swapped — the claim row locked first, the profile second
--                          → intact: APPLY ABORTS · disarmed: 1491/2 S1 · A1
--        A1's 「the gate precedes the NULL-id arm」 arm is an unplanned behavioural witness to the
--        order. R1 stays green, as reasoned: with the profile taken second the claim still waits at
--        it and refuses; the order is observable by source and by a deadlock this fixture cannot
--        manufacture (deletion locks only delivery-holding claim rows).
--   M5   `revoke … claim_gear_tx … from public, anon` deleted
--                          → intact 1493/0 AND disarmed 1493/0 — **reddens NOTHING here, and that is
--        an UNREACHABLE state, not a blind pin**: the harness applies every migration in order from
--        scratch, so 0195's revoke is preserved by 0217's `create or replace` and every runtime ACL
--        sweep (98 H1/H9, S1's ACL arm) is green however many files rely on preservation. The gate
--        is the detector: `MIGRATIONS_DIR=<M5 copy> node scripts/check-definer-acl.mjs` → exit 1
--        naming 0217/claim_gear_tx; the unplanted copy → exit 0 (control).
--   Restored after every plant; the worktree harness re-run green after the LAST edit (1493/0).
-- ═══════════════════════════════════════════════════════════
set client_min_messages = warning;

create or replace function t_cdl_claim(p_owner uuid, p_item text, p_status claim_status)
returns uuid language sql as $$
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (p_owner, 'runner', p_item, 10, p_status) returning id
$$;

-- the claim row as the TABLE holds it — pins read this, never a function's answer
create or replace function t_cdl_row(p_claim uuid) returns jsonb language sql as $$
  select jsonb_build_object(
    'status', g.status::text, 'item', g.item,
    'claimed', (g.claimed_at is not null),
    'delivery', g.delivery, 'delivery_text', coalesce(g.delivery::text, ''),
    'delivery_null', (g.delivery is null),
    'carrier', g.delivery_carrier, 'tracking', g.delivery_tracking,
    'dispatched', (g.dispatched_at is not null))
  from gear_claims g where g.id = p_claim
$$;

-- call claim_gear_tx as someone; the jwt is cleared on BOTH paths (218 ①'s rule)
create or replace function t_cdl_claim_as(p_uid uuid, p_claim uuid) returns jsonb
language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from claim_gear_tx(p_claim, '최툼스톤', '010-2170-0217', '서울시 서초구 반포대로 217', '0217호', '06590');
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('status', r.status, 'already', r.already_claimed);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_cdl_pending_as(p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_agg(jsonb_build_object('claim', claim_id, 'recipient', recipient,
             'phone', phone, 'address1', address1, 'address2', address2, 'postal', postal)
             order by claim_id), '[]'::jsonb)
      into v from ops_gear_claims_pending();
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('rows', v);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_cdl_ship_as(p_uid uuid, p_claim uuid) returns jsonb
language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from ops_mark_gear_shipped(p_claim, 'CJ대한통운', 'cdl-1234567890');
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('status', r.status, 'carrier', r.carrier, 'tracking', r.tracking);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- the ops bells this claim rang
create or replace function t_cdl_bells(p_claim uuid) returns int language sql as $$
  select count(*)::int from notifications
   where ref_id = p_claim and kind = 'system' and title = '굿즈 수령 신청 — 확인 필요'
$$;

do $$
declare
  ops1     uuid;   -- an active `payout_due` operator
  rLive    uuid;   -- the control runner (never deleted)
  rGone    uuid;   -- deleted by the REAL deletion, with a claimable row left behind (A1)
  rSnap    uuid;   -- tombstoned DIRECTLY after claiming — the hole's end state (B1, C1)
  rX       uuid;   -- a live stranger (E1)
  rDX      uuid;   -- a tombstoned stranger (E1)
  cLive    uuid;   -- rLive's claim (D1 → listed in B1 → shipped in C1)
  cGone    uuid;   -- rGone's claimable row
  cSnap    uuid;   -- rSnap's claimed row with a live snapshot behind the tombstone
  cSnapSh  uuid;   -- rSnap's `shipped` row — C1's ordering control
  cSnapCl  uuid;   -- rSnap's `claimable` row — C1's ordering control
  cRedact  uuid;   -- rLive's second claim, redacted by marker — B1's 「0202 still fires」 control
  cDX      uuid;   -- rDX's own claimable row (E1: own id == foreign id == missing)
  v        jsonb;
  v_row    jsonb;
  v_before jsonb;
  v_bad    text;
  v_msg    text;
  v_word   text;
  v_a      text;
  v_b      text;
  v_c      text;
  v_n      int;
  v_roster int;
  v_src    text;
  v_oid    oid;
  fn       text;
  p1 int; p2 int; p3 int; p4 int; p5 int;
  ABSENT constant uuid := '00000000-0000-0000-0000-000000000217';
begin
  perform set_config('request.jwt.claim.sub', '', true);
  ops1  := t_user('cdl_ops',  'owner');
  rLive := t_user('cdl_live', 'runner');
  rGone := t_user('cdl_gone', 'runner');
  rSnap := t_user('cdl_snap', 'runner');
  rX    := t_user('cdl_x',    'runner');
  rDX   := t_user('cdl_dx',   'runner');
  insert into ops_recipients (profile_id, event_class, active) values (ops1, 'payout_due', true);

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-D1] the non-deleted path, bell included — the positive control
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    cLive := t_cdl_claim(rLive, 'cdl 현역 캡', 'claimable');
    select count(*)::int into v_roster from ops_recipients_for('payout_due') as rc(profile_id);
    if v_roster < 1 then v_bad := v_bad || ' 픽스처: payout_due 명부가 비어 있다 (종을 잴 수 없다)'; end if;

    v := t_cdl_claim_as(rLive, cLive);
    if v->>'raised' is not null then v_bad := v_bad || ' 현역 러너의 신청이 거절됨: ' || (v->>'raised'); end if;
    if v->>'status' is distinct from 'claimed' then v_bad := v_bad || ' status=' || coalesce(v->>'status','NULL'); end if;
    if (v->>'already')::boolean is not false then v_bad := v_bad || ' 첫 신청이 already_claimed=true'; end if;
    v_row := t_cdl_row(cLive);
    if v_row->'delivery'->>'recipient' is distinct from '최툼스톤' then v_bad := v_bad || ' 받는사람이 행에 없다'; end if;
    if v_row->'delivery'->>'phone'     is distinct from '01021700217' then v_bad := v_bad || ' 전화가 숫자만으로 저장되지 않았다: ' || coalesce(v_row->'delivery'->>'phone','NULL'); end if;
    if v_row->'delivery'->>'postal'    is distinct from '06590' then v_bad := v_bad || ' 우편번호가 행에 없다'; end if;
    -- the bell reached exactly the roster
    v_n := t_cdl_bells(cLive);
    if v_n is distinct from v_roster
    then v_bad := v_bad || ' 종이 명부(' || v_roster || '명)와 다르게 울렸다: ' || v_n; end if;
    -- the re-claim is the flat field and rings nothing
    v := t_cdl_claim_as(rLive, cLive);
    if (v->>'already')::boolean is not true then v_bad := v_bad || ' 재신청이 already_claimed=true가 아니다: ' || coalesce(v->>'raised', v->>'status', 'NULL'); end if;
    if t_cdl_bells(cLive) is distinct from v_n then v_bad := v_bad || ' 재신청이 종을 또 울렸다'; end if;
    -- and the profile is, of course, not tombstoned
    if (select deleted_at from profiles where id = rLive) is not null then v_bad := v_bad || ' 현역 러너에게 툼스톤이 찍혔다'; end if;

    if v_bad = '' then call _pass('tomb','0217-D1 살아 있는 러너의 길은 0214 그대로다 — 신청은 claimed, 다섯 칸은 행에서 되읽히고(전화는 숫자만), ops 종은 활성 payout_due 명부 수와 정확히 같게 울리며(≥1, 픽스처가 한 명을 앉힌다), 재신청은 already_claimed=true 플랫 필드이고 종을 다시 울리지 않는다. 🔴 이 핀이 다른 모든 거절 핀의 양성 대조다 — 없으면 「모두 거절」하는 함수도 초록이다');
    else v_msg := v_bad; call _fail('tomb','0217-D1 live path unchanged', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('tomb','0217-D1 live path unchanged', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-A1] 🔴 a tombstoned caller cannot claim — the REAL deletion, the row it left behind
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    cGone := t_cdl_claim(rGone, 'cdl 탈퇴자 후디', 'claimable');
    perform set_config('request.jwt.claim.sub', '', true);
    perform delete_my_account_tx(rGone);
    -- the fixture must CONTAIN the defect's precondition: a tombstone, and a claimable row the
    -- deletion did not touch (delivery NULL, so 0202 §B②'s redaction had nothing to redact)
    if (select deleted_at from profiles where id = rGone) is null
    then v_bad := v_bad || ' 픽스처: 탈퇴가 툼스톤을 찍지 않았다'; end if;
    v_before := t_cdl_row(cGone);
    if v_before->>'status' is distinct from 'claimable' or (v_before->>'delivery_null')::boolean is not true
    then v_bad := v_bad || ' 픽스처: 탈퇴가 claimable 행을 건드렸다 (' || coalesce(v_before->>'status','NULL') || ')'; end if;

    v := t_cdl_claim_as(rGone, cGone);
    v_a := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_a is distinct from 'profile_deleted'
    then v_bad := v_bad || ' 🔴 탈퇴한 사람의 신청이 ' || v_a || ' — profile_deleted 여야 한다'; end if;
    -- the gate precedes the NULL-id arm
    v := t_cdl_claim_as(rGone, null);
    if coalesce(v->>'raised','ACCEPTED') is distinct from 'profile_deleted'
    then v_bad := v_bad || ' NULL id 로는 ' || coalesce(v->>'raised','ACCEPTED') || ' (게이트가 NULL-id 팔보다 뒤에 있다)'; end if;
    -- the refusal wrote nothing: the row is byte-identical and no bell rang
    if t_cdl_row(cGone) is distinct from v_before
    then v_bad := v_bad || ' 🔴 거절이 행을 바꿨다: ' || (t_cdl_row(cGone))::text; end if;
    if t_cdl_bells(cGone) is distinct from 0
    then v_bad := v_bad || ' 거절된 신청이 ops 종을 울렸다'; end if;
    -- and no address exists anywhere behind this tombstone (the finding's sentence, negated)
    select count(*)::int into v_n from gear_claims g join profiles p on p.id = g.profile_id
     where p.id = rGone and g.delivery is not null;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 툼스톤 뒤에 배송지가 ' || v_n || '건 있다'; end if;

    if v_bad = '' then call _pass('tomb','0217-A1 🔴 탈퇴한 사람은 신청할 수 없다 — 진짜 탈퇴(delete_my_account_tx)가 남긴 claimable 행(delivery NULL, 0202 §B②의 지움이 건드릴 것이 없던 행)에 대해 본인 id 로도 NULL 로도 profile_deleted 한 낱말이고(게이트가 NULL-id 팔보다 앞), 행은 바이트 그대로이며(여전히 claimable · delivery NULL — 자기 자신에 대해 참인 상태), 종은 안 울렸고, 툼스톤 뒤에 배송지가 0건이다. 픽스처가 툼스톤과 손대지 않은 행을 실제로 들고 있음을 먼저 단언한다. 양성 대조는 D1');
    else v_msg := v_bad; call _fail('tomb','0217-A1 tombstoned caller refused', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('tomb','0217-A1 tombstoned caller refused', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-B1] the ops queue does not hand out an address written behind a tombstone
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the hole's END STATE, by hand: claim while live, then stamp the tombstone DIRECTLY so the
    -- redaction never runs — exactly what a claim resuming after deletion produces on trunk
    cSnap := t_cdl_claim(rSnap, 'cdl 툼스톤 뒤 스냅샷', 'claimable');
    v := t_cdl_claim_as(rSnap, cSnap);
    if v->>'raised' is not null then v_bad := v_bad || ' 픽스처: 살아 있을 때의 신청이 거절됨: ' || (v->>'raised'); end if;
    update profiles set deleted_at = now() where id = rSnap;
    v_row := t_cdl_row(cSnap);
    if v_row->'delivery'->>'recipient' is distinct from '최툼스톤'
    then v_bad := v_bad || ' 픽스처: 툼스톤 뒤에 살아 있는 스냅샷이 없다 — 이 핀은 빈 세계의 부재를 재고 있다'; end if;
    if (select deleted_at from profiles where id = rSnap) is null then v_bad := v_bad || ' 픽스처: 툼스톤이 없다'; end if;
    -- 0202's marker rule cannot see this row — stated, and the reason the join exists
    if coalesce(v_row->'delivery' ? 'redacted', false) is not false
    then v_bad := v_bad || ' 픽스처: 행에 redacted 표식이 있다 — 표식 규칙이 잡는 행이라 이 핀의 대상이 아니다'; end if;
    -- the 「0202 still fires」 control: a LIVE profile's redacted row
    cRedact := t_cdl_claim(rLive, 'cdl 지워진 행', 'claimable');
    update gear_claims set status = 'claimed', claimed_at = now(), delivery = '{"redacted": true}'::jsonb where id = cRedact;

    v := t_cdl_pending_as(ops1);
    if v->>'raised' is not null then v_bad := v_bad || ' ops 목록이 거절됨: ' || (v->>'raised');
    else
      if (select count(*) from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cSnap) <> 0
      then v_bad := v_bad || ' 🔴 툼스톤 뒤의 신청이 발송 대기 목록에 있다'; end if;
      foreach v_word in array array['최툼스톤', '01021700217', '서울시 서초구 반포대로 217', '0217호', '06590'] loop
        -- rLive typed the SAME five strings, and is listed — so the absence is asserted on the
        -- payload with rLive's row removed, not on the whole payload
        if position(v_word in (select coalesce(jsonb_agg(e), '[]'::jsonb)::text
                                 from jsonb_array_elements(v->'rows') e
                                where (e->>'claim')::uuid is distinct from cLive)) > 0
        then v_bad := v_bad || ' 🔴 목록에 「' || v_word || '」 가 툼스톤 뒤 행에서 실려 있다'; end if;
      end loop;
      if (select count(*) from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cRedact) <> 0
      then v_bad := v_bad || ' 0202 의 표식 제외가 죽었다 — 살아 있는 프로필의 지워진 행이 목록에 있다'; end if;
      -- 🔴 THE CONTROL: the live runner's claim is listed, fields intact
      if (select count(*) from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cLive) <> 1
      then v_bad := v_bad || ' 🔴 대조: 현역 러너의 신청이 목록에서 사라졌다'; end if;
      if (select e->>'recipient' from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cLive) is distinct from '최툼스톤'
      then v_bad := v_bad || ' 대조: 현역 러너의 받는사람이 안 실렸다'; end if;
      if (select e->>'postal' from jsonb_array_elements(v->'rows') e where (e->>'claim')::uuid = cLive) is distinct from '06590'
      then v_bad := v_bad || ' 대조: 현역 러너의 우편번호가 안 실렸다'; end if;
    end if;

    if v_bad = '' then call _pass('tomb','0217-B1 ops_gear_claims_pending 은 툼스톤 뒤에 쓰인 주소를 내주지 않는다 — 픽스처는 구멍의 끝 상태를 손으로 만든 것(살아 있을 때 신청 → deleted_at 을 직접 찍어 0202 §B② 의 지움을 우회): redacted 표식이 없어 표식 규칙은 못 보고 조인만 본다. 그 id 도 다섯 칸의 글자 어느 것도 (현역 행을 뺀) 응답에 없다. 🔴 대조 둘 — 현역 러너의 신청은 받는사람·우편번호까지 그대로 나오고, 살아 있는 프로필의 지워진 행은 0202 의 표식 규칙으로 여전히 빠진다(두 제외는 서로 다른 실패를 덮는다)');
    else v_msg := v_bad; call _fail('tomb','0217-B1 pending excludes tombstoned owners', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('tomb','0217-B1 pending excludes tombstoned owners', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-C1] ship refuses a tombstoned owner's claim, by 0202's name, writing nothing
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_before := t_cdl_row(cSnap);
    v := t_cdl_ship_as(ops1, cSnap);
    v_a := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_a is distinct from 'claim_redacted'
    then v_bad := v_bad || ' 🔴 툼스톤 뒤 신청의 발송이 ' || v_a || ' — claim_redacted 여야 한다'; end if;
    if t_cdl_row(cSnap) is distinct from v_before
    then v_bad := v_bad || ' 🔴 거절이 행을 바꿨다: ' || (t_cdl_row(cSnap))::text; end if;
    -- 0202's gate ORDER survives for a tombstoned owner's other rows
    cSnapSh := t_cdl_claim(rSnap, 'cdl 이미 떠난 상자', 'claimable');
    update gear_claims set status = 'shipped', claimed_at = now(), dispatched_at = now(),
           delivery_carrier = '한진', delivery_tracking = 'cdl-gone-1',
           delivery = jsonb_build_object('recipient','최툼스톤','phone','01021700217','address1','서울시 서초구 반포대로 217','address2',null,'postal','06590')
     where id = cSnapSh;
    v := t_cdl_ship_as(ops1, cSnapSh);
    if v->>'raised' is distinct from 'already_shipped'
    then v_bad := v_bad || ' 순서: 툼스톤 주인의 shipped 행이 ' || coalesce(v->>'raised','ACCEPTED') || ' (already_shipped 여야)'; end if;
    cSnapCl := t_cdl_claim(rSnap, 'cdl 아직 신청 전', 'claimable');
    v := t_cdl_ship_as(ops1, cSnapCl);
    if v->>'raised' is distinct from 'not_claimed'
    then v_bad := v_bad || ' 순서: 툼스톤 주인의 claimable 행이 ' || coalesce(v->>'raised','ACCEPTED') || ' (not_claimed 여야)'; end if;
    -- 🔴 THE CONTROL: the live runner's claim ships
    v := t_cdl_ship_as(ops1, cLive);
    if v->>'raised' is not null then v_bad := v_bad || ' 🔴 대조: 현역 러너의 발송이 거절됨: ' || (v->>'raised'); end if;
    if v->>'status' is distinct from 'shipped' then v_bad := v_bad || ' 대조: status=' || coalesce(v->>'status','NULL'); end if;
    v_row := t_cdl_row(cLive);
    if v_row->>'carrier' is distinct from 'CJ대한통운' or v_row->>'tracking' is distinct from 'cdl-1234567890'
    then v_bad := v_bad || ' 대조: 택배사/송장이 행에 없다'; end if;

    if v_bad = '' then call _pass('tomb','0217-C1 툼스톤 주인의 신청은 발송할 수 없다 — 같은 손으로 만든 행에 claim_redacted(0202 의 낱말: 운영자가 할 일이 같다 — 신청을 취소하고 상자는 부치지 않는다), 행은 바이트 그대로. 0202 의 게이트 순서는 산다: 툼스톤 주인의 shipped 행은 already_shipped, claimable 행은 not_claimed. 🔴 대조: 현역 러너의 신청은 shipped 가 되고 택배사·송장이 행에 남는다');
    else v_msg := v_bad; call _fail('tomb','0217-C1 ship refuses tombstoned owners', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('tomb','0217-C1 ship refuses tombstoned owners', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-E1] no oracle on either side of the tombstone
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- a live stranger: foreign id (cGone, a real claimable row) == missing uuid, one word, 0214's
    v := t_cdl_claim_as(rX, cGone);
    v_a := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    v := t_cdl_claim_as(rX, ABSENT);
    v_b := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_a is distinct from 'not_claim_owner' then v_bad := v_bad || ' 낯선 사람 + 남의 id: ' || v_a; end if;
    if v_b is distinct from v_a then v_bad := v_bad || ' 🔴 낯선 사람에게 두 세계가 다르다 — real=' || v_a || ' absent=' || v_b; end if;
    -- a tombstoned stranger: foreign id == missing uuid == their OWN row, one word
    cDX := t_cdl_claim(rDX, 'cdl 탈퇴 낯선이의 것', 'claimable');
    perform set_config('request.jwt.claim.sub', '', true);
    perform delete_my_account_tx(rDX);
    if (select deleted_at from profiles where id = rDX) is null then v_bad := v_bad || ' 픽스처: 낯선이의 툼스톤이 없다'; end if;
    v := t_cdl_claim_as(rDX, cGone);
    v_a := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    v := t_cdl_claim_as(rDX, ABSENT);
    v_b := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    v := t_cdl_claim_as(rDX, cDX);
    v_c := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_a is distinct from 'profile_deleted' then v_bad := v_bad || ' 탈퇴 낯선이 + 남의 id: ' || v_a; end if;
    if v_b is distinct from v_a then v_bad := v_bad || ' 🔴 탈퇴 낯선이에게 두 세계가 다르다 — real=' || v_a || ' absent=' || v_b; end if;
    if v_c is distinct from v_a then v_bad := v_bad || ' 🔴 탈퇴 낯선이의 본인 id 가 다른 낱말 — own=' || v_c || ' foreign=' || v_a || ' (답이 호출자만의 함수가 아니다)'; end if;
    -- nothing moved
    select count(*)::int into v_n from gear_claims where id in (cGone, cDX) and (status <> 'claimable' or delivery is not null);
    if v_n is distinct from 0 then v_bad := v_bad || ' 거절이 행을 움직였다 (n=' || v_n || ')'; end if;

    if v_bad = '' then call _pass('tomb','0217-E1 오라클 없음, 툼스톤 양쪽에서 — 살아 있는 낯선 사람은 남의 id 와 없는 uuid 에 not_claim_owner 한 낱말(0214 그대로); 탈퇴한 낯선 사람은 남의 id·없는 uuid·**본인 id** 셋 모두에 profile_deleted 한 낱말이라 답이 호출자만의 함수이고 행에 대해 아무것도 싣지 않는다. 두 거절 모두 행을 움직이지 않았다. 양성 대조는 D1');
    else v_msg := v_bad; call _fail('tomb','0217-E1 no oracle either side', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('tomb','0217-E1 no oracle either side', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0217-S1] deployed shape — comments stripped, absence loud
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_oid := to_regprocedure('claim_gear_tx(uuid,text,text,text,text,text)');
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(claim_gear_tx)';
    else
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
      else
        p1 := position('from profiles p' in v_src);
        p2 := position('for share' in v_src);
        p3 := position('for update' in v_src);                       -- the FIRST one = the claim row
        p4 := position('raise exception ''profile_deleted''' in v_src);
        p5 := position('from gear_claims g' in v_src);
        if p1 = 0 then v_bad := v_bad || ' 프로필을 읽지 않는다'; end if;
        if p2 = 0 then v_bad := v_bad || ' 프로필 행 잠금(for share)이 없다'; end if;
        if p4 = 0 then v_bad := v_bad || ' profile_deleted 를 던지지 않는다'; end if;
        if (p1 > 0 and p2 > 0 and p1 < p2) is not true then v_bad := v_bad || ' 프로필 읽기와 잠금이 한 문장이 아니다'; end if;
        if (p2 > 0 and p3 > 0 and p2 < p3) is not true then v_bad := v_bad || ' 🔴 프로필 잠금이 교환권 행 잠금보다 뒤다 (탈퇴의 잠금 순서와 어긋난다)'; end if;
        if (p2 > 0 and p5 > 0 and p2 < p5) is not true then v_bad := v_bad || ' 프로필 잠금이 교환권 읽기보다 뒤다'; end if;
        if (p4 > 0 and p5 > 0 and p4 < p5) is not true then v_bad := v_bad || ' 탈퇴 게이트가 교환권 읽기보다 뒤다'; end if;
        if (p4 > 0 and p4 < position('raise exception ''not_claim_owner''' in v_src)) is not true
        then v_bad := v_bad || ' 탈퇴 게이트가 소유 거절보다 뒤다'; end if;
        if position('v_deleted is not null' in v_src) = 0 then v_bad := v_bad || ' 탈퇴 술어가 exact boolean 이 아니다'; end if;
        -- inherited from 0214, not regressed
        if position('g.profile_id = v_uid' in v_src) = 0 then v_bad := v_bad || ' 0214 의 호출자 스코프가 사라졌다'; end if;
        if position('claim_not_found' in v_src) > 0 then v_bad := v_bad || ' claim_not_found 가 돌아왔다'; end if;
      end if;
    end if;

    v_oid := to_regprocedure('ops_gear_claims_pending()');
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_gear_claims_pending)';
    else
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_gear_claims_pending)';
      else
        if position('join profiles p on p.id = g.profile_id' in v_src) = 0 then v_bad := v_bad || ' pending: profiles 조인이 없다'; end if;
        if position('p.deleted_at is null' in v_src) = 0 then v_bad := v_bad || ' pending: 툼스톤 제외절이 없다'; end if;
        if position('''redacted''' in v_src) = 0 then v_bad := v_bad || ' pending: 0202 의 표식 제외가 사라졌다'; end if;
        if (v_src ~ 'g\.status = ''claimed''') is not true then v_bad := v_bad || ' pending: 술어가 긍정 매칭이 아니다'; end if;
      end if;
    end if;

    v_oid := to_regprocedure('ops_mark_gear_shipped(uuid,text,text)');
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_mark_gear_shipped)';
    else
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_mark_gear_shipped)';
      else
        if position('join profiles p on p.id = g.profile_id' in v_src) = 0 then v_bad := v_bad || ' ship: profiles 조인이 없다'; end if;
        if position('(p.deleted_at is not null)' in v_src) = 0 then v_bad := v_bad || ' ship: 툼스톤을 boolean 으로 읽지 않는다'; end if;
        if position('for update of g' in v_src) = 0 then v_bad := v_bad || ' ship: 조인 쪽까지 잠근다 (탈퇴의 잠금 순서를 뒤집는다)'; end if;
        if position('v_tombstone is not false' in v_src) = 0 then v_bad := v_bad || ' ship: 툼스톤 주인을 거절하지 않는다'; end if;
        if position('''redacted''' in v_src) = 0 then v_bad := v_bad || ' ship: 0202 의 표식 거절이 사라졌다'; end if;
        -- the tombstone is read in the SAME statement as the lock (one row version)
        if (position('(p.deleted_at is not null)' in v_src) > 0
            and position('(p.deleted_at is not null)' in v_src) < position('for update of g' in v_src)) is not true
        then v_bad := v_bad || ' ship: 툼스톤이 잠금 문장 밖에서 읽힌다'; end if;
      end if;
    end if;

    foreach fn in array array['claim_gear_tx(uuid,text,text,text,text,text)',
                              'ops_gear_claims_pending()', 'ops_mark_gear_shipped(uuid,text,text)'] loop
      v_oid := to_regprocedure(fn);
      if v_oid is null then continue; end if;
      if (select prosecdef from pg_proc where oid = v_oid) is not true then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
      if (select coalesce(array_to_string(proconfig, ','), '') like '%search_path=public, pg_temp%' from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':SEARCH-PATH'; end if;
      if has_function_privilege('anon', v_oid, 'EXECUTE') is not false then v_bad := v_bad || ' ' || fn || ':ANON-EXECUTABLE'; end if;
      if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true then v_bad := v_bad || ' ' || fn || ':NO-AUTHENTICATED'; end if;
    end loop;

    if v_bad = '' then call _pass('tomb','0217-S1 배포 형상(주석 벗긴 prosrc) — claim_gear_tx: 프로필 읽기와 for share 가 한 문장이고 그 잠금이 첫 for update(교환권 행)보다 **앞**이며(탈퇴 트랜잭션의 순서 = 프로필 → 교환권 행), profile_deleted 가 소유 거절과 교환권 읽기보다 앞이고 술어는 exact boolean; 0214 의 호출자 스코프와 claim_not_found 부재는 물려받았다. pending: profiles 조인 + deleted_at is null + 0202 의 표식 제외 + 긍정 술어. ship: 조인 + (deleted_at is not null) 을 잠금 문장 **안**에서 + for update of g(조인 쪽은 안 잠근다) + v_tombstone is not false + 표식 거절. 셋 다 definer·본문 search_path·anon 거부·authenticated 허용. NO-FUNCTION/NO-SOURCE 는 빨갛다');
    else v_msg := v_bad; call _fail('tomb','0217-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('tomb','0217-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ⚠ PUT THE WORLD BACK for anything registered after this file: the operator seeded above is a
-- global input to every `payout_due` roster read (90's RP arm learned this the hard way).
delete from ops_recipients where profile_id in (select id from profiles where name = 'cdl_ops');
