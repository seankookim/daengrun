-- ═══ 241 — 0210: ops alerts get their own switch · the unknown kind stops failing open into
-- ═══        always-on · the runner whose payout is stuck is told
-- ═══        0210-O1 · O2 · C1 · F1 · R1 · P1 · P2 · P3 · S1, tag `ocp`
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · O1 **`ops` GATES THE `system` KIND AND NOTHING ELSE GATES IT.** Control FIRST, and it is
--        what makes every 0 below mean something: with no prefs row a `system` row reaches the
--        HTTP stub. Then `ops = false` alone silences it while booking · chat · community · reward
--        keep arriving, and `booking = false` (with `ops` on) does NOT silence it — the cross arms
--        are what stop a one-flag implementation and a mapper that collapses two categories. In
--        every arm the `notifications` ROW is written: a preference gates the PUSH, never the
--        record, which is what keeps the ops console and `alerts.tsx` whole.
--   · O2 **THE ALWAYS-ON CATEGORY DID NOT MOVE, AND THE FOUR OPS TITLES ARE GENUINELY GATED.**
--        With ALL FIVE columns false a `kind='safety'` row still pushes and a `kind='booking'` row
--        titled `SOS` still pushes, while each of the four REAL ops titles goes silent. 🔴 And the
--        arm that makes the silence attributable: **not one of those four titles is a member of
--        `_noti_urgent_noti_titles()`**, asserted by value. Without it, 「the ops title was
--        silenced」 and 「this title was never urgent in the first place」 are the same observation,
--        and moving `system` off the always-on arm could have been a no-op hiding behind a green.
--   · C1 **THE CLASSIFIER'S ANSWER FOR EVERY `noti_kind` MEMBER, BY VALUE.** All six members plus
--        the chat discriminator and each urgent title. A source pin could not tell a changed arm
--        from a changed comment; this asks the shipped function what it answers.
--   · F1 **THE UNKNOWN KIND IS SENT BY DEFAULT AND IS NOW SILENCEABLE.** `shop` — the enum member
--        with zero writers — pushes with no prefs row (0187 §C's fail-open rule, kept), is
--        SILENCED by `booking = false`, and is NOT silenced by `ops = false`. 🔴 The fixture sits
--        exactly where the old rule and the new rule DISAGREE: under `else 'safety'` the middle
--        arm pushes, under `else 'booking'` it does not. A fixture in the agreement zone would be
--        green in both worlds (the 175-V2 / fixture-agreement law).
--   · R1 **THE TWO RPCs CARRY THE FIFTH COLUMN AND A NULL STILL MEANS 「LEAVE IT ALONE」.** A
--        person who never saved reads five trues and a NULL `updated_at`; setting `ops = false` on
--        its own moves that column and no other and the getter reads it back; and a FOUR-ARGUMENT
--        positional call — the pre-0210 client's shape — leaves `ops` untouched, which is what
--        makes the client and server halves of this slice independently deployable.
--   · P1 **THE RUNNER IS TOLD, THROUGH THE REAL SWEEP.** `ops_payouts_stuck_sweep()` is called;
--        the runner whose oldest unpaid settled row is past seven days gains exactly one row —
--        kind `booking`, ref_id NULL, the exact title — whose body carries THEIR OWN unpaid total
--        as the ledger computes it. Controls in the same tick: the ops roster still gets its bell
--        (the new leg did not replace the old one), and a second runner whose rows are two days
--        old gets nothing from either leg.
--   · P2 **ONCE, THEN ONCE A WEEK.** A second tick immediately afterwards adds nothing for the
--        runner (while the ledger is still stuck, so the candidate query still finds them — the
--        control that the silence is the dedupe and not an empty candidate set); aging that
--        notification past the window makes the next tick tell them again. Both numbers are
--        deltas this suite caused, never a state found lying around.
--   · P3 **THE BANK SENTENCE IS BOUND TO A REAL READ.** Two runners, both stuck, swept in ONE
--        tick: the one with no `bank_accounts` row is told 「정산 계좌를 확인해주세요」 and the one
--        with a row is not — so the difference is attributable to the bank row rather than to the
--        tick. Telling a runner who already registered an account to go register one would be a
--        fabricated instruction, and a constant string satisfies neither half of this arm.
--   · S1 **DEPLOYED SHAPE.** The column's NOT NULL + default; three definers with prosecdef and
--        the in-body `search_path`; ACLs by value in BOTH directions; the old four-argument setter
--        GONE (a surviving arity makes every positional call ambiguous); `notifications_push`
--        `tgenabled = 'O'` (state, not shape — the `pg_get_triggerdef` law); and the three
--        function bodies with COMMENTS STRIPPED, each with a NO-SOURCE arm so an absent function
--        fails LOUDLY instead of silently.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · The push itself. `00_shim.sql` stubs `net.http_post` into `net._stub_calls`, so what is
--     measured is 「the row → HTTP step was taken」, never that Expo delivered anything.
--   · That the runner leg's NESTED subtransaction protects the ops bell. The property is real and
--     it is why the block is nested — but the harness cannot make the runner insert fail without
--     also breaking the fixture that makes the ops insert happen, so every arm one could write
--     would pass unconditionally. A limitation is prose; an unfalsifiable pin is a green that
--     licenses nothing (CLAUDE.md). The shape is asserted in 0210's own header instead.
--   · The client screen. `app/test/notification-prefs.test.cjs` pins the category → copy table and
--     the operator-only visibility of the 운영 알림 row; no SQL pin can see a `.tsx` route module.
--   · Whether an OPERATOR is the person reading a `system` row. `ops_recipients_for` decides that
--     and 239 owns it; this file only proves what happens to a `system` row once it exists.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared explicitly in every arm (218 ①'s rule): a leftover
--     claim from an earlier suite would make a 「no caller」 arm silently measure the wrong thing.
--  ② Every push measurement is a DELTA around one INSERT, never an absolute count — other suites
--     in this same database have already written to `net._stub_calls`.
--  ③ The fixture profiles hold a real `ExponentPushToken…` in `push_tokens`. Without it
--     `notify_push` returns before the HTTP call for a reason that has nothing to do with
--     preferences, and every arm would read 0 — the fixture must contain the defect's
--     precondition (218 ③, and the same law as 「a fixture that omits the defect cannot test the
--     fix」).
--  ④ The sweep is GLOBAL: it walks every runner in the database, and earlier suites have their
--     own ledger rows and their own `payout_due` recipients. So nothing here reads a global count.
--     Every number is scoped to this suite's own profiles, and the ops-side delta is scoped to
--     this suite's own recipient AND to this suite's own runner as `ref_id`.
set client_min_messages = warning;

-- One INSERT, measured both ways: how many stub calls it produced, and whether the row landed.
create or replace function t_ocp_probe(p_profile uuid, p_kind noti_kind, p_title text)
returns jsonb language plpgsql as $$
declare v0 int; v1 int; v_row int; v_id uuid;
begin
  select count(*) into v0 from net._stub_calls;
  insert into notifications (profile_id, kind, title, body, ref_id)
       values (p_profile, p_kind, p_title, 'ocp-probe', null)
    returning id into v_id;
  select count(*) into v1 from net._stub_calls;
  select count(*) into v_row from notifications where id = v_id;
  return jsonb_build_object('pushes', v1 - v0, 'row', v_row);
end $$;

-- The five-column setter, with the raise trapped so an arm records a NAME instead of aborting.
create or replace function t_ocp_set(p_b boolean, p_c boolean, p_m boolean, p_r boolean, p_o boolean)
returns jsonb language plpgsql as $$
declare r record;
begin
  select * into r from set_notification_prefs(p_b, p_c, p_m, p_r, p_o);
  return jsonb_build_object('booking', r.booking, 'chat', r.chat, 'community', r.community,
                            'reward', r.reward, 'ops', r.ops, 'has_row', (r.updated_at is not null));
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

-- The PRE-0210 client's shape: four positional arguments, `p_ops` left to its default.
create or replace function t_ocp_set4(p_b boolean, p_c boolean, p_m boolean, p_r boolean)
returns jsonb language plpgsql as $$
declare r record;
begin
  select * into r from set_notification_prefs(p_b, p_c, p_m, p_r);
  return jsonb_build_object('booking', r.booking, 'chat', r.chat, 'community', r.community,
                            'reward', r.reward, 'ops', r.ops, 'has_row', (r.updated_at is not null));
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_ocp_get() returns jsonb language plpgsql as $$
declare r record;
begin
  select * into r from get_notification_prefs();
  return jsonb_build_object('booking', r.booking, 'chat', r.chat, 'community', r.community,
                            'reward', r.reward, 'ops', r.ops, 'has_row', (r.updated_at is not null));
exception when others then return jsonb_build_object('raised', sqlerrm);
end $$;

-- A runner with `p_items` settled, unpaid ledger rows, aged `p_age` into the past. The rows are
-- written by the REAL settle path (`t_active_booking` + `t_settle`), so the sweep's candidate
-- query sees exactly what production would give it; only `created_at` is moved, because the
-- condition under test is 「older than seven days」 and the harness cannot wait.
create or replace function t_ocp_runner(p_tag text, p_items int, p_age interval, p_bank boolean,
                                        out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('ocp_' || p_tag || '_o', 'owner');
  r  := t_user('ocp_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'ocp-' || p_tag);
  rt := t_route('ocp 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
  end loop;
  update ledger_items set created_at = now() - p_age where runner_id = r;
  if p_bank then
    insert into bank_accounts (runner_id, bank, account_enc, holder)
    values (r, '토스뱅크', 'ENC-' || upper(p_tag), '김러너')
    on conflict (runner_id) do nothing;
  end if;
  insert into push_tokens (profile_id, token) values (r, 'ExponentPushToken[ocp-' || p_tag || ']')
  on conflict (profile_id) do nothing;
end $$;

-- What the runner's own unpaid ledger sums to — the same summand `my_ledger_unpaid_total` and the
-- sweep both use. Written out here so the body's number is compared against a value this suite
-- computed from the ROWS, never against a string the sweep also produced.
create or replace function t_ocp_unpaid(p_runner uuid) returns bigint language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::bigint
    from ledger_items where runner_id = p_runner and paid_payout_id is null
$$;

-- The runner's own stuck-payout rows, scoped by every field the writer sets.
create or replace function t_ocp_runner_rows(p_runner uuid) returns int language sql as $$
  select count(*)::int from notifications
   where profile_id = p_runner and kind = 'booking'
     and title = '정산 지급이 늦어지고 있어요' and ref_id is null
$$;

do $$
declare
  ops1 uuid;
  o uuid; r uuid; d uuid; rt uuid;
  o2 uuid; r2 uuid; d2 uuid; rt2 uuid;
  o3 uuid; r3 uuid; d3 uuid; rt3 uuid;
  v jsonb; v_bad text; v_msg text; v_n int; v_txt text; v_src text;
  v_before int; v_after int; v_body text; v_net bigint;
  k text; ttl text;
  OPS_TITLES constant text[] := array['지급 대기 — 확인 필요', '인계 확인 멈춤 — 확인 필요',
                                      '반환 좌초 — 확인 필요', '굿즈 수령 신청 — 확인 필요'];
  RUNNER_TITLE constant text := '정산 지급이 늦어지고 있어요';
begin
  perform set_config('request.jwt.claim.sub', '', true);                                        -- ①
  ops1 := t_user('ocp_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active) values (ops1, 'payout_due', true);
  insert into push_tokens (profile_id, token) values (ops1, 'ExponentPushToken[ocp-ops]')
  on conflict (profile_id) do nothing;                                                          -- ③

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-O1] the `ops` column gates `system`, and only `ops` gates it
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;

    -- CONTROL FIRST. With NO prefs row every category reaches the stub — a notify_push that threw
    -- (its `exception when others` swallows into a skipped push) would give 0 here too, and this
    -- arm is the only thing that tells those two worlds apart.
    foreach k in array array['booking','community','reward','safety','system','shop'] loop
      v := t_ocp_probe(ops1, k::noti_kind, '알림');
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL(no row) ' || k || ' pushes=' || coalesce(v->>'pushes','NULL'); end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' CONTROL ' || k || ' wrote no notifications row'; end if;
    end loop;

    -- ops OFF, the other four ON: `system` alone goes quiet.
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(true, true, true, true, false);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_ocp_probe(ops1, 'system'::noti_kind, '지급 대기 — 확인 필요');
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' ops-off: the system push survived (' || coalesce(v->>'pushes','NULL') || ')'; end if;
    if (v->>'row')::int is distinct from 1
    then v_bad := v_bad || ' ops-off: the notifications ROW was lost — a preference gates the push, never the record'; end if;
    foreach k in array array['booking','community','reward'] loop
      v := t_ocp_probe(ops1, k::noti_kind, '알림');
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' ops-off: ' || k || ' was silenced by the ops column'; end if;
    end loop;
    v := t_ocp_probe(ops1, 'booking'::noti_kind, '새 메시지');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' ops-off: the chat nudge was silenced by the ops column'; end if;

    -- THE CROSS ARM: booking off, ops ON ⇒ `system` still arrives. A one-flag implementation, or a
    -- mapper that collapsed `system` into `booking`, passes the arm above and dies here.
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(false, false, false, false, true);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_ocp_probe(ops1, 'system'::noti_kind, '지급 대기 — 확인 필요');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' booking/chat/community/reward off + ops ON: the system push was silenced by somebody else''s column'; end if;

    -- and back ON ⇒ it arrives again (the round trip, so 「silent」 is a state this suite caused)
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(true, true, true, true, true);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_ocp_probe(ops1, 'system'::noti_kind, '지급 대기 — 확인 필요');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' ops back ON: the system push did not come back'; end if;

    delete from notification_prefs where profile_id = ops1;
    if v_bad = '' then call _pass('ocp','0210-O1 ops 칸이 system 종류를 끈다 — 행이 없으면 전부 발송(컨트롤), ops만 끄면 system만 조용해지고 booking·chat·community·reward는 그대로, 반대로 나머지 넷을 끄고 ops를 켜면 system은 그대로 도착한다(교차 팔); 다시 켜면 돌아온다; 모든 팔에서 notifications 행은 남는다');
    else v_msg := v_bad; call _fail('ocp','0210-O1 ops column gates system', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ocp','0210-O1 ops column gates system', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-O2] the always-on category did not move, and the four ops titles are genuinely gated
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;

    -- 🔴 THE ATTRIBUTION ARM, and it is why this pin is not O1 repeated. If one of the four ops
    -- titles were a member of the urgent family, its row would be `safety` by TITLE and would push
    -- no matter what the `ops` column said — so 「the ops title went silent」 would be measuring a
    -- title that was never urgent, and moving `system` off the always-on arm could have been a
    -- no-op wearing a green. Asked of the shipped array, by value.
    foreach ttl in array OPS_TITLES loop
      if (ttl = any (_noti_urgent_noti_titles())) is not false
      then v_bad := v_bad || ' the ops title 「' || ttl || '」 IS in the urgent family — it can never be gated by any column'; end if;
    end loop;

    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(false, false, false, false, false);
    perform set_config('request.jwt.claim.sub', '', true);

    -- ALL FIVE OFF and the always-on category is untouched, both the kind and the title routes
    v := t_ocp_probe(ops1, 'safety'::noti_kind, '즉시 확인하세요');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' all-off: a kind=safety row was SILENCED — safety has no column and must never acquire one'; end if;
    foreach ttl in array _noti_urgent_noti_titles() loop
      v := t_ocp_probe(ops1, 'booking'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 1
      then v_bad := v_bad || ' all-off: the urgent title 「' || ttl || '」 arrived as kind=booking and was silenced'; end if;
    end loop;

    -- …and each of the four REAL ops titles is silent, with its row intact
    foreach ttl in array OPS_TITLES loop
      v := t_ocp_probe(ops1, 'system'::noti_kind, ttl);
      if (v->>'pushes')::int is distinct from 0
      then v_bad := v_bad || ' all-off: the ops title 「' || ttl || '」 still pushed'; end if;
      if (v->>'row')::int is distinct from 1
      then v_bad := v_bad || ' all-off: the ops title 「' || ttl || '」 lost its notifications row'; end if;
    end loop;

    delete from notification_prefs where profile_id = ops1;
    if v_bad = '' then call _pass('ocp','0210-O2 안전·긴급은 그대로다 — 다섯 칸을 모두 꺼도 kind=safety 행과 긴급 제목 4종(_noti_urgent_noti_titles의 실제 배열을 순회)은 그대로 나가고, 실제 운영 제목 4종은 조용해진다; 그리고 그 운영 제목 넷 중 어느 것도 긴급 배열의 멤버가 아니라는 것을 값으로 재므로 「원래 긴급이 아니었을 뿐」과 구별된다');
    else v_msg := v_bad; call _fail('ocp','0210-O2 safety did not move', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ocp','0210-O2 safety did not move', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-C1] the classifier's answer for every enum member, BY VALUE
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- Not a source match: the arms live in a `case` whose every branch is a string that also appears
  -- in the comments explaining it, and a grep cannot tell a changed arm from a changed comment.
  begin
    v_bad := '';
    if _noti_push_category('safety'::noti_kind, '아무거나') is distinct from 'safety'
    then v_bad := v_bad || ' safety→' || coalesce(_noti_push_category('safety'::noti_kind, '아무거나'),'NULL'); end if;
    if _noti_push_category('system'::noti_kind, '아무거나') is distinct from 'ops'
    then v_bad := v_bad || ' system→' || coalesce(_noti_push_category('system'::noti_kind, '아무거나'),'NULL') || ' (expected ops)'; end if;
    if _noti_push_category('booking'::noti_kind, '새 메시지') is distinct from 'chat'
    then v_bad := v_bad || ' the chat discriminator moved'; end if;
    if _noti_push_category('booking'::noti_kind, '응가 완료') is distinct from 'booking'
    then v_bad := v_bad || ' ordinary booking moved'; end if;
    if _noti_push_category('community'::noti_kind, 'x') is distinct from 'community'
    then v_bad := v_bad || ' community moved'; end if;
    if _noti_push_category('reward'::noti_kind, 'x') is distinct from 'reward'
    then v_bad := v_bad || ' reward moved'; end if;
    -- the fallthrough, asked of the one enum member with no arm of its own
    if _noti_push_category('shop'::noti_kind, '아무거나') is distinct from 'booking'
    then v_bad := v_bad || ' the unknown-kind fallthrough answers '
                        || coalesce(_noti_push_category('shop'::noti_kind, '아무거나'),'NULL')
                        || ' (expected booking — the least-privileged DISABLEABLE category)'; end if;
    -- the urgent family beats the kind, including for `system`
    foreach ttl in array _noti_urgent_noti_titles() loop
      if _noti_push_category('booking'::noti_kind, ttl) is distinct from 'safety'
      then v_bad := v_bad || ' the urgent title 「' || ttl || '」 is no longer safety'; end if;
      if _noti_push_category('system'::noti_kind, ttl) is distinct from 'safety'
      then v_bad := v_bad || ' the urgent title 「' || ttl || '」 on a system row fell to ops — the urgent arm must sit ABOVE the system arm'; end if;
    end loop;
    -- EXACT equality, not a prefix: a near miss is an ordinary row of its own kind
    if _noti_push_category('booking'::noti_kind, 'SOS ') is distinct from 'booking'
       or _noti_push_category('booking'::noti_kind, ' SOS') is distinct from 'booking'
       or _noti_push_category('system'::noti_kind, 'SOS 접수') is distinct from 'ops'
    then v_bad := v_bad || ' a near-miss title was treated as urgent'; end if;

    if v_bad = '' then call _pass('ocp','0210-C1 매퍼의 답을 값으로 잰다 — safety→safety, system→ops, booking+새 메시지→chat, booking→booking, community→community, reward→reward, 그리고 유일하게 팔이 없는 멤버 shop→booking(끌 수 있는 최저 권한 칸); 긴급 제목은 kind가 booking이든 system이든 safety로 이기고, 앞뒤 공백이 붙은 근접 문자열은 평범한 행이다');
    else v_msg := v_bad; call _fail('ocp','0210-C1 classifier answers', v_msg); end if;
  exception when others then call _fail('ocp','0210-C1 classifier answers', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-F1] the unknown kind: still SENT by default, and now silenceable
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- 🔴 THE FIXTURE SITS WHERE THE TWO RULES DISAGREE. Under 0189's `else 'safety'` the middle arm
  -- below pushes; under 0210's `else 'booking'` it does not. A fixture with no prefs row would be
  -- green in BOTH worlds and would be measuring the fixture rather than the rule.
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;

    -- ① fail-OPEN is kept: no prefs row ⇒ an uncategorised kind is SENT
    v := t_ocp_probe(ops1, 'shop'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' no row: the unknown kind was muted — an uncategorised push must never be silently dropped'; end if;

    -- ② …and it is now SILENCEABLE, by the least-privileged disableable column
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(false, true, true, true, true);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_ocp_probe(ops1, 'shop'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 0
    then v_bad := v_bad || ' booking off: the unknown kind still pushed (' || coalesce(v->>'pushes','NULL')
                        || ') — the fallthrough is still the undisableable category'; end if;
    if (v->>'row')::int is distinct from 1
    then v_bad := v_bad || ' booking off: the unknown kind lost its notifications row'; end if;

    -- ③ and it is NOT the ops category: `ops = false` alone leaves it alone
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    perform t_ocp_set(true, true, true, true, false);
    perform set_config('request.jwt.claim.sub', '', true);
    v := t_ocp_probe(ops1, 'shop'::noti_kind, '알림');
    if (v->>'pushes')::int is distinct from 1
    then v_bad := v_bad || ' ops off: the unknown kind was silenced by the ops column — the fallthrough is not the ops category'; end if;

    delete from notification_prefs where profile_id = ops1;
    if v_bad = '' then call _pass('ocp','0210-F1 미분류 kind는 여전히 기본 발송이고(행 없음 ⇒ 나간다) 이제 끌 수 있다 — booking을 끄면 조용해지고 ops만 꺼서는 조용해지지 않는다; 픽스처가 옛 규칙(else safety)과 새 규칙(else booking)이 갈라지는 자리에 있으므로 이 세 팔은 두 세계를 구별한다');
    else v_msg := v_bad; call _fail('ocp','0210-F1 unknown kind', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ocp','0210-F1 unknown kind', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-R1] the RPCs carry the fifth column, and a NULL still means 「leave it alone」
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    delete from notification_prefs where profile_id = ops1;
    perform set_config('request.jwt.claim.sub', ops1::text, true);

    v := t_ocp_get();
    if v->>'raised' is not null then v_bad := v_bad || ' getter raised=' || (v->>'raised'); end if;
    if (v->>'ops')::boolean is distinct from true
    then v_bad := v_bad || ' a person who never saved does not read ops=true (' || coalesce(v->>'ops','NULL') || ')'; end if;
    if (v->>'has_row')::boolean is distinct from false
    then v_bad := v_bad || ' updated_at is not NULL on an absent row'; end if;
    select count(*) into v_n from notification_prefs where profile_id = ops1;
    if v_n is distinct from 0 then v_bad := v_bad || ' the READ created a row (n=' || v_n || ')'; end if;

    -- one switch on its own: ops false, everything else left alone
    v := t_ocp_set(null, null, null, null, false);
    if v->>'raised' is not null then v_bad := v_bad || ' setter raised=' || (v->>'raised'); end if;
    if (v->>'ops')::boolean is distinct from false then v_bad := v_bad || ' ops did not save'; end if;
    if (v->>'booking')::boolean is distinct from true
       or (v->>'chat')::boolean is distinct from true
       or (v->>'community')::boolean is distinct from true
       or (v->>'reward')::boolean is distinct from true
    then v_bad := v_bad || ' saving ops alone moved another column'; end if;
    v := t_ocp_get();
    if (v->>'ops')::boolean is distinct from false then v_bad := v_bad || ' the getter does not read ops back'; end if;

    -- 🔴 THE PRE-0210 CLIENT'S SHAPE: four positional arguments must leave `ops` where it is.
    -- This is what makes the two halves of the slice independently deployable — a build that does
    -- not know about `ops` must not silently switch it back on.
    v := t_ocp_set4(false, false, false, false);
    if v->>'raised' is not null then v_bad := v_bad || ' the 4-argument call raised=' || (v->>'raised'); end if;
    if (v->>'ops')::boolean is distinct from false
    then v_bad := v_bad || ' a 4-argument call RESET ops to ' || coalesce(v->>'ops','NULL')
                        || ' — a pre-0210 client would undo the operator''s choice on every save'; end if;
    if (v->>'booking')::boolean is distinct from false
    then v_bad := v_bad || ' the 4-argument call did not save its own four columns'; end if;

    delete from notification_prefs where profile_id = ops1;
    perform set_config('request.jwt.claim.sub', '', true);
    if v_bad = '' then call _pass('ocp','0210-R1 두 RPC가 다섯 번째 칸을 나른다 — 저장한 적 없는 사람은 ops=true와 updated_at NULL을 읽고(읽기만으로 행이 생기지 않는다), ops만 false로 저장하면 그 칸만 움직이며 게터가 그대로 돌려주고, **네 인자 위치 호출(0210 이전 클라이언트의 모양)은 ops를 건드리지 않는다**');
    else v_msg := v_bad; call _fail('ocp','0210-R1 rpc shape', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ocp','0210-R1 rpc shape', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-P1] the runner is told, through the REAL sweep
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the stuck runner (10 days old, NO bank row) and the control runner (2 days old) ④
    select * into o, r, d, rt from t_ocp_runner('p1', 2, interval '10 days', false);
    select * into o2, r2, d2, rt2 from t_ocp_runner('p1ctl', 2, interval '2 days', false);
    v_net := t_ocp_unpaid(r);
    if v_net <= 0 then v_bad := v_bad || ' fixture: the runner has no unpaid net (' || v_net || ') — the sweep would never consider them'; end if;

    v_before := t_ocp_runner_rows(r);
    select count(*) into v_n from notifications
     where profile_id = ops1 and kind = 'system' and title = OPS_TITLES[1] and ref_id = r;

    perform ops_payouts_stuck_sweep();

    v_after := t_ocp_runner_rows(r);
    if v_after - v_before is distinct from 1
    then v_bad := v_bad || ' the runner was told ' || (v_after - v_before) || ' time(s), expected exactly 1'; end if;

    -- the CONTROL that the new leg did not replace the old one: the ops bell still rang, for this
    -- suite's own recipient and this suite's own runner as the ref
    select count(*) into v_after from notifications
     where profile_id = ops1 and kind = 'system' and title = OPS_TITLES[1] and ref_id = r;
    if v_after - v_n is distinct from 1
    then v_bad := v_bad || ' the ops bell delta is ' || (v_after - v_n) || ', expected 1 — the runner leg replaced the escalation instead of joining it'; end if;

    -- the row's SHAPE, field by field, and its body carries the runner's OWN number
    select body into v_body from notifications
     where profile_id = r and title = RUNNER_TITLE order by created_at desc limit 1;
    if v_body is null then v_bad := v_bad || ' NO-ROW(the runner notification body)';
    else
      if (position(to_char(v_net, 'FM999,999,999,999') in v_body) > 0) is not true
      then v_bad := v_bad || ' the body does not carry the runner''s own unpaid total ('
                          || to_char(v_net, 'FM999,999,999,999') || ' not in 「' || v_body || '」)'; end if;
    end if;
    select count(*) into v_n from notifications
     where profile_id = r and title = RUNNER_TITLE and kind = 'booking' and ref_id is null;
    if v_n is distinct from 1
    then v_bad := v_bad || ' the runner row is not (kind=booking, ref_id NULL) — n=' || v_n; end if;

    -- the CONTROL runner, two days old: nothing from either leg
    if t_ocp_runner_rows(r2) is distinct from 0
    then v_bad := v_bad || ' the 2-day-old runner was told their payout is stuck'; end if;
    select count(*) into v_n from notifications
     where profile_id = ops1 and kind = 'system' and title = OPS_TITLES[1] and ref_id = r2;
    if v_n is distinct from 0
    then v_bad := v_bad || ' the 2-day-old runner was escalated to ops'; end if;

    if v_bad = '' then call _pass('ocp','0210-P1 러너가 실제 스윕으로 통보받는다 — 7일을 넘긴 미지급 러너에게 정확히 1행(kind=booking · ref_id NULL · 제목 일치)이 생기고 본문이 **본인의 미지급 합계**를 담는다; 같은 틱에서 ops 종도 그대로 울린다(새 다리가 옛 다리를 대체하지 않았다는 대조); 2일짜리 대조 러너는 양쪽 모두 0이다');
    else v_msg := v_bad; call _fail('ocp','0210-P1 the runner is told', v_msg); end if;
  exception when others then call _fail('ocp','0210-P1 the runner is told', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-P2] once, then once a week — and the silence is the dedupe, not an empty candidate set
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the P1 runner is still stuck: the candidate query still finds them, so a second tick that
    -- adds nothing is measuring the dedupe rather than the disappearance of the condition.
    if t_ocp_unpaid(r) <= 0 then v_bad := v_bad || ' fixture: the runner is no longer a candidate'; end if;
    if (select min(created_at) from ledger_items where runner_id = r and paid_payout_id is null)
         >= now() - interval '7 days'
    then v_bad := v_bad || ' fixture: the ledger is no longer past STUCK_AFTER'; end if;

    v_before := t_ocp_runner_rows(r);
    perform ops_payouts_stuck_sweep();
    v_after := t_ocp_runner_rows(r);
    if v_after - v_before is distinct from 0
    then v_bad := v_bad || ' the second tick told them again (delta=' || (v_after - v_before) || ')'; end if;

    -- age the notification past the window and the NEXT tick speaks again — the arm that proves
    -- the silence above is a WINDOW and not a permanent one-shot that would leave a runner with a
    -- payout stuck for a month hearing about it exactly once.
    update notifications set created_at = now() - interval '8 days'
     where profile_id = r and title = RUNNER_TITLE;
    v_before := t_ocp_runner_rows(r);
    perform ops_payouts_stuck_sweep();
    v_after := t_ocp_runner_rows(r);
    if v_after - v_before is distinct from 1
    then v_bad := v_bad || ' after the window expired the runner was told ' || (v_after - v_before) || ' time(s), expected 1'; end if;

    if v_bad = '' then call _pass('ocp','0210-P2 한 번, 그리고 일주일에 한 번 — 곧바로 이어지는 두 번째 틱은 아무것도 더하지 않고(대조: 원장은 여전히 막혀 있으므로 후보 질의는 이 러너를 계속 찾는다 — 침묵의 원인이 중복 방지지 빈 후보 집합이 아니다), 알림을 창 밖으로 늙히면 다음 틱이 다시 말한다');
    else v_msg := v_bad; call _fail('ocp','0210-P2 once then weekly', v_msg); end if;
  exception when others then call _fail('ocp','0210-P2 once then weekly', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-P3] the bank sentence is bound to a real read
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- Two stuck runners swept in ONE tick, differing ONLY in whether `bank_accounts` holds their
  -- row. A constant string satisfies neither half; a body that ignored the read would give both
  -- runners the same sentence, and the difference here is attributable to the row rather than to
  -- the tick that wrote it.
  begin
    v_bad := '';
    select * into o2, r2, d2, rt2 from t_ocp_runner('p3nb', 1, interval '12 days', false);
    select * into o3, r3, d3, rt3 from t_ocp_runner('p3wb', 1, interval '12 days', true);
    if exists (select 1 from bank_accounts where runner_id = r2)
    then v_bad := v_bad || ' fixture: the no-bank runner has a bank row'; end if;
    if not exists (select 1 from bank_accounts where runner_id = r3)
    then v_bad := v_bad || ' fixture: the with-bank runner has no bank row — the two arms below would agree for the wrong reason'; end if;

    perform ops_payouts_stuck_sweep();

    select body into v_body from notifications
     where profile_id = r2 and title = RUNNER_TITLE order by created_at desc limit 1;
    if v_body is null then v_bad := v_bad || ' NO-ROW(no-bank runner)';
    else
      if (position('정산 계좌를 확인해주세요' in v_body) > 0) is not true
      then v_bad := v_bad || ' the runner with NO bank account was not told to register one: 「' || v_body || '」'; end if;
    end if;

    select body into v_body from notifications
     where profile_id = r3 and title = RUNNER_TITLE order by created_at desc limit 1;
    if v_body is null then v_bad := v_bad || ' NO-ROW(with-bank runner)';
    else
      if (position('정산 계좌를 확인해주세요' in v_body) > 0) is not false
      then v_bad := v_bad || ' the runner WITH a bank account was told to register one: 「' || v_body || '」'; end if;
      if (position('수익 화면에서 내역을 확인할 수 있어요' in v_body) > 0) is not true
      then v_bad := v_bad || ' the with-bank runner got no second half at all: 「' || v_body || '」'; end if;
    end if;

    if v_bad = '' then call _pass('ocp','0210-P3 계좌 문장은 실제 읽기에 묶여 있다 — 같은 틱에서 쓸린 두 러너가 bank_accounts 행 유무로만 다르고, 없는 쪽만 「정산 계좌를 확인해주세요」를 받고 있는 쪽은 받지 않는다(상수 문자열은 두 팔 중 어느 쪽도 만족시키지 못한다)');
    else v_msg := v_bad; call _fail('ocp','0210-P3 the bank sentence', v_msg); end if;
  exception when others then call _fail('ocp','0210-P3 the bank sentence', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0210-S1] the deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- 0210's VERIFY block asserts overlapping properties at APPLY time. That protects them exactly
  -- until someone recreates a function in a LATER migration, which the VERIFY never sees — so the
  -- standing pin lives here as well, deliberately, and the two are not redundant.
  begin
    v_bad := '';
    -- the column: NOT NULL and default true (opt-out, never opt-in)
    select count(*) into v_n from information_schema.columns
     where table_schema = 'public' and table_name = 'notification_prefs' and column_name = 'ops'
       and data_type = 'boolean' and is_nullable = 'NO' and column_default = 'true';
    if v_n is distinct from 1 then v_bad := v_bad || ' the ops column is missing, nullable or not default-true'; end if;

    -- definer + in-body search_path, by value
    select count(*) into v_n from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push','get_notification_prefs','set_notification_prefs','ops_payouts_stuck_sweep')
       and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig);
    if v_n is distinct from 4 then v_bad := v_bad || ' definer+search_path count=' || v_n || ' (expected 4)'; end if;

    -- ACL by value, BOTH directions
    select string_agg(p.oid::regprocedure::text, ', ') into v_txt from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('notify_push','get_notification_prefs','set_notification_prefs',
                         '_noti_push_category','ops_payouts_stuck_sweep')
       and (has_function_privilege('public', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
    if v_txt is not null then v_bad := v_bad || ' PUBLIC/anon can execute: ' || v_txt; end if;
    if has_function_privilege('authenticated', 'get_notification_prefs()', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot call get_notification_prefs'; end if;
    if has_function_privilege('authenticated',
         'set_notification_prefs(boolean, boolean, boolean, boolean, boolean)', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot call the 5-argument set_notification_prefs'; end if;
    if has_function_privilege('authenticated', '_noti_push_category(noti_kind, text)', 'execute') is not false
    then v_bad := v_bad || ' authenticated can call the internal mapper'; end if;
    if has_function_privilege('authenticated', 'ops_payouts_stuck_sweep()', 'execute') is not false
    then v_bad := v_bad || ' authenticated can run the ops sweep'; end if;

    -- 🔴 the OLD four-argument arity must be GONE. A surviving one makes every positional call
    -- ambiguous, and `to_regprocedure` answers NULL rather than raising, so this is a real arm.
    if to_regprocedure('set_notification_prefs(boolean, boolean, boolean, boolean)') is not null
    then v_bad := v_bad || ' the pre-0210 4-argument setter survived beside the 5-argument one'; end if;

    -- the trigger that makes any of this reachable — STATE, not shape (the pg_get_triggerdef law)
    select count(*) into v_n from pg_trigger
     where tgrelid = 'notifications'::regclass and tgname = 'notifications_push'
       and not tgisinternal and tgenabled = 'O';
    if v_n is distinct from 1 then v_bad := v_bad || ' notifications_push enabled-count=' || v_n || ' (tgenabled must be O)'; end if;

    -- notify_push's SOURCE, COMMENTS STRIPPED (a comment explaining the gate would otherwise
    -- satisfy a check for the gate — the standing law), with a NO-SOURCE arm so an absent
    -- function fails LOUDLY: position(x in NULL) is NULL and a bare IF on NULL never fires.
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
    else
      if (position('when ''ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' the send path has no ops arm — the column would be unreadable'; end if;
      if (v_src ~ 'v_cat\s*<>\s*''safety''') is not true
      then v_bad := v_bad || ' the safety-excluding conjunct is gone from the send path'; end if;
      if (position('''safety''' in v_src) > 0
          and position('''safety''' in v_src) < position('notification_prefs' in v_src)) is not true
      then v_bad := v_bad || ' the safety decision is not taken BEFORE the prefs read'; end if;
    end if;

    -- the sweep's source: the runner leg, the bank read, and 0190's lock still first
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ops_payouts_stuck_sweep';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_payouts_stuck_sweep)';
    else
      -- 🔴 THE INSERT, NOT THE CONSTANT — measured, not reasoned (battery M4). Deleting the whole
      -- runner leg while leaving `c_runner_title constant text := '정산 지급이 늦어지고 있어요'` in
      -- the declare block reddened P1/P2/P3 and left THIS BLOCK GREEN, because the title literal
      -- was still in the source of a function that no longer wrote it. That is the comment-quoting
      -- law wearing a constant's costume, and the repair is to match the thing only an INSERT can
      -- produce. Property, stated without reference to that mutation: the sweep writes a `booking`
      -- row addressed to the runner. ⚠ Not anchored on `c_runner_title` — inlining the literal is
      -- a legitimate refactor and a gate that cries on correct code gets bypassed; the title and
      -- the body are held behaviourally by `0210-P1`/`P3`.
      if (v_src ~ 'select\s+r\.runner,\s*''booking''::noti_kind,') is not true
      then v_bad := v_bad || ' the sweep does not INSERT a booking row addressed to the runner — a declared title is not a written row'; end if;
      if (v_src ~ 'v_bank\s*:=\s*exists\s*\(') is not true
      then v_bad := v_bad || ' the bank sentence is not driven by a read'; end if;
      if (v_src ~ 'case\s+when\s+v_bank\s+then') is not true
      then v_bad := v_bad || ' the body does not branch on the bank read — a constant sentence would satisfy neither arm of 0210-P3'; end if;
      if (position('bank_accounts' in v_src) > 0) is not true
      then v_bad := v_bad || ' the bank sentence is not bound to a read of bank_accounts'; end if;
      if (position('ops_recipients_for' in v_src) > 0) is not true
      then v_bad := v_bad || ' the ops bell is gone from the sweep'; end if;
      if (position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src) > 0
          and position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src)
              < position('from ledger_items' in v_src)) is not true
      then v_bad := v_bad || ' 0190''s job lock is gone or no longer precedes the candidate query'; end if;
      if (position('pg_advisory_unlock' in v_src) > 0) is not false
      then v_bad := v_bad || ' an early unlock re-opened the window the xact-scoped lock closes'; end if;
    end if;

    if v_bad = '' then call _pass('ocp','0210-S1 배포 형상 — ops 칸은 NOT NULL·default true; 네 definer는 prosecdef + 본문 search_path이고 PUBLIC/anon 실행 불가이며 authenticated는 두 RPC만 부른다(매퍼도 스윕도 못 부른다); **0210 이전의 네 인자 세터는 사라졌다**(남아 있으면 위치 호출이 모호해진다); notifications_push는 tgenabled=O(정의가 아니라 상태); notify_push 소스(주석 제거)에 ops 팔이 있고 safety 판정이 prefs 읽기보다 앞서며, 스윕 소스에는 bank_accounts 읽기·ops 종·0190의 잡 락이 후보 질의보다 먼저 있고 이른 unlock은 없다');
    else v_msg := v_bad; call _fail('ocp','0210-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('ocp','0210-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
