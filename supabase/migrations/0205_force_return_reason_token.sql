-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0205 — force_return_tx stops writing free text into a party-readable column
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 236_force_return_reason_token_suite.sql (tag `frt`) — 0205-F1 · F2 · F3 · S1
--
-- ═══ §0a WHAT THIS FILE IS — 0201 §0b's NAMED BILL, PAID ═════════════════════════════════════
-- Codex's 2026-09-22 finding #1 (`docs/reviews/2026-09-22-post-reset-codex-verdict.md`) had a
-- SENTENCE — «an operator's private note must not land in a party-readable column» — and 0201 §A
-- fixed the one site the reviewer cited, `ops_resolve_return_tx`. 0201 §0b then enumerated the
-- OTHER site the same sentence covers, `force_return_tx` (`0089:132`, `return_force_reason =
-- p_reason`), and deliberately left it, writing down the bill: «**If that function ever gains a
-- caller, this is its bill.**»
--
-- This file pays it early, and the reason is the house law it would otherwise sit on the wrong
-- side of: **a finding's SENTENCE is the property; the site the reviewer cited is one place that
-- property happens to be observable.** 0201's three reasons for waiting were all true and none of
-- them was 「the column is safe」 — they were 「nobody writes to it yet」. `authenticated` holds
-- table-level SELECT on `bookings` and `bookings party read` (`0002:92`) scopes it to the two
-- parties, so whatever `force_return_tx` puts in `return_force_reason` is one PostgREST call away
-- from both of them, today, for any row it has ever touched. A guard that depends on nobody
-- calling the function is a guard that arms itself the day somebody does — and 0198's ops console
-- is exactly the kind of slice that grows one.
--
-- 🔴 **ZERO CALLERS, RE-MEASURED ON THIS TREE AND STATED AS A NUMBER, NOT AS A MEMORY.**
--   `grep -rn force_return_tx app supabase/functions scripts` → **4 raw hits, 0 executable**:
--     · `supabase/functions/transition-booking/index.ts:477`     — comment («the remedy 0096 §7
--       named (`force_return_tx`) has never had a caller. This is the caller.» — about
--       `resolve_return`, which calls `ops_resolve_return_tx`, not this function)
--     · `supabase/functions/transition-booking/resolve_return.ts:10` — comment
--     · `supabase/functions/_test/settle_charge_test.ts:965` and `:1170`  — comments
--   `app/` → **0 hits of any kind.** The only executable callers anywhere are SQL: `119`, `125`
--   and `132`'s pins, and `232`'s M2 fixture.
--   ⚠ Counted the way §comment-quoting requires — the raw count is 4 and the executable count is
--   0, and the difference is entirely comments that NAME the function while describing something
--   else. A bare `grep -c` here answers 「is the word present」, which was never the question.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   · §A — `return_resolutions` (0193 §A) admits a SECOND ROW KIND. It could not before: its
--     `resolved_by` is `not null references profiles(id)` and `force_return_tx` has no actor
--     profile BY CONSTRUCTION (it refuses any caller with an `auth.uid()`, `0089:99`), so the
--     journal as shipped structurally cannot hold a force. A `source` discriminator plus a CHECK
--     that ties each source to its actor shape is the minimum that admits the path **without**
--     dissolving the invariant the resolver's rows still carry.
--   · §B — `force_return_tx` re-declared from 0089 §6, its LATEST declaration, with exactly TWO
--     behavioural changes: `return_force_reason` receives the fixed token `ops_forced`, and the
--     caller's free-text `p_reason` is journalled in `return_resolutions` instead. Every gate,
--     every refusal name, the response shape, `_settle_sealed_run`, first-writer-wins and 0089's
--     rule that NO party stamp is ever forged are 0089's, unchanged and copied BY SCRIPT.
--   · §C — `_scrub_ops_return_reasons` (0201 §B) learns the discriminator. This is not optional
--     and not tidying: that repair identifies its targets by 「has a `return_resolutions` row」,
--     and 0201's own comment says force rows are outside the set **BY CONSTRUCTION** because they
--     write no journal row. §B makes them write one. Un-taught, the scrub would relabel a force's
--     `ops_forced` as `ops_resolved:strand` — turning a psql adjudication into a resolver rescue
--     in the record a dispute reads. **Widening what a table can contain is a change to every
--     reader of that table, even the readers this file does not otherwise touch** (the §④ law).
--   · §D — the two comments that would otherwise contradict the code: the column's and the
--     table's.
--
-- ═══ §0c WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
-- - **0201, 0199, 0193, 0096, 0089 and 0083 are NOT edited.** They landed. 0201 §0b's paragraph
--   saying `force_return_tx` is left alone stays exactly as written — it was true of its own tree
--   and the house law is that a landed migration is a record, not a draft. This header is where
--   the reader finds out it was paid.
-- - **`return_force_evidence` is enumerated and LEFT, with 0201 §0b's argument and one addition.**
--   `force_return_tx` requires it (`evidence_required`) and it is the dispute record 0083 §1 built
--   this schema around; stripping it would delete the adjudication's justification, which is worse
--   than the leak. ⚠ **The addition, stated rather than hidden:** unlike the resolver's, whose
--   evidence is assembled SERVER-side (`jsonb_build_object('source', …)`), a force's evidence is
--   free-form jsonb chosen by the caller, so an operator who types prose into it puts prose in a
--   party-readable column through a door this file does not close. That is a REAL residual and it
--   is not pinned, because a pin over 「the caller chose good jsonb」 would be a pin over the
--   caller. The honest shape of the constraint is: the reason field is now structurally safe; the
--   evidence field is safe by operator discipline. **If `force_return_tx` gains a product caller,
--   that caller owes a server-composed evidence object** — the same bill, one column over.
-- - It does not widen `my_return_resolution` (0199 §A) and it does not narrow it either — see the
--   named consequence in §A. No client build, no edge deploy, no cron, no enum, no policy.
-- - It does not touch `ops_resolve_return_tx`, `sweep_run_end_recovery`, `confirm_return_tx`,
--   `_settle_sealed_run`, any money arithmetic, or `be/0203`/`be/0204`'s surfaces.
--
-- ═══ §0d WHOSE OBJECTS THIS BUILDS ON ════════════════════════════════════════════════════════
-- Re-declares TWO: `force_return_tx` (last declared 0089 §6) and `_scrub_ops_return_reasons`
-- (last declared 0201 §B). Alters ONE table: `return_resolutions` (0193 §A) — one column, two
-- constraints, one NOT NULL dropped. Creates nothing. Adds no enum, no policy, no trigger.
--
-- ⚠ **`force_return_tx`'s BODY WAS COPIED BY SCRIPT FROM 0089's TEXT, NOT BY HAND** — 0193 §D's
--   and 0201 §A's discipline, for their reason: a hand copy of ~90 lines is how a comment-level
--   difference becomes a behavioural one. Each of the three anchors was asserted present EXACTLY
--   ONCE before the edit, and the generator refuses to write the file otherwise.
--
-- ═══ §0e DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated in THIS file ·
-- party/ops gate before any read on the LOCKED row (0089's, untouched) · `is distinct from` /
-- `is not true`, never a bare `IF` on a nullable predicate · comments stripped before every
-- `prosrc` match · pins in `236_force_return_reason_token_suite.sql`.
--
-- ═══ §0f THREE SHIPPED PINS MOVE, AND THEY MOVE FOR A TRUE REASON ════════════════════════════
-- All three asserted the defect, correctly, as of the day they were written. The house law is to
-- update the pin, say WHY, and name the pin that owns the new property:
--   · `119:704` (`R6`) — 「the second force did not overwrite the first REASON」. The reason is now
--     a constant, so comparing it to the first call's free text measured nothing about
--     immutability once both calls write the same token. Rewritten to assert the token in the
--     column AND that the JOURNAL still holds the FIRST call's text and exactly one row — which
--     is where immutability is now observable at all. `0205-F2` owns the property.
--   · `119:776` (`R17`) — the same comparison on the re-entry branch. Same repair, same reason.
--   · `232:339-382` (`0201-M2` arm ⓒ) — 「a `force_return_tx` row has free text and NO journal
--     row, and the scrub leaves it」. Two of those three clauses are now false by design. The arm
--     keeps its JOB — it is the arm that separates 「scrubbed 0193's copies」 from 「overwrote every
--     ops reason」 — and gets its discriminator from `source` instead of from absence. `0205-F3`
--     owns the new property and is the pin that would have caught §C being forgotten.
-- 232's header NAMED GAP («force_return_tx writes free text to the same party-readable column and
-- 0201 deliberately leaves it») is rewritten in the same slice. A stale gap note is a document
-- manufacturing a false green: the next session reads it, runs the suite, and learns the wrong
-- thing about which of the two is out of date.
--
-- ═══ §0g DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   1. `supabase db push` — this file. 0193 and 0201 must already be applied.
--   2. Nothing else. No `functions deploy`, no cron, no secret, no client build. The function has
--      no caller to redeploy, which is the whole reason this could be paid cheaply.
--   ⚠ On production (at `0156` when 0201 was written; 0193/0199/0201 not yet applied) §A's ALTERs
--     run against a table with zero rows, so the backfill of `source` is vacuous and measured as
--     such rather than hoped. Nothing here rewrites an existing `return_force_reason`: §C's scrub
--     is not called by this file, because the rows it repairs are 0193's and 0201 already ran it.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A return_resolutions admits a SECOND ROW KIND — and keeps the first kind's invariant
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0193 §A's journal was built for exactly one writer, and its column comment says so. Two of its
-- constraints encode that writer's shape rather than the journal's purpose:
--   · `resolved_by uuid not null references profiles(id)` — an ops PROFILE, because
--     `ops_resolve_return_tx` takes `p_actor` and checks it against the roster.
--   · nothing distinguishes one writer from another, because there was only one.
-- `force_return_tx` has no profile to record and cannot acquire one: `0089:99` refuses any caller
-- carrying an `auth.uid()` at all («ops is a server-side override; a phone cannot claim it»), so
-- a force is a shell and a service-role connection. **Making `resolved_by` simply nullable would
-- admit the force AND quietly delete the resolver's invariant** — every later resolver row could
-- then be written with a NULL actor and nothing would notice. The CHECK below is what keeps the
-- two facts separate: each source is tied to the actor shape it actually has.
--
-- ⚠ **A NAMED, DELIBERATE CONSEQUENCE, because it is a party-facing read.** `my_return_resolution`
--   (0199 §A) returns the LATEST journal row for a booking to either party — `created_at`,
--   `from_status`, and a FIXED Korean sentence chosen server-side from `from_status`. It is not
--   edited here, so from this file onward a party whose return was forced by ops can also read
--   「운영팀이 귀가를 확인 처리했어요」. That is **true** (`return_forced_by = 'ops'`, an
--   adjudication) and it is the same sentence, from the same `case`, with the memo still absent —
--   the three columns that leave that function do not include `memo` and do not include
--   `resolved_by`. Widening it is the honest direction: the alternative is a party whose return
--   was resolved by a human at a shell being told nothing at all, which is the shape this whole
--   ceremony exists to stop. Recorded here rather than left for a reader to discover, because
--   «the caller of a widened return is inside the slice's blast radius even when the slice does
--   not touch it» is this repo's §④ law and a party-readable sentence is the costliest kind.
--   `0205-F1` pins that what the party can read is the token and the fixed sentence, never the
--   operator's text.
alter table return_resolutions
  add column if not exists source text not null default 'ops_resolve_return_tx';

-- The value set is CLOSED and named, so a third writer has to arrive through a migration rather
-- than through a typo. Dropped-then-added so a re-apply onto a database that already has it lands
-- on the same definition rather than erroring.
alter table return_resolutions drop constraint if exists return_resolutions_source_check;
alter table return_resolutions add constraint return_resolutions_source_check
  check (source in ('ops_resolve_return_tx', 'force_return_tx'));

-- `resolved_by` stops being NOT NULL at the column level and becomes NOT NULL at the SOURCE level.
-- Note the second arm is an equality, not a permission: a force row must have NO actor, because
-- 0089 guarantees there is none and a row claiming one would be a fabricated actor in an
-- adjudication journal — the worst thing this table could hold.
alter table return_resolutions alter column resolved_by drop not null;
alter table return_resolutions drop constraint if exists return_resolutions_actor_check;
alter table return_resolutions add constraint return_resolutions_actor_check
  check ((source = 'ops_resolve_return_tx' and resolved_by is not null)
      or (source = 'force_return_tx'       and resolved_by is null));

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B force_return_tx — the token in the column, the operator's sentence in the journal
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0089 §6's body, copied BY SCRIPT, with exactly TWO behavioural changes:
--   ① `return_force_reason = v_token` where it used to be `= p_reason`
--   ② one `insert into return_resolutions`, on the first-force path only, carrying `p_reason`
-- Everything else is 0089's: the `force_party_forbidden` refusal by name, `bad_side`,
-- `quote_from_client`, `evidence_required`, `reason_required`, the `for update` read, the
-- server-only caller gate, `club_out_of_scope`, the `completed` early return, `not_active`,
-- `run_not_ended`, first-writer-wins with its `eligible_at` shape-compatibility echo, the refusal
-- to write `return_eligible_at`, 🔴 the refusal to write EITHER party's confirmation stamp, the
-- `_settle_sealed_run` call and the response shape.
--
-- 🔴 **WHY A TOKEN AND NOT A KOREAN SENTENCE** — 0201 §A's argument, which applies unchanged:
-- `return_force_reason` is not display vocabulary and must not become it (`grep -rn
-- return_force_reason app/` is **0**, and the standing STATUS_MAP law says a client gates on raw
-- server words and never prints them). The one sentence a party is shown is 0199's `note_public`,
-- chosen server-side. A second Korean sentence here would be product copy nobody wrote, reviewed
-- or translated, sitting in the column a party reads directly.
--
-- ⚠ **WHY A SINGLE CONSTANT AND NOT A `case` LIKE THE RESOLVER'S.** 0201 §A's token is three-armed
-- because its gate admits two rescued-from states (`active`, `incident_review`) and a third could
-- be added. `force_return_tx` admits exactly ONE: `0089:113` raises `not_active` on anything but
-- `active`, and the `completed` row returns early without writing. A `case` here would have one
-- reachable arm and two arms that exist to look thorough — which is how a reader later concludes
-- the column can carry values it cannot. The journal's `from_status` records the state anyway, so
-- nothing is lost: the token says WHICH DOOR, and the journal says FROM WHAT.
--
-- ⚠ **AND THE TOKEN IS A DIFFERENT WORD FROM THE RESOLVER'S ON PURPOSE.** `ops_forced` and
-- `ops_resolved:*` are two different acts — a shell override with operator-supplied evidence, and
-- a rostered operator going through the product's own door with a roster check, a memo and a
-- journalled actor. Collapsing them to one token would make the column cheaper to read and would
-- destroy the one distinction `bookings.return_forced_by`'s own comment (0089 §5) says this row
-- exists to preserve: that a later reader can tell WHO resolved it and HOW.
create or replace function force_return_tx(
  p_booking  uuid,
  p_side     text,
  p_reason   text,
  p_evidence jsonb,
  p_quote    jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_settled jsonb;
  -- [0205 §B] the fixed token. ONE value, not a `case`: this door admits exactly one
  -- rescued-from state (`not_active` refuses the rest, and a `completed` row returns
  -- early without writing), so extra arms would only teach a later reader that the
  -- column can carry values it cannot. The journal's `from_status` records the state.
  v_token constant text := 'ops_forced';
begin
  -- [0089 §2] ops only. `runner`/`owner` are refused BY NAME rather than by falling through to a
  -- generic bad-input error: the caller is asking for something the product used to allow, and
  -- the honest answer names the rule rather than pretending the value was never understood.
  if p_side = 'runner' or p_side = 'owner' then
    raise exception 'force_party_forbidden'
      using detail = '인계 확인은 양측이 함께 해야 해요 — 한 쪽만으로는 확정할 수 없어요';
  end if;
  if p_side <> 'ops' then raise exception 'bad_side'; end if;
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;
  -- An adjudication with no evidence is just an assertion wearing a uniform.
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then
    raise exception 'evidence_required';
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason_required'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by, bk.return_eligible_at
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ops is a server-side override; a phone cannot claim it. (Unchanged from 0083.)
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  if b.status = 'completed' then
    return jsonb_build_object('forced', false, 'settled', true, 'unchanged', true);
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;

  -- First-writer-wins, and `settled` is never claimed unless the primitive actually ran
  -- (0083's fix, preserved).
  if b.return_forced_by is not null then
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
    return jsonb_build_object(
      -- `eligible_at` is echoed for shape-compatibility with 0083's response and is NULL from
      -- 0089 onward (see the update below). Dropping the key silently would have been an
      -- undocumented change to a contract inside a file whose thesis is "the record is what a
      -- dispute reads" — flagged on review, restored rather than removed.
      'forced', false, 'forced_by', b.return_forced_by,
      'eligible_at', b.return_eligible_at, 'sealed', true,
      'settled', coalesce((v_settled->>'settled')::boolean, false),
      'unchanged', coalesce((v_settled->>'unchanged')::boolean, true));
  end if;

  update bookings set
      return_forced_by      = 'ops',
      return_forced_at      = v_now,
      -- 🔴 [0205 §B] THE TOKEN, not `p_reason`. `authenticated` holds table SELECT on
      -- `bookings` and `bookings party read` (0002:92) scopes it to the two parties, so an
      -- operator's sentence written here is read by both of them (codex 2026-09-22 #1,
      -- whose sentence covered this site as well as the resolver 0201 §A fixed). The
      -- sentence is still REQUIRED (`reason_required`, above) — it now lands in the sealed
      -- `return_resolutions` journal instead, below.
      return_force_reason   = v_token,
      return_force_evidence = p_evidence,
      -- [0089, corrected on review] `return_eligible_at` is NOT written. With the party path
      -- gone there is no waiting period for anyone, so the column would always equal
      -- `run_ended_at` — a cache of something derivable, which 0083 §1 explicitly forbids of
      -- this schema ("never a cache of anything derivable"). The concept retired with the
      -- grace; the column stays only because rows written before 0089 could carry it (there are
      -- none — §5). Leaving it NULL is what makes "no grace exists" readable in the data.
      -- 🔴 [0089 §2] NO party stamp is written. 0083 wrote the forcing side's own confirmation
      -- and called it "implied by the act". Under the ruling it is implied by nothing: an
      -- adjudication resolves a return, it does not confirm one. Both stamps stay as they were.
      settlement_ready_at   = coalesce(b.settlement_ready_at, v_now)
  where id = p_booking;

  -- [0205 §B] THE JOURNAL. Reached only on the first-force path — the re-entry branch above
  -- returns before this, so a second force writes no second row and the FIRST operator's
  -- sentence is what stands. That is where this function's immutability is observable at
  -- all now: the column holds a constant, so comparing two calls' column values can no
  -- longer tell 「the second force was refused」 from 「the second force overwrote with the
  -- same word」.
  -- `b` was read BEFORE the UPDATE, so the two stamp booleans are the state ops actually
  -- adjudicated — the same fact 0193 §A built this table to hold, and the same fact the
  -- resolving UPDATE destroys.
  -- `resolved_by` is NULL and the table's CHECK requires it to be: 0089 refuses any caller
  -- carrying an `auth.uid()`, so there is no profile to record and a row claiming one would
  -- be a fabricated actor in an adjudication journal.
  insert into return_resolutions (booking_id, resolved_by, from_status,
                                  runner_stamped, owner_stamped, memo, source)
  values (p_booking, null, b.status,
          (b.runner_confirmed_return_at is not null),
          (b.owner_confirmed_return_at is not null), p_reason, 'force_return_tx');

  if p_quote is not null then
    v_settled := _settle_sealed_run(p_booking, p_quote);
  end if;

  return jsonb_build_object(
    'forced', true, 'forced_by', 'ops', 'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false));
end $$;

-- ACL restated in THIS file, never inherited. `create or replace` preserves an ACL only where the
-- function already exists; on a partial prior apply or a rebuilt environment this statement is a
-- plain CREATE and a new function is born PUBLIC-executable (0116:636). A SECURITY DEFINER that
-- seals a return and releases money is the worst shape this repo can produce, so the revoke is the
-- guard and not the tidying — and it is BYTE-FOR-BYTE 0089's, including `authenticated`, which
-- 0089 §2 moved this function out of and 219's `0188-D1` pins from the other side.
revoke execute on function force_return_tx(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
grant  execute on function force_return_tx(uuid, text, text, jsonb, jsonb) to service_role;

comment on function force_return_tx is
  '0089, amended by 0205 — OPS-ONLY adjudication of a stuck return, from a shell. A party (runner or
owner) is refused by name with force_party_forbidden: Sean 2026-08-13, "the confirmation must happen
with both parties and never just the runner". Writes NO party confirmation stamp — settlement_ready_at
only — so the row distinguishes "ops resolved" from "both confirmed".
🔴 **0205: the caller''s free-text p_reason no longer reaches bookings.return_force_reason.** That
column is party-readable (authenticated holds table SELECT on bookings; 0002:92 scopes it to the two
parties), so an operator''s sentence written there is read by both of them — codex 2026-09-22 #1,
whose sentence covered this site as well as the resolver 0201 §A fixed. The column now receives the
fixed token ''ops_forced'' and the reason is journalled in return_resolutions (source =
''force_return_tx'', resolved_by NULL — this caller has no profile by construction). reason_required
still holds: the sentence is still mandatory, it just lands where only the server can read it.
⚠ return_force_evidence is UNCHANGED and is still party-readable free-form jsonb — enumerated and
left (0205 §0c), and the residual an operator can still create by typing prose into it. 236
0205-F1·F2·S1 pin this.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C _scrub_ops_return_reasons — the discriminator, because §B just broke its premise
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0201 §B's body with exactly ONE added conjunct, and it is load-bearing rather than defensive.
--
-- 🔴 **WHAT CHANGED UNDER IT.** 0201's own comment states the repair's targeting argument:
-- «`force_return_tx`'s rows write no journal row and are therefore outside the set BY CONSTRUCTION
-- rather than by a filter someone has to remember.» §B makes that sentence false. Left alone, the
-- scrub would find a force's journal row, compute `case from_status when 'active' then
-- 'ops_resolved:strand'`, see that `ops_forced` differs from it, and OVERWRITE — relabelling a
-- shell adjudication as a resolver rescue in the record 0083 §1 built for disputes. Not a leak; a
-- FALSIFICATION, which is worse in the artifact a dispute is read from.
--
-- ⚠ This is the §④ law arriving in its own slice rather than a later one: widening what a table can
-- contain changes every reader of that table, and the reader here is one this file would otherwise
-- have no reason to open. The generalisation worth keeping is that «outside the set BY
-- CONSTRUCTION» is a claim about the WORLD, not about the query — and the day the world gains a
-- row kind, the query that relied on it is wrong with nothing to show for it.
--
-- ⚠ The conjunct sits inside the subselect, on `return_resolutions` itself, rather than on the
-- outer UPDATE: `distinct on (r.booking_id) … order by r.booking_id, r.created_at desc` picks the
-- LATEST row per booking, so filtering after the pick would let a later force row HIDE an earlier
-- resolver row that still needs repair. Filter first, then pick. (0201's note about `distinct on`
-- over a one-to-many join is exactly why this ordering matters and it is now reachable: a booking
-- genuinely can hold two journal rows of different kinds.)
create or replace function _scrub_ops_return_reasons() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int := 0;
begin
  update bookings b
     set return_force_reason = x.token
    from (
      select distinct on (r.booking_id)
             r.booking_id,
             case r.from_status
               when 'active'          then 'ops_resolved:strand'
               when 'incident_review' then 'ops_resolved:review'
               else                        'ops_resolved'
             end as token
        from return_resolutions r
       where r.source = 'ops_resolve_return_tx'
       order by r.booking_id, r.created_at desc
    ) x
   where x.booking_id = b.id
     and b.return_forced_by = 'ops'
     and b.return_force_reason is distinct from x.token;
  get diagnostics v_n = row_count;
  raise notice '_scrub_ops_return_reasons: % booking(s) had a 0193-written ops memo in return_force_reason; replaced with the rescued-from token (the journal keeps the memo)', v_n;
  return v_n;
end $$;

revoke execute on function _scrub_ops_return_reasons() from public, anon, authenticated;
grant  execute on function _scrub_ops_return_reasons() to service_role;

comment on function _scrub_ops_return_reasons is
  '0201 §B, amended by 0205 §C: 0193이 이미 bookings.return_force_reason에 복사해 둔 운영 메모를
0201 §A의 고정 토큰으로 덮는다. 대상은 **저널 조인**으로 식별한다 — 그리고 0205부터 그 조인만으로는
부족하다. 0201의 근거는 「force_return_tx는 저널 행을 쓰지 않으므로 구조적으로 이 집합 밖」이었는데,
0205 §B가 바로 그 문장을 거짓으로 만들었다(강제도 이제 저널을 쓴다 — source=''force_return_tx'').
그래서 부분질의에 source 조건이 붙는다: 붙이지 않으면 강제 행의 ''ops_forced''가 ''ops_resolved:strand''로
덮여, 셸 판정이 해결기 구조로 **기록상** 둔갑한다. 조건은 부분질의 안(고르기 전)에 있다 — distinct on이
예약당 최신 행을 고르므로, 고른 뒤에 걸면 나중에 생긴 강제 행이 아직 고쳐야 할 해결기 행을 가린다.
마지막 조건은 쓰려는 값 자체와 비교하므로 멱등이다. 저널의 memo는 건드리지 않는다. 232 0201-M2와
236 0205-F3이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D the two comments that would otherwise contradict the code
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0201 §A amended the column's comment to say 「TWO WRITERS, TWO REGISTERS」 and named
-- `force_return_tx` as the one that still writes free text. It no longer does. A column comment
-- that is true of one writer and false of another is, in 0201's own words, «how the next session
-- writes a memo back into it in good faith» — and a comment left stale by the very file that
-- falsified it is that failure with a shorter fuse.
comment on column bookings.return_force_reason is
  '0083 §1, amended by 0201 §A and 0205 §B — the recorded reason for a return force. ⚠ TWO WRITERS,
and as of 0205 BOTH write a FIXED TOKEN and NEITHER writes free text. `ops_resolve_return_tx`
(0193 §C-b, re-declared 0201 §A) writes `ops_resolved:strand` | `ops_resolved:review` |
`ops_resolved`, keyed by the rescued-from state. `force_return_tx` (0089 §6, re-declared 0205 §B)
writes `ops_forced` — one value, because that door admits exactly one state (`not_active` refuses
the rest). The two words are deliberately different: a rostered operator through the product''s own
door is not the same act as a shell override, and 0089 §5 says this row exists so a later reader can
tell those apart. **Neither writer''s operator text is here.** Both land in the sealed
`return_resolutions` journal (0193 §A) — the resolver''s `memo`, the force''s `p_reason` — because
`authenticated` holds table SELECT on `bookings` and `0002:92` scopes it to the two parties, so
anything written here is read by both of them (codex 2026-09-22 #1). The one sentence a party is
shown is `my_return_resolution.note_public` (0199 §A). Recorded immutably either way — neither
writer overwrites an existing force. 232 0201-M1 and 236 0205-F1 pin it.';

comment on table return_resolutions is
  '0193 §A (codex REJECT A1/A2), amended by 0205 §A: the ops adjudication journal for a stranded 1:1
return. **TWO ROW KINDS since 0205, told apart by `source`.**
  · `ops_resolve_return_tx` — the product''s own door. `resolved_by` is the rostered operator''s
    profile and is REQUIRED (the CHECK, not the column, now carries that).
  · `force_return_tx` — 0089''s shell override. `resolved_by` is NULL and is REQUIRED to be, because
    that function refuses any caller carrying an `auth.uid()` (0089:99): there is no profile to
    record, and a row claiming one would be a fabricated actor in an adjudication journal.
Either kind records who decided (or that nobody could be named), what they typed, which state the
booking was rescued from (`active` = a strand, `incident_review` = 0188 ⓑ-①''s zero-stamp timeout)
and **which party stamps existed at that moment** — the last two are why this is a table and not
columns on `bookings`, since the resolving UPDATE destroys exactly those facts. SEALED: RLS on, zero
policies, no client grant. 0089''s rule is untouched — the party stamp columns are never written by
ops, so 「nobody confirmed, ops resolved」 stays distinguishable from 「both parties confirmed」.
⚠ `_scrub_ops_return_reasons` (0201 §B, 0205 §C) reads this table and MUST filter on `source`: it
was written when there was one writer. 236 0205-F2·F3 pin both halves.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 236
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Apply-time source checks are protected exactly until somebody recreates the function (0131-G4's
-- lesson), so 236 owns the standing pins and this block owns 「the file that just ran did what it
-- says」. Comments are STRIPPED before every match: `prosrc` is source plus our own prose, and this
-- file explains every predicate it checks for — un-stripped, each arm would be satisfied by the
-- paragraph explaining it, and the better the explanation the more surely.
do $$
declare v_src text; v_bad text := ''; v_n int;
begin
  -- ── §B the force ───────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'force_return_tx';
  if v_src is null then raise exception '0205 VERIFY: NO-SOURCE(force_return_tx)'; end if;
  -- the ASSIGNMENT, not the word: a check for `v_token` alone would be satisfied by a declaration
  -- that nothing uses, and a check for `return_force_reason` alone is satisfied by both worlds.
  if (v_src ~ 'return_force_reason\s*=\s*v_token') is not true
    then v_bad := v_bad || ' 강제: 판정 사유 칸에 고정 토큰을 쓰지 않는다;'; end if;
  if (v_src ~ 'return_force_reason\s*=\s*p_reason') is not false
    then v_bad := v_bad || ' 🔴 강제: 호출자 free text가 당사자가 읽는 칸에 다시 실린다;'; end if;
  -- …and the reason must STILL reach the journal. A fix that simply dropped p_reason would pass
  -- the two arms above and destroy the adjudication's only justification.
  if (v_src ~ 'insert into return_resolutions') is not true
    then v_bad := v_bad || ' 강제: 저널을 쓰지 않는다;'; end if;
  if (v_src ~ '\mp_reason\M') is not true
    then v_bad := v_bad || ' 강제: 사유가 본문에서 사라졌다 (감사 기록이 빈다);'; end if;
  if (v_src ~ 'raise exception ''reason_required''') is not true
    then v_bad := v_bad || ' 강제: reason_required 거절이 없다;'; end if;
  -- 0089's invariants, re-asserted because this file re-declared the function
  if (v_src ~ 'raise exception ''force_party_forbidden''') is not true
    then v_bad := v_bad || ' 강제: 당사자 거절이 사라졌다 (2026-08-13 판단);'; end if;
  if (v_src ~ 'runner_confirmed_return_at\s*=') is true
    then v_bad := v_bad || ' 강제: 러너 스탬프를 위조한다;'; end if;
  if (v_src ~ 'owner_confirmed_return_at\s*=') is true
    then v_bad := v_bad || ' 강제: 보호자 스탬프를 위조한다;'; end if;
  if (v_src ~ 'return_eligible_at\s*=') is true
    then v_bad := v_bad || ' 강제: 파생 캐시를 다시 쓴다 (0089의 정정 되돌림);'; end if;
  if (v_src ~ '_settle_sealed_run') is not true
    then v_bad := v_bad || ' 강제: 정산 프리미티브를 쓰지 않는다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'force_return_tx'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 강제: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
    then v_bad := v_bad || ' 강제가 authenticated에 열려 있다 (0089 §2 위반);'; end if;
  if not has_function_privilege('service_role', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
    then v_bad := v_bad || ' 강제를 service_role이 실행할 수 없다;'; end if;

  -- ── §C the scrub ───────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_scrub_ops_return_reasons';
  if v_src is null then raise exception '0205 VERIFY: NO-SOURCE(_scrub_ops_return_reasons)'; end if;
  if (v_src ~ 'from return_resolutions') is not true
    then v_bad := v_bad || ' 스크럽: 저널 조인이 없다;'; end if;
  if (v_src ~ 'r\.source\s*=\s*''ops_resolve_return_tx''') is not true
    then v_bad := v_bad || ' 🔴 스크럽: source 판별자가 없다 (강제 행의 토큰을 덮어쓴다);'; end if;
  if (v_src ~ 'return_forced_by = ''ops''') is not true
    then v_bad := v_bad || ' 스크럽: ops 마커 조건이 없다;'; end if;

  -- ── §A the table ───────────────────────────────────────────────────────────────────────
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'return_resolutions'
                    and column_name = 'source' and is_nullable = 'NO')
    then v_bad := v_bad || ' 저널: source 칸이 없거나 NULL 허용이다;'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'return_resolutions'
                    and column_name = 'resolved_by' and is_nullable = 'YES')
    then v_bad := v_bad || ' 저널: resolved_by의 NOT NULL이 풀리지 않았다 (강제가 행을 쓸 수 없다);'; end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_actor_check')
    then v_bad := v_bad || ' 저널: 행위자 CHECK이 없다 (해결기의 불변식이 사라졌다);'; end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_source_check')
    then v_bad := v_bad || ' 저널: source 값 CHECK이 없다;'; end if;
  -- the journal stays SEALED — this file added a column, not a door
  if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
    then v_bad := v_bad || ' 저널에 RLS가 없다;'; end if;
  if has_table_privilege('authenticated', 'public.return_resolutions', 'select')
    then v_bad := v_bad || ' 저널이 authenticated에 열려 있다;'; end if;
  -- the backfill is a MEASUREMENT, not a hope: every pre-existing row is the resolver's.
  select count(*) into v_n from return_resolutions where source is distinct from 'ops_resolve_return_tx';
  if v_n <> 0 then v_bad := v_bad || ' 저널: 기존 행 중 ' || v_n || '건이 해결기 행이 아니다;'; end if;
  raise notice '0205 §A: return_resolutions backfilled — % pre-existing row(s), all source=ops_resolve_return_tx',
    (select count(*) from return_resolutions);

  if v_bad <> '' then raise exception '0205 VERIFY FAILED:%', v_bad; end if;
  raise notice '0205 VERIFY: ok — force_return_tx writes the token and journals the reason; the scrub knows the discriminator; the journal is sealed and two-kinded';
end $$;
