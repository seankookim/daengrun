# Migration + suite number registry

**Claim your number HERE, in a commit pushed to `origin/redesign-v4`, BEFORE you write
the file.** Four collisions happened on 2026-08-13 alone (0078 claimed three times,
0081 twice, 0082 twice) because every parallel session picks "next free" against its own
fork point, which is stale the moment another session lands.

## The rule

1. `git fetch origin && git log --oneline origin/redesign-v4 -1` — then read THIS file at
   `origin/redesign-v4`, not on your branch.
2. Add your row, push that one-line commit to `origin/redesign-v4` immediately.
3. Then write the migration. If step 2 conflicts, someone took it — take the next.
4. Unpushed work does not reserve a number. A number is claimed when it is on origin.
5. **Tiebreak when two sessions both claim:** whoever has NOT yet written the file moves,
   regardless of who announced first. And when yielding, say so to the other session
   explicitly — two polite simultaneous yields put both parties on the same next number,
   which happened on 0083.

## Two security detectors, both earned by a miss (trust, 2026-08-14)

**① Audit the tables with NO policies — not the policies.** `0088` and `0093` were both policies
with no caller term, and every sweep that found them enumerated `pg_policies`. A table with RLS
**off** contributes zero rows to that view, so it is invisible to exactly the query that catches
its siblings — and in a listing it looks identical to the many tables here that are
RLS-on-with-no-policies, which are fail-CLOSED and correct. `club_critical_titles` sat open from
`0049` to `0095` for this reason: anon could `GET` (200) and `DELETE` (204) it over PostgREST with
the shipped public key, which silently disables the 30-minute unacked→host alert escalation.

    select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity = false;

⚠ **CORRECTION 2026-08-14, same day, by the session that wrote detector ② — it has a
false-negative class and the wrong version is kept below so nobody re-derives it.** The query I
used was `qual NOT LIKE '%auth.uid()%'`. It misses `runners`, whose policy is
`tier <> 'applicant' OR profile_id = auth.uid()` — a caller term in ONE ARM OF AN OR, which is
not a caller *gate*: the first disjunct alone matches for anon, and 9 rows with 7 free-text
`bio`s are readable without an account. **Presence of `auth.uid()` does not mean gated by
`auth.uid()`.** A grep cannot tell a gate from a disjunct, so the enumerator must be
privilege-based, not text-based:

    -- what can anon ACTUALLY read? ask the engine, not the policy text
    select c.relname, has_table_privilege('anon', c.oid, 'SELECT') as anon_select
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r','v','m') and has_table_privilege('anon', c.oid, 'SELECT');

then `set local role anon` and COUNT each one. Include `relkind in ('v','m')` — views were the
other miss; `available_runners` and `marketplace_open_requests` are anon-readable definer views
that no `pg_policies` query returns at all.

**④ A FLOOR TESTED ONLY WHERE IT BINDS ASSERTS NOTHING ABOUT THE BASE UNDERNEATH IT.**
Money's finding on `0101`, 2026-08-15, and it is detector ③ in a third costume. Mutating the
runner base 9,900 → 7,900 reddened an unrelated pin **and left the `min_fare` floor pins GREEN** —
because a 20,000 floor absorbs a 2,000 underpay. **The floor and the base are two parts of one
control**, and a suite that exercises the floor only on rows where it binds proves nothing about
the number underneath it: every runner could be quietly underpaid with the floor pins green.

⚠ **And the production half is worse than the test half.** `min_fare` defaults to **9,900 —
exactly the runner base** — so **on shipped data the floor is a tautology and never binds.** Every
fixture that exercises it is invented (`0101`'s fixture C uses 20,000). So anyone reasoning about
the floor from production rows concludes it is inert, and the only rows that would reveal an
underpaid base do not exist yet.

The general form, which is what to carry: **when a control has a clamp and a value, test the
value where the clamp does NOT apply.** Testing where it does apply measures the clamp.

**③ WHEN THE GRANT AND ITS PROTECTION LIVE IN DIFFERENT PLACES, NEITHER SWEEP TELLS THE TRUTH.**
Found by money on `runs`, 2026-08-14, verified by me: `has_table_privilege` says **anon AND
authenticated hold INSERT**, while `runs` carries exactly two policies — `runs party read`
(SELECT) and `runs runner update` (UPDATE) — and **no INSERT policy at all**, so RLS default-deny
is the only thing refusing the write. `0087` dropped the old `runs runner write` policy and left
the grant standing.

Harmless today. **The hazard is the shape:** the privilege says yes and the missing policy says
no, so a later convenience feature that adds a permissive INSERT policy reopens `0087`'s forgery
hole **with no grant change for a grants audit to see**. And it is exactly the blind spot detector
① and the corrected ② each have on their own — a privilege enumerator reports INSERT granted and
shrugs; a policy sweep finds nothing to flag. **Only the JOIN of the two is a control.**

    -- tables where a role holds a write privilege that no policy grants
    select c.relname, has_table_privilege('anon', c.oid, 'INSERT') as anon_ins,
           (select count(*) from pg_policies p where p.tablename = c.relname and p.cmd = 'INSERT') as ins_policies
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='public' and c.relkind='r' and has_table_privilege('anon', c.oid, 'INSERT');

⚠ **And this one has a money consequence, which is why it is written here rather than left tidy:**
`0087` closing that path is the stated reason a **blocking cutover gate was downgraded** (the
charge sweep re-anchoring off client-writable `runs` data). If the grant ever becomes live again,
it silently re-arms a money-path risk that a cutover document now records as handled. **A
downgrade that rests on a precondition must name the precondition, or the precondition can rot
without the downgrade noticing.**

**② A `using (true)` policy is neither a finding nor a pass — the GRANT decides.** `0093`
deliberately LEFT `using (true)` in place and closed its hole with a revoke; `profiles` still
carries a no-caller-term policy and is shut. So a sweep that greps `0002_rls.sql` for a missing
`auth.uid()` flags two closed holes and misses an open one. **Read grants and policies together,
then execute as the role** — `set local role anon`, and over HTTP where you can, because that is
the path an attacker actually has. ⚠ And clear `request.jwt.claim.sub` before `set local role
anon`, or `auth.uid()` keeps returning an earlier user and the probe lies (six false positives in
suite 124).

⚠ **An empty result is not a control.** `club_sessions` currently exposes 13 real meetup points
and times to anon; the name-join returns 0 only because today's hosts happen not to appear in
`available_runners`. Recording that as "0 rows, fine" is the same error as reading `[]` through an
anon key as "the table is empty" when it means "hidden". See `docs/security-club-session-exposure.md`.

## The silent collision class — worse than numbering

Numbering collisions are loud (you find out at merge). Several slices `create or replace`
the SAME objects — `settle_run_tx`, `sweep_settled_without_payments`, `compute_owner_charge`,
`_guard_run_cols`, the 0063/0079 LA triggers and stale sweep. **Re-creating one another slice
just changed silently reverts it, and the harness still passes**, because each slice's pins
live in its own suite. Before re-creating a shared object, read the newest migration that
touched it and name whose version you build on in your file header.

## Claimed

| # | Migration | Suite | Owner (branch) | State |
|---|---|---|---|---|
| 0078 | `0078_route_catalog.sql` | — | banpo-route-catalog | on origin/redesign-v4 |
| 0079 | `0079_pace_state.sql` | 115 | pace-state-ui-build | on origin/redesign-v4 |
| 0080 | `0080_charge_machine.sql` | 116 | payments-toss-plan-slice | on origin/redesign-v4 |
| 0081 | `0081_club_money_gates.sql` | 117 | club-money-gates | on origin/redesign-v4 |
| 0082 | `0082_route_ladder.sql` | 118 | **route session** (반포 route catalog / route discovery; landed via the main checkout, `a95aa34`) | on origin/redesign-v4 — settled |
| 0083 | `0083_run_end_flow.sql` | 119 | run-end-flow (`claude/run-end-flow-1a67e0`) | **SETTLED 2026-08-13** — on disk, in build |
| 0084 | `0084_g1_ops_cutover.sql` | 120 | payments (`claude/g1-ops-club-decisions`) | **SETTLED 2026-08-13** — on disk, in build |
| 0085 | `0085_cancel_share.sql` | 121 | ⑩ cancel-fee runner share (`claude/club-delegation-money-gaps-b59eb8`) | **BUILT 2026-08-13** — harness 467/0, deno 161/0, 5 mutations verified |
| 0086 | `0086_runner_stop_passthrough.sql` | 122 | ⑨a pass-through runner pay (`claude/g1-ops-club-decisions`) | **TAKEN** — file pushed on that branch 2026-08-13; row added by a third session that spotted it |
| 0087 | `0087_run_insert_seal.sql` | 123 | **runs INSERT seal** — revoke client INSERT on `runs` + atomic `start_run_tx` (`claude/run-end-flow-1a67e0`) | **BUILT 2026-08-13** — harness 487/0 (baseline 478/0), deno 173/0, 4 mutations verified |
| 0088 | `0088_profiles_column_grants.sql` | 124 | profiles column grants — P0 PII/PG-key leak (`claude/g1-ops-club-decisions`) | **CLAIMED 2026-08-13** — `profiles public runner read` has no column grant, so `phone` and `toss_customer_key` are returned to any authenticated user |
| 0089 | `0089_return_force_ops_only.sql` | 125 | return force → OPS ONLY (`claude/run-end-flow-1a67e0`) | **CLAIMED 2026-08-13** — Sean: *"the confirmation must happen with both parties and never just the runner. also handoff."* Removes `runner`/`owner` from the force actor set |
| 0090 | `0090_chat_notify.sql` | 126 | ⑬ chat→notification trigger (`claude/club-delegation-money-gaps-b59eb8`) | **BUILT 2026-08-13** — harness 510/0, deno 185/0, 5 mutations verified |
| 0091 | `0091_profiles_write_grants.sql` | 127 | profiles WRITE column whitelist — the other half of 0088 (`claude/g1-ops-club-decisions`) | **BUILT 2026-08-13** — harness 515/0, 8 mutations verified. Was claimed as 0089; `claude/run-end-flow-1a67e0` pushed its 0089 FILE first, so this moved (whoever has no file moves). ⚠ **0088 CANNOT DEPLOY WITHOUT THIS** — 0088's grant omits `role`, and PostgREST's role-picker upsert reads `excluded.role`, so every signup 403s until this lands. |
| 0092 | `0092_runner_work_gate.sql` | 128 | ⑫ runner work gate (`claude/run-end-flow-continuation-d9c485`) | **BUILT 2026-08-13** — harness 529/0, deno 185/0, 3 mutations verified. Sean: *"pay the runner but dont let them make new runs until the dog is confirmed by both sides."* ⚠ **RENAMED from `0092_incident_verify_work_gate` and DESCOPED to ⑫ alone.** The claim said ⑫'s exit IS ⑪'s machine; it is not — Sean said the **dog** is confirmed, which is 0083's two return stamps (shipped), not ⑪'s incident verification (unbuilt). ⑫ ships alone and ⑪ stays open. Also DERIVED, not a `runners` flag: a flag is a cache of a derivable and drifts, the shape 0089's review removed the same day. NEW objects only: `runner_work_gate`, `_runner_work_gate_blocking`, `bookings_runner_unreturned_idx`. Also edits `transition-booking/index.ts` (accept path, before the conflict guard). ⚠ **MY PROCESS MISS, kept because it is the useful part:** another session hit the pre-push hook on 0092 and recorded a row saying "taken by file, row was missing". They were right. I did claim before writing — but I pushed the claim to MY BRANCH, not to `origin/redesign-v4`, so trunk's copy of this table never showed it. Step 2 of the rule says *push that one-line commit to `origin/redesign-v4`*, and a claim that lands anywhere else is invisible to exactly the person it exists to warn. Their row is folded into this one rather than deleted. |
| 0093 | `0093_availability_anon_revoke.sql` | 129 | runner_availability_rules anon revoke (`claude/g1-ops-club-decisions`) | **BUILT 2026-08-13** — post-deploy canary measured it live: anon reads 63 rows / 9 runners, and 6 of them join to name+동네 via `available_runners`. `0002:77` is `using (true)` — the same no-caller-term shape as 0088, two lines below it in the same file. ⚠ Closes the no-account case only; authenticated bulk read remains (§C, Sean's call). |
| 0094 | `0094_incident_verification.sql` | 130 | ⑪ two-sided incident verification + the marketplace incident-open path (`claude/run-end-flow-continuation-d9c485`) | **BUILT 2026-08-13** — harness 539/0, deno 185/0, 4 mutations verified. Sean: *"incident verified by both runner and owner."* ⚠ Was bigger than two stamps: `incidents` had **NO WRITER anywhere**, so `incident_contact()` (0088 §E) returned 0 rows for every marketplace booking — the door Sean's phone ruling depends on was built, correct, and connected to nothing. Also DROPS `0002:154`'s `"incidents report"` INSERT policy, which checked only `reporter_id = auth.uid()` and not the booking — a remote privacy trigger the moment that door started working. 🔴 **The phone door opens on OPEN, not on verified** (an emergency cannot wait for the other party); mutation P3 proves the plausible 'hardening' reddens both V3 and 0088's own G7. NEW objects only: `open_incident_tx`, `verify_incident_tx`, `force_verify_incident_tx`; `incident_contact` UNTOUCHED. No money, no booking-status change (⑪ = is it real, ⑫ = what money does). |
| 0095 | `0095_club_critical_titles_rls.sql` | 131 | 🔴 `club_critical_titles` has **RLS OFF** — anon can insert/delete/truncate the registry that drives critical-alert acks (`claude/deploy-edge-functions-money-68e990`, worktree deploy-edge-functions-money-68e990) | **BUILT + DEPLOYED + VERIFIED 2026-08-14** — applied to production and re-checked as anon after the deploy (`42501 permission denied`). Found by executing against production, not by reading policies: anon INSERT took the table 13→14 and anon DELETE took it 13→12, both rolled back. Open since `0049`. Deleting a title silently disables the 30-minute unacked→host escalation for that alert class, including `인시던트 발생`. |
| 0096 | `0096_return_confirm_after_escalation.sql` | 132 | 🔴 ⑫ deadlock — a gated runner with no party-reachable exit (`claude/run-end-flow-continuation-d9c485`) | **BUILT 2026-08-14** — harness 544/0, deno 185/0, 3 mutations verified. Composition defect across three individually-correct migrations (`0092` gate · `0089` ops-only force · `0083` 2h escalation + `confirm_return_tx`'s `active`-only gate) that left a runner permanently unable to earn. Fix: a party may stamp the return from `incident_review` — a CUSTODY fact — but it does **NOT seal and does NOT settle**; money stays `active`-only and `incident_review` remains a money dead end for `settle_run_tx`/`_settle_sealed_run`/`force_return_tx`. EXTENDS `confirm_return_tx` ←0083 (only definition; 0084-0094 do not re-create it). NEW: `ops_gated_runners` (queryable detection, service_role). ⚠ 119 R16 arm ⓒ rewritten in the same slice — it asserted the `not_active` raise this removes. ⚠ **No pager built on purpose:** `ops_recipients` is 0 rows in production and `OPS_PROFILE_ID` is unset, so a pager today routes to nobody — ⑫'s memo says a signal whose remedy does not apply is worse than an unmonitored state. Recipient/ack/severity/response-time are Sean's. |
| 0097 | `0097_unsettled_run_detection.sql` | 133 | the alarm `0096` removed — a runner unpaid for work already done (`claude/run-end-flow-continuation-d9c485`) | **BUILT 2026-08-14** — harness 555/0, deno 185/0, 2 mutations verified. Found by money reviewing `0096`: before it, an escalated booking left the runner gated AND unpaid (loud); after it, un-gated and still unpaid (quiet). `0096` fixed the acute half and removed the symptom that made the chronic half noticeable. ⚠ money's suggested shape — a column on `ops_gated_runners` — CANNOT work, and mutation R1 proves it: that function requires a MISSING stamp, so its row vanishes at the instant the quiet case begins. NEW object only: `ops_unsettled_runs()` (`stable`, service_role). Writes nothing. **The money exit (`0083 §0h`) is untouched and remains money's slice.** |
| 0098 | `0098_route_elevation.sql` | 134 | `routes` has nowhere to store measured elevation gain (`claude/elevation-gain-migration-6e96a5`) | **BUILT + DEPLOYED + VERIFIED 2026-08-14** — applied to production and read back rather than assumed: 32 rows · 20 measured · 12 NULL · range 0–63 · 0 rows with a gain and no geometry · 0 on `active` · trigger and constraint both present. — harness 562/0 (baseline 556), 6 pins, 6 mutations verified. One nullable `integer`, no default, a `>= 0` floor, a geometry-follow trigger, and a backfill for the 20 rows with GPX behind them. **NULL means "no measurement for THIS row's current geometry", never "flat"** — a `default 0` would make every unmeasured route claim level ground. Two measured values are a genuine `0`, so 0-vs-NULL is a distinction the live data makes. NEW objects only: the column, `routes_elevation_gain_nonneg`, `_routes_elevation_follows_geometry` + its trigger. Re-creates nothing; no view, no policy, no grant, no definer function. `elevation_loss_m` deliberately NOT added (§0c-ⓐ: no producer, no reader). ⚠⚠ **ADVERSARIAL REVIEW CHANGED THE KEY AND THAT IS THE HEADLINE.** The draft keyed the backfill on `(town, name)` and shipped green. `0078:54` seeds `몽마르뜨 언덕 루프` (반포동) with `trace '[]'` and `km 2.0`, and the measured 34 m comes from a 1.59 km GPX — so on the harness and on any DB without the Strava ingest, the migration stamped "+34 m measured" onto a row with NO GEOMETRY, committing the exact lie it was written to prevent. The suite could not see it because its header asserted `routes` was empty here; it is not. Fixed by keying on `(town, name, km)` with a `jsonb_array_length(trace) >= 2` guard, and pinned by E5 — mutation M5 reproduces the original sentence. ⚠ Separately: my own payload was ALREADY stale within one session — upstream re-cut `반포 서래섬 리버 루프 3.71km` as `3.31km`, so a name-keyed row matched zero rows and reported success. §C-bis is a postcondition that raises on any payload/row disagreement, because a backfill that matches nothing must not look like one that worked. ⚠ `promote_route_from_run` (0082:136) replaces `trace` and knows nothing about this column, so §B-bis clears the gain whenever geometry changes unless a new measurement is supplied in the same statement — otherwise a candidate's climb silently becomes the certified route's. ⚠ Does NOT touch `anchor_lat`/`anchor_lng` or their 0078 `소비 금지` comment (needs a provenance discriminator that does not exist — all 32 rows are `source='algo'`); does NOT settle the `trace` shape/Korea-bounds CHECK or the km-in-`name` cleanup, both open and both catalog's. |
| 0099 | `0099_route_trace_shape.sql` | 135 | `routes.trace` is `jsonb` with NO element contract — the field that already shipped a silent outage (`claude/elevation-gain-migration-6e96a5`) | **BUILT + DEPLOYED + VERIFIED 2026-08-15** — applied to production; enforcement probed LIVE rather than inferred from `pg_constraint` (a bad write attempted in a self-rolling-back block: `array=refused transposed=refused valid_write=accepted`, catalog unchanged at 32 rows / 5,467 points). Harness 566/0 (baseline 562), 4 pins, 5 mutations verified. 20 of 28 courses rendered as nothing because ingest wrote `[lat,lng]` ARRAYS against the `{lat,lng}` OBJECT contract every consumer reads. No error, no empty state, just absent. Data is repaired (verified independently: 5,467 points across `trace` + `trace_thumb`, all objects, all numeric, all inside Korea), but **the schema still permits a third shape**, and three tolerant readers now exist downstream absorbing what ingest wrote — client's `normalizeTrace()`, ui's `routeDisplayName()`, route-geometry's shape-tolerant `route-guidance.mjs`. Synchronising copies is not the fix; the constraint is. ⚠ A shape check alone is NOT enough and that is the point: a TRANSPOSED point passes any shape test and is 4,800 km wrong (announcer produced exactly that error). So bounds too, reusing 0082:251's `lat between 33 and 39 and lng between 124 and 132` VERBATIM — one definition of "in Korea" cannot drift from itself. NEW objects only: `_route_trace_is_coordinates(jsonb)` (immutable, pure jsonb, `search_path` in the body), `routes_trace_shape`, `routes_trace_thumb_shape`; re-creates nothing, no view, no policy, no grant. Both validate WITHOUT `not valid` — every existing point was checked first. ⚠ **Also makes 0082's declassification a property of the TABLE**: points must carry EXACTLY `lat`+`lng`, so `t`/`v` are unstorable. `routes` is anon-readable (`using (true)`, 0082 §A-4), so a timed point publishes when a runner was where; today only `promote_route_from_run` strips them, and a writer that does not know cannot leak now. **trust: this narrows an anon-readable surface — flagging rather than assuming.** ⚠⚠ **Mutation M5 is the transferable one:** replacing the predicate body with `select true` leaves BOTH constraints listed in `\d routes` and `pg_constraint`, re-validates no existing row, and enforces nothing — so suite 135 asserts that bad values are REFUSED, never that a constraint is present. A constraint count would have been green against a disarmed table. ⚠ `runs.trace` deliberately untouched (it legitimately carries `t`/`v`; suites 60/68/96 own it). |
| 0100 | `0100_route_name_km_agrees.sql` | 136 | a length embedded in `routes.name` can go stale against `km` when geometry is re-cut (`claude/elevation-gain-migration-6e96a5`) | **BUILT + DEPLOYED + VERIFIED 2026-08-15** — applied to production; enforcement probed LIVE in a self-rolling-back block (`stale_length=refused valid_write=accepted`). Harness 569/0 (baseline 566), 3 pins, 2 mutations verified. ⚠ **The reported defect does not exist and the fix that was proposed for it is impossible.** Reported: "name embeds course length and it DISAGREES with km after rounding". Measured: 26 of 32 names carry a km token and **all 26 round exactly to their `km`** — zero disagreements. What looks contradictory on screen (`2.78km` beside `km=2.8`) is the NAME carrying more precision than the column, which ui already handled correctly at display. And the proposed durable fix — strip the token from all 32 names — **violates `routes_town_name_key`** (0078:36, UNIQUE on `(town,name)`): three 반포동 rows collapse to `몽마르뜨 언덕 루프`. In those names the km token is doing IDENTIFICATION work, not measurement. The real class is temporal: nothing stops a token from going stale when geometry is re-cut, which HAPPENED — upstream re-cut `반포 서래섬 리버 루프 3.71km` as `3.31km` mid-sprint and had to rename by hand. So: a CHECK that any trailing km token must round to `km`. Zero data change, no collision, and a re-cut that forgets the name now fails loudly instead of publishing a length nothing measured. |
| 0101 | `0101_compute_runner_payout.sql` | 137 | §0g runner-payout price in SQL (`claude/payments-toss-plan-slice-8079f7`) | **CLAIMED 2026-08-15** — pure extraction of `settle-run/handler.ts:135-187` into the sibling of `compute_owner_charge`. Unblocks §0h (marketplace incident-settlement exit). Contract + trust's plan review in `docs/decisions/g0-runner-payout-in-sql.md`. ⚠ Same slice deletes the TS arithmetic and converts the equivalence pin to value pins. | **VERIFIED DEPLOYED 2026-08-19 (announcer agent, read-only):** applied · body identical to source (0102 supersedes 0101 body; line-diff 0) · proconfig search_path pinned · grants service_role only · 16 invariants pinned live incl. commission 1.0/null/−0.1/1.5 all RAISE invalid_commission, unknown_end_reason, not_found · charging still OFF. Not run: suite 137 against prod; addon-sum arm value-pinned only with empty addons.
| 0102 | `0102_payout_commission_guard.sql` | (pins into 137) | invalid commission must RAISE, not silently pay ₩0 (`claude/payments-toss-plan-slice-8079f7`) | **CLAIMED 2026-08-15** — 0101's general arm computes `round(gross × commission)` with no range check, so a commission of 1.0 pays the runner **nothing, silently**. `compute_runner_personal_payout` (0086 §A) already raises on the same input, so the two arms of one function disagree. Raised by trust at diff review. | **VERIFIED DEPLOYED 2026-08-19 (announcer agent, read-only):** applied · body identical to source (0102 supersedes 0101 body; line-diff 0) · proconfig search_path pinned · grants service_role only · 16 invariants pinned live incl. commission 1.0/null/−0.1/1.5 all RAISE invalid_commission, unknown_end_reason, not_found · charging still OFF. Not run: suite 137 against prod; addon-sum arm value-pinned only with empty addons.
| 0103 | `0103_realtime_run_channel_rls.sql` | 139 | 🔴 CRIT — live runner GPS broadcasts on an UNGATED realtime channel (`claude/deploy-edge-functions-money-68e990`, worktree lucid-neumann-580f5e) | **BUILT + DEPLOYED + VERIFIED 2026-08-15** — applied to production and re-checked live rather than assumed: both policies present on `realtime.messages` scoped to `authenticated`, predicate is definer with `search_path` pinned and anon EXECUTE denied, and exercised against a real `runner_enroute` booking (owner reads ✓ · runner reads ✓ · runner publishes ✓ · stranger denied ✓ · other booking's topic denied ✓). ⚠ On that fixture `owner_id = runner_id` (Sean's account is both), so the owner-cannot-publish arm is proven by suite 139 L1, not by production data. `geo.ts:341/374` opens `supabase.channel('run-<uuid>')` with no `{config:{private:true}}`, and **`realtime.messages` has 0 policies** (measured), so broadcast never consults RLS: anyone holding a booking UUID can read live lat/lng at 3s resolution AND inject a fake position onto the owner's map. Found by the /cso audit; channel construction and the 0-policy count re-verified by me. ⚠ **ORDERING: this migration is INERT until ui ships `private:true` + `setAuth()`, and the client half WITHOUT this migration breaks live tracking entirely** (private channel, no policies, nobody subscribes). Migration first, client second. |
| 0104 | `0104_run_channel_namespace_v2.sql` | — | namespace bump so a NEW client's position can never reach an OLD public subscriber (`claude/deploy-edge-functions-money-68e990`, worktree lucid-neumann-580f5e) | **CLAIMED 2026-08-15** — 0103 authorizes only channels the client marks PRIVATE; a pre-`de95efb` binary requests a PUBLIC channel and so BYPASSES the policy rather than failing it, and there is no project setting to forbid public channels (measured — the realtime config exposes only rate/size limits). Whether a public subscriber is served a private client's broadcasts on the same topic is UNTESTED. Bumping new clients to `run2-<booking_id>` makes the question moot: old binaries keep the dead `run-` namespace that no new client reads or writes. ⚠ Old-binary runners still leak their own position on `run-` — honest forced-upgrade item, not closed by this. Compat cost measured as ~zero TODAY: 10 accounts, 3 ever signed in, **0 active in 7 days**. Suite reuses 139. |
| 0105 | `0105_booking_insert_party_guard.sql` | 140 | 🔴 HIGH — a client INSERT on `bookings` can name ANOTHER user's dog and an arbitrary victim as `runner_id` (`claude/deploy-edge-functions-money-68e990`, worktree lucid-neumann-580f5e) | **CLAIMED 2026-08-15** — `bookings owner insert` WITH CHECK is only `(owner_id = auth.uid() and status='draft')`; nothing constrains `dog_id`, `runner_id`, `address_id`, `club_session_id`. VERIFIED BY EXECUTION against production (rolled back): an owner INSERTed a draft naming a real unrelated runner and it was **ACCEPTED** — which makes `is_booking_party()` true and unlocks chat, reviews and notifications aimed at that victim. ⚠ **Fix is far smaller than the audit brief specified.** `_guard_booking_insert_cols` (BEFORE INSERT, client roles only) ALREADY exists and already refuses custody/return columns — it simply never covered the party columns. Extending it is one `create or replace`: no policy drop, no definer RPC, no reroute of `create-booking-hold` (service_role skips the guard by `current_user`), no client change. Same shape as `0087`. The UPDATE door is already shut by `_guard_booking_cols` (`booking_protected_columns`) — measured. |
| 0106 | `0106_drops_seal.sql` | 141 | 🔴 P0-3 reward drops — revoke client I/U/D on `drops`+`gear_claims`, immutable-once-opened trigger, contents CHECK; open-drop stays service (announcer-spawned builder, tree `p0-drops`) | **CLAIMED 2026-08-19** — Sean's remediation order §3 |
| 0107 | `0107_route_evidence_revoke.sql` | 142 | 🟡 route evidence columns (`verified_run_id`,`verified_runner_id`,`checked_at`,`checked_by`) column-REVOKE from anon+authenticated; promotion fails closed until a de-identified projection exists — REVOKE never DROP, `routes_active_is_earned` depends on them (announcer-spawned builder, tree `p0-routes`) | **CLAIMED 2026-08-19** — Sean's remediation order §5; catalog offline |
| 0108 | `0108_realtime_chat_bk_policies.sql` | 143 | 🔴 realtime.messages policies for `chat-<thread>`, `bk-<booking>`, `club-chat-<session>` (party-bound, same shape as 0103/0104) — prerequisite for the `private_only` flip (announcer-spawned builder, tree `p0-realtime`) | **CLAIMED 2026-08-19** — coordinate with trust (0103/0104 author) |
| 0109 | `0109_revoke_truncate.sql` | 144 | 🟡 defense-in-depth: REVOKE TRUNCATE on every public table from anon+authenticated + `alter default privileges` so future tables don't regain it (TRUNCATE ignores RLS; 65 tables held it; 0 reachable paths today — no callable fn contains TRUNCATE, PostgREST has no verb) (announcer-spawned builder, tree `p0-truncate`) | **BUILT 2026-08-19, on branch `claude/p0-truncate` — NOT deployed** — found by the 0106 builder. Measured on production first: `pg_default_acl` for public tables = `arwdDxtm` from BOTH `postgres` and `supabase_admin`; 68/68 tables owned by `postgres`; anon/authenticated held TRUNCATE on 65 (the 3 sealed = 0075's km_lots/km_ledger + 0095's club_critical_titles); PUBLIC holds none; `postgres` is NOT a member of `supabase_admin`, so that default-ACL row cannot be edited by a migration (only matters for tables supabase_admin itself creates — 0 today; the file says so in a NOTICE). Two arms + a fail-closed verify block (raises if any client role still holds TRUNCATE after the revoke). Harness 596/0 (baseline 592) with `00_shim.sql` changed to grant `all` (not DML-only) on new tables — production's actual default ACL; without it TRUNCATE is never held locally and the suite is vacuous. Mutations: revoke arm deleted → migration refuses (130 pairs) / pins T1,T2 red; default-privileges arm deleted → T3,T2 red; file absent → T1-T3 red. |
| 0110 | *(next free)* | 145 | — | available |

## Where a number comes from: THIS FILE, never a message

Not from a handoff, not from a plan, not from a broadcast — **including a broadcast from the
session whose job is announcing.** That session relayed "next free" three times on 2026-08-13
(`0085`, `0086`, `0087`) and was wrong every time; each was accurate when read and stale when
sent. Their own summary, worth keeping verbatim: *a number relayed by me is a stale cache
carrying an announcer's authority, which is worse than no number, because it stops people
checking.* A confident source suppresses the check that would have caught it.

## A pushed FILE is a claim even when the row is missing — check both
2026-08-13, the sixth collision and a new variant: `0086_runner_stop_passthrough.sql` was
pushed on a feature branch while this file still read `0086 | *(next free)*`, and a
newly-started session was told 0086 was available. Nobody was careless — the rule says "a
number is claimed when it is on origin", and the FILE was on origin; only the ROW was not.
**A pre-push hook now ENFORCES this** (`3fcfeb8`): a push that introduces a number already
present on another remote branch is refused, as is one that introduces a number without its
row here. The instruction below stays because it explains *why*, and because a fresh clone
needs the hook enabled before it protects anything — but the burden is no longer on memory.
**So the check is two-sided, and takes one command:**
```
git fetch --all -q && git branch -r --list 'origin/*' \
  | xargs -I{} git ls-tree {} --name-only supabase/migrations/ 2>/dev/null \
  | grep -oE '[0-9]{4}_' | sort -u | tail -3
```
Read the row, then look at every remote branch — not just trunk. And when you push a
migration, push its row in the same breath; a row that trails its file by even an hour is
the window this collision walked through.
## In-flight claims for work with NO migration number

Migrations have numbers, a ledger and a pre-push hook. **Client fixes, edge-function changes and
copy work have none of that** — and on 2026-08-13 two sessions independently built the same
`charge-states` fix within the same hour, for the second time that day. Nothing was lost (the
pushed version stood, and it was the better one), but it cost an hour twice.

**Claim a shared surface here before you edit it. Remove the row when it merges.** Advisory —
no hook can enforce this — but it is a five-second write and a five-second check, and it only
has to work once to pay for itself.

**Key the match on FILE PATHS, not on what you call the work.** "Charge states" and "payment
projection" are the same two files described two ways — two sessions can both write a truthful
claim that never collides. `app/src/lib/api.ts` collides with `app/src/lib/api.ts` regardless of
vocabulary. Keep the intent line for humans; let the *matching* be on paths. (Same lesson as the
class table below, one turn later: a claim only works when the identifier is the thing that
actually collides — and we first specified the human-readable name, which is exactly the
identifier that doesn't.)

**And say whether the claim is EXCLUSIVE or SHARED.** Some files — `api.ts` above all — are
touched by nearly every slice; nobody can hold one for a day, and a blanket lock would teach
everyone to skip claiming, which is worse than no table. **`shared` means "tell me before you
edit the same FUNCTION", not "stay out".** Two sessions in one file is usually fine; the same
function is the problem.

⚠ **THE HOOK ITSELF CAN BE SILENTLY OFF — trust, 2026-08-15, measured across every worktree.**
`core.hooksPath` was set **per worktree** to an ABSOLUTE path inside one particular worktree
(`daengrun-redesign-v4-77ea99/.githooks`). Five worktrees pointed there, including money,
announcer, ui and session-handoff-docs. **A worktree is disposable — this session's own was
recycled the same day** — and git does not warn when `hooksPath` names a directory that no longer
exists. It just runs no hooks. So the single mechanism this repo built *because protocols fail
under parallelism* was one `rm -rf` away from silently not running, for four active sessions,
during heavy parallel migration work.

Repaired by REMOVING the per-worktree override so every tree inherits the clone-level default,
which was already correct:

    git config --worktree --unset core.hooksPath     # drop the fragile override
    git config --local core.hooksPath /path/to/clone/.githooks   # once per clone, stable

⚠ **`CLAUDE.md` currently prescribes `git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"`,
and in a worktree `--show-toplevel` is THAT WORKTREE** — so the documented instruction is what
produces the fragile config. It wants `--local` on the clone, not per worktree. Flagged rather
than edited: `CLAUDE.md` is Sean's standing-instructions file.

**The generalisation, and it is the sharpest one this file holds:** the repo's own argument for
the hook is *mechanisms beat discipline, because nobody can violate a mechanism by being briefly
confident.* That argument silently assumes the mechanism is running. **A guard whose installation
is itself a convention inherits every weakness of a convention** — verify the guard is armed the
same way you verify anything else: by executing it, not by believing it was set up.

⚠ **A CLEAN-MERGE REPORT IS NOT THE MERGE YOU ARE ABOUT TO PERFORM — route geometry,
2026-08-14.** They were told their branch merged clean into trunk: `git merge-tree`, 0 conflicts.
Performing the merge produced **three real conflicts**, one in `app/src/lib/api.ts`, where trunk
carried a `normalizeTrace()` fix for a bug THEY had introduced and their branch did not have it.
Trusting the clean report would have silently reverted the fix for their own defect, in the exact
file it lived in. **A `merge-tree` run against a different base answers a different question.**
Re-run it against the base you will actually merge into, immediately before merging — or just
perform the merge and read the conflicts. Same family as the tree-name hazard below and as
`migration list`'s "up to date": a well-formed report about a *slightly different world*.

⚠ **A TREE NAME CAN GO STALE UNDER YOU — dated 2026-08-14, found by it happening.** The trust
session's worktree was recycled mid-session from `deploy-edge-functions-money-68e990` to
`lucid-neumann-580f5e`, same branch, same work. Both its claim rows on origin went on naming a
directory that no longer exists — and a claim pointing at a dead tree is worse than no claim,
because the next session reads it, goes looking, finds nothing, and cannot tell "finished and
not released" from "abandoned" from "renamed". **The BRANCH is the durable identifier; the tree
is a hint.** Write both, put the branch first, and when your tree changes, fix your rows in the
same breath — nobody else can, because nobody else knows the two names are the same session.

**And name the TREE the work actually lives in.** A claim that says who and what but not *where*
lets one session hold the same uncommitted change in two working trees at once — which happened
on 2026-08-13: a `0089` slice sat byte-identical and uncommitted in both its own worktree and the
shared main checkout. Whichever is committed first, the other becomes a stale copy that someone
can still commit later, and the two are indistinguishable by reading either one.

⚠ **The shared main checkout `/Users/sean/dev/daengrun` needs naming out loud when you work there,
because it is the one tree nobody owns.** Three consequences, all observed the same day:
- **Nobody watches its ahead-count.** It sat 32 commits ahead of origin with no one responsible
  for noticing. Worth a standing check: `git -C /Users/sean/dev/daengrun rev-list --count origin/redesign-v4..HEAD`.
- **It accumulates several sessions' work at once**, so `git add -A` there sweeps up other
  people's files. Stage by explicit path, or work in your own worktree.
- 🔴 **An uncommitted migration there blocks `supabase db push` for everyone**, because `db push`
  applies every pending local file — CLAUDE.md's "never push from a worktree carrying an
  unfinished migration", pointed at the tree that isn't anyone's.

If you must edit there, the pattern that works: commit **only your own paths**, then cherry-pick
onto `origin/redesign-v4` from your own worktree and push from there. The shared tree is never
rebased under anyone, and the duplicate commit drops itself on their next `pull --rebase`
(identical patch-id).

🔴 **Author name proves nothing about who made a commit.** Every session on this machine commits
as `Sean Kim <seankookim@uchicago.edu>` — it is the repo's configured git user, not evidence.
A session's commit, another agent's commit and Sean's own are indistinguishable by `%an`. **The
only reliable attribution is the commit message and the touched paths.** This matters most
exactly when it is most tempting to skip: deciding whether a commit is safe to rebase away.
Before telling anyone their commit will vanish in a rebase, verify rather than assert:

    git show <sha> | git patch-id --stable

Same id on both sides ⇒ the rebase drops it and nothing is lost. Different ⇒ it does **not**,
and someone is about to lose work. (2026-08-13: a commit was read as Sean's from its author
field and was in fact a session's — the patch-id check settled it in seconds.)

| Path(s) | Session (branch) | Tree | Mode | Started | Intent (one line) |
|---|---|---|---|---|---|
| `supabase/tests/123_run_insert_seal_suite.sql` (S9 arm only) | trust (`claude/deploy-edge-functions-money-68e990`, worktree lucid-neumann-580f5e) | **shared** | 2026-08-14 | Close a false negative in S9: it counts policies with `cmd='INSERT'`, but a `FOR ALL` policy reports `cmd='ALL'` and permits INSERT — so a convenience `FOR ALL` policy on `runs` reopens 0087's forgery hole with S9 still GREEN. Verified: `pg_policies.cmd` = `ALL`. Test-only change, no migration, pinned behaviour unchanged. ⚠ Suite is custody's lineage (0087) and custody is dormant; grants/policy invariants are trust's per roster §1. S9 arm only — tell me before touching it.
| `.githooks/pre-push` (check ④ only) | trust (`claude/deploy-edge-functions-money-68e990`, worktree lucid-neumann-580f5e) | **shared** | 2026-08-15 | Add check ④: a REGISTRY row marked DEPLOYED that this push INTRODUCES must ship with its migration file. Inverse of check ②; announcer approved. Scoped to introduced rows so the current 0098/0099 trunk gap does not refuse everyone's pushes. Additive — checks ①②③ untouched.
| `supabase/migrations/0098_route_elevation.sql` · `supabase/tests/134_route_elevation_suite.sql` | catalog (`claude/elevation-gain-migration-6e96a5`, worktree daengrun-redesign-v4-77ea99) | exclusive | 2026-08-14 | Add `routes.elevation_gain_m` + backfill the 20 GPX-measured rows. New files only; touches no existing object, no `app/`. ⚠ Does NOT touch `anchor_lat`/`anchor_lng` or their 0078 `소비 금지` comment — that contract flip is a separate, unclaimed slice. |
| *(released — trust, 2026-08-14. `0095`+suite 131 are on trunk AND applied in production; re-verified as anon after deploy: `42501 permission denied for table club_critical_titles`. `awaiting-sean.md` §1 correction landed in `33e8a0f`.)* | | | | | |
| *(released — deploy-edge-functions, 2026-08-13. Held the deploy surface `zjabnywjpvpgmtajygqy` exclusively; all five money functions are now deployed from trunk and the row is retired per "delete yours when you merge".)* | | | | | |

⚠ **The claim table cannot hold a DEPLOY, and this is the one row that proved it.** The claim
above was written against `supabase functions list` + `migration list`, both correct when read.
Twenty minutes later another session had applied `0092` and `0094` to the same project while
this session's gates were still running — a claim on origin, in the file, in the right format,
and it changed nothing, because **the surface being claimed was not in the repo.** Every other
row here names paths, and paths are the thing that collides; a project ref is not a path and no
reader of this table was editing a file. Nothing was lost (their apply is what unblocked the
`transition-booking` deploy), so this is recorded as a limit rather than an incident: **the
in-flight table coordinates edits, not effects on production.** A deploy needs an interlock the
repo does not have. Until one exists, say in the handoff who is deploying, not only here.

Conventions: give **paths**, not a ticket name · one line of intent, so a reader can
tell whether their change collides or merely neighbours · stale rows are worse than none, so
delete yours when you merge · if you find a row older than a day, ask before assuming it is
abandoned.

### Routing work between sessions (the other half of the same bug)

The duplicate above was not caused by a missing ledger alone. The routing message named one
owner and, in the same breath, offered the other party a chance to take part of it — so one
session read *settled* and the other read *open invitation*. **A question that stays open while
work proceeds is a race, not an option.** So, when routing:

1. name **one** owner,
2. say explicitly that the other party should **not** start,
3. put any *"would you rather own this?"* question **before** the routing, never alongside it.

(Protocol authored by the announcing session, recorded here because it belongs next to the
claim table it complements.)

## Claim the SLICE, not just the number
2026-08-13: two sessions built ⑩ in full, simultaneously. The registry did its job on numbers
and was silent on units — ⑩ sat in one session's handoff as unclaimed next-work, and the other
claimed it two minutes after that session's agent had fetched. Nothing was lost (the pushed
claim stood, per the 0083/0084 precedent, and both designs had converged independently on the
same shape — sibling function, shared `comp:` lock key, the half in `remaining_guarantee` with
`platform_fee` 0, which is decent evidence it was the right shape). But a day of duplicated
work is a day.
**So: when you take a memo/unit, push a row here naming the UNIT, not only the migration.**
The `Owner (branch)` column already has room for it — write `⑩ cancel-fee runner share`, not
just a file name.
⚠ **And name temp harness dirs after your SESSION, not the migration number.** Both sessions
derived `/tmp/dr<NN>` from `0085` and `rm -rf`'d each other's postmaster mid-run — which
presents as a migration file vanishing halfway through an apply, a failure mode that looks
like disk corruption and is actually a collision.
## The class behind most of this: a shared machine + an identifier that is not unique

Three instances on 2026-08-13, and naming the class is worth more than any of the fixes:

| instance | the non-unique identifier | fix |
|---|---|---|
| migration numbers ×7 | "next free", derived independently per session | claim on origin + pre-push hook |
| `/tmp/dr85` | temp harness dir derived from the **migration number** | name it after the SESSION |
| `pkill -f postgres` | `harness.sh` handed postgres a **relative** `-D`, so every session's command line was byte-identical | absolute `PGDATA` |

A fourth instance is one layer up and the same shape: **work allocation with no claim at all**
— two sessions building one unnumbered client fix, twice in a day, because only *numbered* work
had a ledger. Fixed the same way: give it a claim (see the in-flight table above).

**Every time, the correct fix made the identifier unique AT THE SOURCE** rather than asking
people to be careful with it. That is the same argument as the pre-push hook, and it predicts
where the fourth comes from: **anywhere we derive a name from shared state instead of from the
session.** Read it alongside collision seven's *"a guard on one step invites delegation of the
next"* — together they cover most of this repo's observed failure modes.

## NEVER auto-resolve a conflict in THIS file by picking a winner

**Collision seven (2026-08-13), and the hook cannot see it.** An automated merge resolver
deduped the rows by migration number, silently discarded a live `0088` claim in favour of an
`0087` row, and concatenated the survivor onto a section heading. The pre-push hook guards a
push that *introduces* a number; it has no visibility into a claim **deleted during a merge**.

**Keep BOTH rows and mark the collision.** A duplicate row is a visible problem that takes a
minute; a deduped row is an invisible one that costs a day. And note the timing: six collisions
came from sessions racing, and this one came from **automating the referee** — which became
likelier, not less likely, once the hook made pushing feel safe. A guard on one step invites
delegation of the next.

⚠ **Renaming a migration moves TWO rows**, not one: the claim row *and* its entry in the
shared-objects table below. One rename on 2026-08-13 left the second behind, so the table
briefly described one slice's grant under another slice's seal.

## Standing conflicts to resolve

- 🔴 **0089/125 is DOUBLE-CLAIMED RIGHT NOW** (spotted 2026-08-13 while claiming 0090):
  `0089_profiles_write_grants.sql` (payments) and `0089_return_force_ops_only.sql`
  (run-end-flow) hold the same row. **Both rows kept and marked, per this file's own rule —
  not deduped.** ⚠ The pre-push hook cannot help here: it refuses a push that *introduces* a
  colliding number, and **neither file is pushed on any branch yet** (verified across all
  remotes), so there is nothing for it to see. This is the gap between a claim and a file,
  which is the same gap collision six walked through in the other direction.
  **Resolution per the named-decider rule: the PAYMENTS session decides and pushes the
  corrected rows; run-end-flow accepts without countering.** I have taken 0090 to stay clear
  of it rather than to win it.

- **⑩ was BUILT TWICE on 2026-08-13, in parallel, by two sessions given the same unit** — and the
  duplicate was caught by a temp-directory collision, not by this file. The
  `claude/g1-ops-club-decisions` (payments) session was briefed to build ⑩ + ⑨a; it took 0085/121
  against a fetch made at ~14:50, wrote the migration, the suite, the edge-function half and the
  race pin — and then found `claude/club-delegation-money-gaps-b59eb8` mid-build on the same
  decision, having pushed its claim at 14:52. **Payments YIELDED ⑩ whole** (their claim was on
  origin, and origin beats a fetch that was true a minute ago) and moved its remaining unit, ⑨a,
  to 0086/122. Nothing of the duplicate ships; the yielded diff is kept out of the tree.
  Two lessons, and the second is the new one:
  ① a temp-dir name derived from the migration number (`/tmp/dr85`) is itself a collision detector —
     it is how this was found, ~40 minutes before either side would have hit it at merge;
  ② **numbering discipline does not detect DUPLICATED WORK, only duplicated numbers.** Both
     sessions obeyed every rule in this file. What collided was the assignment, which lives in
     nobody's registry — so when a decision memo is handed to a session, the memo's Status line is
     the only place a second session would look. See the note added to
     `docs/decisions/cancel-fee-runner-share.md`.
- ~~0082 double-claimed~~ **RESOLVED:** route-ladder pushed first (`a95aa34`).
- ✅ **0083/0084 SETTLED 2026-08-13 by the payments session** (named decider in the previous
  revision of this file; run-end-flow accepts without countering, as agreed). The dispute was
  two sessions each reporting the *other's* yield: they yielded 0083 to payments, payments
  yielded it back to them, and both then moved to 0084. Nobody was wrong; two polite yields
  made their own collision. **Resolution: this row's ORIGINAL assignment stands, because it was
  the only claim ever pushed** — 0083/119 run-end-flow, 0084/120 payments. Verified on disk
  2026-08-13 13:52: `0083_run_end_flow.sql` + `119_run_end_suite.sql` in the run-end-flow
  worktree, `0084_g1_ops_cutover.sql` + `120_g1_ops_cutover_suite.sql` in the payments
  worktree. **Both sessions already match this row; no file needs renaming.**
  The rule that resolved it, and the one to reach for next time: *origin beats recollection —
  including your own, and including a yield you are certain you made.*
- **Count is five, not four** (0078 ×3, 0081 ×2, 0082 ×2, 0083 ×2 including the double-yield).
- The `payments_live_since` cutover slice (D-3 statement, per-runner abort telemetry,
  reconciliation heartbeat) has no number yet — claim at build time.


## Which shared objects each slice re-creates — the SILENT collision class

Numbering collisions are loud: you find out at merge. This one ships. Several slices
`create or replace` the SAME objects, and **re-creating one that another slice just changed
silently reverts it while the harness still passes** — because each slice's pins live in
its own suite, so nothing exercises the reverted behaviour.

**Before re-creating any object below, read the newest migration that touched it and name
whose version you build on in your file header.** Fill in your own row; do not guess for
others.

### The rule, stated once

> **Add columns and your own functions. Re-create nothing you did not create.**

If you cannot get what you need by adding, then you are EXTENDING someone's object — say
whose version you built on, in your file header, by migration number. "Re-creates" alone
does not tell the next reader whether work is being continued or covered.

If extending is impossible without replacing, **do not replace silently**: name the hole in
your file, write out the exact fix the owner needs, and say what must not ship until it
lands. `0083 §0f` is the worked example — it creates a hole in `sweep_settled_without_payments`
(because `ended_at` changed meaning), refuses to fix it in 0080's territory, hands the owner
the one-line predicate, and blocks the cutover until it is in.

This rule was written after the run-end-flow session caught its OWN migration about to
silently revert the charge machine's sweep — the same class it had been warning everyone
else about. Applying it to yourself when it is inconvenient is the whole point.

| # | Shared objects it re-creates |
|---|---|
| 0079 | `_guard_run_cols` · LA trace trigger · `owner_la_sweep_stale` |
| 0080 | `compute_owner_charge` · `sweep_settled_without_payments` · `mint_settle_charge_intent` |
| 0081 | `record_enroute_cancel_comp` (0080 §K) ⚠ writes a ledger row for *cancelled* bookings — which is why ledger-presence is NOT a settlement anchor |
| 0082 | **NONE — disjoint surface.** ⚠ **Enum-independent by construction:** `promote_route_from_run` gates on `end_reason = 'completed'` and nothing else, so ADDING an `end_reason` value (⑨'s `runner_incapacity`, or any future one) cannot reach route promotion — no arm to update, no pin to move. This is the property that let two money slices and a route slice touch the same enum in one afternoon without interacting; state it before you assume otherwise.  Owner-verified + independently re-verified: creates only `_route_dist_m`, `promote_route_from_run`, `_routes_guard_activation` + its trigger (zero hits elsewhere); replaces only 0002:89's `routes public read` policy, which nothing else re-creates. Its one `settle_run_tx` mention is a comment. Nothing to build on top of or over. |
| 0083 | EXTENDS (builds on the named version, does not replace): `settle_run_tx` ←0028 · `_guard_run_cols` ←0079 · `owner_la_sweep_stale` ←0079 · `_owner_la_trace_tg` ←0079 · `append_run_event`/`append_run_photo` ←0018. NEW: `end_run_tx`, `confirm_return_tx`, `force_return_tx`, `_settle_sealed_run`, `custody_ping`, `sweep_run_end_recovery`, `_guard_booking_insert_cols`, `_owner_la_run_end_tg`. Also updates `116_charge_suite`'s `t_chg_settled` fixture. ⚠ **Deliberately does NOT touch `sweep_settled_without_payments`** — 0080 owns it; see 0083 §0f for the one-line predicate it needs and why re-creating it here would silently revert 0084. |
| 0084 | *(owner to fill)* |
| 0086 | **NONE — adds one new function** (`compute_runner_personal_payout`). It READS `compute_owner_charge` (←0084 §A) and re-creates nothing. ⚠ **It deliberately does NOT re-create `settle_run_tx`, which the brief expected it to**: 0028:18 is that function's current definition, 0083 EXTENDS it and is not on origin yet, and 0083 < 0086 — so a 0086 built from 0028's body would apply AFTER 0083 and silently revert it while the harness stayed green (0083's pins live in 0083's suite). ⑨a needed no change there anyway: the ledger write inserts the five money parameters it is handed, and `settle-run/handler.ts` composes them. See 0086 §B, which also records that 0028:30's body says `set search_path = public` (no `pg_temp`) — it passes 98 H1 only because 0055's ALTER retro-sealed it, so ANY faithful reproduction of 0028 must add `pg_temp` or turn H1 red. |
| 0085 | EXTENDS nothing — adds ONE new function (`record_late_cancel_share`). Deliberately shares 0080's `comp:` advisory-lock key so the two comp writers are mutually exclusive; re-creates no existing object. `marketplace_cancel_fee` stays 0066's, `record_enroute_cancel_comp`/`mint_cancel_fee_intent` stay 0080's. |
| 0088 | **NONE — creates no object at all.** It is `revoke select` + `grant select (…)` on `profiles`, plus two `comment on column`. It does NOT re-create the 0002 `profiles` policies (row visibility is deliberately unchanged), does NOT touch INSERT/UPDATE/DELETE grants (the write whitelist is a separate, unbuilt slice — 0088 §0b), and does NOT touch `available_runners` (0015), which it only PINS as a subset of the granted columns. ⚠ Anyone adding a column to `profiles` after this must decide whether it is public: the grant is a whitelist, and 124 G1's fourth arm reddens on any column outside it. ⚠ **Disjoint from 0087 (`runs` INSERT seal) by construction** — different table, and 0088 touches no INSERT privilege anywhere; the two seals can land in either order. |
| 0091 | **NONE — creates no object at all.** `revoke insert, update, delete` + `grant insert (…)`/`grant update (…)` on `profiles`, plus `grant select (role)` (see below) and two `comment on column` (`role`, and `handle` — 0074's text, amended to say the whitelist it asked for now exists). No policy, no trigger, no function; in particular NOT a `_guard_profile_cols` trigger (0057's shape) — a grant is right because the rule is per-column and unconditional. Does not touch the 0002 `profiles` policies. ⚠⚠ **IT AMENDS 0088'S READ GRANT AND THAT IS NOT OPTIONAL.** 0088 revoked `select (role)`; PostgREST turns the role picker's `.upsert({id,role,name})` into `ON CONFLICT("id") DO UPDATE SET "id"=EXCLUDED."id", "name"=…, "role"=…`, which requires UPDATE on `id` **and SELECT on `role`**. Measured against real PostgREST v12.2.3 + PG16: **0088 without 0091 returns 403 on every signup AND every role switch** (the check is per-statement, so even a non-conflicting insert fails). 0091 §E has the captured SQL. **These two must ship together; if they are ever split, 0091 is the half that cannot be dropped.** Consequence: `124_profiles_column_grant_suite.sql:132`'s `v_public` must gain `'role'` — mutation ⓑ in suite 127's header proves that red and a working role picker are the same one line. ⚠ Also note for anyone adding a `profiles` column: the write surface is a whitelist too now (125 W9), so a new column is client-UNWRITABLE by default, the same way 0088 made it unreadable. |
| 0087 | **DROPS one policy, re-creates NOTHING.** `"runs runner write"` ←0002:107 — dropped, not replaced (nothing else in the repo re-creates it; verified). ⚠ Deliberately does NOT touch `_guard_run_cols` (←0083), `settle_run_tx`, `end_run_tx`, `owner_la_*`, the append RPCs, or `sweep_settled_without_payments` — 0083 §0f's handoff to the payments session stands **unchanged and still owed**. NEW: `start_run_tx`, `_guard_run_insert_cols` + its trigger. Also edits `transition-booking/index.ts` (the `start_run` case moves to `start_run.ts`, cancel_owner's precedent) — no other edge function. |
| 0101 | **NONE — adds one new function** (`compute_runner_payout`). It READS `bookings` (`km`, `min_fare`, `addons`) and CALLS `compute_runner_personal_payout` (←0086 §A) for the `runner_personal` arm rather than re-deriving it, so the two cannot drift; neither is re-created. ⚠ It deliberately does NOT re-create `settle_run_tx` (0028:18 extended by 0083 — the same trap 0086 §B records) and does NOT touch `_settle_sealed_run`, which KEEPS `p_quote`: dropping that argument is sequencing step 2 in `docs/decisions/g0-runner-payout-in-sql.md`, a separate slice. No policy, no trigger, no table grant. ⚠ The one grant it does write — `execute` to `service_role` only — is the ENTIRE protection: this is a `security definer` over `bookings` with no party gate (correct: no client can reach it), so granting `execute` to `authenticated` turns it into a pricing oracle over every booking. 137 R6 is the pin that watches it; 99 S1 is anon-only and 98 H1 watches `search_path`, so nothing else would redden. ⚠ It reads LIVE `PRICING` constants (9,900 / 3,000), not the booking's frozen fare columns, because a payout is not a consented price — that is the pre-existing rule transcribed, not a new one, and the consequence (a price revision reprices an unsettled run's PAYOUT while leaving its CHARGE alone) is a product decision with its own slice. |

### Settlement anchors — learned the hard way 2026-08-13

- **Never anchor on `bookings.status`** (§0-ter #11, `0080:487`, pinned by 116 C8): an
  `incident_review` / `refund_pending` transition drops a settled booking out of the sweep's
  view — hiding exactly the crash the sweep exists to catch.
- **`ledger_items` presence is not an anchor either** (see 0081 above).
- **`runs.settled_at`** = "did money happen?" → the sweep anchor.
  **`runs.ended_at`** = "when did the service happen?" → cutover eligibility.
