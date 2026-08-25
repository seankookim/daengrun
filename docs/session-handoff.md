# Session handoff — announcer v5, 2026-08-24 → 08-25 morning

**Read with this:** `/announcer` (method — updated this session, read §11) ·
`docs/decisions/2026-08-24-sean-ui-club-commentary.md` (**both of Sean's commentaries VERBATIM
plus every extracted ruling** — the highest-value file this session produced) ·
`docs/plans/2026-08-25-club-delegation-restructure-spec.md` (the club spec + its four-voice
GSTACK REVIEW REPORT + RETHINK addendum) · `docs/decisions/awaiting-sean.md` **§0-undetricies
(line 1285)** — the client session's seven one-word questions, none yet answered ·
`docs/findings-2026-08-24-0118-verification.md` (the day's measured record, 3 parts) ·
`supabase/migrations/REGISTRY.md` (the ledger; 0118/0119/0120 rows carry full measurement
records on their branches) · the console artifact
<https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b> (Sean's single place to
look — keep it CURRENT; it is the morning brief). Prior handoff archived at
`docs/session-handoff-archive-20260821-v4.md`.

Tags: **[verified-now]** checked this session against code/live/gate · **[reported]** an agent or
peer said so, unconfirmed · **[from-history]** earlier in conversation · **[uncertain]**.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Production migrations | **0116 head, UNCHANGED all session.** Charging OFF · 0 payments · 0 billing_keys · ₩111,657 owed / 0 payouts · 11 auth users. Nothing was deployed by this session. | [verified-now] via `supabase_migrations.schema_migrations` — never `migration list` (it misreports; see archive §1) |
| Trunk `redesign-v4` | `c8abc1a` — carries the 0118 + 0119 landings, this handoff, the commentary/spec docs, ui6's UI-pick commits + campaign r7 + the 도그스하이 orderName edit. Merged-trunk verification: **harness 760/0 · deno 225/0 · tsc ✅ · rpc ✅ · route-native ✅** | [verified-now] |
| **0118 club fee** | **LANDED on trunk 2026-08-25.** Four adversarial rounds, ruling B implemented+measured (runnerless cancel = platform half only; FULL-revert mutation reds all five owners — F5, P1, P14, P15, ARM5 — see §6). NOT deployed: production stays 0116 until a deliberate `db push` | [verified-now] |
| **0119 맹견 gate** | **LANDED on trunk 2026-08-25** (merged @ b28a787 after ui6's hand-resolution of dog.tsx/requests.tsx). ⚠ Deploy-order law in §6 is now LIVE: no binary built from trunk reaches a device before `db push` applies 0119 | [verified-now] |
| **0117 late-booking** | branch fat and healthy (796/0 · deno 232/0, R1-R17 + 4B + R10-13 all closed) but **NOT landing**: §4.2's two statement-money arms are UNRULED. When it does land, **the landing vehicle is `claude/cancel-fee-mirror`** (next row), not the stage2 branch alone | [verified-now] |
| **0120 location law** | **PARKED** at `b06f878` with all nine review findings recorded in its REGISTRY row. Clock not running (oldest trace ~weeks vs 1-year cap) | [verified-now] |
| Cancel-fee mirror | **SHIPPED to `claude/cancel-fee-mirror` @ `c5bc01d`** — cut from stage2 (quote_cancel_fee in-tree) with trunk merged in; strict-parse quote, failed quote BLOCKS the commit button, %-constants retired, cancelFeeRateFor deleted. **This branch IS the 0117 deploy unit: merging IT to trunk at deploy time ships migration + client together.** Never land the client half early (DOG_SELECT-400 class) and never land 0117 without it. ui6 merged trunk through 7dc88c9 into it same night — **trunk ⊆ mirror re-verified here: the 0117 deploy-time landing is a fast-forward as of 2026-08-25**. Deployer still re-verifies the ancestor at deploy time (trunk moves), then runs `db push` + the mirror's trunk merge in one breath, `supabase migration list` after (§Operations). Branch existence + stage2 ancestry [verified-now]; the client behavior claims are ui6's gates (tsc 0 · rpc ✅ · lint baseline 6 · 0 FAIL) [reported] |
| Club restructure | **GREENLIT by Sean** (his clarified model: the paired runner owns the dog door-to-door). Spec v1 + four-voice review + RETHINK on origin; **spec v2 ordered** — full per-side/per-state delineation incl. recalibrated host screen + the Mode C ranking algorithm he sketched. NOT STARTED | [verified-now] |
| Runner-money strip | Designed, unbuilt: server-computed net + column revoke + api.ts swap, ATOMIC. ⚠ `runners.commission_rate` must NOT seal until the estimate moves server-side — its silent 0.33 fallback would quote a guessed rate (recorded in ui6's 2130f2e) | [verified-now] |
| 158-token session artifacts | This session's branch `claude/session-handoff-migration-verify-7d7f35` @ `0bba02f` holds the commentary/spec/findings docs — **merge it to trunk with the landings** so the record is where everyone reads | [verified-now] |

## 2. Sean's rulings this session — ALL verbatim in the commentary doc

08-24: **1C** (both no-show gates) · **2A** (config fails loud) · **4B** (own-reason-only) ·
**strict grace** · **ui6's allocation** ("sure on ui6") · **slot-based supply comp** ("go ahead
with that and all other queues") · the fable/opus orchestration grant.
08-25: **Club #1 clarified** — home pickup was never "another stranger"; the paired runner
carries responsibility from the getgo; CEO answer was yes-with-riders (honest transit copy until
insurance signs · no-show predicate moves to arrival-at-start · Mode C rides the counsel brief) ·
**Mode C = build the algorithm** (proximity → runner distance pref → owner distance pref → pace →
rest; deterministic, patent-safe, needs a runner home-address column) · **B for the fee** (done,
measured) · **ship the mirror** (ui6, in flight) · **land 0118+0119** (in progress) ·
**도그스하이 not 댕런** (done, trunk) · **rescue deleted** (done, 157MB).

**STILL HIS, unanswered:** §4.2's two statement-money arms (explained to him ELI5 — awaiting
words) · 맹견 refused-vs-conditions (moves ui6's copy only) · breed-alias scope · feed_posts
`using (true)` vs the 동네 피드 name · picture requirement server-enforced? · ui6's SEVEN at
§0-undetricies · community/account commentary (he owes it: "later").

## 3. The day's method lessons — now in `/announcer` §11 (v5)

1. **Commit before ANY mutation/checkout — unconditional.** Violated FIVE times in one day,
   twice by the author of the rule minutes after writing it down. `git checkout` against
   uncommitted work destroys the work, not the mutation.
2. **A pin with no recorded mutation result is an untested claim.** Six self-correcting pins in
   one day, all one class: *a proposition with an unstated scope* (fixture-context, grammatical,
   collection-vs-current, closure-time). The strongest form found: **both operands of a guard
   came from the same closure — it asked "is this dog this dog" and always heard yes.**
3. **A signal is only a gate input if the real flow can produce it — and nothing can erase it.**
   Verified empirically (throwaway suite driving real RPCs), never by inspection: inspection
   answers "does this column mean what I think" and never "can it be taken away from me."
4. **Same column, two questions**: pairing-scoped evidence is correct for "which terminal does
   this pairing get" and wrong for "did this person fail" — subject determines validity.
5. Vendor diversification under outage: codex authors / Claude measures / blind codex reviews
   kept the whole day moving through a 3-wipeout Anthropic 529 storm.

## 4. Fleet & peers

- **ui6** (`daengrun-redesign-v4-77ea99-1c` on the peer list — ⚠ its socket CHANGED once
  mid-day; peer-list absence is NOT session death, ask before reallocating): holds all of
  `app/`, the mirror slice, the 0119 merge, C④ done. Battle-tested, self-correcting, honest
  about non-fixes. The collaboration protocol that worked: path-keyed claims · verbatim rulings
  on origin before action · verify the peer's claims at source, expect them to verify yours ·
  deliberate deviations stated BEFORE doing (their merge-not-rebase), with a window to object.
- Codex (`codex exec`, gpt-5.6-sol xhigh): author with `-s workspace-write` (CANNOT commit —
  index.lock denied — apply its tree and commit yourself), review with `-s read-only`, ALWAYS
  `< /dev/null` (wedges silently without it). Cannot run the harness.
- Suite-152 pin namespace: ui6 L49-L57+, announcer L48/L48b; L54 asserts label uniqueness over
  EMITTED labels. Resolve next numbers from the branch TIP at write time, never from memory.

## 5. Next 1-5 steps, in order

1. **[land]** Merge `claude/club-fee-slice` → trunk. Conflicts expected: REGISTRY.md (keep both
   rows) + harness.sh suite line (**153 above 154** when 0119 follows — the REGISTRY's own
   recorded rule). Then FULL harness on merged trunk + commit gate, push.
3. **[land]** When ui6 pings green on the 0119 branch merge: ff-merge → trunk harness → push.
   Also merge this session's docs branch (`claude/session-handoff-migration-verify-7d7f35`).
4. **[build]** Spec v2 (greenlit): the coupled machine (pairing/payment/custody/cancel/finish as
   ONE state machine, per the RETHINK), per-side/per-state screens, host respec, the ranking
   algorithm, the consumer-by-consumer migration table. The four-voice report + addendum lists
   every known contradiction to resolve — start from its fact corrections, not from spec v1's
   claims.
5. **[build]** The runner-money strip slice (small, ruled, contract in §1) · R17's remainder
   (sweep → per-row commits; announcer-claimed) · counsel briefs still unsent (Sean).

## 6. The F5 anomaly — RESOLVED, and worth keeping as a lesson

Under the partial revert-mutation (halving only), 66 F5 stayed green while P1/P14/ARM5 reddened.
Explanation, verified by a second measurement: **F5 reads the club_fee_items SUM, and the partial
mutation reverted the fee columns but not the item-split — so the observable F5 watches never
changed.** A pin and a mutation must name the same observable. The FULL revert (halving + item
split together) reds all five owners — F5 `fee=2490`, P15 "공급 몫 행이 존재한다", P1, P14, ARM5 —
recorded on the branch at `fc26796`. Every arm of ruling B now has a mutation red that names it.

**Deploy-order law for 0119 (from ui6 — put this wherever the deploy checklist lives):** landing
0119 on trunk does NOT ship it; DOG_SELECT names the two new columns, so the first binary built
from trunk after the merge must not reach the simulator/TestFlight before `supabase db push`
applies 0119. Merge order is free; deploy order is not.

## 7. Gotchas that will bite again (beyond §3)

- Harness serialization: ONE run at a time machine-wide; parallel runs braid into phantom reds.
  `[axes] X8` (70:168) is a known random flake (~1/17) — rerun, never "fix".
- The main clone's local `redesign-v4` was found STALE mid-session (at a client-session commit).
  `git fetch && merge --ff-only origin/redesign-v4` before committing there.
- `supabase migration list` misreports head; query the ledger table. `db query --linked` never
  meets RLS. The repo's silence is not evidence about production.
- REGISTRY numbers: two-sided at write time from origin (row + file). Suite numbers likewise.
- react-doctor's pre-commit noise about unstaged config files is pre-existing; commits succeed.

## 8. Environment at handoff

Worktrees: `measure-0118` (branch, clean at `0443184` unless the F5 rerun left mutation residue —
it self-reverts), `measure-0119` (branch tip), `slice-0117-4b` (branch tip), `measure-0120`
(parked tip), `daengrun-route-depth-b5bef1` (this session's docs branch). Nothing uncommitted
anywhere [verified-now at write time]. Nothing on production. All review/measurement logs in this
session's scratchpad die with it — everything that matters is in the docs above.
