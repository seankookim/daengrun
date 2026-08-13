-- 0089 — 반환 강제는 OPS 전용. 당사자 한 쪽이 인계를 '확정'할 수 있는 경로를 제거한다.
--
-- ═══ §0 THE RULING ═══════════════════════════════════════════════════════════════════════
-- Sean, 2026-08-13, verbatim:
--   "no, the confirmation must happen with both parties and never just the runner. also handoff."
--
-- Asked in response to a design I proposed and he rejected: I had suggested a force could
-- release money as long as the RECORD stayed honest about it ("runner asserted handover; owner
-- never confirmed"). His answer is that honest labelling is not the point — the confirmation
-- itself is the safety artifact, and a one-sided one is not a confirmation at all.
--
-- ═══ §1 WHAT WAS ACTUALLY SHIPPED IN 0083, AND WHY IT VIOLATES THAT ══════════════════════
-- `force_return_tx` accepted `p_side in ('runner','owner','ops')`. For a party force it:
--   ① required the caller to BE that party, 20 minutes after the stop, and then
--   ② wrote THAT PARTY'S OWN confirmation stamp —
--        `runner_confirmed_return_at = case when p_side = 'runner' then coalesce(..., now())`
--   ③ set `settlement_ready_at`, and settled if a price came with it.
-- So a runner could, 20 minutes after stopping, stamp their own side and release their own
-- payment with the owner never having touched the phone. The comment on ② called the forcing
-- side's confirmation "implied by the act" — that is precisely the inference this ruling denies.
-- The record was legible (`return_forced_by` said who), but legibility was never the ask.
--
-- ═══ §2 WHAT THIS FILE DOES ══════════════════════════════════════════════════════════════
--   · the CHECK on `bookings.return_forced_by` narrows to `('ops')`
--   · `force_return_tx` refuses `runner` and `owner` at the door with **`force_party_forbidden`**
--     — a NAMED refusal, not `bad_side`. The caller is asking for something the product used to
--     allow, so the honest answer names the rule rather than pretending the value was never
--     understood. (`bad_side` survives for a genuinely unknown side.)
--   · **no force writes any party's confirmation stamp, ever.** An ops resolution now leaves
--     both stamps NULL and sets only `settlement_ready_at` — which is the honest shape: nobody
--     confirmed, an adjudicator resolved. Reading that row later, you can tell those apart.
--   · `FORCE_GRACE` and `force_too_early` retire with the party path. They existed to make a
--     party wait; ops has always bypassed them, and there is no longer anyone else to gate.
--
-- ═══ §3 THE CONSEQUENCE — ⑫ IS NOW LOAD-BEARING, NOT OPTIONAL ════════════════════════════
-- Before this file, an unconfirmed return had three exits: both parties confirm, a party forces,
-- or the 2h janitor escalates to `incident_review`. This removes the middle one. So a return the
-- owner never confirms now has exactly two: ops resolves it, or it escalates — **and
-- `incident_review` still has no marketplace commercial exit** (0083 §0h, memo ⑫, unowned).
-- Until ⑫ ships, "ops resolves it" means a human calling `force_return_tx` as service_role.
-- That is a real path, not a hypothetical one, but it is a person and a shell — not a product.
-- 🔴 This is the argument for ⑫ being built before slice 3 ships the client half, because slice
-- 3 is what starts routing real runs through the seal.
--
-- ═══ §4 WHAT THIS FILE DELIBERATELY DOES NOT DO ══════════════════════════════════════════
-- The PICKUP handoff already satisfies the ruling and is untouched: `confirm_handoff`
-- (transition-booking/index.ts:280-296) stamps one side, RE-READS, and only moves to `picked_up`
-- when both stamps exist. Sean's "also handoff" affirms that; it does not ask for a change.
-- Verified before writing rather than assumed.

-- ── §5 the column: only ops may appear here ───────────────────────────────────────────────
-- No rows exist to migrate (nothing deployed; `payments_live_since` and `return_seal_since`
-- are both NULL and no client calls `end_run_tx`), so this is a straight narrowing.
alter table bookings drop constraint if exists bookings_return_forced_by_check;
alter table bookings add constraint bookings_return_forced_by_check
  check (return_forced_by is null or return_forced_by = 'ops');

comment on column bookings.return_forced_by is
  '0089 — ''ops'' or NULL. A PARTY may never force a return (Sean 2026-08-13: "the confirmation
must happen with both parties and never just the runner"). An ops force is an adjudication, not
a confirmation: it sets settlement_ready_at and leaves BOTH party stamps NULL, so a later reader
can tell "nobody confirmed, ops resolved" from "both parties confirmed".';

-- ── §6 the function ───────────────────────────────────────────────────────────────────────
create or replace function force_return_tx(
  p_booking  uuid,
  p_side     text,
  p_reason   text,
  p_evidence jsonb,
  p_quote    jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_settled jsonb;
begin
  -- [0089 §2] ops only. `runner`/`owner` are refused BY NAME rather than by falling through to a
  -- generic bad-input error: the caller is asking for something the product used to allow, and
  -- the honest answer names the rule rather than pretending the value was never understood.
  if p_side = 'runner' or p_side = 'owner' then
    raise exception 'force_party_forbidden'
      using detail = '인계 확인은 양측이 함께 해야 해요 — 한 쪽만으로는 확정할 수 없어요';
  end if;
  if p_side <> 'ops' then raise exception 'bad_side'; end if;
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;
  -- An adjudication with no evidence is just an assertion wearing a uniform.
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then
    raise exception 'evidence_required';
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason_required'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by, bk.return_eligible_at
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ops is a server-side override; a phone cannot claim it. (Unchanged from 0083.)
  if v_uid is not null or current_user not in ('service_role', 'postgres') then
    raise exception 'not_party';
  end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  if b.status = 'completed' then
    return jsonb_build_object('forced', false, 'settled', true, 'unchanged', true);
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;

  -- First-writer-wins, and `settled` is never claimed unless the primitive actually ran
  -- (0083's fix, preserved).
  if b.return_forced_by is not null then
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
    return jsonb_build_object(
      -- `eligible_at` is echoed for shape-compatibility with 0083's response and is NULL from
      -- 0089 onward (see the update below). Dropping the key silently would have been an
      -- undocumented change to a contract inside a file whose thesis is "the record is what a
      -- dispute reads" — flagged on review, restored rather than removed.
      'forced', false, 'forced_by', b.return_forced_by,
      'eligible_at', b.return_eligible_at, 'sealed', true,
      'settled', coalesce((v_settled->>'settled')::boolean, false),
      'unchanged', coalesce((v_settled->>'unchanged')::boolean, true));
  end if;

  update bookings set
      return_forced_by      = 'ops',
      return_forced_at      = v_now,
      return_force_reason   = p_reason,
      return_force_evidence = p_evidence,
      -- [0089, corrected on review] `return_eligible_at` is NOT written. With the party path
      -- gone there is no waiting period for anyone, so the column would always equal
      -- `run_ended_at` — a cache of something derivable, which 0083 §1 explicitly forbids of
      -- this schema ("never a cache of anything derivable"). The concept retired with the
      -- grace; the column stays only because rows written before 0089 could carry it (there are
      -- none — §5). Leaving it NULL is what makes "no grace exists" readable in the data.
      -- 🔴 [0089 §2] NO party stamp is written. 0083 wrote the forcing side's own confirmation
      -- and called it "implied by the act". Under the ruling it is implied by nothing: an
      -- adjudication resolves a return, it does not confirm one. Both stamps stay as they were.
      settlement_ready_at   = coalesce(b.settlement_ready_at, v_now)
  where id = p_booking;

  if p_quote is not null then
    v_settled := _settle_sealed_run(p_booking, p_quote);
  end if;

  return jsonb_build_object(
    'forced', true, 'forced_by', 'ops', 'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false));
end $$;

revoke execute on function force_return_tx(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
grant  execute on function force_return_tx(uuid, text, text, jsonb, jsonb) to service_role;

comment on function force_return_tx is
  '0089 — OPS-ONLY adjudication of a stuck return. A party (runner or owner) is refused by name
with force_party_forbidden: Sean 2026-08-13, "the confirmation must happen with both parties and
never just the runner". Writes NO party confirmation stamp — settlement_ready_at only — so the
row distinguishes "ops resolved" from "both confirmed". ⚠ With the party path gone, an
owner-silent return has exactly two exits: ops here, or the 2h escalation to incident_review,
which still has no marketplace commercial exit (memo ⑫). See §3.';
