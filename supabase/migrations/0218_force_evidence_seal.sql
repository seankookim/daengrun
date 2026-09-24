-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0218 — force_return_tx stops writing the CALLER'S evidence object into a party-readable column,
--        and the shell forces recorded before 0205 get the journal row 0205 never gave them
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 249_force_evidence_seal_suite.sql (tag `fes`) — 0218-E1 · E2 · E3 · E4 · E5 · E6 · E7 · S1
--
-- ═══ §0a WHAT THIS FILE IS — codex 2026-09-25 #3 (high) and #4 (medium), correct-forward ═════
-- `docs/reviews/2026-09-25-server-0201-0215-codex-verdict.md`, both READ-based, both REPRODUCED
-- by suite 249 before the fix (E4's and E5's pre-repair controls read the sentinel out of a
-- party's own row — the hole, measured, not the pin's opinion of it).
--
--   #3  `0205:285-286` — 0205 §B replaced the free-text `return_force_reason` with a token and
--       journalled the sentence, and still copied `p_evidence` VERBATIM into
--       `bookings.return_force_evidence`. `authenticated` holds table SELECT on `bookings` and
--       `bookings party read` (`0002:92`) scopes it to the two parties, so an evidence object
--       like `{"memo": "private operator note"}` — which passes 0089's object/non-empty checks —
--       is read by the owner and the runner. 0205 §0c ENUMERATED this and left it as 「safe by
--       operator discipline」; suite 236's whole-row absence pin supplies evidence WITHOUT a memo
--       sentinel (`236:191`, `214-216`), so it never exercised the path. This file is the bill
--       0205 §0c wrote down («a force's evidence … the same bill, one column over»), paid.
--   #4  `0205:391-397` — 0201 §B's scrub identifies its targets by a `return_resolutions` row
--       with `source = 'ops_resolve_return_tx'`. A booking forced BEFORE 0205 by the shell
--       `force_return_tx` (0089 §6, `return_force_reason = p_reason`, no journal row — 0205 §0b
--       says so: «force_return_tx has no actor profile BY CONSTRUCTION… the journal as shipped
--       structurally cannot hold a force») keeps its free-text reason in the party-readable
--       column FOREVER, and 0205 performs no backfill for it.
--
-- 🔴 A FINDING'S SENTENCE IS THE PROPERTY, AND ITS SITE IS ONE PLACE IT IS OBSERVABLE (the house
-- law 0205 itself invoked to pay 0201's bill). Codex 2026-09-22 #1's sentence was «an operator's
-- private note must not land in a party-readable column». 0201 fixed the resolver's `reason`;
-- 0205 fixed the force's `reason`; BOTH left the force's `evidence`, which is the same column
-- family, the same reader, and a looser input (free-form jsonb chosen by the caller, where the
-- resolver's is `jsonb_build_object(…)` composed server-side at `0201:202`). Third site, same
-- sentence.
--
-- ═══ §0b EVERY `bookings` COLUMN `force_return_tx` WRITES, AND WHO COMPOSES IT ═══════════════
-- Read from 0205 §B's UPDATE (the catalog body — nothing after 0205 re-declares this function,
-- measured: `grep -ln "create or replace function force_return_tx" supabase/migrations` → 0083,
-- 0089, 0205 only).
--   | column                  | value                             | composed by     | after 0218 |
--   |-------------------------|-----------------------------------|-----------------|------------|
--   | return_forced_by        | `'ops'` literal                   | server          | unchanged  |
--   | return_forced_at        | `v_now`                           | server          | unchanged  |
--   | return_force_reason     | `v_token` = `'ops_forced'`        | server (0205)   | unchanged  |
--   | return_force_evidence   | `p_evidence`                      | 🔴 CALLER       | server — `_force_evidence_public(...)` |
--   | settlement_ready_at     | `coalesce(b.settlement_ready_at, v_now)` | server   | unchanged  |
--   NOT written, by 0089 §2's rule and re-asserted in VERIFY: `runner_confirmed_return_at`,
--   `owner_confirmed_return_at`, `return_eligible_at`. After this file, NO caller-supplied value
--   reaches `bookings` from this function: `p_reason` → journal `memo` (0205), `p_evidence` →
--   journal `evidence` (this file), `p_quote` → `_settle_sealed_run` (money, not a column here).
--
-- ═══ §0c WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   · §A — `return_resolutions` gains `evidence jsonb` (the caller's object, verbatim, sealed —
--     the table has RLS on, zero policies, no client grant, all restated here) and a THIRD row
--     kind, `source = 'backfill_0218'`, actor-less like the force's. The `source` CHECK and the
--     actor CHECK are re-issued to admit it; nothing else about the table moves. A NEW CHECK,
--     `return_resolutions_evidence_check`, requires every force-kind row to carry evidence, so a
--     later writer that drops the column from its INSERT fails loudly instead of quietly
--     reverting the journal to 0205's shape.
--   · §B — `_force_evidence_public(...)`, the ONE composer of what a party may see about a force:
--     `{source, from_status, runner_stamped, owner_stamped, forced_at}` — the resolver's own
--     vocabulary at `0201:202` MINUS its actor (`resolved_by`, which the executing review's F6
--     names as an amplification the force never had — this caller has no profile by
--     construction). Then `force_return_tx` re-declared from 0205 §B, copied BY SCRIPT, with
--     exactly TWO textual changes: `return_force_evidence = _force_evidence_public(…)` where it
--     was `= p_evidence`, and `p_evidence` added to the journal INSERT. Every gate, refusal name,
--     the response shape, `_settle_sealed_run`, first-writer-wins, and 0089's no-forged-stamp
--     rule are 0205's = 0089's, unchanged.
--   · §C — `_seal_force_evidence_0218()`, the IDEMPOTENT repair, run once by this file and
--     callable again (suite 249 calls it on a pre-0205-shaped fixture and twice for idempotency):
--       ① BACKFILL (#4): every `return_forced_by = 'ops'` booking with NO journal row of any kind
--          is a pre-0205 shell force — it gets a sealed `backfill_0218` row carrying its free text
--          as `memo`, its caller object as `evidence`, and `created_at = return_forced_at`.
--       ② its public reason becomes `ops_forced` unless it already is one of the four known
--          tokens (`ops_forced` · `ops_resolved` · `ops_resolved:strand` · `ops_resolved:review`,
--          enumerated from 0201 §A + 0205 §B — a token is not prose and is left).
--       ③ PRESERVE (#3): a force-kind journal row with no `evidence` yet receives what `bookings`
--          currently holds, but ONLY if that is not already the server-composed shape — so a row
--          whose journal evidence was lost cannot have the whitelist copied back as 「the caller's
--          object」.
--       ④ SCRUB (#3): `bookings.return_force_evidence` receives the composed shape for every
--          force-kind row, compared against the value about to be written — idempotent by
--          construction, exactly like 0201 §B's final conjunct.
--     ③ precedes ④ inside one function, so no run can scrub what it did not first preserve.
--   · §D — the comments 0205 wrote that this file falsifies: the function's (which says
--     `return_force_evidence is UNCHANGED and is still party-readable free-form jsonb`), the
--     column's, and the table's.
--
-- ═══ §0d WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
-- - **0205, 0201, 0199, 0193, 0089, 0083 are NOT edited.** They landed. 0205 §0c's paragraph
--   enumerating-and-leaving the evidence column stays as written; this header is where the
--   reader finds out it was paid.
-- - **The RESOLVER's evidence (`0201:202`) is not touched.** It is server-composed already. Its
--   `resolved_by` key (an ops profile id in a party-readable column) is the executing review's
--   F6 (`docs/reviews/2026-09-23-executing-review-0203-0213.md`), which 0214 §0c names as «its
--   own slice» — the amplification is closed (`profiles` refuses the party, measured B1b there).
--   §C's target set is keyed on `source in ('force_return_tx', 'backfill_0218')` and 249 E4's
--   control asserts a resolver row's evidence is byte-identical before and after the repair.
-- - `_scrub_ops_return_reasons` (0201 §B / 0205 §C) is not re-declared: it filters
--   `r.source = 'ops_resolve_return_tx'`, so `backfill_0218` rows are outside its set by the
--   discriminator 0205 §C taught it, not by absence. 236 `0205-F3` / `S1` keep pinning it.
-- - `my_return_resolution` (0199 §A) is not edited. ⚠ **NAMED WIDENING, second time this
--   ceremony has had one:** it returns the LATEST journal row for a booking with no `source`
--   filter, so from this file onward a party whose return was shell-forced BEFORE 0205 reads
--   「운영팀이 귀가를 확인 처리했어요」 with `resolved_at = return_forced_at` where they read
--   nothing before. True (an adjudication happened, on that date), memo-free, evidence-free —
--   the three columns that leave that function do not include either. `0218-E5` pins what the
--   party gets: the fixed sentence, the force's own timestamp, and never the text.
-- - ⚠ **A LIMITATION, IN PROSE (a pin cannot reach it):** a backfilled row's `runner_stamped` /
--   `owner_stamped` are the stamps AS OF THE BACKFILL, not as of the force. `confirm_return_tx`
--   (`0193:276-290`) accepts a late party stamp after a force, so a party who stamped between
--   the shell force and this file reads `true` where the force saw `false`. The force never
--   writes a stamp (0089 §2), so the booleans can only be an UPPER BOUND on what the operator
--   saw; the `source = 'backfill_0218'` tag is what tells a dispute reader to treat them so.
--   No fixture can distinguish 「recorded at force time」 from 「recorded at backfill time」 for a
--   row the force itself never journalled, so this is stated here and not asserted anywhere.
-- - No client build: `grep -rn return_force_evidence app/src app/app` → **0** (measured on this
--   tree). No edge deploy: `grep -rn force_return supabase/functions` → 4 hits, all comments
--   (0205 §0a's count, re-measured). No cron, no enum, no policy.
--
-- ═══ §0e THREE SHIPPED PINS / NOTES MOVE, FOR A TRUE REASON, NAMING THEIR SUCCESSOR ═══════════
--   · `119 R6` (`119:689`) asserted `return_force_evidence->>'kind' = 'ops_review'` — the caller's
--     key in the party-readable column, which after §B is exactly the thing that must NOT be
--     there. Rewritten to read the caller's key out of the JOURNAL and the composed `source` out
--     of the column. `0218-E2` / `E3` own the property.
--   · `236` header NAMED GAP («`return_force_evidence` is NOT pinned and is a real residual») is
--     rewritten to point here. A stale gap note is a document manufacturing a false green (0205
--     §0f's own words about 232's).
--   · 236's four pins are UNCHANGED: F1/F2 read the reason and the journal's memo/shape, F3 tests
--     0205 §C's scrub which this file does not touch, and every S1 source arm still holds on §B's
--     body (measured: harness delta = exactly the eight pins 249 adds).
--
-- ═══ §0f DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated in THIS file ·
-- party/ops gate before any read on the LOCKED row (0089's, untouched) · `is distinct from` /
-- `is not true`, never a bare `IF` on a nullable predicate · comments stripped before every
-- `prosrc` match · pins in `249_force_evidence_seal_suite.sql`, labels `0218-…`.
--
-- ═══ §0g DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   1. `supabase db push` — this file. 0193, 0201 and 0205 must already be applied.
--   2. Nothing else. No `functions deploy`, no client build, no cron, no secret.
--   ⚠ §C runs at apply and REPORTS its four counts as NOTICEs. On a database that never applied
--     0205 to a real force, ①–④ are all 0 and VERIFY says so rather than hoping.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A return_resolutions — the caller's evidence gets a sealed home, and a THIRD row kind
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `evidence` is nullable at the column: resolver rows (`ops_resolve_return_tx`) have none here —
-- theirs is server-composed and lives in `bookings` (0201:202). The CHECK below ties presence to
-- the row KIND instead, which is the same move 0205 §A made for `resolved_by`.
alter table return_resolutions add column if not exists evidence jsonb;

comment on column return_resolutions.evidence is
  '0218 §A — the caller''s `p_evidence` object, VERBATIM, for force-kind rows (`force_return_tx`,
`backfill_0218`); NULL for resolver rows, whose evidence is server-composed at 0201:202. This is
the dispute record 0083 §1 built the schema around, moved out of the party-readable
`bookings.return_force_evidence` (codex 2026-09-25 #3) into the one table only the server reads.
Free-form on purpose — an operator may put anything here, which is exactly why it cannot sit
where a party reads. 249 0218-E2 pins.';

alter table return_resolutions drop constraint if exists return_resolutions_source_check;
alter table return_resolutions add constraint return_resolutions_source_check
  check (source in ('ops_resolve_return_tx', 'force_return_tx', 'backfill_0218'));

-- The actor CHECK keeps 0205 §A's two facts separate and adds the third: a backfilled shell force
-- has no actor for the same reason a live one has none (0089:99 refuses any caller with an
-- `auth.uid()`), and a row claiming one would be a fabricated actor in an adjudication journal.
alter table return_resolutions drop constraint if exists return_resolutions_actor_check;
alter table return_resolutions add constraint return_resolutions_actor_check
  check ((source = 'ops_resolve_return_tx' and resolved_by is not null)
      or (source in ('force_return_tx', 'backfill_0218') and resolved_by is null));

-- SEALED, restated: this file added a column and a row kind, not a door.
alter table return_resolutions enable row level security;
revoke all on return_resolutions from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B the ONE composer of what a party may see about a force, then force_return_tx
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Five facts, every one server-derived and already readable on the row or true by the door's
-- own gate: which door (`source`), the state it was rescued from (`from_status` — always `active`
-- through this door, `not_active` refuses the rest; recorded rather than assumed so the column's
-- shape matches the resolver's), the two stamp booleans the adjudicator saw, and the instant.
-- `forced_at` is rendered as a fixed UTC ISO string rather than a raw timestamptz so the composed
-- value does not depend on the session's TimeZone — §C compares stored values against this
-- function to decide whether to write, and a rendering that drifts with the session would make
-- the repair re-write on every run under a different zone and call it a change.
-- STABLE, not IMMUTABLE: `to_char` and `jsonb_build_object` are STABLE in the catalog and a
-- volatility label is a claim about the planner's licence, not a decoration.
create or replace function _force_evidence_public(
  p_from_status    text,
  p_runner_stamped boolean,
  p_owner_stamped  boolean,
  p_forced_at      timestamptz
) returns jsonb
language sql stable set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'source',         'force_return_tx',
    'from_status',    p_from_status,
    'runner_stamped', p_runner_stamped,
    'owner_stamped',  p_owner_stamped,
    'forced_at',      to_char(p_forced_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

revoke execute on function _force_evidence_public(text, boolean, boolean, timestamptz) from public, anon, authenticated;
grant  execute on function _force_evidence_public(text, boolean, boolean, timestamptz) to service_role;

comment on function _force_evidence_public is
  '0218 §B — composes the ONLY value `force_return_tx` (and the 0218 §C repair) may write to the
party-readable `bookings.return_force_evidence`: {source, from_status, runner_stamped,
owner_stamped, forced_at}. Nothing caller-typed reaches it; the caller''s object goes to
`return_resolutions.evidence`. One composer for two writers so the shape cannot drift. 249
0218-E3 pins the key set as an EQUALITY, not an absence.';

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
      -- 🔴 [0218 §B] SERVER-COMPOSED, never the caller's object. This column is read by both
      -- parties (`bookings party read`, 0002:92), so the caller's `p_evidence` — an object an
      -- operator can type prose into — goes to the sealed journal below, and this column
      -- receives the five whitelisted facts `_force_evidence_public` composes and nothing
      -- typed. Same composer as the 0218 §C repair, so the two cannot drift. (codex
      -- 2026-09-25 #3 — the sentence 0205 §0c enumerated and left, now paid.)
      return_force_evidence = _force_evidence_public(
                                b.status,
                                (b.runner_confirmed_return_at is not null),
                                (b.owner_confirmed_return_at is not null),
                                v_now),
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
  -- [0218 §B] `evidence` is the caller's object, VERBATIM, in the sealed journal — the
  -- dispute record 0083 §1 built this schema around, now in the one place only the server
  -- reads. `evidence_required` above still holds: an adjudication with no evidence is still
  -- an assertion wearing a uniform; the evidence just no longer lands where a party reads.
  insert into return_resolutions (booking_id, resolved_by, from_status,
                                  runner_stamped, owner_stamped, memo, source, evidence)
  values (p_booking, null, b.status,
          (b.runner_confirmed_return_at is not null),
          (b.owner_confirmed_return_at is not null), p_reason, 'force_return_tx', p_evidence);

  if p_quote is not null then
    v_settled := _settle_sealed_run(p_booking, p_quote);
  end if;

  return jsonb_build_object(
    'forced', true, 'forced_by', 'ops', 'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false));
end $$;

-- ACL restated in THIS file, never inherited (0116:636 — a `create or replace` that finds no
-- function is a plain CREATE, born PUBLIC-executable). BYTE-FOR-BYTE 0089's = 0205's.
revoke execute on function force_return_tx(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
grant  execute on function force_return_tx(uuid, text, text, jsonb, jsonb) to service_role;

comment on function force_return_tx is
  '0089, amended by 0205 and 0218 — OPS-ONLY adjudication of a stuck return, from a shell. A party
(runner or owner) is refused by name with force_party_forbidden: Sean 2026-08-13, "the confirmation
must happen with both parties and never just the runner". Writes NO party confirmation stamp —
settlement_ready_at only — so the row distinguishes "ops resolved" from "both confirmed".
🔴 0205: the caller''s free-text p_reason no longer reaches bookings.return_force_reason (the fixed
token ''ops_forced'' does; the sentence is journalled in return_resolutions).
🔴 0218: the caller''s p_evidence no longer reaches bookings.return_force_evidence either (codex
2026-09-25 #3 — the same party-readable column family, a looser input). That column now receives
ONLY _force_evidence_public(...) — {source, from_status, runner_stamped, owner_stamped, forced_at},
all server-composed — and the caller''s object is journalled VERBATIM in return_resolutions.evidence
(source = ''force_return_tx'', resolved_by NULL). evidence_required and reason_required both still
hold: both inputs are still mandatory, both now land where only the server reads. NO value a caller
types reaches bookings from this function any more (0218 §0b''s table). 249 0218-E1·E2·E3·E7·S1 pin.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C _seal_force_evidence_0218 — the idempotent repair: backfill, re-token, preserve, scrub
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Four statements in a FIXED order inside one function, because ③ must precede ④ in every run:
-- a scrub that ran before its preservation would delete the only copy of the caller's object.
-- Every statement is idempotent on its own — ① by 「no journal row」, ② by 「not already a token」,
-- ③ by 「journal evidence still NULL and the column is not already the composed shape」, ④ by
-- 「the column differs from the value about to be written」 — so a second call returns four zeros
-- and changes nothing (249 0218-E6 counts journal rows before and after to prove it).
--
-- 🔴 WHY ① KEYS ON 「NO JOURNAL ROW OF ANY KIND」 AND NOT ON THE REASON'S TEXT. The two ops writers
-- are mutually exclusive per booking: the resolver refuses `already_sealed` when
-- `settlement_ready_at` is set, the force refuses re-entry when `return_forced_by` is set, both
-- set both, and nothing in the repo ever clears either (measured: `grep -n "return_forced_by *= *null
-- \|settlement_ready_at *= *null" supabase/migrations/*.sql` → 0). The resolver ALWAYS writes a
-- journal row (0193 §C-b, 0201 §A); the force writes one from 0205 §B on. So an ops-forced booking
-- with no row at all was written by 0089 §6's (or 0083 §6's) shell force and by nothing else — a
-- fact about the WORLD the way 0201 §B's targeting argument was, and 0205 §C's lesson applies:
-- if a fourth writer ever stops journalling, this predicate widens silently. VERIFY's arm that
-- every backfilled row has `return_forced_by = 'ops'` is the cheap half of noticing.
-- ⚠ `from_status` is `'active'` for every backfilled row as a READ fact, not a guess: 0083 §6 and
-- 0089 §6 both raise `not_active` on anything else (and `completed` returns early without writing).
-- ⚠ `created_at = return_forced_at`: the row records the adjudication, and the adjudication
-- happened then. `source = 'backfill_0218'` is what says the ROW was written later. This is the
-- instant 0199's `my_return_resolution` shows the party as `resolved_at` — the force's, not the
-- deploy's.
create or replace function _seal_force_evidence_0218() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_backfilled int := 0; v_reasons int := 0; v_preserved int := 0; v_scrubbed int := 0;
  -- the closed set of tokens the two ops writers produce (0201 §A's three, 0205 §B's one)
  c_tokens constant text[] := array['ops_forced', 'ops_resolved', 'ops_resolved:strand', 'ops_resolved:review'];
begin
  -- ① BACKFILL — the pre-0205 shell forces (codex #4)
  insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped,
                                  memo, source, evidence, created_at)
  select b.id, null, 'active',
         (b.runner_confirmed_return_at is not null),
         (b.owner_confirmed_return_at is not null),
         coalesce(b.return_force_reason, ''),
         'backfill_0218',
         b.return_force_evidence,
         coalesce(b.return_forced_at, now())
    from bookings b
   where b.return_forced_by = 'ops'
     and not exists (select 1 from return_resolutions r where r.booking_id = b.id);
  get diagnostics v_backfilled = row_count;

  -- ② the public REASON of a backfilled booking becomes the force token, unless it already is
  --    one of the known tokens. `is not true` so a NULL reason (no writer produces one, but the
  --    column is nullable) is re-tokened rather than silently skipped: `ops_forced` is true of it.
  update bookings b
     set return_force_reason = 'ops_forced'
   where b.return_forced_by = 'ops'
     and exists (select 1 from return_resolutions r
                  where r.booking_id = b.id and r.source = 'backfill_0218')
     and (b.return_force_reason = any(c_tokens)) is not true;
  get diagnostics v_reasons = row_count;

  -- ③ PRESERVE — a force-kind journal row with no evidence yet takes what bookings holds, but
  --    only if that is the caller's object and not already the composed shape (codex #3)
  update return_resolutions r
     set evidence = b.return_force_evidence
    from bookings b
   where b.id = r.booking_id
     and r.source in ('force_return_tx', 'backfill_0218')
     and r.evidence is null
     and b.return_forced_by = 'ops'
     and b.return_force_evidence is not null
     and b.return_force_evidence is distinct from
         _force_evidence_public(r.from_status, r.runner_stamped, r.owner_stamped, b.return_forced_at);
  get diagnostics v_preserved = row_count;

  -- ④ SCRUB — bookings receives the composed shape for every force-kind row (codex #3).
  --    `distinct on` picks the latest force-kind row per booking (there is one — 0205 §B writes
  --    on the first-force path only and 236 F2 pins the count — but an UPDATE … FROM over a
  --    one-to-many join picks an arbitrary partner, and 「arbitrary」 does not belong in a repair).
  update bookings b
     set return_force_evidence =
         _force_evidence_public(x.from_status, x.runner_stamped, x.owner_stamped, b.return_forced_at)
    from (
      select distinct on (r.booking_id) r.booking_id, r.from_status, r.runner_stamped, r.owner_stamped
        from return_resolutions r
       where r.source in ('force_return_tx', 'backfill_0218')
       order by r.booking_id, r.created_at desc
    ) x
   where x.booking_id = b.id
     and b.return_forced_by = 'ops'
     and b.return_force_evidence is distinct from
         _force_evidence_public(x.from_status, x.runner_stamped, x.owner_stamped, b.return_forced_at);
  get diagnostics v_scrubbed = row_count;

  raise notice '_seal_force_evidence_0218: backfilled=% reasons_scrubbed=% evidence_preserved=% evidence_scrubbed=%',
    v_backfilled, v_reasons, v_preserved, v_scrubbed;
  return jsonb_build_object('backfilled', v_backfilled, 'reasons_scrubbed', v_reasons,
                            'evidence_preserved', v_preserved, 'evidence_scrubbed', v_scrubbed);
end $$;

revoke execute on function _seal_force_evidence_0218() from public, anon, authenticated;
grant  execute on function _seal_force_evidence_0218() to service_role;

comment on function _seal_force_evidence_0218 is
  '0218 §C — the idempotent repair for codex 2026-09-25 #3/#4, in a FIXED order: ① every
return_forced_by=''ops'' booking with NO return_resolutions row (a pre-0205 shell force — the two
ops writers are mutually exclusive per booking and nothing clears the seal) gets a sealed
source=''backfill_0218'' row carrying its free-text reason as memo, its caller object as
evidence, created_at = return_forced_at; ② that booking''s public reason becomes ops_forced
unless it is already a known token; ③ a force-kind journal row with NULL evidence receives the
caller''s object still sitting in bookings (only if it is not already the composed shape); ④
bookings.return_force_evidence becomes _force_evidence_public(…) wherever it differs. Returns the
four counts. A second call returns zeros and changes nothing — 249 0218-E6. Resolver rows
(source=ops_resolve_return_tx) are outside every statement''s set by the discriminator.';

-- run it — and report, not hope
do $$
declare v jsonb;
begin
  v := _seal_force_evidence_0218();
  raise notice '0218 §C repair ran at apply: %', v;
end $$;

-- Now that ③ has filled every historical force-kind row: a force-kind row MUST carry evidence.
-- Added AFTER the repair on purpose — a 0205-written row is NULL here until ③ runs.
alter table return_resolutions drop constraint if exists return_resolutions_evidence_check;
alter table return_resolutions add constraint return_resolutions_evidence_check
  check (source = 'ops_resolve_return_tx' or evidence is not null);

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D the comments this file falsifies
-- ═══════════════════════════════════════════════════════════════════════════════════════
comment on column bookings.return_force_evidence is
  '0083 §1, amended by 0218 §B — the party-readable SUMMARY of a return force, never the caller''s
object. ⚠ TWO WRITERS, and as of 0218 BOTH compose it server-side. `ops_resolve_return_tx` (0201:202)
writes {source, from_status, runner_stamped, owner_stamped, resolved_by, resolved_at};
`force_return_tx` (0205 §B, re-declared 0218 §B) writes _force_evidence_public(…) = {source,
from_status, runner_stamped, owner_stamped, forced_at} — no actor, because that caller has none by
construction (0089:99). **Neither writer''s caller-typed content is here.** The force''s p_evidence
object — 0083 §1''s dispute record, REQUIRED by evidence_required — lives VERBATIM in the sealed
return_resolutions.evidence (0218 §A), because `authenticated` holds table SELECT on bookings and
0002:92 scopes it to the two parties, so anything written here is read by both (codex 2026-09-25 #3;
the same sentence as 2026-09-22 #1, one column over). 0218 §C scrubbed every pre-0218 force row and
preserved its object first. 249 0218-E1·E3·E4 pin it.';

comment on table return_resolutions is
  '0193 §A (codex REJECT A1/A2), amended by 0205 §A and 0218 §A: the ops adjudication journal for a
stranded 1:1 return. **THREE ROW KINDS, told apart by `source`.**
  · `ops_resolve_return_tx` — the product''s own door. `resolved_by` is the rostered operator''s
    profile and is REQUIRED (the CHECK carries that). `evidence` is NULL — theirs is server-composed
    in bookings (0201:202).
  · `force_return_tx` — 0089''s shell override, journalled from 0205 §B. `resolved_by` NULL and
    REQUIRED to be (0089:99 refuses any caller with an auth.uid()). `evidence` = the caller''s
    p_evidence object, VERBATIM, from 0218 §B (required by CHECK).
  · `backfill_0218` — a shell force recorded BEFORE 0205 (free text, no journal row), reconstructed
    by 0218 §C: memo = the free text it carried, evidence = the caller object it carried,
    created_at = return_forced_at. resolved_by NULL. ⚠ Its two stamp booleans are AS OF THE
    BACKFILL, an upper bound on what the operator saw (confirm_return_tx accepts a late stamp
    after a force) — the tag is what tells a reader to treat them so.
Either live kind records who decided (or that nobody could be named), what they typed, which state
the booking was rescued from and which party stamps existed at that moment. SEALED: RLS on, zero
policies, no client grant — and from 0218 this is where the caller''s evidence lives, which is the
reason the seal matters more, not less. The one party-facing read is my_return_resolution (0199
§A): created_at, from_status, a fixed sentence — never memo, never evidence, never resolved_by.
⚠ `_scrub_ops_return_reasons` (0201 §B, 0205 §C) filters source = ops_resolve_return_tx and is
therefore blind to the two force kinds by the discriminator, not by absence. 236 0205-F2·F3 and
249 0218-E2·E5·S1 pin.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time, by VALUE, and NOT a substitute for suite 249
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Apply-time source checks are protected exactly until somebody recreates the function (0131-G4),
-- so 249 owns the standing pins and this block owns 「the file that just ran did what it says」.
-- Comments are STRIPPED before every match: `prosrc` is source plus our own prose, and §B's body
-- explains every predicate it checks for — un-stripped, each arm would be satisfied by the
-- paragraph explaining it.
do $$
declare v_src text; v_raw text; v_bad text := ''; v_n int; v_def text;
begin
  -- ── §B the force ───────────────────────────────────────────────────────────────────────
  select p.prosrc into v_raw
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'force_return_tx';
  if v_raw is null then raise exception '0218 VERIFY: NO-SOURCE(force_return_tx)'; end if;
  v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
  -- the ASSIGNMENT, not the word
  if (v_src ~ 'return_force_evidence\s*=\s*_force_evidence_public\(') is not true
    then v_bad := v_bad || ' 강제: 증거 칸에 서버 조합값을 쓰지 않는다;'; end if;
  if (v_src ~ 'return_force_evidence\s*=\s*p_evidence') is not false
    then v_bad := v_bad || ' 🔴 강제: 호출자 증거 객체가 당사자가 읽는 칸에 다시 실린다;'; end if;
  -- …and the object must STILL reach the journal. A fix that simply dropped p_evidence would pass
  -- the two arms above and destroy the adjudication's only justification.
  if (v_src ~ 'insert into return_resolutions[^;]*evidence[^;]*p_evidence') is not true
    then v_bad := v_bad || ' 강제: 호출자 증거가 저널에 실리지 않는다;'; end if;
  if (v_src ~ 'raise exception ''evidence_required''') is not true
    then v_bad := v_bad || ' 강제: evidence_required 거절이 없다;'; end if;
  -- 0205's and 0089's invariants, re-asserted because this file re-declared the function
  if (v_src ~ 'return_force_reason\s*=\s*v_token') is not true
    then v_bad := v_bad || ' 강제: 판정 사유 칸에 고정 토큰을 쓰지 않는다;'; end if;
  if (v_src ~ 'return_force_reason\s*=\s*p_reason') is not false
    then v_bad := v_bad || ' 🔴 강제: 호출자 free text가 당사자가 읽는 칸에 다시 실린다;'; end if;
  if (v_src ~ '\mp_reason\M') is not true
    then v_bad := v_bad || ' 강제: 사유가 본문에서 사라졌다;'; end if;
  if (v_src ~ 'raise exception ''reason_required''') is not true
    then v_bad := v_bad || ' 강제: reason_required 거절이 없다;'; end if;
  if (v_src ~ 'raise exception ''force_party_forbidden''') is not true
    then v_bad := v_bad || ' 강제: 당사자 거절이 사라졌다 (2026-08-13 판단);'; end if;
  if (v_src ~ 'runner_confirmed_return_at\s*=') is true
    then v_bad := v_bad || ' 강제: 러너 스탬프를 위조한다;'; end if;
  if (v_src ~ 'owner_confirmed_return_at\s*=') is true
    then v_bad := v_bad || ' 강제: 보호자 스탬프를 위조한다;'; end if;
  if (v_src ~ 'return_eligible_at\s*=') is true
    then v_bad := v_bad || ' 강제: 파생 캐시를 다시 쓴다;'; end if;
  if (v_src ~ '_settle_sealed_run') is not true
    then v_bad := v_bad || ' 강제: 정산 프리미티브를 쓰지 않는다;'; end if;
  -- crude control: the raw source DOES carry the words the stripped arms look for
  if (v_raw ~ 'return_force_evidence') is not true
    then v_bad := v_bad || ' 대조: 원본 소스에 return_force_evidence라는 낱말이 없다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'force_return_tx'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 강제: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
    then v_bad := v_bad || ' 강제가 authenticated에 열려 있다 (0089 §2 위반);'; end if;
  if has_function_privilege('anon', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
    then v_bad := v_bad || ' 강제가 anon에 열려 있다;'; end if;
  if not has_function_privilege('service_role', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
    then v_bad := v_bad || ' 강제를 service_role이 실행할 수 없다;'; end if;

  -- ── §B the composer ────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_force_evidence_public';
  if v_src is null then raise exception '0218 VERIFY: NO-SOURCE(_force_evidence_public)'; end if;
  -- the composed key set, BY VALUE, on a sample call — an equality, not an absence
  if (select array_agg(k order by k) from jsonb_object_keys(
        _force_evidence_public('active', true, false, now())) k)
     is distinct from array['forced_at', 'from_status', 'owner_stamped', 'runner_stamped', 'source']
    then v_bad := v_bad || ' 조합기: 키 집합이 문서와 다르다;'; end if;
  if (_force_evidence_public('active', true, false, now())->>'source') is distinct from 'force_return_tx'
    then v_bad := v_bad || ' 조합기: source 값이 force_return_tx가 아니다;'; end if;
  if has_function_privilege('authenticated', 'public._force_evidence_public(text,boolean,boolean,timestamptz)', 'execute')
    then v_bad := v_bad || ' 조합기가 authenticated에 열려 있다;'; end if;

  -- ── §C the repair ──────────────────────────────────────────────────────────────────────
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_seal_force_evidence_0218';
  if v_src is null then raise exception '0218 VERIFY: NO-SOURCE(_seal_force_evidence_0218)'; end if;
  if (v_src ~ '''backfill_0218''') is not true
    then v_bad := v_bad || ' 수리: 백필 행을 쓰지 않는다;'; end if;
  if (v_src ~ 'not exists \(select 1 from return_resolutions') is not true
    then v_bad := v_bad || ' 수리: 「저널 행 없음」 조건이 없다 (백필이 모든 ops 행을 다시 쓴다);'; end if;
  if (v_src ~ 'r\.evidence is null') is not true
    then v_bad := v_bad || ' 수리: 보존이 이미 보존된 행을 다시 덮는다;'; end if;
  if (v_src ~ 'return_force_evidence is distinct from') is not true
    then v_bad := v_bad || ' 수리: 스크럽이 쓰려는 값과 비교하지 않는다 (멱등 아님);'; end if;
  if (v_src ~ 'return_forced_by = ''ops''') is not true
    then v_bad := v_bad || ' 수리: ops 마커 조건이 없다;'; end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = '_seal_force_evidence_0218'
                   and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
    then v_bad := v_bad || ' 수리: definer/search_path 형상 없음;'; end if;
  if has_function_privilege('authenticated', 'public._seal_force_evidence_0218()', 'execute')
    then v_bad := v_bad || ' 수리가 authenticated에 열려 있다;'; end if;
  -- the repair RAN and left the world in the shape it claims — by VALUE, not by trusting §C
  select count(*) into v_n from return_resolutions
   where source in ('force_return_tx', 'backfill_0218') and evidence is null;
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤 증거 없는 강제 저널 행 ' || v_n || '건;'; end if;
  select count(*) into v_n from return_resolutions r
   where r.source = 'backfill_0218'
     and not exists (select 1 from bookings b where b.id = r.booking_id and b.return_forced_by = 'ops');
  if v_n <> 0 then v_bad := v_bad || ' 백필 행 중 ops 강제가 아닌 예약 ' || v_n || '건;'; end if;
  select count(*) into v_n from bookings b
   where b.return_forced_by = 'ops'
     and not exists (select 1 from return_resolutions r where r.booking_id = b.id);
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤에도 저널 행 없는 ops 강제 ' || v_n || '건;'; end if;
  -- every force-kind booking's column is the composed shape (the key set, not a text sniff)
  select count(*) into v_n from bookings b
   where b.return_forced_by = 'ops'
     and exists (select 1 from return_resolutions r where r.booking_id = b.id
                  and r.source in ('force_return_tx', 'backfill_0218'))
     and (select array_agg(k order by k) from jsonb_object_keys(coalesce(b.return_force_evidence, '{}'::jsonb)) k)
         is distinct from array['forced_at', 'from_status', 'owner_stamped', 'runner_stamped', 'source'];
  if v_n <> 0 then v_bad := v_bad || ' 수리 뒤에도 조합 모양이 아닌 강제 증거 칸 ' || v_n || '건;'; end if;

  -- ── §A the table ───────────────────────────────────────────────────────────────────────
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'return_resolutions'
                    and column_name = 'evidence' and data_type = 'jsonb')
    then v_bad := v_bad || ' 저널: evidence 칸이 없다;'; end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_source_check';
  if (v_def ~ 'backfill_0218') is not true
    then v_bad := v_bad || ' 저널: source CHECK이 backfill_0218을 모른다;'; end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint
   where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_actor_check';
  if (v_def ~ 'backfill_0218') is not true
    then v_bad := v_bad || ' 저널: 행위자 CHECK이 backfill_0218을 모른다;'; end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_evidence_check')
    then v_bad := v_bad || ' 저널: 증거 CHECK이 없다;'; end if;
  if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
    then v_bad := v_bad || ' 저널에 RLS가 없다;'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
    then v_bad := v_bad || ' 저널에 정책이 있다 (클라이언트 표면);'; end if;
  if has_table_privilege('authenticated', 'public.return_resolutions', 'select')
    then v_bad := v_bad || ' 저널이 authenticated에 열려 있다;'; end if;
  if has_table_privilege('anon', 'public.return_resolutions', 'select')
    then v_bad := v_bad || ' 저널이 anon에 열려 있다;'; end if;

  if v_bad <> '' then raise exception '0218 VERIFY FAILED:%', v_bad; end if;
  raise notice '0218 VERIFY: ok — force_return_tx composes the evidence column and journals the caller''s object; the repair ran and every force-kind row is sealed; the journal is three-kinded and still sealed';
end $$;
