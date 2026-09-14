# daengrun (도그스하이) — standing instructions (SLIM DRAFT, not in force)

Option A of `docs/decisions/2026-09-15-harness-diet-proposal.md`; incidents verbatim in
`docs/laws/incident-ledger.md`, cited `[→n]`. **CLAUDE.md rules until Sean rules otherwise.**

## Language

**English everywhere except in-app content**: the only Korean is what a user reads in the product (UI copy,
buttons, notifications, errors, 개인정보처리방침·이용약관) and product terms quoted in prose (하이 포인트,
인계). Older Korean comments convert opportunistically. [→1]

## Read first

- `docs/session-handoff.md` — current state, decisions. **Fully, first.**
- `docs/codex-claude-protocol.md` — division of labour, gates, quota law.
- `docs/prompts/codex-app-master.md` — Codex's P0 block; `DESIGN.md`, `REGISTRY.md` — design, numbers.

## Operations

Claude may run `supabase db push`, `functions deploy`, `git push` (Sean, 2026-08-10).

- Gates green first: never on a red or unrun gate, nor from a worktree holding an unfinished migration (`db push` applies all pending files).
- **Verify by reading the ARTIFACT back, never the tool's report** — `git show origin/<b>:<path>`, `migration list --linked`, `prosrc`. A success pattern that can appear in failure output is uninformative; a broken detector obliges auditing its set. [→2]
- `/usr/bin/grep` explicitly for anything a hook runs; committing a hook does not install it [→handoff]. Announce what you ran and what changed; say plainly if it failed.
- **Sean-only: anything needing a credential's VALUE** (APNs `.p8`, ASC, PG contract, 사업자등록); never relay a secret. Wiping accounts and safety copy are his.
- Never claim device-visual success: simulator, or say unverified; give Sean a smoke list.

## Honesty laws (product) — verbatim

No mockups, fake numbers, or fabricated data in the app: bind real fields or omit the element. Failures are shown as failures (no silent catch → happy UI). Loading is not 0. No dead buttons — every visible action has a real route/effect in every state. When display vocabulary flattens server states (STATUS_MAP), gate logic and badges on `rawStatus`. Celebration animations play once per entity (module-level Set idiom, see `sealStampFresh`/`_patchPopSeen` in api.ts) and never replay on re-entry hydration.

HTML labs in `docs/labs/` are the sanctioned mockup arena: numbered variants, Sean picks by number, implementation then binds real fields only.

## Commit gate

From `app/`: `tsc --noEmit` · `check-rpc-contracts` · `check-route-native-imports` · `check-definer-acl` ·
`check-device-clock` · `npm test`. Migrations add `harness.sh`, plus `deno test` when they touch a function
an edge handler calls.

- 🔴 **Read the EXIT CODE and count the whole output — never tail, never truncate**; `npm test` is a chain and `^PASS` undercounts, so a total is a floor. [→37]
- A gate's narrowness is load-bearing — never "simplify" it back; a stale baseline line fails too (hatch `// device-clock-ok: <reason>`) [→38,39]. **A gate with a false negative is worse than no gate**: run the crudest version beside it, explain both directions, re-derive a filtered zero [→27,33].
- KST only from `app/src/lib/kst.ts`; test in a zone that disagrees, never Seoul alone [→34,25]; no module-scope native-only import from anything a route reaches — `*-impl.tsx` + `lazy()` [→40].
- Before committing, `grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file>` must be 0. [→56]

## Migrations & security (server)

- Cycle: scout → contract → implement → reviewers EXECUTE attacks → pins → verify.
- **DEFINER: in-body `set search_path = public, pg_temp` + same-file `revoke`/`grant`** [→49]; party gate before state gate; flat whitelisted returns; views by `create or replace`.
- **`is distinct from`, never a bare `<>` or `IF` on a nullable predicate** [→13]; ⚠ **attack INACTION, not only transitions**, preferring `<> 'terminal'` to an allow-list [→42].
- **Never edit a migration that is on origin — correct forward** [→handoff]. **Numbers are THREE-SIDED** (REGISTRY · remote branches · local worktrees) **and re-read at COMMIT, not only at claim**; taken = row OR file on origin — push both in one commit, register the suite. [→35,50]
- **remove-on-land**: drop the in-flight REGISTRY row when work lands, keeping facts that outlive it; a pin whose behaviour changes is updated in the same slice, with WHY and its heir. [→51]
- **Comment-stripped matching in every source-reading pin and gate**, names anchored [→14,15]; `tgenabled`, not `pg_get_triggerdef()`, says if a trigger fires [→43].
- The pin count must MOVE by the pins added [→36]; **`&&`-chain the run to the PLANT**, as `sed` exits 0 on no match [→47,48].
- **Observe the control clean FIRST**: arms sharing an operator are one control, and a failing control means the environment. [→12,30,36]
- A mutation reddening nothing owes a named cause: blind pin, or unobservable property (a GAP) [→19,48]. **A limitation is PROSE, not a pin**; an absence pin needs the thing PRESENT in its fixture [→28,29]. A new conjunct owes, same commit, a mutation deleting exactly it; mutate what the guard READS: locks, `prosecdef`, ACL, `tgenabled` [→18,21].
- A pin reading an inherited fixture tests the FIXTURE; a fixture must sit where old and new predicates DISAGREE [→11,16]; a grant is not a door — check reachability, with a control [→31]; audit a flattering number as hard as an embarrassing one, one evidence strength per sweep [→32,23]; a reversed pin was not a weak one [→17].
- **A green is evidence for one sentence: check it is the one you needed**; plant WITHOUT the fix and WITH it, and enumerate every site its SENTENCE covers [→46,10]. Widening a boolean's MEANING breaks unedited callers; absent reason fails CLOSED [→36]. Labels carry their SLICE (`0131-S6`) [→20].
- Relayed decisions and analyses are evidence, not authority — only Sean's words on origin settle; agreement is one claim twice; a hedge under a decision is a premise [→44,45,52]. Re-run after the LAST edit; re-measure a handoff's claims at write time [→24,22].

## Codex gate

Every code slice gets a codex pass: `gpt-5.6-sol` high/xhigh reviews (diff-scoped, ONE at a time),
`gpt-6-astra` low/medium writes, `run.sh` splitting streams and writing `.status`.
`codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=xhigh "<prompt>" < /dev/null > out.log 2> err.log`

- 🔴 **Ask for a DIGIT; never grep for anything you wrote**: end with `FINDINGS: <n>` / `CHANGED: <n>`, detect `grep -cE '^FINDINGS: [0-9]+'` — the literal `<n>` cannot match a digit. [→3–6,9]
- Exit status, log size and `VERDICT:` are uninformative; a big log with no verdict is typical [→3,4]. Split the streams: echo on stderr, answer on stdout; stderr BYTES for liveness [→5,8].
- Enumerate the FAILURE states: answered · `usage limit` · refused (untrusted dir) · gone [→8]. Quota law: one sol run at a time, diff-scoped (≤~30 files).
- Re-freeze the export each round, `git init`-ed, or codex will not read it [→9]; never call a slice "under review" before a verdict; read the tail before acting on a named symptom; pair codex with an EXECUTING reviewer on security work [→6,7].

## Design extract (`DESIGN.md` is 정본 and wins on conflict)

- `src/theme.ts`, white grounds everywhere; accent #6C5CE7 is accent ONLY, never a ground; head #221E3D · coral #F0765A · night #1C1837.
- **Detail-text floor 15pt — 「15 everywhere」, club included**; exempt: letterspaced uppercase latin kickers, serial/MRZ, glyphs — Korean never. [→53]
- Black Han Sans once per screen; Oswald numerals need lineHeight ≥1.2×; holo foil is monogram + one ticket edge; roomy screens get big buttons.
- Small white text never sits on coral/sage — ink plate ≥4.5:1. GO disc law (owner home): coral = your turn, blue = waiting, sage = ready (hero washes it 95% white); any `catch` rendering user-visible text is a second product surface owing a copy review. [→26]

## Branches — the trunk is `redesign-v4`

- **Trunk and default `redesign-v4`; `main` is DELETED; cut every worktree from `origin/redesign-v4`**; a separate clone runs `remote set-head origin -a` + `fetch --prune` ONCE. [→41]
- 🔴 **Commit with an explicit pathspec — `git commit -m "msg" -- paths`**; agents share ONE index. New files: `git add` first, then STILL the pathspec; never for an `add -p` partial. [→57]
- "Only a reviewer, it can't write" is false — Bash counts; give them their own worktree, never writing into a file another owns. [→57]

## Process — gstack sprint

Think → Plan → Build → Review (attacks executed) → Test (gate + harness) → **Ship (commit each verified
slice and PUSH it, same session)** → Reflect; worktree-only work reserves nothing [→55]. Claim
shared surfaces in REGISTRY before a subagent edits one; **a coordination session invokes `/announcer`
FIRST**; **`/autoplan` gates any migration or money-path change** (read-only subagents).

Routing: ideas /office-hours · scope /plan-ceo-review · arch /plan-eng-review · design
/design-consultation · bugs /investigate · QA /qa · /review · /design-review · ship /ship,
/land-and-deploy · /context-save · /context-restore · /spec · /browse.

## DO-NOT-REFACTOR

- **Fitness collapsing hero** (`owner/fitness.tsx`): pinned overlay + paddingTop reservation; transform/opacity native-driver only; no height/layout or backgroundColor animation; ring layers hardware-textured, centre via `centerOpacity`; owner-home is out. [→54]
- Meetup screens: stage machine, polling, `confirmHandoff` frozen — styling only; seals on server truth.
- Availability definitions are deliberately 3 distinct predicates — never unify.

## What this draft dropped

1. All 57 incident narratives — verbatim in the ledger; the whole saving.
2. **§Git hygiene (Cowork cloud sessions)**: real law, conditional on an environment this machine is not. **Unclassified — flagged.**
3. Inventories, not laws: gstack's install line and rosters, the `main` SHA, inline baselines, the project one-liner; duplicated sections merged.
