# Session handoff — refreshed 2026-09-15 (new Mac, first session) — everything below the 09-15 block is the 08-31 record

**Read this before doing anything.** `CLAUDE.md` holds the permanent laws; this file holds
current state. **New since 08-31: `docs/codex-claude-protocol.md` (who does what — Codex astra
writes, Claude orchestrates/gates/lands) and `docs/prompts/codex-app-master.md` (Sean's paste
sheet for the Codex app).** Where a line below conflicts with the 09-15 block, the 09-15 block wins.

> 🔴 **DEPLOY FREEZE — STILL HOLDS, and the reason changed.** Trunk `069459b` now carries ALL
> FIVE pending migrations (0157 · 0158 · 0159 · 0160 · 0161) — B1/0157/0158 landed from the rescue
> branches 2026-09-15 with every gate re-run on the new Mac. Production is still `0156` (last
> measured 08-31; `supabase login` has not been done on this machine, so `migration list --linked`
> cannot be re-read here). Two things gate the ONE deploy: **(1) `supabase login` (Sean)**, and
> **(2) the codex verdicts for the five files — NONE EXISTS.** 0159 is REJECT/11 (fixed by 0160,
> the fix unreviewed); 0160/0161/0157/0158 have no verdict. Per Sean 2026-09-15 codex is for build
> work, so the review is a single diff-scoped `gpt-5.6-sol` high run when the deploy is actually
> possible — not a repo sweep (three parallel sweeps burned 673K tokens for zero verdicts today).

## 2026-09-17 02:1x — Xcode 27 is in, the app builds locally again, HIG work is on trunk

**Supersedes the 01:2x block below where they conflict.** Sean installed **Xcode 27.0 (27A266a, Swift
6.4)** and it is selected (`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`). Measured:
- **Local Release simulator build SUCCEEDED** under Xcode 27 (`npx expo prebuild` → `pod install` with
  `LANG=en_US.UTF-8` → `xcodebuild … -sdk iphonesimulator`, ~1 h; artifact
  `/tmp/dd27/Build/Products/Release-iphonesimulator/app.app`). Installed on the iPhone 16 Pro sim
  (iOS 18.3.1, UDID `E5591637-…`) and launched — login screen, screenshot in the session scratchpad.
  The EAS cloud recipe in `docs/setup-new-machine.md` §3 still works and stays the fallback.
- **Native Claude simulator tool still refuses** (「Xcode is installed but not selected」) even though
  the selection is correct — its MCP server cached the check at session start. A fresh Claude Code
  session should clear it; until then `xcrun simctl install/launch/io screenshot` is the door.
- iOS 27 simulator runtime download failed twice (exit 70); not needed — 18.3.1 runs the app.
- **Codex is quota-walled until 06:44 KST** (measured 02:00 via the plugin: 「You've hit your usage
  limit … try again at 6:44 AM」) despite 「credits renewed」 — Sean's four Codex-app sessions share
  the pool. ⚠ The plugin's `task` verb has no `--help`; `task --help` opens a real thread. A one-shot
  cron (06:52) retries ONE astra-medium slice. Until then HIG fixes are Claude agents.

**HIG conformance (Sean 2026-09-17: 「make sure the app ui is streamlined to ios」):**
- `docs/design/hig-conformance-checklist.md` on trunk (`b1b8ba0`) — 99 rows from 61 HIG pages
  (read from Apple's page JSON; the rendered site is empty JS), 8 tensions for Sean, 10 likely
  violations. ⚠ #6 (runners unprimed for location) is refuted — `onboard/runner.tsx` primes inline.
- Landed `9e702c2`: location primer button 「위치 사용 허용」→「계속」 (HIG names 허용 as the forbidden
  word on a pre-alert screen) and `push.ts` reads permission status before asking, never re-asks.
  Gates: tsc · checks · npm test exit 0, 989/0 (= trunk).
- Queue `docs/decisions/awaiting-sean.md` §2026-09-17 items **8–15** (`7eb7506`): Dynamic Type
  ruling, back-swipe, notification-ask placement, action sheets, `pageSheet` modals, `app.json`
  iPad/icon/splash, the primer copy change (reversible in one word), tensions kept as-is.
- In flight at time of writing, two Claude agents in their own worktrees: `hig/autofill` (AutoFill /
  keyboard semantics on all 51 product `TextInput`s) and `hig/safearea` (device insets replace the
  53 literal `paddingTop: 5x` status-bar clearances; `bottomnav` dock pads with `insets.bottom`).
  Each lands only on green gates with the read-back chain; if this section is not followed by a
  landing note, check `git branch -r | grep hig/` — an unlanded branch there is where they stopped.

**02:5x — both HIG slices LANDED, each re-gated on the combined tree (tsc · 4 checks · npm 989/0):**
- `095666d` AutoFill: 18 of 48 product `TextInput`s got `textContentType` / `autoComplete` /
  `autoCorrect` / `returnKeyType` (name ×3, phone ×3, address ×3, labels, search); 26 prose/numeric
  fields correctly untouched; `6f23499` adds the 이름 row on profile edit via a `Field` pass-through.
  Facts, not gaps: zero OTP/email/password fields exist (Kakao-only login), so zero `secureTextEntry`
  is correct. Open: `owner/dog.tsx:324` 생일 needs `numbers-and-punctuation` (hyphens).
- `d3d56ea` safe areas: 49 literal `paddingTop: 54–78` → `insets.top + (literal − 56)` across 49
  route files (relative spacing preserved; content moves out from under the Dynamic Island; correct
  on SE/iPad); `bottomnav` dock and 7 fixed CTA docks pad with `Math.max(insets.bottom, literal)`.
  Left alone on purpose: `owner/fitness.tsx` (DO-NOT-REFACTOR, `RIBBON_H` arithmetic),
  `owner/home.tsx` `PAD_TOP` (written product decision → queue item 16), `owner/request.tsx:1388`
  (modal body), dev labs. Post-edit crude grep = exactly those 4.
- ⚠ **Neither slice has a codex verdict** — the wall (06:44) refused both attempts (0 B stdout,
  `usage limit` on stderr, read from the tail, not re-run). They are on trunk on green gates; the
  06:52 cron's first job is a diff-scoped `review` of `b1b8ba0..d3d56ea` before any new build slice.
- Device-visual: **UNVERIFIED, and blocked.** The incremental rebuild succeeded and installs, but
  `xcrun simctl openurl daengrun:///settings` stops at iOS's own 「Open in 도그스하이?」 dialog, which
  needs a tap — the native Claude sim tool still refuses (`attach`/`tap`: 「Xcode … not selected」) and
  AppleScript UI scripting hung on the accessibility permission (Sean may find a TCC prompt). Two ways
  out, both Sean's: a fresh Claude Code session (the tool re-checks Xcode) or granting Accessibility to
  the Claude app. The login screen is untouched by both slices. Smoke list for Sean on hardware: first text line clear
  of the island on every screen · dock above the home indicator · QuickType offers name/phone/address
  on 온보딩·안전 연락처·주소 추가 · 생일 still accepts hyphens.

**03:1x — audit landed, two more Claude agents in flight (Codex still walled):**
- `571017f` `docs/design/loading-state-audit.md` — all 59 routes read: F1 settled (46 routes name their
  loading state; zero spinners is the house idiom, not a gap), **8 Tier-1 honesty defects** (a failed
  roster read shows 「불러오는 중」 forever; shop/card-link/settings/my swallow failures into the happy
  face; course/shot/cards render nothing while loading), **7 opacity-busy buttons**, 6 silent-catch
  clusters (Tier 3, recorded, not fixed).
- In flight: `hig/a11y` (VoiceOver names + roles on every icon-only control) and `hig/honesty` (Tier 1
  #1–8 and the text-labelled Tier 2 buttons). Both avoid `runner/run.tsx`, `owner/radar.tsx`,
  `owner/live.tsx` (reserved for the 06:52 Codex VoiceOver slice). If this note is not followed by a
  landing line, `git branch -r | grep hig/` shows where they stopped.

**03:4x — `f8ab905` a11y LANDED** (re-gated on the combined tree: tsc · 4 checks · npm 989/0): VoiceOver
names + roles on 32 icon-only controls across 18 files (sheet scrims 「닫기」, camera chips 「사진 보내기」,
bell 「알림」, 112/119 「…에 전화 걸기」, star rating as `radio` with `selected`, photo tiles as
`imagebutton`); 564 controls enumerated, parser diffed against the crude grep both ways (484/484).
Props-only, proven by stripping the a11y attributes from both diff sides (control arm reddened). Not
done on purpose: two image-dominant tiles (a container label would silence their children), selection
chips with a name but no role/state (A2 follow-up). Spoken output UNVERIFIED — VoiceOver smoke list:
owner home bell + moment strip · a club session sheet scrim · safety 112/119 · runner review stars ·
shot photo tile selected state.

**04:2x — `f38d809` honesty slice LANDED** (combined tree: tsc · 4 checks · npm 989/0 — ⚠ that suite
cannot import a route module, so its green means 「nothing regressed」, not 「this slice was checked」):
Tier 1 #1–8 of `loading-state-audit.md` closed — session roster failure now says so + retry (was
「불러오는 중」 forever); shop/card-link/settings/my surface failed reads instead of the happy face
(card-link keeps `locked` null on a failed read — money path, smoke it); course/shot/cards name their
loading state — and 5 opacity-busy buttons became label swaps (`shot` ×3, club 탈퇴, login). Left on
purpose: Tier 2 #13/#14 (icon-only send buttons need a design call), Tier 3, and a NEW note:
`shot/[bid].tsx:1103` uses a **disabled** alpha (DESIGN.md forbids that too) — follow-up. Device
smoke list (9 items, airplane-mode based) is in the agent's report; the money-path one is #3.

**Unchanged:** production tip 0156, fifteen pending = trunk, deploy is Sean's letter (queue item 1).
Sean's four Codex worktrees: nothing pushed.

## 2026-09-17 01:2x — environment changed, trunk did not

**macOS is now 27.0** (Sean upgraded) but **Xcode is still 16.2** — the iOS 18.3.1 simulator no longer
finishes booting (stuck on the Apple logo across two attempts) and the native Claude simulator tool
refuses with 「Xcode is installed but not selected」. Both resolve with **Xcode 26 from the App Store,
then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`** (sudo = Sean). That also
unlocks the LOCAL simulator build (Expo 57 / Swift 6.2) and sim tapping — item 3 in the queue is now
「install Xcode 26」, not 「upgrade macOS」.
**Supabase login is present** (`supabase migration list --linked` answers): **production tip 0156;
PENDING = exactly the fifteen on trunk (0157–0162, 0166–0174)** — measured 01:20, matches the record.
Production table reads (`db query`) are blocked for Claude by the harness classifier; migration listing
is not. Trunk `fd0f7d8`, unchanged since 09-15 13:02; Sean's four Codex worktrees unchanged, nothing
pushed; the deploy is still his letter (queue item 1, recommendation ⓐ).

## ☀️ MORNING READ — 2026-09-15 overnight, everything below measured and read back from origin

**Trunk `83ad0dc` (start of night: `1b9a41f`).** Landed while you slept, each re-gated on the
combined tree before push (harness delta = pins added every time; deno + tsc + checks + npm):

| slice | what | proof |
|---|---|---|
| B1 · 0157 · 0158 | the stranded rescue-branch migrations | 1135 → 1177/0 |
| P7 inline-script · 0162 chat idempotency (both halves) | codex astra wrote them | 983/0 · 1180/0 |
| 185 repairs (0154 #5/#6/#7) · **0166** (0155 REJECT/6, all six) · **0167** (0154 #3 CRITICAL, phone visibility gated on the flag) | codex findings closed | 1183 · 1188 · 1193/0 |
| **0168 two-phase stop** (from its contract) · **0169** settle belt · settle-run `run_stopping` arm | GPS finding 4 — the live money defect — closed, plus the SQL belt | 1201 · 1205/0 · deno 281 |
| **0170 billing intent row** | Toss memo §4 core (billing findings 3/4/6 local halves) | 1213/0 · deno 287/0 |
| client honesty wave 4 · `store.ts` −162 lines | 15 fixes, 12 non-club files | 983/0 |
| club-v2 labs ×4 (3 variants each) · GPS-4 contract · slim CLAUDE.md draft + incident ledger · suite audit · harness-diet proposal | your decision artifacts | — |

**The simulator runs.** EAS cloud build (`runtimeVersion` policy `fingerprint` was the cause of all
four prior failures — now `appVersion` on trunk; local Xcode is dead on macOS 14.6). iPhone 16 Pro
sim, iOS 18.3.1, `com.seankookim.dogshigh`, login screen up, Supabase host in the bundle. **It is
signed out — Kakao login is yours.** Recipe in `docs/setup-new-machine.md` §3.

**06:55 — CODEX VERDICT ON THE ELEVEN: REJECT, 10 findings** (`docs/reviews/2026-09-15-deploy-gate-verdict.md`,
genuine: ANSWERED, digit detector 1). Disposition: **HIGH #1** (collection lost after settlement if the
re-mint fails — `settle-run` `CHARGE LOST` path) and **HIGH #2** (register-billing-key's compensation can
DELETE a key the swap stored; 0170's `unresolved` sweep deliberately unbuilt pending Toss U1/U2) are
STANDING defects behind `payments`/`card_registration` flags Sean holds — not introduced by this set,
but they must be closed before either flag flips (queue). **HIGH #3** (a runner can push fabricated
trace inside the 90 s drain) is the pre-existing provenance class — ingest never checked provenance;
0168 widens the post-tap window by ≤480 m; the real fix is a provenance slice (options in queue).
**HIGH #4** (frozen run unsettleable when `trackMode` is `unavailable`/null — a build without the
location module strands a payout) — client bug, FIX WAVE. **MEDIUM #5** register handler reads the
flag before the profile/tombstone check (party-before-state) — FIX WAVE (edge). **MEDIUM #6**
`_club_phone_visible` carries 0049's bare `custody_phase <> 'resolved'` on a nullable column — FIX
WAVE as 0171 (correct-forward). **MEDIUM #7** `trace_future_fix` has no client copy — FIX WAVE.
**MEDIUM #8** photo retries orphan storage objects (new `Date.now()` path per retry) — FIX WAVE (path
keyed on the client key). **LOW #9** closed-window roster replaces instead of retaining — FIX WAVE.
**LOW #10** `run_stopping` vs contract's `run_stop_pending` — recorded in 0169's header, handler maps
it safely; left. All 0159's 11 findings: 7 measured closed, 4 in excluded `geo.ts` (unverified by this
run, verified by the 08-31 UI rounds).

**07:2x — FIX WAVE LANDED, RE-ATTACK WALLED.** Client wave `6a03ab6` (findings 4 · 7 · 8 · 9: frozen
run settles without local GPS state; `trace_future_fix` gets the contract's clock copy; photo retry
re-uploads the SAME object keyed on the client key with upsert — 0064's policies admit it; closed-window
roster retained, one pin ×3 zones, npm 986/0) · server wave `44e2e9c` (0171 `is distinct from` in
`_club_phone_visible` — ⚠ the finding's premise measured FALSE: `custody_phase` is NOT NULL since 0040:47
under an always-writing trigger, so 0171 is hardening and its P1 manufactures an unreachable state, said
in both headers; register-billing-key reordered auth → tombstone → flag with the divergence-zone deno
test, 288/0; harness 1217/0). **The re-attack review hit the quota wall (try again at 11:41 AM) after 1.3 MB of
reading — the fix wave is UNREVIEWED; REJECT/10 stays the verdict of record with 6 fixed (unreviewed)
+ 4 dispositioned.** Pending on production is now TWELVE (0171 joins).

**08:3x — HIGH #2 half closed (`bf47df7`):** register-billing-key never calls Toss DELETE on a failed or
unknown swap any more — definite SQL refusal → ORDER the revocation through the 0138/0157 outbox;
unknown outcome → nothing but the named intent row; thrown RPC → intent closed then the error
re-thrown unchanged. deno **291/0** (+3), M1/M2/M3 plants reddening the right pins. Still open on #2:
the production ops roster being empty (recheck before the flag), and the `unresolved` sweep (Toss
U1/U2). HIGH #1 (0172 reconciliation sweep) in flight. Sim tapping: `idb-companion` needs Xcode 26 →
macOS upgrade, or Accessibility permission for AppleScript (queue item 3).

**09:0x — HIGH #1 REFUTED, measured on the real settle path:** `sweep_settled_without_payments()`
(0080:569, extended 0116:60; cron `sweep-settled-charges` every 5 min) already re-mints for a settled
booking with no payments row — after `end_run_tx → confirm_return_tx ×2` with 0 payments rows, one
sweep minted `pending | 18900 | settle_charge` equal to `compute_owner_charge()`, and a second added
nothing. The verdict's 「no sweep or owner retry can find it」 was true of the HANDLER (it returns
`lost`) and false of the SYSTEM. ⚠ The briefed predicate (`status='completed'` + ledger row) was the
WRONG anchor per 0116:47-52 (settled bookings move to incident_review/refund_pending; 0080 §K writes
ledger rows for CANCELLED bookings) — the agent stopped on the STOP condition instead of building a
mis-anchored sweep. What 0172 IS: both recovery cron jobs (`sweep-settled-charges`,
`dispatch-due-charges`) were installed under the swallowing `exception when others` form and NOTHING
pinned their registration — 0172 re-registers byte-identically + reads both back in VERIFY; suite 202,
3 pins incl. a control that reports absent. No new constant. Residual, out of scope and named: a settled
booking the sweep can never price (NULL end_reason/actual_km or a raising mint) is skipped with a
`raise notice` and invisible to ops — `payments_reconciliation()` has no `settled_without_payment`
arm (`_shared/ops.ts:95`); latent today. 0172 joins pending → THIRTEEN.

**12:04 — RE-ATTACK VERDICT: REJECT/2 on the fix wave** (`docs/reviews/2026-09-15-fixwave-reattack-verdict.md`,
genuine). Findings 4·5·6·7·8 CLOSED (6 as hardening — codex agrees the premise was false); HIGH #2
half-fix CLOSED as scoped; **HIGH #1 refutation ACCEPTED** (0116:73/121 + suite 151). Two remain, both
mine: **R1 MEDIUM** — finding 9's `packRetainRoster` ignores `sessionId` and the map never resets
roster/peers/camera on a sid change, so session A's people can render under a closed session B on route
reuse (a regression the fix introduced); **R2 MEDIUM** — the residual the 0172 agent named: a settled
booking the sweep cannot price is skipped with `raise notice` and `payments_reconciliation()` (0118:1392,
seven arms) has no `settled_without_payment` arm — silent revenue loss once payments open. Both in a
second fix wave now (client + 0173/203).

**12:34 — WAVE 2 LANDED (`e78f678` R1 roster fix, npm 989/0 · `f180d10` 0173 reconciliation arm, harness
1225/0, deno 292/0) and RE-REVIEWED: R1 CLOSED; R2 WRONG** (`docs/reviews/2026-09-15-fixwave2-reattack-verdict.md`)
— arms seven and eight of `payments_reconciliation()` both emit `payment_id = NULL`, and the group-by
invariant pinned by 116 C11 / 120 J4 groups all NULLs together, exactly as 0118:1382-1385 warned; the 0173
agent had named it 「green because disjoint in this fixture chain」. Fix as 0174 (correct-forward): the
invariant's grouping key becomes arm-aware (`coalesce(payment_id, booking_id)` per arm), 116/120 pins
updated in the same slice per the suite-update law. Pending on production: FOURTEEN → will be FIFTEEN.

**13:1x — 0174 LANDED (`3dcae46`):** `payments_reconciliation()` gains a ninth column `row_key`
(`payment_id::text` for arms one–six, `'booking:'||booking_id` for seven and eight — a SUBJECT key,
deliberately not arm-prefixed because that would defeat C11's duplicate detection; measured by plant ii);
the function is DROPPED and recreated (a `returns table` cannot widen in place — measured on a scratch
cluster, exactly as 0173's header ⑥ predicted), ACL restated; C11/J4 moved to group by `row_key`, same
assertion, same counts (chg 25, goc 10). Harness **1229/0** (+4), deno 292/0. ⚠ Recorded honestly: the
old C11/J4 could not see this defect and cannot demonstrate the fix (no fixture reaches two NULL rows at
their point in the chain) — suite 204 K1 manufactures the collision first, and plant iii proves the
re-keyed pins still catch a real duplicate. Re-review of 0174 running. Pending: FIFTEEN.

**13:02 — 0174 re-review: APPROVE, 0 findings** (`docs/reviews/2026-09-15-fixwave3-reattack-verdict.md`).
**The review chain on the pending set is CLOSED:** deploy-gate REJECT/10 → 6 fixed + 4 dispositioned →
re-attack REJECT/2 → both fixed → wave-2 REJECT/1 → fixed (0174) → APPROVE/0. Every actionable finding
has a reviewed fix on trunk. Still open by disposition, none of them code: HIGH #3 trace provenance
(Sean's option in the queue; 0168 widens a pre-existing class by ≤480 m), HIGH #2's production
recheck that the ops roster is non-empty (before the card flag), HIGH #1 refuted. The deploy of the
FIFTEEN is Sean's call — recommendation ⓐ deploy.

**Production is still 0156. Pending on trunk: FIFTEEN** — 0157 0158 0159 0160 0161 0162 0166 0167
0168 0169 0170. The 06:41 codex review (diff-scoped, sol high) writes its verdict into
`docs/reviews/2026-09-15-deploy-gate-verdict.md` and item 1 of `docs/decisions/awaiting-sean.md`.
**I did not deploy** (your call, and the harness classifier refused an unattended deploy job).

**Your queue, one line each (details in `docs/decisions/awaiting-sean.md`):** ① deploy — with the
verdict in hand, say 「deploy」 or 「hold 0168」 (money path, provisional 90 s/1 min constants) ·
② harness diet — say 「A」 (slim CLAUDE.md, 10 KB, ready) and/or 「B」; D measured at 2.6% of pins,
C withdrawn (19 s) · ③ Xcode 26 needs macOS 15.6+ — an OS upgrade, not an install · ④ labs: pick
numbers in `docs/labs/README-club-v2.md` · ⑤ Toss support ticket (memo §3) unblocks 0170's sweep ·
⑥ isHost split · phones #1/#4 · OPEN-C/F · km wallet, as before.

**Your four Codex sessions** (runner-rules 0163 · board-wrapper 0164 · membership 0165 ·
board-rejected-arm) had dirty worktrees and NO pushed branches all night; the heartbeat lands any
`codex/<slice>` branch the moment it appears. ⚠ 0165 redefines `club_session_roster`, which calls
0167's gated helper — read the gate back from the DB after both apply.

**Two misses of mine, both caught and recorded in `docs/codex-claude-protocol.md`:** 0169 landed
with trunk deno RED for ~40 min (the CONTRACT pin caught the unmapped raise; fixed at `34bd905`;
deno is now a landing gate for every migration) · a docs commit announced 0170 landed while its
trunk push had been rejected (read-back refuted it one command later; re-landed at `d04f74e`;
the landing chain is now `&&`-strict through the read-back).

---

## State, measured 2026-09-15 (new Mac `/Users/seankim/dev/daengrun`)

| | |
|---|---|
| Trunk | `069459b` — B1 (`b4bba36`+`9d874a2`, from rescue c105151) · 0157 (`ff6222d`, merge of rescue fba55f4) · 0158 (`df23718`, merge of rescue a5aa94a) · protocol docs (`069459b`) |
| SQL harness | **1229 / 0** at 0174's landing (1217 at 0171's (1213 at 0170's (1205 at 0169's (1201 at 0168's (1193 at `aa72341` (1188 at `bc7d59d` (1180 at `bb21ccd`, 1177 at `df23718`) — deltas 1135 → 1154 (+19, suites 191/192) → 1163 (+9, suite 188) → 1177 (+14, suite 189): each delta equals the pins added, so each suite demonstrably RAN |
| App tests | exit 0, **983 `^PASS` / 0 `^FAIL`** (+38 ✅ lines from run-geo) at `5bcc4dc`+ (980 at `df23718`); trunk before B1 was 822 |
| tsc · check-rpc-contracts · check-route-native-imports · check-definer-acl · check-device-clock | all exit 0 at `df23718` |
| Deno edge tests | **291 / 0** at bf47df7 (288 at the fix wave (287 at 0170 (277 at 0157 (`deno test --allow-all --node-modules-dir=auto _test` from `supabase/functions`) |
| Production | **MEASURED 02:00 KST after `supabase login`: 0156 deployed · pending 0157 0158 0159 0160 0161** (+0162 since `bb21ccd`) |
| Rescue branches | ⚠ corrected minutes after first push (I wrote 「all eight are ancestors」 — false): `merge-base --is-ancestor` says **4 MERGED** (0157-adopted · 0157-billing-hardening · 0158-adopted · 0158-settled-distance) · `wip-b1-pack-publish` is NOT an ancestor but its two commits landed by cherry-pick (`b4bba36`/`9d874a2`, same diff) · **3 hold UNLANDED work**: `routes-basemap-45de013` (4 ahead), `wip-main-clone-chat-slice-2026-08-28` (1 ahead — the inline-script fix, being adopted by P7), `wip-registry-row-ab47081-2026-08-28` (1 ahead, unexamined) |
| Toolchain | node 20 · pg16 · supabase CLI · cocoapods (needs `LANG=en_US.UTF-8`) · deno · bun · gh · gstack · codex 0.154 (bundled in ChatGPT.app + npm) · Xcode 16.2 + iOS 18.3.1 runtime · `app/ios` regenerated, pods installed |
| Still Sean-only | ~~eas login~~ ✅ · ~~supabase login~~ ✅ · **Xcode 26 install** (sim build) · the deploy go/no-go (see freeze note) |

**Harness lines the 09-15 merges fixed:** the rescue branches carried `suite 190_…` under its OLD
`# 0156` comment; a naive union registered 190 twice (double-counted pins). Deduped before landing;
`awk '/^suite /{print $2}' harness.sh | sort | uniq -d` is empty on trunk.

**Landed later the same night (02:xx KST):** P7 inline-script safety (`5bcc4dc`, codex astra low,
npm test 983/0) · **0162 chat client_key idempotency, both halves** (`bb21ccd`; client by codex astra
medium, server by Claude after codex hit a second quota wall; harness **1180/0**, +3 = suite 193;
mutation plant: index removed → K1 alone reddens 1179/1). Production re-measured after Sean's
`supabase login`: **0156 deployed, pending exactly 0157–0161** (0162 now joins the pending set).
`app/.env` pulled from EAS preview (needed `npm i -g eas-cli@latest`).

**Sean's Codex-app sessions in flight at write time (his worktrees, do not touch):**
`codex/runner-rules-checks` (0163/194) · `codex/board-wrapper-bundle` (0164/195) ·
`codex/membership-three-tier` (0165) · `codex/board-rejected-arm` (no number yet). They land via
Claude re-gating each `codex/<slice>` branch; expect REGISTRY.md + harness.sh unions on every one.

**SIMULATOR IS RUNNING (03:17 KST) — via EAS CLOUD, not local Xcode.** macOS 14.6.1 cannot run
Xcode 26, so the local route is dead until Sean upgrades macOS. The cloud route works: **the cause of
all four prior 「Configure expo-updates」 failures was `runtimeVersion: {policy: 'fingerprint'}`** —
switched to `appVersion` on branch `claude/eas-sim-build` (build `aee5b601` FINISHED; the empty
`expo-widgets` extension was also removed in that build — build 3 is isolating whether the widget
removal is needed at all; only the proven minimum lands on trunk). Installed on iPhone 16 Pro sim
(iOS 18.3.1, UDID `E5591637-…`), bundle id `com.seankookim.dogshigh`, login screen renders, the
Hermes bundle carries the Supabase host (`/usr/bin/grep -a`, 1 hit — this shell's `grep` is ugrep
and prints nothing for `-c` on a binary). **Signed out — Kakao login is Sean's; no smoke row past
the login screen until he signs in.** Recipe in memory + setup guide.

**Club-v2 labs landed (`b56ae34`, four files × 3 variants, Sean picks by number):** chat tiers ·
20-min hold · HOST setup (§16.7h — `club-v2-setup-lab.html` is the OWNER flow, different surface) ·
pack map counter. Index `docs/labs/README-club-v2.md`. Three findings the labs report upward:
① tier ② (signed-up READS) has no server today — `club chat read` admits host/full only and
`_club_shell_access` grades `full` on APPROVAL not payment, so an approved-unpaid owner can already
POST and a merely-signed-up one cannot read (0165, Sean's membership session, is the fix — verify it
narrows the write arm, which is a shipped right); ② 「access ends with the hold」 is unbuilt
(`_club_shell_access` never reads `hold_status`); ③ the seat frees at `hold_expires_at` while
`hold_status` stays `active` until the cron — screens must key on the timestamp. The viewer
counter's VALUE is unreadable by any client role (0160:436, RLS-on zero policies) — drawn as `—`.

**Simulator build BLOCKED on Xcode 26 (LOCAL route only):** Expo SDK 57's `expo-modules-jsi` declares
`swift-tools-version: 6.2`; Xcode 16.2 fails at package resolution. Sean-only (App Store).
Everything else for the build is in place (`ios/` regenerated, pods installed, iOS 18.3.1 runtime,
`.env`). Harness-diet proposal awaiting Sean's letters:
`docs/decisions/2026-09-15-harness-diet-proposal.md`.

**Landed 03:xx KST (Claude agents, no codex quota):** GPS finding-4 CONTRACT
(`docs/contracts/run-end-two-phase-stop-contract.md`, b1ee373 — buildable by astra next; §8 has four
Sean questions) · 185 suite repairs for codex 0154 #5/#6/#7 (`58166cc`, 1183/0) · **0166 revocation
findings** (`bc7d59d`, closes codex 0155 REJECT/6 — all six were still open on trunk, 0157 touched
neither dispatcher nor reporter; suite 196, harness **1188/0**, 8 plants each reddening one pin;
flag-gated, arms only when card registration goes live). **0168 two-phase stop LANDED (money path, codex GPS finding 4, from the contract):** the host tap stamps
`run_stopping_at` and freezes nothing; trace is accepted 90 s more (PROVISIONAL, Sean §8.1) then refused
by name (`run_stopping`); `club_finalize_stopped_runs()` (definer, service_role, pg_cron every minute)
derives km with an EXPLICIT cutoff = the tap and stamps `run_ended_at` = the tap; a derivation that
fails leaves the run `stopping` with NO ledger row (never a client-priced fallback). `_club_derive_run_km`
2-arg DROPPED, 3-arg replaces it (sole caller moved to the sweep; suite 187 updated). settle-run edge:
409 `run_stopping` after the party gate. Client: `runStopping` key on the board (runEnded untouched),
console 「기록을 모으는 중이에요 · 곧 확정돼요」, runner 정산 중 with settle disabled, late-upload banner
red 「업로드가 늦었어요」 not the amber retry. Harness **1201/0** (+8, incl. INACTION and control-pair
pins; M4 「refuse everything」 leaves P2 green), deno **281/0**, npm 983/0. ⚠ NOT codex-reviewed —
the 06:41 review scope includes it. ⚠ NAMED GAP: no SQL belt inside `settle_run_tx` — a direct
service_role caller can still settle a `stopping` booking at the client's numbers. Smoke rows (sim,
needs Sean signed in): host tap → console copy · runner 정산 중 · km appears after ~2 min · backgrounded
runner sees the red banner · owner's pack map stays up through the drain.

**0169 settle belt LANDED** — closes 0168's NAMED GAP: `settle_run_tx` refuses a `stopping` booking
(`raise exception 'run_stopping'` after the existence gate, before any write; base extracted from
0083's last definition, three-line diff). Harness **1205/0** (+4). ⚠ Flagged: contract §5 named this
token `run_stop_pending`; `run_stopping` is also what `club_save_run_trace` raises for the late-upload
event with different copy — the two never meet today (different function/endpoint; settle-run's own
409 fires first, and its RPC error map has no arm for either), but a future client arm must key on
the SETTLE path, not the token.

**0170 billing intent row LANDED** (Toss memo §4's branch-independent core, codex billing findings 3/4/6
local halves): `billing_issue_intents` — one row per issuance attempt, server-minted `Idempotency-Key`
persisted BEFORE Toss is called, states issuing → issued_persisted | issued_unpersisted | provider_error
| unresolved, no edge back to issuing; RLS-on zero client policies + explicit revokes; two definers
(open/close). register-billing-key handler: open → Toss with the persisted key → close(outcome) → swap;
a thrown Toss call closes `unresolved` and re-throws (no client-visible status changed). Harness
**1213/0** (+8), deno **287/0** (+6). PROVISIONAL per memo §3: replay_deadline 15 d (U1),
provider_error terminal (U6). The sweep that RESOLVES `unresolved` rows is NOT built (needs U1/U2 —
Sean's Toss ticket). ⚠ Also this hour: 0169 landed with trunk deno RED for ~40 min — settle-run's
CONTRACT pin caught the unmapped `run_stopping` raise; mapped at `34bd905`, deno is now a landing
gate for every migration (protocol updated).

**Pending on production is now ELEVEN (0170 joins):
0157 0158 0159 0160 0161 0162 0166 0167 0168 0169 0170 0171 0172 0173 0174** (0167 = codex 0154 #3 CRITICAL closed: `_club_phone_visible`
and `incident_contact` consult `phone_collection_live()`; `aa72341`, harness 1193/0, +5; four shipped
pins in 67/124/130 re-fixtured with the switch armed — ⚠ 0165 (Sean's session) redefines
`club_session_roster`, which calls this helper: after both land, read the gate back from the DB).** 0154 #1–#4 remain Sean's; 0154 stays a REJECT until then.
**Client honesty pass, wave 4 (Claude agent, non-club screens)** — 4 commits, 12 files, 15 fixes:
dead buttons removed (shop cart/search/담기, `pickEarliest` no-op, the iOS-only alert that fired on
iOS), loading-is-not-0 (schedule/calendar/community counters), fabricated data unbound (fixture
roster fallback in schedule, `62 + runs×5` 러닝 경험, 「신규」 for a never-written 응답률, 「0kg」),
`ensureRunner()` no longer swallowed on the entry path. npm 983/0, tsc 0. ⚠ **UNVERIFIED on the
simulator** (Xcode 26 blocker): shop header now title-only with non-interactive cards · the three
counters in loading/error states · matching sheet's 러닝 경험 bar for a 0-run runner · 반려견 추가 on
iOS must show exactly one dialog. Deliberately NOT changed (agent's table, worth reading):
`store.ts` dead fixtures (zero importers now — a follow-up delete), `login.tsx` naming legal docs
that do not exist (Sean's), the ~120 sub-15pt sites (director's call).

---

## State, measured 2026-08-31

| | |
|---|---|
| Production | **0156 deployed · pending: 0159 only** (`supabase migration list --linked`; 0157/0158 are REGISTRY rows with no files — invisible to migration list by construction) |
| Trunk | `d9d1451` — moved ~20 commits on 2026-08-31 alone (see Today) |
| App tests | **exit 0, 804 `^PASS` / 0 `^FAIL`** at `d9d1451` — ⚠ `grep -c '^PASS'` UNDERCOUNTS this chain: `run-geo-tests.sh` prints ✅ lines, not PASS lines (backend measured 801 PASS + 38 ✅ = 839 real on its tree). **Exit code + per-suite summaries are the reliable pair**; the PASS count is a floor, not the total |
| tsc | clean, exit 0 at `d9d1451` |
| Money | **OFF.** All three flags null (`payments` · `card_registration` · `phone_collection`), 0 billing keys, 0 revocation rows (measured `db query --linked`) |
| SQL harness | **1135 / 0 — PROVENANCE: b12b4a7's commit body (2026-08-28), NOT re-run 2026-08-31** (backend's B1 will move it; its tree reports 1150/0 unlanded) |
| Repo | **PUBLIC since 2026-08-31** (Sean, for free CI). Secrets sweep clean: only designed-public EXPO_PUBLIC values ever committed. CI (gates + React Doctor) green again on free minutes |

## Today, 2026-08-31 — the master-session day

Sean booted two master sessions off `docs/prompts/master-backend.md` / `master-ui.md`
(announcer-authored, inventory-grounded), coordinated by the announcer. Live sessions:
**announcer** · **master-ui-prompts-docs-6c8c89** · **daengrun-redesign-v4-77ea99 (backend)**.
Every other session named in older sections (b6, ui6, ui5, spec-v2, route-depth) is DEAD; their
claims were audited 2026-08-31 — see the REGISTRY audit note.

**Landed on trunk today (UI session, all codex-gated):** U5 focus-scheme ③ remainder
(`118c844`) · U2 pack-map doors (`1cccaea`) · U3 pay surface + red-line cap (`65fdab9`) ·
U4c host 러닝 종료 (`16c758b`) · U4b 백업 호스트 doors (`4f8ecb5`) · chat-rescue landing
(`2699935`) · runner 예약 규칙 editor (`1e5598b`) · codex wave-1 fixes (`bf0d387`, REJECT/5
all answered) · codex wave-2 fixes (`b8ce1c8`, REJECT/13 all answered,
ledger `docs/reviews/2026-08-31-codex-ui-wave2.md`) · floor rulings (`2ea34ec`). Codex round 3
(re-attack + U4b + rules editor) was running at write time.

**Sean's rulings today — all in `docs/decisions/2026-08-31-sean-rulings.md`, verbatim:**
club floor 15 everywhere (+ correction: the legacy sweep had already landed 08-27) ·
wire `club_end_pack_runs` (done, U4c) · avatar initials are glyphs · drop 不變 · leave ClubTag ·
OPEN-A 20-min hold · OPEN-B three-tier membership (public sees roster+pictures · signed-up
READS chat · paid participates — refined twice, read the file not a summary) · YES to the
pack-map viewer counter (folded into backend 0160/0161).

**Backend session (in flight, unlanded):** B1 pack-publish hardening — contract at
`docs/contracts/pack-publish-hardening-contract.md`, claims 0160/0161 + suites 191/192; design:
publishing moves to RPC `club_pack_publish` (per-publish gating, server-authored payload,
publisher channel removed). Measured on production: **PrivateOnly is enforced** — trunk's pack
map cannot connect until this deploys. B2 = adopt 0157/0158 from the rescue branches (takeover
annotated in REGISTRY). Then: S2.5 three-tier re-key · board rejected-arm widening (must incl.
dog-NAME visibility — dogs RLS has no host arm) · §16.7 pickup/return columns — those three
unblock the UI session's entire U1 fan-out. Announcer holds: 0153/0156 codex reviews + the Toss
provider memo (`docs/research/2026-08-31-toss-provider-memo.md` when landed).

**Standing sequencing (revised with B2 completion):** backend lands B1 → 0157 → 0158
sequentially (each re-gated post-rebase) → codex verdicts for all three off ONE frozen trunk
export → **ONE deploy of 0159+0160+0161+0157+0158** with production probes → freeze lifts at the
backend's announcement. Fallback if codex quota-walls mid-set: deploy the reviewed B1 set alone
and KEEP the freeze until 0157/0158 clear — either way the freeze lifts only when
trunk == production. Then:
UI removes the dead `clubName` param from `club/session/[sid].tsx` (~:1444) → hardware builds
allowed. The pocketed-phone pack-publish fade is a NAMED LIMITATION (smoke doc), not a bug; the
background-task publish fix is a queued backend slice. OPEN-C and OPEN-F stay unruled on Sean's
console. Smoke list: `docs/design/device-smoke-ui-master-2026-08-31.md` (10 ⬜ rows need
fixtures no read-only session can produce).

---

## 08-27/08-28 record below — superseded where it conflicts with the sections above

## State, measured (2026-08-27 — HISTORICAL)

| | |
|---|---|
| Production | **0152 — `migration list` pending: NONE.** Fully caught up for the first time. |
| SQL harness | **1081 pass / 0 fail** |
| App tests | **707 PASS / 0 FAIL** (counted across the whole chain, never `tail`) |
| Money | **OFF.** `payments_live_since` null · `card_registration_live_since` null · 0 billing keys · 0 revocation rows |
| Security sweep | 0 anon-executable definers · 0 definers missing in-body `search_path` |
| Stranded work | **NONE.** 0 unpushed commits; 9 spent agent branches, **9 of 9 confirmed duplicated on trunk by `patch-id`**. ⚠ The first version of this row said 「8 by patch-id, the 9th's file on trunk is a superset」 and **reported 9 clean having measured 8** — a superset proves the file MOVED ON, which happens for reasons unrelated to that branch. Corrected by b6; the 9th was then settled properly (`patch-id` match at `91c581e`). **Same conclusion, and the evidence for it did not exist when it was written.** |

## What went live today (0130 → 0152, three sessions)

A 동반 (self-run) walk becomes a real record · the host's one-tap 러닝 종료 ends every runner's
walk on **server-derived** distances · 1 dog per person enforced by a table trigger, not a hidden
button · the club board's names open profiles, and non-runners have profiles at all · 집 반환
directions · KST everywhere (a ticket no longer prints the wrong weekday on an off-Seoul phone) ·
~950 text-size fixes to the 15pt floor · Instagram-shaped profiles + editor · guests-come-free
said out loud on the club board · unknown distances stopped rendering as `0km` · billing-key
hardening incl. the crash window where a destroyed key could be stored as a live card.

## 🔴 OPEN — needs Sean, in priority order

1. **The lawyer email.** `docs/legal/counsel-email.md` — copy-paste ready, two attachments, a
   three-line pre-send checklist, referral line deliberately blank. **This gates phone
   collection, publishing the privacy policy and terms, the KCC filing, and launch.** Oldest
   open item; nothing else on this list is close.
2. **Device build — and ⚠ RETRACTION of what this line said an hour ago (ui6, 2026-08-27).**
   I wrote here that 「THERE IS NO BUILD, NOTHING HAS EVER REACHED A PHONE」. **That was wrong,
   Sean caught it in one sentence — 「look at the ios sim」 — and the original line it replaced
   was closer to right than my correction.**
   **What I measured:** `eas build:list` empty (**true** — no CLOUD build exists) and no installed
   app for `com.seankookim.dogshigh` (**true, and irrelevant**). **What I reported:** that no build
   exists at all. 🔴 **The installed simulator app is `com.seankookim.daengrun` — the OLD bundle
   id.** The config was renamed to `dogshigh`; the installed shell predates that. I searched for
   the current identifier, got nothing, and promoted it to a claim about the world.
   **The measured truth:**
   · A **simulator build exists**, made **2026-08-13**, bundle id `com.seankookim.daengrun`.
   · It is a **DEBUG** build → it carries **no embedded bundle** and loads JS from **Metro**.
   · Metro is live on `:8081` from a worktree — so **the simulator runs TODAY's client**, and
     today's UI work is visible on it right now (verified by screenshot: `시간만 고르기 ›` renders
     ink — this afternoon's dim-text fix — while `예정된 러닝이 없어요` stays grey, the one
     deliberately left alone).
   🔴 **THE REAL GAP, which is narrower and more useful than what I claimed:** a Debug shell
   carries only NATIVE code. **Any native change since 2026-08-13 is NOT in what anyone is
   looking at** — JS flows through Metro, native does not. And there is still **no artifact
   installable on a PHYSICAL device** and no EAS cloud build.
   ⚠ **Whoever reads the simulator must also read WHICH Metro** — `lsof -nP -iTCP:8081` then the
   pid's `cwd`. A Debug build binds to whatever Metro answers, so it can silently serve a peer
   session's tree, and the screen then shows someone else's work.
   **What was done toward it (ui6, 2026-08-27):**
   · `EXPO_PUBLIC_SUPABASE_URL` + `_ANON_KEY` pushed to the EAS `preview` environment — there
     were **zero** env vars configured, so no build could ever have reached Supabase. Uploaded
     with `eas env:push --path .env`, which reads the file itself (no value handled by hand).
   · a **`simulator`** profile added to `eas.json` — it needs **no Apple signing**, which is the
     only iOS artifact obtainable without an interactive Apple credential setup.
   · `.easignore` added: the archive was **289 MB against a 4.6 MB app** (`docs/` 171 MB +
     `supabase/` 87 MB, neither compiled into a client). ⚠ It is a **superset of `.gitignore`**,
     verified rule-by-rule, because EAS uses it *instead of* `.gitignore` — dropping one line
     would ship `.env` to the build servers.
   · the app **bundles clean**: `expo export` produces a 7.3 MB Hermes bundle, exit 0.
   🔴 **STILL BLOCKED, three attempts, all identical:** every iOS build fails at the
   **`Configure expo-updates` build phase** with `UNKNOWN_ERROR`. ⚠ Ruled out: missing env
   (attempt 2 had it), archive size (attempt 3 was small), and local config — `expo config
   --type introspect` resolves fine, exit 0. **Prime suspect: the `ExpoWidgetsTarget` app
   extension**, which introspection shows carries `widgets: []` — an app extension with no
   widgets, configured alongside expo-updates. **The phase log is on the build page and the CLI
   cannot print it** (`api.expo.dev/.../logs` → 404 unauthenticated); someone with dashboard
   access should read it first — do not spend a fourth build guessing.
   ⚠ **And signed iOS builds are Sean-only regardless:** both `preview` and `testflight` fail at
   credential setup demanding interactive mode (Apple Developer sign-in). Android is not an
   escape — `android.package` is unset, so this app is iOS-only in practice.
   **When a build finally exists, `docs/design/device-smoke-ui6-2026-08-27.md`** is 33 honestly-⬜
   rows; its first section needs the phone's timezone **off Korea** before any row means anything.
   **The old text follows, still true of the code itself:** none of it is
   simulator- or device-verified. ~950 type-size changes and five screens of colour/copy work
   look fine in a diff and wrap badly on hardware. `docs/design/device-smoke-ui6-2026-08-27.md`
   is 33 honestly-⬜ rows; its first section needs the phone's timezone **off Korea** before any
   row means anything.
3. **Guest GPS → now a three-way question: `docs/decisions/guest-gps-options.md`** (landed
   2026-08-27). Every citation above verified at source, but **the framing here was wrong three
   ways and the third one is the decision.** (a) It is a **pack gap, not a guest gap** — there is
   no map of the group anywhere in the product; a 동반 owner *with* a dog is equally invisible
   (`club/companion/[sid].tsx:7,141` imports `startTracking` and publishes nothing), and the host
   sees nobody. So 「the same gps share service」 **has no referent yet**. (b) 「half a ruling
   unbuilt」 overstates it: `2026-08-25-console-rulings.md:1302-1306`, same document and same day
   as the ruling, records that **direction-of-sharing and who-may-see-whom were explicitly left
   open**. Nothing is owed; the question was never asked. (c) The constraint that decides it was
   omitted — `privacy-policy.md:91` promises 「해당 예약의 보호자에게만 … 다른 이용자나 제3자에게
   제공하지 않습니다」, and **every watch-the-pack option rewrites that sentence on a document
   currently in front of counsel** (item 1).
   ⚠ **New and not previously written down: session membership is self-serve.** `session_rsvp`
   has no club-membership and no host-approval gate (`0134:53-61`), `club_sessions` is
   `select using (true)` (`0030:133`). So 「a member of this session」 means 「anyone who found an
   open session and tapped join」 — which in code looks exactly like a membership check.
   Option ①（record, no map）needs one predicate and changes no privacy promise; ②/③ need counsel
   first. **All READ, no production query.**
4. **Card revocation → `docs/decisions/card-revocation-abandoned.md`** (landed 2026-08-27,
   **measured against production, not read**). Handoff confirmed on deployed `prosrc`: the
   8-attempt cap is real in both `claim_` and `report_`, and `enqueue_billing_key_revocation(…,
   'account_deleted')` precedes the local row delete at `0115:535`. OBSERVED live: **0 keys,
   0 revocation rows, 0 abandoned**, both money flags NULL, `revoke-billing-keys` ACTIVE v2 with
   its cron live and **11 ticks all `idle`** — so the `X-Cron-Key` handshake **has never actually
   run in production**, and the first real revocation is also its first live test.
   🔴 **The handoff's most valuable error: 「nothing reads it」 is *nearly* true, and the near-miss
   is worse than the claim.** There IS a reader — the view `billing_key_dispatch_health`, whose
   `due_now` (`0150:413-415`) counts `pending` + expired-lease `processing` and **structurally
   excludes `abandoned`** (verified: the deployed viewdef does not contain the string). So the one
   dashboard-shaped object in this family **reports the queue clean precisely because rows were
   given up on.** Also: 「someone who asked to be gone」 covers **2 of the 5 reasons**; `failed` is
   dead vocabulary written by nothing; and **there is no card-removal affordance in the client at
   all** — 「remove my card」 *is* 「delete my account」.
5. 🔴 **NEW (announcer, 2026-08-27, verified against production myself) — the host sees every
   member's phone number, and it arms the same instant phone collection does, with nothing in
   between.** Deployed `_club_phone_visible` (read from `pg_proc`, not from a migration file) is
   bidirectional host ↔ **everyone** for any session in `open`/`full`. A person-only guest is on
   that roster. **Not breached today and not close:** OBSERVED `profiles where phone is not null`
   = **0**, and `set_my_phone` has **0 client callers** (0133 landed the server deliberately
   without a collection point). ⚠ **But `ops_flags` has no phone column** — card registration has
   a switch and phone collection does not. So there is no way to turn phone collection on
   *without* turning host-sees-everyone on in the same commit. That makes it a decision that has
   to be made **before** the wiring, not after — and it lands in the same envelope as item 1,
   which is what unblocks phone collection in the first place. Related and still open from
   2026-08-26: whether a dogless guest counts as a 「member」 for this rule at all.
6. **`net` schema grant — needs Supabase, not us.** `anon` holds `USAGE` on `net` and `SELECT` on
   `net._http_response` and `net.http_request_queue` (whose headers carry `X-Cron-Key` and an
   `Authorization` bearer). **Structurally out of reach:** `net` is owned by `supabase_admin`,
   migrations run as `postgres` (not superuser, not a member), and REVOKE only removes grants
   issued by the current role — 0151 aborted itself proving this rather than claiming success.
   **Not reachable from outside:** PostgREST exposes only `public, graphql_public`; the anon key
   gets `406 PGRST106` on `net` and `200` on `public.clubs` (control run). **Defence in depth, no
   known reach.** A support request, not a blocker.

## ui6 lane — state at handoff (2026-08-27)

**Deployed and verified against production, not inferred:** 0131→0152, all 22. `migration list`
pending **NONE**. Anon-executable definers **0**, definers missing in-body `search_path` **0**,
`payments_live_since` and `card_registration_live_since` both **null** — no money moves. Edge:
`register-billing-key` v2, `revoke-billing-keys` v1 (first ever deploy, `verify_jwt=false` from
the committed `config.toml`).

🔴 **The money defect is closed ON THE LIVE ROW, not a fixture.** Production booking
`4f053152-…` — `actual_km` NULL, `incident_review` — now answers `basis=incident_unmeasured`,
`measured_km` NULL, `runner_gross` NULL. **An hour earlier that same row quoted 「실측 0km」 and
multiplied the runner's distance and addon fare by that zero.** Found by the announcer on the
screen; escalated here after measuring `0121:296`, where the ratio is *spent*.

**Dim-text wave 3 LANDED** (`69a926a`) — 48 sites read, **10 inked**, 707/0. Ratio ~21%, which
matches owner/home's 2-of-8 and is the third independent confirmation that this is a judgment
pass and not a sweep. ⚠ **`club/receipt` came back 0 of 10 and that is the finding**: its dim
styles are `club-ui`'s shared `bignumLabel`/`LoadGate` recipes byte-for-byte, and `theme.ts:80-86`
already records `L.dim` at **4.24:1 — under the body floor — as an open item reserved for Sean**.
Inking them per-site would be the first half of a product-wide repaint, made by an implementer.
**Left at the wall, deliberately.**

**사고 신고 (incident) client flow LANDED** (`de902e6`) — the biggest missing surface, closed.
New `app/app/incident/[bid].tsx`, `safety.tsx`'s 「준비 중」 card replaced by a real resolver, and
push routing for both roles. 707/0, route count 61→62, rpc calls 116→118 (**both deltas are
positive controls — the checkers demonstrably saw the new code rather than passing by not
looking**).

⚠ **It found that `0114` SUPERSEDES `0094` for the opener, and reading only 0094 would have
shipped a wrong client.** The reportable set (0114 §3 ⑥) is the accepted set **plus
`cancelled_owner` and `refund_pending`**, while `is_booking_party_active` — which gates chat AND
**`notifications` insert** — is the accepted set only. **So in exactly two states a party may
REPORT and may not be NOTIFIED.** Collapsing them ships a control that 42501s in the state 0114
widened the report set to protect.

⚠ **`incident_contact` was deliberately NOT built.** Its privacy prerequisite is met
(`privacy-policy.md:45-46`), but it returns `profiles.phone`, and `0133_phone_collection`
**landed the server and left the collection point unwired** on its own ship gate — measured **0
of 10** rows populated. It would return two blank rows. It stays unbuilt until the lawyer item
(OPEN #1) clears, which is the same gate.
⚠ **The runner sees 「보호자」, not a name** — no `profiles` SELECT policy admits 「the owner of my
booking」 (0002:55-58; 0145's arm is club-board-only). The only route to that name is the definer
that also hands over a phone number.

### What a next session should not re-learn

- ⚠ **`club_join` / `club_leave` are built and unreachable** — membership only happens as a side
  effect of committing to a session. Seven more granted-to-`authenticated` RPCs have no caller:
  `open_incident_tx` · `verify_incident_tx` · `incident_contact` · `session_set_backup` ·
  `club_assume_host` · `session_reconsider_dog` · `km_claim_welcome` · `runner_work_gate` ·
  `set_my_phone`. **That list is the honest map of missing UI**, derived from grants, not memory.
- ⚠ **Dim-text: the counts in circulation were wrong twice and both were mine.** 412 counted a
  colour token appearing anywhere — `placeholderTextColor` (which MUST be dim), dots, borders.
  Honest upper bound ~203 *text* styles. **Measured violation ratio on owner/home: 2 of 8.** The
  real count cannot be produced by grep, because the question is 「may the customer skip this?」.
  **An agent handed the 412 would have turned 29 placeholders ink and made every form look
  pre-filled.**
- ⚠ **`0151` was EDITED IN PLACE after landing on trunk**, against the correct-forward law. The
  exception was narrow and is stated in its header: its abort made every later migration
  unreachable, and `migration list` proved no environment held the old version. **If you meet a
  landed migration that cannot apply, that is the test to run — not the law to ignore.**

## Lanes

- **announcer** (this session) — coordination, Sean's queue, server/security. Nothing in flight.
- **b6** — club session/console/run screens, client honesty. Holds `club/session/[sid].tsx`,
  `club/console/[sid].tsx`, `club/run/[sid].tsx`, `club/receipt/[bid].tsx`,
  `src/components/run-share-card.tsx`, `app/shot/[bid].tsx`, and — added after this file's first
  version — `src/lib/rpc-skew.ts` + `test/rpc-skew.test.cjs`, `src/lib/tier.ts` +
  `test/tier.test.cjs`. ⚠ **Those four are small pure modules with MUTATION-VERIFIED pins:
  anyone editing them must re-run the batteries, not just the suite.** A green suite after a
  predicate edit means very little on its own — that is what the batteries are for.
  **Open for b6: only the guest counterpart on the session screen.** ⚠ **CORRECTED AGAIN — this
  file said 「waiting on the verified findings already sent」 and they had NOT been sent.** The
  announcer promised them twice, told Sean they were sent, and recorded that in this file.
  They were delivered 2026-08-27 after b6 pointed it out. **「Waiting on findings sent」 and
  「waiting on findings not sent」 are different states for whoever picks this up**, which is the
  whole reason it is worth a correction rather than a quiet fix.
  🔴 **And the fifth question — 「does a guest change what the HOST sees」 — was never answered
  by the agent**, which answered a different fifth of its own. Measured against the DEPLOYED
  0131 policy instead: **YES, the guest is visible to the host.** `session_people`'s policy is
  `(auth.uid() IS NOT NULL) AND ((profile_id = auth.uid()) OR _club_session_member(session_id,
  auth.uid()))`, and the deployed helper carries host and backup-host arms — so a host is a
  member and a member reads every `session_people` row in the session, dogless or not. ⚠ This
  only became answerable AFTER the deploy; pre-0131 the table was `auth.uid() IS NOT NULL` and
  the question was meaningless. Everything else b6 built is on trunk.
  ⚠ **CORRECTED — this file's first version said b6's two `PENDING_DEPLOY` entries 「can come
  out」 and the run-screen obligations were 「still open」. Both were already DONE** (`2b5d1c1`,
  `0714ac8`); b6 landed them while this was being written. Measured on origin: PENDING_DEPLOY
  executable mentions **0**, `runEnded` executable gates **3**, rpc-skew pin **10/0**.
  🔴 **The reason this was worth correcting rather than shrugging at:** a handoff saying a pin
  「should be failing until you do it」 sends the next session to run it, watch it PASS, and
  reasonably conclude **the pin is broken**. That is a false green manufactured by
  DOCUMENTATION — the same shape we spent two days removing from code, arriving through a file
  nobody thinks to distrust.
- **ui6** — design system, board, payments, deploy trigger. Holds `owner/request.tsx` and the
  press-grammar sweep.
- **Claim before you edit**, in REGISTRY's in-flight table, path-keyed. **Migration numbers are
  THREE-sided**: REGISTRY row · every remote branch · **local worktree branches** (`git branch -a`
  — `ls-remote` cannot see an unpushed agent worktree, and that is now the likeliest collision
  surface). Re-read at COMMIT time, not only at claim time.

## Two things that will bite the next session

- **Committing a hook does not install it.** `core.hooksPath` is the MAIN CLONE's
  `/Users/sean/dev/daengrun/.githooks`; a worktree's copy is a different file. After committing
  the pre-push fix, the repo had it and the machine did not. **Verify the live file.**
- **This shell wraps `grep` in a function that execs `ugrep`.** A hook runs under `sh` and gets
  `/usr/bin/grep`. Two sessions each spent an hour "verifying a hook's own pattern" through the
  wrapped grep — four checks that varied the input and held the tool fixed, which was the axis
  that mattered. **Use `/usr/bin/grep` explicitly when testing anything a hook runs.**
- ⚠ **The pre-push hook falsely refused two pushes** ("migration NNNN has no REGISTRY.md row")
  on pushes whose row WAS present. **Neither session found the cause and the state is gone.** It
  now prints its evidence on refusal — sha, byte length, rows it can see, the rows nearest the
  one it wants — so the next occurrence is self-describing. Two-sided tested with the evidence
  path exercised on a real refusal, and the ORIGINAL hook returns identical verdicts on both
  arms, so behaviour did not move.

## ui6 session 2026-08-28 — what landed, and two corrections to the brief

**① The card/billing chain now has a codex verdict: REJECT, 7 findings** (5 HIGH, 2 MEDIUM) —
`docs/reviews/2026-08-28-codex-billing-chain.md`, with the prompt archived beside it. First review
that chain has ever had. Nothing fires today (both money flags NULL, 0 keys), but **two HIGH
findings arm on `card_registration_live_since` ALONE** — charging does not have to be on — and both
put a real card in a wrong state.
🔴 **The one thing to act on: findings 3 and 4 both bottom out in a single unanswered PROVIDER
question — can Toss replay or look up a billing-key issuance by a persisted idempotency key, and
what does a repeated DELETE return?** The fix shape for both is unknown until that is answered, so
**it is now on the critical path to turning card registration on**, and it is a question for Toss's
documentation or support, not something to design around by guessing. Nobody owns it yet.
Closed 3 of codex's 5 open questions against production (all reads): the revocation cron **exists
and runs** (jobid 23, 110/110 succeeded, latest 00:48Z — which narrows finding 5 from breached to
latent); base-table ACLs are sealed but **asymmetrically**, a finding codex could not see from
source — `billing_key_revocations` revoked its client grants AND has RLS, `billing_keys` has **only**
RLS while carrying `anon`/`authenticated` SELECT **and INSERT**; and `net.http_request_queue` was
already settled on 2026-08-27.

**② `club_join` / `club_leave` BUILT and landed** (`297139a`). The sharpest of the eight, and the
gap was total: measured on production, exactly three deployed functions insert into `club_members`
— `club_claim_host`, `club_join` (unreachable), `session_runner_commit` — and **`session_rsvp` does
not**, because 0048's R4 abolished auto-join and left the invitation to 「UI/알림 몫」. So an owner
had **no path to membership by any route that existed**. Live data: 1 club, 14 sessions, 1 distinct
participant, `club_members` = 1 row (role=host). `club_overview` has been returning `isMember` the
whole time and the client read it in **exactly one place — the type declaration.**
🔴 **Server defect found while scouting, still open and unowned:** `club_overview.isHost` reads
`clubs.host_profile_id`; `club_demand_board.isHost` reads `club_members.role='host'`. Two deployed
definitions of one word, agreeing only because `club_claim_host` writes both. `club_leave` deletes
just the member row, so a host who leaves splits them. **The client ships with no leave affordance
for a host, so it cannot reach that state** — but the fix (refuse a host, or clear
`clubs.host_profile_id`) is a product call.

### ⚠ Two of the eight are NOT what the list says, and both were measured

The 「eight capabilities the server has and no screen offers」 list is derived from grants, which is
the right method, but a grant with no caller does not by itself mean a missing capability.

- 🔴 **`km_claim_welcome` is NOT a client-only slice — do not build the button.** The RPC is
  server-complete, but **the entire km subsystem has zero client callers**: `km_balance`,
  `km_purchase`, `km_reserve`, `km_settle` — all of them, 0. There is no km wallet anywhere in the
  app. km is wired into `_resolve_checkin` server-side, so granting the welcome 5km would hand
  someone an **invisible asset worth ~₩16,700 in runner pay** that they cannot see, spend, or
  understand. That is a worse defect than the gap. Building it honestly means building the wallet
  surface first, and deciding whether the km prepaid model is the intended one at all — money-shaped,
  with a 500-account cohort cap and ~₩8.4M exposure written into the function. **Sean's call, not an
  implementer's.**
- ⚠ **`runner_work_gate` is already delivered — the capability is not missing.** It has no client
  caller because it does not need one: `transition-booking/index.ts:77` calls it and returns
  **`waiting_on`-differentiated Korean copy** on a 409, so a gated runner is already told exactly
  why and what unblocks it. A direct client call would be pre-emptive polish (tell them before they
  tap, not after), which is real but is not a missing capability. ⚠ I nearly reported this one as
  「the gate is unenforced」 off a SQL-only search that found no caller — the enforcement is in
  TypeScript. **The measurement licensed 「no deployed SQL function references it」, not 「it is
  unenforced」**; caught before it was written down.

**`club_assume_host` and `session_set_backup` were deliberately NOT taken** — they belong on
`club/session/[sid].tsx` and `club/console/[sid].tsx`, which b6 holds exclusively. Flagged, not
built.

⚠ **Nothing in this session is simulator- or device-verified, and that was a choice.** Metro on
`:8081` serves `daengrun-redesign-v4-77ea99/app` — **a peer session's worktree** — so the simulator
cannot show this work, and repointing the shared simulator would have taken it away from that
session. The club membership card is unverified on a device. App tests are **707/0 UNCHANGED**,
which is honest rather than reassuring: `app/test/*.cjs` structurally cannot import a `.tsx` route
module, so the suite says nothing about this screen either way. Gates that DID move:
`check-rpc-contracts` 118 → **120**, exactly the two new calls — a positive control that the
checker saw the code rather than passing by not looking.

## ✅ CLOSED 2026-08-28 — the live board disclosure (was: needs one line). `0153` DEPLOYED

`0147` grants `authenticated` direct EXECUTE on the INNER board function, and that function
**trusts a caller-supplied access grade instead of deriving it**. Found cold by codex; then
**reproduced against production**, which is the pairing this file's laws prescribe.

Measured: `_club_delegation_board_impl(p_session uuid, p_access text)` is `prosecdef`,
`has_function_privilege('authenticated', …, 'EXECUTE')` = **TRUE**, the body references `p_access`
and — comment-stripped — **never references `_club_shell_access`**. The outer
`club_delegation_board` derives the grade correctly; nothing makes a caller use it. It lives in
`public`, which PostgREST **does** expose — so unlike the `net` grant (OPEN #6), the allowlist is
not standing in front of this one.

Executed as role `authenticated` with **no party relationship** to the session, on a session that
actually has content: `p_access='host'` returns **1 dog / 2,185 B**, `p_access='none'` returns
**0 dogs / 663 B**. Different digests. The forged grade hands over `ownerName`, `runnerName`,
`proposedRunnerName`, `custodianProfileId`, `runnerId`, `bookingStatus`, `chargeState`,
`refundState`, `payoutState`, `payoutHoldReason`, `openIncidentId`, `dogName`, `collar` — **names,
re-identifying profile IDs, money state and incident references for a stranger's session.**

**Fix is one line:** `revoke execute on function _club_delegation_board_impl(uuid, text) from
authenticated;`

✅ **DONE — `0153_board_impl_not_for_clients.sql`, deployed and verified TWO-SIDED on production.**
Live catalog after: `authenticated` EXECUTE on the impl **false** · `anon` false · `service_role`
**true** · outer `club_delegation_board` still **true**. 🔴 **The exploit, re-run verbatim, now
returns `42501: permission denied`** where an hour earlier it returned 1 dog / 2,185 B; the control
confirms the legitimate door still opens. Harness **1086/0** (+5 = exactly the pins added — the
positive control that suite 184 RAN rather than being skipped from the manifest). Mutation battery,
4 arms, each `&&`-chained to its plant so an unlanded plant yields no row: revoke removed →
**APPLY ABORTS**; revoke removed + VERIFY removed → **B1 red alone**; over-reach (service_role also
revoked) → **B3 red alone**; control → **1086/0 clean**. B1 is blind to over-reach and B3 to
under-revoke, so they are two genuine controls, not one printed twice.
⚠ **B2 (anon) does NOT redden under the plant, and that is honest rather than a gap** — `anon` was
already revoked by `0147:189`, so B2 pins a property 0147 holds, not one 0153 establishes.
⚠ **NO CODEX PASS. codex was quota-walled until 14:33. This slice is NOT reviewed and nobody may
say it is.** It is owed one.

⚠ **My first attempt at this proof measured NOTHING and read as reassuring** — run against the
first session id in the table, both grades returned identical digests, because that session has 0
dogs and 0 runners. An empty fixture discloses nothing regardless of grade. Same trap as
`billing_keys`. **Find a fixture with content before believing a negative.**
⚠ Rung honesty: the DB-level call is OBSERVED; the same call over PostgREST with a real user JWT is
NOT — that rung is a read, not a measurement.

## Also new 2026-08-28 — the run-end money chain is REJECT, 12 findings

`docs/reviews/2026-08-28-codex-runend-money.md`. Beyond the disclosure above:
- 🔴 **CRITICAL: a runner can mint arbitrarily inflated earnings** with a future-timestamped GPS
  trace. Ingest rejects neither future timestamps nor trace duration; the only bound is 100 km. It
  moves the ledger and runner earnings **today** — no flag involved.
- **`club_end_pack_runs` has ZERO client callers** (verified independently: no executable reference
  anywhere in `app/`). The whole 0144 freeze is not in the settlement path; runs settle from the
  runner's own button, so **the runner's client values price the ledger**. Whether to wire it or
  retire it is Sean's call, and two other findings fall out of that answer.
- **0152 is incomplete**: weekly, fitness and leaderboard aggregates still coalesce unknown distance
  to zero. ✅ Codex's open question answered on production — `completed` bookings with NULL
  `actual_km` = **0 of 8**, so this is schema-reachable but **not observable today**. ⚠ One
  transition away: 1 of 9 runs has NULL km AND NULL duration (the `incident` run sitting in
  `incident_review`).

## 2026-08-28 — a third capability that is NOT a client-only slice, and a live product dead end

`session_reconsider_dog` was scouted and **deliberately not built.** The contract was read from
deployed `pg_proc`: host-only (`not_host` party gate), requires `approval='rejected'`, session
`open`/`full` and not past, and returns a NEW pending `session_dogs` row (the rejected row is never
mutated).

🔴 **The blocker is that the only party allowed to call it cannot SEE the rows it operates on.**
`_club_delegation_board_impl` admits rejected rows only through an **owner-only** arm
(`d.owner_profile_id = auth.uid() and d.approval in ('rejected','withdrawn')`), and
`club_session_board` excludes them for everyone. **Measured with a discriminating control** on the
production session holding the one real rejected dog, at the maximum grade: `auth.uid()` = the dog's
owner → **1 dog**; `auth.uid()` = a different profile → **0 dogs**. ⚠ That session's host IS its
owner, so the naive read proves nothing — the non-owner arm is the measurement that decides it.

🔴 **AND THE PRODUCT HAS A LIVE DEAD END THAT THIS RPC EXISTS TO CLOSE.** Deployed
`session_delegate_dog` refuses re-application after a `host_rejected` attempt, and
`club/delegate/[sid].tsx:104` renders that as **「이 세션에서 거절된 신청이 있어요 — 호스트에게
문의해주세요」**, while `club/session/[sid].tsx:1116-1119` deliberately draws no re-apply door
because the remedy is the host's. **The host's remedy is unbuilt.** The app tells an owner to go ask
the host, and the host has no button — **a mis-tap on 거절 is permanent for that dog in that
session.**

**It belongs on `club/console/[sid].tsx`** (b6's, exclusive) — beside the existing `pending` /
`review` filters, as one sibling section. Flagged, not taken. Whoever owns the console needs: a
rejected-rows source (a host CAN read them by direct table select today — `authenticated` holds
SELECT and `_club_session_member`'s arm ⓐ is the host; the cleaner fix is widening the board's
rejected arm, which is a server slice), an error map for `not_rejected`/`session_closed`/`not_host`/
`not_found`, and copy that promises only 심사 대기 — **not** a seat, since `session_approve_dog` can
still fail `no_capacity`.

⚠ **Two more facts worth carrying.** (a) `club_flags.club_delegation_v2` is **`enabled: false`** on
production, so this RPC and the whole v2 surface raise `feature_disabled` for anyone outside
`club_test_accounts` — whether that is intentional-for-now or a stale flag is a product question
nobody has answered. (b) The RPC is **not idempotent**: it never clears the old row's `rejected`, so
a second call passes all five gates and inserts a second active `(session_id, dog_id)`, violating
`session_dogs_active_uni` with a raw `23505` no error map would translate. ⚠ Deductive from two
observed facts, **not executed** — no write was made to production.

**Running total: three of the eight 「server-complete, client-only」 capabilities are not that.**
`km_claim_welcome` (no km wallet exists at all), `runner_work_gate` (already delivered via the edge
function's 409), and now `session_reconsider_dog` (the caller cannot see its own rows). The list was
derived from grants, which is the right method — but **a grant with no caller is not by itself a
missing capability**, and that distinction has now cost three scouts to learn.

## ✅ 2026-08-28 — the CRITICAL GPS fraud vector is CLOSED on production (`0156`)

A runner supplied every coordinate **and every timestamp**; ingest checked only monotonicity and
≤8 m/s, and derivation had **no upper bound at all**. A plausible slow trace dated hours ahead froze
99 km into a 5 km booking and the payout path wrote it to `ledger_items`. **No flag gated it.**

**Proven on production after deploy, read-only, with two controls:** the attack (two real fixes plus
a DENSE fabricated tail an hour ahead) derives **0.10 km** — identical to the honest trace with no
tail (**0.10**), so the forged tail contributes nothing — and a densely-sampled stationary dog still
derives **0.00**, so the fix did not over-reach into refusing honest zeroes.

**The shape worth knowing:** `_club_derive_run_km` is `stable` and is called from exactly one place,
inside the freeze transaction — so `now()` there IS the host's tap. Bounding on it gave the
reviewer's `started_at <= t <= v_at` with **no signature change and no 225-line recreation**.
A 60 s tap grace is deliberate: a fix a second after the tap is jitter, and a strict bound would
silently UNDER-pay the runner, which is the same class of error pointed the other way.

⚠ **This does NOT close finding 4.** Points arriving after the tap are no longer counted, but the
stale-trace race still needs a two-phase stop. Do not read 0156 as closing it.
⚠ **The 300 s coverage threshold is PROVISIONAL and is Sean's call** — codex's own open question is
「what maximum gap and minimum coverage define a measured run, including a genuinely stationary
dog?」 and nobody has answered it. It is one named constant.
⚠ **NO CODEX PASS** — quota-walled until 14:33. 0153 and 0156 are both owed one and neither is
reviewed.

⚠ **Suite 176 was repaired in the same slice**, per the standing rule. Its over-band fixture
(999 × 111 m ≈ 110.89 km) only ever fit because its generated timestamps ran **≈3.7 hours into the
future** — at the 8 m/s ingest ceiling that distance cannot happen in 30 minutes. `dF` is re-dated
five hours back; it is BLOCKED and freezes no km or duration, so no other pin reads its timing.

⚠ **I also deployed 0154 and 0155, which are another session's**, because `db push` has no per-file
selection and 0156 was a live money bug. **Verified safe before deploying, not assumed:** 0154 ships
`phone_collection_live_since` **NULL** (it adds the switch, it does not flip it) and I confirmed
`phone_still_off = true` on production afterwards; 0155 arms only when card registration goes live
(0 keys, 0 revocation rows). ⚠ **0155's REGISTRY row still reads 「NOT DEPLOYED, NOT PUSHED」 and is
now stale twice over** — its owner should correct it.

## Unreviewed

~14 of the 21 deployed migrations carry **no codex verdict**, and 0131's seven review rounds
cover **0131 alone, not the stack**. Sean was told this before authorising and chose to proceed.
Worth a sweep when there is quota to spend.
