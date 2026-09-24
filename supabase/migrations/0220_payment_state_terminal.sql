-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0220 — a booking that ENDED without a run is told so, instead of waiting forever for a
--        settlement that will never happen
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 251_payment_state_terminal_suite.sql (tag `pst0`). Pins 0220-T1 … T5 · C1 · S1.
-- Correct-forward for the 2026-09-25 Codex server verdict, finding #6 (medium, READ-based):
-- `docs/reviews/2026-09-25-server-0201-0215-codex-verdict.md`.
--
-- ⚠ 0207 IS NOT EDITED. It is on origin. This file re-declares `my_booking_payment_state` from
--   the deployed catalog body with ONE new fork inserted, and restates the ACL (§B).
--
-- ═══ 🔴 THE HOLE, REPRODUCED ON TRUNK'S BODY BEFORE THIS FILE WAS WRITTEN ══════════════════════
-- Codex read it; nothing measured it, so it was measured first. Fixture: charging live
-- (`ops_flags.payments_live_since = now() - 30 days`), a booking with NO `runs` row and NO
-- `payments` row, run through `my_booking_payment_state` as its owner. Trunk's answers:
--
--   ① `cancelled_owner`, `cancel_fee = 0`            →  awaiting_settlement   🔴 the finding
--   ② `cancelled_owner`, `cancel_fee = 12450`, unminted → awaiting_settlement 🔴 same hole
--   ③ `cancelled_owner`, `cancel_fee = 12450`, intent minted → charge_pending ✅ (the control)
--   ④ `cancelled_runner`                             →  awaiting_settlement   🔴
--   ⑤ `expired`                                      →  awaiting_settlement   🔴
--   ⑥ `no_show`                                      →  awaiting_settlement   🔴
--   ⋯ and `payments_reconciliation()` arm eight does NOT report ① (`t_o7_board` = false)
--
-- The last line is the part that decides how bad this is. Arm eight needs `rn.ended_at is not
-- null and rn.settled_at is not null`, and these bookings have no run at all — so the OPS BOARD
-- IS SILENT ABOUT THEM. The owner is the only person being told anything, and what they are told
-- is `awaiting_settlement`, whose shipped copy is 「정산이 끝나면 청구돼요 / 러닝이 끝나고 정산되면
-- 청구서가 만들어져요」 (`app/src/lib/payment-state.ts`). That sentence promises a bill, forever,
-- about a booking whose run will never happen. Nothing contradicts it and nobody is looking.
--
-- ⚠ Why ① is a NORMAL shape and not an edge: `transition-booking/cancel_owner.ts:263` is
--   `if (!(fee > 0)) return;` — a zero-fee cancel deliberately mints nothing — and
--   `mint_cancel_fee_intent` (`0118:588`) carries the same refusal in SQL (`if v_fee <= 0 then
--   return; end if;`). Every free cancellation in the pilot lands here.
--
-- ═══ §0a — WHICH STATUSES ARE 「TERMINAL WITHOUT A RUN」, AND THE LINE THAT SAYS SO ═════════════
-- Not an enumeration invented here. `0075:750` — the `km_release_on_terminal_gate` trigger's own
-- WHEN clause — is
--      new.status in ('expired', 'cancelled_owner', 'cancelled_runner', 'no_show')
-- i.e. exactly the statuses at which this product already RELEASES the km hold because the
-- booking ended and nothing more is owed on that axis. `0193:973` names the identical four under
-- the comment `-- ended`. Two independent deployed lines, same set; this file uses it verbatim.
--
-- ⚠ **`declined` IS NOT A BOOKING STATUS AND WAS NOT ADDED.** Measured: `booking_status`
--   (`0001:9-14`) is draft · quoted · payment_hold · matching · runner_pending · confirmed ·
--   runner_enroute · picked_up · active · completed · cancelled_owner · cancelled_runner ·
--   expired · no_show · incident_review · refund_pending, with **zero** `alter type … add value`
--   anywhere in `supabase/migrations/`. `declined` exists only as an `assignment_state` /
--   `runner_assignment_events.event` value (`0040:40,56`) — a runner declining a proposal leaves
--   the booking in `matching`, which is not terminal. Naming a state for it would have been a
--   vocabulary this repo does not have.
-- ⚠ **`incident_review` and `refund_pending` are deliberately NOT in the set**, and both
--   omissions are the same reason: they are RECOVERABLE by a human rather than ended.
--   `0117:637-640` picks `incident_review` precisely because 「it is recoverable by a human, and
--   it moves no money by itself」, and `0193:973` groups both outside its `-- ended` four. A
--   booking sitting in either still has a real financial process in front of it, so
--   `awaiting_settlement` is not a false sentence there — it is the one state that copy was
--   always honest about.
--
-- ═══ §0b — THE NEW FORK IS A STRICT REFINEMENT OF `awaiting_settlement`, BY CONSTRUCTION ═══════
-- 🔴 The fork is placed INSIDE the existing `v_settled is null or v_ended_raw is null` branch,
--    not in front of it. That is deliberate and it is what makes the blast radius provable: the
--    ONLY rows whose answer can change are rows that answered `awaiting_settlement` before this
--    file. Three consequences that would otherwise each need their own argument:
--      · `0207-P1`'s set-agreement with `payments_reconciliation()` arm eight is untouched — arm
--        eight requires BOTH run timestamps, which is exactly the complement of this branch.
--      · the cutover pair (`0084:264-266`) still runs FIRST, so a pre-flip free cancellation
--        keeps answering `no_charge`/`not_charging` and `0207-P4` does not move.
--      · a terminal booking whose run did settle (no writer produces one — `settle_run_tx` never
--        runs for a cancelled booking, `cancel_owner.ts:298`) still walks the settlement ladder.
--        This file makes no claim about that population.
--    `0220-T5` measures the refinement rather than asserting it.
--
-- ═══ §0c — THE TWO NEW ANSWERS, AND THE DEPLOYED LINE EACH IS DERIVED FROM ════════════════════
--
--   answer                     | derived from                                                   |
--   ---------------------------|----------------------------------------------------------------|
--   no_charge / cancelled_free | `coalesce(b.cancel_fee, 0)` = 0 on `cancelled_owner`. The fee   |
--                              | ladder's own zero (`0066` → `marketplace_cancel_fee`), and the  |
--                              | two places that refuse to mint on it: `cancel_owner.ts:263`     |
--                              | `if (!(fee > 0)) return;` and `0118:588` `if v_fee <= 0 then    |
--                              | return; end if;`. Nothing was minted, and nothing ever will be. |
--   no_charge /                | `cancelled_runner` — the runner ended it; `0066`'s ladder bills |
--     cancelled_by_runner      | the OWNER's cancellation, never the runner's.                   |
--   no_charge / expired        | `0017`/`0047`'s unmatched-booking expiry. No runner, no run.    |
--   no_charge / no_show        | `0117:665` — 「pre-custody; a party stated it」, and `0117:57`'s |
--                              | own sentence about that whole protocol: 「it NEVER moves money   |
--                              | and NEVER writes fault — no cancel_fee, no payments」.           |
--   fee_unminted               | the complement: a terminal booking carrying `cancel_fee > 0`    |
--                              | with no qualifying `payments` row. The ops board already has    |
--                              | this shape for the club half — `payments_reconciliation()` arm  |
--                              | `club_fee_unminted` (`0173:184-190`: a fee event older than an  |
--                              | hour with `not exists (_cancel_fee_existing_payment(b.id))`) —  |
--                              | and the marketplace half has had no reader at all.               |
--
-- ⚠ **`fee_unminted` CARRIES NO `amount_won`, AND THAT IS THE HARD PART OF THIS FILE.**
--   `bookings.cancel_fee` is a real stored number, not a fabricated one, so the temptation is to
--   print it. It is refused for a narrower reason than 0173:100-101's: `amount_won`'s CONTRACT,
--   written into both `0207`'s comment and `api.ts`'s wrapper, is 「실제 payments 행이 답한
--   경우에만 숫자」 — a number here means a payments row answered. Filling it from `bookings`
--   would make the same column mean two different things depending on the state, which is the
--   widening-what-a-value-can-mean class this repo has already paid for once. `0207-P6` pins the
--   contract; this file keeps it. The owner is told a fee has not been billed, without a figure
--   the receipt list cannot corroborate.
-- ⚠ **`fee_unminted` carries no `reason` either.** There is exactly one thing it can mean, and a
--   token whose value never varies is a column pretending to be a question.
-- ⚠ **`no_charge`'s reason is no longer a single token, and `0207 §0a`'s collapse argument does
--   NOT extend to the new ones.** That collapse exists because splitting `not_charging` would
--   have handed every authenticated owner the global rollout switch's state. The four new tokens
--   leak nothing: each is a restatement of `bookings.status`, which this caller is the owner of
--   and already reads on the same screen.
--
-- ═══ §0d — BLAST RADIUS OUTSIDE THIS FILE, enumerated by hand ═════════════════════════════════
-- The RPC's SIGNATURE is unchanged (one `uuid` in; the same five columns out), so
-- `check-rpc-contracts` and every existing caller compile untouched. What widens is the VALUE
-- SET of `state` and of `reason` — the 0143 class, where a correct caller breaks with no edit to
-- itself. The callers are enumerable and there is exactly one: `app/src/lib/api.ts`'s
-- `fetchBookingPaymentState` → `app/src/lib/payment-state.ts`'s `paymentFace`, rendered by
-- `app/app/owner/schedule.tsx`. Both move in this same slice. `payments_reconciliation`,
-- `mint_cancel_fee_intent`, `sweep_settled_without_payments`, `charge_row_due` and every edge
-- function are untouched — measured: zero `my_booking_payment_state` references under
-- `supabase/functions/`.
-- ⚠ A phone built before this file meets `fee_unminted` and falls to `paymentFace`'s fail-closed
--   `default` arm (「결제 상태를 확인하고 있어요」) — an admission, never the nearest sentence.
--   That arm already existed; `0220-C1`'s client half pins that it still fires.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — `my_booking_payment_state`, re-declared with the terminal fork ══════════════════════
--
-- Body copied from the deployed catalog (0207 §A) rather than re-derived. The ONLY differences
-- are marked `[0220]`.
create or replace function my_booking_payment_state(p_booking uuid)
returns table (
  state       text,
  amount_won  int,
  charged_at  timestamptz,
  intent_at   timestamptz,
  reason      text
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid       uuid := auth.uid();
  v_pay       payments%rowtype;
  v_since     timestamptz;
  v_ended_raw timestamptz;
  v_ended     timestamptz;
  v_settled   timestamptz;
  v_end_rsn   text;
  v_km        numeric;
  v_attempts  int;
  v_relink    boolean;
  v_state     text;
  v_amount    int;
  v_charged   timestamptz;
  v_intent    timestamptz;
  v_reason    text;
  v_status    text;     -- [0220] the booking's own status, read AFTER the gate
  v_fee       int;      -- [0220] coalesce(bookings.cancel_fee, 0)
begin
  -- ① a subject, before anything is read.
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- ② THE PARTY GATE, ahead of every read. `is not true` rather than a bare `if`, so a NULL from
  --    any cause refuses instead of collapsing into silence (the plpgsql NULL-IF law). The
  --    `exists` shape is what makes a foreign booking and a booking that does not exist
  --    indistinguishable: both are `false`, both raise `not_party`.
  if (select exists (select 1 from bookings b
                      where b.id = p_booking
                        and b.owner_id = v_uid)) is not true
  then raise exception 'not_party'; end if;

  -- ③ THE QUALIFYING ROW — `payments_reconciliation` arm eight's predicate, copied verbatim from
  --    `0173:208-212` rather than re-derived. It is DELIBERATELY WIDER than the mint's own
  --    existence check (`0116:96-106`, review round 2 finding 4: aligning them enabled a
  --    ₩15,000+₩20,000 double-charge on refund-vocabulary rows, and `151 B1 ⓒ′` pins the wider
  --    form). Any kind-bearing row at all, plus confirmed/waived. A narrower predicate here would
  --    tell an owner 「no charge」 about a booking the sweep is deliberately staying out of.
  --    The ORDER is `mint_settle_charge_intent`'s own (`0084:278-279`): a settling row outranks a
  --    still-moving one, then oldest first.
  select p.* into v_pay
    from payments p
   where p.booking_id = p_booking
     and ((p.raw->>'kind') is not null or p.status in ('confirmed', 'waived'))
   order by case when p.status in ('confirmed', 'waived') then 0 else 1 end, p.created_at
   limit 1;

  if v_pay.id is not null then
    -- ④ A ROW EXISTS — the state is that row's status. §0c ⓐ/ⓑ of 0207 carry the two divergences.
    v_attempts := _charge_int(v_pay.raw, 'attempts');
    v_relink   := coalesce(_charge_bool(v_pay.raw, 'needs_card_relink'), false);
    v_amount   := v_pay.amount;
    v_intent   := v_pay.created_at;

    if v_pay.status = 'confirmed' then
      v_state := 'charged';
      -- every writer that sets `confirmed` sets `updated_at` in the SAME statement, and no writer
      -- patches a row that is already confirmed without moving it off `confirmed` — so this is
      -- the instant the money was recorded, not a read time.
      v_charged := v_pay.updated_at;
    elsif v_pay.status = 'waived' then
      v_state := 'waived';
      -- arm five's own predicate (`0173:172-174`): resolution is the ABSENCE of the resolved key.
      if (v_pay.raw->>'review') = 'incident_pending'
         and (v_pay.raw->>'review_resolved_at') is null then
        v_reason := 'incident_review';
      end if;
    elsif v_pay.status = 'pending' then
      v_state := 'charge_pending';
    elsif v_pay.status = 'failed' then
      if v_relink is true then
        v_state := 'arrears'; v_reason := 'card_relink';
      elsif v_attempts is null or v_attempts >= charge_max_attempts() then
        v_state := 'arrears'; v_reason := 'ladder_exhausted';
      else
        v_state := 'charge_retrying';
      end if;
    elsif v_pay.status in ('canceled', 'partial_canceled') then
      v_state := 'refunded';
      v_reason := v_pay.status;      -- server vocabulary, a token the client maps (STATUS_MAP law)
    else
      -- §0b of 0207. A status this file has never heard of gets an admission, never the nearest
      -- sentence.
      v_state := 'unknown';
    end if;
  else
    -- ⑤ NO QUALIFYING ROW — the answer is WHY there is none, and the ladder below walks arm
    --    eight's conjuncts outward-in so each state is the exact complement of the next.
    select f.payments_live_since into v_since from ops_flags f where f.id;
    select r.ended_at, coalesce(r.ended_at, now()), r.settled_at, r.end_reason::text, r.actual_km
      into v_ended_raw, v_ended, v_settled, v_end_rsn, v_km
      from runs r where r.booking_id = p_booking;
    -- [0220] the booking's own two facts. Alias `tb` rather than `b` ON PURPOSE: the VERIFY block
    -- below asserts the party gate PRECEDES every read by position, and the gate's own subquery
    -- says `from bookings b` — an identical alias here would make that arm match the gate itself
    -- and prove nothing. A distinct alias keeps the position check honest.
    select tb.status::text, coalesce(tb.cancel_fee, 0)
      into v_status, v_fee
      from bookings tb where tb.id = p_booking;

    if v_since is null or coalesce(v_ended, now()) < v_since then
      -- the mint's cutover pair, `0084:264-266`. Nothing will ever be minted for this booking.
      v_state := 'no_charge'; v_reason := 'not_charging';
    elsif v_settled is null or v_ended_raw is null then
      -- arm eight's anchor (`0173:204,206`), FAILING. Everything from here to the `else` below is
      -- the population that answered `awaiting_settlement` before 0220 — §0b.
      --
      -- [0220] ⑤-bis THE TERMINAL FORK. `0075:750`'s own four statuses: the booking ENDED and no
      -- run exists to settle, so 「정산이 끝나면 청구돼요」 is a promise nothing can keep.
      -- `is not distinct from` / an explicit `= any` on a non-NULL array, never a bare IF on a
      -- possibly-NULL predicate — `v_status` is NULL only if the booking vanished between the
      -- gate and this read, and a NULL there must fall through to the old answer rather than
      -- silently pick an arm.
      if v_status = any (array['expired', 'cancelled_owner', 'cancelled_runner', 'no_show']) then
        if coalesce(v_fee, 0) <= 0 then
          -- nothing was owed and nothing was minted — `cancel_owner.ts:263` / `0118:588`.
          v_state  := 'no_charge';
          v_reason := case v_status
                        when 'cancelled_owner'  then 'cancelled_free'
                        when 'cancelled_runner' then 'cancelled_by_runner'
                        when 'expired'          then 'expired'
                        else                         'no_show'
                      end;
        else
          -- a fee IS owed and no intent was ever minted. Named for what it is, and it carries no
          -- amount — §0c.
          v_state := 'fee_unminted';
        end if;
      else
        v_state := 'awaiting_settlement';
      end if;
    elsif v_settled >= now() - interval '1 hour' then
      -- arm eight's grace (`0173:207`), complemented. No new constant: the hour is
      -- `payments_reconciliation`'s own, shared with arms two, three and seven.
      v_state := 'settling';
    else
      -- 🔴 arm eight. `reason` is arm eight's `case`, in the sweep's own order (`0173:198-200`),
      --    so the word an owner's screen keys on is the word the ops board would print.
      v_state  := 'settled_without_payment';
      v_reason := case when v_end_rsn is null then 'missing_end_reason'
                       when v_km      is null then 'missing_actual_km'
                       else 'unpriced' end;
    end if;
  end if;

  return query select v_state, v_amount, v_charged, v_intent, v_reason;
end $$;


-- ═══ §B — ACL, written out and never inherited ════════════════════════════════════════════════
-- `create or replace` preserves an ACL only where the function already exists; on a partial prior
-- apply or a rebuilt environment this statement is a plain CREATE and a new function is born
-- PUBLIC-executable (`0116:636`). A SECURITY DEFINER that reads `payments` — the table whose
-- `raw` holds the provider's response — born public-executable is the worst shape this repo can
-- produce, so the revoke is the guard and not the tidying. Restated verbatim from `0207:290-291`,
-- the file that last set it.
revoke execute on function my_booking_payment_state(uuid) from public, anon;
grant  execute on function my_booking_payment_state(uuid) to authenticated;

comment on function my_booking_payment_state(uuid) is
  '0207 + 0220: the OWNER''s payment state for one booking, named by the server rather than
inferred from a row count. Party gate (owner only) runs BEFORE any read; a foreign booking, a
non-existent booking and a runner all get the same `not_party`. Returns EXACTLY ONE flat row,
always: state · amount_won · charged_at · intent_at · reason.
0220 adds the TERMINAL FORK (Codex 2026-09-25 server finding #6, reproduced before it was fixed):
a booking in one of 0075:750''s four ended statuses (expired · cancelled_owner · cancelled_runner ·
no_show) with no run to settle used to answer `awaiting_settlement` — 「정산이 끝나면 청구돼요」 —
forever, while payments_reconciliation arm eight could not see it either (it needs both run
timestamps). Now: cancel_fee 0 → `no_charge` with the reason naming which ending
(cancelled_free · cancelled_by_runner · expired · no_show); cancel_fee > 0 with no qualifying
payments row → `fee_unminted`, the marketplace twin of arm `club_fee_unminted` (0173:184-190).
🔴 The fork sits INSIDE the pre-0220 `awaiting_settlement` branch, so the only rows whose answer
can change are rows that answered `awaiting_settlement`: the cutover pair still runs first and arm
eight''s population is untouched (0220-T5 measures that). amount_won stays NULL for `fee_unminted`
— a number in that column means a payments row answered, and bookings.cancel_fee is not one.
THIS IS STILL A READ: it mints nothing, moves nothing, and changes no sweep. Pinned by 238
0207-P1…P7 · S1 · S2 and by 251 0220-T1…T5 · C1 · S1.';


-- ═══ VERIFY — the deployed ARTIFACT, read back from the catalog ═══════════════════════════════
-- House form. Every arm is an explicit boolean (`is not true` / `is distinct from`), never a bare
-- `IF` on a possibly-NULL predicate: every arm here exists to notice that something is MISSING,
-- and a NULL predicate makes a plpgsql `IF` silent.
do $$
declare
  v_oid     oid;
  v_src     text;
  v_raw     text;
  v_secdef  boolean;
  v_path    boolean;
  v_pub     boolean;
  v_auth    boolean;
  v_gate    int;
  v_read    int;
  v_term    int;
  v_await   int;
  v_cut     int;
  v_bad     text := '';
begin
  select p.oid, p.prosrc, p.prosecdef,
         coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
    into v_oid, v_raw, v_secdef, v_path
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'my_booking_payment_state'
    and p.pronargs = 1;

  -- NO-FUNCTION / NO-SOURCE first: a NULL `prosrc` makes every `position()` below NULL, and a set
  -- of silent arms is precisely how a source check passes on a function that is not there at all.
  if v_oid is null then
    raise exception '0220 VERIFY FAILED: NO-FUNCTION(my_booking_payment_state/1)';
  end if;
  if v_raw is null then
    raise exception '0220 VERIFY FAILED: NO-SOURCE(my_booking_payment_state) — prosrc is NULL, every source arm below would have been silent';
  end if;

  -- ⚠ COMMENTS STRIPPED BEFORE MATCHING, and it is load-bearing rather than tidy: `prosrc` is the
  -- body PLUS our own prose, and this function's prose NAMES every predicate it implements. Read
  -- un-stripped, a migration that DOCUMENTED the fork and failed to write it would satisfy every
  -- arm below — the instrument would reward the documentation as if it were the implementation.
  v_src := regexp_replace(v_raw, '--[^\n]*', '', 'g');

  -- CONTROL on the stripper, and it is genuinely two-sided rather than named two-sided: this arm
  -- catches a stripper that removed NOTHING (every `like` below would then be satisfiable by our
  -- own prose), and the `like` arms below catch a stripper that removed EVERYTHING (they would
  -- all report a missing predicate). Neither direction passes silently.
  if (length(v_src) < length(v_raw)) is not true then
    v_bad := v_bad || ' STRIPPER-NO-OP(no comment was removed from prosrc)';
  end if;
  if (position('fee_unminted' in v_src) > 0) is not true then
    v_bad := v_bad || ' TERMINAL-STATE-MISSING(fee_unminted)';
  end if;

  -- the party gate must PRECEDE the first read of payments/runs/ops_flags/bookings-as-`tb`.
  -- Position, not presence. `tb` is in the list because 0220 added that read.
  v_gate := position('not_party' in v_src);
  v_read := least(
    nullif(position('from payments p' in v_src), 0),
    nullif(position('from ops_flags f' in v_src), 0),
    nullif(position('from runs r' in v_src), 0),
    nullif(position('from bookings tb' in v_src), 0));
  if (v_gate > 0) is not true then
    v_bad := v_bad || ' PARTY-GATE-ABSENT';
  elsif (v_read > 0) is not true then
    v_bad := v_bad || ' NO-READ-FOUND(the gate cannot be shown to precede a read that is not there)';
  elsif (v_gate < v_read) is not true then
    v_bad := v_bad || ' GATE-AFTER-READ(gate=' || v_gate || ' read=' || v_read || ')';
  end if;

  -- 0207's three load-bearing strings, verbatim, still there. If a later edit re-derives any of
  -- them this function stops answering the question the ops board answers, silently.
  if (v_src like '%(p.raw->>''kind'') is not null or p.status in (''confirmed'', ''waived'')%') is not true then
    v_bad := v_bad || ' QUALIFYING-PREDICATE-DIVERGED(0173:211)';
  end if;
  if (v_src like '%now() - interval ''1 hour''%') is not true then
    v_bad := v_bad || ' GRACE-MISSING(0173:207)';
  end if;
  if (v_src like '%payments_live_since%') is not true then
    v_bad := v_bad || ' CUTOVER-SCOPE-MISSING(0084:264)';
  end if;

  -- [0220] the terminal set is 0075:750's four, and the fee is read with a coalesce so a NULL
  -- `cancel_fee` (the column is nullable, `0001:185`) cannot make the zero-fee arm silent.
  if (v_src like '%''expired'', ''cancelled_owner'', ''cancelled_runner'', ''no_show''%') is not true then
    v_bad := v_bad || ' TERMINAL-SET-DIVERGED(0075:750)';
  end if;
  if (v_src like '%coalesce(tb.cancel_fee, 0)%') is not true then
    v_bad := v_bad || ' FEE-READ-NOT-COALESCED(0001:185 is nullable)';
  end if;

  -- [0220] ORDER, the property §0b rests on: the terminal fork must sit INSIDE the branch that
  -- used to answer `awaiting_settlement`, which from the source is visible as the fork's array
  -- preceding the surviving `awaiting_settlement` assignment. If a later edit hoists the fork in
  -- front of the cutover pair, the cutover assignment moves behind it and this arm fires.
  v_term  := position('''cancelled_owner'', ''cancelled_runner''' in v_src);
  v_await := position('v_state := ''awaiting_settlement''' in v_src);
  if (v_term > 0) is not true then
    v_bad := v_bad || ' TERMINAL-FORK-ABSENT';
  elsif (v_await > 0) is not true then
    v_bad := v_bad || ' AWAITING-ARM-GONE(the fork must REFINE that branch, not replace it)';
  elsif (v_term < v_await) is not true then
    v_bad := v_bad || ' FORK-AFTER-AWAITING(term=' || v_term || ' await=' || v_await || ')';
  end if;
  -- …and the cutover pair must still outrank the fork. `position()` returns 0 for ABSENT, and
  -- 0 < v_term is true — so an absent cutover assignment would satisfy a bare comparison and this
  -- arm would be silent about the worst case. Presence is asserted first, separately.
  v_cut := position('v_state := ''no_charge''; v_reason := ''not_charging''' in v_src);
  if (v_cut > 0) is not true then
    v_bad := v_bad || ' CUTOVER-ARM-GONE(0084:264-266)';
  elsif (v_term > 0) and (v_cut < v_term) is not true then
    v_bad := v_bad || ' CUTOVER-NOT-FIRST(cut=' || v_cut || ' term=' || v_term || ')';
  end if;

  -- the two anchors 0116:47-52 refuses BY NAME, asserted in the positive direction so a NULL
  -- cannot make either arm silent. ⚠ `b.status = 'completed'` — 0220 reads `tb.status`, which is
  -- a different thing: the terminal fork never anchors on the DISPLAY status word `completed`.
  if (v_src like '%b.status = ''completed''%') is true then
    v_bad := v_bad || ' WRONG-ANCHOR(bookings.status)';
  end if;
  if (v_src like '%ledger_items%') is true then
    v_bad := v_bad || ' WRONG-ANCHOR(ledger_items)';
  end if;

  if v_secdef is not true then v_bad := v_bad || ' NOT-SECURITY-DEFINER'; end if;
  if v_path   is not true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;

  v_pub  := has_function_privilege('anon', v_oid, 'execute');
  v_auth := has_function_privilege('authenticated', v_oid, 'execute');
  if v_pub  is distinct from false then v_bad := v_bad || ' ANON-CAN-EXECUTE'; end if;
  if v_auth is distinct from true  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-EXECUTE'; end if;

  if v_bad <> '' then
    raise exception '0220 VERIFY FAILED:%', v_bad;
  end if;
end $$;
