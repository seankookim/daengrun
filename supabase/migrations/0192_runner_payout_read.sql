-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0192 — the runner can be PAID, and now the runner can SEE it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 223_runner_payout_read_suite.sql (tag `rpr`) — 0192-R1 · R2 · R3 · R4 · S1
--
-- ─── §0 WHAT THIS FILE IS FOR, AND THE THREE READS IT IS NOT ────────────────────────────────────
-- 0186 gave `payouts` its first writer (`ops_record_manual_payout`) and gave `ledger_items` the
-- marker `paid_payout_id`. 0190 made the bank-detail retention END on final payment. So the money
-- can now move and the database records that it moved — and **the runner's own earnings screen
-- says nothing about any of it**: measured on trunk `92518b0`, `app/src/lib/api.ts` and
-- `app/app/runner/earnings.tsx` contain zero references to `payouts` or `paid_payout_id`.
--
-- ⚠ **THREE OF THE FOUR READS THIS SLICE NEEDS ALREADY EXIST, AND THIS FILE DELIBERATELY DOES NOT
--    ADD THEM AGAIN.** Measured before writing a line of SQL:
--
--   ① **the payouts LIST needs no function.** `payouts` carries RLS `payouts self read`
--      (`0002:126`, `runner_id = auth.uid()`) and 0186:192-195 re-granted a COLUMN-LIMITED SELECT
--      to `authenticated` — `(id, runner_id, period_start, period_end, gross, tax_withheld, net,
--      status, instant, paid_at)`. A runner reading their own payout rows through PostgREST is
--      therefore already correct, already scoped by row AND by column, and already pinned
--      (217 `0186-S1` fixes the column seal by value). A `my_payouts()` definer here would
--      duplicate a shipped grant with a SECOND surface whose column list a later session could
--      widen without ever touching 0186 — which is how the ops half (`memo` · `method` ·
--      `recorded_by`) would eventually follow the runner home. The seal is worth more than the
--      convenience. **223 `0192-R4` owns the runner-side half of that seal** so the decision is
--      guarded rather than merely argued.
--   ② `my_ledger_total()` (0121 §F) is UNTOUCHED. Its sentence is 「every ledger row this runner
--      ever earned」 and that sentence is still true; changing what it MEANS would break its
--      correct callers with no edit to them (the §④ class). §B adds a SECOND function instead.
--   ③ `ops_payouts_due()` / `ops_record_manual_payout()` are ops surfaces and stay ops surfaces.
--
-- What is genuinely missing is the **per-row** fact, and it is missing for a structural reason:
-- `ledger_items` is table-sealed (`0121:224`, restated at `0186:200`), so every runner read of it
-- is an RPC, and the only such RPC — `my_ledger_rows()` — does not return `paid_payout_id`. There
-- is no client-side way to recover it: inferring 「paid」 from a payout's `period_start`/`period_end`
-- covering a row's date would be a GUESS rendered as a fact, which is the honesty law this repo
-- states first. So: §A widens the read.
--
-- ─── §0b THE THREE STATES A LEDGER ROW IS IN, AND WHY `settled` IS RETURNED ─────────────────────
-- 0186 §0d ⓒ established the payable predicate: a row is payable when `paid_payout_id is null`
-- **and** no run on its booking is still open. That second conjunct is not decoration — it is the
-- one state in which the settlement can still write MORE rows for the same booking, so paying it
-- would pay a number that is about to change. It follows that a runner's row is in one of three
-- states, not two:
--     paid          — `paid_payout_id` is set. The money has moved. `paid_at` says when.
--     awaiting      — settled, unpaid. We owe this.
--     not settled   — a run on this booking has not ended. The amount is not final.
-- A client that knows only `paid_payout_id` would flatten the last two into 「지급 대기」 and tell a
-- runner we owe them a number that can still move. `settled` is returned so the screen can stay
-- silent on the third state rather than guess, and it is written as the SAME `not exists` the
-- writer gates on — textually, so a future change to one is visible against the other.
--
-- ⚠ **IT IS A FRESH `not exists` AND NOT A READING OF THE EXISTING `left join runs r` — AND THE
--    REASON IS NOT THE ONE THAT SUGGESTS ITSELF FIRST.** 「a booking may carry several runs, so the
--    join would answer about the wrong one」 is FALSE and this file said it until the harness
--    refused the fixture: `runs.booking_id` is **UNIQUE** (`0001:236`), so that worry does not
--    exist. The real reason is the row with NO run at all. A cancellation-compensation ledger row
--    (0080 `record_enroute_cancel_comp` · 0085 `record_late_cancel_share`) has no `runs` row, so
--    the LEFT JOIN contributes nothing and `r.ended_at is null` evaluates **TRUE** — the join form
--    would call that row 「a run is still open」 and hide 「지급 대기」 from money we genuinely owe,
--    forever, since no run will ever arrive to close it. `not exists` answers TRUE (settled),
--    which is also what `ops_payouts_due()` concludes about the same row: reader and writer agree.
--    223 `0192-R2` ⓑ is that arm, and it is the only reachable way to tell the two forms apart.
--
-- ─── §0c WHAT DOES **NOT** GO TO THE CLIENT, restated because this is a money surface ───────────
-- `payouts.gross` and `payouts.tax_withheld` are grantable and the client will not read them.
-- `gross − net` IS the platform fee, and the fee ÷ gross IS `commission_rate` — the exact
-- subtraction `runner/earnings.tsx`'s own header records as the reason the per-row breakdown was
-- deleted (Sean 2026-08-24: 「keep the margin a secret」). A payout row that prints both numbers
-- hands back in one line what that ruling removed from thirty. The screen reads `net` alone.
-- Nothing here revokes `gross`/`tax_withheld` — a client-side discipline is not a server change,
-- and narrowing 0186's measured whitelist is 0186's slice, not this one's.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A my_ledger_rows — the earnings list learns whether each row has been PAID
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ `drop` + `create`, not `create or replace`: postgres REFUSES a return-type change on a
--   replace, and this returns-table gains three columns. The consequence is the one 0116:636
--   records — **a plain CREATE is born PUBLIC-EXECUTABLE** — so the revoke/grant pair below is not
--   restatement-for-tidiness, it is the only thing standing between a SECURITY DEFINER over sealed
--   money rows and every anonymous caller. 189 `0158-B5` and 98 H9 both read it back.
-- ⚠ The three columns are APPENDED. Every existing consumer names its columns
--   (156 P3/P10 · 165 · 189 read `x.net` / `x.km` / `x.end_reason`; the client maps by key), so
--   position is not load-bearing — but appending keeps the diff to what changed and leaves the
--   0158 §A body byte-identical where it is unchanged, which is what makes the VERIFY arms below
--   able to assert that this slice did not quietly alter the distance decision.
-- ⚠ NOTHING ELSE IN THIS BODY MOVES. `b.km` stays absent (0158's finding #9), `r.actual_km` stays,
--   the attribution gate on `b.runner_id is distinct from l.runner_id` stays, `limit 30` stays.
drop function if exists my_ledger_rows();
create function my_ledger_rows()
returns table (id uuid, booking_id uuid, net int, cancel_comp boolean,
               km numeric, end_reason text, dog_name text, created_at timestamptz,
               paid_payout_id uuid, paid_at timestamptz, settled boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select l.id, l.booking_id,
         (l.base + l.distance_pay + l.addon_pay + l.tip
            + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int,
         -- existence, NOT attribution — see the cancel_comp note in 0132's header
         (r.id is null),
         -- [0158 §A] the MEASURED distance, never the planned one. NULL when the run exists and
         -- nobody measured it — the money on this line was priced from the same absence.
         case when r.id is null or b.runner_id is distinct from l.runner_id
              then null else r.actual_km end,
         case when b.runner_id is distinct from l.runner_id
              then null else r.end_reason::text end,
         d.name, l.created_at,
         -- [0192 §A] the marker `ops_record_manual_payout` writes, and the instant off the payout
         -- row it points at. `paid_payout_id` is what DECIDES paid/unpaid; `paid_at` only supplies
         -- the date, and it is deliberately allowed to be NULL under a non-null id — `payouts`
         -- has three states besides `paid` (0001:22) and a future writer may insert a row before
         -- the money lands. The client renders 「지급 완료」 with no date in that case rather than
         -- inventing one, which is the same law as `end_reason`'s unmapped → NULL directly above.
         l.paid_payout_id,
         po.paid_at,
         -- [0192 §A] 0186 §0d ⓒ's payable-side conjunct, verbatim, and it is the only honest way
         -- to keep 「지급 대기」 off a row whose amount can still change. Written as a proof of
         -- ABSENCE so a NULL from any cause reads as 「not settled」 rather than as 「settled」 —
         -- the direction that refuses is the safe one when the other direction is a promise.
         (not exists (select 1 from runs rn
                       where rn.booking_id = l.booking_id and rn.ended_at is null))
  from ledger_items l
  join bookings b on b.id = l.booking_id
  left join dogs d on d.id = b.dog_id
  left join runs r on r.booking_id = l.booking_id
  left join payouts po on po.id = l.paid_payout_id
  where l.runner_id = auth.uid()
  order by l.created_at desc
  limit 30;
end $$;
revoke execute on function my_ledger_rows() from public, anon;
grant execute on function my_ledger_rows() to authenticated;

comment on function my_ledger_rows is
  '0192 (was 0158, 0132 §A, 0121 §A): 러너 수익 목록. 순액만 — 여섯 구성요소는 서버를 떠나지
않는다(Sean 2026-08-24 마진 비밀). `km`은 `runs.actual_km`(그 돈이 매겨진 거리). **0192가 더한
세 칸**: `paid_payout_id`는 0186이 만든 지급 표식이고 지급 여부를 **결정하는** 값, `paid_at`은 그
payouts 행의 시각으로 **날짜만** 공급한다(표식이 있는데 NULL일 수 있다 — payouts에는 paid 말고도
세 상태가 있다; 그때 화면은 날짜 없이 「지급 완료」라고만 쓴다), `settled`는 0186 §0d ⓒ의
「이 예약에 끝나지 않은 run이 없다」를 그대로 옮긴 것이다. 세 칸이 함께 있어야 행이 세 상태로
읽힌다 — 지급됨 · 정산됐고 미지급 · 아직 정산 전. 앞의 둘만 있으면 금액이 아직 바뀔 수 있는 행에
「지급 대기」라고 쓰게 된다. 223 0192-R1/R2/S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B my_ledger_unpaid_total — because 「정산 예정」 over a lifetime total becomes a LIE on payday
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `my_ledger_total()` (0027, made definer by 0121 §F) sums EVERY ledger row the runner has ever
-- earned, paid or not. That was exactly right for the whole life of this product, because nothing
-- could write `payouts` and therefore no row was ever paid — `0115:541-548` recorded the same fact
-- from the other side (「unpaid balance is NOT COMPUTABLE on this schema; only LIFETIME EARNINGS
-- are」). 0186 made it computable, and the moment the first manual payout lands,
-- `runner/earnings.tsx`'s heading — 「정산 예정 · 원장 합계」 — starts telling a runner that money
-- already in their bank account is still coming.
--
-- ⚠ **THE DEFECT IS THE UNCHANGED LINE.** Nothing in the client is wrong, nothing fails, no gate
--   goes red, and no grep finds it: 0186 widened what the WORLD can contain, and a correct caller
--   became incorrect without being edited. Same shape as the §④ law, arriving through the data
--   rather than through a return type.
--
-- ⚠ Why a SECOND function and not a redefinition: `my_ledger_total` has four other readers
--   (121 · 122 · 137 · 153 · 20 pin it; 156 P10 asserts it equals Σ my_ledger_rows().net), and
--   every one of them means LIFETIME. Changing its meaning to close a client-copy problem would
--   break five pinned propositions to fix one sentence of Korean.
-- ⚠ The predicate is `paid_payout_id is null` and NOT 0186 §0d ⓒ's payable predicate. This number
--   answers 「how much of what I earned has not been paid to me」 — which includes a row whose run
--   is still open, because that money is genuinely still ours to pay. 「what is payable RIGHT NOW」
--   is a different question, it is the OPERATOR's question, and `ops_payouts_due()` already
--   answers it. Two numbers, two sentences; the client labels this one 미지급, never 지급 예정.
create function my_ledger_unpaid_total() returns bigint
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v bigint;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)
    into v from ledger_items
   where runner_id = auth.uid() and paid_payout_id is null;
  return v;
end $$;
revoke execute on function my_ledger_unpaid_total() from public, anon;
grant execute on function my_ledger_unpaid_total() to authenticated;

comment on function my_ledger_unpaid_total is
  '0192 §B: 아직 지급되지 않은 원장 순액 합계 — my_ledger_total(0027/0121 §F)과 **같은 식, 다른
모수**다. 0186 이전에는 둘이 항상 같았고(지급 기록자가 없었으므로) 그래서 화면이 평생 누계에
「정산 예정」이라고 써도 참이었다. 이제는 아니다. 술어는 paid_payout_id IS NULL 하나뿐이고
0186 §0d ⓒ의 「끝나지 않은 run이 없다」는 **일부러 빼 놓았다** — 그건 「지금 지급 가능한가」라는
운영자의 질문이고 ops_payouts_due()가 이미 답한다. 이 함수의 문장은 「내가 번 것 중 아직 못 받은
것」이다. 223 0192-R3이 핀(두 함수가 서로 다른 답을 내는 픽스처 포함).';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C VERIFY — apply-time, and it owns a different sentence than the suite does
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The suite asserts the standing invariant against the schema the harness builds. This block
-- asserts it against the schema THIS FILE just built, on whatever database it was applied to, and
-- it aborts before anything downstream can run. The overlap is deliberate (0131-G4's lesson: a
-- property checked only at apply is protected exactly until someone recreates the function, and a
-- property checked only in a suite is not checked on the environment the file actually lands on).
-- ⚠ Comments are STRIPPED before every source match. `prosrc` is source PLUS our own prose, and
--   every sentence explaining a guard is a string that satisfies a check for the guard — this
--   file's §A body documents `paid_payout_id` in three comments.
do $$
declare
  v_bad text := '';
  v_src text;
  v_oid oid;
  f text;
begin
  foreach f in array array['my_ledger_rows', 'my_ledger_unpaid_total'] loop
    select p.oid into v_oid from pg_proc p
     where p.proname = f and p.pronamespace = 'public'::regnamespace;
    -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
    if v_oid is null then v_bad := v_bad || ' MISSING(' || f || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NOT-DEFINER(' || f || ')'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH(' || f || ')'; end if;
    -- a DROP discards the ACL and a CREATE is born PUBLIC (0116:636) — the NULL arm FIRST, because
    -- aclexplode(NULL) returns zero rows and an `exists` test alone is silent on exactly that state
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL(' || f || ')';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
      then v_bad := v_bad || ' PUBLIC-OR-ANON(' || f || ')'; end if;
    -- the positive half: a seal that also shut the front door passes every negative sweep and
    -- ships an outage (189 0158-B5's own warning, applied here at birth)
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' AUTHENTICATED-CANNOT(' || f || ')'; end if;
  end loop;

  -- ① the three new columns actually came out, by name and by type
  if (select count(*) from unnest(
         (select proargnames from pg_proc
           where proname = 'my_ledger_rows' and pronamespace = 'public'::regnamespace)) n
       where n in ('paid_payout_id', 'paid_at', 'settled')) is distinct from 3
    then v_bad := v_bad || ' LEDGER-ROWS-MISSING-PAYMENT-COLUMNS'; end if;

  -- ② 0158's finding #9 survived this rewrite. The distance decision is not this slice's to move,
  --    and a transcription that quietly reverted it would look exactly like a clean widening.
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_rows' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_rows)';
  else
    if (v_src ~ 'r\.actual_km')      is distinct from true  then v_bad := v_bad || ' LEDGER-NOT-ACTUAL'; end if;
    if (v_src ~ 'b\.km')             is distinct from false then v_bad := v_bad || ' LEDGER-STILL-PLANNED'; end if;
    -- ③ `settled` is the ABSENCE proof, not a reading of the left-joined run row
    if (v_src ~ 'not exists\s*\(\s*select 1 from runs rn') is distinct from true
      then v_bad := v_bad || ' SETTLED-NOT-AN-ABSENCE-PROOF'; end if;
  end if;

  -- ④ §B narrows and `my_ledger_total` does NOT — the two sentences stay two sentences
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_unpaid_total' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_unpaid_total)';
  elsif (v_src ~ 'paid_payout_id is null') is distinct from true
    then v_bad := v_bad || ' UNPAID-TOTAL-DOES-NOT-NARROW'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_total' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_total)';
  elsif (v_src ~ 'paid_payout_id') is distinct from false
    then v_bad := v_bad || ' LIFETIME-TOTAL-WAS-NARROWED(0192 must not change what 0027/0121 means)'; end if;

  if v_bad <> '' then raise exception '0192 VERIFY failed:%', v_bad; end if;
end $$;
