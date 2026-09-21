-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0200 — 「어떻게 들어왔는지」: the runner learns HOW they were paid, and only that
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 231_payout_method_label_suite.sql (tag `pml`) — 0200-P1 · P2 · P3 · P4 · S1
--
-- ═══ §0a WHY NOW — a 지급 내역 row that cannot say how the money arrived ═══════════════════════
-- 0186 §A gave `payouts` the three facts a MANUAL transfer has and an automated one would not:
-- `method` (how it moved), `memo` (what the operator wrote down) and `recorded_by` (who typed
-- it) — and in the same breath it SEALED all three away from the runner, because the memo is an
-- operator's note to other operators (0186:156-169 · the column grant at 0186:192-195, pinned
-- from the runner's side by 223 `0192-R4`). 0192 then built the runner's 지급 내역 list as a plain
-- table read over that grant, which was the right call and remains one.
--
-- The consequence, measured on trunk `92b0329` before a line of this file was written:
--   · `app/src/lib/api.ts:3510` `fetchMyPayouts` selects `id, net, paid_at, period_start,
--     period_end, status` — six columns, and `method` is not among them because it CANNOT be:
--     `authenticated` has no grant on it.
--   · so `runner/earnings.tsx`'s 지급 내역 row is a state word, a period and a number. A runner
--     who was paid by a person at a bank sees 「지급 완료 · 2026년 9월 22일」 and nothing about
--     where to look for it.
-- That is not a lie — it is a true row with a fact missing, and the fact is one the runner needs
-- precisely because the pilot's payouts are hand-made bank transfers (0186 §0a).
--
-- ═══ §0b WHAT THIS FILE DOES, AND THE TWO THINGS IT REFUSES TO DO ═════════════════════════════
-- §A adds ONE function: `my_payout_method_labels(p_payout_ids uuid[])` — a party-scoped read that
-- answers, for the caller's OWN payout rows, with a FIXED Korean label chosen from `method`.
--
-- 🔴 **THE OPS MEMO NEVER LEAVES THE SERVER, AND NEITHER DOES `method` ITSELF.** The memo is a
--    bank reference number an operator typed for an operator (0186:171-174 says the server does
--    not even interpret it); putting it on a 지급 내역 row would turn an internal note into
--    product copy nobody wrote, reviewed or translated, on a money screen a runner screenshots.
--    The raw `method` token is not returned either — it is server vocabulary (`manual` today,
--    deliberately unconstrained so that growing it is not a migration, 0186:172-174), and the
--    standing STATUS_MAP law is that a raw token never reaches a Korean screen. What comes back
--    is a LABEL and nothing else. 231 `0200-P3` asserts the memo's absence BY VALUE against a
--    sentinel written through the real door, and `0200-S1` asserts the column names.
--
-- ⚠ **WHY THE SERVER PICKS THE LABEL RATHER THAN THE CLIENT PICKING IT FROM A KEY.** Identical to
--   0199 §0b's reasoning and settled the same way for the same surface: a phone that has not been
--   rebuilt renders whatever it shipped with, and the set of `method` values is the SERVER's
--   vocabulary. The day a PG auto-payout writes a new token, an old binary handed that token would
--   map nothing and draw nothing; a label chosen here is correct on every installed build the day
--   it changes. Returning the token AND a label would re-create the problem it avoids.
--
-- ⚠ **AND WHY NOT SIMPLY GRANT `method`.** Because the grant is the seal. 0186:192-195 revoked
--   `select` on `payouts` and re-granted exactly ten columns; 0192 §0 ① declined to add a
--   `my_payouts()` definer for precisely the reason that a second surface's column list can drift
--   from that seal without anyone touching 0186. Widening the grant by one column would put
--   `method` on the same PostgREST read as `memo`'s neighbours and make the next widening a
--   one-word diff. A definer that returns a LABEL can never widen into the memo: there is no
--   column list to grow, only a `case`.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON ═════════════════════════════════════════════════════════
-- Re-creates NOTHING. `my_payout_method_labels` is new, first defined here, and sets its own ACL
-- in this file (§B). `payouts` is READ and is NOT re-granted, NOT given a new policy and NOT
-- widened by one column — 223 `0192-R4` and 217 `0186-S1` pin that seal from both sides and stay
-- green, which is the point: a definer is how a partly sealed table answers its own owner without
-- becoming a wider client surface. `ops_record_manual_payout` (0186 §C) is untouched.
--
-- ═══ §0d THE ORDER INSIDE THE FUNCTION, written as the property each step owns ════════════════
--   ① subject      — no `auth.uid()` ⇒ `not_authenticated`, before anything is read.
--   ② arguments    — distinct, null-stripped, bounded. Nothing is read yet; an empty ask is zero
--                    rows and NOT an error (「아무것도 묻지 않았다」 is not a failure).
--   ③ THE ONE READ — the only statement in this body that names `payouts`, and its FIRST conjunct
--                    is `p.runner_id = v_uid`. There is no reachable read of anyone else's row.
--
--   ⚠ **THE PARTY GATE HERE IS THE ROW SCOPE, AND THAT IS A DIFFERENT SHAPE FROM 0199's.** 0199
--     could gate ahead of the read because the question was about ONE booking; this question is
--     about a SET, so 「refuse if any id is not mine」 would be strictly worse: it would turn one
--     stale id in a client's list into a refusal that hides the labels of every legitimate row
--     beside it, and — the part that matters — the refusal itself would announce 「one of these
--     ids exists and is not yours」, which is the oracle this function must not be. Instead a
--     stranger's id and a uuid no payout has produce the SAME answer: absence. 231 `0200-P2`
--     measures the two together for exactly that reason, and `0200-S1` holds the scope in SOURCE
--     so a later edit cannot slip a second, unscoped read of `payouts` in beside it.
--
-- ⚠ **ZERO ROWS IS AN ANSWER, NOT A FAILURE**, for the empty array, for a stranger's ids and for
--   ids that do not exist. Same three-state law as `fetchMyReturnResolution` (0199) and
--   `fetchBookingAddress`: rows / nothing / throw, and a client that met a throw on 「없음」 would
--   make its `catch` the normal path.
--
-- ⚠ **AN UNKNOWN METHOD RETURNS THE ROW WITH A NULL LABEL, NOT A GUESSED WORD.** The `case` has
--   no `else` that invents a sentence: a token this file does not know produces NULL, the client
--   omits the element, and the row keeps saying exactly what it can prove. A future PG payout
--   adds its arm here in its own slice with its own pin — never a `?? method` fallback, which is
--   how `CHARGE_LABEL` once printed the English words 'none' and 'hold' as chips in a Korean UI.
--   `manual` is the only value any writer produces today (0186:367); `bank` is admitted beside it
--   because the vocabulary is deliberately unconstrained and a hand-written ops row is the one
--   other way a real bank transfer reaches this table.
--
-- DEPLOY: `supabase db push` only. No edge function is changed, no cron, no table, no enum, no
-- grant. One new function.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A my_payout_method_labels — the runner's half of `payouts.method`, as a label and never a token
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function my_payout_method_labels(p_payout_ids uuid[])
returns table (payout_id uuid, method_label text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_ids uuid[];
  v_n   int;
begin
  -- ① a subject, before anything is read.
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- ② the argument. Distinct + null-stripped (naming the same row twice is a caller's duplicate,
  --    not two answers), and BOUNDED: a definer should do bounded work per call, and the shipped
  --    caller asks about at most the 50 rows `fetchMyPayouts` reads. Nothing has been read here.
  select array_agg(distinct x) into v_ids
    from unnest(coalesce(p_payout_ids, '{}'::uuid[])) x where x is not null;
  v_n := coalesce(array_length(v_ids, 1), 0);
  if v_n = 0 then return; end if;          -- an empty ask is zero rows, never an error
  if v_n > 200 then raise exception 'too_many_ids'; end if;

  -- ③ THE ONE READ. `p.runner_id = v_uid` is the row scope and it is the FIRST conjunct: a row
  --    that is not the caller's is not reachable through this function at all, so a stranger's id
  --    and a uuid no payout has are indistinguishable — both are simply absent. The id is not an
  --    existence oracle.
  --    🔴 `p.memo`, `p.recorded_by` and the raw `p.method` are NOT selected, and this comment is
  --    the only place in this body those words appear. What leaves is a fixed label.
  return query
  select p.id,
         case p.method
           when 'manual' then '계좌 이체'::text
           when 'bank'   then '계좌 이체'::text
           else null::text
         end
    from payouts p
   where p.runner_id = v_uid
     and p.id = any(v_ids);
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ACL — written out, never inherited
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `create or replace` preserves an ACL only where the function already exists; on a partial prior
-- apply or a rebuilt environment this statement is a plain CREATE and a new function is born
-- PUBLIC-executable (0116:636). A SECURITY DEFINER that reads a money table must never be born
-- that way, so the revoke is the guard and not the tidying.
revoke execute on function my_payout_method_labels(uuid[]) from public, anon;
grant  execute on function my_payout_method_labels(uuid[]) to authenticated;

comment on function my_payout_method_labels(uuid[]) is
  '0200: 러너 자신의 payouts 행이 **어떻게** 들어왔는지를 고정 한국어 라벨로 돌려준다. 0186:192-195가
method·memo·recorded_by를 authenticated에게서 회수했고 그 봉인은 그대로다 — 이 definer는 열을 넓히는
대신 `case`로 라벨만 만든다(넓힐 열 목록이 없으므로 메모 쪽으로 자랄 수 없다). 행 범위는
runner_id = auth.uid()이고 그게 이 함수의 유일한 읽기의 첫 조건절이다: 남의 id와 존재하지 않는 id는
똑같이 **부재**라서 id가 존재 오라클이 되지 않는다(집합을 묻는 질문이라 0199처럼 「하나라도 남의 것이면
거절」로 쓰면 거절 자체가 존재를 알려 준다). 🔴 **운영 메모(memo)와 raw method 토큰은 나가지 않는다** —
운영자가 운영자에게 쓴 참조번호는 아무도 검수하지 않은 제품 카피가 될 수 없고, 원어 토큰은 한국어 화면에
찍지 않는다(STATUS_MAP 법). 모르는 method는 라벨 NULL이고 클라이언트는 요소를 뺀다 — 추측한 낱말을
쓰지 않는다. 빈 배열·남의 id·없는 id는 0행(예외 아님). not_authenticated · too_many_ids 두 단어만
발생시킨다. 231 0200-P1~P4·S1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the apply refuses a shape that would be wrong in production
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_oid oid;
  v_src text;
  v_raw text;
  v_bad text := '';
begin
  select p.oid into v_oid from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'my_payout_method_labels';
  -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
  if v_oid is null then raise exception '0200 VERIFY: NO-FUNCTION(my_payout_method_labels)'; end if;

  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NOT-SECURITY-DEFINER;'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
        from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH;'; end if;
  -- the NULL-ACL arm FIRST: `aclexplode(NULL)` returns zero rows, so an `exists` test alone is
  -- silent on exactly the state a fresh CREATE produces (0116:636).
  if (select proacl from pg_proc where oid = v_oid) is null
    then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL;'; end if;
  if has_function_privilege('anon', v_oid, 'execute') is not false
    then v_bad := v_bad || ' ANON-CAN-EXECUTE;'; end if;
  if has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' AUTHENTICATED-CANNOT-EXECUTE;'; end if;

  -- the source, with COMMENTS STRIPPED: the prose above names `memo`, `recorded_by` and every
  -- refusal word, so an un-stripped match would be satisfied by the writing that EXPLAINS the
  -- guard rather than by the guard. (CLAUDE.md, the comment-matching law.)
  v_raw := (select prosrc from pg_proc where oid = v_oid);
  if v_raw is null or btrim(v_raw) = '' then raise exception '0200 VERIFY: NO-SOURCE(my_payout_method_labels)'; end if;
  v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');

  if (v_src ~ 'not_authenticated') is not true
    then v_bad := v_bad || ' NO-SUBJECT-REFUSAL;'; end if;
  -- the row scope, and it must be the ONLY read of the table
  if (v_src ~ 'runner_id\s*=\s*v_uid') is not true
    then v_bad := v_bad || ' NO-RUNNER-SCOPE;'; end if;
  if (select count(*) from regexp_matches(v_src, '\mpayouts\M', 'g')) is distinct from 1
    then v_bad := v_bad || ' PAYOUTS-READ-MORE-THAN-ONCE;'; end if;
  -- the ops half, by word, in the EXECUTABLE text
  if (v_src ~ '\mmemo\M') is not false
    then v_bad := v_bad || ' OPS-MEMO-REFERENCED-IN-THE-BODY;'; end if;
  if (v_src ~ '\mrecorded_by\M') is not false
    then v_bad := v_bad || ' OPS-RECORDER-REFERENCED-IN-THE-BODY;'; end if;
  -- the crude/stripped CONTROL: the raw source really does contain the word, so a stripper that
  -- silently did nothing would make the two arms above pass for the wrong reason.
  if (v_raw ~ '\mmemo\M') is not true
    then v_bad := v_bad || ' CONTROL-RAW-SOURCE-NEVER-SAID-MEMO(the strip arms prove nothing);'; end if;

  -- 0186's column seal is not this file's to move, and a file that widened it would still pass
  -- every arm above.
  if has_column_privilege('authenticated', 'public.payouts', 'method', 'select') is not false
    then v_bad := v_bad || ' PAYOUTS-METHOD-GRANTED-TO-AUTHENTICATED;'; end if;
  if has_column_privilege('authenticated', 'public.payouts', 'memo', 'select') is not false
    then v_bad := v_bad || ' PAYOUTS-MEMO-GRANTED-TO-AUTHENTICATED;'; end if;
  if has_column_privilege('authenticated', 'public.payouts', 'net', 'select') is not true
    then v_bad := v_bad || ' CONTROL-PAYOUTS-NET-NOT-READABLE(0186 grant is gone, not narrowed);'; end if;

  if v_bad <> '' then raise exception '0200 VERIFY:%', v_bad; end if;
  raise notice '0200 VERIFY ok — my_payout_method_labels is a runner-scoped definer and 0186''s column seal is intact';
end $$;
