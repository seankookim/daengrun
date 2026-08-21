# HANDOFF — client domain (`app/`), written 2026-08-21 midday

**Read with this, in order:** `docs/plans/2026-08-20-client-gap-straightening.md` (the 60-item
inventory + ENDING STATE + Q7–Q10) · `docs/decisions/awaiting-sean.md` · `DESIGN.md` (tokens, laws) ·
`CLAUDE.md` (permanent laws — **§Process was corrected this session, see §6**) ·
`docs/labs/RULINGS-2026-08-19-journey.md` (his verbatim rulings) · `docs/session-handoff.md`
(fleet-wide, announcer-owned — **do not edit**) · `~/.claude/skills/inherited-claims/SKILL.md`
(written this session; its §4 is about this session's own biggest mistake).

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/` (reading it to
verify a claim is fine and was necessary this session — see §6).
This file **replaces** the 2026-08-21-morning version; git history is the archive.

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Trunk | `redesign-v4` @ **`c7dac14`**; my 9 commits all landed, branch `claude/client-redesign-v4-work-3e224f` 0 ahead / 0 behind | **[verified-now]** |
| MAIN CHECKOUT `/Users/sean/dev/daengrun` | clean, **still 3+ behind origin** — I deliberately never fast-forwarded it (§5) | **[verified-now]** |
| `tsc --noEmit` | clean | **[verified-now]** |
| `check-rpc-contracts.mjs` | ✅ 95 calls / 165 signatures | **[verified-now]** |
| `check-route-native-imports.mjs` | ✅ 57 routes | **[verified-now]** |
| `check-embed-fk.mjs` | ✅ 1 pair · 109 files | **[verified-now]** |
| `npm run lint --quiet` | **270 problems, 6 errors** = baseline. I broke it to 7 once and fixed it (§6) | **[verified-now]** |
| iOS simulator | 🔴 **App now RUNS on the sim from a worktree** — first time this session. Parked at role-select, see §4 | **[verified-now]** |
| Hardware | 🔴 **still nothing, ever.** Everything below is code + gates + one simulator boot | **[verified-now]** |
| Installed sim bundle id | **`com.seankookim.daengrun`** — the OLD id. The rename to `dogshigh` is config-only (§4) | **[verified-now]** |

---

## 2. What shipped (9 commits, all on trunk, all five gates green each)

| Commit | What |
|---|---|
| `5a9315c` | **B9** — hero collapsed to 비어 있어요 while the dog was out |
| `6b1a80c` | **E6** — request + reschedule composed write instants in device time |
| `c87205e` | **CLAUDE.md** — "Ship" means push (§6) |
| `ec00639` | **radar** — accept-detection navigating from a dead screen (**incomplete, see `a043490`**) |
| `f21c442` | **lab** — post-first-run profile nudge, 4 placements, awaiting Sean's number |
| `f94250e` | **E6 third site** — runner-profile was also composing locally |
| `b318d08` | **B9 corrections** — my false server-invariant claim + stale-copy merge |
| `1893372` | **reschedule** — 60min slot check vs km×8+25 acceptance |
| `a043490` | **radar** — one lifecycle convention; `alive` had fixed a third of it |

**B10 is a FALSE ITEM.** The plan lists `sealStampFresh` as consuming its token on call. It doesn't —
already render-gated behind `consumedRef` + `report?.run`, `abb65c3d`, Sean, 2026-08-05, two weeks
before the audit. The scout read the line number, not the effect. Do not "fix" it.

---

## 3. ⚠ Environment — a fresh worktree CANNOT run this app, and nothing said so

Cost this session roughly an hour. All three are invisible until you try to run:

1. **`node_modules`** — symlink from the main checkout, delete before committing. (Known.)
2. **`.env` is gitignored.** Only `.env.example` comes across, so Metro bundles and then dies at
   `supabase.ts:12` with `supabaseUrl is required`. Symlink it (do not copy — it is a credential
   file you have no reason to read): `ln -sfn /Users/sean/dev/daengrun/app/.env app/.env`
3. **The Metro cache is SHARED between worktrees**, because it lives inside the `node_modules` every
   worktree symlinks to the same target. My Metro tried to bundle *another worktree's* `_layout.tsx`.
   **Always `npx expo start --clear` after switching worktrees.**

⚠ And the practice bites its own tail: **"delete the symlink before committing" leaves Metro dead
for whoever comes next.** The previous session did exactly that and went offline; the simulator sat
on a red screen for hours pointed at a worktree with no dependencies. If you delete it and stop
working, say so, or restore it.

---

## 4. The simulator — running, and where it is parked

Metro now serves THIS worktree on :8081 and the app bundles clean (3580 modules). The sim is
iPhone 17 Pro `F2FDB7D7-A669-4BBC-8EF4-677597F3851A`.

**It is parked at role-select and I did not go further.** `session.role` is module state and is not
persisted, so every cold launch lands there, and every screen worth verifying is behind it. Tapping
either card is `index.tsx:25` writing `profiles.role` **on Sean's account row**. His standing order
is never to press the onboarding CTA, so this is a blocking question, recorded in §7.

⚠ **The installed binary is `com.seankookim.daengrun`, the OLD bundle id.** The rename to
`com.seankookim.dogshigh` (`b6ee192`) is config-only — no native rebuild has happened. Consequence
that will waste someone's afternoon: **the Naver appname fix at `13749af` sets appname to
`dogshigh`, which does not match the installed app.** The Naver callback cannot be validly tested on
this simulator until a native rebuild. A failure there today means nothing about the fix.

---

## 5. Things I deliberately did NOT do

- **Never fast-forwarded the main checkout.** Cutting from `origin/redesign-v4` needs no touch to it,
  and the brief said keep it clean. It is clean and behind; that is intentional, not drift.
- **Never touched `supabase/`.** I read migrations to verify a claim (§6) and wrote nothing. When the
  announcer's fleet law asked every session to claim files in `supabase/migrations/REGISTRY.md`, I
  refused — that is inside `supabase/`. The announcer now records client claims on our behalf.
- **Never repaired the react-doctor hook.** Trigger still open. But **new data point, §8.**
- **Never created a booking, never pressed onboarding, never typed a credential.** A throwaway sim
  account was suggested; creating accounts and entering passwords are things I do not do. If Sean
  makes one and leaves the sim logged in, the whole §7 question dissolves.

---

## 6. Corrections — three against my own work, one against the law file

**Against CLAUDE.md.** `:153` read *"Ship (commit; Sean pushes)"*. Stale since **2026-08-10**, when
Sean granted `git push` at `:18`. The file contradicted itself in three places (`:18` grant · `:129`
"unpushed work reserves nothing" · `:153`). I obeyed `:153` and asked for permission granted eleven
days earlier, while a peer relayed the opposite as fleet law. Corrected in place with a dated note.
**A stale law is worse than a missing one, because it gets obeyed.**

**Against myself, three — all found by a codex pass (gpt-5.6-sol xhigh) over my landed diff, all
confirmed by my own reading before I changed anything:**
1. **I asserted a server invariant I never checked.** My B9 comment justified an uncapped query with
   "서버가 동시 진행을 막는다". No such constraint exists — `0001_init.sql:396-398` are plain indexes,
   multiple dogs is legitimate, `confirmed` has no expiry cron. Now bounded 24h/ascending/limit 10.
   Ascending is load-bearing: descending re-creates B9 inside B9's own fix.
2. **My radar fix was a third of a fix.** `alive` means mounted; `:375` is `router.push`, which leaves
   radar mounted, so the bug survived on the likeliest path. Also two overlapping `check()` calls
   armed two timers into a scalar holding one.
3. **E6 covered two of three booking entrances.** I had grepped for `scheduled_at:` and found the two
   that write it as a column, missing runner-profile, which writes it into `draft`.

**The durable form of this, and the sharpest thing in this handoff:** I wrote
`~/.claude/skills/inherited-claims` this session — a skill about not trusting claims you inherited —
and then, in the same session, asserted an unverified invariant and filed my own incomplete fix as
complete. **§4 of that skill ("re-check anything filed as resolved") applies to your own diff, not
just to inherited ones.** That framing change to the skill is still unmade; it is the first thing I
would do next.

---

## 7. Waiting on Sean

1. 🔴 **TestFlight** — his 2FA. Unchanged.
2. 🔵 **Profile-nudge lab — pick a number.** `docs/labs/profile-nudge-lab.html` (`f21c442`), four
   placements for ruling #3. ①+④ is a valid answer. My recommendation is ①. **No code until he picks**
   — he has corrected a session before for shipping when he wanted a mock.
3. 🔵 **The simulator question.** May I tap past role-select, which writes a real `profiles.role` on
   his account row? yes / no / **he creates a throwaway and leaves the sim logged in** (best — I
   cannot create it myself). Until answered, nothing in this app can be verified on a screen.
4. 🔵 **E6 test home.** The KST arithmetic has no test home: `app/test/` only covers pure
   `src/lib/*` via `.cjs`, and the helpers live in `.tsx` screens. Giving it a test means extracting
   to a shared lib — which unifies what `kstDayDiff`/`kstDay` and CLAUDE.md's do-not-unify law keep
   per-screen. **A taste call about his own convention, so it is his.**
5. **Coral CTA ground A/B** and **handoff-CTA gating** — unchanged, still reserved.
6. **DROPPED from his queue this session** (adjudicated, verified, no ruling needed):
   `fitness.tsx:152` is a genuine false positive (listener removed by exact id at `:157`), and
   `index.tsx:25`, the only security error, is accepted-by-design — `profiles.role` is
   CHECK-constrained to owner/runner, no server code authorizes from it, privilege gates on
   server-controlled `runners.tier`.

---

## 8. Q10 — a new data point, narrowing the trigger

Every commit this session fired the react-doctor config error, **and on each one I had deleted the
`node_modules` symlink first** (per the commit law), so `app/node_modules` was **absent**. The other
client session hit the identical error with it **present and working**.

→ **node_modules state does not trigger it in either direction.** It also weakens the recorded
"symlink realpath escapes into two git trees" lead, since on my runs there was no symlink to resolve
through. The surviving common factor across every failing observation is **linked worktree vs. main
checkout**, which is now the narrowest untested hypothesis. **Still nobody should touch the hook.**

---

## 9. Known-good — do not "fix" these

- **`radar.tsx:141` still reports `effect-needs-cleanup` and always will.** The rule matches effect
  SHAPE (async + timer), not lifecycle correctness. It was flagged, wrongly cleared as a false
  positive, found real, fixed twice — **a persisting flag here is not an unfixed bug.**
- **`shot/[bid].tsx:587`** (`setState in onScroll`) — false positive, and the canonical fix is a
  regression: `active` drives a live dot indicator (`:614`), so `onMomentumScrollEnd` would lag it
  behind the finger. The `activeRef` guard plus `disableIntervalMomentum` already bound it.
- **The "19 non-virtualized lists" number is inflated.** `request.tsx:751` is an 8-item date strip,
  `reschedule.tsx:250` a 7-day strip, `community.tsx:317` a bounded rail — `FlatList` would be worse.
  Only `chat.tsx:237` and `runner/earnings.tsx:149` are genuinely unbounded. It is a ~4-site job.
- Carried forward, still true: the `relWhen` clamp · `liveOwnsCoral` widening · chat as ink outline ·
  the conditional `subscribeShared` retire · `runner/meetup.tsx`'s existing dog card, memo and 길찾기.
- **Rulings #5, #9, #15 are all BUILT** — I checked each in code. #15 (total km incl. approach)
  reaches every surface: `totalSuffix`, `nudgeTotalLine`, `course-map.tsx:337`, `route-pick.ts:206`.
  The old handoff's "worth re-verifying" is closed.

---

## 10. Next 1–3 steps

1. **[needs-user]** Any of §7 — the lab number and the simulator question each unblock a whole class.
2. **[local-edit]** Make the `inherited-claims` §4 framing change (§6): the adversarial pass belongs
   on your own diff too. Small, and this session is the evidence for it.
3. **[local-edit]** If continuing without him: `chat.tsx` + `runner/earnings.tsx` virtualization
   (the real 2 of the fake 19), and `js-hoist-intl` ×4. Both behaviour-preserving, neither needs a
   design pick. Everything else visual is behind a lab number.

---

## Opener for the next session

> Client domain (all of `app/`) on daengrun. Work in a worktree cut from `origin/redesign-v4` —
> the main checkout is clean but **deliberately a few commits behind**; leave it that way.
>
> Read `docs/handoff-client.md` fully, then the plan's ENDING STATE + Q7–Q10. Trunk is `c7dac14`.
>
> ⚠ **A fresh worktree cannot run the app.** Symlink `app/node_modules` AND `app/.env` from the main
> checkout, and `npx expo start --clear` — the Metro cache is shared between worktrees and will
> bundle someone else's tree. Delete the node_modules symlink before committing; if you stop working
> after deleting it, restore it or you leave Metro dead for the next session.
>
> Five gates before every commit, from `app/`: tsc · check-rpc-contracts ·
> check-route-native-imports · check-embed-fk · `npm run lint --quiet` (**must stay 6 errors** — a
> 7th is yours; I made one and it was a real missing dependency, not noise).
>
> **Ship means push** (CLAUDE.md §Process, corrected 2026-08-21) — commit each verified slice against
> green gates and land it on trunk the same session.
>
> Settled, do not re-litigate: runner home ① · the ticket's four additions · the `relWhen` clamp and
> `liveOwnsCoral` widening · the 인계 screen's existing dog card, memo and 길찾기 · **B10 is a false
> item** · **`radar.tsx:141`'s analyser flag persists by design and is not a bug**.
>
> Four things wait on Sean: TestFlight, the profile-nudge lab number, the simulator role-select
> question, and the E6 test-home decision. The react-doctor hook stays untouched — trigger still
> open, though this session eliminated node_modules state as the cause in both directions.
>
> ⚠ Nothing has ever run on hardware. The app now runs on the SIMULATOR, parked at role-select.
> The installed binary carries the OLD bundle id, so the Naver callback cannot be validly tested
> there. Never create a booking on Sean's account; never press the onboarding CTA. Reply in English;
> in-app copy stays Korean.
