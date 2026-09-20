-- ═══ 0186: the ops MANUAL PAYOUT JOURNAL — `payouts` finally gets a writer ═══════════════════
--
-- ═══ §0 WHAT THIS FILE IS, AND WHOSE PRESCRIPTION IT EXECUTES ════════════════════════════════
-- `docs/decisions/awaiting-sean.md` §0-undetricies, Codex's third ranked risk, verbatim in its
-- operative half: *「do NOT automate bank movement — … add an ops-only manual payout journal that
-- links `ledger_items` to a `payouts` row with `paid_at`, and run a twice-daily stuck-state
-- report. "An unrecorded bank transfer is not acceptable; a spreadsheet keyed by ledger-item ids
-- is, for the first five runs."」*
--
-- Two shipped files already say, in their own words, that this piece is missing:
--   · `0115:282` — the account-deletion gate `unpaid_payout` asks `payouts.paid_at is null` and is
--     「**KNOWINGLY INERT TODAY** … nothing in the repo writes `payouts`」. It was kept because it
--     becomes correct 「the instant a payout writer lands」. This is that instant. ⚠ It stays inert
--     **by construction even now**, and that is deliberate — see §0e.
--   · `0097` (`ops_unsettled_runs`) detects a runner who was never paid and says so in its own
--     §2: 「**Paying a stranded runner is money's slice.** This file writes nothing.」 0186 is the
--     other half: 0097 answers 「who got nothing」, this answers 「what do we owe, and did we move
--     it」.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ══
-- - **NO BANK MOVEMENT, no PG, no `pg_net`, no automation of any kind.** A human moves the money
--   at their bank and then TYPES what they moved into `ops_record_manual_payout`. Every number in
--   a `payouts` row written here is a number a person entered or the database summed — nothing is
--   estimated, projected or rounded.
-- - **It does not change how anything is EARNED.** `compute_runner_payout` (0101/0102),
--   `settle_run_tx`, `record_enroute_cancel_comp`, `club_incident_settle` and the club fee mints
--   are untouched. The `ledger_items` row is still the whole truth about an earning; this file
--   only records whether that earning has been PAID OUT.
-- - **It does not touch `club_release_payouts`** (0045/0072, the club payout machine). That path
--   has its own release semantics and its own cron; a club pair's money is not in this journal's
--   population except through whatever `ledger_items` rows the club paths already write, which is
--   exactly the runner's own earning.
-- - **No client change in this slice.** Nothing in `app/` reads `payouts` (measured: 0 references
--   in `app/src` and `app/app`), and the ops surface is a psql/PostgREST call by Sean. The three
--   functions are additive; no existing RPC contract moves.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON (REGISTRY.md's silent-collision rule) ═══════════════════
-- Re-creates NOTHING. `ops_payouts_due`, `ops_record_manual_payout` and `ops_payouts_stuck_sweep`
-- are all new, all first defined here, all setting their own ACL in this file (§F). It READS
-- `ledger_items`, `runs`, `payouts`, `notifications` and calls `ops_recipients_for` (0084 §E) —
-- none of them redefined. It ALTERS two shipped tables (§A) and re-seals the columns it adds.
--
-- ═══ §0d THE PREDICATE — what 「earned and settled, not yet paid」 MEANS on THIS schema ════════
-- This is the one decision in the file that a reader must be able to check, so it is written as a
-- ladder rather than as a verdict.
--
--   **UNPAID** = `ledger_items.paid_payout_id is null`. That column is born in §A and this file is
--   its only writer. Before today there was no paid marker of any kind — `0115:541` measured it:
--   「`ledger_items` … carries **no paid/settled marker of any kind** … So "unpaid balance" is NOT
--   COMPUTABLE on this schema; only LIFETIME EARNINGS are.」 It is computable as of this file.
--
--   **EARNED/SETTLED** = the row EXISTS and its booking has **no run still in progress**:
--       `not exists (select 1 from runs r where r.booking_id = l.booking_id and r.ended_at is null)`
--   Read the two halves separately, because each rejects an alternative that looks right:
--
--   ⓐ **Existence is the earning.** `ledger_items` has no state column (0001:264-275: eight money
--      columns and `created_at`, nothing else) and no UPDATE path anywhere in the repo — every
--      writer INSERTs a finished row inside the transaction that decided the money
--      (`settle_run_tx`/`_settle_sealed_run` 0020/0028/0083/0169, `record_enroute_cancel_comp`
--      0085, `club_incident_settle` 0072, the club cancel-fee share 0118, the patch bonus 0025).
--      So there is no 「pending ledger row」 state to exclude, and inventing one would be a fiction.
--
--   ⓑ **`runs.settled_at` is the WRONG anchor and the check that proves it is one query.**
--      The obvious predicate — 「the run settled」 — would permanently refuse exactly the population
--      this journal exists to serve. Measured: `club_incident_settle` (0072:150-157) writes the
--      runner's `ledger_items` row and **`settled_at` appears NOWHERE in 0072** (`grep -c` on the
--      file: 0). Those are 0083 §0h's stranded runners — the ones 0097 was built to surface. A
--      journal that refused them would be a payout machine that cannot pay the only people who
--      currently need paying. The same applies to every no-run earning: an en-route cancellation
--      (0085) and a club cancel fee (0118) have no `runs` row at all, and `settled_at is not null`
--      is false for a row that does not exist.
--
--   ⓒ **So the risk the predicate actually guards is 「the amount can still MOVE」**, and on this
--      schema that is exactly one state: a run of the same booking that has not ended, because the
--      settle which ends it will INSERT another `ledger_items` row for the same booking. Paying
--      before that lands means paying a partial against a total the operator believed was final.
--      `runs.ended_at is null` names that state and nothing else.
--      ⚠ **Honest reachability, stated rather than implied:** no SHIPPED writer produces a ledger
--      row beside a live run — every one of them either ends the run in the same statement group
--      (0025:50-62, 0169:215-231) or has no run at all. So today `not_settled` is a BELT against a
--      future writer and against a hand-written ops row, not a refusal anyone will meet. It is a
--      pin and not prose because the harness CAN construct the state (217 `0186-P4` does, and
--      `0186-P2` proves the read excludes it) — the test the house law asks for is 「can you
--      describe the mutation that reddens it」, and here it is: delete the `not exists` conjunct.
--
--   ⚠ NOT part of the predicate, deliberately: whether the OWNER paid. A runner's earning and the
--     owner's charge are separate ledgers on purpose (`0080 §G` invariant #1 has its own detection
--     arm, `settled_without_payment`, and `0173` its own reconciliation). Withholding a runner's
--     money because our collection failed would be a policy decision with a person on the other
--     end of it, and it is Sean's, not a predicate's. The stuck sweep (§D) makes the gap visible;
--     it does not decide it.
--
-- ═══ §0e THE THREE COLUMNS `payouts` ALREADY HAD, AND THE ONE NUMBER THIS FILE REFUSES TO GUESS ═
-- `payouts` (0001:285-296) predates every decision this product has made about money. Its
-- `gross / tax_withheld / net` triple carries a comment saying `tax_withheld` is 「3.3%」. This
-- file writes:
--   · `gross`        := the locked rows' EARNINGS before the platform's commission
--                       (base + distance_pay + addon_pay + tip + remaining_guarantee).
--   · `net`          := `gross − sum(platform_fee)` — the runner's own money, the SAME expression
--                       `my_ledger_rows` / `my_week_stats` / `my_booking_nets` (0121 §A/§B/§C)
--                       already show the runner. One definition of 「net」, three surfaces and now
--                       a fourth; a second definition here would be a number that disagrees with
--                       the runner's own screen.
--   · `tax_withheld` := **0, and that is a statement, not a placeholder.** 3.3% 원천징수 requires
--                       a 사업자등록 that does not exist yet and a withholding decision nobody has
--                       ruled on. Writing a computed 3.3% here would put a number in a money
--                       ledger that no one withheld and no tax office received — a fabricated
--                       figure in the one place the house honesty law is strictest about. `0`
--                       says what is TRUE of a concierge bank transfer in the pilot: nothing was
--                       withheld. When withholding becomes real it arrives as an argument to this
--                       function in its own slice, with its own pin, and NOT as a guess here.
--                       ⚠ Consequence, said out loud so nobody 「fixes」 it: `net ≠ gross −
--                       tax_withheld` on every row this file writes. The invariant that holds is
--                       `net = gross − platform_fee`, and it is pinned (217 `0186-P3`).
--   · `status`       := `'paid'` (the money moved before the call), `instant` := false (this is
--                       not the 빠른 정산 product), `paid_at` := `now()`.
--   · `period_start/_end` := the KST dates of the oldest and newest ledger row in the batch. KST
--                       because a 정산 기간 printed for a Korean operator is a Korean calendar
--                       fact; `at time zone 'Asia/Seoul'` is 0121 §B's precedent.
--
-- ⚠ **`0115`'s `unpaid_payout` GATE STAYS INERT, BY CONSTRUCTION, AND THAT IS THE RIGHT ANSWER.**
--   It refuses deletion while `exists (… where runner_id = p_uid and paid_at is null)`. Every row
--   this file writes has `paid_at = now()`, because the journal records money that has ALREADY
--   MOVED — a row is never created in an owed-but-unpaid state. So the gate still cannot fire, and
--   a future session reading `0115:282` must not conclude that 0186 armed it. What 0186 arms
--   instead is `0115 §④`'s conditional `bank_accounts` delete, which keys on `ledger_items` and is
--   unaffected by this file (the rows stay, they only gain a marker).
--
-- ═══ §0f DOCTRINE (0059 money-path list) ═════════════════════════════════════════════════════
-- self-contained · `set search_path = public, pg_temp` IN THE BODY (98 H1 — ALTER-applied config
-- is reset by `create or replace`) · every ACL written in THIS file, for functions first defined
-- in THIS file · party gate (ops membership) BEFORE any state gate and before the row lock is
-- taken · `is not true` / `is distinct from`, never a bare `IF` on a predicate that can be NULL ·
-- the cron registered WITHOUT a swallowing `exception when others` and READ BACK from `cron.job`
-- (0177's §A-§D shape, whose own header records why: 「`cron.schedule` returning is a claim; a row
-- in `cron.job` is the fact」) · mutation-verified pins in `217_ops_manual_payout_suite.sql`.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A the two tables gain the four columns the journal needs — and the new ones are SEALED
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `paid_payout_id` is the LINK the prescription asks for, in the direction that makes the
-- question cheap: 「is this earning paid?」 is a column read, not a join through a set. A payout
-- row therefore owns N ledger rows and a ledger row belongs to at most one payout — which is the
-- real-world shape (one bank transfer covers a batch).
-- ⚠ NULLABLE and NO DEFAULT on purpose: every row that exists today is unpaid, and `null` is the
--   honest spelling of that. A default would backfill a claim nobody made.
alter table ledger_items add column if not exists paid_payout_id uuid references payouts (id);
create index if not exists ledger_items_unpaid_idx on ledger_items (runner_id, created_at)
  where paid_payout_id is null;

comment on column ledger_items.paid_payout_id is
  '0186 §A: 이 원장 행의 금액이 실제로 지급된 payouts 행. NULL = 아직 미지급(오늘 존재하는 모든
행이 그렇다 — 기본값을 주지 않은 이유). 쓰는 곳은 ops_record_manual_payout 하나뿐이고, 한 번
채워지면 그 행은 already_paid로 영구 거절된다(멱등성의 전부).';

-- `method` / `memo` / `recorded_by` are the three facts a manual transfer has and an automated one
-- would not: HOW it moved, WHAT the operator wrote down, and WHO typed it.
-- ⚠ `recorded_by` is **deliberately NOT a foreign key to `profiles`**, and the reason is 0115.
--   That file's whole design is that every edge into `profiles` is an explicit, reviewed, pinned
--   list (`150 N6-2` refuses a retention table hanging off `profiles` by CASCADE/SET NULL/SET
--   DEFAULT; `N7` sweeps for orphans). A new FK would have to choose between `on delete restrict`
--   — which makes an operator's own account deletion fail with a raw constraint error the
--   deletion RPC does not name, i.e. a refusal the user cannot read or resolve (0115 §B.1's exact
--   prohibition) — and `set null`, which ERASES a money-audit fact to let an account close. Both
--   are 0115's slice to rule on, not this one's. The uid is recorded as a FACT; it resolves while
--   the operator's profile lives and stands as an opaque audit id afterwards.
alter table payouts add column if not exists method      text;
alter table payouts add column if not exists memo        text;
alter table payouts add column if not exists recorded_by uuid;

comment on column payouts.method is
  '0186 §A: 돈이 어떻게 움직였나. 오늘은 ''manual'' 하나뿐 — 사람이 은행에서 이체하고 이 장부에
적는다. PG 자동 지급이 생기면 그때 값이 늘어난다(체크 제약을 걸지 않은 이유는 0084 §E의 event_class와
같다: 어휘를 늘리는 일이 마이그레이션이 되면 안 된다).';
comment on column payouts.memo is
  '0186 §A: 운영자가 적어 넣는 메모(은행 거래 참조번호 등). 서버는 해석하지 않는다. 빈 문자열은
NULL로 저장한다.';
comment on column payouts.recorded_by is
  '0186 §A: 이 행을 기록한 운영자의 uid. **일부러 FK가 아니다** — profiles로 가는 간선은 0115가
명시 목록으로 관리하고(150 N6-2/N7), restrict는 운영자 본인의 탈퇴를 이름 없는 제약 오류로 막고
set null은 돈 감사 사실을 지운다. 둘 다 0115의 결정이지 이 파일의 결정이 아니다.';

-- ── the seal. `payouts` has RLS with `payouts self read` (0002:126, `runner_id = auth.uid()`),
-- so a runner reads their OWN payout rows — which is correct and stays. What must not follow the
-- runner home is the ops half of the row: who the operator was, and what they wrote in a note
-- meant for ops. RLS decides ROWS; a column grant is the only thing that decides COLUMNS
-- (0088's law, and 0107's two-step is the shape).
-- ⚠ TWO-STEP, and the re-grant list is EXACTLY 0001:285-296's ten columns — today's reach,
--   preserved to the column. A `select *` by the runner narrows rather than breaking: PostgREST
--   asks for named columns. Nothing in `app/` reads this table at all (measured), so the blast
--   radius of the revoke is zero and the grant is belt for the day something does.
revoke select on payouts from public, anon, authenticated;
grant select (id, runner_id, period_start, period_end, gross, tax_withheld, net, status,
              instant, paid_at)
  on payouts to authenticated;

-- `ledger_items` needs no re-grant: 0121:224 revoked SELECT from public/anon/authenticated
-- outright and every legitimate client read is an RPC. Restated here as belt — a table-wide
-- revoke already covers a column added afterwards, and saying so where the column is born is
-- cheaper than a future session working it out.
revoke select on ledger_items from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B ops_payouts_due — the read. What do we owe, to whom, and for how long.
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Shape copied from `ops_unsettled_runs` (0097): flat whitelisted columns, an ops-only definer,
-- aggregated per runner.
-- ⚠ **IDS AND NUMBERS ONLY — no name, no phone, no address, no bank row.** An operator pays by
--   looking a runner up in the sealed `bank_accounts` table deliberately, as a second act; this
--   function must never become the surface that joins a payable amount to a person's bank
--   details, because then ONE grant mistake discloses the pair. `0121`'s runner-money strip made
--   exactly this trade on the client side and it is the same trade here.
-- ⚠ `having sum(net) > 0`: a runner whose unpaid rows net to zero or less is not 「due」, and
--   listing them would put rows an operator can do nothing with in front of the rows they can.
create or replace function ops_payouts_due()
returns table (
  runner_profile_id uuid,
  unpaid_net_won    bigint,
  unpaid_items      int,
  oldest_unpaid_at  timestamptz,
  unpaid_for        interval
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  v_uid uuid := auth.uid();
begin
  -- ① PARTY GATE FIRST — before any read of anyone's money, and before anything else at all.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select l.runner_id,
         sum(l.base + l.distance_pay + l.addon_pay + l.tip
               + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::bigint,
         count(*)::int,
         min(l.created_at),
         now() - min(l.created_at)
    from ledger_items l
   where l.paid_payout_id is null
     -- §0d ⓒ: the one state where the booking's total can still move.
     and not exists (select 1 from runs r
                      where r.booking_id = l.booking_id and r.ended_at is null)
   group by l.runner_id
  having sum(l.base + l.distance_pay + l.addon_pay + l.tip
               + coalesce(l.remaining_guarantee, 0) - l.platform_fee) > 0
   order by min(l.created_at), l.runner_id;
end $$;

comment on function ops_payouts_due is
  '0186 §B: 러너별 미지급 정산 합계 — ops 전용 읽기. 행 하나 = 러너 하나. unpaid_net_won은
0121 §A/§B/§C가 러너에게 보여주는 것과 **같은 식**(base+distance+addon+tip+guarantee−platform_fee)이고,
모수는 paid_payout_id IS NULL이면서 같은 예약에 끝나지 않은 run이 없는 행이다(§0d ⓒ — 정산이
아직 행을 더 쓸 수 있는 유일한 상태를 뺀다. runs.settled_at이 앵커가 아닌 이유는 0072가 인시던트
정산 원장을 쓰면서 settled_at을 찍지 않기 때문 — 그 앵커를 쓰면 0097이 찾아낸 바로 그 사람들이
영원히 지급 대상에서 빠진다). 순액이 0 이하인 러너는 나오지 않는다.
⚠ id와 숫자만. 이름·전화·주소·계좌는 절대 이 함수를 통해 나가지 않는다 — 지급액과 계좌를 잇는
표면이 되는 순간 그랜트 실수 하나가 그 쌍을 통째로 노출한다.
호출자는 ops_recipients의 payout_due 활성 수신자여야 한다(아니면 not_ops). 217 0186-P1/P2가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C ops_record_manual_payout — the writer. ONE transaction, and the operator's number wins
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The contract, in the order the body enforces it:
--   ① ops party gate (`not_signed_in` / `not_ops`) — before the lock, before any row is read.
--   ② argument sanity (`no_runner` / `no_items` / `bad_amount`).
--   ③ LOCK the named rows `for update`, ordered by id.
--   ④ state gates ON THE LOCKED ROWS: `not_runner_item` · `already_paid` · `not_settled`.
--   ⑤ `amount_mismatch` — the arithmetic gate, last, because it is the only one that needs all
--      the rows read.
--   ⑥ one `payouts` row, then mark exactly the named ledger rows.
--
-- ⚠ **THE AMOUNT IS AN EQUALITY, NEVER A TOLERANCE.** `p_amount_won` is what the operator moved
--   at the bank. If it is not EXACTLY the locked rows' net, the two facts disagree and the right
--   answer is to refuse and let a human look — not to round, not to accept the closer of the two,
--   and not to write the database's number under the human's authority. A journal whose row can
--   differ from the transfer it records is not a journal.
--
-- ⚠ **WHY THE LOCK IS NOT DECORATION.** Two operators paying the same runner from two terminals,
--   or one operator double-submitting, both read 「unpaid」 and both insert — the runner is paid
--   twice and the ledger says once. `for update` on the named rows makes the second caller wait
--   and then see `paid_payout_id` set, which is the `already_paid` refusal. The idempotency this
--   function claims IS the lock plus that column; neither alone is it.
--   ⚠ The lock is a PRECONDITION of the gate, not part of it — deleting the `for update` leaves
--   every single-session pin green (the reader is the writer) while destroying the property. It
--   is pinned in the source arm for exactly that reason (217 `0186-S1`).
--
-- ⚠ `order by l.id` on the lock: two operators naming overlapping batches in different orders
--   would deadlock without a deterministic lock order. Cheap, and invisible until it is not.
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

  -- ③ THE LOCK. A named id that does not exist is not this runner's item, so the count is the
  --    first half of `not_runner_item` — and it is checked here, on what the lock actually held.
  perform 1 from ledger_items l where l.id = any(v_ids) order by l.id for update;
  get diagnostics v_found = row_count;
  if v_found is distinct from v_named then raise exception 'not_runner_item'; end if;

  -- ④ state gates on the LOCKED rows.
  for r in select l.* from ledger_items l where l.id = any(v_ids) order by l.id loop
    if r.runner_id is distinct from p_runner then raise exception 'not_runner_item'; end if;
    if r.paid_payout_id is not null         then raise exception 'already_paid';    end if;
    -- §0d ⓒ. Written as 「the proof of absence must be TRUE」 rather than 「the presence must be
    -- false」, so a NULL from any cause refuses instead of passing. A bare `IF <exists>` would
    -- be the collapse this repo has lost five pins to.
    if (select not exists (select 1 from runs rn
                            where rn.booking_id = r.booking_id and rn.ended_at is null))
       is not true
    then raise exception 'not_settled'; end if;
  end loop;

  -- ⑤ the arithmetic. `gross` = earnings before commission; `net` = the runner's own money, the
  --    same expression 0121 §A/§B/§C show the runner. KST dates for the 정산 기간 (§0e).
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
  --    (§0e) — nothing was withheld, because nothing is yet withholdable.
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

  return v_payout;
end $$;

comment on function ops_record_manual_payout is
  '0186 §C: 사람이 은행에서 옮긴 돈을 장부에 적는다. ops 전용, 한 트랜잭션. 순서는
파티 게이트(not_signed_in/not_ops) → 인자(no_runner/no_items/bad_amount) → named 행 for update
잠금 → 잠긴 행 위의 상태 게이트(not_runner_item/already_paid/not_settled) → 금액 동일성
(amount_mismatch) → payouts 한 행 + 그 행들만 표시. **금액은 오차 허용이 아니라 동일성이다** —
운영자가 옮긴 액수와 잠긴 행들의 순액이 다르면 둘 중 하나가 틀린 것이고, 답은 반올림이 아니라
거절이다. 멱등성 = 잠금 + paid_payout_id: 같은 행으로 두 번째 호출하면 already_paid로 막히고
아무것도 쓰이지 않는다(예외가 트랜잭션을 되돌린다). tax_withheld는 0으로 적는다 — 원천징수는
아직 제도적으로 존재하지 않고, 아무도 떼지 않은 3.3%를 돈 장부에 적는 것이 이 집의 정직성 법이
가장 엄격하게 금지하는 일이다(§0e). 217 0186-P1·P3·P4·P5가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D ops_payouts_stuck_sweep — the twice-daily stuck-state report
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The other half of the prescription: 「run a twice-daily stuck-state report」.
--
-- **N = 7 DAYS, and the reason is the cadence it has to be legible against.** A concierge payout
-- cycle for the first five runs is weekly — the operator sits down, reads `ops_payouts_due()`,
-- moves money, records it. Anything younger than a week is 「not yet this week's run」, which is
-- normal and must not page. Anything older than a week means a cycle was MISSED, which is the
-- only thing worth waking someone for. A shorter N turns the signal into weather; a longer one
-- lets a runner go unpaid for a fortnight before anyone is told — and 0097's whole §0 is about
-- what happens when the alarm for 「a runner was not paid」 goes quiet.
--
-- **DEDUPE: a 20-HOUR LOOKBACK, not a calendar-day truncation.** The requirement is 「once per
-- runner per day」. With ticks 12 hours apart, a 20-hour window yields exactly one notification
-- per runner per day: the first tick tells, the second (12 h later) is suppressed, the next day's
-- first tick (24 h later) tells again. `date_trunc('day', now())` would be a UTC day boundary
-- sitting at 09:00 KST, i.e. **between** the two ticks — so it would notify twice on the calendar
-- day an operator actually lives in, which is the opposite of the requirement. The cadence
-- decides, not the calendar.
--
-- ⚠ The body carries NO id and NO amount — 0084 §E's standing rule, and its reason is not
--   abstract: 「a wrong recipient id pushes the body verbatim to a real user's lock screen」, and
--   0024's insert trigger pushes notification bodies. The runner id rides in `ref_id`, exactly as
--   0155/0166/0182 do.
-- ⚠ The per-runner `exception when others` is the 0116 B3 / 0182 shape: ONE poisoned row fails its
--   own row and the batch continues. It is NOT the swallow the cron registration in §E must not
--   have — that one hides 「the job was never installed」, this one stops one bad row from
--   silencing every good one.
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

comment on function ops_payouts_stuck_sweep is
  '0186 §D: 하루 두 번 도는 「막힌 지급」 보고. 미지급(paid_payout_id IS NULL) 정산 중 가장 오래된
행이 7일을 넘고 순액이 0보다 큰 러너마다 ops_recipients_for(''payout_due'') 수신자에게 1회 알린다.
7일인 이유: 파일럿의 지급 주기가 주 1회라서 그보다 어린 건 「아직 이번 주 차례가 아니다」이고,
그보다 늙은 건 「한 주기를 놓쳤다」 — 후자만 사람을 깨울 값어치가 있다. 중복 방지는 달력이 아니라
20시간 룩백이다: 틱이 12시간 간격이므로 러너당 하루 정확히 한 번이 되고, UTC 달력 자르기는 경계가
09:00 KST에 앉아 두 틱 사이를 가르므로 운영자가 사는 하루에 두 번 울린다. 본문에는 id도 금액도
없다(0084 §E — 잘못된 수신자에게 본문이 그대로 잠금화면에 간다). 러너 id는 ref_id로 탄다.
행 단위 예외 삼킴은 0116 B3/0182 형상 — 한 행이 배치를 침묵시키지 않게 하는 것이지 §E의 등록
삼킴과는 다른 것이다. 217 0186-P6가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E the cron — registered UNSWALLOWED, then read back from `cron.job`
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0177's §A-§D shape exactly, and its header carries the reason: 17 of this repo's 22 cron jobs
-- are registered inside `do $$ … exception when others then raise notice … end $$`, under which a
-- FAILED `cron.schedule` COMMITS AS A SUCCESSFUL MIGRATION. A scheduler that was never installed
-- and a scheduler that runs are indistinguishable afterwards — except by reading `cron.job`.
--
-- `'25 0,9 * * *'` is **09:25 and 18:25 KST** (pg_cron runs in the database's timezone, UTC).
-- The two ends of a Seoul working day: a stuck payout is seen when the operator starts and once
-- more before they close, which is the cadence 「twice daily」 is actually asking for. The :25
-- offset keeps it off the :00/:15 slots the four 0177 jobs already occupy.
-- ⚠ NO `create extension if not exists pg_cron` (0045:442 already installed it; the harness ships
--   a registry stub) and NO `cron.unschedule` before the schedule — `cron.schedule` UPSERTS on
--   (jobname, username) in pg_cron >= 1.4 and `cron.unschedule` raises P0001 on an absent job,
--   which would make a fresh environment abort. Both are 0177's measured reasoning, unchanged.
do $$
begin
  perform cron.schedule('ops-payouts-stuck', '25 0,9 * * *',
                        'select ops_payouts_stuck_sweep()');
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §F ACL — restated in THIS file, for functions first defined in THIS file
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `create or replace` preserves an ACL only where the function already exists; on a partial prior
-- apply or a rebuilt environment it is a plain CREATE and a SECURITY DEFINER is born
-- PUBLIC-executable (0116:636). Every grant this file relies on is therefore written here.
--
-- ⚠ THE TWO OPS FUNCTIONS ARE GRANTED TO `authenticated` ON PURPOSE. The operator is a signed-in
--   person calling through PostgREST; `auth.uid()` is how the gate knows who they are, and a
--   service_role call carries no uid and so fails CLOSED with `not_ops`. Holding EXECUTE is
--   therefore not holding access — `ops_recipients` membership is, and it is a table with RLS on
--   and ZERO policies that no client can read or write (0084 §E). A signed-in stranger calling
--   either function gets `not_ops` and learns nothing: not whether the runner exists, not whether
--   anything is owed. That is the whole seal, and 217 `0186-P1`/`0186-S1` watch it.
revoke execute on function ops_payouts_due() from public, anon;
grant  execute on function ops_payouts_due() to authenticated;

revoke execute on function ops_record_manual_payout(uuid, uuid[], int, text) from public, anon;
grant  execute on function ops_record_manual_payout(uuid, uuid[], int, text) to authenticated;

-- The sweep is a CRON function: no human calls it, it takes no caller identity, and it notifies
-- on behalf of the system. Client roles have no business holding it.
revoke execute on function ops_payouts_stuck_sweep() from public, anon, authenticated;
grant  execute on function ops_payouts_stuck_sweep() to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 217
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- What this block owns that the suite cannot: the state of the world AT APPLY. A property checked
-- only by a suite is protected until someone recreates the function in a later file; a property
-- checked only here is protected until someone edits this file. Both, then — and the literals
-- below are written independently of §A-§F's so a typo in either place aborts the apply rather
-- than satisfying itself (0177's 「two independent spellings」).
-- `is distinct from` / `is not true` throughout: every arm here exists to notice that something is
-- MISSING, which is exactly the shape that goes silent on a NULL under a bare `IF`.
do $$
declare
  v_bad text := '';
  v_oid oid;
  v_n   int;
begin
  -- ── the three functions: definer · in-body search_path · ACL by value ──
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_payouts_due';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_payouts_due)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_payouts_due:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_payouts_due:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',   v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ops_payouts_due:CLIENT-EXECUTABLE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' ops_payouts_due:NO-AUTHENTICATED'; end if;
  end if;

  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_record_manual_payout';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_record_manual_payout)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_record_manual_payout:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_record_manual_payout:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',   v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ops_record_manual_payout:CLIENT-EXECUTABLE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' ops_record_manual_payout:NO-AUTHENTICATED'; end if;
  end if;

  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_payouts_stuck_sweep';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_payouts_stuck_sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_payouts_stuck_sweep:NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' ops_payouts_stuck_sweep:NO-SEARCH-PATH'; end if;
    if has_function_privilege('public',        v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon',          v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ops_payouts_stuck_sweep:CLIENT-EXECUTABLE'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' ops_payouts_stuck_sweep:NO-SERVICE-ROLE'; end if;
  end if;

  -- ── the four columns, by name and by type ──
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'ledger_items'
         and column_name = 'paid_payout_id') is distinct from 'uuid'
    then v_bad := v_bad || ' NO-COLUMN(ledger_items.paid_payout_id uuid)'; end if;
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'payouts' and column_name = 'method')
     is distinct from 'text'
    then v_bad := v_bad || ' NO-COLUMN(payouts.method text)'; end if;
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'payouts' and column_name = 'memo')
     is distinct from 'text'
    then v_bad := v_bad || ' NO-COLUMN(payouts.memo text)'; end if;
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'payouts' and column_name = 'recorded_by')
     is distinct from 'uuid'
    then v_bad := v_bad || ' NO-COLUMN(payouts.recorded_by uuid)'; end if;

  -- ── the column seal: the ops half of a payout row does not follow the runner home ──
  if has_column_privilege('authenticated', 'payouts', 'memo',        'SELECT') is distinct from false
  or has_column_privilege('authenticated', 'payouts', 'method',      'SELECT') is distinct from false
  or has_column_privilege('authenticated', 'payouts', 'recorded_by', 'SELECT') is distinct from false
    then v_bad := v_bad || ' payouts:OPS-COLUMNS-READABLE'; end if;
  if has_column_privilege('authenticated', 'payouts', 'net', 'SELECT') is distinct from true
    then v_bad := v_bad || ' payouts:SELF-READ-BROKEN'; end if;
  if has_column_privilege('authenticated', 'ledger_items', 'paid_payout_id', 'SELECT')
     is distinct from false
    then v_bad := v_bad || ' ledger_items:CLIENT-READABLE'; end if;

  -- ── the cron ARTIFACT, read back from cron.job (0177's law) ──
  select count(*)::int into v_n
    from cron.job
   where jobname = 'ops-payouts-stuck'
     and active
     and schedule = '25 0,9 * * *'
     and command  = 'select ops_payouts_stuck_sweep()';
  if v_n is distinct from 1
    then v_bad := v_bad || ' CRON(ops-payouts-stuck)=' || coalesce(v_n::text, 'NULL')
                        || ' (expected exactly 1 active row on jobname/schedule/command)'; end if;

  if v_bad <> '' then raise exception '0186 VERIFY FAILED:%', v_bad; end if;
end $$;
