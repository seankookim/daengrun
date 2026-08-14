# Awaiting Sean — the return queue

**Purpose: this queue existed only inside one session's conversation.** The announcing session
asked for it to be written down, applying the day's first rule to itself: *unpushed reserves
nothing.* If that session runs out of context the way the 반포 route session did, an
in-conversation queue evaporates — and it would evaporate silently, because nobody knows to
look for a list they never saw.

Ordered by what blocks the most. Nothing here is decided; **🟡 means it is Sean's**, and per the
governance rule in [README.md](README.md) a stand-in's analysis never becomes a ✅.

---

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

## 1-bis. 🟡 Logged-out club browse — a product call, not a security fix (NEW 2026-08-14)

**Raised by trust while sweeping `0002_rls.sql`; detail in
[../security-club-session-exposure.md](../security-club-session-exposure.md). Queued here by the
announcer, because trust deliberately did not — a correct edit in the wrong lane is still the
wrong lane, and this file is the announcer's.**

`anon` reads **13 `club_sessions`**, carrying `meetup_point`, `scheduled_at`, and three host
profile ids. `club_members` and `feed_posts` sit behind the same `using (true)` and should be
decided in the same pass.

**The shape is familiar and it is the reason this is queued rather than patched.** The name-join
to `available_runners` currently returns 0 rows — but only because today's hosts happen not to be
in that view, **not because anything blocks it.** That is a stay of execution, not a defence:
precisely the structure §1 had for `phone`, where the hole was open and only the data was
missing. The day a host lands in that view, a logged-out stranger reads a named person's meeting
place and time.

**Why nobody has written a migration:** a revoke would close it in one line, and might delete a
real acquisition surface. Whether a logged-out person should be able to browse clubs at all is a
growth decision, not a security one. **🟡 — yours.** Three ways it could go:

- **Revoke** — logged-out browse ends; club discovery requires an account.
- **Keep, minus the sharp fields** — browse survives; `meetup_point` and the host ids stop being
  readable without a session, which removes the "named person, place and time" join entirely.
- **Keep as-is** — a deliberate, recorded acceptance rather than an inherited default.

Trust proposed no migration pending your call, which is the right order. Nothing is blocked on
this today; it becomes urgent the moment a host appears in `available_runners`.

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
