# Awaiting Sean — the return queue

**Purpose: this queue existed only inside one session's conversation.** The announcing session
asked for it to be written down, applying the day's first rule to itself: *unpushed reserves
nothing.* If that session runs out of context the way the 반포 route session did, an
in-conversation queue evaporates — and it would evaporate silently, because nobody knows to
look for a list they never saw.

Ordered by what blocks the most. Nothing here is decided; **🟡 means it is Sean's**, and per the
governance rule in [README.md](README.md) a stand-in's analysis never becomes a ✅.

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

## 0-septies. 📋 RECORD — PR-0's test-owner exclusion exists in practice and is written nowhere

Owner `aa73ce8a-0ee0-473f-af1c-ffa8030a09a9` holds **all 24 existing bookings** and PR-0 reads
zero — so the exclusion is already applied by your judgement and is simply undocumented. Needs no
migration: a recorded owner id + a documented count query. One line from you confirms this is the
flagged-test-owner policy, and then it gets written into the PR-0 doc.

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
