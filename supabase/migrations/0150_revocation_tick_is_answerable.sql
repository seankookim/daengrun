-- ═══ 0150: a REJECTED revocation tick stops looking like an EMPTY QUEUE ═══
--
-- Closes codex round-5 **#5**, which 0148's footer named and deliberately did not close. Its
-- sentence, kept because it is the property and not just the instance:
--
--   the dispatcher fires pg_net and never inspects the response, so an unset or mismatched
--   `CRON_COLLECT_KEY` makes every tick 「succeed」 while the endpoint rejects before claiming,
--   and rows sit at `attempts = 0` forever with no durable failure signal.
--
-- 🔴 THIS IS 0138'S OWN DOCUMENTED FAILURE ONE LAYER DOWN, AND THE FILE THAT FIXED IT REPRODUCED
--    IT. 0141 §D's header says of 0138: 「it found no key, returned 0, and scheduled revocation
--    would NEVER START — silently, since returning 0 is also what 「nothing due」 looks like.」
--    0141 fixed the vault contract and then fired `perform net.http_post(...)` — discarding the
--    request id, never reading the answer. The rejection moved from our side of the wire to
--    theirs and became invisible in exactly the same way.
--
-- ⚠ TODAY THE TWO STATES ARE THE SAME STATE, and that is what makes it undetectable rather than
--   merely unhandled. On a rejected tick the endpoint refuses **before it claims anything**
--   (`revoke-billing-keys/handler.ts:26-27` — the key check precedes the `claim_...` RPC), so:
--   `billing_key_revocations` is byte-unchanged, `attempts` does not move, `last_error` stays
--   null, `dispatch_billing_key_revocations()` returned a positive number and raised nothing, and
--   `cron.job_run_details` records a success. An empty queue produces the identical evidence
--   minus one integer nobody stores. **There is no observer anywhere in the system that can tell
--   「the endpoint is refusing us」 from 「there was nothing to do」.**
--
-- ⚠ AND IT IS THE INACTION CASE, which is the class CLAUDE.md §Migrations says a reviewer must
--   attack: nobody transitions anything, so no state machine can reach it. Two independent
--   reviewers enumerated 0138's transitions and neither saw it, for the same reason.
--
--
-- ═══ THE SHAPE, AND WHY THIS ONE ═══
--
-- pg_net is **asynchronous**: `net.http_post()` returns a request id immediately and the worker
-- writes the response into `net._http_response` some time later. So this cannot be the
-- in-transaction 「call, check, act」 idiom every other guard in this family uses. It has to be a
-- LEDGER plus a RECONCILE: the dispatcher records what it SENT, and a later tick reads the answer
-- back and writes a verdict beside it.
--
-- 🔴 MEASURED AGAINST THE LINKED PRODUCTION PROJECT (2026-08-27), not assumed — the brief for
--    this slice asked which is which, so each line says:
--
--   · `pg_net` version **0.20.4**.                                                     MEASURED
--   · `net._http_response(id bigint, status_code int, content_type text, headers jsonb,
--     content text, timed_out boolean, error_msg text, created timestamptz)`.          MEASURED
--   · **The key is `id`, and it is the value `net.http_post()` returns.** `net.http_post`'s body
--     inserts into `net.http_request_queue` and returns that row's `id`; on production
--     `http_request_queue_id_seq.last_value` = **152** and `max(net._http_response.id)` = **152**,
--     i.e. the response carries the request's own id.                                  MEASURED
--     ⚠ The last step — 「the worker copies the id across」 — is READ from that agreement plus
--       `http_post`'s source, not observed on a request I made. It is the one rung here that is
--       inference, and it is named rather than rounded up.                              READ
--   · **There is NO primary key and NO index on `net._http_response.id`.** The table's only index
--     is `_http_response_created_idx` on `created`. So a lookup by id is a seq scan over at most
--     one TTL window of rows, and nothing in the catalog forbids two rows with the same id. Both
--     facts are why the reconcile below joins on id but never assumes uniqueness (it takes the
--     newest row per tick) and why it is bounded by `sent_at`, not by scanning history. MEASURED
--   · **Retention: `pg_net.ttl = 6 hours`** (source `default`).                        MEASURED
--   · ⚠ **And retention is a CEILING the worker enforces, not a floor it guarantees.** Live rows
--     dated `2026-08-25 04:36` were still present at `2026-08-27 04:43` — **~48 hours, 8× the
--     TTL** — because pruning happens inside the worker loop and the worker had had nothing to do
--     since. So rows can outlive the TTL; the direction that would hurt us (vanishing EARLY)
--     was not observed and is bounded by the setting.                                  MEASURED
--   · The cron fires every 10 minutes (`revoke-billing-keys`, `8-58/10 * * * *`, 0138 §G), so the
--     next tick reads an answer written seconds ago against a 6-hour floor. The margin is 36×.
--   · ⚠ `net` schema is `=U` (PUBLIC has USAGE) and `net._http_response` is `=arwdDxtm` for
--     PUBLIC — i.e. **anon and authenticated can already read every pg_net response body in this
--     project.** That is Supabase's own default, it predates this file, and it is NOT touched
--     here. It is written down because it is the reason reading that table adds no disclosure,
--     and because somebody should look at it in a slice that owns it.               MEASURED
--
--
-- ═══ WHAT THIS FILE DELIBERATELY DOES NOT DO ═══
--
-- 🔴 **NO ALERTING SURFACE, AND NO DECISION ABOUT WHO IS TOLD.** codex round-5 **#4** (an
--    `abandoned` row is terminal and nothing reads it) is the same open question one table over,
--    and 0148's footer already recorded why it is not a migration's call: 「it needs a product
--    decision about WHO is told, which is Sean's」. This file builds the **distinction** and a
--    **readable row**. It routes nothing, notifies nobody, and adds no `ops_recipients` entry.
--    The slice that gets his answer owns escalation; until then the honest position is that these
--    rows are queryable and nothing watches them. Said here rather than implied.
--
-- ⚠ **INERT TODAY — DO NOT READ THIS AS URGENT.** Measured against the linked project this hour:
--    production is at migration **0130**, so nothing from 0138 onward is deployed at all — there
--    is no `billing_key_revocations` table, no `revoke-billing-keys` cron (the live `cron.job`
--    list does not contain it), and `ops_flags.card_registration_live_since` **does not exist as
--    a column**. `ops_flags.payments_live_since` is NULL and `TOSS_ENABLED` is `false`
--    (`app/src/lib/toss.ts:16`). Every gate this path needs is shut, in front of a table that is
--    not there. This arms at flip, in order, behind whichever of those Sean opens last.
--
--
-- ═══ THE STATES, AND WHY THE DOMAIN IS THIS ONE ═══
--
--   `idle`        nothing was due. The tick ran and correctly did nothing. **HEALTHY.**
--   `deferred`    something was due and we could not send (vault absent/malformed). Our side.
--   `sent`        fired; the request id is recorded; no verdict yet. Transient by construction.
--   `accepted`    2xx. `claimed_count` carries what the endpoint said it claimed, when it said.
--   `rejected`    **the endpoint refused the caller.** 401/403/503 — the finding's exact case.
--   `failed`      any other answer, a transport error, or a pg_net timeout.
--   `no_response` sent, the bound elapsed, nothing came back. **Its own third state**, not silence.
--
-- ⚠ **503 IS FILED UNDER `rejected` ON PURPOSE, and the exact code is stored so nothing is lost.**
--   The endpoint's own 「not configured」 refusal is a 503 (`handler.ts:26`: an unset
--   `CRON_COLLECT_KEY` throws `HttpError(503)`) and a wrong one is a 401 (`:27`). **Unset is the
--   more likely half of the finding**, so filing it as a generic `failed` would hide the single
--   most probable production instance of the thing this file exists to surface. A gateway 503
--   from a cold start would also land here; `status_code` is recorded verbatim precisely so an
--   operator can separate them without this file inventing a state to hold the difference.
--
-- ⚠ **`idle` IS RECORDED, NOT SKIPPED, AND THAT IS THE WHOLE POINT.** 「Write nothing when nothing
--   happened」 is what the bug already does. A positive row saying 「the tick ran, the queue was
--   empty」 is what makes a rejected tick and an empty queue different, and it is also what makes
--   **a cron that stopped running entirely** visible as a third thing again: no row at all.
--
-- ⚠ **A RULE THAT FLAGS EVERY QUIET TICK IS THIS DEFECT WITH THE OPPOSITE SIGN.** Nothing here
--   treats `idle` as a problem, and suite 181's `0150-P2` is the control that says so — it
--   reddens on a reconciler that reclassifies healthy silence, where `0150-P1` reddens on one
--   that records nothing. Neither can be satisfied by a hard-wired answer; they fail in opposite
--   directions, which is what makes them two measurements and not one printed twice.


-- ═══ §A the tick ledger ═══
create table if not exists billing_key_dispatch_ticks (
  id            uuid primary key default gen_random_uuid(),
  outcome       text not null
                  check (outcome in ('idle','deferred','sent','accepted','rejected','failed','no_response')),
  due_count     int  not null default 0,
  -- the value `net.http_post()` returned = `net._http_response.id`. NULL on a tick that never
  -- sent (`idle`, `deferred`), which is why it is nullable rather than a NOT NULL with a sentinel.
  request_id    bigint,
  status_code   int,
  claimed_count int,
  detail        text,
  sent_at       timestamptz not null default now(),
  -- set when the outcome stops being provisional. `sent` is the only outcome that leaves it null.
  resolved_at   timestamptz
);

-- The reconcile's working set: ticks still awaiting a verdict. Partial, because every other row
-- in this table is history and is never scanned by the hot path.
create index if not exists billing_key_dispatch_ticks_open_idx
  on billing_key_dispatch_ticks (sent_at)
  where outcome in ('sent','no_response');

alter table billing_key_dispatch_ticks enable row level security;
-- No policies, deliberately — the same seal as `billing_key_revocations` (0138 §A) and for a
-- weaker but sufficient reason: this table holds no credential, but it is an operational record
-- of our payment plumbing's health and no client has any business reading one row of it.
-- `service_role` bypasses RLS; everyone else matches no policy and sees nothing.
revoke all on table billing_key_dispatch_ticks from public, anon, authenticated;
grant select, insert, update, delete on table billing_key_dispatch_ticks to service_role;

comment on table billing_key_dispatch_ticks is
'0150 (codex round-5 #5): one row per `dispatch_billing_key_revocations()` tick, so a REJECTED tick
is distinguishable from an EMPTY QUEUE. Before this table both produced identical evidence — an
unchanged outbox, no error, and a cron success — because the endpoint refuses the caller BEFORE it
claims anything. `outcome` is the distinction; `status_code` keeps the exact answer so no operator
has to infer it from a state name. ⚠ NOTHING READS THIS TABLE YET AND NOTHING IS ALERTED: who gets
told is a product decision (Sean''s), the same one codex #4 is blocked on. This file builds the
distinction and stops there, on purpose.';


-- ═══ §B the reconcile — the later pass that turns a request id into a verdict ═══
--
-- ⚠ WHY A LOOP AND NOT ONE `update … from`: the 2xx arm parses the response body, and a body that
--   is not JSON must not abort the whole pass. A per-row exception block is the only place that
--   containment can live, and the volume is one row per tick.
--
-- ⚠ WHY `distinct on (t.id) … order by h.id desc`: `net._http_response` has no unique constraint
--   on `id` (measured — its only index is on `created`). Nothing observed produces a duplicate,
--   and this costs one clause to be correct if one ever appears, rather than raising
--   `more than one row returned` inside a cron tick.
create or replace function reconcile_billing_key_dispatch_ticks()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  -- A response written seconds after dispatch, against a cron that ticks every 10 minutes. Two
  -- minutes is generous for the first, far inside the second, and well clear of pg_net's own
  -- default request timeout.
  c_bound constant interval := interval '2 minutes';
  -- pg_net's measured retention (`pg_net.ttl = 6 hours`). Past this the answer is gone and cannot
  -- improve, so a tick stops being re-read and keeps whatever verdict it has.
  c_ttl   constant interval := interval '6 hours';
  -- History is kept, but not forever, and NOT symmetrically — see the delete below.
  c_keep  constant interval := interval '30 days';
  r record;
  v_changed int := 0; v_n int;
  v_outcome text; v_claimed int; v_detail text; v_body jsonb;
begin
  for r in
    select distinct on (t.id)
           t.id as tick_id, h.status_code, h.timed_out, h.error_msg, h.content
      from billing_key_dispatch_ticks t
      join net._http_response h on h.id = t.request_id
     where t.outcome in ('sent','no_response')
       and t.request_id is not null
       and t.sent_at > now() - c_ttl
     order by t.id, h.id desc
  loop
    v_claimed := null; v_detail := null; v_body := null;

    -- ⚠ `coalesce(…, false)`: `timed_out` is a nullable boolean and a bare `if r.timed_out` is
    --   NOT TAKEN on NULL, which would silently drop the row into a later arm. The NULL-collapse
    --   law (CLAUDE.md) is about pins; it is the same statement about a branch.
    if coalesce(r.timed_out, false) then
      v_outcome := 'failed';
      v_detail  := 'pg_net timed out — the endpoint did not answer in time';
    elsif r.error_msg is not null then
      v_outcome := 'failed';
      v_detail  := left('transport: ' || r.error_msg, 300);
    elsif r.status_code between 200 and 299 then
      v_outcome := 'accepted';
      begin
        v_body := r.content::jsonb;
      exception when others then
        v_body := null;
      end;
      -- `handle()` returns the handler's object un-wrapped (`_shared/ctx.ts:46`), so the claim
      -- count is top level. A different envelope leaves `claimed_count` NULL and says so in
      -- `detail` — visible, rather than a zero that reads like a measurement.
      if v_body is not null and jsonb_typeof(v_body->'claimed') is not distinct from 'number' then
        v_claimed := (v_body->>'claimed')::int;
      else
        v_detail := '2xx with no claim count in the body';
      end if;
    elsif r.status_code in (401, 403, 503) then
      -- 🔴 THE FINDING. 401 = the cron key is wrong, 503 = it is unset (handler.ts:26-27). Either
      --    way the endpoint answered without claiming a single row, and every tick from here on
      --    will do the same until somebody changes a secret.
      v_outcome := 'rejected';
      v_detail  := left('the endpoint refused this caller (' || r.status_code || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    else
      v_outcome := 'failed';
      v_detail  := left('unexpected answer (' || coalesce(r.status_code::text, 'no status') || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    end if;

    update billing_key_dispatch_ticks
       set outcome       = v_outcome,
           status_code   = r.status_code,
           claimed_count = v_claimed,
           detail        = v_detail,
           resolved_at   = now()
     where id = r.tick_id;
    v_changed := v_changed + 1;
  end loop;

  -- ⚠ THE THIRD STATE. A tick that sent and was never answered is NOT the same as one that was
  --   refused, and it is not silence either — it says the pg_net worker is not running, or the
  --   request never left. Declared only AFTER the bound, so an in-flight tick is never libelled.
  update billing_key_dispatch_ticks
     set outcome     = 'no_response',
         detail      = 'no pg_net response within ' || c_bound::text
                       || ' — the worker may be down, or the request never left',
         resolved_at = now()
   where outcome = 'sent'
     and sent_at <= now() - c_bound;
  get diagnostics v_n = row_count;
  v_changed := v_changed + v_n;

  -- ⚠ THE PRUNE IS DELIBERATELY ASYMMETRIC AND MUST STAY THAT WAY. Only the two outcomes that
  --   mean 「this tick was fine」 are ever deleted. `rejected`, `failed`, `no_response` and
  --   `deferred` are the evidence — the whole reason this table exists — and a retention rule
  --   that swept them on a timer would re-create the defect on a 30-day delay. A permanently
  --   broken system accumulating 144 rows a day is not this table's problem; it is the finding.
  delete from billing_key_dispatch_ticks
   where outcome in ('idle', 'accepted')
     and sent_at < now() - c_keep;

  return v_changed;
end $$;
revoke execute on function reconcile_billing_key_dispatch_ticks() from public, anon, authenticated;
grant  execute on function reconcile_billing_key_dispatch_ticks() to service_role;


-- ═══ §C the dispatcher records what it did — on EVERY path, including the ones that return 0 ═══
--
-- Re-created from 0141 §D's body (§10 T4: start from the newest definition). The vault contract,
-- the header name and the appended path are unchanged and 174's L6 pins all three.
--
-- 🔴 THE RECONCILE CALL IS FIRST, AND ITS POSITION IS LOAD-BEARING RATHER THAN TIDY. Put it after
--    the `v_due = 0` early return and a rejected tick followed by a quiet queue is never resolved
--    — the verdict would arrive only on the next tick that happened to have work, which on a
--    system whose revocation is disabled is a tick that may never come. `0150-P5` mutates exactly
--    this: it plants a stale unresolved tick, dispatches against an EMPTY queue, and asserts the
--    stale tick was resolved anyway. That can only pass if the reconcile precedes the return.
--
-- ⚠ AND IT IS NOT WRAPPED IN AN EXCEPTION HANDLER, unlike the vault read below, which looks
--   inconsistent and is not. The vault is an EXTERNAL dependency that can be legitimately absent
--   mid-rollout, so 0138 chose to defer rather than raise. The reconcile touches only this repo's
--   own table and `net._http_response` — and `net` is a hard dependency of the very next
--   statement in this function. An error there means the dispatcher could not have worked anyway,
--   so swallowing it would buy nothing and would re-create precisely the silent tick this file
--   exists to end.
create or replace function dispatch_billing_key_revocations()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_due int; v_secret text; v_cfg jsonb; v_url text; v_key text; v_req bigint;
begin
  perform reconcile_billing_key_dispatch_ticks();

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
  -- record was a `cron.job_run_details` row nobody reads. Same class as the finding above, one
  -- statement earlier: a tick that did nothing must be able to say why.
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

  -- 🔴 THE RETURN IS CAPTURED. 0141 wrote `perform net.http_post(…)` and threw the request id
  --    away, which is what made the answer unreachable: pg_net keys `net._http_response` by
  --    exactly this value (measured), so discarding it discards the only handle on the verdict.
  v_req := net.http_post(
    url := v_url || '/revoke-billing-keys',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Key', v_key),
    body := jsonb_build_object('mode', 'batch')
  );

  if v_req is null then
    -- pg_net gave us nothing to track. Recorded as a failure and NOT as a send: a `sent` row with
    -- no request id can never be reconciled, so it would sit at 「awaiting verdict」 forever —
    -- a permanent pending, which is the same invisibility in a nicer costume.
    insert into billing_key_dispatch_ticks (outcome, due_count, detail, resolved_at)
    values ('failed', v_due, 'net.http_post returned no request id', now());
    return v_due;
  end if;

  insert into billing_key_dispatch_ticks (outcome, due_count, request_id)
  values ('sent', v_due, v_req);
  return v_due;
end $$;
-- Re-created here from a body first defined in 0138, so this file states the ACL rather than
-- relying on `create or replace` preserving it — on an apply where the function is absent that
-- statement is a plain CREATE and the definer is born PUBLIC-executable (0116:636).
revoke execute on function dispatch_billing_key_revocations() from public, anon, authenticated;
grant  execute on function dispatch_billing_key_revocations() to service_role;

-- ⚠ NO CRON CHANGE. 0138 §G scheduled `revoke-billing-keys` as
--   `select dispatch_billing_key_revocations()` and the signature is unchanged, so the existing
--   entry now reconciles as well as dispatches. Re-scheduling here would duplicate the job on any
--   database where 0138 already applied.


-- ═══ §D the readable row ═══
--
-- One row, always. Every count is over the last 24 hours; the four `last_*` columns are unbounded
-- so a long-dead dispatcher still says when it last worked.
--
-- ⚠ `last_tick_at is null` IS ITS OWN ANSWER and the one no row can carry: it means no tick has
--   been recorded at all in 24h — the cron is not running, which is a different failure from any
--   outcome in the domain. Left as an observable fact rather than folded into a state.
--
-- ⚠ `security_invoker = true`: a view is normally read with its OWNER's privileges, which would
--   walk straight past the RLS seal §A just put on the base table for anyone holding a SELECT
--   grant. There is no such grant — but a view that would leak if someone added one is a
--   different object from one that would not.
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
      and (state = 'pending' or (state = 'processing' and lease_until < now())))     as due_now
from billing_key_dispatch_ticks
where sent_at > now() - interval '24 hours';

revoke all on billing_key_dispatch_health from public, anon, authenticated;
grant select on billing_key_dispatch_health to service_role;

comment on view billing_key_dispatch_health is
'0150: the one-row read of revocation dispatch health. `rejected_24h > 0` means the endpoint is
refusing our cron key and NOTHING is being revoked, which before 0150 was indistinguishable from
`idle_24h > 0` (the queue was empty and all is well). `last_tick_at is null` is a third answer
again: no tick at all, i.e. the cron itself is not running. ⚠ Nothing watches this — see the table
comment; escalation is a product decision that has not been made.';


-- ═══ VERIFY ═══
--
-- ⚠ NO `prosrc` GREP HERE. This file names every one of its own tokens — `rejected`,
--   `no_response`, `net.http_post`, `request_id` — inside its prose, and a comment quoting the
--   code it describes matches every grep that hunts for that code (CLAUDE.md §Migrations). A text
--   scan would be green on a body whose logic had been deleted, purely off the paragraphs above.
--   Every arm below measures CATALOG state, PRIVILEGE answers, or real BEHAVIOUR.
do $$
declare
  v_oid oid; v_sec boolean; v_cfg text[]; v_kind char;
  v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_rls boolean; v_pol int; v_before bigint; v_after bigint;
  v_id uuid; v_id2 uuid; v_txt text; v_admitted boolean;
  fn text;
begin
  -- ① both functions exist and are the SHAPE the ACL / search_path laws are about.
  foreach fn in array array['reconcile_billing_key_dispatch_ticks',
                            'dispatch_billing_key_revocations'] loop
    select p.oid, p.prosecdef, p.proconfig, p.prokind
      into v_oid, v_sec, v_cfg, v_kind
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = fn;
    if v_oid is null   then raise exception '0150 VERIFY ①: % absent', fn; end if;
    if not v_sec       then raise exception '0150 VERIFY ①: % is not SECURITY DEFINER', fn; end if;
    if v_kind <> 'f'   then raise exception '0150 VERIFY ①: % prokind=%', fn, v_kind; end if;
    -- in-body `set search_path` — the form that survives a later `create or replace` (98 H1).
    if not (v_cfg @> array['search_path=public, pg_temp']) then
      raise exception '0150 VERIFY ①: % proconfig=% (expected in-body search_path=public, pg_temp)',
        fn, coalesce(array_to_string(v_cfg, ','), '<null>');
    end if;

    -- ② ACL, BOTH DIRECTIONS. A negative-only check is green on a function nobody can call.
    select has_function_privilege('public', v_oid, 'execute'),
           has_function_privilege('anon', v_oid, 'execute'),
           has_function_privilege('authenticated', v_oid, 'execute'),
           has_function_privilege('service_role', v_oid, 'execute')
      into v_pub, v_anon, v_auth, v_svc;
    if v_pub  then raise exception '0150 VERIFY ②: PUBLIC can execute %', fn; end if;
    if v_anon then raise exception '0150 VERIFY ②: anon can execute %', fn; end if;
    if v_auth then raise exception '0150 VERIFY ②: authenticated can execute %', fn; end if;
    if not v_svc then
      raise exception '0150 VERIFY ②: service_role CANNOT execute % — the grant did not land', fn;
    end if;
  end loop;

  -- ③ the ledger is sealed, and the view with it — both directions again.
  select c.relrowsecurity into v_rls
    from pg_class c where c.oid = 'billing_key_dispatch_ticks'::regclass;
  if not v_rls then raise exception '0150 VERIFY ③: RLS is off on billing_key_dispatch_ticks'; end if;
  select count(*)::int into v_pol
    from pg_policies where schemaname = 'public' and tablename = 'billing_key_dispatch_ticks';
  if v_pol <> 0 then
    raise exception '0150 VERIFY ③: % polic(ies) on a table whose seal is having none', v_pol;
  end if;
  if has_table_privilege('anon', 'billing_key_dispatch_ticks', 'select') then
    raise exception '0150 VERIFY ③: anon can SELECT the tick ledger'; end if;
  if has_table_privilege('authenticated', 'billing_key_dispatch_ticks', 'select') then
    raise exception '0150 VERIFY ③: authenticated can SELECT the tick ledger'; end if;
  if not has_table_privilege('service_role', 'billing_key_dispatch_ticks', 'select') then
    raise exception '0150 VERIFY ③: service_role CANNOT read the tick ledger — the grant did not land'; end if;
  if has_table_privilege('anon', 'billing_key_dispatch_health', 'select') then
    raise exception '0150 VERIFY ③: anon can read the health view'; end if;
  if has_table_privilege('authenticated', 'billing_key_dispatch_health', 'select') then
    raise exception '0150 VERIFY ③: authenticated can read the health view'; end if;
  if not has_table_privilege('service_role', 'billing_key_dispatch_health', 'select') then
    raise exception '0150 VERIFY ③: service_role CANNOT read the health view'; end if;

  -- ④ the outcome domain is CLOSED. A state name nobody checks is a state name that drifts.
  -- ⚠ The verdict rides a FLAG, not a raise inside the try arm: a raise there is swallowed by
  --   this block's own handler and re-emerges as the detector reporting its own failure text.
  v_admitted := false;
  begin
    insert into billing_key_dispatch_ticks (outcome, due_count) values ('bogus_outcome', 0);
    v_admitted := true;
  exception when others then null;
  end;
  if v_admitted then raise exception '0150 VERIFY ④: an unknown outcome was ADMITTED'; end if;

  -- ⑤ BEHAVIOUR, and the two arms are opposites on purpose.
  select count(*) into v_before from billing_key_dispatch_ticks;

  -- ⑤a POSITIVE — a tick that sent, was never answered, and is past the bound becomes its own
  --    state. Negative request ids can never collide with a real one (the pg_net sequence is
  --    positive), so this measures the reconcile without touching the vendor's table.
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 1, -1, now() - interval '10 minutes') returning id into v_id;
  -- ⑤b NEGATIVE CONTROL — an identical tick INSIDE the bound must be left alone. Without this
  --    arm ⑤a is green on a reconciler that declares every tick dead, which is this defect with
  --    the opposite sign.
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 1, -2, now()) returning id into v_id2;

  perform reconcile_billing_key_dispatch_ticks();

  select outcome into v_txt from billing_key_dispatch_ticks where id = v_id;
  if v_txt is distinct from 'no_response' then
    raise exception '0150 VERIFY ⑤a: an unanswered tick reads % (expected no_response)',
      coalesce(v_txt, '<null>');
  end if;
  select outcome into v_txt from billing_key_dispatch_ticks where id = v_id2;
  if v_txt is distinct from 'sent' then
    raise exception '0150 VERIFY ⑤b: a tick inside the bound was declared % — every quiet tick would be flagged',
      coalesce(v_txt, '<null>');
  end if;

  -- ⑤c the probes leave nothing behind. A VERIFY that seeds its own table is a VERIFY that
  --    changes what the next reader measures.
  delete from billing_key_dispatch_ticks where id in (v_id, v_id2);
  select count(*) into v_after from billing_key_dispatch_ticks;
  if v_after <> v_before then
    raise exception '0150 VERIFY ⑤c: the probe left % row(s) behind', v_after - v_before;
  end if;
end $$;
