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

1. **Private the `run-*` channel** before anything else, because it is live, measured, and
   contradicted by a document we are about to publish. — trust
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
