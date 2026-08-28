# Were Sean's 142-variant picks built? — measured 2026-08-28

He asked, verbatim: 「so i made picks for all these labs, including this mega board … have my
preferences been made?? yes or no」.

**Answer: his picks were never lost, and most are built.** 39 asks measured against executable
code. Owner **15/20 built**, runner **7/10 built**, club **4/9 built** — and the club shortfall is
almost entirely *compliance with his own instruction*, not neglect.

⚠ **The mega board artifact is a BLANK pick sheet** — 53 screens, 142 variants, and the Pick column
is empty `<div class="box">` elements. His answers never lived in it; they live in
`docs/decisions/2026-08-24-sean-ui-club-commentary.md`, recorded verbatim the evening he sent them.
**Anyone judging by the board alone would answer 「no」 and be wrong.**

## Scoreboard

| lane | built | partial | not built | superseded | unsettled |
|---|---|---|---|---|---|
| Owner (20) | 15 | 1 | 2 | — | 2 |
| Runner (10) | 7 | 2 | — | 1 (by Sean himself) | — |
| Club (9) | 4 | 2 | 3 | — | — |

## The five that are genuinely missing

1. 🔴 **`club_end_pack_runs` has no button.** `0144_club_pack_run_end.sql:290` — server built,
   contract-anchored, reviewed, deployed. **Zero client callers** (verified independently by the
   announcer: 0 hits for `club_end_pack_runs`/`endPackRuns` across `app/`). The capability his
   Round-7 「러닝 종료」 needs is live and unreachable. Highest-leverage screen in the repo: the
   expensive half is done. ⚠ And it is not cosmetic — until it is wired the ledger is priced by
   the runner's own client values, which is finding #1 of the 2026-08-28 codex REJECT.
2. 🔴 **「too many horizontal red lines」 was never fixed on the screen that showed them.**
   `owner/pay.tsx` still carries three full-bleed `paper.line` (#E8552F) rules — `:363`, `:370`
   (used twice, the double rule), `:385` — plus a `paper.critical` top+bottom fail strip at `:381`.
   A general two-rule cap WAS written and applied — to `matching`, `reschedule`, `addresses`.
   **His actual complaint stands.**
3. 🔴 **The receipt he approved has no door.** `/owner/pay`'s only importer is
   `app/app/dev/pay-lab.tsx:12`. No production route pushes to it.
4. 🔴 **Two-thirds of 「3's focus scheme」 is unbuilt.** The ticker move shipped; the coda size tier
   and the display-font demotion did not. `draw-button.tsx:212` still holds the `96 : 78` pair the
   lab named as the defect, and `home.tsx:451` still renders the wordmark in Black Han Sans —
   two display-font uses on a screen whose law allows one. Recorded as unbuilt, not forgotten.
5. 🟠 **Runner home D③ 예약 규칙 and A② countdown** — the server enforces the booking rules;
   `api.ts:948` is an `insert` with no read/write pair. A② waits on one mapper field.

## The money instruction — verified hardest, both directions

Sean: 「don't show them the 수수료. I don't think we should be showing them the calcuations ever;
only show the final profit per run; keep the margin a secret.」

**HONOURED on screen. Measured by the announcer independently: 0 executable hits** for
`수수료|commission|정산율|공제` across every `app/app/runner/*.tsx`, comments stripped properly.

⚠ **And this is a live worked example of the comment-matching law.** A raw grep returns **20 hits**
and every one is a comment *quoting the removed string* — including the migration's own
「the 정산 수수료 cell (33%) stood here and is REMOVED」. The naive count is 20; the true count is 0.
**The instrument inverts under diligence exactly as CLAUDE.md says it does.**

🟠 **One residual, named and still open.** `api.ts:1468` and `:1533` both
`.select('… base_fare, distance_fare, addon_fare …').eq('runner_id', …)` — the owner's fare
components cross the wire to the runner's client. The mapper discards them and no screen renders
them, so **display-side secrecy holds and wire-side secrecy does not**. The repo already names this
(`0121_runner_money_strip.sql:303`, kept OPEN at `:17`). Not a violation of what he asked to *see*;
a slice is owed.

## Three questions only he can answer — each is one word

1. **「For owner records report, I like 1」** — that lab has section **A** (체력 리포트 / `fitness.tsx`)
   and section **B** (러닝 리포트 / `report.tsx`). It was spent on B — but his very next sentence
   picks B's ① by name (「the stars」), which would make the two sentences redundant. That
   redundancy is evidence the mapping is wrong. **If he meant A, the pick is entirely unspent** and
   `fitness.tsx` has had no design commit since 2026-08-20. **A or B?**
2. **「the general Korean font that I see here」** — the lab told him fonts were SIMULATED by the
   system stack (`enh-owner-home-lab.html:30-32`), and the app sets no Korean `fontFamily` on any
   owner screen outside `Monogram`. So the two probably match *by accident*. **Keep the system
   face, or ship IBM Plex Sans KR properly?**
3. **Which club mock is the target?** 「I like the current shown mock」 was 2026-08-24. He then
   overruled its ground, its font and its purple on 08-25/26 (「the lab isnt good enough; still too
   cramped, remove the purple and the old v0 font」, 「white backgrounds」) and blanket-approved the
   NEW club-v2 set in Round 7 (「i like all lab screens」). **Building honest to the 08-24 mock now
   would re-ship what he later rejected.** 08-24 mock, or the club-v2 set?

## Why the club column is short — and it is NOT neglect

`enh-club-lab.html`'s own verdict: *「EVERYTHING ELSE IN THIS LAB — HELD, not rejected」*. Held on
**his** instruction: 「Straighten this idea out first, every detail and each scenario and screen and
choice everyone needs to make」. The delegation restructure (C4) and the host-screen respec (C6) are
blocked on that spec, which is `docs/plans/2026-08-25-club-delegation-spec-v2.md` — 2,035 lines
whose own status line reads **「Nothing here is built.」**

⚠ **Two club items he asked as QUESTIONS were answered YES and built**, and should not be counted
as debt: the purple block was a photo placeholder and a real `clubs.photo_url` with a host upload
door now stands there (`club/[id].tsx:376-386`); and a case CAN be filed mid-run in the club
(`club/run/[sid].tsx:293`). ⚠ **Not for the marketplace runner** — `runner/run.tsx` has no incident
door at all. That asymmetry is undecided, not ruled.

## Two REGISTRY errors found while measuring

- `REGISTRY.md:202` claims the 「(수수료 차감 후)」 copy was retired. `git log -S` returns exactly one
  commit — the one that ADDED it — and the string is live at `club/case/[cid].tsx:70`. What §H
  actually retired was the runner *notification* copy. Harmless to runners (that screen is
  authority-gated) and wrong as a record.
- The same row still reads 「LAND-READY, NOT LANDED, NOT DEPLOYED」. Measured: its fix-round commit
  is an ancestor of HEAD and 0122–0155 build on it.

## What none of this establishes

**Every verdict above is a source reading.** 「make sure the actual ui is what I see in the mock」
has never been executed as stated — it was satisfied by reading code, in that pass's own words.
Nothing here is simulator- or device-verified, and `docs/design/device-smoke-ui6-2026-08-27.md`
is still 33 unchecked rows. A working local simulator build now exists, so this is closable.
