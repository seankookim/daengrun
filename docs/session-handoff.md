# Session Handoff — 2026-08-01 (v4: delegation backend R0A–R6 complete → design phase closed → RN build started)

> **Companion docs to read first**: `docs/club-run-logic.md` **v3.3+§1b — THE spec for delegation; §16 = testing doctrine + R0A–R6 build record**,
> `docs/todo.md` (master work list), and the design canon in `docs/design/`:
> `delegation-master-lab.html` (**layout canon** — every screen), `delegation-premium-refresh2.html` (**style canon** — tokens/materials),
> `delegation-humane-lab.html` (photography law), `delegation-decisions-lab.html` (chat/ack decision basis).
> This file supersedes the 2026-07-29 handoff (V4 redesign / P-B era — that content is preserved in git history).
> **Language convention** [verified-now]: conversation & docs in English (Sean asked explicitly 2026-07-31: "speak in english"); app UI copy in Korean; commit messages in Korean.

---

## 1. Goal & current state

DOGS HIGH (도그스하이, repo `daengrun`) — dog-fitness marketplace where certified runners run customers' dogs.
React Native/Expo + Supabase. Sean solo-builds; tester account for real-device work is **s4kim2025@chadwickschool.org only** [from-history — allowlist SQL targets this account].

**Workstream status**:
- **Delegation backend R0A–R6** [verified-now for code; harness result from-history]: COMPLETE. Migrations 0040–0050. Harness 181/181 + upgrade_check green (run in the prior compacted session); e2e-club.mjs 12/12 on Sean's machine ("all passed"). **0048·0049·0050 are NOT yet `db push`ed to remote** — everything ≤0047 is remote-applied and therefore frozen (edits go in 0051+).
- **Delegation UI design phase** [verified-now]: CLOSED 2026-08-01. Eight HTML labs in `docs/design/`, all decisions made (see §4). Sean's verdicts: master lab — "everything about this I love it"; premium/photo/glass layers approved by continuation.
- **RN build** [verified-now]: STARTED. Build increment 1 committed (`ad89de1`): lilac tokens, club-ui kit, api.ts delegation block rebuilt (see the critical incident in §8), O1 boarding-pass ticket on club home, O2 consent-paper screen. **Not yet run on any device — parse-checked only.**
- **V4 general app redesign rollout** [from-history]: still pending Sean's on-device review/merge; unrelated to club surfaces.
- **Real PG integration** [from-history]: separate future project; current payments are mock (`payment_attempts` ledger records everything, charges nothing).
- **Two-account real-device full loop** [uncertain]: never done; mandatory before any real delegated pilot (spec §16).

## 2. Standing doctrines (Sean's invariant rules — outlive any task)

- **Honesty principle**: never fabricate data/fake activity; render only real data; no ghost clubs; server error codes surface as one honest sentence, never swallowed.
- **Testing 3 layers** (spec §16, replaces the old per-slice debug-UI gate): ① `supabase/tests/harness.sh` (181 SQL cases incl. `90_race_check.sh` two-connection races) + `upgrade_check.sh` for money/custody/assignment migrations ② `app/scripts/e2e-club.mjs` (12 cases, real GoTrue accounts vs local stack — the gate for backend slices) ③ real-app E2E + device-only native testing (Kakao/push/GPS/maps/payments). `/dev/club-lab` is FROZEN — no new controls.
- **Migration edit rule**: remote-applied migrations (≤0047 now; 0048–0050 after Sean pushes) are immutable — changes go in new numbered files.
- **Design process**: big UI decisions get an HTML lab first → Sean picks by number → then implement. Numbered variants ONLY where genuinely new decisions exist.
- **Rule 7 (word diet, adopted this session)**: one screen = one fact + one action; running text ≤2 lines; max 1 hint; rest behind a single "자세히" link; legally load-bearing sentences move to the moment they bind (e.g., assignment-method consent → payment sheet), never deleted.
- **Photography law (adopted this session)**: photos are content, never wallpaper. 5 slots only (club cover / live polaroid / receipt print / dog's book / group shot). Paper zones (payment, consent, console, roster, case, cancel) are photo-free forever. Scrim law: text never sits on raw photo. Self-sourced only, no stock. photoConsent gates faces. Credit line always.
- **Commits**: detailed Korean messages; Sean does all pushes/deploys; give Sean exact commands (bare commands, one per line — his zsh chokes on `#` comments pasted interactively).
- **Naver Cloud secret** (3yobs…): never in app/repo — root `.env` server-side only.
- **Doctrine one-liners** (enforced in code, don't re-litigate): 정산≠반환 (settlement ≠ return); custody phase speaks before the service axis; open incident on a dog ⇒ payout hold (ended rows INCLUDED); approval=eligibility, only hold/payment consumes capacity; no booking before payment; numbers live in `club_config`; requesting is not a door (shell access); open incidents extend chat write; Model A assignment; no delegation without a signed consent; RSVP≠membership, obligations survive leave; 'settled' as a word is banned in UI copy (SETTLED the flap word is fine); text+check > enum; Korean state labels are first-class.

## 3. Working-relationship norms (brief a new teammate)

- Sean often speaks via voice transcription — rambly surface, but EVERY clause carries intent; decompose carefully. He says "take it or leave it" / "you can push back" — he genuinely accepts pushback when argued (accepted "photos as content, not wallpaper" amendment).
- Aesthetics are decided visually: HTML lab → 3–5 options max → he picks by number ("my decisions are 4, 5"). One confident direction is fine when he says "be creative, go ahead".
- He notices real design flaws precisely: caught stale-style decision renders ("I would assume the chat and ack screens now look different… no?"), radius inconsistency ("the corners are sharper than the other screens"), jargon leakage ("It says rail, I'm not sure what that means" — kill shorthand that needs decoding).
- Taste trajectory this session: dark violet night world OUT for club ("too dark… the rest of the app is very white"); lilac morning IN; then "more premium", then "sharper corners feel premium" (crisp corners + soft shadows = the formula; hard black offsets stay retired); "assume the customer is dumb" → Rule 7.
- Autonomy: "go ahead" = proceed through the whole increment including commits. Direction changes are his call. He answers questions tersely; don't stack questions.

## 4. Decision log (with WHY) — design phase, all final

- **② Consent = drag-to-seal strip with soft coral fill** (#FFDCD1 track, coral ring). Why: consent = action, mis-tap structurally impossible, nothing ever covers the clauses (fixes the old "stamp covers info" flaw). Rejected ①: separate stamp cell (fine but less alive).
- **⑧ Lilac morning, premium "tailored" cut**. Why: matches the white rest-of-app while keeping club territory distinct; violet survives as line-work on a budget. Rejected ⑦ paper daylight (violet fully retired — lost club identity) and ⑨ day/night split (two palettes to maintain; run screens are now light too).
- **Crisp corner scale** (phone 14 / card 8 / inner 6 / btn 8 / tag 5 / paper doc 2 / circles exempt) **+ soft layered shadows**. Why: Sean saw the consent paper's sharp corners as the most premium element. NOTE the apparent contradiction: earlier he called the ORIGINAL sharp look "cheap" — the difference is hard-black-offset posters (cheap) vs crisp corners with soft light (tailored). Both statements stand.
- **Premium materials v1+v2**: hairline law (1px #E6E2F4 trim everywhere; hero = 4px-inset double frame "engraved"); pills → rectangular letterspaced mono tags; embossed flaps (flip = the app's ONE signature motion); dawn wash (canvas only); glass chrome (masthead/shell/dock — content never blurs); foil budget (holo = monogram + ticket edge ONLY; platinum gradient = artifacts/credential frames; gold = SETTLED only); editorial numerals (Oswald 500 large, small ₩, tabular); ring countdown (amber→coral <5min); choreography exactly 4 (flap flip, seal stamp+sweep, stub tear, ring drain) — everything else 150ms fades.
- **④ Chat = pinned host drawer** (over ③ toggle). Host inquiries sit on a platinum-framed drawer above the group stream — a host can't miss one; limited (pre-payment) users see only the drawer full-screen; expands to a sheet when long. Cost accepted: vertical space.
- **⑤ Acks = banner stack** (over ⑥ takeover). Tinted banners under glass chrome, severity-sorted, follow across screens, one-tap 확인, 30-min silence escalates to host. Why: app stays usable mid-field with a dog. ⑥'s motion-demote logic is dead code we never write.
- **Home card = the state machine**: O3/O6/O7 are the same "몽이의 위탁" card changing state (driven verbatim by `ui.primaryStage`), not separate screens — but they ARE each rendered as full screens in master-lab because the "RAIL" shorthand confused Sean. Never use unexplained jargon in labs again.
- **부하 is banned in UI** → "오늘 담당 N/N" (runner load). Why: 부하 double-reads as burden/subordinate.
- **O5 payment sheet carries the legal sentences**: assignment-method consent (host proposes → runner accepts → one owner objection) + cancel ladder — moved there by Rule 7 because that's the moment they bind.
- **Runner reveal = credential card** (VERIFIED tag, runs/incidents/rating ledger row). Rating field awaits a review backend (placeholder until built).
- **Receipt = photo print** (best run shot, gold seal half-on-photo, share/export card = growth loop). Group-shot ritual: one host prompt at session close → fans out to every participant's dog book + becomes club-cover candidate.
- **Model A explained for owners**: nobody browses runners; owner buys the *method* at payment. This wording is product doctrine now.

## 5. Architecture & contracts (what the UI consumes)

**Backend RPC surface for the delegation UI** (all in migrations 0040–0050, wrapped in `app/src/lib/api.ts`):
- `club_delegation_board(p_session)` → board v5 [verified-now, 0048 §M]: session{…, reservedCount, viability{format,attendanceOk,paidDogs,presentRunners,coverageOk,viable}, openIncidents, unassignedIncidents}, runners[], me{}, dogs[] with FULL axes: service (serviceState/completionOutcome/terminationType), charge (chargeState/holdStatus/holdExpiresAt/refundState), custody (custodyPhase/custodianType/custodianExternal/ownerReturnConfirmed/runnerReturnConfirmed), payout (payoutState/payoutHold/payoutHoldReason), assignment (assignmentState/objectionUsed/reviewNeeded + proposedRunner* visible ONLY to host/proposee — runner privacy), and `ui` = server projection.
- `club_dog_ui_state` (projection v4, 0048 §L): {primaryStage (Korean, first-class), secondaryBadges[], blockingIssues[], primaryIssue, requiredActors[], severity, allowedActions[]}. **Client renders these strings verbatim — never invents state text.** Custody beats service axis ('외부 보호 중', '반환 대기' override everything).
- `session_delegate_dog(p_session, p_dog, p_consent jsonb)` — consent REQUIRED (custodyAck, emergencyContact mandatory; vetLimitKrw defaults from `club_config.vet_limit_krw`=200000). Stored immutable in `delegation_consents` v1; re-consent = new row. NO auto-membership.
- `session_pay_delegation(p_session_dog, p_idem_key)` — idempotent mock pay; 20-min hold; last-slot race is serialized (RA).
- `session_cancel_delegation` — server-judged ladder free→10%→20% (config), blocked while incident open; pre-pay cancel = approval 'withdrawn' (re-application allowed).
- `session_confirm_return(p_session_dog, p_side)` — two-sided return (0046); both green → custody resolved → payout clock. **Settlement ≠ return.**
- Assignment (0047): `session_propose_dog` (5-min expiry, real-time), `session_proposal_respond` (server revalidates — stale accept returns honest error), `session_owner_objection` (once), `session_assignment_revoke`, backup host, `club_assignment_recovery` cron (T-10 hard stop full refund).
- Shell (0049): `club_my_shell_access` → 'host'|'full'|'limited'|'none' ("requesting is not a door"); `club_session_roster` (people incl. absent delegating owners; phone rule B — host↔all, owner↔accepted-runner pair, else '호스트 경유'; every revealed number logged to `club_phone_access_log`, deduped — and the UI TELLS the user it's logged); chat = direct RLS on `club_chat_messages` (realtime path; group vs host_channel audiences; rate limit 20/min fires on the 21st; open incidents extend write window); `club_my_acks`/`club_ack` (critical-title registry fanout, 30-min escalation).
- Incidents/GPS (0050): `club_incident_open` (S1–S3; dog subject ⇒ payout_hold under session lock INCLUDING ended rows), `club_sos` (S1 + location evidence + fanout), `club_incident_detail` (case-party gated; timeline by seq), segments born at `club_start_delegated_runs`/closed at settle, `club_save_run_trace` (monotonic t; >8 m/s rejected).
- `club_finish_session` gates: `dogs_not_returned` + `incident_unassigned` — the disabled close button must show these reasons verbatim.

**App-side contracts** [verified-now, build 1]:
- `app/src/theme.ts`: `lilac` / `lilacRadius` / `lilacShadow` exports = the style tokens. Old night tokens still exist (other club screens not yet repainted — DO NOT delete until repaint done).
- `app/src/components/club-ui.tsx`: DawnCanvas (SVG blooms), MonogramDH (SVG holo), ClubMast (translucent approximation — **real blur needs `expo-blur`, NOT installed**; adding it = native rebuild, Sean's call), LilacCard(hero/crit/frame), ClubTag (6 tones), Flap (10 states, embossed; no flip animation yet), ClubCta, BigNumRow, Ticket (perforation + notches + holo edge; `notchColor` must match surrounding bg), SealSlide (PanResponder; ≥92% travel = submit; a11y long-press alternative NOT yet implemented), LiveDot.
- `flapOf()` in api.ts is custody-first and backward-compatible with old 2-field callers (extra fields optional). DO-NOT-REFACTOR into server-side: flap judgment deliberately lives in this one client function while `ui.primaryStage` is the Korean source of truth (flap = flavor).
- `no gradients libs`: `expo-linear-gradient` NOT installed; all gradients go through `react-native-svg` (installed, v15). CTA uses solid coral + shadow, not gradient.

## 6. File map (this session)

**Design labs (all committed, `docs/design/`)**:
- `delegation-production-lab.html` (7a35d6c) — first production lab vs real contracts; decisions ①②/③④/⑤⑥ posed.
- `delegation-look-lab.html` (46a5a88) — bright 3-way ⑦⑧⑨; coral seal locked; Rule 7 receipts (47→12 words).
- `delegation-flow-lab.html` (4a85c48) — lilac premium cut; full screen map O1–O11/H1–H5/R1–R7+3 exceptions; state rail; O1/O5/O9/O10/O11/R3/R6 first renders; ③④⑤⑥ re-posed in lilac.
- `delegation-master-lab.html` (7655ba3) — **layout canon**; O3/O6/O7/O8 full screens; 부하→오늘 담당; everything repainted.
- `delegation-premium-refresh.html` (1aafc42) — tailored cut (crisp corners, hairlines, tags, artifacts, monogram).
- `delegation-premium-refresh2.html` (00f60c1) — **style canon**; dawn/glass/foil/numerals/ring/choreography tokens.
- `delegation-humane-lab.html` (063a7f1) — photography law + 5 photo slots.
- `delegation-decisions-lab.html` (6f71c79) — ③④/⑤⑥ in final canon; basis for Sean's "4, 5".

**App build 1 (ad89de1)**:
- `app/src/theme.ts` — + lilac tokens block (appended; nothing removed).
- `app/src/components/club-ui.tsx` — NEW, the kit (see §5).
- `app/src/lib/api.ts` — delegation block REWRITTEN (lines ~1785+): FlapState 10, flapOf v2, board v5 types, DelegationConsent, delegateDog 3-arg, payDelegation, cancelDelegation, confirmReturn, custodyOverride, transferInitiate/Accept/Cancel, fetchCustodyEvents, fetchSessionIncidents, incidentAssign/Resolve, debugReleasePayouts, proposeDog, respondProposal, ownerObjection.
- `app/app/club/delegate/[sid].tsx` — NEW O2 consent screen.
- `app/app/club/[id].tsx` — O1: next-session card → Ticket with two doors (위탁하기 coral / 함께 뛰기 quiet). Route pushed: `/club/delegate/${ns.id}` with params clubName, when.

**Untouched but relevant**: `app/app/club/session/[sid].tsx` (still old night-world RSVP screen — build 2 replaces it), `app/app/club/pass/[sid].tsx` (night pass — repaint later), `app/app/dev/club-lab.tsx` (frozen; compiles again now that api.ts is restored).

## 7. Pending on Sean's side (exact commands)

In `/Users/sean/dev/daengrun`:
```
find .git -name "*.lock" -delete
rm -rf .git/_stale_locks
find .git/objects -name "tmp_obj_*" -delete
supabase db push
git push
```
(db push applies 0048·0049·0050 — **O2's submit will fail with consent errors until this runs**.)
Then smoke test build 1 on device: club home → ticket → 위탁하기 → consent form → seal drag → expect "신청이 전송됐어요". Also run `cd app && npx tsc --noEmit` — build 1 was only parse-checked in the sandbox (no node_modules there).
Later/known: local stack restart + `node scripts/e2e-club.mjs` re-run (12 cases) after pulling; finalize `club_config` numbers ([Sean 미확정]: vet_limit 200000, cancel_free_hours 24, late 10%, post-accept 20%, split 50/50, host_fee 0, owner_handled_dog_limit 2, min_paid_dogs 1) via one SQL update each; V4 branch on-device review; allowlist insert for the tester account before real-app remote testing.

## 8. Known bugs / gotchas / failure modes

- **CRITICAL INCIDENT (diagnosed this session)**: the compacted session's R2 edits to `api.ts` NEVER LANDED on Sean's machine — `dev/club-lab.tsx` (same mtime batch) imported functions that didn't exist and called 3-arg delegateDog against a 2-arg api. The app could not have compiled since then. Root cause: bridge-disconnect file delivery where only part of a batch got committed. **Lesson (now in workflow-rules.md): after bridge file delivery, verify EVERY file of the batch actually landed (grep for the new symbols), not just the ones you remember.** Fixed in ad89de1.
- **Bridge git lock ritual**: every `git commit` via device_bash leaves `.git/HEAD.lock`/`index.lock`/`tmp_obj_*` that the bridge cannot delete (`rm` = Operation not permitted). Workaround that works: `mkdir -p .git/_stale_locks && mv` the locks before each commit. Sean periodically deletes for real (§7). Without the mv, commits fail with "cannot lock ref 'HEAD'".
- **device_list_dir on app/** overflows (node_modules) — always list subdirs or parse the truncated dump.
- **expo-blur / expo-linear-gradient not installed** — glass is a translucent approximation; gradients via react-native-svg only. Installing either = native rebuild decision for Sean.
- **SealSlide a11y**: drag-only today; long-press alternative promised in the lab but not implemented — build 2 or 3.
- **club home visual seam** [uncertain]: O1 lilac ticket sits on the old cream/forest club home — acceptable interim, resolved when the club surfaces repaint (build 2+).
- Local-stack env traps (from-history, still true): new CLI issues sb_publishable_/sb_secret_ keys (legacy JWT rejected); API roles get NO default grants locally → seed.sql parity grants; `supabase/config.toml` with project_id required; supabase-js silently drops undefined args; stack restart realigns secrets.
- Harness runs in container as root: `runuser -u postgres -- bash harness.sh`; container repo mirror at `/tmp/daengrun` (STALE for app/ — restage from device before editing app files).

## 9. Ideas discussed, not yet built

- **Photo system backend**: club cover ALREADY exists (`clubs.photo_url` + `uploadClubPhoto`) [verified-now in api.ts] — the humane lab's "new field" claim was wrong. Still genuinely new: group-shot fanout (host prompt at finish → all participants' dog books + cover candidate), receipt best-shot selection, polaroid promotion of runner chat photos onto owner live screen (chat photo kind exists; the promotion query doesn't).
- **Review backend** for runner credential card ratings (4.9 in labs = placeholder) — later slice.
- **"가장 자주 달린 사람"** (most-frequent runner) stat in dog's book — simple aggregate over settled delegated runs; not built.
- **Receipt export/share as image** — react-native-view-shot is installed; wire later.
- **Flap flip animation + seal stamp choreography + ring countdown component** — specced (4 signature motions, reduce-motion honored), none implemented yet; ring needed for O4 (pay hold) and R2 (proposal 5-min).
- **Ack banner escalation copy** and motion-demote were CUT (⑤ chosen) — do not resurrect ⑥.

## 10. Next 1–3 steps (build 2)

1. **[needs-user first]** Sean: §7 commands (locks → db push → git push), then device smoke of O1→O2 and `tsc --noEmit`. Fix whatever the typecheck surfaces before new code.
2. **[local-edit]** Build 2a — session shell rebuild: replace `app/app/club/session/[sid].tsx` with lilac shell (ClubMast + 개요/참가자/채팅 tabs; access via `club_my_shell_access`), 개요 tab hosting the O3/O4 state card driven by board v5 `dogs[].ui` (isMine rows; Flap from `flapOf`; badges verbatim; HOLDING deadline from holdExpiresAt).
3. **[local-edit]** Build 2b — O5 payment sheet: bottom sheet with amount, the two legal lines (assignment-method consent check + cancel ladder), `payDelegation(sdId, 'pay-'+sdId)` idempotent, honest error mapping (no_capacity/hold_expired). Then commit; builds 3–5 = O6–O8+host console, runner+live+receipt, chat drawer+acks+case+album.

## 11. Verification commands

Read-only / safe:
```
cd /Users/sean/dev/daengrun && git log --oneline -12
cd /Users/sean/dev/daengrun/app && npx tsc --noEmit
supabase migration list
node scripts/e2e-club.mjs        (needs local stack up)
```
Container (backend harness, safe — local throwaway PG):
```
cd /tmp/daengrun/supabase/tests && runuser -u postgres -- bash harness.sh
```
Expensive / destructive (Sean only, deliberate):
```
supabase db push                  (applies 0048–0050 to remote)
supabase stop --no-backup && supabase start   (local stack reset)
git push
```
