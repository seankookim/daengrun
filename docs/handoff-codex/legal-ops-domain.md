# Legal · Compliance · Ops-and-Release — domain handoff for Codex

**Written 2026-08-21 for an agent with zero history.** The legal session that produced most of the
artefacts below is gone; this file and the repo are the only sources. Everything here was either
re-executed today or is quoted with its provenance marked.

Tree: `/Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a`
Trunk = `origin/redesign-v4`. ⚠ **This tree moved three times while this file was being written**
(`9475c79` → `2cde1a2` → `b6ee192`) because other sessions are landing into it, and one of those
commits invalidated a 🔴 item in the decision queue (§4.2). **Re-measure before acting on any line
here.** Facts below are as of `b6ee192`, 2026-08-21.
Linked production project: `zjabnywjpvpgmtajygqy`, region `ap-northeast-2` (AWS Seoul). **[measured]**

## Provenance legend — read this before you quote anything downstream

- **[measured]** — I executed it today, 2026-08-21, against production or this tree, and the
  output is reproduced or summarised faithfully.
- **[from-doc]** — it is written in a repo document by an earlier session. I did not
  independently re-verify it. Treat it as a dated claim, not as a fact.
- **[inferred]** — my reasoning over measured or documented facts. Argue with it freely.

This distinction is not decoration. **Two of the three factual assumptions in the external legal
review turned out to be wrong or stale when someone finally executed them** (§6), and one of the
two review documents in `docs/legal/` contains a conclusion that today's measurement contradicts
(§2.9). A number that is not marked is a number nobody has checked.

---

## §0. The one-screen state

| Axis | State | Provenance |
|---|---|---|
| 위치기반서비스사업 신고 (KCC) | **NOT FILED.** Upstream of every location feature. | [from-doc] `docs/biz/location-law-counsel-brief.md:35` |
| Counsel engaged | **NO.** Two briefs written and sitting in the repo; nobody has confirmed either reached a lawyer. | [from-doc] `docs/decisions/awaiting-sean.md:369` (d) |
| 개인정보처리방침 / 이용약관 | **DRAFT, unpublished, no 시행일, no public URL.** | [measured] both files carry `시행일: (미정)` |
| 사업자등록 → 통신판매업 → PG → 빌링 심사 | **step ① not started.** Whole chain pending. | [from-doc] `docs/biz/payments-paperwork-checklist.md` |
| Charging | **OFF.** `payments_live_since = null`, `payments = 0`, `billing_keys = 0`, `ops_recipients = 0`. | [measured] |
| Real users | **NONE.** 10 profiles, 9 runners (all 9 marked `club_test_accounts`), 9 runs, all Sean's own account. | [measured] |
| Builds ever shipped | **ZERO.** `eas build:list` → `[]`; one channel `testflight`, 0 update groups. | [measured] |
| Realtime location exposure (the P0) | **CLOSED** at the realtime boundary; `private_only = true` still on today. | [measured] |
| In-app account deletion (App Store 5.1.1(v)) | **BUILT AND DEPLOYED** 2026-08-20 — 0115 applied, `delete-account` edge fn ACTIVE, settings row live. | [measured] |
| 맹견 exclusion | **DOES NOT EXIST** anywhere in client, schema or migrations. | [measured] |
| ⚠ 맹견 exclusion — 2026-08-25 | The line above is TRUE AGAIN, **by ruling, not by drift.** A gate was built (0119, 2026-08-25 am) and removed the same day (0127, Slice A) after Sean ruled twice — the second time with this very review in front of him — 「Remove it completely」. So a future reader must not treat its absence as an oversight this document already flagged: it is a decision this document caused to be made, and then lost. See `docs/decisions/2026-08-25-console-rulings.md` (F1) and `docs/contracts/maenggyeon-gate-removal-contract.md`. The three `dogs` columns 0119 added still exist, unread and unwritten, until Slice B drops them. | [ruled] |
| Location retention / purge | **DOES NOT EXIST.** 17 crons; none touches `runs.trace`. | [measured] |
| 위치정보 이용·제공 확인자료 ledger (제16조) | **DOES NOT EXIST.** | [measured] |
| Feed moderation / 임시조치 | **DOES NOT EXIST**, and there is no admin role to build it on. | [measured] |

**The shape of the whole domain in one sentence:** almost nothing is legally *wrong* yet because
almost nothing is legally *live* yet — one self-testing account, no money, no build — and the risk
is entirely about which of these gaps is still open on the day the first real runner starts a run.

---

## §1. Every legal artifact and its status

All eight artefacts are on trunk. **[measured]** `git ls-tree --name-only origin/redesign-v4 docs/legal/`

### 1.1 `docs/legal/privacy-policy.md` — 152 lines, last touched `9f29640` (2026-08-19)

History: `36c28e4` (2026-08-08, first draft) → `d497ca2` (coordinates rider) → `ecb8be6`
(2026-08-13, ⑪ incident rider) → `9f29640`. **[measured]**

**What it claims.** A full PIPA-shaped policy written from a code audit rather than boilerplate:
§1 collection inventory (email, name, optional phone, dog info, **precise location**, run photos,
chat, reviews, push token, pickup coordinates), §2 purpose table, §3 a dedicated 위치정보법
section, §4 a candid statement that photo media sits in a public-read store, §5 retention table,
§6 processors (Supabase / Expo / 네이버클라우드플랫폼), §7 rights, §8 safeguards, §9 보호책임자
(blank), §10 change notice.

**What is verified.** The collection inventory was audited against real code paths and cross-checks
`docs/appstore-privacy-answers.md`. §3's *"제공 대상: 해당 예약의 보호자에게만"* (`:91`) was **false**
until 2026-08-19 and is **true now** — that blocker was released explicitly at
`readiness-review-2026-08-19.md:352-359` after the channel was privated. **[from-doc, and the
underlying `private_only=true` re-measured by me today]**

**What is draft / owed.** The file's own header (`:1-28`) is a four-item DECIDE-BEFORE-PUBLICATION
list, and **all four are still open**:

1. `:9-11` — the `avatars` bucket is public-read and holds more than avatars. **Still true, and now
   only half-true in the other direction:** [measured] `storage.buckets` shows `avatars public=true`
   (3 objects) and a private `media` bucket created 2026-08-10 (**0 objects**). The client writes
   dog photos, run photos, chat photos, club-chat photos and feed photos to the **private** `media`
   bucket (`app/src/lib/media.tsx:13`, used at `api.ts:389, 1995, 2624, 3555, 3739`) but still
   writes **profile avatar, runner gallery, gear-proof and club photos** to the **public** one
   (`api.ts:1954, 2221, 2265, 3714`). So §4's sentence ("프로필 사진, 반려견 사진, 러닝 사진, 장비
   인증 사진" are all publicly reachable) is **now wrong about 반려견/러닝 사진** — it over-discloses.
   The one-shot backfill `scripts/migrate-private-media.mjs` has evidently never run (`media` holds
   0 objects while legacy rows still carry public URLs — `media.tsx:3-4` says exactly this).
   **§4 must be rewritten before publication, and it is currently a *conservative* error, not a lie.**
2. `:12-14` — the 신고. Open. See §2.1.
3. `:16-19` — the retention row is not a period. Open, and unfixable by drafting. See §2.6.
4. `:20-24` — the 확인자료 right is promised and no ledger exists. Open. See §2.7.

Plus two inline `변호사 확인 필요` blocks: `:116-117` (concrete 전자상거래법 retention periods —
the table is placeholders) and `:130-131` (국외이전 under 개인정보보호법 제28조의8, and the region).
The region question is now largely defused: `ap-northeast-2` is Seoul **[measured]**, but
*storage location* and *processor nationality* are different facts and the counsel brief correctly
declines to conclude either way (`location-law-counsel-brief.md:22-26`).

### 1.2 `docs/legal/terms-of-service.md` — 103 lines, `36c28e4` (2026-08-08) — **NEVER REVISED**

**[measured]** One commit, ever. Every later legal finding was written *about* this file, in other
files. That matters: the two sentences the contract-status brief calls the least supported by the
code (제2조 *"회사는 거래 당사자가 아닙니다"*, 제3조 *"독립적으로"*) are still sitting in the
document exactly as first drafted.

**What it claims.** 제2조 통신판매중개자 posture · 제3조 runner-is-not-an-employee · 제4조 pricing
frozen at booking · 제5조 cancellation ladder · **제6조 custody and liability** (the one the drafter
calls the most important) · **제7조 insurance: explicitly none during the pilot** · 제8조 location
and photography · 제9조 prohibited acts · 제11조 limitation of liability · 제12조 change notice.

**What is verified.** 제7조 (no insurance) matches the app: `app/app/safety.tsx:187` renders
「펫보험 · 파일럿 보험 파트너와 협의 중이에요」, `owner/meetup.tsx:714` and `runner/meetup.tsx:617`
carry the same honest line. **[measured]** Two documents agreeing on an uncomfortable truth is the
one unambiguous compliance asset in this whole domain.

**What is draft / owed to counsel.** Four inline flags: `:34-35` (is pure intermediation defensible
when we vet, price and assign?) · `:54` (청약철회권 exclusion scope for services; the percentages
are placeholders matching `transition-booking`) · `:66-67` (numeric liability caps, fault
allocation, 동물보호법 duties — *"이 조항이 이 서비스에서 가장 중요합니다"*) · `:95`
(약관규제법 — over-broad exculpation is void).

⚠ **There is no §10.4 in this document.** The "§10.4" referenced across the handoff queue is
**§10.4 of the external source review**, audited in
`readiness-review-nonlocation-2026-08-19.md:83-108`. Do not go looking for it in the ToS.

### 1.3 `docs/legal/readiness-review-2026-08-19.md` — 513 lines, `a80152d`, 12 commits in one day

The location/PIPA half. **This is the single most valuable document in the domain** and the one
Codex should read in full before touching anything location-shaped.

It audits an external counsel-adjacent review (`Dogs_High_Korean_Law_Legal_Readiness_Deep_Review_
2026-08-19.md`, **not in the repo** — [inferred] it lived outside version control and is now
unavailable; every quotation from it survives only inside this audit) that returned **RED: pause
even a free pilot**.

Contents, section by section, so you can navigate it:

| § | Subject | Status today |
|---|---|---|
| 1 | RED survives: no 신고, no 위치기반서비스 이용약관, runner's only consent is the OS dialog | still true [measured, §2.1/§2.10] |
| 2ⓐ | "no location policy exists" — STALE, a draft does | still true |
| 2ⓑ | Published routes carry 4 identity columns, anon-readable | **CLOSED by 0107**, verified over the wire |
| 2ⓒ | **The P0**: `run-*` was a public broadcast; a stranger received and could inject a position | **CLOSED**, both instruments, §6-ter |
| 3 | What the review gets right and can be acted on | reference |
| 4 | Open questions the audit cannot answer (신고 sufficiency; Supabase region/DPA) | open |
| 5 | Three buildable items, ranked | 1 and 2 done; **3 (consent gate + 약관 split) NOT done** |
| 6 | Two corrections owed to the counsel brief | applied at `69cf67d` |
| 6-bis | Post-0103 re-measurement: **the P0 is NOT closed** — RLS is only consulted for private joins | superseded by 6-ter |
| 6-ter | CLOSED, both instruments, and the exposure window bounded to one account | **the closure record** |
| 6-quater | Two places the policy promises what the system does not do (purge; ledger) | **both still open** |
| 6-quinquies | The review's §13.2 eleven product controls, scored | 3 ✅ / 4 🟡 / 4 ❌ |
| 7 | The question with a clock: does the capability constitute a 유출? | **UNASKED** |

The §13.2 scorecard (`:456-469`) is the closest thing to a compliance backlog that exists. Its
verdict: ④ ⑤ ⑥ ⑦ ⑨ are the ones that must exist before a real runner does. ⑥ (account deletion)
has since been built (§3.5).

### 1.4 `docs/legal/readiness-review-nonlocation-2026-08-19.md` — 229 lines, `c84dc74`, 3 commits

The companion covering §4 contract structure, §8 animal business, §9 insurance, §10 payments,
§11 reviews/community, §12 shopping. Headline: *"the non-location surface is in much better shape
than the location half — mostly because most of it is not built yet."*

**Its §4 is the highest-value legal question in the product** and it is the one that produced the
contract-status counsel brief. Its §11 contains the one conclusion today's measurement contradicts
— see §2.9, and note that the file **corrects itself in place twice** (`:58` and `:134`), which is
the right idiom and worth copying.

### 1.5 `docs/legal/contract-status-counsel-brief.md` — 88 lines, `d60bc9d` (2026-08-19)

Korean, addressed to a lawyer, **facts only, no legal conclusions**. §3 the control table (what the
company decides), §4 the counter-table (what the runner decides), §5 six ranked questions, §6 two
side questions (recurring pre-charge notice; 면책 validity under 약관규제법 제7조).

Owed: **it has not been sent.** [from-doc] `awaiting-sean.md:369` lists "forward counsel brief v5"
as Sean's errand and the queue never records it done. [inferred] The same is true of this one.

### 1.6 `docs/biz/location-law-counsel-brief.md` — 65 lines, **v5** = `1b2d448`

Five commits, each a factual correction, in the order they were measured:
`d06fcdd` (v1, 2026-08-15, one-pager) → `88e3648` ("the data does NOT leave Korea — corrected
before it reaches a lawyer") → `69cf67d` (§2/§2-bis/§4 corrected against the 08-19 measurements)
→ `a141beb` (footer states execution-measured provenance; Q6 added) → `1b2d448` (Q6 gains the
bounded exposure numbers). **[measured]**

Six questions: (1) is this 신고 대상 and must it precede service? (2) procedure/documents/ordering
vs 사업자등록 (3) is a separate location consent + 위치기반서비스 이용약관 required, minimum
requirements (4) what the 러너↔보호자 relationship additionally requires (5) risk of piloting
unfiled, criminal included (6) **the 유출 notification question, with the measured numbers attached**.
Plus one payment side question on 빌링키 pre-charge notice.

⚠ Two residual defects recorded at `readiness-review-2026-08-19.md:261-263` and never fixed:
the footer still dates all facts to 08-15 and calls them config-derived, which undersells the
execution evidence; and **Question 4 was not updated after §2-bis was added**, so the brief now
*states* the third-party exposure without *asking about* it. [from-doc]

### 1.7 `docs/legal/evidence/run-channel-probe.mjs` — `26c614a`

The probe that produced the P0. Its header is 55 lines of instructions on **why it is evidence and
not a test** — four named defects (no positive arm; cannot tell "rejected" from "slow"; must not
run against production in CI; the topic is synthetic). Read `:17-30` before reusing it. The rule it
distilled: *every instrument that can only observe failure will report success when the system is
dead.*

### 1.8 `docs/legal/evidence/run-channel-private-matrix.mjs` — `099fe53`

The 2×2 that proved 0103 alone was insufficient: `{existing topic, renamed topic} × {private:true,
private:false}`. Post-0103 the `private:false` cells still SUBSCRIBED. It also carries the agreed
**closure gate** at `:33-53` — negative (this file) plus positive (ui's `e2e-run-channel.mjs`) in
one run, or it is not closed.

Both probes read `app/.env` for the anon key and need `app/node_modules`. Neither has one in this
worktree; run from `/Users/sean/dev/daengrun/app` with `DAENGRUN_APP_DIR`.

### 1.9 Adjacent artefacts you will need

| File | What it is |
|---|---|
| `docs/appstore-privacy-answers.md` (`ecb8be6`) | The App Store / Play data-safety answer sheet. **STALE** — see §2.4 |
| `docs/biz/payments-paperwork-checklist.md` | 사업자등록 → PG → 통신판매업 → 빌링 심사, the paper half. The chain is **not serial** (§2 of that file) |
| `docs/pre-charging-checklist.md` | the config half of the same cutover (272 lines) |
| `docs/launch-checklist.md` | Banpo pilot gate list; §1 "Legal and filings" at `:34-49` |
| `docs/security-dashboard-checklist-2026-08-19.md` | the two dashboard toggles, measured, **still unapplied** (§4.5) |
| `docs/decisions/awaiting-sean.md` | **the live decision queue.** §0-* is everything Sean owns |
| `docs/contracts/account-deletion-contract.md` | the adversarially-attacked contract behind 0115 |

---

## §2. The open legal exposures

Each with its statute, its measured factual state, and what closing it actually requires.

### 2.1 🔴 위치기반서비스사업 신고 — upstream of every location feature

**Statute:** 위치정보의 보호 및 이용 등에 관한 법률. A 위치기반서비스사업자 신고 to the
방송통신위원회 is generally required **before service**; operating without it carries **criminal**
rather than revenue-scaled exposure, which is why it outranks the PIPA items even though we are
pre-revenue. [from-doc] `docs/decisions/awaiting-sean.md:164-174`

**Factual state.** Not filed. [from-doc] `location-law-counsel-brief.md:35`. Nothing in the repo
records any contact with the KCC. The product collects 개인위치정보 of an identified natural person
(the runner is a registered individual — `location-law-counsel-brief.md:27`), streams it live, and
stores the post-run track.

**Blocked on:** counsel answering Q1/Q2 of the brief, then Sean filing. It is an errand, not a
decision, but it may itself depend on 사업자등록 (Q2 asks exactly this).

**What it gates:** [inferred] everything location-shaped. Every other item in this section is
downstream of it, including the consent design, the 약관 split, the retention cap and the ledger —
because the filing is what makes us the kind of business those duties attach to in the specific
form the KCC expects.

### 2.2 🔴 Contractor status — the runner decides WHEN and WHETHER; the company decides HOW MUCH

**Statute / authority:** 근로기준법 worker-status doctrine, 대법원 2024두32973 (the
*독립적으로 이윤과 손실을 추구할 기회* factor); 전자상거래법 제20조 (통신판매중개자 duties);
산업재해보상보험법 노무제공자; 직업안정법 유료직업소개사업.

**The control split, from the code.** [from-doc, `readiness-review-nonlocation-2026-08-19.md:32-42`;
the sharp fact re-read by me]

Company holds: owner-facing price (`bookings.base_fare/distance_fare/addon_fare`, platform-computed)
· runner's pay rate (`PRICING.runnerCompBase`, `PRICING.perKm`, read at settle time) · commission
(`runners.commission_rate`, server-side, *"never client input"*) · who may see work at all
(`is_active_runner()` → `runners.tier <> 'applicant'`) · the cancellation ladder (`0066:80-82`,
`round(total_price * 0.5)` / `* 0.1`) · live GPS for the whole engagement · the anti-disintermediation
clause (ToS 제9조).

Runner holds: which booking to take (`marketplace_open_requests`, free acceptance) · when they are
available (`runner_availability_rules/_exceptions`, self-modifiable, `0002:76`) · whether to work
other platforms (**no exclusivity or non-compete exists anywhere**) · whether to accept a 지명
(and the 지명 comes from the *owner*, not the platform — no auto-assignment path exists).

**The asymmetry that is the whole question.** `supabase/migrations/0101_compute_runner_payout.sql`
— the REGISTRY row for 0101 states it in the repo's own words:

> *"It reads LIVE `PRICING` constants (9,900 / 3,000), not the booking's frozen fare columns,
> because a payout is not a consented price … the consequence (a price revision reprices an
> unsettled run's PAYOUT while leaving its CHARGE alone) is a product decision with its own slice."*

The owner is charged from columns frozen at booking (*"동의한 가격만 청구한다"*). The runner is paid
from live platform constants at settle time. **The platform can unilaterally change what a runner
earns for work already underway, and the runner has no mechanism to set, negotiate or lock their
rate.** There is no runner-set price field anywhere in the schema or client; it was searched for.

**Blocked on:** counsel. `docs/legal/contract-status-counsel-brief.md` §5 Q1–Q6 asks it properly and
in Korean. **This is the single highest-value legal question in the product** — it is upstream of
the ToS text, the 전자상거래법 duties, the insurance design, and the payment disclosures.

**Size if the answer goes against us:** [inferred] large but not architectural — freezing the payout
rate at booking (the mirror of what the charge already does) is one migration plus a column, and
`0101`'s REGISTRY row already names it as "a product decision with its own slice."

### 2.3 🟠 §10.4 — variable post-service charges with no pre-charge amount notice

**Statute:** 전자상거래법 pre-charge disclosure; 여신전문금융업법 on 빌링키 charging.

**Why the source review's reassuring answer does not apply.** It answered: *if the consumer clearly
chooses recurring payments of the same amount on the same schedule, the law generally does not
require fresh approval each cycle.* [from-doc, `readiness-review-nonlocation:85-87`]

Our product fails all three limbs. What recurs is a **booking**, not a payment (`0026_recurring.sql`
+ `0080_charge_machine.sql`); each generated booking produces a **variable, post-service** charge
computed from actual distance at settle time. The amount is not the same, not on a fixed schedule,
and **not knowable when the owner consents.**

Layered on: `0026:135` notifies the owner when a recurring booking is auto-created
(*"X월 X일 러닝이 자동 예약됐어요"*) — **that notice carries a date and no amount**, and it fires at
booking creation, not before the charge. Sean's ruling ② cancelled the statement-row slice outright:
no per-charge push, no monthly summary.

**Net: variable-amount automatic charges against a stored billing key, with no pre-charge notice of
amount and no statement.** That may well be lawful — post-pay for a completed service is not a
subscription — but it is a different question and nobody has asked it.

There is one countervailing design fact worth handing counsel: `docs/decisions/card-registration-placement.md:14-17`
argues that **under price invisibility the card-link screen is the only place the owner consents to
actuals-based charging**, which makes it a consent moment rather than a settings chore — and that
this is what the "no per-charge notice" decision leans on. So the disclosure question and the
card-registration UI slice are the same question.

**Blocked on:** counsel (it is §6-1 of the contract brief and the final section of the location
brief). **Not urgent today** — charging is off at four independent layers and `payments = 0`
**[measured]** — but it must be answered before the flip, not after.

### 2.4 🟠 The App Store privacy sheet is STALE, not merely unfiled

**Standard:** App Store Connect App Privacy questionnaire; Google Play Data Safety. A label that
does not match behaviour is a review rejection and a post-launch compliance problem —
`docs/appstore-privacy-answers.md:7-8` says so itself.

**The mismatch, measured today.**

- `app/app.json:75` — `"isIosBackgroundLocationEnabled": true` **[measured]**
- `app/app.json:76` — `"isAndroidForegroundServiceEnabled": true`
- `app/app.json:77` — `"isAndroidBackgroundLocationEnabled": false` (this one is a genuine
  compliance asset — Android background location is *off*, foreground-service only)
- Background location landed at `9e2ec68`, **2026-08-08** ("background GPS: tracking survives the
  screen lock (Sean: all the time, hard block)") **[measured]**
- `docs/appstore-privacy-answers.md:57` still reads: **"Background location is not declared yet."**
  The sheet was last touched `ecb8be6`, 2026-08-13 — *five days after* the capability shipped.

`docs/decisions/awaiting-sean.md:176-178` states the consequence precisely and it is worth
preserving verbatim: *"So that questionnaire is **stale, not merely unfiled** — asking 'has it been
filed yet' accepts a premise that is already false."*

A second, independent staleness in the same file: `docs/decisions/incident-verification.md:141-155`
records that `appstore-privacy-answers.md:27` declares the phone number's purpose as handoff
contact, while the ⑪ incident slice makes phone numbers mutually visible during an open incident —
and *"nothing marks it as submitted."*

**Size:** small — it is a document edit plus, when the sheet is finally filled, a review-notes
justification for background location (the file already drafts an honest one at `:59-62`).
**Blocked on:** nothing. This can be corrected today and should be, because §4.6's TestFlight
errand is the moment it stops being free.

### 2.5 🟡 맹견 — absent everywhere · **CLOSED BY RULING 2026-08-25, read this first**

> **This section is history, not an open gap.** Its recommendation was built (`0119`) and then
> removed (`0127` Slice A) on the same day, because Sean ruled 「Remove it completely」 — twice,
> the second time with this section in front of him. The 「Size: small — a dog-profile field plus
> a booking-time refusal」 line below is exactly what got built; it was not wrong about the work,
> only about whether the work was wanted. **Do not re-open this as an unaddressed finding.** The
> product's exposure here is now carried by the transit-insurance brief's counsel line, which
> states the check was removed by decision on 2026-08-25 — worded as a removed feature, never as
> 「data destroyed」, since a dropped column is logical forgetting and counsel must not be
> overclaimed to. Everything after this box is preserved as it was written.

**Statute:** 동물보호법 맹견 provisions (statutorily-defined breeds and individually-designated
dangerous dogs); the source review asks for both to be excluded from the MVP outright.

**Factual state, measured today by me:** `맹견` appears **9 times in the whole repo and every one is
in `docs/`** — never in the client, never in the schema, never in a migration. **[measured]** There
is no `dogs` column, no booking-time refusal, no question in the booking flow. `공격성` appears only
as advisory copy (`app/app/club/session/[sid].tsx:60` club waiver; ToS 제6조2 at
`terms-of-service.md:59`) and one test fixture string. Nothing stops such a booking today.

**Size:** small — a dog-profile field plus a booking-time refusal. **Blocked on:** ownership only. It
was offered to two sessions on 2026-08-19/20 and declined by both as an unowned custody/trust
surface (`docs/session-handoff.md:40`, `docs/handoff-announcer.md:45`). Legal ranked it **below**
the two retention builds (`awaiting-sean.md:512`) on the ground that the retention items matter at
the first real runner and this one matters at the first real *owner with such a dog*.

**Adjacent, and never decided:** no cap on dogs per runner. Club delegation is multi-dog by design
(`createPosPublisher` takes an array). The review recommends one dog per runner initially. Not a
violation — a product decision nobody has made explicitly, and it interacts with duty-of-care in an
incident. [from-doc]

### 2.6 🔴 No location retention or purge mechanism — and no drafting can fix it

**Statute:** 위치정보법 시행령 제26조의2 — 개인위치정보 is capped at **one year even with separate
retention consent**, and must be destroyed once the purpose is achieved.

**Factual state, re-measured today:** production runs **17 cron jobs**. **[measured]** In full:

```
weekly-rewards · purge-chat · expire-unmatched · expire-reschedules · recurring-gen ·
club-series-gen · club-min-attendance · club-hold-expiry · club-payout-release ·
club-assignment-recovery · purge-holds · owner-la-stale · club-stale-delegation-sweep ·
sweep-payment-intents · sweep-settled-charges · dispatch-due-charges · run-end-recovery
```

`purge-chat` deletes `chat_messages` older than 30 days (`0014_comments_crons.sql:60-64` — and note
it does **not** touch `club_chat_messages`). `purge-holds` deletes expired `slot_holds`. **Nothing
purges `runs.trace`.** No TTL, no job, no function. [measured, and independently confirmed by the
subagent's grep of every `cron.schedule` in the repo]

Current data: **9 runs, 9 with a non-null trace, first 2026-07-28, last 2026-08-11.** **[measured]**
The oldest trace is 24 days old. The one-year cap is not yet breached; there is simply no mechanism
that could ever end the retention.

Against that, `privacy-policy.md:112` says 러닝 기록 및 위치정보 are kept for *"서비스 제공 및 분쟁
대응에 필요한 기간"* — which is not a period.

⚠ `0115_account_deletion.sql:84-86` explicitly disclaims ownership of this purge:

> *"`runs` reached only through bookings (KEEP). ⚠ This is NOT the runs.trace TTL — 위치정보법
> 시행령 제26의2 caps 개인위치정보 at one year and that purge is owned elsewhere, for EVERY run,
> not only deleted ones."*

**"Owned elsewhere" resolves to nothing.** [inferred] Account deletion does not and should not solve
this: the cap applies to every run, including runs of accounts that never delete.

**Blocked on:** nothing legal. It is a build. **Size:** small — one function plus a `cron.schedule`,
in the `purge_old_chat` idiom. ⚠ **The pin belongs on `cron.job`, not on the function**:
`0060:142-147` records that `purge_expired_holds` sat unscheduled for a long time while a comment
claimed it ran every minute, and `0060:129-135` records that its predicate meant it *had never
deleted anything*. A function without a verified schedule row is the exact failure this repo already
made once.

### 2.7 🔴 No 위치정보 이용·제공 사실 확인자료 ledger — and the policy already promises the right

**Statute:** 위치정보법 제16조 — the records must be **recorded automatically**; the Standards for
Administrative and Technical Safeguards require retention of **at least six months**.

**Factual state, measured today:** [measured] querying `information_schema.tables` for anything
matching `%log%|%ledger%|%audit%|%consent%` in `public` returns exactly six tables —
`club_phone_access_log`, `delegation_consents`, `gate_code_access_log`, `km_ledger`, `ledger_items`,
`miles_ledger`. **No location access ledger exists.** If a runner exercised the 열람·고지 right
today there would be nothing to show them.

`privacy-policy.md:95` promises it anyway: *"이용자는 언제든 자신의 위치정보 이용·제공 사실
확인자료를 열람·고지 요구할 수 있습니다."*

**The repo already has the idiom, twice, and they differ in a way that matters:**

- `gate_code_access_log` — `supabase/migrations/0001_init.sql:130-136`. Owner-read policy at
  `0002:84-86`. ⚠ **It has no writer.** `0060_wave3_server_honesty.sql:52-53` records why:
  *"STABLE 유지 = 열람 로그 없음. gate_code_access_log는 한 번도 쓰인 적 없는 빈 껍데기고, 로그를
  달면 함수가 volatile이 된다(Sean 판단 대기 — 원하면 club_phone_access_log 0049 패턴)."*
  **Do not copy this one.** It is the shape without the behaviour.
- `club_phone_access_log` — `supabase/migrations/0049_session_shell.sql:156-163`, RLS on with **zero
  policies** (ops-only). **It is live**: writers at `0049:236-246` and `0053:435-445`, with a
  10-minute dedup so a re-read inside the window does not spam the ledger. **Copy this one.**

**Blocked on:** nothing legal. **Size:** small-to-medium — a table, a writer at every location
read/provide point, and a retention floor. ⚠ One design hook already exists for it:
`0115_account_deletion.sql:788-796` names the future table (`location_access_log`) and the §F
deletion watchdog carries a `%access_log` wildcard **specifically so that account deletion cannot
silently destroy the ledger the day someone builds it.** Whoever builds it inherits that protection
for free — and should verify it fires (the suite already mutation-tests it with a fake table at
`supabase/tests/150_account_deletion_suite.sql:115-148`).

### 2.8 🟡 Reviews read-path widening is a legal decision, not a UI fix — **and the shipped document is wrong about the current state**

**Statute (prospective):** 정보통신망법 defamation / 명예훼손, 초상권, personal-data exposure in UGC.

`readiness-review-nonlocation-2026-08-19.md:134-166` concludes reviews are *"not publicly exposed"*
and that *"the client's intent and the server's enforcement disagree"* — a product bug running in
the safe direction, whose eventual "fix" would be the moment §11 goes live.

**That conclusion is half right and the half that is wrong is the operative half.** [measured]

The anon probe reproduces exactly as documented — I re-ran it today:

```
GET /rest/v1/reviews?select=rating,note,target_id&target_kind=eq.runner&visibility=eq.public
  (anon key, not signed in)  →  401  42501  "permission denied for function is_booking_party"
```

But `anon` failing on the *function* permission tells you nothing about `authenticated`. Querying
`pg_policy` on production returns **four** policies on `reviews`, not three:

| policy | cmd | USING |
|---|---|---|
| `reviews public read` | SELECT | `visibility = 'public' AND is_booking_party(booking_id)` |
| `reviews author read` | SELECT | `author_id = auth.uid()` |
| **`reviews storefront read`** | **SELECT** | **`visibility = 'public' AND target_kind = 'runner'`** |
| `reviews author insert` | INSERT | — |

`reviews storefront read` comes from `supabase/migrations/0011_review_storefront.sql:4-5`, whose own
header says: *"러너 스토어프런트 리뷰 공개 — public 러너 리뷰는 모든 로그인 사용자가 읽음."*
RLS policies are OR'd, so **every authenticated user can already read every public runner review,
party or not.** `fetchRecentReviews` (`app/src/lib/api.ts:2804-2822`) is an unscoped, app-wide
`limit(20)` read and **the server agrees with it.**

**So §11 is already live for signed-in users, not latent.** The mitigating fact — and it is
substantial — is that production holds **exactly 1 review** **[measured]**, and
`reviews.target_kind` admits `'owner'` and `'dog'` (`0001_init.sql:252`), meaning reviews *of
customers and of animals* are possible; those are **not** covered by the storefront policy and
remain party-scoped.

**What to do with this:** correct `readiness-review-nonlocation-2026-08-19.md` §11 in place (the file
already corrects itself twice; that is its idiom), and put the corrected fact in front of counsel.
Do **not** soften it into "mostly not exposed." [inferred] The practical exposure today is near
zero because there is one review and no real users, but the *legal characterisation* changes: this
is a live public-reviews product, not a latent one.

### 2.9 🟡 No reports / moderation / 임시조치 table for the community feed — and no admin role to build one on

**Statute:** 정보통신망법 제44조의2 (임시조치 — takedown on request, with the operator obliged to act).

**Factual state, measured today:**

- The feed is real, server-backed UGC: `feed_posts` (`0013_feed.sql:4`), `feed_comments`
  (`0014_comments_crons.sql:4`), `feed_likes`. Client surface: `fetchFeed` (`api.ts:3798`),
  `addComment` (`api.ts:3166` — a bare insert, no length cap, no rate limit, no filter),
  `toggleFeedLike` (`:3827`), `deleteFeedPost` (`:3839`), `shareRunToFeed` (`:3754`).
- **All three tables are `select using (true)`** — `0013:16`, `0013:31`, `0014:14`. I confirmed
  over the wire that this reaches **anon**: `GET /rest/v1/feed_posts?select=id,body,author_id`
  with the public anon key returns **HTTP 200 with rows**, including `author_id`. **[measured]**
- Production holds **11 feed posts, 0 comments**. **[measured]**
- **There is no reports table, no moderation table, no `blocked_users`, no `hidden` column, and no
  takedown path.** The only delete policy is `"feed delete own" using (author_id = auth.uid())` —
  **the author, and nobody else.** [measured]
- **And there is no admin role to add one to.** `supabase/migrations/0082_route_ladder.sql:174-177`
  states it flatly: *"this repo has no admin role in RLS to lean on."* [measured] There is no
  `is_admin()`, no `admin` role, no admin claim in any policy anywhere in `supabase/migrations/`.
  All operator privilege is out-of-band — the `service_role` key and the SQL console.

The only report mechanism that exists anywhere is scoped to **club chat**, not the feed:
`club_chat_report(p_message, p_reason)` at `0049:127-143` sets a `flagged` boolean and notifies the
session host with a 10-minute dedup. **That is the shape to copy.** [inferred]

**Consequence worth stating plainly:** [inferred] with no admin role, there is today no in-app path
for an operator to honour a 임시조치 request, take down abusive content, or execute a data-subject
access/correction request. Every one of those requires a human connecting to the database directly.
That is defensible at 10 profiles and indefensible at 50 dogs.

### 2.10 🔴 No statutory location-consent gate, and no 위치기반서비스 이용약관

**Statute:** 위치정보법 제18조/제19조 — collection and provision of 개인위치정보 require consent
distinct from PIPA consent, and the service requires its own 위치기반서비스 이용약관 as a **separate
document**, not a clause inside the privacy policy.

**Factual state, re-measured today.** `app/src/lib/geo.ts` calls
`Location.requestForegroundPermissionsAsync()` at **`:175`** (`requestTrackPermission`) and again at
**`:216`** (inside `startTracking`). [measured — note the line numbers moved: the readiness review
cites `:199`, which after `bea1bc8` is now the closing brace of `getOneShotPosition`.] **Nothing
statutory precedes either call.** The prescribed order is `statutory explanation and consent →
in-app Start Tracking → OS permission`; the code goes straight to the OS prompt.

What exists is UX rationale copy only, and it is inconsistent:
- `app/app/onboard/runner.tsx:124-166` — 러닝 중 위치를 보호자에게 보여줘요 / 러닝하는 동안만 ·
  예약한 보호자에게만
- `app/app/runner/run.tsx:1384-1401` — shown **only when** `perm === 'undetermined'`
- `app/app/club/run/[sid].tsx:164` and `club/session/[sid].tsx:403` call `startTracking` with
  **no rationale at all**

`app/app/runner/apply.tsx:659-661` collects exactly three consents and **none is a 위치정보 consent**:
safety-rules, personal-data collection, and ID check. The file's own comment (`:643-645`) records
why the personal-data notice is inlined rather than linked: *"there is no published 개인정보처리방침
to link to, and a consent checkbox pointing at a document that does not exist is a dead link."*

Owner side: `app/app/login.tsx:110-111` — 「로그인하면 이용약관과 개인정보 처리방침에 동의하게 돼요」.
Implied consent, no checkbox, no link, **nothing recorded server-side**.

**Blocked on:** counsel for the *content* (brief Q3 asks the minimum requirements); nothing for the
*mechanism*. **Size:** medium — a gate screen, a consent record with a version, and a document split.
Build it versioned; see §5.2.

### 2.11 ⏱ The one question with a statutory clock, and it is still unasked

**Statute:** 위치정보법 제16조 관련; 개인정보 보호법 제34조 (통지·신고).

**Question:** does a live capability for unauthorized third parties to receive 개인위치정보
constitute a 유출 carrying notification and reporting duties, or does the absence of any evidence of
actual access mean it does not?

**The facts, as established:**
- Demonstrated capability, reproduced by execution against production (§3.1).
- Capability window **2026-07-25 → 2026-08-19**, 25 days. [from-doc]
- **9 runs actually traversed the channel**, 2026-07-28 → 2026-08-11. [measured — I re-derived the
  same 9 runs and the same date range today]
- **All 9 had `runner_id = owner_id`** — one account, both roles: `s4kim2025`, confirmed by Sean in
  his own words as his test account. So **no third party's location was ever on it.** [from-doc for
  the identity; the run count and date range are mine, measured]
- **No evidence of actual access, and nobody has established that realtime access logs of sufficient
  granularity exist.** [from-doc]

**It is Q6 of `location-law-counsel-brief.md` (`:46-55`) with the numbers attached.** The brief has
not been sent. `readiness-review-2026-08-19.md:512-513`: *"If the answer is that a duty arose, the
clock started at discovery, not at remediation."* Discovery was 2026-08-19. **Today is 2026-08-21.**

[inferred] This is the single item in the domain where delay itself is the risk, and it costs one
email.

---

## §3. What is legally CLOSED, and why

Closed here means: the unauthorized operation is rejected at the server/DB/realtime boundary, or the
feature genuinely does not exist. Never "the UI no longer exposes it."

### 3.1 ✅ The live-location broadcast — closed at the realtime boundary

**What it was.** `run-<bookingId>` was a Supabase Realtime **broadcast** channel. Broadcast, unlike
`postgres_changes`, does not consult RLS. Two clients holding only the public anon key, **not logged
in**, with no booking relationship, exchanged a position payload:

```
stranger subscribe status: SUBSCRIBED
publisher subscribe status: SUBSCRIBED
publish result: ok
STRANGER RECEIVED: {"lat":37.5109,"lng":126.9959,"km":1.2,"paceSec":330}
```

Read **and** write: a stranger could receive the runner's live position and inject a fabricated one
onto the owner's map. The only gate was knowledge of a booking UUID — and
`0042_marketplace_choke_point.sql:21` hands `b.id` to **every active runner who sees the request in
the open pool, including all the ones who did not win it.**

**How it was closed — three layers, because the first two were insufficient:**

1. `0103` — `realtime.messages` RLS. Correct, and **bypassable**: policies are only consulted for
   channels joined *as private*, and privacy is the joining client's choice. An attacker passes
   `private: false` and the policy is never reached. Proven by the 2×2 matrix.
2. A topic namespace bump to `run2-` (`geo.ts:368`). **Obscurity, not a control** — the matrix
   showed public joins succeed on *arbitrary* topic names, including a namespace that does not
   exist. Kept because reverting it would break live tracking, but its rationale as a control was
   withdrawn.
3. **`private_only = true`** at the project level, so `private: false` stops being an available
   answer. Plus `0104`/`0108` policies and the client half (`f106b2b`, `9012d7a`) marking all four
   channel families private with `setAuth()`.

**Verified today by me:** `GET /v1/projects/zjabnywjpvpgmtajygqy/config/realtime` → `"private_only":
true`. **[measured 2026-08-21]** Still on.

**The closure gate that was actually satisfied** — both instruments, one run, on production:
negative (`run-channel-private-matrix.mjs`) all four cells CHANNEL_ERROR, *plus a control REST read
returning 200 to prove the key and project were alive*; positive (`e2e-run-channel.mjs` 21/21,
`e2e-party-channels.mjs` 6/6) the real owner still receiving on `run`, `chat` and `bk`.

**And a consequence for the privacy policy:** `privacy-policy.md:91` claims 제공 대상 is the
booking's owner only. That sentence was false while the channel was public and **is now true**.
The legal session released that specific publication blocker and said explicitly that it released
*only* that one.

### 3.2 ✅ The route identity columns — closed by `0107`

Published routes carried `verified_run_id`, `verified_runner_id` (a direct FK from a public course
row to a **named person**), `checked_by` and `checked_at`, and `routes` had
`create policy "routes public read" … using (true)` (`0082:99`). Anon reads returned all four.

Closed by column-level REVOKE from **both** `anon` and `authenticated`, plus a guard in
`promote_route_from_run` that refuses to promote unless a de-identified `routes_public` view exists
and a transitive `pg_depend` walk proves it reads none of the three. `checked_at` deliberately
stays — it is rendered.

Verified over the wire including **`select=*`** (the attacker's actual first move, and the case a
named-column test passes while `*` still leaks), and confirmed for the logged-in case via
`information_schema.column_privileges` **filtered to `privilege_type='SELECT'`** — the unfiltered
query lumps in UPDATE/REFERENCES and reads as though the columns were still granted.

Today: **169 routes in production, 0 with a non-null `verified_run_id`.** **[measured]** The
promotion pipeline has never run. This was a latent defect closed before it fired.

### 3.3 ✅ `identity_verified` — closed by ruling, not by clearing the flag

All **9** `runners` rows carry `identity_verified = true` while PASS is unintegrated and
`profiles.phone` is NULL for every user — a flag sitting behind copy telling an owner a stranger was
personally verified (`app/app/safety.tsx`: *"운영자가 화상 통화로 러너를 직접 만나 신분증을
확인하고 한 명씩 승인해요"*).

**Sean answered, verbatim, 2026-08-15: "3: b" = all 9 runners are TEST DATA.**
`docs/decisions/awaiting-sean.md:56-58`. [from-doc — the ruling; the state below is mine]

Measured today: **9 runners, 9 with `identity_verified = true`, 9 rows in `club_test_accounts`,
0 profiles with a phone number.** **[measured]** So the test-data marking landed and covers all 9.

⚠ **The flag itself was never cleared.** The queue entry says *"the flag/copy gets fixed"*; the flag
is still `true` on all nine. [inferred] This is closed as a *legal* question (nobody is being told a
falsehood about a real person, because there are no real people) and **open as a data-hygiene
question** — the day a real runner is created, the seed rows are indistinguishable from them on this
column unless the marking is what gates the copy.

### 3.4 ✅ The points economy is 마일리지-shaped, not 선불전자지급수단

**The risk the source review flagged (§10.3):** an in-house wallet, stored value, or transferable
credit triggers 전자금융거래법.

**Measured:** `miles_ledger` (`0001_init.sql:299-306`) has **SELECT-only RLS for clients** —
`create policy "miles self read" … using (profile_id = auth.uid())` (`0002:127`). There is **no**
INSERT/UPDATE/DELETE policy for any client role; every writer is a `security definer` server
function. **No transfer, withdrawal, gifting or cash-redemption path exists anywhere.** Points are
earned from the issuer's own service and redeemed for the issuer's own gear (`gear_claims`,
`0001:326`). Production holds 12 `miles_ledger` rows. **[measured]**

The repo states the distinguishing test in its own words at `0115_account_deletion.sql:100-107`:

> *"하이 포인트 is a non-transferable promotional balance with no cash-out path, so forfeiting it
> creates no 잔여 재산 to settle. … `km_lots.won_paid` is '고객이 이 로트에 실제로 낸 ₩'
> (`0075:113`). Miles are issued BY us, FOR free; km is bought FROM us, WITH cash. Forfeiting the
> first is a product rule; forfeiting the second would be keeping someone's money."*

That distinction is load-bearing and is enforced: account deletion forfeits miles with **no gate**,
and refuses outright on a non-zero `km_balance` (`0115:295`).

⚠ **The line to watch, while it is still cheap:** the conclusion depends *entirely* on
non-transferability and no cash-out. **If points ever become giftable, sellable, or refundable in
cash, the analysis changes category** — and that is exactly the kind of feature that ships as a
delight without a legal review. It is worth one sentence to counsel now and a `comment on table
miles_ledger` recording why the constraint exists.

### 3.5 ✅ Account deletion — built, deployed, and it satisfies App Store 5.1.1(v)

This was the top-ranked launch blocker on 2026-08-19 (`awaiting-sean.md:491-502`) and it closed on
2026-08-20 under decision 🔵 O-6.

**Measured today:**
- `supabase/migrations/0115_account_deletion.sql` (866 lines) is **applied** in production.
- `delete_my_account_tx` exists (1 row in `pg_proc`); `account_deletions` table exists.
- Edge function `delete-account` is **ACTIVE, v1**, created **2026-08-20 10:10 KST**.
- Client: `app/app/settings.tsx:80-83` renders a real 계정 삭제 row (promoted out of the old
  「준비 중 · 문의로 처리」 InfoRow), opening `app/src/components/delete-account-sheet.tsx` — a
  hold-to-confirm destructive sheet, with `deleteMyAccount()` at `api.ts:4278-4288` posting
  `{ confirm: 'DELETE' }`.
- **0 deletions executed, 0 tombstones.** The path has never run against a real account.

**Why the design is worth understanding before you touch anything adjacent** — it is the most
carefully reasoned migration in the repo and it turns on a single finding:

`profiles.id → auth.users(id) ON DELETE CASCADE` made `auth.admin.deleteUser()` a **33-path
cascade** that silently destroyed five classes of legally-required record — `payment_attempts`,
`delegation_consents`, `dog_custody_events`, `gate_code_access_log`, `runner_applications` — while
*also* being unusable, because `bookings.owner_id` is NO ACTION and aborts for any user who has
ever booked. Dropping the edge converts 33 silent cascade paths into zero and makes every deletion
an explicit, named list.

And the reviewer then executed the explicit list and found it reproduced the same destruction one
hop down (`gate_code_access_log` went 1 row → 0 via `addresses`). The sentence the file distils:

> **AN EXPLICIT DELETE LIST IS ITSELF A CASCADE SOURCE, AND IT MUST BE CLOSED OVER EXACTLY LIKE THE
> FK GRAPH.**

Hence §F: a recursive `pg_depend`/FK closure watchdog whose **root set includes the RPC's own delete
list**, which **refuses to apply** if the closure reaches a retention table.

**What is kept, and under what basis** (`0115:72-87`): bookings · payments · ledger_items · payouts
· club_fee_items · gear_claims · payment_attempts (전자상거래법 제6조 + 시행령 제6조 — 계약·청약철회
5년, 대금결제 5년, 소비자불만 3년) · delegation_consents · club_acks · runner_applications (**consent
evidence — deleting the evidence of consent is not honouring a withdrawal of consent**) ·
gate_code_access_log · club_phone_access_log (안전조치 audit) · dog_custody_events ·
dog_run_segments · assignment_events · session_dogs (duty-of-care evidence) · incidents ·
club_incidents · club_incident_evidence · runs · chat_messages · reviews · addresses (KEEP+ANON) ·
dogs (`dogs.name` kept — a kept booking is a contract record whose subject is *this* dog).

**PIPA 제37조 note:** the *legal* finding on the old state was mild — a support-mediated path
satisfies 처리정지·동의철회. The hard blocker was Apple's. Both are now closed.

⚠ **What this does NOT close:** the `runs.trace` retention cap (§2.6). 0115 says so itself at `:84-86`.

### 3.6 ✅ Not engaged at all — record these so nobody re-opens them

- **동물운송업 (vehicle transport).** Searched the client and schema: **nothing exists.** The
  review's second-highest RED is not engaged. [from-doc, `readiness-review-nonlocation:168-169`]
- **Fixed facility / 동물위탁관리업.** None — consistent with the reading that an outdoor
  handoff-run-return service may fall outside the current definition. Still a question for 서초구.
- **Body camera and audio.** Absent entirely, which beats a feature flag. `RECORD_AUDIO` was removed
  from Android on 2026-08-08 because nothing used the microphone
  (`appstore-privacy-answers.md:46-49`). ⚠ **Store metadata must not mention bodycam** —
  `launch-checklist.md:155` flags that positioning.md and the investor one-pager both do.
- **Shopping.** `app/app/shop.tsx` is an explicit preview shell; no sales, no feed labelling, no
  veterinary medicines. The review's §12.1 is prospective.
- **Ad/analytics/tracking SDKs.** None: no Sentry, Firebase, Amplitude, Mixpanel, Segment, Facebook,
  AdMob, AppsFlyer, Adjust, Branch. So **no ATT prompt is required** and "Do you use data to track
  users" is a clean No. [from-doc, `appstore-privacy-answers.md:13-16`; consistent with the
  `app/package.json` I read today]
- **The GPS session state machine is a compliance asset, not a gap.** `geo.ts` starts and stops the
  background task with the run (`:234-266`), and `app.json:77` leaves **Android background location
  off**. Tell counsel this — it is the review's own §13.2 ① and it is genuinely green.

---

## §4. Ops and release state — measured

Everything in this section was executed today, 2026-08-21, unless marked otherwise.

### 4.1 Builds and updates: **zero, ever**

```
$ cd /Users/sean/dev/daengrun/app && npx eas build:list --json --non-interactive --limit 20
[]

$ npx eas channel:list --json --non-interactive
testflight | branches: [('testflight', 0 update groups)]
```

**[measured]** No EAS build has ever been produced. No OTA update has ever been published. One
channel (`testflight`) with one branch and zero update groups. `app/eas.json` defines four profiles:
`development`, `preview`, `testflight` (store distribution, `autoIncrement`, `m-medium`),
`production`.

⚠ **The worktree cannot run EAS** — `app/node_modules` is not installed here. Run from
`/Users/sean/dev/daengrun/app`.

**Why this fact keeps mattering:** it is load-bearing for at least three other decisions —
the `routes.trace` revoke was free because no installed binary reads it; `private_only` could be
flipped without a staging project because the forced-upgrade population is zero; and the
service-role key rotation was provably clean because no artifact ever shipped.

### 4.2 TestFlight: **never uploaded** — and the one irreversible decision in front of it CLOSED today

[from-doc] `docs/session-handoff.md:288` — ui drove the flow *to the 2FA prompt* and stopped;
`:353` records that the session **refused to enter Sean's Apple credentials under any authorization**,
which is correct and is the model for every credential carve-out in this repo.

**The bundle-ID trap, and its resolution.** `docs/decisions/awaiting-sean.md:373-385` raised
🔴 §0-septemvicies on 2026-08-20: `app/app.json:22` carried `com.seankookim.daengrun` — the
**retired** brand (댕런 was retired 2026-07-28; the product is 도그스하이) — and **a bundle ID is
immutable once the first build reaches App Store Connect.** After that, changing it means a new app:
new listing, new reviews, new URL, momentum from zero. TestFlight *is* the first upload, so the
queue was ordered wrong and only Sean could reorder it.

✅ **CLOSED at `b6ee192` (2026-08-21), option A, before any upload** — *"bundle id:
com.seankookim.daengrun -> com.seankookim.dogshigh (Sean, 2026-08-20) — before the first upload,
which is when it locks forever."* **[measured]** Current state: `app/app.json:22` =
`com.seankookim.dogshigh`, widget target `:99` = `com.seankookim.dogshigh.ExpoWidgetsTarget`.

⚠ **The queue entry at `awaiting-sean.md:373-385` is now stale** — it still quotes the old id as
current. [measured] Whoever next touches that file should mark it ✅ rather than leave a 🔴 that has
been fixed. This is a live tree: it moved from `9475c79` → `2cde1a2` → `b6ee192` while I was writing
this file, so **re-measure before you act on any line here.**

Also landed for the upload: `b696fa3` (2026-08-19) sets `app/app.json:20`
`"ITSAppUsesNonExemptEncryption": false`, so TestFlight will not stall on the manual export-compliance
question. **[measured]**

### 4.3 Deployed edge functions — all eight, with versions

`supabase functions list --project-ref zjabnywjpvpgmtajygqy` **[measured 2026-08-21]**:

| slug | status | version | last updated (KST) | `verify_jwt` |
|---|---|---|---|---|
| `create-booking-hold` | ACTIVE | **10** | 2026-08-19 19:03 | true |
| `transition-booking` | ACTIVE | **34** | 2026-08-19 19:03 | true |
| `settle-run` | ACTIVE | 14 | 2026-08-13 17:18 | true |
| `open-drop` | ACTIVE | 8 | 2026-07-29 11:31 | true |
| `geocode-address` | ACTIVE | 1 | 2026-08-10 15:46 | true |
| `collect-charges` | ACTIVE | 1 | 2026-08-13 16:57 | **false** |
| `confirm-payment` | ACTIVE | 1 | 2026-08-13 17:18 | true |
| **`delete-account`** | ACTIVE | 1 | **2026-08-20 10:10** | true |

⚠ **`docs/session-handoff.md:285` is stale**: it records `create-booking-hold v8 · transition-booking
v33` and does not list `delete-account` at all. Both moved on 2026-08-19 evening (O-5, pay-after-run)
and `delete-account` landed the next morning. **This is the concrete illustration of the domain's
core discipline — `functions list` is the only source on what is deployed; a doc's memory is not.**

⚠ `collect-charges` runs with `verify_jwt: false` — it is the cron-invoked charge dispatcher and is
protected by `CRON_COLLECT_KEY` instead. [inferred from the name + `docs/pre-charging-checklist.md`
§2.3, which warns that `CRON_COLLECT_KEY` and the Vault `charge_dispatch` secret are *one value in
two places with nothing verifying they agree*.]

⚠ `supabase/functions/create-payment-intent/` exists in the repo and is **NOT deployed**. [measured]

### 4.4 Migrations and suites

**[measured]** Files on trunk: **0001 → 0115** (114 `.sql` files — `0105` no longer exists, having
been superseded and deleted by `0111_booking_entry_rebuild.sql`). Applied in production:
**0001–0104, 0106–0115.** No pending migrations. Test suites run to **150** (numeric sort —
`ls | sort` is lexical and will lie to you: `117_` sorts before `97_`).

`supabase/migrations/HELD` is **empty of entries**, which is the state it should spend most of its
life in. `supabase/migrations/REGISTRY.md` is the number ledger; **numbers come from origin, never
from a doc**, and a number is taken when *either* its row *or* its file reaches origin.

### 4.5 Dashboard toggles — **both still open**, measured today

`docs/security-dashboard-checklist-2026-08-19.md` prepared these on 2026-08-19 and says
"NOTHING HERE HAS BEEN CHANGED." That is still true two days later. **[measured 2026-08-21]**

```
external_email_enabled = True        ← should be False (Sean's ruling "b": Kakao only)
external_kakao_enabled = True        ← correct, leave on
disable_signup         = False
external_anonymous_users_enabled = False   ← correct
site_url = daengrun://login
uri_allow_list = daengrun://login, exp://10.16.75.70:8081/--/login, daengrun://**,
                 exp://**, exp://172.30.1.44:8081/--/login, exp://172.30.1.44:8081
```

**Two open doors.** The email provider is still on server-side even though the client's email path
was removed — *an email door left open server-side is a signup path outside the app.* And the
redirect allowlist still carries two wildcards (`exp://**`, `daengrun://**`) and two stale LAN IPs;
it should be exactly `daengrun://login`.

⚠ **Dashboard only. Do NOT use `supabase config push`** — the repo's `config.toml` has no `[auth]`
section, so a push would send CLI defaults for every auth setting and could switch Kakao off. That
is written at `security-dashboard-checklist:8-10` and repeated in the handoff.

**Also measured and correct, leave alone:** realtime `private_only = true`; JWT expiry 3600;
refresh-token rotation on.

### 4.6 The service-role key, and the deploy path

**Location: `~/.config/daengrun/ops.env` (chmod 600, outside the repo).** [measured — the file
exists with `-rw-------` permissions. I did not read its contents and Codex should not either.]

**Never `app/.env`.** `app/.env.example:20-25` carries the rule verbatim:

> *"NEVER put SUPABASE_SERVICE_ROLE_KEY (or any privileged key) in app/.env or anywhere under app/.
> Expo tooling reads app/.env; a service-role key one `EXPO_PUBLIC_` rename away from the bundle is
> a full-RLS-bypass credential in a client artifact."*

Ops scripts read `~/.config/daengrun/ops.env` or `$DAENGRUN_OPS_ENV` (`app/scripts/e2e-club.mjs:99`).
⚠ **The older scripts under `scripts/` still say "root .env"** — `geocode-backfill.mjs:12`,
`pilot-metrics.mjs:9`, `migrate-private-media.mjs:21`, `seed-runners.mjs:21`, `e2e.mjs:8`,
`runner-ops.mjs:61`, `wipe-test-data.mjs:6`, `diag.mjs:21`. [measured] Those instructions predate the
2026-08-19 CSO audit and were not swept. Reading them literally re-creates the exact defect the audit
closed. [inferred] Worth a sweep.

**Migration deploys: `bash scripts/deploy-migrations.sh`.** It is the one sanctioned path and it
enforces five things that were each a hand-step somebody skipped:

1. It **fetches and cuts a fresh detached worktree at `origin/redesign-v4`**, so "land on trunk
   before deploy" is structural, not remembered.
2. It moves every file named in `supabase/migrations/HELD` aside *before the CLI sees the tree*, so a
   held migration cannot ship as cargo on someone else's deploy.
3. It always dry-runs first and **prints the list**; with `--push` it refuses unless the pending set
   is exactly the filenames you named.
4. It **never** runs `supabase migration repair`. 🔴 The CLI's own hint
   `migration repair --status reverted 0106 0107 0108` would mark genuinely-applied migrations as
   reverted and corrupt the ledger.
5. It prints `migration list --linked` afterwards so you read back what landed.

Usage: `bash scripts/deploy-migrations.sh` (dry run) then
`bash scripts/deploy-migrations.sh --push 0116_your_file.sql`.

**Edge-function deploys** have no wrapper — `supabase functions deploy <slug>` directly. The parity
oracle is that a redeploy of unchanged source prints "No change found."

### 4.7 Charging: off at four independent layers

**[measured]** `ops_flags` → `payments_live_since = null`, `return_seal_since = null`.
`payments = 0`, `billing_keys = 0`, `ops_recipients = 0`, `payouts = 0`, `ledger_items = 8`.

🟠 One item that becomes real the day this flips: `supabase/functions/_shared/charge.ts:117-118`
sets the PG `orderName` to 「**댕런** 산책 이용료」 and 「**댕런** 예약 취소 수수료」 — the retired
brand plus 「산책」, which is on `docs/positioning.md:44`'s banned-word list. **It prints on a real
person's card statement.** Nothing has ever been charged, so no statement has ever carried it.
[from-doc `awaiting-sean.md:387-395`, and the zero-payments half re-measured by me]

### 4.8 What only Sean can physically do

From `docs/decisions/awaiting-sean.md:369` plus the standing law in `CLAUDE.md`. These are carve-outs
**by nature**, not by policy — they require a credential's *value* or a human identity:

| Item | Why |
|---|---|
| (a) Dashboard → Auth → Providers → Email → **disable** | dashboard credential |
| (b) Dashboard → URL config → allowlist = `daengrun://login` only | dashboard credential |
| (c) **TestFlight upload** — Apple 2FA | Apple credential (the bundle-ID blocker in front of it is now cleared — §4.2) |
| (d) **Forward the two counsel briefs** — and Q6 has a statutory clock | human identity |
| APNs `.p8`, App Store Connect, 사업자등록, 통신판매업, PG contract, the KCC 신고 | credential values / filings |
| Product decisions with real-world consequences (wiping production accounts; changing what users are told about safety) | Sean's call even when the command is trivial |

Claude **may** run `supabase db push`, `supabase functions deploy` and `git push`, subject to the
conditions in `CLAUDE.md` (gates green first; never from a tree carrying an unfinished migration;
verify after, don't assume; announce what you ran). It may **use** credentials already configured on
the machine but never types, copies or relays a secret's value.

---

## §5. Exhaustive unbuilt list — every compliance and ops item that does not exist

Ranked roughly by when it starts mattering. Sizes are [inferred].

### 5.1 🔴 The `runs.trace` purge cron, with its pin on `cron.job`
- **Statute:** 위치정보법 시행령 제26조의2 (one-year cap even with separate consent; destruction on
  purpose achievement).
- **State:** nothing exists. 17 crons, none touches location.
- **Blocked on:** nothing. **Size:** small (one function + one `cron.schedule` + a suite pin).
- ⚠ **The pin must assert the row in `cron.job`, not the existence of the function.** `0060:142-147`
  is the precedent: a function annotated "(cron: 매분)" that was never scheduled, while a comment
  claimed otherwise. Legal ranked this **above** the 맹견 gate.

### 5.2 🔴 The 위치정보 이용·제공 확인자료 access ledger
- **Statute:** 위치정보법 제16조 (automatic recording); Standards for Administrative and Technical
  Safeguards (≥ 6 months retention).
- **State:** no table, no writer. `privacy-policy.md:95` already promises the right.
- **Blocked on:** nothing. **Size:** small-medium. **Copy `club_phone_access_log` (`0049:156-163` +
  writers at `0049:236-246`, `0053:435-445`), NOT `gate_code_access_log`** — the latter has never had
  a writer (`0060:52-53`).
- **Free protection already in place:** `0115:788-796`'s `%access_log` wildcard in the deletion
  watchdog.

### 5.3 🔴 Consent versioning — and the owner side has no record at all
- **Statute:** 위치정보법 / PIPA — the review's §13.2 ③ asks for consent **version, time, text,
  device, withdrawal**.
- **State, measured:**

| Surface | Persisted? | Versioned? | Where |
|---|---|---|---|
| Runner application (terms / privacy / ID check) | ✅ **and `not null check(...)`** — an application cannot exist without all three | ❌ **no version, no text snapshot, no device** | `0062:81-83` |
| Owner login (ToS + privacy) | ❌ **nothing recorded at all** — implied consent copy only | ❌ | `login.tsx:110-111` |
| Location consent | ❌ **no table** | ❌ | — |
| Club delegation | ✅ | ✅ `doc_id`, `doc_version` (hardcoded `'v1'`, never bumped) | `0040:137-138`, `0048:141-144` |
| Club waiver | ✅ | ✅ `session_people.waiver_version`, client constant `CLUB_WAIVER_VERSION = '2026-07-29'` | `0030:73`, `api.ts:3174` |
| `delegation_consents.method_consent` / `photo_consent` | ✅ | ❌ (covered by the row's `doc_version`) | `0053:32`, `0040:140` |

- **The pattern to copy exists in-repo** (`0040`/`0030`) and the immutability idiom is written down:
  `0048:140` — *"불변 동의 기록 (§12) — 수정 RPC 없음, 재동의 = 새 행."*
- **Blocked on:** nothing for the mechanism; counsel for the *text*. **Size:** small per surface.
  **Build the location consent versioned from day one** — that was legal's explicit advice
  (`awaiting-sean.md:501-502`).

### 5.4 🔴 The statutory location-consent gate ahead of `geo.ts:175`/`:216`
- **Statute:** 위치정보법 제18조/제19조. Order must be `statutory explanation + consent → in-app
  Start Tracking → OS permission`.
- **State:** absent; two call sites, plus two callers with no rationale at all
  (`club/run/[sid].tsx:164`, `club/session/[sid].tsx:403`).
- **Blocked on:** counsel for minimum content (brief Q3). **Size:** medium (a gate screen + a
  versioned consent record + wiring all four call sites).

### 5.5 🔴 The 위치기반서비스 이용약관 split
- **Statute:** 위치정보법 requires it as **its own document**, not a clause inside the privacy policy.
- **State:** `privacy-policy.md` §3 covers the substance; there is no separate document.
- **Blocked on:** counsel. **Size:** small (a document), but it is one of the four layers the review
  named and layers 3 and 4 are both absent.

### 5.6 🟡 The 맹견 exclusion
- See §2.5. Small. Unowned.

### 5.7 🟡 Admin access controls for location — dual approval, audit log, time limit
- **Statute:** the review's §13.2 ⑦.
- **State:** none, and **there is no admin role in RLS to build on** (`0082:176`). Admin access today
  is the service key and the SQL console — unlogged and unbounded.
- **Size:** medium-large. [inferred] This is the prerequisite for §5.8 and §5.11 too.

### 5.8 🟡 User-facing controls: emergency stop · withdraw location provision · deletion of location
data · data-subject requests
- **Statute:** the review's §13.2 ⑨; PIPA 제35조/제36조/제37조.
- **State:** none of the four exists as a user-facing control. Account deletion (§3.5) covers a
  different right. **Size:** medium.

### 5.9 🟡 Moderation / 임시조치 tooling for the feed
- See §2.9. **Copy `club_chat_report` (`0049:127-143`).** Requires §5.7 to have an actor. Medium.

### 5.10 🟡 The overseas-transfer disclosure check
- **Statute:** 개인정보 보호법 제28조의8.
- **State:** no automated check exists; largely defused because the region is Seoul, but *storage
  location* ≠ *processor nationality* and the counsel brief correctly refuses to conclude.
  Supabase's DPA, subprocessor list and region are unverified against
  `privacy-policy.md:124-128`. **Blocked on:** counsel + reading Supabase's DPA. Small.

### 5.11 🟡 Incident and insurance design
- **State:** ToS 제7조 honestly says there is no pilot insurance and the app agrees. `incidents`,
  `club_incidents`, `club_incident_evidence` tables exist; ⑪ two-sided incident confirmation ships
  phone visibility during an open incident.
- **Owed:** 제6조2 (owner bears undisclosed-condition risk) may be void under 약관규제법 제7조 —
  counsel's call, and it is *the clause that decides who pays when a dog is hurt*. Also owed: the
  privacy policy and the App Store filing must be amended for ⑪ **before it ships**
  (`docs/decisions/incident-verification.md:161, 209`).

### 5.12 🟠 The 통신판매업 / PG chain and its app-side consequence
- **State:** step ① 사업자등록 not started. The chain is **not serial** — 통신판매업 needs the
  구매안전서비스 이용 확인증 that the PG issues, so **start the PG application before the 통신판매업
  filing** (`payments-paperwork-checklist.md:18-32`).
- **App-side consequence, deliberately unbuilt:** the 전자상거래법 사업자정보 footer
  (상호·사업자등록번호·통신판매업신고번호·대표·주소·연락처). `app/app/payments.tsx:30-32` states why:
  *"those numbers do not exist yet (사업자등록 pending). Fabricating them would be both a lie and a
  legal claim. It lands with the real filing, not before."* **Correct. Do not build it with
  placeholders.** It becomes a small client slice the moment ① and ③ return.
- Also flagged in the same checklist: 고객센터 연락처 is currently a `mailto:` (`payments.tsx`);
  price display under the price-invisibility doctrine needs confirming against 표시 의무.

### 5.13 🟠 App Store questionnaire correction
- See §2.4. Two independent staleness items (background location; phone purpose under ⑪). Small,
  unblocked, and it stops being free at the first upload.

### 5.14 🟢 Smaller, recorded so they are not lost
- **The `avatars` bucket decision** — finish the private-media migration or rewrite policy §4. The
  backfill script exists (`scripts/migrate-private-media.mjs`) and has never run (`media` holds 0
  objects). [measured]
- **Concrete retention periods** in `privacy-policy.md` §5 — currently placeholders (`:116-117`).
- **개인정보 보호책임자** — §9 is blank.
- **시행일 and a public URL** for both documents — App Store review requires a reachable privacy
  policy URL.
- **`identity_verified` flag hygiene** — see §3.3.
- **The `scripts/` "root .env" instructions sweep** — see §4.6.
- **`purge_old_chat` does not cover `club_chat_messages`** — [measured] the 30-day retention claim
  in the app applies to one of the two chat tables. Worth checking what the copy actually promises.
- **`km_ledger` cron specified but never registered** (`0075:26`). Money-adjacent, not legal.

---

## §6. Traps — what looks compliant and is not

### 6.1 A policy that promises a right the system cannot deliver is worse than silence

`privacy-policy.md:95` grants the 위치정보 이용·제공 확인자료 열람권. No ledger exists. If a runner
exercised it today, there would be nothing to show them — and the document proves we knew the right
existed.

The same shape appears three times in this domain, and recognising it is the single most useful
pattern to carry forward:

| The sentence | The architecture | Status |
|---|---|---|
| *"제공 대상: 해당 예약의 보호자에게만"* (`:91`) | a public broadcast channel any anon client could join | **repaired** — the architecture moved to match |
| *"러닝 기록 및 위치정보 … 필요한 기간"* (`:112`) | no purge mechanism of any kind | open |
| *"확인자료를 열람·고지 요구할 수 있습니다"* (`:95`) | no ledger | open |

### 6.2 Softening the wording is the WRONG fix for a statutory duty

The tempting repair for §6.1 rows 2 and 3 is to edit §3 and §5 so the document matches the system.
**That would be wrong and it would not work.** Both obligations are **statutory, not contractual**:
Article 16's confirmation records are owed whether or not the policy mentions them, and the one-year
cap binds regardless of what the retention table says.

`readiness-review-2026-08-19.md:440-446` states it in the form worth keeping:

> **"Deleting the sentence removes the evidence of the gap, not the gap. The fix is a deletion job
> and an access ledger; the policy is already telling something close to the truth about what the law
> requires, and the system is what has to catch up."**

[inferred] The corollary generalises past this repo: when a document and a system disagree, ask
first which one the law is addressing. If it is the system, editing the document is destroying
evidence.

### 6.3 The measurement discipline — read the layer you describe; the probe beats the argument

This domain produced the same near-miss **four times**, and every one was caught only by executing
the actual path instead of reasoning about it.

1. **The route grant table.** `information_schema.column_privileges` unfiltered lumps in
   UPDATE/REFERENCES and reads as though revoked columns are still granted. Filtering to
   `privilege_type='SELECT'` gives the opposite answer. *Caught before it became a claim.*
2. **The reviews read path.** The RLS policy at `0002:115` says party-scoped; the client at
   `api.ts:2804` asks for all of them. The reviewer nearly reported the client's intent, then
   measured — and got `401 / 42501 "permission denied for function is_booking_party"`. **⚠ And then
   drew the wrong conclusion from the right measurement**, because `anon` failing on a *function*
   permission says nothing about `authenticated`, and `0011_review_storefront.sql` had added a
   fourth policy that no one read. I found this today by querying `pg_policy` instead of the
   migration I expected to be authoritative. **This is the trap eating its own author** — see §2.8.
3. **`send() === 'ok'` is not authorization.** A publish returning ok proves the socket accepted the
   frame, not that anyone was allowed to receive it. Assert non-delivery to a listener.
4. **The stranger-only instrument.** After `private_only` was flipped, all four matrix cells went
   CHANNEL_ERROR — which is equally consistent with a dead credential, a down project, or a client
   that never connects. The control run (same key, same project, REST read → HTTP 200) is what made
   the refusals *authorization decisions* rather than *breakage*.

The rule those four collapse into, and it is written at the top of
`docs/legal/evidence/run-channel-private-matrix.mjs:50-52`:

> **Every instrument that can only observe failure will report success when the system is dead.**

And its sibling, from `readiness-review-2026-08-19.md:255-257`:

> **Reading the config tells you what was asked for, not what the system does.**

### 6.4 Four more specific traps you will hit

- **`supabase db query` with multiple statements returns only the LAST row-producing statement.** A
  0-row UPDATE will surface the preceding `set_config` row and read as ALLOWED. Chain probes as
  separate statements. Parse the JSON with python — `grep` is line-based and the output is not.
- **`do $$…$$` auto-commits.** Use explicit `begin`/`rollback` for any probe that writes.
- **A bare column REVOKE under a table-wide grant is a no-op**, and `has_column_privilege` metadata
  looks identical for "granted all" and "whitelisted." Execute the read as the role.
- **`ls supabase/tests | sort` is lexical** — `117_` sorts before `97_`. Use
  `grep -oE '^[0-9]+' | sort -n | tail -1`.

### 6.5 The provenance rules this fleet learned the expensive way

- **A relayed decision is evidence, not authority — including from another session.** A ruling is
  settled when the human's own words are on origin. On 2026-08-13 two sessions held contradictory
  records of the same money decision, both in good faith.
- **Unpushed work reserves nothing** — decisions included.
- **✅ only for Sean's own words on origin.** A stand-in's call is 🔵, reversible, and carries its
  reasoning.
- **Date every constraint and every derived dataset.** `readiness-review-2026-08-19.md:403-407`
  models this: it records which half of a finding was measured and which half was relayed, *so a
  later reader can see which line to correct if the relay was wrong.*

---

## §7. Verification commands — safe, read-only, re-runnable

```bash
# Deployed edge functions — the ONLY source on what is live. git's silence is not evidence.
supabase functions list --project-ref zjabnywjpvpgmtajygqy

# Applied migrations
supabase migration list --linked

# Charging off-switches
supabase db query --linked "select * from ops_flags"

# Crons — confirm nothing purges runs.trace (expect 17 rows, none location-related)
supabase db query --linked "select jobid, jobname, schedule, command from cron.job order by jobid"

# Location ledger / consent tables — expect NO location ledger
supabase db query --linked "select table_name from information_schema.tables
  where table_schema='public' and (table_name like '%log%' or table_name like '%ledger%'
     or table_name like '%consent%' or table_name like '%report%') order by 1"

# The reviews policy set — expect FOUR policies, incl. 'reviews storefront read'
supabase db query --linked "select polname, pg_get_expr(polqual,polrelid), polcmd
  from pg_policy where polrelid='public.reviews'::regclass order by polname"

# Realtime private_only — expect true
curl -s -H "Authorization: Bearer $(security find-generic-password -s 'Supabase CLI' -w)" \
  https://api.supabase.com/v1/projects/zjabnywjpvpgmtajygqy/config/realtime

# Auth surface — expect email:true (still open) and kakao:true
curl -s "https://zjabnywjpvpgmtajygqy.supabase.co/auth/v1/settings" -H "apikey: <anon>"

# EAS — expect [] and one channel with zero update groups
cd /Users/sean/dev/daengrun/app && npx eas build:list --json --non-interactive
cd /Users/sean/dev/daengrun/app && npx eas channel:list --json --non-interactive

# The realtime negative instrument (needs app/node_modules; run the POSITIVE arm too or it lies)
DAENGRUN_APP_DIR=/Users/sean/dev/daengrun/app \
  node docs/legal/evidence/run-channel-private-matrix.mjs

# Migration/suite numbers — from ORIGIN, never from a doc
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
ls supabase/tests | grep -oE '^[0-9]+' | sort -n | tail -1
```

**Expensive / destructive — do not run casually:** `supabase db push` (only via
`bash scripts/deploy-migrations.sh --push <exact filenames>`) · `PATCH …/config/realtime
{"private_only":false}` (rollback only) · `eas build` (Sean's Apple 2FA) ·
`supabase migration repair` (🔴 **never** — it corrupts the ledger in this repo).

---

## §8. If Codex does five things in this domain, do these

1. **Send the two counsel briefs.** `docs/biz/location-law-counsel-brief.md` (v5) and
   `docs/legal/contract-status-counsel-brief.md`. Q6 of the first has a statutory clock that started
   at discovery on 2026-08-19. This is Sean's errand and it costs one email. Fix the brief's two
   known residuals first (footer provenance; **Question 4 was never updated** after §2-bis landed).
2. **Correct `readiness-review-nonlocation-2026-08-19.md` §11 in place.** Reviews *are* readable by
   every authenticated user via `0011_review_storefront.sql` — measured today. The file already
   corrects itself twice; use its idiom, and say why, so the next reader sees the whole reasoning
   chain rather than a clean wrong answer.
3. **Build the two retention items** — the `runs.trace` purge with its pin on `cron.job`, and the
   location access ledger copied from `club_phone_access_log`. Both are statutory, both are small,
   both are unblocked, and legal ranked them above 맹견 because they matter at the first real runner.
4. **Fix the App Store privacy sheet before anyone touches TestFlight.** It is stale in two
   independent ways and it is free to fix today. (The bundle-ID blocker that used to sit in front of
   the upload was closed on 2026-08-21 — §4.2.)
5. **Close the two dashboard toggles.** One minute of Sean's time, and the email provider is an open
   signup path outside the app on the only login route we have.
