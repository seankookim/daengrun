-- ═══ 0166: the give-up is REACHABLE, REPORTABLE and CLASSIFIED ═══
--
-- Closes codex's four SQL findings on 0155 (`docs/decisions/2026-08-28-codex-verdicts.md`
-- §「0155 — REJECT, 6 findings」). Findings 5 and 6 are suite work and land in
-- `tests/186_revocation_abandoned_alert_suite.sql` in this same slice.
--
-- 🔴 **MEASURED BEFORE BUILT.** 0148/0149/0155 and then 0157 all touched this surface after codex
--    wrote the memo, so every finding was re-read against the LATEST definition on trunk rather
--    than against the memo's line numbers. 0157's own header says it: 「`claim_billing_key_revocations`
--    and `report_billing_key_revocation` (←0155) are NOT touched」 — and it does not touch
--    `dispatch_billing_key_revocations` (←0150:295) or the health view (←0155:292) either. The
--    ledger, each row read from the deployed end state:
--
--    | # | finding | status | evidence |
--    |---|---|---|---|
--    | 1 | dispatcher counts only `attempts < 8`, records `idle`, never invokes the worker, so the cap sweep inside the claimer never runs | **STILL OPEN → BUILT (§C, §F)** | last def `0150:295-311`; the count at `0150:304` is still `attempts < 8` and the sweep still lives only inside `claim_billing_key_revocations` (`0155:190-201`) |
--    | 2 | empty alert roster is recorded as alerted — `alerted_at` stamps with zero notifications and the dedupe then blocks retry forever | **STILL OPEN → BUILT (§D, §F)** | last def `0155:106-142`; the stamping UPDATE at `0155:115-124` runs before the insert and is not conditioned on it |
--    | 3 | late report with a NULL token can rewrite a TERMINAL row (`abandoned → done`) because the UPDATE has no state gate and NULL matches a cleared `claim_token` | **STILL OPEN → BUILT (§E)** | last def `0155:240-268`; the WHERE is `id = p_id and (claim_token = p_token or (p_token is null and claim_token is null))` and nothing else |
--    | 4 | pre-0155 abandoned rows (NULL `alerted_at`) classify as `abandoned_benign` forever — absence of classification fails OPEN | **STILL OPEN → BUILT (§A, §G)** | last def `0155:292-317`; `abandoned_benign` is `state = 'abandoned' and alerted_at is null`, which is also every unclassifiable row |
--    | 5 | deleting the reporter's `claim_token = null` leaves the whole suite green (A1 never reads the token) | **STILL OPEN → suite repair** | `186:121-135` reads state, `alerted_at` and the notification, never `claim_token`. Arm added to `0155-A1` |
--    | 6 | the cap sweep's `lease_until < now()` guard has no live-lease control | **STILL OPEN → suite repair** | `186:196-218` plants one expired-lease row only. Live-lease control row added to `0155-B1` |
--
-- ⚠ **NOTHING HERE IS BREACHED TODAY AND SAYING SO PRECISELY IS PART OF THE FIX.**
--   `ops_flags.card_registration_live_since` is NULL, `billing_keys` has 0 rows and
--   `billing_key_revocations` has 0 rows. Every one of these arms when the registration flag goes
--   live. They are gates on that flip (the verdicts doc says so), not an incident.
--
-- ⚠ **`due_now` IS STILL NOT WIDENED, and finding 1 is closed WITHOUT widening it.** Folding
--   stranded rows into `due_now` would change what an existing value MEANS and break every correct
--   reader with no edit to the reader — the §④ law. Instead the dispatcher SWEEPS before it counts,
--   so by the time the count runs the stranded row is `abandoned` and `idle` is a true statement
--   again rather than a lie. 0155-D2 (「due_now did not move」) stays green by construction.
--
-- ⚠ **AND THE SWEEP MOVES RATHER THAN BEING DUPLICATED.** Counting the stranded row in the
--   dispatcher would have made the alert depend on the WORKER being up — and the row exists
--   precisely because a worker crashed. The sweep is lifted into one function called by BOTH the
--   claimer (unchanged behaviour, 0155-B1/B4 still own the ordering) and the dispatcher (which runs
--   on cron whatever the worker is doing). One predicate, two callers, no drift.


-- ═══ §A finding 4: the classification is a COLUMN, so absence can fail CLOSED ═══
--
-- 0155 used `alerted_at is null` as the benign discriminator, which conflates three different
-- sentences: 「this abandon was the system working correctly」, 「this abandon is a failure nobody
-- has been told about yet」 and 「this row predates the column and cannot be classified at all」.
-- One NULL cannot carry three meanings, and the one it silently chose is the reassuring one.
--
-- So: an explicit class, written by whichever site abandoned the row, and NULL means UNKNOWN —
-- counted in its own column, never in `abandoned_benign`.
alter table billing_key_revocations add column if not exists abandon_class text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'billing_key_revocations_abandon_class_chk') then
    alter table billing_key_revocations
      add constraint billing_key_revocations_abandon_class_chk
      check (abandon_class is null or abandon_class in ('failure', 'benign'));
  end if;
end $$;

comment on column billing_key_revocations.abandon_class is
  '0166 (codex 0155 #4): WHY this row was abandoned, written by the site that abandoned it.
`failure` = we gave up on a key that is most likely still live at the PG (the report at
attempts>=8, the crashed-at-cap sweep) — a human must be told. `benign` = the system working
correctly (belt 2: the key is somebody''s current card · the never-claimed revival). NULL = this row
was abandoned before 0166 and CANNOT be classified — it is counted as `abandoned_unclassified` and
never as benign, because an absent classification failing open is the defect this column closes.
⚠ `alerted_at` no longer classifies anything; it now means only 「an ops recipient was actually
notified」, which is what makes an empty-roster retry possible.';


-- ═══ §B finding 1, half one: the cap sweep becomes reachable from more than the worker ═══
--
-- Lifted VERBATIM out of `claim_billing_key_revocations` (0155:190-201) — same predicate, same
-- `last_error` text, same emitter call — plus the `abandon_class` write §A introduces. The claimer
-- calls it exactly where the inline block used to sit, so 0155-B1 (the sweep pages) and 0155-B4
-- (belt 2 runs FIRST) are pinning the same ordering they were written for.
--
-- ⚠ IT RETURNS THE COUNT SWEPT rather than void, so a caller — and a pin — can tell 「swept none」
--   from 「did not run」. Those are the two states a battery table cannot otherwise distinguish.
create or replace function _sweep_stranded_billing_key_revocations()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_swept uuid[];
begin
  with swept as (
    update billing_key_revocations r
       set state         = 'abandoned',
           claim_token   = null,
           abandon_class = 'failure',
           last_error    = coalesce(r.last_error || ' | ', '')
                           || 'worker crashed at the attempt cap; lease expired with no report (0148)',
           updated_at    = now()
     where r.state = 'processing'
       and r.lease_until < now()
       and r.attempts >= 8
    returning r.id
  )
  select coalesce(array_agg(swept.id), '{}'::uuid[]) into v_swept from swept;

  perform _note_revocation_abandoned(v_swept);
  return coalesce(cardinality(v_swept), 0);
end $$;
-- Internal only, and `service_role` is named explicitly because it holds function EXECUTE through
-- Supabase's DEFAULT PRIVILEGES, which a `from public, anon, authenticated` revoke does not touch
-- (0118 R3S). Both callers are definers owned by this role and reach it as the owner.
revoke execute on function _sweep_stranded_billing_key_revocations()
  from public, anon, authenticated, service_role;

comment on function _sweep_stranded_billing_key_revocations() is
  '0166 (codex 0155 #1): abandon every row a crashed worker stranded at the attempt cap
(`processing`, lease expired, `attempts >= 8`) and report each one. Lifted out of
`claim_billing_key_revocations` so `dispatch_billing_key_revocations` can run it too — the stranded
row exists BECAUSE a worker crashed, so an escalation that only fires when a worker is healthy is
the same invisibility 0148 was written to end. Returns the number of rows swept.';


-- ═══ §C finding 2: `alerted_at` means TOLD, and an empty roster stays retryable ═══
--
-- 0155 stamped `alerted_at` even when zero notifications were inserted, and argued for it: the
-- column had to mean 「classified as a failure and reported」 or the view could not discriminate.
-- **The premise was the problem, not the conclusion.** §A gives the view a column that carries the
-- classification, so `alerted_at` is free to mean the one thing an operator actually needs it to
-- mean — somebody was told — and the dedupe guard stops doubling as a permanent gag.
--
-- The consequence codex named: with `ops_recipients` empty (it WAS empty in production the last
-- time anyone looked, 0096/0097 and 0155-D3), every failure stamped itself as alerted, and
-- provisioning a recipient afterwards sent nothing, forever. The retry now costs one statement in
-- §F's dispatcher, which is already on cron.
--
-- ⚠ THE GATING UPDATE STAYS A SINGLE UPDATE, and that is a concurrency property rather than a
--   style: it is what makes the dedupe atomic. Two callers racing the same id both block on the
--   row; whichever commits with a non-zero send stamps `alerted_at`, and the other's re-evaluated
--   predicate then excludes it. A SELECT-then-UPDATE would notify twice.
-- ⚠ It therefore re-writes `abandon_class = 'failure'` on every retry tick while the roster is
--   empty. That is a deliberate trade — one no-op-shaped write per unreported row per ten minutes,
--   against losing atomic dedupe. A backlog of unreported failures is by definition tiny and is
--   itself the alarm.
create or replace function _note_revocation_abandoned(p_ids uuid[])
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_marked uuid[]; v_sent int := 0;
begin
  -- NULL-safe on purpose: `cardinality(null)` is NULL, and plpgsql does not take an IF on a NULL
  -- predicate — the guard would be silent in exactly the case it exists for.
  if p_ids is null or coalesce(cardinality(p_ids), 0) = 0 then return 0; end if;

  with s as (
    update billing_key_revocations r
       set abandon_class = 'failure'
     where r.id = any(p_ids)
       and r.state = 'abandoned'                          -- only a real abandon is reportable
       and r.alerted_at is null                           -- and only once TOLD, structurally
       and r.abandon_class is distinct from 'benign'      -- never re-label a correct refusal
    returning r.id
  )
  select coalesce(array_agg(s.id), '{}'::uuid[]) into v_marked from s;

  if coalesce(cardinality(v_marked), 0) = 0 then return 0; end if;

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
    from unnest(v_marked) as x(id)
    cross join ops_recipients_for('billing_key_revocation_abandoned') as rc(profile_id);
  get diagnostics v_sent = row_count;

  -- 🔴 THE STAMP IS CONDITIONED ON A DELIVERY. `v_sent = 0` means nobody is subscribed, which is a
  --    routing gap and not a report — leaving `alerted_at` NULL is what lets §F's tick try again
  --    once somebody is provisioned. `> 0` rather than `is not null`: `get diagnostics` always
  --    yields a number here, and an IF on it is safe.
  if v_sent > 0 then
    update billing_key_revocations r
       set alerted_at = now()
     where r.id = any(v_marked)
       and r.alerted_at is null;
  end if;

  return v_sent;
end $$;
revoke execute on function _note_revocation_abandoned(uuid[])
  from public, anon, authenticated, service_role;

comment on function _note_revocation_abandoned(uuid[]) is
  '0155 (Sean 2026-08-28 「the toss is fine, report to me」), amended by 0166 (codex 0155 #2):
classify a give-up as `abandon_class = ''failure''` and notify the ops roster. Called from the two
failure sites only — never from belt 2 (the key is somebody''s current card) and never from the
never-claimed revival, both of which are the system working correctly. **Stamps `alerted_at` ONLY
when a notification was actually inserted**, so an empty roster leaves the row retryable and
`dispatch_billing_key_revocations` re-offers it every tick; before 0166 an empty roster recorded the
row as alerted and the dedupe blocked it forever. Returns notifications inserted; 0 means nobody is
subscribed to `billing_key_revocation_abandoned`, which the health view reports as
`alert_recipients` and `abandoned_unreported`.';


-- ═══ §D the claimer — 0155's body, with the sweep called rather than inlined ═══
--
-- Re-created from `0155:165-222` (§10 T4: start from the newest definition). TWO changes and
-- nothing else: belt 2 writes its classification, and the cap-sweep block becomes a call to §B.
-- The ORDER is untouched and is pinned by 0155-B4 — belt 2 runs first, so a row in both sets is a
-- refusal (silent) rather than a page.
create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid();
begin
  -- belt 2 [0143 §B] — never hand out a key that is somebody's card right now.
  -- [0149] the token goes with the decision, or a late report resurrects a row we refused.
  -- [0155] 🔴 DELIBERATELY NOT ALERTED, and it runs FIRST on purpose. This is a refusal we chose,
  --   not a failure we suffered; the key is live at Toss because a live customer is using it. An
  --   alert here is the fastest way to get every alert in this family muted. Pinned by 0155-B2.
  -- [0166] and it now SAYS so in a column, instead of being inferred from an absent timestamp.
  update billing_key_revocations r
     set state         = 'abandoned',
         claim_token   = null,
         abandon_class = 'benign',
         last_error    = 'key is currently stored in billing_keys (0143 §B)',
         updated_at    = now()
   where r.state in ('pending', 'processing')
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);

  -- [0148 §B] the stranded-at-cap row, surfaced rather than left in a state nothing reads.
  -- [0155] ALERTED — `attempts >= 8` means the claimer's own predicate will never pick this row up
  --   again: it is terminal by arithmetic, not by decision, and the key's state at Toss is unknown.
  -- [0166] the block moved to `_sweep_stranded_billing_key_revocations()` unchanged, so the cron
  --   can run it when no worker is alive to call this function at all (codex 0155 #1).
  perform _sweep_stranded_billing_key_revocations();

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


-- ═══ §E finding 3: a report can only land on a row somebody is actually holding ═══
--
-- Re-created from `0155:240-268`. ONE conjunct added — and it is the party gate, so it is written
-- FIRST: `state = 'processing'` means 「this row is out with a worker」. Without it the WHERE
-- admitted `p_token is null and claim_token is null`, which is TRUE of every terminal row in the
-- table: `done`, `failed` and every `abandoned` row, all of which have had their token cleared
-- (0149). A three-arg call — the pre-0141 shape, still exercised in this repo's own suites — could
-- therefore flip an `abandoned` row to `done` while the key is live at Toss, writing into the
-- ledger that a key was destroyed when the system had deliberately refused to destroy it, or when
-- it had given up. `done` is terminal, so the reason goes with it.
--
-- ⚠ THE CAP-SWEEP ROW IS THE CASE THIS PROTECTS, not an edge case: 0148's whole point is that the
--   row exists because a worker crashed mid-flight, so a LATE report is the EXPECTED event there.
--   0149 cleared its token precisely so the late report could not land — and then this WHERE
--   admitted it anyway through the NULL arm, which is 0149's fix undone by its neighbour.
--
-- ⚠ `is not distinct from` on the state read below is DEFENCE IN DEPTH, not a live property — see
--   suite 186's header for the measurement (battery M10) and why no pin is written for it.
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
     -- [0166] party gate FIRST: only a row that is out with a worker can be reported on. A
     -- terminal row holds no claim, so nobody may close it a second time.
     and state = 'processing'
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


-- ═══ §F finding 1 + finding 2: the tick sweeps, and it re-offers what nobody was told ═══
--
-- Re-created from `0150:295-372` (§10 T4). TWO statements added, both BEFORE the `v_due = 0` early
-- return, and the position is load-bearing for exactly the reason 0150 wrote about the reconcile
-- call: put either below the return and the work only happens on a tick that already had something
-- to do — which, on a queue whose only remaining row is the stranded one, is a tick that never
-- comes. That is the whole finding.
--
-- ⚠ `v_due` KEEPS 0150's PREDICATE, CHARACTER FOR CHARACTER. The sweep runs first, so by the time
--   the count executes the stranded row is `abandoned` and genuinely not due — `idle` becomes a
--   true statement instead of a lie. Widening the count instead would have changed what `due_now`
--   and `due_count` MEAN for every existing reader (§④) and would still have left the escalation
--   dependent on a worker that is, by construction, dead.
create or replace function dispatch_billing_key_revocations()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_due int; v_secret text; v_cfg jsonb; v_url text; v_key text; v_req bigint;
begin
  perform reconcile_billing_key_dispatch_ticks();

  -- [0166 · codex 0155 #1] the stranded-at-cap rows, swept by the CRON rather than only by a
  -- worker the cron might never invoke.
  perform _sweep_stranded_billing_key_revocations();

  -- [0166 · codex 0155 #2] every failure nobody has been told about, re-offered. With an empty
  -- roster the emitter sends nothing and leaves `alerted_at` NULL, so this picks the row up again
  -- on the next tick — and the tick after a recipient is finally provisioned is the one that
  -- delivers. `= 'failure'` and not `is not distinct from`: a NULL class is a PRE-0166 row we
  -- cannot classify (§A), and paging on unclassifiable history is how this alert gets muted.
  perform _note_revocation_abandoned(array(
    select r.id from billing_key_revocations r
     where r.state = 'abandoned'
       and r.abandon_class = 'failure'
       and r.alerted_at is null
     order by r.updated_at
     limit 100));

  select count(*)::int into v_due
    from billing_key_revocations
   where attempts < 8
     and (state = 'pending' or (state = 'processing' and lease_until < now()));

  if v_due = 0 then
    -- HEALTHY, and recorded as such. This row is the whole difference between 「the queue was
    -- empty」 and 「the endpoint is refusing us」, and it costs one insert per ten minutes.
    insert into billing_key_dispatch_ticks (outcome, due_count, resolved_at)
    values ('idle', 0, now());
    return 0;
  end if;

  begin
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'charge_dispatch';
  exception when others then
    raise notice 'dispatch_billing_key_revocations: vault unavailable (%) — % row(s) deferred', sqlerrm, v_due;
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('deferred', v_due, left('vault unavailable: ' || sqlerrm, 300), now());
    return 0;
  end;
  if v_secret is null then
    raise notice 'dispatch_billing_key_revocations: charge_dispatch secret absent — % row(s) deferred', v_due;
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('deferred', v_due, 'charge_dispatch secret absent', now());
    return 0;
  end if;

  -- [0150] 0141 cast this unguarded, so a malformed secret raised inside a cron tick and the only
  -- record was a `cron.job_run_details` row nobody reads.
  begin
    v_cfg := v_secret::jsonb;
  exception when others then
    raise notice 'dispatch_billing_key_revocations: charge_dispatch secret is not JSON — % row(s) deferred', v_due;
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('deferred', v_due, 'charge_dispatch secret is not JSON', now());
    return 0;
  end;

  v_url := v_cfg->>'url';
  v_key := v_cfg->>'cron_key';
  if v_url is null or v_key is null then
    raise notice 'dispatch_billing_key_revocations: charge_dispatch secret needs {"url":…,"cron_key":…}';
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('deferred', v_due, 'charge_dispatch secret needs url + cron_key', now());
    return 0;
  end if;

  -- 🔴 THE RETURN IS CAPTURED (0150). pg_net keys `net._http_response` by exactly this value, so
  --    discarding it discards the only handle on the verdict.
  v_req := net.http_post(
    url := v_url || '/revoke-billing-keys',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Key', v_key),
    body := jsonb_build_object('mode', 'batch')
  );

  if v_req is null then
    -- pg_net gave us nothing to track. Recorded as a failure and NOT as a send: a `sent` row with
    -- no request id can never be reconciled, so it would sit at 「awaiting verdict」 forever.
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('failed', v_due, 'net.http_post returned no request id', now());
    return v_due;
  end if;

  insert into billing_key_dispatch_ticks (outcome, due_count, request_id)
  values ('sent', v_due, v_req);
  return v_due;
end $$;
revoke execute on function dispatch_billing_key_revocations() from public, anon, authenticated;
grant  execute on function dispatch_billing_key_revocations() to service_role;
-- ⚠ NO CRON CHANGE. The signature is unchanged, so 0138 §G's entry — re-registered and READ BACK
--   by 0157 §A — now sweeps and retries as well as dispatching.


-- ═══ §G the never-claimed revival says what it is ═══
--
-- Re-created from `0157:249-321` (the newest definition — 0148's body with its three enqueues
-- routed through 0157's merge primitive). ONE change: the revival's abandon carries
-- `abandon_class = 'benign'`. Without it the single most ordinary abandon in the product — a
-- 카드 바꾸기 that races itself — would land in `abandoned_unclassified` forever and the new column
-- would report healthy behaviour as unknown, which is how a dashboard column gets ignored.
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text, refusal text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean; v_exists boolean; v_claimed boolean;
begin
  select (deleted_at is null), true into v_alive, v_exists
    from profiles where id = p_profile for update;

  if coalesce(v_alive, false) = false then
    -- [0141 §A] the tombstone race: refuse AND record, in one transaction.
    perform enqueue_billing_key_revocation_row(
      case when coalesce(v_exists, false) then p_profile else null end,
      p_billing_key, 'orphaned_by_deletion', null);
    return query select false, null::text, 'deleted_account'::text;
    return;
  end if;

  -- [0148] the rollout gate, and the flag row is LOCKED before it is read: a close can no longer
  -- land between the read and the store. `ops_flags` is a singleton; an absent row reads CLOSED.
  perform 1 from ops_flags for update;

  -- [0143 §A] REFUSE **AND ENQUEUE** — Toss has already issued the key by the time we are called,
  -- so a bare refusal would strand exactly the credential the gate was closed to prevent.
  if not card_registration_live() then
    perform enqueue_billing_key_revocation_row(p_profile, p_billing_key, 'gate_closed', null);
    return query select false, null::text, 'gate_closed'::text;
    return;
  end if;

  -- [0148 belt 1] was this key EVER handed to a worker? The blocking `for update` is unchanged and
  -- still load-bearing — see 0143 §A for why its mode differs from the claim's `skip locked`.
  perform 1 from billing_key_revocations where billing_key = p_billing_key for update;

  select exists (
    select 1 from billing_key_revocations
     where billing_key = p_billing_key
       and (attempts > 0 or state = 'processing')
  ) into v_claimed;

  if v_claimed then
    -- Permanently untrustworthy: we cannot know whether the DELETE landed. Refusing costs one
    -- re-tap; accepting costs a card that silently cannot be charged.
    return query select false, null::text, 'key_busy'::text;
    return;
  end if;

  select billing_key into v_prev from billing_keys where profile_id = p_profile;

  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (p_profile, p_billing_key, p_card, now())
  on conflict (profile_id) do update
    set billing_key = excluded.billing_key,
        card        = excluded.card,
        updated_at  = now();

  if v_prev is not null and v_prev is distinct from p_billing_key then
    perform enqueue_billing_key_revocation_row(p_profile, v_prev, 'replaced', null);
  end if;

  -- [0148] Only the never-claimed rows are cancellable, and the token goes with them.
  -- [0166] and this is the OTHER benign abandon — nothing was ever attempted, so there is nothing
  -- to escalate. Pinned silent by 0155-B3; classified here so the view can say so positively.
  update billing_key_revocations
     set state         = 'abandoned',
         claim_token   = null,
         abandon_class = 'benign',
         last_error    = 'key became current again before any worker claimed it (0148)',
         updated_at    = now()
   where billing_key = p_billing_key
     and state = 'pending'
     and attempts = 0;

  return query select true, v_prev, null::text;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant  execute on function billing_key_swap(uuid, text, jsonb) to service_role;


-- ═══ §H the view splits three ways, and the unknown bucket is its own column ═══
--
-- Re-created from `0155:292-317`. `due_now` and every tick column are CHARACTER-IDENTICAL; only the
-- two abandon columns change meaning, and they change in the direction that fails closed.
--
-- ⚠ THIS DOES WIDEN NOTHING AND NARROWS ONE THING, deliberately: `abandoned_benign` used to count
--   every unclassifiable row and now counts only rows a site positively called benign. That is the
--   finding. The rows it stops counting are not lost — they surface in `abandoned_unclassified`,
--   which is a NEW column and therefore breaks no reader.
-- ⚠ `abandoned_failures` keys on the CLASS, not on `alerted_at`: a give-up is a failure whether or
--   not anybody was told, and conflating the two is what made `alerted_at` unretryable (§C).
--   `abandoned_unreported` is the pair that must be read with it — failures nobody has been told
--   about, which with an empty roster is all of them.
-- ⚠ New columns are APPENDED, the only place `create or replace view` accepts them.
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
  -- [0166] classification, not timestamp-inference.
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'failure')                         as abandoned_failures,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'benign')                          as abandoned_benign,
  (select count(*) from ops_recipients
    where event_class = 'billing_key_revocation_abandoned' and active)               as alert_recipients,
  -- [0166] the two the old shape could not say.
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class is null)                             as abandoned_unclassified,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'failure'
      and alerted_at is null)                                                        as abandoned_unreported
from billing_key_dispatch_ticks
where sent_at > now() - interval '24 hours';

revoke all on billing_key_dispatch_health from public, anon, authenticated;
grant select on billing_key_dispatch_health to service_role;

comment on view billing_key_dispatch_health is
'0150 + 0155 + 0166: the one-row read of revocation dispatch health. `rejected_24h > 0` means the
endpoint is refusing our cron key and NOTHING is being revoked, which before 0150 was
indistinguishable from `idle_24h > 0` (the queue was empty and all is well). `last_tick_at is null`
is a third answer again: no tick at all, i.e. the cron itself is not running.
`due_now` keeps its 0150 meaning EXACTLY — rows a worker will pick up next tick — and deliberately
still excludes `abandoned`; 0166 closed the stranded-row finding by SWEEPING before the count rather
than by widening it.
[0166] the abandon columns read `abandon_class`, which the abandoning site writes, instead of
inferring from `alerted_at`: `abandoned_failures` = give-ups on a key that is probably still live ·
`abandoned_benign` = the system working correctly (belt 2, the never-claimed revival) ·
`abandoned_unclassified` = rows abandoned before 0166, which CANNOT be classified and are never
counted benign · `abandoned_unreported` = failures nobody has been told about yet, which is what an
empty roster produces and what the tick retries. ⚠ Read `abandoned_failures` with
`alert_recipients` and `abandoned_unreported` together, or the first one is not the reassurance it
looks like.';


-- ═══ VERIFY — read the objects back, never the statements' reports ═══
--
-- Exact booleans and `is distinct from` throughout: plpgsql skips an IF on a NULL predicate
-- silently, and every arm here exists to notice something MISSING — the one state a NULL-collapsing
-- guard is blind to.
do $$
declare v_bad text := ''; v_typ text; v_sec boolean; v_cfg text[]; v_n int;
        v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
begin
  -- §A the column and its constraint
  select t.typname into v_typ
    from pg_attribute a join pg_type t on t.oid = a.atttypid
   where a.attrelid = 'billing_key_revocations'::regclass
     and a.attname = 'abandon_class' and a.attnum > 0 and not a.attisdropped;
  if v_typ is distinct from 'text' then
    v_bad := v_bad || ' abandon_class=' || coalesce(v_typ, 'ABSENT');
  end if;
  select count(*)::int into v_n from pg_constraint
   where conname = 'billing_key_revocations_abandon_class_chk';
  if v_n is distinct from 1 then v_bad := v_bad || ' abandon_class-CHECK-absent'; end if;

  -- §B the new helper's own envelope — a property checked only here is protected exactly until
  -- somebody recreates the function, which is why 196's 0166-F0 pins it standing as well.
  select p.prosecdef, p.proconfig into v_sec, v_cfg
    from pg_proc p
   where p.oid = 'public._sweep_stranded_billing_key_revocations()'::regprocedure;
  if v_sec is not true then v_bad := v_bad || ' sweep-NOT-definer'; end if;
  if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%' then
    v_bad := v_bad || ' sweep-NO-inbody-search_path';
  end if;
  -- FOUR roles, not just PUBLIC. Measured 2026-09-15 while mutation-testing this very block: a
  -- plant of `grant execute … to authenticated` did NOT abort the apply, because `authenticated`
  -- holding a privilege does not make the PUBLIC pseudo-role hold it — the arm's sentence
  -- (「nobody can execute this」) was broader than what it checked. Suite 196's 0166-F0 caught it
  -- and this arm did not; both now check the same four roles.
  select has_function_privilege('public', o, 'execute'),
         has_function_privilege('anon', o, 'execute'),
         has_function_privilege('authenticated', o, 'execute'),
         has_function_privilege('service_role', o, 'execute')
    into v_pub, v_anon, v_auth, v_svc
    from (select 'public._sweep_stranded_billing_key_revocations()'::regprocedure as o) t;
  if v_pub  is not false then v_bad := v_bad || ' sweep-PUBLIC-executable'; end if;
  if v_anon is not false then v_bad := v_bad || ' sweep-anon-executable'; end if;
  if v_auth is not false then v_bad := v_bad || ' sweep-authenticated-executable'; end if;
  if v_svc  is not false then v_bad := v_bad || ' sweep-service_role-executable'; end if;

  -- §E the party gate is in the deployed body. Comments STRIPPED before matching: `prosrc` is
  -- source plus our own prose, and the paragraph above this function names the conjunct — an
  -- unstripped match would be satisfied by the explanation rather than by the code.
  if regexp_replace(
       (select prosrc from pg_proc
         where oid = 'public.report_billing_key_revocation(uuid,boolean,text,uuid)'::regprocedure),
       '--[^\n]*', '', 'g') !~ 'and\s+state\s*=\s*''processing''' then
    v_bad := v_bad || ' reporter-state-gate-ABSENT';
  end if;

  -- §F the tick sweeps and retries
  if regexp_replace(
       (select prosrc from pg_proc
         where oid = 'public.dispatch_billing_key_revocations()'::regprocedure),
       '--[^\n]*', '', 'g') !~ '_sweep_stranded_billing_key_revocations' then
    v_bad := v_bad || ' dispatcher-sweep-ABSENT';
  end if;

  -- §H the three new/changed columns exist
  select count(*)::int into v_n
    from pg_attribute a
   where a.attrelid = 'billing_key_dispatch_health'::regclass
     and a.attname in ('abandoned_unclassified', 'abandoned_unreported', 'abandoned_benign')
     and a.attnum > 0 and not a.attisdropped;
  if v_n is distinct from 3 then v_bad := v_bad || ' health-columns=' || coalesce(v_n::text, '∅'); end if;

  if v_bad <> '' then raise exception '0166 VERIFY:%', v_bad; end if;
end $$;


-- ═══ WHAT THIS FILE DOES NOT CLOSE, named rather than quietly carried ═══
--
-- · **The roster is still empty in production.** `abandoned_unreported` now makes that visible and
--   the tick retries forever instead of giving up once — but nobody is subscribed to
--   `billing_key_revocation_abandoned`, so the first real failure is still told to nobody until a
--   recipient exists. That is a provisioning act, not a migration, and it is a gate on the
--   registration flag going live.
-- · **Pre-0166 abandoned rows stay unclassifiable.** They are counted honestly rather than
--   guessed at. Production has 0 of them today (0 rows in the table), so the bucket is expected to
--   stay at 0 forever; if it is ever non-zero on production, that is history from a restored
--   environment and not a defect.
-- · **`_note_revocation_abandoned`'s `abandon_class is distinct from 'benign'` conjunct has no
--   pin.** No caller can reach it: the two callers are both failure sites and belt 2 never calls
--   the emitter, so no fixture this harness can build reddens its removal. It is kept as defence
--   in depth and recorded here as prose — a pin whose mutation cannot be described is an
--   unfalsifiable guard doing prose's job.
