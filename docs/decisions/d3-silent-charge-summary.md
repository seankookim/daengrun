# ② D-3 — Silent-charge users: accept the silence, or send a monthly summary?

**Status: ✅ BOTH SESSIONS AGREE — monthly summary (not a per-charge push), pending
counsel. UNBUILT.** Sean delegated the call in the club-delegation session (/autoplan);
the charge-slice session reached the same answer independently ("if the answer is
ambiguous, ship C — the monthly summary; do NOT ship a per-charge push by default out
of caution, that is the invisible-cost version of a legal decision"). It builds in the
next money slice (migrations ≥0083) once confirmed.

**The real gate is counsel, and the question is theirs, not ours:** in Korea, for a
marketplace charging a saved card after service on server-computed actuals, is one-time
consent at card link + price disclosure at booking + on-demand receipts sufficient, or
is a per-charge notice required? Ask specifically about 전자상거래법 정보 제공 duties,
여신전문금융업법 자동결제 disclosure, and whether the 자동결제 심사 itself imposes
notification terms.

**Hard dependency either way (not a design choice):** the 전자상거래법 footer
(사업자 정보 + 통신판매업 신고번호) must appear on the payment surfaces the day those
numbers exist. Deliberately omitted today rather than faked, because the numbers don't
exist until 사업자등록 lands.
Adoption AMENDS the price-invisibility doctrine: §0-bis's "money UI in exactly two
modes" gains a third — **one scheduled aggregate receipt per month** (amended in
payments-toss-plan §0-bis in this commit). B is a FLOOR, not a ceiling: if Toss 빌링
심사 or counsel requires per-charge or advance notice, the doctrine itself
renegotiates — that answer is a GO-LIVE requirement.
Origin: pay-rebuild-lab T5 → decision D-3; carried in handoff §4.

## The question

The price-invisibility doctrine (the Kakao T rule) means we send no charge push:
booking confirmation carries no money, the post-run moment is the record card, and
the card issuer's own approval notification does the announcing. **T5 named the
hole: a user who has issuer notifications turned off is charged with no signal at
all.** They'd discover the charges only by opening 설정 → 결제 관리, or their card
statement — possibly months later, as a lump-sum surprise.

## What already mitigates (shipped in the charge slice)

- On-demand receipts: `/payments` 결제 관리 + schedule-sheet 결제 내역 (built, 0080
  slice); consent happened at request (price shown once); actuals-based charging
  disclosed at card link.
- The record card announces every run's *completion* (no amount).
- Exception states (decline/debt/lock) are loud by design (charge-states banners).

## Options (as evaluated)

**A — Accept the silence.** Purest doctrine, zero build — but the surprise-lump-sum
discovery is exactly the experience that produces chargebacks, 민원, and "다크패턴"
framing. Honest-≠-loud holds only while the user *can* notice.

**B — Monthly in-app summary. ← ADOPTED**
- One notification per month with ≥1 charge; no per-run noise; the happy-path price
  still appears exactly once. A monthly ledger digest is a receipt surface, not a
  price ceremony. Creates the auditable we-told-them record for disputes and 심사.

**C — Monthly email statement.** Stronger external artifact; needs email infra +
수신동의; only on counsel's explicit say-so.

## The legal check (the actual counsel item)

- 전자상거래법's transaction-record duty is plausibly satisfied by the on-demand
  surfaces (records kept and accessible, not pushed). Verify, don't assume.
- The sharper constraint: 자동결제 consumer-protection guidance and Toss's 빌링 심사
  conditions. Per-run actuals billing is not a subscription, but the 심사 reviewer
  may not draw that line — **ask Toss during the 자동결제 application what notice
  obligations attach to 빌링키 charges** (launch-checklist §2). If the answer demands
  per-charge or advance notice, B is insufficient and the doctrine renegotiates —
  B never auto-satisfies an unknown obligation.

## Adversarial round — build spec (2026-08-13 dual voices; BINDING on the D-3 slice)

1. **"In-app" is currently a with-sound OS push (both voices, P0).** Every
   `notifications` insert fires Expo push with `sound: default` and the body
   verbatim (0024_push.sql). The summary push is AMOUNT-FREE ("8월 이용 내역이
   도착했어요 — N회의 러닝"); the ₩ amount appears only on the in-app surface it
   opens. Zero schema change needed for this part.
2. **The statement is an immutable row, not a recomputation (Codex).** Unique
   `(owner_id, period)`; period bucketing **Asia/Seoul** (pg_cron runs UTC — a 8/31
   23:30 KST charge is 8월); semantics fixed up front: confirmed charges + cancel
   fees in-period by confirmation time, refunds as their own line in the NEXT
   statement, `waived` runs shown as ₩0 lines in the count. Needs a migration →
   **claim the number in `supabase/migrations/REGISTRY.md` first** (0082 is contested;
   0083 is next free at time of writing).
3. **Tap routing doesn't exist (Codex).** push.ts/alerts.tsx route only
   community/reward/booking kinds — a `system` summary dead-ends on tap. Add a typed
   target that opens `/payments` (or a statement view).
4. **B narrows T5 but doesn't close it for disengaged recurring owners (Claude).**
   An owner who never opens the app while `generate_recurring_bookings` keeps
   generating runs accrues charges with no signal on any channel. The recurring gate
   gains one predicate: pause generation (with notification) after 8 consecutive
   completed runs with zero app opens; Sean-overridable.

## Decision (Sean)

- [ ] A — accept silence
- [x] B — monthly in-app summary — **ADOPTED 2026-08-13 via delegation**; builds in
      the next money slice after Sean's merge confirms
- [ ] C — monthly email
- [ ] Defer until Toss 심사 answers the notice question

Why: cheapest artifact that removes the only genuinely dark reading of the
invisibility doctrine; future-proofs the 심사. Escalate to C only on counsel's
say-so.
