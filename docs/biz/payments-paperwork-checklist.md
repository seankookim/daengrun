# Paperwork checklist — 사업자등록 → 통신판매업 → 자동결제 심사

**Owner: Sean (every step is a filing or a credential). money owns the sequence and the
app-side prerequisites.** This is the **paper half**; `docs/pre-charging-checklist.md` is the
**config half**, and the four credential values are that half's finale. Neither is finished
without the other.

Written 2026-08-15 on Sean's ruling **"4: A"** — start the paperwork chain now, keep the charge
machine. The machine stays inert throughout (four independent layers) and the pilot runs on
manual transfer meanwhile, so **nothing here blocks the pilot**; it unblocks the cutover.

⚠ **Confidence marking.** Documents required, ordering and dependencies below are the settled
shape. **Fees and durations are estimates to confirm at filing** — they vary by 지자체 and by PG,
and I would rather you find a number cheaper than the one written here than plan around a wrong one.

---

## 1. The thing that surprises people: the chain is NOT serial

The naive reading is 사업자등록 → 통신판매업 → PG. The middle step blocks on something the **PG**
issues:

    사업자등록 ──► 통신판매업 신고 ──► PG 계약 ──► 자동결제(빌링) 심사
                        ▲                  │
                        └──────────────────┘
              통신판매업 needs 구매안전서비스 이용 확인증, which the PG (or a bank) issues.
              The PG then wants the 통신판매업 신고증 to finish the contract.

**So start the PG application BEFORE the 통신판매업 filing is complete**, to get the
구매안전서비스 이용 확인증 out of them. Waiting for one to finish before starting the other is the
single most common way this chain takes twice as long as it needs to. A bank-issued
구매안전서비스 (several major banks offer it) is the alternative if the PG is slow.

---

## 2. Step by step

### ① 사업자등록 — 홈택스, or your 세무서 in person

- **Needs from you:** 신분증; the business address (a 임대차계약서 if it is not your home);
  업태/종목 selection.
- **개인사업자 is the fast path.** 법인 changes the timeline materially and is a different decision.
- **Produces:** 사업자등록증 — the document every later step asks for first.
- **Cost/time:** free; typically same-day to a few business days online. *Confirm.*
- ⚠ **업태/종목 matters downstream.** It appears on the PG application and should describe a
  service intermediary/plaform, not a pet-goods retailer. Getting it wrong is fixable but
  re-filing costs you a week you will want back.

### ② PG application, started EARLY — 토스페이먼츠 (or another; see §4)

- **Needs from you:** 사업자등록증; 대표자 신분증; 정산 계좌 사본; the service itself, inspectable.
- **Ask for immediately:** **구매안전서비스 이용 확인증** — this is what ③ blocks on.
- **Produces:** the 확인증 now; the contract after ③ returns.

### ③ 통신판매업 신고 — 정부24, or your 관할 구청

- **Needs from you:** 사업자등록증 + **구매안전서비스 이용 확인증** (from ②).
- **Produces:** 통신판매업 신고증, carrying the **신고번호 that must appear in the app** (§3).
- **Cost/time:** 등록면허세, order of tens of thousands of won annually, varies by 지자체;
  a few business days. *Confirm at filing.*

### ④ 자동결제(빌링) 심사 — a SEPARATE review on top of the PG contract

**This is the one that actually gates us, and it is not the same thing as being able to take a
card payment.** A standard PG contract lets you charge a card the user is looking at. 빌링키 —
charging later, with nobody present — is reviewed separately and more carefully, because it is the
mechanism most open to abuse.

- **Needs from you:** the completed contract from ②/③, plus a service the reviewer can inspect.
- **What the reviewer looks for** is in §3. It is mostly *disclosure*, and it is the part we can
  prepare before the paperwork lands.
- **Time: the long pole.** Plan for it to be the longest single step. *Confirm with the PG.*

---

## 3. What the review inspects in OUR app — money's half, and one real gap

The 심사 looks at the running service. These are ours to have ready, not Sean's to file.

| Requirement | State |
|---|---|
| 이용약관 | ✅ `docs/legal/terms-of-service.md` |
| 개인정보처리방침 | ✅ `docs/legal/privacy-policy.md` — amended 2026-08-13 for ⑪ |
| 취소·환불 정책 | ✅ ToS 제5조 (매칭 전 전액 / 러너 사유 전액) — ⚠ counsel flag already in the file at :54 on 청약철회권 배제 범위 |
| 고객센터 연락처 | ⚠ currently a `mailto:` in `payments.tsx` — fine for a pilot, confirm it satisfies the reviewer |
| **전자상거래법 사업자정보 footer** | ❌ **MISSING, and correctly so — see below** |
| 가격 표시 | ⚠ price-invisibility doctrine shows the price once at request; confirm this satisfies 표시 의무 |

**The footer gap is deliberate and it resolves itself with ①–③.** `app/app/payments.tsx:28`
already says so:

> `전자상거래법 footer (상호·사업자등록번호·통신판매업신고·대표·주소·연락처) — those numbers do not
> exist yet (사업자등록 pending). Fabricating them would be both a lie and a legal claim. It lands
> with the real filing, not before.`

That is the right call and it is why the paperwork is on the critical path rather than the code.
**The moment ① and ③ return, the footer becomes buildable and it is a small client slice** —
상호, 대표자명, 사업자등록번호, 통신판매업 신고번호, 주소, 연락처. Hand it to whoever owns `app/`
with the real numbers; do not let it be built with placeholders in the meantime.

---

## 4. Not on the critical path — things people add by reflex

- **Switching PGs.** Any PG works and **포트원** aggregates them, but our code is written to
  Toss's billing API. Switching now costs the integration and buys nothing the chain does not
  already give us. Decide it if Toss refuses us, not before.
- **The card-registration UI slice.** Real, and it is a pre-flip item on the config half — but it
  cannot be tested end to end without ④ anyway.
- **A live key.** ④'s sandbox is exercised on TEST keys. The live key is the last thing, not an
  early one.

---

## 5. Where this hands off

When ①–④ are done, the config half takes over and its order is already written:
`TOSS_SECRET_KEY` → `CRON_COLLECT_KEY` **and** the Vault `charge_dispatch` secret **from one
copied value in one sitting** → `OPS_PROFILE_ID` (+ `ops_recipients` rows) → the flag, set to a
future timestamp.

⚠ Two of those are one value in two places with nothing verifying they agree, which is the
quietest failure available in this system. `docs/pre-charging-checklist.md` §2.3 carries it.

**The 빌링키 charge-notice obligation** — whether and how we must notify before each automatic
charge — is a counsel question, and it rides in
`docs/biz/location-law-counsel-brief.md` as its final section so it reaches the lawyer in the same
sitting as the rest. It may add a requirement to ④'s disclosure list; answer it before building
the notice, not after.
