# Awaiting Sean — the return queue

> **⚡ 2026-08-20 evening: SECOND OVERNIGHT GRANT — Sean is asleep.** Sean, verbatim, to the client
> session: *"keep going, dont stop, deploy multiple agents, im going to bed (tell everyone)."*
> **[end of Sean's words]** Recorded here by the client session (`exciting-rosalind-e6ac13`) because
> he asked for it to reach everyone and this file is what every session reads. There is no announcer
> online tonight — its socket has been gone since ~14:00, so **nobody is holding a console; each
> session is on its own recognisance.**
>
> **What it grants:** keep building through the night without asking, decide independently, and use
> parallel subagents. **What it does not grant** (structural, not ceremony — unchanged from the
> 08-19 grant): credential VALUES stay his (Apple 2FA, App Store Connect, the APNs .p8, dashboard
> toggles); facts only he holds still need his answer; irreversible destruction of real production
> data still gets one confirmation; and every gate stays in full — for the client that is tsc ·
> check-rpc-contracts · check-route-native-imports · check-embed-fk · lint at its 6-error baseline,
> before every commit.
>
> **Earlier the same day he also said** (client session, verbatim): *"straighten out all gaps in the
> logic or structure or events or the app ui like the world depends on it right now"*, then *"skip
> the rest of the reviews and start fixing criticals first"*, then *"i just want to make progress in
> the app and the ui and make sure the user has ease of click in flow for a smooth path to a live run
> and afterwards as well."* **[end of Sean's words]** The last one is the standing steer: the client
> work is ordered by **journey friction**, not by severity rank.
>
> ⚠ **Two standing laws that matter more than usual tonight, with nobody coordinating:** a relayed
> decision is evidence, not authority — this block is the client session relaying Sean, and it is
> authoritative only as to what he said, not as to what anyone infers from it. And unpushed reserves
> nothing: land your work, or by morning it does not exist.
>
> **Client-domain state at the time of writing** (`58d6521` on trunk): 17 defects fixed and pushed
> tonight in three batches — criticals (dead nomination, wrong-party SOS, the checkout fee lie, an
> unbuilt paid add-on, runner payouts quoted 8% low, an armed catalog bomb), a UI honesty pass, and a
> journey-flow pass (the handoff push landing on the wrong screen, a searching booking with no
> management path, three screens with no exit). Full inventory and what remains:
> `docs/plans/2026-08-20-client-gap-straightening.md`.

> **⚡ 2026-08-19 late evening: OVERNIGHT GRANT.** Sean, verbatim: *"i will be gone overnight, do not
> stop until i come back. let the others know as well; continue advancing the app, no permissions
> asked, do not ask me for input, decide independently."* **[end of Sean's words]**
>
> Applied by the announcer as: every open item below that was waiting on a *decision* gets decided by
> the announcer tonight under this grant, marked **🔵 decided-under-overnight-grant** (never ✅ — a
> stand-in's call is reversible and carries its reasoning so Sean can flip it in one word in the
> morning). Physical/credential items (dashboard toggles, Apple 2FA, counsel forward) stay his by
> nature. Gates stay in full: harness → contract → adversarial reviewer ≠ author → land → deploy via the
> wrapper → verify live → record. Sessions keep building; the announcer keeps the console and this file
> current through the night. Decisions taken tonight are listed at §0-overnight below.

> **⚡ 2026-08-15: SEAN ANSWERED SEVEN AT ONCE.** His words, verbatim: *"1: yes i tried it, but
> no way to download on a real phone unless they have expo no? 2: A, give me a dashboard with
> possible solutions and etc all things necessary. 3: b. 4: A. 5: not sure what that account is
> but yes i do have a test account under user id s4kim2025. 6: give me a brief or short report i
> can show to a lawyer. 7: A"* **[end of Sean's words]**
>
> Applied: **§0** signup tried by Sean (distribution question open — see body) · **§0-quinquies ✅
> alerts go to Sean**, dashboard commissioned; his profile measured as `aa73ce8a…` (name
> `s4kim2025`, handle `choco`) · **§0-ter ✅ all 9 runners are TEST DATA** — trust marks them in
> `club_test_accounts` and the flag/copy gets fixed · **§0-sexies ✅ option A** — start the
> paperwork chain, keep the charge machine; payment-surface honesty fix unblocked · **§0-septies ✅
> confirmed** — Sean's word: the `s4kim2025` test account exists; the mapping `aa73ce8a…` =
> `s4kim2025` (handle `choco`) is a *measurement* (trust verified it unique). Recorded as the
> PR-0 test owner — two facts, two provenances · **위치정보법 brief
> delivered** at `docs/biz/location-law-counsel-brief.md` · **hill notes: yes, ~40 m** ("언덕
> 많음"), ui builds.

> **⚡ 2026-08-15, later: SIGN-IN RULED.** Context: the app's two doors were Kakao OAuth and a
> 6-digit **email** code — no phone/SMS path ever existed. Sean: *"for sign up i always used kakao
> and never the email thing. dont use an email, use phone number. also, we have a text code double
> verification on the phone number pathway?"* — answered (no such pathway exists), options given,
> and he ruled: *"b"* = **KAKAO ONLY for the pilot; the email path is removed; phone/SMS deferred.**
> ui removes the email stages from `login.tsx`; trust verifies the server accepts only what the
> client offers (an email door left open server-side is a signup path outside the app); the
> TestFlight install-day check becomes "Kakao sign-in works on a real phone."

> **⚡ 2026-08-15, later: OPS DASHBOARD LOCATION RULED.** Sean: *"B. a simple web build is fine."*
> — the dashboard is a **standalone local web tool on his computer**, not an in-app screen. So:
> no new party-gated read RPC, no migration number, trust's §6 question is answered, and the tool
> reads the two service-role detection functions from a local server on his machine only (the
> service key never ships in any client). ui builds the page against trust's read contract; trust
> reviews the key handling. The in-app version and the push emitter (nothing emits today —
> 0096/0097 are pull-only) both remain open items, deliberately unsmuggled into this slice.

> **⚡ 2026-08-15, later: STANDING AUTONOMY GRANT.** Sean, verbatim: *"tell the conversations they
> dont have to ask me for permission on things they have fruitful as i want full speed on this app
> production."* **[end of Sean's words]** Applied as: sessions build, gate, and ship fruitful work
> on their owned surfaces WITHOUT asking first. What this does NOT waive (structural, not
> ceremony): credential VALUES stay physically his · facts only he holds still require his answer ·
> irreversible destruction of real production data still gets one confirmation · every quality gate
> (harness, /autoplan on migrations and money paths, trust's plan-time review, the commit gates)
> stays — those are how full speed stays speed instead of rework.

**Purpose: this queue existed only inside one session's conversation.** The announcing session
asked for it to be written down, applying the day's first rule to itself: *unpushed reserves
nothing.* If that session runs out of context the way the 반포 route session did, an
in-conversation queue evaporates — and it would evaporate silently, because nobody knows to
look for a list they never saw.

Ordered by what blocks the most. Nothing here is decided; **🟡 means it is Sean's**, and per the
governance rule in [README.md](README.md) a stand-in's analysis never becomes a ✅.

---

## 0-tredecies. 🟡 CAMPAIGNS ARE BUILT AND LANDED — four small calls, and one of them is permanent (marketing, 2026-08-20 night)

Three campaigns (App Store 사전주문 · TikTok 슬라이드쇼 · Instagram), 49 rendered post files, a
generation prompt library, and the `dogshigh.kr` landing copy are on trunk. **Nothing here blocks
publishing except (C), which is irreversible.** Everything else is a preference I have defaulted and
labelled so it can be flipped in one line.

**Already ruled by you tonight, in your words:** *"color of gps is fine."* **[end of your words]** The
violet route trace is the campaign's repeating signature. I extended that into a rule you did not ask
for and should know about: **the trace is now vector-only, plotted from a real GPX, and any pace/km
readout beside it comes from that same file.** A drawn line with an invented `8:34/km` next to it is a
fabricated data display and walks straight into our own ban on generated GPS trails; plotted from one
of your actual runs, it is proof instead. Cost: a frame with no GPX gets no trace and no number.

| | Question | Default I took | Reversible? |
|---|---|---|---|
| **A** | Install Black Han Sans and re-render all 49 posts, or ship with the stand-in? | Shipped with Apple SD Gothic Neo Bold as a labelled stand-in. I did not download the font — that is yours. Re-render is one command. | yes |
| **B** | Who retouches the swooshes? | I routed around them: the manifesto tile is *built*, not cropped from `REMOVE NIKE.png`. Two `dumb/` files still used in TikTok TS-2 need a pass. | yes |
| **C** | **Bundle ID `com.seankookim.daengrun` carries the dead name and is IMMUTABLE after the first upload.** Migrate before the first build, or keep it forever? | none taken — this one is genuinely permanent and I will not default it | **NO** |
| **D** | The English line set on the assets (CHASE THAT HIGH · TWO HEARTS. ONE PACE. · A TIRED DOG IS A HAPPY DOG.) — canon, or this season only? | treated as this season's campaign layer; the Korean taglines stay the permanent layer | yes |

**Decided under the overnight grant, one line each, all reversible:** the locked style anchor is
`SREF-01` (§2.6 of the prompt library) · posts are fitted inside the centre square of their 4:5 frame
so the grid composition survives any crop ratio · the landing page keeps exactly two buttons and no
testimonial section, not even an empty one.

**One finding worth more than the four questions:** logo contamination in the asset set is **invisible
at thumbnail scale.** The first style anchor I picked looked clean on a contact sheet and had a swoosh
on the shoe at 100%. Inspect at full resolution before trusting any file in `~/Desktop/post`.

**What the campaigns will not say, and why** — 바디캠 (no pipeline), 신원인증 (`identity_verified` is
hardcoded false), any pass-rate figure (1기 has not run), any release date (not ours to promise), and
no App Store screenshots at all (they must come from the real app; no build has ever run). None of
these are faked anywhere in the set.

Files: `docs/campaigns/` (5 docs + 29 paste-ready prompt blocks) · `docs/labs/posts/` (49 files) ·
`docs/labs/preorder-posts.html` and `preorder-campaign-board.html` (open these to look) ·
`.claude/brand-voice-guidelines.md`.

---

## 0. 🔴 SIGNUP — narrowed 2026-08-15, half closed by execution, half still needs one human

**UPDATE (audit, 2026-08-15):** the DATABASE half is closed — trust probed the exact grant chain
that broke signup (`8c1d2fc`): the PostgREST role-picker upsert succeeds as `authenticated`, no
42501. **The GoTrue half (OTP delivery, `auth.users` creation, Kakao OAuth) remains unverified**
and needs a real account creation — one human, one phone, five minutes. Still the only
total-outage risk on the board, but now scoped to the half no session can test.

**Raised independently by both voices of trust's `/autoplan` review, which called the security
sweep the wrong slice while this sits unchecked. Queued 2026-08-14.**

`0088` + `0091` are verified **applied**. That is a different claim from verified **usable**, and
`0091` exists *precisely because* a grant change 403'd every signup: `0088`'s grant omitted `role`,
and PostgREST's role-picker upsert reads `excluded.role`. The fix is applied. **Nobody has run a
signup since.**

Everything else here is a disclosure, a filing or a product call. This one is binary and it is the
front door. It needs one human, one phone, five minutes. **Not a decision — an errand — but it
outranks every decision below it.**

## 0-bis. 🔴 위치정보법 — a filing that gates launch, and carries criminal rather than financial exposure

**Surfaced by trust's review 2026-08-14. Needs Korean counsel; answerable in a day.**

`app.json:74` enables background location and `app/src/lib/bgTrack.ts` streams a runner's
coordinates to a watching owner. That is 개인위치정보 of an identified individual, which in Korea
generally requires a **위치기반서비스사업자 신고 to the KCC BEFORE service**, a location consent
**separate** from the PIPA consent, and a location-specific 약관.

**Why this ranks above the PIPA items below it:** unlike PIPA's revenue-scaled 과징금, operating
without the filing carries **criminal exposure, and it does not shrink because we are pre-revenue.**

⚠ **And it makes §2's question the wrong one.** The App Store privacy sheet says background
location is **not** declared, while `app.json` declares it. So that questionnaire is **stale, not
merely unfiled** — asking "has it been filed yet" accepts a premise that is already false.

## 0-ter. 🔴 Seeded runners claim `identity_verified` behind copy promising personal verification

**Surfaced by trust's review 2026-08-14. Unowned. Measured by the announcer the same day.**

All **9** `runners` rows carry `identity_verified = true`. PASS is unintegrated and
`profiles.phone` is NULL for every user (§6), so **no identity verification has ever occurred** —
the flag is seed data sitting behind copy that tells an owner a stranger was personally verified.

For a service where a stranger takes physical custody of someone's dog, this is a live
honesty-law breach (`CLAUDE.md`: *bind real fields or omit the element*) and a larger liability
than anything on the anon-read surface. It is also **anon-readable**: those 9 rows are returned by
`tier <> 'applicant'`, 7 of them carrying free-text `bio`.

Fix direction is not a decision — clear the flag or gate the copy — but **who owns it is**.

**AUDIT ADDENDUM 2026-08-15 — the user-facing copy this flag now stands behind:** `app/safety.tsx`
was honesty-repaired on 2026-08-08 to claim only *"운영자가 화상 통화로 러너를 직접 만나 신분증을
확인하고 한 명씩 승인해요"* — and its own code comment says this is true **only while no
seeded/grandfathered certified runners exist in prod.** All 9 production runners carry
`identity_verified = true`. **So the question is a fact only Sean holds: did you actually
video-verify those 9 people?** If yes, the flag is true and this item closes. If no, the flag is
seed data and must be cleared before any owner reads that screen next to a runner card.

## 0-quater. ✅ LAUNCH TOWNS — RULED 2026-08-14. It is a rule, not a list.

**Sean, 2026-08-14, verbatim:** *"launch towns are the towns with the gpxs. and yes those 잠실
잠원 gpxs are valid"*

**[end of Sean's words — everything below is the announcer's reading, not his.]**

This closes the open call the previous handoff carried as *"the canonical launch-town list
(district and town overlap on one value of five; 뚝섬/서울숲 are landmarks, not dongs)"*. He did
not hand over a list. He handed over a **derivation**, which is the better artifact: a list goes
stale the moment coverage moves, and this cannot.

**Do not maintain a list here — derive it.** A table of today's answer is exactly the stale
artifact this ruling avoids, so the durable form is the command:

```bash
git ls-tree -r --name-only origin/claude/strava-route-loops-74c5d2 docs/routes/strava/ \
  | grep '\.gpx$' | sed 's|.*/||' | cut -d_ -f1 | sort -u
```

**As of 2026-08-14 that returns seven towns from 19 GPX** — 반포 · 잠원 · 잠실 · 이촌 · 성수 ·
도곡 · 압구정 — which completes the seven districts the original brief named. Route geometry is
still adding coverage, so **run the command rather than trusting that sentence.**

**Two consequences that are now implementation, not decision:**

1. **The vocabulary must be normalised, and the ruling settles which way.** `profiles.district`
   holds `{null, 반포동, 성수, 뚝섬, 서울숲}`; `routes.town` holds `{반포동, 성수동}`. They
   overlap on **one** value, which is why a signed-in 성수 owner saw zero courses even with the
   candidate fallback working perfectly — the town filter emptied the set before the fallback could
   apply (client, `9388a91`). Under this ruling the target vocabulary is **`routes.town`**, and
   `뚝섬`/`서울숲` are landmarks inside 성수동, not towns. Client's surface.

2. ~~**Four of the six towns have GPX but no `routes` rows.** Those INSERTs are a production
   catalog change and still need Sean's explicit go-ahead.~~ **SUPERSEDED SAME DAY — he gave it,
   in the route-geometry conversation:** *"make whatever necessary, no need to ask permission"*
   **[end of Sean's words]**. The INSERTs ran. Measured 2026-08-14 ~17:00: **32 rows · 8 towns ·
   zero empty traces** (반포동 12 · 잠실동 5 · 성수동 5 · 잠원동 4 · 이촌동 3 · 송파동 1 ·
   압구정동 1 · 도곡동 1). ⚠ 송파동 is in production and is not in the seven towns anyone had been
   reciting — worth establishing whether that is intended.

⚠ **THE LESSON HERE OUTRANKS THE FACT, and it is about this file.** The struck sentence above was
written *specifically* so a ruling could not be read as covering the adjacent thing — and it was
correct when written. But it was phrased as a **standing fact** rather than a fact with a
timestamp, so when Sean ruled an hour later in a different conversation, the safeguard did not
merely expire: **it kept asserting the opposite of the truth, with the authority of a deliberate
warning.** The announcer then relayed it to a fresh session, which nearly built an ingest pipeline
for an already-ingested catalog.

**So: date every constraint.** *"As of 16:xx, not authorised"* degrades into obvious staleness.
*"Needs his go-ahead and he has not given it"* degrades into a lie. Same family as the
artifact-looked-right class this repo keeps hitting — the memo looked current. (Correction supplied
by the route-geometry session, which had the ruling; the error was the announcer's.)

**Also settled by the same sentence:** the five 잠실/잠원 GPX that appeared in the route worktree
carrying Sean's Strava author tag are **his and valid**. They are not a second session writing into
the tree. Their names should still be checked against their measurements before ingest, because
measure-then-name is a property that cannot be assumed of any file.


## 0-quinquies. 🔴 The ops escalation chain fires into NOBODY — recipient decision needed (audit 2026-08-15)

Measured: `ops_recipients` exists and has **0 rows**; `OPS_PROFILE_ID` is unset. So 0084's
reconciliation arms, and custody's 0096/0097 unsettled-run detection, all currently resolve to an
empty recipient set — detection works, delivery reaches no one. Custody documented this honestly in
0096's own header ("이것은 PAGER가 아니라 질의 함수다").

**Your half (the decision):** who receives ops events (a profile id — presumably yours for the
pilot), and what acknowledgment/SLA means. **Custody's half (mechanical, after you answer):** insert
the rows / set the env, wire the push. One sentence from you unblocks it.

## 0-sexies. 🟡 Toss vs manual transfer — the pilot's payment reality (money, 2026-08-15)

You asked money *"do i need toss for payments? can i just not ask them to upload credit card
info?"* Their analysis, which I endorse: **you cannot charge today regardless** — the 사업자등록 →
통신판매업 → 자동결제 심사 chain is the long pole — so **the pilot ships on manual transfer as a
STATE, not a choice.** The narrow decision: **start the paperwork chain now (recommended: 심사 runs
in the background for weeks) or commit to manual and delete the charge machine.**

Consequence either way: the no-card empty state **is** the pilot, and the current payment surface
implies automation that does not exist — an honesty-law item, now client's to fix once you pick.

## 0-decies. ✅→📋 CLOSED AT THE BOUNDARY under your default — 0111 DEPLOYED late 2026-08-19; only D1/D2 remains yours

**Outcome (measured, not relayed):** with no answer from you, default **A** ran: contract → attacked in a
scratch cluster (21/21, B-3 reproduced) → F1–F12 folded → 0111 implemented (harness 655/0, Deno 191/0,
eight mutations) → independent adversarial reviewer (FIX-FIRST on a fare-blind belt claim; fence
unbreakable by direct / CTE / INSERT…SELECT / view / definer / role) → round 2 (657/0) → trunk →
`create-booking-hold` v9 + 0111 applied via the wrapper → verified live: client INSERT on
`bookings`/`recurring_series`/`slot_holds` = 0 grants, forged INSERT and forged series UPDATE as
`authenticated` → 42501 (rolled back), `paused` is the only client-writable series column, cron +
service_role untouched. 0105 file deleted, HELD empty, REGISTRY rows 0105 SUPERSEDED / 0111 DEPLOYED.
**/cso #2 is PARTIALLY CLOSED:** F1/F3/F4 closed; **F2 stays open** — the legit nomination chain (own
dog → `payment_ok` → `request_runner` = any runner, no acceptance) still opens chat/push/reviews/incidents
because `is_booking_party` has no status filter. That is **your D1/D2 below**; it decides the shape of
the adjacent slice, and nobody builds it until you answer. Original lookup text kept below for the record.

## 0-decies (original). 🟡 LOOKUP — trust is offline and nobody is rebuilding 0105, the last open P0 (announcer v3, 2026-08-19 evening)

–––––REPORT–––––
**Measured, not relayed:** trust's session has been off the roster for hours. The 0105 *file* is on
trunk and six branches — all the same reviewer-rejected version (`0bb40ac`); **a replacement exists
nowhere** (no origin branch, no local branch, no worktree, no stash). Production: 0106/0107/0108
applied, **0105 not applied** (deliberate). The spec for the rebuild is already on trunk:
`docs/security-booking-party-forgery.md` (F1 `recurring_series` money-mint via the hourly cron; F2
`create-booking-hold` takes `runner_id` from the body; F3 revoke-INSERT has zero client blast radius).
Side effect while it stays open: **every deploy in the fleet is serialized behind it** — see
`docs/handoff-announcer.md` (v3 addendum) for the only safe recipe and the one CLI hint never to run.

**Default I am applying under your "full speed" rule unless you say otherwise:** announcer-directed
subagents rebuild it under the full adversarial cycle (scout → contract → /autoplan → implement →
reviewer ≠ author executing attacks → pins → land on trunk → deploy with the recipe → verify live).
It is a money path, so every gate runs. Catalog offers a scratch cluster reproducing production's
exact schema for the reviewer.

**Update, later the same evening — the contract exists:** `docs/contracts/booking-entry-rebuild-contract.md`
(scout, read-only, measured against production). Recommended shape: revoke client INSERT on `bookings`
+ drop the owner-insert policy (no RPC needed — 31 client `from('bookings')` calls are all `.select`);
close `recurring_series` client writes; ownership re-check in the cron; delete `create-booking-hold`'s
`runner_id` body arm (the client never sends it); supersede 0105 rather than apply it. **New finding
no artifact had (B-3):** `authenticated` holds table-wide UPDATE on `recurring_series` and there is no
trigger, so an owner of a *legitimate* series can re-point `dog_id` to a victim's dog and set
`min_fare` to 500000 today, and the hourly cron mints the booking — an INSERT-only fix would not close
it. Money half is inert while charging is off; the dog-exposure half is live. Next under default A:
an adversarial reviewer executes attacks against the contract before anyone implements.

**One product question inside it (yours, not engineering's):** after the rebuild, `runner_id` can only
be set by `request_runner` (owner-gated). That is a legitimate nomination — and it still opens chat,
reviews, incidents and push to a runner who has **not accepted yet**, because `is_booking_party` has
no status filter. **Is pre-acceptance contact a feature or a leak?** — **D1** = feature, leave it ·
**D2** = leak, narrow party membership to accepted/active states (adjacent slice, not this one).

Your answer, one letter:
- **A** — go (the default; nothing needed from you)
- **B** — reopen trust and let the session that holds the RLS context do it; sessions wait
- **C** — a session name of your choosing
- plus **D1/D2** above when you have a view
–––––[end of report; nothing above is your ruling until you answer]–––––

## 0-quindecies. 📋 LEGAL'S NON-LOCATION REVIEW — on trunk; one counsel item for you, one small build gap (2026-08-19 night)

`docs/legal/readiness-review-nonlocation-2026-08-19.md` (legal, docs-only, merged yours→trunk). Headline: the non-location
surface is in better shape than the location half, largely because most of it is not built. **For you (errand, not
decision): §4 goes to counsel WITH the control table** — the terms claim pure intermediation and runner independence while
the code holds every economic control (prices, runner pay constants, commission server-side, who may see work, the
cancellation ladder, GPS), no runner-set price exists anywhere, and `0101:63-71` lets a price revision reprice an unsettled
run's PAYOUT while the CHARGE stays frozen — against 2024두32973 that is the worker-status question made factual; counsel
decides, not us. Also to counsel as a question: §10.4 variable post-service charges on a stored key with no pre-charge amount
notice (ruling ② cancelled per-charge notice) — not the fixed-amount subscription the source review answered. **Build gap
(small, queued, not tonight's priority): `맹견` appears nowhere** — no dog-profile field, no booking-time refusal; real before
real owners. Relief: no vehicle pickup (동물운송업 not in play), shop is a preview shell, points are non-transferable
(마일리지 shape). Latent: reviews RLS is party-scoped while the client queries all public runner reviews (anon → 401, 1 row;
not exposed) — widening that read path is the moment §11 goes live, so it is a legal decision, not a UI fix; the community
feed has no reports/moderation table (임시조치 will be needed there first).

## 0-tervicies. ✅ CLOSED SAME DAY — the launch-path null-name write (found on device, fixed by ui2, re-verified independently)

Found on a real cold launch by the verification session: **cold launch → role select → settings** raised 「프로필 저장 실패 — null value in column "name"」. The NOT NULL constraint refused it, so **no data changed** — but something on the launch/role-select path is attempting a `profiles` write with a null `name`. This is the SIGNUP path, which is §0 at the head of this queue and the one thing nobody has been able to test end to end. **CLOSED at `3be5c2b` (+ `836245c`), root cause found and fixed by ui2, then re-verified by the session that found it using its exact original repro (cold launch → OWNER → `daengrun://settings`): no alert, production reads `name='s4kim2025', role='owner'`, district intact; all four client `profiles` writers swept, no sibling path can produce it.** Root cause worth knowing when you run §0: role-select used `upsert` with `{id, role}` for an EXISTING row, and Postgres NOT-NULL-checks the proposed tuple BEFORE conflict resolution — so the deliberately-omitted `name` killed the statement on every launch and **the role write silently never landed**. Nothing was corrupted; the fix chooses the statement (`update({role})` vs `insert({id, role, name})`) rather than shaping the payload. This was a real piece of the signup path being unverifiable — §0 still needs your five-minute run, but with one fewer thing broken under it.

## 0-duovicies. 🔴 NOTHING PAYS RUNNERS — no payout mechanism exists at all (measured 2026-08-20)

Surfaced by the 0115 review and confirmed by the announcer: `ledger_items` (0001:264-275) records what a runner EARNED and has **no
paid/settled marker**; `payouts` has `paid_at` (0001:295) and **zero writers anywhere in the repo** — nothing has ever created a
payout row. So the platform can compute lifetime earnings and cannot answer "have we paid them". Consequences already handled:
account deletion does NOT gate on a balance (a gate on lifetime earnings could never clear — it would trap the runner forever and
re-open App Store 5.1.1(v)), and instead keeps the payout destination intact while earnings exist (§0-overnight O-7, Sean's call
2026-08-20: **A-intact-when-owed**). What is NOT handled: **runners cannot actually be paid.** Inert today — 8 ledger rows across 1
runner, all test data, charging off — and it becomes real the day charging flips. Needs: a payout writer (manual ops run or Toss
payout), a paid marker on the earnings, and then the deletion gate becomes implementable. Unowned; money/trust surface.

## 0-tricies. 🔴 MONEY + SERVER DEFECTS THAT MUST BE FIXED BEFORE CHARGING FLIPS — all inert today (2026-08-20)

Found by the money and server sweeps. **Every one is harmless while charging is off** — `payments_live_since` null, 0 payments,
0 billing keys, `TOSS_SECRET_KEY` unset, Vault secret absent: four independent off-switches, all measured. Each becomes real on flip day.

**1. 🔴 A charge can mint for a dog still on the leash.** `sweep_settled_without_payments` lacks the `settled_at is not null` guard —
**verified live by the announcer** (`prosrc like '%settled_at is not null%'` → false, while it does reference `ended_at`). After 0083 the
return handoff is what says the dog is home; without the guard the sweep can bill on run-end alone. One predicate plus a pin.

**2. 🔴 Club cancel fees are structurally uncollectable, and the runner's share never lands.** `_club_record_cancel_fee` writes
`club_fee_items` and **never** `bookings.cancel_fee` — **verified live by the announcer** (writes_booking_fee → false, writes_club_items
→ true). So the charge mint AND the unpaid-debt gate both see zero for a club cancellation, and the runner's supply-compensation share
never reaches `my_ledger_total`. Two fee ladders exist and nobody has ruled which governs. **This one needs YOUR ruling, not just a fix.**

**3. 🔴 One unparseable timestamp stops charge dispatch for everybody.** `dispatch_due_charges` (SQL) and `isDue()` (TS) have drifted:
SQL hardcodes `< 3` where TS uses `MAX_ATTEMPTS`, and an unparseable `next_retry_at` makes the SQL side raise — so the batch never wakes
for any user, while TS treats the same row as due. [reported by the sweep; not independently re-measured]

**4. 🟠 Four definer functions answer questions about strangers.** The server sweep measured four functions with `authenticated`
EXECUTE that take a caller-supplied id and contain **no `auth.uid()` anywhere**: `club_incident_settle_quote` (a full money and
handoff-timing readout of ANY booking), `runner_work_gate` (a liveness oracle for ANY runner), `club_dog_ui_state`, `club_host_stats`.
No suite pins them. The two HIGH ones are small fixes. Not urgent at 1 real user; it is the same class the /cso audit closed elsewhere.

**Also recorded, not decisions:** `docs/payments.md` is wholly obsolete · `docs/decisions/README.md`'s ① and ⑩ status rows are false ·
one assertion still carrying a ✅ on origin (⑪ gates ⑫) is wrong and was retracted elsewhere — a ✅ that is not your current word is
exactly what the governance rule exists to prevent · `km_expire_sweep` is defined but **never scheduled** (checked against all 17 live
cron jobs) · `create-payment-intent` exists locally and is NOT deployed · `addresses` has zero grant/revoke statements in any migration.
Full detail: `docs/handoff-codex/money-domain.md` (both ledgers for every end scenario, 15 reconciled contradictions, 40 unbuilt items)
and `docs/handoff-codex/server-domain.md` (69 tables, 190 definers, 64 unbuilt items, 35 traps).

## 0-undetricies. 🔴 CODEX (gpt-5.6-sol, xhigh) — an independent 30-day read, and one MEASURED bug in the PMF gate itself (2026-08-20)

Sean asked for collaboration with Codex rather than a handoff. Its first pass read the repo cold. **The finding I verified myself and
which outranks the rest: `scripts/pilot-metrics.mjs:135` computes M1's window from `firstDone.created_at` — the BOOKING'S CREATION
TIME — while the comment two lines above states the definition as "from the first COMPLETED run".** The file never references
`runs.ended_at` (0 occurrences). Two consequences, both real: a booking created weeks before the service becomes eligible the moment
the window elapses from CREATION, and a second booking made BEFORE the first run ever happened counts as a rebooking. **So the 60%
rebooking gate that CLAUDE.md and the launch checklist make the condition of expansion is currently measuring "booked twice", not
"came back after a run".** Fix is small (use the run's end, and report "second booking intent" separately from "second completed
run") and unowned. Nothing is invalidated retroactively — there is 1 real user and 0 real customers, so no decision has yet been made
on a bad number.

**Codex's three ranked risks, none of them security or compliance** (its words, condensed; full text in the session log):
1. **No two-sided market evidence** — `docs/validation-interviews.md` says finish 15–20 interviews before writing more code;
   `docs/interviews/` does not exist; all 9 runners are test data. Its prescription: stop expanding routes/clubs/campaigns/brand for
   seven days, recruit 3 owners + 3 runners in Banpo, manually fulfil five runs. **It calls the documented 50-dog/22-runner pilot "a
   scale test masquerading as a pilot" and says the first pilot is 3×3.**
2. **The native product is hypothetical** — 0 EAS builds ever; nine config plugins; Kakao/Naver/background-GPS/push/Live
   Activities/Toss are all unproven on hardware; no UI E2E framework and no `test` script in `app/package.json`. Its prescription:
   cut **Build 0 immediately from clean trunk**, before any remaining polish, and run one two-phone path end to end (cold Kakao
   signup → book → nominate → accept → arrive → handoff → lock the phone and walk 500 m → realtime + push + return seal + ledger).
   "A build is a test artifact, not a release commitment."
3. **No closed-loop operating system** — `ledger_items` has no paid marker and `payouts` has no writer (already §0-duovicies);
   `OPS_PROFILE_ID` unset and `ops_recipients` empty, so every alert terminates in a log nobody reads; no crash reporting, so a
   failure on Banpo LTE is invisible. Its prescription: do NOT automate bank movement — make Sean the recipient for every ops event,
   add an ops-only manual payout journal that links `ledger_items` to a `payouts` row with `paid_at`, and run a twice-daily stuck-state
   report. "An unrecorded bank transfer is not acceptable; a spreadsheet keyed by ledger-item ids is, for the first five runs."

**It also says the route catalog is not the moat yet** — `positioning.md:33` names dog fitness DATA as the moat, and drawn geometry
is not that.

**✅ SEAN CHOSE B (2026-08-20): keep building; Build 0 slots in later.** No feature freeze, no 3×3 concierge pivot right now. What that does NOT dismiss, and what a later Build 0 inherits: the native surface is still entirely unproven (0 builds ever), so every native claim in the app — Kakao login, Naver maps, background GPS, push, Live Activities, Toss — remains code-plus-gates only, and the day Build 0 happens its blocker list becomes the queue. Codex's other two risks (no market evidence; no closed-loop ops) are NOT closed by choosing B — they are deferred, and the ops one overlaps §0-duovicies (nothing pays runners). Separately and cheaply: **fix the M1 gauge** (yes/no — it is a bug either way, but you may want it
fixed before anyone quotes a number from it).

## 0-duodetricies. 🟡 THREE THINGS THE LEGAL/OPS SWEEP FOUND, each verified by the announcer (2026-08-20)

**1. Every logged-in user can read every public runner review — and a shipped legal doc says otherwise.** Measured: `reviews` carries FOUR
SELECT policies, and `reviews storefront read` is `visibility='public' AND target_kind='runner'` with **no party term** (0011). The
non-location legal review concluded reviews were not exposed — but it probed as **anon** (401) and the exposure is to **authenticated**.
Same "read one layer, describe another" family that has bitten five times now. ⚠ Nuance the sweep overstated and I measured: there are
**zero** public runner reviews today (1 review total), so the POLICY is live and the DATA is empty — it becomes real the first time a
public runner review is written. **A** intended, it is a storefront, leave it · **B** narrow it (a review of a runner is about a named
person) — legal's position was that widening this read path is a legal decision, not a UI one.

**2. A decision of yours is buried in a code comment, not in this queue.** `supabase/migrations/0060_wave3_server_honesty.sql:52-53`
(verbatim intent): *gate_code_access_log has never once been written to — it is an empty shell; adding a log would make
`booking_pickup_address` volatile — awaiting Sean's judgement; use the club_phone_access_log (0049) pattern if he wants it.* So the
gate-code viewing log exists as a TABLE with no writer, and whether to actually log gate-code access is your open call. It is the same
family as the 위치정보 제16조 access ledger legal wants built. **A** log it (function becomes volatile; copy the 0049 pattern) · **B**
leave it unlogged and delete the empty table so nobody mistakes the shape for the behaviour.

**3. Eight `scripts/*.mjs` still tell the reader to put the service key in a root `.env`** — the exact defect the CSO audit closed by
moving it to `~/.config/daengrun/ops.env`. Nothing is leaking today (the key is not in the repo), but the instructions would re-create
it. Small cleanup, unowned, no decision needed — flagged so it is not rediscovered as news.

## 0-septemvicies. 🔴 IRREVERSIBLE, AND IT SITS DIRECTLY BEFORE YOUR TESTFLIGHT ERRAND (2026-08-20)

**`app/app.json:22` — `"bundleIdentifier": "com.seankookim.daengrun"`** (and the widget target at `:99` mirrors it). **[measured by the
announcer]** It carries the RETIRED brand name, and a bundle ID is **immutable once the first build is uploaded to App Store Connect** —
after that, changing it means a NEW app: new listing, new reviews, new URL, pre-orders and any App Store momentum start from zero.

⚠ **This is ordered wrong on your queue and only you can fix the order.** TestFlight (your Apple 2FA errand) is the first upload. If
you do the 2FA step before ruling on this, the retired name is locked into the store identity forever. The campaign session refused to
default this one — correctly; it is the only irreversible item in its whole set.

**A** rename now to a 도그스하이-derived id (e.g. `com.seankookim.dogshigh`) BEFORE any upload — costs one edit to `app.json` plus a
rebuild, and it must happen before TestFlight · **B** keep `com.seankookim.daengrun` knowingly, accepting that the store identity
carries a name the product no longer uses · **C** decide at upload time (⚠ not really an option — the upload IS the decision).

## 0-sexvicies. 🟠 THE DEAD BRAND AND A BANNED WORD ARE WIRED TO CARD STATEMENTS — fix before charging flips (2026-08-20)

Found by the brand round, **verified by the announcer**: `supabase/functions/_shared/charge.ts:117-118` sets the PG `orderName` to
「**댕런** 산책 이용료」 and 「**댕런** 예약 취소 수수료」. Two problems in five words — `댕런` was retired 2026-07-28, and 「산책」 is on
`docs/positioning.md:44`'s banned list (안 쓰는 말: 산책, 대행, 돌봄, 시터; the category thesis is 러닝). This is the single
highest-visibility copy the brand owns: it prints on a real person's card statement.

⚠ **Correction to the urgency, measured:** production has `payments = 0`, `billing_keys = 0`, `payments_live_since = null` — **nothing
has ever been charged, so no statement has ever printed it.** It is not bleeding now; it becomes real the moment charging flips, and
that is the deadline. Pinned by `_test/settle_charge_test.ts:311` and `_test/cancel_fee_test.ts:263`, so the pins move in the same
slice. Proposed: 「도그스하이 러닝 이용료」 / 「도그스하이 예약 취소 수수료」. **A** approve that wording and I run it under the money-path
gates (/autoplan + reviewer ≠ author, 0059 doctrine — it is copy, but it is copy on the charge path) · **B** different wording, say it
and I run the same slice · **C** hold until a server-domain session exists. Sibling, CLIENT-domain and already claimable by the live
client session: `app/app/runner/apply.tsx:655` has a runner consenting to safety terms as a 「**댕런** 러너」 — a legally-flavoured
consent naming a company that no longer goes by that name.

## 0-quinvicies. 🟡 ONE-WORD DOMAIN QUESTION — may the client session touch `supabase/` for ONE slice? (2026-08-20)

The deep-link slice (§0-unvicies) has two halves in two domains: the client half (`api.ts` keeping the extra field) and the SERVER
half (`HttpError` gains `detail`; `supabase/functions/_shared/ctx.ts:48` spreads it; the RPC carries a Postgres errdetail).
Both are unowned now that ui2 has ended. The live client session will take the client half and **declined the server half on its own
initiative** — its brief says client domain, never `supabase/`, and it would not let an announcer's routing widen that. Correct, and
noted as correct: `_shared/ctx.ts` is the error contract of **24** edge functions. **A** widen that session's domain for this one
slice (one sentence from you in its session does it; it still gets its own reviewer) · **B** it waits for a server-domain session
to come online. Nothing is blocked either way — the slice is a signpost-becomes-a-door upgrade, not on any critical path.

## 0-unvicies. 📋 QUEUED SLICE (nobody on it): refusals should carry an id, not just a token

Found by ui2 while wiring the account-deletion refusals: a 409 that says `club_custody_owner` tells the owner their dog is out but
not WHICH club session, so the client can only describe the screen in prose instead of deep-linking to it. The field cannot arrive
without `supabase/functions/_shared/ctx.ts:48`, whose error arm builds the body with exactly one key — and that file is imported by
**24 edge functions**, so it is the error contract of the whole project. Deliberately NOT bolted onto the 0115 round (already twice
extended, and its reviewer signed off on a smaller diff). Shape when it runs: `HttpError` gains an optional `detail`; `ctx.ts:48`
spreads it conditionally (every existing caller keeps its one-key body); the RPC carries the id as a Postgres errdetail, never inside
the message string (the client matches on the bare token); ui2 extends `fnError` (`api.ts:13-23`) to keep the extra field; its own
reviewer. Not on any critical path — a signpost becomes a door.

⚠ **Carry this into the slice's brief so it is not rediscovered (ui2):** the id cannot ride the MESSAGE (the client matches on the
bare token) and cannot ride a new top-level key TODAY (`ctx.ts:48`'s single-key literal). Both halves must move in the same slice or
the field silently does not exist — the failure that looks like "the server sent it and the client ignored it". ui2 owns the
`fnError` half — ⚠ that session has ENDED (2026-08-20) and the half is UNOWNED; its work is all on trunk through `93ca631`, nothing stranded (verified). Whoever takes the slice takes BOTH halves, or Sean names an owner.

## 0-vicies. 🟡 ONE-LINE LOOKUPS FROM UI2 (2026-08-20 morning)

1. **Your stale Aug-4 booking fixture** — delete it or keep it? It is on your account and it shapes what you see on the sim.
   **A** delete · **B** keep. (Not decided under the grant: it is your data.)
2. **Runner R6 return seal + R1c work-gate are NOT built** (ui2 measured the gap; server slice). Unowned — trust's surface.
   Nobody is on it; say if it should be tonight's/today's next server slice or wait for trust.

## 0-quatervicies. ✅ CLOSED — masthead spacing needs nothing from you (2026-08-20)

**Closed on measurement, not opinion.** The owning session pixel-scanned the CURRENT (`472c1b0`) owner-home frame — ink-band detection
on the raw 3x screenshot — and the gap between the centred wordmark and the alert line is **28 pt**, not the ~46–50 pt that made the
question worth asking: retiring the greeting took its own breathing plus one margin out of the sum. 28 pt between a masthead and the
first content band is ordinary breathing room. Second reason to close rather than re-queue: your brand-identity round will re-propose
the header treatment wholesale, so a standalone 20 pt decision now would be measured against a layout that may not survive the week.
If the brand round leaves the header untouched, that session re-raises it against whatever is true then. **The two judgement calls
stand** (profile avatar out of the row; `BrandLockup` retired) — the newer change restored neither. Original record follows.

⚠ **The state described below is `ede1b65` and Sean has since revised the header AGAIN — `472c1b0` retires the rotating greeting
entirely and centres the logo (mark + 도그스하이) on BOTH homes.** So the ~46 pt spacing A/B below was measured against a layout that
no longer exists; the announcer has asked the owning session whether the question survives the rebuild before Sean spends attention
on it. The two judgement calls (avatar out, `BrandLockup` retired) still stand — they were about elements the newer change did not
restore. Everything from here is the ede1b65 record, kept because its reasoning is still the reasoning.

Your header change is on trunk (`ede1b65`): one row now — BrandMark(30) · rotating greeting(flex) · bell(40); both wordmarks gone;
everything below moved up ~52 pt (measured on the simulator, not estimated); greeting 22 pt with minimumFontScale 0.65 so it can
never cross the 14 pt floor. ⚠ CORRECTED (the announcer got this wrong first): `BrandLockup` — the FUNCTION — is retired and has zero live references; the FILE `app/src/components/brandmark.tsx` is very much still on trunk and must be, because it exports `BrandMark`, which has three live consumers (`owner/home.tsx`, `runner/home.tsx`, `paper-btn.tsx`). The announcer's first check grepped for a filename that never existed (`brand-lockup`) and read the 0 as "file deleted" — a wrong measurement described confidently; caught by the session that did the work. Otherwise verified: `StatusBarCover` is still mounted last,
no absolute header was reintroduced. ⚠ **The announcer ALSO wrote that Black Han Sans is now used ONCE on that screen. That is FALSE** — the check counted `useDisplayFont` in `owner/home.tsx` the FILE, but a screen is a render TREE: `home-hero.tsx` calls the hook itself and applies it at :92, :169, :177 and :188, so owner home renders FOUR display-font uses and §3's "once per screen" law is violated 4× on the brand's primary screen. The masthead commits' real fix stands — deleting the lockup's second wordmark took the screen from five to four, not two to one. Found by the brand round's archaeology agent, verified by the announcer against the files. (Superseded text: the lockup wordmark had been a second use —
a design-law violation fixed as a side effect).

**The one call left is yours: ~46 pt still sits between the masthead and the alert line.** It is not a defect anyone introduced — it
is four small paddings summing (row breathing 9 + brandRow margin 6 + hero wrap paddingTop 12 + alertRow paddingVertical 12), each
part of the ⑧ v2 grammar you approved by number. Tightening it means editing hero internals, so the session stopped rather than
resolve it silently. **A** tighter — take the next ~20 pt out of the hero internals · **B** leave it as approved.

**Two judgement calls it made, each one line to revert if you disagree:** (1) the profile avatar left that row — you named three
elements and it was not one, it was non-pressable decoration costing the greeting ~2 pt of type (its now-dead `fetchMyProfile`
per-focus fetch went with it); (2) `BrandLockup` was DELETED rather than left unused — owner home was its only consumer, and "remove
the text logos" is poorly served by a file that still holds them; runner home's stale comment claiming the full lockup was the
owner's was corrected in the same slice. ⚠ Note for readers, not a defect: that commit's MESSAGE has three identifiers eaten by
shell backtick substitution; the tree is correct and the reasoning is in the file comments. It was deliberately not amended —
force-pushing a trunk three live sessions are on to repair prose is the worse trade.

## 0-novodecies. 👀 TWO SMALL LOOKS FROM UI2'S OVERNIGHT PASS (2026-08-20 morning)

1. **run.tsx R4 colour law:** the runner run screen has two corals (progress bar + strip) and a VOLT main CTA where lab 13 wants
   coral — the "one coral per frame" rule vs the lab; ui2 left it for you rather than guess. Pick by looking.
2. **Legacy feed posts read 「러닝 기록」 instead of 「완주」** — old `runs` rows carry no `endReason` on the post, so the honest
   label is the generic one; a server backfill from `runs.end_reason` would reclassify them if you want that. **A** backfill ·
   **B** leave as is. (Not decided under the grant: it rewrites what users already see.)

## 0-octodecies. 🟡 THREE ROUTE NAMES ADVERTISE A LENGTH THE LINE DOES NOT HAVE — a naming call, yours (catalog, 2026-08-20 ~04:00)

Measured across all 68 routes (handoff on trunk at 726838c): three original 0078 seeds carry a typed `km` the later-drawn geometry
does not match — `서리풀–몽마르뜨 종주 5km` km=5.0 measured 4.84 · `한강 반포–잠원 7km` km=7.0 measured 6.72 · `반포한강 그랜드 루프`
km=5.0 measured 4.78. **Not money** (catalog checked: `bookings.km` comes from the owner's dial, no server path copies `routes.km`)
— an honesty defect: the catalog advertises 5.0 for a 4.78 km line. The fix is blocked by design: 0100's `routes_name_km_agrees`
refuses `km` 5.0→4.8 unless the NAME changes in the same statement, so correcting two of the three means **renaming user-facing
course names** — catalog declined to do that on its own authority at 4 am, correctly. Your call, one letter per route or for
all: **A** rename the token to the measured length (e.g. `… 4.8km`) · **B** drop the km token from the name (must check the
unique `(town, name)` index first — 0100's 몽마르뜨 trio trap) · **C** leave as is. `반포한강 그랜드 루프` has no token and can
be corrected alone whenever. Not decided under the overnight grant: names are product copy you have ruled on by looking before.

## 0-septendecies. 🔴 NO IN-APP ACCOUNT DELETION — an App Store REJECTION waiting (legal, 2026-08-19 night) — building it tonight

`settings.tsx:89` says `계정 삭제 | 문의로 처리` — honest, and legally mild (PIPA 제37조 is satisfiable by a support path) — but **App Store
Review Guideline 5.1.1(v)** requires an app that creates accounts to let the user INITIATE deletion in-app; a "contact us" path is
the thing that guideline exists to reject. This app creates accounts (Kakao + email) and is headed for submission. Cheap now,
expensive when the build comes back from review. **Decision under the grant (🔵 O-6): build it** — server: a definer
`delete_my_account()` (party gate = auth.uid(); refuses while the user has an active booking/run/unsettled money; anonymises
what must be kept for ledgers/legal retention, deletes the rest, then removes the auth user via the admin path) under the full
cycle; client (ui2): the settings row becomes a real, confirmed, irreversible action per the honesty laws. Ranked ABOVE
§0-sexdecies because it blocks a submission, not a user. Legal also scored §13.2 (3 green / 4 partial / 4 absent — all in
`docs/legal/`); two reassuring corrections: runner consents ARE persisted and `not null` (0062:81-83), only the VERSION is missing
— build the location-consent gate versioned; owner-side consent has no record at all.

## 0-sexdecies. 📋 TWO SMALL BUILDS FROM LEGAL'S RETENTION ROW — statutory, not drafting (2026-08-19 night)

Measured by legal (docs on trunk): **(a) nothing purges `runs.trace`** — 17 crons, `purge-chat` and `purge-holds` exist, no
location TTL or job; the policy says "필요한 기간", and 시행령 제26조의2 caps 개인위치정보 at one year even with separate
consent. **(b) the policy promises the 위치정보 이용·제공 사실 확인자료 열람권 and no ledger exists** — 위치정보법 제16조 requires
automatic recording (≥ 6 months). Both are BUILD items, not wording fixes — softening §3/§5 deletes the evidence of the gap,
not the gap. Shapes exist in-repo: copy `gate_code_access_log` (0001:130) / `club_phone_access_log` (0049:156) for the ledger;
a cron for the purge with the pin on `cron.job` (0060:144 — a function sat unscheduled while a comment claimed it ran). Latent
today (one run, Sean's own); ranks ABOVE the 맹견 gate — matters at the first real runner. Queued for a server session /
announcer-directed build after O-4/O-5; nothing for Sean.

## 0-overnight. 🔵 DECISIONS TAKEN UNDER THE OVERNIGHT GRANT (2026-08-19 → 20) — each reversible in one word

| # | Item | Decided by | Decision | Basis (one line; full reasoning in the linked record) |
|---|---|---|---|---|
| O-1 | §0-undecies routes_public: logged-in = anon? | catalog | **A — authenticated treated exactly like anon** | a logged-in stranger is still a stranger; any Seoul owner can sign up |
| O-2 | §0-undecies trim distance | catalog | **least(200 m, 20 % of route length) per end**, one named constant | 200 m exceeds building-entrance scale; ~5 points/end at 42 m spacing; 20 % clamp keeps a 1.6 km route ≥ 60 % of itself |
| O-3 | §0-quaterdecies anchor 18 vs 44 pt | ui2 (surface owner) | **A′ as zoom-scaled VISIBLE anchors**: 18 pt zoomed out (clusters readable), 30 pt mid, 44 pt visible+tappable at street zoom; selected +8; dev knob removed; recorded in RULINGS 🔵 | measured on the sim: the Naver SDK's only invisible-hit-box path (custom React view marker) drops most markers on iOS (2 of ~10 rendered), so "44 hit area + 18 glyph" is not available; the lab frame shows it |
| O-4 | §0-decies D1/D2 pre-acceptance contact | announcer | **D2-narrow — BUILT + DEPLOYED as 0114 (2026-08-20 ~07:00)**: the nomination still reaches the runner (system push intact, verified live); free-text chat, reviews, notifications refuse pre-acceptance (42501); incidents get a wider reportable set (accepted + cancelled_owner + refund_pending — a party who WAS accepted may still report) with `booking_not_reportable` otherwise. Contract attacked (660/0) → implemented (694/0, eleven mutations) → reviewer ≠ author (FIX-FIRST docs-only → fixed) → wrapper deploy → DB-boundary + over-the-wire probe 12/12. **/cso #2 is now CLOSED for chat/reviews/notifications/incidents.** Residuals named in the forgery doc: the nomination card still renders four owner-authored strings (memo, tags, name/breed, `bookings.pace_label` — a body passthrough) → ui2 hides memo/tags/pace_label pre-accept (in flight); nomination push not rate-limited (adjacent). Client follow-up ui2: schedule chip, chat.tsx honest copy. | closes /cso #2's F2 (B-11) without killing the request flow; attacker-authored push/chat to a stranger is the harm, a system "요청이 왔어요" is the product |
| O-7 | 0115 `bank_accounts` vs a runner owed money (reviewer finding 1) | **Sean, 2026-08-20** | **A-intact-when-owed**: the bank row is deleted only when the runner has NO `ledger_items`; when they have earnings it is KEPT INTACT (not blanked — a redacted account number is a row nobody can pay into), on the same retention basis as the ledger, ending when they are paid. No balance gate: "unpaid" is uncomputable (no paid marker, no payout writers), and a gate on lifetime earnings could never clear — trapping the runner and re-opening App Store 5.1.1(v). | asked "what's best for the runner"; measured answer: they can always leave, they cannot silently forfeit, and the money still has a destination |
| O-5 | pay-after-run server mechanism (Sean's ruling af02f12; ui found it is a state transition in a payment costume) | announcer | **BUILT + DEPLOYED (2026-08-20 ~05:30):** contract → attacked (FIX-CONTRACT-FIRST on the client half) → v2 → implemented (Deno 203/0, 3 mutations) → catalog reviewed ≠ author (LAND-AND-DEPLOY, independent 203/0) → `transition-booking` v34 + `create-booking-hold` v10 live → verified by self-cleaning probe: widget hold → `matching`; `payment_ok` gone; same-dog second hold → 409 (P8). While `payments_live_since` is NULL every hold lands in `matching`; post-flip card-less → 409 `card_required` pre-write; settle already charges only after the return handoff is sealed — exactly where Sean put payment. **Client half LANDED (ui2, 5638037 on trunk, verified by the announcer):** the four post-hold moves in request.tsx (draft.bookingId → createRecurringSeries → requestRunner → route), no push to /owner/pay, CTA "러너 찾기 ›", confirmPayment deleted, pay.tsx confirm path removed (read-only charge view kept for dev/pay-lab). **O-5 is closed end to end.** Smoke line for Sean's build: "러너 찾기 ›" → radar with the new booking; 매주 반복 + 지명 now fire from request.tsx; an OLD build shows a benign 예약이 확정됐어요 with neither — that is the build being old, not a bug. Flip-day in-flight stock named for the money session (§C.3a). | it touches the money state machine; no code before a reviewed contract |

Owner for O-4/O-5: announcer-directed subagents under the full cycle (trust/money offline). Numbers: re-resolved from origin at write time (0112 is next free at this write; catalog's trace revoke also needs one — whoever writes the file first claims the row in the same breath).

## 0-terdecies. ✅ RULING #14 — on origin at e13b579 (`docs/labs/RULINGS-2026-08-19-journey.md` #14, verbatim; relayed first via ui2, verified by the announcer) — pickup point → nearest point on the route

ui2 reports Sean ruled in its session, verbatim as ui2 recorded it: *"pick up point should be wherever
the home owner puts, and the app should recommend the nearest path. the runner should start at the put
starting point and should be led by the app to the nearest point in the path from that starting point,
from which then on the runner will start the lap."* **[end of his words]** — on origin at e13b579, verified. ui2 takes the client side
(route ranking by nearest point ON the trace; approach leg pickup→entry; lap rotated at the entry;
onboarding leads to the address pin); no server change claimed; route geometry asked for the routes-side
read (catalog offline). Nothing for Sean unless a server angle appears.

## 0-quaterdecies. 👀 THE 18 vs 44 pt ANCHOR LAB IS PUBLISHED — pick by looking (ui2, late 2026-08-19)

https://claude.ai/code/artifact/baed214a-80ff-4741-9ca9-d197d76755b0 · `docs/labs/anchor-tap-target-lab.html`.
Options as drawn: **A** / **B** / **A′**. The 44-pt line was the previous announcer's inference, not your
ruling — you asked to see both; this is both.

## 0-duodecies. 📋 SMOKE-LIST LINE for your first hardware build (legal, 2026-08-19 evening) — not a decision

`private_only=true` is live at the project level, and the client change that makes all four channel
families request private (`REALTIME_PRIVATE`, `setAuth`, `geo.ts`) is on trunk — **but in no built
app yet.** So a build predating that change has no working realtime at all: it joins public, the
server refuses public, and live map + chat + booking-status die together. Shipped population is
zero, so no user is harmed — but your hardware smoke test will hit exactly this if the build is old,
and it presents as a mystery outage across three unrelated features. **Smoke list:** *realtime needs a
build containing the private-channel change (f106b2b or later); on an older build, chat / live map /
status all dead at once is the flip working, not a regression.*

## 0-undecies. 🟡 Two calls inside catalog's `routes_public` slice — trim distance, and whether logged-in strangers are strangers (catalog, 2026-08-19 evening; recorded by announcer v3)

–––––REPORT–––––
**Catalog measured** (`has_column_privilege`): anon can still read `routes.trace` and `trace_thumb`
directly at full 6-decimal precision (~11 cm). 0107 shut the identity columns correctly; geometry was
never in its scope. So the de-identified `routes_public` view alone would satisfy 0107's promotion
gate while every reader can still bypass it — the moment a route is promoted from a settled run,
`routes.trace` becomes a recording of where one identifiable person walked one dog, endpoints at pickup
and dropoff. Catalog's fix is three ordered steps (0110 view + a second fail-closed refusal in
`promote_route_from_run` while anon holds select on trace → ui switches reads to the view and ships →
0111 revokes trace/trace_thumb from anon+authenticated). That sequencing is engineering and is
handled. **Two things inside it are yours:**

1. **How far from each end of a public route to trim.** Precision (4 dp ≈ 11 m) is derivable and
   catalog derived it. Trim distance is a judgement about how much of a route's start may be public.
   Catalog will default it in one named constant and flag it; you confirm or set a number.
2. **Should a logged-in user be treated like anon for route geometry?** A logged-in stranger is
   still a stranger. **A** = yes, same de-identified view for everyone (catalog's lean, and the
   safe default) · **B** = no, authenticated may read full geometry.
–––––[end of report; catalog's analysis, not your ruling, until you answer]–––––

## 0-septies-bis. ✅ RETRACTED BY SEAN — no per-migration approval; full speed governs (2026-08-19)

**Sean, 2026-08-19, verbatim:** *"i never said 'work locally first, do not push migrations
without my explicit approval.' dont ask me for permission. im gone for break. full speed on
the app."* **[end of Sean's words]**

The earlier "work locally / no db push / no dashboard without approval" line the announcer
relayed as a constraint is **withdrawn by him and must not be cited.** Standing rule for every
session: **gates, not permission.** Harness green + /autoplan on migrations + trust plan-time
review + commit gates → deploy. Land on trunk BEFORE deploying (0098/0099 lesson). Trust's
0103 deploy was correct under this rule. Dashboard toggles remain his by nature (his account),
not by permission — they are in `docs/security-dashboard-checklist-2026-08-19.md` for whenever
he is back.

## 0-novies. 📋 LEGAL'S PRIVACY-POLICY BAR — RELEASED, NOT APPROVED (2026-08-19)

Legal set one blocker: `privacy-policy.md:81` promised location goes to the booking's owner only,
so the policy could not publish until the channel was private. **That sentence is now true; that
specific bar is lifted — by legal, in its own words.** Nothing else is released, and this line
exists so nobody reads "legal cleared the privacy policy" off a queue: the draft is unreviewed with
no 시행일; there is still no separate 위치기반서비스 이용약관 (required as its own document); the 신고
is not made; §5 retention still says "필요한 기간," which is not a period (위치정보 caps at one year
even with separate consent). **A released blocker is not an approval.** Open, waiting on counsel:
the statutory consent gate ahead of `geo.ts:199` and the 이용약관 split.

**✅ SETTLED — Sean, 2026-08-19, verbatim: *"s4kim2025 is my account."*** [end of his words] So the
only data subject on the public channel for those 25 days was the operator himself; counsel can be
told it as fact. (Measured: 9 runs, one owner = one runner = `aa73ce8a…` = `s4kim2025`.)

## 0-octies. 🔴 TWO DASHBOARD TOGGLES, ONE VISIT — the only door into the app is wider than it should be

**Written by trust, 2026-08-15, crossing a lane on purpose and saying so.** This file is the
announcer's. That session **ended while holding both of these items**, having told me they were
"in front of Sean now" — they never reached the file. That is verbatim the failure this queue's
own header exists to prevent: *an in-conversation queue evaporates, and it evaporates silently,
because nobody knows to look for a list they never saw.* So I am writing them in rather than
being the second session to hold them in a conversation. Both are measured; neither needs a
model's judgement; both are the same screen in the Supabase dashboard.

**Both are ALSO pinned now**, so they cannot rot: `supabase/auth-surface.expected.json` records
the current state and `node scripts/check-auth-surface.mjs` (from `app/`) reddens on any change.
**When you flip either one the check goes RED, and that is how we find out — not by being told.**

### ① Email signup is still open on the server (your `"b"` ruling is half-applied)

`Auth → Providers → Email → disable`.

You ruled Kakao-only for the pilot. ui removed the email door from the app and verified it. **The
server never changed**, because nothing in this repo configures it — measured live:
`external_email_enabled: true`, `disable_signup: false`. Anyone can create an account with one
request using the public key that ships inside every build. **A door removed from the client is
not a door shut.**

**Risk of flipping it: none, measured.** 9 accounts use email — **8 are the marked test fixtures**
and the 9th has no profile row, no dogs, no bookings, and has never signed in. **Your own account
is Kakao** (`aa73ce8a…`, verified). Zero real users affected.

⚠ **Do NOT let anyone "fix" this with `supabase config push`** — our `config.toml` declares no
auth at all, so it would push CLI defaults for every setting it omits **and switch off Kakao.**

### ② The OAuth redirect allowlist accepts any Expo host

`Auth → URL Configuration → Redirect URLs`. Live right now:

```
daengrun://login          ← keep
daengrun://**             ← wildcard on our own scheme
exp://**                  ← 🔴 ANY Expo host
exp://10.16.75.70:8081/--/login     ← a dev machine's LAN IP
exp://172.30.1.44:8081/--/login     ← another
```

In an OAuth flow **the redirect URI is where the session lands**. `exp://**` means Kakao can be
told to deliver a completed login to any `exp://` target: a crafted link, a real Kakao sign-in by
the victim, and the session arrives at someone else's host. A textbook open redirect — **on what
becomes the only door into the product once ① is done.**

**Calibration, deliberately not inflated:** it needs a crafted link, Expo Go installed, and the
pilot user set is tiny. **A launch item, not an incident.** But `exp://` entries have no business
in a production auth config, it is free to fix now, and it is expensive to find later.

**Fix:** delete `exp://**` and both LAN-IP entries, keep `daengrun://login`. Dev machines get
re-added while developing and removed again — that is what makes them dev entries.

## 0-nonies. 🟡 A price change would repay old work at the new rate but still charge the old — money policy, yours

**Raised by money (`0101`'s author), written up by trust at their request so the person flagging
it is not the author of the code it indicts.** Verified in source before writing, because this
file is the one place a wrong claim does the most damage.

**The two sides of a run are priced from different clocks.**

- **What the OWNER is charged** comes from columns frozen onto the booking when they booked —
  `b.base_fare`, `b.addon_fare` (`0080:285`). Change prices tomorrow and their bill does not move.
- **What the RUNNER is paid** comes from constants written into the payout function —
  `RUNNER_COMP_BASE := 9900`, `PER_KM := 3000` (`0101:92-93`). Change those and **every run not yet
  settled is paid at the new rate**, including runs that happened before the change.

**So a price revision retroactively repays completed-but-unsettled work at the new rate while
leaving what the owner was charged for that same work frozen. The platform absorbs the
difference, silently and in whichever direction the revision went.**

**Deliberately not dramatised, because the mechanism makes it smaller than it sounds:** those are
hardcoded SQL constants, so changing them takes a migration — through `/autoplan`, the harness and
review — not a dashboard toggle or a config edit. Nobody changes runner pay by accident. And with
charging off and 9 fixture runners, nothing is live today.

**Why it is on your queue anyway, and why now rather than later:** this is not an engineering
defect, it is a **policy question about work already done**, and it only has a cheap answer
*before* the first price revision. Afterwards it presents as a reconciliation mystery — payouts
that do not reconcile against charges for the same runs, discovered by whoever is closing the
books.

**The question, in one line: when we change prices, should a run that already happened but has
not settled be paid at the old rate or the new one?** Either answer is defensible and neither is
ours to pick. A third option exists — freeze the runner rate onto the booking the way the owner's
is — which makes the two sides symmetric and answers the question permanently, and is a real slice
rather than a toggle.

## 0-septies. 📋 RECORD — PR-0's test-owner exclusion exists in practice and is written nowhere

Owner `aa73ce8a-0ee0-473f-af1c-ffa8030a09a9` holds **all 24 existing bookings** and PR-0 reads
zero — so the exclusion is already applied by your judgement and is simply undocumented. Needs no
migration: a recorded owner id + a documented count query. One line from you confirms this is the
flagged-test-owner policy, and then it gets written into the PR-0 doc.

## 0-octies-bis. (renumbered by the announcer 2026-08-20 — this id was used twice; content unchanged) /cso AUDIT 2026-08-19 — P0 status: 1 CLOSED (GPS), 2 CLOSED (drops), 1 IN REBUILD (booking) — none need Sean

Full JSON at `.gstack/security-reports/2026-08-19-cso.json` (local). Owners already messaged;
recorded here so nothing lives only in chat.

- **CRIT — runner live GPS is a public broadcast channel.** STATUS 2026-08-19 late: **`private_only=true`
  FLIPPED (management API, re-read confirms). Legal's 4-cell matrix + original probe re-run against
  production post-flip: stranger CHANNEL_ERROR on every cell, both modes, both topic shapes. Prereqs
  landed first: 0108 (chat/bk/club-chat realtime policies, adversarially reviewed) applied; ui client
  9012d7a makes all four families private+setAuth; forced-upgrade population = 0 (no build ever
  shipped). Legal re-ran both scripts independently (same result) AND ran the control that
  distinguishes shut from dead: same anon key, REST read → HTTP 200 — key valid, project up, the
  refusals are real authorization decisions. **Exposure window bounded (measured, prod):** channel
  public 2026-07-25 → 08-19 (25 days); 9 runs carried location, ALL with runner = owner = the same
  account, and that account is `aa73ce8a…` = `s4kim2025` — Sean's confirmed test account. **No third
  party's location was ever on the channel; real data did traverse it (say it that way, not
  "population zero").** **✅ CLOSED 2026-08-19 — both instruments, one run, production.** Positive arms (ui, raw): party
  channels 6/6 (owner receives chat + bk; stranger private=false → CHANNEL_ERROR, was SUBSCRIBED);
  run channel 21/21 (owner receives runner's position; old-style public client → CHANNEL_ERROR;
  attacker public publish → cannot even connect, `send false`; anon/unrelated/loser/former runner
  all CHANNEL_ERROR); club-chat verified on the simulator as host s4kim2025 on a8791733… — a
  service-inserted row appeared live through the private channel, no refresh. Negative instrument
  (legal, independent re-run + shut-vs-dead control): all cells CHANNEL_ERROR with the same anon
  key returning REST 200. Closure statement: **the unauthorized operation is rejected at the
  realtime boundary.** Earlier honest line kept
  for the record: **server half correct and live (0103/0104), client half shipped (`f106b2b`, all run
  channels private + setAuth, 16/16 with mutation check) — but the channel is STILL publicly
  joinable by any client that asks for `private:false`, on any topic name; measured post-0103 by
  legal.** New-binary owner↔runner traffic is isolated from public subscribers (measured: public
  subscriber receives nothing). Old binaries still publish publicly (forced-upgrade leak).
  **Closure = project setting `private_only=true`** (management API `UpdateRealtimeConfigBody`;
  omitted from GET when unset, which is why an earlier read missed it), sequenced AFTER
  chat/bk/club-chat get realtime policies + private client joins, or those die. → **trust
  (policies + flip) · ui (client) · TestFlight = Sean's 2FA (physical, cannot be delegated).**
  Ordering: `docs/legal/privacy-policy.md:81` cannot publish until the flip lands.
- **HIGH — `bookings owner insert` forges party status** (any dog, any runner) → push text to
  any runner, fake public review, chat, dog read. Executed, rolled back. → **trust.**
- **HIGH — `drops` UPDATE unguarded; open-drop pays from it.** ✅ **CLOSED 2026-08-19** — 0106
  deployed (615/0, 12 mutations, adversarially reviewed); the exact attack live post-deploy →
  `permission denied for table drops`; open-drop's CAS still works. Rejected at the DB boundary.
- **Dashboard (Sean, minutes):** email provider OFF · redirect allowlist → `daengrun://login` only.
- ✅ **CLOSED 2026-08-19 — 0107 deployed** (600/0, 9 mutations, catalog's four pre-push catches +
  chained-view transitive walk folded in): three identity columns (`verified_run_id`,
  `verified_runner_id`, `checked_by`) revoked from anon+authenticated at the column level, whitelist
  of the 17 the app reads granted; verified OVER THE WIRE as anon — app's column list 200,
  `verified_runner_id` 401/42501; promotion raises until a de-identified `routes_public` exists.
  (`checked_at` stays granted — the app renders it.) Was: four route evidence columns anon-readable (`verified_run_id`, `verified_runner_id` → profiles, `checked_at`,
  `checked_by`) and LOAD-BEARING for `routes_active_is_earned` — **revoke/view, never drop.**
  No route may be promoted until closed. Legal's find; every value NULL today.

## 1. 🟢 CLOSED IN PRODUCTION 2026-08-14 — off your queue, nothing to decide

> **🟢 is not ✅ and must never be read as one.** ✅ in this directory means *Sean's own words are
> on origin*, and nothing else earns it. 🟢 means *a fact this entry asserted has changed, and the
> change was verified by execution.* No ruling of yours is recorded here, because none was needed
> in the end — the thing this entry was waiting on stopped being true.

**What was checked, by whom, and when.** Three independent measurements against the live project,
2026-08-14, all agreeing:

| check | result |
|---|---|
| `set local role anon; select count(*) from profiles` | `ERROR 42501: permission denied for table profiles` |
| `GET /rest/v1/profiles?select=phone` with the app's shipped public key | **HTTP 401** |
| `authenticated` column grants on `profiles` | exactly `0088`'s whitelist — `avatar_url, district, handle, id, name, role`. No `phone`, no `toss_customer_key` |
| `GET /rest/v1/available_runners` | **HTTP 200** — the storefront survived the revoke |

Measured by the trust session over both SQL and HTTP; independently by the announcer session; and
by the money session, which wrote it up in `docs/security-profiles-column-exposure.md`. The HTTP
leg matters more than the SQL leg: it is the exact path an attacker has, and `profiles` refusing
the same key that `available_runners` accepts is what makes it authorization rather than a broken
probe.

**Why it closed without you.** `0088`+`0091` were applied to production as part of the
`0088`–`0094` batch; the deploy call this entry was blocked on was overtaken by the deploy
happening. **This entry outlived the condition it described by about a day**, which is the exact
failure the return queue exists to prevent — it is the first thing you are told to read, and until
now it asked you for a go-ahead on an exposure that was already shut.

⚠ **One claim inside the original is FALSE and is corrected here rather than deleted.** It argued
*"every build that has ever existed is compatible"* because every historical `profiles` SELECT was
a subset of `0088`'s whitelist. The reasoning was sound and the conclusion was wrong: `0088` omits
`SELECT` on `role`, and PostgREST's role-picker upsert reads `excluded.role`, so `0088` alone
**403s every signup**. `0091` grants it. The corollary was disproven the same afternoon it was
written — see `README.md` rule 3, which still holds it up as an exemplar and should not.

<details>
<summary>Original entry, preserved — it was accurate when written</summary>

**Corrected upward 2026-08-13; my first version of this entry understated it.** I wrote "every
logged-in user can read every verified runner's number." Authentication was never part of the
gate. `0002_rls.sql`, verified on trunk:

```sql
create policy "profiles public runner read" on profiles for select using (
  exists (select 1 from runners r where r.profile_id = profiles.id and r.tier <> 'applicant')
);
```

**No caller term at all** — it is a pure row predicate, so it matches for `anon`, the role the
app's **public, shipped-in-the-client** key maps to. The anomaly is visible in its own file: the
other three `profiles` policies (`self read`, `self write`, `self insert`) each carry
`auth.uid()`. The payments session executed it against the real schema and got **101 runner rows
returned to `anon`, including `phone` and `toss_customer_key`.**

**Both halves, so the record is neither scarier nor softer than the truth:**
- `phone` may be **null in practice today**, because PASS looks unintegrated. That is a **stay of
  execution, not a defence** — the hole is open, and the day anyone backfills numbers it becomes
  a live PII leak with no further change.
- `toss_customer_key` is **populated on every row regardless**: `0076:65` adds it
  `not null default gen_random_uuid()`, and 0076's own header argues that identifier must never
  leave our tables.

**UPDATE 2026-08-13: the P0 is DECOUPLED from the cutover, and its last unknown is DISSOLVED.**
`0088` is on trunk and its `revoke` + column grants depend on nothing after `0074`, so **the anon
exposure can be closed without deploying the payment system** — which was this queue's sharpest
tension.

The remaining worry was *"which client build is live, and what columns does it read?"* — which
has no local answer (there is no EAS/OTA record here). The payments session replaced it with a
question that does: they enumerated every `profiles` SELECT in **every commit that ever touched
`app/`**. Five distinct projections, all a strict subset of `0088`'s whitelist. **So it no longer
matters which build is live — every build that has ever existed is compatible**, including a user
on a months-old binary. Independently verified: the only `toss_customer_key` hit in `app/`
history is a comment on an interface field, not a read; writes chain no `.select()` so the grant
is never consulted; every read filters on `id`, which is in the grant; and `role` is written but
never read.

**So this is now purely your go-ahead** — nothing left to establish first.

**The decision was deploy timing, not whether to fix.** The fix is built and verified on the
payments branch (harness 477/0) and cannot ship until `db push` is cleared — which is held while
Sean is away, per rule 4. So: **open in production since `0002`, closed on a branch, blocked on
his deploy call.** Explicitly his and not a stand-in's, since it trades a live exposure window
against deploying unreviewed-by-him migrations.

</details>

## 1-bis. 🟡 What should a logged-out person see at all? — CORRECTED 2026-08-14, the severity was wrong

> **⚠ This entry originally claimed "the day a host lands in that view, a logged-out stranger reads
> a named person's meeting place and time." THAT IS FALSE and the announcer published it.** Trust
> wrote the memo, the announcer queued it faithfully, and neither ran the query first. Trust's own
> `/autoplan` review challenged the severity claim, which is what finally produced the measurement.
> Original reasoning preserved in [../security-club-session-exposure.md](../security-club-session-exposure.md) (corrected in place at `79a5b06`).

**Measured on production, 2026-08-14:** `club_sessions` is 13 rows · **1** host · **1** club · 6
places · `scheduled_at` spanning 2026-07-30 → 2026-08-08 · **0 rows in the future.**

Every exposed session is in the **past**. There is no gathering to intercept. The real disclosure
is *"where this one club met last week"* — a listing, not a stalking vector.

**The other half cuts the opposite way and must stay, or this reads as falsely reassuring.** The
name-join was said to fail; it fails against `available_runners`, but the host joins to `runners`
**today** — and `runners` is anon-readable: **9 rows, 7 with free-text `bio`** (and see §0-ter).
`club_members` and `feed_posts` sit behind the same `using (true)`.

**So the question is narrower and still yours: should a logged-out person browse clubs at all?**
A revoke closes it in one line and may delete a real acquisition surface, which makes it a growth
call rather than a security one.

- **Revoke** — club discovery requires an account.
- **Keep, minus the sharp fields** — browse survives; `meetup_point` and host ids need a session.
- **Keep as-is** — a recorded acceptance rather than an inherited default.

**Not urgent on today's data, and there are TWO separate thresholds — don't merge them.**
A **future-dated session** makes the place and time live: someone could show up. A **host
appearing in `available_runners`** makes it a *named person*; today `runners` carries no name
column at all, so anon has a UUID plus tier/bio/stats and nothing else. Neither holds now, and
they can arrive independently. (Two-threshold framing: trust, 2026-08-15, measured — collapsing
them is how this entry would re-acquire the exact claim it retracts.)

⚠ One soft channel, a stay of execution rather than a control: `bio` is unvetted free text on 9
anon-readable rows, and nothing stops a host typing their own name into it. Measured today: 0
bios contain their owner's name. Same shape as §1's phone-was-null argument.

⚠ **The detector that missed this is fixed in REGISTRY:** trust grepped for policies lacking
`auth.uid()`, and `runners` reads `tier <> 'applicant' OR profile_id = auth.uid()` — **a caller
term in one arm of an OR is a disjunct, not a gate, and grep cannot tell them apart.** Replaced
with a privilege-based enumerator (`has_table_privilege`) that also covers views, which
`pg_policies` never returns at all.

## 2. 🔴 ⑪ conflicts with a written privacy commitment — before ⑪ builds

`docs/appstore-privacy-answers.md:27` declares the phone number's purpose as **"contact during
handoff"**; ⑪ exposes a counterparty's number **during an incident**, which is broader — an
incident is not a handoff. **Scope settled 2026-08-13:** Sean narrowed it himself to *"during
those emergency situations"*, so the amendment needed is small and specific ("handoff **and
during incidents**") rather than the open-ended one an *"at all times"* reading would have
forced. Two
questions, in order: **has that questionnaire been filed with Apple yet** (it reads as
pre-submission, but "reads as" is not a check), and **the declared purpose must move before ⑪
ships** either way — that file states its own re-audit rule and ⑪ trips it. Detail in
[incident-verification.md](incident-verification.md) §0.

## 3. 🟡 The 안심번호 trade-off — his to confirm knowingly

Now a narrower and much cleaner question, since the scope is incident-only: **a masked relay
during incidents specifically**, not a blanket policy. Departing from the Korean norm (Kakao T's
pattern) is defensible for a pilot, but it should be **confirmed, not inherited from a build
decision**. `docs/feature-audit.md` already
discusses 안심번호 — prior art to read rather than re-derive.

## 3-bis. ✅ ⑬ chat now reaches a phone — BUILT 2026-08-13 (0090, harness 510/0)

Shipped: a trigger on `chat_messages` writes the other party a notification, which the existing
0024 trigger turns into a push. **Both small product calls were made deliberately and are his to
overrule in a sentence**, not open questions: the push carries **no message text** (who + which
run only — 0024 puts bodies verbatim on a lock screen, and in an incident that phone gets handed
around), and it sends **one nudge per unread state** (reading it re-arms, so a back-and-forth is
one push). Details in [chat-notifications.md](chat-notifications.md).

## 4. ✅ ⑫ — RULED IN FULL 2026-08-13 (no longer waiting on him)

Does a marketplace incident get its own settle path or become a second caller of 0072's
adjudication · is the runner paid while it is open · what ends the state. Codex's analysis is now
attached to [marketplace-incident-exit.md](marketplace-incident-exit.md) as **🔵 CODEX** (status
stays 🟡). It answers all three and then **explicitly refuses one**, which is the question to
put to Sean first: *when both sides verify an incident but fault is unresolved after the SLA,
should the platform absorb a normal measured runner payout at owner ₩0?* Codex recommends yes
and declines to encode it, because it is a deliberate platform loss outside 0072's model. This is the same class as G1, where he overrode both sessions'
recommendations with a third option neither had proposed.

## 5. ✅ ⑪ + ⑫ ASSIGNED 2026-08-13 — one slice, to the run-end-flow session

Assigned by the coordinating session (Sean delegated assignment) to **run-end-flow**, which owns
the custody/return machinery. They are **one slice, not two**: ⑫'s exit condition — both sides
confirming the dog — **is** ⑪'s two-stamp machine, so building ⑫ without ⑪ means building a gate
with no way to clear it. That is a dependency, not a sequencing preference.

## 6. ✅ `profiles.phone` — ESTABLISHED 2026-08-13, and the hopeful half was wrong

Not a decision, a fact, and it is now measured rather than guessed. **`profiles.phone` is NULL
for every user** — PASS is unintegrated and nothing else writes the column.

**The "real data may live on the application" hope does not survive checking.** This item cited
`0062_runner_applications.sql:380` as declaring `phone text not null`; line 380 is inside the
approval RPC's `update` block, not a column definition. The actual column is `0062:79`
`contact_phone text check (contact_phone is null or contact_phone ~ '^01[0-9]{8,9}$')` —
**nullable** — and `0062:97`'s `runner_app_contact_present` requires **kakao OR phone**, so a
runner can be fully approved having given only a KakaoTalk ID. The approval RPC also does not
copy it to `profiles.phone`.

**Consequence for ⑪, and it inverts the design:** a number-present incident screen is the
exception and a number-absent one is what actually renders today. `incident_contact` returns a
row with a NULL `phone` rather than zero rows — the join succeeds — so the UI knows WHO the
counterparty is and lacks only the number, which is why the empty state can still name the
person and offer 채팅. Both states are drawn in
[run-end-incident-lab-v2.html](../labs/run-end-incident-lab-v2.html) (⑪-P1 / ⑪-P2).

## 7. 🟡 Deploy go-ahead — `db push`

Everything money-related built today (0080, 0081, 0084, 0085, 0086…) is **inert** until
`ops_flags.payments_live_since` is set, and nothing is deployed: no `db push`, no
`functions deploy`. Gated on his 사업자등록 → 통신판매업 → Toss chain (with 자동결제 심사 in the
same application) regardless, plus billing TEST keys and the §4-2 sandbox matrix.

---

## 8. ✅ ⑩'s "reward them" — CLOSED 2026-08-13

*"reward was about tone."* No points, no ledger award, no currency to design — the half-fee is
the reward and the notification's voice carries it. ⑩ is complete, not "built with a gap".
Reasoning kept in the memo so nobody re-opens it as an unbuilt feature.

**Also standing, from ⑩ and ④:** the club-premium disclosure line (④ requires it before
cutover — his wording), and the counsel question on 빌링키 charge-notice obligations (②'s
go-live gate). Both are in their own memos; listed here so the return sweep is one file.

**Maintenance:** whoever adds an item puts it here rather than in a message. Remove an item only
when its memo carries the ruling — not when it has been discussed.

---

## 9. 🟡 What does an owner SEE when no card is registered — and it is now the pilot's default

**Written in by money 2026-08-15, crossing the announcer's lane on purpose and saying so.** The
announcer session told me it was surfacing this as a product call. It then ended, and the item was
never in this file — it existed only inside that conversation. That is verbatim the failure this
file's own header describes: *an in-conversation queue evaporates, and it evaporates silently,
because nobody knows to look for a list they never saw.* Trust found the same thing with two of
its own items and wrote them in as §0-octies; this is the third. **Not a criticism of a session
that is gone — a demonstration that the rule it wrote for others applied to it.**

**The decision.** `billing_keys` is empty: **zero owners have a card registered**, and under your
`4: A` ruling the pilot runs on manual transfer while the paperwork chain proceeds. So the
"no card registered" state is not an edge case to handle — **it is what every owner sees, every
time, for the whole pilot.**

The screen today says `준비 중` and stops there, which is honest but says nothing about how anyone
actually pays. **What should it say?** That is copy and product, not engineering, which is why it
is yours:

- how a 보호자 is told what they owe, and when
- whether the app shows an amount at all before there is a payment to point at (my constraint: if
  it shows an amount it must say what happened to it — an amount next to a date on a screen called
  결제 관리 reads as a receipt whether or not the word appears)
- whether transfer details live in the app or stay in a message from you

**What is already decided and does not need re-deciding:** the facts the screen may assert are
written down in `docs/pre-charging-checklist.md` §4-bis, and the ui session is building against
them. Nothing is charged by any path · no card is stored for anybody · **the runner genuinely is
credited** (`ledger_items` has real rows) so no copy may imply the runner went unrecorded ·
manual transfer is the pilot rather than a fallback.

**Not blocking anything of money's.** It blocks the ui slice from being finishable, and it is the
last honesty gap on the payment surface.

## Not queued, but adjacent — a class-wide RLS question worth its own memo

Applying `0088`'s lesson across every migration turns up **~20 `for select` policies with no
caller term in their `USING` clause**. Some are false positives — `runs`, `chat_threads`,
`chat_messages` use `is_booking_party(...)`, which gates the caller *inside* the function. But
roughly ten are literally `using (true)`: `feed_posts`, `feed_likes`, `feed_comments`, `clubs`,
`club_members`, `club_series`, `club_sessions`, `runner_gear`, `runner_availability_rules`,
`routes`. **Most are probably public by design and nobody has verified which**, because the
answer requires executing `select *` as `anon` against the real schema rather than reading
policy text — a static column check produced results its author explicitly did not trust.

Routed to the payments session with the right suggestion attached: make it a **pinned harness
test** rather than a one-time audit — every table's anon-visible column set asserted, so a new
`using (true)` reddens instead of relying on someone repeating the audit. The same
convention→constraint move as the pre-push hook.

---

## §0-septvicies · 지난 예약(past-time confirmed booking) — Sean ruled A, server slice owed

**Sean, 2026-08-20, in-session:** asked *"so what happens when it's past reservation time? what
does that mean? how many minutes after? this is a new scenario."* — and he was right that nobody
had designed it. He then chose **A: grace window + server expiry**.

### What is true today (measured, not assumed)

1. **The threshold is midnight, not minutes.** `home.tsx` computes
   `nextIsPast = kstDayDiff(scheduledAt) < 0`, and `kstDayDiff` compares KST *calendar day boxes*.
   So a 15:30 booking is still "upcoming" at 23:59 the same day (8.5h late), while a 23:50 booking
   flips "past" at 00:01 (11 min late). The trigger has no relationship to the appointment.
2. **Nothing on the server resolves it.** `expire_unmatched_bookings()` (0017) touches only
   `matching` and `runner_pending`. A **confirmed** booking whose time passed stays `confirmed`
   forever — no cron, no state change. (`home.tsx` already carries the note "confirmed엔 만료 크론이
   없다 — 리뷰 P1".)
3. **The only owner remedy costs money.** `cancel_owner` accepts `confirmed`, and the fee ladder is
   0 at ≥24h / **10% inside 24h, half of it the runner's** (0085). A past-time booking is by
   definition inside that window, so "just cancel it" may charge the owner.

### Client half — SHIPPED (this commit)

Home no longer implies free cleanup. Copy is now 「예약 시간이 / 지났어요」 + 「{when}에 시작하지
못했어요」, the button reads 「예약 확인 / 아직 정리되지 않았어요」, and it takes the **amber**
ground (= `paper.pending`'s wash) because the state is *unresolved and needs attention* — which
also fixes two same-coloured buttons sitting on top of each other.

### Server half — OWED, needs a server-domain session

- **Grace window.** Proposed **scheduled_at + 30 min** (a run is 30–60 min; if no handoff has
  happened 30 min in, something is wrong). Not shipped as a number anywhere yet — Sean's to set.
- **Terminal state.** `confirmed` → `no_show` / `expired_confirmed` past the grace window, so the
  row stops being "upcoming" for both sides.
- **🔴 MONEY RULING REQUIRED, Sean's alone:** when a confirmed booking simply never starts, who
  bears it? Owner charged the 10% (as a late cancel)? Runner compensated (half, per 0085)? Both
  zero (nobody showed, nobody pays)? **The client cannot show a resolution until this is decided**
  — any button we draw would promise an outcome the ledger has not agreed to.
- Until then home states the fact and routes to 일정; it promises nothing.

### ⚠ CORRECTION to §0-septvicies (same day) — Sean's question invalidated half the spec

**He asked:** *"what does a late but confirmed run mean? to be a confirmed run, what conditions
are necessary? has the runner already come to the starting point? if so, there cannot be a
run-expiry thing as the runner is already there ready for the run."*

He is right, and the spec above was written against a label instead of the state machine.

**The client's `confirmed` is a MERGE of two server states** (`api.ts` STATUS_MAP):

| DB status | maps to | what is actually true |
|---|---|---|
| `confirmed` | client `confirmed` | a runner accepted. **Nobody has set off.** Can be days early. |
| `runner_enroute` | client `confirmed` | runner is travelling; `arrived_at` stamps when they get there |
| `picked_up` | client `handoff` | **both sides already confirmed the handoff** — the dog is with the runner |

So "late but confirmed" is currently ambiguous between *nobody came* and *the runner is standing
at your door*, and home renders them identically.

- **`confirmed` past its time** → the runner never set off. Expiry is right, and `no_show` is
  ALREADY a legal transition from `confirmed` (0001:205) — it is simply never set by anything
  (zero hits for `no_show` across `supabase/functions/`). The state exists and is unreachable.
- **`runner_enroute` past its time** → Sean's case exactly. **Expiry here would be harmful** —
  it would cancel a booking while a runner is physically waiting at the pickup point. Never expire
  this. The remedy is 인계 or contact, not cancellation.

**Revised ask:** the grace-window expiry applies to `rawStatus = 'confirmed'` ONLY. `runner_enroute`
is excluded no matter how late it is. The money ruling narrows accordingly: it is about a runner
who never set off, not a runner who showed up and waited.

### 🔴 SECOND DEFECT, found by the same question — the urgent CTA fires one state too late

`picked_up` is reached only when BOTH `owner_confirmed_handoff_at` and
`runner_confirmed_handoff_at` are set (`transition-booking/index.ts:300-320`, "둘 다 눌러야
picked_up (보험 기점)"). Home's `goState === 'handoff'` maps from `picked_up`.

**Therefore home shows the loud coral 「인계하기」 only AFTER the handoff is already done** — and
during the moment the owner actually has to hand the dog over (`runner_enroute`, especially once
`arrived_at` is stamped) home shows the calm 「티켓 보기」. The urgent state and the urgent moment
are off by one.

This is exactly the failure CLAUDE.md names — *"When display vocabulary flattens server states
(STATUS_MAP), gate logic and badges on `rawStatus`"* — and home gates on the flattened value.
`Booking.rawStatus` is already populated by `fetchMyBookings` (`api.ts:3915`), so the fix is
client-side; `arrived_at` would need adding to that select to separate "on the way" from "here".

**Proposed gating (needs Sean's word — it changes which screen shouts, and neighbours the frozen
meetup flow):**
- `confirmed` → calm. Accepted, nothing to do yet.
- `runner_enroute` + no `arrived_at` → calm. 러너가 오는 중.
- `runner_enroute` + `arrived_at` → **coral, 내 차례, 인계하기.** This is the real handoff moment.
- `picked_up` → calm. 인계 완료, 곧 출발 — 지도 보기.

---

### ⬆ This item now has a full memo: **[handoff-cta-gating.md](handoff-cta-gating.md)**

Written 2026-08-20 night. Same question, but it adds three things this section did not have,
all re-verified against HEAD rather than carried from memory:

1. **The meetup screen already implements the rule** — `app/app/owner/meetup.tsx:335-338`: coral
   turns on **only when `arrivedAt` is true**, with a comment saying so. So this is not "should we
   add a rule"; **home is the one screen not following a rule the app already has.** That reframes
   it from a product question to an inconsistency, and it is why the memo recommends A.
2. **The server is deliberately right and must not be touched.** Arrival is a timestamp, not a
   state, because `transition-booking/index.ts:275-277` says moving the status at arrival would
   drag the insurance and settlement basis earlier. Any "fix" that promotes `arrived` to a status
   is wrong. Client-only change.
3. **Two candidate answers, costed** — A (gate home on arrival, recommended) and B (leave the
   gating, fix only the false 인계하기 ask on `picked_up`). Both need the same additive plumbing
   (`arrived_at` into `fetchMyBookings`); after that A is one line and B is copy.

⚠ Two corrections to the section above, found on re-verification — the line numbers it cites had
drifted: the both-confirmations gate is the `confirm_handoff` arm, not `index.ts:300-320`, and
`rawStatus` is populated at `api.ts:3969`, not `:3915`. Trust the memo's citations over this
section's.

**Still queued, not built.** Two sessions independently carved this out for Sean's own ruling on
2026-08-20 (`docs/plans/2026-08-20-client-gap-straightening.md:29` P4, and this section), and the
overnight grant's "decide independently" was not read as reversing a specific carve-out he had
already accepted that day. One word from Sean — **A** or **B** — unblocks it.

---

## §0-duodetricies · The primary CTA's coral is boxed in at AA — deepen it, or accept flat hierarchy?

**One question, one word. Nothing is blocked tonight** — the accessibility failure itself is
already fixed; this is only about whether to take the better fix, which is visible.

**What happened.** `paper.action` (`#C6472C`) is the coral ground under 홈's primary button. Its
sub-line was `#FFD9CE`, measured at **3.70:1** — under the 4.5 floor for 15pt text, so it was a
real AA failure on the most-looked-at control in the app. Found by the peer client session,
reproduced independently here.

**The part that needs you.** Measuring the *ground* rather than the row showed the row is boxed in:

| ink | on `#C6472C` | |
|---|---|---|
| `#FFFFFF` (the title) | **4.84** | ← the ceiling. No ink on this ground does better. |
| `#FFF6F3` | **4.55** | ← the only tint that passes |
| `#FFF4F0` · `#FFF1EC` · `#FFEDE7` | 4.48 · 4.39 · 4.27 | all fail |

Because the title already sits at the ceiling, **any compliant sub-line lands within ~0.3 of it** —
so colour can no longer separate the two lines at all. We shipped `#FFF6F3` (4.55) tonight to clear
the failure, with size and weight now carrying the hierarchy alone. It is compliant and it is thin.

**The alternative needs your word because it is visible:** deepen the ground to `#A63A20` — a
colour **already in that row** as its depth edge, so nothing new enters the system.

| | on `#A63A20` |
|---|---|
| `#FFD9CE` (the original sub) | **4.95** |
| `#FFFFFF` (title) | **6.47** |

Real headroom on both lines, and the title/sub separation comes back. **The cost is that the
primary button gets visibly deeper** — a change to the ⑧ v2 grammar you picked by number, so
neither session took it at 2am, and especially not as a side effect of an accessibility fix.

- **A — deepen the ground to `#A63A20`.** Better contrast, hierarchy restored, no new token. The
  main button looks deeper/darker than the one you picked.
- **B — keep `#C6472C`, stay at 4.55.** Nothing changes visually; the CTA's two lines stay nearly
  the same colour and lean on size and weight.

**Recommendation: A.** 4.55 is compliance without margin, and the flattened hierarchy is a cost we
took silently to reach it. But this is taste on a surface you chose, so it is yours.
