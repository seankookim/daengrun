# Type & Density Audit — 7 screens (2026-08-10, read-only sweep)

Input for the freeze-compliant polish pass (DESIGN.md · go-premium-lab.html Ⓒ).
Produced by a fable audit agent; all claims carry file:line evidence. Baseline
laws: layout.gutter=11 (theme.ts:106), type.caption=12 (:117), paper 14pt floor
(:148-160), Oswald via useNumFont (:99). Exempt: letterspaced caps kickers,
serial/MRZ, barcode/glyphs.

## Cross-cutting conclusions (the headlines)

- **layout.gutter (11) is used by ZERO of the seven screens.** Actual gutters:
  11/13/14/16/28 — three competing gutters on owner/home alone. The July
  "gutter 11" decision never actually governed; standardizing (to ~15) is not a
  reversal, it is the first enforcement.
- **The 14pt floor mostly won.** The dominant sub-14 pattern left is **Korean
  data smuggled into latin kicker styles**: my.tsx role tags 12 (:495), field
  keys 11.5 (:506), role-switch BUTTON label 12 (:597); runner/home tierLabel
  in 12pt kickers (:347, :360); owner/home district/tier data in kickers
  (:1335, :1342). Kicker exemption is for decoration, not data.
- **The two legacy-green screens (request, schedule) have the cleanest sub-14
  record but the weakest numerals**: request.tsx never imports useNumFont —
  its 28.5pt 총 결제 금액 is system-900 (:596); schedule's 25.5pt sheet header
  ignores the loaded nf (:280).
- **~27 filler-text candidates** across 7 screens (kill list below), including
  one STALE-FACT BUG and one honesty flag.

## Notable single findings

- **Stale-fact bug**: schedule.tsx:157 empty state says "홈에서 슬라이드로
  예약해보세요" — the slide-to-book mechanic was retired (owner/home.tsx:1222).
  The empty state instructs a gesture that no longer exists.
- **Honesty flag**: owner/home.tsx:1145 "LIVE RUNNERS · SEOCHO" is a hardcoded
  district claim regardless of user location.
- **Stale budget comment**: owner/home.tsx:1585-1589 s.goDisc comment still
  cites the old 216/122 ring math; :49 (237≤240) is current.
- **Sanctioned, do not cut without Sean**: schedule.tsx:352 바디캠 roadmap line
  (Sean D3=B). **Legal**: login.tsx:139-141 asserts consent to 약관/처리방침
  with no tappable links.
- my.tsx repeats the photo-change hint THREE times (:274, ✎ badge, sheet :461).
- request.tsx:630 "반복 예약 (준비 중)" is a dead chip at opacity .45 while a
  WORKING 매주 반복 toggle exists on the same screen (:541-555).

## Per-screen summary

| Screen | World | Sub-14 non-exempt | Filler | Top enlarge | Landmines |
|---|---|---|---|---|---|
| owner/home | lilac | 3-5 (data-in-kickers :1335/:1342/:1549; stamp 12 cond. :35) | 8 (:1083 :1153 :1151 :1197 :1402 :1447 :1217 :1463) | ticket time 20 (:990 nf✓) · 예상결제 19 (:1201) · D-day 14 (:1669) | GO 237≤240 (:49) · goFont ladder (:477) · HEADER_H 123 (:249) · HERO_SMALL 199 (:260) · STAMP_CELL (:26) · beaconLine (:1633) |
| runner/home | lilac | 3-4 (tierLabel@12 :347/:360; 정산@12 :528) | 6 (:595 :711 :794 :446 :421 :548) | stop times 14 (:1050, w52 cage) · stopPay 14 (:1054) · 월/누적 14 (:969) | bibNoCol 116 (:931) · stubAct 112 (:1030) · stop col 52 (:646) · label col 86 (:133) · BUG-A pairs (:937/:962/:1005/:1035) · bibName frozen (:921) |
| owner/request | legacy green | 0 | 4-5 (:630 dead chip · :285 · :520 · :442) | 총결제 28.5 NO-NF (:596) · timeChip 14/max128 (:580) | timeChip maxW 128 (:799) · paddingBottom 190↔ticket (:271) · routeCard 240 (:494) |
| my | lilac passport | 6-7 (roleTag 12 :495 · fldK 11.5 :506 · microK 12 :493 · idEditEm 11.5 :516 · btnRoleSw 12 :597) | 3 (:200 · :274+:461 dup · :355) | name 15 (:507) · recN 23 (:536) · stamp cnt 14 (:567) | visaCnt pairing (:567) · stamp budgets live in stamp.tsx (:37) |
| owner/schedule | legacy green | 0 | 3 hard (:157 STALE · :129 jargon · :369) +1 sanctioned (:352) | agenda time 18 (:186 nf✓) · sheet 25.5 NO-NF (:280) · price 14.5 (:216) | seal 84 (:583) · rail geom (:565) · sheet maxH 560 (:273) |
| owner/addresses | paper | 0 | 3 (:84 길게눌러 · :125 roadmap · :59 tap-narration) | (weak) | none |
| login | legacy dark | 0 | 0 (legal dead-refs :139) | none | none |

## Button labels < 16 (implementation checklist)

owner/home: meetBtn 14 (:1038,:1011) · fnCta 14 (:1169) · fnPay 15 (:1458) ·
widgetBtn 14 (:1048-:1075) · secLink/beaconGo/nudge links 14.
runner/home: doorName 14.5 (:546 — the money action) · acceptTxt 14 (:1038) ·
btnCoralTxt 14 (:997) · swLabel 14 (:930) · links 14.
request: timeChip 14 (:580) · methodChip/dogSelChip/links 14 · 변경 15 (:367).
my: idEditTxt 14 + idEditEm 11.5 (:515) · btnRoleSwTxt 12 (:597) · menu rows 14.
schedule: filter chips 14 (:146) · shareBtn 14 (:241,:251) · goLiveBtn 15
(:232) · emptyCta 14.5 (:262) · cancelLink 14.5.
addresses: addBtn 14.5 (:119) · PaperBtn label size → src/components/paper-btn.tsx.

## Filler kill list (full quotes in agent transcript; do NOT cut :352 or legal)

owner/home :1083 :1153 :1151 :1197 :1402 :1447 :1217 (:1463 keep 2nd clause) ·
runner/home :595 :711(1st clause) :794(keep 06-22시) :446(keep 매주 정산)
:421(keep 수수료 차감) :548 · request :630 :285 :520 :442 · my :200 :274 :355 ·
schedule :157(REWORD, stale) :129 :369 · addresses :84(→ first-run hint)
:125 :59(2nd clause).
