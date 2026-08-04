# Task brief templates

A good brief is the cheapest defect prevention there is: most subagent failures are scope
failures, and scope failures are brief failures. Fill every field; "n/a" is an answer, silence
is not. Keep briefs concise — decisive facts and paths, not narration.

## Implementer brief

```
OBJECTIVE (user's, one line): …
YOUR UNIT (narrow): …
REPO FACTS YOU NEED (paths + line refs + the fact): …
ACCEPTANCE CRITERIA (testable): …
ALLOWED CHANGE SURFACE (files/dirs): …
FORBIDDEN (explicitly out of scope): …
INVARIANTS THAT MUST SURVIVE: …
REQUIRED COMMANDS (run these; report observed output): …
RETURN FORMAT: files changed (exact paths) · commands run + observed results ·
  decisions made · unresolved risks · anything you saw but did NOT fix
```

Standing implementer rules (include by reference, they're in your agent definition): inspect
before editing; smallest coherent change; repo conventions win; no placeholders, no fake
implementations, no speculative abstraction; never claim success from code appearance; never
push/deploy/broaden scope; applied migrations are immutable — fix forward.

## Scout brief

```
QUESTIONS (numbered, answerable from the repo): …
TERRITORY (dirs/files to cover; where copies live if not the live repo): …
RETURN: per question — FACTS with file:line · INFERENCE (ranked, labeled) ·
  what you could NOT find (say so; never guess content) ·
  recommended verification commands
READ-ONLY. No edits, no fixes, no implementation beyond what inspected code supports.
```

## Reviewer brief

```
DIFF UNDER REVIEW (how to obtain it — e.g., `git diff <range>` or file list): …
SURROUNDING SYSTEM you may need (paths): …
DIMENSIONS for this task (pick from protocol Phase 4 list): …
CONTRACT/INVARIANTS the change must honor: …
RETURN: ALL material findings, each with severity · evidence (file:line) · why it
  matters · failure scenario · minimal corrective action. Rank at the END.
  Style preferences are not findings.
```

## Verifier brief

```
ACCEPTANCE CRITERIA (verbatim from the contract): …
ENVIRONMENT / COMMANDS available: …
EVIDENCE RULES: test the repo state, not reports; no type-check-as-runtime-proof;
  no mocks-as-integration-proof; observed exit codes only.
RETURN: acceptance matrix — Criterion | Evidence | Result | Notes — plus any
  incidental defects observed (reported, not fixed).
Ephemeral test artifacts: allowed only if necessary; remove them; list any created.
```

## Specialist brief

```
DOMAIN (one, named): …
PROBLEM in that domain: …
SCOPE (files/subsystem) and FORBIDDEN: …
ACCEPTANCE CRITERIA: …
RETURN FORMAT: as implementer (if writing) or reviewer (if advising) — state which.
```

Do not instantiate a specialist without a named domain — that's a reviewer with extra steps.
