# Sean's journey rulings — 2026-08-19 (verbatim intent, applied to the compressed labs)

Recorded the moment they arrived so nothing drops. Each line: what he said → what changes.

## Structural (changes the flow, not the styling)
1. **Payment comes AFTER the run and after handoff-back.** Not between reserve and live.
   → The pay/notice screen moves to the END of the journey (after report / return handoff). The
   reservation path is: home → [slots] → **예상 금액 shown once** → radar. No money screen mid-flow.
   → He asked why the current UI shows a price at all pre-run. Answer: it is the frozen quote from
   `create-booking-hold`; showing it is fine ONCE as 예상 금액, but it was styled like a receipt.
2. **Onboarding gains two required things**: owner → home/starting address · runner → home base
   location + **GPS permission requested during onboarding** (not deferred to first run).
3. **Post-first-run "finish your profile" big nudge** — sometime AFTER the first run has taken
   off (not before, not blocking). Design later; noted.

## Preference screen (request)
4. Likes the CURRENT preference UI (dial, strip) — keep its feel — AND the mock's defaults model.
5. **Route selection gets a BIG nudge** — not a quiet row. A large, inviting entry to the course map.
6. Reserve buttons: small arrow + bold text.

## Radar
7. **Radar animation on screen 3** — he asked what the radar looks like right now. → Verify on sim
   and show him; design the animation (no ticking clock — animation ≠ counter).

## Intermediary / meetup
8. Likes 10a (ticket). Intermediary (meetup) screens: **inspired by the CURRENT UI, not the mock**;
   11a/b/c have too much empty space.

## Live
9. Likes 13a. **Live map = live trace + a more-opaque line for the PLANNED route** the runner will
   follow. (Today: planned = lilac.accent, live = voltDeep — CLAUDE.md law: never confuse. Keep the
   pair; make the planned line more visible than the current ghost.)
10. Agrees: retire the morph/GO widget direction. Likes the live-run widget on home (⑧ active state).

## Post-run (report)
11. **Re-order nudge**: "다음 주 같은 시간 예약" — explicit, on the report.
12. **Share nudge**: share the route card (the shot studio's output) — a nudge, not buried.
13. Likes 14a's report-below-map style; likes 14b's stars + photos.

## Answered in this pass
- "what does the radar look like right now?" → sim screenshot + description.
- "why is payment between reserve and live?" → because `owner/pay` is pushed from request step 3
  today (request.tsx → /owner/pay). That is a leftover of the Toss-widget plan; the pilot is manual
  transfer, so there is nothing to collect pre-run. Moving it post-run matches money §4-bis.

## Pickup point · nearest path · entry point (Sean, 2026-08-19 evening, verbatim)
14. *"pick up point should be wherever the home owner puts, and the app should recommend the
    nearest path. the runner should start at the put starting point and should be led by the app
    to the nearest point in the path from that starting point, from which then on the runner will
    start the lap."* [end of his words]
    → **Pickup = the owner's placed point** (the pin is the coordinate truth — 0065 doctrine
    already says so; onboarding must therefore lead to the pin, not leave it behind a door).
    → **Recommendation = nearest PATH to the pickup**, measured to the nearest point ON the route,
    not to `trace[0]` (the old "rank from trace[0]" was a stand-in for "not anchor_lat/lng"; the
    nearest-point metric supersedes it).
    → **Runner guidance = pickup → entry point → lap.** The runner leaves the pickup, is led to the
    nearest point of the route (the entry), and the lap starts there — the loop is rotated to begin
    at the entry. Approach leg and lap are drawn as two things; the approach is not part of the km.
