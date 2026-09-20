-- ═══ 0190: the payout journal's two open ends — a job lock on the sweep, and an END to the ═══
-- ═══        bank-detail retention 0115 always said would end when the runner was paid      ═══
--
-- ═══ §0 WHAT THIS FILE IS — Codex REJECT/2 on 0186, corrected FORWARD ════════════════════════
-- `docs/reviews/2026-09-21-migration-0186-codex-verdict.md`, both MED, both real on reading.
-- **0186 is NOT edited** (it has landed at `a842fe8`); neither is 0115. Both of this file's
-- targets are re-created here, each with its own ACL restated in this file.
--
--   #1 `0186:447-456` — `ops_payouts_stuck_sweep` checks notification history and then inserts.
--      That is read-then-write on `notifications` with nothing serialising the ticks, and there is
--      no uniqueness constraint that could catch it: two overlapping invocations both observe
--      「no ask for this (recipient, runner) in 20 hours」 and both insert. The dedupe I wrote is
--      correct and **sequential-only**, and suite 217 is a single connection, so 217 P6 is green
--      in both worlds. The shape this repo already uses for exactly this — `sweep_run_end_recovery`
--      (0181 §A, tightened in 0182/0183) — was not applied. §A applies it.
--
--   #2 `0186:370-377` — the writer marks rows paid and returns. Meanwhile `0115:566-572` keeps a
--      TOMBSTONED runner's `bank_accounts` row — account number and real holder name — whenever
--      **any** `ledger_items` row exists, and `0115:562-563` says in its own words that the
--      retention basis 「ends when they are paid, not when they leave」. Until 0186 there was no
--      way to express 「paid」, so that sentence was an intention rather than a predicate — 0115
--      says so itself at :541-548. 0186 created the marker and did not go back and use it. So:
--        · **delete-then-pay** — deletion retains (rows unpaid), the payment later clears them,
--          and nothing ever removes the retained row.
--        · **pay-then-delete** — the payment marks them paid, the runner is not yet a tombstone
--          so nothing is released; the later deletion still asks 「are there ANY ledger rows」,
--          finds them, and retains.
--      Both orders retain a real person's bank account and legal name **indefinitely**, for an
--      obligation that no longer exists. §B makes the retention predicate read the marker; §C
--      makes the writer release what is already retained.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - It does not change what is EARNED, what is OWED, or what an operator types. §A adds a lock
--   and no arm; §C adds a release step after a payout that already succeeded.
-- - It does not widen or narrow the 「settled, unpaid」 predicate (0186 §0d). `paid_payout_id is
--   null` is used here as 0186 defined it, in one more place.
-- - It does not touch 0115's twelve state-gate tokens, its tombstone, its redaction, its N6
--   closure or any other delete in its ④ list. §B changes **one predicate** inside a body copied
--   from the catalog, and asserts the body it copied is the one it expects.
-- - **No client change.** `bank_kept` keeps its name, its type and its position in the flat
--   result; what changes is when it is true. Nothing in `app/` reads `payouts`.
-- - It does not re-open Sean's 2026-08-20 ruling **A-intact-when-owed**. That ruling says a
--   payout destination survives deletion *while money is owed* — §B is the other half of the same
--   sentence, which 0115 could not write. 150's P9 keeps both of its arms (its fixtures sit where
--   the old and new predicates AGREE); the arms that can tell them apart are new, in 221.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON ════════════════════════════════════════════════════════
-- Re-creates THREE: `ops_payouts_stuck_sweep` (0186 §D), `ops_record_manual_payout` (0186 §C) and
-- `delete_my_account_tx` (0115 §C, already surgically patched by **0138 §F**). Each restates its
-- own ACL below. Creates nothing new. Reads `profiles`, `bank_accounts`, `ledger_items`.
--
-- ═══ §0d DOCTRINE ═══════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every body · ACLs restated in THIS file · `is not true` /
-- `is distinct from`, never a bare `IF` on a nullable predicate · a transaction-scoped TRY lock
-- that is never queued · the catalog copy fails CLOSED on an unrecognised body · pins in
-- `221_payout_sweep_lock_and_retention_suite.sql` plus a two-process arm in `90_race_check.sh`,
-- because the property §A adds is **invisible to a single connection by construction**.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A ops_payouts_stuck_sweep — a transaction-scoped TRY job lock, before any candidate is read
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0181 §A's shape, byte-for-byte in intent: `pg_try_advisory_xact_lock`, taken BEFORE the
-- candidate query, returning 0 immediately when another tick holds it.
--
--   · **TRY, never `pg_advisory_xact_lock`.** A queueing lock would make the second tick WAIT and
--     then run — which for a twice-daily janitor means the duplicate arrives late rather than not
--     at all, and under a stuck predecessor it means an unbounded pile of waiting cron backends.
--     A skipped tick costs nothing here: the next one is twelve hours away and the condition it
--     reports (a payout unpaid for over a week) does not evaporate in twelve hours.
--   · **xact-scoped, so there is no unlock to forget.** Every exit path — the early return, a
--     raise from any arm, the cron backend dying — releases it at commit or rollback. A
--     `pg_advisory_unlock` anywhere in this body would be an EARLY release that re-opens exactly
--     the window the lock closes, which is why 221 S1 asserts its ABSENCE as well as the lock's
--     presence (0181's own pin does the same).
--   · **Before the `for r in`**, not inside the loop. The race is read-then-write across the
--     whole scan: two ticks reading the same candidate set is harmless, two ticks each deciding
--     「nobody has been told」 for the same (recipient, runner) is the duplicate.
--
-- ⚠ THE KEY IS THE FUNCTION'S OWN NAME, and it must stay distinct from the handoff sweep's. Both
--   are `hashtextextended(<name>, 0)`; sharing a string would make two unrelated janitors block
--   each other for no reason, and the day someone notices it would look like a deadlock rather
--   than a typo.
--
-- ⚠ WHY NO UNIQUE INDEX INSTEAD. `notifications` has no natural key here — the same (profile_id,
--   kind, title, ref_id) tuple is CORRECT to insert again tomorrow, which is the whole point of a
--   20-hour window. A partial unique index would have to encode the window, and a window is not
--   an index predicate. The lock is the right instrument; the dedupe stays where it is.
--
-- Body below is 0186 §D's, unchanged except the six lines marked [0190 §A].
create or replace function ops_payouts_stuck_sweep() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  STUCK_AFTER   constant interval := interval '7 days';
  DEDUPE_WINDOW constant interval := interval '20 hours';
  c_ops_class   constant text := 'payout_due';
  c_title       constant text := '지급 대기 — 확인 필요';
  c_body        constant text := '일주일 넘게 지급되지 않은 러너 정산이 있어요. 지급 장부를 확인해 주세요.';
  r       record;
  n       int := 0;
  v_ops   int;
begin
  -- [0190 §A] the job lock, before a single candidate is read. TRY, so a slow predecessor is
  -- SKIPPED and never queued; transaction-scoped, so every exit path releases it and there is no
  -- unlock to forget. `90_race_check.sh` RP measures the skip with two processes — a single
  -- connection cannot see this property at all, which is why 217 P6 was green without it.
  if not pg_try_advisory_xact_lock(hashtextextended('ops_payouts_stuck_sweep', 0)) then
    raise notice 'ops_payouts_stuck_sweep: another tick holds the job lock — skipped';
    return 0;
  end if;

  for r in
    select l.runner_id as runner, min(l.created_at) as oldest
      from ledger_items l
     where l.paid_payout_id is null
       and not exists (select 1 from runs rn
                        where rn.booking_id = l.booking_id and rn.ended_at is null)
     group by l.runner_id
    having sum(l.base + l.distance_pay + l.addon_pay + l.tip
                 + coalesce(l.remaining_guarantee, 0) - l.platform_fee) > 0
       and min(l.created_at) < now() - STUCK_AFTER
     order by min(l.created_at), l.runner_id
  loop
    begin
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_title, c_body, r.runner
        from ops_recipients_for(c_ops_class) as rc(profile_id)
       where not exists (
             select 1 from notifications n2
              where n2.profile_id = rc.profile_id
                and n2.kind    = 'system'
                and n2.title   = c_title
                and n2.ref_id  = r.runner
                and n2.created_at > now() - DEDUPE_WINDOW);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then n := n + 1; end if;
      raise notice 'ops_payouts_stuck_sweep: runner % unpaid since %, past %: % ops recipient(s) told for %',
        r.runner, r.oldest, STUCK_AFTER, v_ops, c_ops_class;
    exception when others then
      raise notice 'ops_payouts_stuck_sweep: runner % — %', r.runner, sqlerrm;
    end;
  end loop;
  return n;
end $$;
-- 0186 §F's ACL restated (this repo never relies on grant preservation — 0116:636).
revoke execute on function ops_payouts_stuck_sweep() from public, anon, authenticated;
grant  execute on function ops_payouts_stuck_sweep() to service_role;

comment on function ops_payouts_stuck_sweep is
  '0186 §D + [0190 §A]: 하루 두 번 도는 「막힌 지급」 보고. 미지급(paid_payout_id IS NULL) 정산 중
가장 오래된 행이 7일을 넘고 순액이 0보다 큰 러너마다 ops_recipients_for(''payout_due'') 수신자에게
1회 알린다(20시간 룩백 = 러너당 하루 한 번; 본문에 id도 금액도 없다 — 0084 §E).
[0190 §A, codex REJECT #1] 후보를 읽기 전에 pg_try_advisory_xact_lock(hashtextextended(
''ops_payouts_stuck_sweep'', 0))을 잡는다. 중복 방지가 read-then-write라서 겹친 두 틱이 각각
「20시간 안에 알림 없음」을 보고 각각 넣을 수 있었다 — notifications에는 이를 막을 유니크 키가
없고(같은 튜플을 내일 다시 넣는 것이 정상이다), 단일 커넥션인 217 P6은 두 세계에서 똑같이 초록이다.
TRY라서 밀리지 않고 건너뛴다(다음 틱은 12시간 뒤고, 일주일 미지급은 12시간에 사라지지 않는다);
xact 스코프라서 풀 것을 잊을 수 없다. 221 0190-L1이 락의 존재를, 90_race_check.sh RP가 두 프로세스로
건너뜀 자체를 핀으로 잡는다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B delete_my_account_tx — the retention predicate finally reads the paid marker
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0138 §F's SURGICAL CATALOG-COPY shape, and the choice is deliberate rather than stylistic.
-- `delete_my_account_tx` is ~440 lines of 0115 that **0138 §F already rewrote in place** (it
-- inserts `perform enqueue_billing_key_revocation(...)` before the `billing_keys` delete, by
-- patching `prosrc` read back from the catalog). So there are two candidate sources of truth and
-- they DISAGREE: the file says one thing, the deployed function says another. Transcribing 0115's
-- text into this file would silently DELETE 0138's insertion — a card that the PG keeps honouring
-- after the account is gone — and nothing would fail. Copying the live body is the same law as
-- reading an artifact back from origin instead of trusting a tool's report.
--
--   · **Anchored and fail-closed, twice.** The block aborts the apply if the retention read is
--     missing, and if it is not UNIQUE. A blind `replace()` on a body that had moved would no-op,
--     the migration would apply green, and the retention would still be lifetime-scoped — the
--     exact failure 0138 §F wrote its own guard against.
--   · **Exactly one predicate changes.** `where runner_id = p_uid` → `where runner_id = p_uid and
--     paid_payout_id is null`. The `v_bank_kept := v_n > 0` line, the two branches, the
--     `deleted.bank_accounts` count and the flat result's `bank_kept` are all untouched.
--   · **0138's line is asserted to have SURVIVED**, here and in 221 S1. A future session that
--     "cleans this up" by pasting 0115's body would pass every other check.
--
-- ⚠ WHY THIS IS NOT A WIDENING OF THE DELETION GATE. `bank_kept` is a CONDITIONAL DELETE, never a
--   refusal: nobody is blocked from leaving in either world. What changes is the population whose
--   payment instrument survives the tombstone — from 「everyone who ever earned」 to 「everyone who
--   is still owed」, which is the sentence 0115:562-563 already wrote and could not express.
-- ⚠ AND IT IS STILL NOT A LIFETIME GATE. 0115's §B.1 objection — a gate on lifetime earnings can
--   never clear, so a runner could never delete — does not apply to a conditional delete and did
--   not apply before; this narrows the retention, so it strictly reduces what survives.
do $$
declare v_src text; v_new text; v_n int;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then
    raise exception '0190 §B: delete_my_account_tx not found — refusing to guess';
  end if;

  -- 0138 §F's own insertion must be in the body we are about to copy. If it is not, something
  -- re-created this function from 0115's file and the enqueue is already gone; stop loudly rather
  -- than carry the loss forward under our name.
  if position('perform enqueue_billing_key_revocation(p_uid, ''account_deleted'');' in v_src) = 0 then
    raise exception '0190 §B: 0138 §F''s revocation enqueue is not in the live body — do not copy this, find out what removed it';
  end if;

  -- the retention read, anchored on its two lines together so the count below means what it says
  select count(*) into v_n from regexp_matches(
    v_src,
    'select count\(\*\) into v_n from ledger_items where runner_id = p_uid;', 'g');
  if v_n is distinct from 1 then
    raise exception '0190 §B: the bank retention read is not unique in delete_my_account_tx (found %) — patch by hand', v_n;
  end if;

  v_new := replace(
    v_src,
    '  select count(*) into v_n from ledger_items where runner_id = p_uid;' || chr(10) ||
    '  v_bank_kept := v_n > 0;',
    '  -- [0190 §B, codex REJECT #2] THE RETENTION BASIS IS AN OUTSTANDING OBLIGATION, NOT A' || chr(10) ||
    '  -- LIFETIME OF EARNINGS — which is what the note above already says (「it ends when they are' || chr(10) ||
    '  -- paid, not when they leave」) and what this line could not express until 0186 §A gave' || chr(10) ||
    '  -- ledger_items a paid marker. 0115:541-548 recorded the gap in its own words: 「unpaid' || chr(10) ||
    '  -- balance is NOT COMPUTABLE on this schema; only LIFETIME EARNINGS are.」 It is computable' || chr(10) ||
    '  -- now, so the row survives the tombstone only while money is genuinely still owed, and' || chr(10) ||
    '  -- ops_record_manual_payout (0190 §C) removes it when the last unpaid row clears.' || chr(10) ||
    '  select count(*) into v_n from ledger_items where runner_id = p_uid and paid_payout_id is null;' || chr(10) ||
    '  v_bank_kept := v_n > 0;'
  );
  if v_new = v_src then raise exception '0190 §B: patch did not apply'; end if;

  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);
end $$;

-- 0115:645-648 / 0138 §F's ACL restated — a `create or replace` on an absent-function path is a
-- plain CREATE, and a SECURITY DEFINER born PUBLIC-executable is the worst shape this repo makes.
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant  execute on function delete_my_account_tx(uuid) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C ops_record_manual_payout — a tombstoned runner's retained bank details are RELEASED
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B fixes the order 「pay, then delete」. It cannot fix 「delete, then pay」: at deletion time the
-- money really was owed, so the row is correctly retained — and the moment that stops being true
-- is a moment nothing was watching. This is the INACTION law from §Migrations: a grant (here, a
-- retention) justified as 「it ends when X happens」 needs something that fires WHEN X HAPPENS.
-- X is the last unpaid row clearing, and this function is the only thing that can make that true.
--
--   · **Only a TOMBSTONED runner.** A live runner's `bank_accounts` row is their payment
--     destination and deleting it would break the next payout — 221 R4 is the control that says
--     so. The release is 0115's own ④ delete, run late: exactly `delete from bank_accounts where
--     runner_id = …`, nothing anonymised, nothing else touched.
--   · **Only when NOTHING unpaid is left.** A partial payment retains, because the obligation is
--     partly outstanding and a destination with money still owed to it is exactly what Sean's
--     ruling protects (221 R3).
--   · **The profiles row is LOCKED before `deleted_at` is read, and that lock is the whole
--     serialisation** Codex asked for. Without it the two transactions interleave into the worst
--     outcome: the payout reads `deleted_at is null` (not a tombstone yet, so no release) while
--     the deletion, running concurrently, reads the ledger rows as still unpaid (the payout has
--     not committed) and retains — and **neither side is wrong and the row is kept forever**.
--     `delete_my_account_tx` already UPDATEs `profiles` to set `deleted_at` (0115:418-424) BEFORE
--     it reads the ledger for the retention decision (0115:566), so that update takes the row
--     lock for us: whichever transaction gets the profile row first, the other sees its committed
--     result and does the right thing. No new lock is added to 0115's function, and no deadlock
--     cycle is created — the deletion never takes a row lock on `ledger_items`, so the two lock
--     orders cannot cross.
--
-- ⚠ The release is reported in the NOTICE and nowhere else. It deliberately does NOT change this
--   function's return (a uuid), because the ops caller's contract is 「here is the payout id」 and
--   widening what a return can mean is how a correct caller breaks with no edit to the caller.
--
-- Body below is 0186 §C's, unchanged except the two blocks marked [0190 §C].
create or replace function ops_record_manual_payout(
  p_runner uuid, p_ledger_item_ids uuid[], p_amount_won int, p_memo text
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  v_uid    uuid := auth.uid();
  v_ids    uuid[];
  v_named  int;
  v_found  int;
  v_gross  bigint;
  v_fee    bigint;
  v_net    bigint;
  v_from   date;
  v_to     date;
  v_payout uuid;
  v_tomb   boolean;
  v_rel    int := 0;
  r        record;
begin
  -- ① PARTY GATE — ops membership, ahead of every state gate and ahead of the lock.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  -- ② arguments. Distinct + null-stripped: naming the same row twice is an operator typo, not a
  --    double payment, and it must not inflate the expected count in ③.
  if p_runner is null then raise exception 'no_runner'; end if;
  select array_agg(distinct x) into v_ids
    from unnest(coalesce(p_ledger_item_ids, '{}'::uuid[])) x where x is not null;
  v_named := coalesce(array_length(v_ids, 1), 0);
  if v_named = 0 then raise exception 'no_items'; end if;
  -- A zero or negative transfer is not a payout. Without this, an empty-sum batch would
  -- 「match」 at 0 and write a payout row recording nothing.
  if p_amount_won is null or p_amount_won <= 0 then raise exception 'bad_amount'; end if;

  -- [0190 §C] LOCK THE RUNNER'S PROFILE before anything reads its tombstone state. This is the
  -- serialisation between this function and `delete_my_account_tx`, which sets `deleted_at` on
  -- this same row (0115:418-424) before it decides the bank retention (0115:566). Taken here,
  -- above the ledger lock, so the two functions' lock orders cannot cross.
  perform 1 from profiles pr where pr.id = p_runner for update;

  -- ③ THE LOCK. A named id that does not exist is not this runner's item, so the count is the
  --    first half of `not_runner_item` — and it is checked here, on what the lock actually held.
  perform 1 from ledger_items l where l.id = any(v_ids) order by l.id for update;
  get diagnostics v_found = row_count;
  if v_found is distinct from v_named then raise exception 'not_runner_item'; end if;

  -- ④ state gates on the LOCKED rows.
  for r in select l.* from ledger_items l where l.id = any(v_ids) order by l.id loop
    if r.runner_id is distinct from p_runner then raise exception 'not_runner_item'; end if;
    if r.paid_payout_id is not null         then raise exception 'already_paid';    end if;
    -- 0186 §0d ⓒ. Written as 「the proof of absence must be TRUE」 rather than 「the presence must
    -- be false」, so a NULL from any cause refuses instead of passing.
    if (select not exists (select 1 from runs rn
                            where rn.booking_id = r.booking_id and rn.ended_at is null))
       is not true
    then raise exception 'not_settled'; end if;
  end loop;

  -- ⑤ the arithmetic. `gross` = earnings before commission; `net` = the runner's own money, the
  --    same expression 0121 §A/§B/§C show the runner. KST dates for the 정산 기간 (0186 §0e).
  select coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0)), 0),
         coalesce(sum(l.platform_fee), 0),
         (min(l.created_at) at time zone 'Asia/Seoul')::date,
         (max(l.created_at) at time zone 'Asia/Seoul')::date
    into v_gross, v_fee, v_from, v_to
    from ledger_items l where l.id = any(v_ids);
  v_net := v_gross - v_fee;
  if v_net is distinct from p_amount_won::bigint then raise exception 'amount_mismatch'; end if;

  -- ⑥ the row. `tax_withheld = 0` is a statement of fact about this transfer, not a placeholder
  --    (0186 §0e) — nothing was withheld, because nothing is yet withholdable.
  insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net,
                       status, instant, paid_at, method, memo, recorded_by)
  values (p_runner, v_from, v_to, v_gross::int, 0, v_net::int,
          'paid', false, now(), 'manual', nullif(btrim(coalesce(p_memo, '')), ''), v_uid)
  returning id into v_payout;

  update ledger_items set paid_payout_id = v_payout
   where id = any(v_ids) and paid_payout_id is null;
  get diagnostics v_found = row_count;
  -- Cannot happen under the lock — and that is precisely why it is asserted rather than assumed.
  -- A payout row whose ledger rows are not all marked is a double-payment waiting to be made.
  if v_found is distinct from v_named then raise exception 'mark_lost'; end if;

  -- [0190 §C, codex REJECT #2] THE RETENTION ENDS HERE, for the order §B cannot reach. A runner
  -- who deleted their account while money was owed had their `bank_accounts` row KEPT INTACT by
  -- 0115 ④ — account number and real holder name — on a basis that 0115:562-563 says ends when
  -- they are paid. This is the moment it ends, and nothing else was ever going to notice it:
  -- the deletion cannot run again (0115:227-234 short-circuits a tombstoned retry and never
  -- reaches ④), so without this block the row survives forever.
  --   · tombstoned only — a LIVE runner's destination must not be deleted by paying them (221 R4)
  --   · nothing unpaid left — a partial payment keeps the obligation, so it keeps the row (221 R3)
  --   · `is true` on both, so a NULL from any cause keeps the row rather than deleting it: the
  --     failure direction here is 「retain something we could have released」, never 「release
  --     something still owed」.
  select (pr.deleted_at is not null) into v_tomb from profiles pr where pr.id = p_runner;
  if v_tomb is true
     and (select not exists (select 1 from ledger_items l2
                              where l2.runner_id = p_runner and l2.paid_payout_id is null)) is true
  then
    delete from bank_accounts where runner_id = p_runner;
    get diagnostics v_rel = row_count;
    raise notice 'ops_record_manual_payout: tombstoned runner % fully paid — % retained bank row(s) released (0115 ④, run late)', p_runner, v_rel;
  end if;

  return v_payout;
end $$;
-- 0186 §F's ACL restated.
revoke execute on function ops_record_manual_payout(uuid, uuid[], int, text) from public, anon;
grant  execute on function ops_record_manual_payout(uuid, uuid[], int, text) to authenticated;

comment on function ops_record_manual_payout is
  '0186 §C + [0190 §C]: 사람이 은행에서 옮긴 돈을 장부에 적는다. ops 전용, 한 트랜잭션. 순서는
파티 게이트 → 인자 → **러너 프로필 행 잠금** → named 원장 행 잠금 → 상태 게이트 → 금액 동일성 →
payouts 한 행 + 그 행들만 표시 → **탈퇴한 러너의 보관 계좌 해제**.
[0190 §C, codex REJECT #2] 0115 ④는 미지급 정산이 있는 러너의 bank_accounts 행을 계좌번호와
실명까지 그대로 보관하고(Sean 2026-08-20 A-intact-when-owed), 0115:562-563은 그 보관이
「지급되면 끝난다」고 적어 뒀다. 그 끝을 만드는 것이 이 블록이다 — 탈퇴한 러너의 마지막 미지급
행이 사라지는 순간 0115가 삭제했을 바로 그 행을 삭제한다. 탈퇴 재시도는 0115:227-234에서 조기
반환하므로 ④에 다시 도달하지 않는다: 이 블록이 없으면 그 행은 영원히 남는다. 살아 있는 러너는
건드리지 않고(지급 대상의 입금처다), 부분 지급은 보관을 유지한다. 프로필 행 잠금이 삭제
트랜잭션과의 직렬화 전부다 — 잠그지 않으면 두 트랜잭션이 「아직 탈퇴 아님」과 「아직 미지급」을
각각 읽고 둘 다 옳은 채로 행이 영구 보관된다. 221 0190-R1~R4·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 221
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Two independent spellings again (0177's law): the literals here are written separately from
-- §A-§C's, so a typo in either place aborts the apply rather than satisfying itself.
do $$
declare
  v_bad text := '';
  v_oid oid;
  v_src text;
begin
  -- ── §A the sweep: the lock is present, before the first arm, and nothing releases it early ──
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_payouts_stuck_sweep';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_payouts_stuck_sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' sweep:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' sweep:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public',        v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',          v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' sweep:CLIENT-EXECUTABLE'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' sweep:NO-SERVICE-ROLE'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' sweep:NO-SOURCE';
    else
      if (position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src) > 0
          and position('for r in' in v_src) > 0
          and position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src)
              < position('for r in' in v_src)) is distinct from true
        then v_bad := v_bad || ' sweep:JOB-LOCK-MISSING-OR-AFTER-THE-FIRST-ARM'; end if;
      if (v_src ~ 'pg_advisory_unlock') is distinct from false
        then v_bad := v_bad || ' sweep:SESSION-UNLOCK-PRESENT(an early release re-opens the race)'; end if;
    end if;
  end if;

  -- ── §B the deletion: the retention reads the marker, and 0138's enqueue survived the copy ──
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'delete_my_account_tx';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(delete_my_account_tx)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' delete:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' delete:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public',        v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',          v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' delete:CLIENT-EXECUTABLE(the uid is a PARAMETER — this would let a client name a victim)'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' delete:NO-SERVICE-ROLE'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' delete:NO-SOURCE';
    else
      if (v_src ~ 'from ledger_items where runner_id = p_uid and paid_payout_id is null;')
         is distinct from true
        then v_bad := v_bad || ' delete:RETENTION-STILL-LIFETIME-SCOPED'; end if;
      if (v_src ~ 'enqueue_billing_key_revocation\(p_uid, ''account_deleted''\)')
         is distinct from true
        then v_bad := v_bad || ' delete:0138-ENQUEUE-LOST-IN-THE-COPY'; end if;
      if (v_src ~ 'v_bank_kept := v_n > 0;') is distinct from true
        then v_bad := v_bad || ' delete:BANK-KEPT-ASSIGNMENT-GONE'; end if;
    end if;
  end if;

  -- ── §C the writer: the release, and the profile lock that makes it correct under concurrency ──
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_record_manual_payout';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_record_manual_payout)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' writer:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' writer:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',   v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' writer:PUBLIC-OR-ANON-EXECUTABLE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' writer:NO-AUTHENTICATED'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' writer:NO-SOURCE';
    else
      if (v_src ~ 'delete from bank_accounts where runner_id = p_runner;') is distinct from true
        then v_bad := v_bad || ' writer:NO-RELEASE'; end if;
      -- `position` takes a LITERAL, never a regex — the profile lock is matched by its own text
      -- so the ordering arm below compares two positions that both mean what they say.
      if (position('from profiles pr where pr.id = p_runner for update;' in v_src) > 0)
         is distinct from true
        then v_bad := v_bad || ' writer:NO-PROFILE-LOCK'; end if;
      if (position('from profiles pr where pr.id = p_runner for update;' in v_src) > 0
          and position('pr.deleted_at is not null' in v_src) > 0
          and position('from profiles pr where pr.id = p_runner for update;' in v_src)
              < position('pr.deleted_at is not null' in v_src))
         is distinct from true
        then v_bad := v_bad || ' writer:TOMBSTONE-READ-BEFORE-THE-LOCK'; end if;
      if (v_src ~ 'l2\.paid_payout_id is null') is distinct from true
        then v_bad := v_bad || ' writer:RELEASE-NOT-GATED-ON-THE-LAST-UNPAID-ROW'; end if;
    end if;
  end if;

  if v_bad <> '' then raise exception '0190 VERIFY FAILED:%', v_bad; end if;
end $$;
