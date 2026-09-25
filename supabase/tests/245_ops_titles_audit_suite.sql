-- ═══ 245 — 0214: the ops category stops being inherited by every `system` row · and
-- ═══        `claim_gear_tx` stops telling a stranger whether a uuid is a gear claim
-- ═══        0214-T1 · T2 · T3 · T4 · C1 · S1, tag `otx`
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · T1 **THE LEDGER IS THE MEASURED SET AND IT DID NOT SILENTLY MOVE.** `_noti_ops_titles()`
--        holds ELEVEN distinct titles and each of the eleven this suite spells out is a member.
--        🔴 Its sentence is 「the migration's array did not move」, not 「the array is correct」 —
--        this arm and the migration are two copies of one list, so agreement between them is one
--        claim counted twice. T4 and `app/test/ops-system-titles.test.cjs` own correctness, by
--        re-deriving the set from the WRITERS. Plus the attribution arm 0210-O2 taught: not one of
--        the eleven is a member of `_noti_urgent_noti_titles()`, so 「it went silent」 and 「it was
--        never always-on in the first place」 are distinguishable observations.
--   · T2 **EVERY OPS-ADDRESSED TITLE IS SILENCED BY `ops = false`, THROUGH THE REAL TRIGGER.**
--        All eleven, with all five columns false: push 0, `notifications` row 1. And the CROSS
--        arm — `ops` ON with the other four OFF — each of the eleven still pushes, so the silence
--        above is attributable to the `ops` column and to no other. Controls in the same arm: a
--        `kind='safety'` row still pushes, every `_noti_urgent_noti_titles()` member still pushes
--        as `kind='booking'` AND as `kind='system'` (the urgent arm sits above both system arms).
--   · T3 **A `system` TITLE NOBODY HAS LEDGERED IS NOT THE OPERATOR'S.** It classifies as
--        `booking`; it PUSHES with no prefs row (0187 §C's fail-open rule, kept); `ops = false`
--        alone does NOT silence it; `booking = false` with `ops` ON DOES. A NULL title lands the
--        same way, which is what stops a `case` arm on NULL collapsing into silence.
--        🔴 The fixture sits exactly where the OLD rule and the NEW rule DISAGREE: under 0210's
--        `when p_kind = 'system' then 'ops'` an unledgered title is `ops` and the last two arms
--        invert. A fixture using a ledgered title would be green in both worlds.
--   · T4 **THE DRIFT GUARD, SERVER SIDE: the set of DEPLOYED functions that write `kind='system'`
--        is exactly the declared writer list.** Read out of `pg_proc.prosrc`, comments stripped
--        first (a comment quoting a removed insert matches every grep that hunts for it), so a
--        later migration that adds a `system` writer reddens here until its title is ledgered.
--        🔴 Two-sided: every declared writer must also be FOUND, which is the control that stops
--        a broken matcher reading as a clean sweep.
--   · C1 **`claim_gear_tx` IS NOT AN EXISTENCE ORACLE.** A stranger gets the SAME word —
--        `not_claim_owner` — for a real claim id, a random uuid and NULL, and learns nothing about
--        the claim's state. CONTROL on the same id: the real owner gets through, so 「it refuses
--        everyone」 is excluded, and the refusal wrote nothing.
--   · S1 **DEPLOYED SHAPE.** The ledger and the classifier are pure/immutable and executable by
--        neither `anon` nor `authenticated`; `claim_gear_tx` is a definer with an in-body
--        `search_path`, revoked from `anon`, granted to `authenticated`; and in the classifier's
--        comment-stripped source the urgent arm PRECEDES both `system` arms, which is the ordering
--        every behavioural arm above depends on. NO-FUNCTION / NO-SOURCE fail loudly.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · The five `_shared/ops.ts` titles are pinned here only as ledger MEMBERS and as classifier
--     INPUTS. That those five strings are what `notifyOps` actually writes is a fact about a
--     TypeScript module, and no SQL pin can read one. `app/test/ops-system-titles.test.cjs` owns
--     it by reading `ops.ts` itself — the same source-vs-runtime division as `check-definer-acl`
--     beside 98 H1, and the same warning: **neither is evidence for the other.**
--   · Whether an OPERATOR is the person reading a `system` row. `ops_recipients_for` decides that
--     and 239 owns it.
--   · F4 (`transition-booking`'s `runner_accept` gate) is an edge function and is pinned by
--     `supabase/functions/_test/runner_accept_gate_test.ts`. Nothing in SQL can see it.
--   · The push itself. `00_shim.sql` stubs `net.http_post` into `net._stub_calls`, so what is
--     measured is 「the row → HTTP step was taken」, never that Expo delivered anything.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared explicitly in every arm (218 ①'s rule).
--  ② Every push measurement is a DELTA around one INSERT, never an absolute count — other suites
--     in this same database have already written to `net._stub_calls`.
--  ③ The fixture profile holds a real `ExponentPushToken…` in `push_tokens`. Without it
--     `notify_push` returns before the HTTP call for a reason that has nothing to do with
--     preferences, and every arm would read 0 — the fixture must contain the defect's
--     precondition (「a fixture that omits the defect cannot test the fix」).
set client_min_messages = warning;

-- One INSERT, measured both ways: how many stub calls it produced, and whether the row landed.
create or replace function t_otx_probe(p_profile uuid, p_kind noti_kind, p_title text)
returns jsonb language plpgsql as $$
declare v0 int; v1 int; v_row int; v_id uuid;
begin
  select count(*) into v0 from net._stub_calls;
  insert into notifications (profile_id, kind, title, body, ref_id)
       values (p_profile, p_kind, p_title, 'otx-probe', null)
    returning id into v_id;
  select count(*) into v1 from net._stub_calls;
  select count(*) into v_row from notifications where id = v_id;
  return jsonb_build_object('pushes', v1 - v0, 'row', v_row);
end $$;

create or replace function t_otx_set(p_uid uuid, p_b boolean, p_c boolean, p_m boolean,
                                     p_r boolean, p_o boolean)
returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  begin
    select * into r from set_notification_prefs(p_b, p_c, p_m, p_r, p_o);
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('ops', r.ops, 'booking', r.booking);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_otx_claim(p_owner uuid, p_item text) returns uuid language sql as $$
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (p_owner, 'runner', p_item, 10, 'claimable') returning id
$$;

-- Call `claim_gear_tx` as someone. Returns the raised token, or the row it answered with — the
-- STATE is returned on purpose, because 「a stranger learns the claim's status」 is half of C1.
create or replace function t_otx_claim_as(p_uid uuid, p_claim uuid) returns jsonb
language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from claim_gear_tx(p_claim, '김러너', '010-1234-5678', '반포동 1-2', null, '06500');
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('status', r.status, 'already', r.already_claimed);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

do $$
declare
  ops1 uuid; owner1 uuid; runner1 uuid; stranger uuid;
  claimA uuid; claimB uuid;
  v jsonb; v_bad text; v_msg text; v_n int; v_src text; v_txt text; v_a text; v_b text;
  ttl text; fn text; v_oid oid;
  ABSENT constant uuid := '00000000-0000-0000-0000-0000000002f5';
  -- ⚠ Spelled out here so a silent edit to the migration's array reddens T1. NOT a claim that the
  --   list is right — see T1's sentence above.
  OPS_TITLES constant text[] := array[
    '지급 대기 — 확인 필요',
    '인계 확인 멈춤 — 확인 필요',
    '반환 좌초 — 확인 필요',
    '굿즈 수령 신청 — 확인 필요',
    '카드 해지 실패 — 확인 필요',
    '클럽 취소 수수료 인텐트 실패 — 확인 필요',
    '결제 자동 취소 실패 — 수동 취소 필요',
    '이동 중 취소 보상 기록 실패 — 수동 확인 필요',
    '결제 취소 실패 기록이 남지 않았어요 — 즉시 확인 필요',
    '취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요',
    '운영 확인이 필요한 이벤트가 있어요',
    -- [0224] three more SQL writers (two custody strands, the sealed-unsettled run). 11 → 14; the
    -- property this list owns — 「the migration's array did not silently move」 — is unchanged, and
    -- 255 `0224-B2` owns the new titles against what the writers actually wrote.
    '러닝 시작 좌초 — 확인 필요',
    '러닝 종료 좌초 — 확인 필요',
    '정산 미완료 — 확인 필요',
    -- [0233/0234] four more SQL writers — 0233 arm ⓗ's pre-run incident bell and 0234's incident_opened
    -- bell (one title per severity). 14 → 18; this list's property is unchanged, and 264 `0233-B2` /
    -- 265 `0234-B2` own the new titles against what the writers actually wrote.
    '러닝 전 사고 검토 — 확인 필요',
    '사고 접수 — 확인 필요',
    '긴급 사고 접수 — 확인 필요',
    'SOS 사고 접수 — 즉시 확인 필요'];
  -- Every deployed function that writes `kind='system'`, with the migration that last declared it.
  -- A new entry here without a matching `_noti_ops_titles()` entry is what T4 + the client drift
  -- test exist to make loud.
  SYSTEM_WRITERS constant text[] := array[
    'ops_payouts_stuck_sweep',        -- 0210 §D
    'sweep_run_end_recovery',         -- 0201 §B (인계 확인 멈춤 ×2, 반환 좌초)
    'claim_gear_tx',                  -- 0206 §C → 0214 §C
    '_note_revocation_abandoned',     -- 0166 §B
    '_club_note_fee_mint_failure',    -- 0118
    '_sweep_custody_strands',         -- 0224 §C (러닝 시작 좌초 · 러닝 종료 좌초); 정산 미완료 rides sweep_run_end_recovery
    '_sweep_prerun_incidents',        -- 0233 §C (러닝 전 사고 검토)
    'open_incident_tx'];              -- 0234 §B (사고 접수 · 긴급 사고 접수 · SOS 사고 접수)
  UNLEDGERED constant text := '아직 아무도 쓰지 않은 운영 제목 (otx)';
begin
  perform set_config('request.jwt.claim.sub', '', true);                                        -- ①
  ops1     := t_user('otx_ops', 'owner');
  owner1   := t_user('otx_o', 'owner');
  runner1  := t_user('otx_r', 'runner');
  stranger := t_user('otx_x', 'runner');
  insert into push_tokens (profile_id, token) values (ops1, 'ExponentPushToken[otx-ops]')
  on conflict (profile_id) do nothing;                                                          -- ③

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-T1] the ledger: eleven, distinct, and none of them is in the always-on family
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if to_regprocedure('public._noti_ops_titles()') is null then
      v_bad := v_bad || ' NO-FUNCTION(_noti_ops_titles)';
    else
      if array_length(_noti_ops_titles(), 1) is distinct from 18                -- [0224] 11 → 14 · [0233/0234] → 18
      then v_bad := v_bad || ' the ledger holds '
                          || coalesce(array_length(_noti_ops_titles(), 1)::text, 'NULL')
                          || ' entries (this suite knows 18)'; end if;
      -- Duplicates are asked against the array's OWN length, never against 11: comparing to the
      -- expected size would make this arm fire on a ledger that merely changed size and print
      -- 「has duplicates」 about a list that has none — a true failure with a false reason, which is
      -- how a later session learns to distrust the message instead of the code.
      select count(*) into v_n from (select distinct unnest(_noti_ops_titles()) t) s;
      if v_n is distinct from coalesce(array_length(_noti_ops_titles(), 1), -1)
      then v_bad := v_bad || ' the ledger has duplicates (' || v_n || ' distinct of '
                          || coalesce(array_length(_noti_ops_titles(), 1)::text, 'NULL') || ')'; end if;

      -- each title this suite spells out is IN the deployed ledger …
      foreach ttl in array OPS_TITLES loop
        if (ttl = any (_noti_ops_titles())) is not true
        then v_bad := v_bad || ' the ledger lost 「' || ttl || '」'; end if;
      end loop;
      -- … and nothing is in the ledger that this suite does not know about
      foreach ttl in array _noti_ops_titles() loop
        if (ttl = any (OPS_TITLES)) is not true
        then v_bad := v_bad || ' the ledger gained 「' || coalesce(ttl, 'NULL')
                            || '」 — add it here and to app/test/ops-system-titles.test.cjs'; end if;
      end loop;

      -- 🔴 THE ATTRIBUTION ARM (0210-O2's, widened to eleven). If one of these were a member of
      -- the urgent family, its row would be `safety` BY TITLE and no column could ever gate it —
      -- so T2's zeros would be measuring a title that was never disableable, and the whole
      -- category would be a no-op wearing a green. Asked of the shipped array, by value.
      foreach ttl in array OPS_TITLES loop
        if (ttl = any (_noti_urgent_noti_titles())) is not false
        then v_bad := v_bad || ' the ops title 「' || ttl || '」 IS in the urgent family — no column can gate it'; end if;
      end loop;
    end if;

    if v_bad = '' then call _pass('otx','0214-T1 운영 제목 원장은 18개(0224가 셋, 0233·0234가 넷 추가)이고 중복이 없으며, 이 스위트가 적어 둔 18개와 정확히 같은 집합이다(양방향 — 잃어도 늘어도 빨개진다). 🔴 이 팔의 문장은 「마이그레이션의 배열이 몰래 움직이지 않았다」이지 「배열이 옳다」가 아니다: 옳음은 T4와 클라 드리프트 테스트가 쓰는 쪽에서 재유도한다. 그리고 귀속 팔 — 열한 개 중 어느 것도 _noti_urgent_noti_titles의 멤버가 아니므로 T2의 0은 「끌 수 있게 됐다」이지 「원래 끌 수 없던 적이 없다」가 아니다');
    else v_msg := v_bad; call _fail('otx','0214-T1 ops title ledger', v_msg); end if;
  exception when others then call _fail('otx','0214-T1 ops title ledger', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-T2] the walk — every ops-addressed title, through the real trigger
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;

    -- CONTROL FIRST, and it is what makes every 0 below mean something: with NO prefs row every
    -- one of the eleven reaches the HTTP stub. A notify_push that threw (its `exception when
    -- others` swallows into a skipped push) would give 0 here too, and only this arm separates
    -- those two worlds.
    foreach ttl in array OPS_TITLES loop
      v := t_otx_probe(ops1, 'system'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL(no prefs row) 「' || ttl || '」 pushes='
                          || coalesce(v->>'pushes','NULL'); end if;
    end loop;

    -- ALL FIVE OFF ⇒ every one of the eleven is silent, and every one keeps its row.
    perform t_otx_set(ops1, false, false, false, false, false);
    foreach ttl in array OPS_TITLES loop
      if _noti_push_category('system'::noti_kind, ttl) is distinct from 'ops'
      then v_bad := v_bad || ' 「' || ttl || '」 classifies as '
                          || coalesce(_noti_push_category('system'::noti_kind, ttl),'NULL')
                          || ' (expected ops)'; end if;
      v := t_otx_probe(ops1, 'system'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' all-off: 「' || ttl || '」 still pushed'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' all-off: 「' || ttl || '」 lost its notifications row — a preference gates the PUSH, never the record'; end if;
    end loop;

    -- CONTROLS in the same world: the always-on category did not move.
    v := t_otx_probe(ops1, 'safety'::noti_kind, '즉시 확인하세요');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' all-off: a kind=safety row was SILENCED — safety has no column and must never acquire one'; end if;
    foreach ttl in array _noti_urgent_noti_titles() loop
      v := t_otx_probe(ops1, 'booking'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' all-off: the urgent title 「' || ttl || '」 as kind=booking was silenced'; end if;
      -- and on a `system` row the urgent arm must still win, which is the ONE thing that keeps an
      -- ops writer borrowing an urgent title always-on
      v := t_otx_probe(ops1, 'system'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' all-off: the urgent title 「' || ttl || '」 on a system row was silenced — the urgent arm must sit ABOVE both system arms'; end if;
      if _noti_push_category('system'::noti_kind, ttl) is distinct from 'safety'
      then v_bad := v_bad || ' the urgent title 「' || ttl || '」 on a system row classifies as '
                          || coalesce(_noti_push_category('system'::noti_kind, ttl),'NULL'); end if;
    end loop;

    -- 🔴 THE CROSS ARM. `ops` ON, the other four OFF ⇒ all eleven arrive. A one-flag
    -- implementation, or a mapper that collapsed `ops` into `booking`, passes the arm above and
    -- dies here — it is what makes the silence attributable to the `ops` column.
    perform t_otx_set(ops1, false, false, false, false, true);
    foreach ttl in array OPS_TITLES loop
      v := t_otx_probe(ops1, 'system'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' ops ON / the other four off: 「' || ttl || '」 was silenced by somebody else''s column'; end if;
    end loop;

    delete from notification_prefs where profile_id = ops1;
    if v_bad = '' then call _pass('otx','0214-T2 운영 명부 앞으로 쓰이는 제목 14종 전부가 실제 트리거를 통과해 측정된다 — 설정 행이 없으면 14종 모두 발송(대조), 다섯 칸을 모두 끄면 14종 모두 조용해지고 notifications 행은 남으며, 반대로 ops만 켜고 넷을 끄면 14종 모두 다시 도착한다(귀속). 같은 세계에서 kind=safety와 긴급 제목 4종은 booking으로도 system으로도 그대로 나간다 — 긴급 팔이 두 system 팔보다 위에 있다는 뜻');
    else v_msg := v_bad; call _fail('otx','0214-T2 the ops walk', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('otx','0214-T2 the ops walk', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-T3] an unledgered `system` title does not inherit the operator's switch
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- 🔴 THE FIXTURE SITS WHERE THE TWO RULES DISAGREE. Under 0210's `when p_kind='system' then
  -- 'ops'` an unledgered title is `ops`, so the last two arms below INVERT. A fixture built on a
  -- ledgered title would be green in both worlds and would measure the fixture, not the rule.
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;

    if _noti_push_category('system'::noti_kind, UNLEDGERED) is distinct from 'booking'
    then v_bad := v_bad || ' an unledgered system title classifies as '
                        || coalesce(_noti_push_category('system'::noti_kind, UNLEDGERED),'NULL')
                        || ' (expected booking — the least-privileged DISABLEABLE category)'; end if;
    -- NULL: `= any(...)` is NULL, a `case` arm on NULL does not fire, and the row must land on
    -- `booking` rather than on NULL. This is the arm the NULL-collapse law is about.
    if _noti_push_category('system'::noti_kind, null) is distinct from 'booking'
    then v_bad := v_bad || ' a NULL title on a system row classifies as '
                        || coalesce(_noti_push_category('system'::noti_kind, null),'NULL')
                        || ' (expected booking)'; end if;

    -- CONTROL: with no prefs row it is SENT. 0187 §C's fail-open rule is untouched.
    v := t_otx_probe(ops1, 'system'::noti_kind, UNLEDGERED);
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' CONTROL(no prefs row): an unledgered system title was not sent'; end if;

    -- `ops = false` alone does NOT silence it — it is not the operator's category.
    perform t_otx_set(ops1, true, true, true, true, false);
    v := t_otx_probe(ops1, 'system'::noti_kind, UNLEDGERED);
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' ops=false silenced an UNLEDGERED system title — it would be muted by a switch its reader may not even be shown'; end if;

    -- `booking = false` with `ops` ON DOES silence it, and the row survives.
    perform t_otx_set(ops1, false, true, true, true, true);
    v := t_otx_probe(ops1, 'system'::noti_kind, UNLEDGERED);
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' booking=false did not silence an unledgered system title — it is gated by no column at all'; end if;
    if (v->>'row')::int is distinct from 1
    then v_bad := v_bad || ' the unledgered system title lost its notifications row'; end if;
    -- …and in the SAME world a LEDGERED title still arrives, which is what separates 「booking
    -- swallowed everything」 from 「the two system arms are genuinely different」.
    v := t_otx_probe(ops1, 'system'::noti_kind, '지급 대기 — 확인 필요');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' booking=false ALSO silenced a ledgered ops title — the two system arms collapsed into one'; end if;

    delete from notification_prefs where profile_id = ops1;
    if v_bad = '' then call _pass('otx','0214-T3 원장에 없는 system 제목은 운영자의 스위치를 물려받지 않는다 — 분류는 booking(끌 수 있는 최저 권한 칸), 설정 행이 없으면 그대로 발송(0187 §C 유지), ops=false 하나로는 조용해지지 않고 booking=false로는 조용해지며 행은 남는다. NULL 제목도 같은 쪽이다(= any(...)는 NULL이고 NULL 위의 case 팔은 켜지지 않는다). 🔴 픽스처가 두 규칙이 어긋나는 자리에 있다 — 0210의 `system이면 ops` 아래에서는 마지막 두 팔이 뒤집힌다');
    else v_msg := v_bad; call _fail('otx','0214-T3 unledgered system title', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('otx','0214-T3 unledgered system title', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-T4] the drift guard — the DEPLOYED `system` writers are exactly the declared set
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- Comments are stripped before matching. Two of this repo's own migrations carry comments that
  -- quote a notification insert while explaining it, and a comment that explains a writer would
  -- otherwise count as a writer (the standing comment-matching law). Whitespace is collapsed so a
  -- body wrapped across lines still matches — a formatting change must not make this pin BLIND,
  -- which is the dangerous direction for a gate.
  begin
    v_bad := '';
    -- ① nothing outside the declared set writes `kind='system'`
    for v_txt in
      select p.proname
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.prosrc is not null
         and regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
                            '\s+', ' ', 'g') like '%insert into notifications%'
         and regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
                            '\s+', ' ', 'g') like '%''system''%'
    loop
      if (v_txt = any (SYSTEM_WRITERS)) is not true
      then v_bad := v_bad || ' 🔴 UNDECLARED kind=system writer: ' || v_txt
                          || ' — add it to SYSTEM_WRITERS here, ledger its title in _noti_ops_titles(), and add it to app/test/ops-system-titles.test.cjs'; end if;
    end loop;

    -- ② 🔴 THE CONTROL, and it is the half that stops a broken matcher reading as a clean sweep:
    --    every declared writer must be FOUND by the same query. A pattern that stopped matching
    --    (a reformat, a renamed table, a stripper that ate too much) would make ① silent — a
    --    zero from a filtered sweep is the easiest false negative there is.
    foreach fn in array SYSTEM_WRITERS loop
      select count(*)::int into v_n
        from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = fn
         and p.prosrc is not null
         and regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
                            '\s+', ' ', 'g') like '%insert into notifications%'
         and regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'),
                            '\s+', ' ', 'g') like '%''system''%';
      if v_n is distinct from 1
      then v_bad := v_bad || ' the declared writer ' || fn || ' was NOT found by this pin''s own matcher (n='
                          || v_n || ') — either it stopped writing system rows, or the matcher is blind'; end if;
    end loop;

    if v_bad = '' then call _pass('otx','0214-T4 배포된 함수 중 kind=system 알림을 쓰는 것은 선언된 여덟 개뿐이다(0224가 _sweep_custody_strands, 0233이 _sweep_prerun_incidents, 0234가 open_incident_tx 추가) — prosrc에서 주석을 벗기고 공백을 접은 뒤 본다(주석이 제거된 코드를 인용하면 모든 grep이 맞는다는 법, 그리고 줄바꿈 하나로 게이트가 눈이 머는 쪽이 위험한 방향이라서). 🔴 양방향 — 선언된 다섯 개가 이 핀 자신의 매처로 실제로 발견되는지도 재므로, 매처가 깨져서 0을 돌려주는 것이 깨끗한 스윕으로 읽히지 않는다');
    else v_msg := v_bad; call _fail('otx','0214-T4 system writer drift', v_msg); end if;
  exception when others then call _fail('otx','0214-T4 system writer drift', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-C1] claim_gear_tx is not an existence oracle
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    claimA := t_otx_claim(runner1, 'otx-tee-A');
    claimB := t_otx_claim(runner1, 'otx-tee-B');

    -- a REAL claim id, a random uuid and NULL, all from the same stranger — ONE word.
    v := t_otx_claim_as(stranger, claimA);
    v_a := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_a is distinct from 'not_claim_owner'
    then v_bad := v_bad || ' stranger + a REAL claim id: ' || v_a; end if;

    v := t_otx_claim_as(stranger, ABSENT);
    v_b := coalesce(v->>'raised', 'ACCEPTED:' || coalesce(v->>'status','?'));
    if v_b is distinct from v_a
    then v_bad := v_bad || ' 🔴 the two worlds answer differently — real=' || v_a || ' absent=' || v_b; end if;

    v := t_otx_claim_as(stranger, null);
    if coalesce(v->>'raised','ACCEPTED') is distinct from v_a
    then v_bad := v_bad || ' a NULL claim id answers ' || coalesce(v->>'raised','ACCEPTED')
                        || ' instead of ' || v_a; end if;

    -- the STATE is not disclosed either: the same stranger against a claim in a DIFFERENT state
    -- must still get the one word. (`locked` is a state a runner can legitimately be told about —
    -- when it is their own.)
    update gear_claims set status = 'locked' where id = claimB;
    v := t_otx_claim_as(stranger, claimB);
    if coalesce(v->>'raised','ACCEPTED') is distinct from v_a
    then v_bad := v_bad || ' a stranger read the claim STATE through the refusal: '
                        || coalesce(v->>'raised','ACCEPTED'); end if;
    update gear_claims set status = 'claimable' where id = claimB;

    -- and the refusals wrote nothing
    select count(*)::int into v_n from gear_claims
     where id in (claimA, claimB) and status <> 'claimable';
    if v_n is distinct from 0
    then v_bad := v_bad || ' a refused call moved a claim row (n=' || v_n || ')'; end if;

    -- 🔴 CONTROL on the SAME id: the real owner gets through. Without it every assertion above
    -- would also pass against a function that refused everybody, which is a wall and not a gate.
    v := t_otx_claim_as(runner1, claimA);
    if v->>'raised' is not null
    then v_bad := v_bad || ' CONTROL: the real owner was refused (' || (v->>'raised') || ')'; end if;
    if v->>'status' is distinct from 'claimed'
    then v_bad := v_bad || ' CONTROL: the owner''s claim answered status='
                        || coalesce(v->>'status','NULL'); end if;
    -- …and the SECOND call is the flat idempotent field, not an exception (0195 §0e, unchanged)
    v := t_otx_claim_as(runner1, claimA);
    if (v->>'already')::boolean is not true
    then v_bad := v_bad || ' CONTROL: a re-claim is no longer already_claimed=true'; end if;

    -- an anonymous caller is refused for its own reason, ahead of everything
    v := t_otx_claim_as(null, claimA);
    if v->>'raised' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' anon: ' || coalesce(v->>'raised','ACCEPTED'); end if;

    if v_bad = '' then call _pass('otx','0214-C1 claim_gear_tx는 존재 오라클이 아니다 — 같은 낯선 사람이 실재하는 교환권 id·무작위 uuid·NULL 셋 모두에서 not_claim_owner 한 낱말을 받고, 상태가 다른 행(locked)에서도 같은 낱말을 받으며(상태도 새지 않는다), 거절은 아무 행도 움직이지 않는다. 🔴 같은 id 위의 대조 — 진짜 주인은 통과해 claimed를 받고 재호출은 already_claimed=true다(벽이 아니라 문이라는 증거), 무기명은 not_signed_in으로 그보다 먼저 거절된다');
    else v_msg := v_bad; call _fail('otx','0214-C1 claim_gear_tx oracle', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('otx','0214-C1 claim_gear_tx oracle', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0214-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ These arms and 0214's VERIFY are DIFFERENT ARTIFACTS: that one aborts an apply that lands
  --   wrong, this one reddens when a LATER file undoes something (0131-G4's law).
  -- ⚠ Every arm asserts an EXACT boolean. `position(… in NULL)` is NULL and plpgsql does not take
  --   an `IF` on NULL, so a bare `IF` would be SILENT for exactly the missing function these arms
  --   exist to notice — NO-FUNCTION / NO-SOURCE fail loudly instead of skipping.
  begin
    v_bad := '';
    foreach fn in array array['_noti_ops_titles()', '_noti_push_category(noti_kind,text)',
                              'claim_gear_tx(uuid,text,text,text,text,text)'] loop
      v_oid := to_regprocedure(fn);
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || fn || ' is executable by anon'; end if;
    end loop;

    -- the two classifier halves are PURE: no definer, and therefore nothing to shadow
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname in ('_noti_ops_titles', '_noti_push_category') and p.prosecdef)
    then v_bad := v_bad || ' a classifier function became SECURITY DEFINER — it reads no table and must not'; end if;
    foreach fn in array array['_noti_ops_titles()', '_noti_push_category(noti_kind,text)'] loop
      v_oid := to_regprocedure(fn);
      if v_oid is not null and has_function_privilege('authenticated', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || fn || ' is executable by authenticated — only notify_push calls it'; end if;
    end loop;

    -- claim_gear_tx: definer + in-body search_path + the grant the runner needs
    if not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                    and p.proname = 'claim_gear_tx' and p.prosecdef
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' claim_gear_tx lost SECURITY DEFINER or its in-body search_path'; end if;
    v_oid := to_regprocedure('claim_gear_tx(uuid,text,text,text,text,text)');
    if v_oid is not null and has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' claim_gear_tx is not executable by authenticated — the runner cannot claim'; end if;

    -- 🔴 THE ORDERING, in the classifier's own comment-stripped source. Every behavioural arm in
    -- T2 depends on the urgent arm sitting ABOVE both `system` arms, and a future edit could move
    -- it while every fixture here stayed green — the urgent titles are only four strings and none
    -- of them is an ops title, so the two orderings agree on everything this suite can build.
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_noti_push_category';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(_noti_push_category)';
    else
      if position('_noti_urgent_noti_titles' in v_src) = 0
      then v_bad := v_bad || ' the classifier no longer consults the urgent family'; end if;
      if position('_noti_ops_titles' in v_src) = 0
      then v_bad := v_bad || ' the classifier no longer consults the ops ledger — the system arm is kind-keyed again'; end if;
      if (position('_noti_urgent_noti_titles' in v_src) < position('_noti_ops_titles' in v_src)) is not true
      then v_bad := v_bad || ' the urgent arm no longer precedes the ops arm in source (urgent@'
                          || position('_noti_urgent_noti_titles' in v_src) || ' ops@'
                          || position('_noti_ops_titles' in v_src) || ')'; end if;
    end if;

    -- and notify_push still routes through the mapper at all (0187-N5's property, restated here
    -- because this slice re-declares the mapper and not the caller)
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
    elsif position('_noti_push_category' in v_src) = 0
    then v_bad := v_bad || ' notify_push no longer calls the category mapper'; end if;

    if v_bad = '' then call _pass('otx','0214-S1 배포 형상 — 원장과 분류기는 순수 함수이고(definer 아님) anon·authenticated 어느 쪽에도 실행 권한이 없다; claim_gear_tx는 definer + 본문 search_path + anon 거부/authenticated 허용이다; 그리고 주석을 벗긴 분류기 소스에서 긴급 팔이 두 system 팔보다 **앞선다** — T2의 모든 행동 팔이 이 순서에 기대고 있는데, 긴급 제목 4종 중 운영 제목이 하나도 없어서 순서가 바뀌어도 이 스위트가 만들 수 있는 픽스처는 전부 그대로 초록이기 때문이다; notify_push는 여전히 매퍼를 부른다; NO-FUNCTION/NO-SOURCE는 조용히 넘어가지 않고 빨개진다');
    else v_msg := v_bad; call _fail('otx','0214-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('otx','0214-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
