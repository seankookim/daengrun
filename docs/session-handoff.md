# SESSION HANDOFF — 2026-08-10 (both blockers closed · A-wave shipped · everything deployed)

English everywhere except in-app user-facing copy (CLAUDE.md §Language).
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md is the permanent law book. Prior handoffs: `docs/session-handoff-archive-20260805.md`
and this file's git history.

**Build in the MAIN checkout `/Users/sean/dev/daengrun` (branch redesign-v4).** Worktrees under
`.claude/worktrees/` are stale snapshots — never build or gate there.

---

## ⓪ STATUS — everything is deployed and pushed

| | |
|---|---|
| git | **origin up to date** (through `3ec216c`) — nothing local, working tree clean |
| database | **0064** applied on prod; 0060–0064 all live |
| edge functions | current — `transition-booking` v30 verified at parity ("No change found") |
| harness | **296 / 0** |
| tsc · check-rpc · geo | 0 · 75 calls/108 sigs · 37/0 |
| simulator | fresh build **Aug 10 14:28** installed and verified running |

**Both critical-path blockers are closed.** A runner can become bookable (0062), and GPS survives
the screen lock (background task + hard block). What remains between here and a paying customer is
payments, legal, interviews, and device verification — not missing features.

### 🔑 Authorization changed this session
**Claude may now run `supabase db push`, `supabase functions deploy`, and `git push`** (CLAUDE.md
§Operations). Conditions: gates green first, never push from a worktree holding an unfinished
migration, verify after rather than assume, announce what ran. **Still Sean-only:** anything
needing a credential's *value* (APNs `.p8`, App Store Connect, PG contracts), and product
decisions with real-world consequences even when the command is one line.

---

## 🔴 WHAT ONLY SEAN CAN DO — full commands in `docs/sean-commands.md`

1. **Decide the seed runners.** Production has **6 fabricated certified/veteran/master runners
   with `identity_verified: true` and zero real runners**, while `safety.tsx` now tells owners an
   operator personally verified each one on video. **That sentence is false until this is done.**
   Recommended (reversible):
   ```sql
   update runners set tier = 'applicant', identity_verified = false, online = false
   where profile_id in (select id from auth.users where email like '%@daengrun.seed');
   ```
2. **Owner Live Activity relay** — the only unfinished half of 0063. Write
   `supabase/functions/live-activity-push` holding your APNs `.p8` (I can write the function; you
   supply the key as a function secret), deploy it, then:
   ```sql
   insert into owner_la_push_config (id, relay_url, relay_secret)
   values (true, '<function url>', '<long random string>');
   ```
   Until that row exists the push composer is a deliberate silent no-op — no phantom pipeline.
   Also confirm `pg_cron` + `pg_net` are enabled (Database → Extensions).
3. **Media backfill** — `node scripts/migrate-private-media.mjs` → `--yes` → verify in app →
   `--yes --purge`. **New uploads are already private; existing dog/run/chat photos stay
   world-readable until purge**, and the privacy policy cannot claim "private" before then.
4. **Device smoke on real hardware** — the simulator covered UI; it cannot do real GPS movement,
   real APNs delivery, or battery/thermal. The one that matters most: **lock the screen, pocket
   the phone, walk 500 m, unlock — the distance must reflect all of it.**
5. **Off-machine:** 변호사 review of `docs/legal/`, 위치기반서비스 신고, 사업자등록 ⟷
   예비창업패키지 2027 fork then PG, 15-20 owner interviews, App Store privacy labels →
   `eas build --profile testflight -p ios`.

---

## What shipped today

`8151139` honesty wave 2.5 · `ac936f5` wave 3 · `2f113d8` **0061 P0 seal** · `cf6d93a` **0062
runner funnel** · `9e2ec68` **background GPS** · `719edd3` **A-wave** (0063 owner LA, 0064 private
media, LA reskin, 4 riders) · `3ec216c` grandfathered-runner fix · plus docs, legal drafts,
privacy answers, the LA lab, and the geo-test-runner repair.

**Verified against production (2026-08-10): zero exploitation of the 0061 hole.** All 9 privileged
`runners` rows are the 6 seeds + 2 e2e + `s4kim2025`; every `commission_rate` is 0.33.

---

## The lesson worth carrying: three times, the *test* was the thing that was wrong

- My commission-rate drift pin compared a literal against the schema and **stayed green under the
  exact bug it was written for.**
- The relay-secret pin counted an **empty table** — it ran before the config row was inserted, so
  it passed regardless of whether RLS worked.
- A funnel pin probed a *live* foreign row where only a **terminal** one exposes the oracle.

All three looked like coverage. **Mutation-proof every pin, and verify the revert actually
applied** — a regex that matches nothing is a fake proof.

**And the corollary, learned on the simulator:** every automated gate passed while the app showed
certified runners a submit button that the server would reject. Gates test the contract; only
looking at the screen finds a client offering an action the server refuses. **Run the app.**

---

## Environment gotchas (both produce false success, not honest failure)

- **CocoaPods needs a UTF-8 locale on this machine** — the same gap that breaks the SQL harness.
  Without it `pod install` dies on a Unicode error and **Expo still exits 0**, leaving a stale
  binary installed while reporting success. Always:
  `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && cd app && npx expo run:ios`.
  Verify by the installed bundle's timestamp, never the exit code.
- **Expo's auto-launch is blocked by macOS automation permission** (it AppleScripts System Events).
  Build and install succeed; only the launch fails. Launch directly, or approve
  Terminal → System Events in Privacy & Security → Automation.
- Harness: `pkill -f "bin/postgres -D .pgtest/data"` before each run — repeated runs orphan
  clusters and eventually fail with a misleading error.

---

## Standing laws (CLAUDE.md is authoritative)

- **Never `git add -A`** — untracked investor decks, agent tooling, and Supabase container secrets
  live in this tree. Stage explicitly.
- Honesty: no mock data, failures shown as failures, loading ≠ empty, no dead buttons, gate on
  `rawStatus` not display vocabulary.
- Commit gate: tsc + check-rpc. Migrations also: PG16 harness with mutation proofs. Money changes
  get their own migration and their own adversarial cycle (0059 doctrine).
- New definer functions: `set search_path = public, pg_temp` **in the body**; revoke from
  public/anon; party gate before state gate; errors identical for absent vs not-yours.
- DO-NOT-REFACTOR: owner-home collapsing hero · meetup stage machines and once-law hydration
  ordering · the 2-layer matching compositor.

## Key artifacts

`docs/sean-commands.md` (every command + undo) · `docs/launch-checklist.md` ·
`docs/plans/finish-the-app-plan.md` · `docs/labs/live-activity-lab.html` (**option ② picked,
awaiting your confirmation**) · `docs/legal/` · `docs/appstore-privacy-answers.md` ·
plans for the funnel, background GPS, and wave 3.

## Open / unresolved

- **A dev warnings toast appears in the app and I could not identify its source** — log queries
  came back empty. Could be a benign RN deprecation or something from today. Check via the in-app
  debugger or `npx expo start` console. Flagged rather than assumed harmless.
- Riders: `GEAR_META.bodycam.hint` still promises video on the runner profile · 3 surviving
  opacity-disabled tricks · `store.runners` dead mock with 신원인증/펫보험 badges · signed-URL TTL
  is a real 1h window outliving permission revocation (documented in `media.tsx`) · owner/live
  local `done` km can differ from settled km by metres · harness.sh never stops its cluster.
- **Product gaps behind honest "준비 중" labels:** payments (the biggest — `payment_ok` is a mock
  and pay.tsx says so), shop (gated on your first affiliate link), incident reporting on the
  safety screen, and map coordinates (nothing ever writes `addresses.lat/lng`; there is no
  geocoding path, which is why every map surface says 준비 중).

## Next 1-3

1. **[Sean]** Seed-runner decision, then the relay function and the media purge.
2. **[me]** Whichever product gap you pick — my read is **coordinates/geocoding** unlocks the most
   (real maps on meetup, request, and course all at once, plus 길찾기), and **incident reporting**
   is the one whose absence is least defensible on a safety screen.
3. **[Sean]** Interviews and the 사업자등록 fork — those set the payment timeline, which sets
   everything else.
