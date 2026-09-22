-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0213 — the runner's home strip stops reading a 30-row window and calling it 「all my money」
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 244_ledger_stuck_state_suite.sql (tag `lss`) — 0213-A1 · A2 · A3 · A4 · A5 · S1
-- Deploy: `supabase db push` only, plus a client build. No edge function, no cron, no new table,
--         no new grant on any table.
--
-- ─── §0 THE DEFECT, MEASURED ON TRUNK 0776c11 ─────────────────────────────────────────────────
-- 0210 §E taught the server to tell a runner their payout is stuck, and `payout-status.ts`'s
-- `payoutStuckDays` let the SCREEN say it too, so a runner who never taps a push still finds out.
-- The screen's half reads `fetchLedger()` → `my_ledger_rows()` (0121 §A → 0192 §A), and that
-- function carries **`limit 30` ordered `created_at desc`**.
--
-- `payoutStuckDays` needs the **OLDEST** qualifying row. A `limit 30` on a DESCENDING order keeps
-- the THIRTY NEWEST and discards precisely the end the answer lives at. So:
--   · a runner with ≤ 30 ledger rows gets the right number,
--   · a runner with more gets a SHORTER number or no strip at all,
--   · and the second group is exactly the runners 0210 §E exists for — the ones with enough
--     settled work for a payout to be worth chasing.
-- The cap does not make the strip wrong at random. It makes it wrong **in the flattering
-- direction, for the busiest people, silently.** Nothing fails, no gate goes red, and the runner
-- sees a screen that says nothing and reads as 「everything is fine」.
--
-- 🔴 THIS IS THE THIRD TIME THE SAME CLASS HAS BEEN CLOSED ON THIS SURFACE, AND THE FIRST TWO
--    CLOSURES ARE WHY THE THIRD WAS EASY TO MISS. 0121 gave the ledger TOTAL its own function
--    rather than summing a capped list; 0209 §A gave the MONTH totals theirs, and its header says
--    in as many words that bucketing `my_ledger_rows` in JS 「would be silently WRONG for exactly
--    the runners who work most」. 0210 §E then derived an AGE from that same capped list. The
--    capped read was never re-introduced by carelessness — each slice re-derived a new aggregate
--    from the one list the client already had, which is the cheapest available shape every time.
-- ⚠ AND 0210 SAID SO OUT LOUD. `payout-status.ts`'s header carries a 🔴 paragraph stating the
--   under-report and naming it 「the `fetchRunnerJobs` cap class arriving through an aggregate」.
--   A documented defect is still a defect; the comment made the behaviour honest and left the
--   screen wrong. Saying 「it can only under-report」 in a file nobody reads at runtime is not the
--   same as not under-reporting. That paragraph is replaced in this slice, not merely softened.
--
-- ─── §0b WHY AN AGGREGATE AND NOT A WIDER LIMIT ───────────────────────────────────────────────
-- Raising `my_ledger_rows`' cap would fix this number and break the reason the cap exists (it is
-- the earnings LIST, and a list is drawn). It would also make the correctness of the strip depend
-- on a constant that another slice may lower for a rendering reason — a coupling nobody would
-- think to check. An aggregate is cap-immune by construction: it returns ONE row, so there is no
-- window to be outside of, which is 0209 §A's argument for the same move one question over.
--
-- ─── §0c THREE PREDICATES OVER ONE TABLE, AND TWO OF THEM ARE NOT THE SAME ────────────────────
-- 🔴 The single most dangerous thing this file could do is collapse 「unpaid」 and 「awaiting」 into
--    one number because they are equal on most fixtures. They are DIFFERENT PROPOSITIONS and this
--    repo already ships both, deliberately:
--
--   `my_ledger_unpaid_total()`      (0192 §B)  `paid_payout_id is null`
--        → 「what I have earned and not been paid」. INCLUDES a row whose run is still open,
--          because that money is genuinely still ours to pay. The client labels it 미지급.
--   `ops_payouts_stuck_sweep()`     (0186 §D → 0190 §A → 0210 §E)
--        → `paid_payout_id is null` AND 0186 §0d ⓒ's 「no run on this booking is still open」.
--          That is what the writer will actually PAY, and it is the candidate set whose
--          `min(created_at)` decides that a runner is stuck.
--   `ledgerPaymentState(row) === 'awaiting'`   (payout-status.ts)
--        → the client's name for the second one, row by row. `payoutStuckDays` filters on it.
--
-- So this function returns BOTH moduli, each under a column named after its own sentence:
--   · `unpaid_won`                     — 0192 §B's predicate. Equal to `my_ledger_unpaid_total()`.
--   · `oldest_awaiting_at`             — the sweep's predicate. NULL when no row qualifies.
--   · `awaiting_count`                 — the sweep's predicate, counted.
-- 244 `0213-A2` pins the equality as a RESULT rather than trusting the transcription, and it does
-- so on a fixture that holds an UNSETTLED unpaid row — so `unpaid_won` and the awaiting sum
-- genuinely DISAGREE there. A fixture where every unpaid row is settled sits in the zone where
-- the two predicates AGREE, and a pin there would be green under either implementation
-- (CLAUDE.md, the 175-V2 fixture-agreement law).
--
-- ─── §0d WHAT THE FOURTH COLUMN IS FOR, AND WHAT IT IS NOT ────────────────────────────────────
-- `has_bank_account` is `exists (select 1 from bank_accounts where runner_id = auth.uid())` — the
-- same read 0210 §E does before choosing between 「수익 화면에서 내역을 확인할 수 있어요」 and
-- 「정산 계좌를 확인해주세요」. It is a BOOLEAN about the caller's own registration state and
-- carries no bank, no holder and no ciphertext; `bank_accounts` is never selected from beyond
-- `exists`. 0194 §F④'s access journal is the OPERATOR's door (`ops_bank_account`) and is not
-- touched here — a runner asking whether they themselves have registered an account is not an
-- access to anybody's details.
--
-- ⚠ **`unpaid_won` AND `has_bank_account` HAVE NO CLIENT READER IN THIS SLICE, AND THAT IS SAID
--   HERE RATHER THAN LEFT FOR SOMEONE TO DISCOVER.** The strip's copy is unchanged by decision, so
--   only `oldest_awaiting_at` is rendered today. They are returned now instead of later because
--   `create or replace` REFUSES a return-type change on a returns-table function — adding a
--   column afterwards costs a `drop` + `create`, and 0192 §A's header records what that costs:
--   the recreated function is a plain CREATE, born PUBLIC-executable (0116:636), so every later
--   column is also a new chance to ship a PUBLIC security definer over sealed money rows. Two
--   columns the caller may already read about themselves, in one round trip, is the cheaper and
--   safer shape. Nothing here is a mockup: both are computed from real rows on every call.
--
-- ─── §0e THE PARTY GATE IS AN ABSENCE ─────────────────────────────────────────────────────────
-- There is NO subject argument. The only runner this function can be asked about is `auth.uid()`,
-- which is the sole conjunct of its only WHERE clause and the sole conjunct of the bank read. An
-- anonymous caller is refused BEFORE any table is touched. That shape is stronger than a checked
-- argument because there is nothing to check, and 244 `0213-S1` asserts it over
-- `pg_proc.proargnames` rather than over behaviour — a `p_runner` added later would redden no
-- behavioural arm on a fixture where the caller and the subject are the same person (0203 `E4`).
--
-- ─── §0f WHAT THIS FILE DOES NOT DO ───────────────────────────────────────────────────────────
-- No ledger row, settlement, payout or notification moves. `my_ledger_rows` keeps its `limit 30`
-- (it is the LIST and the cap is right there), `my_ledger_unpaid_total`, `my_ledger_total`,
-- `my_ledger_month_totals`, `ops_payouts_due` and `ops_payouts_stuck_sweep` are untouched, and no
-- table grant changes. This is a READ beside them — 0192 §0's reasoning for adding a SECOND
-- function rather than widening a correct one applies here unchanged (the §④ class: widening what
-- an existing value MEANS breaks correct callers with no edit to them).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A my_ledger_stuck_state — one flat row, over EVERY row the runner owns
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ Money is `bigint` to match `my_ledger_total` / `my_ledger_unpaid_total`, so `0213-A2`'s
--   equality is measured without a cast standing between the two numbers.
-- ⚠ The aggregate query has no GROUP BY, so it returns EXACTLY ONE ROW even for a runner with no
--   ledger rows at all: `unpaid_won` 0, `oldest_awaiting_at` NULL, `awaiting_count` 0. A caller
--   that got zero rows back would have to invent a meaning for the absence, and 「no rows」 and
--   「nothing owed」 are different facts. `has_bank_account` is read into a variable rather than
--   written as a scalar subquery in the target list, so its answer does not depend on the shape
--   of an aggregate that may be summing nothing.
create function my_ledger_stuck_state()
returns table (unpaid_won bigint, oldest_awaiting_at timestamptz,
               awaiting_count int, has_bank_account boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_bank boolean;
begin
  -- Party gate BEFORE any state read (house law). There is nothing to compare a subject against
  -- because there is no subject — see §0e.
  if auth.uid() is null then raise exception 'not_authenticated'; end if;

  -- §0d: the caller's own registration state, as a boolean and nothing else.
  v_bank := exists (select 1 from bank_accounts ba where ba.runner_id = auth.uid());

  return query
  -- 🔴 NO `limit`, AND NO ORDER FOR A ROW TO FALL OUTSIDE OF. This CTE is every ledger row the
  --    runner owns, which is the whole point of the file: `my_ledger_rows`' `limit 30` on a
  --    `created_at desc` order keeps the thirty NEWEST and throws away the end `min()` lives at.
  with mine as (
    select l.created_at,
           -- 0027/0121 §F's summand, character for character, and deliberately NOT cast here:
           -- `sum(int)` is bigint while `sum(bigint)` is numeric, and 0213-A2 compares this
           -- against `my_ledger_unpaid_total()` with no cast standing between the two numbers.
           (l.base + l.distance_pay + l.addon_pay + l.tip
              + coalesce(l.remaining_guarantee, 0) - l.platform_fee) as net,
           -- §0c ①: 0192 §B's predicate. Settled or not — an open run's money is still ours to
           -- pay, which is exactly why 0192 §B left the settled conjunct out on purpose.
           (l.paid_payout_id is null) as unpaid,
           -- §0c ②: 0186 §0d ⓒ's payable-side conjunct, transcribed from 0210 §E and 0192 §A.
           -- Written as a proof of ABSENCE so a NULL from any cause reads as 「not settled」
           -- rather than as 「settled」: the direction that refuses is the safe one when the
           -- other direction is a promise of money.
           (not exists (select 1 from runs rn
                         where rn.booking_id = l.booking_id and rn.ended_at is null)) as settled
      from ledger_items l
     where l.runner_id = auth.uid()
  )
  select
    coalesce(sum(m.net) filter (where m.unpaid), 0)::bigint,
    -- the OLDEST row the writer would actually pay. NULL when no row qualifies — and the screen
    -- draws nothing for NULL, because 「nothing to say」 and 「zero days」 are different sentences.
    min(m.created_at) filter (where m.unpaid and m.settled),
    -- the same predicate, counted. `count` never returns NULL, so an empty answer is 0 rather
    -- than an absence — and that 0 is a MEASURED zero, never a loading state.
    (count(*) filter (where m.unpaid and m.settled))::int,
    v_bank
  from mine m;
end $$;
revoke execute on function my_ledger_stuck_state() from public, anon;
grant execute on function my_ledger_stuck_state() to authenticated;

comment on function my_ledger_stuck_state is
  '0213 §A: 러너 본인의 **미지급 상태 한 행** — 캡이 없다. 0210 §E의 홈 스트립은
my_ledger_rows(0121 §A/0192 §A)를 읽었는데 그 함수는 `limit 30`을 created_at DESC로 걸어
**가장 최신 30행만** 남긴다. 그런데 「며칠째 밀렸나」는 **가장 오래된** 해당 행이 답이라서,
많이 뛴 러너일수록 짧은 숫자나 아무 줄도 못 봤다 — 0210 §E가 존재하는 이유인 바로 그 사람들이다.
**두 모수를 함께 돌려주고, 둘은 같은 것이 아니다**: unpaid_won 은 0192 §B의 술어
(paid_payout_id IS NULL, 정산 여부 불문 — 끝나지 않은 run의 돈도 우리가 갚을 돈이다),
oldest_awaiting_at·awaiting_count 는 스윕의 후보 술어(미지급 **그리고** 0186 §0d ⓒ의
「이 예약에 끝나지 않은 run이 없다」)다. 대부분의 픽스처에서 둘은 같고, 같다고 하나로 합치면
지급 대기가 아닌 행이 나이 계산에 들어간다. 해당 행이 없으면 oldest_awaiting_at 은 NULL이고
화면은 아무것도 그리지 않는다(0이 아니라 없음 — 0은 측정된 0이어야 한다).
has_bank_account 은 0210 §E가 문장을 고를 때 하는 그 exists 읽기이고 불리언 하나뿐이다 —
계좌도, 예금주도, 암호문도 나가지 않는다. 인자가 없다는 것이 파티 게이트다: 물어볼 수 있는
러너는 auth.uid() 뿐이다. 244 0213-A1 ~ A5 · S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B VERIFY — apply-time, and it owns a different sentence than the suite does
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The suite asserts the standing invariant against the schema the harness builds. This block
-- asserts it against the schema THIS FILE just built, on whatever database it was applied to, and
-- it aborts before anything downstream can run. The overlap is deliberate (0131-G4's lesson: a
-- property checked only at apply is protected exactly until someone recreates the function, and a
-- property checked only in a suite is not checked on the environment the file actually lands on).
do $$
declare
  v_oid oid;
  v_raw text;
  v_src text;
  v_bad text := '';
begin
  select oid into v_oid from pg_proc
   where proname = 'my_ledger_stuck_state' and pronamespace = 'public'::regnamespace;

  -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
  if v_oid is null then v_bad := v_bad || ' MISSING(my_ledger_stuck_state)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
    -- a CREATE is born PUBLIC-executable (0116:636). The NULL arm goes FIRST, because
    -- aclexplode(NULL) returns zero rows and an `exists` test alone is silent on exactly that.
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
      then v_bad := v_bad || ' PUBLIC-OR-ANON'; end if;
    -- the positive half: a seal that also shut the front door passes every negative sweep and
    -- ships an outage (189 0158-B5's warning, applied at birth).
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' AUTHENTICATED-CANNOT'; end if;

    -- ① §0e: the party gate is an ABSENCE. No subject argument, of any spelling.
    if (select count(*) from unnest(
          coalesce((select proargnames from pg_proc where oid = v_oid), '{}'::text[])) n
         where n in ('p_runner', 'p_uid', 'p_profile', 'p_runner_profile_id', 'p_runner_id'))
         is distinct from 0
      then v_bad := v_bad || ' TAKES-A-SUBJECT(the gate must be auth.uid() and nothing else)'; end if;
    -- ② §0d / the 2026-08-24 margin ruling: no component of the fare may ride out beside a net.
    if exists (select 1 from unnest(
                 coalesce((select proargnames from pg_proc where oid = v_oid), '{}'::text[])) n
                where n in ('gross_won', 'fee_won', 'commission_rate', 'platform_fee', 'gross',
                            'account_enc', 'bank', 'holder'))
      then v_bad := v_bad || ' MARGIN-OR-BANK-COLUMN-ON-A-RUNNER-SURFACE'; end if;

    select prosrc into v_raw from pg_proc where oid = v_oid;
    if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(my_ledger_stuck_state)';
    else
      -- Comments are stripped before every match. `prosrc` is source PLUS our own prose, and this
      -- file's body documents every predicate it implements — so an un-stripped check would be
      -- satisfied by the EXPLANATION of a conjunct rather than by the conjunct (CLAUDE.md, the
      -- comment-matching law).
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      -- ③ the whole point of the file: no cap, in the EXECUTABLE text.
      if (v_src ~ '\mlimit\M') is distinct from false
        then v_bad := v_bad || ' A-LIMIT-CAME-BACK(this function exists because the list has one)'; end if;
      -- ④ the row scope, and it is the caller's own uid
      if (v_src ~ 'l\.runner_id = auth\.uid\(\)') is distinct from true
        then v_bad := v_bad || ' NO-PARTY-SCOPE'; end if;
      if (v_src ~ 'ba\.runner_id = auth\.uid\(\)') is distinct from true
        then v_bad := v_bad || ' BANK-READ-NOT-SCOPED-TO-THE-CALLER'; end if;
      if (v_src ~ 'not_authenticated') is distinct from true
        then v_bad := v_bad || ' NO-ANONYMOUS-REFUSAL'; end if;
      -- ⑤ §0c ②: the sweep's settled conjunct is present, by its executable shape.
      if (v_src ~ 'not exists \(select 1 from runs rn') is distinct from true
        then v_bad := v_bad || ' NO-SETTLED-CONJUNCT(the age would count rows the writer refuses to pay)'; end if;
      if (v_src ~ 'rn\.ended_at is null') is distinct from true
        then v_bad := v_bad || ' SETTLED-CONJUNCT-DOES-NOT-TEST-AN-OPEN-RUN'; end if;
      -- ⑥ THE CRUDE CONTROL FOR THE STRIPPER. The RAW source contains a `--` comment carrying the
      --    word `limit` (③ would pass for the wrong reason if the stripper silently did nothing —
      --    in the direction that FAILS, which is the honest way round for this particular arm, and
      --    it would still mean ③ was measuring prose). Both sides are asserted: the raw text HAS
      --    the comment, the stripped text has NOT.
      if (v_raw ~ '-- 🔴 NO `limit`') is distinct from true
        then v_bad := v_bad || ' STRIP-CONTROL-ABSENT(the arms above prove nothing)'; end if;
      if (v_src ~ '-- 🔴 NO `limit`') is distinct from false
        then v_bad := v_bad || ' STRIPPER-DID-NOT-RUN'; end if;
    end if;
  end if;

  -- ⑦ this file must not have moved the two functions its number is compared against.
  if to_regprocedure('my_ledger_unpaid_total()') is null
    then v_bad := v_bad || ' MISSING(my_ledger_unpaid_total — 0213-A2 compares against it)'; end if;
  if to_regprocedure('ops_payouts_stuck_sweep()') is null
    then v_bad := v_bad || ' MISSING(ops_payouts_stuck_sweep — 0213-A3 compares against it)'; end if;

  if v_bad <> '' then raise exception '0213 VERIFY failed:%', v_bad; end if;
end $$;
