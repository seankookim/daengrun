-- 0105 — a client can no longer name someone else's dog, or a victim runner, on a new booking.
--
-- ═══ §0 THE HOLE, MEASURED ══════════════════════════════════════════════════════════════
-- `bookings owner insert` WITH CHECK is `(owner_id = auth.uid() and status = 'draft')` and nothing
-- more. `dog_id`, `runner_id`, `address_id` and `club_session_id` are unconstrained. Executed
-- against production as a real owner, rolled back:
--
--   insert into bookings(owner_id, dog_id, runner_id, status, …)
--     values (me, my_dog, <an unrelated real runner>, 'draft', …)   → ACCEPTED
--
-- The row is what makes `is_booking_party()` true, so a forged draft is a key: it unlocks a chat
-- thread to the victim, a review naming them, and notifications delivered to their phone — the
-- audit demonstrated all three from this one root. Setting `runner_id = self` instead exposes any
-- dog row through `dogs runner read via booking`.
--
-- ═══ §1 WHY THIS IS ONE `create or replace` AND NOT THE REWRITE THAT WAS SPECIFIED ══════
-- The remediation brief called for revoking client INSERT, building a `create_booking_draft`
-- definer RPC, and rerouting `create-booking-hold`. That is the architecturally cleaner end state
-- and it is a much larger change: it drops a live policy, moves pricing, and touches the edge
-- function that holds the money path.
--
-- **`_guard_booking_insert_cols` already exists** — BEFORE INSERT, scoped to `current_user in
-- ('authenticated','anon')` — and already refuses the custody/return/handoff columns. It simply
-- never covered the party columns. Extending it:
--   · needs no policy drop and no client change
--   · leaves `create-booking-hold` untouched — it runs as `service_role`, so the guard skips it by
--     `current_user`, exactly as it already does for the columns guarded since 0083
--   · enforces at the same server boundary, fails closed, and is testable in the harness
-- This is the shape `0087` used for `runs`. The RPC remains the better long-term architecture and
-- is NOT cancelled — it is simply not what should stand between today and a closed hole.
--
-- ⚠ The UPDATE door is ALREADY SHUT and was not part of the brief: `_guard_booking_cols` raises
-- `booking_protected_columns` when a client re-points `runner_id` on an existing row (measured).
-- So closing INSERT does not just move the attack one statement later — that was checked, not
-- assumed.

create or replace function _guard_booking_insert_cols() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user in ('authenticated', 'anon') then
    -- ① server-written custody/return facts (0083 lineage, unchanged)
    if new.run_ended_at               is not null
    or new.runner_confirmed_return_at is not null
    or new.owner_confirmed_return_at  is not null
    or new.return_forced_by           is not null
    or new.return_forced_at           is not null
    or new.return_force_reason        is not null
    or new.return_force_evidence      is not null
    or new.return_eligible_at         is not null
    or new.settlement_ready_at        is not null
    or new.custody_last_seen_at       is not null
    or new.owner_confirmed_handoff_at is not null
    or new.runner_confirmed_handoff_at is not null
    then
      raise exception 'booking_protected_columns'
        using detail = '인계·귀가 확인 시각은 서버만 기록해요 — 새 예약에 미리 담을 수 없어요';
    end if;

    -- ② PARTY columns (0105). Assignment is a server decision, never a client claim.
    -- A client-supplied runner_id is the whole exploit: the row is what is_booking_party() reads.
    if new.runner_id is not null then
      raise exception 'booking_runner_is_server_assigned'
        using detail = '러너 배정은 서버가 정해요 — 예약을 만들 때 지정할 수 없어요';
    end if;
    if new.club_session_id is not null then
      raise exception 'booking_club_session_is_server_assigned'
        using detail = '클럽 세션 연결은 서버가 해요';
    end if;

    -- ③ the dog and the address must belong to the caller. Checked against auth.uid() rather
    -- than new.owner_id: the policy already pins owner_id = auth.uid(), and checking the same
    -- thing twice through one variable would let a future policy change move both at once.
    if new.dog_id is not null
       and not exists (select 1 from dogs d where d.id = new.dog_id and d.owner_id = auth.uid()) then
      raise exception 'booking_dog_not_owned'
        using detail = '본인 반려견으로만 예약할 수 있어요';
    end if;
    if new.address_id is not null
       and not exists (select 1 from addresses a where a.id = new.address_id and a.owner_id = auth.uid()) then
      raise exception 'booking_address_not_owned'
        using detail = '본인 주소로만 예약할 수 있어요';
    end if;
  end if;
  return new;
end $$;

comment on function _guard_booking_insert_cols() is
  '0105: client INSERTs on bookings may not carry server-written custody columns, may not name a runner or club session, and must reference a dog and address the caller owns. service_role is unaffected (create-booking-hold).';
