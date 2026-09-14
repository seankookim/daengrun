# Codex app — master prompts for Sean (astra low/medium builds)

Written 2026-09-15 on the new Mac. These are the prompts you paste into the **Codex app**
yourself. Codex writes the code; Claude (the orchestrator session) scouts, writes contracts,
runs the gates, verifies on the simulator, and lands on trunk. Read
`docs/codex-claude-protocol.md` once for the division of labor; this file is the paste sheet.

**Model routing (yours, 2026-09-15):** `gpt-6-astra` **low** for mechanical edits, **medium** for
feature slices front and back. `gpt-5.6-sol` only when a task below says so. Codex credits are
finite — measured today: three parallel sol-high whole-repo *reads* burned ~673K tokens and
returned nothing. Every prompt here is scoped to a slice, never to the repo.

**Rule for every Codex session:** it works on its own branch `codex/<slice>` in its own worktree,
commits with `git commit -- <paths>`, pushes **that branch only**, and ends with the report block
in P0. It never pushes trunk, never runs `supabase db push`, never claims a migration number
without the three-sided check in P0. You then tell Claude 「codex/<slice> is ready」.

---

## P0 — session boot (paste first, every time; then paste one task prompt)

```
You are Codex (gpt-6-astra) building daengrun (도그스하이), a React Native/Expo + Supabase dog-running
marketplace. Repo: /Users/seankim/dev/daengrun, trunk branch redesign-v4. You are paired with a Claude
session that lands your work; you build, it gates and ships.

Setup for this session:
1. git fetch origin && git worktree add /Users/seankim/dev/daengrun/.claude/worktrees/codex-<slice> -b codex/<slice> origin/redesign-v4
   and work ONLY inside that worktree. Symlink node_modules: ln -s /Users/seankim/dev/daengrun/app/node_modules <worktree>/app/node_modules
2. Read CLAUDE.md sections: Language · Honesty laws · Commit gate · Migrations & security (the bullets, skip the incident narratives) · Design system. Read docs/session-handoff.md header only.
3. Laws that are not negotiable: English everywhere except in-app Korean copy. No mockups or fake data — bind real fields or omit the element. Failures render as failures, loading is never 0, no dead buttons, gate badges on rawStatus. KST via app/src/lib/kst.ts only. 15pt floor for Korean text. Accent #6C5CE7 is never a ground. SECURITY DEFINER functions: in-body `set search_path = public, pg_temp`, explicit same-file revoke/grant, party gate before state gate, `is distinct from` never bare `<>`/IF on nullable predicates. Never edit a migration that is on origin — correct forward with a new one.
4. Migration/suite numbers: take the next free number by reading origin at WRITE time — `git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3` and the same for supabase/tests/ — and check every other branch: `for r in $(git branch -a --format='%(refname)'); do git ls-tree --name-only -r $r supabase/migrations supabase/tests | grep -E '/(NNNN)_'; done`. Add the REGISTRY.md row in the same commit as the file. Register a new suite in supabase/tests/harness.sh at the tail.
5. Before you say done, from <worktree>/app run: ./node_modules/.bin/tsc --noEmit · node scripts/check-rpc-contracts.mjs · node scripts/check-route-native-imports.mjs · node scripts/check-definer-acl.mjs · node scripts/check-device-clock.mjs · npm test (read the EXIT CODE, count ^PASS and ^FAIL across the whole output). For any migration: from <worktree>/supabase/tests run PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=C bash harness.sh, read the final `N pass / M fail` line, then stop the cluster: pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast. For edge functions: from supabase/functions run deno test --allow-all --node-modules-dir=auto _test.
6. Commit with `git add <paths> && git commit -m "<what and why>" -- <paths>`. Push ONLY your branch: git push -u origin codex/<slice>. Never push redesign-v4. Never run supabase db push or functions deploy.
7. End with exactly this report, nothing after it:
   FILES: <list>
   GATES: tsc=<exit> rpc=<exit> route-native=<exit> definer-acl=<exit> device-clock=<exit> npm-test=<exit> PASS=<n> FAIL=<n> harness=<n pass / m fail or SKIPPED: reason> deno=<passed/failed or SKIPPED>
   UNVERIFIED: <anything you could not prove — say it plainly; a claim you did not measure is not a claim>
   BRANCH: codex/<slice> @ <sha>
   CHANGED: <number of files changed>
Task follows.
```

---

## Backend tasks (astra medium unless marked)

### P1 — chat idempotency, schema half (astra low)

```
Slice: chat-idempotency-schema. The client half landed on trunk at 2b63484: app maps a 23505 on chat message insert to success (verify by reading app/src/lib/api.ts and app/app/chat.tsx for the 23505 handling; if it is NOT there, stop and report — do not build the client half). Build the server half as ONE migration:
- alter table chat_messages add column client_key uuid;  (nullable — legacy rows and any writer that does not send one)
- create unique index concurrently is not allowed inside a migration transaction here; use a plain partial unique index: create unique index chat_messages_thread_client_key_uni on chat_messages(thread_id, client_key) where client_key is not null;
- Read the existing chat insert path (RPC or direct insert — find it: grep -rn 'chat_messages' supabase/migrations | tail; grep -rn "from('chat_messages')\|chat_send\|send_chat" app/src) and thread client_key through whichever writer the client uses, so the client's key actually reaches the row. If the writer is a SECURITY DEFINER RPC, adding a parameter means create or replace with the full ACL block in the same file (see 0160_pack_publish_hardening.sql for the house shape).
- Suite: one small SQL suite with three pins: duplicate (thread, key) refused on SQLSTATE 23505; same key in a DIFFERENT thread admitted; NULL key twice admitted (legacy writers unaffected). Follow the shape of supabase/tests/192_billing_keys_grants_suite.sql (short suite, `_t` insert per pin).
Do not touch any other table. Report per P0.
```

### P2 — `runner_booking_rules` CHECK constraints (astra low)

```
Slice: runner-rules-checks. Read supabase/migrations for the runner_booking_rules table (grep -ln runner_booking_rules supabase/migrations/*.sql) and the editor in app/app/runner/ that writes it (grep -rn runner_booking_rules app/app app/src). Identify the TWO columns the SERVER reads when a booking is evaluated (follow the readers in migrations, not the editor). Add one migration with CHECK constraints on exactly those two columns bounding them to the ranges the editor's UI already enforces (read the editor's min/max). Constrain nothing else. If any existing production-shaped row could violate the constraint, add a `not valid` constraint plus a comment saying why, instead of a validating one. Suite: two pins, one refused value per column, plus one accepted boundary value. Report per P0.
```

### P3 — B3: the 0052 board wrapper bundle (astra medium; ruled, contract in the review docs)

```
Slice: board-wrapper-bundle. Sources you must read first: docs/decisions/2026-08-28-codex-verdicts.md (the 0153 REJECT/2 addendum — outer-wrapper envelope + access-model honesty), docs/decisions/2026-08-31-sean-rulings.md ruling 5 (「Narrow it」: 'none' means none), supabase/migrations/0153_board_impl_not_for_clients.sql, and the outer wrapper's CURRENT definition (grep -n 'function club_delegation_board' supabase/migrations/*.sql | tail -1 — the LAST definition wins).
Build ONE migration that:
(a) redefines public.club_delegation_board(...) forward with `set search_path = public, pg_temp` IN THE BODY and an explicit ACL block in the same file (revoke all from public, anon; grant execute to authenticated; verify block asserting has_function_privilege for all three roles);
(b) when the derived access grade is 'none', does NOT call _club_delegation_board_impl at all and returns the contract-compatible empty/refused shape (read what the client expects: grep -rn club_delegation_board app/src/lib/api.ts and the type it decodes — the shape must decode without a client change);
(c) converts session_set_backup's bare `<>` at 0047:308 (verify the line — it may have moved; find it by content) to `is distinct from`, again as a forward create-or-replace with the full ACL block.
Cite ruling 5 in the migration header comment. Suite: stranger with grade 'none' gets the empty shape AND the impl function is provably not called (wrap: temporarily rename? no — assert via a pin that the outer body, comment-stripped with regexp_replace(prosrc,'--[^\n]*','','g'), contains the grade check BEFORE the impl call); host still gets rows (positive control); session_set_backup with a NULL on either side behaves per `is distinct from`. Update app/scripts/check-definer-acl-baseline.txt if the gate tells you a baseline line went stale (delete the stale line, never add one). Report per P0.
```

### P4 — S2.5 three-tier membership re-key (astra medium; the UI-unblocker)

```
Slice: membership-three-tier. Read FIRST, fully: docs/decisions/2026-08-31-sean-rulings.md §4 (OPEN-A 20-minute hold, OPEN-B refined TWICE — final model is THREE-TIER: anyone sees roster+pictures · signed-up-unpaid READS chat · paid participates), and docs/plans/2026-08-25-club-delegation-spec-v2.md §S2.5. Then read the current membership predicate(s): grep -n '_club_session_member\|_club_shell_access\|club_members' supabase/migrations/*.sql | tail -40 and read the LAST definition of each helper.
Build the server re-key as ONE migration: a single helper returning the tier ('none' | 'reader' | 'participant') for (session, uid), used by the chat read policy (reader+), chat write/RPC (participant only), roster/pictures read (no gate — public), and the approved-unpaid hold: a signup approved but unpaid holds its slot 20 minutes from approval, after which the slot releases AND reader access ends together (one predicate, one clock column — never two clocks). Keep every existing RPC signature. All helpers SECURITY DEFINER with in-body search_path and explicit ACL. Everything stays behind club_flags.club_delegation_v2 where the existing code is; do not flip any flag.
Suite: one pin per tier per surface (chat read, chat write, roster) + the hold expiry two-sided (at 19 min reader, at 21 min none) + the money control: a paid participant is unaffected by the hold clock. Report per P0, and list every RPC/policy whose meaning you widened so Claude can enumerate client callers.
```

### P5 — board rejected-arm widening incl. dog-name visibility (astra medium)

```
Slice: board-rejected-arm. Context: docs/session-handoff.md section 「2026-08-28 — a third capability that is NOT a client-only slice」. Today a host cannot see rejected session_dogs rows (only the owner arm admits them) and dogs' RLS has no host arm, so the host's reconsider remedy (session_reconsider_dog) has no rows to act on. Read _club_delegation_board_impl's LAST definition and the dogs table's policies. Build ONE migration that (a) widens the impl's rejected arm so the session HOST (and backup host) reads rejected/withdrawn rows for their own session, (b) adds a dogs SELECT arm for the host of a session the dog is delegated into (name + photo only if the table is wider — if dogs carries fields a host must not see, return name via the board projection instead of widening dogs), (c) leaves strangers at zero rows (ruling 5). Suite: host sees the rejected row (positive), a non-host member does NOT (control), stranger sees nothing; dog name present in the host's board row. Report per P0.
```

### P6 — §16.7 `session_dogs.pickup_mode` / `return_mode` columns (astra low)

```
Slice: session-dogs-modes. Read docs/plans/2026-08-25-club-delegation-spec-v2.md §16.7 for the column semantics and allowed values. Add both columns to session_dogs as text with CHECK constraints on the enumerated values and sensible defaults from the spec; thread them through the delegation RPC that inserts session_dogs (LAST definition; create or replace with full ACL block) as optional parameters defaulting to today's behaviour so no client changes are required; expose them in club_delegation_board's projection. Suite: default insert yields the spec default; an invalid value is refused; the board returns the column. Report per P0.
```

---

## Frontend tasks (astra medium)

### P7 — inline-script safety adoption (astra low)

```
Slice: inline-script-safety. A WebView security fix exists on a rescue branch and never landed: git show origin/rescue/wip-main-clone-chat-slice-2026-08-28 -- app/src/lib/inline-script.ts app/test/inline-script.test.cjs app/test/run-inline-script-tests.sh. Verify it is absent from trunk (grep -rn safeInlineScriptString app/src → nothing). Bring those three files onto your branch as-is, add the run script to package.json's test chain, then find every injectedJavaScript / WebView script string built from user data (grep -rn 'injectedJavaScript\|injectJavaScript' app/app app/src) and route each through safeInlineScriptString. Do not change WebView behaviour otherwise. Report per P0 with the list of call sites converted.
```

### P8 — club-v2 screen fan-out (one prompt per screen, after P4/P5/P6 land)

```
Slice: club-v2-<screen>. Read docs/plans/2026-08-25-club-delegation-spec-v2.md section for <screen>, DESIGN.md (white grounds, 15pt floor, accent-only #6C5CE7, display font once per screen, Oswald numerals need lineHeight ≥1.2×), and the nearest existing club screen as the style reference (app/app/club/session/[sid].tsx). Build app/app/club/<screen>.tsx behind club_flags.club_delegation_v2 (read how the flag is read today: grep -rn club_delegation_v2 app/src). Bind ONLY real fields from the RPCs that exist on trunk (grep the migration for the RPC's return columns) — if the spec wants a field no RPC returns, omit the element and list it under UNVERIFIED. Three-tier consequences: a signed-up-unpaid viewer gets a READ-ONLY chat with the input replaced by 「참여는 결제 후에」 (never a disabled input); roster and pictures gate on nothing. Every error branch renders Korean copy that names the refusal reason from the RPC's error map. No new test infrastructure. Report per P0.
```

### P9 — post-deploy cleanup (only after Claude announces the 0159–0161 deploy)

```
Slice: clubname-param-removal. The pack map's clubName parameter in app/app/club/session/[sid].tsx (~line 1444, find by content) became dead when club_pack_publish went live server-side. Remove the dead parameter and any plumbing that only existed to carry it; confirm the map masthead still binds its club name from the roster payload (app/src/lib/pack.ts). tsc + npm test. Report per P0.
```

---

## What only you do (no Claude, no Codex)

- `eas login` then `cd app && eas env:pull --environment preview --path .env` — without `.env`
  the Release simulator build cannot reach Supabase. (Or copy `app/.env` from the old Mac.)
- `supabase login` — lifts the deploy freeze once the five pending migrations have their review.
- In the Codex app: anything that needs a credential's VALUE (Toss dashboard, App Store Connect,
  the Toss support ticket in `docs/research/2026-08-31-toss-provider-memo.md` §3).
- Rulings: OPEN-C (pack start display), OPEN-F (runner pay when a leg disappears), the harness
  cut list, the 0154 #1/#4 phone-visibility scope. Claude puts these to you as options.
