# Legal readiness review — audit against the code, 2026-08-19

**Source document:** `Dogs_High_Korean_Law_Legal_Readiness_Deep_Review_2026-08-19.md` (external,
counsel-adjacent, not a formal opinion). It reviews the product under 위치정보법 / PIPA /
전자상거래법 and returns **RED: pause even a free pilot** on the location architecture.

**This file is the legal session's audit of that review against the actual repository and the
live project.** The review's legal reasoning is not second-guessed here. What is checked is its
*factual assumptions* — because it says up front that its conclusions turn on them, and three of
them are wrong or stale in ways that change what has to be done.

Everything below marked **MEASURED** was executed against production
(`zjabnywjpvpgmtajygqy`, the linked project) on 2026-08-19. Everything marked **READ** is
code-verified only.

---

## 1. The review's headline conclusion survives the audit

RED on the location feature stands. No 위치기반서비스사업 신고 exists, no 위치기반서비스 이용약관
exists, and the runner's only location consent is the OS permission dialog. The review's §5.4
four-layer structure (terms · privacy policy · location terms · runner's express location
consent) is the right frame, and layers 3 and 4 are absent outright.

The exact line where layer 4 is missing is **`app/src/lib/geo.ts:199`** — READ:

```
const perm = await Location.requestForegroundPermissionsAsync();
```

Nothing statutory precedes it. The review's prescribed order is
`statutory explanation and consent → in-app Start Tracking → OS permission`; the code goes
straight to the OS prompt. `app/app/runner/apply.tsx:644` collects three consent checkboxes
(terms · privacy · ID check) and **none of them is a 위치정보 consent**; that file's own comment
(`:207`) records that there is no published 개인정보처리방침 to link to.

## 2. Three factual corrections to the review

### ⓐ "No location-information policy exists" — STALE

`docs/legal/privacy-policy.md` exists (written 2026-08-08) and carries a **§3 위치정보의 처리
(위치정보법)** section covering collection window, purpose, recipient, retention, refusal rights,
and the 이용·제공 사실 확인자료 right. `docs/legal/terms-of-service.md` exists too.

This does not move RED, because the draft is unpublished (시행일 미정, no public URL), is marked
DRAFT-pending-변호사, and is **not** a separate 위치기반서비스 이용약관 — which 위치정보법 requires
as its own document, not a clause inside the privacy policy. But it changes the work: counsel is
reviewing an audited draft whose authors already flagged the same two gaps the review found
(the 신고, and the 국외이전 표기), not starting from zero. Feed the draft to counsel *with* the
review.

### ⓑ "Only the time is removed when a course is published" — INVERTED

READ, `supabase/migrations/0082_route_ladder.sql:178` (`promote_route_from_run`): per-point
timestamps *are* dropped — the function rebuilds each point as
`jsonb_build_object('lat', lat, 'lng', lng)`. So far, as described.

But the published `routes` row then **gains four identifiers** the review did not know about
(corrected 2026-08-19 — the first pass of this file found two of them):

- `verified_run_id` — `uuid unique references runs` (`0082:112`), a direct foreign key from the
  public course to the one specific run that produced it, and through it to that run's booking,
  owner and dog.
- `verified_runner_id` — `uuid references profiles` (`0082:111`), **a direct foreign key from a
  public course row to a named person.** This is the sharpest of the four and the one most
  clearly outside any anonymity claim.
- `checked_by` — the curator who approved activation (`0082:120`).
- `checked_at` — set from `runs.ended_at` (`0083:75`), the run's actual end time.

And `0082:99` is `create policy "routes public read" on routes for select using (true)` — every
row, every status, no auth term. `0099:45`'s own comment independently records the same fact
("`routes` is anon-readable").

**MEASURED**, logged out, public anon key only:

```
GET /rest/v1/routes?select=id,name,status,verified_run_id,verified_runner_id,checked_by,checked_at
→ 200, rows returned, all four columns present
```

**The remedy is a grant/projection change, never a column drop.** `routes_active_is_earned`
(`0082:127`) is a CHECK constraint requiring `checked_at is not null and verified_run_id is not
null` for any route in `active` status — the evidence columns are load-bearing for the activation
invariant. Dropping them would break the route ladder. The 0088 shape is the right one: revoke
the columns from `anon`, or route public reads through a whitelisted view, and leave the table
alone.

So the published artefact is not "a route with the time removed." It is a route carrying the
run, the runner, the curator and the date, published to anonymous readers. That is a stronger
re-identification handle than the review's §5.6 anticipated — it does not require the spatial
re-identification argument at all, because the identity is a foreign key rather than an inference.

**It has not fired yet.** Every `verified_run_id` in production is currently NULL — no route has
been promoted from a real run. And `promote_route_from_run` is deliberately **admin SQL only, not
a client RPC** (`0082:174`), curated by Sean by hand. So this is a latent defect on a pipeline
that has never run, not a live exposure: **it is a cheap column change today and an incident the
first time a course is published.** That timing is the whole point of raising it now.

### ⓒ "Real-time location is provided to the owner" — TRUE, and it is provided to more than the owner

This is the finding the review does not contain, and it is the most serious one.

The live map is a Supabase Realtime **broadcast** channel named `run-<bookingId>`
(`app/src/lib/geo.ts:341`, `:363`, `:374`). READ: nothing in the client sets
`config: { private: true }`, and no migration in the repo creates any policy on
`realtime.messages`. Broadcast, unlike `postgres_changes`, does not consult RLS — and the two
other channels in the app (`chat-*`, `bk-*`) *are* `postgres_changes` and therefore are fine.
Only the location channel is broadcast.

**MEASURED.** Two independent clients holding only the app's public anon key, **not logged in**,
with no booking relationship of any kind:

```
stranger subscribe status: SUBSCRIBED
publisher subscribe status: SUBSCRIBED
publish result: ok
STRANGER RECEIVED: {"lat":37.5109,"lng":126.9959,"km":1.2,"paceSec":330}
```

The unrelated client received the position payload. The channel is public in both directions:
a stranger can **read** the runner's live position, and can **publish** a fabricated position
onto the owner's live map.

The only thing standing between that and a real runner is knowledge of a booking UUID — and the
product hands those out. `supabase/migrations/0042_marketplace_choke_point.sql:21` has the
`marketplace_open_requests` view select `b.id` for every booking in `matching`, granted to
`authenticated` and gated on `is_active_runner()`. **Every active runner who sees a request in
the open pool keeps that booking's UUID, including all the runners who did not win it** — and can
then subscribe to the winner's live GPS for the whole run, at 3-second resolution, over a route
that starts at the dog's home.

Three consequences worth stating separately:

1. It is a 위치정보법 problem, not only a security one. Personal location information is being
   made available beyond the 제공 대상 the runner would ever be asked to consent to.
2. **The drafted privacy policy already makes the opposite claim in writing.**
   `docs/legal/privacy-policy.md:81` — *"제공 대상: 해당 예약의 보호자에게만 제공됩니다. 다른
   이용자나 제3자에게 제공하지 않습니다."* Publishing that sentence against this architecture
   converts an access-control defect into a false statement in a privacy policy. **The policy
   must not be published until the channel is private**, independent of everything else.
3. It sits directly under the review's own launch gate — *"Customer-support and development
   personnel cannot freely access real-time location."* The measured answer is worse than the
   gate contemplates: it is not staff, it is any holder of a public key.

Fix shape (not this session's to build): private channels
(`supabase.channel(topic, { config: { private: true } })`) plus a `realtime.messages` RLS policy
admitting only the booking's owner and its assigned runner, plus `supabase.realtime.setAuth()`.
Owner it needs: **trust** (RLS/grants). It is a client + migration pair, so it needs a REGISTRY
number.

## 3. What the review gets right that this repo can act on immediately

- **§5.2** — the 소상공인 one-month exception does not suspend consent, terms, notice, safeguards
  or deletion. Those apply from day one. A "free beta" label is not a defense.
- **§5.6** — 위치정보 retention is capped at **one year even with separate retention consent**.
  `docs/legal/privacy-policy.md:98` currently says 러닝 기록 및 위치정보 is kept for
  "서비스 제공 및 분쟁 대응에 필요한 기간," which is not a period and cannot be one.
- **§13.2** — "GPS operates only through an explicit session start/end state machine" is already
  true in the code and is worth telling counsel: `geo.ts` starts and stops the background task
  with the run, and `app.json:76` leaves Android background location **off**
  (`isAndroidBackgroundLocationEnabled: false`), foreground-service only. iOS background is on
  (`:74`). That is a genuine compliance asset, not a gap.
- **§10** — 통신판매업 신고 and the PG structure are already Sean's known critical path
  (사업자등록 → 통신판매업 → Toss), and charging is off at four independent layers. The review's
  payment section describes a risk the repo has already gated.

## 4. Open questions this audit cannot answer

- Whether the 위치기반서비스 신고 alone suffices or 개인위치정보사업 registration is also required
  (review §5.1) — needs the architecture diagram in front of the regulator.
- Supabase region, DPA, and subprocessor list versus what `privacy-policy.md:110` discloses
  (review §6.1). The project region is `ap-northeast-2` per `supabase projects list`, which is
  Seoul — worth confirming, because it may make the 국외이전 analysis much easier than the review
  assumed when it wrote "overseas Supabase region."

## 5. Recommendation to the fleet

Nothing here argues with the review's RED. It sharpens it into three things that are actually
buildable, in this order:

1. ~~**Private the `run-*` channel**~~ — **DONE 2026-08-19**, closed at the realtime boundary
   (§6-ter): `private_only=true`, both instruments green on production. Took three passes —
   server RLS alone was bypassable, and the namespace bump was obscurity.
2. **Revoke `verified_run_id` / `verified_runner_id` / `checked_by` / `checked_at` from anon
   route reads** (grant change, not a column drop — see ⓑ) before the first
   course is ever promoted. Cheap now, incident later. — backend/catalog
3. **Insert the statutory location-consent gate ahead of `geo.ts:199`**, and split a
   위치기반서비스 이용약관 out of the privacy policy draft. — client + legal

Items 1 and 2 are engineering with a legal cause and do not wait on counsel. Item 3 and the 신고
itself do.

---

## 6. The counsel brief needs two corrections before it is sent

`docs/biz/location-law-counsel-brief.md` (2026-08-15) is the document that reaches an actual
lawyer. Its region paragraph is better than this file's first framing — it separates 저장 위치
from 처리자의 국적 and declines to conclude 국외이전 either way, which is the right posture. Two
of its facts predate the measurements above and are now contradicted. Raised with the brief's
owner 2026-08-19; not edited here, `docs/biz/` is not this session's surface.

**ⓐ §2 describes the recipient as 보호자, and the storage as covering the live feed.** Both are
wrong in ways that matter differently:

- The live position is channel-only and never reaches the database (`geo.ts:319` — "DB 기록 없음
  — 채널만"). What is stored is the post-run `runs.trace`. 제19조 (제공) and 제23조 (보유) are
  separately regulated, and merging the two flows muddies both analyses.
- The recipient is not the owner. Per §2ⓒ above it is, today, any holder of the public anon key
  who has a booking UUID.

This is the consequential one because **the brief's own Question 4 asks what notice and consent
the 러너 ↔ 보호자 relationship requires.** Answered against "recipient = the booking's owner,"
counsel's advice would be built on a premise the architecture does not satisfy — and the shape of
the 제공 consent design is exactly what turns on it.

**ⓑ §4 states "누가 언제 어디 있었는지는 공개 안 됨."** Per-point timestamps are indeed dropped,
but per §2ⓑ the published row carries the run, the runner (an FK to a named person), the curator
and the run date, all anon-readable. 누가 and 언제 are precisely what publication would expose.
Latent — nothing has been promoted — but §4 asserts it as a present property of the design, and
counsel would rely on it.

The general point, and the reason this is a legal finding rather than a copy edit: the brief's
footer stakes its value on "사실관계는 앱 설정 파일과 서버 상태에서 직접 확인한 내용입니다."
That claim was true when written. Facts verified from configuration go stale the moment someone
probes behaviour instead — which is the same lesson this repo keeps relearning in
`session-handoff.md` §3-ter, one layer up: **reading the config tells you what was asked for, not
what the system does.**

**Applied at `69cf67d`** (trunk), faithfully and with two improvements — the 제19조/제23조 split
is now stated explicitly for counsel, and the remediation shape is named. Two items raised after
reading the applied version: the footer still dates all facts to 08-15 and still describes them
as config-derived, which undersells the one piece of execution evidence in the document; and
**Question 4 was not updated**, so the brief now states the exposure without asking about it.

## 6-bis. Post-0103 re-measurement — the P0 is NOT closed

`0103` (the server half: `realtime.messages` RLS) was deployed the same day. Re-measured against
production immediately after, `docs/legal/evidence/run-channel-private-matrix.mjs`:

```
existing namespace             private=true  -> CHANNEL_ERROR     ← 0103 works
existing namespace             private=false -> SUBSCRIBED        ← and is bypassable
hypothetical bumped namespace  private=true  -> CHANNEL_ERROR
hypothetical bumped namespace  private=false -> SUBSCRIBED        ← rename cannot help
```

The original end-to-end probe still completes unchanged: stranger SUBSCRIBED → publish ok →
payload received.

**0103 is correct and does its job.** `realtime.messages` policies are only consulted for
channels joined *as private*, and against those it holds. But **privacy is the joining client's
choice, not the server's** — and an attacker is not using our client. They pass `private: false`
and the policy is never reached.

**A topic-namespace rename is obscurity, not a control**, and the matrix demonstrates it rather
than arguing it: neither probed topic belongs to any booking, and one is a namespace that does
not exist. Public joins succeed on **arbitrary** topic names. Renaming helps only against a stale
subscriber still sitting on the old topic — worth having, not the control — and the new name
ships inside the client bundle, which is public by construction.

Closure requires **project-level enforcement refusing public channels outright**, so that
`private: false` stops being an available answer. That is project configuration, not a migration,
and it must be flipped *together with* the client half or the live map breaks for every real user.

**Untested and deliberately not assumed:** `chat-*` and `bk-*` are `postgres_changes` — a
different mechanism from broadcast, but riding the same channel transport. Whether disabling
public channels project-wide also breaks them is unknown. It needs testing on a non-production
project before any flip; if they break, they need their own private mode and policies, which is a
larger slice than the one in flight.

**Reporting consequence.** "0103 deployed and verified live" is true, and "authorized for
private-requesting clients" is honest — but either sentence alone reads as *closed*, and it is
not. The accurate line is: **server half correct and live; the channel remains publicly joinable
by any client that asks for public, measured 2026-08-19 post-0103.**

**The agreed closure gate**, recorded here because this file's probes are the instrument it names.
After `private_only` is flipped, on a real build before and on production after, in ONE run:

- **negative** (`run-channel-private-matrix.mjs`) — stranger refused, CHANNEL_ERROR on all four cells.
- **positive** (ui's test) — the booking's real owner, signed in, `private: true` + `setAuth()`,
  SUBSCRIBED and receiving; likewise a real chat thread and a real booking-status subscription,
  since those families convert at the same time.

Fail either and it is not closed. The negative instrument alone cannot prove closure: all four
cells go CHANNEL_ERROR just as readily against a broken policy, a killed transport, or a client
that never connects. **A stranger-only instrument cannot tell "shut" from "dead."**

This exposure produced that mistake three times — negative-only on the first test, `private:
true`-only after 0103, stranger-only on this gate — which is why it is now one rule rather than
three incidents: **every instrument that can only observe failure will report success when the
system is dead.**

## 6-ter. CLOSED (negative half), and the exposure window is now bounded and small

`private_only = true` was set via the management API on 2026-08-19. **Re-measured independently
by this session** — not accepted as relayed:

```
existing namespace             private=true  -> CHANNEL_ERROR
existing namespace             private=false -> CHANNEL_ERROR
hypothetical bumped namespace  private=true  -> CHANNEL_ERROR
hypothetical bumped namespace  private=false -> CHANNEL_ERROR

end-to-end probe: stranger CHANNEL_ERROR · publisher CHANNEL_ERROR · STRANGER RECEIVED: null
```

**Control run, because this file's own rule demands it** — an all-CHANNEL_ERROR result is equally
consistent with a dead credential or a down project. Same anon key, same project, REST read:
`HTTP 200`. The key is valid and the project is up, so the refusals are genuine authorization
decisions. The negative instrument says shut, and is not merely broken.

Per §6-bis this is **half** the gate. **The other half came back green the same day** — ui's
positive arms against production, post-flip: party channels 6/6 (owner receives on `chat` and
`bk`; both stranger `private=false` lines flipped SUBSCRIBED → CHANNEL_ERROR), `run` channel 21/21
(owner receives the runner's position; an attacker's public publish returns `false` — cannot even
connect), and `club-chat` verified on device as host. Recorded by the announcer at `d67d6f0`.

**Both instruments, one run, on production. The P0 is CLOSED at the realtime boundary.**

### ⚠ Constraint released — but only this one

§2ⓒ made publication of the privacy policy conditional: `privacy-policy.md:81` states 제공 대상 is
the booking's owner only, which was false while the channel was public. **That statement is now
true, and this session releases that specific blocker.**

Nothing else about publication is released. The policy remains unpublishable for the reasons in
§1 and §2ⓐ — it is an unreviewed draft with no 시행일, there is still no separate 위치기반서비스
이용약관, the 신고 has not been made, and the retention row (§3, "필요한 기간") is not a period.
A released blocker is not an approval, and this one was narrow.

### The window, and who was actually in it

Counsel needs this for the §7 question, and it turns out to be the fact that right-sizes
everything above.

- **Capability window:** the live-map broadcast shipped `2026-07-25` (`ec8ec95`, "real distance,
  traces, live map"); the club multi-publisher followed `2026-08-02` (`572e9f1`). Closed
  `2026-08-19`.
- **Actual data flow — MEASURED against production:** **9 runs, all inside the window**, first
  `2026-07-28`, last `2026-08-11`. So the channel did carry real 개인위치정보; "no build shipped
  to the App Store" is true but is not the same statement.
- **Affected data subjects — MEASURED:** **one distinct runner and one distinct owner**, and
  across all 9 runs `runner_id = owner_id` — **the same account on both sides.**

So every byte of personal location information that ever traversed the public channel belonged to
a single self-testing account that was simultaneously the runner and the recipient. **No third
party's location was ever on it.**

**What this does and does not license.** It does not make the defect less real: the capability was
live for 25 days and was closed only after being measured. It does substantially change §7 — the
notification duty under 개인정보 보호법 제34조 runs to affected 정보주체, and the affected
population here is one account that was its own recipient. That is a materially different question
from the one §7 poses in the abstract, and counsel should be asked it *with these numbers
attached* rather than in general terms.

**The limit named above is now closed, by measurement rather than by asking.** Re-queried
independently by this session — one row, one distinct id, both roles, all 9 runs:

```
name        runs  first        last         same_acct  distinct_ids
s4kim2025      9  2026-07-28   2026-08-11   true       1
```

The account is `s4kim2025`, which Sean identified as his own test account in his own words earlier
the same day ("i do have a test account under user id s4kim2025"), relayed by the announcer
session. So **"no third party's location was ever on the channel" is established, not inferred.**

Two residual epistemics, small but worth stating because this is the sentence a lawyer will rely
on. `profiles.name` is a user-settable field, so it is an identifier by convention rather than an
authenticated identity; and Sean's confirmation reached this session relayed rather than directly.
Neither is a realistic doubt — one account, one name, and the operator saying it is his — but the
claim that does the legal work is *"the only affected data subject is the operator himself,"* and
that half rests on Sean's statement rather than on anything measured here. **One word from Sean
converts it from well-evidenced to settled**, and it costs nothing to get.

## 7. The question with a clock, and it is not yet asked

Everything above concerns what the product must do before launch. One question runs the other
way, and it is the only item in this audit with a statutory deadline attached rather than a
launch gate:

**Does a live capability for unauthorized third parties to receive 개인위치정보 constitute a
유출 carrying notification and reporting duties** (위치정보법 제16조 관련; 개인정보 보호법
제34조 통지·신고), **or does the absence of any evidence of actual access mean it does not?**

This audit does not answer that and should not. The honest statement of what is known:

- There is a **demonstrated capability** — §2ⓒ, reproduced by execution against production.
- There is **no evidence of actual access** by any third party. Nobody has examined realtime
  access logs, and it is not established that logs of sufficient granularity exist.
- The capability has existed since the live-map feature shipped, not since it was measured.

The gap between "could" and "did" is precisely the lawyer's call, and it is the reason this
belongs in the counsel brief as its own question rather than inside the consent-design question.
Raised for addition as Q6. **If the answer is that a duty arose, the clock started at discovery,
not at remediation** — which is why it is recorded here with a date: measured 2026-08-19,
raised the same day.
