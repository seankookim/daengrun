-- ═══ 0171: `_club_phone_visible`'s lifetime arm stops using a bare `<>` on custody phase ═══
--
-- closes codex deploy-gate MEDIUM #6 (`docs/reviews/2026-09-15-deploy-gate-verdict.md`):
--   「`_club_phone_visible` uses `sd.custody_phase <> 'resolved'`, while the scoped client
--    contract declares custody phase nullable. [0167:125-134], [api.ts:4204-4212] … After session
--    closure, a delegated row with NULL phase silently fails the unresolved-custody lifetime arm;
--    use `IS DISTINCT FROM 'resolved'`.」
--
-- The predicate change is correct and lands here. **The premise behind it is not, and saying so is
-- the load-bearing half of this file** — because a later session reading suite 201's green must
-- not conclude that production ever produced a NULL custody phase, and because the same
-- conflation will be made again by the next reviewer who reads the client contract.
--
-- ═══ 🔴 WHAT WAS ACTUALLY MEASURED, AS A LADDER — NOT AS A VERDICT ═══
-- (house law: 「write the rung, not the verdict」. Three rungs, and only two of them are reads.)
--
--   | claim | rung |
--   |---|---|
--   | `session_dogs.custody_phase` is **NOT NULL** | **OBSERVED** on the harness schema built from 0000→0170: `pg_attribute.attnotnull = t`, default `'with_custodian'::text`. Declared at `0040:47` (`add column … text not null default 'with_custodian'`); no later migration drops it — swept `alter column` / `drop not null` across all of `supabase/migrations/*.sql`, zero hits |
--   | no write path can leave it NULL even if the constraint went | **OBSERVED + READ.** `club_v1_axes_sync` is a `BEFORE INSERT OR UPDATE` trigger on `session_dogs` with **`tgenabled = 'O'`** (measured live, not `pg_get_triggerdef` — that renders a DISABLED trigger identically, 0166-era law), and `_club_sync_axes_tg` assigns `new.custody_phase := j->>'custody_phase'` **unconditionally**. Every branch of `_club_compute_axes` emits a non-null literal (`with_custodian` · `outbound_pending` · `transfer_pending` · `return_pending` · `resolved`) — read from the deployed `prosrc`, not from a migration file |
--   | the client contract's `custodyPhase: string | null` (`api.ts:4210`) is a **projection** nullability, not a column nullability | **READ.** It is the board/delegation projection's shape — a dog row with no session_dog, or a payload from a bundle that predates the axis. It says nothing about what the base column can hold |
--
-- **So the NULL state codex describes is unreachable today, by two independent constructions.**
-- This file is therefore **hardening, not a breach fix** — the same category as 0121:240's missing
-- revoke: latent, not live. It is still worth landing, for exactly one reason: the property is
-- held by a NOT NULL and a derivation trigger, and **both are one `alter` away from gone**, at
-- which point the helper would answer `false` — CLOSED — for a delegated dog whose custody is
-- genuinely unresolved. `is distinct from` costs nothing and removes the dependency.
--
-- ⚠ AND THE FIX IS BEHAVIOUR-IDENTICAL ON EVERY ROW THAT EXISTS. `x <> 'resolved'` and
--   `x is distinct from 'resolved'` differ **only** where `x` is NULL. With NOT NULL in force
--   they agree on every row, so nothing in production moves. That is also why suite 201's P1 has
--   to MANUFACTURE the NULL (201's header says exactly how, and says that it is manufactured) —
--   a fixture that started where production starts could not tell the two predicates apart at
--   all, which is this repo's 「a pin whose fixture cannot distinguish two rules is testing the
--   fixture」 law arriving before the pin was written instead of after.
--
-- ═══ THE OTHER BARE COMPARISONS IN THIS BODY — ENUMERATED, AND DELIBERATELY LEFT ALONE ═══
-- The finding's sentence is 「a bare `<>`/`=` on something that can be NULL」, and the cited site is
-- one place that sentence is observable (house law: a finding's SENTENCE is the property). So every
-- comparison in 0167's body was measured for nullability and ruled on individually. **Four of the
-- five must stay bare, and converting them would be a DEFECT, not a tidy-up:**
--
--   · `s.status in ('open','full')`                      — `club_sessions.status` **NOT NULL** (measured).
--                                                          Nothing to convert.
--   · `sd.custody = 'runner_delegated'`                  — `session_dogs.custody` **NOT NULL** (measured,
--                                                          default `'owner_handled'`). Nothing to convert.
--   · `sd.custody_phase <> 'resolved'`                   — **THE ONE THAT CHANGES.** Not because the column
--                                                          is nullable (it is not) but because an UNKNOWN
--                                                          phase must read as UNRESOLVED, i.e. fail OPEN on
--                                                          the lifetime arm and then be closed or opened by
--                                                          규칙 B, rather than fail SHUT silently.
--   · `s.host_profile_id = p_viewer` /
--     `s.backup_host_profile_id = p_viewer`              — `backup_host_profile_id` **IS nullable** (measured)
--                                                          and **must stay `=`**. `is not distinct from` would
--                                                          make a session with NO backup host match a NULL
--                                                          `p_viewer`, i.e. hand 규칙 B's host arm to a caller
--                                                          who named nobody. NULL-excluded is the CORRECT
--                                                          semantics here: an unknown backup host is not you.
--   · `b.runner_id = p_target` / `= p_viewer`            — `bookings.runner_id` **IS nullable** (measured) and
--                                                          must stay `=`, and is already guarded one line
--                                                          above by `b.runner_id is not null` (0049:144).
--                                                          Same argument: an unassigned booking's runner is
--                                                          not you.
--
-- ⚠ The asymmetry is the point and is worth keeping in prose: these are all in a **SQL WHERE
--   clause**, where NULL is simply not-true and the row drops — it is not the plpgsql `IF`-on-NULL
--   collapse this repo has measured five times. So 「NULL excluded」 is sometimes exactly right
--   (a stranger is not a host) and sometimes exactly wrong (an unknown custody phase is not a
--   resolved one). **The question is never 「is this column nullable」; it is 「which way should
--   UNKNOWN fall for THIS proposition」** — and the answers differ inside one expression.
--
-- ═══ SCOPE — one predicate, and what is deliberately NOT here ═══
--   · `incident_contact` (0167 §B) is **NOT touched**. It contains no custody comparison at all.
--   · **0167's flag gate is carried forward BYTE-IDENTICAL**, comment included, and that is
--     deliberate: it is the CRITICAL that file exists for (codex 0154 #3), and a null-safety slice
--     that re-typed it would be asking a reviewer to diff a security gate for no reason. The VERIFY
--     below re-asserts it, comments stripped, so 「carried forward」 is checked and not claimed.
--   · Nothing else in 0167 §A moves. The body below is 0167:126-148 with **exactly three tokens
--     changed** (`<>` → `is distinct from`) on one line, so the diff is one line.
--
-- ⚠ THIS IS A `create or replace` OF A FUNCTION FIRST DEFINED IN ANOTHER FILE (0049, carried by
--   0167), so the explicit ACL below is MANDATORY and is not decoration — on an apply where the
--   function is absent (a partial prior apply, a branch that never ran 0049/0167, a rebuilt
--   environment) this statement is a plain CREATE and the definer is born PUBLIC-executable
--   (0116:636). `check-definer-acl.mjs` refuses exactly this shape in a file that does not set the
--   ACL itself. The revoke below is **0167:154 verbatim, which is 0049:193 verbatim** — cited,
--   not re-derived.
--
-- ⚠ IN-BODY `set search_path = public, pg_temp`, for the reason 0167:85-89 records: ALTER-applied
--   config is discarded by `create or replace`, so writing it in the body is what keeps 98 H1 green.
--
-- ⚠ NO SHIPPED SUITE'S PINNED BEHAVIOUR MOVES IN THIS SLICE, and that is a CONSEQUENCE of the
--   measurement rather than luck: with the column NOT NULL the two predicates agree on every row
--   any existing fixture can build, so 197's P1/P2, 67's H5, 124's G5 and 130's V3 ⓑ all read
--   exactly as before. Suite 201 is new, and its P1 is the only place in the harness where the two
--   predicates are distinguishable at all.

-- ═══ §A `_club_phone_visible` — 0167 §A forward, one predicate null-safe ═══
create or replace function _club_phone_visible(
  p_session uuid, p_viewer uuid, p_target uuid
) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- [0167] THE VISIBILITY GATE. Sean's switch is the only thing that opens a phone number to
  -- anybody, in either direction, on any surface. `is not true` and not `not`: a NULL answer is
  -- CLOSED, and a bare `IF` on NULL is silent in exactly the state this guard exists to notice.
  -- ⚠ [0171] CARRIED FORWARD BYTE-IDENTICAL. This is 0167's CRITICAL and 0171 does not touch it.
  if phone_collection_live() is not true then return false; end if;

  -- Everything below is 0167:126-148 (which is 0049:172-191) unchanged EXCEPT the one marked line.
  return (
  select
    -- 수명 게이트
    (exists (select 1 from club_sessions s where s.id = p_session and s.status in ('open', 'full'))
     or exists (select 1 from session_dogs sd where sd.session_id = p_session
                -- ⚠ [0171] `is distinct from`, not `<>` — codex deploy-gate #6. UNKNOWN phase reads
                -- as UNRESOLVED (the arm stays OPEN and 규칙 B below decides), never as resolved.
                -- 「until custody is resolved」 is the arm's own sentence (0049), and a phase nobody
                -- has recorded is not a custody somebody has resolved. Today the column is NOT NULL
                -- (0040:47) and a BEFORE-trigger derives it, so this is behaviour-identical on every
                -- existing row — see this file's header ladder. It removes the dependency on both.
                and sd.custody = 'runner_delegated' and sd.custody_phase is distinct from 'resolved'
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
-- ACL: 0167:154 verbatim, which is 0049:193 verbatim. Nobody client-facing executes this — it is a
-- helper the roster definer calls as its owner. `service_role` keeps EXECUTE by Supabase's function
-- default privileges (00_shim.sql:135 models production), measured live: proacl
-- {postgres=X/postgres, service_role=X/postgres}. There is nothing to grant back; there IS
-- something to revoke.
revoke execute on function _club_phone_visible(uuid, uuid, uuid) from public, anon, authenticated;

comment on function _club_phone_visible is
  '0049 규칙 B + [0167] 수집 스위치 + [0171] NULL 안전. phone_collection_live() 가 열려 있지 않으면
**무조건 false** (codex 0154 #3). 그 다음이 0049 의 규칙 B: 호스트 ↔ 전원(양방향) · 보호자 ↔ (자기 개의)
수락 러너(양방향), 세션 진행 중이거나 본인 관련 커스터디가 미해소인 동안만.
🔴 [0171] 수명 게이트의 커스터디 조건은 `custody_phase is distinct from ''resolved''` 다 (codex
deploy-gate #6). **기록되지 않은(UNKNOWN) 단계는 「해소됨」이 아니다** — 모르는 값은 미해소로 읽고
규칙 B 가 판단한다. ⚠ 오늘 이 컬럼은 NOT NULL 이고(0040:47) BEFORE 트리거가 값을 파생하므로 실제 행의
동작은 한 줄도 바뀌지 않는다. 바뀌는 것은 그 두 보호막에 대한 의존뿐이다.
⚠ 같은 본문의 나머지 `=` 비교(backup_host_profile_id · runner_id)는 **일부러 bare 로 둔다** — 거기서는
UNKNOWN 이 「아니다」로 떨어지는 것이 옳다 (0171 헤더의 열거).';

-- ═══ §B VERIFY — apply-time, and NOT a substitute for suite 201 ═══
-- Different kinds of evidence and neither is evidence for the other: VERIFY says 「the apply
-- produced this shape」, the suite says 「the property holds and a mutation breaks it」. A property
-- checked only at apply is protected exactly until someone recreates the function (0131-G4).
-- ⚠ EVERY ARM ASSERTS AN EXACT BOOLEAN. `has_function_privilege` can answer NULL and plpgsql does
--   not take an `IF` on NULL, so a bare `IF has_*` arm is SILENT in exactly the state it exists to
--   notice. `to_regprocedure` rather than `::regprocedure` for the same reason: the cast RAISES on
--   an absent function (an opaque death that says nothing about the ACL) while `to_regprocedure`
--   returns NULL, which the NO-FUNCTION arm reports by name.
do $$
declare
  v_bad text := '';
  v_cpv regprocedure := to_regprocedure('_club_phone_visible(uuid,uuid,uuid)');
  v_src text;
begin
  -- ① the function exists at all. Without this every arm below is vacuously green.
  if v_cpv is null then
    raise exception '0171 VERIFY FAILED: NO-FUNCTION(_club_phone_visible)';
  end if;

  -- ② definer + in-body search_path (98 H1's obligation, checked here so a bad apply fails loudly
  --    rather than waiting for the sweep). `create or replace` discards ALTER-applied config, so
  --    this arm is what catches a future edit that drops the in-body clause.
  if (select prosecdef from pg_proc where oid = v_cpv) is distinct from true
    then v_bad := v_bad || ' cpv-not-definer'; end if;
  if (select proconfig::text like '%search_path=public, pg_temp%' from pg_proc where oid = v_cpv)
     is distinct from true
    then v_bad := v_bad || ' cpv-no-in-body-search_path'; end if;

  -- ③ the ACL this file is obliged to set explicitly. anon and authenticated refused; service_role
  --    kept as the POSITIVE control — revoking everybody would satisfy the two refusal arms
  --    perfectly and silently kill the roster.
  if has_function_privilege('anon', v_cpv, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' anon-can-cpv'; end if;
  if has_function_privilege('authenticated', v_cpv, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' authed-can-cpv'; end if;
  if has_function_privilege('service_role', v_cpv, 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' service_role-LOST-cpv'; end if;

  -- ④ 🔴 THE SOURCE ARMS, COMMENTS STRIPPED BEFORE MATCHING — and the stripping is the whole
  --    point, not hygiene. This file's own header and the in-body comment at the changed line both
  --    quote `<> 'resolved'` **in prose, several times**, precisely because the change is being
  --    explained. An unstripped check would therefore pass on a body that still carries the bare
  --    operator, and would pass MOST surely on the best-documented version of the bug. That is
  --    this repo's most-repeated instrument failure (「`prosrc` is source PLUS our own prose, so the
  --    instrument inverts under diligence」) and it is live in this exact file.
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc where oid = v_cpv;
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE(_club_phone_visible)';
  else
    -- ④a the bare operator is GONE. Matches `<> 'resolved'` with or without whitespace.
    if (v_src ~ '<>\s*''resolved''') is distinct from false
      then v_bad := v_bad || ' bare-<>-resolved-STILL-PRESENT'; end if;
    -- ④b and the null-safe one is PRESENT. ④a alone is satisfied by DELETING the conjunct, which
    --    would open the lifetime arm permanently — a strictly worse bug than the one being fixed.
    if (v_src ~ 'custody_phase\s+is\s+distinct\s+from\s+''resolved''') is distinct from true
      then v_bad := v_bad || ' null-safe-conjunct-MISSING'; end if;
    -- ④c 0167's gate is still the first thing the body does. This file carries it forward; an edit
    --    that dropped it while landing the null-safety would reopen codex 0154 #3 (CRITICAL) and
    --    every arm above would stay green.
    if (position('phone_collection_live()' in v_src) > 0
        and position('phone_collection_live()' in v_src) < position('select' in v_src)) is not true
      then v_bad := v_bad || ' 0167-gate-ABSENT-or-NOT-FIRST'; end if;
  end if;

  -- ⑤ the flag itself still ships CLOSED (0167:295, same argument). If this aborts an apply,
  --    somebody armed collection in a migration, which is Sean's act and not a file's.
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' flag-ARMED-at-apply'; end if;

  if v_bad <> '' then raise exception '0171 VERIFY FAILED:%', v_bad; end if;
end $$;
