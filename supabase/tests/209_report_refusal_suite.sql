-- ═══ 209 — 0178's `report_billing_key_revocation` names its refusal — 0178-R1…R6, tag `rrt` ═══
--
-- THE PROPOSITION THIS FILE OWNS: a refused report SAYS WHY, with one token per cause, in a fixed
-- precedence, and a landed report says nothing — so the worker can count 「lost the lease」 apart
-- from 「the row was already closed」 apart from 「the row is gone」. Backend honesty audit
-- 2026-09-17 M7: 0155's boolean meant one thing, 0166 gave `false` a second cause, and the
-- handler kept reading the first (the ④ class). 0178 is the fix; this file is its battery.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE:
--   · 171 · 174 L2/L3 — the claim/lease mechanics and 「a late report is not applied」 (174 L3
--     now reads `applied`; its property is unchanged).
--   · 186 A1–A3 / 196 F2 — the give-up, its note and its class. R5 touches the abandoned branch
--     only to show it still runs through the new return shape; the note is theirs.
--   · 196 F3 — the terminal-row refusal's ROW effects (byte-unchanged, no page). R2 re-asserts
--     the row is untouched because the token is meaningless if the write happened anyway.
--
-- ─── THE DISAGREEMENT ZONE, which is the point of the fixtures ─────────────────────────────────
--   Under 0155 a `done` row with no token answered TRUE (re-closed). Under 0166 it answers FALSE —
--   the same FALSE as a lost lease. Under 0178 it answers (false, not_processing) while a lost
--   lease answers (false, lease_lost). R1 and R2 sit on the two sides of that line; R4 sits on
--   the row where BOTH causes hold and pins which token wins.
--
-- ─── MUTATION MAP — MEASURED, not predicted (plants `&&`-chained to their run against an
--     md5-identical COPY; CONTROL = the VERIFY demoted to a notice with NO plant ⇒ 1252/0 first;
--     the copy restored to its md5 after). The first draft of this map was written before the
--     battery and disagreed with it on three rows (cold review #3); this is the measured version.
--   (i)   0166's `and state = 'processing'` deleted ⇒ un-demoted: APPLY ABORTS
--         `0166-PROCESSING-CONJUNCT-MISSING` (measures the VERIFY, 0131-G4); demoted ⇒ 1249/3 =
--         R2 (「done:APPLIED … abandoned:APPLIED」 — terminal rows RE-CLOSED) + R6 + **196 0166-F3**
--         (「LATE-REPORT-APPLIED」 — the rewritten shipped pin still sees it). R1/R3/R4/R5 GREEN:
--         R4's done+wrong-token is still refused by the token clause and diagnosed from the
--         pre-image, so it is not observable through this plant.
--   (ii)  the lease judged BEFORE the state ⇒ 1250/2 = R4 (「the-two-sides-agree(lease_lost) — the
--         boolean is back」) + R5's second-tap arm (a now-done row's cleared token reads as a lost
--         lease). Predicted R4 alone; measured R4 + R5.
--   (iii) every refusal collapsed to `lease_lost` ⇒ un-demoted: APPLY ABORTS `TOKENS-MISSING`;
--         demoted ⇒ 1247/5 = R2 + R3 + R4 + R5 + R6; **R1 GREEN** — the one pin whose answer really
--         is lease_lost, which is what makes the other five measurements of vocabulary.
--   (iv)  the absent arm answers (false, NULL) ⇒ un-demoted: APPLY ABORTS `TOKENS-MISSING`;
--         demoted ⇒ 1250/2 = R3 + R6 (「(false,NULL)-observed」 — the ledger arm's one job).
--   (v)   the `for update` deleted ⇒ un-demoted: APPLY ABORTS `LOCK-NOT-BEFORE-WRITE`; demoted ⇒
--         1251/1 = R6 ALONE (the order arm) — and THE RACE below comes back.
--   THE RACE, measured by hand and NOT pinned (it needs two connections; `90_race_check.sh` is
--   single-purpose — NAMED GAP, closed by R6's order arm plus this measurement): a writer flips
--   one row processing↔pending 30,000× while a reporter offers the HOLDER's token 2,000×, so with
--   that token `lease_lost` is serially impossible (processing+token APPLIES; every other state is
--   not_processing). Control with no writer: 0/2000 every time. The FIRST DRAFT (diagnosis = a
--   second unlocked read after the refused UPDATE) ⇒ **52/2000 lease_lost** (the cold reader
--   measured 243/2000 on the same draft) — the M7 conflation rebuilt under concurrency. The
--   SHIPPED body (row locked before the write, diagnosis from the pre-image) ⇒ **0/2000**, with
--   applied=997 / not_processing=1003 showing the two sessions genuinely interleaved. Plant (v)
--   ⇒ **453/2000** — the lock is load-bearing, measured.
--
-- ─── FIXTURE NOTES ───
--  ① Rows are inserted directly (186's idiom), never through the claimer: this suite is about the
--     REPORT's answer given a row shape; 171/174 own how a row comes to be `processing`.
--  ② No `ops_recipients` row is seeded on purpose: `_note_revocation_abandoned` cross-joins the
--     recipients and inserts nothing when there are none, so R5's abandoned arm exercises the
--     branch without paging; the paging is 186's.
--  ③ `updated_at`/`last_error` are captured BEFORE each refused call and compared after — a
--     refusal that still wrote something would be worse than the old boolean.
set client_min_messages = warning;

do $$
declare
  u1 uuid;
  v_id uuid; v_id2 uuid; v_tok uuid; v_tok2 uuid;
  v_ap boolean; v_rf text; v_ap2 boolean; v_rf2 text;
  v_state text; v_err text; v_upd timestamptz; v_ctok uuid; v_lease timestamptz; v_att int;
  v_n int; v_bad text; v_msg text; v_st text; v_seen int := 0;
  v_pairs text[] := '{}';       -- every (applied, refusal) pair observed, for R6's ledger arm
  v_oid oid; v_res text; v_src text; v_acl text;
begin
  u1 := t_user('rrt_owner', 'owner');

  -- ---------- [0178-R1] a held row, the wrong token ⇒ lease_lost, and the row is untouched ----------
  v_bad := '';
  v_tok := gen_random_uuid(); v_tok2 := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until, last_error)
  values (u1, 'rrt_R1', 'replaced', 'processing', 2, v_tok, now() + interval '5 minutes', 'earlier toss 500')
  returning id into v_id;
  update billing_key_revocations set updated_at = now() - interval '10 minutes' where id = v_id;
  select updated_at into v_upd from billing_key_revocations where id = v_id;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, true, null, v_tok2);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false then v_bad := v_bad || ' applied=' || coalesce(v_ap::text,'NULL'); end if;
  if v_rf is distinct from 'lease_lost' then v_bad := v_bad || ' refusal=' || coalesce(v_rf,'NULL'); end if;
  select state, claim_token, lease_until, attempts, last_error into v_state, v_ctok, v_lease, v_att, v_err
    from billing_key_revocations where id = v_id;
  if v_state is distinct from 'processing' then v_bad := v_bad || ' state-moved(' || coalesce(v_state,'NULL') || ')'; end if;
  if v_ctok is distinct from v_tok then v_bad := v_bad || ' token-moved'; end if;
  if v_lease is null then v_bad := v_bad || ' lease-cleared'; end if;
  if v_err is distinct from 'earlier toss 500' then v_bad := v_bad || ' last_error-moved'; end if;
  if (select updated_at from billing_key_revocations where id = v_id) is distinct from v_upd then v_bad := v_bad || ' updated_at-moved'; end if;
  -- the pre-0141 token-less call shape against a HELD row is the same refusal
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, true, null);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false or v_rf is distinct from 'lease_lost' then v_bad := v_bad || ' null-token-on-held-row=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  if v_bad = '' then call _pass('rrt','0178-R1 잡혀 있는 행에 다른 토큰 ⇒ (false, lease_lost), 행은 그대로 (state·token·lease·last_error·updated_at); 토큰 없는 옛 호출도 같은 거절');
  else v_msg := v_bad; call _fail('rrt','0178-R1 lease_lost', v_msg); end if;

  -- ---------- [0178-R2] THE DISAGREEMENT ZONE: a row nobody holds ⇒ not_processing, whatever its state ----------
  -- Under 0155 this exact call (null token on a null-token row) APPLIED and re-closed the row;
  -- under 0166 it answered the same `false` a lost lease answers. The fixture's `p_token` is NULL
  -- on purpose so that the state gate is the ONLY thing refusing here.
  v_bad := '';
  foreach v_st in array array['done', 'abandoned', 'pending', 'failed'] loop
    v_seen := v_seen + 1;
    insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until, last_error)
    values (u1, 'rrt_R2_' || v_st, 'replaced', v_st, 3, null, null, 'fixture ' || v_st)
    returning id into v_id;
    update billing_key_revocations set updated_at = now() - interval '1 hour' where id = v_id;
    select updated_at into v_upd from billing_key_revocations where id = v_id;
    select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, true, null);
    v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
    if v_ap is distinct from false then v_bad := v_bad || ' ' || v_st || ':APPLIED'; end if;
    if v_rf is distinct from 'not_processing' then v_bad := v_bad || ' ' || v_st || ':refusal=' || coalesce(v_rf,'NULL'); end if;
    select state, last_error, updated_at, claim_token into v_state, v_err, v_upd, v_ctok from billing_key_revocations where id = v_id;
    if v_state is distinct from v_st then v_bad := v_bad || ' ' || v_st || ':state-moved(' || coalesce(v_state,'NULL') || ')'; end if;
    if v_err is distinct from ('fixture ' || v_st) then v_bad := v_bad || ' ' || v_st || ':last_error-moved'; end if;
    if v_upd > now() - interval '30 minutes' then v_bad := v_bad || ' ' || v_st || ':updated_at-moved'; end if;
    if v_ctok is not null then v_bad := v_bad || ' ' || v_st || ':claim_token-appeared'; end if;
  end loop;
  -- an empty or shortened loop would pass every arm above by never running it (cold review #4)
  if v_seen <> 4 then v_bad := v_bad || ' loop-ran-' || v_seen || '-times(expected 4)'; end if;
  if v_bad = '' then call _pass('rrt','0178-R2 아무도 안 잡은 행(done·abandoned·pending·failed)에 토큰 없는 보고 ⇒ (false, not_processing) — 0155에선 적용됐고 0166에선 lease_lost와 같은 false였던 바로 그 자리; 행은 그대로');
  else v_msg := v_bad; call _fail('rrt','0178-R2 not_processing', v_msg); end if;

  -- ---------- [0178-R3] no such row ⇒ absent, and nothing is written ----------
  v_bad := '';
  select count(*) into v_n from billing_key_revocations;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(gen_random_uuid(), true, null, gen_random_uuid());
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false or v_rf is distinct from 'absent' then v_bad := v_bad || ' random-id=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(null, false, 'x', null);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false or v_rf is distinct from 'absent' then v_bad := v_bad || ' null-id=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  -- exactly one row per call, never zero (a caller that reads `data[0]` must find it)
  select count(*) into v_att from report_billing_key_revocation(gen_random_uuid(), true, null);
  if v_att <> 1 then v_bad := v_bad || ' rows-per-call=' || v_att; end if;
  if (select count(*) from billing_key_revocations) <> v_n then v_bad := v_bad || ' row-count-moved'; end if;
  if v_bad = '' then call _pass('rrt','0178-R3 없는 id(무작위·NULL) ⇒ (false, absent), 호출당 정확히 1행, 아무것도 안 쓴다');
  else v_msg := v_bad; call _fail('rrt','0178-R3 absent', v_msg); end if;

  -- ---------- [0178-R4] PRECEDENCE: both causes true ⇒ not_processing wins; and the two sides differ ----------
  -- A `done` row reported with a WRONG token satisfies neither conjunct. The lease question is
  -- moot on a row nobody holds, so the answer must be not_processing — a caller told lease_lost
  -- would wait for a lease that will never be re-claimed.
  v_bad := '';
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until)
  values (u1, 'rrt_R4', 'replaced', 'done', 1, null, null) returning id into v_id;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, false, 'late', gen_random_uuid());
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false or v_rf is distinct from 'not_processing' then v_bad := v_bad || ' done+wrong-token=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  -- the other side of the line, on a held row with a wrong token, in the same pin so the two
  -- answers are compared rather than each asserted alone
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until)
  values (u1, 'rrt_R4b', 'replaced', 'processing', 1, v_tok, now() + interval '5 minutes') returning id into v_id2;
  select applied, refusal into v_ap2, v_rf2 from report_billing_key_revocation(v_id2, false, 'late', gen_random_uuid());
  v_pairs := v_pairs || (coalesce(v_ap2::text,'NULL') || '/' || coalesce(v_rf2,'NULL'));
  if v_rf2 is distinct from 'lease_lost' then v_bad := v_bad || ' held+wrong-token=' || coalesce(v_rf2,'NULL'); end if;
  if v_rf is not distinct from v_rf2 then v_bad := v_bad || ' the-two-sides-agree(' || coalesce(v_rf,'NULL') || ') — the boolean is back'; end if;
  if v_bad = '' then call _pass('rrt','0178-R4 우선순위 — done 행 + 틀린 토큰 ⇒ not_processing (lease_lost가 아니다); 잡힌 행 + 틀린 토큰 ⇒ lease_lost; 두 답이 다르다');
  else v_msg := v_bad; call _fail('rrt','0178-R4 precedence', v_msg); end if;

  -- ---------- [0178-R5] THE CONTROL in the other direction: a landed report is (true, NULL) on every branch ----------
  v_bad := '';
  -- done
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until)
  values (u1, 'rrt_R5a', 'replaced', 'processing', 2, v_tok, now() + interval '5 minutes') returning id into v_id;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, true, null, v_tok);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  select state, claim_token, lease_until, last_error into v_state, v_ctok, v_lease, v_err from billing_key_revocations where id = v_id;
  if v_ap is distinct from true or v_rf is not null then v_bad := v_bad || ' ok=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  if v_state is distinct from 'done' or v_ctok is not null or v_lease is not null or v_err is not null then v_bad := v_bad || ' done-row-wrong(' || coalesce(v_state,'NULL') || ')'; end if;
  -- pending (retryable failure, attempts < 8)
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until)
  values (u1, 'rrt_R5b', 'replaced', 'processing', 4, v_tok, now() + interval '5 minutes') returning id into v_id;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, false, 'toss 500', v_tok);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  select state, last_error into v_state, v_err from billing_key_revocations where id = v_id;
  if v_ap is distinct from true or v_rf is not null then v_bad := v_bad || ' retry=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  if v_state is distinct from 'pending' or v_err is distinct from 'toss 500' then v_bad := v_bad || ' retry-row-wrong(' || coalesce(v_state,'NULL') || ')'; end if;
  -- abandoned (the give-up; the note is 186's — no recipients seeded, ②)
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, claim_token, lease_until)
  values (u1, 'rrt_R5c', 'replaced', 'processing', 8, v_tok, now() + interval '5 minutes') returning id into v_id;
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, false, 'toss 500', v_tok);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  select state into v_state from billing_key_revocations where id = v_id;
  if v_ap is distinct from true or v_rf is not null then v_bad := v_bad || ' giveup=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  if v_state is distinct from 'abandoned' then v_bad := v_bad || ' giveup-row-wrong(' || coalesce(v_state,'NULL') || ')'; end if;
  -- and the second tap on the now-done row is the R2 refusal, through the same door
  select applied, refusal into v_ap, v_rf from report_billing_key_revocation(v_id, true, null, v_tok);
  v_pairs := v_pairs || (coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'));
  if v_ap is distinct from false or v_rf is distinct from 'not_processing' then v_bad := v_bad || ' second-tap=' || coalesce(v_ap::text,'NULL') || '/' || coalesce(v_rf,'NULL'); end if;
  if v_bad = '' then call _pass('rrt','0178-R5 적용된 보고는 (true, NULL) — done·pending·abandoned 세 갈래 모두, 행 상태는 0166 그대로; 닫힌 뒤 두 번째 보고는 not_processing');
  else v_msg := v_bad; call _fail('rrt','0178-R5 applied-control', v_msg); end if;

  -- ---------- [0178-R6] deployed shape + the fail-closed LEDGER ----------
  v_bad := '';
  -- every pair this suite observed: never (false, NULL), never (true, <token>)
  -- EXACT count, NULL-safe: `array_length` of an empty array is NULL and a bare `<` on NULL is
  -- silent (cold review #5); 14 = R1 2 + R2 4 + R3 2 + R4 2 + R5 4 — a pin that adds a call
  -- must move this number, which is the point.
  if coalesce(array_length(v_pairs, 1), 0) <> 14 then v_bad := v_bad || ' ledger-count=' || coalesce(array_length(v_pairs,1)::text,'0') || '(expected 14)'; end if;
  if exists (select 1 from unnest(v_pairs) p where p = 'false/NULL') then v_bad := v_bad || ' (false,NULL)-observed'; end if;
  if exists (select 1 from unnest(v_pairs) p where p like 'true/%' and p <> 'true/NULL') then v_bad := v_bad || ' (true,token)-observed'; end if;
  if exists (select 1 from unnest(v_pairs) p where p like 'NULL/%') then v_bad := v_bad || ' applied-NULL-observed'; end if;
  -- the deployed shape
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'report_billing_key_revocation';
  if v_n <> 1 then v_bad := v_bad || ' overloads=' || v_n; end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'report_billing_key_revocation'
     and pg_get_function_identity_arguments(p.oid) = 'p_id uuid, p_ok boolean, p_error text, p_token uuid';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION';
  else
    select pg_get_function_result(v_oid) into v_res;
    if (v_res = 'TABLE(applied boolean, refusal text)') is distinct from true then v_bad := v_bad || ' result=' || coalesce(v_res,'NULL'); end if;
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' 본문 search_path 없음'; end if;
    if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' ACL 기본값(PUBLIC)'; end if;
    select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
    if (coalesce(v_acl,'') ~ '(^|,)=[^/]*X') is distinct from false then v_bad := v_bad || ' PUBLIC 실행 항목'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' authenticated 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE';
    else
      -- 0166's guard, pinned in the DEPLOYED source now that a file has recreated the function
      if (v_src ~ 'and\s+state\s*=\s*''processing''') is distinct from true then v_bad := v_bad || ' 0166 processing 조건 없음'; end if;
      -- the lock before the write is the diagnosis' precondition (cold review #1): measured 243/2000
      -- inversions without it; pinned as ORDER here, the race itself measured by hand (see header)
      if (position('for update' in v_src) > 0 and position('for update' in v_src) < position('update billing_key_revocations' in v_src)) is distinct from true then v_bad := v_bad || ' 락이 UPDATE 앞에 없음'; end if;
      if (v_src ~ '''absent''' and v_src ~ '''not_processing''' and v_src ~ '''lease_lost''') is distinct from true then v_bad := v_bad || ' 토큰 누락'; end if;
      if (v_src ~* 'exception\s+when\s+others') is distinct from false then v_bad := v_bad || ' 삼키는 핸들러'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('rrt','0178-R6 배포 형태 — TABLE(applied, refusal)·오버로드 1개·definer·search_path·ACL(service_role만)·주석 제거 소스에 0166 processing 조건+세 토큰+UPDATE 앞의 락·삼키는 핸들러 없음; 관측한 14쌍 어느 것도 (false,NULL)/(true,토큰)이 아니다');
  else v_msg := v_bad; call _fail('rrt','0178-R6 shape+ledger', v_msg); end if;
end $$;
