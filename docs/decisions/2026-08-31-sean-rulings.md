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

## Operational note, same day

GitHub Actions is DOWN for this repo on a billing block: push cbe8af7's jobs (deno-edge,
sql-harness, client-gates) were "not started — recent account payments have failed or your
spending limit needs to be increased." Sean's to fix (GitHub → Settings → Billing & plans). Until
fixed, CI greens/reds mean nothing (jobs don't run); the local commit gates + harness + read-back
remain the only bar, which per house law they already were. Do not read the absence of a CI red
as a green.
