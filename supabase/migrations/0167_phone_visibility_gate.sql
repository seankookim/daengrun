-- ═══ 0167: the phone-collection switch gates VISIBILITY, not only WRITES ═══
--
-- closes codex 0154 #3 (CRITICAL), `docs/decisions/2026-08-28-codex-verdicts.md` §0154:
--   「the collection switch gates only WRITES (0154:139-145); visibility paths
--    (`_club_phone_visible`, roster) never consult `phone_collection_live()` — numbers written via
--    0133/service_role are returnable while the flag is closed.」
--
-- WHY THAT IS A REAL HOLE AND NOT A THEORETICAL ONE. 0154 put the ship gate on the WRITE path
-- (`set_my_phone` raises `phone_collection_closed`) and stopped there, because the write path is
-- the only way a CLIENT can put a number in. But `profiles.phone` has two other writers that the
-- flag says nothing about: `service_role` (edge functions, an ops console, a restore) and any
-- future backfill — and **every suite fixture in this repo writes it directly**, which is exactly
-- how a reviewer reading the suites would conclude the numbers are there. Once a number is in the
-- column by ANY route, the two read doors hand it out while Sean's switch is still off:
--   · `_club_phone_visible` (0049:167-192) → `club_session_roster` (0053:412 · 0053:438) embeds
--     the number in the roster payload AND writes a `club_phone_access_log` row for it;
--   · `incident_contact` (0088:238-270) returns both booking parties' numbers.
-- The flag's whole purpose (0154 §A's comment, contract §8) is that **no third-party disclosure of
-- a phone number happens until counsel's revised 개인정보처리방침 is live in-app.** A gate that only
-- stops collection does not buy that property; it buys 「our own client cannot collect」, which is a
-- smaller sentence than the one the flag is quoted for.
--
-- ⚠ THIS IS THE 「A FINDING'S SENTENCE IS THE PROPERTY, THE CITED SITE IS ONE PLACE IT IS
--   OBSERVABLE」 LAW APPLIED FORWARD. codex cited `_club_phone_visible` and 「roster」; the sentence
--   is 「a number must not be RETURNABLE while the flag is closed」, so `incident_contact` — a
--   marketplace door codex named separately as #4 — is inside the same sentence and is gated here.
--
-- ═══ SCOPE — exactly two functions, and what is deliberately NOT here ═══
--   · `club_session_roster` is **NOT touched**. It is being redefined in 0165 by another session
--     right now, and it does not need to be: it reads `_club_phone_visible` per person (0053:412)
--     and again for the access log (0053:438), so gating inside (a) propagates to both — the
--     number falls out of the payload AND no access-log row is written. Editing it here would be a
--     collision for no gain. Suite 197 pins the propagation THROUGH the roster anyway, so if 0165
--     lands a roster that stops consulting the helper, a pin says so.
--   · 0154 #1 (host↔everyone is bidirectional and wide) and #4 (both parties see both numbers)
--     are **Sean's product calls**, ruled twice already (contract §10 ②, and 2026-08-28
--     「guest is a member」). This file does not narrow WHO may see a number. It makes the whole
--     disclosure surface answer to the one switch he flips.
--   · #2 (requiredness after RSVP) is untouched.
--   · **No new column and no new flag.** One reader, `phone_collection_live()` (0154 §B), already
--     exists, already fails closed on a NULL flag AND on a missing `ops_flags` row, and is already
--     the thing `set_my_phone` consults. A second switch would be a second thing to remember to
--     flip, which is how a fail-closed posture dies.
--
-- ═══ THE GATE'S EXACT SHAPE, AND WHY `is not true` AND NOT `not` ═══
--   `phone_collection_live()` is declared `returns boolean` and its body coalesces — so today it
--   cannot answer NULL. **`is not true` does not depend on that staying so.** If the reader ever
--   gains a condition that can be NULL (the column is nullable; a future `and <something>` is one
--   edit away), `if not phone_collection_live()` is plpgsql-SILENT on NULL — no branch taken,
--   execution falls through, and the number is disclosed. That is this repo's most-measured defect
--   class, and it lands in precisely the guards whose job is to notice something MISSING.
--   **NULL is CLOSED.** Written as `is not true` in the plpgsql door and as an explicit
--   `is true` conjunct where a boolean is being computed.
--
-- ═══ WHAT CHANGED PER FUNCTION, so a reviewer can diff it in their head ═══
--  (a) `_club_phone_visible(uuid, uuid, uuid)` — ONE prepended statement, and a LANGUAGE change
--      forced by it. 0049's body is `language sql`; a `return false` early exit is plpgsql. The
--      rest of the body is 0049:172-191 **byte-identical**, wrapped in `return ( … );` — the
--      lifetime gate, the host arm and the 보호자↔수락 러너 arm are not re-typed, re-indented or
--      re-commented, so the diff is the wrapper and nothing else. ⚠ The one consequence of the
--      language change worth naming: a `language sql` body can be INLINED into the calling query
--      plan and a plpgsql body cannot. Both call sites (0053:412, 0053:438) run over one session's
--      roster — tens of rows — so this is not a hot path; recording it because 「why is this
--      plpgsql」 is the question a later reader will ask, and the answer is 「so the gate can be a
--      statement rather than a conjunct the source pin cannot see」.
--  (b) `incident_contact(uuid)` — the gate must NOT be an early `return`, and that is the whole
--      design decision. The function returns `table (role text, name text, phone text)`; returning
--      zero rows while the flag is closed would make 「collection is off」 INDISTINGUISHABLE from
--      「you are not a party」 and 「there is no open incident」 — which 0088 §E built on purpose and
--      which the client reads as 「no incident」 (`api.ts:3559` says so in those words). A person
--      mid-incident would be told there is no incident. So the SHAPE is unchanged and only the
--      `phone` column is nulled: `role` and `name` are still returned, the row COUNT is unchanged,
--      and nothing raises. The client does not call this function today (`api.ts:3487-3495`
--      records the two measured reasons), so nothing decodes differently — but the ui6 incident
--      screen is claimed work (REGISTRY:316), and it will decode `(role, name, phone)` with a null
--      phone exactly as it would for a party who never entered one.
--
-- ⚠ BOTH ARE `create or replace` OF FUNCTIONS FIRST DEFINED IN OTHER FILES (0049 · 0088), so the
--   explicit ACL below is MANDATORY and is not decoration — on an apply where the function is
--   absent (a partial prior apply, a branch that never ran 0049/0088, a rebuilt environment) each
--   statement is a plain CREATE and the definer is born PUBLIC-executable (0116:636).
--   `check-definer-acl.mjs` refuses exactly this shape in a file that does not set the ACL itself.
--   The ACLs below are 0049:193 and 0088:273-274 verbatim, cited, not re-derived.
--
-- ⚠ IN-BODY `set search_path = public, pg_temp` ON BOTH, and on (a) that is a REPAIR as well as an
--   obligation: 0049:170 wrote `set search_path = public` (no `pg_temp`) and 0055 §2's bulk
--   `alter function` added it afterwards — **ALTER-applied config is discarded by
--   `create or replace`**, so writing this in the body is what keeps 98 H1 green. Measured on the
--   harness before this file existed: `proconfig = {"search_path=public, pg_temp"}`.
--
-- ⚠ SUITES WHOSE PINNED BEHAVIOUR LEGITIMATELY CHANGES, updated in this slice (house law), each
--   by ARMING the flag in its own fixture and restoring it — never by softening a proposition.
--   FOUR pins across THREE files, and every one of them asserts a REAL NUMBER on purpose:
--     · `67_shell_suite.sql` H5 — 규칙 B roster + access-log dedup. Its sentence is rule B.
--     · `124_profiles_column_grant_suite.sql` G5 — the definer bypass. Its sentence is 「a definer
--       runs as its OWNER, so a revoked column grant does not touch it」, and an arm relaxed to
--       accept NULL could not tell that from 「the switch was shut」, which is the whole pin.
--     · `124 …` G7 — `incident_contact`'s party gate and state gate.
--     · `130_incident_verification_suite.sql` V3 ⓑ — the door opens on OPEN, not on VERIFIED.
--       Same argument as G5: an arm satisfied by NULL cannot see the thing V3 exists to see.
--   The flag's own effect on all four calls is 197's job (P1/P2 club, P3/P4 marketplace).
--
-- 🔴 THE ENUMERATION ABOVE IS THE SECOND ONE. THE FIRST WAS WRONG AND THE HARNESS CAUGHT IT, and
--   the cause is worth writing down because it is this file's own law: the first sweep was
--   `grep -rn 'incident_contact' *.sql | head`, and `head` **cut 130, 141, 149 and 150 out of the
--   answer** — a filter that truncates output is a filter that can hide the answer. It produced a
--   confident list of two suites, of which one (124) was right for the wrong reason: I had opened
--   it at G7 and never seen G5. Re-run unfiltered, the real set is 67 · 96 · 124 · 130 · 141 ·
--   149 · 150, and each was then read rather than assumed: 96 F6 asserts people-array LENGTHS,
--   150 asserts only that a tombstoned call does not raise, 141's single hit is a COMMENT, and
--   149's P-7/P-24 assert ROW COUNTS (0 and 2) — none of which this change moves. Four pins
--   across three files genuinely move, and the harness named the two I had missed.

-- ═══ §A `_club_phone_visible` — the club door ═══
create or replace function _club_phone_visible(
  p_session uuid, p_viewer uuid, p_target uuid
) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- [0167] THE VISIBILITY GATE. Sean's switch is the only thing that opens a phone number to
  -- anybody, in either direction, on any surface. `is not true` and not `not`: a NULL answer is
  -- CLOSED, and a bare `IF` on NULL is silent in exactly the state this guard exists to notice.
  if phone_collection_live() is not true then return false; end if;

  -- Everything below is 0049:172-191 unchanged, comments included, so the diff is this wrapper.
  return (
  select
    -- 수명 게이트
    (exists (select 1 from club_sessions s where s.id = p_session and s.status in ('open', 'full'))
     or exists (select 1 from session_dogs sd where sd.session_id = p_session
                and sd.custody = 'runner_delegated' and sd.custody_phase <> 'resolved'
                and sd.service_state is distinct from 'ended'
                and (sd.owner_profile_id in (p_viewer, p_target)
                     or sd.custodian_profile_id in (p_viewer, p_target))))
    and (
      -- 호스트 ↔ 전원 (양방향)
      exists (select 1 from club_sessions s where s.id = p_session
              and (s.host_profile_id = p_viewer or s.backup_host_profile_id = p_viewer))
      or exists (select 1 from club_sessions s where s.id = p_session
                 and (s.host_profile_id = p_target or s.backup_host_profile_id = p_target))
      -- 보호자 ↔ 수락 러너 (자기 개 한정, 양방향)
      or exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
                 where sd.session_id = p_session and sd.custody = 'runner_delegated'
                   and b.runner_id is not null
                   and ((sd.owner_profile_id = p_viewer and b.runner_id = p_target)
                     or (sd.owner_profile_id = p_target and b.runner_id = p_viewer)))
    )
  );
end $$;
-- ACL: 0049:193 verbatim. Nobody client-facing executes this — it is a helper the roster definer
-- calls as its owner. `service_role` keeps EXECUTE by Supabase's function default privileges
-- (00_shim.sql:135 models production), measured live: proacl {postgres=X/postgres,
-- service_role=X/postgres}. There is nothing to grant back; there IS something to revoke.
revoke execute on function _club_phone_visible(uuid, uuid, uuid) from public, anon, authenticated;

comment on function _club_phone_visible is
  '0049 규칙 B + [0167] 수집 스위치. phone_collection_live() 가 열려 있지 않으면 **무조건 false** —
스위치가 닫힌 동안에는 어떤 경로로 들어온 번호도 반환되지 않는다 (codex 0154 #3). 그 다음이 0049 의
규칙 B: 호스트 ↔ 전원(양방향) · 보호자 ↔ (자기 개의) 수락 러너(양방향), 세션 진행 중이거나 본인 관련
커스터디가 미해소인 동안만. ⚠ NULL 은 닫힘이다 (`is not true`).';

-- ═══ §B `incident_contact` — the marketplace door ═══
-- ⚠ The gate is a PROJECTION, not an early return, and §B's paragraph in the header is the
--   argument: zero rows already means two other things here, and a person mid-incident must not be
--   told there is no incident because of a flag they cannot see. Same defect shape as
--   `set_my_phone` answering `invalid_phone` to a valid number (0154 §C's ordering comment) — a
--   false statement about the CALLER in place of a true statement about OUR rollout.
create or replace function incident_contact(p_booking uuid)
returns table (role text, name text, phone text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare b record; v_live boolean;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- ① party gate. `select … into` + `found` rather than `is_booking_party()` because the two
  -- party ids are needed for the result anyway, and one read beats two.
  select owner_id, runner_id into b from bookings where id = p_booking;
  if not found then return; end if;                        -- unknown booking: silence, not 404
  if auth.uid() is distinct from b.owner_id
     and auth.uid() is distinct from b.runner_id then
    return;                                                -- stranger: silence, not an error
  end if;

  -- ② state gate.
  if not exists (select 1 from incidents i
                  where i.booking_id = p_booking and i.resolved_at is null) then
    return;
  end if;

  -- ③ [0167] THE VISIBILITY GATE. Read AFTER both gates so a stranger's call costs nothing extra
  -- and the silence above is untouched. `is true`, so a NULL answer is CLOSED.
  v_live := phone_collection_live() is true;

  -- Both parties, always both — the ruling is that each side sees the other, and a caller who
  -- also sees their own number learns nothing they did not type in themselves. An unassigned
  -- booking yields ONE row (the owner): the join drops a null runner rather than inventing a
  -- placeholder person.
  -- [0167] `phone` is NULL while the switch is closed. The row count, the roles and the names are
  -- unchanged — the shape a caller decodes does not move, and a null phone is a state this door
  -- could always produce anyway (a party who never entered a number).
  return query
    select v.who, p.name, case when v_live then p.phone else null::text end
      from (values ('owner', b.owner_id), ('runner', b.runner_id)) as v(who, pid)
      join profiles p on p.id = v.pid
     order by v.who;
end $$;

-- ACL: 0088:273-274 verbatim.
revoke execute on function incident_contact(uuid) from public, anon;
grant  execute on function incident_contact(uuid) to authenticated;

comment on function incident_contact is
  '0088 §E: 열린 인시던트 동안 예약 당사자끼리 서로의 전화번호를 본다 (결정 ⑪).
게이트 순서 = 당사자 → 상태. 당사자가 아니거나 열린 인시던트가 없으면 **에러가 아니라 0행** —
두 경우가 구분되면 부킹 id를 훑어 인시던트 유무를 알아내는 오라클이 된다.
🔴 [0167] 세 번째 게이트: phone_collection_live() 가 닫혀 있으면 phone 이 NULL 로 나간다.
**행 수·role·name 은 그대로다** — 0행으로 줄이면 「수집이 닫혔다」가 「당사자가 아니다」·「인시던트가
없다」와 구분되지 않고, 사고 한가운데 있는 사람에게 사고가 없다고 말하게 된다 (codex 0154 #3).
⚠ NULL 은 닫힘이다 (`is true`).';

-- ═══ §C VERIFY — apply-time, and NOT a substitute for suite 197 ═══
-- Different kinds of evidence and neither is evidence for the other: VERIFY says 「the apply
-- produced this shape」, the suite says 「the property holds and a mutation breaks it」. A property
-- checked only at apply is protected exactly until someone recreates the function (0131-G4).
-- ⚠ EVERY ARM ASSERTS AN EXACT BOOLEAN. `has_function_privilege` can answer NULL and plpgsql does
--   not take an `IF` on NULL, so a bare `IF has_*` arm is SILENT in exactly the state it exists to
--   notice. `to_regprocedure` rather than `::regprocedure` for the same reason: the cast RAISES on
--   an absent function (an opaque death that says nothing about the ACL) while `to_regprocedure`
--   returns NULL, which the NO-FUNCTION arms report by name.
do $$
declare
  v_bad text := '';
  v_cpv regprocedure := to_regprocedure('_club_phone_visible(uuid,uuid,uuid)');
  v_ic  regprocedure := to_regprocedure('incident_contact(uuid)');
begin
  -- ① both functions exist at all. Without this every arm below is vacuously green.
  if v_cpv is null then v_bad := v_bad || ' NO-FUNCTION(_club_phone_visible)'; end if;
  if v_ic  is null then v_bad := v_bad || ' NO-FUNCTION(incident_contact)'; end if;

  if v_cpv is not null then
    -- ② definer + in-body search_path (98 H1's obligation, checked here so a bad apply fails
    --    loudly rather than waiting for the sweep). 0049 wrote `set search_path = public` and 0055
    --    ALTERed pg_temp in; `create or replace` discards ALTER-applied config, so this arm is
    --    what catches a future edit that drops the in-body clause.
    if (select prosecdef from pg_proc where oid = v_cpv) is distinct from true
      then v_bad := v_bad || ' cpv-not-definer'; end if;
    if (select proconfig::text like '%search_path=public, pg_temp%' from pg_proc where oid = v_cpv)
       is distinct from true
      then v_bad := v_bad || ' cpv-no-in-body-search_path'; end if;
    -- ③ the ACL this file is obliged to set explicitly. anon and authenticated refused;
    --    service_role kept as the POSITIVE control — revoking everybody would satisfy the two
    --    refusal arms perfectly and silently kill the roster.
    if has_function_privilege('anon', v_cpv, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' anon-can-cpv'; end if;
    if has_function_privilege('authenticated', v_cpv, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' authed-can-cpv'; end if;
    if has_function_privilege('service_role', v_cpv, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' service_role-LOST-cpv'; end if;
  end if;

  if v_ic is not null then
    if (select prosecdef from pg_proc where oid = v_ic) is distinct from true
      then v_bad := v_bad || ' ic-not-definer'; end if;
    if (select proconfig::text like '%search_path=public, pg_temp%' from pg_proc where oid = v_ic)
       is distinct from true
      then v_bad := v_bad || ' ic-no-in-body-search_path'; end if;
    if has_function_privilege('anon', v_ic, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' anon-can-incident_contact'; end if;
    -- authenticated MUST keep it (0088:274) — this is the door, and a shut door is not a safe
    -- door, it is a dead one.
    if has_function_privilege('authenticated', v_ic, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' authed-LOST-incident_contact'; end if;
    if has_function_privilege('service_role', v_ic, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' service_role-LOST-incident_contact'; end if;
  end if;

  -- ④ the gate is actually IN the source of both, comments STRIPPED before matching. A comment
  --    explaining the gate matches every grep that hunts for the gate, and the better the comment
  --    the more certainly it matches — this file's §A/§B headers name `phone_collection_live()`
  --    several times, so an unstripped check here would pass on a body that never calls it.
  if v_cpv is not null
     and (select regexp_replace(prosrc, '--[^\n]*', '', 'g') like '%phone_collection_live()%'
            from pg_proc where oid = v_cpv) is distinct from true
    then v_bad := v_bad || ' cpv-does-not-call-the-gate'; end if;
  if v_ic is not null
     and (select regexp_replace(prosrc, '--[^\n]*', '', 'g') like '%phone_collection_live()%'
            from pg_proc where oid = v_ic) is distinct from true
    then v_bad := v_bad || ' ic-does-not-call-the-gate'; end if;

  -- ⑤ the flag itself still ships CLOSED. If this aborts an apply, somebody armed collection in a
  --    migration, which is Sean's act and not a file's (0154 §E ① says the same thing; repeated
  --    here because THIS file is the one that makes the flag govern disclosure).
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' flag-ARMED-at-apply'; end if;

  if v_bad <> '' then raise exception '0167 VERIFY FAILED:%', v_bad; end if;
end $$;
