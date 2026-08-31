# Session handoff — 2026-08-27, announcer session

**Read this before doing anything.** `CLAUDE.md` holds the permanent laws; this file holds
current state, what is open, and who owns what. Everything below was measured at write time,
not carried forward from an earlier note.

> 🔴 **DEPLOY FREEZE (2026-08-31, announcer): NO session runs `supabase db push` until the
> backend master session announces its 0159+0160+0161 landing and performs the deploy itself.**
> Reason: 0159 (pack channel, codex REJECT/11, `docs/decisions/2026-08-28-codex-verdicts.md`) is
> the ONLY pending migration on trunk — `db push` applies every pending file, so any push by any
> session deploys the rejected slice alone, with its defect list world-readable in the now-public
> repo. The freeze lifts only via the backend session's announcement to the announcer.

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

## ✅ CLOSED 2026-08-28 — the live board disclosure (was: needs one line). `0153` DEPLOYED

`0147` grants `authenticated` direct EXECUTE on the INNER board function, and that function
**trusts a caller-supplied access grade instead of deriving it**. Found cold by codex; then
**reproduced against production**, which is the pairing this file's laws prescribe.

Measured: `_club_delegation_board_impl(p_session uuid, p_access text)` is `prosecdef`,
`has_function_privilege('authenticated', …, 'EXECUTE')` = **TRUE**, the body references `p_access`
and — comment-stripped — **never references `_club_shell_access`**. The outer
`club_delegation_board` derives the grade correctly; nothing makes a caller use it. It lives in
`public`, which PostgREST **does** expose — so unlike the `net` grant (OPEN #6), the allowlist is
not standing in front of this one.

Executed as role `authenticated` with **no party relationship** to the session, on a session that
actually has content: `p_access='host'` returns **1 dog / 2,185 B**, `p_access='none'` returns
**0 dogs / 663 B**. Different digests. The forged grade hands over `ownerName`, `runnerName`,
`proposedRunnerName`, `custodianProfileId`, `runnerId`, `bookingStatus`, `chargeState`,
`refundState`, `payoutState`, `payoutHoldReason`, `openIncidentId`, `dogName`, `collar` — **names,
re-identifying profile IDs, money state and incident references for a stranger's session.**

**Fix is one line:** `revoke execute on function _club_delegation_board_impl(uuid, text) from
authenticated;`

✅ **DONE — `0153_board_impl_not_for_clients.sql`, deployed and verified TWO-SIDED on production.**
Live catalog after: `authenticated` EXECUTE on the impl **false** · `anon` false · `service_role`
**true** · outer `club_delegation_board` still **true**. 🔴 **The exploit, re-run verbatim, now
returns `42501: permission denied`** where an hour earlier it returned 1 dog / 2,185 B; the control
confirms the legitimate door still opens. Harness **1086/0** (+5 = exactly the pins added — the
positive control that suite 184 RAN rather than being skipped from the manifest). Mutation battery,
4 arms, each `&&`-chained to its plant so an unlanded plant yields no row: revoke removed →
**APPLY ABORTS**; revoke removed + VERIFY removed → **B1 red alone**; over-reach (service_role also
revoked) → **B3 red alone**; control → **1086/0 clean**. B1 is blind to over-reach and B3 to
under-revoke, so they are two genuine controls, not one printed twice.
⚠ **B2 (anon) does NOT redden under the plant, and that is honest rather than a gap** — `anon` was
already revoked by `0147:189`, so B2 pins a property 0147 holds, not one 0153 establishes.
⚠ **NO CODEX PASS. codex was quota-walled until 14:33. This slice is NOT reviewed and nobody may
say it is.** It is owed one.

⚠ **My first attempt at this proof measured NOTHING and read as reassuring** — run against the
first session id in the table, both grades returned identical digests, because that session has 0
dogs and 0 runners. An empty fixture discloses nothing regardless of grade. Same trap as
`billing_keys`. **Find a fixture with content before believing a negative.**
⚠ Rung honesty: the DB-level call is OBSERVED; the same call over PostgREST with a real user JWT is
NOT — that rung is a read, not a measurement.

## Also new 2026-08-28 — the run-end money chain is REJECT, 12 findings

`docs/reviews/2026-08-28-codex-runend-money.md`. Beyond the disclosure above:
- 🔴 **CRITICAL: a runner can mint arbitrarily inflated earnings** with a future-timestamped GPS
  trace. Ingest rejects neither future timestamps nor trace duration; the only bound is 100 km. It
  moves the ledger and runner earnings **today** — no flag involved.
- **`club_end_pack_runs` has ZERO client callers** (verified independently: no executable reference
  anywhere in `app/`). The whole 0144 freeze is not in the settlement path; runs settle from the
  runner's own button, so **the runner's client values price the ledger**. Whether to wire it or
  retire it is Sean's call, and two other findings fall out of that answer.
- **0152 is incomplete**: weekly, fitness and leaderboard aggregates still coalesce unknown distance
  to zero. ✅ Codex's open question answered on production — `completed` bookings with NULL
  `actual_km` = **0 of 8**, so this is schema-reachable but **not observable today**. ⚠ One
  transition away: 1 of 9 runs has NULL km AND NULL duration (the `incident` run sitting in
  `incident_review`).

## 2026-08-28 — a third capability that is NOT a client-only slice, and a live product dead end

`session_reconsider_dog` was scouted and **deliberately not built.** The contract was read from
deployed `pg_proc`: host-only (`not_host` party gate), requires `approval='rejected'`, session
`open`/`full` and not past, and returns a NEW pending `session_dogs` row (the rejected row is never
mutated).

🔴 **The blocker is that the only party allowed to call it cannot SEE the rows it operates on.**
`_club_delegation_board_impl` admits rejected rows only through an **owner-only** arm
(`d.owner_profile_id = auth.uid() and d.approval in ('rejected','withdrawn')`), and
`club_session_board` excludes them for everyone. **Measured with a discriminating control** on the
production session holding the one real rejected dog, at the maximum grade: `auth.uid()` = the dog's
owner → **1 dog**; `auth.uid()` = a different profile → **0 dogs**. ⚠ That session's host IS its
owner, so the naive read proves nothing — the non-owner arm is the measurement that decides it.

🔴 **AND THE PRODUCT HAS A LIVE DEAD END THAT THIS RPC EXISTS TO CLOSE.** Deployed
`session_delegate_dog` refuses re-application after a `host_rejected` attempt, and
`club/delegate/[sid].tsx:104` renders that as **「이 세션에서 거절된 신청이 있어요 — 호스트에게
문의해주세요」**, while `club/session/[sid].tsx:1116-1119` deliberately draws no re-apply door
because the remedy is the host's. **The host's remedy is unbuilt.** The app tells an owner to go ask
the host, and the host has no button — **a mis-tap on 거절 is permanent for that dog in that
session.**

**It belongs on `club/console/[sid].tsx`** (b6's, exclusive) — beside the existing `pending` /
`review` filters, as one sibling section. Flagged, not taken. Whoever owns the console needs: a
rejected-rows source (a host CAN read them by direct table select today — `authenticated` holds
SELECT and `_club_session_member`'s arm ⓐ is the host; the cleaner fix is widening the board's
rejected arm, which is a server slice), an error map for `not_rejected`/`session_closed`/`not_host`/
`not_found`, and copy that promises only 심사 대기 — **not** a seat, since `session_approve_dog` can
still fail `no_capacity`.

⚠ **Two more facts worth carrying.** (a) `club_flags.club_delegation_v2` is **`enabled: false`** on
production, so this RPC and the whole v2 surface raise `feature_disabled` for anyone outside
`club_test_accounts` — whether that is intentional-for-now or a stale flag is a product question
nobody has answered. (b) The RPC is **not idempotent**: it never clears the old row's `rejected`, so
a second call passes all five gates and inserts a second active `(session_id, dog_id)`, violating
`session_dogs_active_uni` with a raw `23505` no error map would translate. ⚠ Deductive from two
observed facts, **not executed** — no write was made to production.

**Running total: three of the eight 「server-complete, client-only」 capabilities are not that.**
`km_claim_welcome` (no km wallet exists at all), `runner_work_gate` (already delivered via the edge
function's 409), and now `session_reconsider_dog` (the caller cannot see its own rows). The list was
derived from grants, which is the right method — but **a grant with no caller is not by itself a
missing capability**, and that distinction has now cost three scouts to learn.

## ✅ 2026-08-28 — the CRITICAL GPS fraud vector is CLOSED on production (`0156`)

A runner supplied every coordinate **and every timestamp**; ingest checked only monotonicity and
≤8 m/s, and derivation had **no upper bound at all**. A plausible slow trace dated hours ahead froze
99 km into a 5 km booking and the payout path wrote it to `ledger_items`. **No flag gated it.**

**Proven on production after deploy, read-only, with two controls:** the attack (two real fixes plus
a DENSE fabricated tail an hour ahead) derives **0.10 km** — identical to the honest trace with no
tail (**0.10**), so the forged tail contributes nothing — and a densely-sampled stationary dog still
derives **0.00**, so the fix did not over-reach into refusing honest zeroes.

**The shape worth knowing:** `_club_derive_run_km` is `stable` and is called from exactly one place,
inside the freeze transaction — so `now()` there IS the host's tap. Bounding on it gave the
reviewer's `started_at <= t <= v_at` with **no signature change and no 225-line recreation**.
A 60 s tap grace is deliberate: a fix a second after the tap is jitter, and a strict bound would
silently UNDER-pay the runner, which is the same class of error pointed the other way.

⚠ **This does NOT close finding 4.** Points arriving after the tap are no longer counted, but the
stale-trace race still needs a two-phase stop. Do not read 0156 as closing it.
⚠ **The 300 s coverage threshold is PROVISIONAL and is Sean's call** — codex's own open question is
「what maximum gap and minimum coverage define a measured run, including a genuinely stationary
dog?」 and nobody has answered it. It is one named constant.
⚠ **NO CODEX PASS** — quota-walled until 14:33. 0153 and 0156 are both owed one and neither is
reviewed.

⚠ **Suite 176 was repaired in the same slice**, per the standing rule. Its over-band fixture
(999 × 111 m ≈ 110.89 km) only ever fit because its generated timestamps ran **≈3.7 hours into the
future** — at the 8 m/s ingest ceiling that distance cannot happen in 30 minutes. `dF` is re-dated
five hours back; it is BLOCKED and freezes no km or duration, so no other pin reads its timing.

⚠ **I also deployed 0154 and 0155, which are another session's**, because `db push` has no per-file
selection and 0156 was a live money bug. **Verified safe before deploying, not assumed:** 0154 ships
`phone_collection_live_since` **NULL** (it adds the switch, it does not flip it) and I confirmed
`phone_still_off = true` on production afterwards; 0155 arms only when card registration goes live
(0 keys, 0 revocation rows). ⚠ **0155's REGISTRY row still reads 「NOT DEPLOYED, NOT PUSHED」 and is
now stale twice over** — its owner should correct it.

## Unreviewed

~14 of the 21 deployed migrations carry **no codex verdict**, and 0131's seven review rounds
cover **0131 alone, not the stack**. Sean was told this before authorising and chose to proceed.
Worth a sweep when there is quota to spend.
