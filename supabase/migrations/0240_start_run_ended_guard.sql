-- ═══ 0240: start_run_tx refuses to START a run that has already ENDED ═══
--
-- The server half of Codex wave-4 c3 (docs/reviews/2026-09-25-wave4-codex-verdicts.md:20; the
-- client half is PR #7's ended-check in `app/app/runner/run.tsx`). Master-prompt B4.
--
-- ═══ §0 WHY ═══
-- `end_run_tx` (0083 §3) freezes the measurement and stamps `bookings.run_ended_at`, and it leaves
-- `status = 'active'` ON PURPOSE (0083 plan §1: the dog is still in the runner's hands, so every
-- custody-inclusive consumer must keep behaving as if the run were live) — the status moves only at
-- settlement. `start_run_tx` (0087 §2) answers ANY `active` booking with `{unchanged:true}` and
-- repairs a missing `started_at`; it never read `run_ended_at`. So on an ended-but-unsettled booking
-- a start request is ACCEPTED, and three things follow, none of them a start:
--   ① the edge caller (`transition-booking/start_run.ts:59`) pushes the owner 「러닝 시작 —
--      실시간으로 지켜보세요」 on every accepted call (its own comment: 0087 §0c, behaviour
--      preserved) — a false 「러닝 시작」 after the run is over;
--   ② a client without PR #7's ended-check (every build before it, or one holding a stale cached
--      verdict — c3's own mechanism: a failed `fetchReturnSeal` resolved the check to false and was
--      cached) re-enters the live-run UI on a finished run and records again;
--   ③ were the `runs` row ever missing on such a booking, 0087's repair arm would (re)write
--      `started_at` on a run whose `ended_at` is frozen.
-- The client fix is necessary and not sufficient: a server that accepts the request will be asked
-- again by the next stale client. The refusal belongs here, and it is one conjunct.
--
-- ═══ §0b WHAT CHANGES ═══
-- `start_run_tx(uuid)` is re-declared from 0087 §2 — its ONLY declaration (measured: no later
-- `create or replace function start_run_tx` anywhere in 0088–0228) — with exactly THREE anchored
-- edits, built BY SCRIPT so that undoing them reproduces 0087:150-217 byte for byte (asserted at
-- build; pristine 0087 file md5 110561f19b0d154311c2a91ca8e6ed2b, its block md5 cf4e8deb519fc8c74d820f033bf2cd40, this block
-- md5 edd2c7ac1426159ca9a73c05f47846b2):
--   ⓐ the locked record select also reads `bk.run_ended_at`;
--   ⓑ inside the `active` branch, FIRST — before the repair and the idempotent return —
--      `run_ended_at is not null` raises `run_ended`;
--   ⓒ the comment explaining ⓑ.
-- The ACL is restated explicitly and never relied on preservation (`app/scripts/check-definer-acl.mjs`
-- refuses a same-name recreation in a file that does not set the ACL itself; and a `create or
-- replace` where the function is absent is a CREATE born PUBLIC-executable, 0116:636). The function
-- comment is restated with one added sentence. §B VERIFY fails the apply on shape, ACL or source.
--
-- ═══ §0c WHAT DOES NOT CHANGE ═══
-- · Party gate before state gate (repo law): `not_found` and `not_run_runner` still precede
--   everything, so a stranger on an ended run learns `not_run_runner`, never `run_ended` (271 S5).
-- · The idempotent answer for a LIVE `active` run — `{unchanged:true}` with the same `started_at` —
--   and 0087's repair of a NULL / missing `started_at` on a live run: both kept (271 S2 / S3).
-- · The `picked_up → active` claim, the server clock, the on-conflict OVERWRITE on the claim path
--   and the on-conflict COALESCE on the repair path (0087 §2, 123 S1/S6): kept byte for byte
--   (271 S4 is the control; 123 stays green).
-- · The edge caller's code. The RPC error already becomes `HttpError(409, message)`, so `run_ended`
--   reaches the client exactly as `not_picked_up` does. Only its comment names the new refusal, and
--   `_test/start_run_test.ts` gains the case.
-- · No notification change. A duplicate 「러닝 시작」 on a LIVE re-tap is still sent (0087 §0c
--   left it to a client slice); this file removes only the one sent after the run ended.
-- · `club_start_delegated_runs` (0038 §B / 0050 §B, the club start path — Codex lane, NOT touched).
--   It selects `status = 'picked_up'` only, so it cannot re-enter an ended (`active`) run; it does
--   not read `run_ended_at` either, and `end_run_tx` refuses club bookings (`club_out_of_scope`) so
--   no club booking carries the stamp today. Noted as the asymmetry it is, not as a hole.
-- · `ops_resolve_return_tx` (0193 → 0201 → 0224) moves a strand / incident_review booking BACK to
--   `active` with `run_ended_at` already set. After this file a start on that booking answers
--   `run_ended` instead of `{unchanged:true}` + a 「러닝 시작」 push — the intended reading, since
--   the resolution is about the RETURN, never a permission to run again.
--
-- ═══ §0d THE SENTENCE EACH PIN OWNS (271_start_run_ended_guard_suite.sql) ═══
--   0240-S1  a start on an ENDED run raises `run_ended` and moves nothing (status, run_ended_at,
--            runs.started_at, runs row count, notification rows). Fixture A is the REAL path —
--            started through start_run_tx, ended through end_run_tx. Fixture B is hand-stamped
--            (`active` + `run_ended_at` + NO runs row), a state the real path cannot reach because
--            end_run_tx always upserts the row; it is the arm that observes the ORDER — the refusal
--            precedes the repair, so no runs row is born.
--   0240-S2  a second start on a LIVE run is still `{unchanged:true}` with the SAME started_at, one
--            runs row, and no notification row change.
--   0240-S3  0087's repair on a LIVE run is kept: no runs row → born with a server started_at; a
--            NULL started_at → repaired.
--   0240-S4  control: picked_up → active, unchanged=false, server started_at; confirmed →
--            `not_picked_up` (0087's own state gate survived the copy).
--   0240-S5  a different runner on an ENDED run gets `not_run_runner`, not `run_ended` — while the
--            assigned runner on the SAME booking gets `run_ended`, so the fixture sits where the two
--            gates diverge and the ORDER is what is measured.
--   0240-S6  preconditions the guard reads, pinned every run (0131-G4's lesson): definer · in-body
--            search_path · proacl not NULL · anon / authenticated / public cannot execute ·
--            service_role can · NO-FUNCTION red.
--   0240-S7  source, COMMENTS STRIPPED: the raise and its conjunct present, positioned after the
--            party gate and before both the repair insert and the unchanged return; NO-SOURCE red.
--
-- ═══ §0e WHAT STAYS UNVERIFIED ═══
-- · deno is not installed in the build container: `_test/start_run_test.ts`'s new case is
--   UNVERIFIED locally (CI's deno-edge job runs it on the PR).
-- · Nothing here is deployed; production runs 0087's body until `db push`.
-- · The client fold. `api.ts invokeTransition` (1371-1383) folds EVERY non-Korean message to
--   「요청을 처리하지 못했어요 — 다시 시도해주세요」, and `runner/run.tsx`'s catch (1168-1180) shows
--   「러닝 시작을 서버에 기록하지 못했어요 · 다시 시도」 — a retry offer on a start that can never
--   succeed. Not edited here (api.ts is touched by 14 open cloud/* branches; run.tsx is PR #7's);
--   named as the follow-up in the slice report with those lines.
-- · The two-connection race on the claim (123's own named gap) is unchanged and still unpinned.
--
-- ═══ §0f WHOSE TEXT (concurrent-session hygiene) ═══
--   · `start_run_tx(uuid)` ← 0087 §2 (its only declaration). RE-DECLARED here; 0087 is not edited.
--   · Nothing else is created, altered or dropped.

-- ═══ §A start_run_tx — 0087 §2's body with the three anchored edits ═══
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
  select bk.id, bk.runner_id, bk.owner_id, bk.status::text as status, bk.km,
         bk.run_ended_at
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
    -- [0240] ended-but-unsettled. end_run_tx (0083 §3) stamps bookings.run_ended_at and leaves
    -- the status `active` until settlement, so an `active` row with the stamp is not a live run
    -- being re-entered — it is a start request on a run that is OVER. Refuse BEFORE the repair
    -- and the idempotent return below: the repair would (re)write started_at on a frozen run,
    -- and the edge caller pushes 「러닝 시작」 to the owner on every accepted answer
    -- (transition-booking/start_run.ts). Codex wave-4 c3, the server half; PR #7 is the client's.
    if b.run_ended_at is not null then raise exception 'run_ended'; end if;
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
{unchanged:true} and repairs a missing started_at, never an error — EXCEPT on a run that has
already ENDED: [0240] bookings.run_ended_at set (end_run_tx leaves the status active until
settlement) raises run_ended before the idempotent return, so a stale client cannot re-enter a
finished run and the owner is not pushed 러닝 시작 after the run ended. service_role only';

-- ═══ §B VERIFY — fail the apply, not a later harness run ═══
-- Every arm is an exact boolean (`is not true` / `is not false`): a NULL predicate must FAIL the
-- apply, never slide past a bare IF. The source arms read prosrc with comments stripped, because
-- the comment inside the body above names the very tokens they look for.
do $verify$
declare
  v_bad text := ''; v_oid oid; v_raw text; v_src text;
  v_p_party int; v_p_gate int; v_p_repair int; v_p_unch int;
begin
  v_oid := to_regprocedure('start_run_tx(uuid)')::oid;
  if v_oid is null then raise exception '❌ 0240 VERIFY: NO-FUNCTION(start_run_tx(uuid))'; end if;

  -- ① shape
  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NOT-DEFINER'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NO-BODY-SEARCH-PATH'; end if;
  if (select pronamespace = 'public'::regnamespace from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NOT-IN-PUBLIC'; end if;

  -- ② ACL both ways — the NULL-ACL arm first (a NULL proacl IS public-executable)
  if (select proacl from pg_proc where oid = v_oid) is null
    then v_bad := v_bad || ' NULL-ACL'; end if;
  if (has_function_privilege('public',        v_oid, 'execute')
   or has_function_privilege('anon',          v_oid, 'execute')
   or has_function_privilege('authenticated', v_oid, 'execute')) is not false
    then v_bad := v_bad || ' CLIENT-OR-PUBLIC-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'execute') is not true
    then v_bad := v_bad || ' SERVICE-ROLE-CANNOT-CALL'; end if;

  -- ③ source, comments stripped: the raise, its conjunct, and its POSITION
  select prosrc into v_raw from pg_proc where oid = v_oid;
  if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(start_run_tx)';
  else
    v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
    if (v_src ~ 'raise\s+exception\s+''run_ended''') is not true
      then v_bad := v_bad || ' NO-RAISE(run_ended)'; end if;
    v_p_party  := position('not_run_runner' in v_src);
    v_p_gate   := position('b.run_ended_at is not null' in v_src);
    v_p_repair := position('insert into runs' in v_src);
    v_p_unch   := position('''unchanged'', true' in v_src);
    if (v_p_gate > 0) is not true then v_bad := v_bad || ' NO-CONJUNCT(run_ended_at)'; end if;
    if (v_p_party > 0 and v_p_repair > 0 and v_p_unch > 0) is not true
      then v_bad := v_bad || ' 0087-SHAPE-MISSING(party gate / repair insert / unchanged return)'; end if;
    if (v_p_gate > v_p_party and v_p_gate < v_p_repair and v_p_gate < v_p_unch) is not true
      then v_bad := v_bad || ' ORDER(party gate < ended check < repair, unchanged)'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0240 VERIFY:%', v_bad;
  end if;
end $verify$;
