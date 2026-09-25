-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0238 — no client can silence a SHIPPED ops bell or fake its instant on an ops list
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 269_ops_bell_keys_suite.sql (tag `obk`) — 0238-A1 · A2 · F1 · F2 · F3 · G1 · G2 · G3 · G4 · S1
-- Found by the executing review of 0233/0234 (fix round `4e40bad`, 0233 §C ⚠ BELL IDENTITY); this file
-- applies the same identity to every SHIPPED site that sentence covers.
--
-- ═══ §0a WHAT IS WRONG, MEASURED ON `cloud/0233-incident-exits` @ 2aaef9b ══════════════════════
-- Two production doors let a client write a `notifications` row it chooses the shape of:
--   ⓟ `noti party insert` (0114:273-283) — a booking PARTY inserts `kind='booking'` rows with ANY
--      title and ANY `created_at`, `ref_id` = a booking in the accepted set, addressed to either party.
--   ⓢ `noti self update` (0002:139) — USING-only, so WITH CHECK defaults to the same predicate: ANY
--      signed-in user rewrites one of their OWN rows' kind / title / body / ref_id / created_at /
--      handoff_cycle_id. Only `profile_id` is held (the new row must still be theirs).
-- Five shipped functions decided 「this ops bell already rang」 by (ref_id, title) ALONE:
--   · `sweep_run_end_recovery` (0233 §D, byte-faithful from 0226 §A): arm ⓐ's operator bell
--     「정산 미완료 — 확인 필요」's one-shot, and arm ⓕ's 「반환 좌초 — 확인 필요」 one-shot (candidate
--     query AND in-lock re-check);
--   · `_sweep_custody_strands` (0224 §C, arm ⓖ): pass 2's candidate query and both in-lock re-checks
--     (「러닝 시작 좌초 — 확인 필요」 / 「러닝 종료 좌초 — 확인 필요」);
--   · `ops_sealed_unsettled` (0224 §F): `notified_at`;
--   · `ops_stranded_custody` (0224 §F): `notified_at` AND its 「a bell exists」 admission;
--   · `ops_stranded_returns` (0206 §A): `notified_at` AND its 「a bell exists」 admission.
-- Measured with 269 against this stack BEFORE this file existed: **1622 pass / 10 fail** — every
-- 269 pin red, and red for the stated reason (each forging write asserted to land; the untouched
-- control booking rang exactly once; a real earlier ring was present): an operator-owner's
-- `kind='booking'` look-alike (ⓟ) and a stranger's own row rewritten to `system` (ⓢ) each silenced
-- arm ⓐ, arm ⓕ and both arm ⓖ shapes; and with the deadlines switched off, either look-alike put a
-- NEVER-RUNG booking on `ops_stranded_returns` / `ops_stranded_custody` — a client could put their
-- own booking on an operator's desk and give it any 「notified」 instant, 2000-01-01 included.
--
-- ═══ §0b WHAT THIS FILE DOES ════════════════════════════════════════════════════════════════
-- Every site above now uses 0233 §C's BELL IDENTITY, spelled identically at each:
--     and nt.kind = 'system'
--     and exists (select 1 from ops_recipients orr
--                  where orr.profile_id = nt.profile_id and orr.event_class = <the bell's class>)
-- — a row counts only when it is kind `system` (ⓟ can only write `booking`) AND is addressed to
-- someone who is or was seated at the class that bell rings (ⓢ can only re-address nothing; it keeps
-- the forger's own `profile_id`, and `ops_recipients` has no client write door — 0208). Active OR
-- not: a deactivated operator's bell was still delivered. The class is the BELL's, not the reader's
-- gate by coincidence: arm ⓐ / `ops_sealed_unsettled` → `payout_due`; arm ⓕ, arm ⓖ,
-- `ops_stranded_returns`, `ops_stranded_custody` → `return_strand` (each function's own constant).
-- Eleven sites in five functions. Each function is copied BY SCRIPT from its LATEST body on this stack
-- (`sweep_run_end_recovery` ←0233, `_sweep_custody_strands` / `ops_stranded_custody` /
-- `ops_sealed_unsettled` ←0224, `ops_stranded_returns` ←0206 — no later file re-declares any of
-- them), and the build script asserted each anchor matched exactly once AND that deleting the
-- inserted lines returns the source text byte for byte. Nothing else moves: no title, no body, no
-- class, no status, no order, no limit, no lock, no handler.
-- ⚠ A later slice re-declaring any of these five must carry the identity (269 `0238-S1` counts it,
--   comment-stripped, per function and per class constant).
-- ⚠ Deploy effect, stated: a booking whose ops bell was silenced by a look-alike rings ONCE on the
--   first tick after `db push`. Every real bell is `system` and was written to `ops_recipients_for`
--   of that class (0193/0224's inserts), so no really-rung booking rings twice — 269 pins that
--   direction too (a real earlier ring still suppresses).
--
-- ═══ §0c EVERY READER OF `notifications`, ENUMERATED — measured on the DEPLOYED harness catalog ═══
-- `pg_proc` in `public`, comment-stripped `prosrc` matching `(from|join) notifications` (the grep
-- over migration text found the same set, plus one false hit on a `format()`-generated body; the
-- catalog is the authority). 19 non-fixture functions:
--   FIXED HERE (an OPS bell or an ops list keyed on (ref_id, title)):
--     sweep_run_end_recovery (ⓐ-ops, ⓕ ×2) · _sweep_custody_strands (×3) · ops_sealed_unsettled ·
--     ops_stranded_custody (×2) · ops_stranded_returns (×2)
--   ALREADY FIXED (4e40bad): _sweep_prerun_incidents (×2) · ops_prerun_cases · ops_open_incidents
--   NOT an ops bell keyed on (ref_id, title) — each keys on ONE recipient's own row, so the only
--   client who can forge a matching row through ⓢ is that recipient, silencing their own copy:
--     ops_payouts_stuck_sweep (0210: per operator, `kind='system'`, 20 h window — the forger can only
--       be the operator it is for: 0233 §C's named residual, unchanged) · _club_note_fee_mint_failure
--       (0118: per `club_fee_mint_failed` recipient) · club_assignment_recovery · club_chat_report ·
--       club_incident_open · club_notify_min_attendance · club_stale_delegation_sweep ·
--       generate_recurring_bookings · notify_chat_message · sweep_cancel_money_gaps
--   NOT a reader: delete_my_account_tx (deletes the caller's rows — which is also how 0233 §C's
--     「the bell rings again if every recipient deletes their account」 residual arises).
--   Edge code: every `from("notifications")` in `supabase/functions/` is an INSERT (transition-booking,
--   confirm-payment, _shared/charge.ts, _shared/ops.ts); no edge one-shot reads the table.
--
-- ═══ §0d THE ROOT CAUSE — `noti self update` — IS NOT TIGHTENED HERE, AND WHY (a decision) ═══════
-- The tempting fix is to take ⓢ away: `revoke update on notifications from anon, authenticated;
-- grant update (read_at) on notifications to authenticated;` (a column grant; a WITH CHECK cannot
-- compare OLD to NEW, so the policy alone cannot pin the other columns). Every client writer was
-- enumerated and would survive it — they write `read_at` and nothing else:
--   `api.ts markAllNotificationsRead` · `markNotificationsRead` · `markNotificationsReadByTap` (all
--   `.update({ read_at })` filtered on `read_at`, `id`, `title`, `ref_id` — filters need SELECT,
--   which stays table-wide), and the definer writers `chat_mark_read` / `chat_mark_read_to` (0228,
--   owned by postgres — a grant to `authenticated` never touches them). No edge function UPDATEs it.
-- It is deliberately NOT done in this file, for three reasons:
--   (1) It does not close the class. ⓟ stays open by design (0114 B-11.d: a party may write a
--       `booking` row to the other party), so every PARTY-addressed one-shot keyed on (ref_id,
--       title) stays forgeable with or without ⓢ — see §0e. Only the kind + recipient identity (or a
--       writer-provenance column, §0e) answers 「did the SERVER write this」; revoking ⓢ would leave
--       the ops sites exactly as forgeable through ⓟ as they were, so the identity is needed anyway.
--   (2) It moves two SHIPPED pins that this slice may not edit: 264 `0233-B4`'s arm (ii) and 265
--       `0234-L3` stage their forgery THROUGH ⓢ and assert it LANDS (a FIXTURE arm — 「the pin would
--       prove nothing」). Tightening turns both red for a true reason; each must be rewritten to assert
--       the forge is REFUSED, in the same slice as the grant (CLAUDE.md: a suite whose pinned
--       behaviour legitimately changes moves in the same slice). MEASURED in a lab copy (the grant
--       appended to this file, plus an apply-time probe that aborts the apply unless an owner's
--       `update … set read_at` changes exactly 1 row AND a `set kind = 'system'` on the same row raises
--       insufficient_privilege — it applied, so both held): harness 1632 → **1621 / 11** — 264
--       `0233-B4`, 265 `0234-L3` and ALL NINE behavioural pins of this file's own 269 (its staging
--       forges through ⓢ, so the whole staging aborts with 「permission denied for table
--       notifications」). No other shipped pin moved. The follow-up therefore owns three suites.
--   (3) It changes what a field client may do to a table every build writes, which deserves its own
--       codex pass and its own deploy note rather than riding a sweep fix.
-- RECOMMENDED FOLLOW-UP, one slice: the column grant above + 264 B4 (ii) / 265 L3 / 269's ⓢ forgeries
-- flipped to assert the refusal (the ⓟ arms stay: party insert is untouched) + a pin that a client
-- can still mark read (its own row, `read_at` only) and cannot
-- change kind / title / ref_id / created_at / body / handoff_cycle_id. It closes 0233 §C's operator
-- self-forge residual too (an operator could then no longer re-kind their own row to `system`).
--
-- ═══ §0e WHAT THIS FILE DELIBERATELY DOES NOT CLOSE — named, not hidden ═══════════════════════
--   · **PARTY-addressed one-shots are still keyed on (ref_id, title) and a PARTY can silence the
--     COUNTERPARTY's copy through ⓟ** — the look-alike can be addressed to the forger themself, so
--     the victim receives nothing at all. Sites: `sweep_run_end_recovery` arm ⓐ 「정산을 확인하고
--     있어요」, arm ⓑ-② 「반환 확인이 멈춰 있어요」 (candidate + re-check), and `_sweep_custody_strands`
--     pass 1 「러닝 시작이 / 종료가 멈춰 있어요」 (candidate + two re-checks). Out of this slice's
--     sentence (they are not ops bells) and NOT fixable with this idiom: the real rows ARE
--     `kind='booking'` to a party, which is exactly what ⓟ writes. Every one of them has an ops bell
--     behind it (ⓐ-ops, ⓕ, ⓖ pass 2) that this file makes unsilenceable, so an operator still hears
--     of the row; the parties' own notice is what can be lost. The durable fix is a WRITER-PROVENANCE
--     column (e.g. `server_written boolean`, stamped by a BEFORE INSERT trigger from `current_user
--     not in ('authenticated','anon')` and never client-updatable) that every one-shot keys on — a
--     schema change across every writer, for its own slice. Recorded as an open item for Sean.
--   · A seated operator of a class can still forge on their OWN row through ⓢ (0233 §C's residual) —
--     closed by §0d's follow-up, not here.
--   · Per-recipient bells (§0c's third group) can be silenced only by their own recipient — through
--     ⓢ, and through ⓟ by a counterparty only where the key omits `profile_id` (none of that group
--     does). Named, not changed.
--   · Arm ⓓ/ⓔ's ops escalation is keyed on `handoff_escalated_at` / `handoff_ops_alerted_at` (bookings
--     columns, no client write door) — not forgeable, not touched.
--
-- ═══ §0f WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES, each from the highest declaring migration on this stack (grepped AND read back from
--   the harness catalog):
--     `sweep_run_end_recovery()` ←0233 §D (copied by script; 3 identity insertions)
--     `_sweep_custody_strands()` ←0224 §C (copied by script; 3 identity insertions)
--     `ops_stranded_custody()`   ←0224 §F (copied by script; 2 identity insertions)
--     `ops_sealed_unsettled()`   ←0224 §F (copied by script; 1 identity insertion)
--     `ops_stranded_returns()`   ←0206 §A (copied by script; 2 identity insertions)
--   Every ACL is restated in THIS file (0116:636; `check-definer-acl.mjs`'s class). Comments on the
--   functions are not restated — `create or replace` keeps them, and none of their sentences moves.
--   CREATES nothing. No table, policy, grant on a table, or title changes.
--   ⚠ No VERIFY block: 269 `0238-S1` owns the shape, and a VERIFY duplicating it would make every
--   single-conjunct mutation abort the APPLY — measuring the VERIFY instead of the pins (0131's lesson).
--
-- ═══ §0g SHIPPED PINS THAT MOVE ══════════════════════════════════════════════════════════════
-- None (measured: the full harness is green with this file applied; see the REGISTRY row).
--
-- ═══ §0g′ MUTATION BATTERY — a lab copy of `supabase/` outside the worktree, one fresh copy per
-- plant, every plant asserting it LANDED and `&&`-gated to its harness run (a failed plant yields no
-- row — two plants failed their own assertion on the first try and produced NO row, as designed);
-- control CTL observed clean FIRST: 1632/0. Sites numbered in file order: ① ⓐ-ops · ② ⓕ candidate ·
-- ③ ⓕ re-check · ④ ⓖ pass-2 candidate · ⑤ ⓖ start re-check · ⑥ ⓖ end re-check · ⑦ custody
-- notified_at · ⑧ custody admission · ⑨ sealed notified_at · ⑩ returns notified_at · ⑪ returns
-- admission. K = the kind conjunct deleted, R = the recipient conjunct deleted.
--   UNFIX (all 11 identities deleted) → 1622/10: every 269 pin (the hole reproduces with this file present)
--   K1/R1 → A1 + A2 + S1          K2/R2, K3/R3 → F1 + F2 + S1     K4/R4 → G1 + G2 + G3 + S1
--   K5/R5 → G1 + G3 + S1          K6/R6 → G2 + G3 + S1            K7/R7 → G3 + S1
--   K8/R8 → G4 + S1               K9/R9 → A2 + S1                 K10/R10 → F2 + S1   K11/R11 → F3 + S1
--   (A2/F2/G3 redden beside a one-shot plant because a silenced bell leaves no real instant to read.)
--   All 22 single-conjunct deletions redden a behavioural pin of their own site, not only S1.
--   W1 (ⓐ keyed on a class nobody sits on — the identity too NARROW) → A1 (「a real earlier ring did
--      not suppress」) + shipped 255 0224-B1 · 257 0226-F1/F2 + S1: the over-narrow direction is caught.
--   W3 (ⓕ candidate AND re-check too narrow) → F1 + shipped 224 0193-R4 · 232 0201-L1 + S1.
--   W2 (ⓕ CANDIDATE ONLY too narrow) → S1 ALONE — a named GAP, not a pass: the in-lock re-check still
--      excludes the really-rung row, so no duplicate bell is observable here. It is NOT harmless: rung
--      rows would stop draining from the candidate set, and past `c_batch` (50) of them they would take
--      every slot and shadow a new strand forever (cold review 0188 #3's class). A fixture of 51 rung
--      strands could observe it; this suite does not build one. S1's per-function site count is its
--      only guard.
--
-- ═══ §0h DOCTRINE ════════════════════════════════════════════════════════════════════════════
-- `set search_path = public, pg_temp` in every definer body (carried verbatim) · every ACL restated
-- here · `exists` is never NULL, so the added conjuncts cannot collapse a plpgsql `if`.
--
-- ═══ §0i DEPLOY ══════════════════════════════════════════════════════════════════════════════
-- `supabase db push` (after 0232–0234 on this stack). Server-only: no client or edge change.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A sweep_run_end_recovery — 0233 §D's body; arm ⓐ-ops and arm ⓕ (×2) key on the bell's OWN row
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT from 0233's text. The three insertions are the marked `[0238]` lines; the build
-- script asserted removing them returns 0233's body byte for byte (arm ⓗ's call included).
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
                         where nt.ref_id = r.id and nt.title = c_seal_ops_title
                          -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                          and nt.kind = 'system'
                          and exists (select 1 from ops_recipients orr
                                       where orr.profile_id = nt.profile_id
                                         and orr.event_class = c_seal_ops_class)) then
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
                        where nt.ref_id = b.id and nt.title = c_strand_title
                        -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                        and nt.kind = 'system'
                        and exists (select 1 from ops_recipients orr
                                     where orr.profile_id = nt.profile_id
                                       and orr.event_class = c_strand_ops_class))
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
                   where nt.ref_id = v_b.id and nt.title = c_strand_title
                   -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                   and nt.kind = 'system'
                   and exists (select 1 from ops_recipients orr
                                where orr.profile_id = nt.profile_id
                                  and orr.event_class = c_strand_ops_class)) then continue; end if;
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

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B _sweep_custody_strands — 0224 §C's body; pass 2 (candidate + both re-checks) keys on the bell's OWN row
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT from 0224's text; three insertions, round trip asserted. Pass 1 (the PARTIES'
-- notice) is untouched — see §0e for why it cannot take this idiom.
create or replace function _sweep_custody_strands() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_b record; n int := 0; v_ops int;
  v_shape text; v_stranded boolean;
  v_start_min int; v_end_min int;
  c_batch constant int := 50;
  c_ops_class constant text := 'return_strand';
  -- the parties — one title per SHAPE, shared by both parties (arm ⓑ-②'s `c_ret_title` idiom), so
  -- a booking that strands at the start and again at the end is told about each, once
  c_start_title        constant text := '러닝 시작이 멈춰 있어요';
  c_start_body_runner  constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 앱에서 러닝을 시작해주세요';
  c_start_body_owner   constant text := '인계는 끝났는데 러닝이 아직 시작되지 않았어요 — 러너에게도 알렸어요';
  c_end_title          constant text := '러닝 종료가 멈춰 있어요';
  c_end_body_runner    constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 앱에서 러닝을 종료해주세요';
  c_end_body_owner     constant text := '예정 시간이 지났는데 러닝이 아직 종료되지 않았어요 — 러너에게도 알렸어요';
  -- the owner's sentence when there is no runner to have told — 「러너에게도 알렸어요」 would be a lie
  c_body_owner_alone   constant text := '러닝 진행이 확인되지 않은 예약이 있어요 — 예약을 확인해주세요';
  -- the operators — one title per shape, for the same reason
  c_start_ops_title    constant text := '러닝 시작 좌초 — 확인 필요';
  c_start_ops_body     constant text := '인계는 끝났는데 러닝이 시작되지 않은 예약이 있어요. 예약을 확인해 주세요.';
  c_end_ops_title      constant text := '러닝 종료 좌초 — 확인 필요';
  c_end_ops_body       constant text := '예정 시간이 지났는데 러닝이 종료되지 않은 예약이 있어요. 예약을 확인해 주세요.';
begin
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice '_sweep_custody_strands: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- Both thresholds NULL (the shipped state) ⇒ read no booking at all. §B would answer 「not
  -- stranded」 for every row anyway; this is the short-circuit, not the rule.
  select f.custody_start_strand_minutes, f.custody_end_strand_minutes
    into v_start_min, v_end_min from ops_flags f where f.id;
  if v_start_min is null and v_end_min is null then return 0; end if;

  -- The two passes sit in ONE protected block. Each row already has its own sub-block (arm ⓑ's
  -- reasoning: one surprising row must not stop the sweep for every other); this outer one is for a
  -- surprise OUTSIDE any row — a candidate query that raises — and it rolls back THIS arm's writes
  -- and nothing else, so the caller's arms ⓐ–ⓕ keep their tick. It lives HERE rather than around
  -- the call in `sweep_run_end_recovery` so that function's own handler count (214 `0183-E6`) keeps
  -- describing that function's arms.
  begin
  -- ── pass 1: the two parties, once per shape ─────────────────────────────────────────────────
  for r in
    select b.id
      from bookings b
      cross join lateral _custody_strand(b.id) cs
     where b.status in ('picked_up', 'active')
       and cs.stranded is true
       and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id
                          and nt.title = case cs.shape when 'start_run' then c_start_title
                                                       else c_end_title end)
     order by cs.due_at, b.id
     limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id into v_b
        from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice '_sweep_custody_strands: parties % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- every candidate predicate, re-asserted on the LOCKED row through the same predicate
      v_shape := null; v_stranded := null;
      select cs.shape, cs.stranded into v_shape, v_stranded from _custody_strand(v_b.id) cs;
      if v_stranded is not true then continue; end if;
      if v_shape = 'start_run' then
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_start_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'booking', c_start_title,
                case when v_b.runner_id is null then c_body_owner_alone else c_start_body_owner end, v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'booking', c_start_title, c_start_body_runner, v_b.id);
        end if;
      else
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_end_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'booking', c_end_title,
                case when v_b.runner_id is null then c_body_owner_alone else c_end_body_owner end, v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'booking', c_end_title, c_end_body_runner, v_b.id);
        end if;
      end if;
      raise notice '_sweep_custody_strands: booking % — custody strand (%) told to both parties once', v_b.id, v_shape;
      n := n + 1;
    exception when others then
      raise notice '_sweep_custody_strands: parties % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ── pass 2: the return_strand roster, once per shape; retried every tick while it is empty ───
  for r in
    select b.id
      from bookings b
      cross join lateral _custody_strand(b.id) cs
     where b.status in ('picked_up', 'active')
       and cs.stranded is true
       and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id
                          and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                                       else c_end_ops_title end
                          -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                          and nt.kind = 'system'
                          and exists (select 1 from ops_recipients orr
                                       where orr.profile_id = nt.profile_id
                                         and orr.event_class = c_ops_class))
     order by cs.due_at, b.id
     limit c_batch
  loop
    begin
      select b.id into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice '_sweep_custody_strands: ops % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      v_shape := null; v_stranded := null;
      select cs.shape, cs.stranded into v_shape, v_stranded from _custody_strand(v_b.id) cs;
      if v_stranded is not true then continue; end if;
      if v_shape = 'start_run' then
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_start_ops_title
                   -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                   and nt.kind = 'system'
                   and exists (select 1 from ops_recipients orr
                                where orr.profile_id = nt.profile_id
                                  and orr.event_class = c_ops_class)) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_start_ops_title, c_start_ops_body, v_b.id
          from ops_recipients_for(c_ops_class) as rc(profile_id);
      else
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_end_ops_title
                   -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                   and nt.kind = 'system'
                   and exists (select 1 from ops_recipients orr
                                where orr.profile_id = nt.profile_id
                                  and orr.event_class = c_ops_class)) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_end_ops_title, c_end_ops_body, v_b.id
          from ops_recipients_for(c_ops_class) as rc(profile_id);
      end if;
      get diagnostics v_ops = row_count;
      raise notice '_sweep_custody_strands: booking % — custody strand (%): % ops recipient(s) for %', v_b.id, v_shape, v_ops,
        c_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
      if v_ops > 0 then n := n + 1; end if;
    exception when others then
      raise notice '_sweep_custody_strands: ops % — %', r.id, sqlerrm;
    end;
  end loop;
  exception when others then
    -- nothing this arm wrote in this tick survives the rollback, so the count says so
    raise notice '_sweep_custody_strands: arm aborted, its writes rolled back — %', sqlerrm;
    n := 0;
  end;

  return n;
end $$;

revoke execute on function _sweep_custody_strands() from public, anon, authenticated;
grant  execute on function _sweep_custody_strands() to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C ops_stranded_custody — 0224 §F's body; notified_at AND the 「a bell exists」 admission
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT; two insertions, round trip asserted. The admission is the one that matters most:
-- with both thresholds NULL (shipped) the list shows ONLY belled rows, so a look-alike was the whole
-- of what put a row on it.
create or replace function ops_stranded_custody()
returns table (
  booking_id      uuid,
  dog_name        text,
  owner_name      text,
  runner_name     text,
  status          text,
  shape           text,
  since_at        timestamptz,
  due_at          timestamptz,
  minutes_overdue int,
  strand_minutes  int,
  notified_at     timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class       constant text := 'return_strand';
  -- §C's two ops titles, verbatim; `0224-A4` compares this list against the sweep's own output
  c_start_ops_title constant text := '러닝 시작 좌초 — 확인 필요';
  c_end_ops_title   constant text := '러닝 종료 좌초 — 확인 필요';
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
         cs.shape,
         cs.since_at,
         cs.due_at,
         case when cs.due_at is null then null
              else floor(extract(epoch from (now() - cs.due_at)) / 60)::int end,
         case cs.shape when 'start_run' then f.custody_start_strand_minutes
                       else f.custody_end_strand_minutes end,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id
             and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                          else c_end_ops_title end
             -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
             and nt.kind = 'system'
             and exists (select 1 from ops_recipients orr
                          where orr.profile_id = nt.profile_id
                            and orr.event_class = c_ops_class))
    from bookings b
    cross join lateral _custody_strand(b.id) cs
    left join ops_flags f   on f.id
    left join dogs d        on d.id = b.dog_id
    left join profiles po   on po.id = b.owner_id
    left join profiles pr   on pr.id = b.runner_id
   where b.status in ('picked_up', 'active')
     and (cs.stranded is true
          or exists (select 1 from notifications nt
                      where nt.ref_id = b.id
                        and nt.title = case cs.shape when 'start_run' then c_start_ops_title
                                                     else c_end_ops_title end
                        -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                        and nt.kind = 'system'
                        and exists (select 1 from ops_recipients orr
                                     where orr.profile_id = nt.profile_id
                                       and orr.event_class = c_ops_class)))
   order by cs.due_at nulls last, b.id;
end $$;

revoke execute on function ops_stranded_custody() from public, anon;
grant  execute on function ops_stranded_custody() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D ops_sealed_unsettled — 0224 §F's body; notified_at
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT; one insertion, round trip asserted. Admission is arm ⓐ's candidate predicate and
-- reads no notification, so only the instant could be faked.
create or replace function ops_sealed_unsettled()
returns table (
  booking_id          uuid,
  dog_name            text,
  owner_name          text,
  runner_name         text,
  status              text,
  run_ended_at        timestamptz,
  settlement_ready_at timestamptz,
  minutes_sealed      int,
  notified_at         timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class      constant text := 'payout_due';
  -- §D ①'s title, verbatim; `0224-B3` compares the list against the sweep's own output
  c_seal_ops_title constant text := '정산 미완료 — 확인 필요';
  v_uid uuid := auth.uid();
begin
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
         b.run_ended_at,
         b.settlement_ready_at,
         floor(extract(epoch from (now() - b.settlement_ready_at)) / 60)::int,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id and nt.title = c_seal_ops_title
             -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
             and nt.kind = 'system'
             and exists (select 1 from ops_recipients orr
                          where orr.profile_id = nt.profile_id
                            and orr.event_class = c_ops_class))
    from bookings b
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── arm ⓐ's candidate predicate (0201:528-530), conjunct for conjunct ───────────────────────
   where b.status = 'active'
     and b.club_session_id is null
     and b.settlement_ready_at is not null
   order by b.settlement_ready_at, b.id;
end $$;

revoke execute on function ops_sealed_unsettled() from public, anon;
grant  execute on function ops_sealed_unsettled() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E ops_stranded_returns — 0206 §A's body; notified_at AND the 「a bell exists」 admission
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Copied BY SCRIPT; two insertions, round trip asserted. Same shape as §C: with the deadline NULL
-- the admission was the only way onto the list.
create or replace function ops_stranded_returns()
returns table (
  booking_id        uuid,
  dog_name          text,
  owner_name        text,
  runner_name       text,
  status            text,
  run_ended_at      timestamptz,
  runner_stamped    boolean,
  owner_stamped     boolean,
  minutes_stranded  int,
  strand_minutes    int,
  notified_at       timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- the SAME class `ops_resolve_return_tx` (0193 §C-b / 0201 §A) gates on, and the same one arm ⓕ
  -- delivers to. §0b says why it is not `payout_due`.
  c_ops_class   constant text := 'return_strand';
  -- arm ⓕ's title, verbatim (0193:656). It is the dedupe key there and the `notified_at` key here;
  -- 237 `0206-S1` asserts the two spellings against the deployed sweep so they cannot part.
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  v_uid uuid := auth.uid();
  v_min int;
begin
  -- ① PARTY GATE FIRST — before any read of anybody's booking. There is no argument to check
  --    afterwards (this function takes none, for the same structural reason `ops_me` takes none:
  --    there is no parameter by which to point it at a third party's booking).
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  -- ② the deadline, read FRESH exactly as arm ⓕ reads it (0201:732), so a flip needs no redeploy
  --    and the list and the sweep never disagree about which number is current.
  select f.return_strand_minutes into v_min from ops_flags f where f.id;

  return query
  select b.id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         b.run_ended_at,
         (b.runner_confirmed_return_at is not null),
         (b.owner_confirmed_return_at is not null),
         floor(extract(epoch from (now() - b.run_ended_at)) / 60)::int,
         v_min,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = b.id and nt.title = c_strand_title
             -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
             and nt.kind = 'system'
             and exists (select 1 from ops_recipients orr
                          where orr.profile_id = nt.profile_id
                            and orr.event_class = c_ops_class))
    from bookings b
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   -- ── arm ⓕ's candidate predicate (0201:737-742), conjunct for conjunct ──────────────────────
   where b.club_session_id is null
     and b.status in ('active', 'incident_review')
     and b.run_ended_at is not null
     and b.settlement_ready_at is null
     -- TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
     -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and 0096 lets late
     -- stamps land there without sealing — so an unsealed `incident_review` return is a strand
     -- regardless of how many stamps it carries (0201's codex #2).
     and (b.status = 'incident_review'
          or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
   -- ── the two documented differences (1) and (2) above ────────────────────────────────────────
     and ((v_min is not null and b.run_ended_at < now() - make_interval(mins => v_min))
          or exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_strand_title
                        -- [0238] the bell's OWN row (0233 §C's BELL IDENTITY), not a client look-alike
                        and nt.kind = 'system'
                        and exists (select 1 from ops_recipients orr
                                     where orr.profile_id = nt.profile_id
                                       and orr.event_class = c_ops_class)))
   order by b.run_ended_at, b.id;
end $$;

revoke execute on function ops_stranded_returns() from public, anon;
grant  execute on function ops_stranded_returns() to authenticated;
