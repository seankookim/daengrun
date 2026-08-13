# Awaiting Sean — the return queue

**Purpose: this queue existed only inside one session's conversation.** The announcing session
asked for it to be written down, applying the day's first rule to itself: *unpushed reserves
nothing.* If that session runs out of context the way the 반포 route session did, an
in-conversation queue evaporates — and it would evaporate silently, because nobody knows to
look for a list they never saw.

Ordered by what blocks the most. Nothing here is decided; **🟡 means it is Sean's**, and per the
governance rule in [README.md](README.md) a stand-in's analysis never becomes a ✅.

---

## 1. 🔴 `0088` — `profiles` is readable by **anon**, not merely by logged-in users (P0)

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

## 3-bis. 🔴 ⑬ chat never reaches a phone — blocks ⑪ AND ⑫, needs no ruling to start

Push fires only on a `notifications` insert; nothing writes one when a chat is sent, so
runner↔owner chat is in-app-only. Sean's ⑫ rulings are all *tell someone something*, and his
design gate is *"we dont want the runner stranded in the middle of town"* — today that runner
can message the owner and the owner's phone stays silent. **A build item, not a decision**;
[chat-notifications.md](chat-notifications.md) has the wiring. Two small product calls inside it
are his: whether the push carries the message text (0024 pushes bodies verbatim to a lock
screen), and how to collapse repeats.

## 4. 🟡 ⑫ — the MONEY half (the custody half is ruled)

Does a marketplace incident get its own settle path or become a second caller of 0072's
adjudication · is the runner paid while it is open · what ends the state. Codex's analysis is now
attached to [marketplace-incident-exit.md](marketplace-incident-exit.md) as **🔵 CODEX** (status
stays 🟡). It answers all three and then **explicitly refuses one**, which is the question to
put to Sean first: *when both sides verify an incident but fault is unresolved after the SLA,
should the platform absorb a normal measured runner payout at owner ₩0?* Codex recommends yes
and declines to encode it, because it is a deliberate platform loss outside 0072's model. This is the same class as G1, where he overrode both sessions'
recommendations with a third option neither had proposed.

## 5. 🟡 ⑪ ownership, and ⑪-before-⑫ sequencing

⑪ is ruled, specified, and **unowned** — both build sessions declined it rather than
self-assign. Argument for ⑪ first: its two-sided gate makes ⑫'s adjudication cheaper by ensuring
only verified incidents reach it. ⑪ is also blocked on `0083` landing (its test doctrine models
on 0083's two-party machine).

## 6. 🟡 `profiles.phone` may be null in practice — verify before ⑪ designs against it

Nullable, annotated *"PASS 본인인증 후 확정"*, PASS apparently unintegrated. But
`0062_runner_applications.sql:380` declares `phone text not null`, so the real data may live on
the **application** rather than the profile. Not a decision so much as a fact to establish —
but it changes ⑪'s screen, so it belongs before the build rather than during it.

## 7. 🟡 Deploy go-ahead — `db push`

Everything money-related built today (0080, 0081, 0084, 0085, 0086…) is **inert** until
`ops_flags.payments_live_since` is set, and nothing is deployed: no `db push`, no
`functions deploy`. Gated on his 사업자등록 → 통신판매업 → Toss chain (with 자동결제 심사 in the
same application) regardless, plus billing TEST keys and the §4-2 sandbox matrix.

---

## 8. 🟡 ⑩'s "reward them" is currently paid in sentences only

Your ruling was *"pay the runner and let them know, **reward them** ykwim"*. The pay half shipped
(0085) and the telling half shipped (the notification reads as good news). **The reward half did
not.** The 하이 포인트 ledger exists, but nothing awards points for holding a slot that got
cancelled — and the payments session deliberately did not invent a number you had not set, which
was the right call.

So: **what is the reward, concretely?** Points, and how many? Something else? Or is being paid
the half-fee itself the reward, and the word was about tone rather than a second currency? A
one-line answer closes it; it is a real gap between the ruling and the build either way.

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
