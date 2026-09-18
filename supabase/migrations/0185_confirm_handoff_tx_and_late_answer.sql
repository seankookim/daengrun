-- ═══ 0185: the stamp and the promotion are ONE locked transaction · a late answer wakes a no_response tick ═══
--
-- Codex's re-review of 0184 (docs/reviews/2026-09-18-migration-0184-codex-verdict.md, REJECT/2 —
-- the HIGH executed against the real handler with mocked HTTP; the MED static). Fixed forward,
-- 0184 not edited:
--   #1 HIGH — 0184 made the STAMP atomic and party-scoped, but the `picked_up` promotion was still
--            a SEPARATE id-only UPDATE (`set({ status: "picked_up" })`) authorised by the stamp's
--            RETURNED confirmations. Runner A's stamp returns both stamps; a reassignment
--            (`session_propose_dog`, 0048:470-498) commits cycle B and voids both; the handler then
--            marks B `picked_up` and tells runner A; the custody trigger (0045:44-54) trusts
--            `picked_up` and records the NEW runner as custodian with neither confirmation — a
--            pairing in custody that nobody confirmed. → §A `confirm_handoff_tx(p_booking, p_uid,
--            p_side)`: the row is LOCKED (`for update`), the party gate is taken on the LOCKED row
--            (the mirror order — a re-match that committed first makes the caller a stranger and
--            the answer is `not_party`, no stamp), the status gate on the locked row, then the
--            stamp AND the promotion in ONE UPDATE whose condition is evaluated on the locked row
--            (both stamps · both THIS cycle's · an eligible status · a runner). A reassignment
--            that reaches the row after this transaction finds `picked_up` and is refused by
--            0048's own `already_handed_off`; one that reached it before finds no party to stamp.
--            The edge calls the RPC and notifies ONLY from the row it returns — never from the
--            pre-request snapshot, never from a second statement. Deno `[0185]` pins the edge's
--            half (one rpc, no PATCH, the refusal → 409, the recipient from the returned row);
--            216 G1–G5 pin the RPC, G5 at the custody trigger itself.
--            Two rules the RPC settles that the edge never stated:
--            · a stamp that predates the cycle boundary (`handoff_cycle_at`, 0182) is NOT this
--              cycle's: it never promotes, it is CLEARED, and that party is asked again — a row
--              left with two stamps and no promotion would sit forever (sweep ⓒ: 「both stamps ⇒
--              nothing」; the attack-INACTION law). No shipped pre-handoff runner change keeps a
--              stamp (0047/0048/0057/0124/0118 void both; `session_transfer_accept` changes the
--              runner only in custody, status ≥ picked_up); the 0183 backfill sets the id alone,
--              so no production stamp precedes its boundary. The belt is for the class — G3.
--            · a re-tap by the same side KEEPS the first stamp (the edge overwrote it): sweep ⓒ's
--              5-minute and ⓓ's 30-minute clocks read that stamp, and an overwrite let a re-tapping
--              party postpone escalation indefinitely. A re-tap is not a new cycle (the trigger
--              sees no reset) and the cycle id the ask carries is unchanged.
--   #2 MED  — a delayed answer arriving on a tick already `no_response`, met by an unnamed fault on
--            the read, kept the row `no_response` with the transport-blaming detail (0184:249-252
--            wrote observation metadata only, although the candidate query admits `no_response`
--            rows); `stuck_unreadable` counts `sent` only, so after 24 h the row left every health
--            view. → §B the unreadable-answer arm moves an unresolved `no_response` back to `sent`
--            (the stale detail and `resolved_at` cleared — the tick DID get an answer), guarded
--            against a concurrent completed verdict (`outcome in ('sent', 'no_response')` — the
--            same CAS on the `failed` write, which is the same sentence at the other exception
--            arm); the row is then counted by `stuck_unreadable` and reconciles once the fault
--            clears. 216 H1 pins the path; the two-connection guard is `90_race_check.sh` RV.
--            The main verdict write is deliberately NOT guarded: two ticks reading the same
--            immutable answer compute the same verdict.
--
-- ═══ §A `confirm_handoff_tx(p_booking uuid, p_uid uuid, p_side text) returns jsonb` ═══
--   service_role only (the edge's admin client; `p_uid` is the caller the edge verified —
--   `auth.uid()` wins over it when present, so the argument cannot be spoofed by anyone who could
--   ever execute this). Raises by name: not_signed_in · bad_side · not_found · not_party ·
--   wrong_status. Returns {unchanged, promoted, both, ask_to, status, owner_id, runner_id,
--   handoff_cycle_id} — the row AS THE STATEMENT LEFT IT.
-- ═══ §B `reconcile_billing_key_dispatch_ticks` — 0184's body + two marked changes ═══
-- ⚠ `create or replace` of a definer FIRST DEFINED IN 0150 — ACL restated. 181 · 211 · 213 D5 · 214
--   E5 · 215 F1–F3 pin the reconciler's earlier properties and are unmoved (measured).
-- ⚠ DEPLOY ORDER: `db push` FIRST, then `functions deploy transition-booking` — inverted, the new
--   edge's rpc call dies on `undefined_function` and confirm_handoff answers 409 until the
--   migration lands (no stamp, no ask, nothing wrong recorded — the sweep needs nothing).
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 216's header and the REGISTRY row.

-- ═══ §A ═══
create or replace function confirm_handoff_tx(p_booking uuid, p_uid uuid, p_side text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b           record;
  v_uid       uuid := coalesce(auth.uid(), p_uid);
  v_now       timestamptz := now();
  v_owner_ok  boolean; v_runner_ok boolean; v_both boolean; v_promote boolean;
  v_owner     uuid; v_runner uuid; v_status text; v_cycle uuid; v_ask_to uuid;
begin
  if p_side is null or p_side not in ('owner', 'runner') then raise exception 'bad_side'; end if;
  if v_uid is null then raise exception 'not_signed_in'; end if;

  -- ── THE LOCKED ROW IS THE ONLY THING ANY DECISION BELOW READS ─────────────────────────────
  select id, owner_id, runner_id, status::text as status,
         owner_confirmed_handoff_at, runner_confirmed_handoff_at, handoff_cycle_id, handoff_cycle_at
    into b
  from bookings where id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ── party gate BEFORE state gate (repo law), on the locked row — the mirror order ──────────
  -- A re-match that committed before this lock has replaced the runner: the old runner is a
  -- stranger to this row now, and their confirmation lands nowhere (0184's party-scoped stamp,
  -- moved under the lock so the promotion below sees the same parties).
  if p_side = 'owner'  and b.owner_id  is distinct from v_uid then raise exception 'not_party'; end if;
  if p_side = 'runner' and b.runner_id is distinct from v_uid then raise exception 'not_party'; end if;

  -- ── state gate ─────────────────────────────────────────────────────────────────────────────
  -- Already handed off: a re-tap (a stale push, a remount) is a silent success, nothing written,
  -- nobody told — the edge's own rule since 0184's returned-row decision.
  if b.status in ('picked_up', 'active') then
    return jsonb_build_object('unchanged', true, 'promoted', false,
                              'both', (b.owner_confirmed_handoff_at is not null and b.runner_confirmed_handoff_at is not null),   -- the row, not an assertion
                              'ask_to', null,
                              'status', b.status, 'owner_id', b.owner_id, 'runner_id', b.runner_id,
                              'handoff_cycle_id', b.handoff_cycle_id);
  end if;
  -- `confirmed` and `runner_enroute` are the two states a handoff is confirmed from (0047's map:
  -- both → picked_up; sweep ⓒ's own pair). Anything else is a stamp on a booking that is not
  -- being handed over — refused by name instead of stamped and left for the map to refuse later.
  if b.status not in ('confirmed', 'runner_enroute') then raise exception 'wrong_status'; end if;

  -- ── a stamp is THIS cycle's only if it is not older than the cycle's boundary ─────────────
  -- `handoff_cycle_at` (0182) is the database time of the latest runner change or stamp reset;
  -- NULL = the row never had one (a legitimate stamp is then simply present).
  v_owner_ok  := b.owner_confirmed_handoff_at  is not null and coalesce(b.owner_confirmed_handoff_at  >= b.handoff_cycle_at, true);
  v_runner_ok := b.runner_confirmed_handoff_at is not null and coalesce(b.runner_confirmed_handoff_at >= b.handoff_cycle_at, true);
  v_both      := (p_side = 'owner' or v_owner_ok) and (p_side = 'runner' or v_runner_ok);
  v_promote   := v_both and b.runner_id is not null;                     -- the status is eligible (gated above)

  -- ── THE STAMP AND THE PROMOTION ARE ONE STATEMENT ─────────────────────────────────────────
  -- Every column below is decided from the locked row: the caller's stamp (kept if already this
  -- cycle's, else set now), the counterparty's stamp (kept if this cycle's, else CLEARED — a stamp
  -- from another pairing never completes this one, and clearing it starts a fresh cycle by the
  -- 0183 trigger so the ask below carries the cycle the row is actually in), and the status.
  -- Two shapes on purpose: `status` is in the SET list only when it changes, so a stamp-only
  -- confirm does not fire the `after update of status` triggers (custody, segments, live
  -- activity, axes) for nothing.
  if v_promote then
    update bookings
       set owner_confirmed_handoff_at  = case when p_side = 'owner'  then (case when v_owner_ok  then owner_confirmed_handoff_at  else v_now end)
                                             when v_owner_ok  then owner_confirmed_handoff_at  else null end,
           runner_confirmed_handoff_at = case when p_side = 'runner' then (case when v_runner_ok then runner_confirmed_handoff_at else v_now end)
                                             when v_runner_ok then runner_confirmed_handoff_at else null end,
           status                      = 'picked_up'::booking_status
     where id = p_booking
     returning owner_id, runner_id, status::text, handoff_cycle_id into v_owner, v_runner, v_status, v_cycle;
  else
    update bookings
       set owner_confirmed_handoff_at  = case when p_side = 'owner'  then (case when v_owner_ok  then owner_confirmed_handoff_at  else v_now end)
                                             when v_owner_ok  then owner_confirmed_handoff_at  else null end,
           runner_confirmed_handoff_at = case when p_side = 'runner' then (case when v_runner_ok then runner_confirmed_handoff_at else v_now end)
                                             when v_runner_ok then runner_confirmed_handoff_at else null end
     where id = p_booking
     returning owner_id, runner_id, status::text, handoff_cycle_id into v_owner, v_runner, v_status, v_cycle;
  end if;
  if v_status is null then raise exception 'not_found'; end if;   -- unreachable under the lock; fail closed rather than notify from nothing

  -- the party who has NOT confirmed this cycle is the one to ask — from the row as written
  v_ask_to := case when v_both then null when p_side = 'owner' then v_runner else v_owner end;
  return jsonb_build_object('unchanged', false, 'promoted', v_promote, 'both', v_both, 'ask_to', v_ask_to,
                            'status', v_status, 'owner_id', v_owner, 'runner_id', v_runner,
                            'handoff_cycle_id', v_cycle);
end $$;
revoke execute on function confirm_handoff_tx(uuid, uuid, text) from public, anon, authenticated;
grant  execute on function confirm_handoff_tx(uuid, uuid, text) to service_role;
comment on function confirm_handoff_tx(uuid, uuid, text) is
  '0185: one party''s handoff confirmation — party gate on the LOCKED row (for update), status gate, then the stamp and the picked_up promotion in ONE statement decided on that row (both stamps, both this cycle''s, confirmed|runner_enroute, a runner). A counterparty stamp older than handoff_cycle_at is another pairing''s: cleared, that party re-asked. A re-tap keeps the first stamp. service_role only; p_uid is the caller the edge verified (auth.uid() wins when present). Raises not_signed_in · bad_side · not_found · not_party · wrong_status. Returns the row as the statement left it: {unchanged, promoted, both, ask_to, status, owner_id, runner_id, handoff_cycle_id}. codex 0184 #1 (custody without confirmation).';

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
        -- [0185] AND AN OBSERVED ANSWER WAKES A `no_response` ROW (codex 0184 #2): the candidate
        -- query admits `no_response` rows so a late answer can still become a verdict, but this arm
        -- wrote only the observation — a late answer met by an unnamed fault left the row
        -- `no_response` with a detail blaming the transport, uncounted by `stuck_unreadable`
        -- (`sent` only) and gone from every health view after 24 h. The tick DID get an answer:
        -- it goes back to `sent`, the obsolete verdict (detail, resolved_at) is cleared, and the
        -- health view counts it until the fault clears. CAS'd on the outcome: a verdict another
        -- tick completed meanwhile (accepted/rejected/failed) is never overwritten by evidence
        -- about a read that failed — the two-connection case is `90_race_check.sh` RV.
        update billing_key_dispatch_ticks
           set outcome              = 'sent',
               detail               = case when outcome = 'no_response' then null else detail end,
               resolved_at          = case when outcome = 'no_response' then null else resolved_at end,
               response_observed_at = coalesce(response_observed_at, now()),
               reconcile_error      = left(sqlstate || ': ' || sqlerrm, 300)
         where id = r.tick_id
           and outcome in ('sent', 'no_response');
        raise notice 'reconcile_billing_key_dispatch_ticks: tick % — not a verdict (%), kept as sent: %', r.tick_id, sqlstate, sqlerrm;
        continue;
      end if;
      update billing_key_dispatch_ticks
         set outcome = 'failed', status_code = r.status_code,
             detail = left('reconciler could not read this answer: ' || sqlerrm, 300),
             resolved_at = now(),
             response_observed_at = coalesce(response_observed_at, now()),   -- [0184]
             reconcile_error      = null                                     -- [0184] the error became the verdict, in `detail`
       where id = r.tick_id
         and outcome in ('sent', 'no_response');                             -- [0185] never over a verdict another tick completed
      get diagnostics v_n = row_count; v_changed := v_changed + v_n;         -- [0185] a CAS that matched nothing changed nothing
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

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 216 ═══
do $$
declare v_oid oid; v_src text; v_bad text := ''; v_n int;
begin
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'confirm_handoff_tx';
  if v_oid is null then raise exception '0185 VERIFY FAILED: A:NO-FUNCTION'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:NO-IN-BODY-SEARCH-PATH'; end if;
  if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:public-EXECUTE'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' A:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' A:NO-SOURCE';
  else
    if (v_src ~ 'from bookings where id = p_booking for update;') is distinct from true then v_bad := v_bad || ' A:NO-ROW-LOCK'; end if;
    if (position('raise exception ''not_party''' in v_src) > 0 and position('raise exception ''not_party''' in v_src) < position('update bookings' in v_src)) is distinct from true then v_bad := v_bad || ' A:PARTY-GATE-NOT-BEFORE-THE-WRITE'; end if;
    if (position('for update;' in v_src) > 0 and position('raise exception ''not_party''' in v_src) > 0 and position('for update;' in v_src) < position('raise exception ''not_party''' in v_src)) is distinct from true then v_bad := v_bad || ' A:PARTY-GATE-BEFORE-THE-LOCK'; end if;
    -- the promotion rides the SAME statement as the stamp: one UPDATE sets both stamps and picked_up
    if (v_src ~ 'update bookings\s+set owner_confirmed_handoff_at[^;]*runner_confirmed_handoff_at[^;]*status\s+= ''picked_up''::booking_status\s+where id = p_booking\s+returning') is distinct from true then v_bad := v_bad || ' A:PROMOTION-NOT-IN-THE-STAMP-STATEMENT'; end if;
    select count(*) into v_n from regexp_matches(v_src, '''picked_up''::booking_status', 'g');
    if v_n is distinct from 1 then v_bad := v_bad || ' A:PICKED_UP-WRITES(' || v_n || '/1 — a second promotion statement)'; end if;
    select count(*) into v_n from regexp_matches(v_src, '>= b\.handoff_cycle_at, true\)', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' A:CYCLE-BOUNDARY-CONJUNCTS(' || v_n || '/2)'; end if;
    if (v_src ~ 'v_promote\s+:= v_both and b\.runner_id is not null') is distinct from true then v_bad := v_bad || ' A:PROMOTION-NOT-BOTH-STAMPS'; end if;
    if (v_src ~ 'if b\.status not in \(''confirmed'', ''runner_enroute''\) then raise exception ''wrong_status''') is distinct from true then v_bad := v_bad || ' A:NO-STATUS-GATE'; end if;
  end if;
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then raise exception '0185 VERIFY FAILED: B:NO-FUNCTION'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NOT-DEFINER'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:CLIENT-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
  else
    -- the unreadable-answer arm wakes a no_response row: outcome back to sent, the stale verdict cleared
    if (v_src ~ 'set outcome              = ''sent'',\s+detail               = case when outcome = ''no_response'' then null else detail end,\s+resolved_at          = case when outcome = ''no_response'' then null else resolved_at end,') is distinct from true then v_bad := v_bad || ' B:NO_RESPONSE-NOT-WOKEN-BY-AN-OBSERVED-ANSWER'; end if;
    -- …and both exception-arm writes are CAS'd against a concurrent completed verdict
    select count(*) into v_n from regexp_matches(v_src, 'where id = r\.tick_id\s+and outcome in \(''sent'', ''no_response''\);', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:EXCEPTION-WRITES-UNGUARDED(' || v_n || '/2)'; end if;
    -- 0184's arms, still there
    select count(*) into v_n from regexp_matches(v_src, 'response_observed_at = coalesce\(response_observed_at, now\(\)\)', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:OBSERVATION-STAMPS(' || v_n || '/3)'; end if;
    if (v_src ~ 'and response_observed_at is null\s+and not exists \(select 1 from net\._http_response h where h\.id = request_id\)') is distinct from true then v_bad := v_bad || ' B:NO_RESPONSE-IGNORES-THE-RECORD'; end if;
    if (v_src ~ 'or t\.response_observed_at is not null\)') is distinct from true then v_bad := v_bad || ' B:TTL-STILL-BLOCKS-AN-OBSERVED-TICK'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' B:VERDICT-FILTER-MISSING'; end if;
  end if;
  if v_bad <> '' then raise exception '0185 VERIFY FAILED:%', v_bad; end if;
end $$;
