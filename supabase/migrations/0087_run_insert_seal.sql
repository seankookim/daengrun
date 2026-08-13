-- ═══ 0087: the runs INSERT seal — a run row is a SERVER fact, start to finish ═══
--
-- Sibling of 0061 (the `runners` INSERT seal, pinned by suite 101) and its exact repeat on a
-- different table. 0061's one-line summary was: "`_guard_runner_cols` was `before update` only,
-- so one free signup bought tier=master". This file's is: **`_guard_run_cols` is `before update`
-- only (0057:465), and `runs runner write` (0002:107) lets an assigned runner INSERT a `runs`
-- row with every column pre-filled.** The UPDATE side of this table has been hardened four times
-- (0057 §5, 0079 §1, 0083 §2); the INSERT side has never been looked at.
--
-- Found by an adversarial review of 0083 (codex), verified against this branch before writing.
--
-- ═══ §0 THE THREE EXPLOITS — each is an authenticated assigned runner, on their OWN booking ═══
-- The RLS predicate is only `b.runner_id = auth.uid()`. It asks WHO, never WHAT. Every column of
-- `runs` is therefore client-supplied on the insert path, including three that money reads.
--
-- ① **DEFEAT THE CUTOVER.** Plant `runs(booking_id, started_at = '2000-01-01')` while the booking
--    is still `picked_up`. `transition-booking`'s `start_run` then did
--    `set({status:'active'})` **and a separate `db.from("runs").insert(...)` whose error it
--    discarded** (`index.ts:301-304`, no `error` binding at all) — so the plant survives the
--    unique-violation and the run goes live carrying a client-chosen birthday.
--    0083 §6's seal gate grandfathers the old-client arm on exactly that column:
--        `select r.started_at into v_started from runs r where r.booking_id = p_booking;`
--        `if coalesce(v_started, now()) >= v_seal_since then raise 'run_not_ended'`
--    A `started_at` in 2000 is `< return_seal_since` forever, so the run settles with **no return
--    seal** no matter when Sean flips the flag — the codex bypass 0083 exists to close, reopened
--    from underneath by the one input 0083 assumed was a server fact.
-- ② **FORGE THE SETTLEMENT ANCHOR.** `runs.settled_at` (added by 0083 §1) is the anchor the
--    payments session is about to build `sweep_settled_without_payments` on (0083 §0f: `and
--    rn.settled_at is not null`). It is client-writable on INSERT today. 119 R11 pins the
--    property that fix depends on — *"`settled_at` is written by settlement and by nothing
--    else"* — and R11 could not see this: it watches the RPCs, and this is a raw INSERT that
--    never calls one. ⚠ CORRECTION TO THE BRIEF, stated rather than smoothed over: a forged
--    `settled_at` does **not** make a booking invisible to that sweep, because the predicate is
--    `is not null` — it makes it *visible*. It is the entry ticket to ③, not an evasion. Once
--    §0f lands, ③ needs a `settled_at` too, and this column is where it would come from. The
--    defect is the same either way (a money anchor with a client writer) and the fix is the same.
-- ③ **MINT A CHARGE FOR A RUN THAT NEVER HAPPENED.** Plant `runs(booking_id, ended_at = now(),
--    actual_km = 9.9, end_reason = 'completed')` on a booking that was never even started.
--    Post-cutover, `sweep_settled_without_payments` (0080 §G) selects on `rn.ended_at` and reads
--    `rn.end_reason` / `rn.actual_km` **off that same row**, then calls
--    `mint_settle_charge_intent`, which checks no booking status at all. That is a real charge
--    intent against the owner's card, for a walk that did not occur, priced by numbers the
--    beneficiary typed. `settle_run_tx`'s atomic `where status = 'active'` claim protects the
--    normal path; **the sweep reads `runs` directly and inherits none of it.**
--
-- ═══ §0b WHAT THIS FILE DOES ═══
--   §1  the revocation   — no client role may INSERT into `runs`. The hole, closed at the source.
--   §2  start_run_tx     — the two-step start becomes ONE transaction with a SERVER `started_at`
--   §3  _guard_run_insert_cols — defence in depth: the belt for when someone re-adds the policy
--   §4  the anchor       — why `runs.started_at` is trustworthy after §1-§3, verified not asserted
--
-- ═══ §0c WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - It does not touch `_guard_run_cols`, `settle_run_tx`, `end_run_tx`, `owner_la_*`, the append
--   RPCs, or any 0080/0081/0082/0083/0084/0085/0086 object. The UPDATE side is already sealed and
--   reproducing it here would be the silent-revert class REGISTRY.md warns about.
-- - It does not fix `sweep_settled_without_payments`. 0083 §0f's handoff stands unchanged and is
--   still owed by the payments session; this file removes the *forgery* input to that sweep, not
--   the missing `settled_at` predicate. ⚠ **`payments_live_since` must still not be flipped until
--   §0f lands** — closing ③'s forgery does not close §0f's scenario B, which is an honest
--   unreturned run, not a planted row.
-- - It does not narrow `start_run` to marketplace-only. `end_run_tx` refuses `club_session_id is
--   not null`, and the symmetry is tempting — but `start_run` has never carried that gate, the
--   club start path (`club_start_delegated_runs`, 0038/0050) is a separate definer, and adding a
--   refusal to the START of a run is the one place a wrong guess strands a runner holding a dog.
--   Behaviour preserved deliberately; named here so the asymmetry is a decision, not an oversight.
-- - It does not change `start_run`'s notification. A re-tap on an already-active booking still
--   sends "러닝 시작" a second time, exactly as today (the transition trigger short-circuits
--   `old.status = new.status`, so this was always so). Idempotence is now explicit rather than
--   accidental, and the duplicate notification is left alone because it is a client-slice
--   question, not a money one.
-- - **It adds no new alert, notification, or ops escalation** — deliberately, and this is the
--   0085 post-merge lesson applied ahead of time: *a failure class carries a remedy, so the
--   remedy must match the writer that actually failed.* Every refusal here is a synchronous raise
--   to the caller who attempted the write, which is the only actor who can act on it. Nothing
--   here routes into `incident_review`, which 0083 §0h records as having **no marketplace
--   commercial exit** — an alert landing there would name a remedy that does not exist.
--
-- ═══ §0d WHOSE TEXT EACH TOUCHED OBJECT WAS BUILT ON (concurrent-session hygiene) ═══
--   · `"runs runner write"` ← 0002:107. **DROPPED**, not replaced — see §1 for why a narrowed
--     insert policy was rejected in favour of no insert policy at all. Nothing else in the repo
--     re-creates it (verified: `grep -n 'runs runner write' supabase/migrations/*.sql` → 0002 only).
--   · `"runs runner update"` ← 0057 §5 — **UNTOUCHED**. The runner legitimately writes
--     `runs.trace` through it (`api.ts:1807` saveTrace) and `_guard_run_cols` polices which
--     columns. Dropping it would take live trace persistence down with it.
--   · `"runs party read"` ← 0002:106 — UNTOUCHED.
--   NEW and owned here: `start_run_tx`, `_guard_run_insert_cols` + its trigger.
--
-- ═══ §0e DOCTRINE (0059 money-path list) ═══
-- self-contained · every definer carries `set search_path = public, pg_temp` IN THE BODY (98 H1)
-- · party gate before state gate · role judgement is `current_user` in an INVOKER trigger, never
-- inside a definer (0083's header records the trap: `current_user` in a SECURITY DEFINER is
-- always `postgres`, so a definer guard judges nobody) · mutation-proven pins
-- (`123_run_insert_seal_suite.sql`, S1-S9).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §1 THE REVOCATION — no client role inserts into `runs`
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0002's three `runs` policies split cleanly by verb, so the INSERT one can go on its own:
--   106 `runs party read`   for select  — untouched
--   107 `runs runner write` for insert  — THIS, dropped
--   110 `runs runner update` for update — untouched (re-created by 0057 §5 with a WITH CHECK)
-- Despite its name, `runs runner write` grants INSERT and nothing else; the runner's legitimate
-- writes (the live trace) ride the UPDATE policy, which stays exactly as 0057 left it.
--
-- WHY DROP RATHER THAN NARROW. A `with check` restricting the insert to `started_at is null` and
-- friends was the obvious smaller change, and it is the wrong one: a WITH CHECK cannot express
-- "the server chose this timestamp", only "the client did not choose that one" — and the whole
-- lesson of ① is that a column nobody validates becomes a money input two migrations later. With
-- the policy gone there is exactly ONE way a `runs` row is born (a SECURITY DEFINER that is
-- service_role-only), which is a property §4 can actually verify. RLS with no INSERT policy is a
-- refusal, not an omission: `runs` has had `enable row level security` since 0002:38, and under
-- RLS an absent policy denies. Nothing needs to be added for the deny to hold.
--
-- WHO STILL INSERTS, all of them audited before this line was written:
--   · `start_run_tx`              (§2, new)          — definer, owner postgres → bypasses RLS
--   · `end_run_tx`                (0083 §3)          — definer, service_role only
--   · `settle_run_tx`             (0028 ③ / 0083 §6) — definer, the upsert backstop
--   · `club_start_delegated_runs` (0038:110 / 0050:181) — definer, the club start path
--   · `transition-booking`, `settle-run`             — service_role edge functions, RLS-exempt
--   · the harness suites                             — run as `postgres`, the table owner
-- The client (`app/`) has never inserted into `runs`: `grep -n "from('runs')" app/src/lib/api.ts`
-- returns five selects and one `update({ trace })`. Verified before dropping, because a policy
-- removal that breaks a shipped screen is worse than the hole it closes.
drop policy if exists "runs runner write" on runs;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §2 start_run_tx — the two-step start becomes one transaction
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Today (`transition-booking/index.ts:301`):
--     await set({ status: "active" });
--     await db.from("runs").insert({ booking_id, started_at: new Date().toISOString() });
-- Two statements, two commits, and the second one's result is never bound — so a conflicting
-- insert (exploit ①'s plant, or a genuine double-tap) is discarded in silence. Even without the
-- plant this is wrong in three ways: the timestamp is the *client's* clock passed through an
-- edge function; a crash between the two lines leaves `active` with no run row (and therefore no
-- elapsed clock for either party — `fetchRunMeta`, `api.ts:3217`); and there is no lock, so the
-- status change and the row creation can interleave with anything.
--
-- This function is the same shape `end_run_tx` (0083 §3) has at the other end of the run: lock
-- the booking, party gate, state gate, idempotence, then write. Symmetry is the point — a run
-- now OPENS and CLOSES through one server-owned transaction each, and `runs.started_at` /
-- `runs.ended_at` are both server clocks read from `now()` inside a locked transaction.
--
-- ⚠ SERVICE_ROLE ONLY, for `end_run_tx`'s reason one step earlier: `started_at` is the column
-- 0083 §6's cutover grandfathering reads, so a client that could call this directly could still
-- not choose the value (it takes no timestamp argument) but should not be given a second way to
-- move the state machine either. The party gate is the edge function's `isRunner`; the `auth.uid()`
-- check below is the same belt-and-braces `end_run_tx` carries, live whenever a caller identity
-- is present (the suites set one; `admin()` does not).
create or replace function start_run_tx(p_booking uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b         record;
  v_now     timestamptz := now();
  v_uid     uuid := auth.uid();
  v_started timestamptz;
  v_claim   uuid;
begin
  -- ── party gate before state gate (repo law) ────────────────────────────────────────────
  select bk.id, bk.runner_id, bk.owner_id, bk.status::text as status, bk.km
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  if b.runner_id is null then raise exception 'not_run_runner'; end if;
  if v_uid is not null and v_uid is distinct from b.runner_id then
    raise exception 'not_run_runner';
  end if;

  -- ── idempotence: a second start is not an error, it is the same start ─────────────────
  -- `end_run_tx`'s contract, mirrored: the runner's screen re-fires `startRunServer` on every
  -- re-entry from the calendar (`runner/run.tsx:623`) and swallows the rejection, so a raise here
  -- would be invisible AND would leave a legitimately-active run without a repair path. Checked
  -- under the row lock taken above, so the claim below can only ever confirm this answer.
  if b.status = 'active' then
    select r.started_at into v_started from runs r where r.booking_id = p_booking;
    if v_started is null then
      -- An `active` booking with no started_at: the two-step's second statement died, or a
      -- legacy row exists with the column empty. Repairing it is the honest act — every elapsed
      -- clock in the product reads this column, and a null one shows both parties nothing.
      insert into runs (booking_id, started_at) values (p_booking, v_now)
      on conflict (booking_id) do update set started_at = coalesce(runs.started_at, excluded.started_at)
      returning runs.started_at into v_started;
    end if;
    return jsonb_build_object('unchanged', true, 'started_at', v_started);
  end if;

  -- ── state gate ─────────────────────────────────────────────────────────────────────────
  -- `picked_up → active` is the only legal edge (0066 §1's map, base 0047:39). Asserting it here
  -- rather than leaving it to `enforce_booking_transition` buys a NAMED refusal instead of
  -- `invalid booking transition: confirmed -> active` leaking to a runner's screen.
  if b.status <> 'picked_up' then raise exception 'not_picked_up'; end if;

  update bookings set status = 'active'
   where id = p_booking and status = 'picked_up'
  returning id into v_claim;
  if v_claim is null then
    -- Unreachable under the row lock; kept because the atomic claim is the thing that makes this
    -- function safe, and a claim whose 0-row branch is unwritten is a claim nobody can trust.
    raise exception 'not_picked_up';
  end if;

  -- ── the run row is born HERE, with the SERVER's clock ──────────────────────────────────
  -- ⚠ `started_at = excluded.started_at` on conflict, NOT `coalesce(runs.started_at, …)`, and the
  -- difference is exploit ① exactly. A booking that is `picked_up` has no legitimate `runs` row:
  -- nothing in the repo creates one before the start (the club path creates the row and moves the
  -- status in the same definer). So a row found here is debris or a plant, and the only safe act
  -- is to overwrite the timestamp with the server's. Coalescing would preserve a planted
  -- `'2000-01-01'` through a perfectly legitimate start — which is the residual path §4 checks
  -- for, and the one revert that reddens S1 on its own.
  -- (The idempotent branch above keeps `coalesce` on purpose: there the run is ALREADY running
  -- and its real start time is the one thing a repair must not move.)
  insert into runs (booking_id, started_at) values (p_booking, v_now)
  on conflict (booking_id) do update set started_at = excluded.started_at
  returning runs.started_at into v_started;

  return jsonb_build_object('unchanged', false, 'started_at', v_started);
end $$;
revoke execute on function start_run_tx(uuid) from public, anon, authenticated;
grant execute on function start_run_tx(uuid) to service_role;

comment on function start_run_tx is
  '0087 §2: THE START, atomic. Locks the booking, validates the assigned runner and picked_up,
claims picked_up → active and creates the runs row with a SERVER started_at, in one transaction.
Replaces transition-booking''s two-step (status update + a separate insert whose error was
discarded — the survival path for a pre-planted runs row). Idempotent: a second start returns
{unchanged:true} and repairs a missing started_at, never an error. service_role only';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §3 _guard_run_insert_cols — defence in depth
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §1 is the fix; this is the belt. The hole existed because a policy written in 0002 was never
-- revisited when the columns behind it became money, and the honest read of that is that the
-- NEXT permissive `runs` insert policy is one convenience away. `_guard_run_cols` has guarded
-- UPDATE since 0057 §5 and no equivalent has ever watched INSERT — this closes that asymmetry so
-- that re-adding a policy costs a plant instead of granting one.
--
-- SHAPE: a LIST, following 0083 §2's `_guard_booking_insert_cols` rather than 0058 §3's deny-all,
-- for the reason that file states — the guard has to survive a legitimate insert, and the only
-- column such an insert honestly carries is `booking_id`. Said plainly: after §1 there is no
-- legitimate client insert AT ALL, so this list is not "what a client may not send today", it is
-- **the set a future permissive policy must still not let through**, and every name in it is a
-- name money reads (§0 ①②③) or a name a derived surface reads (`events` → the 응가 stamp
-- `settle_run_tx` pays +30 miles for, 0028:88; `photos`/`trace` → the feed and the LA banner).
-- `pace_suggest_sec` is deliberately ABSENT and not an oversight: 0079's `_runs_pace_snapshot_tg`
-- recomputes it on every insert and overwrites whatever the caller supplied, so it is already a
-- server fact by a stronger mechanism than a refusal. `booking_id` is absent because it is the
-- row's identity, and `id` because it is generated.
--
-- ROLE JUDGEMENT is `current_user`, exactly as 0057/0058 argue and 0083 §2 repeats:
--   ① service_role edge functions → current_user = 'service_role' → outside the branch
--   ② definer RPCs (`start_run_tx`, `end_run_tx`, `settle_run_tx`, `club_start_delegated_runs`)
--      → current_user = 'postgres' → outside the branch
--   ③ the harness suites → 'postgres' → outside the branch
-- ⚠ SECURITY **INVOKER**, and this is the trap 0083's own header records: `current_user` inside a
-- SECURITY DEFINER is always the owner (`postgres`), so a DEFINER guard would judge nobody and
-- pass everybody, silently. 0079's `_runs_pace_snapshot_tg` is a DEFINER on the same table for
-- the opposite reason (it must READ `dogs.preferences` past RLS and judges no caller) — the two
-- sit side by side on `before insert` and the distinction is why they do not conflict.
--
-- FIRING ORDER: same-timing triggers fire in name order, so `_guard_run_insert` (0x5F) runs
-- before `runs_pace_snapshot` (0x72) — the guard therefore inspects the caller's RAW row, before
-- 0079 stamps its own value over one field. (0058's header states this ordering law for the
-- bookings triggers; it is the same rule.)
create or replace function _guard_run_insert_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    -- ⚠ `events` / `photos` / `trace` are NOT NULL with defaults ('[]', '{}', '[]'), so the test
    -- is "differs from the default", never "is not null" — the latter would refuse every insert
    -- including the empty one, which is a guard that cannot tell an attack from a caller.
    if new.started_at          is not null
    or new.ended_at            is not null
    or new.settled_at          is not null
    or new.actual_km           is not null
    or new.duration_sec        is not null
    or new.avg_pace_sec_per_km is not null
    or new.end_reason          is not null
    or new.condition_note      is not null
    or coalesce(new.events, '[]'::jsonb)  is distinct from '[]'::jsonb
    or coalesce(new.trace,  '[]'::jsonb)  is distinct from '[]'::jsonb
    or coalesce(new.photos, '{}'::text[]) is distinct from '{}'::text[]
    then
      raise exception 'run_insert_protected_columns'
        using detail = '러닝 기록은 서버만 만들어요 — 거리·시간·종료사유·정산 시각을 담아 새 기록을 만들 수 없어요';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_run_insert on runs;
create trigger _guard_run_insert before insert on runs
  for each row execute function _guard_run_insert_cols();

comment on function _guard_run_insert_cols is
  '0087 §3: the INSERT half of the runs seal, the belt behind §1''s policy drop. _guard_run_cols
(0057 §5) has been `before update` only since it was written, so every column a client could
pre-fill on INSERT — started_at (the cutover anchor), ended_at/actual_km/end_reason (what 0080''s
sweep mints a charge from), settled_at (the settlement anchor) — was unguarded. Blacklist rather
than deny-all, per 0083 §2. INVOKER: current_user in a DEFINER is always postgres';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §4 THE CUTOVER ANCHOR — is `runs.started_at` trustworthy now? YES, and here is the audit
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0083 §6's old-client arm grandfathers a settlement when
--     `coalesce(runs.started_at, now()) < ops_flags.return_seal_since`
-- which is only a law if `runs.started_at` is a server fact. Before this file it was not. The
-- claim that it now is rests on an exhaustive writer list, not on a feeling — every write to that
-- column in the repo, and what each one puts there:
--
--   WRITER                                       | value                       | reachable by a client?
--   ---------------------------------------------+-----------------------------+----------------------
--   `start_run_tx`            (§2, new)          | `now()`, inside the lock    | no — service_role only
--   `club_start_delegated_runs` (0038:110/0050)  | `now()`                     | no — definer, host-gated
--   `end_run_tx`              (0083 §3)          | `now() - duration`, back-derived, and only when the column is NULL (`coalesce`) | no — service_role only
--   `settle_run_tx`           (0028 ③/0083 §6)   | same back-derivation, same `coalesce` | no — service_role only
--   client INSERT             (0002:107)         | ANYTHING                    | **was YES — §1 removes it, §3 refuses it**
--   client UPDATE             (0002:110/0057 §5) | ANYTHING                    | no — `_guard_run_cols` ② has refused `started_at` since 0057:453
--
-- With the last client row gone, `runs.started_at` has no client writer on any path, and the
-- grandfathering reads a server clock. **The anchor is trustworthy — no rebase onto a booking
-- fact is needed**, which is the better outcome: `bookings.scheduled_at` was the obvious
-- alternative and it is *not* the same fact (a runner who starts 40 minutes late would be
-- grandfathered on a schedule they did not keep).
--
-- ⚠ TWO RESIDUALS, named rather than left to be found:
--   (a) **A row planted BEFORE this migration applied** keeps its forged `started_at` until the
--       booking is started. §2's on-conflict overwrite is what closes this: the plant is
--       corrected by the very act of starting the run, and a plant on a booking that never
--       starts can never settle (`settle_run_tx`'s claim is `where status = 'active'`, and
--       `active` is now only reachable through `start_run_tx` or the club definer). So the
--       exposure is a booking that is planted, started, and settled — and the start rewrites it.
--       S1 pins exactly that sequence.
--   (b) **`return_seal_since` is NULL on origin and must stay NULL until the run-end client build
--       ships** (0083 §6ⓐ / §9 D-r4). Nothing here changes that sequencing; this file makes the
--       flag safe to flip, it does not flip it.
