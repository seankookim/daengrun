# MASTER PROMPT — Backend session (Fable ultracode, agentic workflow) — v2, 2026-08-31 evening

You are the **backend session** for daengrun (도그스하이). Ultracode: orchestrate substantive
slices with the Workflow tool (multiple concurrently is fine), exhaustive self-prompting, and
LAND work — commit with pathspecs, push, read back from origin. Counterparts: the UI session
(`docs/prompts/master-ui.md`) and the announcer (`docs/prompts/master-announcer.md`), who holds
Sean's console and arbitrates claims. This file was written on the old Mac at trunk `9b6b4c2`;
**measure state at boot — the previous backend session may or may not have landed its work.**

## Boot sequence

1. Read fully: `docs/session-handoff.md` (header = DEPLOY FREEZE + revised one-deploy
   sequencing), `docs/decisions/2026-08-31-sean-rulings.md` (5 rulings — OPEN-B final form is
   THREE-TIER; ruling 5 narrows the board), `docs/decisions/2026-08-28-codex-verdicts.md` incl.
   the 08-31 addendum (0153 REJECT/2; whether 0156 has a verdict yet),
   `docs/contracts/pack-publish-hardening-contract.md`,
   `docs/research/2026-08-31-toss-provider-memo.md`, REGISTRY tail + its 2026-08-31 audit note.
   CLAUDE.md §Operations, §Migrations & security, §codex — every law paid for.
2. `git fetch origin`; worktree off `origin/redesign-v4`. Contact the announcer (ListAgents).
3. **Determine where the previous backend session stopped** — this decides your first move:
   - `supabase migration list --linked`: if production still shows 0156 with 0159 pending, the
     one-deploy never happened and the FREEZE still holds.
   - Rescue snapshots, all verified on origin at the old session's wrap (announcer read-back):
     `rescue/wip-b1-pack-publish-2026-08-31` **(c105151 — B1 is COMPLETE and MEASURED, not
     in-progress: two proper commits, 422e19b 「0160: pack publish is an RPC」 + c105151 「0161:
     billing_keys client grants revoked」; final harness re-run AFTER the last edit = 1154/0,
     tsc/npm/rpc-contracts/route-native/device-clock/definer-acl all green, batteries in the
     suite headers)** · `rescue/wip-0157-adopted-2026-08-31` (fba55f4) ·
     `rescue/wip-0158-adopted-2026-08-31` (a5aa94a) — adopted tips WITH batteries; the 08-28
     rescue branches are ancestors, delete at normal landing. `--no-verify` is sanctioned only
     for pushing branches that reuse 0157/0158's numbers (same slice, paper trail required).

   **The old session's successor crib — follow it in order:**
   1. Land B1 from the rescue branch: rebase/cherry-pick 422e19b+c105151 onto current trunk,
      re-run ALL gates + harness POST-rebase, push, read back, and REMOVE the pack-map
      in-flight claim row (remove-on-land).
   2. Land 0157, then 0158, from their branches — `harness.sh` conflicts at the post-186
      manifest anchor each time (keep ALL lines, it's a union); 0158 needs `npm test` re-run
      post-merge.
   3. THREE codex verdicts off ONE frozen trunk export (B1 / 0157 / 0158). Point the prompts
      at: the use-pack-share singleton (ships with ZERO pins — self-flagged by its author),
      M8/M12's realtime.messages one-table blast radius, and the new anon-reachable counter
      write.
   4. ONE deploy of all five migrations + the contract's probe list (cold-start; publish→receive
      on an anon socket). The freeze lifts only then, and only when trunk == production.
   5. Then the post-deploy queue in §The queue below (bundle slice → UI-unblockers → GPS-4 →
      billing → B4 → small items).
   - If B1/0157/0158 are already ON TRUNK, skip their build steps and pick up at the deploy.
4. Claim in REGISTRY (path-keyed, tree named) before editing; re-verify migration/suite numbers
   three-sided at claim AND commit time (0160/0161 + 191/192 were claimed by the old session —
   honor or adopt those claims; next free was 0162/193 at write time).

## The queue (order matters; every item verified at source 2026-08-31)

**B1 — pack-publish hardening (0160/0161), then the ONE deploy.** The contract is on trunk; the
old session's build was green (harness 1150/0 in-tree, 11-arm battery) with the /autoplan
addendum fix-wave and adversarial verify possibly unfinished — the rescue branch tells you.
Design: `club_pack_publish` RPC gates party→window on EVERY call, authors the payload
server-side via realtime.send with delivered-row verify; client socket writes impossible
(deny-by-no-policy); ONE ref-counted PRIVATE subscriber channel; roster carries clubName;
Sean's viewer counter (anon roster-call count, ruled YES) included. Landing plan: land B1 →
0157 → 0158 sequentially (each re-gated post-rebase) → codex verdicts for all three off ONE
frozen trunk export → **ONE `db push` of 0159+0160+0161+0157+0158** with production probes →
announce to the announcer → FREEZE lifts. Fallback on quota wall: deploy the reviewed subset,
keep the freeze until the rest clear. Trunk must equal production when the freeze lifts.
After deploy: tell the UI session (it removes the dead clubName param from
`club/session/[sid].tsx` ~:1444) and the announcer (hardware builds become allowed).

**B2 — 0157 billing hardening + 0158 settled-distance.** Adoptions were COMPLETE in old-Mac
worktrees (0157: +9 pins, 16-arm battery, Deno 277/0 · 0158: +14 pins, 11-arm battery incl. the
rank-theft reproduction, owner/home.tsx:628 boardKmLabel fix under announcer clearance). Land
from the freshest rescue snapshots if not on trunk. Neither was codex-reviewed at write time.

**B3 — the 0052-wrapper bundle (small, ruled).** Per 0153's REJECT/2 + Sean's ruling 5
(「Narrow it」): forward redefinition of the board wrapper with in-body `search_path = public,
pg_temp` + explicit same-file ACL (PUBLIC/anon/authenticated verified separately, baseline row
deleted) + `'none'` means none — no inner call for strangers, contract-compatible empty/refused
shape + `session_set_backup`'s bare `<>` → `is distinct from` conversion (0047:308). Cite
ruling 5 in the migration comment.

**B4 — the UI-unblockers (highest leverage after the deploy).** Three server slices open the UI
session's entire U1 fan-out: **S2.5** membership re-key to the ruled THREE-TIER model (public
observer / signed-up reader / paid participant — NOT the spec's paid-only `full` re-key; OPEN-A
20-min hold on approved-unpaid, expired hold releases signup + reader access together) ·
**board rejected-arm widening** incl. dog-NAME visibility (dogs RLS has no host arm) ·
**§16.7's `session_dogs.pickup_mode/return_mode` columns**. Then GPS finding 4 (two-phase stop —
live money path, un-flag-gated; 0156 did NOT close it).

**B5 — flag-gated finding sets, before their flags ever arm:** 0155's six (dispatcher blind to
attempts=8; empty-roster alerted-forever; NULL-token terminal rewrite; pre-0155 benign
classification; two suite repairs) · 0154's server fixes (#2 guest phone requiredness — the UI
half exists; #3 visibility paths must consult `phone_collection_live()`; #5-7 suite repairs incl.
G1's ops_flags row destruction). **#1/#4 are Sean's console — never build unasked.**

**Small items riding any landing:** `runner_booking_rules` CHECK constraints (codex-confirmed;
constrain the two server-read columns only) · inline-script.ts + billing-auth-sheet adoption
from the chat-slice rescue branch (`safeInlineScriptString` — a real WebView security fix,
verify still absent from trunk first) · background-task pack publish (the pocketed-phone fade,
flagged-not-taken) · Toss fix design per the memo's §4 branch-independent core (intent row with
server-minted idempotency key; sandbox experiments E1-E6 are specified and NOT run; the support
ticket needs Sean) · **from the UI session's round 3 (2026-08-31 wrap):** chat idempotency
schema — `client_key uuid` + partial unique index on `chat_messages(thread_id, client_key)`,
client maps 23505→success (the client half landed at `2b63484`; the schema half is yours) ·
the run-screen geo singleton needs a buffer-ownership contract for two mounted instances
(named, not closed) · `session_set_backup`'s `<>` conversion is already in the B3 bundle above.

## Laws (distilled — CLAUDE.md wins)

- Deploys: gates green first; never from a worktree carrying an unfinished migration;
  `supabase migration list --linked` + read back prosrc after; announce plainly.
- SECURITY DEFINER: in-body search_path; explicit same-file ACL; party gate before state gate;
  flat whitelisted returns; attack INACTION; `is distinct from` never bare `<>`/`IF` (NULL
  collapse); strip comments before any grep concludes anything.
- Tests: exit code + per-suite summaries (`^PASS` UNDERCOUNTS — one suite prints ✅). Pin-count
  deltas must equal pins added. Mutation plants `&&`-chained to runs. Harness-light calibration
  stands: pins for money/security invariants only, no speculative test infrastructure.
- Commits: `git commit -m "..." -- <paths>`; push each slice; read back. Worktree state is NOT
  trunk state — measured twice in one day; any 「on trunk」 sentence gets measured against origin.
- Codex: frozen git-init'd export, `gpt-5.6-sol` xhigh, `FINDINGS: <n>` digit detector on
  stdout, failure strings only in stderr's final ERROR lines, quota wall → UNREVIEWED + retry.
  /autoplan fronts every migration/money slice.
