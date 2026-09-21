-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0198 — the two reads an OPS CONSOLE needs and nothing else
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 229_ops_console_suite.sql (tag `opc`) — 0198-M1 · M2 · D1 · D2 · G1 · S1
--
-- DEPLOY: `supabase db push` + a client build. NO edge function changes, no cron, no secret.
-- ⚠ An operator only exists once Sean writes their row: `insert into ops_recipients
--   (profile_id, event_class, active) values ('<uuid>', 'payout_due', true);`. That table is
--   SEALED (0084 §E: RLS on, zero policies, server only) and this file does not write to it — a
--   migration that granted itself an operator would be a migration that decides who can read
--   bank account numbers.
--
-- ─── §0 WHAT IS MISSING, MEASURED BEFORE A LINE WAS WRITTEN ─────────────────────────────────────
-- 0186 · 0190 · 0192 · 0194 · 0195 built a payout loop that works and that **only works from
-- psql**. The operator's five doors are all there —
--     `ops_payouts_due()`            (0186 §B) who we owe and how much
--     `ops_record_manual_payout()`   (0186 §C) the journal entry for a transfer that happened
--     `ops_bank_account()`           (0194 §F④) where to send it, decrypted and journalled
--     `ops_gear_claims_pending()`    (0195 §C) which boxes to post
--     `ops_mark_gear_shipped()`      (0195 §D) the carrier and the tracking number
-- — and `app/` calls **none of them** (measured on trunk `5bab5e1`: zero references to any of the
-- five names under `app/`). So a phone cannot do the job, which means the job is done by
-- hand-typed SQL against production, which is the shape that produces the wrong `p_amount_won`.
--
-- ⚠ **ONLY TWO READS ARE ACTUALLY MISSING, AND THIS FILE ADDS EXACTLY THOSE TWO.** The temptation
--   with a console is to build a console-shaped API. Enumerated instead:
--     · the DUE list                → `ops_payouts_due()` already answers it. Untouched.
--     · the GEAR list and the SHIP  → 0195 already answers both. Untouched.
--     · the BANK read               → 0194 already answers it, journal and all. Untouched.
--     · the PAYOUT write            → 0186 already answers it. Untouched — and in particular the
--                                     `amount_mismatch` equality is NOT softened for a client
--                                     that now computes the number (§0b).
--   What has no door at all:
--     ① **「am I an operator?」** — `ops_recipients` is sealed, so a client cannot read its own
--        membership by any path. Without this the console entry is either always shown (a dead
--        button for every runner and owner in the product) or always hidden (the console is
--        unreachable). §A.
--     ② **the ROW IDS behind a runner's total.** `ops_payouts_due()` is aggregated PER RUNNER by
--        construction (`group by l.runner_id`) — it answers 「we owe this person 24,000원 across
--        4 rows」 and never says WHICH four. `ops_record_manual_payout` takes
--        `p_ledger_item_ids uuid[]`. There is no path from the first answer to the second
--        argument, and `ledger_items` is table-sealed (0121:224, restated 0186:200) so the client
--        cannot read them directly. §B.
--
-- ─── §0b THE CLIENT COMPUTES THE AMOUNT AND THE SERVER STILL REFUSES IT ─────────────────────────
-- The console's payout screen ticks rows and sends their sum as `p_amount_won`. That is NOT the
-- server trusting the client: 0186 §C recomputes the net from the LOCKED rows and raises
-- `amount_mismatch` on any disagreement, and this file changes nothing about that. The sum the
-- client sends is a SECOND opinion whose only job is to disagree when the operator's screen is
-- stale — a row paid by another terminal between the read and the tap is precisely the case where
-- the two numbers differ, and refusing is the correct answer. A console that sent the server's own
-- number back to it would turn the equality gate into a no-op while leaving it looking present.
--
-- ─── §0c WHAT §B DISCLOSES, AND WHY IT IS NOT 0186 §B's RULE BEING BROKEN ───────────────────────
-- 0186 §B refuses to carry a name, a phone, an address or a bank row beside a payable amount, on
-- the ground that one grant mistake would then disclose the PAIR. §B here carries a **dog's
-- name**, so the difference is stated rather than left to look like an oversight — the same way
-- 0195 §C stated its address exception.
--   · 0186 §B's subject is the rule 「the amount and the bank destination do not meet in one
--     window」. A dog's name is not a payment credential and cannot be used to move money.
--   · The operator's task here is 「which of these four rows does the transfer I just made
--     cover」. Without a human-legible row the screen is four checkboxes against four uuids, and
--     the failure mode of that screen is a WRONG BATCH — which is the exact failure 0186 §C's
--     equality gate exists to catch and would then catch every time, stalling the loop.
--   · The gate is the same gate. A caller who can reach §B can already reach `ops_bank_account`,
--     which decrypts an account number. This adds no new reachability.
-- What §B still refuses to carry: the runner's name, the runner's phone, the OWNER's identity, any
-- bank field, and the six fee components (Sean 2026-08-24, 「keep the margin a secret」 — 0192 §0c
-- records that `gross − net` IS the commission). `net_won` alone, the same expression the runner
-- is shown and the same one `ops_payouts_due()` sums.
--
-- ─── §0d `is_ops` MEANS 「CAN YOU USE THE CONSOLE」, NOT 「ARE YOU STAFF」 ──────────────────────────
-- All five shipped ops functions gate on `ops_recipients_for('payout_due')`. If `is_ops` meant
-- 「holds any active ops row」, an operator subscribed only to `charge_dispatch_stale` would see
-- the console entry and every door behind it would answer `not_ops` — a dead button reached
-- through an honest-looking check. So `is_ops` is computed THROUGH `ops_recipients_for` with the
-- same class constant the gates use: it is the gate's own answer, not a second opinion about it.
-- `kinds` is the caller's full active class list, which is a different and also true sentence; the
-- console entry is decided by `is_ops` alone, and `kinds` lets the refusal screen say 「you are an
-- operator, just not for this desk」 instead of a flat no.
--
-- ⚠ **AND `ops_me()` IS NOT AN ORACLE ABOUT ANYONE ELSE — IT TAKES NO ARGUMENT.** That is the
--   whole defence and it is structural rather than a gate: there is no parameter to point at
--   another profile, so no caller can ask it about a third party. A `p_uid` argument would have
--   made this function a staff-roster probe for every authenticated user in the product, which is
--   exactly what 0084 §E sealed `ops_recipients` to prevent. 229 `0198-S1` pins `pronargs = 0`.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A ops_me — the caller's own operator status, and only ever the caller's
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function ops_me()
returns table (is_ops boolean, kinds text[])
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- the SAME constant every shipped ops door uses (0186 §B/§C · 0194 §F④ · 0195 §C/§D). If a
  -- future desk moves to its own class, this line and those gates move together or the console
  -- entry stops meaning what it says.
  c_ops_class constant text := 'payout_due';
  v_uid   uuid := auth.uid();
  v_kinds text[];
  v_is    boolean;
begin
  -- ① There is no party gate to write here, because there is no party to gate: the subject IS
  --    `auth.uid()`. A caller with no subject is refused by name rather than answered `false` —
  --    「not signed in」 and 「signed in and not an operator」 are different facts and a screen that
  --    flattened them would show a sign-in-expired session the 운영자 전용 refusal.
  if v_uid is null then raise exception 'not_signed_in'; end if;

  -- ② the caller's OWN active classes. Scoped by `profile_id = v_uid` on a sealed table, so this
  --    definer reads exactly one person's rows and there is no argument by which to ask for
  --    another's. `'{}'` and not NULL when there are none — an empty list is an answer, and a NULL
  --    array would make `kinds[1] is null` and `array_length(kinds,1) = 0` disagree on the client.
  select coalesce(array_agg(r.event_class order by r.event_class), '{}'::text[])
    into v_kinds
    from ops_recipients r
   where r.profile_id = v_uid and r.active;

  -- ③ `is_ops` is the GATE'S answer, taken through the gate's own window (§0d). Not
  --    `'payout_due' = any(v_kinds)` — that would be a SECOND implementation of the membership
  --    rule, correct today and free to drift from `ops_recipients_for` tomorrow, and the drift
  --    would show up as a console entry that opens onto `not_ops`.
  v_is := coalesce((select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                                   where rc.profile_id = v_uid)), false);

  return query select v_is, v_kinds;
end $$;
revoke execute on function ops_me() from public, anon;
grant  execute on function ops_me() to authenticated;

comment on function ops_me is
  '0198 §A: 호출자 **자신**의 운영자 자격. 인자가 없다 — 그게 방어 그 자체다(남을 가리킬 파라미터가
없으므로 누구도 제3자에 대해 물을 수 없다; 0084 §E가 ops_recipients를 봉인한 이유가 바로 그것이다).
`is_ops`는 「운영자인가」가 아니라 **「이 콘솔을 쓸 수 있는가」**이고, 0186/0194/0195의 다섯 문이
쓰는 것과 같은 ops_recipients_for(''payout_due'') 창구로 계산한다 — `''payout_due'' = any(kinds)`로
쓰면 멤버십 규칙의 두 번째 구현이 생기고, 그 둘이 갈라지는 날 콘솔 입구가 not_ops로 열린다.
`kinds`는 호출자의 활성 클래스 전부(다른 문장이고 역시 참이다): 입구는 is_ops 하나로 정하고,
kinds는 거절 화면이 「운영자이긴 한데 이 창구는 아니다」라고 말할 수 있게 한다. 로그인이 없으면
false가 아니라 not_signed_in — 세션 만료와 「운영자가 아님」은 다른 사실이다. 229 0198-M1/M2가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ops_runner_payout_detail — the rows behind one runner's total, so a batch can be CHOSEN
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **THE PREDICATE AND THE NET EXPRESSION ARE 0186 §B's, TEXTUALLY.** Not 「equivalent」 —
--   the same clause, so a future edit to one is visible against the other. If the detail used a
--   different predicate, the rows an operator can tick would not sum to the total the same
--   operator is looking at, and the first symptom would be `amount_mismatch` on a correct batch:
--   two doors enforcing one ruling and answering differently, which is the failure 0194 §F③'s
--   header argues about from the other side.
--
-- ⚠ **NO `having sum(...) > 0` HERE, AND THAT IS DELIBERATE.** 0186 §B drops a RUNNER whose rows
--   net to zero or less, because an operator can do nothing with them. This function is inside one
--   runner, and dropping an individual NEGATIVE row would make the tickable rows sum to MORE than
--   `unpaid_net_won` — the operator would compute a number the server then refuses. Every unpaid
--   settled row the aggregate counted is returned, including a negative one.
--
-- ⚠ NO `limit`. `my_ledger_rows()` caps at 30 because it is a feed; this is a batch-selection
--   surface and a truncated list means an operator pays a subset while believing they paid a
--   runner off. The set is bounded by 「this one runner's unpaid settled rows」, which is bounded
--   by how far behind we are.
create or replace function ops_runner_payout_detail(p_runner uuid)
returns table (
  ledger_item_id uuid,
  booking_id     uuid,
  net_won        int,
  dog_name       text,
  cancel_comp    boolean,
  created_at     timestamptz,
  settled_at     timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  v_uid uuid := auth.uid();
begin
  -- ① PARTY GATE FIRST — before any read of anyone's money, and before the argument is even
  --    looked at. `p_runner is null` is checked AFTER, exactly as 0194 §F④ orders it: a stranger
  --    passing a null must learn `not_ops`, because the difference between `not_ops` and
  --    `no_runner` is itself information about the gate. For the same reason a stranger naming a
  --    runner who exists and a stranger naming a uuid that does not must get the identical word —
  --    229 `0198-G1` measures precisely that pair.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;
  if p_runner is null then raise exception 'no_runner'; end if;

  return query
  select l.id, l.booking_id,
         (l.base + l.distance_pay + l.addon_pay + l.tip
            + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int,
         d.name,
         -- existence, NOT attribution (0132's cancel_comp note): a ledger row with no `runs` row
         -- is a cancellation compensation (0080 §K · 0085). It is genuinely payable and it has no
         -- walk behind it, so the operator is told rather than shown a blank where a dog was.
         (r.id is null),
         l.created_at,
         -- `runs.settled_at` = 「did money happen」 (the settlement anchor). NULL on a cancel-comp
         -- row and NULL on a run that ended without a settlement stamp (0072 writes incident
         -- settlement ledgers without stamping it — 0192 §0b's ⓑ). Carried as NULL rather than
         -- coalesced to `created_at`, because a date we do not have is absent, not approximate.
         r.settled_at
    from ledger_items l
    join bookings b on b.id = l.booking_id
    left join dogs d on d.id = b.dog_id
    left join runs r on r.booking_id = l.booking_id
   where l.runner_id = p_runner
     -- ── 0186 §B's payable predicate, textually ──────────────────────────────────────────────
     and l.paid_payout_id is null
     -- §0d ⓒ: the one state where the booking's total can still move. `not exists` and NOT a
     -- reading of the `left join runs r` above — a cancel-comp row has no `runs` row at all, so
     -- `r.ended_at is null` evaluates TRUE through the join and would hide money we genuinely
     -- owe, forever, since no run will ever arrive to close it (0192 §0b, measured there).
     and not exists (select 1 from runs rn
                      where rn.booking_id = l.booking_id and rn.ended_at is null)
   order by l.created_at, l.id;
end $$;
revoke execute on function ops_runner_payout_detail(uuid) from public, anon;
grant  execute on function ops_runner_payout_detail(uuid) to authenticated;

comment on function ops_runner_payout_detail(uuid) is
  '0198 §B: 러너 한 명의 **미지급 정산 행들** — 운영자가 이번 이체가 어느 행들을 덮는지 고르려고
읽는다. ops_payouts_due()는 group by l.runner_id 로 합계만 주고 어느 행인지는 말하지 않는데
ops_record_manual_payout은 p_ledger_item_ids를 받는다; ledger_items는 테이블 봉인(0121:224)이라
클라가 직접 읽을 길이 없어 그 사이에 문이 없었다.
술어와 순액 식은 0186 §B의 것을 **글자 그대로** 쓴다(「동등한」이 아니라 같은 절) — 다르면 운영자가
고를 수 있는 행들의 합이 같은 화면의 합계와 어긋나고, 첫 증상은 올바른 배치에 대한 amount_mismatch다.
having sum>0은 **없다**: 그 절은 러너 단위로 무의미한 러너를 빼는 것이고, 여기서 개별 음수 행을
빼면 고를 수 있는 행들의 합이 unpaid_net_won보다 커진다. limit도 없다 — 잘린 목록은 운영자가
일부만 지급하고 다 갚았다고 믿게 만든다.
싣는 것: 원장 행 id · 예약 id · 순액 · 개 이름 · 취소보상 여부 · 생성시각 · runs.settled_at(없으면
NULL, 근사치로 채우지 않는다). 싣지 않는 것: 러너 이름·전화, 보호자 신원, 계좌 어느 칸도, 수수료
여섯 구성요소(0192 §0c — gross−net이 곧 수수료율이다). 개 이름은 0186 §B 규칙의 의도된 예외이고
근거는 0198 §0c에 적혀 있다: 그 규칙의 주어는 「금액과 계좌가 한 창구에서 만나지 않는다」이고,
개 이름은 돈을 옮길 수 있는 자격증명이 아니며, 그것이 없으면 화면은 uuid 네 개에 대한 체크박스가
되어 **잘못된 배치**라는 실패로 간다. 게이트는 모든 읽기보다 앞이고, 없는 러너와 있는 러너에게
같은 단어(not_ops)를 준다. 229 0198-D1·D2·G1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C VERIFY — this apply fails rather than ships a half-built gate
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ These arms and `229_ops_console_suite.sql` are DIFFERENT ARTIFACTS and neither is evidence for
--   the other: this aborts a production apply that lands wrong; the suite reddens when a LATER
--   file undoes something. Per `0131-G4`, a property checked only at apply is protected exactly
--   until someone recreates the function — so `0198-S1` restates these in the suite.
-- ⚠ Source matching strips comments first. This file documents its own guards at length, and a
--   check that the gate is CALLED would otherwise be satisfied by the paragraph EXPLAINING it —
--   the better the explanation, the more certainly green (CLAUDE.md, the comment-matching law).
do $verify$
declare
  v_bad text := '';
  v_oid oid;
  v_src text;
  fn    text;
  fns   text[] := array['ops_me()', 'ops_runner_payout_detail(uuid)'];
begin
  foreach fn in array fns loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') = 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':SEARCH-PATH'; end if;
    -- A definer born PUBLIC-executable is the worst shape this repo can produce (0116:636), and
    -- `create or replace` preserves an ACL only where the function ALREADY EXISTS. Both directions.
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC-EXEC'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':ANON-EXEC'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':NO-AUTHENTICATED'; end if;
  end loop;

  -- §0d's structural claim, asserted rather than trusted: `ops_me` has no argument, so it cannot
  -- be pointed at a third party. A future `ops_me(p_uid uuid)` aborts the apply here.
  if (select pronargs from pg_proc where oid = to_regprocedure('ops_me()')) is distinct from 0
    then v_bad := v_bad || ' ops_me:TAKES-ARGUMENTS'; end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_runner_payout_detail(uuid)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_runner_payout_detail)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' detail:NO-OPS-GATE'; end if;
    if (position('raise exception ''not_ops''' in v_src)
        < position('from ledger_items' in v_src)) is not true
      then v_bad := v_bad || ' detail:GATE-AFTER-READ'; end if;
    if (position('raise exception ''not_ops''' in v_src)
        < position('raise exception ''no_runner''' in v_src)) is not true
      then v_bad := v_bad || ' detail:NO-RUNNER-BEFORE-GATE'; end if;
    if (position('l.paid_payout_id is null' in v_src) > 0) is not true
      then v_bad := v_bad || ' detail:NOT-0186-PREDICATE'; end if;
    if (v_src ~ 'not exists \(select 1 from runs rn') is not true
      then v_bad := v_bad || ' detail:NOT-0186-SETTLED-CLAUSE'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_me()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_me)';
  else
    -- §0d: `is_ops` through the gate's own window, never a re-implementation of membership.
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' ops_me:NOT-THROUGH-ROSTER-WINDOW'; end if;
  end if;

  if v_bad <> '' then raise exception '0198 §C VERIFY:%', v_bad; end if;
end $verify$;
