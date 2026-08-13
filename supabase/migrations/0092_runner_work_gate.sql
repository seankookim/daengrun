-- 0092 — ⑫ 러너 작업 게이트. 돈은 풀되, 개가 양측 확인으로 돌아올 때까지 새 러닝은 못 받는다.
--
-- ═══ §0 THE RULING ═══════════════════════════════════════════════════════════════════════
-- Sean, 2026-08-13, verbatim:
--   "for 12, pay the runner but dont let them make new runs until the dog is confirmed by
--    both sides."
--
-- Every proposal before this — both sessions' and codex's — made the PAYMENT conditional and
-- then argued about the condition. His answer does not touch the payment at all. The runner is
-- paid. The counterweight is a gate on FUTURE WORK. That dissolves codex's hazard (a runner
-- withholding confirmation to trigger a timeout payout) without inventing a fourth financial
-- outcome: withholding confirmation now costs you every future booking, which is a far stronger
-- deterrent than withholding one fee, and it costs no new money policy.
--
-- ═══ §1 WHAT "THE DOG IS CONFIRMED BY BOTH SIDES" ALREADY MEANS ══════════════════════════
-- 🔴 READ THIS BEFORE ASSUMING THIS SLICE NEEDS ⑪.
-- The assignment that reached this session said ⑫'s exit condition IS ⑪'s two-stamp machine,
-- and that the two therefore had to be built together. That is not what Sean said. He said
-- **the DOG** is confirmed by both sides — custody handed back — not that the INCIDENT is
-- verified by both sides. Those are two different facts about two different things:
--   · ⑪ asks "did this incident really happen?"     → a new two-stamp machine, unbuilt
--   · ⑫ asks "is the dog back with its owner?"      → `bookings.runner_confirmed_return_at`
--                                                     + `owner_confirmed_return_at`, SHIPPED
--                                                     in 0083 and hardened by 0089
-- So ⑫ needs no new confirmation machine. It reads the one that already exists. Building it
-- on ⑪ would have coupled a shippable gate to an unbuilt slice for no reason, and — worse —
-- would have made the gate clear when an INCIDENT was verified rather than when a DOG came
-- home, which is not the ruling.
--
-- ═══ §2 WHY THIS IS DERIVED AND NOT A FLAG ON `runners` ══════════════════════════════════
-- ⑫'s memo build-note proposes "a flag on `runners`/availability". This file deliberately does
-- NOT add one, and the reason is a mistake this repo made and corrected THIS SAME DAY: 0089's
-- review removed a `return_eligible_at` write for being "a cache of something derivable", citing
-- 0083 §1's rule against exactly that. A `runners.work_gated` boolean is that same shape and
-- fails the same way — it is a denormalized copy of a fact the `bookings` rows already carry,
-- so it can DRIFT: a confirmation lands and the flag never clears, a crash lands between the
-- stamp and the flag write, an ops correction moves one and not the other. A drifted gate is
-- worse than no gate, because it silently suspends an innocent runner and no one can tell from
-- the row whether the suspension is real.
-- A derived predicate cannot drift: it is recomputed from the stamps at the moment the question
-- is asked, so the instant the second stamp lands the runner is free with no second write to
-- get wrong. The build note is a note, not the ruling; the ruling is the outcome, and the
-- outcome is exactly preserved.
-- ⚠ The cost is honest and named: this is a query per accept rather than a column read. It is
-- indexed (§5) and bounded by one runner's own live bookings, which is the same order as the
-- conflict-guard query the accept path ALREADY runs (`transition-booking/index.ts:64-73`).
--
-- ═══ §3 WHAT COUNTS AS HOLDING A DOG ═════════════════════════════════════════════════════
-- A booking gates its runner when the run has STOPPED but the dog is not yet home:
--   `run_ended_at is not null` AND NOT (both return stamps present)
-- and also while the dog is demonstrably still out on a booking that went sideways
-- (`incident_review`), which is the state ⑫ was written about in the first place.
-- ⚠ It deliberately does NOT gate on `active`/`picked_up` alone. A runner mid-run obviously
-- holds a dog, but the ACCEPT path already refuses overlapping work through its scheduled-window
-- conflict guard, and gating on "currently running" would change the meaning from "you did not
-- bring a dog home" to "you are busy" — a different rule with different false positives.
-- What this closes is the CAPACITY GAP the run-end plan §4 names: the conflict guard uses the
-- NOMINAL scheduled window (`km*8+25min`), so a 귀가 that runs past the estimate lets a runner
-- accept new work while still holding the first dog. This gate is unconditional on wall-clock
-- and therefore closes exactly that.
--
-- ═══ §4 WHAT THIS FILE DOES NOT DO ═══════════════════════════════════════════════════════
-- · It does not touch money. The payment is released by the return/settle path exactly as
--   before — that is the whole point of the ruling.
-- · It does not add a `bookings` status or transition, so it stays clear of the
--   `incident_review → refund_pending` cul-de-sac that was ⑫'s original finding (0001:193).
-- · It does not enforce anything in the client. The client may READ this to explain itself
--   (§6's whole purpose), but the refusal lives on the server path that actually assigns work.
-- · It does not re-create `runners_available_for` (0054) or any object another slice owns.
--   NEW OBJECTS ONLY: `runner_work_gate`, `_runner_work_gate_blocking`.

-- ── §5 the index the predicate rides on ───────────────────────────────────────────────────
-- Partial: only rows that can possibly gate. Keeps the gate query off a full runner-history scan
-- on a runner with hundreds of completed bookings.
create index if not exists bookings_runner_unreturned_idx
  on bookings (runner_id)
  where runner_id is not null
    and (runner_confirmed_return_at is null or owner_confirmed_return_at is null);

-- ── §6 the blocking row, and WHY it blocks ────────────────────────────────────────────────
-- Returns the single oldest blocking booking, or no row. Split out from the boolean because the
-- ruling's second half is legibility: ⑫'s memo is explicit that a runner who does not know why
-- they cannot accept work, or what clears it, is the same defect class as an ops alert whose
-- remedy does not apply. A bare boolean cannot carry that, so nothing in this file returns one.
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
         -- WHICH SIDE the runner is waiting on decides what we can honestly tell them to do.
         -- "확인해주세요" to a runner who has already stamped is a lie about their own action.
         case
           when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
             then 'both'
           when b.runner_confirmed_return_at is null then 'runner'
           else 'owner'
         end
    from bookings b
   where b.runner_id = p_runner
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and b.club_session_id is null          -- clubs run their own custody machine (0045/0069)
     and (
           -- the run stopped and the dog is not confirmed home (0083's 귀가 window)
           (b.run_ended_at is not null and b.status::text = 'active')
           -- or the booking went sideways with the dog still out — ⑫'s own case
           or b.status::text = 'incident_review'
         )
   order by b.run_ended_at nulls last, b.id
   limit 1
$$;

revoke execute on function _runner_work_gate_blocking(uuid) from public, anon, authenticated;
grant  execute on function _runner_work_gate_blocking(uuid) to service_role;

-- ── §7 the gate ───────────────────────────────────────────────────────────────────────────
-- Flat whitelisted return (house law). `gated` is the answer; everything else exists so the
-- caller can say something true to the runner without a second query.
create or replace function runner_work_gate(p_runner uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g record;
begin
  if p_runner is null then raise exception 'runner_required'; end if;
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
              else 'both_confirm_return'
            end);
end $$;

revoke execute on function runner_work_gate(uuid) from public, anon;
-- A runner may ask about THEIR OWN standing — that is the legibility half of the ruling, and
-- the function is party-safe by construction: it takes a runner id and returns only that
-- runner's own blocking booking. It is NOT the enforcement point (§4); the accept path is.
grant  execute on function runner_work_gate(uuid) to authenticated, service_role;

comment on function runner_work_gate is
  '0092 ⑫ — may this runner take new work? Sean 2026-08-13: "pay the runner but dont let them
make new runs until the dog is confirmed by both sides". DERIVED from 0083''s two return stamps,
never cached on `runners` (§2: a flag is a copy of a derivable and drifts; 0089''s review removed
exactly that shape the same day). Returns the blocking booking, which side is outstanding, and
the named exit — a gate a runner cannot read is an unexplained suspension (⑫ memo). Enforcement
lives on the accept path, not here and never in the client.';
