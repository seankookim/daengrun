# Device smoke — UI master session wave, 2026-08-31

**What is already sim-verified (Release build, worktree, fresh-literal-proven Hermes bundle,
Sean's signed-in account)** — these rows are ✅ and need no re-check:

- ✅ U5 owner home: wordmark renders 본문 900 (display face appears exactly once — the hero
  phrase); both decision buttons in body 800 (요청 보기 26pt with sub · 미리 예약 box-fill);
  the three utility doors (코스 둘러보기 · 크루 피드에 자랑 · 안심 센터) in the 56pt-floor coda
  tier with art, chevron, and 3px lip. 크루 피드 door correctly gated on a real lastDone.
- ✅ App boots Release from the worktree build; login → role fork → owner home; my/settings/
  결제 관리 all render. 결제 관리 shows the honest empty (no card · no rows) for this account.

**Not verifiable with current fixtures — the smoke list.** Every row below needs the state named
in it; none of it could be produced read-only against production. The installed sim build
`com.seankookim.daengrun` (2026-08-31, second install of the day) now contains EVERYTHING in this
wave — U2/U3/U4b/U4c/U5, the chat rescue, the 예약 규칙 editor, and all 13 round-2 codex fixes
(trunk b8ce1c8; bundle freshness proven by the `doAssumeHost` literal before install). No rebuild
is pending for any row below.

| # | Surface | Needs | What to look at |
|---|---|---|---|
| ⬜ 1 | `/payments` list rows → receipt door (U3a) | ≥1 payments row on the account | each row shows a chevron, presses with the wash, opens `/owner/pay?bid=` for THAT booking |
| ⬜ 2 | schedule booking-sheet 결제 내역 rows → same door (U3a) | a booking with a charge | sheet closes, receipt opens; row without onPress (dev lab) unchanged |
| ⬜ 3 | `/owner/pay` red-line cap (U3b) | any charged booking | exactly TWO coral horizontals (the total's double rule); charge-table rows + footer are neutral #EEE; fail strip (if failed state) stays critical red |
| ⬜ 4 | 팩 지도 door (U2a) | a club session inside the check-in window, map-capable build | 팩 지도 CTA on the overview tab; absent outside the window; absent in a map-less build |
| ⬜ 5 | run-screen publisher (U2b) | a delegated runner mid-run (checked in, active booking) | 「팩 지도 공유가 켜져 있어요」 appears only while GPS fixes actually arrive; the runner's dot appears on ANOTHER participant's open map. ⚠ until 0160/0161 deploy, the map channel is refused (PrivateOnly) — the map shows its honest cannot-connect state; do not read that as this slice failing |
| ⬜ 6 | 러닝 종료 (U4c) | host console during a live pack run (active bookings) | running dogs listed by name; tap → confirm → three named lists (km per ended dog; blocked reasons in Korean; case link on incident_open); no counts anywhere |
| ⬜ 7 | 백업 호스트 지정 (U4b) | host console, ≥1 committed runner besides the host | current backup line (지정 안 됨 honest when null); picker chips; no un-set button exists — deliberate |
| ⬜ 8 | 호스트 인수 (U4b) | the BACKUP runner's account, T−30min window | info line before the window, card+CTA inside it; host_present refusal copy when host checked in |
| ⬜ 9 | chat merge/retry (rescue) | any booking chat | error state shows 다시 시도 and it works; no duplicate bubbles when realtime echo + poll race |
| ⬜ 10 | 예약 규칙 editor (U5) | runner-role account, 가용시간 설정 screen | new section below the grid: 휴식/하루 최대 steppers, save button appears only when dirty and names what it saves, values survive re-entry; availability grid's own save untouched |

⚠ All club rows (4-8) additionally need `club_flags.club_delegation_v2` or membership in
`club_test_accounts` — otherwise every new button correctly refuses with the 허용목록 translation,
which is the flag working, not the slice failing.

⚠ **Known product limitation, not a bug (backend-flagged 2026-08-31):** pack publishing runs on a
foreground hook timer on every entry point — a pocketed/locked phone stops publishing and that
runner FADES off the pack map (the 1:1 `run2-` publisher rides the background location task and
does not). A hardware smoke that pockets the phone mid-run and sees the dot fade is seeing the
named limitation, not a regression. The fix (pack publish inside the background task callback) is
a queued backend slice, deliberately not taken in this wave.
