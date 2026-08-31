# Sean rulings — 2026-08-31 (via announcer console, structured options)

Both answered 2026-08-31, Sean picking from explicit options. Verbatim option labels chosen.

## 1. Club detail-text floor: 「15 everywhere」

Question: new club-v2 screens (delegation spec v2, §16.7 setup screen) at 14pt (matching the
eight legacy club screens) or 15pt (the product-wide floor)?

**Ruling: 15 everywhere** — new club screens built at 15pt, AND a sweep raising the eight legacy
club screens (clubText.stateStrong/body/dim/vkTitle, mastSub in club-ui.tsx:360-377, ~52 sites in
club/session/[sid].tsx) to match. This closes the club-world exception noted in CLAUDE.md
§Design system and DESIGN.md:145-152; the club world no longer ships below the floor.

Owner: UI session (master-ui-prompts-docs-6c8c89) — new screens immediately; the legacy sweep is
a scheduled slice (respect the hierarchy law: raising a floor is not find-and-replace, kickers
may need to move further, per the owner-home precedent DESIGN.md:147-152).

## 2. club_end_pack_runs: 「Wire it」

Question: the deployed host 러닝 종료 RPC (0144_club_pack_run_end.sql:290) has zero client
callers, so a runner's own client values price the ledger (codex run-end REJECT finding). Wire or
retire?

**Ruling: Wire it** — the host gets a 러닝 종료 button on the console/run screen;
server-authoritative distances price the ledger. This un-blocks U4c (UI session) and closes the
codex run-end finding as build-the-caller, not won't-fix. The 0144 client obligations noted in
the handoff (blocked on a payload field) ride along — backend session owns any payload gap.

### ⚠ Correction, same day (announcer): the legacy-sweep half of ruling 1 was ALREADY DONE

The UI session's floor-sweep scout found — and the announcer verified at origin — that the legacy
club 15pt sweep landed 2026-08-27 (`4f4bbed` 69 files; `aa48f02` 71 club session/console sites;
`club-ui.tsx` stateStrong/body/dim/vkTitle all read 15 on trunk today). The ruling's premise came
from a stale CLAUDE.md extract carried into the master prompt. **The live half of ruling 1 stands:
new club-v2 screens are built at 15pt.** The sweep half is closed as already-landed, not as new
work. (The stale extract in CLAUDE.md §Design system is the same class as the 「Sean pushes」 line —
a doc drifting behind the artifact.)

## 3. Floor judgment items (2026-08-31, structured options — the sweep's true remainder)

- **Avatar-dot initials: 「Glyph — exempt」.** A one-letter initial inside a DogDot/Monogram is
  identification, not prose; computed 7–14.4pt sizes stay. The floor does not apply.
- **club/delegate:277 「CONSENT · v1 — 不變」: 「Drop 不變」.** The kicker becomes pure latin
  (「CONSENT · v1」) and rides the exemption cleanly. CJK never rides the kicker exemption — rule
  unchanged, string fixed. Owner: UI session (one-line copy change).
- **ClubTag 16/800 beside stateStrong 15/800: 「Leave as is」.** Pre-existing inversion, noted in
  DESIGN.md rather than fixed. Owner: UI session adds the DESIGN.md note; no code change.

## Operational note, same day

GitHub Actions is DOWN for this repo on a billing block: push cbe8af7's jobs (deno-edge,
sql-harness, client-gates) were "not started — recent account payments have failed or your
spending limit needs to be increased." Sean's to fix (GitHub → Settings → Billing & plans). Until
fixed, CI greens/reds mean nothing (jobs don't run); the local commit gates + harness + read-back
remain the only bar, which per house law they already were. Do not read the absence of a CI red
as a green.
