# Awaiting Sean — the return queue

**Purpose: this queue existed only inside one session's conversation.** The announcing session
asked for it to be written down, applying the day's first rule to itself: *unpushed reserves
nothing.* If that session runs out of context the way the 반포 route session did, an
in-conversation queue evaporates — and it would evaporate silently, because nobody knows to
look for a list they never saw.

Ordered by what blocks the most. Nothing here is decided; **🟡 means it is Sean's**, and per the
governance rule in [README.md](README.md) a stand-in's analysis never becomes a ✅.

---

## 1. 🔴 `0088` — PII / PG-key exposure on `profiles` (P0, security)

**Today every logged-in user can read every verified runner's phone number.** Being fixed by the
payments session in `0088`; the fix is not yet on trunk.

⚠ **Recorded here because it exists nowhere in `docs/`** — only as a REGISTRY row and on a
feature branch. A P0 that lives in one branch and one conversation is the same failure this file
exists to prevent. Sean's call is not *whether* to fix it (it is being fixed) but whether it
changes the pilot timeline or needs disclosure once real users exist.

## 2. 🔴 ⑪ conflicts with a written privacy commitment — before ⑪ builds

`docs/appstore-privacy-answers.md:27` declares the phone number's purpose as **"contact during
handoff"**; ⑪ exposes a counterparty's number **during an incident**, which is broader. Two
questions, in order: **has that questionnaire been filed with Apple yet** (it reads as
pre-submission, but "reads as" is not a check), and **the declared purpose must move before ⑪
ships** either way — that file states its own re-audit rule and ⑪ trips it. Detail in
[incident-verification.md](incident-verification.md) §0.

## 3. 🟡 The 안심번호 trade-off — his to confirm knowingly

Departing from the Korean masked-relay norm (Kakao T's pattern) is defensible for a pilot, but
it should be **confirmed, not inherited from a build decision**. `docs/feature-audit.md` already
discusses 안심번호 — prior art to read rather than re-derive.

## 4. 🟡 ⑫ — the three rulings

Does a marketplace incident get its own settle path or become a second caller of 0072's
adjudication · is the runner paid while it is open · what ends the state. Codex's analysis is
attached to [marketplace-incident-exit.md](marketplace-incident-exit.md) as **🔵 CODEX** when it
returns; status stays 🟡. This is the same class as G1, where he overrode both sessions'
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

**Also standing, from ⑩ and ④:** the club-premium disclosure line (④ requires it before
cutover — his wording), and the counsel question on 빌링키 charge-notice obligations (②'s
go-live gate). Both are in their own memos; listed here so the return sweep is one file.

**Maintenance:** whoever adds an item puts it here rather than in a message. Remove an item only
when its memo carries the ruling — not when it has been discussed.
