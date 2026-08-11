# Plan — Sean's directive list §D (owner side), all 5 items

Branch `redesign-v4`. Written 2026-08-12. Status: **SHIPPED 2026-08-12.** Codex reviewed as Sean's proxy and **did not approve as written** —
its verdicts and what happened to each are recorded at the bottom. Prod is on 0073.

Sean: *"do d next, all 5 of them, then next session do c. im going to bed so ask codex for
replies."* So codex answers the taste decisions and user challenges that would normally be his.

---

## Ground truth gathered before planning (all measured, not remembered)

Two of the five pointers in TODOS were **wrong or stale**, and one backlog entry is dead:

| Claim in backlog | Reality |
|---|---|
| "price tag is at `pay.tsx:334`/`:275`" | ❌ `pay.tsx`'s CTA carries **no price**. The big **red** button is `owner/home.tsx`'s 미리 예약 (`MONEY_DEEP #C6472C`, 31pt display); its price tag is the 예상 결제 block at `:1306-1311`. |
| M5 — "club-acks.tsx missed FLOOR14 (9.5pt body/button)" | ❌ **Already fixed.** `club-acks.tsx` body is 14pt, `btnTxt` 16pt, both carrying `[FLOOR14 2026-08-11]` comments. `case/[cid].tsx` has **zero** sub-14pt. Entry is stale. |
| "special note … editable for owner" | ⚠ Deeper than it reads — **there is no address edit path at all.** |

---

## D11 — "Big Red Reservation button delete price tag"

**Target:** `owner/home.tsx:1306-1311`, the 예상 결제 / `{bookPrice}원` block inside `s.bookFacts`,
directly above the red `s.cta` 미리 예약 button.

**Why it should go, beyond Sean asking:**
- `bookPrice = pricing.baseFare + bookKm * pricing.perKm` (`:620`) — a **client-side estimate**, no
  addons, for a booking that does not exist yet. It is the least-earned number on the screen.
- The §3b Money-button law already says **"no price sub-plate"**; the 2026-08-10 pass deleted the
  sub-plate but kept this facts-row price, on the argument that "the facts row already says it".
  Sean is now closing the loop.
- 🔴 **It becomes actively false when the km token model ships.** §A retires the base fare entirely
  (₩5,000/km flat, 3km floor), so `baseFare + km*perKm` is a formula with a shelf life.
- No honesty loss: the real price appears on `/owner/request` (configurable, with addons) and again
  on `/owner/pay` before any commit. This CTA only navigates.

**Do NOT touch** the CTA itself — `goBook` → `/owner/request` is the entry to the booking funnel.

## D12 — "Font consistency (pre reserve card vs rest)"

**Not yet diagnosed — must be looked at on the simulator, not guessed.** What the code says so far:
the card mixes `lilac.head`/`lilac.dim` (correct for owner home's world, §2) with a 14/700 facts
line, a 14/600 `bookKicker` at `letterSpacing 0.5`, a 22pt Oswald price, and a 31pt display CTA
label — four type treatments in one card. Once D11 removes the price, two of them go with it.
**Sequence D11 first, then re-look** — the inconsistency may substantially resolve itself.

## D13 — "Clean small info text"

Scanner written for this (Korean below the 14pt floor, including the class that arrives at runtime
through variables — a static scan under-reports it). Confirmed violations:

| Site | Size | Content | Why it is a violation |
|---|---|---|---|
| `owner/pay.tsx:243` | **11.5** | `MOCK · 준비 중`, `REVIEW · 확인 중`, `REFUND · 환불 중` | Korean in a latin-kicker slot, **on the money screen** |
| `alerts.tsx:212` | **12** | `tagFor()` → 기록·클럽·취소·반복·변경·확정·완료 | pure Korean, pure data |
| `community.tsx:284` | **12** | `{rv.when}` (e.g. 8월 3일) | Korean date |
| `community.tsx:293` | **12** | `{t}` review tags | user-authored Korean |
| `club/run/[sid].tsx:490` | **9.5** | `조기 종료` | Korean section label on the run-end screen |
| `shot/[bid].tsx:589` | **13** | `사진 N장을 못 불러왔어요 …` | **a failure message** — the one class that must read |

**Correctly exempt, leave alone:** `FINISHER`/`DOGS HIGH` stamp caps (`owner/schedule.tsx:599,601`),
`DOGS HIGH GEAR` tag, glyph-only ✓/›/·/✚, `club/[id].tsx:376` (marked `CLUB15 단위 접미사 예외`).
**Open question for codex:** `shot/[bid].tsx:67` — a repeating `도그스하이 · DOGS HIGH` band at 13pt
used as decorative tape on the share artifact. Korean, but ornament rather than information.

## D14 — "My screen subtext filler removal"

`my.tsx` MENU `desc` strings, audited one by one:

| Label | desc | Verdict |
|---|---|---|
| 안심 센터 | SOS · 긴급 연락처 · 보험 | **keep** — names contents the label does not |
| 러너 인증 센터 | `certDesc` (live status) | **keep** — dynamic, says where you are in the funnel |
| 주소 관리 | 픽업 장소 · 공동현산 정보 | **keep** — names contents |
| 반려견 프로필 | 사진 · 성향 · 러너에게 전달되는 정보 | **keep** — the last clause is a real disclosure |
| 예약 관리 | 다가오는 일정과 지난 예약 | **cut** — restates the label in more words |
| 러닝 기록 | 도장 · 코스 패치 컬렉션 | **keep** — corrects a destination that was misnamed |
| 알림 | 알림 확인 및 설정 | **cut** — pure restatement, the worst offender |
| 설정 | 계정 · 로그아웃 · 문의 | **keep** — names contents |

Cutting 2 of 8 leaves rows without a subtitle beside rows with one — the row component must render
a single-line row cleanly, not leave a gap. That is the actual work here.

## D15 — pin/address sync + special note *(the real one)*

Three parts, and the ground truth reframes all three.

**(a) There is no way to edit an address.** Mutations that exist: `addAddress`, `setAddressPin`,
`setDefaultAddress`, `deleteAddress` (`api.ts:2257-2308`). **No `updateAddress`.** So
`addresses.detail` — which *is* the "special note", it already exists in the schema
(`0001_init.sql:122`) and already reaches the runner — is **write-once at creation**. To change
"1층 로비에서 인계" the owner must delete the address and rebuild it, losing the pin and the default
flag. That is the gap Sean felt.

**(b) The owner never sees the note.** `runner/meetup.tsx:332` renders `addr · detail` (and only in
the `ok` state). `owner/meetup.tsx` renders the map plate and pin but **never `detail` at all** — so
the owner cannot see what their runner is being told. "Always visible in intermediary" = render it
on **both** meetup screens, in every state where an address exists.

**(c) Pin staleness** — the known P2. A pin set while the runner's meetup screen is open only
arrives on remount or via the error-strip retry. ⚠ The fix folds an address refetch into the
**frozen** meetup polling (DESIGN §9), which is why it was deferred.

### Server surface question — the one thing that needs a decision

`booking_pickup_address` (0065) already returns `detail`, so the **read** path is complete. Only the
**write** path is missing, and `addresses` has owner RLS already (0002), so `updateAddress` can be a
plain PostgREST `.update()` — **no migration, no definer function.** That keeps this out of 0059
money-doctrine territory entirely.

---

## Proposed scope, in order

1. **D11** — delete the price block. (1 file, ~6 lines)
2. **D12** — re-look at the card on the simulator after D11, then normalise. (1 file)
3. **D14** — cut 2 desc strings, make single-line rows render cleanly. (1 file)
4. **D13** — 6 floor fixes across 5 files. Mechanical but touches the money screen.
5. **D15a+b** — `updateAddress` + an edit sheet in `owner/addresses.tsx` + render `detail` on
   `owner/meetup.tsx` and un-gate it on `runner/meetup.tsx`. (3 files + api)
6. **D15c** — pin refetch in the meetup poll. **Frozen zone.** Proposed as a separate, careful step
   and explicitly last, so it can be dropped without losing 1-5.

**Gates:** tsc 0 · check-rpc · geo 38/0. No migration expected — if one becomes necessary, stop and
apply the 0059 doctrine instead of improvising.


---

## Codex gate — verdicts and outcomes

Codex reviewed standing in for Sean. It rejected the plan as written; the D15 redesign it forced is
the most valuable thing in this slice.

| # | Codex verdict | Outcome |
|---|---|---|
| D11 | **Keep a qualified price anchor** — a red money button with no number reads as concealment, and disclosure comes "too late" | **Overruled, after checking.** `KmDial` (`request.tsx:564`) renders a 54pt km with the live price beneath it as the destination screen's main content, on arrival, no interaction. The premise was false. Sean's instruction stands; price fully removed. |
| D13 | Repetition does not make Korean a glyph — **make the tape 14pt or classify it as logo artwork**; also the scan is incomplete | **Accepted both.** Took the classification branch and made it real: DESIGN.md §3 now carries a three-clause **logo-artwork exemption**, and the marks declare themselves as decoration. Rescanned the file and found two more sites codex was right about (`iTiny` at 10pt carrying a Korean date + course name). |
| D14 | Mixed 1-line/2-line rows are correct; make `desc` optional | **Accepted verbatim.** |
| D15 | 🔴 **Reject the plain `.update()`. Require a definer with a column whitelist** | **Accepted.** `0073` + `owner_update_address_detail`, note-only. Two corrections to codex's reasoning, from measuring: `gate_code_enc` is written by nothing (dead column, not an exposed secret), and the policy's missing `WITH CHECK` means Postgres reuses `USING`, so it is not a cross-tenant hole. The real risk is the integrity one codex ranked #2. |
| D15 | An RPC without revoking broad UPDATE is **security theater** | **Accepted, and deliberately not half-done.** The revoke touches two shipped writers and is its own slice — logged **P1 SECURITY** in TODOS. 0073's own header says in writing that it is not a seal. |
| D15b | The runner side needs nothing — it already renders `detail` | **Accepted.** Only the owner read model and JSX were widened. |
| D15c | **Defer automatic polling**; ship an explicit refresh instead | **Accepted.** Its failure-mode list (stale address overwriting a fresh pin, `loading` blanking the map each poll, effect-order replaying the handoff once-law) is exactly why. Shipped 주소·메모 다시 확인 on the existing `addrTry`; the frozen poll is untouched. |
| D12 | Not implementation-ready — reinspect visually, do not authorise a vague normalise pass | **Accepted. Left open.** |

## What was verified on the device, not assumed

- D11: the red 미리 예약 button renders with no price.
- D15: the note editor saves through the RPC **against prod** — and the first attempt failed loudly
  with *"Could not find the function … in the schema cache"*, which was the honest surfacing of an
  unpushed migration rather than a silent no-op. Pushed 0073, retried, the note saved and both strip
  states (coral invitation → dim edit) rendered.
- 🔴 **A real layout bug was caught only by looking**: the owner/meetup note strip first rendered
  *inside* the fixed-height 290px map plate, overlapping the top bar — `s.topBar` lives inside
  `mapPlate`, so the anchor was wrong. Re-anchored as the first child of the ScrollView.
- The prod test note was cleared afterwards (`detail is not null` → 0 rows).

## Gates at ship

tsc 0 · check-rpc 79 calls / 114 signatures · geo 38/0 · **SQL harness 343/0** (336 → 343, +7 pins),
with all six 0073 reverts run and observed red. Prod synced through 0073.
