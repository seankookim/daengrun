-- Bound only the two rules read by is_slot_available (0003_availability.sql).
-- Match app/app/runner/availability.tsx: rest 0..120 minutes, daily sessions 1..8.
-- NOT VALID preserves legacy rows: these self-writable integers previously had
-- no bounds, so existing production rows can be outside the editor's ranges.
-- New inserts and updates are checked immediately; validation needs a later
-- production data audit rather than silently rewriting a runner's saved rules.
alter table public.runner_booking_rules
  add constraint runner_booking_rules_rest_after_min_bounds
    check (rest_after_min between 0 and 120) not valid,
  add constraint runner_booking_rules_max_sessions_per_day_bounds
    check (max_sessions_per_day between 1 and 8) not valid;
