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
    at the entry. Approach leg and lap are drawn as two things; the approach is not part of
    `routes.km` (the measured lap). Whether it counts toward the BOOKED km was open here — settled
    by #15 below: it counts.

## Approach leg counts · route km shown WITH it (Sean, 2026-08-19 evening, verbatim)
15. Asked "does the approach leg (pickup → entry) count toward the booked km, or lap only?" —
    *"counts; the route selection should show kms with those included, which is why we need a
    large variety of routes made."* [end of his words]
    → `actual_km` keeps its meaning (whole tracked buffer); no settle-path change.
    → Route selection (request nudge/carousel, course-map sheet) shows the **total the dog will
      run** = lap km + the approach (pickup → entry, and back to the pickup for the return
      handoff), labelled as an estimate (straight-line approach), with the lap km still visible.
      Km-tier matching in `pickRoute` uses that total, not `routes.km` alone.
    → Catalog note (for route geometry): more routes per town, so some route's total lands on the
      dial km for any pickup.

## 🔵 Decided under the overnight grant (ui, 2026-08-19 night) — Sean flips with a word
- **Course-map anchors = A′, zoom-scaled** (18 pt when zoomed out · 30 pt at neighbourhood zoom ·
  44 pt at street zoom; selected +8). Why not A (18 everywhere): 17 % of the HIG target area on the
  one screen where the user hunts for a small thing. Why not B (44 everywhere): measured on the
  simulator, 44 pt glyphs overlap each other at the Banpo cluster. Why not "18 pt glyph + invisible
  44 pt hit box": the Naver SDK has no hit-slop and its custom-view marker path dropped most markers
  on iOS when photographed (frame C in `docs/labs/anchor-tap-target-lab.html`). Verified on the
  simulator at the three zooms. The dev `?anchor=` knob is removed; `anchorSizeForZoom()` in
  `app/app/owner/course-map.tsx` is the one line to change.
