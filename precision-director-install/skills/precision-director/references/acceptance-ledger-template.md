# Delivery contract, decision ledger, acceptance matrix

These are the director's working memory. Keep them compact and current — a stale ledger is
worse than none because it lies with confidence. They are internal instruments: maintain them
in your working notes (or a scratch file), surface them to the user only on request or at
final acceptance where relevant.

## Delivery contract (Phase 0 exit artifact)

```
OBJECTIVE: (one sentence, the user's actual goal — not the literal request if they differ;
            if they differ, say how and why you chose)
IN SCOPE: …
OUT OF SCOPE: (explicit — this is what prevents drift)
EXISTING INVARIANTS: (behaviors/contracts that must survive; include logical→physical
                      name mappings discovered in Phase 0)
ACCEPTANCE CRITERIA: (numbered, each independently testable)
REQUIRED EVIDENCE: (per criterion: the command/observation that proves it)
APPROVAL-GATED ACTIONS: (destructive/remote actions that need explicit user authorization,
                         and whether authorization has been given in this conversation)
KNOWN UNCERTAINTIES: (what you don't know yet and how you'll find out)
```

## Decision ledger (living, updated every phase)

```
CURRENT OBJECTIVE: …
ACCEPTED DECISIONS: (decision → reason; include architecture choices)
REJECTED ALTERNATIVES: (alternative → why not; prevents relitigating)
REPO STATE: (branch, dirty files, migrations pending, last verified commit)
COMPLETED UNITS: (unit → evidence pointer)
FAILING CRITERIA: (criterion → last evidence → current hypothesis → attempt count)
NEXT ACTION: (one thing)
APPROVALS STILL OWED: …
```

## Acceptance matrix (Phase 5/7 exit artifact)

```
| # | Criterion | Evidence (command/observation + where) | Result | Notes |
|---|-----------|----------------------------------------|--------|-------|
| 1 | …         | `cmd` → observed exit 0, output …      | PASS   |       |
| 2 | …         | screenshot/api response/db assertion … | FAIL   | see repair loop |
| 3 | …         | blocked: needs <user action>           | BLOCKED| smallest unblock: … |
```

Rules: every criterion appears; every Result is backed by observed evidence, not reports;
BLOCKED entries name the smallest user decision/credential/environment change that unblocks.
