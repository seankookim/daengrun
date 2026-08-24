# HANDOFF — client domain (`app/`), written 2026-08-21 night

**Read in order:** this file · `docs/plans/2026-08-21-late-booking-protocol.md` (the protocol, its
§12 server contract, and the **AMENDMENT at §12** you must not undo) · `CLAUDE.md` ·
`docs/handoff-codex/` · `~/.claude/skills/inherited-claims/SKILL.md` (written this session; its §4
is about this session's own repeated mistake).

Domain: **client — all of `app/`**. Never write a migration. Reading `supabase/` to verify a claim
is required and was done constantly.

---

## 1. Status

| | |
|---|---|
| Trunk | `redesign-v4`, my ~35 commits landed, branch `claude/client-redesign-v4-work-3e224f` in sync |
| Five gates | tsc 0 · rpc ✅ · route-native 57 ✅ · embed-fk ✅ · **lint 270 / 6 errors** (baseline) |
| **`npm test`** | **NEW — six suites chained, green.** Was: nothing. Nobody ran the four that predate me |
| Suites added | `lateness` (65) · `late-copy` (34) · `kst` (14 UTC + 15 Seoul) — all mutation-verified |
| Simulator | app RUNS from a worktree; owner hero verified on screen twice |
| Hardware | 🔴 still nothing, ever |
| 0117 (server) | **NOT deployed, NOT landed.** Production is 0115/0116 |

---

## 2. 🔴 READ THIS FIRST — a 36-agent audit found 20 confirmed defects, 2 are BLOCKERs

`/workflows` run `wf_a68ecb4d-309`, four lenses + adversarial verification (31 raised, 20 survived,
11 refuted). Full report in that run's `journal.jsonl`. **Do not flip
`ops_flags.late_protocol_live_since` before F1, F2, F3, F4 and F6 land** — every one is inert today
and fires on the first late booking after the flip.

**F1 · BLOCKER (server).** `_checkin_custody` requires BOTH handoff stamps for `'post'`. One stamp
is the *normal interval*, not a failure. So: owner hands the dog over and taps 인계했어요, runner's
phone dies → the deadline arm classifies `runner_enroute` as pre-custody and writes **`no_show` over
the owner's own attestation**. `0066:56` makes that irreversible, the run can never settle, and
`0075:750` fires a km release for a dog that is out walking.

**F2 · BLOCKER (server).** Entry is pre-custody-only; **resolution is not.** Sweep arm ⓐ selects on
the check-in row alone, so a check-in armed at 10:33 resolves a run that started at 10:52 → a run 11
minutes in flips to `incident_review`, which per `0097:80` has **no marketplace money exit**. I
asserted the opposite in `late-copy.ts:33-35` — that post-custody never enters the protocol. Half
true: entry doesn't, resolution does.

**F3 · HIGH (mine).** The 3-hour ceiling is **a sentence with no gate anywhere.** `resumable` has no
mount consumer and no server rule enforces it. Sean's Aug-4 row shows 「이 예약은 진행할 수
없어요」 with a coral 「픽업 이동 시작」 82 lines below — and `runner/meetup.tsx:184` fires
`runnerEnroute()` from a **mount effect**, so merely opening the screen revives it. FM4 is not
handled; the plan says it is.

**F4 · HIGH.** `runner/meetup.tsx:157`'s terminal guard is a **deny-list** that predates both new
terminals. On the protocol's modal path (runner proceeding, owner silent) the runner stands on a
`no_show` booking with a live 인계 확인 button and unbounded retry.

**F5 · HIGH — one half FIXED TONIGHT.** The hero's handoff frame tells the owner to hand over a dog
already handed over (`'handoff'` is written only after BOTH confirmations). It also carried **a live
TDZ crash I introduced**: `openNext` read `isLate` declared 95 lines below the branch that returns
first. **Crash fixed** (`isLate` hoisted above `openNext`). **The mislabelled frame is NOT fixed** —
it is a UI change Sean should see.

F6-F20 (fee/reschedule doors, `RunnerJob` status arms, 112·119 copy, stale records) are in the
journal with file:line, concrete failure, and cheapest fix for each.

---

## 3. §12 clauses that are satisfiable-but-wrong

The amendment at `§12` states the rule — **specify what a mechanism must REFUSE, not that it
exists** — and the audit then applied it to my remaining clauses. **C1, C3, C4, C5** each name a
mechanism and no refusal. **C2 (`§13:315`) is worse: it states the custody rule outright wrong**
(`status ∈ picked_up|active → 'post'`), the server implemented something stricter, and client and
server now disagree on the D3 line while both "conform". Exact replacement wording for all five is
in the journal. **Apply them before round 5.**

---

## 4. What happened to my conformance verdict

I returned CONFORMS on `a984584`. A blind reviewer later found `fetch_checkin` and
`quote_cancel_fee` gate with `elsif current_user not in ('service_role','postgres')` — under
SECURITY DEFINER `current_user` IS the owner, so the predicate is always false and the gate never
fires. **I quoted that exact block and passed it.**

The lesson, now in `§12` and the announcer skill: **conformance review and security review are
different questions, and passing one says nothing about the other.** I asked "does this match §12";
§12 said "party-gated"; a gate was present. The verdict is **stale-in-scope, not withdrawn** — true
of `a984584`, superseded, and NOT a live landing gate.

---

## 5. ⚠ Environment — a fresh worktree cannot run this app

1. `ln -sfn /Users/sean/dev/daengrun/app/node_modules app/node_modules`
2. `ln -sfn /Users/sean/dev/daengrun/app/.env app/.env` — gitignored; without it Metro dies at
   `supabase.ts:12`
3. `npx expo start --clear` — **the Metro cache lives inside the shared `node_modules`**, so a new
   worktree bundles a *different* worktree's tree until cleared
4. Delete the node_modules symlink before committing — **and restore it after**, or you leave the
   next session a dead Metro (that is what happened to me)

⚠ The installed sim binary is `com.seankookim.daengrun`, the **old** bundle id. The `dogshigh`
rename is config-only, so the Naver appname fix at `13749af` **cannot be validly tested there**.

---

## 6. My failure pattern, stated so it can be watched for

I shipped **five false claims** today and caught every one only after shipping. All five were
**promises about what the system would do**, never statements about what it knows:
「수수료 없이 닫아요」 · 「확인이 필요해요」 · 「운영팀이 바로 확인해요」 · a fee-waiver line for an
undeployed policy · 「이 예약은 진행할 수 없어요」 for a thing nothing prevents.

Four review rounds, one coherence audit and one 36-agent audit each found real defects in my own
landed work. **The app also corrected me three times** — `home-hero.tsx:256` on the fee,
`END_REASONS` on one-tap-vs-two, `relWhen()` on which clock wins. When this codebase and I disagree,
it has been right every time so far.

---

## 7. Waiting on Sean

1. **CRIT-1 flag window.** 0117 ships the clock OFF behind a flag. My client does not know about it,
   so between deploy and flip the app says "late" while nothing acts — the same implies-a-watcher
   problem we just closed. Flip with the deploy, or my copy learns the flag?
2. **Stop-reason build** — ③+③-A settled (`§8-bis`), blocked on deploy.
3. **F5's mislabelled handoff frame** — UI change, wants his eye.
4. TestFlight · coral CTA ground A/B · handoff-CTA gating — unchanged.

Settled, do not re-litigate: runner home ① · grace 30 / ceiling 3h (his words, direct) · profile
nudge ② with no dismiss · late-booking lab approved · B10 is a false item · `radar.tsx:141`'s
analyser flag persists **by design** after a real fix.

---

## Opener for the next session

> Client domain (all of `app/`) on daengrun. Cut a worktree from `origin/redesign-v4`.
>
> **Read `docs/handoff-client.md` §2 first — a 36-agent audit found 20 confirmed defects, two of
> them BLOCKERs, and the full report with file:line and fixes is in `/workflows` run
> `wf_a68ecb4d-309`'s `journal.jsonl`. Nothing may flip `late_protocol_live_since` until F1-F4 and
> F6 land.**
>
> ⚠ A fresh worktree **cannot run the app**: symlink `app/node_modules` AND `app/.env`, and
> `npx expo start --clear` (the Metro cache is shared between worktrees). Restore the symlink after
> committing or you strand the next session.
>
> Five gates from `app/`: tsc · check-rpc-contracts · check-route-native-imports · check-embed-fk ·
> `npm run lint --quiet` (**must stay 6 errors**). **`npm test` now exists** — six suites, run it.
>
> **Ship means push** (CLAUDE.md §Process). Land on trunk the same session.
>
> The client's job now is §2's F3, F4, and the client halves of F1/F2 — not new surface. And when
> the code and your plan disagree, the code has been right every time.
