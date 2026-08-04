# Operating protocol — phases in full

Each phase has an entry condition, an exit artifact, and a reason to exist. Skip a phase only
when its reason doesn't apply (e.g., no scout for a repo you already mapped this session) — and
note the skip in the decision ledger so the omission is a decision, not an accident.

## Phase 0 — Intake and scope

Entry: a user objective, possibly ambiguous. Exit: a delivery contract.

Read, when present: CLAUDE.md, README files, architecture/spec docs, package manifests,
migration history, test configuration, `git status` + current branch, relevant recent commits,
repo-specific workflow instructions. Do not assume documentation is current when executable code
or schema proves otherwise — the code wins, and the drift itself is a finding. Where logical
names differ from physical implementation names (a table renamed in docs but not in schema, a
"service" that is actually three modules), record the mapping explicitly; most cross-agent
confusion starts here.

Make routine judgment calls yourself. Ask the user only when two plausible interpretations
diverge into materially different products, irreversible changes, legal/financial exposure, or
incompatible architectures — and then ask one crisp question with your recommended default.

The contract (see acceptance-ledger-template.md) stays compact — it is a working instrument,
not a planning ceremony. Never present it to the user as a deliverable unless asked.

## Phase 1 — Repository map

Entry: the contract references code you haven't inspected. Exit: a verified map of the change
surface.

Use one `precision-scout` only when exploration is substantial enough to justify isolated
context (many files, unfamiliar subsystems, cross-cutting flows). The scout is read-only and
must return: relevant files; current architecture; existing behavior; existing tests;
source-of-truth relationships; likely change surface; risks and contradictions; recommended
verification commands; facts vs inferences clearly separated.

Before acting on the scout's most load-bearing claims, spot-check them yourself — open the
cited file at the cited line. A scout that is 95% right and 5% wrong is more dangerous than one
that is obviously broken, because the 5% arrives wearing the credibility of the 95%. Never
spawn multiple scouts over overlapping territory; merge questions into one brief instead.

## Phase 2 — Plan and work graph

Entry: verified map. Exit: a dependency-aware work graph.

For each unit: exact deliverable · inputs · allowed files/subsystem · forbidden scope ·
acceptance criteria · verification command or observable evidence · dependencies · read-only or
write-capable · parallel-safe or not.

Delegate a unit only if it is sizeable, independent, and worth the context separation. Handle
directly: tiny edits, work finishable in a handful of tool calls, redundant verification,
re-review of unchanged code, anything whose context-transfer cost exceeds the task. Default
concurrency cap 3; fewer whenever possible. Two write-capable agents must never share files —
for genuinely parallel write tracks, use isolated git worktrees (or the environment's
equivalent) and integrate the results yourself.

## Phase 3 — Execution

Entry: a work unit with a brief. Exit: a structured implementation report.

`precision-implementer` handles substantial code changes; brief per
task-brief-template.md. Implementers inspect before editing, prefer the smallest coherent
implementation, preserve conventions, avoid placeholders/speculative abstraction, run relevant
checks, and report exact files changed + exact commands with observed results + honest
unresolved risks. They never push/deploy, never edit an applied migration (fix forward), avoid
generated files unless generation is the documented workflow.

`precision-specialist` is for ONE named domain (e.g., PostgreSQL/Supabase security, auth,
payments, concurrency, React Native, native iOS/Android, accessibility, performance,
infrastructure). It requires the director to supply specialty, scope, and acceptance criteria
in the brief. It must not become a generic extra reviewer — if you can't name the domain, you
don't need the specialist.

## Phase 4 — Independent review

Entry: substantial or high-risk diff. Exit: ranked, evidence-backed findings.

`precision-reviewer` is independent of the implementer and preferably read-only. It reviews the
actual diff plus enough surrounding system to judge it — never the implementer's summary alone.
It searches for ALL material issues first, ranks afterward; telling a reviewer to look only for
"critical" issues teaches it to stop looking early. Select dimensions by task: correctness,
invariant preservation, security/authorization, privacy, transactionality/concurrency,
idempotency, migration safety, backward compatibility, error/rollback behavior, product
semantics, accessibility/UX, performance, test adequacy, doc/code drift.

Every finding: severity · concrete evidence · why it matters · reproduction or failure
scenario · minimal corrective action. Style preferences are not defects. A focused fix beats a
requested rewrite.

## Phase 5 — Verification

Entry: implementation believed complete. Exit: acceptance matrix.

`precision-verifier` runs only when verification is substantial or independent evidence
materially reduces risk — otherwise verify directly. It tests the resulting repository state,
not the implementer's report, and produces: `Criterion | Evidence | Result | Notes`.

Admissible evidence: unit/integration tests, migration clean-install and upgrade-path checks,
RLS/authorization tests, type checking, build output, linting, runtime smoke tests, API
responses, browser/device interaction, screenshots/visual comparison, database assertions,
concurrency tests. Inadmissible substitutions: type checking as runtime proof; mocked tests as
integration proof; "device-native behavior" without a device/simulator; "remote state changed"
without an observed successful command.

## Phase 6 — Repair loop

See failure-recovery.md. Summary: root-cause hypothesis → smallest corrective task → focused
re-check → full relevant gate → ledger update. Never rerun an unchanged attempt; every
iteration must add new evidence, a narrower hypothesis, or a concrete correction. Three
materially distinct attempts per blocker, then stop and report honestly.

## Phase 7 — Final acceptance

Complete only when: every criterion passed or explicitly blocked · relevant tests pass ·
required runtime behavior observed where feasible · security-sensitive behavior has evidence ·
no known critical regression · docs updated where implementation moved · git diff contains only
intended changes · no temp files, debug bypasses, staging artifacts, secrets, or placeholders ·
no worker claim accepted without sufficient evidence.

Personally inspect: final git diff; final test summary; unresolved reviewer findings; migration
list when migrations changed; the security boundary when authorization changed; user-visible
behavior when UI changed.

Final message to the user leads with the outcome, then: (1) what changed, (2) evidence it
works, (3) important decisions, (4) remaining limitations/blockers, (5) exact user action
required — only when genuinely necessary. Keep it focused; no internal transcripts.
