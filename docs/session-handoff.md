# SESSION HANDOFF — 2026-08-10/11 · coordinates shipped · design system rebuilt · honesty sweep

English everywhere except in-app user-facing copy (CLAUDE.md §Language).
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md is the permanent law book. **`DESIGN.md` is now the design law book** —
read it before touching any UI. Prior handoffs live in this file's git history.

**Build in the MAIN checkout `/Users/sean/dev/daengrun` (branch redesign-v4).**
Worktrees under `.claude/worktrees/` are stale — never build or gate there.

---

## ⓪ STATUS — everything committed and pushed

| | |
|---|---|
| git | **`331bcf4`**, origin up to date, working tree clean |
| database | **0066** applied + verified on prod (local = remote) |
| edge functions | `geocode-address` + `transition-booking` deployed |
| harness | **305 / 0** (independently re-run, not just reported) |
| gates | tsc 0 · check-rpc 75/109 · **geo runner 38/0 — now part of the commit gate** |
| simulator | owner home · request stepper + gear dial · runner home · earnings · community · compose · meetup all walked |

⚠ **Deploy coupling:** 0066 must be pushed before any `functions deploy` — the
edge function calls `marketplace_cancel_fee`, which 0066 creates.

## ① What shipped (14 commits, `c5f22db` → `331bcf4`)

**Product**
1. **0065 coordinates/geocoding** — pin-first capture (`owner/address-pin.tsx`),
   real pickup maps on both meetup screens, 길찾기 with web fallback,
   `geocode-address` as an honest no-op until the NCP secret exists, backfill
   script. Course maps stay honestly dark (`routes.trace` is schematic).
2. **0066 en-route cancel at 50%** (your decision) — transition map widened for
   `runner_enroute → cancelled_owner`, `picked_up` still blocked and pinned. Fee
   ladder moved into SQL so the harness can pin a money constant. A CAS on the
   quoted status closes the quote-then-depart race the widening created.
   Verified on prod: 12,450 on a 24,900 booking = exactly 50%.
3. **Community + compose** — Instagram *anatomy* on paper grammar, `compose.tsx`
   (completed-run picker, honest preconditions), entry points on both homes.
   Post→delete verified against prod.

**Design system**
4. **DESIGN.md created and hardened four times** — §2 token worlds + paper
   migration grammar · §3 typography · **§3b COMPONENT SPEC** (your "thought you
   were using it" critique fixed at the root) · §7 honesty · §7b decluttering
   (Laws of UX / HIG / Maze) · **§7c Apple fluid-interface doctrine** · §8
   budgets · §9 frozen zones.
5. Paper chrome on every main tab · type/density wave (gutter 15 finally
   enforced — it had ZERO importers before) · GO premium Ⓐ④ + energy green ·
   brand lockup masthead · emoji purge (~160 marks, 33 files) · owner/runner/
   request rebuilt to §3b incl. the **gear distance dial** · **7 legacy-green
   runner screens scrapped**.

**Honesty sweep (the most valuable work of the session)**
6. Full-app design review → `docs/design/design-review-20260811.md` (51 screens
   + 13 components, no coverage gaps). Verdicts: PASS 8 · MINOR 30 · NEEDS WORK
   25 · SCRAP 1. Every **P1 fixed** in `331bcf4`:
   - **Mock data was reaching customers**: every completion screen named the
     *mock* dog 초코; `run.tsx` used the mock's km as the **auto-settle
     threshold** (a fabricated number deciding money). Both dead. Auto-settle is
     now hard-off without a real target, announced honestly.
   - **A silent catch was destroying runner data**: `availability.tsx` rendered
     the default all-쉬는날 grid on a *failed* load, so one 저장하기 wiped the
     runner's real schedule. Now structurally unreachable.
   - ~30 silent-catch sites across 22 screens now render loading ≠ empty ≠ error,
     including the club **consent document** (was lying on a legal surface) and
     two screens painting a slot 가능 when the check had **failed**.
   - **Trust theater removed**: the owner stop button made no server call;
     matching fabricated an 88% response rate carrying 35% of the score; the
     신원인증 badge had no data source.

## 🔴 ② WHAT ONLY SEAN CAN DO

**Ops (unblocks shipped features)**
1. **NCP console — TWO checkboxes**: Mobile Dynamic Map **and** Geocoding API on
   the app registered for `com.seankookim.daengrun`. Device maps + geocode
   pre-centering are blocked until then.
2. **`supabase secrets set NAVER_GEOCODE_SECRET=...`** — until then the picker is
   pin-only by design and backfill refuses to run.
3. **Counsel**: privacy policy carries a coordinates rider (HTML-comment marked);
   also flag that §1 never listed the pickup **address itself** as collected.
4. **Spot-chip review** (5 min): 세빛섬 is map-calibrated; the other 7 in
   `address-pin.tsx` CHIPS are my map reading.
5. **Device smoke**: 길찾기 with the Naver Map app installed (sim only proved the
   web fallback) · the pocket-walk GPS test · APNs.
6. Standing: seed-runner decision, owner LA relay + config row, media purge,
   변호사 / 위치기반 신고 / interviews / TestFlight.

**Product decisions logged in TODOS.md**
- **P1 — mid-run stop can go unseen.** The owner's stop reason now goes via chat
  (the only real channel — no owner-side transition exists for an active run),
  but chat has **no push**. Fix is either a real owner-stop transition (money ⇒
  own migration + adversarial cycle) or a chat push. Your call.
- **P1 — prod `identity_verified` cleanup** gates re-adding the 신원인증 badge
  *and* the safety.tsx verification claim. Data cleanup, not client work.
- `earnings.tsx` settlement-intent CTAs were removed (no honest store exists).
- The 안심 결제 chip was removed from request per the lab mock — restore?
- `docs/labs/declutter-lab.html` Ⓐ variants were never picked (you gave an
  explicit home list instead). Its **5 "free surgeries"** still apply — chiefly
  merging the find-now radar island, which duplicates the GO disc's own handler.

## ③ Known-good / known-bad map

**Genuinely good (don't "fix" these):** zero TouchableOpacity app-wide, zero
colored emoji, compose, the receipt seal ceremony, `club/case`'s LoadGate idiom
(now promoted to a shared component), the GPS honesty stack, shot's photo
truthfulness.

**Still open (P2/P3, full list in the review + TODOS):** reduced motion is wired
into only 2 of ~10 loops · momentum projection for the gear dial (§7c:
`snapToInterval` alone lands short on a fast flick) · `rewards.tsx:168` prints a
raw English enum · `owner/pay.tsx` authorizing dead-end needs a poll/재확인 CTA ·
club receipt photo-consent gate fails **open** · `ui.tsx` still exports the
pre-§3b kit · ClubTag ships 9.5pt Korean chips on six screens.

## ④ Infrastructure notes

- **Skills installed** at `~/.claude/skills/`: `apple-design` + `prototype`
  (both apply), `pick-ui-library` + `ask-sonner` (**web-only** — Sonner/base-ui/
  cmdk/Framer Motion cannot install in RN; taste references only). The app's
  missing toast primitive still needs an RN-native answer.
- House ritual is numbered labs, picked by number: `docs/labs/go-premium-lab.html`,
  `docs/labs/declutter-lab.html`, `docs/design/design-review-20260811.md`.
- Harness: `pkill -f "bin/postgres"` first; UTF-8 locale required.
- Expo/CocoaPods need `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`; verify installs by
  bundle container path, never exit code.
- The dev-client "Open debugger to view warnings" banner is RN LogBox in dev
  builds — not a product bug (resolved from the prior handoff).

## ⑤ Test data on prod (deliberate)

s4kim2025 has one address ("Home", pin at 세빛섬) attached to two 8/4
`runner_enroute` bookings, used to verify map + cancel surfaces. One belongs to a
recurring series. The in-app cancel is the honest way to clear them; I did not
execute the destructive cancel against prod.

## ⑥ Next 1–3

1. **[Sean]** NCP checkboxes + geocode secret + counsel flags + chip review, then
   the two P1 product decisions above.
2. **[me]** The review's P2 tier: reduced motion across the remaining loops,
   gear-dial momentum projection, the `ui.tsx`/ClubTag component-layer sweep
   (~30 findings clear from one component), `owner/pay.tsx`'s dead-end.
3. **[Sean + me]** The strategic call the CEO voice made twice today: **payments
   (manual bank-transfer bridge) and incident reporting** are what actually stand
   between here and a paying customer. The design system and the honesty floor
   are now solid enough that this should be the next slice.
