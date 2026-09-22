-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0207 — the owner is told the payment state the SERVER already knows, not a row count
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 238_owner_payment_state_suite.sql (tag `ops7`). Pins 0207-P1 … P7 · S1 · S2.
--
-- ═══ 🔴 THE GAP, MEASURED ON TRUNK BEFORE THIS FILE ════════════════════════════════════════════
--
-- `0173` added arm eight to `payments_reconciliation()` — a SETTLED booking with no qualifying
-- `payments` row, past an hour of five-minute sweeps. `0172 §A` reads the sweep's cron row back.
-- Both are OPS machinery: `payments_reconciliation` is `revoke execute … from authenticated`
-- (`0173:217`) and has **no runtime caller at all**. Re-measured for this slice rather than
-- inherited from `0173:118-119`: **zero** `.rpc("payments_reconciliation"…)` invocations across
-- `app/` and `supabase/functions/`, and all eight executable mentions are STRINGS — the Korean
-- operator copy in `_shared/ops.ts:66,126` that tells a human to go and run the query, plus two
-- Deno test assertions about that copy. Nothing calls it.
--
-- The owner's screen reads the OTHER side of the same fact and draws the opposite conclusion.
-- `app/src/lib/api.ts`'s `fetchBookingPayments` selects `payments` rows for one booking, and
-- `app/app/owner/schedule.tsx` renders
--        payRows.length === 0  →  「아직 청구 내역이 없어요 — 정산이 끝나면 여기에 표시돼요」
-- for every settled booking with zero rows. That sentence is TRUE of a booking still settling and
-- **FALSE of exactly the population arm eight exists to report**: the mint raised, or the run
-- cannot be priced, and an hour of sweeps has produced nothing. The server knows the difference;
-- the owner is told 「아직」 — a word that means 「it is coming」 — about a charge that is not coming
-- without a human. A count of rows is not a state, and 0 rows has two meanings.
--
-- ⚠ This is `WHAT THE DATABASE SHOWS IS NOT WHAT THE PRODUCT MEANS` in its client half: the client
--   measured `count(payments) = 0` and rendered it as 「청구가 없었다」. Different propositions.
--
-- ═══ WHAT THIS FILE IS, AND WHAT IT IS NOT ════════════════════════════════════════════════════
-- 🔴 **IT IS A READ. It moves no money, mints nothing, writes nothing, and changes no sweep.**
--    Its entire effect is that one owner-only `select` can now name the state the reconciliation
--    arms are already keyed on. Nothing in `sweep_settled_without_payments`,
--    `mint_settle_charge_intent`, `dispatch_due_charges` or `payments_reconciliation` is touched.
-- ⚠ **It does not price anything.** For a settled booking with no payments row, `amount_won` is
--    NULL — `0173:100-101`'s own sentence: 「the defining property of these rows is that nobody
--    could price them, and a number here would be a fabricated one」. The quote the owner agreed
--    to is already on that sheet, correctly labelled 「예상 결제 · 완주 기준」; reprinting it inside
--    the payment line would say 「this is what you were charged」 about a charge that does not
--    exist. The settled-without-payment line therefore carries a SENTENCE and no number.
-- ⚠ **It adds no new constant.** Every threshold below is lifted from a deployed function and
--    cited to its line; nothing here is PROVISIONAL.
--
-- ═══ §0a — THE STATE VOCABULARY, AND THE LINE EACH ONE IS DERIVED FROM ════════════════════════
--
--   state                    | derived from                                                     |
--   -------------------------|------------------------------------------------------------------|
--   no_charge                | `mint_settle_charge_intent`'s cutover PAIR, `0084:264-266`:       |
--                            | `payments_live_since is null` → the mint returns and writes       |
--                            | nothing; `coalesce(r.ended_at, now()) < v_since` → 「pilot-era     |
--                            | run: free, forever」 (that file's own words). Both are the same    |
--                            | product fact: nothing will ever be charged for this booking.      |
--   awaiting_settlement      | arm eight's ANCHOR failing — `0173:204,206`                       |
--                            | (`rn.ended_at is not null and rn.settled_at is not null`).        |
--                            | The run has not settled, so no charge exists YET and that is       |
--                            | correct. This is the only state today's copy was ever true of.     |
--   settling                 | arm eight's GRACE failing — `0173:207`                            |
--                            | (`rn.settled_at < now() - interval '1 hour'`). Settled, no row,    |
--                            | INSIDE the hour: `0173:84-88` says SQL cannot distinguish a mint   |
--                            | that raised from a sweep that has not reached the row, and the     |
--                            | grace is exactly what buys that distinction. Inside it, 「the       |
--                            | sweep is coming」 is the honest sentence.                          |
--   settled_without_payment  | 🔴 arm eight itself — `0173:197-212`, every conjunct. `reason`     |
--                            | is arm eight's own `case`, IN ITS ORDER (`0173:198-200`):         |
--                            | `missing_end_reason` → `missing_actual_km` → `unpriced`.          |
--   charge_pending           | `mint_settle_charge_intent`'s own output — `0084:299`,            |
--                            | `case when amount = 0 then 'waived' else 'pending' end`.          |
--   charge_retrying          | `charge_row_due` arm ⓐ — `0116:272-275`: `failed`, attempts below  |
--                            | `charge_max_attempts()` (`0116:232-233`), relink flag false. The   |
--                            | ladder will fire again on its own.                                |
--   arrears                  | the two ways the ladder STOPS: `payments_reconciliation` arm four  |
--                            | `ladder_exhausted` (`0173:162-167`, attempts at the cap) and       |
--                            | `charge_row_due`'s relink conjunct (`0116:274`) — a row whose card |
--                            | is known dead 「waits for the owner to relink, not for the clock」   |
--                            | (`0116:237-239`). Both mean: nothing retries without a person.     |
--   charged                  | `payments.status = 'confirmed'` (`0071:46`), the status every      |
--                            | capture writer sets together with `payment_key` and `updated_at`   |
--                            | in ONE statement (`confirm-payment/handler.ts:186,286`,           |
--                            | `collect-charges/handler.ts:305-310`, `_shared/charge.ts` §flip) — |
--                            | which is why `updated_at` is the honest `charged_at`.              |
--   waived                   | `0080:147,161` — a `waived` row is `amount = 0` and keyless BY     |
--                            | CONSTRAINT. A decision, not an absence, which is why it is not     |
--                            | folded into `no_charge`. `reason = incident_review` when           |
--                            | `0084 §B`'s review marker is open (`raw.review = incident_pending` |
--                            | and no `review_resolved_at` — arm five's own predicate,            |
--                            | `0173:172-174`).                                                  |
--   refunded                 | arm six's statuses — `0173:179` `('canceled','partial_canceled')`. |
--                            | `reason` carries which, because a full and a partial refund are    |
--                            | two different sentences to the person who paid.                    |
--   unknown                  | 🔴 THE FAIL-CLOSED ARM. See §0b.                                   |
--
-- ⚠ **`no_charge` HAS ONE REASON TOKEN, `not_charging`, AND THE COLLAPSE IS DELIBERATE.** The two
--   causes — the flag is NULL, or this run ended before the flip — produce the same product
--   sentence, and splitting them would hand every authenticated owner the global rollout switch's
--   state in exchange for nothing. Minimal honest option.
--
-- ═══ §0b — WHY `unknown` EXISTS, AND WHY IT IS NOT PINNED ═════════════════════════════════════
-- 🔴 WIDENING WHAT AN ENUM CAN MEAN BREAKS A CORRECT CALLER WITH NO EDIT TO THE CALLER. Every one
--    of the six values `payments_status_vocab` (`0080:147`) admits has an explicit arm below. A
--    seventh, added by some later migration, must NOT fall into the nearest arm and tell an owner
--    a sentence nobody wrote for it — so the `else` produces `unknown`, whose client face is
--    「결제 상태를 확인하고 있어요」: an admission, not a guess.
-- ⚠ **It is NOT pinned behaviourally, and that is the house law rather than an omission.** Every
--    status the CHECK admits is mapped, so no fixture this harness can build reaches the `else`;
--    a pin over it would be green by construction and would read as coverage forever. The
--    limitation is prose — this paragraph — and what IS pinned is the property that makes the
--    `else` unreachable: `0207-S2` reads the CHECK's own literals out of `pg_constraint` and
--    asserts each one has an arm in the function's comment-stripped source. That pin reddens when
--    an arm is deleted AND when the vocabulary grows without one, which is the real obligation.
--
-- ═══ §0c — DIVERGENCES FROM THE ARMS, NAMED RATHER THAN DISCOVERED ═══════════════════════════
-- ⓐ **Arm four casts `(p.raw->>'attempts')::int` bare (`0173:167`); this function does not.** A
--    poisoned `attempts` would raise inside a CLIENT read and paint a failure strip on a screen
--    whose booking is fine — the same class `0116 §C` fixed for the dispatcher, where one
--    unparseable row took the whole batch down. `_charge_int` (`0116:211-217`) is the raise-proof
--    reader the repo already has. ⚠ It cannot distinguish ABSENT from GARBAGE (both NULL), so a
--    `failed` row whose ladder count cannot be read is reported as `arrears` — the fail-LOUD
--    direction: 「a person must look」 rather than 「we are still trying」. A minted row always
--    carries `attempts` when it can fail at all (`0084:301-302` writes it whenever amount > 0), so
--    this arm only fires for a row no current writer produces.
-- ⓑ **The relink conjunct is checked BEFORE the cap.** `charge_row_due` requires BOTH; a relink
--    flag alone already means the ladder will never fire, whatever the count says, and the owner's
--    action differs (relink the card, not wait).
-- ⓑ-bis **THREE HELPERS THIS FUNCTION CALLS ARE REVOKED FROM `authenticated`** — `_charge_int`,
--    `_charge_bool` (`0116:285-287`) and `charge_max_attempts` (`0116:289`). That is fine and it
--    is also load-bearing: they are reachable only because this function is SECURITY DEFINER and
--    runs as its owner. A later 「simplify」 to SECURITY INVOKER does not merely widen a gate, it
--    makes the function raise `42501` for every caller. `0207-S1` pins `prosecdef`, and the
--    battery's `M7` measures exactly this. 🔴 **MEASURED, AND THE RESULT IS A NAMED LIMIT:**
--    planting `security invoker` reddens **`0207-S1` ALONE** (1437/1) and **no behavioural pin at
--    all** — because the harness calls this function as the SUPERUSER THAT OWNS the three helpers,
--    so the `42501` a real `authenticated` caller would meet is structurally unreachable here.
--    That is a fact about the harness, not a weak pin: `S1`'s `prosecdef` arm is the ONLY thing
--    standing between a 「simplify to invoker」 edit and a function that raises for every real
--    caller, and no fixture this repo can build would notice.
-- ⓒ **A `payments` row is read BEFORE the cutover pair.** A confirmed pilot-era row is money that
--    actually moved and stays `charged` whatever the flag says today. The flag decides whether new
--    charges are MINTED, not whether old ones happened. Widget-era debris cannot get in: it is
--    kind-less `pending`/`failed`, which the qualifying predicate in §A excludes.
--
-- ═══ §0d — BLAST RADIUS OUTSIDE THIS FILE, enumerated by hand ════════════════════════════════
-- New function, no existing caller, no existing behaviour changed. `payments_reconciliation`,
-- `sweep_settled_without_payments`, `mint_settle_charge_intent`, `dispatch_due_charges`,
-- `charge_row_due` and `_shared/ops.ts`'s `RECONCILIATION_ARM` map are all untouched. The client
-- half of the slice adds a wrapper and a pure module and leaves `fetchBookingPayments` exactly as
-- it is — the receipt LIST is still the rows; only the SENTENCE above it changes hands.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — `my_booking_payment_state` ═══════════════════════════════════════════════════════════
--
-- Party gate FIRST, then the state. The party is the **OWNER** and only the owner: a payment state
-- is the PAYER's fact. The runner's money view is `ledger_items` (`0071:31`), and `payments.raw`
-- carries the provider's response — masked card metadata and the payer's own details — which is
-- why `0071`'s single RLS policy is owner-only too. A runner therefore gets `not_party`, the same
-- word a stranger gets and the same word a non-existent booking gets, so the id is not an
-- existence oracle.
--
-- ⚠ EXACTLY ONE ROW, ALWAYS. Zero rows would re-create the ambiguity this whole file exists to
--   close — the caller would be back to reading an absence and guessing what it meant.
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
    -- ④ A ROW EXISTS — the state is that row's status. §0c ⓐ/ⓑ carry the two divergences.
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
      -- §0b. A status this file has never heard of gets an admission, never the nearest sentence.
      v_state := 'unknown';
    end if;
  else
    -- ⑤ NO QUALIFYING ROW — the answer is WHY there is none, and the ladder below walks arm
    --    eight's conjuncts outward-in so each state is the exact complement of the next.
    select f.payments_live_since into v_since from ops_flags f where f.id;
    select r.ended_at, coalesce(r.ended_at, now()), r.settled_at, r.end_reason::text, r.actual_km
      into v_ended_raw, v_ended, v_settled, v_end_rsn, v_km
      from runs r where r.booking_id = p_booking;

    if v_since is null or coalesce(v_ended, now()) < v_since then
      -- the mint's cutover pair, `0084:264-266`. Nothing will ever be minted for this booking.
      v_state := 'no_charge'; v_reason := 'not_charging';
    elsif v_settled is null or v_ended_raw is null then
      -- arm eight's anchor (`0173:204,206`). `v_ended_raw is null` keeps this function's
      -- settled-branch population EXACTLY arm eight's rather than a superset of it.
      v_state := 'awaiting_settlement';
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
-- produce, so the revoke is the guard and not the tidying.
revoke execute on function my_booking_payment_state(uuid) from public, anon;
grant  execute on function my_booking_payment_state(uuid) to authenticated;

comment on function my_booking_payment_state(uuid) is
  '0207: the OWNER''s payment state for one booking, named by the server rather than inferred from
a row count. Before this, app/app/owner/schedule.tsx read `payments` directly and rendered zero
rows as 「아직 청구 내역이 없어요」 — true of a booking still settling and FALSE of exactly the
population payments_reconciliation arm eight (0173) reports: settled, unpriceable or mint-raised,
an hour of five-minute sweeps and still no row. Party gate (owner only — a payment state is the
PAYER''s fact; the runner''s money view is ledger_items) runs BEFORE any read, and a foreign
booking, a non-existent booking and a runner all get the same `not_party`. Returns EXACTLY ONE
flat row, always: state · amount_won · charged_at · intent_at · reason. States, each derived from a
deployed predicate and none invented: no_charge (the mint''s cutover pair, 0084:264-266) ·
awaiting_settlement (arm eight''s anchor, 0173:204/206) · settling (inside arm eight''s 1h grace,
0173:207) · settled_without_payment (arm eight itself, with arm eight''s own reason case in its own
order) · charge_pending (0084:299) · charge_retrying (charge_row_due ⓐ, 0116:272-275) · arrears
(arm four 0173:162-167, or the relink conjunct 0116:274) · charged · waived (0080:147/161) ·
refunded (arm six''s two statuses) · unknown (the fail-closed arm for a status vocabulary widened
after this file — never the nearest sentence). 🔴 amount_won is NULL when there is no payments row:
0173:100-101 — nobody could price these, and a number here would be fabricated. THIS IS A READ: it
mints nothing, moves nothing, and changes no sweep. Pinned by 238 0207-P1…P7 · S1 · S2.';


-- ═══ VERIFY — the deployed ARTIFACT, read back from the catalog ═══════════════════════════════
-- House form. Every arm is an explicit boolean (`is not true` / `is distinct from`), never a bare
-- `IF` on a possibly-NULL predicate: every arm here exists to notice that something is MISSING,
-- and a NULL predicate makes a plpgsql `IF` silent — the exact collapse that killed five pins in
-- this repo in one afternoon.
do $$
declare
  v_oid     oid;
  v_src     text;
  v_secdef  boolean;
  v_path    boolean;
  v_pub     boolean;
  v_auth    boolean;
  v_gate    int;
  v_read    int;
  v_bad     text := '';
begin
  select p.oid, p.prosrc, p.prosecdef,
         coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
    into v_oid, v_src, v_secdef, v_path
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'my_booking_payment_state'
    and p.pronargs = 1;

  -- NO-FUNCTION / NO-SOURCE first: a NULL `prosrc` makes every `position()` below NULL, and a set
  -- of silent arms is precisely how a source check passes on a function that is not there at all.
  if v_oid is null then
    raise exception '0207 VERIFY FAILED: NO-FUNCTION(my_booking_payment_state/1)';
  end if;
  if v_src is null then
    raise exception '0207 VERIFY FAILED: NO-SOURCE(my_booking_payment_state) — prosrc is NULL, every source arm below would have been silent';
  end if;

  -- ⚠ COMMENTS STRIPPED BEFORE MATCHING, and it is load-bearing rather than tidy: `prosrc` is the
  -- body PLUS our own prose, and this function's prose NAMES every predicate it implements. Read
  -- un-stripped, a migration that DOCUMENTED the gate and failed to write it would satisfy every
  -- arm below — the instrument would reward the documentation as if it were the implementation.
  v_src := regexp_replace(v_src, '--[^\n]*', '', 'g');

  -- the party gate must PRECEDE the first read of payments/runs/ops_flags. Position, not presence.
  v_gate := position('not_party' in v_src);
  v_read := least(
    nullif(position('from payments p' in v_src), 0),
    nullif(position('from ops_flags f' in v_src), 0),
    nullif(position('from runs r' in v_src), 0));
  if (v_gate > 0) is not true then
    v_bad := v_bad || ' PARTY-GATE-ABSENT';
  elsif (v_read > 0) is not true then
    v_bad := v_bad || ' NO-READ-FOUND(the gate cannot be shown to precede a read that is not there)';
  elsif (v_gate < v_read) is not true then
    v_bad := v_bad || ' GATE-AFTER-READ(gate=' || v_gate || ' read=' || v_read || ')';
  end if;

  -- arm eight's three load-bearing strings, verbatim. If a later edit re-derives any of them this
  -- function stops answering the question the ops board answers, silently.
  if (v_src like '%(p.raw->>''kind'') is not null or p.status in (''confirmed'', ''waived'')%') is not true then
    v_bad := v_bad || ' QUALIFYING-PREDICATE-DIVERGED(0173:211)';
  end if;
  if (v_src like '%now() - interval ''1 hour''%') is not true then
    v_bad := v_bad || ' GRACE-MISSING(0173:207)';
  end if;
  if (v_src like '%payments_live_since%') is not true then
    v_bad := v_bad || ' CUTOVER-SCOPE-MISSING(0084:264)';
  end if;

  -- the two anchors 0116:47-52 refuses BY NAME, asserted in the positive direction so a NULL
  -- cannot make either arm silent.
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
    raise exception '0207 VERIFY FAILED:%', v_bad;
  end if;
end $$;
