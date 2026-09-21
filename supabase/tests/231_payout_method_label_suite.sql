-- ═══ 231 — 0200: the runner learns HOW they were paid, and only that ══════════════════════════
-- ═══        0200-P1 · P2 · P3 · P4 · S1, tag `pml`                                       ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than
-- the property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · P1 A runner asking about their OWN payout rows — written through the REAL door
--        (`ops_record_manual_payout`, so `method` is literally what production writes) — gets one
--        row per id, each carrying the fixed label 「계좌 이체」. Two payouts, both answered, in
--        one call, and the label is joined to the RIGHT id (the two rows are deliberately
--        different amounts so 「it answered about the other one」 is visible).
--   · P2 **ABSENCE IS THE ONLY ANSWER A STRANGER GETS, AND IT IS THE SAME ABSENCE AS A UUID NO
--        PAYOUT HAS.** Another runner's real payout id, a random uuid and a mix of both come back
--        with ZERO rows and NO raise, so the id is not an existence oracle — and a mixed call
--        (my id + a stranger's id) answers about mine ALONE rather than refusing, which is the
--        shape §0d argues for. No caller ⇒ `not_authenticated`. An empty array ⇒ zero rows and
--        no raise. Controls: the owner passes on the same ids in the same block, and the other
--        runner passes on their own, so 「it refuses everyone」 and 「the session is broken」 are
--        both excluded.
--   · P3 **THE OPS MEMO NEVER LEAVES THE SERVER.** A sentinel memo is written through the real
--        door, is genuinely in `payouts.memo` afterwards (the control that makes 「absent」 mean
--        something), and appears in NO value of the runner's row — asserted over the whole row as
--        JSON, so a memo concatenated into the label or riding a third column is caught too. The
--        raw `method` token is absent by the same test.
--   · P4 **THE LABEL IS CHOSEN BY `method`, MEASURED IN BOTH DIRECTIONS.** A row whose method is
--        a token this file does not know, and a row whose method is NULL, come back PRESENT with
--        a NULL label — the row is not filtered away and no word is guessed — while a `manual`
--        row in the same call carries the label. A hard-wired constant satisfies neither pair.
--   · S1 Deployed shape: definer, in-body `search_path`, ACL by effective privilege in BOTH
--        directions, exactly two output columns named `payout_id`/`method_label` with no
--        `method`/`memo`/`recorded_by` among them, the comment-STRIPPED source carrying the
--        `runner_id = v_uid` scope and exactly ONE reference to `payouts`, no `memo` /
--        `recorded_by` token in the executable text (with the raw-source crude control that makes
--        those two arms mean something), and 0186:192-195's column seal still shut for
--        `authenticated` (with `net` readable as the control that the grant was not simply
--        deleted). NO-FUNCTION / NO-SOURCE arms fail loudly rather than passing on an absence.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (two runners, their own owner, dog, route, ops operator) and
--     every assertion is scoped to ids it created. It borrows only the shared `10_settle` helpers.
--     A pin that inherits another suite's setup is testing that setup (`175 V2`'s law).
--  ② Payout rows are written through `ops_record_manual_payout` (0186 §C) rather than by INSERT,
--     so `method = 'manual'` and the memo are what the PRODUCT writes and not what this file
--     believes it writes. P4's two odd rows are the exception and must be: no shipped writer can
--     produce an unknown or NULL `method`, and a direct UPDATE of that column is a legal edge
--     (0186:172-174 deliberately put no CHECK on it precisely so the vocabulary can grow).
--  ③ `request.jwt.claim.sub` is SESSION-scoped here (`set_config(..., false)`, 230's idiom) and is
--     cleared explicitly before the no-caller arm — a leftover claim would make
--     `not_authenticated` unreachable and that arm would pass for the wrong reason.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`), control observed
-- clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------
-- one settled, unpaid ledger row for a runner, through the real settle path.
create or replace function t_pml_world(p_tag text, p_items int,
                                       out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('pml_' || p_tag || '_o', 'owner');
  r  := t_user('pml_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'pml-' || p_tag);
  rt := t_route('pml 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
  end loop;
end $$;

-- the runner's unpaid ledger ids for ONE booking — the batch an operator would pay
create or replace function t_pml_items(p_booking uuid) returns uuid[] language sql as $$
  select coalesce(array_agg(id order by id), '{}'::uuid[])
    from ledger_items where booking_id = p_booking and paid_payout_id is null
$$;

-- the net of the named rows — the number the operator reads out of ops_payouts_due(), never a
-- literal (a hand-typed amount is a second source of truth)
create or replace function t_pml_net(p_ids uuid[]) returns int language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::int
    from ledger_items where id = any(p_ids)
$$;

-- pay through the REAL door, as the ops caller, and hand back the payout id
create or replace function t_pml_pay(p_ops uuid, p_runner uuid, p_ids uuid[], p_memo text)
returns uuid language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub', p_ops::text, false);
  v := ops_record_manual_payout(p_runner, p_ids, t_pml_net(p_ids), p_memo);
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

-- Call the door as p_uid and report EITHER the rows OR the raise word — never both, and never a
-- swallowed success. `n` is reported separately from the rows so that 「zero rows」 and 「it raised」
-- are two different answers rather than one empty-looking one.
create or replace function t_pml_read_as(p_uid uuid, p_ids uuid[]) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'payout_id', x.payout_id,
             'label',     x.method_label) order by x.payout_id), '[]'::jsonb)
      into v from my_payout_method_labels(p_ids) x;
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- one row of a read, by payout id — NULL when the id is absent from the answer, which every
-- caller below distinguishes from a row whose label happens to be null.
create or replace function t_pml_row(p_js jsonb, p_id uuid) returns jsonb
language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_js->'rows', '[]'::jsonb)) e
   where e->>'payout_id' = p_id::text
   limit 1
$$;

do $$
declare
  oA   uuid; rA uuid; dA uuid; rtA uuid;   -- the runner this suite is about
  oB   uuid; rB uuid; dB uuid; rtB uuid;   -- a SECOND runner — the stranger, with real rows
  ops  uuid;
  bk1  uuid; bk2  uuid; bk3 uuid; bk4 uuid;
  payA1 uuid; payA2 uuid; payA3 uuid; payA4 uuid;
  payB  uuid; bkB uuid;
  c_memo   constant text := '신한 20260922-PML-SENTINEL-7731 이체 완료';
  c_label  constant text := '계좌 이체';
  c_unknown constant text := 'pg_auto_pml';
  v_js  jsonb;
  v_js2 jsonb;
  v_row jsonb;
  v_bad text := '';
  v_msg text;
  v_n   int;
  v_src text;
  v_raw text;
  v_oid oid;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  ops := t_user('pml_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'payout_due', true) on conflict (profile_id, event_class) do nothing;

  -- ── the world, built through the REAL doors ──────────────────────────────────────────────
  select w.o, w.r, w.d, w.rt into oA, rA, dA, rtA from t_pml_world('a', 4) w;
  select w.o, w.r, w.d, w.rt into oB, rB, dB, rtB from t_pml_world('b', 1) w;

  select id into bk1 from bookings where runner_id = rA order by created_at, id limit 1;
  select id into bk2 from bookings where runner_id = rA order by created_at, id offset 1 limit 1;
  select id into bk3 from bookings where runner_id = rA order by created_at, id offset 2 limit 1;
  select id into bk4 from bookings where runner_id = rA order by created_at, id offset 3 limit 1;
  select id into bkB from bookings where runner_id = rB order by created_at, id limit 1;

  -- two REAL payouts for runner A, the first carrying the sentinel ops memo (P3's fixture must
  -- contain the defect, or its absence arm is worth zero — 0151 N1/N2's lesson).
  payA1 := t_pml_pay(ops, rA, t_pml_items(bk1), c_memo);
  payA2 := t_pml_pay(ops, rA, t_pml_items(bk2), 'pml 두 번째 이체');
  -- two more for P4: one with a method this build does not know, one with NO method at all.
  -- Written through the real door and then UPDATEd, so everything except that one column is
  -- exactly what production holds (fixture note ②).
  payA3 := t_pml_pay(ops, rA, t_pml_items(bk3), 'pml 미지의 수단');
  payA4 := t_pml_pay(ops, rA, t_pml_items(bk4), 'pml 수단 없음');
  update payouts set method = c_unknown where id = payA3;
  update payouts set method = null       where id = payA4;
  -- one REAL payout for the OTHER runner — P2's stranger id is a live row, not a fiction
  payB := t_pml_pay(ops, rB, t_pml_items(bkB), 'pml 남의 이체');

  -- ① fixture honesty: the world this file asserts about is the world it thinks it built
  v_bad := '';
  if payA1 is null or payA2 is null or payA3 is null or payA4 is null or payB is null
    then v_bad := v_bad || ' 지급 행이 만들어지지 않았다'; end if;
  if (select method from payouts where id = payA1) is distinct from 'manual'
    then v_bad := v_bad || ' payA1.method=' || coalesce((select method from payouts where id = payA1), '(null)'); end if;
  if (select method from payouts where id = payA3) is distinct from c_unknown
    then v_bad := v_bad || ' payA3의 미지 수단이 심어지지 않았다'; end if;
  if (select method from payouts where id = payA4) is not null
    then v_bad := v_bad || ' payA4의 수단이 NULL이 아니다'; end if;
  if (select runner_id from payouts where id = payB) is distinct from rB
    then v_bad := v_bad || ' payB가 다른 러너의 행이 아니다'; end if;
  -- the four rows of runner A must be four DISTINCT payout rows: this file's discriminator is the
  -- id (no amount leaves this function), so two ids that happened to be equal would make 「it
  -- answered about the other row」 invisible in every pin below.
  if (select count(distinct x) from unnest(array[payA1, payA2, payA3, payA4]) x) is distinct from 4
    then v_bad := v_bad || ' 러너 A의 지급 행 네 개가 서로 다르지 않다'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('pml','fixture', v_msg); v_bad := ''; end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0200-P1] the runner sees HOW their own money arrived
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js := t_pml_read_as(rA, array[payA1, payA2]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 러너 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 2 then v_bad := v_bad || ' 행 수=' || (v_js->>'n'); end if;
      -- joined to the RIGHT id, both of them — a function that answered about one row twice, or
      -- about whichever row it found first, is visible here and nowhere else
      v_row := t_pml_row(v_js, payA1);
      if v_row is null then v_bad := v_bad || ' payA1이 답에 없다';
      elsif (v_row->>'label') is distinct from c_label
        then v_bad := v_bad || ' payA1 라벨=' || coalesce(v_row->>'label', '(null)'); end if;
      v_row := t_pml_row(v_js, payA2);
      if v_row is null then v_bad := v_bad || ' payA2가 답에 없다';
      elsif (v_row->>'label') is distinct from c_label
        then v_bad := v_bad || ' payA2 라벨=' || coalesce(v_row->>'label', '(null)'); end if;
    end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('pml','0200-P1 러너는 자기 지급이 **어떻게** 들어왔는지 본다 — 실제 문(ops_record_manual_payout)이 쓴 method=manual 두 행이 한 번의 호출에서 각자의 id에 붙은 고정 라벨 「계좌 이체」로 돌아온다(라벨을 id별로 확인하므로 한 행에 대해 두 번 답하거나 먼저 찾은 행에 대해 답하는 구현이 보인다)');
    else v_msg := v_bad; call _fail('pml','0200-P1 자기 지급 라벨', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pml','0200-P1 자기 지급 라벨', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0200-P2] 남의 id는 그냥 없다 — 없는 uuid와 구별되지 않는다 (존재 오라클이 아니다)
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- (a) another runner's REAL payout id
    v_js := t_pml_read_as(rA, array[payB]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' (a) 남의 id가 예외를 일으켰다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' (a) 남의 id 행 수=' || (v_js->>'n'); end if;
    -- (b) a uuid no payout has — must be the SAME answer, or the difference itself says 「이건 있다」
    v_js2 := t_pml_read_as(rA, array['00000000-0000-0000-0000-0000000200fe'::uuid]);
    if v_js2->>'raised' is not null then v_bad := v_bad || ' (b) 없는 id가 예외를 일으켰다: ' || (v_js2->>'raised');
    elsif (v_js2->>'n')::int is distinct from 0 then v_bad := v_bad || ' (b) 없는 id 행 수=' || (v_js2->>'n'); end if;
    if (v_js->'rows') is distinct from (v_js2->'rows')
      then v_bad := v_bad || ' (a)와 (b)의 답이 다르다 — id가 존재 오라클이 된다'; end if;
    -- (c) MIXED: my id beside a stranger's. The call must answer about MINE and not refuse —
    --     a refusal would hide every legitimate row beside one stale id, and the refusal itself
    --     would announce that the stranger's id exists (0200 §0d).
    v_js := t_pml_read_as(rA, array[payA1, payB]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' (c) 섞인 호출이 거절됐다: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 1 then v_bad := v_bad || ' (c) 섞인 호출 행 수=' || (v_js->>'n'); end if;
      if t_pml_row(v_js, payA1) is null then v_bad := v_bad || ' (c) 내 행이 빠졌다'; end if;
      if t_pml_row(v_js, payB)  is not null then v_bad := v_bad || ' 🔴 (c) 남의 행이 실렸다'; end if;
    end if;
    -- (d) an empty ask — zero rows and NOT an error
    v_js := t_pml_read_as(rA, '{}'::uuid[]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' (d) 빈 배열이 예외를 일으켰다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' (d) 빈 배열 행 수=' || (v_js->>'n'); end if;
    -- (e) no caller at all
    v_js := t_pml_read_as(null, array[payA1]);
    if (v_js->>'raised') is distinct from 'not_authenticated'
      then v_bad := v_bad || ' (e) 무기명 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- (f) CONTROLS, same ids, same block: the owner passes, and the OTHER runner passes on their
    --     own row. Without these 「전부 0행」 is green and so is a broken session.
    v_js := t_pml_read_as(rA, array[payA1]);
    if (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' (f) 대조 실패: 주인도 자기 행을 못 읽는다 ' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    v_js := t_pml_read_as(rB, array[payB]);
    if (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' (f) 대조 실패: 상대 러너도 자기 행을 못 읽는다 ' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    if (t_pml_row(v_js, payB)->>'label') is distinct from c_label
      then v_bad := v_bad || ' (f) 대조: 상대 러너의 라벨=' || coalesce(t_pml_row(v_js, payB)->>'label', '(null)'); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('pml','0200-P2 남의 지급 id는 그냥 부재다 — 실재하는 남의 행과 존재하지 않는 uuid가 **글자 그대로 같은 답**(0행·예외 없음)이라 id가 존재 오라클이 되지 않는다; 내 id와 남의 id를 섞어 물으면 거절이 아니라 내 것만 답한다(거절이면 한 개의 낡은 id가 나머지 정상 행의 라벨을 전부 가리고, 거절 자체가 그 id의 존재를 알린다); 빈 배열은 0행이고 예외가 아니다; 무기명은 not_authenticated; 대조 둘 — 같은 id에서 주인은 통과하고 상대 러너도 자기 행을 라벨까지 읽는다');
    else v_msg := v_bad; call _fail('pml','0200-P2 파티 범위', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pml','0200-P2 파티 범위', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0200-P3] THE OPS MEMO NEVER LEAVES — and the fixture contains the defect
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- CONTROL FIRST: the sentinel really is in the database. An absence pin over a world that
    -- never held the thing is worth exactly zero (0151 N1/N2's lesson).
    if (select p.memo from payouts p where p.id = payA1) is distinct from c_memo
      then v_bad := v_bad || ' 대조 실패: 지급 행에 운영 메모가 없다'; end if;
    if (select p.recorded_by from payouts p where p.id = payA1) is distinct from ops
      then v_bad := v_bad || ' 대조 실패: 지급 행에 기록자가 없다'; end if;

    v_js := t_pml_read_as(rA, array[payA1, payA2]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 읽기가 거절됨: ' || (v_js->>'raised');
    else
      -- by VALUE, over the WHOLE returned set rather than over a column list: a memo that arrived
      -- concatenated into the label, or in a third column added later, is caught here too.
      v_raw := v_js->>'rows';
      if (position('PML-SENTINEL-7731' in coalesce(v_raw, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 운영 메모가 러너 행에 실렸다'; end if;
      if (position(c_memo in coalesce(v_raw, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 운영 메모 전문이 러너 행에 실렸다'; end if;
      -- the RAW method token is server vocabulary and is not display copy either
      if (position('manual' in coalesce(v_raw, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 raw method 토큰이 러너 행에 실렸다'; end if;
      if (position(ops::text in coalesce(v_raw, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 기록자 uid가 러너 행에 실렸다'; end if;
    end if;
    -- the CONTRACT, off the catalog: exactly two output columns, named, and none of the ops three.
    select count(*)::int into v_n from unnest((select proargnames from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'my_payout_method_labels')) a
     where a in ('payout_id', 'method_label');
    if v_n is distinct from 2 then v_bad := v_bad || ' 출력 칸 이름 둘이 아니다 (' || v_n || ')'; end if;
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname = 'my_payout_method_labels'
                 and ('memo' = any(coalesce(p.proargnames, '{}'))
                      or 'method' = any(coalesce(p.proargnames, '{}'))
                      or 'recorded_by' = any(coalesce(p.proargnames, '{}'))))
      then v_bad := v_bad || ' 🔴 시그니처에 ops 칸이 있다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('pml','0200-P3 운영 메모는 서버를 떠나지 않는다 — 실제 문으로 쓴 센티넬 메모와 기록자 uid가 payouts 행에는 분명히 있고(대조 2개: 부재 핀이 빈 세계 위에 서지 않도록) 러너가 받은 어떤 값에도 없다; raw method 토큰(manual)도 없다 — 나가는 것은 라벨뿐이다; 출력은 payout_id·method_label 정확히 둘이고 memo·method·recorded_by는 시그니처에도 없다');
    else v_msg := v_bad; call _fail('pml','0200-P3 운영 메모 비노출', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pml','0200-P3 운영 메모 비노출', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0200-P4] 라벨은 method가 고른다 — 모르는 수단은 NULL이고 행은 사라지지 않는다
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- all four in ONE call: the known row and the two odd ones must coexist in one answer, which
    -- is also the shape the client actually asks in.
    v_js := t_pml_read_as(rA, array[payA1, payA3, payA4]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 3 then v_bad := v_bad || ' 행 수=' || (v_js->>'n'); end if;
      -- ⓐ the known method carries the label …
      v_row := t_pml_row(v_js, payA1);
      if v_row is null then v_bad := v_bad || ' manual 행이 답에 없다';
      elsif (v_row->>'label') is distinct from c_label
        then v_bad := v_bad || ' manual 라벨=' || coalesce(v_row->>'label', '(null)'); end if;
      -- ⓑ … an UNKNOWN token is PRESENT with a NULL label: the row is not filtered away (the
      --    client must still be able to tell 「내 행」 from 「남의 행」) and no word is guessed
      v_row := t_pml_row(v_js, payA3);
      if v_row is null then v_bad := v_bad || ' 🔴 모르는 수단의 행이 통째로 사라졌다';
      elsif (v_row->>'label') is not null
        then v_bad := v_bad || ' 🔴 모르는 수단에 낱말이 발명됐다: ' || (v_row->>'label'); end if;
      -- ⓒ … and a NULL method behaves the same way
      v_row := t_pml_row(v_js, payA4);
      if v_row is null then v_bad := v_bad || ' 🔴 수단이 없는 행이 통째로 사라졌다';
      elsif (v_row->>'label') is not null
        then v_bad := v_bad || ' 🔴 수단이 없는 행에 낱말이 발명됐다: ' || (v_row->>'label'); end if;
      -- the PAIR is what a constant cannot satisfy: one arm demands the label, two demand its
      -- absence, in the same call on the same caller's rows.
      if (t_pml_row(v_js, payA1)->>'label') is not distinct from (t_pml_row(v_js, payA3)->>'label')
        then v_bad := v_bad || ' 두 수단이 같은 답을 냈다 (상수)'; end if;
    end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('pml','0200-P4 라벨은 method가 고른다 — 한 번의 호출에서 manual은 「계좌 이체」를, 모르는 토큰과 NULL 수단은 **행은 그대로 둔 채 라벨만 NULL**을 낸다(행을 걸러 버리면 클라가 내 행과 남의 행을 구별할 수 없고, 낱말을 발명하면 아무도 안 쓴 카피가 돈 화면에 찍힌다); 어느 한쪽으로 고정된 상수는 세 팔을 동시에 만족시킬 수 없다');
    else v_msg := v_bad; call _fail('pml','0200-P4 수단→라벨', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pml','0200-P4 수단→라벨', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0200-S1] the deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'my_payout_method_labels';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(my_payout_method_labels)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
            from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      -- ACL by EFFECTIVE privilege, in BOTH directions. A `create` that relied on grant
      -- preservation is born PUBLIC-executable (0116:636), and this reads a money table.
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' ACL이 NULL이다 (기본 PUBLIC)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;

      -- COMMENTS STRIPPED before matching. `prosrc` is source plus our own prose, and the body's
      -- own comment names `memo` and `recorded_by` — an un-stripped match would be satisfied by
      -- the writing that EXPLAINS the guard (CLAUDE.md, the comment-matching law).
      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(my_payout_method_labels)';
      else
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'not_authenticated') is not true
          then v_bad := v_bad || ' not_authenticated 거절이 없다'; end if;
        if (v_src ~ 'runner_id\s*=\s*v_uid') is not true
          then v_bad := v_bad || ' 행 범위(runner_id = v_uid)가 없다'; end if;
        -- ONE read of the table, so a later edit cannot slip an unscoped second one in beside it
        if (select count(*) from regexp_matches(v_src, '\mpayouts\M', 'g')) is distinct from 1
          then v_bad := v_bad || ' payouts를 한 번보다 많이 읽는다'; end if;
        if (v_src ~ '\mmemo\M') is not false
          then v_bad := v_bad || ' 🔴 본문이 memo를 참조한다'; end if;
        if (v_src ~ '\mrecorded_by\M') is not false
          then v_bad := v_bad || ' 🔴 본문이 recorded_by를 참조한다'; end if;
        -- the crude/stripped CONTROL: the raw source DOES contain the word, so a stripper that
        -- silently did nothing would make the two arms above pass for the wrong reason.
        if (v_raw ~ '\mmemo\M') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 memo라는 낱말이 아예 없다 (주석 제거 팔이 무의미)'; end if;
      end if;
    end if;
    -- 0186:192-195's COLUMN SEAL is not this file's to move, and a file that widened it would
    -- still pass every arm above. `net` is the control: the grant was not simply deleted.
    if has_column_privilege('authenticated', 'public.payouts', 'method', 'select') is not false
      then v_bad := v_bad || ' 🔴 authenticated가 payouts.method를 직접 읽는다'; end if;
    if has_column_privilege('authenticated', 'public.payouts', 'memo', 'select') is not false
      then v_bad := v_bad || ' 🔴 authenticated가 payouts.memo를 직접 읽는다'; end if;
    if has_column_privilege('authenticated', 'public.payouts', 'recorded_by', 'select') is not false
      then v_bad := v_bad || ' 🔴 authenticated가 payouts.recorded_by를 직접 읽는다'; end if;
    if has_column_privilege('authenticated', 'public.payouts', 'net', 'select') is not true
      then v_bad := v_bad || ' 대조: authenticated가 payouts.net도 못 읽는다 (0186의 그랜트가 사라졌다)'; end if;
    if v_bad = '' then call _pass('pml','0200-S1 배포 형상 — definer·본문 search_path·ACL 양방향(NULL-ACL 팔 먼저)·주석 벗긴 소스에서 not_authenticated와 행 범위 runner_id = v_uid가 있고 payouts를 **정확히 한 번** 읽으며 memo·recorded_by 낱말이 본문에 없다(원본에는 있다는 크루드 대조 포함); 0186:192-195의 열 봉인은 그대로 — method·memo·recorded_by는 authenticated에게 여전히 닫혀 있고 net은 열려 있다(그랜트를 통째로 지운 게 아니라는 대조); NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('pml','0200-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('pml','0200-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
