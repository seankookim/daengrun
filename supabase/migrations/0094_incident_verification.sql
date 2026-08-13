-- 0094 — ⑪ 인시던트는 양측이 확인한다. 그리고 그 전에, 마켓플레이스 인시던트를 만들 수 있게 한다.
--
-- ═══ §0 THE RULING ═══════════════════════════════════════════════════════════════════════
-- Sean, 2026-08-13, verbatim:
--   "incident verified by both runner and owner."
--
-- `incident` is the largest single loss in the money system and the only outcome nobody
-- disputes, because the owner is not billed. Every other cell has a natural auditor — an owner
-- who is charged reads the charge. Here there is none. 0084 built two thirds of Sean's original
-- instruction ("verify incident first to avoid abuse"): `settle-run` refuses a runner-declared
-- `incident`, and the waive is reviewable rather than silent. **What was missing was a person.**
-- This file adds the person, and makes it two of them.
--
-- ═══ §1 WHAT I FOUND BEFORE WRITING A LINE, WHICH CHANGED THE SLICE ══════════════════════
-- ⑪'s memo describes this as "model it on the two-sided handoff" — i.e. add two stamps. It is
-- not that, because **there is nothing to stamp.** Measured, not assumed:
--   ① **`incidents` has NO WRITER ANYWHERE.** Not a migration, not `api.ts`, not an edge
--      function. The table has existed since `0001:383` and only ever been read.
--   ② therefore **`incident_contact()` (0088 §E) returns ZERO ROWS for every marketplace
--      booking, by construction** — its state gate is `exists (select 1 from incidents where
--      booking_id = … and resolved_at is null)`, and no such row can exist. 0088's own comment
--      says so out loud: *"incidents에 행을 넣는 코드도 없다"*. The door Sean's phone ruling
--      depends on is built, correct, and connected to nothing.
--   ③ **0083's 2h janitor reaches `incident_review` WITHOUT creating an incident row.** So the
--      one marketplace path that actually produces an incident today produces a booking STATUS
--      and no incident RECORD — which means during exactly the emergency ⑪ is about, the two
--      parties cannot see each other's numbers.
-- A slice that added verification stamps on top of this would have pinned a machine that can
-- never run. So §3 builds the open path first. That is scope growth, and it is named here
-- rather than absorbed quietly.
--
-- ═══ §2 A SECURITY HOLE ON THE WAY PAST — `0002:154` ═════════════════════════════════════
-- 🔴 `create policy "incidents report" on incidents for insert with check (reporter_id = auth.uid())`
-- checks WHO is reporting and **not WHICH BOOKING they are reporting on**. Any authenticated
-- user may insert an incident row against ANY booking id. It has never been exploitable in
-- practice for the reason above (nothing reads incidents except `incident_contact`, and nothing
-- writes them) — but the moment ③ is fixed and `incident_contact` starts returning rows, this
-- becomes a **remote privacy trigger**: a stranger opens an incident on your booking and your
-- runner and you are handed each other's phone numbers by a third party's action.
-- The gate order that matters (party BEFORE state, house law) protects the *caller*; it does not
-- protect the *subject*. So the raw INSERT policy is DROPPED and replaced by a party-gated RPC.
-- ⚠ Dropped, not narrowed: nothing else in the repo re-creates `"incidents report"` (verified),
-- and a policy that must check booking party is doing an RPC's job in a WITH CHECK clause.
--
-- ═══ §3 THE OPEN PATH — who may say an incident happened ═════════════════════════════════
-- Either party of THAT booking, through `open_incident_tx`. Not ops-only: an incident is an
-- emergency and the people present are the parties. Opening is deliberately CHEAP and one-sided,
-- and that is not in tension with the ruling — see §4.
--
-- ═══ §4 🔴 OPENING IS ONE-SIDED. ESTABLISHING IS NOT. AND THE PHONES OPEN ON THE OPEN. ═══
-- This is the load-bearing distinction in the file, and getting it backwards would be dangerous
-- in the literal sense.
--   · **Opening** an incident is a CLAIM by one party. It costs nothing, decides nothing, and
--     moves no money. One person is enough, because a dog may be bleeding.
--   · **Verifying** is the two-sided fact Sean ruled on. `verified_at` is written only when both
--     parties have stamped. That is what makes the incident *established*.
--   · **The phone door opens on the OPEN, not on the verification.** Sean's words are "phone
--     numbers should be present during those emergency situations" — an emergency needs phones
--     in the first minute, and requiring the other party to confirm before you can call them is
--     a deadlock precisely when it is most expensive. `incident_contact` is therefore left
--     EXACTLY as 0088 wrote it: gated on `resolved_at is null`, not on `verified_at`.
--     ⚠ This file neither widens nor narrows that door. 0088 §E is the correctly-scoped ruling
--     and ⑪'s memo warns specifically against a future reader "unblocking" ⑪ by widening it —
--     narrowing it to verified-only would be the same error wearing a safety costume.
--   · So a one-sided claim CAN expose two phone numbers. That is the accepted cost, and §2's
--     fix is what makes it acceptable: only a party to that booking can trigger it, and it is
--     recorded against their name.
--
-- ═══ §5 THE FORCE PATH IS OPS-ONLY AND WRITES NO PARTY STAMP (0089's law, inherited) ═════
-- 0089 removed the party force from the RETURN path because Sean ruled "the confirmation must
-- happen with both parties and never just the runner". A two-party machine born AFTER that
-- ruling must not reintroduce the shape it deleted. So `force_verify_incident_tx` is service_role
-- only, refuses `runner`/`owner` by name, and — the part 0089 fought for — writes NEITHER party
-- stamp. An ops resolution sets `verified_at` and records itself as the actor, leaving both party
-- stamps NULL, so a later reader can tell "ops established this" from "both parties confirmed it".
-- ⚠ ⑪'s memo build-note #4 says "a force path recording actor, eligibility time, reason and
-- evidence immutably", which was written from 0083's pre-0089 shape. Eligibility TIME is
-- deliberately not recorded: `FORCE_GRACE` retired with the party path in 0089, and inventing a
-- waiting period here would imply a grace that no longer exists for anyone.
--
-- ═══ §6 WHAT THIS FILE DELIBERATELY DOES NOT DO ══════════════════════════════════════════
-- · **No money.** ⑪ decides whether an incident is real; ⑫ decides what money does once it is,
--   and Sean already ruled ⑫ (pay the runner, gate the next run — `0092`). Nothing here writes
--   `ledger_items`, `payments`, or touches `settle_run_tx`/`compute_owner_charge`.
-- · **No booking status change.** Opening an incident does NOT push the booking to
--   `incident_review`. That transition has exactly one marketplace commercial exit problem
--   (`0001:193`, only → `refund_pending`) and walking into it on a one-sided claim would strand
--   the booking. The incident is a RECORD alongside the booking, not a state of it.
-- · **No self-healing sweep, and no 2h escalation.** ⑪'s memo suggests both. Neither is built
--   here and the reason is that this machine has no crash window to recover: `verify_incident_tx`
--   writes the stamp and computes `verified_at` in ONE statement, so there is no gap between
--   stamp and effect for a sweep to find. 0083 needed one because its effect was a PAYMENT that
--   SQL could not re-drive. Inheriting the sweep without inheriting the reason would be building
--   a recovery mechanism for a failure that cannot occur.
-- · **Does not re-create any object another slice owns.** NEW ONLY: `open_incident_tx`,
--   `verify_incident_tx`, `force_verify_incident_tx`. `incident_contact` (0088) is UNTOUCHED.

-- ── §7 the columns ────────────────────────────────────────────────────────────────────────
alter table incidents
  add column if not exists runner_verified_at timestamptz,
  add column if not exists owner_verified_at  timestamptz,
  add column if not exists verified_at        timestamptz,
  add column if not exists verify_forced_by   text,
  add column if not exists verify_forced_at   timestamptz,
  add column if not exists verify_force_reason   text,
  add column if not exists verify_force_evidence jsonb;

alter table incidents drop constraint if exists incidents_verify_forced_by_check;
alter table incidents add constraint incidents_verify_forced_by_check
  check (verify_forced_by is null or verify_forced_by = 'ops');

comment on column incidents.verified_at is
  '0094 ⑪ — 이 인시던트가 사실로 확립된 시각. 양측 도장이 모두 찍혔을 때, 또는 ops 판정이 있었을 때만
채워진다 (Sean 2026-08-13: "incident verified by both runner and owner"). ⚠ 열림(open)과 다르다:
여는 것은 한쪽의 주장이고 공짜이며, 전화번호 문은 열림에서 열린다 (0088 §E, 0094 §4). 확립은 양측이다.';
comment on column incidents.verify_forced_by is
  '0094 — ''ops'' 또는 NULL. 당사자는 절대 강제할 수 없다 (0089의 판결을 상속). ops 판정은 verified_at만
채우고 양측 도장은 NULL로 남긴다 — 나중에 읽는 사람이 "ops가 확립" 과 "양측이 확인"을 구분할 수 있어야 한다.';

-- ── §8 §2's hole: the raw INSERT policy goes ──────────────────────────────────────────────
drop policy if exists "incidents report" on incidents;

-- ── §9 the open path ──────────────────────────────────────────────────────────────────────
create or replace function open_incident_tx(
  p_booking  uuid,
  p_kind     text,
  p_severity text default 'normal',
  p_note     text default null,
  p_media    text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- party gate BEFORE state gate (house law), and the party check is on THIS booking — which is
  -- the whole of §2's fix. `for update` so two simultaneous opens serialise on the booking.
  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status
    into b from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
    raise exception 'not_party';
  end if;
  if p_kind not in ('dog_injury','lost_dog','third_party','equipment','other')
    then raise exception 'bad_kind'; end if;
  if p_severity not in ('normal','urgent','sos') then raise exception 'bad_severity'; end if;

  -- One OPEN incident per booking. A second open is not an error — it returns the existing one,
  -- so a double-tap in an emergency does not produce two cases for one event, and the caller
  -- still gets a usable id rather than a raise it has to interpret under stress.
  select i.id into v_id from incidents i
   where i.booking_id = p_booking and i.resolved_at is null
   order by i.created_at limit 1;
  if v_id is not null then return v_id; end if;

  insert into incidents (booking_id, reporter_id, kind, severity, note, media)
  values (p_booking, v_uid, p_kind, p_severity, p_note, coalesce(p_media, '{}'))
  returning id into v_id;
  return v_id;
end $$;

revoke execute on function open_incident_tx(uuid, text, text, text, text[]) from public, anon;
grant  execute on function open_incident_tx(uuid, text, text, text, text[]) to authenticated, service_role;

-- ── §10 the two-sided verification ────────────────────────────────────────────────────────
create or replace function verify_incident_tx(p_incident uuid, p_side text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare i record; b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
        v_r timestamptz; v_o timestamptz; v_verified timestamptz;
begin
  if p_side not in ('runner','owner') then raise exception 'bad_side'; end if;

  select inc.id, inc.booking_id, inc.resolved_at, inc.verified_at,
         inc.runner_verified_at, inc.owner_verified_at, inc.verify_forced_by
    into i from incidents inc where inc.id = p_incident for update;
  if i.id is null then raise exception 'not_found'; end if;

  select bk.owner_id, bk.runner_id into b from bookings bk where bk.id = i.booking_id;
  -- party gate before state gate. The caller must BE the side they claim — this is where a
  -- one-sided machine would leak: "I am the owner" is a claim, `auth.uid()` is a fact.
  if v_uid is null or v_uid is distinct from (case when p_side = 'runner' then b.runner_id else b.owner_id end)
    then raise exception 'not_party'; end if;

  -- DISTINCT FACTS GET DISTINCT NAMES (0083's law, ⑪ memo build-note #7). "already established"
  -- and "already closed" are different sentences to a human and must not collapse into one.
  if i.resolved_at is not null then raise exception 'incident_resolved'; end if;

  -- Idempotent: a second stamp from the same side is success, not a raise. The concurrent loser
  -- returns the same shape after re-reading, rather than an error it would have to interpret.
  update incidents set
      runner_verified_at = case when p_side = 'runner'
                                then coalesce(runner_verified_at, v_now) else runner_verified_at end,
      owner_verified_at  = case when p_side = 'owner'
                                then coalesce(owner_verified_at,  v_now) else owner_verified_at  end
   where id = p_incident
  returning runner_verified_at, owner_verified_at into v_r, v_o;

  -- The effect fires in the SAME statement's aftermath, from the RE-READ values — never from
  -- what this call believes it wrote. Both stamps present, and only then.
  if v_r is not null and v_o is not null then
    update incidents set verified_at = coalesce(verified_at, v_now)
     where id = p_incident returning verified_at into v_verified;
  else
    v_verified := null;
  end if;

  return jsonb_build_object(
    'incident_id', p_incident,
    'runner_verified', v_r is not null,
    'owner_verified',  v_o is not null,
    'verified', v_verified is not null,
    'verified_at', v_verified,
    'waiting_on', case when v_r is null and v_o is null then 'both'
                       when v_r is null then 'runner'
                       when v_o is null then 'owner'
                       else null end);
end $$;

revoke execute on function verify_incident_tx(uuid, text) from public, anon;
grant  execute on function verify_incident_tx(uuid, text) to authenticated, service_role;

comment on function verify_incident_tx is
  '0094 ⑪ — 인시던트 양측 확인 (Sean: "incident verified by both runner and owner"). 한쪽 도장만으로는
verified_at이 절대 채워지지 않는다. 멱등이며, 재읽기 값으로만 효과를 판단한다. 당사자 게이트가 상태
게이트보다 먼저. incident_resolved와 not_party는 서로 다른 사실이므로 이름도 다르다.';

-- ── §11 the ops force — inherits 0089's law ───────────────────────────────────────────────
create or replace function force_verify_incident_tx(
  p_incident uuid,
  p_side     text,
  p_reason   text,
  p_evidence jsonb
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare i record; v_uid uuid := auth.uid(); v_now timestamptz := now();
begin
  -- Refused BY NAME, exactly as 0089 §6 does for the return force: the caller is asking for
  -- something a sibling machine used to allow, and the honest answer names the rule.
  if p_side = 'runner' or p_side = 'owner' then
    raise exception 'force_party_forbidden'
      using detail = '인시던트 확인은 양측이 함께 해야 해요 — 한 쪽만으로는 확정할 수 없어요';
  end if;
  if p_side <> 'ops' then raise exception 'bad_side'; end if;
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then
    raise exception 'evidence_required';
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason_required'; end if;

  select inc.id, inc.verified_at, inc.verify_forced_by, inc.resolved_at
    into i from incidents inc where inc.id = p_incident for update;
  if i.id is null then raise exception 'not_found'; end if;
  if i.resolved_at is not null then raise exception 'incident_resolved'; end if;

  -- First-writer-wins: the first adjudication is the one a dispute reads.
  if i.verify_forced_by is not null then
    return jsonb_build_object('forced', false, 'forced_by', i.verify_forced_by,
                              'verified', i.verified_at is not null, 'unchanged', true);
  end if;

  update incidents set
      verify_forced_by      = 'ops',
      verify_forced_at      = v_now,
      verify_force_reason   = p_reason,
      verify_force_evidence = p_evidence,
      -- 🔴 [0089's law] NO party stamp is written. An adjudication ESTABLISHES an incident; it
      -- does not CONFIRM one. Both stamps stay exactly as they were, so the row distinguishes
      -- "ops established this" from "both parties confirmed it".
      verified_at           = coalesce(verified_at, v_now)
   where id = p_incident;

  return jsonb_build_object('forced', true, 'forced_by', 'ops', 'verified', true, 'unchanged', false);
end $$;

revoke execute on function force_verify_incident_tx(uuid, text, text, jsonb) from public, anon, authenticated;
grant  execute on function force_verify_incident_tx(uuid, text, text, jsonb) to service_role;

comment on function force_verify_incident_tx is
  '0094 ⑪ — OPS 전용 인시던트 확립. 당사자(runner/owner)는 이름을 불러 거부된다
(force_party_forbidden) — 0089가 반환 경로에서 제거한 한쪽 확정을, 그 판결 뒤에 태어난 기계가
다시 들여올 수는 없다. 어느 쪽 도장도 찍지 않고 verified_at과 행위자만 남긴다.';
