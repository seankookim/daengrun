# MASTER PROMPT — UI session (Fable ultracode, agentic workflow) — v2, 2026-08-31 evening

You are the **UI session** for daengrun (도그스하이). Ultracode: orchestrate substantive slices
with the Workflow tool (multiple concurrently is fine), exhaustive self-prompting, and LAND
screens — commit with pathspecs, push, read back from origin. Counterparts: the backend session
(`docs/prompts/master-backend.md`) and the announcer (`docs/prompts/master-announcer.md`), who
holds Sean's console. Written on the old Mac at trunk `9b6b4c2`; **measure state at boot — the
previous UI session may or may not have landed its round-3 fix wave.**

The v1 queue is nearly done — landed 2026-08-31: U5 focus-scheme remainder, U2 pack-map doors,
U3 pay surface + red-line cap, U4b 백업 호스트 doors, U4c 러닝 종료 (per Sean's Wire-it), the
chat-rescue landing, the runner 예약 규칙 editor, codex rounds 1-2 fully fixed (5 + 13 findings),
floor rulings applied. What remains is below.

## Boot sequence

1. Read fully: `docs/session-handoff.md` (header: DEPLOY FREEZE + hardware-build hold),
   `docs/decisions/2026-08-31-sean-rulings.md` (5 rulings — **OPEN-B was refined TWICE; the
   final model is THREE-TIER**: anyone sees roster+pictures · signed-up-unpaid READS chat ·
   paid participates), `DESIGN.md` (정본), `docs/reviews/2026-08-31-codex-ui-wave2.md`
   (rounds 2-3 ledgers), `docs/design/device-smoke-ui-master-2026-08-31.md`,
   `docs/plans/2026-08-25-club-delegation-spec-v2.md` (U1's spec). CLAUDE.md — honesty laws +
   commit gates are non-negotiable.
2. `git fetch origin`; worktree off `origin/redesign-v4`. Contact the announcer; claim in
   REGISTRY before editing (the 08-31 audit note is authoritative on live vs dead claims).
3. **Determine where the previous UI session stopped:**
   - If its codex round-3 fix wave (REJECT/19) is on trunk with final ledger dispositions,
     continue from the queue below.
   - If NOT: adopt `origin/rescue/wip-ui-round3-2026-08-31` (commit 551d86b3). ⚠ Its commit says
     plainly: **gates NOT run, do not merge as-is**. Finish the remaining fixes (chat
     send-handler guards, api.ts F10/F18, availability F19, charge-states F16, payphase pins),
     run full gates, land properly. ⚠ The ledger's rows R3-2..R3-19 read 「verifying」 — the
     verification verdicts died with the old machine; **re-derive dispositions from the fixes
     themselves in the rescue diff (each carries a `[codex r3-N]` comment naming its finding)
     rather than trusting the 「verifying」 cells**, and write final dispositions into the ledger
     in the landing commit.

## The queue

**U-r3 — finish and land the round-3 fix wave** (see boot step 3). Nothing else lands before it:
19 confirmed findings across payphase/pay/run/console/chat are known-open until this is on trunk.

**U1 — club delegation spec v2: the mother lode, now partially unblocked.** Spec status was
「Nothing here is built」. The moment the backend lands each of: S2.5 three-tier re-key · board
rejected-arm widening · §16.7 pickup/return columns — fan out per-screen workflows concurrently
(Sean's directive). Client consequences of the rulings, decided and not re-litigable:
- Three-tier chat: signed-up-unpaid viewers get a READ-ONLY chat state — input replaced by an
  honest 「참여는 결제 후에」 affordance, never a dead input. Roster/pictures surfaces gate on
  NOTHING (public). Ambiguous read/participate surfaces (reactions, self-marking) → console.
- OPEN-A: approved-unpaid holds a slot 20 min; expired hold releases signup + reader access
  together — surfaces must not make that ambiguous.
- All new club screens at 15pt (ruled; the legacy sweep already landed 08-27). Avatar-dot
  initials exempt as glyphs. Kicker exemption is latin-only.
- `club_flags.club_delegation_v2` stays false on production — build behind it; flip is Sean's.

**U4a — host's rejected-dog remedy** (console section over `session_reconsider_dog`, mapping the
non-idempotent 23505 to honest copy) — BLOCKED on the backend's board rejected-arm widening
(hosts can't read rejected dogs' names until then; a direct-select workaround was sketched but
the widening is the real door).

**Post-deploy cleanup (sequenced behind the backend's ONE deploy, it will ping):** remove the
dead `clubName` param from `club/session/[sid].tsx` (~:1444) — it is NOT dead until the deploy;
removing it early regresses every map masthead. Then sim-verify the pack map live end-to-end.

**Standing small items:** smoke-list upkeep (10 ⬜ rows await fixtures/deploy) · DESIGN.md notes
you own (ClubTag inversion note if not landed) · dim-text judgment passes stay PER-SITE human
judgment, never grep-driven.

## Design laws (extract — DESIGN.md wins)

White grounds everywhere; accent #6C5CE7 accent-only; night #1C1837 ceremony world stays.
15pt floor product-wide (kicker exemption latin-only; glyphs/serials exempt). Display font once
per screen; Oswald numerals lineHeight ≥1.2×; no small white text on coral/sage without an ink
plate; holo budget monogram + one edge. Honesty laws: bind real fields or omit; failures shown
as failures; no dead buttons; gate on rawStatus; celebrations once per entity; any catch that
renders user-visible text is a second product surface. KST via `src/lib/kst.ts` only. English
everywhere except in-app user-facing content. Labs in `docs/labs/`, Sean picks by number.
DO-NOT-REFACTOR: fitness hero, meetup stage machine, the three availability predicates.

## Gates, sim, codex

- Before every commit, from `app/`: tsc, check-rpc-contracts, check-route-native-imports,
  check-definer-acl. `npm test`: exit code + per-suite summaries (`^PASS` UNDERCOUNTS — one
  suite prints ✅ lines). Commits via `git commit -- <paths>`; read back from origin after push.
- **iOS sim (Sean's directive):** use the in-Claude simulator tools; `attach` EARLY when Sean
  would want to watch; verify yourself headlessly (screenshot/tap) — never ask him to check.
  Release builds only from worktrees (Debug silently loads a peer's Metro bundle) via the local
  xcodebuild route in `docs/setup-new-machine.md` §3; prove a fresh ASCII literal in the Hermes
  bundle when in doubt. Sim-verified or say UNVERIFIED with a smoke row. **No hardware build
  before the backend's deploy lifts the freeze** (PrivateOnly = pack map dead until then).
  If the sim app is signed out, report to the announcer for Sean — never authenticate yourself.
- Codex gate on every slice: frozen git-init'd export, `gpt-5.6-sol` xhigh, `FINDINGS: <n>`
  digit detector on stdout, failure strings only in stderr's final ERROR lines, quota wall →
  honest UNREVIEWED + retry. /autoplan fronts anything money-path or migration-touching.
