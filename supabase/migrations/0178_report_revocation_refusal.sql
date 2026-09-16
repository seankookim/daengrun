-- ═══ 0178: report_billing_key_revocation NAMES its refusal — `false` had grown a second cause ═══
--
-- BACKEND HONESTY AUDIT 2026-09-17 **M7**, the server-side instance of the ④ class (CLAUDE.md:
-- 「widening a SQL return's MEANING breaks a correct caller with no edit to the caller」). The
-- function's answer was widened twice without widening its vocabulary:
--   0138  returns void     — the report always applied.
--   0155  returns boolean  — `false` = 「your claim expired and someone else owns this row now」:
--         the compare-and-set on `claim_token` (0141 §C), ONE cause, and
--         `revoke-billing-keys/handler.ts` mapped it to `stale++`. Correct, then.
--   0166  adds `and state = 'processing'` to the WHERE — a terminal row (done / abandoned) or an
--         unclaimed one (pending / failed) now ALSO answers `false`, and so does a row that no
--         longer exists. The handler still reads every `false` as `stale++`, citing 0141 §C: a
--         report refused because the row was already closed is counted as 「lost the lease」, the
--         tick row merges three causes into one number, and no gate sees it because the handler
--         did not change — THE DEFECT IS THE UNCHANGED LINE.
--
-- THE FIX is 0143's `billing_key_swap` shape: `(applied boolean, refusal text)`, the refusal
-- NAMING the cause, read from the row's PRE-IMAGE — locked before the write, so it is the row the
-- UPDATE judged — in a fixed precedence:
--   absent           no row with that id (or a NULL id).
--   not_processing   the row exists but is not out with a worker — done / abandoned / pending /
--                    failed — whatever token was offered. The lease question is moot on a row
--                    nobody holds, so this OUTRANKS lease_lost (209-R4 pins the order).
--   lease_lost       the row IS processing and `p_token` is not its `claim_token` — 0141 §C, the
--                    one meaning `false` ever had; also the pre-0141 token-less call shape against
--                    a held row.
--   (true, NULL)     the report landed: done / pending / abandoned exactly as before; the abandon
--                    note (0155 / 0166) unchanged.
-- Fail-closed by construction: no branch returns `(false, NULL)` or `(true, <token>)` (209-R6
-- ledgers every pair the suite observes), and the handler treats an absent or unknown token —
-- including the OLD boolean shape — as 「could not record」, never as stale.
--
-- ⚠ DROP-then-CREATE (0141:134 / 0143:59 precedent): postgres refuses a return-type change on
--   `create or replace`. The grant goes with the drop and is RESTATED below in full — the
--   check-definer-acl law: the file that (re)creates a definer sets its ACL. The UPDATE is
--   0166's, statement for statement — the WHERE, the CASE, the token clause, the abandon note — so
--   0166's guard (only a processing row can be reported on) stands, and 209-R6 pins that conjunct
--   in the DEPLOYED source, which 0166's VERIFY did only at its own apply time; this file is
--   exactly the 「somebody recreates the function」 event that warning was about.
--
-- 🔴 DEPLOY ORDER FOR THIS SLICE IS THE REVERSE OF 0176's: FUNCTIONS DEPLOY FIRST, THEN `db push`.
--   Measured (cold review, both windows against the real handlers): new handler + old boolean ⇒
--   every report fails CLOSED to `unreported` with an UNREADABLE log line (loud, honest); old
--   handler + this function ⇒ the old `if (applied === false)` tests an ARRAY, never matches, and
--   a REFUSED report is counted as `revoked` (silent, and worse than the bug being fixed). Row
--   state cannot be corrupted either way — it is decided in here, and the cron discards the tick
--   row — but the counters and logs are exactly the surface this slice exists to make honest.
--
-- ⚠ THE OPEN HALF, named rather than implied: the split is durable NOWHERE. `reconcile_billing_key_
--   dispatch_ticks` (0150:218-241) persists only `claimed` from the response body; `stale` was
--   never persisted either. `not_processing` / `absent` / `unreported` live in the function's log
--   and in `net._http_response` (6 h). The response and the logs now separate the causes; the tick
--   TABLE still cannot. A later slice that wants them durable widens that table, not this function.
--
-- ⚠ Named non-observable (cold review #7): a `processing` row whose `claim_token` is NULL answers
--   `lease_lost` to a token-bearing caller. Unreachable — the claimer writes the token in the same
--   statement that sets `processing`, and both abandon sweeps clear the token with the state — so
--   it is recorded, not special-cased. The reachable neighbour, a NULL token offered to that row,
--   APPLIES (0141's pre-0141 call shape), unchanged.
--
-- ═══ CALLERS, enumerated by hand — the ④ obligation ═══
--   · `revoke-billing-keys/handler.ts` — changed in THIS slice: maps each token, counts them
--     apart (`stale` · `not_processing` · `absent`), and fails CLOSED on a missing or unknown
--     token — including the OLD boolean shape — as `unreported` with a log line, so a mixed deploy
--     window (new handler, old function) counts nothing as revoked that it cannot prove.
--   · SQL suites 171 (`perform` — unaffected), 174 L3, 186 A1–A3, 196 F2/F3 read the boolean by
--     value → each site now reads `applied` (the suite-update law; reason at each site). Their
--     properties are unchanged; the token vocabulary is 209's.
--   · No other SQL function calls it (swept: only its own definitions and VERIFY references).
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 209's header and the REGISTRY row, not here.

drop function if exists report_billing_key_revocation(uuid, boolean, text, uuid);
create function report_billing_key_revocation(p_id uuid, p_ok boolean, p_error text,
                                              p_token uuid default null)
returns table (applied boolean, refusal text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_n int;
  v_state text;
  v_row_state text;
begin
  -- [0178] Lock the row FIRST and keep its pre-image: the diagnosis below must name the row AS THE
  -- UPDATE SAW IT. The first draft diagnosed from a second read after the refused write — two
  -- statements, no lock, READ COMMITTED — and the cold review measured 243 of 2,000 state-gate
  -- refusals named `lease_lost` under a concurrent writer: the M7 conflation rebuilt under
  -- concurrency. Under this lock nothing moves between the read and the write. The worker reports
  -- on a row it already holds, so contention is nil (0142:47 / 0176 step 2 shape), and a lock on a
  -- missing row locks nothing, so absence is answered first.
  select r.state into v_row_state from billing_key_revocations r where r.id = p_id for update;
  if not found then
    return query select false, 'absent'::text;
    return;
  end if;

  -- 0166's statement, unchanged: only a processing row, only with the holder's token.
  update billing_key_revocations
     set state = case when p_ok then 'done'
                      when attempts >= 8 then 'abandoned'
                      else 'pending' end,
         claim_token = null,
         lease_until = null,
         last_error = case when p_ok then null else p_error end,
         updated_at = now()
   where id = p_id
     -- [0166] party gate FIRST: only a row that is out with a worker can be reported on. A
     -- terminal row holds no claim, so nobody may close it a second time.
     and state = 'processing'
     -- p_token null is accepted ONLY for a row nobody holds, so the pre-0141 call shape cannot
     -- silently stomp a live lease during the deploy window.
     and (claim_token = p_token or (p_token is null and claim_token is null))
  returning state into v_state;
  get diagnostics v_n = row_count;

  if v_n = 1 then
    -- THE give-up: eight non-2xx answers from Toss (0155-A1; A2/A3 are the controls). Unchanged.
    if v_state is not distinct from 'abandoned' then
      perform _note_revocation_abandoned(array[p_id]);
    end if;
    return query select true, null::text;
    return;
  end if;

  -- [0178] Refused, and the locked pre-image says why: a row nobody holds outranks the lease
  -- question (there is no lease to lose); otherwise the token did not match. Every branch names
  -- exactly one token — there is no (false, NULL).
  if v_row_state is distinct from 'processing' then
    return query select false, 'not_processing'::text;
    return;
  end if;
  return query select false, 'lease_lost'::text;
end $$;

revoke execute on function report_billing_key_revocation(uuid, boolean, text, uuid)
  from public, anon, authenticated;
grant  execute on function report_billing_key_revocation(uuid, boolean, text, uuid) to service_role;

comment on function report_billing_key_revocation(uuid, boolean, text, uuid) is
  '0178 (audit M7): the worker''s report, compare-and-set on claim_token, only on a processing row. Returns (applied, refusal): applied=true → done/pending/abandoned as before; applied=false names WHY — absent · not_processing · lease_lost, in that precedence — so the handler stops counting every refusal as a lost lease. service_role only.';

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 209 ═══
-- Every arm is `is distinct from`, never a bare IF: a NULL answer must fail, not fall silent.
do $$
declare
  v_oid oid;
  v_n int;
  v_res text;
  v_src text;
  v_acl text;
  v_bad text := '';
begin
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'report_billing_key_revocation';
  -- exactly ONE overload: a surviving boolean-returning sibling would be the ④ class with a new face
  if v_n is distinct from 1 then
    raise exception '0178 VERIFY FAILED: OVERLOADS(%) — expected exactly one report_billing_key_revocation', v_n;
  end if;
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'report_billing_key_revocation'
     and pg_get_function_identity_arguments(p.oid) = 'p_id uuid, p_ok boolean, p_error text, p_token uuid';
  if v_oid is null then
    raise exception '0178 VERIFY FAILED: NO-FUNCTION(report_billing_key_revocation(uuid, boolean, text, uuid))';
  end if;

  select pg_get_function_result(v_oid) into v_res;
  if (v_res = 'TABLE(applied boolean, refusal text)') is distinct from true
    then v_bad := v_bad || ' RESULT-SHAPE(' || coalesce(v_res, 'NULL') || ')'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
        from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;

  -- ACL by value: the drop took the grants with it, so this is a CREATE and 0116:636's default
  -- (PUBLIC EXECUTE) is what a missing revoke would leave behind.
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-is-default)'; end if;
  select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
  if (coalesce(v_acl, '') ~ '(^|,)=[^/]*X') is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-entry)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' service_role-CANNOT-EXECUTE'; end if;

  -- Source, comments STRIPPED first (the comment-matching law: this file's own prose names every
  -- token and the conjunct it carries forward, so un-stripped text would satisfy every arm).
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = v_oid;
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE';
  else
    if (v_src ~ 'and\s+state\s*=\s*''processing''') is distinct from true
      then v_bad := v_bad || ' 0166-PROCESSING-CONJUNCT-MISSING'; end if;
    -- the lock is the precondition of the diagnosis (cold review #1): it must exist and precede the write
    if (position('for update' in v_src) > 0
        and position('for update' in v_src) < position('update billing_key_revocations' in v_src)) is distinct from true
      then v_bad := v_bad || ' LOCK-NOT-BEFORE-WRITE'; end if;
    if (v_src ~ '''absent''' and v_src ~ '''not_processing''' and v_src ~ '''lease_lost''') is distinct from true
      then v_bad := v_bad || ' TOKENS-MISSING'; end if;
    if (v_src ~* 'exception\s+when\s+others') is distinct from false
      then v_bad := v_bad || ' SWALLOWING-HANDLER'; end if;
  end if;

  if v_bad <> '' then
    raise exception '0178 VERIFY FAILED:%', v_bad;
  end if;
end $$;
