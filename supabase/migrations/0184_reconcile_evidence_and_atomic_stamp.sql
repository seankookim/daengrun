-- ═══ 0184: the stamp returns its cycle · an observed answer is remembered beyond pg_net's retention ═══
--
-- Codex's re-review of 0183 (docs/reviews/2026-09-18-migration-0183-codex-verdict.md, REJECT/2 —
-- the HIGH executed against the real handler with mocked HTTP; the MED static). Fixed forward,
-- 0183 not edited:
--   #1 HIGH (the EDGE, carried in this slice) — `transition-booking` stamped in one PostgREST call
--            and read `handoff_cycle_id` in a second. A reassignment between them cleared the old
--            runner's stamp and minted cycle B; the read returned B; the OLD request's ask carried
--            B, the cycle guard accepted it, and when runner B later stamped, their genuine lost ask
--            was suppressed by that row. → the stamping UPDATE RETURNS `handoff_cycle_id` (one
--            statement) and the edge carries exactly that id; a reassignment after the stamp makes
--            it stale and the guard refuses it. The returned row also decides `picked_up` — the
--            separate post-stamp re-read is gone. Deno `[0184]` pins both, with the reassignment
--            modelled as 「the stamp returns A, any later read would say B, the ask carries A」.
--            ⚠ AND THE MIRROR ORDER (cold review 0184 #1, HIGH, measured): a re-match committing
--            BEFORE the stamp — the edge's party gate had passed on the pre-request snapshot, and
--            a bare `where id = …` stamp then landed the OLD runner's confirmation on the NEW
--            pairing, returning cycle B (accepted by the guard), and `picked_up` was reachable with
--            the assigned runner never confirming. The stamping UPDATE is now PARTY-SCOPED
--            (`… and runner_id = uid` / `owner_id = uid`): that stamp matches no row and the edge
--            answers 409 (Korean copy — the club screens print it verbatim). Inherited from
--            `set()`, closed here because it is the same sentence. The ask's recipient comes from
--            the returned row too (#5): the snapshot's runner may be the one who just left.
--            SQL cannot tell a stale request's ask from a fresh one once both carry the current
--            id — the fix and its pins live at the stamp (deno); 215 does not pretend otherwise.
--            Two concurrent stampers: exactly one returned row shows both stamps (the second
--            UPDATE waits on the row lock and re-reads under READ COMMITTED — measured by the cold
--            review); the FIRST now sends a redundant ask to a party who just confirmed, where
--            0183's coin flip could produce a duplicate `picked_up` write — a net improvement,
--            recorded (#10).
--   #2 MED  — an unnamed reconciliation error left the tick `sent` with a notice, protected from
--            `no_response` only by 0183's 「it HAS an answer」 test — which lived in
--            `net._http_response`, deleted by pg_net after six hours; and the candidate cutoff at
--            six hours stopped re-reading it. → the tick row remembers `response_observed_at` and
--            `reconcile_error`; `no_response` honours the record whatever retention does; the
--            candidate query keeps re-reading an observed tick for as long as its answer still
--            exists (the answer's CONTENT cannot outlive pg_net's retention — that is pg_net's,
--            not this function's; past it the row stays `sent` with `reconcile_error` naming why,
--            a readable stuck state, never a lie — and the health view COUNTS it, §C). The TTL
--            unbounded for an observed tick means it stays joinable by `request_id` past six
--            hours; pg_net's ids are sequence-backed so an id is not reused — only a `drop/create
--            extension pg_net` would reset that sequence (cold review #8), recorded as the rung.
--
-- ═══ §A ═══
-- Two columns on `billing_key_dispatch_ticks`, nullable, no default (a pre-0184 tick was never
-- observed by this rule; NULL is that truth).
-- ═══ §B `reconcile_billing_key_dispatch_ticks` — 0183's body + four marked changes ═══
--   · the unnamed-fault branch persists `response_observed_at` (first time only) and the error;
--   · the verdict write and the `failed` write stamp `response_observed_at` and clear the error;
--   · the candidate query admits an observed tick past the TTL;
--   · the `no_response` arm excludes an observed tick, independently of retention.
-- ⚠ `create or replace` of a definer FIRST DEFINED IN 0150 — ACL restated. 181 · 211 · 213 D5 · 214
--   E5 pin the reconciler's earlier properties and are unmoved (measured); 215 owns the evidence.
-- ⚠ DEPLOY ORDER, unchanged from 0183 and stated again because it is the letter's: `db push`
--   FIRST, then `functions deploy transition-booking` — inverted, the new edge's ask insert dies
--   on `undefined_column` and is logged non-fatally; the recovery sweep catches up.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 215's header and the REGISTRY row.

-- ═══ §A ═══
alter table billing_key_dispatch_ticks add column if not exists response_observed_at timestamptz;
alter table billing_key_dispatch_ticks add column if not exists reconcile_error      text;
comment on column billing_key_dispatch_ticks.response_observed_at is
  '0184: the first time the reconciler SAW this tick''s answer in net._http_response — set whether it could read it (a verdict) or not (an unnamed fault). Once set, the tick can never become no_response, whatever pg_net has since deleted, and it keeps being re-read while its answer exists. NULL = never observed (or pre-0184).';
comment on column billing_key_dispatch_ticks.reconcile_error is
  '0184: the SQLSTATE and message of the last unnamed (non-verdict) error that kept the reconciler from reading this tick''s answer; cleared when a later read succeeds or becomes a verdict. A row still `sent` with this set past pg_net''s retention is 「answered, unreadable, and the answer is gone」 — a readable stuck state, not a worker failure.';

-- ═══ §B ═══
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
  -- [0180] the worker's per-cause counters (0178 split them in the response; the table kept only
  -- `claimed`). NULL = 「the body did not carry this number」, never 0.
  v_revoked int; v_failed int; v_stale int; v_not_processing int; v_absent int; v_unreported int;
  -- [0180] the seven counters are read through ONE guarded path: a JSON number is taken only when
  -- it is an integer in int4 range; anything else is NAMED, never cast — a cast that raises here
  -- aborts the whole call, and every tick behind it stays `sent` for the 6-hour TTL (cold review).
  c_fields constant text[] := array['claimed','revoked','failed','stale','not_processing','absent','unreported'];
  v_f text; v_num numeric; v_vals jsonb; v_missing text[];
begin
  for r in
    select distinct on (t.id)
           t.id as tick_id, h.status_code, h.timed_out, h.error_msg, h.content
      from billing_key_dispatch_ticks t
      join net._http_response h on h.id = t.request_id
     where t.outcome in ('sent','no_response')
       and t.request_id is not null
       -- [0184] the TTL cutoff no longer blocks a tick whose answer was OBSERVED and could not be
       -- read: it is re-read for as long as its answer row still exists (pg_net's retention is
       -- what ends that, not this predicate — codex 0183 #2)
       and (t.sent_at > now() - c_ttl or t.response_observed_at is not null)
     order by t.id, h.id desc
  loop
    -- [0182] a per-tick boundary (codex 0180 #4): one answer this block cannot read must not roll
    -- back every sibling's verdict, the stale sweep and the prune with it (measured: an int4 sum
    -- overflow did exactly that; the sum is bigint now, and this arm is for the next such class).
    -- The tick is marked `failed` with the reason — the honest verdict for an answer that arrived
    -- and could not be interpreted — and stops being re-read.
    begin
    v_claimed := null; v_detail := null; v_body := null;
    v_revoked := null; v_failed := null; v_stale := null; v_not_processing := null; v_absent := null; v_unreported := null;

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
        -- [0183] the same classification as the per-tick handler below (cold review 0183 #2: this
        -- inner arm swallowed EVERY class, so an out-of-memory during the parse became `accepted`
        -- with 「no claim count」 — and prunable). A malformed body (22P02) is the answer's own
        -- fault → NULL body; anything else is not a verdict and goes to the per-tick handler.
        if left(sqlstate, 2) in ('22', '23', 'P0') then v_body := null; else raise; end if;
      end;
      -- `handle()` returns the handler's object un-wrapped (`_shared/ctx.ts:46`), so the claim
      -- count is top level. A different envelope leaves `claimed_count` NULL and says so in
      -- `detail` — visible, rather than a zero that reads like a measurement.
      if v_body is not null and jsonb_typeof(v_body) = 'object' then
        -- [0180] one guarded read for all seven. `jsonb_typeof = 'number'` guards the READ; the
        -- integer test guards the CAST (1.5, 4.0 and 3000000000 are all JSON numbers, and each
        -- would have raised `invalid input syntax` / `out of range` from a bare `::int`). What is
        -- not taken is listed in `v_missing` with its raw value, so `detail` names what it saw.
        v_vals := '{}'::jsonb; v_missing := '{}';
        foreach v_f in array c_fields loop
          if jsonb_typeof(v_body->v_f) is not distinct from 'number' then
            v_num := (v_body->>v_f)::numeric;
            if v_num = trunc(v_num) and v_num between -2147483648 and 2147483647 then
              v_vals := v_vals || jsonb_build_object(v_f, v_num::int);
            else
              v_missing := array_append(v_missing, v_f || '=' || v_num::text || ' (not an integer)');
            end if;
          elsif v_body ? v_f then
            v_missing := array_append(v_missing, v_f || '=' || coalesce(left(v_body->>v_f, 40), 'null') || ' (not a number)');
          elsif v_f <> 'claimed' then
            v_missing := array_append(v_missing, v_f || ' (absent)');
          end if;
        end loop;
        v_claimed        := (v_vals->>'claimed')::int;
        v_revoked        := (v_vals->>'revoked')::int;
        v_failed         := (v_vals->>'failed')::int;
        v_stale          := (v_vals->>'stale')::int;
        v_not_processing := (v_vals->>'not_processing')::int;
        v_absent         := (v_vals->>'absent')::int;
        v_unreported     := (v_vals->>'unreported')::int;
        if v_revoked is null or v_failed is null or v_stale is null or v_not_processing is null
           or v_absent is null or v_unreported is null then
          -- ALL or NOTHING: a body that carries some of the six is an OLDER worker's shape, and in
          -- that shape `stale` still merges three causes (pre-0178). Storing the three it happens
          -- to name beside three NULLs would put a differently-defined number in the same column.
          -- The detail names each field that was absent or unreadable — a diagnosis the code made,
          -- not a guess about which worker sent it.
          v_revoked := null; v_failed := null; v_stale := null;
          v_not_processing := null; v_absent := null; v_unreported := null;
          v_detail := case when v_claimed is null then '2xx with no claim count in the body; ' else '' end
                      || 'per-cause split incomplete — ' || array_to_string(v_missing, ', ') || ' — counters left NULL';
        elsif v_claimed is null then
          -- the six are measurements the worker sent; kept, and the detail says the arithmetic
          -- could not be checked against a claim count that is not there (or not an integer)
          v_detail := '2xx with no claim count in the body'
                      || case when v_body ? 'claimed' then ' (claimed=' || coalesce(left(v_body->>'claimed', 40), 'null') || ')' else '' end
                      || ' — split kept, unchecked';
        elsif least(v_claimed, v_revoked, v_failed, v_stale, v_not_processing, v_absent, v_unreported) < 0 then
          -- 「minus one key was revoked」 is a contradiction whether or not it happens to balance
          v_detail := 'a counter is negative: claimed ' || v_claimed || ', revoked ' || v_revoked || ', failed ' || v_failed
                      || ', stale ' || v_stale || ', not_processing ' || v_not_processing || ', absent ' || v_absent
                      || ', unreported ' || v_unreported;
        elsif v_claimed::bigint <> v_revoked::bigint + v_failed + v_stale + v_not_processing + v_absent + v_unreported then
          -- the tick row must never carry a set of numbers that contradict each other in silence:
          -- every claimed row ends in exactly one bucket (handler.ts), so a body where they do not
          -- sum is a worker bug, and the detail names it while the numbers are kept as sent.
          v_detail := 'counters do not balance: claimed ' || v_claimed || ' <> revoked ' || v_revoked
                      || ' + failed ' || v_failed || ' + stale ' || v_stale || ' + not_processing '
                      || v_not_processing || ' + absent ' || v_absent || ' + unreported ' || v_unreported;
        end if;
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
       set outcome              = v_outcome,
           status_code          = r.status_code,
           claimed_count        = v_claimed,
           revoked_count        = v_revoked,
           failed_count         = v_failed,
           stale_count          = v_stale,
           not_processing_count = v_not_processing,
           absent_count         = v_absent,
           unreported_count     = v_unreported,
           detail               = v_detail,
           resolved_at          = now(),
           response_observed_at = coalesce(response_observed_at, now()),   -- [0184] an answer was seen
           reconcile_error      = null                                     -- [0184] and read, this time
     where id = r.tick_id;
    v_changed := v_changed + 1;
    exception when others then
      -- [0183] ONLY an identified DETERMINISTIC response error becomes a verdict (codex 0182 #3 —
      -- 0182's allow-list of four transient classes missed 53 out_of_memory and 58 io_error, which
      -- would have become permanent `failed`s): class 22 = a data exception (the body's own
      -- numbers), class 23 = an integrity violation (a verdict the table refuses), class P0 = a
      -- raise from our own plpgsql path. EVERYTHING ELSE — deadlocks (40), resources (53), locks
      -- (55), cancels/shutdowns (57), I/O (58), connections (08), internal (XX), and any class
      -- nobody has named yet — is NOT a verdict and NOT an abort either (cold review 0183 #3: a
      -- re-raise killed the siblings' verdicts, the stale sweep and the prune every tick for a
      -- deterministic unnamed fault such as 42883): the tick is left exactly as it is, `sent`, the
      -- notice names it, the loop goes on. Inside the TTL the next tick reads it again (a transient
      -- fault heals); past it the row stays `sent` beside its answer — visible, and the
      -- `no_response` arm below will not mislabel it (it skips ticks that HAVE an answer).
      if left(sqlstate, 2) not in ('22', '23', 'P0') then
        -- [0184] PERSIST THE EVIDENCE (codex 0183 #2): 0183's 「skip ticks that have an answer」 rule
        -- lived only in `net._http_response`, which pg_net deletes after six hours — an error that
        -- outlived the retention let the `no_response` arm blame the worker for a tick that WAS
        -- answered. The row itself now remembers that an answer was observed and what stopped the
        -- reading; `no_response` honours the record whatever retention does, and the candidate
        -- query above keeps re-reading the tick while its answer still exists.
        update billing_key_dispatch_ticks
           set response_observed_at = coalesce(response_observed_at, now()),
               reconcile_error      = left(sqlstate || ': ' || sqlerrm, 300)
         where id = r.tick_id;
        raise notice 'reconcile_billing_key_dispatch_ticks: tick % — not a verdict (%), left as it is: %', r.tick_id, sqlstate, sqlerrm;
        continue;
      end if;
      update billing_key_dispatch_ticks
         set outcome = 'failed', status_code = r.status_code,
             detail = left('reconciler could not read this answer: ' || sqlerrm, 300),
             resolved_at = now(),
             response_observed_at = coalesce(response_observed_at, now()),   -- [0184]
             reconcile_error      = null                                     -- [0184] the error became the verdict, in `detail`
       where id = r.tick_id;
      v_changed := v_changed + 1;
      raise notice 'reconcile_billing_key_dispatch_ticks: tick % — %', r.tick_id, sqlerrm;
    end;
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
     and sent_at <= now() - c_bound
     -- [0184] a tick whose answer was ever OBSERVED is not 「no response」, whatever pg_net has since
     -- deleted; [0183] nor is one whose answer is still on disk
     and response_observed_at is null
     and not exists (select 1 from net._http_response h where h.id = request_id);
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

-- ═══ §C the operator's one-row read says 「stuck」 (cold review 0184 #2, the ④ law) ═══
-- 0183's `no_response` exclusion and 0184's record remove the only alarm the health view had for
-- an answered-but-unreadable tick (it used to become `no_response_24h`); a stuck `sent` row with
-- `reconcile_error` was invisible there and, past 24 h, left the view entirely while the prune
-- (idle/accepted only) keeps it forever. One column, APPENDED (the append-only view law), and
-- deliberately NOT bound to the 24-hour window: a stuck tick's `sent_at` is the day it was sent,
-- and the whole point is that it never leaves `sent`.
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
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'failure')                         as abandoned_failures,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'benign')                          as abandoned_benign,
  (select count(*) from ops_recipients
    where event_class = 'billing_key_revocation_abandoned' and active)               as alert_recipients,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class is null)                             as abandoned_unclassified,
  (select count(*) from billing_key_revocations
    where state = 'abandoned' and abandon_class = 'failure'
      and alerted_at is null)                                                        as abandoned_unreported,
  -- [0184] answered, unreadable, still `sent` — all time, because such a row never leaves `sent`
  (select count(*) from billing_key_dispatch_ticks
    where outcome = 'sent' and reconcile_error is not null)                          as stuck_unreadable
from billing_key_dispatch_ticks
where sent_at > now() - interval '24 hours';

revoke all on billing_key_dispatch_health from public, anon, authenticated;
grant select on billing_key_dispatch_health to service_role;

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 215 ═══
do $$
declare v_oid oid; v_src text; v_bad text := ''; v_n int;
begin
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped and attname in ('response_observed_at', 'reconcile_error');
  if v_n is distinct from 2 then v_bad := v_bad || ' A:COLUMNS(' || v_n || '/2)'; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_ticks'::regclass and not attisdropped and attname in ('response_observed_at', 'reconcile_error') and (atthasdef or attnotnull);
  if v_n is distinct from 0 then v_bad := v_bad || ' A:COLUMN-HAS-DEFAULT-OR-NOT-NULL(' || v_n || ')'; end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then raise exception '0184 VERIFY FAILED: NO-FUNCTION'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NO-IN-BODY-SEARCH-PATH'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
  else
    if (v_src ~ 'reconcile_error      = left\(sqlstate \|\| '': '' \|\| sqlerrm, 300\)') is distinct from true then v_bad := v_bad || ' B:UNNAMED-FAULT-NOT-RECORDED'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'response_observed_at = coalesce\(response_observed_at, now\(\)\)', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:OBSERVATION-STAMPS(' || v_n || '/3 — the verdict, the failed marking, the unnamed fault)'; end if;
    if (v_src ~ 'and response_observed_at is null\s+and not exists \(select 1 from net\._http_response h where h\.id = request_id\)') is distinct from true then v_bad := v_bad || ' B:NO_RESPONSE-IGNORES-THE-RECORD'; end if;
    if (v_src ~ 'or t\.response_observed_at is not null\)') is distinct from true then v_bad := v_bad || ' B:TTL-STILL-BLOCKS-AN-OBSERVED-TICK'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' B:VERDICT-FILTER-MISSING'; end if;
    if (v_src ~ 'not in \(''22'', ''23'', ''P0''\) then raise;') is distinct from false then v_bad := v_bad || ' B:UNNAMED-FAULT-ABORTS'; end if;
    if (v_src ~ 'v_claimed::bigint <> v_revoked::bigint \+') is distinct from true then v_bad := v_bad || ' B:BALANCE-SUM-NOT-BIGINT'; end if;
  end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.billing_key_dispatch_health'::regclass and not attisdropped and attname = 'stuck_unreadable';
  if v_n is distinct from 1 then v_bad := v_bad || ' C:HEALTH-VIEW-HAS-NO-STUCK-COLUMN'; end if;
  if v_bad <> '' then raise exception '0184 VERIFY FAILED:%', v_bad; end if;
end $$;
