-- ═══ 0155: when a billing-key revocation gives up, Sean is told — and only when it is a FAILURE ═══
--
-- Sean's ruling, verbatim (2026-08-28): 「the toss is fine, report to me.」
-- That is option ② of `docs/decisions/card-revocation-abandoned.md`: he is notified when it
-- happens, rather than being handed a CLI he has to remember to run (①) and rather than telling
-- the customer (③, whose deleted-account arm is blocked on counsel).
--
-- Nothing here fires today. Production has 0 billing keys and 0 revocation rows, and
-- `ops_flags.card_registration_live_since` is NULL, so no row can be created at all. This arms the
-- day card registration is switched on. (Those figures are READ from the decision memo's
-- 2026-08-27 production measurement; not re-measured by this file.)
--
-- ═══ WHICH ABANDONS ALERT, AND WHY THE DISTINCTION IS THE WHOLE SLICE ═══
--
-- `abandoned` is reachable FOUR ways and only TWO of them are failures. An alert that fires on the
-- other two pages a human for the system working correctly, and an alert that pages on healthy
-- behaviour is muted within a week — after which it protects nothing while everyone believes it
-- is on. So:
--
--   # | site                                             | verdict   | why
--  ---|--------------------------------------------------|-----------|------------------------------
--   1 | report_billing_key_revocation, attempts >= 8      | **ALERT** | THE give-up. Eight non-2xx
--     |                                                  |           | answers from Toss. The key is
--     |                                                  |           | most likely still LIVE and
--     |                                                  |           | nothing will try again.
--   2 | claim_…, belt 2 — the key is in `billing_keys`    | silent    | We deliberately REFUSED to
--     |                                                  |           | revoke: it is somebody's card
--     |                                                  |           | right now. Working correctly.
--   3 | claim_…, cap sweep (crashed worker at the cap)    | **ALERT** | The row is stranded. The
--     |                                                  |           | claimer's `attempts < 8` will
--     |                                                  |           | never pick it up again.
--   4 | billing_key_swap — a never-claimed key revived    | silent    | attempts = 0, nothing was ever
--     |                                                  |           | attempted, the obligation is
--     |                                                  |           | void. Working correctly.
--
-- 🔴 **THE CLASSIFICATION IS MADE AT THE SITE, NOT BY READING `last_error`.** The memo proposed
--    filtering on the reason string, and the string is genuinely distinct per site — but a check
--    that parses OUR OWN PROSE to decide whether to page is the comment-matching class wearing an
--    alerting costume: it passes or fails on how a sentence is worded, and the next person to
--    improve the wording silently changes who gets woken up. Each abandon site already KNOWS what
--    it is. Sites #1 and #3 call the emitter; sites #2 and #4 do not, and #4 is not touched by this
--    file at all. The distinction is therefore structural — a mutation that moves the emitter call
--    is the only way to break it, and suite 186 has that mutation.
--
-- ⚠ **THE ORDER INSIDE `claim_…` IS LOAD-BEARING AND IS PRESERVED EXACTLY.** Belt 2 runs BEFORE
--   the cap sweep. A row that is `processing`, expired, `attempts >= 8` AND whose key is currently
--   stored in `billing_keys` is caught by belt 2 and is therefore SILENT. That is the correct
--   answer, not an accident of ordering: whatever else is true of that row, we are refusing to
--   revoke a live card, and a refusal is not a failure. Swapping the two blocks would page on it.
--
-- ⚠ **THIS FILE DOES NOT SWALLOW.** If the notification insert raises, `claim_…` / `report_…`
--   raise with it and the tick fails. That is deliberate and it is the less-bad direction: a dead
--   revocation cron is VISIBLE (0150's `billing_key_dispatch_health` records the failed tick and
--   `due_now` climbs), while a silently-lost alert is exactly the state Sean has just ruled
--   against. Every failure mode of the insert is a schema catastrophe rather than an operational
--   condition — `ops_recipients.profile_id` has an FK to `profiles`, so a recipient always exists.
--
-- ⚠ **WHAT THIS FILE DOES NOT CLOSE, said plainly rather than left to be discovered.**
--   `ops_recipients` had ZERO ROWS in production when it was last queried (0096/0097 record it).
--   Nobody is subscribed to any event class. SQL cannot use `_shared/ops.ts`'s `OPS_PROFILE_ID`
--   env fallback, so until a row exists for `billing_key_revocation_abandoned`, the alert path
--   runs and tells NOBODY. That is a provisioning gap that predates this slice and belongs to
--   whoever flips `card_registration_live_since` — but a silent path is precisely what this file
--   exists to end, so it is made VISIBLE rather than assumed: §D adds `alert_recipients` to the
--   health view, and a dashboard reading `abandoned_failures = 3, alert_recipients = 0` says the
--   true thing out loud.

-- ═══ §A the record that someone was told ═══
--
-- One column, doing three jobs, and each of them is why it beats the alternatives:
--   · the DEDUPE key — the emitter's `alerted_at is null` predicate makes a second call a no-op by
--     construction, instead of 0118's 「a notification with this title in the last hour」 string
--     match, which is prose-matching again;
--   · the RECORD — 「Sean was told, at this time」 is a fact worth keeping in the table whose entire
--     purpose is to be the record;
--   · the DISCRIMINATOR the view needs — `state = 'abandoned' and alerted_at is not null` is
--     exactly the set of real failures, derived from which code path ran rather than from a string.
--
-- ⚠ Rows abandoned BEFORE this migration carry NULL and therefore read as benign. That is a real
--   ambiguity and it is empty in practice: the memo OBSERVED 0 abandoned rows on production on
--   2026-08-27. It is stated here rather than papered over, because a future reader of
--   `abandoned_benign` deserves to know the column cannot classify pre-0155 history.
alter table billing_key_revocations add column if not exists alerted_at timestamptz;

comment on column billing_key_revocations.alerted_at is
  '0155: when an ops recipient was notified that this revocation gave up FOR A FAILURE REASON
(report at attempts>=8, or the crashed-at-cap sweep). NULL on an abandon that is the system working
correctly — belt 2 (the key is somebody''s current card) and the never-claimed revival — so
`state = ''abandoned'' and alerted_at is not null` is the failure set and `alerted_at is null` is
the benign set. Set only by `_note_revocation_abandoned`, once, never cleared. Event class:
billing_key_revocation_abandoned. ⚠ Rows abandoned before 0155 carry NULL and cannot be classified.';


-- ═══ §B the emitter ═══
--
-- Takes an id ARRAY because one of its two callers (the cap sweep) abandons a SET in one statement.
-- Returns the number of NOTIFICATIONS actually inserted, which is 0 when nobody is subscribed —
-- the honest report, and the number §D's `alert_recipients` column exists to explain.
--
-- ⚠ It stamps `alerted_at` even when the notification count is 0. That is the right side of a real
--   trade: the alternative leaves the row un-stamped, so a later call would re-classify it and the
--   column would mean 「told」 rather than 「classified as a failure and reported」. Two different
--   propositions; the view needs the second one, and 「reported to a roster that happens to be
--   empty」 is a routing fact that `alert_recipients` reports directly instead of hiding inside a
--   NULL that also means 「benign」.
create or replace function _note_revocation_abandoned(p_ids uuid[])
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_stamped uuid[]; v_sent int := 0;
begin
  -- NULL-safe on purpose: `cardinality(null)` is NULL, and plpgsql does not take an IF on a NULL
  -- predicate — the guard would be silent in exactly the case it exists for.
  if p_ids is null or coalesce(cardinality(p_ids), 0) = 0 then return 0; end if;

  with s as (
    update billing_key_revocations r
       set alerted_at = now()
     where r.id = any(p_ids)
       and r.state = 'abandoned'      -- only a real abandon is reportable
       and r.alerted_at is null       -- and only once, structurally
    returning r.id
  )
  select coalesce(array_agg(s.id), '{}'::uuid[]) into v_stamped from s;

  if coalesce(cardinality(v_stamped), 0) = 0 then return 0; end if;

  -- The body carries NO customer identifier, no key, no amount — 0084 §E's redaction law, which
  -- exists because 0024 pushes a notification body verbatim to a lock screen and a wrong recipient
  -- id therefore publishes it. The revocation row id rides in `ref_id`, where the operator's own
  -- tooling can use it and a push cannot render it as a sentence.
  insert into notifications (profile_id, kind, title, body, ref_id)
  select rc.profile_id,
         'system'::noti_kind,
         '카드 해지 실패 — 확인 필요',
         '결제사에서 카드를 지우지 못한 채 포기했어요. 토스 콘솔에서 직접 삭제해 주세요.',
         x.id
    from unnest(v_stamped) as x(id)
    cross join ops_recipients_for('billing_key_revocation_abandoned') as rc(profile_id);
  get diagnostics v_sent = row_count;
  return v_sent;
end $$;
-- Internal only. Both callers are SECURITY DEFINER functions owned by the same role, so they reach
-- it as the owner and need no grant; `service_role` is named explicitly because it holds function
-- EXECUTE through Supabase's DEFAULT PRIVILEGES, which a `from public, anon, authenticated` revoke
-- does not touch (0118 R3S).
revoke execute on function _note_revocation_abandoned(uuid[])
  from public, anon, authenticated, service_role;

comment on function _note_revocation_abandoned(uuid[]) is
  '0155 (Sean 2026-08-28 「the toss is fine, report to me」): notify the ops roster that a billing-key
revocation gave up for a FAILURE reason. Called from the two failure sites only — never from belt 2
(the key is somebody''s current card) and never from the never-claimed revival, both of which are the
system working correctly. Stamps `alerted_at` so a second call is a no-op by construction rather than
by a title match. Returns notifications inserted; 0 means nobody is subscribed to
`billing_key_revocation_abandoned`, which is a routing gap the health view reports as
`alert_recipients`.';


-- ═══ §C the two failure sites call it ═══
--
-- Both bodies are re-created FAITHFULLY from their newest definitions (0149 for the claimer, 0141
-- for the reporter) per the §10 T4 start-from-the-deployed-body rule. The ONLY changes are the
-- emitter calls and the plumbing that collects the swept ids.

create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid(); v_swept uuid[];
begin
  -- belt 2 [0143 §B] — never hand out a key that is somebody's card right now.
  -- [0149] the token goes with the decision, or a late report resurrects a row we refused.
  -- [0155] 🔴 DELIBERATELY NOT ALERTED, and it runs FIRST on purpose. This is a refusal we chose,
  --   not a failure we suffered; the key is live at Toss because a live customer is using it. An
  --   alert here is the fastest way to get every alert in this family muted. Pinned by 0155-B2.
  update billing_key_revocations r
     set state       = 'abandoned',
         claim_token = null,
         last_error  = 'key is currently stored in billing_keys (0143 §B)',
         updated_at  = now()
   where r.state in ('pending', 'processing')
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);

  -- [0148 §B] the stranded-at-cap row, surfaced rather than left in a state nothing reads.
  -- [0149] and its token cleared — this is the ONE case where a late report is the EXPECTED
  -- event, since the row exists precisely because a worker crashed mid-flight.
  -- [0155] **ALERTED.** `attempts >= 8` means the claimer's own predicate will never pick this row
  --   up again: it is terminal by arithmetic, not by decision, and the key's state at Toss is
  --   unknown. 0148's footer recorded 「escalate is a word in a comment and not a mechanism」 —
  --   this is the mechanism.
  with swept as (
    update billing_key_revocations r
       set state       = 'abandoned',
           claim_token = null,
           last_error  = coalesce(r.last_error || ' | ', '')
                         || 'worker crashed at the attempt cap; lease expired with no report (0148)',
           updated_at  = now()
     where r.state = 'processing'
       and r.lease_until < now()
       and r.attempts >= 8
    returning r.id
  )
  select coalesce(array_agg(swept.id), '{}'::uuid[]) into v_swept from swept;
  perform _note_revocation_abandoned(v_swept);

  return query
  update billing_key_revocations r
     set state       = 'processing',
         claim_token = v_token,
         lease_until = now() + interval '5 minutes',
         attempts    = r.attempts + 1,
         updated_at  = now()
   where r.id in (
     select r2.id from billing_key_revocations r2
      where (r2.state = 'pending'
             or (r2.state = 'processing' and r2.lease_until < now()))
        and r2.attempts < 8
      order by r2.created_at
      for update skip locked
      limit greatest(1, least(p_limit, 100))
   )
  returning r.id, r.billing_key, r.claim_token;
end $$;
revoke execute on function claim_billing_key_revocations(int) from public, anon, authenticated;
grant  execute on function claim_billing_key_revocations(int) to service_role;

-- Reporting stays a COMPARE-AND-SET on the token (0141): a worker whose lease expired and was
-- reclaimed can no longer overwrite the newer result.
-- [0155] and the ONE terminal failure it can produce now reports itself.
-- ⚠ THE `is not distinct from` IS DEFENCE IN DEPTH, NOT A LIVE PROPERTY — and that is MEASURED,
--   not reasoned. Weakening it to a bare `= 'abandoned'` reddens NOTHING (battery M10, 1099/0),
--   and the reason is worth writing down rather than reshaping a pin around: `v_state` is NULL
--   only when the UPDATE matched no row, in which case `v_n = 0`, and SQL's `false AND null` is
--   `false` — a real boolean, so the IF takes its else branch and the NULL predicate is
--   unreachable through this guard. The property is therefore not separately observable through
--   any fixture the harness can build, which is a fact about the code and not a blind pin. It is
--   kept because it costs nothing and because the `v_n = 1` conjunct is exactly the kind of
--   short-circuit a later edit removes without noticing what it was holding up. Recorded as a
--   named gap in suite 186's header rather than pinned, since a pin whose mutation cannot redden
--   it is an unfalsifiable guard doing prose's job.
create or replace function report_billing_key_revocation(p_id uuid, p_ok boolean, p_error text,
                                                         p_token uuid default null)
returns boolean
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_n int; v_state text;
begin
  update billing_key_revocations
     set state = case when p_ok then 'done'
                      when attempts >= 8 then 'abandoned'
                      else 'pending' end,
         claim_token = null,
         lease_until = null,
         last_error = case when p_ok then null else p_error end,
         updated_at = now()
   where id = p_id
     -- p_token null is accepted ONLY for a row nobody holds, so the pre-0141 call shape cannot
     -- silently stomp a live lease during the deploy window.
     and (claim_token = p_token or (p_token is null and claim_token is null))
  returning state into v_state;
  get diagnostics v_n = row_count;

  -- THE give-up: eight non-2xx answers from Toss. Pinned by 0155-A1, with 0155-A2 (a success) and
  -- 0155-A3 (a retryable failure) as the controls that redden in the opposite direction.
  if v_n = 1 and v_state is not distinct from 'abandoned' then
    perform _note_revocation_abandoned(array[p_id]);
  end if;

  return v_n = 1;   -- false = your claim expired and someone else owns this row now
end $$;
revoke execute on function report_billing_key_revocation(uuid, boolean, text, uuid) from public, anon, authenticated;
grant  execute on function report_billing_key_revocation(uuid, boolean, text, uuid) to service_role;


-- ═══ §D the health view stops reporting clean BECAUSE rows were given up on ═══
--
-- 🔴 The memo's sharpest finding: `billing_key_dispatch_health.due_now` (0150) counts `pending`
--    plus expired-lease `processing` and STRUCTURALLY EXCLUDES `abandoned`. So the one
--    dashboard-shaped object in this family reports the queue clean *precisely because* rows were
--    given up on. A reader that cannot see the failure state is not a partial reader; it is a
--    false green with a column name.
--
-- ⚠ **`due_now` IS NOT TOUCHED, and that is deliberate.** Widening what an existing value MEANS
--   breaks a correct caller with no edit to the caller and no failing gate — the defect is the
--   UNCHANGED line, and no grep finds it. `due_now` keeps 0150's sentence exactly: 「rows a worker
--   will pick up on the next tick」. An abandoned row is not one of those, and folding it in would
--   turn 「0 due」 from a true statement into a lie in the other direction. The failure count is a
--   NEW column beside it. Pinned both ways: 0155-D1 asserts the failures become visible, 0155-D2
--   asserts `due_now` did not move when they did.
--
-- ⚠ Appended at the END, which is the only place `create or replace view` accepts new columns.
--   No DROP — grants are preserved, and restated below anyway (this repo does not rely on
--   preservation).
create or replace view billing_key_dispatch_health
with (security_invoker = true) as
select
  (select max(sent_at) from billing_key_dispatch_ticks)                              as last_tick_at,
  (select outcome  from billing_key_dispatch_ticks order by sent_at desc limit 1)    as last_outcome,
  (select max(sent_at) from billing_key_dispatch_ticks where outcome = 'accepted')   as last_accepted_at,
  (select max(sent_at) from billing_key_dispatch_ticks where outcome = 'rejected')   as last_rejected_at,
  count(*) filter (where outcome = 'idle')        as idle_24h,
  count(*) filter (where outcome = 'deferred')    as deferred_24h,
  count(*) filter (where outcome = 'sent')        as sent_24h,
  count(*) filter (where outcome = 'accepted')    as accepted_24h,
  count(*) filter (where outcome = 'rejected')    as rejected_24h,
  count(*) filter (where outcome = 'failed')      as failed_24h,
  count(*) filter (where outcome = 'no_response') as no_response_24h,
  coalesce(sum(claimed_count) filter (where outcome = 'accepted'), 0) as claimed_24h,
  (select count(*) from billing_key_revocations
    where attempts < 8
      and (state = 'pending' or (state = 'processing' and lease_until < now())))     as due_now,
  -- [0155] the three columns the memo's finding demands, and none of them changes a word above.
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and alerted_at is not null)                            as abandoned_failures,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and alerted_at is null)                                as abandoned_benign,
  (select count(*) from ops_recipients
    where event_class = 'billing_key_revocation_abandoned' and active)               as alert_recipients
from billing_key_dispatch_ticks
where sent_at > now() - interval '24 hours';

revoke all on billing_key_dispatch_health from public, anon, authenticated;
grant select on billing_key_dispatch_health to service_role;

comment on view billing_key_dispatch_health is
'0150 + 0155: the one-row read of revocation dispatch health. `rejected_24h > 0` means the endpoint
is refusing our cron key and NOTHING is being revoked, which before 0150 was indistinguishable from
`idle_24h > 0` (the queue was empty and all is well). `last_tick_at is null` is a third answer again:
no tick at all, i.e. the cron itself is not running.
[0155] `due_now` keeps its 0150 meaning EXACTLY — rows a worker will pick up next tick — and
deliberately still excludes `abandoned`. The give-ups are reported beside it instead:
`abandoned_failures` = abandons a human was told about (the report at attempts>=8, the crashed-at-cap
sweep) · `abandoned_benign` = abandons that are the system working correctly (the key is somebody''s
current card; a never-claimed key revived) · `alert_recipients` = how many people are actually
subscribed to `billing_key_revocation_abandoned`. ⚠ `abandoned_failures > 0` with
`alert_recipients = 0` means the failures happened and NOBODY WAS TOLD — read those two together or
the first one is not the reassurance it looks like.';


-- ═══ §E the event class joins the routing vocabulary ═══
--
-- 0084 §E deliberately put NO check constraint on `ops_recipients.event_class` — a constrained
-- vocabulary makes adding an emitter a migration, and a typo already degrades safely to zero rows.
-- The vocabulary lives in the table comment instead, and that comment says it is「the contract」.
-- So the class is APPENDED to it rather than the comment being restated (a restatement drifts, and
-- 0118 added `club_fee_mint_failed` without one, which is how a contract stops being one).
do $$
declare v_c text;
begin
  select obj_description('ops_recipients'::regclass, 'pg_class') into v_c;
  if v_c is null or length(v_c) = 0 then
    raise exception '0155 §E: ops_recipients carries no comment — refusing to invent the contract';
  end if;
  if position('billing_key_revocation_abandoned' in v_c) = 0 then
    execute format('comment on table ops_recipients is %L', v_c || chr(10) ||
      '  billing_key_revocation_abandoned — [0155, Sean 2026-08-28] a Toss billing-key revocation ' ||
      'gave up for a FAILURE reason (8 non-2xx answers, or a worker crashed at the attempt cap). ' ||
      'The key is probably still LIVE at the PG and must be deleted by hand in the Toss console. ' ||
      'NOT emitted for the two correct give-ups (the key is somebody''s current card; a ' ||
      'never-claimed key became current again). Emitted by _note_revocation_abandoned.');
  end if;
end $$;


-- ═══ VERIFY ═══
--
-- ⚠ NO `prosrc` GREPS. This file names every one of its own tokens — `_note_revocation_abandoned`,
--   `alerted_at`, `abandoned_failures` — inside the prose above, and a comment that quotes the code
--   it describes matches every grep that hunts for that code. Every arm below reads CATALOG state
--   or PRIVILEGE answers, which this file's paragraphs cannot forge.
do $$
declare
  v_typ text; v_sec boolean; v_cfg text[]; v_bad text := '';
  v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_cols text[];
begin
  -- ① the column
  select format_type(a.atttypid, null) into v_typ
    from pg_attribute a
   where a.attrelid = 'billing_key_revocations'::regclass
     and a.attname = 'alerted_at' and a.attnum > 0 and not a.attisdropped;
  if v_typ is distinct from 'timestamp with time zone' then
    v_bad := v_bad || ' alerted_at=' || coalesce(v_typ, 'ABSENT');
  end if;

  -- ② the emitter's own shape — prosecdef, in-body search_path, and reachable by NOBODY.
  --    A guard's PRECONDITIONS are checked here and pinned standing by 0155-S1; a property checked
  --    only at apply is protected exactly until someone recreates the function.
  select p.prosecdef, p.proconfig into v_sec, v_cfg
    from pg_proc p where p.oid = 'public._note_revocation_abandoned(uuid[])'::regprocedure;
  if v_sec is not true then v_bad := v_bad || ' emitter-not-definer'; end if;
  -- Same tolerant form as 98 H1, so a formatting difference in proconfig cannot abort an apply
  -- over a function that is in fact sealed.
  if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%' then
    v_bad := v_bad || ' emitter-no-inbody-search_path';
  end if;
  select has_function_privilege('public', o, 'execute'),
         has_function_privilege('anon', o, 'execute'),
         has_function_privilege('authenticated', o, 'execute'),
         has_function_privilege('service_role', o, 'execute')
    into v_pub, v_anon, v_auth, v_svc
    from (select 'public._note_revocation_abandoned(uuid[])'::regprocedure as o) t;
  if v_pub is not false or v_anon is not false or v_auth is not false or v_svc is not false then
    v_bad := v_bad || ' emitter-EXECUTABLE(pub=' || coalesce(v_pub::text,'∅')
             || ' anon=' || coalesce(v_anon::text,'∅')
             || ' auth=' || coalesce(v_auth::text,'∅')
             || ' svc='  || coalesce(v_svc::text,'∅') || ')';
  end if;

  -- ③ the two recreated definers kept their seals. A `create or replace` on an absent-function
  --    path is a plain CREATE and is born PUBLIC-executable (0116:636), so this is checked rather
  --    than assumed even though both files above restate the ACL.
  select has_function_privilege('public', o, 'execute'),
         has_function_privilege('anon', o, 'execute'),
         has_function_privilege('authenticated', o, 'execute'),
         has_function_privilege('service_role', o, 'execute')
    into v_pub, v_anon, v_auth, v_svc
    from (select 'public.claim_billing_key_revocations(int)'::regprocedure as o) t;
  if v_pub is not false or v_anon is not false or v_auth is not false or v_svc is not true then
    v_bad := v_bad || ' claim-ACL-wrong';
  end if;
  select has_function_privilege('public', o, 'execute'),
         has_function_privilege('anon', o, 'execute'),
         has_function_privilege('authenticated', o, 'execute'),
         has_function_privilege('service_role', o, 'execute')
    into v_pub, v_anon, v_auth, v_svc
    from (select 'public.report_billing_key_revocation(uuid,boolean,text,uuid)'::regprocedure as o) t;
  if v_pub is not false or v_anon is not false or v_auth is not false or v_svc is not true then
    v_bad := v_bad || ' report-ACL-wrong';
  end if;

  -- ④ the view gained exactly the three columns and kept `due_now`.
  select coalesce(array_agg(a.attname::text order by a.attnum), '{}') into v_cols
    from pg_attribute a
   where a.attrelid = 'billing_key_dispatch_health'::regclass
     and a.attnum > 0 and not a.attisdropped;
  if not ('due_now' = any(v_cols))            then v_bad := v_bad || ' view-lost-due_now'; end if;
  if not ('abandoned_failures' = any(v_cols)) then v_bad := v_bad || ' view-no-abandoned_failures'; end if;
  if not ('abandoned_benign' = any(v_cols))   then v_bad := v_bad || ' view-no-abandoned_benign'; end if;
  if not ('alert_recipients' = any(v_cols))   then v_bad := v_bad || ' view-no-alert_recipients'; end if;

  -- ⑤ the routing vocabulary carries the class.
  if position('billing_key_revocation_abandoned' in
              coalesce(obj_description('ops_recipients'::regclass, 'pg_class'), '')) = 0 then
    v_bad := v_bad || ' event-class-not-in-contract';
  end if;

  if v_bad <> '' then
    raise exception '0155 VERIFY:%', v_bad;
  end if;
  raise notice '0155 VERIFY ok';
end $$;
