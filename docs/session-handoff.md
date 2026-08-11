# SESSION HANDOFF — 2026-08-10/11 (coordinates shipped · design system rebuilt · en-route cancel)

English everywhere except in-app user-facing copy (CLAUDE.md §Language).
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md is the permanent law book. **`DESIGN.md` is now the design law book** —
read it before any UI work. Prior handoffs live in this file's git history.

**Build in the MAIN checkout `/Users/sean/dev/daengrun` (branch redesign-v4).**
Worktrees under `.claude/worktrees/` are stale — never build or gate there.

---

## ⓪ STATUS

| | |
|---|---|
| git | pushed through `bc0102f` (+ the design-review doc commit if it landed after) |
| database | **0066** applied + verified on prod (`marketplace_cancel_fee` returns 12,450 on a 24,900 booking = exactly 50%) |
| edge functions | `geocode-address` + `transition-booking` deployed (0066 coupling: DB first, always) |
| harness | **305 / 0** (298 + 7 new en-route-cancel pins), independently re-run |
| gates | tsc 0 · check-rpc 75/109 · **geo runner 38/0 — now part of the commit gate** |
| simulator | owner home, request stepper + gear dial, runner home, earnings, community, compose all walked this session |

## ① What shipped (in order)

1. **0065 coordinates/geocoding** — pin-first capture (`owner/address-pin.tsx`),
   real pickup maps on both meetup screens, 길찾기, `geocode-address` edge fn as
   an honest no-op until the NCP secret exists, backfill script.
2. **DESIGN.md created, then hardened three times** — it is now the single design
   source of truth: §2 token worlds + paper migration grammar, §3 typography,
   **§3b COMPONENT SPEC** (the fix for Sean's "thought you were using it"
   critique — section headers, four button kinds, status chips, cards, GO ladder,
   energy green), §7 honesty, §7b decluttering doctrine (Laws of UX / HIG / Maze),
   **§7c Apple fluid-interface doctrine**, §8 budgets, §9 frozen zones.
3. **Paper chrome on every main tab** — white canvas everywhere, sharp cards,
   full-bleed coral rules, white dock with coral hairline.
4. **Type/density consistency wave** — gutter 15 actually enforced (it had ZERO
   importers before), 14pt floor completed, Oswald on all money, ~24 filler
   strings culled.
5. **GO premium (lab pick Ⓐ④ Keyline Orbit)** + redder coral + press-scale 0.96
   app-wide + the brand lockup masthead.
6. **Emoji purge** — ~160 pictorial marks across 33 files; ink glyphs kept.
7. **Community/compose** — Instagram *anatomy* on paper grammar, `compose.tsx`
   (completed-run picker), entry points on both homes. Post→delete verified
   against prod.
8. **0066 en-route cancel at 50%** (Sean's decision) — see §③.
9. **Owner home / runner home Ⓑ① / request Ⓒ①** rebuilt against §3b, incl. the
   **gear distance dial** (1km min, 0.5 steps, snap detents, live price, haptic).
10. **Seven legacy-green runner screens scrapped** and rebuilt on paper.

## ② The design system — read DESIGN.md, but know these

- Section header = **one grammar**: coral rule + 20/800 ink title + optional
  16/800 link. **No latin kickers, no section subtitles** — this single rule is
  what killed ROSTER / VERIFIED COURSES / NEXT RUN·BOARDING PASS / 동네에서 함께.
- **Four button kinds only**; primary 17/800 ink, money = coral 31-display
  full-bleed with no price plate, secondary, destructive. All sharp, scale 0.96.
- Status chip 16/800 **on the same baseline row as its datum**.
- Radius 0 everywhere. Club widget keeps side margins (Sean's veto) but not
  rounded corners.
- **No emoji.** Ink glyphs (✓ ✎ ★ ➤ ›) are fine; Lucide icons where an
  affordance is genuinely needed.
- Peak-End protection: GO press, handoff seal, run completion, done screen —
  polish these, never minimize them. "Simplicity is not minimalism."
- Decluttering never becomes hiding: honest states are content.

## 🔴 ③ WHAT ONLY SEAN CAN DO

1. **NCP console — TWO checkboxes**: Mobile Dynamic Map **and** Geocoding API on
   the app registered for `com.seankookim.daengrun`. Device maps + geocode
   pre-centering are blocked until this is done.
2. **`supabase secrets set NAVER_GEOCODE_SECRET=...`** — until then the picker is
   pin-only by design and backfill refuses to run.
3. **Counsel**: the privacy policy carries a coordinates rider (HTML-comment
   marked); also flag that §1 never listed the pickup **address itself** as
   collected data.
4. **Spot-chip review** (5 min): 세빛섬 was map-calibrated; the other 7 chips in
   `address-pin.tsx` CHIPS are my map reading — swap any by name.
5. **Device smoke**: 길찾기 with the Naver Map app installed (the sim only proved
   the web fallback); the pocket-walk GPS test; APNs.
6. Standing: seed-runner decision, owner LA relay + config row, media purge,
   변호사 / 위치기반 신고 / interviews / TestFlight.

### Decisions awaiting Sean (in TODOS.md)
- **P1 — `done.tsx` can print a stale mock dog name** on a Peak moment
  (`done.tsx:30` reads `runRequests[0]` because `runResult` carries no dogName).
- `earnings.tsx` has two announcement-only buttons (빠른 정산 신청 / 등록) —
  remove until real, or keep as an explicit waitlist affordance?
- `rewards.tsx:168` prints a raw English enum.
- The 안심 결제 chip was removed from request per the lab mock — restore?
- Declutter lab (`docs/labs/declutter-lab.html`) variants Ⓐ①/Ⓐ② were never
  picked (Sean gave an explicit home list instead); the **5 "free surgeries"**
  in it still apply — chiefly merging the find-now radar island, which
  duplicates the GO disc's own handler for zero information loss.

## ④ Infrastructure notes

- **Skills installed** at `~/.claude/skills/`: `apple-design`, `prototype`
  (both apply), `pick-ui-library`, `ask-sonner` (**web-only** — Sonner/base-ui/
  cmdk/Framer Motion cannot install in RN; use them for taste, never for
  dependencies). The app's missing toast primitive still needs an RN-native
  answer.
- gstack labs are the house ritual: numbered variants, Sean picks by number.
  New this session: `docs/labs/go-premium-lab.html`,
  `docs/labs/declutter-lab.html`, `docs/design/design-review-20260811.md`.
- Harness: `pkill -f "bin/postgres"` first; UTF-8 locale required.
- CocoaPods/Expo need `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`; verify installs by
  bundle container path, never exit code.
- The dev-client "Open debugger to view warnings" banner is RN LogBox in dev
  builds — not a product bug (resolved mystery from the prior handoff).

## ⑤ Test data on prod (deliberate)

s4kim2025 has one address ("Home", pin at 세빛섬) attached to two 8/4
`runner_enroute` bookings, used to verify the map and cancel surfaces. One
belongs to a recurring series. Cancelling them is the honest in-app path; I did
NOT execute the destructive cancel against prod.

## ⑥ Next 1–3

1. **[me]** Land the design-review findings (`docs/design/design-review-20260811.md`)
   — reduced motion is wired into only 2 loops so far; momentum projection for
   the gear dial; the P1 done.tsx name bug.
2. **[Sean]** NCP checkboxes + geocode secret + counsel flags + chip review.
3. **[Sean]** The strategic call the CEO voice made twice: **payments (manual
   bank-transfer bridge) and incident reporting** are what actually stand between
   here and a paying customer. The design system is now strong enough that this
   should be the next slice.
