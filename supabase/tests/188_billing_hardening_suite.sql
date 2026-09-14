-- ═══ 188: one key, one outstanding order to destroy it — and the cron is READ BACK (0157) ═══
--    0157-C1 · 0157-S1 · 0157-U1 ~ 0157-U6 · 0157-R1  (9 pins)
--
-- 🔴 THE PROPERTY THIS FILE OWNS: a billing key may have **at most one OUTSTANDING (pending or
--    processing) revocation row at a time**, no matter which of the five enqueue paths reaches it,
--    and merging a second enqueue must never resurrect the first — not its state, not its attempt
--    count, not its claim token, not its lease.
--
--    Why it matters more than a tidy table: two outstanding rows mean two `DELETE /v1/billing/{key}`
--    calls at Toss. A successful first followed by a non-2xx second writes `abandoned` — and since
--    0155 `abandoned` PAGES the ops roster with 「카드 해지 실패 — 확인 필요」. So a duplicate converts a
--    revocation that WORKED into a human being told to go hand-delete a key that is already gone.
--    0155's own header argues that an alert firing on the system working correctly is muted within
--    a week; a duplicate row is exactly how that happens.
--
-- ⚠ **LATENT, ALL OF IT.** `ops_flags.card_registration_live_since` and `payments_live_since` are
--   both NULL and there are 0 billing keys in production, so no duplicate can exist today. These
--   pins arm with the registration flag. That is a reason to pin it now, not a reason to wait.
--
-- ⚠ **EVERY PIN CAUSES ITS OWN DELTA.** Suites 170/174/175/180/186 leave rows in
--   `billing_key_revocations`, so nothing here reads a global count. Each pin uses its own
--   `bkh_*` key and counts rows for THAT key, before and after an action it performs itself —
--   a number this pin caused, never a state it found.
--
-- ⚠ **`0157-C1` PINS THE JOB'S SHAPE, NOT THE SWALLOW — and the distinction is worth stating
--   because it is exactly the 「a green is evidence for one sentence」 trap.** `cron.schedule`
--   UPSERTS on (jobname, username), so deleting 0157 §A leaves 0138's identical registration behind
--   and C1 stays green. C1 cannot see the swallow. What C1 does see — and what a migration-time
--   VERIFY cannot, because a property checked only at apply survives exactly until somebody
--   re-registers or unschedules the job — is that the job exists, is active, runs the right command,
--   and that the command names a function that EXISTS. **The removal of the `exception when others`
--   is proved by the APPLY, two-sided, in the battery recorded BELOW as M5/M6** (this sentence
--   originally promised the battery in the REGISTRY row; the battery was run on 2026-08-31 and is
--   recorded here, in the file it is about, with the REGISTRY row carrying only a one-liner):
--   with `cron.schedule` planted to raise, 0138's swallowed form applies GREEN and 0157's form
--   ABORTS the migration. A suite structurally cannot observe that, because a suite only runs after
--   an apply succeeds. ⚠ That was a PREDICTION when it was written and it is now a MEASUREMENT —
--   M5 applies green having installed nothing, M6 aborts at 0157:50.
--
-- ⚠ **NAMED GAP — §B's duplicate-collapse block is NOT PINNED, deliberately.** The collapse runs
--   once, at apply, against whatever duplicates an already-running database holds. Production has 0
--   rows and this harness applies migrations to an empty table, so there is no fixture in which the
--   collapse does anything; every arm a pin could assert would pass unconditionally. Per the
--   standing rule, a limitation is PROSE — the tell is that no mutation could redden such a pin,
--   and none can. Its correctness is instead guarded by 0157's VERIFY ④, which aborts the apply if
--   any duplicate outstanding rows survive.
--
-- ⚠ Finding **7** (the constant-time cron-secret compare) has no SQL surface at all and is pinned in
--   `functions/_test/revoke_billing_keys_test.ts` and `collect_charges_test.ts`. It is named here so
--   a reader of this file does not conclude the slice forgot it.
--
-- ⚠ Every arm asserts an EXACT boolean (`is not true` / `is distinct from`). plpgsql does not take
--   an `IF` on a NULL predicate, and every pin in this file exists to notice that something is
--   MISSING — which is precisely the state where a bare `IF` goes silent.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ═══ THE MUTATION BATTERY, MEASURED 2026-08-31 ═══════════════════════════════════════════════
-- Baseline **1135 → 1144 (+9 = exactly the pins in this file)** — the positive control that this
-- suite RAN rather than being silently skipped from `harness.sh`'s manifest. The 1135 is a
-- MEASUREMENT, not a remembered number: a pristine `git archive` of trunk WITHOUT this slice was
-- applied and run in its own scratch cluster and returned `1135 pass / 0 fail`; the adopted tree
-- returns `1144 pass / 0 fail` with 9 `0157-*` rows and 0 red. 1144 − 1135 = 9 = the pins added.
-- ⚠ Every plant ASSERTS its own occurrence count AND reads the file back, and every harness run is
--   `&&`-CHAINED to its plant, so a plant that does not land yields NO ROW rather than a plausible
--   green one. **That guard fired for real**: a parallel agent's battery overwrote the shared
--   planter mid-run and two mutations produced NO ROW instead of a green one. The entire set was
--   then re-run from a private toolchain, and that re-run is what the table reports.
-- ⚠ CONTROL observed clean FIRST (1144/0) and again LAST (1144/0), on a `rsync` copy of the tree —
--   no mutation ever touched the live worktree.
--
-- | # | mutation | result |
-- |---|---|---|
-- | CONTROL | none | **1144/0** — observed FIRST, so the deltas below mean something |
-- | M1  | §B's `create unique index … outstanding_uq` deleted | **APPLY ABORTS** — `0157 VERIFY: NO-OUTSTANDING-UQ` |
-- | M2  | M1 + VERIFY ①'s arm deleted | the harness **DIES at suite 170** — `there is no unique or exclusion constraint matching the ON CONFLICT specification` (170:122). Loud, but it never reaches 188: the index is gone while §B.1's `on conflict … where` remains, and that clause cannot infer an absent partial index. **So M2 does not measure the finding — M16 does** |
-- | M16 | 🔴 **THE PRE-0157 WORLD, WHOLE** — index deleted, VERIFY ① deleted, and the primitive reverted to 0138's raw INSERT | **1140/4 = `0157-U1`·`U2`·`U3`·`U4`.** U1 reports `SECOND-OUTSTANDING-ADMITTED OUTSTANDING-COUNT=2 TOTAL-COUNT=3` — **one key carrying two live orders to DELETE it at Toss, which is finding 6 itself, reproduced** |
-- | M3  | §A's read-back deleted **and** the scheduled command pointed at a function that does not exist | **THE APPLY SUCCEEDS SILENTLY** — that IS finding 5's hole, a migration reporting success having installed a scheduler pointed at nothing — and **1143/1 = `0157-C1` alone**: `COMMAND=select no_such_dispatcher() COMMANDED-FUNCTION-ABSENT(no_such_dispatcher)` |
-- | M4  | the same broken command, read-back PRESENT | **APPLY ABORTS** — `0157 §A VERIFY: expected exactly 1 active … found 0`. ⚠ Only the SCHEDULE's copy of the command string was moved: rewriting the read-back's copy too would have moved the detector along with the defect, and the pin would have agreed with the bug |
-- | M5  | 🔴 **finding 5 WHOLE** — `cron.schedule` planted to refuse this one job, §A reverted to 0138:283-291's `exception when others` swallow, read-back deleted | **APPLY GREEN with nothing installed**, and **1143/1 = `0157-C1` alone** (`JOB-COUNT=0`) |
-- | M6  | the same planted refusal, §A exactly as SHIPPED | **APPLY ABORTS** — `planted: pg_cron unavailable for revoke-billing-keys` at 0157:50. M5+M6 together are the two-sided proof of the swallow removal, which no suite can observe |
-- | M7  | both `on conflict … do update` arms deleted, index kept | 1141/3 = `0157-U2`·`U3`·`U4`, each on a real 23505 raised out of the RPC |
-- | M8  | the merge RESURRECTS — `do update` also resets `state`/`attempts`/`claim_token`/`lease_until` | **1143/1 = `0157-U2` alone**: `STATE=pending ATTEMPTS=0 CLAIM-TOKEN-MOVED LEASE-CLEARED`, all four equalities firing |
-- | M14 | the empty-key RAISE replaced by `return null` | **1143/1 = `0157-U5` alone**: `NULL-KEY-ACCEPTED BLANK-KEY-ACCEPTED` |
-- | M15 | the FK fallback disarmed (`when foreign_key_violation` → `when division_by_zero`) | **1143/1 = `0157-U6` alone**: `RAISED(23503 …) ROWS=0` — the KEY is lost along with the provenance |
-- | M9  | the primitive's `revoke … from public, anon, authenticated` deleted | **APPLY ABORTS** — `PRIMITIVE-public-execute PRIMITIVE-anon-execute PRIMITIVE-authenticated-execute` |
-- | M10 | M9 + VERIFY ②'s three ACL arms deleted | 1141/3 = **`98 H9`** + **`99 S1`** + `0157-S1` — three independent detectors, two of them schema-wide sweeps that catch it without knowing this slice exists |
-- | M11 | `billing_key_swap`'s revoke deleted | **1144/0 — REDDENS NOTHING.** Diagnosed below; it is NOT a blind pin |
-- | M12 | `billing_key_swap` actively WIDENED (`grant … to authenticated`) | **APPLY ABORTS** — `0157 VERIFY: SWAP-authenticated-execute` |
-- | M13 | M12 + VERIFY ③'s two swap arms deleted | **1143/1 = `170 B5` alone** (`authenticated-CAN`) — a shipped pin stands in front, so the widening is still caught with 0157's own VERIFY disarmed |
-- | CONTROL | none, tree restored | **1144/0** |
--
-- 🔴 **M11 REDDENS NOTHING, AND THE TWO CAUSES WERE TOLD APART BY OBSERVATION RATHER THAN BY
--    REASONING.** Deleting 0157's `revoke execute on function billing_key_swap(…) from public,
--    anon, authenticated` leaves 1144/0. The pins are not blind — **the property is not observable
--    through this door**, and that is measured: with M11 applied, the database returns
--    `billing_key_swap | postgres=X/postgres service_role=X/postgres` and
--    `has_function_privilege('authenticated', …) = f`, identical to the control. The harness applies
--    every migration in numeric order from scratch, so `billing_key_swap` ALWAYS already exists
--    (0137 first defines it) and `create or replace` preserves its ACL — preservation can never fail
--    here. That is exactly the class CLAUDE.md records the runtime harness as structurally green on.
--    **The guard that DOES stand in front is the SOURCE gate, and it was run two-sided:**
--    `MIGRATIONS_DIR=<mutated tree> node app/scripts/check-definer-acl.mjs` → **exit 1**, naming
--    `0157_billing_cron_and_key_hardening.sql:117  billing_key_swap()  — 최초 정의는
--    0137_billing_key_swap.sql`; the same gate on the unmutated tree → **exit 0**, baseline 81
--    unchanged. So M11's null result is a fact about the harness, not a gap in coverage — but it is
--    only allowed to be that fact BECAUSE the other gate was observed to redden.
--    ⚠ The contrast with M12/M13 is what makes this a diagnosis rather than an excuse: an ACTUAL
--      widening of the same function's ACL aborts the apply (M12) and, with 0157's VERIFY arms
--      removed, reddens `170 B5` (M13). The detectors on that surface are alive. It is specifically
--      the DELETION OF A REDUNDANT REVOKE that has no observable consequence in a from-scratch apply.
--
-- ⚠ **SEVEN MUTATIONS ABORT THE APPLY, WHICH MEASURES 0157's VERIFY AND NOT THIS SUITE.** That is
--   the three-proposition discipline: 「the hole is real」, 「a pin notices」 and 「the fix closes it」
--   are three different claims and one mutation proves only the middle. So each apply-aborting plant
--   was re-run with its own VERIFY arm removed — M1→M16, M4→M3, M6→M5, M9→M10, M12→M13 — so that a
--   SUITE pin (or a shipped sweep) had to catch it alone. A property checked only at apply is
--   protected exactly until somebody recreates the function.

do $$
declare
  u1 uuid; u2 uuid; u3 uuid; u4 uuid;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_txt text;
  v_id uuid; v_id2 uuid; v_tok uuid; v_ok boolean; v_ref text;
  v_sec boolean; v_cfg text[]; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_state text; v_att int; v_lease timestamptz; v_reasons text[]; v_prof uuid;
  v_flag_before timestamptz; v_flag_after timestamptz;
  c1 constant text := '0157-C1 revoke-billing-keys 크론이 cron.job 에서 되읽힌다 (보고가 아니라 사실)';
  s1 constant text := '0157-S1 병합 프리미티브의 형태 — definer · in-body search_path · 클라이언트 롤 거절';
  u1p constant text := '0157-U1 부분 유니크 인덱스: 미결 행은 하나뿐, 종결 행은 허용';
  u2p constant text := '0157-U2 두 번째 등록은 병합된다 — 그리고 진행 중인 작업을 되살리지 않는다';
  u3p constant text := '0157-U3 billing_key_swap 의 gate_closed 경로가 중복 행을 만들지 않는다';
  u4p constant text := '0157-U4 계정 삭제 경로(enqueue_billing_key_revocation)도 프리미티브를 지난다';
  u5p constant text := '0157-U5 빈 키는 시끄럽게 거절되고 아무것도 쓰지 않는다';
  u6p constant text := '0157-U6 FK 위반은 출처를 잃을 뿐, 키를 잃지 않는다';
  r1  constant text := '0157-R1 스위트가 카드 등록 플래그를 원래대로 되돌렸다';
begin
  u1 := t_user('bkh_merge', 'owner');
  u2 := t_user('bkh_index', 'owner');
  u3 := t_user('bkh_gate',  'owner');
  u4 := t_user('bkh_del',   'owner');
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  select card_registration_live_since into v_flag_before from ops_flags limit 1;

  ------------------------------------------------------------------------------------------
  -- 0157-C1: the cron registration, read back from the catalog.
  --
  -- 🔴 THE FINDING IN ONE SENTENCE: 0138 wrapped `cron.schedule` in `exception when others`, so a
  --    failed install COMMITTED as a successful migration and nobody would ever invoke the
  --    dispatcher. On the live project it did NOT fail (jobid 23, 110 successful runs) — latent,
  --    not breached — and 0157 removes the swallow and reads the job back.
  --
  -- ⚠ THE `command` ARM IS TWO FACTS, NOT ONE. That the command string is what we expect, AND that
  --   the function it names actually EXISTS. A scheduler faithfully running `select
  --   no_such_function()` every ten minutes is the same product outcome as no scheduler at all,
  --   and the string arm alone cannot tell them apart.
  -- ⚠ ABSENT ARM FIRST. With no `cron` schema every arm below would be vacuously green — the exact
  --   NULL-collapse this repo has measured four times — so absence is an explicit, loud failure.
  begin
    if to_regclass('cron.job') is null then
      v_bad := v_bad || ' NO-cron.job(pg_cron absent — arms would be vacuous)';
    else
      select count(*)::int into v_n from cron.job where jobname = 'revoke-billing-keys';
      if v_n is distinct from 1 then
        v_bad := v_bad || ' JOB-COUNT=' || coalesce(v_n::text, 'NULL');
      else
        select active, schedule, command into v_ok, v_txt, v_state
          from cron.job where jobname = 'revoke-billing-keys';
        if v_ok is not true then v_bad := v_bad || ' JOB-INACTIVE'; end if;
        if v_txt is distinct from '8-58/10 * * * *'
          then v_bad := v_bad || ' SCHEDULE=' || coalesce(v_txt, 'NULL'); end if;
        if v_state is distinct from 'select dispatch_billing_key_revocations()'
          then v_bad := v_bad || ' COMMAND=' || coalesce(v_state, 'NULL'); end if;
        -- ⚠ The function is resolved OUT OF THE COMMAND ROW, never from a name written here.
        --   A hard-coded `to_regprocedure('public.dispatch_billing_key_revocations()')` answers
        --   「does our dispatcher exist」 — a true and useless sentence, since it stays true no
        --   matter what the scheduler was pointed at. Measured: under battery M1 (the command
        --   changed to a function that does not exist) the hard-coded form stayed GREEN while the
        --   string arm alone reddened. Reading it out of the row is what makes this an arm about
        --   the SCHEDULE rather than about the schema.
        v_txt := substring(v_state from 'select\s+([a-z0-9_]+)\s*\(');
        if v_txt is null then
          v_bad := v_bad || ' COMMAND-NAMES-NO-FUNCTION';
        elsif to_regprocedure('public.' || v_txt || '()') is null then
          v_bad := v_bad || ' COMMANDED-FUNCTION-ABSENT(' || v_txt || ')';
        end if;
      end if;
    end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', c1, v_msg); else call _pass('bkh', c1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-S1: the primitive's own shape. 0157's VERIFY ② checks this at APPLY, and a property
  -- checked only at apply is protected exactly until somebody recreates the function (0155-S1's
  -- precedent, same argument). It is also the precondition that makes every other pin here mean
  -- something: a non-definer cannot write the sealed outbox from inside `billing_key_swap`, and an
  -- `authenticated`-executable one is an arbitrary-revocation injector — a client could enqueue a
  -- stranger's live billing key for destruction.
  begin
    select p.prosecdef, p.proconfig into v_sec, v_cfg
      from pg_proc p
     where p.oid = 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure;
    if v_sec is not true then v_bad := v_bad || ' NOT-definer'; end if;
    if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%'
      then v_bad := v_bad || ' NO-inbody-search_path'; end if;
    select has_function_privilege('public', o, 'execute'),
           has_function_privilege('anon', o, 'execute'),
           has_function_privilege('authenticated', o, 'execute'),
           has_function_privilege('service_role', o, 'execute')
      into v_pub, v_anon, v_auth, v_svc
      from (select 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure as o) t;
    if v_pub  is not false then v_bad := v_bad || ' PUBLIC-can-execute'; end if;
    if v_anon is not false then v_bad := v_bad || ' anon-can-execute'; end if;
    if v_auth is not false then v_bad := v_bad || ' authenticated-can-execute'; end if;
    -- The POSITIVE control on the same line: the worker calls this on the service key, so a slice
    -- that revoked everything would satisfy the three arms above and break the product.
    if v_svc  is not true  then v_bad := v_bad || ' service_role-CANNOT-execute'; end if;
  exception when others then v_bad := v_bad || ' ABSENT(' || sqlerrm || ')';
  end;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', s1, v_msg); else call _pass('bkh', s1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U1: the CONSTRAINT itself, three arms, and the second two are what make it a real pin
  -- rather than 「an index exists」.
  --   ⓐ a second OUTSTANDING row for the same key is REFUSED, and the SQLSTATE is asserted
  --     (23505) rather than 「it raised」 — a NOT NULL violation would also raise, and would mean
  --     something else entirely;
  --   ⓑ a second row for the same key in a TERMINAL state is ADMITTED. The index is PARTIAL on
  --     purpose: `done`/`failed`/`abandoned` rows are history and a key legitimately gets a second
  --     obligation later. A full unique index passes ⓐ perfectly and ships the wrong product —
  --     this arm is the only thing that tells the two apart;
  --   ⓒ a DIFFERENT key is admitted, so ⓐ cannot be satisfied by an index that refuses everything.
  -- The blind-spot lists of the three arms are different, which is what makes them controls
  -- rather than one claim printed three times.
  insert into billing_key_revocations (profile_id, billing_key, reason, state)
  values (u2, 'bkh_U1', 'replaced', 'pending');

  begin
    insert into billing_key_revocations (profile_id, billing_key, reason, state)
    values (u2, 'bkh_U1', 'gate_closed', 'processing');
    v_bad := v_bad || ' SECOND-OUTSTANDING-ADMITTED';
  exception
    when unique_violation then null;                       -- the expected refusal
    when others then v_bad := v_bad || ' WRONG-SQLSTATE(' || sqlstate || ')';
  end;

  begin
    insert into billing_key_revocations (profile_id, billing_key, reason, state)
    values (u2, 'bkh_U1', 'account_deleted', 'done');
  exception when others then v_bad := v_bad || ' TERMINAL-DUPLICATE-REFUSED(' || sqlerrm || ')';
  end;

  begin
    insert into billing_key_revocations (profile_id, billing_key, reason, state)
    values (u2, 'bkh_U1_other', 'replaced', 'pending');
  exception when others then v_bad := v_bad || ' DIFFERENT-KEY-REFUSED(' || sqlerrm || ')';
  end;

  select count(*)::int into v_n from billing_key_revocations
   where billing_key = 'bkh_U1' and state in ('pending', 'processing');
  if v_n is distinct from 1 then v_bad := v_bad || ' OUTSTANDING-COUNT=' || coalesce(v_n::text, 'NULL'); end if;
  select count(*)::int into v_n2 from billing_key_revocations where billing_key = 'bkh_U1';
  if v_n2 is distinct from 2 then v_bad := v_bad || ' TOTAL-COUNT=' || coalesce(v_n2::text, 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u1p, v_msg); else call _pass('bkh', u1p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U2: the MERGE, and the half that matters most is what it does NOT touch.
  --
  -- 🔴 A merge that reset `state`, `attempts`, `claim_token` or `lease_until` would look like a
  --    tidy-up and would BE the defect: it hands a row a worker is currently holding back to the
  --    claimer, i.e. a second DELETE for the same key — the exact outcome this slice exists to
  --    prevent, re-created by the fix. So the fixture is deliberately a row MID-FLIGHT (processing,
  --    attempts 3, a live token and lease), and the assertions are equalities on all four.
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'bkh_U2', 'replaced', 'processing', 3, v_tok, now() + interval '5 minutes')
  returning id into v_id;

  begin
    v_id2 := enqueue_billing_key_revocation_row(u1, 'bkh_U2', 'gate_closed', 'a second path agreed');
    if v_id2 is distinct from v_id then v_bad := v_bad || ' RETURNED-A-DIFFERENT-ROW'; end if;
  exception when others then v_bad := v_bad || ' MERGE-RAISED(' || sqlerrm || ')';
  end;

  select count(*)::int into v_n from billing_key_revocations where billing_key = 'bkh_U2';
  if v_n is distinct from 1 then v_bad := v_bad || ' ROWS=' || coalesce(v_n::text, 'NULL'); end if;

  select state, attempts, claim_token, lease_until, reason, merged_reasons
    into v_state, v_att, v_id2, v_lease, v_txt, v_reasons
    from billing_key_revocations where id = v_id;
  if v_state is distinct from 'processing' then v_bad := v_bad || ' STATE=' || coalesce(v_state, 'NULL'); end if;
  if v_att   is distinct from 3           then v_bad := v_bad || ' ATTEMPTS=' || coalesce(v_att::text, 'NULL'); end if;
  if v_id2   is distinct from v_tok       then v_bad := v_bad || ' CLAIM-TOKEN-MOVED'; end if;
  if v_lease is null                      then v_bad := v_bad || ' LEASE-CLEARED'; end if;
  -- The original obligation keeps its own reason; the newcomer's rides in `merged_reasons`, where
  -- `report_billing_key_revocation` cannot overwrite it the way it overwrites `last_error`.
  if v_txt     is distinct from 'replaced'                 then v_bad := v_bad || ' REASON-REWRITTEN=' || coalesce(v_txt, 'NULL'); end if;
  if v_reasons is distinct from array['gate_closed']::text[] then v_bad := v_bad || ' MERGED=' || coalesce(array_to_string(v_reasons, ','), 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u2p, v_msg); else call _pass('bkh', u2p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U3: the same property through the REAL path, because a primitive nobody calls is a
  -- primitive nobody calls. `billing_key_swap`'s `gate_closed` branch is the cheapest of its three
  -- enqueue sites to reach — Sean's flag shut, a live profile, Toss has already issued the key —
  -- and 0143's own comment says it must REFUSE **AND ENQUEUE**, so a bare refusal would strand the
  -- credential the gate was closed to prevent.
  --
  -- Two identical calls stand in for the retry the finding describes. Before 0157 they produce two
  -- outstanding rows and two DELETEs; a mutation reverting this branch to a raw INSERT makes the
  -- second call raise `unique_violation` out of the RPC, which reddens here.
  -- ⚠ The refusal itself is asserted on BOTH calls: a fix that stopped the duplicate by breaking
  --   the swap would otherwise pass the row count perfectly.
  update ops_flags set card_registration_live_since = null;
  begin
    select swapped, refusal into v_ok, v_ref
      from billing_key_swap(u3, 'bkh_U3', '{"brand":"test","last4":"4242"}'::jsonb);
    if v_ok  is not false                   then v_bad := v_bad || ' CALL1-SWAPPED'; end if;
    if v_ref is distinct from 'gate_closed' then v_bad := v_bad || ' CALL1-REFUSAL=' || coalesce(v_ref, 'NULL'); end if;

    select swapped, refusal into v_ok, v_ref
      from billing_key_swap(u3, 'bkh_U3', '{"brand":"test","last4":"4242"}'::jsonb);
    if v_ok  is not false                   then v_bad := v_bad || ' CALL2-SWAPPED'; end if;
    if v_ref is distinct from 'gate_closed' then v_bad := v_bad || ' CALL2-REFUSAL=' || coalesce(v_ref, 'NULL'); end if;
  exception when others then v_bad := v_bad || ' SWAP-RAISED(' || sqlstate || ' ' || sqlerrm || ')';
  end;

  select count(*)::int into v_n from billing_key_revocations where billing_key = 'bkh_U3';
  if v_n is distinct from 1 then v_bad := v_bad || ' ROWS=' || coalesce(v_n::text, 'NULL'); end if;
  select reason, merged_reasons, state into v_txt, v_reasons, v_state
    from billing_key_revocations where billing_key = 'bkh_U3';
  if v_txt     is distinct from 'gate_closed'                then v_bad := v_bad || ' REASON=' || coalesce(v_txt, 'NULL'); end if;
  if v_state   is distinct from 'pending'                    then v_bad := v_bad || ' STATE=' || coalesce(v_state, 'NULL'); end if;
  if v_reasons is distinct from array['gate_closed']::text[]  then v_bad := v_bad || ' MERGED=' || coalesce(array_to_string(v_reasons, ','), 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u3p, v_msg); else call _pass('bkh', u3p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U4: the fifth enqueue site — `enqueue_billing_key_revocation`, whose only caller is
  -- `delete_my_account_tx` (patched in by 0138 §F, BEFORE the `billing_keys` delete, because it
  -- reads that table). It is the site a reviewer is least likely to look at and the one whose rows
  -- MOST need revoking: an orphaned key belonging to a deleted account.
  --
  -- Three arms, and the third is the control that stops the pin passing on a broken function:
  --   ⓐ first call inserts · ⓑ second call MERGES · ⓒ a profile with no stored card writes nothing
  --     (0138's own early return, preserved here rather than assumed).
  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (u4, 'bkh_U4', '{"brand":"test","last4":"1111"}'::jsonb, now())
  on conflict (profile_id) do update set billing_key = excluded.billing_key;

  begin
    perform enqueue_billing_key_revocation(u4, 'account_deleted');
    select count(*)::int into v_n from billing_key_revocations where billing_key = 'bkh_U4';
    if v_n is distinct from 1 then v_bad := v_bad || ' AFTER-1ST=' || coalesce(v_n::text, 'NULL'); end if;

    perform enqueue_billing_key_revocation(u4, 'account_deleted');
    select count(*)::int into v_n from billing_key_revocations where billing_key = 'bkh_U4';
    if v_n is distinct from 1 then v_bad := v_bad || ' AFTER-2ND=' || coalesce(v_n::text, 'NULL'); end if;

    select merged_reasons into v_reasons from billing_key_revocations where billing_key = 'bkh_U4';
    if v_reasons is distinct from array['account_deleted']::text[]
      then v_bad := v_bad || ' MERGED=' || coalesce(array_to_string(v_reasons, ','), 'NULL'); end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlstate || ' ' || sqlerrm || ')';
  end;

  begin
    perform enqueue_billing_key_revocation(u3, 'account_deleted');   -- u3 has no billing_keys row
  exception when others then v_bad := v_bad || ' NO-CARD-RAISED(' || sqlerrm || ')';
  end;
  select count(*)::int into v_n2 from billing_key_revocations where profile_id = u3 and reason = 'account_deleted';
  if v_n2 is distinct from 0 then v_bad := v_bad || ' NO-CARD-WROTE=' || coalesce(v_n2::text, 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u4p, v_msg); else call _pass('bkh', u4p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U5: an absent key is a CALLER BUG, and it is refused loudly.
  --
  -- ⚠ The tempting alternative — `if p_billing_key is null then return; end if` — is the silent
  --   shape this repo keeps meeting: it converts 「a live charging credential was not recorded」 into
  --   「nothing to do」, and the two are indistinguishable afterwards. Both the RAISE and the absence
  --   of a written row are asserted; either alone is satisfiable by a body doing the wrong thing.
  select count(*)::int into v_n from billing_key_revocations;
  begin
    v_id2 := enqueue_billing_key_revocation_row(u1, null, 'replaced', null);
    v_bad := v_bad || ' NULL-KEY-ACCEPTED';
  exception when others then null;
  end;
  begin
    v_id2 := enqueue_billing_key_revocation_row(u1, '   ', 'replaced', null);
    v_bad := v_bad || ' BLANK-KEY-ACCEPTED';
  exception when others then null;
  end;
  select count(*)::int into v_n2 from billing_key_revocations;
  if v_n2 is distinct from v_n then v_bad := v_bad || ' WROTE-' || coalesce((v_n2 - v_n)::text, 'NULL') || '-ROWS'; end if;
  -- The control: the same call with a real key DOES write exactly one row, so the two arms above
  -- cannot be satisfied by a primitive that refuses everything.
  begin
    v_id2 := enqueue_billing_key_revocation_row(u1, 'bkh_U5', 'replaced', null);
    if v_id2 is null then v_bad := v_bad || ' CONTROL-RETURNED-NULL'; end if;
  exception when others then v_bad := v_bad || ' CONTROL-RAISED(' || sqlerrm || ')';
  end;
  select count(*)::int into v_n2 from billing_key_revocations where billing_key = 'bkh_U5';
  if v_n2 is distinct from 1 then v_bad := v_bad || ' CONTROL-ROWS=' || coalesce(v_n2::text, 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u5p, v_msg); else call _pass('bkh', u5p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-U6: PROVENANCE IS DROPPED BEFORE THE KEY IS.
  --
  -- `billing_key_revocations.profile_id` references `profiles(id)`, and a profile can be
  -- hard-deleted between a caller's read and this write. An FK violation would lose the BILLING
  -- KEY — the only field the sweep needs — so the primitive retries without provenance. 0141 §A
  -- makes the same trade inside the definer and `register-billing-key` made it edge-side; 0157
  -- moves it here so the three cannot drift, and this pin is where that consolidation is checked.
  -- ⚠ BOTH halves asserted: the row EXISTS (the key survived) and `profile_id` IS NULL (we admit
  --   what we lost). A pin asserting only the first would pass on a function that invented a
  --   profile id, and only the second on a function that wrote nothing at all.
  begin
    v_id2 := enqueue_billing_key_revocation_row(gen_random_uuid(), 'bkh_U6', 'orphaned_by_deletion', null);
    if v_id2 is null then v_bad := v_bad || ' RETURNED-NULL'; end if;
  exception when others then v_bad := v_bad || ' RAISED(' || sqlstate || ' ' || sqlerrm || ')';
  end;
  select count(*)::int into v_n from billing_key_revocations where billing_key = 'bkh_U6';
  if v_n is distinct from 1 then v_bad := v_bad || ' ROWS=' || coalesce(v_n::text, 'NULL'); end if;
  select profile_id, reason into v_prof, v_txt from billing_key_revocations where billing_key = 'bkh_U6';
  if v_prof is not null                              then v_bad := v_bad || ' PROFILE-INVENTED'; end if;
  if v_txt  is distinct from 'orphaned_by_deletion'  then v_bad := v_bad || ' REASON=' || coalesce(v_txt, 'NULL'); end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', u6p, v_msg); else call _pass('bkh', u6p); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0157-R1: U3 shut the registration flag to reach the `gate_closed` branch. Restoring it is
  -- pinned rather than assumed, because a failed restore poisons every suite that runs after this
  -- one and would present as their bug, not as this one's (185-G4's precedent).
  update ops_flags set card_registration_live_since = v_flag_before;
  select card_registration_live_since into v_flag_after from ops_flags limit 1;
  if v_flag_after is distinct from v_flag_before then v_bad := v_bad || ' FLAG-NOT-RESTORED'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('bkh', r1, v_msg); else call _pass('bkh', r1); end if;
  v_bad := '';
end $$;
