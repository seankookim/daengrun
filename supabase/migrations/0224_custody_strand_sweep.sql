-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 — a dog in custody with no run moving is finally somebody's problem · a sealed-but-unsettled
--        run finally pages an operator · the recurring pause stops re-sending every hour · and the
--        resolver's actor id leaves the party-readable blob
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 255_custody_strand_suite.sql (tag `cst`) — 0224-A1 · A2 · A3 · A4 · A5 · B1 · B2 · B3 ·
--        C1 · D1 · S1
--
-- ═══ §0a WHAT IS WRONG, RE-READ ON TRUNK `943eb7c`, REBASED AND RE-CHECKED ON `70901dc` ═════════
-- Four findings from the 2026-09-25 finish-line gap sweep (planner slice be/custody-strand-sweep).
--
--   backend-logic-1 (high) — **CUSTODY STATES WITH NO RUNNER ACTION HAVE NO EXIT.** A booking at
--     `picked_up` (the handoff finished, `start_run` never came) and a booking at `active` with
--     `run_ended_at IS NULL` (the run started, `end_run` never came) are swept by nothing, listed
--     nowhere and gate nobody. Measured on this tree:
--       · every run-end arm of `sweep_run_end_recovery` keys on the END of a run — ⓐ on
--         `settlement_ready_at is not null` (0201:531), ⓑ on `run_ended_at is not null` (0201:633),
--         ⓕ on `run_ended_at is not null` (0201:739) — and arms ⓒ/ⓓ/ⓔ name `picked_up` and
--         `active` in `c_dead` (0201:485-487), i.e. they deliberately look away from both;
--       · `late_booking_sweep` selects only `confirmed` / `runner_enroute` (0126:78, :105);
--       · `ops_stranded_returns()` requires `run_ended_at is not null` (0206:172);
--       · `_runner_work_gate_blocking` fires only on `(run_ended_at not null and active)` or
--         `incident_review` (0092:112-117) — so a runner holding a dog whose run never started can
--         keep accepting new work indefinitely.
--   backend-logic-2 (medium) — **arm ⓐ tells both parties 「담당자가 확인하고 있어요」 and tells no
--     operator.** Its only writes are the two `booking` rows (0201:543-552); the function's
--     `ops_recipients_for` calls are arms ⓕ/ⓓ/ⓔ only, no list shows a sealed row (0206:173 requires
--     `settlement_ready_at is null`) and `_noti_ops_titles()` (0214:156-170) has no title for it.
--   backend-logic-4 (medium) — **`generate_recurring_bookings` re-sends 「반복 예약 일시 중지」 on
--     every hourly tick for up to 72 h per occurrence.** `v_notified` is per CALL (0180:96), the
--     once-per-owner guard (0180:175) therefore resets every tick, the cron is still hourly, and no
--     dedupe exists for this title.
--   backend-logic-6 (low) — **F6: the operator's profile id still reaches both parties** through
--     `bookings.return_force_evidence` — `ops_resolve_return_tx` writes `'resolved_by', p_actor`
--     into the blob (0201:207), a column `authenticated` holds table SELECT on and `0002:92`
--     scopes to the two parties. 0214 §0c and 0218 §0d both name it as its own slice. This is it.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A  two NULL-shipped flags on `ops_flags`: `custody_start_strand_minutes`,
--       `custody_end_strand_minutes`. **NULL = the custody arm does nothing, the gate's custody arm
--       admits nothing, and the list shows only rows already belled** — the 0193
--       `return_strand_minutes` pattern exactly. The NUMBERS are Sean's letter; nothing here picks
--       one, and a CHECK refuses zero and negatives so a typo cannot strand every live run at once.
--   §B  `_custody_strand(booking)` — THE ONE PREDICATE. Four consumers read it (the sweep arm, the
--       work gate, the two ops reads) so they cannot drift apart the way 0096's `ops_gated_runners`
--       had to promise in prose that it matched 0092's predicate.
--   §C  `_sweep_custody_strands()` — arm ⓖ. Parties once per shape, the `return_strand` roster once
--       per shape, two passes so an empty roster cannot hold the parties' notice hostage.
--   §D  `sweep_run_end_recovery` — 0201 §D's body, copied BY SCRIPT, with TWO insertions: arm ⓐ's
--       ops bell (backend-logic-2) and the call to arm ⓖ. Arms ⓑ–ⓕ are byte-identical to 0201's.
--   §E  the work gate learns the custody shape — `_runner_work_gate_blocking` (0092 §6),
--       `runner_work_gate` (0116 §D ⓑ, copied by script, one edit) and `ops_gated_runners`
--       (0096 §7), all three reading §B.
--   §F  two ops reads: `ops_stranded_custody()` (roster `return_strand`) and
--       `ops_sealed_unsettled()` (roster `payout_due`). Read-only. No button.
--   §G  `_noti_ops_titles()` — 0214 §A's ledger plus the three titles this file writes.
--   §H  `generate_recurring_bookings` — 0180 §A's body, copied by script, one edit: the pause notice
--       is sent at most once per 24 h per owner, AND a new block after the series has produced a
--       booking again counts as a new episode (see the function).
--   §I  `ops_resolve_return_tx` — 0201 §A's body, copied by script, one line removed
--       (`resolved_by` out of the party-readable blob; the journal keeps it) — and
--       `_scrub_resolver_actor_0224()`, the idempotent repair, run once below.
--
-- ═══ §0c WHAT THIS FILE DELIBERATELY DOES NOT DO — each one a decision, not an omission ═══════
--   · **It does not let anyone END a custody strand.** Whether an operator may force-end a run the
--     runner never stopped (or start one they never started) is Sean's letter. §F is a READ; the
--     only exits are the runner's own `start_run` / `end_run`, an SOS/incident, or a human in psql.
--     The list exists so the bell lands somewhere; it names no remedy it cannot deliver.
--   · **It does not pick either threshold** (§A) and it does not touch `return_strand_minutes`.
--   · **The work gate does NOT gate a LIVE run.** The planner's brief read Sean's 2026-08-13 ruling
--     literally ("dont let them make new runs until the dog is confirmed by both sides") and asked
--     for `picked_up` and `active + run_ended_at is null` to gate unconditionally. 0092 §3 refused
--     exactly that, by name: 「gating on "currently running" would change the meaning from "you did
--     not bring a dog home" to "you are busy"」. And there is a measured reason not to override it
--     server-side today: the runner-home strip (`app/app/runner/home.tsx:1240-1284` on `70901dc`) maps only
--     `waiting_on ∈ {owner, runner, both}` and draws 「지난 러닝의 반환 확인이 아직이에요 … 반환 봉인
--     찍기 ›」 → `/runner/return-seal` for anything else — so an unconditional arm would put a false
--     sentence and a dead exit on EVERY runner's home during EVERY run, with no client build. So the
--     custody arm gates only a STRANDED custody (past §A's threshold) and ships inert. Whether a
--     live run should gate is left as the letter it always was.
--   · ⚠ **DEPLOY-ORDER CONSEQUENCE, stated where Sean will read it:** setting either §A threshold
--     ALSO arms the gate's custody arm, and until the client strip maps `waiting_on = start_run |
--     end_run` (exits `runner_start_run` | `runner_end_run`) a STRANDED runner's home strip will print
--     the return-seal sentence. The edge's accept refusal falls to its `both` sentence
--     (`transition-booking/index.ts:213`), which is loosely true. Set the thresholds after the
--     client row lands, or accept that one wrong strip for runners who are already hours overdue.
--   · **Club bookings are out of scope** (`club_session_id is not null` → §B returns nothing), as in
--     arms ⓐ/ⓑ/ⓕ and the gate: a club run ends by the host's stop (0144:94) and clubs run their own
--     custody machine (0045/0069). Whether a club custody can strand the same way was not examined
--     here.
--   · **It does not settle the sealed-but-unsettled row.** That needs the pricing RE-DRIVE 0083 §0f
--     names (a pg_net dispatcher to an edge function with its own contract). §D rings a bell and §F
--     lists the row; `ops_resolve_return_tx` still refuses it by name (`already_sealed`). The
--     party sentence 「담당자가 확인하고 있어요」 is now backed by a delivered row **only when the
--     `payout_due` roster is non-empty** — with an empty roster it is still unbacked, and the
--     notice says 「0 recipient(s)」. Provisioning the roster is Sean's (0193 §0e item 4).
--   · **No client, no edge function.** The client rows (the console list, notification routing for
--     the five new titles, the runner strip's two new `waiting_on` words) are the next wave.
--     `transition-booking` calls `runner_work_gate`; its response shape is unchanged (two new
--     `waiting_on`/`exit` VALUES, no new key).
--
-- ═══ §0d WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES, each from the highest declaring migration on this tree (grepped):
--     `sweep_run_end_recovery()`          ←0201 §D  (copied by script; +arm ⓐ ops bell, +call ⓖ)
--     `ops_resolve_return_tx(uuid,jsonb,text,uuid)` ←0201 §A (copied by script; −1 line)
--     `generate_recurring_bookings()`     ←0180 §A  (copied by script; the pause guard)
--     `_noti_ops_titles()`                ←0214 §A  (copied by script; +3 titles)
--     `runner_work_gate(uuid)`            ←0116 §D ⓑ (copied by script; +2 exit arms)
--     `_runner_work_gate_blocking(uuid)`  ←0092 §6  (re-written: one lateral read of §B)
--     `ops_gated_runners()`               ←0096 §7  (re-written: the same lateral read)
--   CREATES: `_custody_strand`, `_sweep_custody_strands`, `ops_stranded_custody`,
--     `ops_sealed_unsettled`, `_scrub_resolver_actor_0224`. ADDS two columns to `ops_flags`.
--   Every ACL is restated in THIS file (`check-definer-acl.mjs`'s class — 0116:636).
--
-- ═══ §0e SHIPPED PINS THAT MOVE, AND WHY (the house law: update, say why, name the new owner) ══
--   · `245 0214-T1` — the ledger is now FOURTEEN; its spelled-out list gains the three titles.
--     `0214-T4` — `_sweep_custody_strands` joins SYSTEM_WRITERS (it writes the two custody ops
--     rows). `0224-B2` owns the new titles.
--   · `241 0210-O2` — its ops-title array gains the three titles (so the walk proves each is gated
--     by the `ops` column and is not in the urgent family).
--   · `116 C14` — its ⓑ arm expected a SECOND 「반복 예약 일시 중지」 in the same transaction as
--     C13's. That is exactly the repeat §H removes; the arm now clears the owner's earlier pause
--     rows before measuring what IT is about (the switch-keyed gate). `0224-C1` owns the dedupe.
--   · `161 P4` — freezes `generate_recurring_bookings`'s body and comment by md5 + length, and its
--     own note says what to do when the generator moves on purpose: re-read both from the catalog,
--     paste them, say why. Done (the body moved in §H's one anchored place; the comment still
--     carries `[0111]`). `0224-C1` owns the new behaviour.
--   · `app/test/ops-system-titles.test.cjs` read the ledger out of 0214 BY FILE NAME, so any later
--     re-declaration of `_noti_ops_titles()` — which is the only way a new `system` writer can be
--     ledgered without editing a landed migration — would redden it forever. It now reads the
--     LATEST declaration, the rule it already applied to the writers.
--   The lock-count pins on `sweep_run_end_recovery` (219 `0188-B4`, 214 `0183-E6`, 232 `0201-S1`:
--   「5 × `for update skip locked`, 5 × `limit c_batch`」) do NOT move: arm ⓖ lives in its own
--   function, which `0224-S1` pins as locked and bounded (2 × each). Their sentence — every arm OF
--   THAT FUNCTION that writes is locked and bounded — is still true of the body they read.
--
-- ═══ §0f DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated here · party/ops
-- gate before any read (both lists) · every candidate predicate re-asserted on the LOCKED row ·
-- `is true` / `is distinct from`, never a bare `IF` on a nullable predicate · comments stripped
-- before every `prosrc` match · pins in `255_custody_strand_suite.sql`, labels `0224-…`.
--
-- ═══ §0g INACTION, ENUMERATED — for every state this file touches, what resolves it ════════════
--   | state                                   | swept by                    | listed by               | exit                                  |
--   |-----------------------------------------|-----------------------------|-------------------------|---------------------------------------|
--   | `picked_up`, past start threshold       | ⓖ (parties + return_strand) | ops_stranded_custody    | runner `start_run` · incident · psql  |
--   | `active`, no stop, past end threshold   | ⓖ (parties + return_strand) | ops_stranded_custody    | runner `end_run` · SOS · psql         |
--   | either, threshold NULL (shipped)        | NOTHING — by design         | only if already belled  | same; the number is Sean's letter     |
--   | either, roster empty                    | parties once; ops retried every tick (durable PENDING) | — | same                    |
--   | sealed, unsettled                       | ⓐ (parties once + payout_due once) | ops_sealed_unsettled | pricing re-drive (0083 §0f) · none built |
--   | recurring series, owner blocked         | owner told ≤ 1 / 24 h per episode | —                 | the debt clears / a card is added     |
--   A custody strand whose runner never acts and whose operator cannot act stays stranded and
--   LISTED — which is the honest state until Sean rules on an ops door. It is no longer silent.
--
-- ═══ §0h DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   1. `supabase db push` — this file. No edge deploy, no client build, no cron change (arm ⓖ rides
--      the existing `sweep_run_end_recovery` tick; the recurring cron is unchanged).
--   2. §I's scrub runs inside the push and reports its count. Production has never applied 0193's
--      resolver path to a real strand as far as this file can know, so the count is expected to be
--      small or 0 — it is reported, not assumed.
--   3. **SEAN — TWO PRODUCTION WRITES, AND THEY ARE DECISIONS, NOT CHORES (after the client row):**
--          update ops_flags set custody_start_strand_minutes = <m>, custody_end_strand_minutes = <m>,
--                               updated_at = now();
--      NULL (shipped) = inert. And `ops_recipients` needs active `return_strand` / `payout_due` rows
--      or the ops half delivers to nobody (the notice says so every tick).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A the two thresholds
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- DURATIONS, like `return_strand_minutes` (0193 §A) and for its reason: there is no retroactive
-- charge to protect against, and the question is 「how long may a custody sit still before a human
-- is told」. Two columns, not one, because the two shapes have different clocks — the start strand
-- counts from the moment the pickup handoff finished, the end strand from the run's NOMINAL end —
-- and a single number would have to be wrong for one of them.
alter table ops_flags add column if not exists custody_start_strand_minutes int;
alter table ops_flags add column if not exists custody_end_strand_minutes int;

-- Zero and negatives are refused: a `0` would strand every `picked_up` row the instant the handoff
-- completes and gate every runner mid-pickup. NULL stays legal — it is the off switch.
alter table ops_flags drop constraint if exists ops_flags_custody_strand_minutes_check;
alter table ops_flags add constraint ops_flags_custody_strand_minutes_check
  check ((custody_start_strand_minutes is null or custody_start_strand_minutes > 0)
     and (custody_end_strand_minutes   is null or custody_end_strand_minutes   > 0));

comment on column ops_flags.custody_start_strand_minutes is
  '0224 §A: minutes after the pickup handoff completed (greatest of the two handoff stamps) at which
a marketplace booking still at `picked_up` is a custody STRAND — the runner holds the dog and never
started the run. NULL = off (the shipped value): sweep arm ⓖ ignores the shape, the work gate does
not gate on it, and ops_stranded_custody() shows only rows already belled. The number is Sean''s.
⚠ Setting it also arms the work gate''s custody arm (0224 §0c) — set it after the runner-home strip
maps waiting_on = start_run. 255 0224-A1/A3/A4 pin both arms.';
comment on column ops_flags.custody_end_strand_minutes is
  '0224 §A: minutes after the run''s NOMINAL end (runs.started_at + km*8+25 min — the formula every
availability check uses) at which a marketplace booking still `active` with no run_ended_at is a
custody STRAND — the run started and was never stopped. NULL = off (shipped). The number is Sean''s.
⚠ Setting it also arms the work gate''s custody arm (0224 §0c). 255 0224-A2/A3/A4 pin both arms.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B _custody_strand — THE predicate, read by four consumers
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Zero rows for anything that is not a marketplace custody shape. One row otherwise:
--   shape     'start_run'  status `picked_up`
--             'end_run'    status `active` AND `run_ended_at is null`
--   since_at  where the strand clock starts:
--             start_run → the moment the handoff completed (greatest of the two handoff stamps)
--             end_run   → the run's NOMINAL end: `runs.started_at + (km*8+25) min`
--   due_at    since_at + the shape's threshold — NULL when the threshold is NULL
--   stranded  `due_at < now()`, and FALSE (never NULL) when due_at is NULL — a caller that writes
--             `where stranded` must not be able to collapse a NULL into 「not stranded」 by accident
--             and a caller that writes `is not true` must get the same answer.
--
-- 🔴 **STATUS IS THE FACT, NOT `runs`.** The brief proposed 「picked_up AND no runs row」. `start_run_tx`
--   moves `picked_up → active` and inserts the `runs` row in ONE transaction (0087 §2), so a
--   `picked_up` row that somehow carries a `runs` row is an anomaly — and excluding it would make the
--   anomaly the one custody nobody sweeps. The deny-list instinct (attack inaction): a row whose
--   status says the dog is in custody and the run has not started IS that, whatever else it carries.
-- ⚠ **EVERY CLOCK HAS A FALLBACK, so no custody is unsweepable for want of a timestamp.** An `active`
--   row with no `runs` row (the two-step's dead second statement that 0087 §0 describes; `start_run_tx`
--   repairs it only on a re-tap) falls back to the handoff instant and then to `scheduled_at`, which
--   is NOT NULL. A clock that could be NULL is an arm that could be silent forever.
-- ⚠ A `language sql` definer: callers are definers too, but the helper is reachable on its own only
--   by `service_role` — a booking id in, a custody verdict out, is an oracle a client must not hold.
create or replace function _custody_strand(p_booking uuid)
returns table (shape text, since_at timestamptz, due_at timestamptz, stranded boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select x.shape, x.since_at, x.due_at, coalesce(x.due_at < now(), false)
    from (
      select s.shape, s.since_at,
             s.since_at + make_interval(mins => case s.shape
                                                  when 'start_run' then f.custody_start_strand_minutes
                                                  else f.custody_end_strand_minutes
                                                end) as due_at
        from bookings b
        -- the SHAPE is decided once, here, and everything below keys on it — a second copy of the
        -- status test in the clock would be a second place for the two to disagree
        cross join lateral (
          select case
                   when b.status::text = 'picked_up' then 'start_run'
                   when b.status::text = 'active' and b.run_ended_at is null then 'end_run'
                 end as shape
        ) s0
        cross join lateral (
          select s0.shape,
                 case s0.shape
                   when 'start_run'
                     then coalesce(greatest(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at),
                                   b.scheduled_at)
                   when 'end_run'
                     then coalesce((select r.started_at from runs r where r.booking_id = b.id),
                                   greatest(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at),
                                   b.scheduled_at)
                          + make_interval(mins => (b.km * 8 + 25)::int)
                 end as since_at
        ) s
        left join ops_flags f on f.id
       where b.id = p_booking
         and b.club_session_id is null
         and s.shape is not null
    ) x
$$;

revoke execute on function _custody_strand(uuid) from public, anon, authenticated;
grant  execute on function _custody_strand(uuid) to service_role;

comment on function _custody_strand is
  '0224 §B: the ONE custody-strand predicate. Zero rows unless the booking is a marketplace custody
shape — start_run (status picked_up) or end_run (status active, run_ended_at null). since_at is where
the clock starts (handoff completed / the run''s nominal end runs.started_at + km*8+25 min, with
fallbacks to the handoff stamps and scheduled_at so no custody is unsweepable for want of a
timestamp); due_at adds the shape''s ops_flags threshold (NULL when the flag is NULL); stranded is
due_at < now() and FALSE — never NULL — when due_at is NULL. Read by _sweep_custody_strands,
_runner_work_gate_blocking, ops_gated_runners and ops_stranded_custody so the four cannot drift.
Status is the fact, not runs (0224 §B). service_role only. 255 0224-A1..A4 pin it through its callers.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C _sweep_custody_strands — arm ⓖ
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Called by `sweep_run_end_recovery` (§D) on every tick, inside that tick's job lock.
--
-- ⚠ **ITS OWN FUNCTION, AND THE REASON IS NOT TIDINESS.** (1) It is independently callable, so a
--   suite can drive it without re-running arms ⓐ–ⓕ over every other suite's leftovers. (2) The
--   lock-count pins on the sweep's own body stay pinned to what they say: 「every arm OF THAT
--   FUNCTION that writes is locked」. This arm is locked and bounded here, and `0224-S1` pins it.
-- ⚠ **THE SAME JOB LOCK.** `pg_try_advisory_xact_lock` on the sweep's own key: re-entrant inside a
--   tick (the caller already holds it, so this succeeds), and a standalone call made while a real
--   tick runs is skipped rather than interleaved — both writes are read-then-write on
--   `notifications`, which is exactly the overlap the key exists to prevent (0181's reason).
-- ⚠ **TWO PASSES, NOT ONE.** The parties' notice and the ops bell are separate one-shots keyed by
--   separate titles. In ONE pass, a row whose ops half is PENDING (empty roster) never leaves the
--   candidate set, and fifty of them fill every `limit c_batch` slot forever — so the fifty-first
--   stranded dog's RUNNER would never be told, because an OPERATOR was never provisioned. That is
--   cold review 0188 #3's shadowing failure, one arm over. Two passes, each draining on its own
--   title: the party pass always drains; the ops pass drains the moment a roster exists, and until
--   then blocks nothing but the ops delivery an empty roster was going to lose anyway.
-- ⚠ Both passes: candidate query, then LOCK (`for update skip locked` — a row a writer holds is left
--   for the next tick, never waited on), then EVERY candidate predicate re-asserted on the locked
--   row through §B itself (arm ⓑ's law), then the one-shot re-taken under the lock.
-- ⚠ The ops rows carry NO identifier and NO amount (0084 §E: a wrong recipient id pushes the body
--   verbatim to a stranger's lock screen); the booking rides in `ref_id`. The titles are written
--   through CONSTANTS, one insert per shape, so `app/test/ops-system-titles.test.cjs` can resolve
--   each `system` title to a literal — an expression there would read as UNRESOLVED and fail loudly.
-- ⚠ Kinds: the parties' rows are `booking` (the brief's; this is the runner's job and the owner's
--   booking), the ops rows `system` (the operator's category, ledgered in §G).
create or replace function _sweep_custody_strands() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_b record; n int := 0; v_ops int;
  v_shape text; v_stranded boolean;
  v_start_min int; v_end_min int;
  c_batch constant int := 50;
  c_ops_class constant text := 'return_strand';
  -- the parties — one title per SHAPE, shared by both parties (arm ⓑ-②'s `c_ret_title` idiom), so
  -- a booking that strands at the start and again at the end is told about each, once
  c_start_title        constant text := '러닝 시작이 멈춰 있어요';
  c_start_body_runner  constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 앱에서 러닝을 시작해주세요';
  c_start_body_owner   constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 러너에게도 알렸어요';
  c_end_title          constant text := '러닝 종료가 멈춰 있어요';
  c_end_body_runner    constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 앱에서 러닝을 종료해주세요';
  c_end_body_owner     constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 러너에게도 알렸어요';
  -- the owner's sentence when there is no runner to have told — 「러너에게도 알렸어요」 would be a lie
  c_body_owner_alone   constant text := '러닝 진행이 확인되지 않은 예약이 있어요 — 예약을 확인해주세요';
  -- the operators — one title per shape, for the same reason
  c_start_ops_title    constant text := '러닝 시작 좌초 — 확인 필요';
  c_start_ops_body     constant text := '인계는 끝났는데 러닝이 시작되지 않은 예약이 있어요. 예약을 확인해 주세요.';
  c_end_ops_title      constant text := '러닝 종료 좌초 — 확인 필요';
  c_end_ops_body       constant text := '예정 시간이 지났는데 러닝이 종료되지 않은 예약이 있어요. 예약을 확인해 주세요.';
begin
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice '_sweep_custody_strands: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- Both thresholds NULL (the shipped state) ⇒ read no booking at all. §B would answer 「not
  -- stranded」 for every row anyway; this is the short-circuit, not the rule.
  select f.custody_start_strand_minutes, f.custody_end_strand_minutes
    into v_start_min, v_end_min from ops_flags f where f.id;
  if v_start_min is null and v_end_min is null then return 0; end if;

  -- The two passes sit in ONE protected block. Each row already has its own sub-block (arm ⓑ's
  -- reasoning: one surprising row must not stop the sweep for every other); this outer one is for a
  -- surprise OUTSIDE any row — a candidate query that raises — and it rolls back THIS arm's writes
  -- and nothing else, so the caller's arms ⓐ–ⓕ keep their tick. It lives HERE rather than around
  -- the call in `sweep_run_end_recovery` so that function's own handler count (214 `0183-E6`) keeps
  -- describing that function's arms.
  begin
  -- ── pass 1: the two parties, once per shape ─────────────────────────────────────────────────
  for r in
    select b.id
      from bookings b
      cross join lateral _custody_strand(b.id) cs
     where b.status in ('picked_up', 'active')
       and cs.stranded is true
       and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id
                          and nt.title = case cs.shape when 'start_run' then c_start_title
                                                       else c_end_title end)
     order by cs.due_at, b.id
     limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id into v_b
        from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice '_sweep_custody_strands: parties % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- every candidate predicate, re-asserted on the LOCKED row through the same predicate
      v_shape := null; v_stranded := null;
      select cs.shape, cs.stranded into v_shape, v_stranded from _custody_strand(v_b.id) cs;
      if v_stranded is not true then continue; end if;
      if v_shape = 'start_run' then
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_start_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'booking', c_start_title,
                case when v_b.runner_id is null then c_body_owner_alone else c_start_body_owner end, v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'booking', c_start_title, c_start_body_runner, v_b.id);
        end if;
      else
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_end_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'booking', c_end_title,
                case when v_b.runner_id is null then c_body_owner_alone else c_end_body_owner end, v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'booking', c_end_title, c_end_body_runner, v_b.id);
        end if;
      end if;
      raise notice '_sweep_custody_strands: booking % — custody strand (%) told to both parties once', v_b.id, v_shape;
      n := n + 1;
    exception when others then
      raise notice '_sweep_custody_strands: parties % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ── pass 2: the return_strand roster, once per shape; retried every tick while it is empty ───
  for r in
    select b.id
      from bookings b
      cross join lateral _custody_strand(b.id) cs
     where b.status in ('picked_up', 'active')
       and cs.stranded is true
       and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id
                          and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                                       else c_end_ops_title end)
     order by cs.due_at, b.id
     limit c_batch
  loop
    begin
      select b.id into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice '_sweep_custody_strands: ops % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      v_shape := null; v_stranded := null;
      select cs.shape, cs.stranded into v_shape, v_stranded from _custody_strand(v_b.id) cs;
      if v_stranded is not true then continue; end if;
      if v_shape = 'start_run' then
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_start_ops_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_start_ops_title, c_start_ops_body, v_b.id
          from ops_recipients_for(c_ops_class) as rc(profile_id);
      else
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_end_ops_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_end_ops_title, c_end_ops_body, v_b.id
          from ops_recipients_for(c_ops_class) as rc(profile_id);
      end if;
      get diagnostics v_ops = row_count;
      raise notice '_sweep_custody_strands: booking % — custody strand (%): % ops recipient(s) for %', v_b.id, v_shape, v_ops,
        c_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
      if v_ops > 0 then n := n + 1; end if;
    exception when others then
      raise notice '_sweep_custody_strands: ops % — %', r.id, sqlerrm;
    end;
  end loop;
  exception when others then
    -- nothing this arm wrote in this tick survives the rollback, so the count says so
    raise notice '_sweep_custody_strands: arm aborted, its writes rolled back — %', sqlerrm;
    n := 0;
  end;

  return n;
end $$;

revoke execute on function _sweep_custody_strands() from public, anon, authenticated;
grant  execute on function _sweep_custody_strands() to service_role;

comment on function _sweep_custody_strands is
  '0224 §C — sweep_run_end_recovery arm ⓖ (backend-logic-1): a marketplace custody that never moved.
start_run = picked_up past ops_flags.custody_start_strand_minutes after the handoff; end_run = active
with no run_ended_at past custody_end_strand_minutes after the nominal end. Both NULL (shipped) ⇒ it
reads no booking. Pass 1 tells both parties once per shape (kind booking, one title per shape); pass
2 tells the return_strand roster once per shape (kind system, identifier-free body, ref_id = the
booking), retried every tick while the roster is empty. Two passes so a PENDING ops half can never
shadow a newer row''s party notice under the batch limit. Every candidate predicate is re-asserted on
the locked row through _custody_strand; the one-shots are re-taken under the lock. Runs inside the
sweep''s job lock (the same key, re-entrant). NO status move, no door — ending a custody is Sean''s
letter. service_role only. 255 0224-A1/A2/A5/S1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D sweep_run_end_recovery — 0201 §D's body, two insertions
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT from 0201's text (0201 §0c's own discipline: a hand copy of 450 lines is how a
-- comment-level difference becomes a behavioural one). Each anchor was asserted present EXACTLY ONCE
-- before its edit. The two insertions, and nothing else:
--   ① ARM ⓐ's OPS BELL (backend-logic-2). Inside the arm's loop, after the parties' alarm and keyed
--     on the SAME age (`SEAL_ALARM_AFTER`) but on its OWN one-shot title, so rows whose parties
--     were told before this file still get their operator bell once. The roster is `payout_due` —
--     a sealed-but-unsettled run is a runner owed money, and that is the class 0084 §E pages for
--     money. An EMPTY roster writes nothing and the arm tries again next tick (0193 ⓕ's durable
--     PENDING shape). NO row lock, deliberately: arm ⓐ never locked (it moves no state) and the job
--     lock already serialises ticks; locking here would also move the lock-count pins' subject.
--   ② THE CALL TO ARM ⓖ (§C), last. Its protection against a surprise is INSIDE §C (one outer
--     handler around both passes), so a raise there is a notice rather than a rollback of arms
--     ⓐ–ⓕ's work in this tick — and this body's own handler count stays five (214 `0183-E6`).
-- Arms ⓑ · ⓒ · ⓓ · ⓔ · ⓕ are byte-identical to 0201's.
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
  -- [0224 §D ①] arm ⓐ's OPERATOR bell. `payout_due` — a sealed-but-unsettled run is a runner owed
  -- money, the class 0084 §E pages for money. Its own one-shot title (NOT the parties'), so a row
  -- whose parties were told before 0224 still rings once. NO id and NO amount in the body (0084 §E).
  c_seal_ops_class constant text := 'payout_due';
  c_seal_ops_title constant text := '정산 미완료 — 확인 필요';
  c_seal_ops_body  constant text := '인계는 확인됐는데 정산이 마무리되지 않은 예약이 있어요. 예약을 확인해 주세요.';
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
    -- [0224 §D ①] …and the OPERATORS, once, by their own title, at the same age. Until this file
    -- the sentence above — 「담당자가 확인하고 있어요」 — had nobody behind it: no operator was told
    -- and no list showed the row (backend-logic-2). An EMPTY roster writes nothing and is retried
    -- next tick (0193 ⓕ's durable PENDING), and the notice says so rather than reading as sent.
    if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
       and not exists (select 1 from notifications nt
                       where nt.ref_id = r.id and nt.title = c_seal_ops_title) then
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_seal_ops_title, c_seal_ops_body, r.id
        from ops_recipients_for(c_seal_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      raise notice 'sweep_run_end_recovery: booking % — sealed but unsettled past %: % ops recipient(s) for %',
        r.id, SEAL_ALARM_AFTER, v_ops,
        c_seal_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
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
        and (b.status = 'incident_review'
             or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
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
        if (v_b.status is distinct from 'incident_review')
           and v_b.runner_confirmed_return_at is not null
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

  -- ⓖ [0224 §C] A CUSTODY THAT NEVER MOVED — `picked_up` with no start, `active` with no stop, past
  -- the thresholds Sean sets (NULL ⇒ it reads no booking). Its own function, locked and bounded
  -- there, with its own handler so a surprise in it cannot roll back arms ⓐ–ⓕ's work.
  n := n + _sweep_custody_strands();

  return n;
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited — 0193 §D's line, for the same reason.
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant  execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9 · 0181 ⓒ · 0182 ⓓ · 0183 ⓔ · 0188 ⓑ · 0193 ⓕ · 0201 §D, and 0224 §D: (1) arm ⓐ now also
bells the payout_due roster once per sealed-but-unsettled booking past SEAL_ALARM_AFTER (its own
one-shot title, identifier-free body; an empty roster is retried every tick) — the parties'' sentence
「담당자가 확인하고 있어요」 finally has an operator behind it whenever the roster is provisioned;
(2) arm ⓖ, _sweep_custody_strands(), runs last (its own handler inside it). Arms ⓑ–ⓕ are 0201''s byte for
byte. 255 0224-B1/A1/S1 pin the additions; 232/224/219/214/213/212 keep pinning the rest.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E the work gate learns the custody shape — only once it is a STRAND
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §0c says why the custody arm is threshold-gated and not literal. The three functions below read
-- §B through ONE lateral join each, so the admission and the `waiting_on` word come from the same
-- row of the same predicate — they cannot disagree about which shape a booking is in.
--
-- ⚠ `waiting_on` gains two words, `start_run` and `end_run`, and they come FIRST: a custody row
--   carries no return stamps, so the old case would have called it `both` and the runner would have
--   been told to confirm a return from a run that never ended. The return-stamp words are unchanged
--   for every row the old arms admit.
-- ⚠ The lateral's status conjunct is a ONE-TIME FILTER on the outer row, so §B is not called for the
--   runner's cancelled/completed history (the partial index 0092 §5 built covers every unreturned
--   row, which includes every cancellation). It is performance, not logic — §B returns nothing for
--   those statuses anyway — and is recorded as such rather than pinned (a pin could not tell).
create or replace function _runner_work_gate_blocking(p_runner uuid)
returns table (
  booking_id uuid,
  status text,
  run_ended_at timestamptz,
  runner_confirmed boolean,
  owner_confirmed boolean,
  waiting_on text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.id,
         b.status::text,
         b.run_ended_at,
         b.runner_confirmed_return_at is not null,
         b.owner_confirmed_return_at  is not null,
         -- [0224] a stranded custody names ITS exit; otherwise 0092 §6's words, unchanged —
         -- "확인해주세요" to a runner who has already stamped is a lie about their own action.
         coalesce(x.shape,
                  case
                    when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
                      then 'both'
                    when b.runner_confirmed_return_at is null then 'runner'
                    else 'owner'
                  end)
    from bookings b
    left join lateral (
      select cs.shape
        from _custody_strand(b.id) cs
       where b.status::text in ('picked_up', 'active')
         and cs.stranded is true
    ) x on true
   where b.runner_id = p_runner
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and b.club_session_id is null          -- clubs run their own custody machine (0045/0069)
     and (
           -- the run stopped and the dog is not confirmed home (0083's 귀가 window)
           (b.run_ended_at is not null and b.status::text = 'active')
           -- or the booking went sideways with the dog still out — ⑫'s own case
           or b.status::text = 'incident_review'
           -- [0224] or the runner holds the dog and the run has STRANDED — never started, or never
           -- stopped, past the threshold Sean sets (NULL ⇒ this arm admits nothing)
           or x.shape is not null
         )
   order by b.run_ended_at nulls last, b.id
   limit 1
$$;

revoke execute on function _runner_work_gate_blocking(uuid) from public, anon, authenticated;
grant  execute on function _runner_work_gate_blocking(uuid) to service_role;

comment on function _runner_work_gate_blocking is
  '0092 §6 + 0224 §E: the single oldest booking blocking this runner from new work. 0092''s two arms
unchanged (run stopped + return unconfirmed; incident_review), plus a third: a marketplace custody
that has STRANDED per _custody_strand (picked_up past custody_start_strand_minutes, or active with no
stop past custody_end_strand_minutes). NOT a live run — 0092 §3''s "you are busy" line is kept, and the
thresholds ship NULL. waiting_on gains start_run / end_run, which come first because a custody row
carries no return stamps. service_role only. 255 0224-A3 pins it.';

create or replace function runner_work_gate(p_runner uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g record;
begin
  if p_runner is null then raise exception 'runner_required'; end if;
  -- [0116 §D ⓑ] PARTY GATE FIRST — a client may ask about themselves and nobody else.
  if auth.uid() is not null and auth.uid() <> p_runner then raise exception 'not_party'; end if;
  select * into g from _runner_work_gate_blocking(p_runner);
  if g.booking_id is null then
    return jsonb_build_object('gated', false);
  end if;
  return jsonb_build_object(
    'gated', true,
    'booking_id', g.booking_id,
    'status', g.status,
    'run_ended_at', g.run_ended_at,
    'runner_confirmed', g.runner_confirmed,
    'owner_confirmed', g.owner_confirmed,
    'waiting_on', g.waiting_on,
    -- The exit, named in the payload rather than left to each caller to reinvent — the same
    -- reason 0083 raises distinct exception names: a caller that has to compose the remedy
    -- itself will eventually compose a different one.
    'exit', case g.waiting_on
              when 'runner' then 'runner_confirm_return'
              when 'owner'  then 'owner_confirm_return'
              -- [0224 §E] a stranded custody's exit is the run itself, never a return stamp
              when 'start_run' then 'runner_start_run'
              when 'end_run'   then 'runner_end_run'
              else 'both_confirm_return'
            end);
end $$;

revoke execute on function runner_work_gate(uuid) from public, anon;
grant  execute on function runner_work_gate(uuid) to authenticated, service_role;

comment on function runner_work_gate is
  '0092 ⑫ + 0116 §D ⓑ + 0224 §E — may this runner take new work? Sean 2026-08-13: "pay the runner but
dont let them make new runs until the dog is confirmed by both sides". DERIVED, never cached. Party
gate first: a signed-in caller may ask only about THEMSELVES (not_party otherwise). 0224 adds two
exit words for a stranded custody — runner_start_run / runner_end_run — beside the three return exits;
no new key, so the accept path''s response shape is unchanged.';

-- 0096 §7's roster of gated runners, which promised in prose to be 「0092의 술어와 같은 모양」. It is
-- now the same predicate by construction: the same lateral read of §B, the same third arm.
create or replace function ops_gated_runners()
returns table (
  runner_id uuid,
  booking_id uuid,
  status text,
  gated_since timestamptz,
  waiting_on text,
  remedy text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.runner_id,
         b.id,
         b.status::text,
         coalesce(x.due_at, b.run_ended_at, b.updated_at, b.scheduled_at),
         coalesce(x.shape,
                  case
                    when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
                      then 'both'
                    when b.runner_confirmed_return_at is null then 'runner'
                    else 'owner'
                  end),
         case
           when x.shape = 'start_run' then 'the runner starts the run (start_run) — no ops door ends a custody strand; that is Sean''s letter (0224 §0c)'
           when x.shape = 'end_run'   then 'the runner stops the run (end_run) — no ops door ends a custody strand; that is Sean''s letter (0224 §0c)'
           when b.status::text = 'incident_review' then 'either party may confirm_return_tx — allowed from incident_review since 0096; clears the gate without settling'
           else 'either party may confirm_return_tx as normal'
         end
    from bookings b
    left join lateral (
      select cs.shape, cs.due_at
        from _custody_strand(b.id) cs
       where b.status::text in ('picked_up', 'active')
         and cs.stranded is true
    ) x on true
   where b.runner_id is not null
     and b.club_session_id is null
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and (
           (b.run_ended_at is not null and b.status::text = 'active')
           or b.status::text = 'incident_review'
           or x.shape is not null
         )
   order by coalesce(x.due_at, b.run_ended_at, b.updated_at, b.scheduled_at), b.id
$$;

revoke execute on function ops_gated_runners() from public, anon, authenticated;
grant  execute on function ops_gated_runners() to service_role;

comment on function ops_gated_runners is
  '0096 §7 + 0224 §E — every runner currently held by the work gate, one row per blocking booking, with
the remedy by name. Now reads _custody_strand through the same lateral as _runner_work_gate_blocking,
so a stranded custody is listed exactly when it gates, and its remedy says honestly that no ops door
exists. A query function, not a pager. service_role only. 255 0224-A3 pins it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §F the two ops reads — the rows behind the three new bells
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0206 §A's shape, deliberately: zero arguments (there is no parameter by which to point it at a
-- third party's booking), the roster gate FIRST — before any read of any booking — `is not true` so
-- a NULL refuses, flat whitelisted columns, NO money, no contact field, no memo. The dog's name and
-- both parties' display names are carried for 0206 §0c's reason: the operator's task is to find out
-- what happened to THIS dog, and the gate is the same gate that already reaches every other ops read.
--
-- ⚠ WHICH ROSTER GATES WHICH READ — the class of the bell, never `payout_due` by default (0206 §0b):
--   `ops_stranded_custody()` → `return_strand`, the roster §C bells; `ops_sealed_unsettled()` →
--   `payout_due`, the roster §D ① bells. The people who were TOLD are the people who may look.
-- ⚠ `ops_stranded_custody` ADMITS `stranded OR a bell exists for the row's CURRENT shape` — 0206
--   §A's inversion of the sweep's one-shot: a list that hid belled rows would hide exactly the rows
--   an operator was paged about. With both thresholds NULL it shows only rows already belled and
--   invents no deadline of its own. A row belled at `start_run` that has since STARTED is not in
--   the list (its shape changed; the start bell no longer describes it) until it strands again.
-- ⚠ `ops_sealed_unsettled` ADMITS arm ⓐ's candidate predicate conjunct for conjunct
--   (`status = 'active'`, `club_session_id is null`, `settlement_ready_at is not null` — 0201:528-530)
--   and NO age: arm ⓐ reports every such row in its notice on every tick, and the list is that
--   report made readable. `minutes_sealed` carries the age and `notified_at` the bell. The brief's
--   「no ledger row」 conjunct is NOT added: `_settle_sealed_run` writes the ledger row and moves the
--   booking to `completed` in one transaction (0083:720/754), so an `active` row with a ledger row
--   is an anomaly, and hiding an anomaly from the one list that could show it is the inaction class.
create or replace function ops_stranded_custody()
returns table (
  booking_id      uuid,
  dog_name        text,
  owner_name      text,
  runner_name     text,
  status          text,
  shape           text,
  since_at        timestamptz,
  due_at          timestamptz,
  minutes_overdue int,
  strand_minutes  int,
  notified_at     timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class       constant text := 'return_strand';
  -- §C's two ops titles, verbatim; `0224-A4` compares this list against the sweep's own output
  c_start_ops_title constant text := '러닝 시작 좌초 — 확인 필요';
  c_end_ops_title   constant text := '러닝 종료 좌초 — 확인 필요';
  v_uid uuid := auth.uid();
begin
  -- ① THE ROSTER GATE, before any read of anybody's booking
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         cs.shape,
         cs.since_at,
         cs.due_at,
         case when cs.due_at is null then null
              else floor(extract(epoch from (now() - cs.due_at)) / 60)::int end,
         case cs.shape when 'start_run' then f.custody_start_strand_minutes
                       else f.custody_end_strand_minutes end,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id
             and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                          else c_end_ops_title end)
    from bookings b
    cross join lateral _custody_strand(b.id) cs
    left join ops_flags f   on f.id
    left join dogs d        on d.id = b.dog_id
    left join profiles po   on po.id = b.owner_id
    left join profiles pr   on pr.id = b.runner_id
   where b.status in ('picked_up', 'active')
     and (cs.stranded is true
          or exists (select 1 from notifications nt
                      where nt.ref_id = b.id
                        and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                                     else c_end_ops_title end))
   order by cs.due_at nulls last, b.id;
end $$;

revoke execute on function ops_stranded_custody() from public, anon;
grant  execute on function ops_stranded_custody() to authenticated;

comment on function ops_stranded_custody is
  '0224 §F: the rows behind the two custody-strand bells (러닝 시작 좌초 / 러닝 종료 좌초 — 확인 필요).
Gate: the return_strand roster, BEFORE any read (not_signed_in / not_ops). Admits a marketplace custody
that is stranded per _custody_strand OR already belled for its current shape — so with both thresholds
NULL it shows only belled rows and invents no deadline. Carries booking id, dog and both display names,
the raw status (gate on it, never print it), the shape, since_at / due_at / minutes_overdue, the
current threshold and the bell instant. No money, no contact field, no memo. Read-only: ending a
custody is Sean''s letter. 255 0224-A4 pins it.';

create or replace function ops_sealed_unsettled()
returns table (
  booking_id          uuid,
  dog_name            text,
  owner_name          text,
  runner_name         text,
  status              text,
  run_ended_at        timestamptz,
  settlement_ready_at timestamptz,
  minutes_sealed      int,
  notified_at         timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class      constant text := 'payout_due';
  -- §D ①'s title, verbatim; `0224-B3` compares the list against the sweep's own output
  c_seal_ops_title constant text := '정산 미완료 — 확인 필요';
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         b.run_ended_at,
         b.settlement_ready_at,
         floor(extract(epoch from (now() - b.settlement_ready_at)) / 60)::int,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id and nt.title = c_seal_ops_title)
    from bookings b
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── arm ⓐ's candidate predicate (0201:528-530), conjunct for conjunct ───────────────────────
   where b.status = 'active'
     and b.club_session_id is null
     and b.settlement_ready_at is not null
   order by b.settlement_ready_at, b.id;
end $$;

revoke execute on function ops_sealed_unsettled() from public, anon;
grant  execute on function ops_sealed_unsettled() to authenticated;

comment on function ops_sealed_unsettled is
  '0224 §F: the rows behind the 「정산 미완료 — 확인 필요」 bell — every marketplace booking sealed for
settlement (settlement_ready_at set) and still active, i.e. arm ⓐ''s candidate set, which the sweep
reports in its notice every tick. Gate: the payout_due roster, BEFORE any read. Carries booking id,
dog and both display names, raw status, run end, seal instant, minutes sealed, bell instant. No
money, no contact field. Read-only: settling it needs the pricing re-drive 0083 §0f names, which is
not built. 255 0224-B3 pins it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §G _noti_ops_titles — 0214 §A's ledger, plus the three titles this file writes
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied by script; the three entries are appended and nothing else moves. Pure and immutable — no
-- definer, so no `search_path` (0214 §A's note). `_noti_push_category` is NOT re-declared: it reads
-- this function by name, so the new titles become the `ops` category through the existing arm ③.
create or replace function _noti_ops_titles() returns text[]
language sql immutable as $$
  -- Derived from the writers, NEVER hand-listed (§0①). One entry per DISTINCT title; the two
  -- sites that share 「인계 확인 멈춤」 are one entry.
  select array[
    -- ── SQL writers, latest declaration of each function ──
    '지급 대기 — 확인 필요',                                 -- ops_payouts_stuck_sweep      0210:417
    '인계 확인 멈춤 — 확인 필요',                             -- sweep_run_end_recovery       0201:928/976
    '반환 좌초 — 확인 필요',                                 -- sweep_run_end_recovery       0201:768
    '굿즈 수령 신청 — 확인 필요',                             -- claim_gear_tx                §B below
    '카드 해지 실패 — 확인 필요',                             -- _note_revocation_abandoned   0166:166
    '클럽 취소 수수료 인텐트 실패 — 확인 필요',                 -- _club_note_fee_mint_failure  0118:674
    -- ── edge writers, all five through `notifyOps` (_shared/ops.ts:163 sets kind:"system") ──
    '결제 자동 취소 실패 — 수동 취소 필요',                     -- COPY.payment_manual_cancel   ops.ts:65
    '이동 중 취소 보상 기록 실패 — 수동 확인 필요',              -- COPY.enroute_comp_failed     ops.ts:69
    '결제 취소 실패 기록이 남지 않았어요 — 즉시 확인 필요',       -- COPY.payment_marker_lost     ops.ts:79
    '취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요',    -- COPY.late_comp_failed        ops.ts:84
    '운영 확인이 필요한 이벤트가 있어요',                        -- generic()                    ops.ts:124
    -- ── [0224] three more SQL writers ──
    '러닝 시작 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '러닝 종료 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '정산 미완료 — 확인 필요'                                 -- sweep_run_end_recovery ⓐ     0224 §D
  ]::text[]
$$;

revoke execute on function _noti_ops_titles() from public, anon, authenticated;

comment on function _noti_ops_titles is
  '0214 §A + 0224 §G: every title written with kind=''system'', i.e. every notification ADDRESSED TO THE
OPS ROSTER — fourteen: nine SQL writers through ops_recipients_for(<class>) (0224 adds the two custody
strand bells and the sealed-unsettled bell) and five through _shared/ops.ts''s notifyOps. Consulted by
_noti_push_category: a system row whose title is here is the ''ops'' category (disableable by
notification_prefs.ops); any other system title is ''booking''. Adding a system writer means adding its
title HERE, in a new re-declaration. Pinned by 245 0214-T1/T2/T4, 255 0224-B2 and
app/test/ops-system-titles.test.cjs, which re-derives the set from the writers'' own source.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §H generate_recurring_bookings — the pause notice, at most once per 24 h per owner per episode
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied by script from 0180 §A; ONE edit, to the ⓓ guard. `v_notified` stays — it is still the
-- intra-call guard (two series of one owner in one tick → one row) — and it gains a durable twin:
--
--     … and not exists (a 「반복 예약 일시 중지」 row for this owner created in the last 24 h
--                       that no cron-generated booking of theirs is NEWER than)
--
-- ⚠ MATCHED BY PROFILE + TITLE, because the row's `ref_id` is NULL by construction (it is about the
--   money gate, not a booking — `notification-route.test.cjs` pins that NULL).
-- ⚠ **THE EPISODE CONJUNCT IS WHY THIS IS NOT JUST THE 24 h WINDOW THE BRIEF ASKED FOR.** A bare
--   window opens an inaction hole of its own: owner blocked at 10:00 (told), debt cleared at 11:00,
--   the series generates a booking, a NEW failure blocks it again at 15:00 — and a bare 24 h window
--   says nothing, so the owner, who was told 「결제 문제를 해결하면 다시 시작돼요」 and did exactly
--   that, never learns it paused again. So an earlier notice counts only while no booking of this
--   owner's series has been created SINCE it — a fact that already happened, not a second clock.
--   ⚠ `created_at` of a booking made by this same tick equals the notice's (both `now()`), and the
--   comparison is STRICT, so a same-transaction booking never resets the episode it sits beside —
--   and an owner-level block stops every series of that owner in the tick anyway.
-- ⚠ NO COPY CHANGE (the brief's instruction, and the body already says it resumes when the debt
--   clears). The title, body and NULL ref are byte-identical to 0180's, so
--   `app/test/notification-route.test.cjs`'s reads of 0180 still describe the deployed strings.
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
  v_live boolean;              -- [0080] cutover switch, read once per sweep
  v_block text;                -- [0080] null | 'debt' | 'no_card'
  v_notified uuid[] := '{}';   -- [0080] owners already told this sweep (ⓓ)
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  -- [0180] the bounded wait (0117 MINOR-14's other half, late_booking_sweep's value): the dog
  -- locks below can WAIT, and a sweep stalled on one holds every lock it already took. Past 2 s
  -- the statement raises, this transaction and its locks release, and the next tick retries.
  perform set_config('lock_timeout', '2000', true);

  -- [0180] deterministic candidate order: two overlapping ticks take the dog locks below in the
  -- same sequence, so they queue instead of deadlocking (0117 MINOR-14's lesson, applied here).
  for s in select * from recurring_series where not paused and dog_id is not null
           order by dog_id, id loop
    v_dow := (s.rule->'weekdays'->>0)::int;
    v_time := s.rule->>'time';
    if v_dow is null or v_time is null then continue; end if;

    -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
    v_kst_now := now() at time zone 'Asia/Seoul';
    v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
    v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
    if v_sched < now() + interval '2 hours' then
      v_sched := v_sched + interval '7 days';
    end if;
    if v_sched > now() + interval '72 hours' then continue; end if;

    -- [0180] THE DOG LOCK — the same key text `create_booking_hold_tx` (0179) takes, so this sweep
    -- and an edge hold for the same dog SERIALIZE: whichever runs second sees the first's committed
    -- row in the clash guard below. Transaction-scoped and held to COMMIT on purpose — releasing it
    -- early (a session lock unlocked in an exception arm, 0117's job-lock shape) would let an edge
    -- hold take the lock, read a snapshot with this sweep's row still uncommitted, and pass: the
    -- exact race this lock exists to close. Taken only for a series with something due (after the
    -- 72h gate), before any read of this dog's bookings. The edge takes key-lock then dog-lock; this
    -- sweep takes only dog locks, in `order by dog_id` sequence, so no lock cycle is possible.
    perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || s.dog_id::text, 0));

    -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
    if exists (
      select 1 from bookings
      where series_id = s.id
        and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
    ) then continue; end if;

    v_start := v_sched;
    v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

    -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
    select exists (
      select 1 from bookings c
      where c.dog_id = s.dog_id
        and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
        and c.scheduled_at < v_end
        and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
    ) into v_clash;
    if v_clash then continue; end if;

    -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
    v_runner := null;
    select b2.runner_id into v_runner from bookings b2
    where b2.series_id = s.id and b2.runner_id is not null
      and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
    order by b2.scheduled_at desc limit 1;
    if v_runner is not null then
      begin
        select is_slot_available(v_runner, v_start, v_end) into v_avail;
      exception when others then
        v_avail := false;
      end;
      if not coalesce(v_avail, false) then v_runner := null; end if;
    end if;

    -- ⓑ/ⓒ [0080 §0-ter #3] money gates — the last thing before the insert.
    v_block := null;
    if owner_has_unsettled_charge(s.owner_id) then
      v_block := 'debt';
    elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = s.owner_id) then
      v_block := 'no_card';
    end if;
    if v_block is not null then
      -- ⓓ once per owner per sweep (v_notified) — [0224 §H] AND at most once per 24 h per owner
      -- per EPISODE: an earlier pause notice counts only while no booking of this owner's series
      -- has been created since it (the owner fixed it, it resumed, it broke again ⇒ tell them).
      if not (s.owner_id = any(v_notified))
         and not exists (
           select 1 from notifications nt
            where nt.profile_id = s.owner_id
              and nt.title = '반복 예약 일시 중지'
              and nt.created_at > now() - interval '24 hours'
              and not exists (select 1 from bookings gb
                                join recurring_series gs on gs.id = gb.series_id
                               where gs.owner_id = s.owner_id
                                 and gb.created_at > nt.created_at)) then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (s.owner_id, 'booking', '반복 예약 일시 중지',
                '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null);
        v_notified := v_notified || s.owner_id;
      end if;
      continue;
    end if;

    -- ⓔ [0111] the series row is a snapshot, and a snapshot can go stale or (before this
    -- migration) be FORGED. Ownership is re-asked at copy time, not trusted from write time.
    -- A silent `continue` would make a skipped series indistinguishable from a series with
    -- nothing due, so say so in the log first — this warning is the ONLY signal that the second
    -- belt fired at all. `continue`, never `raise`: see this file's §3 header.
    if not exists (select 1 from dogs d where d.id = s.dog_id and d.owner_id = s.owner_id)
       or (s.address_id is not null
           and not exists (select 1 from addresses a where a.id = s.address_id and a.owner_id = s.owner_id))
    then
      raise warning 'recurring_series % skipped: dog/address not owned by series owner', s.id;
      continue;
    end if;

    insert into bookings
      (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
       km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values
      (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
       (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
       v_sched, s.km, s.pace_label, s.addons,
       s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
    returning id into v_bid;

    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.owner_id, 'booking', '반복 러닝 예약 생성',
            to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
            || ' 러닝이 자동 예약됐어요'
            || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
            v_bid);
    if v_runner is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_runner, 'booking', '지명 러닝 요청',
              '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
    end if;

    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘 + [0111] 복사 시점 소유권 재확인 + [0180] 강아지별 xact 락 —
+ [0224 §H] the pause notice (「반복 예약 일시 중지」) is sent at most once per 24 h per owner, and a
new block after the owner''s series has produced a booking again is a new episode and is told again
(backend-logic-4: v_notified reset every hourly tick, so a blocked owner was re-told for up to 72 h).
Title, body and NULL ref unchanged. 255 0224-C1 pins it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §I ops_resolve_return_tx — the operator's id leaves the party-readable blob (F6)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0201 §A's body, copied by script, with exactly ONE line removed: the `resolved_by` key of the
-- `jsonb_build_object` that becomes `bookings.return_force_evidence`. Everything else — the
-- server-only caller class, the ops gate ahead of the lock, the state gates on the LOCKED row, the
-- fixed-token reason, the journal INSERT (which KEEPS `resolved_by`: `return_resolutions` requires
-- an actor on this source, 0218's CHECK), `_settle_sealed_run`, the response — is 0201's.
--
-- WHY IT IS WORTH A SLICE AT ALL, given the amplification is closed (0214 §0c: `profiles` refuses the
-- party, measured B1b there): an operator's profile id is a stable identifier for a PERSON on the ops
-- roster, and both parties read it straight out of PostgREST. The dispute record does not need it —
-- the journal holds it, sealed, where a dispute reader with the right to see it looks. 0218 already
-- composed the FORCE's public blob without an actor for exactly this reason; this makes the
-- resolver's match.
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
  v_reason  text;
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
  v_reason := case v_from
                when 'active'          then 'ops_resolved:strand'
                when 'incident_review' then 'ops_resolved:review'
                else                        'ops_resolved'
              end;
  update bookings
     set status                = 'active',
         return_forced_by      = 'ops',
         return_forced_at      = v_now,
         return_force_reason   = v_reason,
         return_force_evidence = jsonb_build_object(
           'source', 'ops_resolve_return_tx',
           'from_status', v_from,
           'runner_stamped', (b.runner_confirmed_return_at is not null),
           'owner_stamped',  (b.owner_confirmed_return_at is not null),
           -- [0224 §I] no operator id in the party-readable blob; the journal row below keeps it
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
  '0193 §C-b → 0201 §A → 0224 §I: the ops adjudication of a stranded 1:1 return. Server-only caller,
return_strand roster gate before the lock, state gates on the locked row, the party-readable reason is
a fixed token keyed by the rescued-from state, and — since 0224 — the party-readable evidence blob
carries {source, from_status, runner_stamped, owner_stamped, resolved_at} and NO operator id: the
sealed return_resolutions journal keeps resolved_by and the memo. Settles through _settle_sealed_run.
232 0201-M1/S1 and 255 0224-D1 pin it.';

-- The IDEMPOTENT repair for blobs the resolver wrote before this file. A FUNCTION called once below,
-- not an inline DO block, for 0201 §B's reason: a one-time block has already run by the time any
-- suite connects, so no pin could redden it. As a function the property is falsifiable — `0224-D1`
-- builds the pre-0224 shape and calls it twice.
-- ⚠ Keyed on the KEY, not on a writer: the property is 「no party-readable return blob carries an
--   actor id」, whoever wrote it. After 0218 the force's blob is server-composed without one, so in
--   practice this touches only resolver rows. `jsonb_typeof = 'object'` because `?` also matches a
--   string element of an ARRAY and `-` would then delete an array element — a shape nobody writes,
--   and not a thing to leave to chance in a repair that runs once on production.
-- ⚠ The final conjunct is the value about to be written, so a second run returns 0.
create or replace function _scrub_resolver_actor_0224() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int := 0;
begin
  update bookings b
     set return_force_evidence = b.return_force_evidence - 'resolved_by'
   where jsonb_typeof(b.return_force_evidence) = 'object'
     and b.return_force_evidence ? 'resolved_by';
  get diagnostics v_n = row_count;
  raise notice '_scrub_resolver_actor_0224: % booking(s) carried an operator id in return_force_evidence; removed (the journal keeps it)', v_n;
  return v_n;
end $$;

revoke execute on function _scrub_resolver_actor_0224() from public, anon, authenticated;
grant  execute on function _scrub_resolver_actor_0224() to service_role;

comment on function _scrub_resolver_actor_0224 is
  '0224 §I (F6): removes the resolved_by key from every party-readable bookings.return_force_evidence
object that carries one. Idempotent (a second call returns 0). The sealed return_resolutions journal
is untouched and keeps the actor. Called once by 0224; 255 0224-D1 pins it.';

do $$
declare v_n int;
begin
  select _scrub_resolver_actor_0224() into v_n;
  raise notice '0224 §I: one-time scrub of resolved_by from bookings.return_force_evidence — % row(s)', v_n;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time SHAPE only. Behaviour is suite 255's (apply-time checks are protected only
-- until somebody recreates the function, 0131-G4's lesson), and keeping VERIFY to shape keeps the
-- mutation battery measuring the suite rather than this block.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  fn text;
  v_src text;
  server_only text[] := array['_custody_strand(uuid)', '_sweep_custody_strands()', 'sweep_run_end_recovery()',
                              '_runner_work_gate_blocking(uuid)', 'ops_gated_runners()',
                              'ops_resolve_return_tx(uuid,jsonb,text,uuid)', '_scrub_resolver_actor_0224()',
                              'generate_recurring_bookings()'];
  signed_in   text[] := array['ops_stranded_custody()', 'ops_sealed_unsettled()', 'runner_work_gate(uuid)'];
begin
  foreach fn in array server_only || signed_in loop
    if to_regprocedure('public.' || fn) is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || fn)
                    and p.prosecdef and 'search_path=public, pg_temp' = any(coalesce(p.proconfig, '{}')))
      then v_bad := v_bad || ' ' || fn || ': not a definer with the in-body search_path;'; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': anon can execute;'; end if;
  end loop;
  foreach fn in array server_only loop
    if to_regprocedure('public.' || fn) is not null
       and has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': authenticated can execute (server-only);'; end if;
  end loop;
  foreach fn in array signed_in loop
    if to_regprocedure('public.' || fn) is not null
       and not has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': authenticated cannot execute (the door is dead);'; end if;
  end loop;
  if has_function_privilege('authenticated', 'public._noti_ops_titles()', 'execute')
    then v_bad := v_bad || ' _noti_ops_titles: authenticated can execute;'; end if;
  -- the thresholds ship NULL — a default here would be a deadline nobody chose
  if (select custody_start_strand_minutes is not null or custody_end_strand_minutes is not null
        from ops_flags where id) is not false
    then v_bad := v_bad || ' ops_flags: a custody threshold is not NULL at apply (Sean''s number, not a migration''s);'; end if;
  -- the two new sources exist as code (NO-SOURCE fails loudly rather than reading as clean)
  foreach fn in array array['_sweep_custody_strands', 'sweep_run_end_recovery', 'ops_resolve_return_tx',
                            'generate_recurring_bookings'] loop
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = fn;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(' || fn || ');'; end if;
  end loop;
  if v_bad <> '' then raise exception '0224 VERIFY failed:%', v_bad; end if;
  raise notice '0224 VERIFY ok — shapes and ACLs as declared; the two custody thresholds ship NULL';
end $$;
