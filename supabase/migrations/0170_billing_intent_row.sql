-- ═══ 0170: a billing-key issuance is NAMED before Toss is called ═══════════════════════════════
--
-- Closes the LOCAL half of codex billing findings **3** and **4**
-- (`docs/reviews/2026-08-28-codex-billing-chain.md:35-36`), and nothing else. It is the
-- branch-independent core of the Toss provider memo
-- (`docs/research/2026-08-31-toss-provider-memo.md` §4, "Design-now core (correct under EVERY
-- branch)") — the part the backend may build BEFORE the two provider questions in §3 are answered,
-- because it is the same move under every possible answer.
--
-- 🔴 **THE FINDING, IN ITS OWN WORDS.** 「Issuance has no durable record before Toss is called — a
--    lost response leaves a live provider credential in neither `billing_keys` nor the queue.」
--    Today `register-billing-key/handler.ts` calls `tossBillingIssue` with everything before it a
--    READ, and the issuance `Idempotency-Key` is a per-attempt `crypto.randomUUID()` minted inside
--    `_shared/toss.ts` and persisted NOWHERE — it dies with the isolate. If the response never
--    comes back (timeout, isolate recycle, network), Toss may hold a live standing authority to
--    charge somebody's card and we hold no row that names it, in any table, for ever.
--
-- 🔴 **WHY THIS IS SAFE TO BUILD WITH THE PROVIDER QUESTIONS STILL OPEN** (memo §4, core #1). Under
--    every branch of 「can Toss replay or look up an issuance by a persisted idempotency key?」 the
--    FIRST move is identical: mint the key server-side, write an intent row before the call, fail
--    closed if that write fails, and send the PERSISTED key. Under branch A (replay works) the row
--    is what a recovery re-POST replays. Under branch B (a lookup API exists) the row is what the
--    lookup is keyed on. Under branch C (neither) the row IS the durable record the finding
--    demands — it converts 「in neither table nor queue」 into 「named by an unresolved intent」, with
--    `customer_key` as the coordinate a provider-side reconciliation must use
--    (`handler.ts:163-174` already says so about the last-resort confession log).
--
-- ⚠ **WHAT THIS FILE DELIBERATELY DOES NOT BUILD, so nobody reads its absence as an oversight:**
--   · **the recovery sweep's RESOLUTION arm** (re-POST vs query vs escalate). That is the ONE thing
--     the memo says waits on E3/U2 (§4, 「Backend can start now」), and guessing it is exactly what
--     the review forbids (`review:127-131`). The intent row is the sweep's input; the sweep is a
--     later slice that starts when the provider answer lands.
--   · **409 `IDEMPOTENT_REQUEST_PROCESSING` handling** (memo §2a claim 10, core #4). It is a state
--     the handler cannot reach — a key is sent exactly once per attempt and the attempt nonce is
--     single-use — so it belongs to the sweep that re-sends, and a pin here could not redden.
--   · **anything in `billing_key_swap`.** Its semantics are untouched by this file; the intent is
--     closed by a SECOND call after the swap returns, never inside it. See §D for the window that
--     buys and why it is the right trade.
--   · **the edge-affinity question** (`review:132-134`). The attempt nonce stays ISOLATE-LOCAL
--     memory and `consumeNonce` is still the belt; this table merely uses the nonce's VALUE as the
--     attempt's NAME. A row here is written only AFTER that in-memory check has already passed, so
--     it neither makes the nonce durable nor closes that question.
--
-- ⚠ **LATENT.** `ops_flags.card_registration_live_since` is NULL and there are 0 billing keys, so
--   nothing here fires today. It arms with the registration flag — which is precisely the flag the
--   review says findings 3 and 4 must close BEFORE (`review:142-146`).


-- ═══ §A the intent row ════════════════════════════════════════════════════════════════════════
--
-- One row per ISSUANCE ATTEMPT, written before the Toss call and closed with the outcome after it.
--
-- THE STATE MACHINE — one open state, four terminal ones, and no edge back:
--   issuing            → written before the Toss call. The only non-terminal state.
--   issued_persisted   → Toss issued AND `billing_key_swap` stored it. Nothing is owed.
--   issued_unpersisted → Toss issued and our store did not take it. A LIVE credential exists; the
--                        revocation outbox owns destroying it and this row names the key and the
--                        idempotency key it was issued under.
--   provider_error     → Toss answered with a refusal. No key exists.
--   unresolved         → 🔴 THE FINDING'S OWN STATE. No answer reached us (throw/timeout), or a 2xx
--                        carrying no `billingKey`. We do not know whether a credential exists. This
--                        is the state the recovery sweep is for, and the reason the row is written
--                        BEFORE the call rather than after it.
create table if not exists billing_issue_intents (
  id               uuid primary key default gen_random_uuid(),
  -- `on delete set null`, NOT cascade — 0138:37's argument, unchanged: the obligation to find out
  -- what happened to a credential OUTLIVES the account, and an intent belonging to a deleted
  -- profile is the case that most needs resolving. `customer_key` below is what Toss knows this
  -- owner by, and it is kept as a plain text copy for exactly that reason.
  profile_id       uuid references profiles(id) on delete set null,
  -- The attempt's NAME. This is the value `register-billing-key` minted at `prepare` and consumed
  -- at `issue`; it is not a credential and it is not an auth belt here (the in-memory single-use
  -- check is, and it runs first). One intent per attempt is enforced by the UNIQUE below, and that
  -- constraint — not the function's politeness — is what makes a retried open return the SAME key.
  attempt_nonce    text not null unique,
  -- The coordinate Toss knows this owner by (0076 §B). Denormalised on purpose: a provider-side
  -- reconciliation needs it after the profile may be gone.
  customer_key     text not null,
  -- 🔴 THE SERVER-MINTED IDEMPOTENCY KEY — the whole point of the row. UUID-shaped and ≤300 chars
  --    per the docs (memo §2a claim 11), UNIQUE across intents because Toss's documented dedupe
  --    tuple is (key, API key, URL, method) and OMITS THE BODY (claim 8): two intents sharing a key
  --    would let one attempt's cached response come back for the other, and Toss would not catch it.
  idempotency_key  text not null unique
                     check (length(idempotency_key) between 1 and 300),
  state            text not null default 'issuing'
                     check (state in ('issuing', 'issued_persisted', 'issued_unpersisted',
                                      'provider_error', 'unresolved')),
  billing_key      text,
  note             text,
  -- PROVISIONAL (memo §3 U1) — 15 days is DOCUMENTED (memo §2a claim 5: a key is valid 15 days from
  -- first use) but whether retain-and-replay covers `POST /v1/billing/authorizations/issue` AT ALL
  -- is the unmeasured half of Q1, and experiment E3 has not been run. So this column is a recorded
  -- DEADLINE and nothing in this file branches on it: it exists so the sweep, when its resolution
  -- arm is finally written, has the number it must not re-derive, and so an intent still open near
  -- the deadline can be escalated rather than re-POSTed (memo §4 core #3 — past expiry a re-POST is
  -- a FRESH EXECUTION, and whether that refuses or issues is exactly what must not be guessed).
  replay_deadline  timestamptz not null default now() + interval '15 days',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  closed_at        timestamptz,
  -- The state machine, as constraints rather than as prose. ⚠ `closed_at` is what makes 「open」 and
  -- 「terminal」 impossible to disagree about; a row that says `issuing` with a close stamp is a bug
  -- in whoever wrote it, and it fails at the write instead of being discovered by a sweep.
  constraint billing_issue_intents_open_iff_unstamped
    check ((state = 'issuing') = (closed_at is null)),
  -- A provider refusal means NO credential exists. Recording a key on it would invent one.
  constraint billing_issue_intents_error_has_no_key
    check (state <> 'provider_error' or billing_key is null),
  -- Both 「issued」 outcomes know the key by definition — they are only reachable from a response
  -- that carried one. A row claiming issuance without naming the key is worse than no row: it says
  -- a credential exists and refuses to say which.
  constraint billing_issue_intents_issued_names_the_key
    check (state not in ('issued_persisted', 'issued_unpersisted') or billing_key is not null)
);

-- The sweep's future index: the open intents, oldest first. Partial, because `issuing` is the only
-- state anything has to DO something about and terminal rows are history.
create index if not exists billing_issue_intents_open_idx
  on billing_issue_intents (created_at) where state = 'issuing';

-- ═══ §B the seal — RLS on, zero policies, AND no client grant (the 0161 pattern) ══════════════
--
-- ⚠ TWO WALLS, NOT ONE, AND THE SECOND IS THE POINT OF WRITING BOTH LINES. Supabase ships
--   `alter default privileges in schema public grant all on tables to anon, authenticated`, so a
--   table created in `public` is BORN with client DML privileges and RLS is the only thing in front
--   of it. `billing_keys` shipped that way from 0080 to 0161 and the review called the asymmetry out
--   (`review:` OQ2). This table is more sensitive than `billing_keys`, not less — it names live
--   credentials AND the idempotency keys they were issued under, which is the pair a replay needs —
--   so it gets both walls on its first line of life rather than three years later.
alter table billing_issue_intents enable row level security;
revoke all on table billing_issue_intents from anon, authenticated;

comment on table billing_issue_intents is
  '0170 (codex billing #3/#4, Toss provider memo §4 core): one row per billing-key ISSUANCE
ATTEMPT, written BEFORE Toss is called and carrying the server-minted Idempotency-Key that call is
sent under. Before this table a lost response left a live charging credential named in no table at
all; now it is named by an `unresolved` intent. SEALED — RLS on, zero policies, and no client-role
grant (0161''s pattern, applied on day one). Written only by `billing_issue_intent_open` /
`billing_issue_intent_close`, both service_role-only definers. The RESOLUTION of an `unresolved`
intent is deliberately NOT built here: it depends on the two Toss questions in memo §3.';

comment on column billing_issue_intents.idempotency_key is
  '0170: server-minted, UUID-shaped, ≤300 chars (memo §2a claim 11), and UNIQUE across intents
because Toss''s documented dedupe tuple omits the request BODY (claim 8) — two intents sharing a key
would let one attempt''s cached response be returned for the other, with nothing at Toss to catch it.';

comment on column billing_issue_intents.state is
  '0170: issuing (the only open state, written before the Toss call) → issued_persisted (Toss issued
and billing_key_swap stored it) · issued_unpersisted (Toss issued, our store refused or failed — a
live key the revocation outbox owns) · provider_error (Toss refused; no key exists) · unresolved (no
answer reached us, or a 2xx with no billingKey — we do not know whether a credential exists). No edge
returns to `issuing`.';


-- ═══ §C billing_issue_intent_open — called BEFORE the Toss request ════════════════════════════
--
-- Party gate, then state gate, then the write. Returns the key the caller MUST send as
-- `Idempotency-Key`, and a `refusal` naming why when it returns none.
--
-- ⚠ **A RETRIED OPEN FOR THE SAME ATTEMPT RETURNS THE SAME KEY** (memo §4 core #2). A second key for
--   one attempt would make a recovery re-POST a FRESH execution instead of a replay — the exact move
--   the memo forbids without E3 — so the key belongs to the attempt, not to the call.
--
-- ⚠ **A TERMINAL INTENT NEVER REOPENS.** Handing back a closed intent's key would let a spent
--   attempt be replayed at Toss under a key whose outcome we have already recorded, and (under the
--   replay branch) return that recorded outcome as if it were fresh.
--
-- ⚠ THE GATE READ HERE IS A SECOND BELT, NOT THE GATE. `billing_key_swap` (0166 §G) reads
--   `card_registration_live()` under a `for update` on `ops_flags` and that remains the
--   authoritative decision; this one is unlocked on purpose, because locking the singleton flag row
--   on every open would serialise every registration attempt against every swap for no correctness
--   gain. What it buys is that no intent — and therefore no Toss call — is ever STARTED while the
--   gate is shut, which is strictly cheaper than refusing after a credential already exists.
create or replace function billing_issue_intent_open(
  p_profile      uuid,
  p_nonce        text,
  p_customer_key text
)
returns table (intent_id uuid, idempotency_key text, reopened boolean, refusal text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_alive boolean; v_id uuid; v_key text; v_state text;
begin
  -- Caller bugs are LOUD, never a row the sweep can never resolve. Same posture as
  -- `enqueue_billing_key_revocation_row`'s empty-key raise (0157 §B.1): a blank attempt name or a
  -- blank customer key would produce an intent nothing could ever be reconciled against.
  if p_nonce is null or btrim(p_nonce) = '' then
    raise exception '0170: billing_issue_intent_open called with no attempt nonce';
  end if;
  if p_customer_key is null or btrim(p_customer_key) = '' then
    raise exception '0170: billing_issue_intent_open called with no customer key';
  end if;

  -- ── PARTY GATE (first, and before the state gate on purpose: a tombstoned account must get the
  --    same answer whether or not Sean has opened registration — the rollout state is not a fact
  --    that account is entitled to learn, and 「deleted」 is the stronger refusal).
  --    `for update` serialises against `delete_my_account_tx`, which updates this same row, so an
  --    account tombstoned while the handler was between its own profile read and this call is seen
  --    here rather than after Toss has issued a credential. Absent and tombstoned are the SAME
  --    answer, 0137's argument unchanged.
  select (deleted_at is null) into v_alive from profiles where id = p_profile for update;
  if coalesce(v_alive, false) is distinct from true then
    return query select null::uuid, null::text, false, 'deleted_account'::text;
    return;
  end if;

  -- ── STATE GATE
  if card_registration_live() is distinct from true then
    return query select null::uuid, null::text, false, 'gate_closed'::text;
    return;
  end if;

  select i.id, i.idempotency_key, i.state into v_id, v_key, v_state
    from billing_issue_intents i where i.attempt_nonce = p_nonce for update;

  if found then
    if v_state is distinct from 'issuing' then
      return query select null::uuid, null::text, false, 'intent_closed'::text;
      return;
    end if;
    update billing_issue_intents set updated_at = now() where id = v_id;
    return query select v_id, v_key, true, null::text;
    return;
  end if;

  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (p_profile, p_nonce, p_customer_key, gen_random_uuid()::text)
    returning id, billing_issue_intents.idempotency_key into v_id, v_key;
  exception when unique_violation then
    -- Two opens for one attempt raced and the other won. The UNIQUE on `attempt_nonce` is what
    -- makes that a caught collision instead of a second key for the same attempt — re-read and
    -- return THEIRS, because the key that must be sent is the one that exists.
    select i.id, i.idempotency_key, i.state into v_id, v_key, v_state
      from billing_issue_intents i where i.attempt_nonce = p_nonce;
    -- ⚠ Not every unique violation is the nonce. A collision on `idempotency_key` (two intents, one
    --   key) is the one thing this table exists to make impossible, and swallowing it here as
    --   「somebody else opened your attempt」 would hide it behind a plausible refusal. Re-raise.
    if v_id is null then raise; end if;
    if v_state is distinct from 'issuing' then
      return query select null::uuid, null::text, false, 'intent_closed'::text;
      return;
    end if;
    return query select v_id, v_key, true, null::text;
    return;
  end;

  return query select v_id, v_key, false, null::text;
end $$;
revoke execute on function billing_issue_intent_open(uuid, text, text) from public, anon, authenticated;
grant  execute on function billing_issue_intent_open(uuid, text, text) to service_role;

comment on function billing_issue_intent_open(uuid, text, text) is
  '0170: opens the durable record for ONE billing-key issuance attempt and returns the server-minted
Idempotency-Key the caller must send to Toss. Party gate (tombstoned/absent profile, under a row
lock) before state gate (card_registration_live). A retried open for the same attempt nonce returns
the SAME key — a second key would make a recovery re-POST a fresh execution instead of a replay — and
a terminal intent refuses `intent_closed` rather than reopening. service_role ONLY: the client never
opens an intent, and a definer granted to `authenticated` would let anyone mint issuance records.';


-- ═══ §D billing_issue_intent_close — called with the outcome, after the Toss request ══════════
--
-- ⚠ **WHY THIS IS A SECOND CALL AND NOT PART OF `billing_key_swap`.** Folding the close into the
--   swap would make the record atomic with the store — genuinely better — at the cost of changing
--   the swap's signature and semantics, which this slice is explicitly not allowed to do and which
--   the memo does not require. The window it leaves is stated rather than hidden: between a
--   COMMITTED swap and a successful close the intent sits `issuing` while its key IS persisted. A
--   sweep must therefore reconcile an open intent against `billing_keys` before acting — which it
--   must do anyway, because memo §4 (U3) says a replayed 200 is 「what happened then」, never 「state
--   now」. So the window costs the sweep nothing it was not already obliged to do.
--
-- ⚠ EVERY DISAGREEMENT BETWEEN THE OUTCOME AND ITS EVIDENCE RAISES. An `issued_*` close with no key
--   would assert a credential exists and refuse to name it; a `provider_error` close carrying a key
--   would invent one. Both are caller bugs and both fail loudly here rather than landing a row a
--   human would later have to reason about.
create or replace function billing_issue_intent_close(
  p_intent      uuid,
  p_outcome     text,
  p_billing_key text default null,
  p_note        text default null
)
returns table (closed boolean, refusal text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_state text; v_key text := nullif(btrim(coalesce(p_billing_key, '')), '');
begin
  if p_outcome is null or p_outcome not in
       ('issued_persisted', 'issued_unpersisted', 'provider_error', 'unresolved') then
    raise exception '0170: billing_issue_intent_close called with outcome %',
      coalesce(p_outcome, 'NULL');
  end if;
  if p_outcome in ('issued_persisted', 'issued_unpersisted') and v_key is null then
    raise exception '0170: outcome % must name the billing key it is talking about', p_outcome;
  end if;
  if p_outcome in ('provider_error', 'unresolved') and v_key is not null then
    raise exception '0170: outcome % must not carry a billing key', p_outcome;
  end if;
  if p_intent is null then
    raise exception '0170: billing_issue_intent_close called with no intent id';
  end if;

  select state into v_state from billing_issue_intents where id = p_intent for update;

  -- ⚠ TWO CAUSES, TWO ANSWERS. `closed=false` used to be able to mean only one thing in this
  --   function's first draft, and that is exactly the widened-boolean defect CLAUDE.md §④ is about.
  --   An absent intent and an already-closed one are different facts and the caller maps them
  --   differently, so each has its own reason and an absent reason must fail CLOSED.
  if not found then
    return query select false, 'no_intent'::text;
    return;
  end if;
  if v_state is distinct from 'issuing' then
    return query select false, 'already_closed'::text;
    return;
  end if;

  update billing_issue_intents
     set state       = p_outcome,
         billing_key = v_key,
         note        = nullif(left(coalesce(p_note, ''), 500), ''),
         closed_at   = now(),
         updated_at  = now()
   where id = p_intent;

  return query select true, null::text;
end $$;
revoke execute on function billing_issue_intent_close(uuid, text, text, text) from public, anon, authenticated;
grant  execute on function billing_issue_intent_close(uuid, text, text, text) to service_role;

comment on function billing_issue_intent_close(uuid, text, text, text) is
  '0170: records the outcome of one issuance attempt and closes its intent. Four terminal outcomes;
`issued_persisted`/`issued_unpersisted` MUST name the billing key and `provider_error`/`unresolved`
must not carry one, both enforced by a raise rather than by a row nobody can interpret. Refuses with
`no_intent` or `already_closed` — two different facts, never one boolean — and never returns a closed
intent to `issuing`. service_role ONLY.';


-- ═══ VERIFY — house form. Every arm is `is distinct from` / `is not true`, never a bare `if`:
-- `has_*_privilege` and a catalog lookup can both answer NULL, plpgsql does not take an IF on a NULL
-- predicate, and every arm below exists to notice that something is MISSING — which is precisely the
-- state where a bare IF goes silent. An absent function is reported as a VALUE by name
-- (`to_regprocedure`) rather than raising, so one missing object does not hide the rest.
do $mig$
declare
  v_bad text := ''; v_n int; v_sec boolean; v_cfg text[]; v_o regprocedure; v_nm text;
  o_open  regprocedure := to_regprocedure('public.billing_issue_intent_open(uuid, text, text)');
  o_close regprocedure := to_regprocedure('public.billing_issue_intent_close(uuid, text, text, text)');
begin
  -- ① the table, its seal, and the two uniqueness constraints this slice is built on
  if to_regclass('public.billing_issue_intents') is null then
    v_bad := v_bad || ' NO-TABLE(billing_issue_intents)';
  else
    if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'billing_issue_intents') is distinct from true
      then v_bad := v_bad || ' NO-RLS'; end if;
    select count(*) into v_n from pg_policies
      where schemaname = 'public' and tablename = 'billing_issue_intents';
    if v_n is distinct from 0 then v_bad := v_bad || ' POLICIES=' || coalesce(v_n::text, 'NULL'); end if;

    select count(*) into v_n from (
      select r.rolname, pr.priv
        from (values ('anon'),('authenticated')) r(rolname),
             (values ('select'),('insert'),('update'),('delete')) pr(priv)
       where has_table_privilege(r.rolname, 'public.billing_issue_intents', pr.priv) is distinct from false
    ) t;
    if v_n is distinct from 0 then v_bad := v_bad || ' CLIENT-GRANTS=' || coalesce(v_n::text, 'NULL'); end if;
    -- the over-revoke control: this direction leaks nothing and breaks card registration silently
    if has_table_privilege('service_role', 'public.billing_issue_intents', 'select') is distinct from true
      then v_bad := v_bad || ' service_role-CANNOT-read'; end if;

    -- ⚠ ASSERTED BY THE COLUMNS THEY COVER, never by constraint NAME: a unique index renamed is
    --   still the guarantee, and a name match would be satisfied by an index on the wrong column.
    select count(*) into v_n from pg_index i
      join pg_class c on c.oid = i.indrelid
     where c.relname = 'billing_issue_intents' and i.indisunique and i.indnkeyatts = 1
       and (select a.attname from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'attempt_nonce';
    if v_n is distinct from 1 then v_bad := v_bad || ' NO-UQ(attempt_nonce)'; end if;
    select count(*) into v_n from pg_index i
      join pg_class c on c.oid = i.indrelid
     where c.relname = 'billing_issue_intents' and i.indisunique and i.indnkeyatts = 1
       and (select a.attname from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'idempotency_key';
    if v_n is distinct from 1 then v_bad := v_bad || ' NO-UQ(idempotency_key)'; end if;
  end if;

  -- ② both functions: they exist, they are definers, they carry an IN-BODY search_path (an
  --    ALTER-applied one is discarded by `create or replace`), and their ACL is the one written
  --    above rather than whatever a default handed them.
  if o_open  is null then v_bad := v_bad || ' NO-FN(billing_issue_intent_open)'; end if;
  if o_close is null then v_bad := v_bad || ' NO-FN(billing_issue_intent_close)'; end if;
  if o_open is not null and o_close is not null then
    foreach v_o in array array[o_open, o_close] loop
      v_nm := case when v_o = o_open then 'open' else 'close' end;
      select p.prosecdef, p.proconfig into v_sec, v_cfg from pg_proc p where p.oid = v_o::oid;
      if v_sec is not true then v_bad := v_bad || ' NOT-DEFINER(' || v_nm || ')'; end if;
      if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%' then
        v_bad := v_bad || ' NO-INBODY-SEARCH_PATH(' || v_nm || ')'; end if;
      if has_function_privilege('public', v_o, 'execute') is not false
        then v_bad := v_bad || ' PUBLIC-EXECUTE(' || v_nm || ')'; end if;
      if has_function_privilege('anon', v_o, 'execute') is not false
        then v_bad := v_bad || ' anon-EXECUTE(' || v_nm || ')'; end if;
      if has_function_privilege('authenticated', v_o, 'execute') is not false
        then v_bad := v_bad || ' authenticated-EXECUTE(' || v_nm || ')'; end if;
      -- the positive control, on the same line: the edge function calls both on the service key, so
      -- 「revoke everything」 would satisfy the three arms above and take card registration down
      if has_function_privilege('service_role', v_o, 'execute') is not true
        then v_bad := v_bad || ' service_role-CANNOT-EXECUTE(' || v_nm || ')'; end if;
    end loop;
  end if;

  -- ⚠ NO ARM ASSERTS THAT `card_registration_live()` IS SHUT, and the omission is deliberate. It is
  --    true today and this file does not touch `ops_flags`, but an apply that ABORTS because Sean
  --    has legitimately opened registration would be a guard that fires on the system working —
  --    and nothing this VERIFY could observe would tell that apart from a breach. The latency is
  --    PROSE (the header), not an unfalsifiable arm.

  if v_bad <> '' then
    raise exception '0170 VERIFY FAILED:%', v_bad;
  end if;
end $mig$;
