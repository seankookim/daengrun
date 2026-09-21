-- ═══ 0193: the run-end ceremony's dead ends get an EXIT — a price the second stamp cannot ═══
-- ═══        skip, an ops door that can end a strand, and the 귀가 alarm made undisableable ═══
--
-- ═══ §0 WHAT THIS FILE IS — Codex REJECT/9 on 0188 · 0189 · 0190, corrected FORWARD ══════════
-- `docs/reviews/2026-09-22-0188-0189-0190-codex-verdict.md`. **0188, 0189 and 0190 are NOT edited**
-- (they landed at `e13c61a` / `e710ef1` / `ba18098`); 0083, 0089, 0096 and 0115 are not edited
-- either. Every function this file re-creates restates its own ACL here (the grant-preservation
-- class, `check-definer-acl.mjs`).
--
-- The five findings routed here, each with the sentence it is answering:
--
--   **A3** (high) `supabase/functions/transition-booking/confirm_return.ts:178-187` — 「the price
--     guard still trusts a stale pre-stop snapshot」. A confirm request can read `bk.run_ended_at`
--     as NULL and therefore obtain NO quote (there is no `runs.actual_km` yet to price from), the
--     stop commits, the counterparty stamps, and this request is then the SECOND stamp: 0096:159-166
--     seals and does not settle, because `p_quote` is null. The 503 that exists to prevent exactly
--     that state is conditioned on the same stale snapshot, so it cannot see the interleaving.
--     §B makes the SQL refuse (`quote_required`) and the edge re-price and retry once.
--
--   **A1** (high) `0188:278-299` — 「a missing second stamp blocks earnings indefinitely」. Arm ⓑ-②
--     correctly stops escalating a row a party has already confirmed, and 0188's own header names
--     the residue it creates: one notification at two hours, then permanent silence, `active`
--     forever, the runner work-gated (0092) and unpaid. The remedy 0096 §7 names — `force_return_tx`
--     — **has no caller anywhere** (measured again here: `grep -rn force_return_tx` over
--     `supabase/functions/`, `app/` and `scripts/` still returns only comment mentions). §C builds a
--     reachable, audited ops resolution; §D tells somebody about the strand in the first place.
--
--   **A2** (high) `0188:300-311` — 「the zero-stamp timeout destroys the normal settlement path」.
--     Arm ⓑ-① escalates `active → incident_review`; 0066:56 gives `incident_review` exactly one
--     edge (`refund_pending`) and `_settle_sealed_run` is `active`-only, so a run that was actually
--     performed becomes unpayable even after both parties stamp late (0096 lets the stamps LAND and
--     deliberately does not seal). §C's resolution is the adjudicated settlement path codex asked
--     for, and §C-b is the ONE transition-map edge that makes it possible.
--
--   **B5** (high) `0189:96-100` — 「the missing-dog escalation remains disableable」. 0188's
--     escalation writes 「귀가 확인이 필요해요」 as `kind='booking'`, and 0187's classifier files a
--     booking row as disableable, so `booking = false` silences the most safety-shaped sentence this
--     product sends. §D classifies it at the WRITER (`kind = 'safety'`) and §E adds the title to the
--     always-on family, so a row already written by a pre-0193 tick is covered too.
--
--   **C9** (medium) `0190:376-381` — 「previously retained bank details never reach cleanup」.
--     0190 §C releases a tombstoned runner's retained `bank_accounts` row at the moment their last
--     unpaid ledger row clears — but only from inside a NEW payout. A runner tombstoned and fully
--     paid BEFORE 0190 is reachable by nothing: 0115:227-234 short-circuits a deletion retry and
--     never reaches ④. §F is the guarded one-time cleanup.
--
-- ⚠ **C9 IS VACUOUS FOR THIS DEPLOYMENT, AND IT IS KEPT ANYWAY.** Production is at `0156`; the
--   `payouts` table had no writer at all until 0186 (0115:282 calls that 「the moment a payout
--   recorder appears」), so no runner has ever been 「fully paid」 and the predicate cannot match a
--   single row here. It ships because it is cheap, correct, and the ONE environment where it is not
--   vacuous is the one nobody is looking at — a rebuilt or lagging environment that upgrades past
--   0190 with rows already in that shape. It is a FUNCTION called once by this file rather than an
--   inline DO block, for a reason that is the house law rather than taste: a one-time inline block
--   has already run by the time any suite sees the database, so its property would be unpinnable and
--   its green would license nothing.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - **B8 is NOT built** and is recorded as a gap, not as an oversight. 「tombstoning does not
--   invalidate a push already queued in the same window」 (0189:185-195) is real: `net.http_post`
--   queues a payload carrying the token, and neither the deletion nor pg_net's dispatcher re-checks
--   the recipient. Closing it needs a recipient-aware OUTBOX with a dispatch-time re-read — a
--   different mechanism, not a conjunct — and it is its own slice in Sean's queue.
-- - **A4 · A6 · A7 are CLIENT findings** and are fixed in the same commit, in
--   `app/src/lib/notification-route.ts`, `app/app/runner/return-seal.tsx` and
--   `app/app/runner/done.tsx`. No SQL here depends on them and none of them depends on this file.
-- - It does not change what is EARNED or what is OWED. §C settles through `_settle_sealed_run` with
--   a price its caller computed, which is the same door and the same primitive the second stamp
--   uses; no money arithmetic is written or copied here.
-- - It does not re-open 0089's ruling that a PARTY may never force a return. §C is an OPS
--   adjudication and uses 0089's own marker — `return_forced_by = 'ops'` with both party stamp
--   columns LEFT AS THEY ARE — so a later reader can still tell 「nobody confirmed, ops resolved」
--   from 「both parties confirmed」. **No party's stamp is ever forged.**
-- - It does not pick the strand deadline. `ops_flags.return_strand_minutes` ships **NULL**, and NULL
--   means §D's arm does nothing at all. The NUMBER is Sean's (queue item 23).
-- - It does not touch the sealed-but-unsettled row (arm ⓐ's subject, suite 133's). That row needs a
--   pricing RE-DRIVE, which 0083 §0f already names as a pg_net dispatcher to an edge function with
--   its own contract. §C refuses it BY NAME (`already_sealed`) rather than half-handling it.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON ════════════════════════════════════════════════════════
-- Re-creates FOUR: `confirm_return_tx` (first defined 0083 §6-ⓓ, last declared **0096 §6** — 0188
-- only REVOKED it), `sweep_run_end_recovery` (0083 §9, last declared 0188 §A),
-- `enforce_booking_transition` (0001, last declared 0066 §1) and `_noti_urgent_noti_titles` (0189
-- §A). Creates THREE: `return_resolutions`, `ops_resolve_return_tx`, `_release_orphan_bank_rows`.
-- Adds ONE column: `ops_flags.return_strand_minutes`.
--
-- ⚠ **0188 DID NOT DECLARE `confirm_return_tx`'s BODY** — it revoked its grant. The body copied in
--   §B is **0096 §6's**, which is the latest declaration in the tree (`grep -n 'create or replace
--   function confirm_return_tx' supabase/migrations/*.sql` → 0083:952 and 0096:92, and nothing
--   after). Copying from 0188 would have copied nothing; copying from 0083 would have silently
--   deleted 0096's `incident_review` arm, which is the fix that keeps a runner from being
--   permanently gated. The catalog is not consulted here because no migration has patched this body
--   in place the way 0138 §F patched `delete_my_account_tx` — VERIFY asserts the deployed body
--   carries 0096's arm, so a surprise would abort the apply rather than land silently.
--
-- ═══ §0d DOCTRINE ═══════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated in THIS file ·
-- party gate before state gate, on the LOCKED row · `is not true` / `is distinct from`, never a bare
-- `IF` on a nullable predicate · comments stripped before every `prosrc` match · pins in
-- `224_ceremony_strand_resolution_suite.sql`.
--
-- ═══ §0e DEPLOY ═════════════════════════════════════════════════════════════════════════════
--   1. `supabase db push`            — this file. 0188/0189/0190 must already be applied.
--   2. `supabase functions deploy transition-booking`  — STRICTLY AFTER the push. The edge's new
--      `resolve_return` action calls a function that does not exist until step 1, and its
--      `quote_required` retry is dead code against a pre-0193 database (harmless, never taken).
--      The reverse order is the one that breaks: a deployed edge calling an absent RPC answers 409
--      with a raw SQL sentence.
--   3. **SEAN, ONE PRODUCTION WRITE, AND IT IS A DECISION NOT A CHORE:**
--          update ops_flags set return_strand_minutes = <minutes>, updated_at = now();
--      NULL (the shipped value) = §D's arm is inert and nobody is told about a strand. Any integer
--      arms it. Until this is set, A1's DETECTION half is off by design; the RESOLUTION half (§C)
--      works from the first minute, because it is reached by an operator rather than by a clock.
--   4. Also still open and NOT done by this file: `ops_recipients` needs at least one active
--      `return_strand` row, or §D delivers to nobody and §C's gate refuses everybody. Both are
--      honest failures — the sweep says 「0 recipient(s)」 in its notice and the RPC says `not_ops` —
--      and neither is silent.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A the two new nouns — the strand deadline, and the journal
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- A TIMESTAMP would have been wrong here and `payments_live_since` is why: 0080 §C chose a moment
-- over a boolean so a flip could not retroactively charge pilot-era runs. This flag has no
-- retroactivity to protect against — it is a DURATION, and the question it answers is 「how long may
-- a return stay unfinished before a human is told」. NULL is 「nobody is told」, which is the shipped
-- value and is not a placeholder: it is the only value that is honest before Sean has chosen one.
alter table ops_flags add column if not exists return_strand_minutes int;

comment on column ops_flags.return_strand_minutes is
  '0193 §A: minutes after `bookings.run_ended_at` at which an unfinished 1:1 return is reported to
the `return_strand` ops roster (sweep_run_end_recovery arm ⓕ). **NULL = the arm does nothing** —
the shipped value, because the number is Sean''s ruling (queue item 23) and a clock nobody chose is
worse than no clock. Not a moment (unlike payments_live_since, 0080 §C): there is no retroactive
charge to protect against, and the question is a duration. 224 0193-R4 pins both halves.';

-- ── the journal ───────────────────────────────────────────────────────────────────────────
-- SEALED the way `ops_recipients` and `ops_flags` are (68 V1's law): RLS on, ZERO policies, server
-- only. A row here says 「a human decided this return was finished without both parties saying so」,
-- which is an adjudication record: a client read is an operator's audit trail and a client write is
-- the forgery this whole file exists to make impossible.
-- ⚠ It is a SEPARATE TABLE rather than four more columns on `bookings` because the facts it records
--   are about the RESOLUTION, not about the booking: which of the two stamps was missing AT THE
--   MOMENT ops acted, and which state it was rescued from. `bookings` cannot carry those — the same
--   UPDATE that resolves the row destroys the state they describe.
create table if not exists return_resolutions (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid not null references bookings(id) on delete cascade,
  resolved_by    uuid not null references profiles(id),
  from_status    text not null,
  runner_stamped boolean not null,
  owner_stamped  boolean not null,
  memo           text not null,
  created_at     timestamptz not null default now()
);
create index if not exists return_resolutions_booking_idx on return_resolutions (booking_id, created_at desc);
alter table return_resolutions enable row level security;
revoke all on return_resolutions from public, anon, authenticated;

comment on table return_resolutions is
  '0193 §A (codex REJECT A1/A2): the ops adjudication journal for a stranded 1:1 return. One row per
`ops_resolve_return_tx` call: who decided, what they typed, which state the booking was rescued from
(`active` = a strand, `incident_review` = 0188 ⓑ-①''s zero-stamp timeout) and **which party stamps
existed at that moment** — the last two are why this is a table and not columns on `bookings`, since
the resolving UPDATE destroys exactly those facts. SEALED: RLS on, zero policies, no client grant.
0089''s rule is untouched — the party stamp columns are never written by ops, so 「nobody confirmed,
ops resolved」 stays distinguishable from 「both parties confirmed」.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B confirm_return_tx — a SERVER caller may not be the stamp that SEALS without a price
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Copied from **0096 §6** (the latest declaration — see §0c) with exactly one added gate.
--
-- 🔴 **WHY THIS IS NARROWER THAN THE RAISE 0188 §B ARGUED AGAINST, AND WHY THAT MATTERS.**
-- 0188's header refused 「raise when `v_both and v_may_settle and p_quote is null`」 on the grounds
-- that it would delete a DESIGNED capability: 0083 §6 says a client-class caller 「may seal — the
-- stamp is its own truthful act — and settlement then belongs to the server call that follows」, and
-- suites 133 · 119 R12/R16 exist to detect the row that leaves behind. That argument is correct and
-- this gate does not touch it, because it fires only for a caller with **NO IDENTITY OF ITS OWN**:
--
--     `quote_from_client` (0083, unchanged):  a caller WITH an identity may not bring a price.
--     `quote_required`    (0193, added):      then a caller WITHOUT one must.
--
-- The two halves are one sentence, and the second half was missing. Measured before writing: every
-- 「seal without a price」 fixture in the shipped suites sets `request.jwt.claim.sub` to a real party
-- first (119:485-487, 119:1144-1146, 133:115-117, 133:154-156, 132:112-135), i.e. all of them are
-- CLIENT-class and none of them reaches this branch. 119/132/133 are therefore not edited and stay
-- green for a TRUE reason, which is the only kind worth having — `0193-Q2` pins that capability
-- explicitly so the next session cannot mistake it for an accident.
--
-- ⚠ AND IT FIRES ONLY WHEN **THIS CALL WOULD SEAL**, never on a re-tap. `settlement_ready_at is
--   null` is a conjunct: a second call on a row that is already sealed writes nothing, settles
--   nothing and must keep answering idempotently, which is what the edge's retry depends on.
-- ⚠ `incident_review` is excluded for free, through `v_may_settle` — 0096 seals nothing there, so
--   there is no seal to refuse and a stamp from a case-review screen still lands.
create or replace function confirm_return_tx(
  p_booking uuid, p_side text, p_quote jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_both boolean; v_settled jsonb := null; v_stamped boolean := false;
  v_may_settle boolean;
  v_seals_now boolean;   -- [0193] would THIS call turn an unsealed row into a sealed one?
begin
  if p_side not in ('runner', 'owner') then raise exception 'bad_side'; end if;
  -- A caller with an identity of its own is a CLIENT, and a client must never hand us a price.
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- party gate before state gate (unchanged from 0083).
  if v_uid is not null then
    if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
    if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  -- club exclusion stays ABOVE the status gate — 119 R14 pins that a club booking answers
  -- `club_out_of_scope` and not a status error, and the ordering is what makes that true.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  -- idempotence before the state gate: a booking already settled answers "done", never an error.
  if b.status = 'completed' then
    return jsonb_build_object('stamped', false, 'settled', true, 'unchanged', true);
  end if;

  -- [0096 §2] ─── THE CHANGED GATE ────────────────────────────────────────────────────────
  -- `incident_review` is admitted so the parties can always say the dog is home. Everything
  -- else is still refused: a cancelled or refunding booking has no custody left to confirm.
  if b.status not in ('active', 'incident_review') then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;
  -- [0096 §3] money remains `active`-only. Computed BEFORE the stamp so the rule reads in one
  -- place, and fenced explicitly rather than left to `_settle_sealed_run`'s own raise — that
  -- raise would abort this transaction and take the stamp with it (0096 §3).
  v_may_settle := (b.status = 'active');

  -- [0193 §B, codex A3] ─── THE PRICE THE SEALING STAMP OWES ───────────────────────────────
  -- Decided on the LOCKED row, BEFORE anything is written, so a refusal costs a retry and never a
  -- half-written ceremony. `coalesce(..., false)` because every input is nullable and a bare `IF`
  -- on a NULL predicate is silent — which is precisely the shape this repo has lost pins to.
  -- ⚠ `v_uid is null` IS THE FIRST CONJUNCT AND IT IS THE WHOLE NARROWING. Without it this gate
  -- refuses a CLIENT-class second stamp too — which is 0083 §6's designed capability, the one 0188
  -- §B argued must survive, and the subject of suites 133 · 119 R12/R16 · 125 F4. Measured: an
  -- earlier draft of this file omitted it and the harness reddened `119 R15`, `119 R16` and
  -- `133 U2` — three shipped pins whose fixtures seal as a party, exactly as the product does not.
  v_seals_now := coalesce(
      v_uid is null
      and b.settlement_ready_at is null
      and v_may_settle
      and b.run_ended_at is not null
      and ((case when p_side = 'runner' then b.owner_confirmed_return_at
                 else b.runner_confirmed_return_at end) is not null
           or b.return_forced_by is not null), false);
  if v_seals_now and p_quote is null then
    -- The edge re-reads the booking under its CURRENT state, re-prices, and retries exactly once
    -- (`confirm_return.ts`). Nothing in this transaction has been written, so the retry is a fresh
    -- attempt rather than a repair.
    raise exception 'quote_required'
      using detail = 'the second stamp seals, and a seal with no price is a settlement nothing can re-drive (0083 §0f)';
  end if;

  -- ① the stamp (idempotent — a double tap is the same tap)
  if p_side = 'runner' and b.runner_confirmed_return_at is null then
    update bookings set runner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  elsif p_side = 'owner' and b.owner_confirmed_return_at is null then
    update bookings set owner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  end if;

  -- ② the seal — both stamps, or a force that already happened
  select (bk.runner_confirmed_return_at is not null and bk.owner_confirmed_return_at is not null)
         or bk.return_forced_by is not null
    into v_both
  from bookings bk where bk.id = p_booking;

  -- [0096 §2] the seal is part of the MONEY path, not the custody path: `settlement_ready_at`
  -- means "money may move". From `incident_review` money may not move, so nothing is sealed —
  -- which also keeps this row visible to `sweep_run_end_recovery`'s arm ⓑ semantics and out of
  -- arm ⓐ's sealed-but-unsettled alarm, and keeps 125 F4's DB-wide invariant intact
  -- (that invariant is about a seal without stamps; this writes stamps without a seal).
  if v_both and v_may_settle then
    if b.settlement_ready_at is null then
      update bookings set settlement_ready_at = v_now
       where id = p_booking and settlement_ready_at is null;
    end if;
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
  end if;

  return jsonb_build_object(
    'stamped', v_stamped,
    -- `sealed` reports the SEAL, not the pair. From `incident_review` both stamps can exist
    -- while nothing is sealed, and saying `sealed: true` there would tell a caller money is
    -- free to move when it is not. The pair is still observable via the two columns.
    'sealed', coalesce(v_both and v_may_settle, false),
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false),
    -- new, and the reason the call is worth making from a case-review screen: both parties have
    -- now said the dog is home, so the runner is no longer gated — even though the case is open.
    'both_confirmed', coalesce(v_both, false),
    'case_open', (b.status = 'incident_review'));
end $$;

-- 0096 §6's ACL restated, plus 0188 §B's revoke — a phone may not be the stamp that seals, and a
-- `create or replace` on a database where this function is absent is a plain CREATE that would be
-- born PUBLIC-executable (0116:636). 219 `0188-D1` pins both directions and is untouched by this
-- file; the three statements below are what keep it green.
revoke execute on function confirm_return_tx(uuid, text, jsonb) from public, anon;
revoke execute on function confirm_return_tx(uuid, text, jsonb) from authenticated;
grant  execute on function confirm_return_tx(uuid, text, jsonb) to service_role;

comment on function confirm_return_tx is
  '0096 §6 + [0193 §B]: 인계 확인. 0083/0096 그대로이고 게이트가 하나 늘었다 — **자기 신원이 없는
호출자(서버)가 봉인하는 스탬프가 되려면 가격을 들고 와야 한다** (`quote_required`).
0083의 `quote_from_client`(신원이 있는 호출자는 가격을 넘길 수 없다)와 한 문장의 나머지 반쪽이고,
빠져 있던 쪽이다. 코덱스 A3: 엣지가 정지 이전 스냅샷을 읽어 `run_ended_at`이 NULL이면 가격을 구하지
못하고, 그 사이 정지가 커밋되고 상대가 찍으면 이 요청이 **두 번째 스탬프**가 되어 0096:159-166이
정산 없이 봉인만 한다 — 그 상태는 앱에서 고칠 수 없다(두 스탬프가 다 있으니 모든 확인 CTA가 사라진다).
새 게이트는 **이 호출이 실제로 봉인을 만들 때에만**(settlement_ready_at is null ∧ active ∧ 상대 스탬프
존재) 발화하므로 재탭의 멱등성도, 0083 §6이 설계한 클라이언트의 「봉인만 하고 멈춘다」 능력도 그대로다
(133·119 R12/R16의 주제). incident_review에서는 애초에 봉인이 없어 해당 없음. 224 0193-Q1·Q2가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C-a enforce_booking_transition — ONE new edge, and it is an ops adjudication or nothing
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0066 §1's map, reproduced verbatim, with one disjunct added to a status that previously fell
-- through to the `else` arm. This is the edge codex A2 asks for: a run that was performed cannot be
-- left unpayable because a clock moved it somewhere `_settle_sealed_run` refuses to look.
--
-- 🔴 **WHY WIDENING THE MAP IS THE NARROW MOVE HERE.** The alternatives were worse in ways that are
-- checkable rather than aesthetic: loosening `_settle_sealed_run`'s `active`-only gate would widen
-- the MONEY primitive for every caller it has; writing a second settlement path would duplicate the
-- one thing 0083 §6 says must exist exactly once. This adds an edge that **only an ops adjudication
-- can take**, and leaves both of those untouched.
--
-- 🔴 **WHAT EACH CONJUNCT IS FOR — and the first one is a BELT, measured, not the load-bearing
-- guard.** A draft of this paragraph said 「a party CAN write `bookings.status` directly, because
-- 0057's policy admits a party UPDATE and `_guard_booking_cols` does not protect `status`」. That
-- was true of 0057 and **false since 0058 F3**, which promoted that guard from a column blacklist
-- to a DENY-ALL: `if current_user in ('authenticated','anon') and new is distinct from old then
-- raise 'booking_protected_columns'`. A party's direct UPDATE of a booking is refused outright,
-- before this trigger's map is consulted. Stated plainly rather than quietly dropped, because the
-- wrong version is exactly the premise a later session would build on.
--   · `current_user not in ('authenticated','anon')` — the SAME discriminator `_guard_booking_cols`
--     uses (0057 §4, 0058 F3), so this is a house idiom rather than an invention. Today it is a
--     BELT: the deny-all closes the client path first. It is worth its line because a map edge
--     outlives the guard in front of it — a future relaxation of that deny-all, or any definer that
--     forwards a caller's status, meets this conjunct instead of nothing.
--     ⚠ **NAMED GAP, and 224's header carries it too: this conjunct is not separately observable in
--     the harness.** A client-role UPDATE dies at the deny-all (so the refusal you measure is that
--     guard's name, not this one's) and every other harness caller is `postgres`, for whom the
--     conjunct is always true. It is pinned by SOURCE (`0193-S1`) and by this comment, and the
--     behavioural arm belongs to whoever relaxes 0058 F3.
--   · `new.return_forced_by = 'ops'` — the adjudication marker must be written by the SAME
--     statement, so the edge cannot be taken by a plain status update.
--   · `new.run_ended_at is not null` — only a run that actually ended can be resolved.
--   · `old.settlement_ready_at is null` — a sealed row is not in this class at all (§C refuses it).
-- ⚠ `coalesce(..., false)` wraps the disjunct because `new.return_forced_by = 'ops'` is NULL on a
--   row where that column is NULL, and `false or NULL` is NULL — which would make `ok` NULL, make
--   `if not ok` silent, and **allow every transition from `incident_review`**. The bare-IF collapse,
--   in the one place where it would have been a hole rather than a blind pin.
-- ⚠ `if ok is not true` replaces 0066's `if not ok` for the same reason. Behaviourally identical on
--   0066's map (`status` is NOT NULL, so `new.status in (...)` is never NULL); the change is that it
--   stays identical after somebody adds a nullable conjunct to this function, which is what just
--   happened.
create or replace function enforce_booking_transition() returns trigger
language plpgsql as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'          then new.status in ('quoted','expired')
    when 'quoted'         then new.status in ('payment_hold','expired')
    when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    when 'matching'       then new.status in ('runner_pending','confirmed','expired','refund_pending','cancelled_owner')
    when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')
    -- [R3] matching 추가 — 배정 철회/보호자 이의 (인계 전 한정, 클럽 RPC만 수행)
    when 'confirmed'      then new.status in ('matching','runner_enroute','picked_up','cancelled_owner','cancelled_runner','no_show')
    -- [0066] cancelled_owner added — owner cancel while the runner is en route (50% fee,
    -- runner compensation). picked_up below stays closed: past the handoff it's an incident.
    when 'runner_enroute' then new.status in ('picked_up','no_show','cancelled_runner','incident_review','cancelled_owner')
    when 'picked_up'      then new.status in ('active','incident_review')
    when 'active'         then new.status in ('completed','incident_review')
    when 'completed'      then new.status in ('incident_review')
    -- [0193 §C-a] incident_review → active, as an OPS RETURN ADJUDICATION and nothing else.
    -- Previously this status fell through to the `else` arm below and had exactly one exit
    -- (`refund_pending`), which is what made 0188 ⓑ-①'s zero-stamp escalation a money dead end for
    -- a run that was actually performed (codex A2). `refund_pending` is preserved EXACTLY; the
    -- second disjunct is reachable only from `ops_resolve_return_tx` (§C-b) — see the four
    -- conjuncts and why each one is load-bearing in the block comment above.
    when 'incident_review' then new.status in ('refund_pending')
      or coalesce(new.status = 'active'
                  and current_user not in ('authenticated', 'anon')
                  and new.return_forced_by = 'ops'
                  and new.run_ended_at is not null
                  and old.settlement_ready_at is null
                  and new.club_session_id is null, false)
    else new.status in ('refund_pending')
  end;
  if ok is not true then
    raise exception 'invalid booking transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;

comment on function enforce_booking_transition is
  '0066 map (base = 0047) + [0193 §C-a] incident_review → active as an ops return adjudication.
The new edge requires, in ONE statement: a non-client role (the 0057 §4 discriminator),
return_forced_by = ''ops'', run_ended_at set, the row not already sealed, and no club session —
so only `ops_resolve_return_tx` can take it and a party cannot walk their own case back out of
review. incident_review → refund_pending is unchanged. `if ok is not true` rather than `if not ok`:
the new disjunct is nullable and plpgsql does not take an IF on NULL, which would have allowed
EVERY transition instead of refusing one. 224 0193-R2·R3가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C-b ops_resolve_return_tx — the reachable, audited exit A1 and A2 both asked for
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The contract, in the order the body enforces it:
--   ① caller class — SERVER ONLY (`not_party`), 0089's rule for `force_return_tx` verbatim: an ops
--      override is a server-side act and a phone may not claim it. The edge authenticates the human
--      and passes their id; this function never trusts a client's claim about who it is.
--   ② the ops party gate on that id (`ops_actor_required` / `not_ops`) — BEFORE the lock and before
--      any row of anyone's booking is read, so a non-operator learns nothing, not even whether the
--      booking exists.
--   ③ argument sanity (`quote_required` / `memo_required`).
--   ④ LOCK the booking `for update`.
--   ⑤ state gates ON THE LOCKED ROW (`club_out_of_scope` · idempotent `completed` · `not_resolvable`
--      · `run_not_ended` · `already_sealed` · `both_confirmed`).
--   ⑥ the adjudication marker + the journal row, then settle through `_settle_sealed_run`.
--
-- 🔴 **WHY THE QUOTE IS REQUIRED RATHER THAN OPTIONAL, which 0089 left optional.** A resolution with
-- no price writes a seal and no settlement — the exact state this file's §B just closed one door to
-- and §0b refuses to half-handle. There is no caller that wants it: the edge prices this booking the
-- same way `confirm_return` does, from the frozen `runs` row, before it calls.
--
-- 🔴 **WHY NO PARTY STAMP IS EVER WRITTEN.** 0089's column comment is the ruling: 「an ops force is an
-- adjudication, not a confirmation: it sets settlement_ready_at and leaves BOTH party stamps NULL,
-- so a later reader can tell 'nobody confirmed, ops resolved' from 'both parties confirmed'」. This
-- function obeys it exactly — it records what was MISSING in `return_resolutions` and in the
-- evidence blob, and touches neither stamp column. A runner freed by this is freed because
-- `runner_work_gate` (0092) also clears on `completed`, never because someone typed their consent
-- for them.
--
-- ⚠ `p_actor` is a FOURTH parameter the routing note did not name, and it is not optional: the edge
--   runs as `service_role`, so `auth.uid()` inside this function is NULL and the ops roster cannot
--   be checked against 「the caller」 the way 0186 §C checks it. This is `confirm_return.ts` §1's own
--   shape — the server has already authenticated its user and passes the verified id — and the
--   function is granted to `service_role` alone precisely so that shape cannot be abused from a
--   phone.
create or replace function ops_resolve_return_tx(
  p_booking uuid, p_quote jsonb default null, p_memo text default null, p_actor uuid default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_ops_class constant text := 'return_strand';
  b record;
  v_uid     uuid := auth.uid();
  v_now     timestamptz := now();
  v_memo    text;
  v_from    text;
  v_settled jsonb := null;
  v_res     uuid;
begin
  -- ① SERVER ONLY (0089 §6's line, verbatim in substance).
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;
  -- ② THE OPS PARTY GATE, ahead of every state gate and ahead of the lock (0186 §C ①'s order and
  --    its membership test, reused rather than re-invented). `is not true`, so a NULL from any
  --    cause refuses instead of passing.
  if p_actor is null then raise exception 'ops_actor_required'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = p_actor)) is not true
  then raise exception 'not_ops'; end if;

  -- ③ arguments.
  if p_quote is null then raise exception 'quote_required'; end if;
  v_memo := nullif(btrim(coalesce(p_memo, '')), '');
  -- An adjudication with no sentence is just an assertion wearing a uniform (0089's words).
  if v_memo is null then raise exception 'memo_required'; end if;

  -- ④ THE LOCK.
  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ⑤ state gates on the LOCKED row. The club wall stays ABOVE the status gate, as 0096 §6 and
  --    0188 do, so a club booking is refused by its own name rather than by a status accident.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;
  if b.status = 'completed' then
    return jsonb_build_object('resolved', false, 'settled', true, 'unchanged', true);
  end if;
  -- The two states a STRAND can be in, and nothing else. `incident_review` is identified by the
  -- FACTS 0188 ⓑ-① leaves behind (a run that ended, no seal) and never by a free-text reason —
  -- a reason string is prose and this is a money gate.
  if b.status not in ('active', 'incident_review') then raise exception 'not_resolvable'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;
  -- A sealed row is arm ⓐ's subject and needs a pricing RE-DRIVE (0083 §0f), not an adjudication.
  -- Refused by name rather than half-handled — see §0b.
  if b.settlement_ready_at is not null then raise exception 'already_sealed'; end if;
  -- Both stamps present with no seal means `incident_review` with two late confirmations. The
  -- parties agree; there is nothing to adjudicate and nothing MISSING to record. That row is the
  -- other half of A2 and it is resolved the same way — through this door, because 0096 refuses to
  -- seal it — so it is deliberately NOT refused here. (Kept as an explicit note rather than a
  -- conjunct: the temptation to add `both_confirmed` as a refusal is exactly what would re-create
  -- codex's A2 for the case where both parties DID say the dog is home.)

  -- ⑥ THE ADJUDICATION. One UPDATE, because §C-a's trigger arm reads `new.return_forced_by` and
  --    `new.status` together: splitting it would refuse itself.
  v_from := b.status;
  update bookings
     set status                = 'active',
         return_forced_by      = 'ops',
         return_forced_at      = v_now,
         return_force_reason   = v_memo,
         return_force_evidence = jsonb_build_object(
           'source', 'ops_resolve_return_tx',
           'from_status', v_from,
           'runner_stamped', (b.runner_confirmed_return_at is not null),
           'owner_stamped',  (b.owner_confirmed_return_at is not null),
           'resolved_by', p_actor,
           'resolved_at', v_now),
         settlement_ready_at   = v_now
   where id = p_booking;

  insert into return_resolutions (booking_id, resolved_by, from_status,
                                  runner_stamped, owner_stamped, memo)
  values (p_booking, p_actor, v_from,
          (b.runner_confirmed_return_at is not null),
          (b.owner_confirmed_return_at is not null), v_memo)
  returning id into v_res;

  -- ⑦ SETTLE THROUGH THE SAME DOOR THE SECOND STAMP USES. `_settle_sealed_run` is THE settlement
  --    primitive (0083 §6) and re-reads the frozen measurement under its own lock; nothing about
  --    money is computed, copied or decided here. Collection is the edge's half, exactly as it is
  --    for `confirm_return` (`_shared/charge.ts` → `collectAfterSettle`), so the two doors cannot
  --    drift.
  v_settled := _settle_sealed_run(p_booking, p_quote);

  raise notice 'ops_resolve_return_tx: booking % resolved from % by % — runner_stamped=% owner_stamped=%',
    p_booking, v_from, p_actor,
    (b.runner_confirmed_return_at is not null), (b.owner_confirmed_return_at is not null);

  return jsonb_build_object(
    'resolved', true,
    'resolution_id', v_res,
    'from_status', v_from,
    'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false),
    'runner_stamped', (b.runner_confirmed_return_at is not null),
    'owner_stamped', (b.owner_confirmed_return_at is not null));
end $$;

revoke execute on function ops_resolve_return_tx(uuid, jsonb, text, uuid) from public, anon, authenticated;
grant  execute on function ops_resolve_return_tx(uuid, jsonb, text, uuid) to service_role;

comment on function ops_resolve_return_tx is
  '0193 §C-b (codex REJECT A1/A2): 좌초된 1:1 반환의 **도달 가능한** 출구. 0096 §7이 remedy로 이름을
댄 force_return_tx는 오늘까지 호출자가 0명이었고(측정), 그래서 「한쪽만 찍힌 채 영원히」도
「아무도 안 찍어 incident_review로 간 뒤 영원히」도 사람이 SQL을 직접 치는 것 말고는 빠져나갈 길이
없었다. 이 함수가 그 길이다: service_role 전용(0089의 규칙 — 운영 판정은 서버의 행위다), 엣지가
인증한 ops 담당자 id를 p_actor로 받아 `ops_recipients_for(''return_strand'')` 명부로 게이트하고(어떤
행도 읽기 전에), 예약 행을 잠그고, `active`(스탬프 2개 미만) 또는 `incident_review`(0188 ⓑ-①의 0스탬프
타임아웃 — 이유 문자열이 아니라 run_ended_at·seal 사실로 식별)만 받아, **당사자 스탬프는 절대 위조하지
않고** 0089의 마커(return_forced_by=''ops'')와 return_resolutions 저널로 「무엇이 빠진 채 해결됐는지」를
남긴 뒤, 두 번째 스탬프가 쓰는 바로 그 문(_settle_sealed_run)으로 정산한다. 가격은 선택이 아니라
필수다 — 가격 없는 해결은 정산 없는 봉인이고, 그건 이 파일이 §B에서 막은 바로 그 상태다.
이미 봉인된 행(arm ⓐ의 주제)은 already_sealed로 이름 붙여 거절한다: 그건 0083 §0f의 가격 재구동
슬라이스의 몫이다. 224 0193-R1·R2·R3가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D sweep_run_end_recovery — the escalation becomes SAFETY, and a strand is finally told
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0188 §A's body, reproduced with exactly TWO changes, each measured rather than asserted:
--   ⓑ-①'s two escalation inserts become `kind = 'safety'` (codex B5) — and nothing else about that
--      branch moves: same predicate, same titles, same two bodies, same one-shot, same UPDATE.
--   a NEW arm ⓕ is inserted BEFORE arm ⓒ, so 0188's own byte-identity measurement (「from the
--      literal line `  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED` up to `end $$;` → 14,650 bytes,
--      byte-for-byte equal to 0183」) is untouched and still re-runnable on this file.
-- Arms ⓐ · ⓑ-② · ⓒ · ⓓ · ⓔ are byte-identical to 0188. The copy was made by script from 0188's
-- text with each anchor asserted present exactly once and the RESULT asserted afterwards (five
-- row locks, five batch bounds, two safety inserts, zero `booking` escalation inserts, one
-- escalation statement, the job lock and ⓔ still present) — a hand copy of 450 lines is how a
-- comment-level difference becomes a behavioural one.
--
-- ⚠ THREE SHIPPED PIN ARMS COUNT THINGS THIS ARM CHANGES, and all three are updated in this slice
--   rather than left to fail for a true reason (the house law): 219 `0188-B4` and 214 `0183-E6`
--   each assert `for update skip locked` = 4 and `limit c_batch` = 4 — five arms write now — and
--   220 `0189-U2` asserts the urgent family holds exactly 3 titles (§E makes it 4). Each carries a
--   comment naming 0193 and the pin that owns the new property.
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0188] arm ⓑ-②'s one-shot alarm: a return ONE side has confirmed and the other has not.
  -- A DISTINCT title from the escalation's 「귀가 확인이 필요해요」 so neither dedupe key can
  -- silence the other, and so the client can route them apart. `notification-route.ts` routes it
  -- (runner → /runner/return-seal · owner → the bid-scoped report) and
  -- `app/test/notification-route.test.cjs` reads THIS constant out of THIS file, so the two
  -- spellings cannot drift (the c_esc_title idiom, 0182).
  c_ret_title     constant text := '반환 확인이 멈춰 있어요';
  -- to the side that has NOT stamped …
  c_ret_body_ask  constant text := '러닝이 끝났는데 반환 확인이 아직이에요 — 앱에서 인계를 확인해주세요';
  -- … and to the side that HAS. Never the first sentence: telling someone to confirm what they
  -- already confirmed is a lie about their own action (0092 §6).
  c_ret_body_wait constant text := '내 반환 확인은 끝났고 상대방 확인을 기다리고 있어요 — 확인되면 정산이 마무리돼요';
  -- [0181] arm ⓒ: how long a one-sided handoff may sit with no ask row before the sweep re-sends
  -- the ask, and how far an ask row may PRECEDE the stamp it answers (the edge stamps with its
  -- own clock, the row is stamped by the database's) and still count as that stamp's ask.
  ASK_AFTER constant interval := interval '5 minutes';
  -- the edge's exact strings (`transition-booking/index.ts`, case confirm_handoff): `push.ts`
  -- routes the runner by EXACT title, and the inbox must show one ask, not two spellings of it.
  c_ask_title constant text := '인계 확인 요청';
  c_ask_body  constant text := '상대방이 인계를 확인했어요 — 확인해주세요';
  -- [0182] arm ⓓ: how long a handoff may stay one-sided — ask delivered or not — before both
  -- parties and the ops roster are told ONCE for this cycle. 30 min: the re-send (arm ⓒ) lands
  -- 5–15 min after the stamp, so the re-sent ask has had at least 15 min to be answered.
  ESCALATE_AFTER constant interval := interval '30 minutes';
  c_esc_title constant text := '인계 확인이 멈춰 있어요';
  c_esc_body  constant text := '인계 확인이 한쪽만 된 채 30분이 지났어요 — 담당자가 확인하고 있어요';
  c_ops_class constant text := 'handoff_unanswered';
  -- [0182] the statuses in which a pickup handoff is NOT underway — the same fourteen arm ⓒ's
  -- candidate query names literally (212 C8 anchors on that literal); this constant is what the
  -- re-checks and arm ⓓ use, and VERIFY / 213 D7 assert the two spellings are identical.
  c_dead constant booking_status[] := array['draft','quoted','payment_hold','matching','runner_pending',
                                            'picked_up','active','completed',
                                            'cancelled_owner','cancelled_runner','expired','no_show',
                                            'incident_review','refund_pending']::booking_status[];
  -- [0182] rows served per tick per arm (ⓒ, ⓓ): every row lock these arms take is held to
  -- commit, and a counterparty's confirm (a plain UPDATE, no NOWAIT) waits behind it — so the
  -- number held is bounded, the arms are idempotent, and the rest wait for the next tick, ten
  -- minutes away (cold review 0182 #6; late_booking_sweep's `limit 5` is the precedent, 0126:61).
  c_batch constant int := 50;
  v_b record; v_cp uuid; v_st timestamptz; v_ops int;
  v_cid uuid;   -- [0183] the cycle the locked row is in, minted on the spot if it has none (legacy)
  -- [0193 §D] arm ⓕ. A DURATION read from `ops_flags` at the top of the arm, not a constant: the
  -- number is Sean's ruling (queue item 23) and NULL — the shipped value — means the arm does
  -- nothing at all. The ops class is its own, not `payout_due`'s: the people who can END a strand
  -- (`ops_resolve_return_tx` gates on exactly this roster) are the people who should be told.
  c_strand_ops_class constant text := 'return_strand';
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  -- NO id and NO amount in the body (0084 §E: a wrong recipient id pushes the body verbatim to a
  -- stranger's lock screen). The booking id rides in `ref_id`, as 0155/0166/0182 do.
  c_strand_body  constant text := '러닝이 끝났는데 반환 확인이 끝나지 않은 예약이 있어요. 예약을 확인해 주세요.';
  v_strand_min int;
begin
  -- [0181] ONE tick at a time (0117's job-lock idiom; 0177 gave owner-la the same): arm ⓐ's
  -- one-shot alarm and arm ⓒ's re-send are both read-then-write on `notifications`, and two
  -- overlapping ticks would each see no row and each insert (audit M10's class). A TRY-lock, so
  -- a slow predecessor is skipped and never queued; transaction-scoped, so any raise below
  -- releases it with no unlock to forget. `90_race_check.sh` RL measures the skip with two
  -- processes; 212 C8 sees the lock held after the call.
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice 'sweep_run_end_recovery: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- [0182] the bounded wait (0117 MINOR-14, 0180 §A's value): ⓒ/ⓓ never wait (skip locked), but
  -- arm ⓑ's UPDATE can, and a sweep stalled there holds every row lock ⓒ already took.
  perform set_config('lock_timeout', '2000', true);
  -- ⓐ report every sealed-but-unsettled row. The runner is owed money on a booking whose
  -- settlement died; SQL cannot price it (see the header), so the honest output is a visible
  -- notice per row and a count, not a silent zero.
  for r in
    select b.id, b.owner_id, b.runner_id, b.settlement_ready_at
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.settlement_ready_at is not null
  loop
    raise notice 'sweep_run_end_recovery: booking % is sealed but unsettled since % — settlement needs the pricing path (0083 §0f)',
      r.id, r.settlement_ready_at;
    n := n + 1;
    -- …and after SEAL_ALARM_AFTER, a notice in a cron log is not enough: tell both parties, once.
    -- This alarm deliberately does NOT move the status. The row stays `active`, which is the only
    -- state from which `_settle_sealed_run` can still pay the runner — escalating it to
    -- `incident_review` would trade a slow settlement for an impossible one (see the header).
    -- One-shot by construction: a title that exists for this booking is an alarm already raised.
    if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
       and not exists (select 1 from notifications nt
                       where nt.ref_id = r.id and nt.title = '정산을 확인하고 있어요') then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.owner_id, 'booking', '정산을 확인하고 있어요',
              '인계는 확인됐는데 정산이 마무리되지 않았어요 — 담당자가 확인하고 있어요', r.id);
      if r.runner_id is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.runner_id, 'booking', '정산을 확인하고 있어요',
                '인계는 확인됐는데 정산이 마무리되지 않았어요 — 지급은 취소되지 않아요, 담당자가 확인하고 있어요', r.id);
      end if;
    end if;
  end loop;

  -- ⓑ [0188] THE RUN-END STRAND — narrowed, because what this arm does to a row is a MONEY DEAD
  -- END and this slice is the first thing in the product that can put a row in front of it.
  --
  -- 0083 wrote this arm while `end_run_tx` had ZERO callers, so it has never escalated a real
  -- marketplace 귀가. The run-end ceremony (⑪/⑫) gives it rows for the first time, and the
  -- composition is a defect measured before it shipped:
  --   ① the runner stops (`end_run_tx`) and stamps their own return on R6a seconds later;
  --   ② the owner is slower than STRAND_AFTER — at work, phone silent; two hours is not long;
  --   ③ this arm moves the booking `active → incident_review`;
  --   ④ the owner stamps that evening. 0096 lets the stamp LAND and deliberately does not seal;
  --   ⑤ `_settle_sealed_run` requires `active` (0083 §6) and `enforce_booking_transition` gives
  --      `incident_review` exactly one edge — `refund_pending` (0066:56) — so the run can NEVER
  --      settle. The runner walked the dog, brought it home, BOTH parties said so, and the only
  --      state the money could have moved from is gone.
  -- 0083's own header already refused this shape for SEALED rows ("an owner who simply did not
  -- tap confirm within 2 hours able to render the runner permanently unpayable"). The UNSEALED
  -- row acquires the identical property the moment 0096 makes a late stamp possible — and 0096
  -- landed after 0083, so neither file could see it alone.
  --
  -- ⚠ AND THE ESCALATION BUYS NOTHING IT WAS BOUGHT FOR. Its stated purpose is that `active` is
  -- LIVE to the runner-accept conflict guard, "so the runner's future bookings are blocked by a
  -- dog they returned two days ago". Both halves are false today:
  --   · the block is ⑫'s WORK GATE (0092), which reads the two stamp columns and ALSO catches
  --     `incident_review` (`0092:112-117`) — escalating frees no runner. Pinned: 219 0188-B3.
  --   · the accept-time conflict guard (`transition-booking/index.ts`) compares SCHEDULED
  --     WINDOWS within ±6h, so a two-day-old booking overlaps nothing it could block. READ from
  --     that source, NOT pinned here — it is TypeScript and this is SQL, and per the house law
  --     neither is evidence for the other.
  --
  -- SO: this arm escalates only a return NOBODY has confirmed — zero stamps, which is the state
  -- `incident_review` actually names (the dog is unaccounted for). A row where at least one party
  -- has said the dog is home keeps `active`, and therefore keeps its money path, and is ALARMED
  -- instead: both parties told once, no status move. That is arm ⓓ's own principle, three arms
  -- down and written by a later author for the same class of stuck two-sided confirmation —
  -- "what a stuck pickup handoff should become is a product decision (Sean's), not a clock's".
  --
  -- ⚠ NAMED RESIDUE, deliberately NOT closed here, and stated in FULL because the first draft of
  -- this paragraph named only half of it (cold review #7):
  --   ① a return NOBODY confirms still escalates at STRAND_AFTER, and is still a dead end if both
  --      parties stamp afterwards;
  --   ② AND THE ONE-STAMP ROW THIS ARM NOW PRESERVES HAS ITS OWN NEW TERMINAL. Runner stamps,
  --      owner never does: one notification at 2h, then permanent silence, `active` forever, the
  --      runner work-gated (0092) and unpaid. That is strictly better than the escalation it
  --      replaces — the money path SURVIVES, so a stamp on any later day still settles — but it
  --      is not bounded, and the honest word for the detection is HALF: `ops_gated_runners()`
  --      (0096 §7) lists the row, and the remedy it names, `force_return_tx`, **HAS NO CALLER
  --      ANYWHERE** — measured: `grep -rn force_return_tx` over `supabase/functions/`, `app/` and
  --      `scripts/` returns only two comment mentions in a deno test. No edge action, no ops
  --      console, no client. The only exit is a human typing SQL.
  -- Both need the same decision, and it is Sean's rather than a clock's (awaiting-sean §4): what,
  -- if anything, may a timer do with money. What this arm guarantees is smaller and checkable:
  -- **a run where at least one party has said the dog is home is never made unpayable by a
  -- clock.** An escalating alarm (rather than the one-shot) and an ops door for
  -- `force_return_tx` are the two follow-ups this creates.
  --
  -- ⚠ LOCK, THEN LOOK AGAIN — arm ⓒ's idiom (codex 0181 #3), applied here because the branch is
  -- now destructive and the race lands exactly on the defect being closed: a stamp committing
  -- between the candidate read and the UPDATE would escalate a row that had just become
  -- settleable. `skip locked` leaves a row a writer holds for the next tick rather than stalling
  -- a sweep that holds every lock arm ⓒ took (0180's lesson).
  -- ⚠ [cold review #3] THE CANDIDATE SET MUST DRAIN, and this arm is the first in the function
  -- whose rows do NOT leave it. 0183's arm ⓑ had neither `order by` nor `limit`, and that was safe
  -- there because every candidate was escalated and left the set by changing status. A ⓑ-② row
  -- never leaves: status stays `active`, `run_ended_at` stays set, `settlement_ready_at` stays
  -- null, and the one-shot check makes it silent on every later tick. Adding `limit c_batch` to a
  -- non-draining set with `order by b.id` — a v4 uuid, so an ARBITRARY but STABLE order — would
  -- select the same fifty lowest-uuid corpses every tick forever, and a new zero-stamp row sorting
  -- above them would never be escalated at all. Two changes, and they are independent:
  --   · `order by b.run_ended_at` — OLDEST FIRST, a meaningful order, so nothing can be
  --     permanently shadowed by rows that merely have smaller ids;
  --   · the alarmed rows are excluded from the CANDIDATE, not just skipped in the loop, which
  --     restores the drain: a row that has had its one-shot alarm is done with this arm.
  -- The same `not exists` still guards the insert under the lock (a candidate read is a snapshot).
  for r in
    select b.id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
      and not exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_ret_title)
    order by b.run_ended_at
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
             b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: strand % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- Every predicate of the candidate query, re-asserted on the LOCKED row.
      -- ⚠ [cold review #8] `club_session_id` is in this list because the comment SAID "every"
      -- and the first version omitted it — and 219's `0188-B4` pins this re-check by matching
      -- this exact string, so the pin would have inherited the gap. No live path re-parents a
      -- booking into a club session, so this is a comment made true rather than a hole closed;
      -- that distinction is the finding, and it is worth the one conjunct.
      if v_b.status <> 'active' or v_b.run_ended_at is null or v_b.settlement_ready_at is not null
         or v_b.club_session_id is not null then continue; end if;
      if v_b.run_ended_at >= now() - STRAND_AFTER then continue; end if;

      if v_b.runner_confirmed_return_at is not null or v_b.owner_confirmed_return_at is not null then
        -- ⓑ-② ONE SIDE HAS SAID THE DOG IS HOME. No status move, ever. Both parties told ONCE —
        -- one-shot by construction (arm ⓐ's idiom): a row with this title for this booking is an
        -- alarm already raised. The two bodies are NOT interchangeable: telling a party who has
        -- already stamped to "확인해주세요" is a lie about their own action (0092 §6's rule for
        -- `waiting_on`, which exists for exactly this sentence).
        if not exists (select 1 from notifications nt
                       where nt.ref_id = v_b.id and nt.title = c_ret_title) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.owner_id, 'booking', c_ret_title,
                  case when v_b.owner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                  v_b.id);
          if v_b.runner_id is not null then
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_b.runner_id, 'booking', c_ret_title,
                    case when v_b.runner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                    v_b.id);
          end if;
          raise notice 'sweep_run_end_recovery: booking % — 반환 확인이 한쪽만 된 채 % 경과: 양측 1회 통지, 상태 무이동 (0188 ⓑ-②)',
            v_b.id, STRAND_AFTER;
          n := n + 1;
        end if;
      else
        -- ⓑ-① NOBODY has confirmed the return. This is the state `incident_review` names, and
        -- 0083's escalation is reproduced here verbatim — same UPDATE, same two titles, same
        -- two bodies. A human has to look, and `ops_gated_runners` (0096 §7) is where they look.
        update bookings set status = 'incident_review' where id = v_b.id and status = 'active';
        -- [0193 §D, codex B5] `safety`, NOT `booking`. 0187's classifier files a booking row as
        -- disableable, so with 예약 알림 off this push — 「the dog is unaccounted for」 — was
        -- silenced. Classified at the WRITER, which is what codex asked for; §E's title entry is
        -- the belt that covers rows a pre-0193 tick already wrote as `booking`.
        -- ⚠ 0114:273-281 admits only kind='booking' from a booking PARTY. This is a definer owned
        -- by postgres, so no policy applies and `safety` is writable here — which is exactly why
        -- the client writers (api.ts) were left alone in 0189 and are still left alone.
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                  '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', v_b.id);
        end if;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;
  -- ⓕ [0193] THE STRAND IS FINALLY TOLD TO SOMEBODY WHO CAN END IT (codex A1's detection half).
  --
  -- 0188 arm ⓑ-② is correct and it is not enough: it tells the two PARTIES once and then goes
  -- silent forever, and the parties are precisely the people who are already not acting. 0188's own
  -- header names the residue in full — 「one notification at 2h, then permanent silence, `active`
  -- forever, the runner work-gated (0092) and unpaid」 — and calls an ops door the follow-up it
  -- creates. This is that door's bell; `ops_resolve_return_tx` (§C-b) is the door.
  --
  -- 🔴 **NULL MEANS THE ARM DOES NOTHING, AND THAT IS THE SHIPPED STATE.** `return_strand_minutes`
  -- is Sean's ruling (queue item 23) and a deadline nobody chose is worse than no deadline: it
  -- would page an operator on a cadence invented by whoever typed the migration. Read fresh each
  -- tick so the flip needs no redeploy, and `is null` short-circuits before a single booking is
  -- read.
  --
  -- ⚠ TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
  -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and that row is the
  -- WORSE one (0096 lets late stamps land and refuses to seal, so it cannot settle at all until an
  -- operator acts). It is identified by the FACTS it carries — a run that ended, no seal — never by
  -- a free-text reason, because a reason string is prose and this is the input to a money door.
  --
  -- ⚠ ONCE PER BOOKING, by arm ⓐ/ⓑ's idiom: a row with this title for this booking is a bell
  -- already rung, and the candidate query excludes it so the set DRAINS (cold review 0188 #3's
  -- lesson: a `limit` over a non-draining set shadows new rows forever). An EMPTY ROSTER writes
  -- nothing, so the arm retries every tick until somebody is provisioned — the same durable-PENDING
  -- shape as ⓓ/ⓔ, and the honest one: an escalation recorded as delivered when nobody received it
  -- is worse than an unmonitored state (0096 §4).
  select f.return_strand_minutes into v_strand_min from ops_flags f where f.id;
  if v_strand_min is not null then
    for r in
      select b.id
      from bookings b
      where b.club_session_id is null
        and b.status in ('active', 'incident_review')
        and b.run_ended_at is not null
        and b.settlement_ready_at is null
        and not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null)
        and b.run_ended_at < now() - make_interval(mins => v_strand_min)
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.title = c_strand_title)
      order by b.run_ended_at
      limit c_batch
    loop
      begin
        select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
               b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
          into v_b from bookings b where b.id = r.id for update skip locked;
        if not found then
          raise notice 'sweep_run_end_recovery: strand-ops % — row locked by a writer, left for the next tick', r.id;
          continue;
        end if;
        -- every predicate of the candidate query, re-asserted on the LOCKED row (arm ⓑ's law)
        if v_b.club_session_id is not null or v_b.run_ended_at is null
           or v_b.settlement_ready_at is not null then continue; end if;
        if v_b.status not in ('active', 'incident_review') then continue; end if;
        if v_b.runner_confirmed_return_at is not null
           and v_b.owner_confirmed_return_at is not null then continue; end if;
        if v_b.run_ended_at >= now() - make_interval(mins => v_strand_min) then continue; end if;
        -- the candidate read was a snapshot; the one-shot guard is re-taken under the lock
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_strand_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_strand_title, c_strand_body, v_b.id
          from ops_recipients_for(c_strand_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — 반환이 %분 넘게 끝나지 않았다 (status=%, stamps=%/%): ops 수신자 %명 (%)',
          v_b.id, v_strand_min, v_b.status,
          (v_b.runner_confirmed_return_at is not null), (v_b.owner_confirmed_return_at is not null),
          v_ops,
          c_strand_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (다음 틱에 다시 시도)' else '' end;
        if v_ops > 0 then n := n + 1; end if;
      exception when others then
        raise notice 'sweep_run_end_recovery: strand-ops % — %', r.id, sqlerrm;
      end;
    end loop;
  end if;

  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED — backend audit M2's second half (the attack-INACTION one).
  -- `transition-booking`'s confirm_handoff stamps one side and then asks the OTHER side with a
  -- 「인계 확인 요청」 notification — the only thing in the product that asks. Since M2 a lost
  -- insert is a log line; nothing retried it, and no sweep looked for a handoff that was asked
  -- for and never answered because the ask never existed. This arm does: exactly one stamp set,
  -- the booking still able to reach `picked_up`, a runner to hand to, older than ASK_AFTER, and
  -- NO ask row for the counterparty created at or after that stamp (an earlier cycle's ask —
  -- stamps are reset on re-match, 0047:112 / index.ts:163 — does not count) ⇒ the ask is written
  -- ONCE, counted in the return, and named in a notice. The counterparty is the side that has
  -- NOT stamped: the party who stamped is never asked to confirm their own handoff.
  -- ⚠ STATUS IS A DENY-LIST, NOT AN ALLOW-LIST (the attack-INACTION law). A handoff is underway
  --   in exactly two statuses of 0066's map — `confirmed` and `runner_enroute`, the two from
  --   which `picked_up` is one edge away — and this arm names the OTHER fourteen rather than
  --   those two: before assignment there is no agreed handoff to confirm (a stamp there is a
  --   leftover; re-match resets it), after the pickup or in any end state there is nothing left
  --   to ask. So a status added to the enum lands in the sweep by default — re-sent, the failure
  --   this arm exists to close, and one spurious ask if it was in fact an end state (a wrong
  --   line in an inbox, visible) — and 212 C6 walks the enum so that new status reddens a pin
  --   until someone places it, instead of being decided by omission.
  -- ⚠ NO `club_session_id is null` here, unlike arms ⓐ/ⓑ. 0144:94 scoped THOSE for run-END
  --   reasons (a club run ends by the host's stop, not by `end_run_tx`). The PICKUP ask is the
  --   same edge action for both worlds — `club/session/[sid].tsx:665,708` call confirm_handoff
  --   exactly as `owner/meetup.tsx:252` does — so a club booking's lost ask is the same defect
  --   and is swept here; `runner_id is not null` already excludes an owner-handled club dog,
  --   which has no handoff to confirm.
  for r in
    select b.id, x.counterparty, x.stamped_at
    from bookings b
    -- the counterparty and the stamp are computed ONCE (lateral) and used by both the insert and
    -- the not-exists below — two copies of that `case` would be two places to drift (cold review)
    cross join lateral (
      select case when b.owner_confirmed_handoff_at is not null then b.runner_id else b.owner_id end as counterparty,
             coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) as stamped_at
    ) x
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and b.status not in ('draft', 'quoted', 'payment_hold', 'matching', 'runner_pending',        -- before assignment: no agreed handoff to confirm
                           'picked_up', 'active', 'completed',                                    -- past the pickup: nothing left to ask
                           'cancelled_owner', 'cancelled_runner', 'expired', 'no_show',          -- ended
                           'incident_review', 'refund_pending')
      and x.stamped_at < now() - ASK_AFTER
      -- ⚠ `nt.profile_id = x.counterparty` is load-bearing and easy to read as redundant: an ask
      --   row addressed to the OTHER party (the previous cycle's, inside the skew — re-match
      --   resets the stamps and leaves the row) must not silence this party's re-send. Measured
      --   by the cold review: without it the owner is NEVER asked in that shape. 212 C9 pins it.
      and not exists (
        select 1 from notifications nt
        where nt.ref_id = b.id
          and nt.title = c_ask_title
          and nt.profile_id = x.counterparty
          -- [0183] …and CARRYING THIS CYCLE'S IDENTITY. `handoff_cycle_id` is minted by the
          -- database (trigger _handoff_cycle) when a cycle starts — a first stamp, a runner change,
          -- a stamp reset — the edge writes it onto the ask it inserts, and `_notification_cycle_guard`
          -- refuses an ask whose id is not the booking's current one. A timestamp could not tell
          -- cycles apart (codex 0182 #1: a delayed old-cycle ask lands inside the new window); an
          -- id can. A row with no id (legacy) matches nothing here and is given one in the loop.
          and nt.handoff_cycle_id = b.handoff_cycle_id)
    order by b.id
    limit c_batch
  loop
    -- arm ⓑ's shape, for arm ⓑ's reason (0117:1222): one surprising row must not stop the sweep
    -- for every other. Measured — without this sub-block a single failing insert here rolled
    -- arm ⓑ's escalations back with it. Latent today (the runner conjunct and owner_id NOT NULL
    -- make the insert unable to fail), and that is one conjunct away from not latent.
    begin
      -- [0182] LOCK, THEN LOOK AGAIN (codex 0181 #3). The candidate query read a snapshot; a
      -- transition-booking write (the counterparty's confirm, a cancel, a re-match) can commit
      -- between that read and this insert, and the ask would then be obsolete — or addressed to
      -- the former runner. `for update skip locked`: a row a writer holds right now is left for
      -- the next tick (its outcome decides), never waited on (a sweep holding every dog lock it
      -- took must not stall — 0180's lesson). The row we DO get is re-evaluated on its locked,
      -- current version, and the insert happens while the lock is held, so no write can slip in.
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_cycle_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: ask % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      v_cp := case when v_b.owner_confirmed_handoff_at is not null then v_b.runner_id else v_b.owner_id end;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ASK_AFTER then continue; end if;
      -- [0183] THE LEGACY RULE, stated: a one-sided row with no cycle identity (it predates 0183 and
      -- the apply-time backfill somehow missed it, or a fixture) is given one by this touch — the
      -- trigger mints on any update of a stamped, id-less row — and every ask it already has
      -- (NULL id) cannot prove it belongs to this cycle, so the row is asked ONCE MORE: a
      -- duplicate push over a silent stall. The ask written below carries the id, so the next
      -- tick matches it.
      v_cid := v_b.handoff_cycle_id;
      if v_cid is null then
        update bookings set handoff_cycle_at = handoff_cycle_at where id = v_b.id returning handoff_cycle_id into v_cid;
        raise notice 'sweep_run_end_recovery: booking % had no handoff cycle identity — minted % (legacy row)', v_b.id, v_cid;
      end if;
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_ask_title and nt.profile_id = v_cp
                   and nt.handoff_cycle_id = v_cid) then
        continue;
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
      values (v_cp, 'booking', c_ask_title, c_ask_body, v_b.id, v_cid);
      raise notice 'sweep_run_end_recovery: booking % — 인계 확인 요청 re-sent to % (one-sided since %, no ask row this cycle)',
        v_b.id, v_cp, v_st;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: ask % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓓ [0182] THE DEADLINE (codex 0181 #2 — the attack-INACTION shape, again). After arm ⓒ's one
  -- re-send an unanswered handoff was excluded forever: arms ⓐ/ⓑ need run-end states, and
  -- `late_booking_sweep` is gated on `ops_flags.late_protocol_live_since` AND marketplace-only
  -- (0126:43,78-80). This arm is a bounded ONE-SHOT per cycle, for club and marketplace alike,
  -- reading no flag: ESCALATE_AFTER after the stamp, still one-sided, the parties are told (a
  -- `booking` row each — no '요청' in the title, so it routes to the report / calendar, never to
  -- a CTA that was already declined twice) and the ops roster is told (a redacted `system` row,
  -- 0155's shape; zero subscribers is the honest answer and is in the notice). NO status move —
  -- what a stuck pickup handoff should become is a product decision (Sean's), not a clock's.
  -- ONCE by a column, not by prose: `handoff_escalated_at` is the record and the dedupe key,
  -- reset by the cycle trigger so a NEW pairing can escalate again.
  for r in
    select b.id
    from bookings b
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
      and coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) < now() - ESCALATE_AFTER
      and b.handoff_escalated_at is null
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) or v_b.handoff_escalated_at is not null then continue; end if;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ESCALATE_AFTER then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_b.owner_id,  'booking', c_esc_title, c_esc_body, v_b.id),
             (v_b.runner_id, 'booking', c_esc_title, c_esc_body, v_b.id);
      -- the ops row carries NO identifier in its body (0084 §E: a wrong recipient id pushes a body
      -- verbatim to a stranger's lock screen); the booking id rides in ref_id, as 0155/0166 do.
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      -- [0183] TWO RECORDS, not one (codex 0182 #2): the parties' delivery is done here and once;
      -- the OPS delivery is recorded ONLY when a recipient actually got a row. An empty roster
      -- leaves `handoff_ops_alerted_at` NULL — a durable PENDING ops escalation that arm ⓔ retries
      -- every tick until somebody is provisioned, without telling the parties twice (0166's
      -- 「the stamp is conditioned on a delivery」 rule, applied to the half it fits).
      update bookings
         set handoff_escalated_at = now(),
             handoff_ops_alerted_at = case when v_ops > 0 then now() end
       where id = v_b.id;
      raise notice 'sweep_run_end_recovery: booking % — handoff one-sided since %, past %: both parties told, % ops recipient(s) for %',
        v_b.id, v_st, ESCALATE_AFTER, v_ops,
        c_ops_class || case when v_ops = 0 then ' — ops escalation PENDING until the roster is provisioned' else '' end;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: escalate % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓔ [0183] THE PENDING OPS ESCALATION (codex 0182 #2). Rows whose parties were told (ⓓ) while
  -- the ops roster was empty keep `handoff_ops_alerted_at` NULL; every tick tries the roster again
  -- for rows still one-sided and live, records the delivery only when a row was written, and never
  -- touches the parties. Locked and re-checked like ⓒ/ⓓ (cold review 0183 #6, measured: without
  -- the lock a confirm committing inside the loop still got ops paged about a handoff that had
  -- just finished — the row WAS escalated, but the page's whole content is 「still stuck」). The job
  -- lock serializes ticks. Bounded by `c_batch`; resets with the cycle (the trigger).
  for r in
    select b.id
    from bookings b
    where b.handoff_escalated_at is not null
      and b.handoff_ops_alerted_at is null
      and (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at, b.handoff_ops_alerted_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      if v_b.handoff_escalated_at is null or v_b.handoff_ops_alerted_at is not null then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then
        update bookings set handoff_ops_alerted_at = now() where id = v_b.id and handoff_ops_alerted_at is null;
        raise notice 'sweep_run_end_recovery: booking % — pending ops escalation delivered to % recipient(s)', v_b.id, v_ops;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: pending ops % — %', r.id, sqlerrm;
    end;
  end loop;

  return n;
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited. `create or replace` preserves an ACL only where the
-- function already exists; on an apply where it does not (a partial prior apply, a rebuilt
-- environment) this statement is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable
-- (0116:636). `check-definer-acl.mjs` exists for exactly this class and this file is its 82nd.
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant execute on function sweep_run_end_recovery() to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E the urgent title family gains the escalation (codex B5, the belt half)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D classifies 「귀가 확인이 필요해요」 at the WRITER, which is the load-bearing half and the one
-- codex asked for (「classify the actual custody-escalation payload as safety, preferably at its
-- writer」). This is the belt, and it covers what the writer cannot: **every row a pre-0193 tick has
-- already inserted as `kind='booking'`**, which will keep arriving in inboxes and keep being pushed
-- for as long as those rows exist. The classifier is consulted per push, not per insert, so a title
-- in this array rescues history as well as the future.
--
-- ⚠ THE FAMILY IS NO LONGER 「the three titles a CLIENT writes」, and the drift gate had to learn
--   that. `app/test/notification-prefs.test.cjs` compared this array against `ALWAYS_ON_TITLES` in
--   BOTH directions and asserted a length of exactly three — correct while every member was a
--   client writer, and a false failure the moment a SERVER-written title joined. The gate now reads
--   the LATEST migration that declares this function (not 0189 by name), splits the family into the
--   client writers and the server-written escalation (whose constant it reads from
--   `notification-route.ts`'s `RETURN_ESCALATION_TITLE`), and still refuses a widening in both
--   directions. Suite 220's `0189-U2` count arm moves 3 → 4 in the same slice, with the reason and
--   the new owner named there.
create or replace function _noti_urgent_noti_titles() returns text[]
language sql immutable as $$
  -- api.ts:3548 sendSOS (SOS_TITLE) · api.ts:3741 openBookingIncident (INCIDENT_NOTI_TITLE) ·
  -- api.ts:3811 notifyRunStop (RUN_STOP_TITLE). Exact equality only — see 0189 §0's 「도착」 note.
  -- [0193 §E] …and the ONE server-written member: 0188 arm ⓑ-①'s escalation, which says a dog is
  -- unaccounted for. Its writer now sends `kind='safety'` (§D) so new rows never need this entry;
  -- the entry is what covers rows already written as `booking`.
  select array['SOS', '사고 신고 접수', '러닝 중단 요청', '귀가 확인이 필요해요']::text[]
$$;

revoke execute on function _noti_urgent_noti_titles() from public, anon, authenticated;

comment on function _noti_urgent_noti_titles is
  '0189 §A + [0193 §E]: the titles that must push whatever a recipient has switched off. Three are
CLIENT writers (0114''s INSERT policy admits only kind=''booking'' from a party, so they arrive
disableable) and mirror SOS_TITLE / INCIDENT_NOTI_TITLE / RUN_STOP_TITLE in app/src/lib/api.ts. The
fourth, 「귀가 확인이 필요해요」, is SERVER-written — 0188 arm ⓑ-①''s zero-stamp escalation — and is
here as a belt for rows written before 0193 flipped its writer to kind=''safety''. Drift-pinned in
both directions by app/test/notification-prefs.test.cjs, which reads the LATEST declaring migration
rather than 0189 by name.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §F the pre-0190 orphan: a tombstoned, fully paid runner whose bank row nobody can reach
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- A FUNCTION called once below, not an inline block, and the reason is the house law rather than
-- style: a one-time DO block has already run by the time any suite connects, so no pin could ever
-- redden and its green would license nothing (「do not write a pin to document a limitation」). As a
-- function the property is falsifiable — 224 `0193-C9` builds the pre-upgrade shape and calls it.
--
-- 0190 §C's discipline, reused exactly:
--   · the PROFILE ROW LOCK before the tombstone is read — without it a concurrent
--     `delete_my_account_tx` and this sweep each read a true fact (「not a tombstone yet」 /
--     「still unpaid」) and the row is retained forever with neither side wrong.
--   · `is true` on both predicates, so a NULL from any cause KEEPS the row. The failure direction
--     here is 「retain something we could have released」, never 「release a destination still owed
--     money」 — a blanked row is one nobody can pay into (Sean 2026-08-20, A-intact-when-owed).
create or replace function _release_orphan_bank_rows() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; v_n int := 0; v_rel int;
begin
  for r in
    select ba.runner_id as runner
      from bank_accounts ba
      join profiles pr on pr.id = ba.runner_id
     where pr.deleted_at is not null
     order by ba.runner_id
  loop
    begin
      -- 0190 §C's serialisation: `delete_my_account_tx` UPDATEs `profiles` to set `deleted_at`
      -- (0115:418-424) BEFORE it reads the ledger for the retention decision (0115:566), so this
      -- lock is the other side of that pair. Nothing here row-locks `ledger_items`, so the two
      -- lock orders cannot cross and no deadlock cycle is created.
      perform 1 from profiles pr where pr.id = r.runner for update;
      if (select (pr.deleted_at is not null) from profiles pr where pr.id = r.runner) is not true
        then continue; end if;
      if (select not exists (select 1 from ledger_items l
                              where l.runner_id = r.runner and l.paid_payout_id is null)) is not true
        then continue; end if;
      delete from bank_accounts where runner_id = r.runner;
      get diagnostics v_rel = row_count;
      v_n := v_n + v_rel;
      raise notice '_release_orphan_bank_rows: tombstoned runner % has no unpaid ledger row — % retained bank row(s) released (0115 ④, run late)',
        r.runner, v_rel;
    exception when others then
      -- 0116 B3 / 0182's shape: one surprising row fails its own row and the sweep continues. This
      -- is NOT the swallow that hides 「the job was never installed」 — the count is returned and the
      -- caller below reports it.
      raise notice '_release_orphan_bank_rows: runner % — %', r.runner, sqlerrm;
    end;
  end loop;
  return v_n;
end $$;

revoke execute on function _release_orphan_bank_rows() from public, anon, authenticated;
grant  execute on function _release_orphan_bank_rows() to service_role;

comment on function _release_orphan_bank_rows is
  '0193 §F (codex REJECT C9): 0190 §C가 닿지 못하는 한 종류의 행을 해제한다 — **0190 이전에 탈퇴했고
이미 전액 지급된** 러너의 보관 계좌. 0190의 해제는 새 payout 안에서만 일어나고, 그런 러너에게는 새
payout이 없다; 탈퇴 재시도도 0115:227-234에서 조기 반환해 ④에 닿지 않는다. 즉 이 함수가 없으면 그
행은 영원히 남는다. 0190 §C와 같은 규율: 툼스톤 판독 **이전에** 프로필 행 잠금, 두 술어 모두 `is true`
(NULL이면 보관 유지 — 틀리는 방향은 「해제할 수 있었는데 보관」이지 「아직 빚진 입금처를 삭제」가 절대
아니다), 행 단위 예외는 배치를 멈추지 않는다. ⚠ 이 배포에서는 **공허하다**: 프로덕션은 0156이고
payouts에는 0186 전까지 기록자가 없었으므로 「전액 지급된」 러너가 한 명도 없다. 그래도 싣는 이유는
싸고 옳으며, 공허하지 않은 환경은 아무도 보고 있지 않은 환경이기 때문이다. 224 0193-C9가 핀.';

-- the one-time call. Its count is reported rather than swallowed; on this deployment it is 0 and
-- that zero is a measurement, not a hope.
do $$
declare v_n int;
begin
  select _release_orphan_bank_rows() into v_n;
  raise notice '0193 §F: one-time orphan bank-row release — % row(s)', v_n;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 224
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Apply-time source checks are protected exactly until somebody recreates the function (0131-G4's
-- lesson), so 224 owns the standing pins and this block owns 「the file that just ran did what it
-- says」. Comments are STRIPPED before every match: `prosrc` is source plus our own prose, and this
-- file documents every predicate it checks for — un-stripped, each check would be satisfied by the
-- paragraph explaining it, and the better the explanation the more surely.
do $$
declare v_src text; v_bad text := '';
begin
  -- ── §B confirm_return_tx ────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'confirm_return_tx';
  if v_src is null then raise exception '0193 VERIFY: NO-SOURCE(confirm_return_tx)'; end if;
  -- ⚠ MEASURED, AND IT CHANGED THIS ARM. The first version matched the STRINGS `quote_required`
  -- and `v_seals_now`, and a mutation that replaced the guard with `if false then` left BOTH in the
  -- body — a dead raise satisfies a check for its own name. The pattern was present in the guarded
  -- and the unguarded state alike, which is the uninformative-detector class, inside the block
  -- written to prevent it. Match the GUARD, not the vocabulary.
  if (v_src ~ 'if v_seals_now and p_quote is null then') is not true
    then v_bad := v_bad || ' confirm_return_tx: 가격 없는 봉인 가드가 없다;'; end if;
  if (v_src ~ 'raise exception ''quote_required''') is not true
    then v_bad := v_bad || ' confirm_return_tx: quote_required 거절이 없다;'; end if;
  if (v_src ~ 'v_seals_now := coalesce\(\s*v_uid is null') is not true
    then v_bad := v_bad || ' confirm_return_tx: 서버 한정 조건이 봉인 예측의 첫 조건이 아니다;'; end if;
  -- 0096's arm must have survived the copy — copying 0083's body instead would have deleted it
  -- silently and re-gated a runner forever (§0c).
  if (v_src ~ 'status not in \(''active'', ''incident_review''\)') is not true
    then v_bad := v_bad || ' confirm_return_tx: 0096의 incident_review 팔 유실;'; end if;
  if (v_src ~ 'quote_from_client') is not true then v_bad := v_bad || ' confirm_return_tx: quote_from_client 유실;'; end if;
  if has_function_privilege('authenticated', 'public.confirm_return_tx(uuid,text,jsonb)', 'execute')
    then v_bad := v_bad || ' confirm_return_tx: authenticated가 실행할 수 있다 (0188 §B 무효화);'; end if;
  if not has_function_privilege('service_role', 'public.confirm_return_tx(uuid,text,jsonb)', 'execute')
    then v_bad := v_bad || ' confirm_return_tx: service_role이 실행할 수 없다 (모든 정산 좌초);'; end if;

  -- ── §C-a the transition map ────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'enforce_booking_transition';
  if v_src is null then raise exception '0193 VERIFY: NO-SOURCE(enforce_booking_transition)'; end if;
  if (v_src ~ 'current_user not in \(''authenticated'', ''anon''\)') is not true
    then v_bad := v_bad || ' 전이맵: 클라 역할 판별 없음;'; end if;
  if (v_src ~ 'new\.return_forced_by = ''ops''') is not true
    then v_bad := v_bad || ' 전이맵: ops 마커 조건 없음;'; end if;
  if (v_src ~ 'ok is not true') is not true
    then v_bad := v_bad || ' 전이맵: NULL 붕괴 방어 없음;'; end if;
  if (select count(*) from regexp_matches(v_src, 'refund_pending', 'g')) < 4
    then v_bad := v_bad || ' 전이맵: 기존 refund_pending 출구가 줄었다;'; end if;

  -- ── §C-b ops_resolve_return_tx ─────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx';
  if v_src is null then raise exception '0193 VERIFY: NO-SOURCE(ops_resolve_return_tx)'; end if;
  -- the ops gate must PRECEDE the lock, which is what makes 「refused before any read」 true
  if not (position('ops_recipients_for(c_ops_class)' in v_src) > 0
          and position('ops_recipients_for(c_ops_class)' in v_src) < position('for update' in v_src))
    then v_bad := v_bad || ' 해결 RPC: ops 게이트가 잠금보다 뒤에 있다;'; end if;
  if (v_src ~ 'runner_confirmed_return_at = ') is true
    then v_bad := v_bad || ' 해결 RPC: 러너 스탬프를 위조한다;'; end if;
  if (v_src ~ 'owner_confirmed_return_at = ') is true
    then v_bad := v_bad || ' 해결 RPC: 보호자 스탬프를 위조한다;'; end if;
  if (v_src ~ '_settle_sealed_run') is not true
    then v_bad := v_bad || ' 해결 RPC: 정산 프리미티브를 쓰지 않는다;'; end if;
  if (v_src ~ 'insert into return_resolutions') is not true
    then v_bad := v_bad || ' 해결 RPC: 저널을 쓰지 않는다;'; end if;

  -- ── §D the sweep ───────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_src is null then raise exception '0193 VERIFY: NO-SOURCE(sweep_run_end_recovery)'; end if;
  -- B5: the escalation is written as safety, and there are exactly two of those inserts (owner +
  -- runner). Matching the CAST, not the word: 'safety' also names the c_safety constant.
  if (select count(*) from regexp_matches(v_src, '''safety''::noti_kind, ''귀가 확인이 필요해요''', 'g')) <> 2
    then v_bad := v_bad || ' 스윕: 귀가 승격이 safety로 쓰이지 않는다(2건이 아님);'; end if;
  if (select count(*) from regexp_matches(v_src, 'set status = ''incident_review''', 'g')) <> 1
    then v_bad := v_bad || ' 스윕: 0188의 승격 구문이 1개가 아니다;'; end if;
  -- A1's detection arm and its off switch
  if (v_src ~ 'return_strand_minutes') is not true then v_bad := v_bad || ' 스윕: 좌초 팔 없음;'; end if;
  if (v_src ~ 'c_strand_ops_class') is not true then v_bad := v_bad || ' 스윕: 좌초 ops 클래스 없음;'; end if;
  -- the four arms 0188/0183 own must still be in the body
  if (v_src ~ 'handoff_ops_alerted_at') is not true then v_bad := v_bad || ' 스윕: ⓔ 팔 유실;'; end if;
  if (v_src ~ 'pg_try_advisory_xact_lock') is not true then v_bad := v_bad || ' 스윕: 잡 락 유실;'; end if;
  if (select count(*) from regexp_matches(v_src, 'for update skip locked', 'g')) <> 5
    then v_bad := v_bad || ' 스윕: 행 락 수가 5가 아니다(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ);'; end if;
  if (v_src ~ '반환 확인이 멈춰 있어요') is not true then v_bad := v_bad || ' 스윕: ⓑ-② 알림 제목 유실;'; end if;

  -- ── §E the urgent family ───────────────────────────────────────────────────────────────
  if not ('귀가 확인이 필요해요' = any(_noti_urgent_noti_titles()))
    then v_bad := v_bad || ' 긴급 제목 목록에 귀가 승격이 없다;'; end if;
  if array_length(_noti_urgent_noti_titles(), 1) is distinct from 4
    then v_bad := v_bad || ' 긴급 제목 목록이 4개가 아니다;'; end if;
  if _noti_push_category('booking'::noti_kind, '귀가 확인이 필요해요') is distinct from 'safety'
    then v_bad := v_bad || ' 분류기가 귀가 승격을 safety로 보지 않는다;'; end if;

  -- ── the definers' own shape (98 H1 / check-definer-acl's class) ────────────────────────
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 해결 RPC: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute')
    then v_bad := v_bad || ' 해결 RPC가 authenticated에 열려 있다;'; end if;
  if not has_function_privilege('service_role', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute')
    then v_bad := v_bad || ' 해결 RPC를 service_role이 실행할 수 없다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = '_release_orphan_bank_rows'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 고아 계좌 해제: definer/search_path 형상 없음;'; end if;
  -- the journal is SEALED (RLS on, zero policies) — a policy here would be a client surface
  if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
    then v_bad := v_bad || ' return_resolutions에 RLS가 없다;'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
    then v_bad := v_bad || ' return_resolutions에 정책이 있다 (클라이언트 표면);'; end if;

  if v_bad <> '' then raise exception '0193 VERIFY failed:%', v_bad; end if;
end $$;
