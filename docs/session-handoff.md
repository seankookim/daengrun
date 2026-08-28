# Session handoff — 2026-08-27, announcer session

**Read this before doing anything.** `CLAUDE.md` holds the permanent laws; this file holds
current state, what is open, and who owns what. Everything below was measured at write time,
not carried forward from an earlier note.

---

## State, measured

| | |
|---|---|
| Production | **0152 — `migration list` pending: NONE.** Fully caught up for the first time. |
| SQL harness | **1081 pass / 0 fail** |
| App tests | **707 PASS / 0 FAIL** (counted across the whole chain, never `tail`) |
| Money | **OFF.** `payments_live_since` null · `card_registration_live_since` null · 0 billing keys · 0 revocation rows |
| Security sweep | 0 anon-executable definers · 0 definers missing in-body `search_path` |
| Stranded work | **NONE.** 0 unpushed commits; 9 spent agent branches, **9 of 9 confirmed duplicated on trunk by `patch-id`**. ⚠ The first version of this row said 「8 by patch-id, the 9th's file on trunk is a superset」 and **reported 9 clean having measured 8** — a superset proves the file MOVED ON, which happens for reasons unrelated to that branch. Corrected by b6; the 9th was then settled properly (`patch-id` match at `91c581e`). **Same conclusion, and the evidence for it did not exist when it was written.** |

## What went live today (0130 → 0152, three sessions)

A 동반 (self-run) walk becomes a real record · the host's one-tap 러닝 종료 ends every runner's
walk on **server-derived** distances · 1 dog per person enforced by a table trigger, not a hidden
button · the club board's names open profiles, and non-runners have profiles at all · 집 반환
directions · KST everywhere (a ticket no longer prints the wrong weekday on an off-Seoul phone) ·
~950 text-size fixes to the 15pt floor · Instagram-shaped profiles + editor · guests-come-free
said out loud on the club board · unknown distances stopped rendering as `0km` · billing-key
hardening incl. the crash window where a destroyed key could be stored as a live card.

## 🔴 OPEN — needs Sean, in priority order

1. **The lawyer email.** `docs/legal/counsel-email.md` — copy-paste ready, two attachments, a
   three-line pre-send checklist, referral line deliberately blank. **This gates phone
   collection, publishing the privacy policy and terms, the KCC filing, and launch.** Oldest
   open item; nothing else on this list is close.
2. **Device build — and ⚠ RETRACTION of what this line said an hour ago (ui6, 2026-08-27).**
   I wrote here that 「THERE IS NO BUILD, NOTHING HAS EVER REACHED A PHONE」. **That was wrong,
   Sean caught it in one sentence — 「look at the ios sim」 — and the original line it replaced
   was closer to right than my correction.**
   **What I measured:** `eas build:list` empty (**true** — no CLOUD build exists) and no installed
   app for `com.seankookim.dogshigh` (**true, and irrelevant**). **What I reported:** that no build
   exists at all. 🔴 **The installed simulator app is `com.seankookim.daengrun` — the OLD bundle
   id.** The config was renamed to `dogshigh`; the installed shell predates that. I searched for
   the current identifier, got nothing, and promoted it to a claim about the world.
   **The measured truth:**
   · A **simulator build exists**, made **2026-08-13**, bundle id `com.seankookim.daengrun`.
   · It is a **DEBUG** build → it carries **no embedded bundle** and loads JS from **Metro**.
   · Metro is live on `:8081` from a worktree — so **the simulator runs TODAY's client**, and
     today's UI work is visible on it right now (verified by screenshot: `시간만 고르기 ›` renders
     ink — this afternoon's dim-text fix — while `예정된 러닝이 없어요` stays grey, the one
     deliberately left alone).
   🔴 **THE REAL GAP, which is narrower and more useful than what I claimed:** a Debug shell
   carries only NATIVE code. **Any native change since 2026-08-13 is NOT in what anyone is
   looking at** — JS flows through Metro, native does not. And there is still **no artifact
   installable on a PHYSICAL device** and no EAS cloud build.
   ⚠ **Whoever reads the simulator must also read WHICH Metro** — `lsof -nP -iTCP:8081` then the
   pid's `cwd`. A Debug build binds to whatever Metro answers, so it can silently serve a peer
   session's tree, and the screen then shows someone else's work.
   **What was done toward it (ui6, 2026-08-27):**
   · `EXPO_PUBLIC_SUPABASE_URL` + `_ANON_KEY` pushed to the EAS `preview` environment — there
     were **zero** env vars configured, so no build could ever have reached Supabase. Uploaded
     with `eas env:push --path .env`, which reads the file itself (no value handled by hand).
   · a **`simulator`** profile added to `eas.json` — it needs **no Apple signing**, which is the
     only iOS artifact obtainable without an interactive Apple credential setup.
   · `.easignore` added: the archive was **289 MB against a 4.6 MB app** (`docs/` 171 MB +
     `supabase/` 87 MB, neither compiled into a client). ⚠ It is a **superset of `.gitignore`**,
     verified rule-by-rule, because EAS uses it *instead of* `.gitignore` — dropping one line
     would ship `.env` to the build servers.
   · the app **bundles clean**: `expo export` produces a 7.3 MB Hermes bundle, exit 0.
   🔴 **STILL BLOCKED, three attempts, all identical:** every iOS build fails at the
   **`Configure expo-updates` build phase** with `UNKNOWN_ERROR`. ⚠ Ruled out: missing env
   (attempt 2 had it), archive size (attempt 3 was small), and local config — `expo config
   --type introspect` resolves fine, exit 0. **Prime suspect: the `ExpoWidgetsTarget` app
   extension**, which introspection shows carries `widgets: []` — an app extension with no
   widgets, configured alongside expo-updates. **The phase log is on the build page and the CLI
   cannot print it** (`api.expo.dev/.../logs` → 404 unauthenticated); someone with dashboard
   access should read it first — do not spend a fourth build guessing.
   ⚠ **And signed iOS builds are Sean-only regardless:** both `preview` and `testflight` fail at
   credential setup demanding interactive mode (Apple Developer sign-in). Android is not an
   escape — `android.package` is unset, so this app is iOS-only in practice.
   **When a build finally exists, `docs/design/device-smoke-ui6-2026-08-27.md`** is 33 honestly-⬜
   rows; its first section needs the phone's timezone **off Korea** before any row means anything.
   **The old text follows, still true of the code itself:** none of it is
   simulator- or device-verified. ~950 type-size changes and five screens of colour/copy work
   look fine in a diff and wrap badly on hardware. `docs/design/device-smoke-ui6-2026-08-27.md`
   is 33 honestly-⬜ rows; its first section needs the phone's timezone **off Korea** before any
   row means anything.
3. **Guest GPS → now a three-way question: `docs/decisions/guest-gps-options.md`** (landed
   2026-08-27). Every citation above verified at source, but **the framing here was wrong three
   ways and the third one is the decision.** (a) It is a **pack gap, not a guest gap** — there is
   no map of the group anywhere in the product; a 동반 owner *with* a dog is equally invisible
   (`club/companion/[sid].tsx:7,141` imports `startTracking` and publishes nothing), and the host
   sees nobody. So 「the same gps share service」 **has no referent yet**. (b) 「half a ruling
   unbuilt」 overstates it: `2026-08-25-console-rulings.md:1302-1306`, same document and same day
   as the ruling, records that **direction-of-sharing and who-may-see-whom were explicitly left
   open**. Nothing is owed; the question was never asked. (c) The constraint that decides it was
   omitted — `privacy-policy.md:91` promises 「해당 예약의 보호자에게만 … 다른 이용자나 제3자에게
   제공하지 않습니다」, and **every watch-the-pack option rewrites that sentence on a document
   currently in front of counsel** (item 1).
   ⚠ **New and not previously written down: session membership is self-serve.** `session_rsvp`
   has no club-membership and no host-approval gate (`0134:53-61`), `club_sessions` is
   `select using (true)` (`0030:133`). So 「a member of this session」 means 「anyone who found an
   open session and tapped join」 — which in code looks exactly like a membership check.
   Option ①（record, no map）needs one predicate and changes no privacy promise; ②/③ need counsel
   first. **All READ, no production query.**
4. **Card revocation → `docs/decisions/card-revocation-abandoned.md`** (landed 2026-08-27,
   **measured against production, not read**). Handoff confirmed on deployed `prosrc`: the
   8-attempt cap is real in both `claim_` and `report_`, and `enqueue_billing_key_revocation(…,
   'account_deleted')` precedes the local row delete at `0115:535`. OBSERVED live: **0 keys,
   0 revocation rows, 0 abandoned**, both money flags NULL, `revoke-billing-keys` ACTIVE v2 with
   its cron live and **11 ticks all `idle`** — so the `X-Cron-Key` handshake **has never actually
   run in production**, and the first real revocation is also its first live test.
   🔴 **The handoff's most valuable error: 「nothing reads it」 is *nearly* true, and the near-miss
   is worse than the claim.** There IS a reader — the view `billing_key_dispatch_health`, whose
   `due_now` (`0150:413-415`) counts `pending` + expired-lease `processing` and **structurally
   excludes `abandoned`** (verified: the deployed viewdef does not contain the string). So the one
   dashboard-shaped object in this family **reports the queue clean precisely because rows were
   given up on.** Also: 「someone who asked to be gone」 covers **2 of the 5 reasons**; `failed` is
   dead vocabulary written by nothing; and **there is no card-removal affordance in the client at
   all** — 「remove my card」 *is* 「delete my account」.
5. 🔴 **NEW (announcer, 2026-08-27, verified against production myself) — the host sees every
   member's phone number, and it arms the same instant phone collection does, with nothing in
   between.** Deployed `_club_phone_visible` (read from `pg_proc`, not from a migration file) is
   bidirectional host ↔ **everyone** for any session in `open`/`full`. A person-only guest is on
   that roster. **Not breached today and not close:** OBSERVED `profiles where phone is not null`
   = **0**, and `set_my_phone` has **0 client callers** (0133 landed the server deliberately
   without a collection point). ⚠ **But `ops_flags` has no phone column** — card registration has
   a switch and phone collection does not. So there is no way to turn phone collection on
   *without* turning host-sees-everyone on in the same commit. That makes it a decision that has
   to be made **before** the wiring, not after — and it lands in the same envelope as item 1,
   which is what unblocks phone collection in the first place. Related and still open from
   2026-08-26: whether a dogless guest counts as a 「member」 for this rule at all.
6. **`net` schema grant — needs Supabase, not us.** `anon` holds `USAGE` on `net` and `SELECT` on
   `net._http_response` and `net.http_request_queue` (whose headers carry `X-Cron-Key` and an
   `Authorization` bearer). **Structurally out of reach:** `net` is owned by `supabase_admin`,
   migrations run as `postgres` (not superuser, not a member), and REVOKE only removes grants
   issued by the current role — 0151 aborted itself proving this rather than claiming success.
   **Not reachable from outside:** PostgREST exposes only `public, graphql_public`; the anon key
   gets `406 PGRST106` on `net` and `200` on `public.clubs` (control run). **Defence in depth, no
   known reach.** A support request, not a blocker.

## ui6 lane — state at handoff (2026-08-27)

**Deployed and verified against production, not inferred:** 0131→0152, all 22. `migration list`
pending **NONE**. Anon-executable definers **0**, definers missing in-body `search_path` **0**,
`payments_live_since` and `card_registration_live_since` both **null** — no money moves. Edge:
`register-billing-key` v2, `revoke-billing-keys` v1 (first ever deploy, `verify_jwt=false` from
the committed `config.toml`).

🔴 **The money defect is closed ON THE LIVE ROW, not a fixture.** Production booking
`4f053152-…` — `actual_km` NULL, `incident_review` — now answers `basis=incident_unmeasured`,
`measured_km` NULL, `runner_gross` NULL. **An hour earlier that same row quoted 「실측 0km」 and
multiplied the runner's distance and addon fare by that zero.** Found by the announcer on the
screen; escalated here after measuring `0121:296`, where the ratio is *spent*.

**Dim-text wave 3 LANDED** (`69a926a`) — 48 sites read, **10 inked**, 707/0. Ratio ~21%, which
matches owner/home's 2-of-8 and is the third independent confirmation that this is a judgment
pass and not a sweep. ⚠ **`club/receipt` came back 0 of 10 and that is the finding**: its dim
styles are `club-ui`'s shared `bignumLabel`/`LoadGate` recipes byte-for-byte, and `theme.ts:80-86`
already records `L.dim` at **4.24:1 — under the body floor — as an open item reserved for Sean**.
Inking them per-site would be the first half of a product-wide repaint, made by an implementer.
**Left at the wall, deliberately.**

**사고 신고 (incident) client flow LANDED** (`de902e6`) — the biggest missing surface, closed.
New `app/app/incident/[bid].tsx`, `safety.tsx`'s 「준비 중」 card replaced by a real resolver, and
push routing for both roles. 707/0, route count 61→62, rpc calls 116→118 (**both deltas are
positive controls — the checkers demonstrably saw the new code rather than passing by not
looking**).

⚠ **It found that `0114` SUPERSEDES `0094` for the opener, and reading only 0094 would have
shipped a wrong client.** The reportable set (0114 §3 ⑥) is the accepted set **plus
`cancelled_owner` and `refund_pending`**, while `is_booking_party_active` — which gates chat AND
**`notifications` insert** — is the accepted set only. **So in exactly two states a party may
REPORT and may not be NOTIFIED.** Collapsing them ships a control that 42501s in the state 0114
widened the report set to protect.

⚠ **`incident_contact` was deliberately NOT built.** Its privacy prerequisite is met
(`privacy-policy.md:45-46`), but it returns `profiles.phone`, and `0133_phone_collection`
**landed the server and left the collection point unwired** on its own ship gate — measured **0
of 10** rows populated. It would return two blank rows. It stays unbuilt until the lawyer item
(OPEN #1) clears, which is the same gate.
⚠ **The runner sees 「보호자」, not a name** — no `profiles` SELECT policy admits 「the owner of my
booking」 (0002:55-58; 0145's arm is club-board-only). The only route to that name is the definer
that also hands over a phone number.

### What a next session should not re-learn

- ⚠ **`club_join` / `club_leave` are built and unreachable** — membership only happens as a side
  effect of committing to a session. Seven more granted-to-`authenticated` RPCs have no caller:
  `open_incident_tx` · `verify_incident_tx` · `incident_contact` · `session_set_backup` ·
  `club_assume_host` · `session_reconsider_dog` · `km_claim_welcome` · `runner_work_gate` ·
  `set_my_phone`. **That list is the honest map of missing UI**, derived from grants, not memory.
- ⚠ **Dim-text: the counts in circulation were wrong twice and both were mine.** 412 counted a
  colour token appearing anywhere — `placeholderTextColor` (which MUST be dim), dots, borders.
  Honest upper bound ~203 *text* styles. **Measured violation ratio on owner/home: 2 of 8.** The
  real count cannot be produced by grep, because the question is 「may the customer skip this?」.
  **An agent handed the 412 would have turned 29 placeholders ink and made every form look
  pre-filled.**
- ⚠ **`0151` was EDITED IN PLACE after landing on trunk**, against the correct-forward law. The
  exception was narrow and is stated in its header: its abort made every later migration
  unreachable, and `migration list` proved no environment held the old version. **If you meet a
  landed migration that cannot apply, that is the test to run — not the law to ignore.**

## Lanes

- **announcer** (this session) — coordination, Sean's queue, server/security. Nothing in flight.
- **b6** — club session/console/run screens, client honesty. Holds `club/session/[sid].tsx`,
  `club/console/[sid].tsx`, `club/run/[sid].tsx`, `club/receipt/[bid].tsx`,
  `src/components/run-share-card.tsx`, `app/shot/[bid].tsx`, and — added after this file's first
  version — `src/lib/rpc-skew.ts` + `test/rpc-skew.test.cjs`, `src/lib/tier.ts` +
  `test/tier.test.cjs`. ⚠ **Those four are small pure modules with MUTATION-VERIFIED pins:
  anyone editing them must re-run the batteries, not just the suite.** A green suite after a
  predicate edit means very little on its own — that is what the batteries are for.
  **Open for b6: only the guest counterpart on the session screen.** ⚠ **CORRECTED AGAIN — this
  file said 「waiting on the verified findings already sent」 and they had NOT been sent.** The
  announcer promised them twice, told Sean they were sent, and recorded that in this file.
  They were delivered 2026-08-27 after b6 pointed it out. **「Waiting on findings sent」 and
  「waiting on findings not sent」 are different states for whoever picks this up**, which is the
  whole reason it is worth a correction rather than a quiet fix.
  🔴 **And the fifth question — 「does a guest change what the HOST sees」 — was never answered
  by the agent**, which answered a different fifth of its own. Measured against the DEPLOYED
  0131 policy instead: **YES, the guest is visible to the host.** `session_people`'s policy is
  `(auth.uid() IS NOT NULL) AND ((profile_id = auth.uid()) OR _club_session_member(session_id,
  auth.uid()))`, and the deployed helper carries host and backup-host arms — so a host is a
  member and a member reads every `session_people` row in the session, dogless or not. ⚠ This
  only became answerable AFTER the deploy; pre-0131 the table was `auth.uid() IS NOT NULL` and
  the question was meaningless. Everything else b6 built is on trunk.
  ⚠ **CORRECTED — this file's first version said b6's two `PENDING_DEPLOY` entries 「can come
  out」 and the run-screen obligations were 「still open」. Both were already DONE** (`2b5d1c1`,
  `0714ac8`); b6 landed them while this was being written. Measured on origin: PENDING_DEPLOY
  executable mentions **0**, `runEnded` executable gates **3**, rpc-skew pin **10/0**.
  🔴 **The reason this was worth correcting rather than shrugging at:** a handoff saying a pin
  「should be failing until you do it」 sends the next session to run it, watch it PASS, and
  reasonably conclude **the pin is broken**. That is a false green manufactured by
  DOCUMENTATION — the same shape we spent two days removing from code, arriving through a file
  nobody thinks to distrust.
- **ui6** — design system, board, payments, deploy trigger. Holds `owner/request.tsx` and the
  press-grammar sweep.
- **Claim before you edit**, in REGISTRY's in-flight table, path-keyed. **Migration numbers are
  THREE-sided**: REGISTRY row · every remote branch · **local worktree branches** (`git branch -a`
  — `ls-remote` cannot see an unpushed agent worktree, and that is now the likeliest collision
  surface). Re-read at COMMIT time, not only at claim time.

## Two things that will bite the next session

- **Committing a hook does not install it.** `core.hooksPath` is the MAIN CLONE's
  `/Users/sean/dev/daengrun/.githooks`; a worktree's copy is a different file. After committing
  the pre-push fix, the repo had it and the machine did not. **Verify the live file.**
- **This shell wraps `grep` in a function that execs `ugrep`.** A hook runs under `sh` and gets
  `/usr/bin/grep`. Two sessions each spent an hour "verifying a hook's own pattern" through the
  wrapped grep — four checks that varied the input and held the tool fixed, which was the axis
  that mattered. **Use `/usr/bin/grep` explicitly when testing anything a hook runs.**
- ⚠ **The pre-push hook falsely refused two pushes** ("migration NNNN has no REGISTRY.md row")
  on pushes whose row WAS present. **Neither session found the cause and the state is gone.** It
  now prints its evidence on refusal — sha, byte length, rows it can see, the rows nearest the
  one it wants — so the next occurrence is self-describing. Two-sided tested with the evidence
  path exercised on a real refusal, and the ORIGINAL hook returns identical verdicts on both
  arms, so behaviour did not move.

## ui6 session 2026-08-28 — what landed, and two corrections to the brief

**① The card/billing chain now has a codex verdict: REJECT, 7 findings** (5 HIGH, 2 MEDIUM) —
`docs/reviews/2026-08-28-codex-billing-chain.md`, with the prompt archived beside it. First review
that chain has ever had. Nothing fires today (both money flags NULL, 0 keys), but **two HIGH
findings arm on `card_registration_live_since` ALONE** — charging does not have to be on — and both
put a real card in a wrong state.
🔴 **The one thing to act on: findings 3 and 4 both bottom out in a single unanswered PROVIDER
question — can Toss replay or look up a billing-key issuance by a persisted idempotency key, and
what does a repeated DELETE return?** The fix shape for both is unknown until that is answered, so
**it is now on the critical path to turning card registration on**, and it is a question for Toss's
documentation or support, not something to design around by guessing. Nobody owns it yet.
Closed 3 of codex's 5 open questions against production (all reads): the revocation cron **exists
and runs** (jobid 23, 110/110 succeeded, latest 00:48Z — which narrows finding 5 from breached to
latent); base-table ACLs are sealed but **asymmetrically**, a finding codex could not see from
source — `billing_key_revocations` revoked its client grants AND has RLS, `billing_keys` has **only**
RLS while carrying `anon`/`authenticated` SELECT **and INSERT**; and `net.http_request_queue` was
already settled on 2026-08-27.

**② `club_join` / `club_leave` BUILT and landed** (`297139a`). The sharpest of the eight, and the
gap was total: measured on production, exactly three deployed functions insert into `club_members`
— `club_claim_host`, `club_join` (unreachable), `session_runner_commit` — and **`session_rsvp` does
not**, because 0048's R4 abolished auto-join and left the invitation to 「UI/알림 몫」. So an owner
had **no path to membership by any route that existed**. Live data: 1 club, 14 sessions, 1 distinct
participant, `club_members` = 1 row (role=host). `club_overview` has been returning `isMember` the
whole time and the client read it in **exactly one place — the type declaration.**
🔴 **Server defect found while scouting, still open and unowned:** `club_overview.isHost` reads
`clubs.host_profile_id`; `club_demand_board.isHost` reads `club_members.role='host'`. Two deployed
definitions of one word, agreeing only because `club_claim_host` writes both. `club_leave` deletes
just the member row, so a host who leaves splits them. **The client ships with no leave affordance
for a host, so it cannot reach that state** — but the fix (refuse a host, or clear
`clubs.host_profile_id`) is a product call.

### ⚠ Two of the eight are NOT what the list says, and both were measured

The 「eight capabilities the server has and no screen offers」 list is derived from grants, which is
the right method, but a grant with no caller does not by itself mean a missing capability.

- 🔴 **`km_claim_welcome` is NOT a client-only slice — do not build the button.** The RPC is
  server-complete, but **the entire km subsystem has zero client callers**: `km_balance`,
  `km_purchase`, `km_reserve`, `km_settle` — all of them, 0. There is no km wallet anywhere in the
  app. km is wired into `_resolve_checkin` server-side, so granting the welcome 5km would hand
  someone an **invisible asset worth ~₩16,700 in runner pay** that they cannot see, spend, or
  understand. That is a worse defect than the gap. Building it honestly means building the wallet
  surface first, and deciding whether the km prepaid model is the intended one at all — money-shaped,
  with a 500-account cohort cap and ~₩8.4M exposure written into the function. **Sean's call, not an
  implementer's.**
- ⚠ **`runner_work_gate` is already delivered — the capability is not missing.** It has no client
  caller because it does not need one: `transition-booking/index.ts:77` calls it and returns
  **`waiting_on`-differentiated Korean copy** on a 409, so a gated runner is already told exactly
  why and what unblocks it. A direct client call would be pre-emptive polish (tell them before they
  tap, not after), which is real but is not a missing capability. ⚠ I nearly reported this one as
  「the gate is unenforced」 off a SQL-only search that found no caller — the enforcement is in
  TypeScript. **The measurement licensed 「no deployed SQL function references it」, not 「it is
  unenforced」**; caught before it was written down.

**`club_assume_host` and `session_set_backup` were deliberately NOT taken** — they belong on
`club/session/[sid].tsx` and `club/console/[sid].tsx`, which b6 holds exclusively. Flagged, not
built.

⚠ **Nothing in this session is simulator- or device-verified, and that was a choice.** Metro on
`:8081` serves `daengrun-redesign-v4-77ea99/app` — **a peer session's worktree** — so the simulator
cannot show this work, and repointing the shared simulator would have taken it away from that
session. The club membership card is unverified on a device. App tests are **707/0 UNCHANGED**,
which is honest rather than reassuring: `app/test/*.cjs` structurally cannot import a `.tsx` route
module, so the suite says nothing about this screen either way. Gates that DID move:
`check-rpc-contracts` 118 → **120**, exactly the two new calls — a positive control that the
checker saw the code rather than passing by not looking.

## Unreviewed

~14 of the 21 deployed migrations carry **no codex verdict**, and 0131's seven review rounds
cover **0131 alone, not the stack**. Sean was told this before authorising and chose to proceed.
Worth a sweep when there is quota to spend.
