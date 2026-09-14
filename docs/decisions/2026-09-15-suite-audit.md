# Harness diet — option D: per-suite keep/cut/merge audit (2026-09-15)

Answers `2026-09-15-harness-diet-proposal.md` option D. **Nothing is cut by this document** — it is
the per-suite read Sean asked for before anything is cut blind. Every CUT and every MERGE names the
property that becomes unpinned, or says which pin already owns it.

## Method, and what it does and does not license

Measured, not remembered, at branch `claude/suite-audit` off trunk `5aa9a85`:

- the registered list is `grep -E '^suite ' supabase/tests/harness.sh` — **112 suites** (the
  proposal doc said 106; trunk moved). Plus `90_race_check.sh`, the only two-connection runner.
- pins per suite = `grep -c "_pass('" <file>`; lines = `wc -l`.
  **Totals: 1,246 pin call sites · 49,551 lines · 16,137 comment lines (32.5%) · 31,019 code lines.**
- ⚠ **The pin number is CALL SITES, not a harness run.** This audit is read-only; I did not run
  `harness.sh`. A call site inside a loop counts once here and many times there, which is why 1,246
  does not equal the ~1,213 the last run printed. Every count below is a source count and says so.
- bucket + verdict come from each file's own header block (they self-describe by rule) plus its
  `_pass('<tag>','<label>'` lines. Where the header is one line — the twelve legacy suites, 10
  through 80 — I classified from the pin labels and the body, and **every one of those rows carries
  ⚠** because a one-line header cannot state a property.

**The headline finding, and it contradicts the premise the diet was proposed on.** The cut mandate
aimed at "speculative, duplicate, and vocabulary/copy pins". Measured: **two suites out of 112 are
primarily copy/vocab (40, 168 — 8 pins, 163 lines).** There is no large seam of vocabulary pins to
remove. The corpus's weight is (a) **32.5% comments**, and (b) **a long tail of one-slice files** —
21 suites that are follow-ups, corrections or siblings of another suite and belong inside it.
So the honest saving is ~2.6% of pins and ~6.7% of lines, and most of that is prose, not coverage.

## Buckets

MONEY ledger/charge/settle/fee/payout/billing/km-pricing · SECURITY RLS/ACL/definer/party
gate/disclosure · SHAPE columns, constraints, triggers exist · STATE booking/session/run
transitions · COPY asserts Korean strings/labels/notification wording · INFRA harness self-checks,
fixture preconditions, source pins on `prosrc`.

## The table

Sorted by suite number. `p` = pin call sites, `L` = lines. ⚠ = a human read is owed on this row.

| suite | p | L | bucket | verdict | reason · property unpinned if cut |
|---|---|---|---|---|---|
| 10_settle | 23 | 398 | MONEY ⚠ | KEEP | settle_run_tx end-to-end: ledger, miles, pace, drops, patch bonuses. ⚠ one-line header |
| 20_recurring | 19 | 246 | MONEY ⚠ | KEEP | series生成 + balance/net aggregate RPCs + grant boundary. ⚠ one-line header, mixed STATE |
| 30_club | 32 | 521 | STATE ⚠ | KEEP | club lifecycle: claim, RSVP, capacity, checkin, recap. ⚠ S5–S11 are feed/stat display, trim candidates |
| 40_records | 5 | 67 | **COPY** | **CUT** | asserts notification COPY (`%최고 페이스 경신%`, `%40초 단축%`, `%누적 10km 달성%`). **Unpinned: "a pace record or 10km milestone emits exactly ONE reward notification, and a first run / early stop emits none" — the 정직한 팡파레 rule (R1/R5). Move R1+R5 into 10 as two arms rather than losing them** ⚠ |
| 50_delegation | 24 | 551 | MONEY ⚠ | KEEP | delegation money moments: club_fare, hold→pay, refund fan-out, expiry. ⚠ one-line header |
| 60_custody | 25 | 793 | STATE ⚠ | KEEP | custody chain, handoff, 정산≠반환, runner-to-runner transfer. ⚠ one-line header |
| 65_assignment | 10 | 312 | STATE ⚠ | KEEP | assignment loop + candidate privacy + T-10 retire. ⚠ one-line header |
| 66_r4 | 8 | 217 | MONEY ⚠ | KEEP | consent gate, cancel ladder, capacity, host fee ledger. ⚠ one-line header |
| 67_shell | 7 | 277 | SECURITY ⚠ | KEEP | access grade, moderation, roster rule B, phone. ⚠ one-line header |
| 68_adversarial | 8 | 219 | SECURITY ⚠ | KEEP | V1 is a schema-wide seal sweep (RLS on + 0 policies + 0 stranger rows) — standing tripwire |
| 70_axes | 13 | 306 | SHAPE ⚠ | KEEP | axis backfill/sync/drift + X10 RLS seal. ⚠ X1/X7/X13 are three angles on "drift zero" |
| 80_choke | 6 | 108 | SECURITY ⚠ | KEEP | open-request view: leak, party, column whitelist, service_role. ⚠ one-line header |
| 95_audit_gates | 15 | 367 | SECURITY | KEEP | 0052 party gate · custody guard · honesty badge |
| 96_audit_followups | 6 | 225 | SECURITY | KEEP | method_consent, trace append, photo_allowed, post-reject chat |
| 97_availability | 15 | 508 | STATE | KEEP | the display mirror of the accept gate, both directions. DO-NOT-REFACTOR names these predicates |
| 98_hardening | 9 | 346 | SECURITY | KEEP | H1 sweeps every definer's in-body `search_path` schema-wide. Standing invariant |
| 99_security | 11 | 464 | SECURITY | KEEP | S1 sweeps anon EXECUTE over every definer schema-wide. Standing invariant |
| 100_wave3 | 14 | 527 | SECURITY | KEEP | pickup-address gate, hold expiry, arrived_at CAS |
| 101_runner_insert_seal | 8 | 175 | SECURITY | KEEP | a signup cannot mint tier=master / commission 0 / identity_verified |
| 102_runner_funnel | 14 | 595 | SECURITY | KEEP | the only tier-promotion path; application table unreachable; projection leak |
| 103_owner_la | 17 | 402 | SECURITY ⚠ | KEEP | APNs token registry seal, party-before-state. ⚠ several pins assert push PAYLOAD shape/vocab |
| 104_private_media | 14 | 253 | SECURITY | KEEP | private bucket denies by execution, not by policy text |
| 105_enroute_cancel | 8 | 158 | MONEY | KEEP | en-route cancel fee ladder (50% literal) + the widening that must NOT reach picked_up |
| 106_incident_subject | 8 | 260 | SECURITY | KEEP | P1 subject injection + cross-club payout freeze |
| 107_recovery_force_resolve | 7 | 352 | STATE | KEEP | three defects that strand a session and its money forever |
| 108_incident_accountability | 7 | 251 | MONEY | KEEP | case ownership, hold recompute, stale delegation sweep |
| 109_payments | 12 | 432 | MONEY | KEEP | the shape of the table that will hold real charges, pinned while it is still empty |
| 110_incident_settlement | 7 | 290 | MONEY | KEEP | the commercial exit from incident_review; literals, not re-derivation |
| 111_address_note | 8 | 169 | SECURITY | KEEP | the one owner-writable definer — the point is the columns that must NOT move |
| 112_handles_feed_claims | 13 | 213 | SHAPE ⚠ | KEEP | F1 pins a Sean DECISION (uploads unrestricted). ⚠ H2/H4/H5 are handle-format arms, trimmable |
| 113_km_ledger | 24 | 530 | MONEY | KEEP | the stored-value system: burn order, expiry, idempotence, clamps |
| 114_recurring_guard | 5 | 87 | SECURITY | KEEP | caller-class double belt on create_recurring_series |
| 115_pace_state | 10 | 365 | STATE ⚠ | KEEP | pace honesty gate + snapshot seal. ⚠ part of the claim is push payload vocabulary |
| 116_charge | 26 | 1292 | MONEY | KEEP | the charge machine: basis table, ceiling, mints, debt, sweeps, cutover |
| 117_club_money | 9 | 522 | MONEY | KEEP | the third booking path's debt + instrument gates |
| 118_route_ladder | 14 | 376 | SHAPE | KEEP | **merge target for 134/135** — a course is verified only after a dog ran it |
| 119_run_end | 18 | 1372 | MONEY | KEEP | freeze · seal · 귀가 · janitor. 귀가 as a server invariant |
| 120_g1_ops_cutover | 11 | 805 | MONEY | KEEP | Sean's rulings ①③⑥ as SQL; J1 pins dog_condition ≡ completed as an identity |
| 121_cancel_share | 7 | 186 | MONEY | KEEP | the runner's half of the 10% tier — the sentence the cancel sheet already shows owners |
| 122_runner_stop_pay | 5 | 229 | MONEY | KEEP | ⑨a pass-through as a FORMULA, not the memo's two figures |
| 123_run_insert_seal | 10 | 643 | SECURITY | KEEP | a `runs` row is a server fact from birth; three money outcomes measured |
| 124_profiles_column_grant | 10 | 618 | SECURITY | KEEP | RLS is row-level; phone + toss_customer_key needed a column wall |
| 125_return_force_ops | 6 | 505 | SECURITY | KEEP | Sean's ruling: a one-sided confirmation is not a confirmation. The CHECK survives a rewrite |
| 126_chat_notify | 5 | 111 | SECURITY | KEEP | recipient, sender silence, anti-storm, and no message body on a lock screen |
| 127_profiles_write_grant | 10 | 411 | SECURITY | KEEP | the write half of 0088's wall; W5 executes the real PostgREST upsert statement |
| 128_runner_work_gate | 6 | 345 | STATE | KEEP | ⑫ the gate is DERIVED — written to fail if someone caches it in a column |
| 129_availability_anon | 6 | 143 | SECURITY | KEEP | cuts the name × 동네 × time join for anon without killing the storefront (A3) |
| 130_incident_verification | 6 | 434 | SECURITY | KEEP | opening is one-sided, verifying is two-sided, the phone door opens on the OPEN |
| 131_club_critical_titles | 7 | 151 | SECURITY ⚠ | KEEP | registry with no read policy. ⚠ C5 has no mutation in 0095 that reddens it — its own header says so; it reddens only if the ack fanout breaks |
| 132_gated_runner_exit | 6 | 354 | STATE | KEEP | E3 is the only end-to-end pin across three migrations — the composition nobody owned |
| 133_unsettled_run_detection | 7 | 358 | MONEY | KEEP | the alarm 0096 removed: un-gated and still unpaid |
| 134_route_elevation | 7 | 284 | SHAPE | **MERGE-INTO-118** | keep the NULL≠0 distinction + the `>= 0` floor + the read surface; **cut the catalog-data-quality arms. Unpinned: "the 0078 seed rows carry the elevation they were measured at" — the header already says the 19 other values are production data no fixture can carry** |
| 135_route_trace_shape | 5 | 175 | SHAPE | **MERGE-INTO-118** | keep the two arms that prove a bad value is REFUSED on both geometry columns; **cut the remaining shape arms. Unpinned: none — 118 R5's evidence CHECK and the migration's non-`not valid` validation cover them** ⚠ |
| 136_route_name_km | 4 | 115 | SHAPE | **CUT** | a km token in a 32-row admin-curated catalog agreeing with `routes.km`. **Unpinned: "a route name that claims a length keeps claiming a true one after geometry is re-cut". Its own header says the real proof was the constraint validating WITHOUT `not valid` on push — the constraint stays; only the pins go** |
| 137_runner_payout | 8 | 462 | MONEY | KEEP | the captured equivalence table from the deleted TypeScript. Re-deriving would destroy it |
| 139_run_channel_rls | 9 | 177 | SECURITY | KEEP | live GPS: executed at the realtime.messages boundary, not against the predicate |
| 141_drops_seal | 23 | 505 | MONEY | KEEP | a reward drop is a server fact; the published exploit reproduced and closed |
| 142_route_evidence | 9 | 548 | SECURITY | KEEP | the catalog is public; the runner and curator behind it are not |
| 143_realtime_chat_bk | 14 | 396 | SECURITY | KEEP | three postgres_changes rooms admit exactly their table's people, wired not stated |
| 144_revoke_truncate | 5 | 256 | SECURITY | KEEP | TRUNCATE/TRIGGER/REFERENCES — the verbs RLS never covered. T1 executes per role per table |
| 145_routes_public | 4 | 163 | SECURITY | KEEP | the de-identified projection and the gate that stops it being decorative |
| 146_booking_entry | 24 | 953 | SECURITY | KEEP | a client cannot make a booking row exist. Supersedes the deleted suite 140 |
| 147_view_dml | 4 | 108 | SECURITY | KEEP | a definer view has no RLS behind it; D3 is a schema-wide watchdog for the next such view |
| 148_geometry_revoke | 3 | 116 | SECURITY ⚠ | KEEP, **cut R2** | R1/R3 are the wall and the outage control. **R2 is unfalsifiable by its own measurement — the header records "R2 has no revert that can redden it" (service_role holds table-wide SELECT, so a column revoke against it is a no-op). Per the standing law a limitation is prose. Unpinned: nothing — R2 never pinned anything** |
| 149_party_active | 29 | 926 | SECURITY | KEEP | a nominated-but-not-accepted stranger is not a party for any WRITE surface |
| 150_account_deletion | 30 | 1386 | SECURITY | KEEP | App Store 5.1.1(v) + PIPA 제37조. N6's wildcard closure is legal-surface |
| 151_flip_blockers | 8 | 618 | MONEY | KEEP | four defects inert today and real on flip day; every pin written both ways |
| 152_late_booking | 61 | 2350 | MONEY ⚠ | KEEP | the clock, resolver, fault, the 0066 carve-out. ⚠ largest suite; an internal trim pass is warranted, not a suite cut |
| 153_club_cancel_fee | 16 | 1784 | MONEY ⚠ | KEEP | ruled cancel/no-show ladder + ledger. ⚠ 735 comment lines incl. a superseded pre-ruling measurement block — prose trim, no pin cut |
| 156_runner_money_strip | 19 | 355 | SECURITY | KEEP | net-only server surfaces; P15's sweep is argnames-only and says so |
| 157_pickup_dong | 15 | 568 | SECURITY | KEEP | the first pre-accept disclosure about where a dog lives, pinned both ways |
| 158_runner_base_distance | 23 | 1192 | SECURITY | KEEP | 개인위치정보 at rest + the cooldown that is the actual defence (quantization was measured false) |
| 159_cancel_ladder_repricing | 6 | 217 | MONEY ⚠ | KEEP | rulings #11/#13. ⚠ L1/L2 match notification COPY (`%취소 수수료는 없어요%`) — replace those matchers with the fee VALUE and the suite stops being copy-coupled |
| 160_flip_activation | 4 | 67 | INFRA ⚠ | KEEP | bounded tick + partial index + flag gate; F2 is a source pin the harness cannot reach behaviourally. ⚠ smallest real suite |
| 161_breed_gate_removal | 6 | 1123 | SHAPE | **MERGE-INTO-173** | **worst ratio in the corpus: 187 lines per pin, 648 of 1,123 lines are comments.** Keep P1/P2/P5 (P2 is the one-liner that reds when an orphaned trigger bricks every dog save). **Cut P3/P4/P6 — they re-run 0127's own apply-time VERIFY. Unpinned: "nobody re-creates the dropped 맹견 columns/enum in a later migration". Real but low-probability; the ruling was "remove it completely"** ⚠ |
| 162_club_return_address | 10 | 735 | SECURITY | **MERGE-INTO-163** | 163 is 162 CORRECTED — 163's own header records that 162's fixtures were not reachable by the lifecycle, so its repairs "detected their tailored mutations without establishing the property on any real path". **Unpinned: none — 163 P1..P15 re-establish every proposition on RPC-driven fixtures, plus 162's P1 differential which belongs in `docs/contracts/club-return-address-arm-contract.md`** |
| 163_club_return_address_fix | 16 | 1147 | SECURITY | KEEP | the custody arm that closes by itself, on lifecycle-reachable fixtures |
| 164_scoped_read_policies | 18 | 1175 | SECURITY | KEEP | four club tables lose `(auth.uid() IS NOT NULL)`; G5 pins the deparsed predicates |
| 165_ledger_row_reason | 6 | 164 | MONEY | KEEP | a runner's earnings row says why, and the run it reads is one they performed |
| 166_phone_collection | 8 | 195 | SECURITY | **MERGE-INTO-185** | same column, same switch, same grant question as 185/197. **Unpinned: none — P1..P7 move verbatim; 185's header already says "166 pins X, this suite pins what 0154 ADDS"** |
| 167_club_rsvp_hardening | 23 | 448 | STATE | KEEP | every refusal also asserts ZERO writes — the damage, not the token |
| 168_approve_notification | 3 | 96 | **COPY** | **CUT** | N1 asserts the title contains `20분` and `자리` and not `결제`/`청구`/`환불`; N2 asserts the exact literal `위탁 신청 거절`. **G1 is worse than copy: its schema-wide sweep matches `prosrc like '%움직이는 돈은 없다%'` — a COMMENT — which is precisely the comment-matching class CLAUDE.md says is uninformative. Unpinned: "a step where no money moves does not send a title claiming payment". Keep it as a line in the contract; if Sean wants it pinned, it belongs as one VALUE arm (no ledger row, no intent row) in 117, not as a string match** |
| 169_club_session_board | 14 | 544 | SECURITY | KEEP | **merge target for 172/184** — the DONE test: a one-minute-old member can name nothing |
| 170_billing_key_swap | 6 | 122 | MONEY | **MERGE-INTO-188** | billing-key family, ten files for one lifecycle. **Unpinned: none — B1..B6 move as-is** |
| 171_billing_key_revocation | 8 | 180 | MONEY | **MERGE-INTO-188** | same family. **Unpinned: none — R1..R8 move as-is** |
| 172_board_profile_ids | 4 | 112 | SECURITY | **MERGE-INTO-169** | an id must not be disclosed where the name is hidden — the same gate 169 owns. **Unpinned: none — I1..I4 move as-is** |
| 173_owner_dog_limit | 4 | 77 | STATE | KEEP | **merge target for 161** — Sean 「1 dog per person」 on the dogs/session_dogs trigger |
| 174_revocation_lease | 6 | 150 | MONEY | **MERGE-INTO-188** | same family. **Unpinned: none — L1..L6 move as-is** |
| 175_revocation_live_key | 7 | 203 | MONEY | **MERGE-INTO-188** | same family. **Unpinned: none — V1..V7 move as-is** |
| 176_club_pack_run_end | 14 | 1262 | MONEY | KEEP | **merge target for 179** — P7 compares the two numbers nobody compares |
| 177_profile_board_peer | 8 | 326 | SECURITY ⚠ | KEEP | the board's tap resolves to a card. ⚠ third board suite; merge with 169/172/184 if the merge is done at all |
| 178_companion_run_record | 13 | 486 | STATE ⚠ | KEEP | the 동반 walk gets a record; C1 catches the person_id-vs-profile_id FK trap. ⚠ mixed SHAPE |
| 179_board_run_frozen_flag | 4 | 78 | MONEY | **MERGE-INTO-176** | 0147 exists only because 0144's freeze had no client-visible key. **Unpinned: none — F1..F4 move as-is** |
| 180_revocation_claimed_forever | 7 | 281 | MONEY | **MERGE-INTO-188** | same family; W1/W6 are source pins for locks the harness cannot reach behaviourally. **Unpinned: none — W1..W7 move as-is** |
| 181_revocation_tick_answerable | 9 | 534 | INFRA | **MERGE-INTO-188** | a refused tick and an empty queue must be two readable states. **Unpinned: none — P1..P9 move as-is** |
| 182_net_schema_grants | 5 | 91 | SECURITY ⚠ | KEEP | ⚠ **narrow by its own header: production's `net` is owned by `supabase_admin` and `postgres` cannot revoke there, so N1/N2 are green here because THIS harness can revoke. It guards a needless grant behind one config line, not a live exposure.** Kept because the config is a setting, not an invariant |
| 183_unmeasured_not_zero | 5 | 133 | MONEY | **MERGE-INTO-189** | 189's own header says it "continues 0152/183's job" and states the identical distinction. **Unpinned: none — U1..U5 move as-is and sit beside the aggregates that inherit them** |
| 184_board_impl_acl | 5 | 85 | SECURITY | **MERGE-INTO-169** | the inner board function; the defect was measured live on production. **Unpinned: none — B1..B5 move as-is** |
| 185_phone_switch | 10 | 491 | SECURITY | KEEP | **merge target for 166/197** — collection shut by default, as a refusal not a no-op |
| 186_revocation_abandoned_alert | 13 | 481 | INFRA | **MERGE-INTO-188** | same family; alerting on exactly the two failing paths. **Unpinned: none — A1..D3 move as-is** |
| 187_gps_trace_bounds | 7 | 176 | MONEY | KEEP | a runner-supplied timestamp froze 99 km into a 5 km booking. Live money, no flag |
| 188_billing_hardening | 9 | 444 | MONEY | KEEP | **merge target for 170/171/174/175/180/181/186/192/196/200** — at most one outstanding revocation per key |
| 189_settled_distance | 14 | 609 | MONEY | KEEP | **merge target for 183** — settled money is labelled with the distance that priced it |
| 190_pack_map_channel | 21 | 770 | SECURITY ⚠ | KEEP | pack channel read side. ⚠ four pins were INVERTED by 0160; 190+191 are one contract read from two ends and are a candidate single suite |
| 191_pack_publish | 16 | 1041 | SECURITY ⚠ | KEEP | the RPC that replaced the socket write door. ⚠ see 190 |
| 192_billing_keys_grants | 3 | 94 | SECURITY | **MERGE-INTO-188** | billing_keys sealed by two walls. **Unpinned: none — N1..N3 move as-is** |
| 193_chat_client_key | 3 | 81 | SHAPE ⚠ | KEEP | partial unique index idempotency, three arms with different blind spots. ⚠ small but no natural home |
| 196_revocation_findings | 5 | 305 | INFRA | **MERGE-INTO-188** | same family; explicitly written as "what 186 could not see". **Unpinned: none — F0..F4 move as-is, next to the 186 pins they repair** |
| 197_phone_visibility_gate | 5 | 281 | SECURITY | **MERGE-INTO-185** | the read half of the switch 185 pins on the write side. **Unpinned: none — P1..P5 move as-is** |
| 198_two_phase_stop | 8 | 672 | MONEY | KEEP | **merge target for 199** — live money, un-flag-gated |
| 199_settle_stopping_belt | 4 | 365 | MONEY | **MERGE-INTO-198** | the SQL door behind 0168's 409; its own header calls itself "0168's defect through a different door". **Unpinned: none — B1..B4 move as-is** |
| 200_billing_intent | 8 | 434 | MONEY | **MERGE-INTO-188** | same key lifecycle, same flag, same latency. **Unpinned: none — B1..B8 move as-is** |

## (a) Suites whose pins are SOURCE pins on `prosrc` only

**None.** Measured: 30 of the 112 registered suites reference `prosrc`, and every one pairs it with a behavioural
arm. The source pins are deliberate and each says why in its header — they exist where the harness
is *structurally* single-connection or single-transaction and cannot reach the property:

`121 S6` · `156 P8b` · `159 L4` · `160 F2` (lock wait) · `167 G0` (session lock) · `169 P14` ·
`170 B6` (row lock) · `180 W1/W6` (outbox lock) · `191 0160-S1` · `197 0167-P5` ·
`198 0168-P8` · `199 0169-B4`.

The highest source ratio is **161** (23 `prosrc` references, 6 pins) — its P3/P4/P6 re-run a
migration's apply-time VERIFY — and it is the one merge-with-cut proposed above.
⚠ Note in their favour: `187 G6/G7`, `191 S1`, `197 P5` and `199 B4` **strip comments before
matching**, which is the house fix for the comment-matching class. Any source pin that does not
strip should be repaired rather than cut.

## (b) Same property from different angles — candidates for one merged suite

| cluster | suites | files→ | p | L |
|---|---|---|---|---|
| billing-key lifecycle (issue · swap · revoke · lease · alert · grants) | 170 171 174 175 180 181 186 188 192 196 200 | **11 → 1** | 81 | 3,228 |
| phone collection (write · switch · read) | 166 185 197 | 3 → 1 | 23 | 967 |
| club session board (board · ids · peer card · inner ACL) | 169 172 177 184 | 4 → 1 ⚠ | 31 | 1,067 |
| route catalog (ladder · elevation · trace shape · name/km) | 118 134 135 136 | 4 → 1 | 30 | 950 |
| club return address (arm · corrected arm) | 162 163 | 2 → 1 | 26 | 1,882 |
| unmeasured-vs-zero km (per-run quote · per-row label + aggregates) | 183 189 | 2 → 1 | 19 | 742 |
| two-phase stop (edge belt · SQL belt) | 198 199 | 2 → 1 | 12 | 1,037 |
| pack map (read side · publish RPC) | 190 191 | 2 → 1 ⚠ | 37 | 1,811 |
| pack run-end (fan-out · frozen flag) | 176 179 | 2 → 1 | 18 | 1,340 |

⚠ **A merge is not free and the risk is asymmetric.** These files each say "every pin causes its own
delta" precisely because siblings leave rows behind; merging them into one file makes that
discipline easier to hold, but the merge itself is an edit to 21 green suites. Per this repo's own
law, a merged suite's pin TOTAL must be recorded before and after and the delta must equal zero —
if it does not, the merge silently dropped coverage and the harness will not say so.

## (c) Suites whose header pins a limitation or an unfalsifiable guard

Measured across all 112 headers. **The corpus is already compliant** — 00_shim, 164, 182, 186, 188,
189, 190, 191, 200 each explicitly refuse to pin a limitation and write it as prose instead, citing
the standing law. Two exceptions, both small:

1. **`148 R2`** — the header states in its own words that R2 "has no revert that can redden it".
   **CUT the arm.** It licenses nothing.
2. **`131 C5`** ⚠ — "NO MUTATION IN 0095 REDDENS IT", and a predicted mutation was measured wrong.
   **KEEP**: it is falsifiable against the ack fan-out itself (drop `club_ack_fanout`, drop the
   trigger's registry lookup), which is live code. It is a positive control on a neighbouring
   feature, not an unfalsifiable guard — but a human should confirm that reading.

## (d) Totals

**By bucket (primary classification, 112 suites):**

| bucket | suites | pins | lines |
|---|---|---|---|
| SECURITY | 50 | 541 | 21,721 |
| MONEY | 37 | 450 | 19,046 |
| STATE | 11 | 151 | 4,561 |
| SHAPE | 8 | 65 | 2,673 |
| INFRA | 4 | 31 | 1,387 |
| COPY | 2 | 8 | 163 |
| UNCLEAR | 0 | — | — |
| **total** | **112** | **1,246** | **49,551** |

**By verdict:**

| verdict | suites | pins affected |
|---|---|---|
| KEEP | 88 | 1 arm cut (148 R2) |
| MERGE (into 8 targets) | 21 | 20 cut inside 4 of them (134, 135, 161, 162) |
| CUT (whole suite) | 3 | 12 |

**⚠ rows: 29 of 112.** Twelve are the legacy one-line-header suites (10 · 20 · 30 · 40 · 50 · 60 ·
65 · 66 · 67 · 68 · 70 · 80), where the bucket comes from pin labels and body rather than from a
stated property. The other seventeen (103 · 112 · 115 · 131 · 135 · 148 · 152 · 153 · 159 · 160 ·
161 · 177 · 178 · 182 · 190 · 191 · 193) are rows where the bucket is genuinely mixed, the value is
narrower than the file's name suggests, or a merge is arguable rather than clear. **Nothing on a ⚠
row should be cut without a human reading the file.**

## (e) After the proposed cuts

| | now (measured) | after (estimated) |
|---|---|---|
| registered suites | 112 | **88** |
| pin call sites | 1,246 | **~1,214** (−32, −2.6%) |
| lines | 49,551 | **~46,250** (−3,300, −6.7%) |
| comment lines | 16,137 (32.5%) | ~14,000 |

Line arithmetic: whole-suite cuts −278 (40, 136, 168) · arm cuts inside merges −1,880 (161 ≈ −900,
162 −735, 134 −160, 135 −70, 148 R2 −15) · header-prose dedup across the 8 merge clusters ≈ −1,150.
⚠ The last figure is an ESTIMATE, not a measurement — it assumes ~25% of the merged files' 4,600
header lines are restatements of their target's. Nothing else in this document is estimated.

## What I would actually do, and what I would not

**The three cuts I am most confident of, each with its unpinned property named:**

1. **168_approve_notification (3 pins, 96 lines)** — the only suite whose pins are wholly string
   matches on a notification title, and whose schema-wide arm matches a *comment* in `prosrc`.
   **Unpinned: "an approval step that moves no money does not send a title claiming payment."**
   If Sean wants that kept, it is one VALUE arm in 117 (no ledger row and no payment intent exists
   at approval), which is stronger than the string match and survives a copy rewrite.
2. **136_route_name_km (4 pins, 115 lines)** — data quality on a 32-row admin-curated catalog.
   **Unpinned: "a route name claiming a length still claims a true one after the geometry is
   re-cut."** The CHECK constraint stays and was validated without `not valid` on push, which the
   suite's own header calls the real proof; only the fixture pins go.
3. **162_club_return_address (10 pins, 735 lines)** — superseded in full by 163, which rebuilt every
   proposition on lifecycle-reachable fixtures after finding 162's were constructible only by
   direct INSERT. **Unpinned: none — 163 owns all ten; 162's P1 pre-fix differential belongs in
   `docs/contracts/club-return-address-arm-contract.md`, not in the harness.**

**What I would not cut, and it is the answer to the question Sean asked.** 87 of 112 suites are
money or security, holding 991 of 1,246 pins and 40,767 of 49,551 lines. There is no version of
this diet that saves meaningful minutes or meaningful context without deleting money or security
pins. **Option D's honest yield is ~2.6% of pins.** If the goal is context and time rather than
tidiness, options A (move CLAUDE.md's incident narratives to `docs/laws/`), B (stop writing new
harness by default) and C (one runner for the app test chain) are where the saving actually is —
and the 16,137 comment lines in `supabase/tests/` are a bigger single target than every cut
proposed above combined.

## Unregistered files in `supabase/tests/` — all four accounted for

`00_shim.sql` (harness preamble) · `90_race_setup.sql` (consumed by `90_race_check.sh`) ·
`upgrade_seed_v1.sql` (consumed by `upgrade_check.sh`, a separate upgrade-path gate) ·
`154_dangerous_breed_suite.sql` (**deliberately retired** — 0127 removed the gate on Sean's ruling
and 161 replaced it; the file stays on disk as the record of what the gate did, which is the house
form of retirement). None is orphaned; none needs action.
