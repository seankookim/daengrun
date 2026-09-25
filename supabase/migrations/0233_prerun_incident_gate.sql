-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0233 — a runner who only tapped 도착 is no longer work-gated forever · a pre-run incident review
--        finally rings an operator and has a list
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 264_prerun_incident_gate_suite.sql (tag `pig`) — 0233-G1 · G2 · G3 · G4 · R1 · B1 · B2 ·
--        B3 · L1 · S1
-- Gap sweep 2 P5 · M1 (docs/reviews/2026-09-25-gap-sweep-2-final.md §P5). 0234 is M2 (incidents).
--
-- ═══ §0a WHAT IS WRONG, READ ON `cloud/0232-sweep-honesty-route-gate` @ 54dfae7 ═══════════════════
--   (1) `_resolve_checkin` (0117:608-715) moves a booking to `incident_review` whenever the late
--       protocol's clock resolves with EVIDENCE on the row — and `arrived_at` alone is evidence
--       (0117:608-610): a runner who tapped 도착 at the door and whose owner never came out. That
--       row has no handoff stamp and no `run_ended_at`: the dog never left home. But
--       `_runner_work_gate_blocking` (0224:1112-1119) gates on `incident_review` UNCONDITIONALLY,
--       and every exit a runner or an operator has raises `run_not_ended` on it
--       (`confirm_return_tx` 0193:236, `ops_resolve_return_tx` 0224:1686, `force_return_tx`
--       0218:265). So the runner is refused new work forever, and `ops_gated_runners` (0224:1182,
--       :1208) lists the row with a remedy — `confirm_return_tx` — that raises.
--   (2) Every `incident_review` with `run_ended_at IS NULL` — the arrived-only arm above, the
--       `picked_up`-no-run arm (0117:652-656) and the pre-custody evidence arms — rings NO operator
--       and is on NO ops list: `sweep_run_end_recovery` arm ⓕ (0226:437-445) and
--       `ops_stranded_returns()` (0206:171) both require `run_ended_at is not null`.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `_runner_work_gate_blocking` — 0224 §E's text, copied BY SCRIPT, ONE edit: the incident arm
--      becomes `(incident_review AND (run_ended_at not null OR a handoff stamp exists))`. The dog
--      was out ⇒ the gate still holds (the three gated variants 264 `0233-G2/G3/G4` pin); the dog
--      never left home ⇒ the gate lets the runner work (`0233-G1`).
--   §B `ops_gated_runners` — 0224 §E's text, copied BY SCRIPT, TWO edits: the same incident arm, so
--      the list is still exactly the gate's set; and an `incident_review` row with `run_ended_at`
--      NULL (the gated pre-run shapes: a handoff stamp, no run) names NO door — 0224 §0c's idiom —
--      instead of `confirm_return_tx`, which raises `run_not_ended` on exactly that row.
--   §C `_sweep_prerun_incidents()` — arm ⓗ, its OWN function (0224 §C's reasons, restated there).
--      Marketplace `incident_review` with `run_ended_at` NULL → the `return_strand` roster ONCE per
--      booking (0226 arm ⓕ's one-shot title on `ref_id`), an EMPTY roster writes nothing and is
--      retried every tick. No threshold: `incident_review` is already the state that means 「a
--      human must look」 — a clock nobody chose would only delay the look.
--   §D `sweep_run_end_recovery` — 0226 §A's body, copied BY SCRIPT, ONE insertion: the call to arm
--      ⓗ after arm ⓖ. Arms ⓐ–ⓖ, the handler count (7) and the lock counts (5/5) are 0226's, byte
--      for byte (the build script asserts the round trip).
--   §E `_noti_ops_titles()` — 0224 §G's ledger plus arm ⓗ's title (15).
--   §F `ops_prerun_cases()` — the roster's READ of the same set. Zero arguments, the
--      `return_strand` roster gate FIRST, flat whitelisted columns, no money, no contact field, no
--      memo — 0224 §F's shape. It carries `runner_gated` so an operator can see which of these
--      rows still hold a runner (the handoff-stamped ones) and which do not.
--
-- ═══ §0c WHAT THIS FILE DELIBERATELY DOES NOT DO — each one a decision, not an omission ═══════
--   · **NO resolve/close door for a pre-run incident_review** (gap sweep 2 §P5 DO NOT BUILD, letters
--     L2/L3). The list and the bell name no remedy; `ops_gated_runners`' remedy text says 「no door
--     exists — pre-run incident; awaiting Sean ruling」. A pre-run incident that DID hold the dog
--     (a handoff stamp, no run) still gates its runner and still has no exit: that is the honest
--     state until Sean rules, and it is now LISTED and BELLED rather than silent.
--   · ⚠ **OPEN QUESTION FOR SEAN — a ONE-sided handoff stamp is knowingly left as a permanent
--     lockout until he rules** (executing review of 8682181, finding 2 — READ, not measured on a
--     device). §A gates on EITHER stamp, as the gap-sweep brief specified (「one handoff stamp →
--     gated」). That shape is reachable and is not a handoff in flight: 0117's ceiling arm
--     (0117:565-580) ends a one-stamp booking `runner_enroute → incident_review` precisely because 「at
--     the ceiling a one-stamp booking is rotted, not mid-handoff」, and the handoff never promoted
--     (0185:103-133 promotes only on BOTH stamps). Every other custody predicate in the repo requires
--     BOTH stamps (0072:66, 0116:452, 0121:284, 0152:80). So such a runner is refused new work with no
--     door — the very lockout this file removes for the arrived-only row. Two rulings would end it:
--     L2/L3 (a door), or the predicate moved to BOTH stamps (the one-stamp row then joins the
--     arrived-only row: not gated, still listed and belled). 264 `0233-G2` pins the current rule and
--     is the pin that moves if he rules the second way.
--   · `confirm_return_tx`, `my_booking_payment_state` and the client's `work-gate-strip.ts` copy are
--     untouched (DO NOT BUILD). `runner_work_gate` is not re-declared — it reads §A by name.
--   · Clubs are out of scope (`club_session_id is not null` → neither the gate arm, the bell nor the
--     list), as in every other arm of the gate and the sweep.
--   · The bell's roster is `return_strand` — the roster that already owns the custody and return
--     strand lists, and whose console desk (`ops/custody.tsx`) draws §F. No new class here (0234
--     adds `incident_opened` for incidents REPORTED through `open_incident_tx`, a different event).
--
-- ═══ §0d WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES, each from the highest declaring migration on this tree (grepped; 0232 re-declares
--   none of them):
--     `_runner_work_gate_blocking(uuid)` ←0224 §E (copied by script; one edit)
--     `ops_gated_runners()`             ←0224 §E (copied by script; two edits)
--     `sweep_run_end_recovery()`        ←0226 §A (copied by script; one insertion)
--     `_noti_ops_titles()`              ←0224 §G (copied by script; +1 title) — 0234 re-declares it again
--   CREATES: `_sweep_prerun_incidents()`, `ops_prerun_cases()`. Every ACL is restated in THIS file.
--   ⚠ A later slice re-declaring `sweep_run_end_recovery` must keep the call to
--     `_sweep_prerun_incidents()` (264 `0233-S1`) beside 0226's list.
--
-- ═══ §0e SHIPPED PINS THAT MOVE, AND WHY ═════════════════════════════════════════════════════
--   · `245 0214-T1` — the ledger grows (0233 +1, 0234 +3 → 18); its spelled-out list gains them.
--     `0214-T4` — `_sweep_prerun_incidents` (and 0234's `open_incident_tx`) join SYSTEM_WRITERS.
--     264 `0233-B2` / 265 `0234-B2` own the new titles against what the writers actually wrote.
--   · `app/test/notification-prefs.test.cjs` ⑦ gains the two families; `notification-route.test.cjs`'s
--     「exactly the seven ops titles」 becomes eleven.
--
-- ═══ §0f DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body · every ACL restated here · roster gate
-- before any read · every candidate predicate re-asserted on the LOCKED row · `is true` / `is not
-- true`, never a bare `IF` on a nullable predicate · comments stripped before every `prosrc` match.
--
-- ═══ §0g INACTION, ENUMERATED ════════════════════════════════════════════════════════════════
--   | state                                          | gated? | swept by            | listed by          | exit            |
--   |------------------------------------------------|--------|---------------------|--------------------|-----------------|
--   | incident_review, arrived_at only (no stamps)   | NO     | ⓗ (return_strand)   | ops_prerun_cases   | none — Sean's L2/L3 |
--   | incident_review, BOTH stamps, no run (picked_up) | yes  | ⓗ                   | ops_prerun_cases · ops_gated_runners | none — Sean's L2/L3 |
--   | incident_review, ONE stamp, no run (0117 ceiling) | yes  | ⓗ                   | ops_prerun_cases · ops_gated_runners | none — PERMANENT until Sean rules (§0c) |
--   | incident_review, run ended                     | yes    | ⓕ (0193, threshold) | ops_stranded_returns · ops_gated_runners | ops_resolve_return_tx / confirm_return_tx |
--   | any of the above, roster empty                 | —      | ⓗ retried every tick | still listed     | —               |
--
-- ═══ §0h DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   `supabase db push` (with 0234). Client build for the console rows (ops/custody.tsx, ops/index.tsx)
--   and the two new RPCs are on `PENDING_DEPLOY` until then. `ops_recipients` needs an active
--   `return_strand` row or arm ⓗ's bell delivers to nobody (the notice says so every tick).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A _runner_work_gate_blocking — the incident arm asks whether the dog was ever out
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §E's text, copied BY SCRIPT; the only edit is the marked incident arm. `run_ended_at`, then
-- either handoff stamp: a stamp is the first moment the product records the dog changing hands
-- (0117:608-610 lists `arrived_at` beside them as EVIDENCE of a human acting, not of custody).
create or replace function _runner_work_gate_blocking(p_runner uuid)
returns table (
  booking_id uuid,
  status text,
  run_ended_at timestamptz,
  runner_confirmed boolean,
  owner_confirmed boolean,
  waiting_on text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.id,
         b.status::text,
         b.run_ended_at,
         b.runner_confirmed_return_at is not null,
         b.owner_confirmed_return_at  is not null,
         -- [0224] a stranded custody names ITS exit; otherwise 0092 §6's words, unchanged —
         -- "확인해주세요" to a runner who has already stamped is a lie about their own action.
         coalesce(x.shape,
                  case
                    when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
                      then 'both'
                    when b.runner_confirmed_return_at is null then 'runner'
                    else 'owner'
                  end)
    from bookings b
    left join lateral (
      select cs.shape
        from _custody_strand(b.id) cs
       where b.status::text in ('picked_up', 'active')
         and cs.stranded is true
    ) x on true
   where b.runner_id = p_runner
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and b.club_session_id is null          -- clubs run their own custody machine (0045/0069)
     and (
           -- the run stopped and the dog is not confirmed home (0083's 귀가 window)
           (b.run_ended_at is not null and b.status::text = 'active')
           -- or the booking went sideways with the dog still out — ⑫'s own case
           -- [0233 §A] …and ONLY when the dog was ever out: the run ended, or a handoff stamp exists.
           --   An incident_review reached by a runner who only tapped 도착 (0117 _resolve_checkin's
           --   evidence arm) has no exit — every return door raises run_not_ended — so gating it
           --   locked the runner out forever for a dog that never left home.
           or (b.status::text = 'incident_review'
               and (b.run_ended_at is not null
                    or b.owner_confirmed_handoff_at is not null
                    or b.runner_confirmed_handoff_at is not null))
           -- [0224] or the runner holds the dog and the run has STRANDED — never started, or never
           -- stopped, past the threshold Sean sets (NULL ⇒ this arm admits nothing)
           or x.shape is not null
         )
   order by b.run_ended_at nulls last, b.id
   limit 1
$$;

revoke execute on function _runner_work_gate_blocking(uuid) from public, anon, authenticated;
grant  execute on function _runner_work_gate_blocking(uuid) to service_role;

comment on function _runner_work_gate_blocking is
  '0092 §6 + 0224 §E + 0233 §A: the single oldest booking blocking this runner from new work. Arms:
run stopped + return unconfirmed; incident_review ONLY when the dog was ever out (run_ended_at, or a
handoff stamp — 0233: an incident_review reached by a runner who only tapped 도착 has no exit, every
return door raises run_not_ended, so gating it locked the runner out forever); a marketplace custody
STRANDED per _custody_strand (0224). NOT a live run. waiting_on start_run / end_run come first.
service_role only. 255 0224-A3 · 264 0233-G1..G4 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ops_gated_runners — the same arm, and a pre-run incident names no door
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §E's text, copied BY SCRIPT, two edits. ⚠ The remedy arm for a run_ended_at-NULL
-- incident_review comes BEFORE 0096's 「either party may confirm_return_tx」 arm: `confirm_return_tx`
-- raises `run_not_ended` on exactly that row (0193:236), so the old sentence named a door that fails.
create or replace function ops_gated_runners()
returns table (
  runner_id uuid,
  booking_id uuid,
  status text,
  gated_since timestamptz,
  waiting_on text,
  remedy text
)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.runner_id,
         b.id,
         b.status::text,
         coalesce(x.due_at, b.run_ended_at, b.updated_at, b.scheduled_at),
         coalesce(x.shape,
                  case
                    when b.runner_confirmed_return_at is null and b.owner_confirmed_return_at is null
                      then 'both'
                    when b.runner_confirmed_return_at is null then 'runner'
                    else 'owner'
                  end),
         case
           when x.shape = 'start_run' then 'the runner starts the run (start_run) — no ops door ends a custody strand; that is Sean''s letter (0224 §0c)'
           when x.shape = 'end_run'   then 'the runner stops the run (end_run) — no ops door ends a custody strand; that is Sean''s letter (0224 §0c)'
           -- [0233 §B] a gated incident_review whose run never ended: every return door raises
           --   run_not_ended there (confirm_return_tx 0193:236 · ops_resolve_return_tx 0224:1686 ·
           --   force_return_tx 0218:265), so the old sentence below named a door that fails
           when b.status::text = 'incident_review' and b.run_ended_at is null then 'no door exists — pre-run incident; awaiting Sean ruling (every return door refuses a run that never ended)'
           when b.status::text = 'incident_review' then 'either party may confirm_return_tx — allowed from incident_review since 0096; clears the gate without settling'
           else 'either party may confirm_return_tx as normal'
         end
    from bookings b
    left join lateral (
      select cs.shape, cs.due_at
        from _custody_strand(b.id) cs
       where b.status::text in ('picked_up', 'active')
         and cs.stranded is true
    ) x on true
   where b.runner_id is not null
     and b.club_session_id is null
     and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null)
     and (
           (b.run_ended_at is not null and b.status::text = 'active')
           -- [0233 §B] the gate's incident arm, verbatim (§A) — the list is exactly the gated set
           or (b.status::text = 'incident_review'
               and (b.run_ended_at is not null
                    or b.owner_confirmed_handoff_at is not null
                    or b.runner_confirmed_handoff_at is not null))
           or x.shape is not null
         )
   order by coalesce(x.due_at, b.run_ended_at, b.updated_at, b.scheduled_at), b.id
$$;

revoke execute on function ops_gated_runners() from public, anon, authenticated;
grant  execute on function ops_gated_runners() to service_role;

comment on function ops_gated_runners is
  '0096 §7 + 0224 §E + 0233 §B — every runner currently held by the work gate, one row per blocking
booking, with the remedy by name. The same predicate as _runner_work_gate_blocking (0233: incident_review
gates only when the dog was ever out). A gated incident_review with no run_ended_at names NO door —
every return door raises run_not_ended there; resolving it is Sean''s letter (L2/L3). A query
function, not a pager. service_role only. 255 0224-A3 · 264 0233-R1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C _sweep_prerun_incidents — arm ⓗ
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Called by `sweep_run_end_recovery` (§D) on every tick, inside that tick's job lock.
-- ⚠ ITS OWN FUNCTION, for 0224 §C's two reasons: a suite can drive it without re-running arms ⓐ–ⓖ
--   over every other suite's leftovers, and the sweep's own lock/handler-count pins (219 `0188-B4`,
--   214 `0183-E6`, 232 `0201-S1`) keep describing that body. 264 `0233-S1` pins this one.
-- ⚠ THE SAME JOB LOCK (re-entrant inside a tick; a standalone call while a tick runs is skipped).
-- ⚠ ONCE PER BOOKING by 0226 arm ⓕ's idiom: a row with this title for this booking is a bell already
--   rung. The candidate query EXCLUDES belled rows so the set drains once a roster exists; while the
--   roster is empty nothing is written and every tick tries again (durable PENDING — an escalation
--   recorded as delivered when nobody received it is worse than an unmonitored state, 0096 §4).
--   Oldest first (`updated_at`, then id) so a `limit` can never permanently shadow a newer row
--   behind older ones that merely have smaller ids (cold review 0188 #3).
-- ⚠ LOCK, THEN LOOK AGAIN: `for update skip locked`, every candidate predicate re-asserted on the
--   locked row, the one-shot re-taken under the lock (arm ⓑ's law).
-- ⚠ BELL IDENTITY (executing review of 8682181, finding 1 — MEASURED there): a row counts as 「the
--   bell already rang」 only when it is kind `system` AND addressed to someone who is or was seated at
--   `return_strand` (`ops_recipients`, active or not — a deactivated operator's bell was still
--   delivered). Matching on (ref_id, title) alone let a booking PARTY silence the bell: 0114's
--   `noti party insert` admits `kind='booking'` rows with any title on a booking the caller is
--   party to (incident_review included), and `noti self update` (0002, USING-only) lets ANY signed-in
--   user rewrite one of their own rows' kind/title/ref_id/created_at — so `kind = 'system'` alone is
--   not enough; the recipient conjunct is what a client cannot forge. `ops_recipients` has no client
--   write door (0208). The same identity is used by §F's `notified_at`. 264 `0233-B4` pins both.
--   Residual, named: a profile once seated at `return_strand` can still forge one on their own row —
--   an operator, the role this bell exists to reach. If every such row's recipient later deletes
--   their account (0115 deletes the roster row) the bell rings again for the current roster.
-- ⚠ The ops row carries NO identifier and NO amount (0084 §E); the booking rides in `ref_id`. The
--   title is a CONSTANT, so `app/test/ops-system-titles.test.cjs` resolves it to a literal.
-- ⚠ One protected block around the loop (0224 §C's outer handler): a surprise outside any row rolls
--   back THIS arm's writes and nothing else, so the caller's arms ⓐ–ⓖ keep their tick.
create or replace function _sweep_prerun_incidents() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_b record; n int := 0; v_ops int;
  c_batch constant int := 50;
  c_ops_class constant text := 'return_strand';
  c_prerun_ops_title constant text := '러닝 전 사고 검토 — 확인 필요';
  c_prerun_ops_body  constant text := '러닝이 시작되기 전에 사고 검토로 넘어간 예약이 있어요. 예약을 확인해 주세요.';
begin
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice '_sweep_prerun_incidents: another tick holds the job lock — skipped';
    return 0;
  end if;

  begin
  for r in
    select b.id
      from bookings b
     where b.status = 'incident_review'
       and b.run_ended_at is null
       and b.club_session_id is null
       and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.title = c_prerun_ops_title
                          -- [0233 fix] the bell's OWN row, not a look-alike (see ⚠ BELL IDENTITY)
                          and nt.kind = 'system'
                          and exists (select 1 from ops_recipients orr
                                       where orr.profile_id = nt.profile_id
                                         and orr.event_class = c_ops_class))
     order by b.updated_at, b.id
     limit c_batch
  loop
    begin
      select b.id, b.status, b.run_ended_at, b.club_session_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice '_sweep_prerun_incidents: % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- every candidate predicate, re-asserted on the LOCKED row
      if (v_b.status = 'incident_review') is not true
         or v_b.run_ended_at is not null
         or v_b.club_session_id is not null then continue; end if;
      -- the candidate read was a snapshot; the one-shot is re-taken under the lock
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_prerun_ops_title
                   and nt.kind = 'system'
                   and exists (select 1 from ops_recipients orr
                                where orr.profile_id = nt.profile_id
                                  and orr.event_class = c_ops_class)) then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_prerun_ops_title, c_prerun_ops_body, v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      raise notice '_sweep_prerun_incidents: booking % — pre-run incident review: % ops recipient(s) for %', v_b.id, v_ops,
        c_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
      if v_ops > 0 then n := n + 1; end if;
    exception when others then
      raise notice '_sweep_prerun_incidents: % — %', r.id, sqlerrm;
    end;
  end loop;
  exception when others then
    raise notice '_sweep_prerun_incidents: arm aborted, its writes rolled back — %', sqlerrm;
    n := 0;
  end;

  return n;
end $$;

revoke execute on function _sweep_prerun_incidents() from public, anon, authenticated;
grant  execute on function _sweep_prerun_incidents() to service_role;

comment on function _sweep_prerun_incidents is
  '0233 §C — sweep_run_end_recovery arm ⓗ: a marketplace booking in incident_review whose run never
ended (arrived-only, picked_up-no-run and the pre-custody evidence arms of 0117 _resolve_checkin)
rings the return_strand roster ONCE per booking — title 「러닝 전 사고 검토 — 확인 필요」, kind system,
identifier-free body, ref_id = the booking. An empty roster writes nothing and is retried every tick.
No threshold, no status move, no door (L2/L3 are Sean''s). Locked, re-checked, bounded; runs inside
the sweep''s job lock. service_role only. 264 0233-B1/B3/S1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D sweep_run_end_recovery — 0226 §A's body, one insertion
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT from 0226's text. The one insertion is arm ⓗ's call, after arm ⓖ's; the build
-- script asserted removing it returns 0226's body byte for byte.
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0188] arm ⓑ-②'s one-shot alarm: a return ONE side has confirmed and the other has not.
  -- A DISTINCT title from the escalation's 「귀가 확인이 필요해요」 so neither dedupe key can
  -- silence the other, and so the client can route them apart. `notification-route.ts` routes it
  -- (runner → /runner/return-seal · owner → the bid-scoped report) and
  -- `app/test/notification-route.test.cjs` reads THIS constant out of THIS file, so the two
  -- spellings cannot drift (the c_esc_title idiom, 0182).
  c_ret_title     constant text := '반환 확인이 멈춰 있어요';
  -- to the side that has NOT stamped …
  c_ret_body_ask  constant text := '러닝이 끝났는데 반환 확인이 아직이에요 — 앱에서 인계를 확인해주세요';
  -- … and to the side that HAS. Never the first sentence: telling someone to confirm what they
  -- already confirmed is a lie about their own action (0092 §6).
  c_ret_body_wait constant text := '내 반환 확인은 끝났고 상대방 확인을 기다리고 있어요 — 확인되면 정산이 마무리돼요';
  -- [0181] arm ⓒ: how long a one-sided handoff may sit with no ask row before the sweep re-sends
  -- the ask, and how far an ask row may PRECEDE the stamp it answers (the edge stamps with its
  -- own clock, the row is stamped by the database's) and still count as that stamp's ask.
  ASK_AFTER constant interval := interval '5 minutes';
  -- the edge's exact strings (`transition-booking/index.ts`, case confirm_handoff): `push.ts`
  -- routes the runner by EXACT title, and the inbox must show one ask, not two spellings of it.
  c_ask_title constant text := '인계 확인 요청';
  c_ask_body  constant text := '상대방이 인계를 확인했어요 — 확인해주세요';
  -- [0182] arm ⓓ: how long a handoff may stay one-sided — ask delivered or not — before both
  -- parties and the ops roster are told ONCE for this cycle. 30 min: the re-send (arm ⓒ) lands
  -- 5–15 min after the stamp, so the re-sent ask has had at least 15 min to be answered.
  ESCALATE_AFTER constant interval := interval '30 minutes';
  c_esc_title constant text := '인계 확인이 멈춰 있어요';
  c_esc_body  constant text := '인계 확인이 한쪽만 된 채 30분이 지났어요 — 담당자가 확인하고 있어요';
  c_ops_class constant text := 'handoff_unanswered';
  -- [0182] the statuses in which a pickup handoff is NOT underway — the same fourteen arm ⓒ's
  -- candidate query names literally (212 C8 anchors on that literal); this constant is what the
  -- re-checks and arm ⓓ use, and VERIFY / 213 D7 assert the two spellings are identical.
  c_dead constant booking_status[] := array['draft','quoted','payment_hold','matching','runner_pending',
                                            'picked_up','active','completed',
                                            'cancelled_owner','cancelled_runner','expired','no_show',
                                            'incident_review','refund_pending']::booking_status[];
  -- [0182] rows served per tick per arm (ⓒ, ⓓ): every row lock these arms take is held to
  -- commit, and a counterparty's confirm (a plain UPDATE, no NOWAIT) waits behind it — so the
  -- number held is bounded, the arms are idempotent, and the rest wait for the next tick, ten
  -- minutes away (cold review 0182 #6; late_booking_sweep's `limit 5` is the precedent, 0126:61).
  c_batch constant int := 50;
  v_b record; v_cp uuid; v_st timestamptz; v_ops int;
  v_cid uuid;   -- [0183] the cycle the locked row is in, minted on the spot if it has none (legacy)
  -- [0193 §D] arm ⓕ. A DURATION read from `ops_flags` at the top of the arm, not a constant: the
  -- number is Sean's ruling (queue item 23) and NULL — the shipped value — means the arm does
  -- nothing at all. The ops class is its own, not `payout_due`'s: the people who can END a strand
  -- (`ops_resolve_return_tx` gates on exactly this roster) are the people who should be told.
  c_strand_ops_class constant text := 'return_strand';
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  -- NO id and NO amount in the body (0084 §E: a wrong recipient id pushes the body verbatim to a
  -- stranger's lock screen). The booking id rides in `ref_id`, as 0155/0166/0182 do.
  c_strand_body  constant text := '러닝이 끝났는데 반환 확인이 끝나지 않은 예약이 있어요. 예약을 확인해 주세요.';
  v_strand_min int;
  -- [0224 §D ①] arm ⓐ's OPERATOR bell. `payout_due` — a sealed-but-unsettled run is a runner owed
  -- money, the class 0084 §E pages for money. Its own one-shot title (NOT the parties'), so a row
  -- whose parties were told before 0224 still rings once. NO id and NO amount in the body (0084 §E).
  c_seal_ops_class constant text := 'payout_due';
  c_seal_ops_title constant text := '정산 미완료 — 확인 필요';
  c_seal_ops_body  constant text := '인계는 확인됐는데 정산이 마무리되지 않은 예약이 있어요. 예약을 확인해 주세요.';
begin
  -- [0181] ONE tick at a time (0117's job-lock idiom; 0177 gave owner-la the same): arm ⓐ's
  -- one-shot alarm and arm ⓒ's re-send are both read-then-write on `notifications`, and two
  -- overlapping ticks would each see no row and each insert (audit M10's class). A TRY-lock, so
  -- a slow predecessor is skipped and never queued; transaction-scoped, so any raise below
  -- releases it with no unlock to forget. `90_race_check.sh` RL measures the skip with two
  -- processes; 212 C8 sees the lock held after the call.
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice 'sweep_run_end_recovery: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- [0182] the bounded wait (0117 MINOR-14, 0180 §A's value): ⓒ/ⓓ never wait (skip locked), but
  -- arm ⓑ's UPDATE can, and a sweep stalled there holds every row lock ⓒ already took.
  perform set_config('lock_timeout', '2000', true);
  -- ⓐ report every sealed-but-unsettled row. The runner is owed money on a booking whose
  -- settlement died; SQL cannot price it (see the header), so the honest output is a visible
  -- notice per row and a count, not a silent zero.
  for r in
    select b.id, b.owner_id, b.runner_id, b.settlement_ready_at
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.settlement_ready_at is not null
  loop
    raise notice 'sweep_run_end_recovery: booking % is sealed but unsettled since % — settlement needs the pricing path (0083 §0f)',
      r.id, r.settlement_ready_at;
    n := n + 1;
    -- …and after SEAL_ALARM_AFTER, a notice in a cron log is not enough: tell both parties, once.
    -- This alarm deliberately does NOT move the status. The row stays `active`, which is the only
    -- state from which `_settle_sealed_run` can still pay the runner — escalating it to
    -- `incident_review` would trade a slow settlement for an impossible one (see the header).
    -- One-shot by construction: a title that exists for this booking is an alarm already raised.
    -- [0226 §A] ITS OWN SUBTRANSACTION (codex s1). Without it one row whose insert raises — a
    -- recipient row held past this function's own 2 s lock_timeout, or anything else — raised out
    -- of the whole sweep: every earlier row's notice rolled back and arms ⓑ–ⓖ never ran (measured,
    -- 257 `0226-F1` against 0224). A failure is a NOTICE, the one-shot title is not written, and the
    -- next tick tries again. The owner row and the runner row stay in ONE block: the one-shot key is
    -- the title on this booking, so a half-written pair would silence the other half forever.
    begin
      if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
         and not exists (select 1 from notifications nt
                         where nt.ref_id = r.id and nt.title = '정산을 확인하고 있어요') then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.owner_id, 'booking', '정산을 확인하고 있어요',
                '인계는 확인됐는데 정산이 마무리되지 않았어요 — 담당자가 확인하고 있어요', r.id);
        if r.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (r.runner_id, 'booking', '정산을 확인하고 있어요',
                  '인계는 확인됐는데 정산이 마무리되지 않았어요 — 지급은 취소되지 않아요, 담당자가 확인하고 있어요', r.id);
        end if;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: seal-alarm % — the parties'' alarm failed (% %); nothing written, retried next tick',
        r.id, sqlstate, sqlerrm;
    end;
    -- [0224 §D ①] …and the OPERATORS, once, by their own title, at the same age. Until this file
    -- the sentence above — 「담당자가 확인하고 있어요」 — had nobody behind it: no operator was told
    -- and no list showed the row (backend-logic-2). An EMPTY roster writes nothing and is retried
    -- next tick (0193 ⓕ's durable PENDING), and the notice says so rather than reading as sent.
    -- [0226 §A] A SIBLING subtransaction, not nested in the one above and not sharing it: a failing
    -- bell must not roll back the parties' alarm (0210 §E's reason), and a failing alarm must not
    -- skip the bell (which one block around both would do). 257 `0226-F2` pins both directions.
    begin
      if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
         and not exists (select 1 from notifications nt
                         where nt.ref_id = r.id and nt.title = c_seal_ops_title) then
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_seal_ops_title, c_seal_ops_body, r.id
          from ops_recipients_for(c_seal_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — sealed but unsettled past %: % ops recipient(s) for %',
          r.id, SEAL_ALARM_AFTER, v_ops,
          c_seal_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: seal-ops % — the payout_due bell failed (% %); nothing written, retried next tick',
        r.id, sqlstate, sqlerrm;
    end;
  end loop;

  -- ⓑ [0188] THE RUN-END STRAND — narrowed, because what this arm does to a row is a MONEY DEAD
  -- END and this slice is the first thing in the product that can put a row in front of it.
  --
  -- 0083 wrote this arm while `end_run_tx` had ZERO callers, so it has never escalated a real
  -- marketplace 귀가. The run-end ceremony (⑪/⑫) gives it rows for the first time, and the
  -- composition is a defect measured before it shipped:
  --   ① the runner stops (`end_run_tx`) and stamps their own return on R6a seconds later;
  --   ② the owner is slower than STRAND_AFTER — at work, phone silent; two hours is not long;
  --   ③ this arm moves the booking `active → incident_review`;
  --   ④ the owner stamps that evening. 0096 lets the stamp LAND and deliberately does not seal;
  --   ⑤ `_settle_sealed_run` requires `active` (0083 §6) and `enforce_booking_transition` gives
  --      `incident_review` exactly one edge — `refund_pending` (0066:56) — so the run can NEVER
  --      settle. The runner walked the dog, brought it home, BOTH parties said so, and the only
  --      state the money could have moved from is gone.
  -- 0083's own header already refused this shape for SEALED rows ("an owner who simply did not
  -- tap confirm within 2 hours able to render the runner permanently unpayable"). The UNSEALED
  -- row acquires the identical property the moment 0096 makes a late stamp possible — and 0096
  -- landed after 0083, so neither file could see it alone.
  --
  -- ⚠ AND THE ESCALATION BUYS NOTHING IT WAS BOUGHT FOR. Its stated purpose is that `active` is
  -- LIVE to the runner-accept conflict guard, "so the runner's future bookings are blocked by a
  -- dog they returned two days ago". Both halves are false today:
  --   · the block is ⑫'s WORK GATE (0092), which reads the two stamp columns and ALSO catches
  --     `incident_review` (`0092:112-117`) — escalating frees no runner. Pinned: 219 0188-B3.
  --   · the accept-time conflict guard (`transition-booking/index.ts`) compares SCHEDULED
  --     WINDOWS within ±6h, so a two-day-old booking overlaps nothing it could block. READ from
  --     that source, NOT pinned here — it is TypeScript and this is SQL, and per the house law
  --     neither is evidence for the other.
  --
  -- SO: this arm escalates only a return NOBODY has confirmed — zero stamps, which is the state
  -- `incident_review` actually names (the dog is unaccounted for). A row where at least one party
  -- has said the dog is home keeps `active`, and therefore keeps its money path, and is ALARMED
  -- instead: both parties told once, no status move. That is arm ⓓ's own principle, three arms
  -- down and written by a later author for the same class of stuck two-sided confirmation —
  -- "what a stuck pickup handoff should become is a product decision (Sean's), not a clock's".
  --
  -- ⚠ NAMED RESIDUE, deliberately NOT closed here, and stated in FULL because the first draft of
  -- this paragraph named only half of it (cold review #7):
  --   ① a return NOBODY confirms still escalates at STRAND_AFTER, and is still a dead end if both
  --      parties stamp afterwards;
  --   ② AND THE ONE-STAMP ROW THIS ARM NOW PRESERVES HAS ITS OWN NEW TERMINAL. Runner stamps,
  --      owner never does: one notification at 2h, then permanent silence, `active` forever, the
  --      runner work-gated (0092) and unpaid. That is strictly better than the escalation it
  --      replaces — the money path SURVIVES, so a stamp on any later day still settles — but it
  --      is not bounded, and the honest word for the detection is HALF: `ops_gated_runners()`
  --      (0096 §7) lists the row, and the remedy it names, `force_return_tx`, **HAS NO CALLER
  --      ANYWHERE** — measured: `grep -rn force_return_tx` over `supabase/functions/`, `app/` and
  --      `scripts/` returns only two comment mentions in a deno test. No edge action, no ops
  --      console, no client. The only exit is a human typing SQL.
  -- Both need the same decision, and it is Sean's rather than a clock's (awaiting-sean §4): what,
  -- if anything, may a timer do with money. What this arm guarantees is smaller and checkable:
  -- **a run where at least one party has said the dog is home is never made unpayable by a
  -- clock.** An escalating alarm (rather than the one-shot) and an ops door for
  -- `force_return_tx` are the two follow-ups this creates.
  --
  -- ⚠ LOCK, THEN LOOK AGAIN — arm ⓒ's idiom (codex 0181 #3), applied here because the branch is
  -- now destructive and the race lands exactly on the defect being closed: a stamp committing
  -- between the candidate read and the UPDATE would escalate a row that had just become
  -- settleable. `skip locked` leaves a row a writer holds for the next tick rather than stalling
  -- a sweep that holds every lock arm ⓒ took (0180's lesson).
  -- ⚠ [cold review #3] THE CANDIDATE SET MUST DRAIN, and this arm is the first in the function
  -- whose rows do NOT leave it. 0183's arm ⓑ had neither `order by` nor `limit`, and that was safe
  -- there because every candidate was escalated and left the set by changing status. A ⓑ-② row
  -- never leaves: status stays `active`, `run_ended_at` stays set, `settlement_ready_at` stays
  -- null, and the one-shot check makes it silent on every later tick. Adding `limit c_batch` to a
  -- non-draining set with `order by b.id` — a v4 uuid, so an ARBITRARY but STABLE order — would
  -- select the same fifty lowest-uuid corpses every tick forever, and a new zero-stamp row sorting
  -- above them would never be escalated at all. Two changes, and they are independent:
  --   · `order by b.run_ended_at` — OLDEST FIRST, a meaningful order, so nothing can be
  --     permanently shadowed by rows that merely have smaller ids;
  --   · the alarmed rows are excluded from the CANDIDATE, not just skipped in the loop, which
  --     restores the drain: a row that has had its one-shot alarm is done with this arm.
  -- The same `not exists` still guards the insert under the lock (a candidate read is a snapshot).
  for r in
    select b.id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
      and not exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_ret_title)
    order by b.run_ended_at
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
             b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: strand % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- Every predicate of the candidate query, re-asserted on the LOCKED row.
      -- ⚠ [cold review #8] `club_session_id` is in this list because the comment SAID "every"
      -- and the first version omitted it — and 219's `0188-B4` pins this re-check by matching
      -- this exact string, so the pin would have inherited the gap. No live path re-parents a
      -- booking into a club session, so this is a comment made true rather than a hole closed;
      -- that distinction is the finding, and it is worth the one conjunct.
      if v_b.status <> 'active' or v_b.run_ended_at is null or v_b.settlement_ready_at is not null
         or v_b.club_session_id is not null then continue; end if;
      if v_b.run_ended_at >= now() - STRAND_AFTER then continue; end if;

      if v_b.runner_confirmed_return_at is not null or v_b.owner_confirmed_return_at is not null then
        -- ⓑ-② ONE SIDE HAS SAID THE DOG IS HOME. No status move, ever. Both parties told ONCE —
        -- one-shot by construction (arm ⓐ's idiom): a row with this title for this booking is an
        -- alarm already raised. The two bodies are NOT interchangeable: telling a party who has
        -- already stamped to "확인해주세요" is a lie about their own action (0092 §6's rule for
        -- `waiting_on`, which exists for exactly this sentence).
        if not exists (select 1 from notifications nt
                       where nt.ref_id = v_b.id and nt.title = c_ret_title) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.owner_id, 'booking', c_ret_title,
                  case when v_b.owner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                  v_b.id);
          if v_b.runner_id is not null then
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_b.runner_id, 'booking', c_ret_title,
                    case when v_b.runner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                    v_b.id);
          end if;
          raise notice 'sweep_run_end_recovery: booking % — 반환 확인이 한쪽만 된 채 % 경과: 양측 1회 통지, 상태 무이동 (0188 ⓑ-②)',
            v_b.id, STRAND_AFTER;
          n := n + 1;
        end if;
      else
        -- ⓑ-① NOBODY has confirmed the return. This is the state `incident_review` names, and
        -- 0083's escalation is reproduced here verbatim — same UPDATE, same two titles, same
        -- two bodies. A human has to look, and `ops_gated_runners` (0096 §7) is where they look.
        update bookings set status = 'incident_review' where id = v_b.id and status = 'active';
        -- [0193 §D, codex B5] `safety`, NOT `booking`. 0187's classifier files a booking row as
        -- disableable, so with 예약 알림 off this push — 「the dog is unaccounted for」 — was
        -- silenced. Classified at the WRITER, which is what codex asked for; §E's title entry is
        -- the belt that covers rows a pre-0193 tick already wrote as `booking`.
        -- ⚠ 0114:273-281 admits only kind='booking' from a booking PARTY. This is a definer owned
        -- by postgres, so no policy applies and `safety` is writable here — which is exactly why
        -- the client writers (api.ts) were left alone in 0189 and are still left alone.
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                  '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', v_b.id);
        end if;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;
  -- ⓕ [0193] THE STRAND IS FINALLY TOLD TO SOMEBODY WHO CAN END IT (codex A1's detection half).
  --
  -- 0188 arm ⓑ-② is correct and it is not enough: it tells the two PARTIES once and then goes
  -- silent forever, and the parties are precisely the people who are already not acting. 0188's own
  -- header names the residue in full — 「one notification at 2h, then permanent silence, `active`
  -- forever, the runner work-gated (0092) and unpaid」 — and calls an ops door the follow-up it
  -- creates. This is that door's bell; `ops_resolve_return_tx` (§C-b) is the door.
  --
  -- 🔴 **NULL MEANS THE ARM DOES NOTHING, AND THAT IS THE SHIPPED STATE.** `return_strand_minutes`
  -- is Sean's ruling (queue item 23) and a deadline nobody chose is worse than no deadline: it
  -- would page an operator on a cadence invented by whoever typed the migration. Read fresh each
  -- tick so the flip needs no redeploy, and `is null` short-circuits before a single booking is
  -- read.
  --
  -- ⚠ TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
  -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and that row is the
  -- WORSE one (0096 lets late stamps land and refuses to seal, so it cannot settle at all until an
  -- operator acts). It is identified by the FACTS it carries — a run that ended, no seal — never by
  -- a free-text reason, because a reason string is prose and this is the input to a money door.
  --
  -- ⚠ ONCE PER BOOKING, by arm ⓐ/ⓑ's idiom: a row with this title for this booking is a bell
  -- already rung, and the candidate query excludes it so the set DRAINS (cold review 0188 #3's
  -- lesson: a `limit` over a non-draining set shadows new rows forever). An EMPTY ROSTER writes
  -- nothing, so the arm retries every tick until somebody is provisioned — the same durable-PENDING
  -- shape as ⓓ/ⓔ, and the honest one: an escalation recorded as delivered when nobody received it
  -- is worse than an unmonitored state (0096 §4).
  select f.return_strand_minutes into v_strand_min from ops_flags f where f.id;
  if v_strand_min is not null then
    for r in
      select b.id
      from bookings b
      where b.club_session_id is null
        and b.status in ('active', 'incident_review')
        and b.run_ended_at is not null
        and b.settlement_ready_at is null
        and (b.status = 'incident_review'
             or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
        and b.run_ended_at < now() - make_interval(mins => v_strand_min)
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.title = c_strand_title)
      order by b.run_ended_at
      limit c_batch
    loop
      begin
        select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
               b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
          into v_b from bookings b where b.id = r.id for update skip locked;
        if not found then
          raise notice 'sweep_run_end_recovery: strand-ops % — row locked by a writer, left for the next tick', r.id;
          continue;
        end if;
        -- every predicate of the candidate query, re-asserted on the LOCKED row (arm ⓑ's law)
        if v_b.club_session_id is not null or v_b.run_ended_at is null
           or v_b.settlement_ready_at is not null then continue; end if;
        if v_b.status not in ('active', 'incident_review') then continue; end if;
        if (v_b.status is distinct from 'incident_review')
           and v_b.runner_confirmed_return_at is not null
           and v_b.owner_confirmed_return_at is not null then continue; end if;
        if v_b.run_ended_at >= now() - make_interval(mins => v_strand_min) then continue; end if;
        -- the candidate read was a snapshot; the one-shot guard is re-taken under the lock
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_strand_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_strand_title, c_strand_body, v_b.id
          from ops_recipients_for(c_strand_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — 반환이 %분 넘게 끝나지 않았다 (status=%, stamps=%/%): ops 수신자 %명 (%)',
          v_b.id, v_strand_min, v_b.status,
          (v_b.runner_confirmed_return_at is not null), (v_b.owner_confirmed_return_at is not null),
          v_ops,
          c_strand_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (다음 틱에 다시 시도)' else '' end;
        if v_ops > 0 then n := n + 1; end if;
      exception when others then
        raise notice 'sweep_run_end_recovery: strand-ops % — %', r.id, sqlerrm;
      end;
    end loop;
  end if;

  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED — backend audit M2's second half (the attack-INACTION one).
  -- `transition-booking`'s confirm_handoff stamps one side and then asks the OTHER side with a
  -- 「인계 확인 요청」 notification — the only thing in the product that asks. Since M2 a lost
  -- insert is a log line; nothing retried it, and no sweep looked for a handoff that was asked
  -- for and never answered because the ask never existed. This arm does: exactly one stamp set,
  -- the booking still able to reach `picked_up`, a runner to hand to, older than ASK_AFTER, and
  -- NO ask row for the counterparty created at or after that stamp (an earlier cycle's ask —
  -- stamps are reset on re-match, 0047:112 / index.ts:163 — does not count) ⇒ the ask is written
  -- ONCE, counted in the return, and named in a notice. The counterparty is the side that has
  -- NOT stamped: the party who stamped is never asked to confirm their own handoff.
  -- ⚠ STATUS IS A DENY-LIST, NOT AN ALLOW-LIST (the attack-INACTION law). A handoff is underway
  --   in exactly two statuses of 0066's map — `confirmed` and `runner_enroute`, the two from
  --   which `picked_up` is one edge away — and this arm names the OTHER fourteen rather than
  --   those two: before assignment there is no agreed handoff to confirm (a stamp there is a
  --   leftover; re-match resets it), after the pickup or in any end state there is nothing left
  --   to ask. So a status added to the enum lands in the sweep by default — re-sent, the failure
  --   this arm exists to close, and one spurious ask if it was in fact an end state (a wrong
  --   line in an inbox, visible) — and 212 C6 walks the enum so that new status reddens a pin
  --   until someone places it, instead of being decided by omission.
  -- ⚠ NO `club_session_id is null` here, unlike arms ⓐ/ⓑ. 0144:94 scoped THOSE for run-END
  --   reasons (a club run ends by the host's stop, not by `end_run_tx`). The PICKUP ask is the
  --   same edge action for both worlds — `club/session/[sid].tsx:665,708` call confirm_handoff
  --   exactly as `owner/meetup.tsx:252` does — so a club booking's lost ask is the same defect
  --   and is swept here; `runner_id is not null` already excludes an owner-handled club dog,
  --   which has no handoff to confirm.
  for r in
    select b.id, x.counterparty, x.stamped_at
    from bookings b
    -- the counterparty and the stamp are computed ONCE (lateral) and used by both the insert and
    -- the not-exists below — two copies of that `case` would be two places to drift (cold review)
    cross join lateral (
      select case when b.owner_confirmed_handoff_at is not null then b.runner_id else b.owner_id end as counterparty,
             coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) as stamped_at
    ) x
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and b.status not in ('draft', 'quoted', 'payment_hold', 'matching', 'runner_pending',        -- before assignment: no agreed handoff to confirm
                           'picked_up', 'active', 'completed',                                    -- past the pickup: nothing left to ask
                           'cancelled_owner', 'cancelled_runner', 'expired', 'no_show',          -- ended
                           'incident_review', 'refund_pending')
      and x.stamped_at < now() - ASK_AFTER
      -- ⚠ `nt.profile_id = x.counterparty` is load-bearing and easy to read as redundant: an ask
      --   row addressed to the OTHER party (the previous cycle's, inside the skew — re-match
      --   resets the stamps and leaves the row) must not silence this party's re-send. Measured
      --   by the cold review: without it the owner is NEVER asked in that shape. 212 C9 pins it.
      and not exists (
        select 1 from notifications nt
        where nt.ref_id = b.id
          and nt.title = c_ask_title
          and nt.profile_id = x.counterparty
          -- [0183] …and CARRYING THIS CYCLE'S IDENTITY. `handoff_cycle_id` is minted by the
          -- database (trigger _handoff_cycle) when a cycle starts — a first stamp, a runner change,
          -- a stamp reset — the edge writes it onto the ask it inserts, and `_notification_cycle_guard`
          -- refuses an ask whose id is not the booking's current one. A timestamp could not tell
          -- cycles apart (codex 0182 #1: a delayed old-cycle ask lands inside the new window); an
          -- id can. A row with no id (legacy) matches nothing here and is given one in the loop.
          and nt.handoff_cycle_id = b.handoff_cycle_id)
    order by b.id
    limit c_batch
  loop
    -- arm ⓑ's shape, for arm ⓑ's reason (0117:1222): one surprising row must not stop the sweep
    -- for every other. Measured — without this sub-block a single failing insert here rolled
    -- arm ⓑ's escalations back with it. Latent today (the runner conjunct and owner_id NOT NULL
    -- make the insert unable to fail), and that is one conjunct away from not latent.
    begin
      -- [0182] LOCK, THEN LOOK AGAIN (codex 0181 #3). The candidate query read a snapshot; a
      -- transition-booking write (the counterparty's confirm, a cancel, a re-match) can commit
      -- between that read and this insert, and the ask would then be obsolete — or addressed to
      -- the former runner. `for update skip locked`: a row a writer holds right now is left for
      -- the next tick (its outcome decides), never waited on (a sweep holding every dog lock it
      -- took must not stall — 0180's lesson). The row we DO get is re-evaluated on its locked,
      -- current version, and the insert happens while the lock is held, so no write can slip in.
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_cycle_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: ask % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      v_cp := case when v_b.owner_confirmed_handoff_at is not null then v_b.runner_id else v_b.owner_id end;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ASK_AFTER then continue; end if;
      -- [0183] THE LEGACY RULE, stated: a one-sided row with no cycle identity (it predates 0183 and
      -- the apply-time backfill somehow missed it, or a fixture) is given one by this touch — the
      -- trigger mints on any update of a stamped, id-less row — and every ask it already has
      -- (NULL id) cannot prove it belongs to this cycle, so the row is asked ONCE MORE: a
      -- duplicate push over a silent stall. The ask written below carries the id, so the next
      -- tick matches it.
      v_cid := v_b.handoff_cycle_id;
      if v_cid is null then
        update bookings set handoff_cycle_at = handoff_cycle_at where id = v_b.id returning handoff_cycle_id into v_cid;
        raise notice 'sweep_run_end_recovery: booking % had no handoff cycle identity — minted % (legacy row)', v_b.id, v_cid;
      end if;
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_ask_title and nt.profile_id = v_cp
                   and nt.handoff_cycle_id = v_cid) then
        continue;
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
      values (v_cp, 'booking', c_ask_title, c_ask_body, v_b.id, v_cid);
      raise notice 'sweep_run_end_recovery: booking % — 인계 확인 요청 re-sent to % (one-sided since %, no ask row this cycle)',
        v_b.id, v_cp, v_st;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: ask % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓓ [0182] THE DEADLINE (codex 0181 #2 — the attack-INACTION shape, again). After arm ⓒ's one
  -- re-send an unanswered handoff was excluded forever: arms ⓐ/ⓑ need run-end states, and
  -- `late_booking_sweep` is gated on `ops_flags.late_protocol_live_since` AND marketplace-only
  -- (0126:43,78-80). This arm is a bounded ONE-SHOT per cycle, for club and marketplace alike,
  -- reading no flag: ESCALATE_AFTER after the stamp, still one-sided, the parties are told (a
  -- `booking` row each — no '요청' in the title, so it routes to the report / calendar, never to
  -- a CTA that was already declined twice) and the ops roster is told (a redacted `system` row,
  -- 0155's shape; zero subscribers is the honest answer and is in the notice). NO status move —
  -- what a stuck pickup handoff should become is a product decision (Sean's), not a clock's.
  -- ONCE by a column, not by prose: `handoff_escalated_at` is the record and the dedupe key,
  -- reset by the cycle trigger so a NEW pairing can escalate again.
  for r in
    select b.id
    from bookings b
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
      and coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) < now() - ESCALATE_AFTER
      and b.handoff_escalated_at is null
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) or v_b.handoff_escalated_at is not null then continue; end if;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ESCALATE_AFTER then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_b.owner_id,  'booking', c_esc_title, c_esc_body, v_b.id),
             (v_b.runner_id, 'booking', c_esc_title, c_esc_body, v_b.id);
      -- the ops row carries NO identifier in its body (0084 §E: a wrong recipient id pushes a body
      -- verbatim to a stranger's lock screen); the booking id rides in ref_id, as 0155/0166 do.
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      -- [0183] TWO RECORDS, not one (codex 0182 #2): the parties' delivery is done here and once;
      -- the OPS delivery is recorded ONLY when a recipient actually got a row. An empty roster
      -- leaves `handoff_ops_alerted_at` NULL — a durable PENDING ops escalation that arm ⓔ retries
      -- every tick until somebody is provisioned, without telling the parties twice (0166's
      -- 「the stamp is conditioned on a delivery」 rule, applied to the half it fits).
      update bookings
         set handoff_escalated_at = now(),
             handoff_ops_alerted_at = case when v_ops > 0 then now() end
       where id = v_b.id;
      raise notice 'sweep_run_end_recovery: booking % — handoff one-sided since %, past %: both parties told, % ops recipient(s) for %',
        v_b.id, v_st, ESCALATE_AFTER, v_ops,
        c_ops_class || case when v_ops = 0 then ' — ops escalation PENDING until the roster is provisioned' else '' end;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: escalate % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓔ [0183] THE PENDING OPS ESCALATION (codex 0182 #2). Rows whose parties were told (ⓓ) while
  -- the ops roster was empty keep `handoff_ops_alerted_at` NULL; every tick tries the roster again
  -- for rows still one-sided and live, records the delivery only when a row was written, and never
  -- touches the parties. Locked and re-checked like ⓒ/ⓓ (cold review 0183 #6, measured: without
  -- the lock a confirm committing inside the loop still got ops paged about a handoff that had
  -- just finished — the row WAS escalated, but the page's whole content is 「still stuck」). The job
  -- lock serializes ticks. Bounded by `c_batch`; resets with the cycle (the trigger).
  for r in
    select b.id
    from bookings b
    where b.handoff_escalated_at is not null
      and b.handoff_ops_alerted_at is null
      and (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at, b.handoff_ops_alerted_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      if v_b.handoff_escalated_at is null or v_b.handoff_ops_alerted_at is not null then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then
        update bookings set handoff_ops_alerted_at = now() where id = v_b.id and handoff_ops_alerted_at is null;
        raise notice 'sweep_run_end_recovery: booking % — pending ops escalation delivered to % recipient(s)', v_b.id, v_ops;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: pending ops % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓖ [0224 §C] A CUSTODY THAT NEVER MOVED — `picked_up` with no start, `active` with no stop, past
  -- the thresholds Sean sets (NULL ⇒ it reads no booking). Its own function, locked and bounded
  -- there, with its own handler so a surprise in it cannot roll back arms ⓐ–ⓕ's work.
  n := n + _sweep_custody_strands();

  -- ⓗ [0233 §C] A PRE-RUN INCIDENT REVIEW — a marketplace `incident_review` whose run never ended
  -- (arrived-only, picked_up-no-run). Arms ⓕ and every ops list require `run_ended_at`, so until
  -- this call nobody was told. Its own function, locked, bounded and handled there.
  n := n + _sweep_prerun_incidents();

  return n;
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited (0116:636; `check-definer-acl.mjs`'s class).
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant  execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9 · 0181 ⓒ · 0182 ⓓ · 0183 ⓔ · 0188 ⓑ · 0193 ⓕ · 0201 §D · 0224 §D · 0226 §A, and 0233 §D:
arm ⓗ, _sweep_prerun_incidents(), runs after arm ⓖ — a pre-run incident_review finally rings the
return_strand roster once. Everything else is 0226''s byte for byte (arm ⓐ''s two legs in sibling
subtransactions; arm ⓖ _sweep_custody_strands()). 264 0233-S1 pins the call; 257/255/232/224/219/214/
213/212 keep pinning the rest.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E _noti_ops_titles — 0224 §G's ledger, plus arm ⓗ's title
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied by script; one entry appended. Pure and immutable — no definer, so no `search_path`.
create or replace function _noti_ops_titles() returns text[]
language sql immutable as $$
  -- Derived from the writers, NEVER hand-listed (§0①). One entry per DISTINCT title; the two
  -- sites that share 「인계 확인 멈춤」 are one entry.
  select array[
    -- ── SQL writers, latest declaration of each function ──
    '지급 대기 — 확인 필요',                                 -- ops_payouts_stuck_sweep      0210:417
    '인계 확인 멈춤 — 확인 필요',                             -- sweep_run_end_recovery       0201:928/976
    '반환 좌초 — 확인 필요',                                 -- sweep_run_end_recovery       0201:768
    '굿즈 수령 신청 — 확인 필요',                             -- claim_gear_tx                §B below
    '카드 해지 실패 — 확인 필요',                             -- _note_revocation_abandoned   0166:166
    '클럽 취소 수수료 인텐트 실패 — 확인 필요',                 -- _club_note_fee_mint_failure  0118:674
    -- ── edge writers, all five through `notifyOps` (_shared/ops.ts:163 sets kind:"system") ──
    '결제 자동 취소 실패 — 수동 취소 필요',                     -- COPY.payment_manual_cancel   ops.ts:65
    '이동 중 취소 보상 기록 실패 — 수동 확인 필요',              -- COPY.enroute_comp_failed     ops.ts:69
    '결제 취소 실패 기록이 남지 않았어요 — 즉시 확인 필요',       -- COPY.payment_marker_lost     ops.ts:79
    '취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요',    -- COPY.late_comp_failed        ops.ts:84
    '운영 확인이 필요한 이벤트가 있어요',                        -- generic()                    ops.ts:124
    -- ── [0224] three more SQL writers ──
    '러닝 시작 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '러닝 종료 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '정산 미완료 — 확인 필요',                                -- sweep_run_end_recovery ⓐ     0224 §D
    -- ── [0233] one more SQL writer ──
    '러닝 전 사고 검토 — 확인 필요'                           -- _sweep_prerun_incidents      0233 §C
  ]::text[]
$$;

revoke execute on function _noti_ops_titles() from public, anon, authenticated;

comment on function _noti_ops_titles is
  '0214 §A + 0224 §G + 0233 §E: every title written with kind=''system'' — fifteen at 0233 (arm ⓗ''s
「러닝 전 사고 검토 — 확인 필요」 added). Consulted by _noti_push_category: a system row whose title is
here is the ''ops'' category (disableable by notification_prefs.ops). Adding a system writer means
adding its title HERE, in a new re-declaration. Pinned by 245 0214-T1/T2/T4, 264 0233-B2 and
app/test/ops-system-titles.test.cjs.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §F ops_prerun_cases — the return_strand roster's read of arm ⓗ's set
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §F's shape: zero arguments, the roster gate FIRST (before any read of any booking), `is not
-- true` so a NULL refuses, flat columns, no money, no contact field, no memo. It admits arm ⓗ's
-- candidate predicate conjunct for conjunct and NO bell condition: every such row is listed, belled
-- or not, because none of them has an exit and hiding one would be the inaction class.
-- `runner_gated` is §A's incident arm evaluated on the row (run_ended_at is NULL here by admission,
-- so it reduces to 「a handoff stamp exists」); 264 `0233-L1` pins it against `runner_work_gate`.
-- `arrived_at` is the late protocol's evidence stamp (0117), carried so the operator can see WHY the
-- row is here. `last_changed_at` is `bookings.updated_at` — named for what it is: no column records
-- the instant the row entered incident_review.
create or replace function ops_prerun_cases()
returns table (
  booking_id                  uuid,
  dog_name                    text,
  owner_name                  text,
  runner_name                 text,
  status                      text,
  scheduled_at                timestamptz,
  arrived_at                  timestamptz,
  owner_confirmed_handoff_at  timestamptz,
  runner_confirmed_handoff_at timestamptz,
  runner_gated                boolean,
  last_changed_at             timestamptz,
  notified_at                 timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class        constant text := 'return_strand';
  -- §C's title, verbatim; `0233-L1` compares this list against what the sweep wrote
  c_prerun_ops_title constant text := '러닝 전 사고 검토 — 확인 필요';
  v_uid uuid := auth.uid();
begin
  -- ① THE ROSTER GATE, before any read of anybody's booking
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         b.scheduled_at,
         b.arrived_at,
         b.owner_confirmed_handoff_at,
         b.runner_confirmed_handoff_at,
         (b.owner_confirmed_handoff_at is not null or b.runner_confirmed_handoff_at is not null),
         b.updated_at,
         -- [0233 fix] the same BELL IDENTITY as §C's one-shot: a look-alike row is not the bell
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id and nt.title = c_prerun_ops_title
             and nt.kind = 'system'
             and exists (select 1 from ops_recipients orr
                          where orr.profile_id = nt.profile_id
                            and orr.event_class = c_ops_class))
    from bookings b
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── arm ⓗ's candidate predicate (§C), conjunct for conjunct, minus the one-shot ────────────
   where b.status = 'incident_review'
     and b.run_ended_at is null
     and b.club_session_id is null
   order by b.updated_at, b.id;
end $$;

revoke execute on function ops_prerun_cases() from public, anon;
grant  execute on function ops_prerun_cases() to authenticated;

comment on function ops_prerun_cases is
  '0233 §F: every marketplace booking in incident_review whose run never ended — the rows behind the
「러닝 전 사고 검토 — 확인 필요」 bell (arm ⓗ). Gate: the return_strand roster, BEFORE any read
(not_signed_in / not_ops). Carries booking id, dog and both display names, raw status (gate on it,
never print it), scheduled_at, arrived_at and both handoff stamps, runner_gated (does this row hold
the runner — a handoff stamp exists), last_changed_at (bookings.updated_at — NOT the entry instant,
which no column records) and the bell instant. No money, no contact field, no memo. Read-only: no
door resolves these rows (L2/L3, Sean''s). 264 0233-L1 pins it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the apply refuses to finish if the shape it promises is not the shape that landed
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare v_src text;
begin
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = '_runner_work_gate_blocking';
  if v_src is null then raise exception '0233 VERIFY: _runner_work_gate_blocking missing'; end if;
  if position('b.runner_confirmed_handoff_at is not null' in v_src) = 0
     or position('b.run_ended_at is not null' in v_src) = 0 then
    raise exception '0233 VERIFY: the gate''s incident arm does not ask whether the dog was ever out';
  end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'sweep_run_end_recovery';
  if position('_sweep_prerun_incidents()' in coalesce(v_src, '')) = 0 then
    raise exception '0233 VERIFY: sweep_run_end_recovery does not call arm ⓗ';
  end if;
  if ('러닝 전 사고 검토 — 확인 필요' = any (_noti_ops_titles())) is not true then
    raise exception '0233 VERIFY: arm ⓗ''s title is not ledgered';
  end if;
end $verify$;
