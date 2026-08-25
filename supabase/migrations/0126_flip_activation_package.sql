-- ═══ 0126: the flip-activation package — the late-booking clock gets its seatbelts ═══
--
-- Sean, console 2026-08-25T05:20:16Z: clock-flip = 「Turn it on (with the pre-flight)」.
-- Spec: docs/contracts/r17-sweep-per-row-commit-contract.md §VERDICT — the dual-voice review
-- that DEFERRED the per-row-commit conversion re-scoped R17's remainder to exactly this
-- package, built when the flip is scheduled. It now is.
--
-- PREFLIGHT, MEASURED LIVE BEFORE AUTHORING (ask-production law, 2026-08-25):
--   arm ⓐ expired check-ins ........ 0
--   arm ⓑ ceiling backfill ......... 1   (the known 2026-08-04 booking — the ONLY batch)
--   arm ⓒ past-grace unopened ...... 0
--   flag late_protocol_live_since .. NULL · cron late-booking-sweep .. active
-- The convoy the shelved conversion fixed does not exist at this scale; these protections are
-- the cheap operational floor for the activation itself (his cooldown-card posture applies:
-- operational safety yes, speculative counters no).
--
-- FOUR named edits to `late_booking_sweep` (0117:1197, otherwise byte-faithful) + one index +
-- one cron re-registration:
--   ① per-arm LIMIT 5 — a tick is bounded; the backlog drains across ticks (or the manual
--     drain loop in the ⑥ procedure), never in one lock-holding batch.
--   ② lock_timeout 2000 → 250ms — a blocked row is skipped in a quarter second; the per-row
--     handler logs it and the next tick retries.
--   ③ (index) partial index on unresolved deadlines — arm ⓐ's scan is the one that grows
--     with adoption; the other two arms ride the bookings status predicates.
--   ④ (cron) the job command gains a session `statement_timeout = 5s` fuse — a stuck sweep
--     dies in 5 seconds instead of holding its locks for a tick. The fuse lives in the CRON
--     COMMAND, deliberately: a timeout cannot cap its own containing statement, so neither an
--     in-function set_config nor an ALTER FUNCTION SET can bound the call that is already
--     running — only the session that issues the SELECT can arm it first.
-- The flag itself is NOT flipped here — the ⑥ procedure does that live, with the counts
-- re-taken, the cron paused, and the rollback line pre-written (see the REGISTRY row).

create index if not exists booking_checkins_unresolved_deadline_idx
  on booking_checkins (deadline_at)
  where resolved_at is null;
comment on index booking_checkins_unresolved_deadline_idx is
  '0126 ③: arm ⓐ의 스캔 — 미해결 데드라인만. 해결된 행이 쌓여도 스윕 비용은 미해결 수에만 비례한다.';

create or replace function late_booking_sweep() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  if (select f.late_protocol_live_since from ops_flags f) is null then return 0; end if;
  -- [MINOR-14] ONE sweep at a time. `lock_timeout` alone turns a collision into a silently
  -- skipped row (the booking waits a full tick, or forever if the pattern repeats); a session
  -- lock makes a duplicate tick leave immediately, which is what a duplicate tick should do.
  -- try, not wait: a slow predecessor must not queue ticks behind it.
  if not pg_try_advisory_lock(hashtextextended('late_booking_sweep', 0)) then return 0; end if;
  -- [codex MEDIUM-11 → 0126 ②] one abandoned row lock must not stall the whole batch: with a
  -- 250ms bounded wait a blocked row times out, its per-row handler logs, the sweep moves on,
  -- and the next tick retries it.
  perform set_config('lock_timeout', '250', true);

  -- ⓐ expired check-ins → the resolver (deadline rules; renewals never happen here)
  for r in
    select bc.booking_id from booking_checkins bc
    where bc.resolved_at is null and bc.deadline_at <= now()
    -- [MINOR-14] deterministic candidate order: overlapping ticks take rows in the same
    -- sequence, so they queue instead of deadlocking.
    order by bc.booking_id
    limit 5   -- [0126 ①]
  loop
    begin
      perform _resolve_checkin(r.booking_id, 'deadline');
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep deadline % : %', r.booking_id, sqlerrm;
    end;
  end loop;

  -- ⓑ the ceiling: pre-custody marketplace bookings past maximum lateness — WITH or WITHOUT
  -- a check-in row (the without case is every booking that predates the protocol, the
  -- 2026-08-04 row first among them). Resolution is a STATUS and a record, never money
  -- (0068 — see the file header). Already-resolved check-ins are excluded so a closed
  -- protocol is never re-entered.
  for r in
    select b.id from bookings b
    where b.status in ('confirmed', 'runner_enroute')
      and b.club_session_id is null
      and late_ceiling_at(b.scheduled_at) <= now()
      and not exists (select 1 from booking_checkins bc
                      where bc.booking_id = b.id and bc.resolved_at is not null)
      -- [blind review MAJOR-8] NO EXTRA MARGIN. Round 2 delayed row-less bookings by a full
      -- grace period past the ceiling so the protocol would not "claim a window it never
      -- offered" — but that made the ruled 3h ceiling a 3h30m ceiling in fact, and during the
      -- extra half hour the confirmed tier still charged 10% and accrued a runner share. The
      -- honesty that margin was buying is carried by the CAUSE TOKEN instead
      -- (`ceiling_backfill` says in the record that no answer window ever existed), which
      -- costs nothing and keeps Sean's number the number.
    order by b.id
    limit 5   -- [0126 ①]
  loop
    begin
      perform _resolve_checkin(r.id, 'ceiling');
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep ceiling % : %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓒ arm the protocol: pre-custody marketplace bookings past grace, under the ceiling,
  -- no protocol row yet.
  for r in
    select b.id from bookings b
    where b.status in ('confirmed', 'runner_enroute')
      and b.club_session_id is null
      and b.scheduled_at + late_grace() <= now()
      and late_ceiling_at(b.scheduled_at) > now()
      and not exists (select 1 from booking_checkins bc where bc.booking_id = b.id)
    order by b.id
    limit 5   -- [0126 ①]
  loop
    begin
      perform open_checkin(r.id);
      n := n + 1;
    exception when others then
      raise warning 'late_booking_sweep open % : %', r.id, sqlerrm;
    end;
  end loop;

  perform pg_advisory_unlock(hashtextextended('late_booking_sweep', 0));
  return n;
exception when others then
  -- session-scoped: it must not survive a failed tick
  perform pg_advisory_unlock(hashtextextended('late_booking_sweep', 0));
  raise;
end $$;

revoke execute on function late_booking_sweep() from public, anon, authenticated;
grant  execute on function late_booking_sweep() to service_role;

comment on function late_booking_sweep is
  '0117 §8 + [0126]: the late-booking clock, activation-hardened — per-arm LIMIT 5, 250ms lock
wait; the 5s statement fuse rides the cron command (a timeout cannot cap its own statement).
ⓐ resolve expired check-ins ⓑ ceiling-resolve rotted pre-custody bookings (status only, never
money — 0068) ⓒ open check-ins past grace. Club excluded throughout.';

-- [0126 ④] re-register the job with the fuse in the command. Guarded like 0117:1300 — the
-- local harness has no pg_cron and must still apply cleanly; the LIVE job's command is a ⑥
-- checklist readback item (cron.job.command), not something a pin here can see.
do $$ begin
  perform cron.unschedule('late-booking-sweep');
  perform cron.schedule('late-booking-sweep', '3-53/10 * * * *',
                        'set statement_timeout = ''5s''; select late_booking_sweep();');
exception when invalid_schema_name or undefined_function or undefined_table then
  raise notice 'pg_cron unavailable — 서비스 키 스케줄러가 같은 두 문장을 실행해야 합니다';
end $$;
