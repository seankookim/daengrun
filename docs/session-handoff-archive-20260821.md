# Session handoff — announcer v3, 2026-08-19 evening → 2026-08-20 (overnight + Codex pairing)

**Read with this:** `/announcer` (method) · `docs/handoff-codex/README.md` + its **7 domain reports** (~10k lines,
the single best briefing that now exists) · `docs/decisions/awaiting-sean.md` (**35 sections**, §0-* head = Sean's
queue) · `docs/fleet-roster.md` §7/§7-bis (54+ method lessons) · `supabase/migrations/REGISTRY.md` (the ledger) ·
`CLAUDE.md` (the laws). Prior handoff archived at `docs/session-handoff-archive-20260820.md`.

Tags: **[verified-now]** checked this session against code/gate/live · **[reported]** an agent said so, I did not
confirm · **[from-history]** earlier in conversation · **[uncertain]** inference.

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Trunk `origin/redesign-v4` | `13749af` at write time; moves every few minutes (5+ live sessions) | [verified-now] |
| Migrations applied in production | **0001–0104, 0106–0115**. `0105` exists nowhere (rejected, deleted by 0111). `HELD` is empty | [verified-now] `migration list --linked` |
| Next free | migration **0116**, suite **151** — re-resolve two-sided at write time | [verified-now] |
| Edge functions deployed (8) | create-booking-hold **v10** · transition-booking **v34** · settle-run v14 · open-drop v8 · geocode-address v1 · collect-charges v1 · confirm-payment v1 · **delete-account v1** | [verified-now] `functions list` |
| Charging | **OFF** — `payments_live_since` null · payments **0** · billing_keys **0** (plus TOSS_SECRET_KEY unset, Vault secret absent) | [verified-now] |
| Harness | **723/0** on the 0115 branch; 66 suites registered on trunk | [reported] for 723; suite count [verified-now] |
| Deno tests | 217/0 after the 0115 fix round | [reported] |
| App builds | **ZERO ever** (`eas build:list` → `[]`). Nothing has run on hardware | [verified-now] |
| Main checkout | **Was** mid-merge with 2 conflicts + 103 staged files; **now RESOLVED, clean, HEAD on trunk** | [verified-now] |
| Rescue backup | `/Users/sean/dev/daengrun-rescue-2026-08-20/` (157 MB tgz + status/staged-stat/head) — safe to delete once someone confirms nothing was lost | [verified-now] |

## 2. Goal & current state

Pre-revenue Banpo pilot. PMF gate = 60% M1 rebooking. This session was **coordination**, not building: route verified
facts between parallel sessions, hold Sean's queue, and run the server slices nobody owned (trust/money/catalog/legal
all went offline during the night).

| Workstream | State |
|---|---|
| /cso audit P0s | **All four closed at their boundaries.** 0111 (booking entry) + 0114 (party membership) finished the last one |
| Account deletion (App Store 5.1.1(v)) | **DONE, live, verified 38/38 over the wire** — 0115 + `delete-account` v1 |
| Pay-after-run | **DONE end to end** — server v34/v10 + client `5638037` |
| Route privacy sequence | **DONE** — 0107 → 0110 → client switch → 0112 → 0113; promotion unblocked, never run |
| Flip-blockers (4 money/server defects) | **IN FLIGHT** — agent building `claude/p0-flip-blockers`, migration 0116; Codex reviews before landing |
| M1 gauge | **FIXED** `f82e779` |
| Brand identity round | Research done (4 agents); **synthesis lab never delivered** — that session ended |
| Codex pairing | Live and productive (`gpt-5.6-sol` xhigh, already the CLI default) |

## 3. What shipped this session (by theme)

**Security / server.** `0109` TRUNCATE+TRIGGER+REFERENCES revoke (two review rounds; Codex found the grantor gap and
one-directional pins) · `0111` booking-entry rebuild superseding the rejected 0105 · `0112` no client DML on any view
(**a live P0 the announcer found: anon could UPDATE/DELETE catalog rows through a definer view**) · `0113` base-table
trace revoke · `0114` party membership narrowed to accepted states, closing /cso #2's last half · `0115` account
deletion. All deployed via `scripts/deploy-migrations.sh` and verified live.

**Mechanism, not discipline.** `scripts/deploy-migrations.sh` + `supabase/migrations/HELD` — cuts a detached tree at
trunk, moves held files aside, dry-runs, and **refuses to push anything you did not name by exact filename**.
Built because `--include-all` would have shipped a held migration as cargo under someone else's name.

**Handoff corpus.** `docs/handoff-codex/` — 7 reports: server (69 tables, 190 definers, 64 unbuilt, 35 traps) · money
(both ledgers every scenario, 40 unbuilt, 15 reconciled contradictions) · catalog (44 unbuilt, 12 traps) · legal/ops ·
marketing (11 traps) · product-and-process (**40 Sean rulings verbatim** + 18 retracted, 168 unbuilt) · README.

**Fixes.** M1 gauge (`f82e779`) · bundle ID → `com.seankookim.dogshigh` (`b6ee192`) before the first upload locks it.

## 4. Standing doctrines (canonical: `CLAUDE.md`, `docs/fleet-roster.md`)

1. **Verify at send time; never relay.** A claim from another agent is evidence, not authority. Say measured / reported / inferred.
2. **Closure = the unauthorized operation refused at the server boundary**, never "the UI no longer exposes it".
3. **Reviewer ≠ author, and reviewers EXECUTE attacks.** Mutation-test every pin — a pin green with its fix deleted is theatre (3 instances this week).
4. **Migration numbers two-sided from origin at write time**; land on trunk before deploy; deploy only through the wrapper.
5. **Honesty laws**: no dead buttons, refusals rendered as refusals, loading ≠ 0, bind real fields or omit. **Never claim device-visual success.**

## 5. Working-relationship norms

Sean writes short and decisive ("sure", "B", "do M1 and bundle the flip-blockers"), and his latest word governs. He
**picks by looking** (labs by number, screenshots) and dislikes being asked to choose between things he cannot see.
He grants broad autonomy and expects gates instead of permission — but **irreversible or physical things stay his**
(Apple 2FA, dashboard toggles, credential values, anything that locks). He wants **plain-language reports under a
`–––––REPORT–––––` banner with lettered answer choices**. He retracts sometimes ("i never said…") — record his words
verbatim with `[end of his words]` and mark stand-in decisions **🔵**, never ✅.

## 6. Decision log with WHY

- **Pay-after-run**: `payment_ok` deleted in ONE move, not two — the old client never calls it (measured), shipped population is zero. **Rejected**: a compatibility shim for a code path nobody executes.
- **O-7 bank accounts (Sean)**: keep the row **intact, not blanked**, when a runner has earnings. **Rejected**: gating deletion on balance — "unpaid" is uncomputable (`payouts` has no writer), so a gate could never clear, trapping the runner and re-opening App Store 5.1.1(v).
- **O-4 party membership**: narrow chat/reviews/notifications to accepted states; give incidents a **wider** set (accepted + cancelled_owner + refund_pending) — a party who *was* accepted may still report a safety event.
- **`club_custody` split into two tokens**: one holder-side, one owner-side, because a refusal must name a remedy its reader can perform. An owner cannot "finish the handoff".
- **Deep-link `detail` field RETRACTED from the 0115 round** — it needs `_shared/ctx.ts`, the error contract of **24** functions; a scope change to a reviewed round is worse than a missing feature. Now its own slice (§0-unvicies).
- **Sean chose B** on Codex's 30-day read: keep building, Build 0 later. Its other two risks are **deferred, not closed**.
- **Refusals**: I declined to resolve another session's merge conflicts blind (backed it up instead); declined to widen a client session's domain onto `supabase/` on my own authority (**ownership vacancy is not authorisation**); declined to rule the club fee ladder.

## 7. Architecture & contracts (deliberate things that look wrong)

- **Ordering that bites**: realtime policies → client private → `private_only`. Migration before its edge function. `routes_public` view → client switch → base-table revoke (revoke-first = catalog outage, the 0088/0091 shape).
- **DO-NOT-REFACTOR**: fitness collapsing hero (owner-home was released) · meetup stage machine · three availability predicates.
- **Client render-tree facts** (`docs/handoff-client.md` §7): owner home's header is **not** pinned — reintroducing an absolute header brings back plate bleed-through; `StatusBarCover` must stay mounted **last**.
- **Cross-layer**: `chat.tsx`'s permanent-refusal copy keys on **42501** surviving `ensureThread`'s rethrow. Don't replace that error.
- `create-payment-intent` exists locally and is **NOT deployed** — establish dead code vs dependency before touching payments.

## 8. File map

`docs/handoff-codex/*` (7 reports + README) · `docs/decisions/awaiting-sean.md` (the queue, 35 sections) ·
`docs/fleet-roster.md` §7-bis (method lessons) · `supabase/migrations/0109,0111–0115` + suites 144,146,149,150 ·
`supabase/migrations/HELD` + `scripts/deploy-migrations.sh` (**the only sanctioned deploy path**) ·
`scripts/pilot-metrics.mjs` (M1, fixed) · `docs/contracts/{pay-after-run,party-membership-status-filter,account-deletion,booking-entry-rebuild}-contract.md`.

Harness: `PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C bash <ABSOLUTE>/supabase/tests/harness.sh` — absolute path only.

## 9. Pending on Sean

**Ops (only he can do):** two dashboard toggles (email provider OFF; redirect allowlist → `daengrun://login` only) ·
TestFlight 2FA (**bundle ID now fixed, so this is safe to do**) · forward two counsel briefs (location-law v5 +
contract-status) · one real signup on a phone (§0, the front door, never verified).

**Decisions (each blocks something):**
- **Club cancel-fee ladder** — which of two ladders governs. *Blocks*: the F2 half of the flip-blocker slice.
- **`§0-sexvicies` orderName** — approve 「도그스하이 러닝 이용료」/「…예약 취소 수수료」; today the charge path prints the retired 댕런 and the banned 산책 onto card statements. *Blocks*: nothing today, everything at flip.
- **`§0-quinvicies`** — may a client session touch `supabase/` for the one deep-link slice? *Blocks*: that slice only.
- **`§0-undecies`** — routes_public trim distance + whether logged-in = anon (catalog defaulted both 🔵).
- **`§0-decies` D1/D2** — is pre-acceptance contact a feature or a leak (0114 narrowed it; the shape is his).
- **Look-and-pick**: route names that advertise the wrong length (A/B/C) · run.tsx R4 coral-vs-volt · legacy feed labels · his stale Aug-4 fixture.
- **The 9 runners**: did he actually video-verify them? `identity_verified=true` sits behind copy promising it.

## 10. Known bugs, gotchas, false-success producers

`db query` multi-statement returns only the LAST row-producing statement · `do $$` auto-commits · bare column REVOKE
under a table-wide grant is a no-op · **views are definer by default and single-table views are auto-updatable** (the
0112 P0) · `service_role`'s table-wide SELECT cannot be fenced by a column revoke · `create or replace` wipes
ALTER-applied `proconfig` · harness `$0` self-pin needs an ABSOLUTE path · **`.githooks/pre-commit`'s react-doctor
block cannot fail a commit** (no `exit 1`) [reported] · **unquoted `git commit -m` lets the shell eat backticked
identifiers** — use `-F -` with a quoted heredoc (bit me twice, including inside perl) · a **grep for a name that never
existed returns 0 and looks like proof** · a **truncated `head` makes a false negative sound confident** · a screen's
type budget is a **render-tree** property, not a file property.

## 11. Known-good — do not "fix"

Money paths (amounts never client-supplied; four independent off-switches) · all 190 definers `search_path`-pinned
in-body · the deploy wrapper + HELD · 0114's twelve-token refusal set and its two-directional pins · the
`routes_name_km_agrees` constraint (it is doing real work) · `run2-` topic namespace · the honesty states ui shipped.

## 12. Ideas discussed, not built

Brand-identity synthesis (research done, lab never delivered — ~18 tensions incl. blue meaning three things, 4
DESIGN.md colours with zero code uses, App Store icon on the retired palette) · payout mechanism (6 pieces specified
in `money-domain.md`) · location purge cron + 위치정보 access ledger (statutory; copy `club_phone_access_log`, **not**
`gate_code_access_log` — that one has never had a writer) · 맹견 gate · versioned consent · ops dashboard · push
emitter (nothing emits today) · moderation for the feed · the deep-link `detail` slice · i18n (absent, discussed nowhere).

## 13. Strategic read

**The fleet's engineering discipline is now better than its contact with reality, and that gap is the risk.** Six
migrations, four P0s closed, ~10k lines of handoff — against zero builds, zero interviews, zero customers. Codex named
it independently and I agree with it. Sean chose to keep building (B), which is his call and defensible while the
native surface is genuinely unfinished — **but every additional week of server rigour compounds the same unknown**:
nothing in this product has ever run on a phone. If he pushes back, my argument is narrow: **a build is a test
artifact, not a release commitment**, and the first one will produce a blocker list nobody can currently predict.
Second: the flip-blockers are the right slice to finish because they are cheap now and expensive after money moves.
Third: **stop adding queue items faster than he can answer them** — 35 sections is past the point where a queue helps.

## 14. Next 1–3 steps

1. **[read-only]** `git fetch && git log --oneline -5 origin/redesign-v4`; `supabase migration list --linked`; confirm 0116 free two-sided. **Verify the flip-blocker branch state first** — `origin/claude/p0-flip-blockers` may exist by now.
2. **[needs-deploy]** When that agent reports: **Codex reviews it adversarially** (`codex exec … -s read-only`), fix what it finds, land on trunk, deploy via the wrapper, verify live, record in REGISTRY.
3. **[needs-user]** Put the club fee ladder and the orderName wording in front of Sean — both block work that is otherwise ready.

## 15. Verification commands

**Safe:** `supabase migration list --linked` · `supabase functions list` · `supabase db query --linked "select …"` (one
statement per call) · `bash scripts/deploy-migrations.sh` (dry-run, prints the pending set) · `node scripts/pilot-metrics.mjs`
(read-only) · the harness by absolute path.
**Expensive/irreversible:** `scripts/deploy-migrations.sh --push <names>` · `supabase functions deploy <slug>` ·
any `delete-account` invocation (**deletes a real auth user**) · `eas build` (Sean's 2FA).

## Environment & test data left behind

**None on production** — every probe used throwaway accounts and verified its own cleanup (profiles back to 10,
`account_deletions` back to 0, no tombstones). Local: harness postmasters may be running under
`.claude/worktrees/*/supabase/tests/.pgtest`. `/Users/sean/dev/daengrun-rescue-2026-08-20/` is the rescue backup —
delete once someone confirms the resolved merge lost nothing.

## Agent work at handoff

**Running:** the flip-blocker implementer (`claude/p0-flip-blockers`, migration 0116 — F1 return-seal guard, F2 club
cancel-fee plumbing, F3 dispatch drift, F4 four unscoped definers). Its output lands on that branch; it was told not to
deploy and to STOP on F2 if the fee ladder cannot be plumbed without Sean's ruling.
**Completed:** 7 domain reports · the 0109/0111/0114/0115 review-and-fix rounds · three live production probes.
**Coverage gaps:** the client/brand session ended before delivering its report — `docs/handoff-codex/` has **no
client-domain report**, and the brand synthesis was never produced. Everything device-visual is unverified by me.
