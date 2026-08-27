-- ═══ 0144: 러닝 종료 — THE CLUB PACK RUN-END FAN-OUT (the host's single tap) ═══════════════
--
-- Contract: `docs/contracts/club-pack-run-end-contract.md`. ⚠ **§0-bis and §11 override §1–§10
-- wherever they conflict**, and this file is built against §0-bis, not against §1–§10. Thirteen
-- claims in §1–§10 are void; the three that decide the SHAPE of this file are R-1, R-2 and R-3,
-- and each was re-read at source in this tree before a line was written (citations below).
--
-- Sean, 2026-08-26, §11, all four answers RULED:
--   ① each runner's numbers are **computed SERVER-SIDE** (overruling §2 ARM 3's rejection)
--   ② the **backup host** may press 러닝 종료
--   ③ duration is measured to **the host's tap**, not the runner's own settle
--   ④ a pair blocked by an open case is named **on the run-end screen**
-- and §11.2, the objection that survived: **the CHARGE stays its own gated step.** This file
-- mints nothing, moves no ledger row, and computes no fare. §D's VERIFY enforces that at the
-- level of the function's own source text, not as a promise in a comment.
--
-- ═══ §0a THE TWO TRAPS THIS FILE IS BUILT AGAINST — both verified at source, here ═══════════
--
-- 🔴 **R-2 — THE SILENT-OVERWRITE NO-OP. This is the most likely way to build the ruled feature
-- and have it do nothing at all.** Two halves, both read in this tree:
--   · `0083_run_end_flow.sql:744` — `actual_km = case when v_run_ended is null then
--     excluded.actual_km else runs.actual_km end`, where `v_run_ended` is `bookings.run_ended_at`
--     (`0083:670` reads it). The line above it says so in the file's own words: 「정지 스탬프가
--     없는 행(레거시·클럽 경로)은 0028 그대로 excluded가 이긴다」. A club booking has never carried
--     that stamp (`0083:383` refuses clubs in `end_run_tx`, the only other writer), so the
--     DEVICE's number has always won.
--   · `supabase/functions/settle-run/handler.ts:77` — `const frozen = bk.run_ended_at ? await
--     readFrozenRun(…) : null;` and `:115` — `const km = frozen ? frozen.km : Number(p.actual_km);`
--     For a club booking `frozen` was ALWAYS null, so the phone's number reached
--     `compute_runner_payout` and priced the ledger.
--   **Therefore the freeze must be COMPLETE: `bookings.run_ended_at` AND `runs.{ended_at,
--   actual_km, duration_sec, end_reason}` in the same statement set.** Half of it is worse than
--   none of it, in BOTH directions, and §C is written so neither half can ship alone:
--     · stamp only → the device still wins and every gate stays green (the no-op);
--     · `runs` only, or `run_ended_at` with a NULL `actual_km` → `settle_run_tx`'s §6-ⓔ gate
--       (`0083:709-717`) compares `round(p_actual_km,2)` against the frozen value and a frozen
--       NULL is `distinct from` every number, so **every club settle would raise
--       `frozen_measurement_mismatch` forever** — the runner is never paid.
--   A pair whose numbers cannot be derived is therefore **BLOCKED and left completely unstamped**,
--   never stamped-and-empty. That is the single most load-bearing sentence in this file.
--
-- 🔴 **R-1 — `custody_phase` is DERIVED, so this file does not write it, and does not try.**
-- `session_dogs` carries `club_v1_axes_sync` (`0040:280-282`), BEFORE INSERT OR UPDATE, FOR EACH
-- ROW, no WHEN clause, which recomputes every axis from `_club_compute_axes` (live definition
-- `0048:687`) on every write. That function derives `custody_phase` from `bookings.status`
-- (`0048:806-807`: `case when v_bst = 'completed' then 'return_pending' else 'with_custodian'`),
-- so §1-ⓑ's 「the fan-out writes custody_phase = 'return_pending'」 **cannot stick** — it would
-- normalise straight back with no exception, no red gate and nothing dirty.
--   **Consequence, stated loudly rather than discovered later: this slice does NOT make the
--   return reachable before the runner settles.** The pair proceeds to settle → `completed` →
--   the 0045 trigger → `return_pending` → transfer, exactly as today. What the tap changes is
--   WHOSE numbers and WHICH instant the record carries — which is precisely what §11.1 says the
--   ruling is for. Re-keying `_club_compute_axes` so `return_pending` is reachable while the
--   booking is `active` is a real and separate decision (it moves a derived axis that four
--   shipped functions read); it is NOT smuggled in here.
--   §D's VERIFY asserts the normalizer is still present, still enabled and still keyed the way it
--   was, so 「we deliberately did not touch it」 is a measured statement and not a claim.
--
-- ⚠ **R-3 — `runs.ended_at` IS THE CHARGING CUTOVER, and this file moves it. NAMED CONSEQUENCE.**
-- `mint_settle_charge_intent` (live body `0084_g1_ops_cutover.sql:265-266`) compares
-- `coalesce(r.ended_at, now())` against `ops_flags.payments_live_since`. Until this file, a club
-- run's `runs.ended_at` was written only by `settle_run_tx` and therefore meant **settlement
-- time**; from this file it means **the host's tap** — the honest stop time, and the same meaning
-- 0083 §0③ gave it for the marketplace. The direction of the change is the safe one: a run that
-- stopped before the cutover but settles after it is now FREE, which is 0080's 「no retroactive
-- charging」 law working. `payments_live_since` is NULL today, so **no harness green can see
-- this** (the 「a green light is evidence for exactly one sentence」 shape, the sentence being
-- 「charging is off, so nothing here is measured」) — suite 176 P8 therefore SETS the flag and
-- measures both directions.
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO ═════════════════════════════════════════════════════════
-- - **No money.** No ledger row, no charge intent, no fare, no rate, no `payout_state`. The host
--   declares WHEN, the server derives WHAT, and the charge stays its own gated step (§11.2).
-- - **No `bookings.status` write.** The runner's own settle still claims `active → completed`
--   and still writes the ledger, unchanged — which is why ARM 1 (§2) is rejected: a status claim
--   here would make the runner's settle raise `not_active` and leave them unpaid forever.
-- - **No custody write, no `custody_phase`, no `session_dogs` write at all** (R-1).
-- - **No marketplace object.** `end_run_tx`, `settle_run_tx`, `confirm_return_tx`,
--   `force_return_tx`, `compute_owner_charge`, `compute_runner_payout`, `settle-run`,
--   `transition-booking` and `ops_flags` are all untouched. `end_run_tx` refuses clubs at
--   `0083:383`; this is a SIBLING of it, never a reuse.
-- - **No new column.** A `run_end_by` column was considered and rejected: it would have no reader,
--   which is `0060:52`'s 「한 번도 쓰인 적 없는 빈 껍데기」. The provenance is already derivable and
--   exact — **`bookings.run_ended_at is not null` on a club booking means「the host ended this
--   run」**, uniquely, because `end_run_tx` is the only other writer of that column and it refuses
--   clubs. `runs.settled_at is null` beside it distinguishes 「ended, not yet settled」.
-- - **No sweep, cron or expiry** for a session whose runs were never ended, and no client screen.
--
-- ═══ §0c THINGS THIS FILE CHANGES FOR A CLUB BOOKING THAT NEVER CHANGED BEFORE ═══════════════
-- `bookings.run_ended_at` on a club row is new in the world. Every shipped reader of it was
-- enumerated and read, not assumed:
--   · `_runner_work_gate_blocking` (`0092:110`) — `b.club_session_id is null`. Excluded.
--   · `ops_unsettled_runs` (`0097:88`) — `b.club_session_id is null`. Excluded.
--   · `sweep_run_end_recovery`, both arms (`0083:1437`, `0083:1468`) — `club_session_id is null`.
--   · `confirm_return_tx` (`0096:121`) / `force_return_tx` (`0089:104`) — raise
--     `club_out_of_scope` ABOVE the `run_not_ended` gate, so the new stamp changes no answer.
--   · `sweep_settled_without_payments` (live `0116:60`) — requires `rn.settled_at is not null`,
--     which this file never writes. A tapped-but-unsettled club run is invisible to it.
--   · `owner_has_unsettled_charge` (`0080:507`) — requires a server-minted `payments` row; a stop
--     stamp alone cannot create debt.
--   · `_owner_la_run_end_tg` (`0083:1278`) — fires on this UPDATE and pushes the 귀가 banner if
--     that booking has a live-activity token. Correct rather than incidental: the owner's lock
--     screen should stop claiming a run in progress. It swallows its own errors (`0083:1274`).
--   · `owner_la_sweep_stale` arm ① (`0083:1308`) — now correctly stops claiming 「위치가
--     갱신되지 않았어요」 for a club pair whose run has ended.
--
-- ⚠ **AND ONE THING IT LEAVES OPEN, NAMED HERE RATHER THAN FOUND IN AN INCIDENT.**
-- `club_save_run_trace` (live `0053:124`) is a SECURITY DEFINER and is gated only on
-- `b.status = 'active'`. `_guard_run_cols`'s 「frozen after end」 arm (`0083:295`) bites only on
-- `current_user in ('authenticated','anon')`, so it cannot see a definer. After this tap the
-- runner's app keeps uploading and the trace keeps GROWING past the freeze. The money does not
-- move (`actual_km` is frozen and `0083:744` now preserves it), so this is a record-honesty
-- defect and not a money one — but the marketplace closes it (`end_run_tx` commits the final
-- trace and §2 shuts the window) and clubs do not. The one-line remedy is
-- `and b.run_ended_at is null` in `club_save_run_trace`'s loop selector; it is a re-creation of a
-- shipped function that this slice was not scoped to touch, and it is handed on rather than done
-- quietly. Suite 176 P9 ⓒ **records the current behaviour as measured**, so the follow-on slice
-- inherits a fact and not a suspicion.
--
-- ═══ §0d ONE CONSEQUENCE FOR THE CLIENT, AND IT IS A REAL ONE ═══════════════════════════════
-- After the tap, `settle-run/handler.ts:115-118` takes km, duration, end_reason AND
-- condition_note from the frozen row and IGNORES the body (it logs 「body ignored (frozen)」 at
-- `:82`). So a runner who taps 조기 종료 with `dog_condition` after the host has ended the pack
-- gets `completed` and a server km, silently. That is the ruling working as ruled (③: one
-- instant for the whole pack) — but the run screen must stop OFFERING the early-end reasons for
-- a pair whose run is already ended, or it is a dead choice dressed as a live one.
-- `app/app/club/run/[sid].tsx:230` also refuses to settle at all when `trackMode === 'denied'`,
-- which after this file is wrong for a frozen pair: the server already holds the numbers.
-- **Both are client obligations of the ui slice, named here so they are not rediscovered.**
--
-- ═══ §0e DOCTRINE (0059 money-path list) ════════════════════════════════════════════════════
-- self-contained · party gate before state gate · flat whitelisted return · in-body
-- `set search_path = public, pg_temp` (98 H1 — an ALTER-applied config is reset by
-- `create or replace`) · explicit `revoke` written out every time, never relying on grant
-- preservation (`0116:636`; `check-definer-acl.mjs`) · per-row subtransactions (`0117:1209-1224`)
-- · mutation-proven pins (`176_club_pack_run_end_suite.sql`).

begin;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE DERIVATION — one runner's own trace, truncated to one dog's run, billable metres only
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- **There is no server-side distance derivation anywhere in this repo today.**
-- `club_save_run_trace` computes a distance only to REJECT `impossible_speed` and then discards
-- it (`0053:133-139`). This function is that arithmetic kept instead of thrown away, plus the
-- client's own billable rules.
--
-- ⚠ **THE STORED TRACE IS THE RUNNER'S WHOLE-SESSION TRACE, SHARED ACROSS EVERY DOG THEY HOLD.**
-- `club_save_run_trace` writes the same merged batch into every `active` run of that runner in
-- that session (`0053:145-146`), so a dog handed over late would otherwise inherit the pack's
-- earlier kilometres. Truncation by that run's own `started_at` is not a refinement; it is what
-- makes the number belong to the dog. `app/app/club/run/[sid].tsx:228` records the client
-- learning exactly this: 「늦게 인계된 아이가 그룹 누적 km·최초 경과를 받던 것 — 그 아이의
-- started_at 기준으로 절단」.
--
-- ── EVERY DELIBERATE DIVERGENCE FROM THE CLIENT'S MATH, STATED ─────────────────────────────
--  D1 **Equirectangular, not haversine.** The client bills with `distM` (haversine, `geo.ts:16`);
--     this mirrors `club_save_run_trace`'s own validation math (`0053:137-138`,
--     lat×111000 / lng×88800) instead, so the server never bills a segment its own integrity
--     check would have rejected. At the pilot's latitude (37.51°) the constant 88800 overstates
--     the true 88,338 m/degree by ≈0.5% on the east-west component — a systematic, bounded,
--     upward divergence on that axis, recorded rather than hidden.
--  D2 **Second resolution.** The stored trace is floored to whole seconds before upload
--     (`[sid].tsx:200`, `const t = Math.floor(p.t / 1000)`) while the client accumulates at fix
--     resolution, so the server's polyline is a SUBSET of the client's and the derived distance
--     is systematically ≤ the client's. The explicit second-collapse below is a no-op on any
--     trace our client produced (it is already strictly-increasing whole seconds) and exists so a
--     hand-rolled caller cannot inflate a number with sub-second points.
--  D3 **No accuracy gate.** `acceptFix` drops fixes with `acc > 25` (`geo.ts:31`) — but `acc` is
--     discarded before upload (`[sid].tsx:196` builds `{lat,lng,t}` only), so the server CANNOT
--     reproduce it and does not pretend to. The server trusts the client's accuracy filtering,
--     and a trace uploaded by anything else carries no accuracy claim at all. Named, not fixed:
--     persisting `acc` is a schema change with a client half.
--  D4 **No 10 m/s teleport gate.** `acceptFix`'s gate is client-side; the server has only the
--     8 m/s BILLABLE gate, which is stricter, so a teleport earns nothing here either — it simply
--     stays in the trace, as `geo.ts:73-74` intends («points above it stay in the trace (they
--     happened) but earn nothing»).
--  D5 **Server clock vs device clock.** `runs.started_at` is `now()` on the server
--     (`0050:181`); trace `t` is the OS fix timestamp on the phone (`geo.ts:150-152`). A device
--     clock behind the server drops legitimate early points; ahead, it admits points from before
--     this dog joined. There is no clock-sync fact in the schema to correct with, so this is a
--     RESIDUAL, not a bug hidden by a fudge factor. A skew large enough to strip the window
--     yields fewer than two in-window points and the pair is BLOCKED, never silently zeroed.
--  D6 **`end_run_tx`'s planned-relative band and 50% completion floor are NOT applied.** Those
--     defend against a number a RUNNER declared (`0083:400-410`); this number is derived by the
--     server from a server-validated trace and cannot be inflated by a phone. Applying them here
--     would block the ruled feature wholesale whenever a host picked a route whose recorded km
--     does not match the walk — a refusal with no remedy on the finish line. The absolute band
--     (0…100 km, `0083:406`) IS kept: it is what protects `numeric(5,2)` and what makes a garbage
--     trace visible instead of chargeable.
create or replace function public._club_derive_run_km(p_trace jsonb, p_started timestamptz)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_t0   numeric;
  v_pts  jsonb;
  v_n    int;
  i      int;
  v_prev jsonb;
  v_cur  jsonb;
  v_psec numeric;
  v_csec numeric;
  v_dt   numeric;
  v_d    numeric;
  v_km   numeric := 0;
begin
  if p_trace is null or p_started is null then return null; end if;
  if jsonb_typeof(p_trace) <> 'array' then return null; end if;
  v_t0 := extract(epoch from p_started);

  -- Truncate to this dog's own window and sort. Points with a missing coordinate or timestamp
  -- are dropped rather than defaulted: a fix with no position is not a fix at zero.
  select jsonb_agg(e order by (e->>'t')::numeric)
    into v_pts
    from jsonb_array_elements(p_trace) e
   where jsonb_typeof(e) = 'object'
     and (e->>'t')   is not null
     and (e->>'lat') is not null
     and (e->>'lng') is not null
     and (e->>'t')::numeric >= v_t0;

  -- Fewer than two in-window points is an ABSENCE of measurement, not a measurement of zero, and
  -- the difference decides whether a pair is frozen or blocked. NULL says "I have nothing";
  -- 0.00 says "I looked and the dog did not move", and both are honest answers to different
  -- questions. Returning 0 here is how a fabricated number gets into a ledger.
  if v_pts is null then return null; end if;
  v_n := jsonb_array_length(v_pts);
  if v_n < 2 then return null; end if;

  v_prev := v_pts->0;
  v_psec := floor((v_prev->>'t')::numeric);
  for i in 1 .. v_n - 1 loop
    v_cur  := v_pts->i;
    v_csec := floor((v_cur->>'t')::numeric);
    if v_csec > v_psec then
      v_dt := v_csec - v_psec;
      v_d  := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
      -- geo.ts:103, mirrored exactly: jitter floor, teleport ceiling, and the 8 m/s billable
      -- gate that matches the server's own trace-integrity gate (0053:139).
      if v_d > 2 and v_d < 120 and v_d / v_dt <= 8 then
        v_km := v_km + v_d / 1000;
      end if;
      -- The cursor advances to EVERY accepted point, billable or not — `mergeFixes` does the
      -- same (`geo.ts:105-106`). Carrying a rejected segment forward would let two jitter fixes
      -- add up to one billable one.
      v_prev := v_cur;
      v_psec := v_csec;
    end if;
  end loop;

  -- Rounded to the STORED scale (`runs.actual_km` is numeric(5,2), 0001:239) before it leaves
  -- this function, for 0083's reason: the freeze must operate on the number that will actually
  -- BE frozen, or the caller's honest echo becomes a mismatch (0083:404-406).
  return round(v_km, 2);
end $$;

revoke execute on function public._club_derive_run_km(jsonb, timestamptz)
  from public, anon, authenticated, service_role;

comment on function public._club_derive_run_km is
  '0144 §A — 러너의 세션 전체 트레이스에서 그 개의 런(started_at)만 잘라 과금 거리(km)를 도출한다.
club_save_run_trace의 등장방형 검증 수학(0053:137-138)과 geo.ts mergeFixes의 과금 규칙(2m/120m/8m/s)을
그대로 옮긴 것. 창 안 포인트가 2개 미만이면 NULL(=측정 없음)이지 0이 아니다. 서버 전용.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  club_end_pack_runs — one tap, N pairings, best-effort, with an explicit remainder
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **BEST-EFFORT IS THE DECISION, NOT A CONVENIENCE** (§6). Atomic-or-nothing means one runner
-- mid-incident stops NOBODY's run ending: N owners stand at the finish point with the transfer
-- closed for all of them because one unrelated pairing has an open case, and the host's only
-- remedy is to resolve an incident on the spot — the one thing that cannot be done quickly by
-- design (`club_incident_resolve` requires a settlement first, `0072:276-283`). `0118:64` records
-- this repo already paying for that shape once: one raise inside a session-wide loop rolled the
-- WHOLE thing back and a session's worth of refunds was lost. Best-effort makes the blast radius
-- of a failure proportional to the failure.
--
-- ⚠ **THREE LISTS, NEVER A COUNT** (§6.2). 「3 of 4」 cannot be rendered honestly and cannot be
-- acted on. `already` means 「nothing to do here」; `blocked` means 「this dog's run did not end and
-- somebody must act」, and it carries the dog's NAME because a remainder the host cannot name is
-- the 「silent catch → happy UI」 the honesty law forbids. Merging the two lists is the mutation
-- M7 exists to catch.
--
-- ⚠ **`blocked` IS A REPORT, NOT A REFUSAL.** The call succeeds. The host is not blocked from
-- anything, least of all 세션 종료, which has its own gates (`dogs_not_returned`,
-- `incident_unassigned`, `0118:1121-1127`) and is the correct place for that refusal.
create or replace function public.club_end_pack_runs(p_session uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s        record;
  r        record;
  v_bk     record;
  v_at     timestamptz;
  v_ended  jsonb := '[]'::jsonb;
  v_block  jsonb := '[]'::jsonb;
  v_alrdy  jsonb := '[]'::jsonb;
  v_verd   text;
  v_reason text;
  v_inc    uuid;
  v_km     numeric;
  v_dur    int;
  v_has    boolean;
  v_start  timestamptz;
  v_rend   timestamptz;
  v_trace  jsonb;
begin
  -- ── 1-5: feature gate, then PARTY gate, then STATE gate (repo law) ────────────────────────
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- The session lock is taken here and held for the whole call: it serialises this tap against
  -- the other tap, against club_incident_open (0070:410), against club_finish_session
  -- (0118:1115) and against club_release_payouts (0072:231), which is the discipline every club
  -- session-wide mutation already follows.
  select cs.id, cs.host_profile_id, cs.backup_host_profile_id, cs.status
    into s
  from club_sessions cs where cs.id = p_session for update;
  -- A session that does not exist answers EXACTLY what a session that is not yours answers.
  -- 0070:186-189's law, and the reason 0067 §C killed the existence oracle 0069 revived.
  if s.id is null then raise exception 'not_host'; end if;

  -- ⚠ `is distinct from` twice, NEVER `auth.uid() in (host, backup)`. With
  -- `backup_host_profile_id` NULL the `in` form folds to NULL and `not (NULL)` never fires — the
  -- fail-open this repo has already shipped twice (`0072:117-121`, `0116:410`). `0070:195-196`
  -- is the exact idiom copied.
  --
  -- ⚠ HOST **AND BACKUP**, and the asymmetry with 세션 종료 is DELIBERATE (§11.3, ruled thirty-five
  -- seconds apart from 「backup may not remove a member」). 러닝 종료 is a practical act by whoever
  -- is standing at the finish line, and `0070:191-193` already measured the host-only version of
  -- exactly this situation: 「소규모 클럽의 호스트가 곧 러너라 self_override로 막히고, 백업은
  -- not_host로 막혔다 — 독립 리뷰가 실행해서 증명」. 세션 종료 (`club_finish_session`, host-only,
  -- `0118:1113-1114`) is untouched by this file.
  if auth.uid() is distinct from s.host_profile_id
     and auth.uid() is distinct from s.backup_host_profile_id then
    raise exception 'not_host';
  end if;
  if s.status not in ('open', 'full') then raise exception 'session_closed'; end if;

  -- ONE clock for the whole tap (§6.2). Per-pairing `now()` inside one transaction returns the
  -- same value anyway; naming it makes the invariant explicit and testable, and it is what makes
  -- ruling ③ ('duration is measured to the host's tap') mean one instant rather than N.
  v_at := now();

  -- One abandoned row lock must not stall the whole tap (`0117:1209`, codex MEDIUM-11).
  perform set_config('lock_timeout', '2000', true);

  for r in
    select sd.id as sd_id, sd.dog_id, sd.booking_id, d.name as dog_name
      from session_dogs sd
      join dogs d      on d.id = sd.dog_id
      join bookings b  on b.id = sd.booking_id
     where sd.session_id = p_session
       and sd.custody = 'runner_delegated'
       and sd.booking_id is not null
       -- 163's M1: the pairing and its booking must agree about which session they are in.
       and b.club_session_id = sd.session_id
     -- Deterministic order so two overlapping taps queue instead of deadlocking (0117:1216).
     order by sd.id
  loop
    v_verd := 'ended'; v_reason := null; v_inc := null; v_km := null; v_dur := null;

    -- ── the per-pairing subtransaction (0117:1213). NOT the per-row-COMMIT procedure form: a
    -- club session is a handful of pairings tapped once, not a 50-row cron tick, and a procedure
    -- that COMMITs cannot be called from a DO block, which would make every suite fixture harder
    -- for no benefit. Stated so a later session does not "upgrade" it without a reason.
    begin
      -- Lock order is bookings-then-runs, the same order 0083:670 takes before its own upsert,
      -- so the settle path and this one can never deadlock against each other.
      select bk.id, bk.status::text as status, bk.run_ended_at, bk.runner_id, bk.owner_id
        into v_bk
      from bookings bk where bk.id = r.booking_id for update;

      select true, rn.started_at, rn.ended_at, rn.trace
        into v_has, v_start, v_rend, v_trace
      from runs rn where rn.booking_id = r.booking_id for update;

      if v_bk.id is null then
        v_verd := 'blocked'; v_reason := 'not_found';       -- FK makes this unreachable; belt.

      -- Idempotence and order-independence. If the runner settled first, that run HAS ended and
      -- this is not an error — 0083:386-388's law, 「a second stop is not the same stop」 read the
      -- other way round. Checked UNDER the row lock so the write below can only confirm it.
      elsif v_bk.status = 'completed' then
        v_verd := 'already'; v_reason := 'already_settled';
      elsif v_bk.run_ended_at is not null or v_rend is not null then
        v_verd := 'already'; v_reason := 'already_ended';

      -- Handed over but never started: the runner has the dog and never tapped 시작. There is no
      -- run to end and no honest number to derive, so it is BLOCKED and named — the host can see
      -- whose it is and go and ask.
      elsif v_bk.status = 'picked_up' then
        v_verd := 'blocked'; v_reason := 'not_started';

      -- Anything else non-active: cancelled, refunding, or force-resolved into `incident_review`
      -- (`session_host_force_resolve`, 0070:213). That dog's run was ended by a case, not by the
      -- pack, and the host is told by name rather than left to infer it from silence.
      elsif v_bk.status <> 'active' then
        v_verd := 'blocked'; v_reason := 'not_active';

      else
        -- The shipped incident predicate, COPIED not reinvented — `club_release_payouts`'s
        -- second defence line, `0072:239-244`, which is a disjunction over the DOG **or** the
        -- BOOKING. A dog-only read is narrower than the shipped rule, so the incident id is
        -- returned here for the screen to act on.
        select i.id into v_inc
          from club_incident_subjects sub
          join club_incidents i on i.id = sub.incident_id
         where i.state <> 'resolved'
           and i.session_id = p_session
           and ((sub.subject_type = 'dog'     and sub.subject_id = r.dog_id)
             or (sub.subject_type = 'booking' and sub.subject_id = r.booking_id))
         order by i.id
         limit 1;

        if v_inc is not null then
          v_verd := 'blocked'; v_reason := 'incident_open';
        elsif not coalesce(v_has, false) or v_start is null then
          v_verd := 'blocked'; v_reason := 'not_started';
        else
          v_km := _club_derive_run_km(v_trace, v_start);
          if v_km is null then
            -- No usable fixes in this dog's window (GPS refused, app never ran, clock skew).
            -- The pair is left COMPLETELY unstamped and the runner's own settle still works
            -- exactly as it does today — that is the remedy, and it is why a fabricated 0.00 is
            -- not written here.
            v_verd := 'blocked'; v_reason := 'no_trace';
          elsif v_km < 0 or v_km > 100 then
            v_verd := 'blocked'; v_reason := 'km_out_of_band';
          else
            -- Mirrors `[sid].tsx:254` + `:268` — measured elapsed, floored at one second because
            -- zero is not a duration anything can render. `Math.max(60, …)` was removed from the
            -- client on the day it was recognised as inventing time (`[sid].tsx:229`); this does
            -- not reintroduce it.
            v_dur := greatest(1, extract(epoch from (v_at - v_start))::int);

            -- ═══ THE FREEZE. BOTH STATEMENTS OR NEITHER — see §0a R-2. ═══════════════════════
            -- They are in one subtransaction, so any failure in either leaves the pairing
            -- untouched and it is reported as blocked. The `runs` row is written FIRST for
            -- 0083:415's reason: the homeward banner fires on the bookings UPDATE and reads the
            -- frozen numbers off `runs`, so stamping first would push a banner carrying blanks.
            update runs set
              ended_at            = v_at,
              actual_km           = v_km,
              duration_sec        = v_dur,
              avg_pace_sec_per_km = case when v_km > 0 then round(v_dur / v_km)::int end,
              end_reason          = 'completed'::end_reason
            where booking_id = r.booking_id;

            update bookings set run_ended_at = v_at
             where id = r.booking_id and run_ended_at is null;

            -- Both notifications are inside this pairing's subtransaction: a notification for a
            -- pairing that did not end is a lie, and it must roll back with it (§4.4).
            -- ⚠ Neither says anything about money. The owner is not told what anything cost and
            -- the runner is not told they have been paid — the charge is its own gated step.
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_bk.owner_id, 'booking', '러닝 종료',
                    r.dog_name || '의 러닝이 끝났어요 — 기록을 정리하고 있어요', r.booking_id);
            if v_bk.runner_id is not null then
              insert into notifications (profile_id, kind, title, body, ref_id)
              values (v_bk.runner_id, 'booking', '러닝 종료',
                      '호스트가 팩 러닝을 종료했어요 — ' || r.dog_name ||
                      '의 기록이 준비됐어요, 마무리해주세요', r.booking_id);
            end if;
          end if;
        end if;
      end if;

    exception
      when lock_not_available then
        v_verd := 'blocked'; v_reason := 'locked';
      when others then
        -- ⚠ `when others` catches a BUG as readily as a busy row, so every caught pairing is
        -- named in the remainder AND raised as a warning: a genuine defect surfaces in the log
        -- instead of being laundered into 「one dog couldn't end」.
        v_verd := 'blocked'; v_reason := 'error';
        raise warning 'club_end_pack_runs: pairing % — % %', r.sd_id, sqlstate, sqlerrm;
    end;

    -- ⚠ The accumulators are appended OUTSIDE the block, deliberately. A plpgsql variable is NOT
    -- rolled back by its enclosing subtransaction, so appending to `ended` before a later
    -- statement raised would report a pairing as ended whose writes had vanished.
    if v_verd = 'ended' then
      v_ended := v_ended || jsonb_build_object(
        'sdId', r.sd_id, 'bookingId', r.booking_id, 'runnerId', v_bk.runner_id,
        'dogId', r.dog_id, 'dogName', r.dog_name, 'km', v_km, 'durationSec', v_dur);
    elsif v_verd = 'already' then
      v_alrdy := v_alrdy || jsonb_build_object(
        'sdId', r.sd_id, 'dogId', r.dog_id, 'dogName', r.dog_name, 'reason', v_reason);
    else
      -- `incidentId` is present as a KEY on every blocked row and NULL where it does not apply.
      -- §6.2 sketched it as key-present-only; a fixed key set is flatter for the client and
      -- costs nothing, and 0065 W6's near-miss (a body returning constant NULLs passing a
      -- key-set check) is answered by pinning the VALUE, which 176 P3 does.
      v_block := v_block || jsonb_build_object(
        'sdId', r.sd_id, 'dogId', r.dog_id, 'dogName', r.dog_name,
        'reason', v_reason, 'incidentId', v_inc);
    end if;
  end loop;

  return jsonb_build_object(
    'session', p_session,
    'at',      v_at,
    'ended',   v_ended,
    'blocked', v_block,
    'already', v_alrdy);
end $$;

-- ⚠ WRITTEN OUT EVERY TIME, never relying on grant preservation. On an apply where the function
-- is absent (a partial prior apply, a branch that never ran this file, a rebuilt environment) a
-- `create or replace` is a plain CREATE and the definer is born PUBLIC-executable (0116:636).
-- `service_role` is revoked EXPLICITLY: it holds EXECUTE through Supabase DEFAULT PRIVILEGES,
-- which a revoke naming only public/anon/authenticated does not touch (`0057:59-62`), so a pin
-- asserting 「no service_role grant」 would be green while service_role could execute
-- (`0118:937-938` is the shipped remedy). This is a client-facing host RPC; the grant below IS
-- the allowlist.
revoke execute on function public.club_end_pack_runs(uuid) from public, anon, service_role;
grant  execute on function public.club_end_pack_runs(uuid) to authenticated;

comment on function public.club_end_pack_runs is
  '0144 §B — 러닝 종료: 호스트(또는 백업 호스트)의 한 번의 탭으로 세션의 모든 위탁 페어의 런을 끝낸다.
각 러너의 거리는 그 러너 본인의 업로드 트레이스에서 서버가 도출하고(_club_derive_run_km), 시간은 탭
시각까지로 잰다(Sean 2026-08-26 §11 ③). bookings.run_ended_at과 runs.{ended_at,actual_km,duration_sec,
end_reason}를 함께 동결한다 — 반쪽 동결은 0083:744로 인해 무의미하거나(디바이스 승) 정산 영구
불가(frozen_measurement_mismatch)가 된다. 돈은 건드리지 않는다: 원장도 청구도 이 함수 밖의 게이트된
단계다(§11.2). 반환은 세 리스트(ended/blocked/already), 절대 개수가 아니다. 호스트+백업만.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  VERIFY — positive AND negative, with STATE checks, at apply time
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Three different propositions, kept apart: ⓐ the thing I built exists and is sealed the way I
-- say it is; ⓑ the thing I deliberately did NOT touch is still there, still enabled, still keyed
-- the same way (R-1); ⓒ the shipped mechanism this whole design LEANS ON is present at apply
-- time (R-2). ⓒ matters because if `settle_run_tx`'s freeze arm were ever absent, this file
-- would be writing numbers nothing reads — a green harness on a feature that does nothing.
--
-- ⚠ The money-surface check reads `prosrc`, which for a plpgsql function INCLUDES its comments.
-- That is why the two function bodies above discuss the money path in the FILE's comments and
-- never inside `$$…$$`: CLAUDE.md's own law is that a comment quoting the code it replaced
-- matches every grep hunting for that code, so a body that explains 「this writes no ledger_items
-- row」 would fail a check for `ledger_items` and, worse, would pass one written the other way.
do $$
declare
  v_secdef boolean; v_cfg text[]; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_src text; v_tok text; v_n int; v_en char;
begin
  -- ── ⓐ POSITIVE: the RPC exists, is a definer, and carries search_path IN THE BODY ────────
  select p.prosecdef, p.proconfig, p.prosrc into v_secdef, v_cfg, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_end_pack_runs';
  if v_secdef is null then raise exception '0144 C-a: club_end_pack_runs is absent'; end if;
  if not v_secdef then raise exception '0144 C-a: club_end_pack_runs is not SECURITY DEFINER'; end if;
  if v_cfg is null or not ('search_path=public, pg_temp' = any(v_cfg)) then
    raise exception '0144 C-a: search_path not set in the body — proconfig=%', v_cfg;
  end if;

  -- ── ⓐ POSITIVE **AND** NEGATIVE on the ACL. Both arms, because "revoked from public" alone is
  --     satisfied by a function nobody can call, and "granted to authenticated" alone is
  --     satisfied by one everybody can.
  select has_function_privilege('public',        'public.club_end_pack_runs(uuid)', 'execute'),
         has_function_privilege('anon',          'public.club_end_pack_runs(uuid)', 'execute'),
         has_function_privilege('authenticated', 'public.club_end_pack_runs(uuid)', 'execute'),
         has_function_privilege('service_role',  'public.club_end_pack_runs(uuid)', 'execute')
    into v_pub, v_anon, v_auth, v_svc;
  if v_pub or v_anon or v_svc then
    raise exception '0144 C-a: ACL leak — public=% anon=% service_role=%', v_pub, v_anon, v_svc;
  end if;
  if not v_auth then raise exception '0144 C-a: authenticated cannot execute the host RPC'; end if;

  -- the derivation helper is server-only: it takes a caller-supplied trace and has no party gate.
  select has_function_privilege('public',        'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('anon',          'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('authenticated', 'public._club_derive_run_km(jsonb, timestamptz)', 'execute'),
         has_function_privilege('service_role',  'public._club_derive_run_km(jsonb, timestamptz)', 'execute')
    into v_pub, v_anon, v_auth, v_svc;
  if v_pub or v_anon or v_auth or v_svc then
    raise exception '0144 C-a: helper ACL leak — %/%/%/%', v_pub, v_anon, v_auth, v_svc;
  end if;

  -- ── ⓐ NEGATIVE: the money surfaces are absent from the SOURCE of both functions ──────────
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_end_pack_runs';
  foreach v_tok in array array['ledger_items', 'miles_ledger', 'payments', 'club_fee_items',
                               'settle_run_tx', 'mint_settle_charge_intent', 'compute_owner_charge',
                               'compute_runner_payout', 'payout_state', 'settled_at',
                               'custody_phase', 'update bookings set status']
  loop
    if position(v_tok in v_src) > 0 then
      raise exception '0144 C-a: club_end_pack_runs names a forbidden surface: %', v_tok;
    end if;
  end loop;
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_derive_run_km';
  if v_src is null then raise exception '0144 C-a: _club_derive_run_km is absent'; end if;

  -- ── ⓑ NEGATIVE (R-1): the axes normalizer is untouched, PRESENT and ENABLED ──────────────
  -- tgenabled is the STATE; the definition is only the shape. That distinction is the lesson
  -- this trigger itself taught (0140 §D quotes it), and it is exactly what makes 「I did not
  -- disturb the derived-axes machine」 a measurement rather than an assurance.
  select count(*), min(tgenabled) into v_n, v_en from pg_trigger
   where tgrelid = 'public.session_dogs'::regclass and tgname = 'club_v1_axes_sync';
  if v_n <> 1 or v_en <> 'O' then
    raise exception '0144 C-b: club_v1_axes_sync n=% enabled=% (expected 1/O)', v_n, v_en;
  end if;
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_compute_axes';
  if v_src is null then raise exception '0144 C-b: _club_compute_axes is absent'; end if;
  -- Still derived from bookings.status, exactly as before this file. If a later slice re-keys it
  -- so `return_pending` is reachable while the booking is `active`, this line is where the
  -- decision is recorded as having been made ON PURPOSE and not as a side effect of 0144.
  if position('v_bst = ''completed'' then ''return_pending''' in v_src) = 0 then
    raise exception '0144 C-b: _club_compute_axes no longer derives return_pending from bookings.status';
  end if;
  -- and this file added no trigger of its own to session_dogs or bookings
  if exists (select 1 from pg_trigger
              where tgrelid in ('public.session_dogs'::regclass, 'public.bookings'::regclass)
                and tgname like '%pack_run%') then
    raise exception '0144 C-b: 0144 must add no trigger';
  end if;

  -- ── ⓒ POSITIVE (R-2): the shipped mechanism this design leans on is present ──────────────
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'settle_run_tx';
  if v_src is null then raise exception '0144 C-c: settle_run_tx is absent'; end if;
  -- the freeze GATE — a settle whose numbers are not the frozen ones is refused (0083:709-717)
  if position('frozen_measurement_mismatch' in v_src) = 0 then
    raise exception '0144 C-c: settle_run_tx has no frozen_measurement_mismatch gate — the freeze this file writes would be unenforced';
  end if;
  -- the freeze PRESERVATION — with the stamp present, the device no longer wins (0083:744)
  if position('when v_run_ended is null then excluded.actual_km' in v_src) = 0 then
    raise exception '0144 C-c: settle_run_tx no longer preserves a frozen actual_km — R-2 is reopened';
  end if;
  -- and settle_run_tx's return seal is still marketplace-only, so a club booking carrying the
  -- new stamp cannot be walked into `return_not_sealed` (0083:681)
  if position('if v_club is null then' in v_src) = 0 then
    raise exception '0144 C-c: settle_run_tx return seal is no longer club-exempt — the new stamp would strand every club settle';
  end if;
end $$;

commit;
