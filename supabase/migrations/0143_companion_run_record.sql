-- 0143 — the 동반 (self-run) walk finally gets a RECORD. The writer `participant_activities`
-- never had.
--
-- Sean, 2026-08-26, verbatim: 「why those owner run dogs dont have gps? they should and app should
-- ask for it on first download. also yes the self runs are still part of the pack. so yes.」
-- Recorded at docs/decisions/2026-08-25-console-rulings.md §「2026-08-26 — 동반 runs ARE the pack」,
-- RULED #1: 동반 walks ARE part of the pack and are recorded at 러닝 종료.
--
-- THE GAP, measured rather than argued (same file, 「Measured chain, production prosrc」):
--   · `session_rsvp` writes a `session_dogs` row and creates NO booking (0048:186-190).
--   · every `insert into runs` requires a `booking_id` (0083:419, 0083:729, 0087:180, 0087:212).
--   · `club_start_delegated_runs` is `b.runner_id = auth.uid()`-scoped (0038:130-134) and never
--     mentions `owner_handled`.
--   ⇒ a 동반 dog can never hold a `runs` row, so the 0038:137 trigger — the ONLY thing that has
--     ever written a measured `participant_activities` row — can never fire for it. The host, the
--     one person guaranteed to walk, was the one person guaranteed to get no record.
--
-- NO NEW TABLE. `participant_activities` (0030:101) was built for exactly this: `run_id` nullable,
-- `source` already admitting `self_reported` and `checkin_only`, `unique (session_id, person_id)`.
-- The schema anticipated participants without bookings; nothing wrote it for them.
--
-- ⚠ `person_id` IS A FK TO `session_people(id)`, NOT `profiles(id)` (0030:104). 0131 hit this
--   once already — a draft policy arm reading `person_id = auth.uid()` could NEVER match and read
--   as an own-row guarantee (REGISTRY 0131 row, defect (a)). This function resolves the caller's
--   `session_people.id` and writes THAT. Suite 175 C1 pins the linkage by joining back, not by
--   asserting non-null.
--
-- 🔴 WHY THE UPSERT IS THE WHOLE MECHANISM. `session_checkin` (0030:262) ALREADY inserts a
--   `checkin_only` row for this (session, person) the moment they check in. So this function is
--   almost always an UPDATE of a row that exists, and「re-finishing replaces, never duplicates」
--   falls straight out of the 0030:112 unique constraint. `_club_log_activity` writes rows with
--   `person_id = null`, so a delegated dog's `gps_verified` row can never be the conflict target
--   (NULLs are distinct in a unique index). `run_id` is deliberately NOT in the insert column list
--   and NOT in the DO UPDATE set: if a row ever did carry a run link, this call records the walk
--   without severing it.
--
-- WHAT THIS IS NOT: not money. `participant_activities` has zero readers in migrations, edge
-- functions and `app/src` outside 0030/0038/0131 (measured by grep across all three trees), and
-- no write RLS policy exists on it at all (0030:139 — 「쓰기 정책 없음 = 직접 쓰기 금지 (RPC 전용)」),
-- so this definer is the only door and nothing downstream re-prices on it.
--
-- ⚠ NO `_club_require_v2()`. That gate is the 위탁 v2 allowlist (0044:23). 동반 is not delegation —
--   Sean ruled Mode A FREE and fee-less (console follow-up F2, 「무료로 크루 참가」), and its
--   siblings `session_rsvp` / `session_checkin` / `session_add_my_dog` carry no such gate either.
--   Putting one here would lock a free feature behind the paid feature's allowlist.

begin;

-- ═══ the writer ═══
--
-- GATE ORDER — party gate before state gate (0116 §D ⓐ), and the tokens are named so the client
-- can say something true in Korean instead of surfacing a PostgREST string.
--
--   not_signed_in    → no JWT at all.
--   not_joined       → no `session_people` row. ⚠ Deliberately the SAME answer for 「this session
--                      does not exist」 and 「you never joined it」: both are the row-absent
--                      condition and splitting them would build an enumeration oracle out of a
--                      UUID. `session_cancel_rsvp` (0134 §D) makes the identical choice for the
--                      identical reason — do not 「improve」 this into not_found/not_joined.
--   not_checked_in   → they hold a seat but never stamped in. A record of a walk by somebody who
--                      was not at the meetup is the same class as a fixture the lifecycle cannot
--                      produce, except the product would be producing it.
--   no_companion_dog → checked in, but no live `owner_handled` dog here. This is what refuses a
--                      purely DELEGATED owner and the dogless crew: a delegated dog's walk is
--                      recorded by 0038:137 off its own `runs` row at settle, and a second
--                      self-reported row for the same walk would be the same walk counted twice.
--   invalid_measure  → the sanity bands below.
--
-- ⚠ NO SESSION-STATUS GATE, AND THAT IS A DECISION. The obvious extra conjunct
--   (`status in ('open','full')`, or a clock window) would strand precisely the person this
--   function exists for: the slow walker who taps 종료 after the host already closed the session.
--   CLAUDE.md §Migrations: prefer a conjunct keyed to a fact that has ALREADY OCCURRED over a
--   clock. `checked_in_at is not null` is that fact — it is durable, it is the counterparty-
--   independent evidence that this person was physically at this meetup, and `session_checkin`
--   already enforces the −2h/+6h window when the stamp is made (0030:245-247). Recording against
--   a stamp that already exists cannot be earlier or looser than the stamp itself.
--   The residual is stated rather than hidden: a checked-in participant can write their own record
--   arbitrarily late. It is their own row, it holds no money, and it overwrites nothing but itself.
--
-- ⚠ THE PREDICATE IS `checked_in_at`, NOT `attendance = 'checked_in'`. 95:52 moves `attendance` to
--   'no_show' by UPDATE while the stamp stands, and someone who checked in still physically
--   attended. 0134 §D chose the same column for the same reason and D5 pins it there.
create or replace function session_record_companion_run(
  p_session uuid,
  p_km numeric default null,
  p_duration_sec int default null
) returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_person uuid; v_checked timestamptz; v_dog uuid; v_source text; v_pace int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- PARTY GATE.
  select id, checked_in_at into v_person, v_checked
  from session_people where session_id = p_session and profile_id = auth.uid();
  if v_person is null then raise exception 'not_joined'; end if;

  -- STATE GATE ① — attendance.
  if v_checked is null then raise exception 'not_checked_in'; end if;

  -- STATE GATE ② — a live 동반 dog of THEIRS in THIS session.
  -- ⚠ `service_state is distinct from 'ended'` is a UNIFORMITY conjunct here and this comment is
  --   what stops a green pin being read as proof of it: the axes function returns
  --   `service_state => null` for EVERY `owner_handled` row (0043:94-102), so today no
  --   owner_handled row can be 'ended' and this conjunct cannot fail. It is kept because it is the
  --   byte-identical liveness predicate used by 0134 §C, 0134 §D and 0140, and diverging from it
  --   here would be the kind of one-off that a future custody flip turns into a bug.
  --   `custody = 'owner_handled'` is the conjunct doing the real work — it is what makes a mixed
  --   owner's record name their COMPANION dog and not the one they handed to a runner (C9).
  -- `owner_profile_id`, not `responsible_profile_id`: 0140's limit counts by owner, and every
  -- owner_handled writer sets both to the same uid (0048:187, 0134 §C).
  select sd.dog_id into v_dog
  from session_dogs sd
  where sd.session_id = p_session
    and sd.owner_profile_id = auth.uid()
    and sd.custody = 'owner_handled'
    and sd.service_state is distinct from 'ended'
  order by sd.seq
  limit 1;
  if v_dog is null then raise exception 'no_companion_dog'; end if;

  -- SANITY BANDS, mirroring the house rules: km ∈ [0, 100] (0028:46, 0083:405), duration
  -- non-negative (0028:49, 0083:407), plus a ceiling the house never needed because a booking
  -- bounded it — 24h. A walk longer than a day is not a walk, and `pace_sec_per_km` is an `int`.
  -- ⚠ ONE TOKEN, `invalid_measure`, where the house splits `invalid_km` / `invalid_duration`.
  --   Deliberate and narrow: this is not a money path, neither band is separately actionable by
  --   the person tapping 종료, and the client has exactly one 저장 실패 branch. If a future caller
  --   ever needs to tell them apart, splitting the token is one line and one pin.
  if p_km is not null and (p_km < 0 or p_km > 100) then raise exception 'invalid_measure'; end if;
  if p_duration_sec is not null and (p_duration_sec < 0 or p_duration_sec > 86400) then
    raise exception 'invalid_measure';
  end if;

  -- SOURCE. Sean's checkin_only ruling, in the same section: 「A 동반 walk with GPS lands as
  -- gps_verified; one with a flat battery lands as checkin_only rather than never having
  -- happened.」 A null km is the flat battery — the walk still happened and the row still says so.
  -- ⚠ `gps_verified` is NOT written here on purpose: 0038:152 reserves it for a walk the SERVER
  --   measured off a stored `runs` row. This function is handed a number by a client, which is
  --   exactly what `self_reported` means. Calling it verified would be a fake number by vocabulary.
  v_source := case when p_km is null then 'checkin_only' else 'self_reported' end;

  -- pace only when both halves are real — mirrors 0028:72's guard, which exists because km can be
  -- 0.00 and division by zero is not a pace.
  v_pace := case
    when p_km is not null and p_km > 0 and p_duration_sec is not null and p_duration_sec > 0
    then round(p_duration_sec / p_km)::int
  end;

  -- ONE ROW PER (session, person). See the header: the conflict target is normally the row
  -- `session_checkin` already wrote. `run_id` is untouched by both arms, by design.
  insert into participant_activities
    (session_id, person_id, dog_id, km, pace_sec_per_km, duration_sec, source)
  values
    (p_session, v_person, v_dog, p_km, v_pace, p_duration_sec, v_source)
  on conflict (session_id, person_id) do update
    set dog_id          = excluded.dog_id,
        km              = excluded.km,
        pace_sec_per_km = excluded.pace_sec_per_km,
        duration_sec    = excluded.duration_sec,
        source          = excluded.source;
end $$;

-- EXPLICIT ACL — never grant preservation (0116:636; CLAUDE.md §Migrations). This function is
-- first defined here, so the pair below is what decides its ACL on EVERY apply path.
revoke execute on function session_record_companion_run(uuid, numeric, int) from public, anon;
grant execute on function session_record_companion_run(uuid, numeric, int)
  to authenticated, service_role;

comment on function session_record_companion_run is
  '0143: the 동반 (self-run) walk''s record writer. Sean 2026-08-26 「the self runs are still part
of the pack」. Upserts the single participant_activities row for (session, caller) — source
self_reported when a km is supplied, checkin_only when it is not (flat battery is still a walk that
happened). person_id is the caller''s session_people.id, NOT their profile id (0030:104 FK).
Party gate (session_people row) before state gates (checked_in_at, then a live owner_handled dog).
No booking, no runs row, no money. A delegated dog is refused here: 0038:137 records it from its
own runs row at settle, and a second self-reported row would be the same walk counted twice.';

-- ═══ VERIFY ═══
--
-- ⚠ NO prosrc GREP HERE, DELIBERATELY. A comment that quotes the code it replaced matches every
--   grep that hunts for that code (CLAUDE.md §Migrations, 2026-08-26), and this file is dense with
--   comments naming its own tokens — a text scan over `prosrc` would be green on a body whose
--   gates had all been deleted, purely off the comments above. So every arm below measures STATE
--   (catalog columns, privilege answers) or BEHAVIOUR (a real call), never shape.
do $$
declare
  v_oid oid; v_sec boolean; v_cfg text[]; v_kind char;
  v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_before bigint; v_after bigint; v_err text; v_probe uuid := gen_random_uuid();
  v_accepted boolean;
begin
  -- ① the object exists, and is the SHAPE the ACL/search_path laws are about.
  select p.oid, p.prosecdef, p.proconfig, p.prokind
    into v_oid, v_sec, v_cfg, v_kind
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace
    and p.proname = 'session_record_companion_run';
  if v_oid is null then raise exception '0143 VERIFY ①: function absent'; end if;
  if not v_sec then raise exception '0143 VERIFY ①: not SECURITY DEFINER'; end if;
  if v_kind <> 'f' then raise exception '0143 VERIFY ①: prokind=%', v_kind; end if;
  -- in-body `set search_path`, which is what survives create or replace (98 H1's property).
  if not (v_cfg @> array['search_path=public, pg_temp']) then
    raise exception '0143 VERIFY ①: proconfig=% (expected in-body search_path=public, pg_temp)',
      coalesce(array_to_string(v_cfg, ','), '<null>');
  end if;

  -- ② ACL — BOTH DIRECTIONS. A negative-only ACL check passes on a function nobody can call.
  select has_function_privilege('public', v_oid, 'execute'),
         has_function_privilege('anon', v_oid, 'execute'),
         has_function_privilege('authenticated', v_oid, 'execute'),
         has_function_privilege('service_role', v_oid, 'execute')
    into v_pub, v_anon, v_auth, v_svc;
  if v_pub then raise exception '0143 VERIFY ②: PUBLIC can execute'; end if;
  if v_anon then raise exception '0143 VERIFY ②: anon can execute'; end if;
  if not v_auth then raise exception '0143 VERIFY ②: authenticated CANNOT execute — the grant did not land'; end if;
  if not v_svc then raise exception '0143 VERIFY ②: service_role CANNOT execute'; end if;

  -- ③ BEHAVIOUR, two live calls, zero residue. `set_config(..., true)` is transaction-LOCAL, so
  --    the identity set here is gone at commit; the migration applies inside one transaction
  --    (harness --single-transaction, and `supabase db push` does the same per file).
  select count(*) into v_before from participant_activities;

  -- ③a NEGATIVE: no identity at all.
  -- ⚠ The verdict rides a FLAG, not a raise inside the block: a `raise` in the try arm would be
  --   swallowed by this block's own `when others` and re-emerge as 「expected X, got <my own
  --   message>」 — a detector reporting its own failure text, which is the substring-detector
  --   family this repo has already been bitten by twice.
  v_accepted := false; v_err := null;
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    perform session_record_companion_run(v_probe, 3.0, 1800);
    v_accepted := true;
  exception when others then v_err := sqlerrm;
  end;
  if v_accepted then raise exception '0143 VERIFY ③a: a null-uid caller was ACCEPTED'; end if;
  if v_err <> 'not_signed_in' then
    raise exception '0143 VERIFY ③a: expected not_signed_in, got %', v_err;
  end if;

  -- ③b THE GATE IS REACHED — a signed-in stranger gets past not_signed_in and is stopped by the
  --    PARTY gate. Without this arm ③a is green on a body whose first line raises unconditionally.
  v_accepted := false; v_err := null;
  begin
    perform set_config('request.jwt.claim.sub', v_probe::text, true);
    perform session_record_companion_run(v_probe, 3.0, 1800);
    v_accepted := true;
  exception when others then v_err := sqlerrm;
  end;
  if v_accepted then raise exception '0143 VERIFY ③b: a non-participant was ACCEPTED'; end if;
  if v_err <> 'not_joined' then
    raise exception '0143 VERIFY ③b: expected not_joined, got %', v_err;
  end if;
  perform set_config('request.jwt.claim.sub', '', true);

  -- ③c neither refusal wrote anything. A refusal that leaves a row behind is 0134 §B's F4.
  select count(*) into v_after from participant_activities;
  if v_after <> v_before then
    raise exception '0143 VERIFY ③c: refusals wrote % row(s)', v_after - v_before;
  end if;
end $$;

commit;
