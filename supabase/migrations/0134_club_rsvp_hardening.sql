-- ═══ 0134: club RSVP-family hardening — three refusals and one new door ═══
--
-- Contract: docs/contracts/club-rsvp-hardening-contract.md v1 (+ §10 delta). Folds blind-review
-- findings F4 (silent-no-op RSVP), F5 (the host cannot run their own dog), F6 (no format gate),
-- F8 (cancel-rsvp has no time gate and cascades records away). F7 (destructive mode switch) is
-- deferred to S3 and is NOT here.
--
-- THE INVARIANT (contract §0): a 동반 (owner_handled) dog row exists in a session if and only if a
-- human deliberately put it there, in a session whose format admits companion dogs, under the
-- shared dog cap — and once a participant has physically checked in, no RPC deletes their record.
--
-- Nothing here moves money, mints a charge, touches a booking, changes a capacity number, or
-- alters what a delegated dog does. `delegation_active` (0052:213-217) stays exactly as shipped —
-- this slice adds a gate ABOVE it, it does not soften it.
--
-- ⚠ EVERY FUNCTION BELOW CARRIES `set search_path = public, pg_temp` IN ITS OWN BODY. Both
--   `session_rsvp` (0048:159) and `session_cancel_rsvp` (0052:206) were written with a bare
--   `set search_path = public` and pass 98 H1 today ONLY because `0055_definer_hardening.sql:171`
--   retro-sealed them by ALTER — and `create or replace` RESETS an ALTER-applied config (0116's
--   header, measured). Recreating them without the in-body config turns 98 H1 red. Measured on
--   production before authoring: both currently report proconfig {search_path=public, pg_temp}.
--
-- ⚠ NAMED RESIDUAL (contract §0): §A is an ENTRY gate, and it is complete only because
--   `club_sessions.format` has no post-creation writer — `club_create_session` (0037:377) and
--   `club_series_start` (0037:438) are the only writers, and `club_sessions` carries exactly one
--   RLS policy, `for select using (true)` (0030:133), so an authenticated UPDATE matches no policy
--   and changes zero rows. Suite 167 G1 pins that rather than assuming it. If a format-edit RPC is
--   ever added it inherits the question of what to do with 동반 rows already seated.

-- ═══ §A + §B — session_rsvp: the format gate, and the silent no-op becomes a refusal ═══
--
-- §A token `companion_closed`. ⚠ `format_closed` was REJECTED: 0048:110, 0043:185, 0043:232 and
-- 0037:93/173 all raise it with the OPPOSITE meaning ("this session does not admit delegation"),
-- and delegate/[sid].tsx maps it to a delegation sentence. One token cannot mean two contradictory
-- things to the same client.
--
-- ⚠ THE PREDICATE IS POSITIVE: `v_format = 'delegated_only'`, never `not in ('owner_only','mixed')`.
--   0119's lesson (154 G-header): a negative match silently admits any enum value added later. A
--   fourth format must fail this gate loudly rather than pass quietly.
-- ⚠ THE DEFAULTS ARE PART OF THE SHIPPED SIGNATURE AND MUST BE RESTATED. Measured on production:
--   `p_session uuid, p_dog uuid DEFAULT NULL::uuid, p_waiver text DEFAULT NULL::text`
--   (pronargdefaults = 2). `create or replace` REPLACES the defaults rather than preserving them,
--   so omitting them here silently breaks every two-argument call — which is how the suites call
--   it (`session_rsvp(v_s, dgoc)`, e.g. 95:38) and how the dogless path is expressed. The failure
--   would be a function-does-not-exist error at call time, far from this file.
create or replace function session_rsvp(p_session uuid, p_dog uuid default null, p_waiver text default null)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_status text; v_when timestamptz; v_cap int; v_cnt int; v_club uuid;
  v_role text; v_total_cap int; v_format text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  -- `format` joins the existing SELECT — one column, same lock, same row.
  select status, scheduled_at, people_capacity, club_id, total_dog_capacity, format
    into v_status, v_when, v_cap, v_club, v_total_cap, v_format
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status <> 'open' or v_when < now() then raise exception 'session_closed'; end if;
  select count(*) into v_cnt from session_people where session_id = p_session and attendance <> 'no_show';
  if v_cnt >= v_cap then raise exception 'session_full'; end if;
  if p_dog is not null and not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;

  -- §A. Placed AFTER `not_your_dog` because 0116 §D ⓐ puts the party gate over the named object
  -- first, and `not_your_dog` is already the one-sentence anti-enumeration answer for both "no
  -- such dog" and "someone else's dog". Placed BEFORE `dog_capacity_full` because a
  -- delegated_only session's companion cap is none of a 동반 applicant's business, and
  -- `dog_capacity_full` would be a TRUE sentence that sends them to wait for a seat that will
  -- never admit their dog — a truthful dead end is still a dead end.
  if p_dog is not null and v_format = 'delegated_only' then
    raise exception 'companion_closed';
  end if;

  -- §B belt 1 — the pre-check, above the people insert so a refusal leaves NO ORPHAN PEOPLE ROW.
  -- That orphan is the worse half of F4: `session_delegate_dog` creates no `session_people` row,
  -- so an owner who delegated a dog and never RSVP'd could call `session_rsvp` with that same
  -- dog, sail past `already_joined` (they have no people row), get a people row INSERTED, then
  -- hit `session_dogs_active_uni` (0043:29-31) at the dog insert and silently do nothing. The RPC
  -- returned void and session/[sid].tsx:221 fired haptic('success') — for a call that seated a
  -- people row the owner never asked for and zero dogs.
  --
  -- 🔴 THE `custody = 'runner_delegated'` CONJUNCT IS LOAD-BEARING AND IT DIVERGES FROM THE
  --    CONTRACT'S LITERAL TEXT. §B specifies this pre-check as mirroring 0048:122-124, i.e.
  --    `service_state is distinct from 'ended'` with no custody filter. Written that way it also
  --    matches an `owner_handled` row — and because this gate sits ABOVE the people insert, it
  --    would answer `already_delegated` to an owner re-RSVPing their OWN companion dog, who must
  --    get `already_joined`. That is the contract's own pin B4, and the unfiltered form fails it.
  --    §B's justification for the shared token ("an active owner_handled row implies a people row,
  --    so already_joined answers first") is sound but describes belt 2, which sits below the
  --    people insert — it does not carry up here. The conjunct is how B1 and B4 are both true.
  --    Suite 167 M-B4 plants the unfiltered form and reddens B4, so this is measured, not argued.
  if p_dog is not null and exists (
    select 1 from session_dogs
     where session_id = p_session and dog_id = p_dog
       and custody = 'runner_delegated'
       and service_state is distinct from 'ended'
  ) then
    raise exception 'already_delegated';
  end if;

  -- Gate-order divergence from `session_delegate_dog`, named rather than fixed: 0048 checks
  -- `dog_capacity_full` (118-120) BEFORE `already_registered` (122-124). Here `already_delegated`
  -- comes first, because a dog already occupying a slot cannot honestly be refused for lack of a
  -- slot. `session_delegate_dog`'s own order is NOT touched — it is a money-path function outside
  -- this slice, and 66 F6 pins its arm through it.
  if p_dog is not null and _club_total_dogs(p_session) >= coalesce(v_total_cap, v_cap) then
    raise exception 'dog_capacity_full';
  end if;

  v_role := case when p_dog is null and exists (
    select 1 from runners where profile_id = auth.uid() and tier <> 'applicant'
  ) then 'runner_attending' else 'owner_attending' end;
  begin
    insert into session_people (session_id, profile_id, role, waiver_version)
    values (p_session, auth.uid(), v_role, p_waiver);
  exception when unique_violation then
    raise exception 'already_joined';
  end;
  if p_dog is not null then
    insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id)
    values (p_session, p_dog, auth.uid(), 'owner_handled', auth.uid())
    on conflict (session_id, dog_id) where (service_state is distinct from 'ended') do nothing;
    -- §B belt 2. The `for update` on club_sessions serializes same-session RSVPs, so belt 1 is
    -- not racy TODAY; belt 2 is what keeps the guarantee true if that lock is ever narrowed. The
    -- battery proves each belt independently by deleting the other.
    if not found then raise exception 'already_delegated'; end if;
  end if;
  -- [R4] 멤버십 자동 가입 폐지 — 게스트 RSVP 1급 (가입 권유는 UI/알림 몫)
  if v_cnt + 1 >= v_cap then update club_sessions set status = 'full' where id = p_session; end if;
end $$;
revoke execute on function session_rsvp(uuid, uuid, text) from public, anon;
grant execute on function session_rsvp(uuid, uuid, text) to authenticated;

-- ═══ §C — session_add_my_dog: the door F5 found missing ═══
--
-- ⚠ NAME AND GATE. The addendum proposed `session_host_add_dog`; superseded deliberately, because
--   the name follows the gate and the gate is MEMBERSHIP, not hostship. F5's structural wall —
--   "your session_people row already exists, so session_rsvp can only ever answer already_joined"
--   — is not unique to the host: a dogless RSVP (0048:178-180, ruling #6's crew) hits it
--   identically the moment that person decides to bring their dog. Gating on hostship would build
--   the door for one person and leave the same wall standing for everyone else in the session.
--   §10b records that §16.2 (no host approval) makes this argument stronger, not weaker — the
--   host is no longer a privileged party to the delegated flow either.
--   🔵 Reversible: narrowing to host_profile_id is one predicate and one pin.
create or replace function session_add_my_dog(p_session uuid, p_dog uuid)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_status text; v_when timestamptz; v_format text; v_total_cap int; v_people_cap int;
        v_custody text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select status, scheduled_at, format, total_dog_capacity, people_capacity
    into v_status, v_when, v_format, v_total_cap, v_people_cap
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;

  -- PARTY GATE. A separate `not_found` above is acceptable here — and this is the reason, written
  -- where a reviewer will look for it: `club_sessions` is `for select using (true)` (0030:133), so
  -- session existence is ALREADY public and splitting it discloses nothing new. `session_rsvp`
  -- (0048:168) and `session_cancel_rsvp` make the same split for the same reason.
  if not exists (select 1 from session_people where session_id = p_session and profile_id = auth.uid()) then
    raise exception 'not_joined';
  end if;

  -- STATE. ⚠ This follows `session_delegate_dog` (0048:109), NOT `session_rsvp` (0048:169), and
  -- the divergence is deliberate: session_rsvp refuses a `full` session because the applicant
  -- needs a SEAT. This caller already holds their seat — only the DOG cap can refuse them. Do not
  -- "harmonize" this with session_rsvp later; C8 pins the behaviour, not this comment.
  if v_status not in ('open','full') or v_when < now() then raise exception 'session_closed'; end if;

  if not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;

  -- §A's law reaching the second door. One law, two doors.
  if v_format = 'delegated_only' then raise exception 'companion_closed'; end if;

  -- TWO TOKENS, split on custody. ⚠ This is NOT an enumeration oracle, and the reason must be
  -- re-read before anyone "fixes" it into one sentence: the party gate (membership) and the
  -- ownership gate (not_your_dog) have BOTH already passed, so the caller is established as a
  -- party to this session AND the owner of this dog. They are entitled to know which of their own
  -- rows exists. Unlike session_rsvp, both shapes are genuinely reachable here.
  select custody into v_custody from session_dogs
   where session_id = p_session and dog_id = p_dog and service_state is distinct from 'ended'
   limit 1;
  if v_custody = 'runner_delegated' then raise exception 'already_delegated';
  elsif v_custody is not null then raise exception 'already_added'; end if;

  -- The shared pool is shared — this door does not get its own budget. Byte-identical predicate
  -- to 0048:118-120 and 0048:175-177.
  if _club_total_dogs(p_session) >= coalesce(v_total_cap, v_people_cap) then
    raise exception 'dog_capacity_full';
  end if;

  -- Exactly one row. No session_people row (it exists — that is the precondition), no
  -- club_sessions.status transition (the people count did not move, so 0048:193's transition
  -- would be a lie here), no notification, no booking, no money.
  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id)
  values (p_session, p_dog, auth.uid(), 'owner_handled', auth.uid())
  on conflict (session_id, dog_id) where (service_state is distinct from 'ended') do nothing;
  if not found then raise exception 'already_added'; end if;
end $$;
revoke execute on function session_add_my_dog(uuid, uuid) from public, anon;
grant execute on function session_add_my_dog(uuid, uuid) to authenticated;

-- ═══ §D — session_cancel_rsvp refuses after check-in ═══
--
-- ⚠ NOT A UI REGRESSION — IT CLOSES A DIRECT-RPC HOLE. session/[sid].tsx:1223 already renders the
--   cancel CTA only while myAttendance === 'rsvp', so a checked-in participant is offered no
--   button. The record deletion was reachable only by calling this RPC directly, which any
--   authenticated client can. The gate makes the server say what the UI already implies.
create or replace function session_cancel_rsvp(p_session uuid)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_role text; v_checked timestamptz;
begin
  -- NEW, and it is a behaviour change so it is named: today a null-uid caller falls through to
  -- `not_joined` — fail-closed, but by ACCIDENT of the SELECT returning no row rather than by a
  -- gate. Measured: no migration and no edge function calls this; the only callers are
  -- api.ts:3516 (cancelClubRsvp) and the suites, all JWT-bearing.
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  select role, checked_in_at into v_role, v_checked
    from session_people where session_id = p_session and profile_id = auth.uid();
  -- The one-sentence anti-enumeration answer: a session that does not exist and a session the
  -- caller never joined produce the identical row-absent condition and the identical token.
  -- PRESERVED DELIBERATELY — do not "improve" this into a not_found/not_joined split.
  if v_role is null then raise exception 'not_joined'; end if;
  if v_role = 'host_runner' then raise exception 'host_cannot_leave'; end if;

  -- 🔴 ORDER RULING: `already_checked_in` BEFORE `delegation_active`. Both are refusals, so no
  --    invariant is weakened either way — but already_checked_in is TERMINAL (a check-in cannot
  --    be undone) and delegation_active is RESOLVABLE (cancel the delegation and retry).
  --    Answering the resolvable one first sends a mixed-mode owner off to cancel a real
  --    delegation — a money-bearing act — and then refuses them anyway. That is exactly the dead
  --    end the honesty laws exist to prevent. Pinned as a conjunction (D2), not left as a comment.
  --
  -- ⚠ THE PREDICATE IS `checked_in_at is not null`, NOT `attendance = 'checked_in'`.
  --   session_checkin sets both (0030:254-256), but `attendance` can subsequently move to
  --   'no_show' while checked_in_at stays stamped (95:52 does exactly that by UPDATE). Someone who
  --   checked in and was later marked no-show still PHYSICALLY ATTENDED; their record must stand.
  --   The timestamp is durable evidence and cannot be laundered by an attendance move. D5 pins it.
  if v_checked is not null then raise exception 'already_checked_in'; end if;

  -- [0052 §3] 위탁은 참여 취소로 조용히 사라지지 않는다 — 먼저 위탁을 취소해야 한다
  if exists (select 1 from session_dogs
             where session_id = p_session and owner_profile_id = auth.uid()
               and custody = 'runner_delegated' and service_state is distinct from 'ended') then
    raise exception 'delegation_active';
  end if;
  delete from session_dogs where session_id = p_session and owner_profile_id = auth.uid()
    and custody = 'owner_handled';
  delete from session_people where session_id = p_session and profile_id = auth.uid();
  update club_sessions set status = 'open' where id = p_session and status = 'full';
end $$;
revoke execute on function session_cancel_rsvp(uuid) from public, anon;
grant execute on function session_cancel_rsvp(uuid) to authenticated;

comment on function session_add_my_dog is
  '0134 §C (contract club-rsvp-hardening §3C, finding F5): lets any SEATED participant — the host
included, which is the case F5 named — put their own dog into a session they already joined.
session_rsvp cannot do this: their session_people row exists, so it can only ever answer
already_joined (0030:76 unique + 0048:185). Gated on MEMBERSHIP not hostship, deliberately: a
dogless RSVP hits the identical wall. Same format, cap, ownership and conflict law as session_rsvp;
writes exactly one owner_handled session_dogs row and nothing else — no people row, no status
transition, no booking, no money.';
