# Self-check on the journey labs — what I missed, what could be better (2026-08-19)

Sean: "any screens or buttons or things you are missing out or anything that can be done better?"
Honest audit of v3 + the labs before it. Grouped: **missed screens · missed states · missed
buttons · things I did wrong · things that could be better**. Then his two new directions.

## Missed screens (not drawn anywhere)
1. **Cancel flow** — I drew "요청 취소" / "취소 ›" buttons in three places and never the screen they
   open. It has real money consequence (`cancel_owner`: free ≥24h out, else a fee — code in
   meetup.tsx:78, schedule cancel vocabulary). The fee sentence must appear BEFORE the confirm.
   Undrawn = a dead button in the mock.
2. **Reschedule** (12) — same: "일정 변경 ›" drawn as a door, screen never drawn.
3. **Runner-side journey** — zero screens. The runner is half the transaction: requests inbox →
   accept → meetup → run → return → done/earnings. Sean asked for onboarding for runners; the rest
   of their path is unmocked. Their live-run screen publishes the location the owner watches.
4. **Chat** — drawn as "채팅 ›" doors ~8 times, never the screen. It carries the private-channel
   work from today; it deserves one state (thread) drawn.
5. **Notifications / 알림 (the bell)** — home's top-right bell is in the current UI and in the
   mocks; the screen it opens is not drawn. Under Zeigarnik it is where "러너가 응답했어요" lands
   when the app was closed — the radar copy PROMISES this ("앱을 닫아도 돼요 — 알림으로 와요"),
   so the screen that fulfils the promise must exist.
6. **Course map from the preferences nudge** — the big nudge goes to course-map; that screen exists
   and is built, but the RETURN path (chose a course → back to preferences with the row filled)
   is not drawn.
7. **Address pin from onboarding** — "지도에서 정확히 맞추기 ›" drawn, target not.
8. **The pending "finish your profile" nudge** — Sean said design later; noted, not missed.

## Missed states
9. **Preferences with a candidate course chosen** — the amber 점검 예정 + candidate_ack sheet
   (server refuses without it). Drawn in mocks-1 03b, DROPPED in v3's rewrite. Regression.
10. **Radar → nobody accepts (timeout)** — drawn "0 runners online"; not drawn "3 runners were
    asked, none answered in N minutes". Different fact, different sentence.
11. **Return-handoff when the runner ended EARLY** (dog_condition) — I drew the report state (14c)
    but the return-handoff screen only in the happy state.
12. **Pay: 입금 확인됨** — drew 입금 대기 only. The confirmed state is the one that closes the loop.
13. **Live: stale ≥90s** — the code has it ("N분째 위치가 갱신되지 않았어요"); I drew connecting /
    live / denied / error and forgot stale. Five states, not four. **My own live.tsx work today
    has it — I misreported my own count to the announcer.** Correcting there too.
14. **Home when the LAST run is unpaid** — with pay moved post-run, an unpaid completed run is now
    a home state (Zeigarnik: unfinished business). Alert line: "지난 러닝 결제가 남았어요 ›". Not
    drawn, and it is the most important new state v3 created.

## Missed buttons / affordances
15. **SOS on meetup** — safety.tsx exists and live has SOS; the meetup (arrived, dog about to be
    handed to a stranger) has none in my mock. Current UI links 신고·SOS from the club session
    screen; the 1:1 meetup should too.
16. **"러너 프로필 보기"** — runner cards everywhere, tap target to `runner-profile/[id]` nowhere.
17. **Back / close on the slot screen** — I removed the "다음" button (good) but the pinned
    "가장 빠른 시간으로 ›" CTA means the only way to NOT proceed is the top-left ‹. Fine, but I
    should say it is deliberate.
18. **Report → 문제 신고** — the current report has it (report → /cards etc.). A bad run needs a
    door to 신고, especially the dog_condition early-end case.

## Things I did wrong
19. **HOME TAB POSITION.** Sean's ruling: home leftmost, not centre. `bottomnav.tsx:34-38` has it
    3rd of 5 — and **every mock I drew copied that** without questioning it. Serial position:
    the first tab is the one people remember and reach for; home is where the two options live.
    Owner order → 홈 · 내 일정 · 커뮤니티 · 샵 · 마이. Runner → 홈 · 요청 · 캘린더 · … (same rule).
20. **Live-state count** — see 13. Reported four, it is five.
21. **The 9-screen lab (mocks-1) still on trunk** as if current. It is superseded by v3; it should
    be marked SUPERSEDED at the top or moved to an archive folder, or someone builds to it.
22. **Nav-bar mock consistency** — the mocks show a 5-slot bar with glyphs; the real bar uses
    lucide icons + labels. Cosmetic, but a mock that does not look like the app's own chrome
    reads as a different app.

## Could be better
23. **Preferences course nudge** — "반포동 코스 9개" is a real number today but hardcoded in the
    mock; the built version binds `routes` count for the owner's town, and says "0개" honestly
    when there are none (nudge hides).
24. **Radar** — the runner list under the rings duplicates matching; fine, but "지명 ›" on a runner
    who is not online should not render (only `available_runners`).
25. **Report share nudge** — "이 러닝 카드 공유하기" opens the shot studio's default skin; make the
    default skin the one that needs no photo, so the nudge never lands on "사진을 먼저 골라주세요".
26. **Rebook nudge copy** — "다음 주 같은 시간 예약" is Sean's phrase and it is right; the button
    should say the resolved slot ("다음 주 수 19:30") not the abstraction, per the CTA rule.
27. **Onboarding runner GPS** — request WHEN-IN-USE at onboarding; ALWAYS at first run start (iOS
    prompts twice anyway and the second prompt has a better reason at that moment).

## Sean's two new directions
- **"later, this style in the other tabs"** — 내 일정 (10a/b/c is already drawn), 커뮤니티, 샵
  (준비 중 plate), 마이/passport. Community and My are the two real ones. Queue after the journey
  build; the grammar (card-less, one coral, kicker+gap, alert line) transfers directly.
- **"home tab leftmost"** — one-line change in bottomnav.tsx (owner AND runner arrays), plus every
  mock's tab strip. Cheap; do it in the same commit as the pay redirect.
