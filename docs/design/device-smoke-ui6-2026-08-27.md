# Device smoke list — ui6's 2026-08-27 slices (KST, card path, board tap, floor raise)

Written for Sean. Build: `redesign-v4` tip at or after `4119a64`.

**Nothing below has been verified by anyone.** No simulator pass was run for these slices — every
row is ⬜. That is the honest state, and it is why this file exists rather than a claim.

**⚠ Two rows need the SERVER deployed and cannot pass before it.** Production is at migration
`0130`; the board tap (§3) needs `0145` and the card refusals (§5) need `0143`. Everything else is
client-only and testable on today's server.

---

## 🔴 §1 — THE ONE TO RUN FIRST, AND IT NEEDS A SETTING CHANGE

**Set the phone's timezone to something that is not Korea** (Settings → General → Date & Time →
off automatic → New York). This is the whole point: **a phone set to Seoul cannot fail any row in
this section.** Measured on the fix — re-planting the bug fails 25 checks under New York and
**zero** under Seoul, which is exactly why the class shipped unnoticed.

Then set it back when you are done, or every later row lies to you in the other direction.

| ⬜ | what | expected |
|---|---|---|
| ⬜ | Open a club 입장권 (ticket) for a session you know the real time of | DATE cell shows the **Korean** weekday and time, not the phone's |
| ⬜ | Same ticket, phone back on Seoul time | **Identical string.** Any difference between the two is the bug |
| ⬜ | 예약 내역 / report screen → the 「다음 주 같은 시간」 panel | **It appears at all.** Off-KST it used to silently never render — no error, nothing to notice |
| ⬜ | A route chip for an evening run (19:00-ish) | Night/dawn **safety copy** matches Korean hours, not the phone's |
| ⬜ | Any chat thread | Bubble times read 오전/오후 in Korean time |
| ⬜ | 설정 → the 「can change again on …」 date | Correct near midnight KST (this one is off by a **day**, not an hour) |

## §2 — the ticket screen's shape (repaint + the two-line date cell)

| ⬜ | what | expected |
|---|---|---|
| ⬜ | Ticket, normal session | DATE cell is **two lines** (date over clock), and the MEET block sits on the **same baseline** as the DATE kicker |
| ⬜ | A session at 00:0x KST | Clock reads `00:0x` — zero-padded, not `0:0` |
| ⬜ | A **December** session | `12월 28일 (수)` fits without wrapping or clipping — this is the widest realistic label |
| ⬜ | Deep-link `/club/pass/<sid>` with no params | **Headline is ABSENT, not an empty box.** It used to print the product's brand word where a club name belongs |
| ⬜ | Press the 체크인 button | Physical-key feel: it sinks, no shadow, no scale, box height unchanged. Busy state swaps the **label**, never dims the button |
| ⬜ | Anywhere on the ticket | No 「HIGH-VERIFIED」 badge (it was a claim no field backed) and the TEAMS count is never a bare `0` beside a real capacity |

## §3 — board tap → profile ⚠ NEEDS `0145` DEPLOYED

| ⬜ | what | expected |
|---|---|---|
| ⬜ | Club session board → tap a **runner's** name | Opens their profile (worked before; confirm no regression) |
| ⬜ | Tap a **non-runner** owner's or crew member's name | **Opens their profile.** This is the new behaviour — it was a dead end |
| ⬜ | A row whose runner is **proposed but not yet accepted** | Name is **not underlined and not tappable**. This is the privacy arm — it must stay shut |
| ⬜ | A non-runner's profile once open | Header + grid render; the runner-only sections are simply absent, not an error |

## §4 — the 15pt floor on 예약 만들기 (`owner/request.tsx`), 43 sizes raised

**Four layout risks were flagged by the agent that raised them and could not be checked statically.**
These four are the reason this section exists:

| ⬜ | what | watch for |
|---|---|---|
| ⬜ | Course area while the map is loading | 「지도 준비 중」 may now **wrap to two lines** in a 96pt box. Degrades gracefully, but looks different |
| ⬜ | Route card badge (안심 코스 / 점검 예정) | Badge sits clear of the name row — it is absolutely positioned and the label grew ~1pt |
| ⬜ | Slot sheet, on the **smallest phone you have** (SE / 320pt) | The two method chips (날짜·시간 선택 / 가장 빠른 시간) still fit on one row |
| ⬜ | Slot-hold card after picking a time | 「● 서버 홀드 확보 …」 may wrap to two lines; card should grow, not clip |
| ⬜ | The screen generally | Nothing Korean looks smaller than the rest; group headers still read as **headers** over their items |

## §5 — card registration refusals ⚠ NEEDS `0143` DEPLOYED

⚠ **Do not attempt these by breaking a real card.** They are listed so the strings can be read if
they ever appear, not as steps to force. **Never** run them against a real payment method.

| ⬜ | what | expected |
|---|---|---|
| ⬜ | If registration is refused while the feature flag is closed | Message says registration is **not open**, not 「no profile」 |
| ⬜ | If refused because the key is being revoked | Message indicates a **retry will help** |
| ⬜ | Tombstoned account | Still 「no profile」, unchanged |

## §6 — distances read as two different facts

| ⬜ | what | expected |
|---|---|---|
| ⬜ | 예약 목록 card whose route name ends in its own km | Booking distance reads **`예약 5km`**, and the route name keeps its own number. The same number must never appear twice unlabelled |
| ⬜ | 관리 sheet on the same booking | Same |
| ⬜ | Club 위탁 screen fee line | Route name shown once, with one distance |

---

## What a failure here means

**A ⬜ that fails in §1 is a real bug and I want to know the exact string.** Those are server-truth
facts rendered wrong; there is no styling judgement involved.

**A ⬜ that fails in §2 or §4 is most likely a layout call, not a defect** — a wrap, a tight row, a
baseline. Tell me what it looked like rather than what you think the fix is; several of these have
a deliberate reason behind them (the two-line date cell exists because the one-line form does not
fit at the legibility floor, and shrinking it is not available).

**§3 and §5 failing before their migration is deployed is expected and is not a finding.**
