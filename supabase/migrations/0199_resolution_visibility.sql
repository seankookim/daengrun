-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0199 — the ops adjudication becomes visible to the two people it was about
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 230_resolution_visibility_suite.sql (tag `rvz`) — 0199-V1 · V2 · V3 · V4 · H1 · S1
--
-- ═══ §0a WHY NOW — a decision nobody is told about ════════════════════════════════════════════
-- 0193 §A built the exit for a stranded 1:1 return: `ops_resolve_return_tx` rescues a booking from
-- `active` (one or zero party stamps, run stopped, nothing sealed) or from `incident_review`
-- (0188 arm ⓑ-①'s zero-stamp timeout), seals it, settles it through `_settle_sealed_run`, and
-- writes one row to the `return_resolutions` journal saying who decided, from which state, which
-- party stamps existed at that moment, and what the operator typed.
--
-- The parties see NONE of it. Measured on trunk `cc61132`, before a line of this file was written:
--   · `return_resolutions` is sealed — RLS on, zero policies, `revoke all … from public, anon,
--     authenticated` (0193:155-156), and 224 `0193-S1` pins all three.
--   · `grep -rn return_resolutions app/` → **0 hits**.
-- So from the owner's side the run simply becomes `completed` with a settled money line and no
-- explanation, and the ⑫ gate that was asking them to confirm 반환 — `app/app/owner/report.tsx`
-- renders it only for `rawStatus in ('active','incident_review')` — silently vanishes. The app's
-- last word to that owner was 「반려견을 받으셨나요?」 and its next word is nothing.
--
-- ═══ §0b WHAT THIS FILE DOES, AND THE ONE THING IT REFUSES TO DO ══════════════════════════════
-- §A adds ONE function: `my_return_resolution(p_booking)` — a party-gated, flat, whitelisted read
-- of the latest resolution for one booking.
--
-- 🔴 **THE OPS MEMO NEVER LEAVES THE SERVER.** `return_resolutions.memo` is what an operator typed
--    for an operator — 0193:446 calls the journal 「an adjudication record: a client read is an
--    operator's audit trail」 — and `return_force_reason` on `bookings` carries the same string.
--    A party-facing read that returned it would turn an internal note into product copy that
--    nobody wrote, reviewed or translated, in a screen a customer screenshots. So the return
--    carries a FIXED sentence chosen by `from_status`, and `memo` is not in the returns-table at
--    all — an absence the suite asserts by VALUE (230 `0199-V4`), not by reading the column list.
--
-- ⚠ **WHY THE SERVER PICKS THE SENTENCE RATHER THAN THE CLIENT PICKING IT FROM A KEY.** Both were
--   available and the choice had to be made once, consistently (the slice's own instruction). The
--   server wins for one reason that is specific to this surface: a phone that has not been
--   rebuilt still renders whatever it shipped with, and the set of `from_status` values is the
--   server's vocabulary — 0193 admits exactly `active` and `incident_review` today, and any later
--   state 0193's gate learns to rescue would arrive at an old binary as an unmapped key and render
--   NOTHING. A sentence chosen here is correct on every installed build the day it changes.
--   `rescued_from` is returned ANYWAY and is deliberately NOT display vocabulary: it is the raw
--   server word, for gate logic and for an operator reading a support ticket, and the client is
--   under the standing STATUS_MAP law — gate on `rawStatus`, never print it.
--
-- ⚠ **NOTHING IS DONE ABOUT `bookings.handoff_escalated_at` HERE, AND THAT IS A MEASUREMENT.**
--   The second half of this slice (the meetup strip that says 운영팀에 알렸어요) needed the
--   question answered before any SQL was written: is the parties' booking read a definer whose
--   projection must be widened? It is **not**. `fetchBookingSync` (`app/src/lib/api.ts:1323`) is a
--   plain PostgREST `select … from bookings`, `authenticated` holds table-level SELECT on
--   `bookings` (the shim's default privileges, mirroring production; the only narrowing anywhere
--   is `0111:174`'s `revoke insert`), and `bookings party read` (`0002:92`) scopes it by row. A
--   table-level grant covers columns added later, so 0182 §A's `handoff_cycle_at` and
--   `handoff_escalated_at` are ALREADY readable by a party and already invisible to a stranger,
--   with no server change at all. Adding a `my_handoff_state()` definer would be a second surface
--   over a table that already answers correctly — the same judgement 0192 §0 ① and 0195 §0b made,
--   and for the same reason. What this slice owes instead is a PIN, because the client now
--   depends on that read: 230 `0199-H1` executes it as `authenticated` in both directions.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON ═════════════════════════════════════════════════════════
-- Re-creates NOTHING. `my_return_resolution` is new, first defined here, and sets its own ACL in
-- this file (§B). `return_resolutions` (0193 §A) is READ and is NOT re-granted, NOT given a policy
-- and NOT unsealed — 224 `0193-S1` asserts all three and stays green, which is the point: a
-- definer is how a sealed table answers a party without becoming a client surface.
--
-- ═══ §0d THE ORDER INSIDE THE FUNCTION, written as the property each step owns ════════════════
--   ① subject   — no `auth.uid()` ⇒ `not_authenticated`, before anything is read.
--   ② PARTY GATE — one `exists` over `bookings`; a non-party and a non-existent booking take the
--                  SAME branch and raise the SAME word, so the id is not an existence oracle.
--   ③ the journal read, which is the first statement that touches `return_resolutions`.
--
--   ⚠ ② deliberately does not `select … into` the booking row first. A row read has no observable
--     effect and an inverted body would still refuse — so no fixture could tell the two apart
--     (the limitation 226's battery row (iv) records) — but the ORDER is what stops a future edit
--     slipping a state-dependent branch above the gate. It is held in SOURCE by `0199-S1`.
--
-- ⚠ **ZERO ROWS IS AN ANSWER, NOT A FAILURE.** A booking with no adjudication returns no row and
--   raises nothing: 「운영팀이 개입한 적 없음」 is the ordinary case for every healthy run in the
--   product, and raising there would make the client's `catch` the normal path and teach a screen
--   to treat a real transport failure as 「없음」. Same three-state law as `fetchBookingAddress`
--   (`api.ts`: row / null / throw).
--
-- ⚠ `limit 1`, newest first. `ops_resolve_return_tx` short-circuits on a `completed` row so a
--   second call writes no second journal row today — but the table has no uniqueness constraint
--   on `booking_id` (0193:144-155) and a reader that assumed one would break silently the first
--   time that changed. The index `return_resolutions_booking_idx (booking_id, created_at desc)`
--   is exactly this access path.
--
-- DEPLOY: `supabase db push` only. No edge function is changed, no cron, no table, no enum.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A my_return_resolution — the party's half of the ops journal
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function my_return_resolution(p_booking uuid)
returns table (resolved_at timestamptz, rescued_from text, note_public text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
begin
  -- ① a subject, before anything is read.
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- ② THE PARTY GATE, ahead of every read of the journal. `is not true` rather than a bare `if`,
  --    so a NULL from any cause refuses instead of collapsing into silence (the plpgsql NULL-IF
  --    law). The `exists` shape is what makes a foreign booking and a booking that does not exist
  --    indistinguishable: both are `false`, both raise `not_party`.
  if (select exists (select 1 from bookings b
                      where b.id = p_booking
                        and (b.owner_id = v_uid or b.runner_id = v_uid))) is not true
  then raise exception 'not_party'; end if;

  -- ③ the journal. THREE columns leave this function and `memo` is not one of them — see §0b.
  return query
  select r.created_at,
         r.from_status,
         -- The fixed sentences. `active` is the STRAND (the run stopped, one side or neither
         -- stamped, nothing sealed) and what ops did there is confirm the 귀가; `incident_review`
         -- is 0188 ⓑ-①'s zero-stamp timeout, where what ops did is adjudicate and let the money
         -- move. The `else` is not decoration: 0193's gate admits exactly two states today, and a
         -- third one added later must still produce a true sentence rather than NULL — a NULL
         -- here would render as an empty strip on a screen that already decided to show one.
         case r.from_status
           when 'active'          then '운영팀이 귀가를 확인 처리했어요'
           when 'incident_review' then '운영팀이 검토 후 정산 처리했어요'
           else                        '운영팀이 확인 후 처리했어요'
         end
    from return_resolutions r
   where r.booking_id = p_booking
   order by r.created_at desc
   limit 1;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ACL — written out, never inherited
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `create or replace` preserves an ACL only where the function already exists; on a partial prior
-- apply or a rebuilt environment this statement is a plain CREATE and a new function is born
-- PUBLIC-executable (0116:636). A SECURITY DEFINER over a sealed adjudication journal is the worst
-- shape this repo can produce, so the revoke is the guard and not the tidying.
revoke execute on function my_return_resolution(uuid) from public, anon;
grant  execute on function my_return_resolution(uuid) to authenticated;

comment on function my_return_resolution(uuid) is
  '0199: 좌초된 반환을 운영팀이 해결한 사실을 **당사자에게** 돌려준다. 0193 §A의
return_resolutions 저널은 봉인돼 있고(RLS 켜짐·정책 0개·authenticated 권한 없음) 앞으로도 그렇다 —
이 definer가 유일한 당사자 창구다. 파티 게이트(보호자 또는 러너)가 저널 읽기보다 **먼저** 돌고,
없는 예약과 남의 예약은 똑같이 not_party라 id가 존재 오라클이 되지 않는다. 돌려주는 세 칸은
resolved_at · rescued_from(active | incident_review — 서버 어휘, 표시용 아님) ·
note_public(from_status가 고르는 고정 한국어 문장). 🔴 **운영 메모(memo·return_force_reason)는
절대 나가지 않는다** — 운영자가 운영자에게 쓴 글은 아무도 검수하지 않은 제품 카피가 될 수 없다.
해결 기록이 없으면 0행(예외 아님): 「운영팀이 개입한 적 없음」은 정상 상태다. not_authenticated ·
not_party 두 단어만 발생시킨다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the apply refuses a shape that would be wrong in production
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_oid oid;
  v_src text;
  v_bad text := '';
begin
  select p.oid into v_oid from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'my_return_resolution';
  if v_oid is null then raise exception '0199 VERIFY: NO-FUNCTION(my_return_resolution)'; end if;

  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NOT-SECURITY-DEFINER;'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
        from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH;'; end if;
  if has_function_privilege('anon', v_oid, 'execute') is not false
    then v_bad := v_bad || ' ANON-CAN-EXECUTE;'; end if;
  if has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' AUTHENTICATED-CANNOT-EXECUTE;'; end if;

  -- the source, with COMMENTS STRIPPED: every sentence above names `memo` and every party word,
  -- so an un-stripped match would be satisfied by the prose explaining the guard rather than by
  -- the guard. (CLAUDE.md, the comment-matching law — `prosrc` is source plus our own writing.)
  v_src := regexp_replace((select prosrc from pg_proc where oid = v_oid), '--[^' || chr(10) || ']*', '', 'g');
  if v_src is null or btrim(v_src) = '' then raise exception '0199 VERIFY: NO-SOURCE(my_return_resolution)'; end if;
  if (v_src ~ 'not_party') is not true
    then v_bad := v_bad || ' NO-PARTY-REFUSAL;'; end if;
  -- the gate must PRECEDE the journal read, in this order, in the executable text
  if (position('not_party' in v_src) < position('return_resolutions' in v_src)) is not true
    then v_bad := v_bad || ' PARTY-GATE-NOT-BEFORE-THE-JOURNAL-READ;'; end if;
  if (v_src ~ '\mmemo\M') is not false
    then v_bad := v_bad || ' OPS-MEMO-REFERENCED-IN-THE-BODY;'; end if;
  if (v_src ~ 'return_force_reason') is not false
    then v_bad := v_bad || ' OPS-REASON-REFERENCED-IN-THE-BODY;'; end if;

  -- the journal stays sealed: this file must not have unsealed what 0193 sealed
  if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
    then v_bad := v_bad || ' JOURNAL-RLS-OFF;'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
    then v_bad := v_bad || ' JOURNAL-HAS-A-POLICY;'; end if;
  if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
    then v_bad := v_bad || ' JOURNAL-READABLE-BY-AUTHENTICATED;'; end if;

  if v_bad <> '' then raise exception '0199 VERIFY:%', v_bad; end if;
  raise notice '0199 VERIFY ok — my_return_resolution is a party-gated definer and the journal is still sealed';
end $$;
