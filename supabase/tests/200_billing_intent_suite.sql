-- ═══ 200: an issuance is NAMED before Toss is called (0170) — 0170-B1 ~ 0170-B8 (8 pins) ═══════
--
-- 🔴 THE PROPERTY THIS FILE OWNS: **every billing-key issuance attempt has exactly ONE durable row,
--    written before the provider is called, carrying ONE server-minted idempotency key that belongs
--    to the ATTEMPT and not to the call** — so a retry sends the same key (a replay, not a second
--    execution), two attempts can never share one (Toss's dedupe tuple omits the request body, memo
--    §2a claim 8), and a finished attempt can never be reopened and re-sent.
--
--    Why it is worth pins rather than prose: before 0170 the issuance `Idempotency-Key` was a
--    `crypto.randomUUID()` minted inside the edge isolate and persisted nowhere. A lost response
--    left a live standing authority to charge a real card named in NO table — codex billing finding
--    3 (`docs/reviews/2026-08-28-codex-billing-chain.md:35`).
--
-- ⚠ **LATENT, ALL OF IT.** `ops_flags.card_registration_live_since` is NULL in production and 0
--   billing keys exist. These pins arm with the registration flag — which is exactly the flag the
--   review says findings 3 and 4 must close BEFORE (`review:142-146`). This suite ARMS the flag for
--   its own fixtures and `0170-B8` asserts by VALUE that it put it back.
--
-- ⚠ **EVERY PIN CAUSES ITS OWN DELTA.** No arm reads a global count: each uses its own `bik_*`
--   attempt nonce and counts rows for THAT nonce, before and after an action it performs itself.
--   (「if you deleted the behaviour entirely, would this pin's number change?」 — yes, to 0.)
--
-- ⚠ **WHAT THIS SUITE CANNOT REACH, stated as PROSE rather than as an unfalsifiable pin:**
--   · the RECOVERY SWEEP does not exist — its resolution arm waits on the two Toss questions in
--     memo §3, so there is nothing here to redden;
--   · `unresolved`'s real cause (a response that never arrives) is an edge-runtime fact; the SQL can
--     only assert that the state is writable and terminal. The handler's side is pinned in
--     `functions/_test/register_billing_key_test.ts`;
--   · 0170's own VERIFY arms are measured by the APPLY, two-sided, in the battery below — a suite
--     structurally cannot observe an apply-time abort, so each apply-aborting plant was re-run with
--     its VERIFY arm removed so a SUITE pin had to catch it alone.
--
-- ⚠ Every arm asserts an EXACT boolean (`is not true` / `is distinct from`). plpgsql does not take
--   an `IF` on a NULL predicate, and every pin here exists to notice that something is MISSING —
--   which is precisely the state where a bare `IF` goes silent.
-- ⚠ `_fail` args pre-computed into `v_msg`, never a subquery (the 110 header law).
-- ⚠ Pin labels are SLICE-PREFIXED (`0170-…`): the namespace is owned, not shared.
--
-- ═══ THE MUTATION BATTERY, MEASURED 2026-09-15 ════════════════════════════════════════════════
-- Baseline **1201 → 1209 (+8 = exactly the pins in this file)** — the positive control that this
-- suite RAN rather than being silently skipped from `harness.sh`'s manifest. The 1201 is a
-- MEASUREMENT on this tree, taken twice: once before 0170 existed at all, and again with the
-- migration applied and no suite (still 1201, so the delta is the suite and not the migration).
-- ⚠ Every plant is `&&`-CHAINED to its harness run and re-reads the file BACK from disk, asserting
--   that the new text landed AND that the old text is gone — a plant that does not land yields NO
--   ROW rather than a plausible green one.
-- ⚠ No mutation ever touched this worktree: every run is against an `rsync` copy (`.pgtest`
--   excluded, so each lab does its own initdb) and each lab cluster is stopped after its run.
-- ⚠ CONTROL observed clean FIRST **and** LAST, both 1209/0.
--
-- | # | mutation | result |
-- |---|---|---|
-- | CONTROL | none | **1209/0** — observed FIRST, so the deltas below mean something |
-- | M1  | §A's `unique` on `attempt_nonce` deleted | **APPLY ABORTS** — `0170 VERIFY FAILED: NO-UQ(attempt_nonce)`. That measures the VERIFY, not this suite, so it is re-run as M1b |
-- | M1b | M1 **with VERIFY ①'s `NO-UQ(attempt_nonce)` arm also deleted** | **1208/1 = `0170-B3` ALONE** — `HAND-WRITTEN-SECOND-INTENT-FOR-ONE-ATTEMPT-ADMITTED`: one attempt carrying two intents and two different idempotency keys |
-- | M2  | §B's `revoke all … from anon, authenticated` deleted | **APPLY ABORTS** — `0170 VERIFY FAILED: CLIENT-GRANTS=8` |
-- | M2b | M2 **with VERIFY ①'s `CLIENT-GRANTS` arm also deleted** | **1208/1 = `0170-B2` ALONE**, and the detail names all eight: `anon:delete, anon:insert, anon:select, anon:update, authenticated:delete, authenticated:insert, authenticated:select, authenticated:update` |
-- | M3  | §A's `unique` on `idempotency_key` deleted **+ its VERIFY arm** | **1208/1 = `0170-B5` ALONE** — `SHARED-KEY-ADMITTED(two attempts, one Idempotency-Key)` |
-- | M4  | §C's `if v_state is distinct from 'issuing'` reopen guard deleted (behaviour, so no VERIFY arm stands in front and no apply aborts) | **1208/1 = `0170-B4` ALONE** — `REOPENED(refusal=NULL) REOPEN-RETURNED-AN-INTENT REOPEN-HANDED-BACK-THE-KEY` |
-- | M5  | §C's party gate and state gate SWAPPED | **1208/1 = `0170-B6` ALONE** — `ORDER: a tombstoned account was answered gate_closed — the STATE gate ran before the PARTY gate` |
-- | CONTROL | none, lab restored from pristine | **1209/0** |
--
-- 🔴 **ONE FINDING CAME OUT OF THE BATTERY ITSELF AND CHANGED THIS FILE.** B3's constraint arm ⓓ
--    originally planted its duplicate on `bik_n1` — B4's fixture nonce — and M1b then measured
--    **1207/2, B3 AND B4**: with the `unique` gone, B4's reopen found the surviving OPEN twin and
--    was handed its key. That is a true and ugly consequence and it is recorded here, but it made
--    the battery read 「two pins」 where the finding is one, and it coupled B4's result to B3's
--    fixture. ⓓ now owns `bik_n3d` and creates BOTH of its rows itself, so B4 measures the reopen
--    guard alone — re-measured after the change, and the control was re-observed clean (1209/0)
--    before the re-run.
--
-- ⚠ **WHAT M1b DOES *NOT* SHOW, stated because the green half is the interesting half.** With the
--   `unique` removed, arms ⓐ–ⓒ stay GREEN: `billing_issue_intent_open` selects the existing row
--   first, so it still hands back the same key and still leaves one row. The FUNCTION is polite
--   without the constraint. What the constraint buys is the caller who is not — a second writer, a
--   racing open (the `unique_violation` handler in §C is built on it), a future SQL path. That is
--   why ⓓ asserts the CONSTRAINT and not the function's answer, and it is the only arm that moves.

do $suite$
declare
  u_ok uuid; u_dead uuid;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_txt text;
  v_id uuid; v_id2 uuid; v_key text; v_key2 text; v_ref text; v_rep boolean;
  v_ok boolean; v_state text; v_bk text; v_closed timestamptz;
  v_sec boolean; v_cfg text[]; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_o regprocedure; v_nm text;
  v_flag_before timestamptz; v_flag_after timestamptz;
  b1 constant text := '0170-B1 both intent definers have the shape that makes every other pin here mean something';
  b2 constant text := '0170-B2 the intent table is sealed by TWO walls — RLS with zero policies AND no client grant';
  b3 constant text := '0170-B3 one intent per attempt, and a retried open returns the SAME idempotency key';
  b4 constant text := '0170-B4 a closed intent never reopens — not through the open RPC, not through a second close';
  b5 constant text := '0170-B5 one key per intent: two attempts can never share an idempotency key, and 300 chars is the ceiling';
  b6 constant text := '0170-B6 party gate BEFORE state gate, and neither refusal mints a key';
  b7 constant text := '0170-B7 the close records the outcome faithfully and fails LOUDLY on a contradictory one';
  b8 constant text := '0170-B8 the suite put the card-registration flag back exactly as it found it';
begin
  u_ok   := t_user('bik_owner', 'owner');
  u_dead := t_user('bik_ghost', 'owner');
  update profiles set deleted_at = now() where id = u_dead;
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  select card_registration_live_since into v_flag_before from ops_flags limit 1;
  -- ARM the gate. Every pin below except B6's shut arms needs it open, because `billing_issue_intent_open`
  -- refuses `gate_closed` first — and a suite that ran entirely against a shut gate would be green
  -- on 「everything refuses」, which is the failure this file must not be handed for free.
  update ops_flags set card_registration_live_since = now() - interval '1 day';

  ------------------------------------------------------------------------------------------
  -- 0170-B1: the two definers' own SHAPE. 0170's VERIFY ② checks this at APPLY, and a property
  -- checked only at apply is protected exactly until somebody recreates the function. It is also
  -- the precondition that makes every behavioural pin below mean something: a non-definer cannot
  -- write a table sealed from every client role, and an `authenticated`-executable open is a
  -- machine for minting issuance records against any profile id a caller cares to type.
  begin
    foreach v_o in array array[
      to_regprocedure('public.billing_issue_intent_open(uuid, text, text)'),
      to_regprocedure('public.billing_issue_intent_close(uuid, text, text, text)')] loop
      if v_o is null then v_bad := v_bad || ' ABSENT-FUNCTION'; continue; end if;
      v_nm := split_part(v_o::text, '(', 1);
      select p.prosecdef, p.proconfig into v_sec, v_cfg from pg_proc p where p.oid = v_o::oid;
      if v_sec is not true then v_bad := v_bad || ' NOT-definer(' || v_nm || ')'; end if;
      if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%'
        then v_bad := v_bad || ' NO-inbody-search_path(' || v_nm || ')'; end if;
      select has_function_privilege('public', v_o, 'execute'),
             has_function_privilege('anon', v_o, 'execute'),
             has_function_privilege('authenticated', v_o, 'execute'),
             has_function_privilege('service_role', v_o, 'execute')
        into v_pub, v_anon, v_auth, v_svc;
      if v_pub  is not false then v_bad := v_bad || ' PUBLIC-can-execute(' || v_nm || ')'; end if;
      if v_anon is not false then v_bad := v_bad || ' anon-can-execute(' || v_nm || ')'; end if;
      if v_auth is not false then v_bad := v_bad || ' authenticated-can-execute(' || v_nm || ')'; end if;
      -- the positive control on the same line: the edge function calls BOTH on the service key, so
      -- 「revoke everything」 satisfies the three arms above and silently kills card registration
      if v_svc  is not true  then v_bad := v_bad || ' service_role-CANNOT-execute(' || v_nm || ')'; end if;
    end loop;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b1, v_msg); else call _pass('bik', b1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B2: the seal. Eight arms (2 roles × 4 privileges), each named in the failure string,
  -- because 「something regressed」 and 「this role, this privilege」 are different messages to wake
  -- up to. Plus the two walls stated separately and the two controls that keep the pin honest.
  begin
    select count(*), coalesce(string_agg(t.rolname || ':' || t.priv, ', ' order by t.rolname, t.priv), '')
      into v_n, v_txt
    from (
      select r.rolname, pr.priv
        from (values ('anon'),('authenticated')) r(rolname),
             (values ('select'),('insert'),('update'),('delete')) pr(priv)
       where has_table_privilege(r.rolname, 'public.billing_issue_intents', pr.priv) is distinct from false
    ) t;
    if v_n is distinct from 0 then v_bad := v_bad || ' CLIENT-GRANTS(' || v_txt || ')'; end if;
    if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relname = 'billing_issue_intents') is distinct from true
      then v_bad := v_bad || ' NO-RLS'; end if;
    select count(*) into v_n from pg_policies
      where schemaname = 'public' and tablename = 'billing_issue_intents';
    if v_n is distinct from 0 then v_bad := v_bad || ' POLICIES=' || coalesce(v_n::text, 'NULL'); end if;
    -- ⚠ CONTROL ⓐ — the fixture starts where PRODUCTION starts. `00_shim.sql` mirrors Supabase's
    --   `alter default privileges … grant all on tables to anon, authenticated`, so this table is
    --   BORN with all four for both client roles and 0170's revoke removes something real. Without
    --   this arm the eight above would be green over an empty world and would license nothing —
    --   0151's measured near-miss, one family over.
    if has_table_privilege('authenticated', 'public.session_people', 'select') is not true
      then v_bad := v_bad || ' FIXTURE-CONTROL-FAILED(an ordinary table has no default grant either — the eight arms above are measuring an empty world, not a revoke)'; end if;
    -- ⚠ CONTROL ⓑ — the over-revoke direction, which leaks nothing and breaks card registration.
    if has_table_privilege('service_role', 'public.billing_issue_intents', 'select') is not true
      then v_bad := v_bad || ' service_role-CANNOT-read'; end if;
    if has_table_privilege('service_role', 'public.billing_issue_intents', 'insert') is not true
      then v_bad := v_bad || ' service_role-CANNOT-write'; end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b2, v_msg); else call _pass('bik', b2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B3: 🔴 THE HEADLINE. One intent per attempt, and a retried open returns the SAME key.
  --
  -- Four arms with DIFFERENT blind spots, which is what makes the set a control rather than one
  -- claim printed four times:
  --   ⓐ the second open returns the first key            — blind to: a function that returns one
  --                                                        hard-wired key for every attempt
  --   ⓑ a DIFFERENT attempt gets a DIFFERENT key         — kills exactly that
  --   ⓒ the row count for this nonce goes 0 → 1, a delta THIS PIN CAUSED, never a state it found
  --   ⓓ a hand-written second row for the same nonce is REFUSED (23505 asserted, not 「it raised」 —
  --     a NOT NULL violation also raises and means something else). This arm is the CONSTRAINT
  --     rather than the function's politeness, and it is the one that survives a caller who does
  --     not ask nicely.
  select count(*) into v_n from billing_issue_intents where attempt_nonce = 'bik_n1';
  begin
    select intent_id, idempotency_key, reopened, refusal into v_id, v_key, v_rep, v_ref
      from billing_issue_intent_open(u_ok, 'bik_n1', 'bik_ck_1');
    if v_ref is not null then v_bad := v_bad || ' FIRST-OPEN-REFUSED(' || v_ref || ')'; end if;
    if v_id is null then v_bad := v_bad || ' FIRST-OPEN-NO-INTENT'; end if;
    if v_key is null then v_bad := v_bad || ' FIRST-OPEN-NO-KEY'; end if;
    if v_rep is not false then v_bad := v_bad || ' FIRST-OPEN-CLAIMS-REOPENED'; end if;

    select intent_id, idempotency_key, reopened, refusal into v_id2, v_key2, v_rep, v_ref
      from billing_issue_intent_open(u_ok, 'bik_n1', 'bik_ck_1');
    if v_ref is not null then v_bad := v_bad || ' SECOND-OPEN-REFUSED(' || v_ref || ')'; end if;
    if v_key2 is distinct from v_key then
      v_bad := v_bad || ' SECOND-OPEN-MINTED-A-NEW-KEY(' || coalesce(v_key, 'NULL') || ' -> ' || coalesce(v_key2, 'NULL') || ')'; end if;
    if v_id2 is distinct from v_id then v_bad := v_bad || ' SECOND-OPEN-NEW-INTENT'; end if;
    if v_rep is not true then v_bad := v_bad || ' SECOND-OPEN-DOES-NOT-SAY-REOPENED'; end if;

    select count(*) into v_n2 from billing_issue_intents where attempt_nonce = 'bik_n1';
    if (v_n2 - v_n) is distinct from 1 then
      v_bad := v_bad || ' SECOND-ROW-ADMITTED-FOR-ONE-ATTEMPT(rows=' || coalesce(v_n2::text, 'NULL') || ')'; end if;

    -- ⓑ the control
    select idempotency_key into v_txt from billing_issue_intent_open(u_ok, 'bik_n2', 'bik_ck_1');
    if v_txt is null then v_bad := v_bad || ' CONTROL-SECOND-ATTEMPT-REFUSED';
    elsif v_txt is not distinct from v_key then
      v_bad := v_bad || ' CONTROL-FAILED: a DIFFERENT attempt got the SAME key — the function hands out one key for everything'; end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  -- ⓓ the constraint itself, on its OWN attempt nonce.
  -- ⚠ IT IS DELIBERATELY NOT `bik_n1`, and the reason was MEASURED rather than reasoned: with the
  --   `unique` removed, a duplicate row planted on B4's fixture nonce reddens B4 as well (the
  --   reopen finds the surviving OPEN twin and hands its key back — a real and ugly consequence,
  --   but one that makes the battery read 「two pins」 where the finding is one). Its own nonce keeps
  --   this arm attributable to B3 and leaves B4 measuring the reopen guard alone.
  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (u_ok, 'bik_n3d', 'bik_ck_1', 'bik_hand_key_3d_a');
  exception when others then
    v_bad := v_bad || ' FIXTURE-FAILED: the FIRST row for a fresh attempt was refused (' || sqlstate || ')';
  end;
  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (u_ok, 'bik_n3d', 'bik_ck_1', 'bik_hand_key_3d_b');
    v_bad := v_bad || ' HAND-WRITTEN-SECOND-INTENT-FOR-ONE-ATTEMPT-ADMITTED';
  exception
    when unique_violation then null;                      -- 23505, the expected refusal
    when others then v_bad := v_bad || ' WRONG-SQLSTATE(' || sqlstate || ' ' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b3, v_msg); else call _pass('bik', b3); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B4: a closed intent never reopens.
  --
  -- Why it is its own pin and not a footnote on B3: handing a TERMINAL intent's key back would let
  -- a spent attempt be re-sent to Toss under a key whose outcome we have already written down —
  -- and under the replay branch (memo §2a claim 6) Toss would answer with that recorded outcome, so
  -- the retry would look like a fresh success. The row must also be unchanged afterwards: a reopen
  -- that RESURRECTED the row would destroy the record of what actually happened.
  begin
    select closed, refusal into v_ok, v_ref
      from billing_issue_intent_close(v_id, 'issued_persisted', 'bik_bill_1', 'B4 fixture');
    if v_ok is not true then v_bad := v_bad || ' CLOSE-REFUSED(' || coalesce(v_ref, 'NULL') || ')'; end if;

    select intent_id, idempotency_key, refusal into v_id2, v_key2, v_ref
      from billing_issue_intent_open(u_ok, 'bik_n1', 'bik_ck_1');
    if v_ref is distinct from 'intent_closed' then
      v_bad := v_bad || ' REOPENED(refusal=' || coalesce(v_ref, 'NULL') || ')'; end if;
    if v_id2 is not null then v_bad := v_bad || ' REOPEN-RETURNED-AN-INTENT'; end if;
    if v_key2 is not null then v_bad := v_bad || ' REOPEN-HANDED-BACK-THE-KEY'; end if;

    -- the row is untouched — state, key and close stamp all still say what happened
    select count(*) into v_n2 from billing_issue_intents where attempt_nonce = 'bik_n1';
    if v_n2 is distinct from 1 then v_bad := v_bad || ' REOPEN-WROTE-A-ROW(rows=' || coalesce(v_n2::text, 'NULL') || ')'; end if;
    select state, billing_key, closed_at into v_state, v_bk, v_closed
      from billing_issue_intents where attempt_nonce = 'bik_n1';
    if v_state is distinct from 'issued_persisted' then v_bad := v_bad || ' STATE=' || coalesce(v_state, 'NULL'); end if;
    if v_bk is distinct from 'bik_bill_1' then v_bad := v_bad || ' KEY=' || coalesce(v_bk, 'NULL'); end if;
    if v_closed is null then v_bad := v_bad || ' NO-CLOSE-STAMP'; end if;

    -- and the close is one-way too: a second one is REFUSED BY NAME rather than overwriting
    select closed, refusal into v_ok, v_ref
      from billing_issue_intent_close(v_id, 'unresolved', null, 'B4 second close');
    if v_ok is not false then v_bad := v_bad || ' SECOND-CLOSE-ACCEPTED'; end if;
    if v_ref is distinct from 'already_closed' then
      v_bad := v_bad || ' SECOND-CLOSE-REFUSAL=' || coalesce(v_ref, 'NULL'); end if;
    select state into v_state from billing_issue_intents where attempt_nonce = 'bik_n1';
    if v_state is distinct from 'issued_persisted' then
      v_bad := v_bad || ' SECOND-CLOSE-OVERWROTE-THE-OUTCOME(' || coalesce(v_state, 'NULL') || ')'; end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b4, v_msg); else call _pass('bik', b4); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B5: one key per intent, across intents — the uniqueness Toss itself will NOT enforce.
  --
  -- 🔴 The documented dedupe tuple is (key, API key, URL, method) and OMITS THE REQUEST BODY (memo
  --    §2a claim 8), so if two attempts shared a key Toss would hand one attempt's cached response
  --    to the other and nothing at the provider would notice. The database is the only place this
  --    can be made impossible.
  --   ⓐ a second row carrying an EXISTING key is refused, 23505 asserted;
  --   ⓑ a fresh key is admitted — so ⓐ cannot be satisfied by a table that refuses everything;
  --   ⓒ 301 characters is refused (memo §2a claim 11: >300 → 400 INVALID_IDEMPOTENCY_KEY at Toss;
  --     a row we can never legally send is worse than a refused write), 23514 asserted.
  select idempotency_key into v_key from billing_issue_intents where attempt_nonce = 'bik_n1';
  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (u_ok, 'bik_n5a', 'bik_ck_1', v_key);
    v_bad := v_bad || ' SHARED-KEY-ADMITTED(two attempts, one Idempotency-Key)';
  exception
    when unique_violation then null;
    when others then v_bad := v_bad || ' WRONG-SQLSTATE-ON-SHARE(' || sqlstate || ')';
  end;
  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (u_ok, 'bik_n5b', 'bik_ck_1', 'bik_fresh_key_5b');
    select count(*) into v_n2 from billing_issue_intents where attempt_nonce = 'bik_n5b';
    if v_n2 is distinct from 1 then v_bad := v_bad || ' CONTROL-FRESH-KEY-NOT-STORED'; end if;
  exception when others then
    v_bad := v_bad || ' CONTROL-FAILED: a FRESH key was refused too (' || sqlstate || ') — ⓐ is measuring a table that refuses everything';
  end;
  begin
    insert into billing_issue_intents (profile_id, attempt_nonce, customer_key, idempotency_key)
    values (u_ok, 'bik_n5c', 'bik_ck_1', repeat('k', 301));
    v_bad := v_bad || ' 301-CHAR-KEY-ADMITTED(Toss answers 400 INVALID_IDEMPOTENCY_KEY to it)';
  exception
    when check_violation then null;
    when others then v_bad := v_bad || ' WRONG-SQLSTATE-ON-LENGTH(' || sqlstate || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b5, v_msg); else call _pass('bik', b5); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B6: party gate BEFORE state gate, and neither refusal mints a key.
  --
  -- ⚠ ARM ⓑ IS THE ORDERING ITSELF and it is the only arm that can see it. A tombstoned account
  --   asked while the gate is ALSO shut must be told `deleted_account`: answering `gate_closed`
  --   would mean the state gate ran first, and it would tell a deleted account our rollout state —
  --   a fact about US, disclosed to the one caller with no business asking.
  -- ⚠ ARM ⓓ is the positive control. Without it 「refuse everything」 passes ⓐⓑⓒ perfectly while
  --   making card registration impossible, with no leak and no failing pin.
  begin
    -- ⓐ dead profile, gate OPEN
    select intent_id, idempotency_key, refusal into v_id2, v_key2, v_ref
      from billing_issue_intent_open(u_dead, 'bik_n6a', 'bik_ck_dead');
    if v_ref is distinct from 'deleted_account' then v_bad := v_bad || ' DEAD-OPEN-refusal=' || coalesce(v_ref, 'NULL'); end if;
    if v_key2 is not null then v_bad := v_bad || ' DEAD-OPEN-MINTED-A-KEY'; end if;
    select count(*) into v_n2 from billing_issue_intents where attempt_nonce = 'bik_n6a';
    if v_n2 is distinct from 0 then v_bad := v_bad || ' DEAD-OPEN-WROTE-A-ROW=' || coalesce(v_n2::text, 'NULL'); end if;

    update ops_flags set card_registration_live_since = null;

    -- ⓑ dead profile, gate SHUT → the party answer, not the state answer
    select refusal into v_ref from billing_issue_intent_open(u_dead, 'bik_n6b', 'bik_ck_dead');
    if v_ref is distinct from 'deleted_account' then
      v_bad := v_bad || ' ORDER: a tombstoned account was answered ' || coalesce(v_ref, 'NULL') || ' — the STATE gate ran before the PARTY gate'; end if;

    -- ⓒ live profile, gate SHUT
    select intent_id, idempotency_key, refusal into v_id2, v_key2, v_ref
      from billing_issue_intent_open(u_ok, 'bik_n6c', 'bik_ck_1');
    if v_ref is distinct from 'gate_closed' then v_bad := v_bad || ' SHUT-refusal=' || coalesce(v_ref, 'NULL'); end if;
    if v_key2 is not null then v_bad := v_bad || ' SHUT-MINTED-A-KEY'; end if;
    select count(*) into v_n2 from billing_issue_intents where attempt_nonce = 'bik_n6c';
    if v_n2 is distinct from 0 then v_bad := v_bad || ' SHUT-WROTE-A-ROW=' || coalesce(v_n2::text, 'NULL'); end if;

    update ops_flags set card_registration_live_since = now() - interval '1 day';

    -- ⓓ the positive control
    select idempotency_key, refusal into v_key2, v_ref
      from billing_issue_intent_open(u_ok, 'bik_n6d', 'bik_ck_1');
    if v_ref is not null then v_bad := v_bad || ' CONTROL-REFUSED(' || v_ref || ')'; end if;
    if v_key2 is null then v_bad := v_bad || ' CONTROL-FAILED: a live profile with the gate OPEN got no key — every arm above is green because this function refuses everything'; end if;
  exception when others then
    v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
    update ops_flags set card_registration_live_since = now() - interval '1 day';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b6, v_msg); else call _pass('bik', b6); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B7: the close records the outcome faithfully, and a contradictory one fails LOUDLY.
  --
  -- An `issued_*` close with no key asserts that a live charging credential exists and refuses to
  -- say which — strictly worse than no row. A `provider_error` carrying a key INVENTS one. Both are
  -- caller bugs; both must die at the write rather than land a row a human reasons about later.
  select intent_id into v_id2 from billing_issue_intent_open(u_ok, 'bik_n7', 'bik_ck_1');
  if v_id2 is null then v_bad := v_bad || ' FIXTURE-NO-INTENT'; end if;
  begin
    perform billing_issue_intent_close(v_id2, 'provider_error', 'bik_bill_7', null);
    v_bad := v_bad || ' provider_error-WITH-A-KEY-ACCEPTED';
  exception when others then null; end;
  begin
    perform billing_issue_intent_close(v_id2, 'issued_unpersisted', null, null);
    v_bad := v_bad || ' issued_unpersisted-WITHOUT-A-KEY-ACCEPTED';
  exception when others then null; end;
  begin
    perform billing_issue_intent_close(v_id2, 'done', null, null);
    v_bad := v_bad || ' UNKNOWN-OUTCOME-ACCEPTED';
  exception when others then null; end;
  begin
    -- the honest arm: the state finding 3 is about, written and stamped
    select closed, refusal into v_ok, v_ref
      from billing_issue_intent_close(v_id2, 'unresolved', null, 'no answer from Toss');
    if v_ok is not true then v_bad := v_bad || ' unresolved-REFUSED(' || coalesce(v_ref, 'NULL') || ')'; end if;
    select state, billing_key, closed_at into v_state, v_bk, v_closed
      from billing_issue_intents where id = v_id2;
    if v_state is distinct from 'unresolved' then v_bad := v_bad || ' STATE=' || coalesce(v_state, 'NULL'); end if;
    if v_bk is not null then v_bad := v_bad || ' unresolved-CARRIES-A-KEY'; end if;
    if v_closed is null then v_bad := v_bad || ' NO-CLOSE-STAMP'; end if;

    -- an intent that does not exist is its OWN answer, never the same boolean as 「already closed」
    select closed, refusal into v_ok, v_ref
      from billing_issue_intent_close(gen_random_uuid(), 'unresolved', null, null);
    if v_ok is not false then v_bad := v_bad || ' ABSENT-INTENT-CLOSED'; end if;
    if v_ref is distinct from 'no_intent' then v_bad := v_bad || ' ABSENT-refusal=' || coalesce(v_ref, 'NULL'); end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  -- the state machine as a constraint: a terminal row cannot be walked back to `issuing` by hand
  begin
    update billing_issue_intents set state = 'issuing' where id = v_id2;
    v_bad := v_bad || ' TERMINAL-ROW-WALKED-BACK-TO-issuing(the open/closed invariant is not enforced)';
  exception
    when check_violation then null;
    when others then v_bad := v_bad || ' WRONG-SQLSTATE-ON-WALKBACK(' || sqlstate || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b7, v_msg); else call _pass('bik', b7); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0170-B8: the flag is put back exactly as it was found, asserted by VALUE against the snapshot
  -- taken at the top of this file. A suite that arms a money-adjacent gate and leaves it armed
  -- would hand every later slice a fixture that lies about production (0157-R1's precedent).
  update ops_flags set card_registration_live_since = v_flag_before;
  select card_registration_live_since into v_flag_after from ops_flags limit 1;
  if v_flag_after is distinct from v_flag_before then
    v_bad := v_bad || ' FLAG-LEFT-AT=' || coalesce(v_flag_after::text, 'NULL')
                   || ' EXPECTED=' || coalesce(v_flag_before::text, 'NULL'); end if;
  -- ⚠ Conditioned on the snapshot, not asserted flat: this arm says 「the reader agrees with the
  --   restore」, and hard-coding 「shut」 would false-fire on any future fixture that legitimately
  --   arrived here with the flag already armed.
  if v_flag_before is null and card_registration_live() is not false then
    v_bad := v_bad || ' card_registration_live() STILL TRUE after restoring a NULL flag'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bik', b8, v_msg); else call _pass('bik', b8); end if;
end $suite$;
