# Loading · error · empty · submit audit — every route, read not grepped (2026-09-17)

Settles `docs/design/hig-conformance-checklist.md` row **F1** and re-checks the CLAUDE.md honesty
laws (loading is not 0 · failures are shown as failures · busy = label swap, never opacity) route by
route. 59 route files under `app/app/**` judged (excluding `dev/`, `_layout.tsx`, `+not-found.tsx`),
each verdict read from the component with a `file:line`; `[unverified]` marks an inference. Produced
by a read-only audit agent (Claude Opus 5) and persisted by the orchestrating session; line numbers are
trunk `ffea066`.

**F1 verdict:** production `ActivityIndicator` = 0 (both hits are `app/app/dev/club-lab.tsx`). That is
**not** a missing loading state — 46 of 59 routes render an explicit loading affordance (44 a named
Korean sentence, 2 a `Skeleton` block: `owner/report.tsx:482`, `owner/request.tsx:969`). The house
idiom is a sentence, not a spinner. Whether a sentence satisfies HIG F1's "system progress indicator"
or only F2's "placeholder, not a blank screen" is a judgement left open; a stricter reading of F1 would
fail all 44 sentences. The real gap is the Tier 1 list below, not the absence of a spinner.

## Counts (rows judged, not grep hits)

| axis | result |
|---|---|
| Loading (59) | 46 explicit affordance · 4 `—` placeholders (no fabricated zero) · 3 render nothing · **2 render the empty/settled face** · **1 renders a failure as loading** · 3 N/A |
| Error (59) | 41 copy + working retry · 6 copy, no retry · **3 silent** · **3 console-only** · 6 N/A |
| Empty (59) | 26 honest + next action · 13 honest, no action · 3 blank / section vanishes · 17 N/A |
| Refresh | 14 files mount `RefreshControl` (16 usages); 0 carry an instructional `title` (F10 passes) |
| Submit (38 routes with a server-writing primary) | 31 label swap · **6 opacity** (5 with no label swap) · 1 no in-flight affordance (`owner/matching.tsx:293`) · every submit path surfaces its failure |

## Ranked violations

**Tier 1 — failure or loading wearing the wrong face (honesty law)**

1. `app/app/club/session/[sid].tsx:251` — `fetchSessionRoster(sid).then(…).catch(() => {})`: a failed
   roster read leaves `roster` null, so `renderRoster()` (`:1186`) falls to `:1191` and prints
   `명단을 불러오는 중...` **forever**. The board call 8 lines down (`:259–261`) does it right with
   `setBoardFailed`. Fix: give the roster the `boardFailed` treatment.
2. `app/app/shop.tsx:47–50` — four `.catch(() => {})`, no state, no console, no retry. `claims`/`drops`
   stay `[]` so a failed read renders as "you own none" (`:114`, `:123` vanish) and a failed `fetchMiles`
   renders the earn-rate blurb (`:100–103`). Loading, failure and empty are one face. Fix: per-section
   `err` flag + fail strip, the `runner/rewards.tsx:162` shape.
3. `app/app/owner/card-link.tsx:33–37` — `fetchUnsettledCharge().catch(() => null)` then
   `setLocked(lk === true)` turns an unread lock into "nothing owed"; `:34 fetchMyPayments(30).catch(() => [])`
   turns an unread ledger into "no failed charges", so the arrears face can never appear after a failed
   read. The comment at `:27–31` says `locked` stays null on failure — `:37` contradicts it. Fix: keep
   `locked` null on failure and gate `arrears` on a known value.
4. `app/app/settings.tsx:59` — `fetchMyProfile().then(setProfile).catch(() => {})`; `:94` renders `'—'`
   identically while loading and after failure.
5. `app/app/my.tsx:104` — profile read is console-only; `:201–202` falls to `'—'`, avatar to `'나'`. The
   two sibling reads on the same screen (`recErr :62→:343`, `stampErr :84→:356`) do loud-fail + retry.
6. `app/app/course/[id].tsx:194–204` — no loading state (body gated at `:227`, only the back bar
   renders); error at `:225` is a dim box with **no retry and no exit**.
7. `app/app/shot/[bid].tsx:238–244` — no loading state: while the first fetch is in flight `:831`,
   `:839`, `:849`, `:853` are all false, so the screen is a header over nothing.
8. `app/app/cards.tsx:62–65` — no loading state: `patches`/`stampStats` null means `:97`, `:124`,
   `:167`, `:178` are all false and the masthead renders over an empty page (failure handling at
   `:116/:124/:167` is fine).

**Tier 2 — busy rendered as opacity (DESIGN.md button matrix: busy = label swap, never alpha)**

9. `app/app/shot/[bid].tsx:1005` — `busy && { opacity: 0.5 }`; `ghostLabel` (`:802–811`) has no busy
   branch; no `accessibilityState`.
10. `app/app/shot/[bid].tsx:1026` — `busy && { opacity: 0.6 }` with a fixed label (`:1034`); the comment
    `:1021–1023` claims busy "keeps the lip and loses only the travel" — the alpha is what renders.
11. `app/app/shot/[bid].tsx:1008` — label swaps (`mainLabel :800`) but `opacity: 0.6` is layered on top.
12. `app/app/club/[id].tsx:772` — `memBusy && { opacity: 0.5 }`, label fixed (`:774`); the join CTA at
    `:787–792` uses `ClubCta busy` with a label swap — one screen, two grammars.
13. `app/app/chat.tsx:413` — `sendBlocked && { opacity: 0.5 }`; `sendBlocked :273` folds `sending` in
    with the genuinely-disabled cases; a11y (`:418`) reports `disabled`, never `busy`. Icon-only `↑`.
14. `app/app/community.tsx:755` — identical shape (`sendBlocked :239`, a11y `:758`).
15. `app/app/login.tsx:79` — `busy && { opacity: 0.6 }`; the label does swap (`:86`), but this is the
    app's only door.

**Tier 3 — silent catches with a smaller blast radius ("failure = section absent")**

16. `app/app/club/[id].tsx:152–155` — four `.catch(() => {})`; `:139` calls them 「장식」 but `board`
    drives the RSVP/delegation rows.
17. `app/app/owner/report.tsx:281,285,289,300–306,318,382` — cluster of catch-to-nothing (standings,
    earning, review, patch/stamp pop, gaps, slot); each defended in comment; none surfaces.
18. `app/app/owner/home.tsx:250,253,254,256,262` — console-only on unread/moments/ticker/runners/beacon;
    the sections just don't render (the primary bookings read is exemplary: `:486` → `home-hero.tsx:172/184`).
19. `app/app/runner/rewards.tsx:59,63,64` — miles/claims/status silent while `drops` alone gets
    loud-fail (`:62→:162`).
20. `app/app/club/receipt/[bid].tsx:89` — `fetchRunEarning(bid).catch(() => {})`; block at `:382`
    silently absent.
21. `app/app/owner/address-pin.tsx:118–120` — resolve chain falls back to a hardcoded BANPO center with
    `bottomed = true`; `:208` says 주소를 불러오지 못했어요 but there is no retry.

## Per-route table

| Route | Loading | Error | Empty | Refresh | Submit |
|---|---|---|---|---|---|
| alerts.tsx | text `:180` | loud-fail + retry `:186` (set `:76`) | honest + next `:198` | yes `:117` | mark-read; Alert on fail `:95`, no busy label |
| cards.tsx | **blank** — sections absent `:97,:124,:167` | per-section copy `:118,:132,:175`, no retry | honest `:151` | no | N/A |
| chat.tsx | header `연결 중...` `:284`; body blank `:346` | copy + retry `:332` (set `:99`) | honest + prompt `:353` | no (poll `:154`) | **opacity-only `:413`** (`sendBlocked :273`); Alert `:179,:190` |
| club/[id].tsx | text `:403` | loud-fail + retry `:361` (set `:158`) | honest + action `:413` | yes `:349` | join label swap `:788`; **탈퇴 opacity-only `:772`**; Alert `:230,:269,:291` |
| club/case/[cid].tsx | LoadGate `:103` | LoadGate + retry `:103` (set `:42`) | copy, no action `:158` | yes `:138` | ClubCta busy `:179,:232,:252`; Alert `:121,:129` |
| club/companion/[sid].tsx | text `:213` | strip `:226`, no retry (set `:105`) | honest + instruction `:231` | no | 4-state save `:92`; failure shown `:297` |
| club/console/[sid].tsx | LoadGate `:179,:193` | LoadGate + retry (set `:142,:151`) | honest `:596,:633,:691,:728` | yes `:472,:535,:573` | ClubCta busy `:494,:877,:960`; Alert `:221` |
| club/delegate/[sid].tsx | text `:199,:254` | branch `:200` (set `:67`) | honest + next `:140` | no | SealSlide disabled `:246` + reason `:251`; Alert `:97` |
| club/map/[sid].tsx | `연결하는 중...` `:467` (gate `:343`) | `:428` + retry, `:457` | window copy `:468` | no (30 s `:202`) | N/A [unverified — 627 lines not all read] |
| club/pass/[sid].tsx | LoadGate `:58` | LoadGate + retry (set `:51`) | N/A | no | ClubCta busy `:197`; Alert `:94` |
| club/receipt/[bid].tsx | LoadGate `:183` | LoadGate + retry (set `:80`) | N/A | no | busy `:453`, label swap `:416`; **earning silent `:89`** |
| club/run/[sid].tsx | LoadGate `:474` | LoadGate (set `:172`) | `:482` | no | ClubCta busy `:638,:674,:728`; Alert `:402,:416` |
| club/session/[sid].tsx | LoadGate `:353` | LoadGate + retry (set `:227`); **roster failure = loading `:251→:1191`** | `:1189` | yes `:189` | busy + Alert `:414,:503,:730` |
| community.tsx | text `:447`, `:389` | loud-fail + retry `:449,:392` | honest + action `:458,:401` | yes `:276` | **opacity-only `:755`** (`:239`); Alert `:251` |
| compose.tsx | text `:200` | `:203` + retry | honest `:213` | no | PaperBtn busyLabel `:191`; Alert `:116,:127` |
| course/[id].tsx | **nothing/blank** `:194–204`, body gated `:227` | dim box `:225`, **no retry** | `:203` not-found | no | nav CTA `:284` — N/A |
| incident/[bid].tsx | text `:136` | `:138` + retry | `:148` null | yes `:251` | busyLabel `:180,:237`; Alert `:115,:129` |
| index.tsx | `notReady :133` → `시작하는 중... :135` | `fail() :75,:88` | N/A | no | label swap `:135`, disabled `:151,:166`, a11y `:154,:169` |
| leaderboard.tsx | text `:102` | `:107` + retry (set `:38`) | honest `:116` | yes `:52` | N/A |
| login.tsx | N/A | persistent box + retry `:91` | N/A | no | label swap `:86` **+ opacity `:79`** |
| my.tsx | `—` placeholders, sections absent | recErr `:343`, stampErr `:356` + retry; **profile console-only `:104`** | honest `:151` | no | upload ellipsis `:236`; Alert `:137` |
| onboard/owner.tsx | pin `unknown :50` | pin error `:262`; setErr `:144` | N/A | no | busyLabel `:287`, disabled `:251,:295` |
| onboard/runner.tsx | N/A | inline `:78` | N/A | no | busyLabel `:185` |
| owner/address-pin.tsx | text `:208,:210` | `:208` **no retry**; save `:286` retry | `:212` | no | busyLabel `:336`, `:313` |
| owner/addresses.tsx | text `:151` | `:157` + retry (set `:71`) | honest + action `:166` | no | busyLabel `:230`; Alert `:83,:112,:123` |
| owner/card-link.tsx | **settled face `:105`** | **silent `:33,:34→:37`** | N/A | no | four honest outcomes `:75–91` |
| owner/course-map.tsx | text `:370,:508` | `:410` + retry | `:381,:390` | no | N/A |
| owner/dog.tsx | text `:253` | `:257` + retry (set `:110`) | honest + action `:270` | no | busyLabel `:450`; Alert `:156,:231` |
| owner/fitness.tsx | `—`, no 0 claims `:192,:221,:434` | fitFail + retry `:176`; moments `:325` | honest + action `:264` | no | optimistic + rollback + Alert `:113` |
| owner/home.tsx | home-hero.tsx `:172` (gate `:486`) | home-hero.tsx `:184` + retry; fitErr `:746` | `:572` | no | nav; **console-only `:250,:253,:254,:256,:262`** |
| owner/live.tsx | text `:637` | `:629` + retry; route `:541`; pickup `:345` | `:38` | no (realtime) | label swap `:1040`, disabled `:1036`; Alert `:484` |
| owner/matching.tsx | `:440` (`rosterLoading :204`) | `:418` + retry | `:448` (`:289`) | no | Alert on fail `:300`; no in-row busy affordance `:293` [unverified] |
| owner/meetup.tsx | text `:473` | `:457` + retry | no-pin + action `:462` | no | busyLabel `:685,:701`; Alert `:318` |
| owner/pay.tsx | `LOADING :42,:66`, table gated `:223` | `:443` + 다시 불러오기 | N/A | no | busyLabel `:439,:445,:478` |
| owner/radar.tsx | `확인 중… :431` | `:423` + retry (set `:195`); card `:359` | honest `:432` | no | label swap `:486`, a11y `:483`; busyLabel `:500`; Alert `:277,:304` |
| owner/report.tsx | **Skeleton `:482–484`** | `:465` (set `:280`) | honest + action `:488`; exit `:473` | no | N/A; **silent cluster `:281,:285,:289,:300,:318,:382`** |
| owner/request.tsx | text `:886,:1142`, **Skeleton `:969`** | `:915,:944,:971` | `:1146`, `:210` | no | Alert `:587` + `haptic('error') :524,:548` |
| owner/reschedule.tsx | `확인 중 :421` | `:346`, `:404`, retry `:398` | `:360` | no | busyLabel `:443`; Alert `:199,:213` |
| owner/review.tsx | N/A | Alert `:78`; dup `:71` | N/A | no | busyLabel `:166` |
| owner/schedule.tsx | text `:591`, header `:502` | `:597` + retry (set `:215`) | honest + action `:603` | yes `:483` | Alert `:277,:1075` |
| payments.tsx | text `:195,:252` | `:196,:253` + retry | `:233,:261` | no | busy label `:173,:185`; Alert `:131`; honest re-read `:135` |
| profile/edit.tsx | text `:141` | `:134` + retry; bio `:169` | N/A | no | busyLabel `:185`; step-named `saveErr :115` |
| runner-profile/[id].tsx | `—` kept `:326`; posts `:398` | `:373`, `:399` + retry, `:127` | `:405,:549,:616` | no | label swap `:447`; Alert `:230,:251` |
| runner/apply.tsx | `:318,:408` | `:324` + retry, `:411` | `:406` | no | busyLabel `:743,:850`; `:270,:286` inline |
| runner/availability.tsx | `:261,:357` | `:267,:361` + retry | `:373` | no | busyLabel `:443`; `:415` swap; Alert `:134,:187` |
| runner/base-pin.tsx | `resolving :76`, no copy | readErr `:104` [render site unverified]; save strip `:151` | locked `:284` | no | busyLabel `:290` |
| runner/calendar.tsx | text `:322`, header `:288` | `:328` + retry (set `:97`) | honest + action `:337` | yes `:259` | N/A |
| runner/done.tsx | trace `:189`, photos `:268` | `:194`, `:271` + retry | honest `:295` | no | label swap `:283,:349`; Alert `:143` |
| runner/earnings.tsx | text `:168` | `:174` + retry (set `:87`) | honest `:183` | yes `:110` | N/A |
| runner/home.tsx | `:977,:996,:1113,:1266` | `:979,:989,:1115,:1256` + retry | `:997,:980` | no | label swap `:911`, disabled `:910,:917`; Alert `:311,:334,:389,:410` |
| runner/meetup.tsx | text `:399,:441` (`:100`) | `:400,:433`, retry `:490` | `:122` | no | busy `:638`; inline `:248`; Alert `:263` |
| runner/requests.tsx | `:760`, header `:613` | `:766` + retry (set `:351`) | honest + action `:780,:828` | yes `:604` | label swap `:707,:748`, both disabled `:656`; Alert `:402,:702,:741` |
| runner/review.tsx | context only `:61` | inline loud-fail + retry `:84` | N/A | no | label swap `:232`; busy never painted disabled `:130` |
| runner/rewards.tsx | text `:156` | `:162` + retry (set `:62`) | honest `:170` | yes `:105` | label swap `:203,:224`; Alert `:83`; **silent `:59,:63,:64`** |
| runner/run.tsx | text `:1361,:1389` | `:1081`, `:545` | N/A | no | label swap `:1520,:1536`; Alert `:234,:822` |
| safety.tsx | text `:156,:248` | `:145` + retry (set `:43`) | honest + action `:158` | no | Alert `:71` w/ 112·119, `:84,:94` |
| settings.tsx | **`—` `:94`** | **silent `:59`** | N/A | no | nav rows only |
| shop.tsx | **`—` + earn blurb `:78,:100`** | **silent `:47–50`** | sections vanish `:114,:123` | yes `:64` | N/A |
| shot/[bid].tsx | **nothing/blank `:238–244`** | `:831` + retry, `:839` + exit | `:849` | no | main swap `:800` **+ opacity `:1008`**; **ghost `:1005` / IG `:1026` opacity-only** |

## Could not determine

- Long files (`owner/live`, `owner/meetup`, `runner/meetup`, `club/console`, `club/run`, `owner/request`,
  `runner/home`, `runner/run`, `club/session`): verdicts rest on the cited branches; a silent catch outside
  the regions read would not appear here.
- `runner/base-pin.tsx:104` sets `readErr` — its render site was not located.
- `runner/done.tsx` renders a `runResult` handed in by the run screen; whether a cold deep link exists
  (which would make the first frame blank) is unverified.
