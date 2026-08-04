# Failure recovery — the repair loop and honest stopping

The repair loop exists because the two failure modes of automated delivery are mirror images:
giving up too early (dumping a half-broken change on the user) and not giving up (burning the
budget re-running the same failing idea). Both are solved by the same discipline: every
iteration must be materially different, and the loop must have an honest exit.

## The loop (per failing criterion)

1. Root-cause first. Read the actual failure output; reproduce it if cheap. Name the most
   likely cause as a testable hypothesis — "X fails because Y" that some observation could
   falsify.
2. Assign the smallest corrective task that tests the hypothesis. Prefer fixing directly over
   delegating unless the correction is itself substantial.
3. Apply the correction.
4. Re-run the FOCUSED check first — the single test/command that captures the failure. Fast
   feedback beats full coverage while iterating.
5. Once the focused check passes, run the full relevant gate (the suite/build/typecheck set
   that guards this area). A focused pass with a broken gate is a regression, not progress.
6. Update the decision ledger: hypothesis, what changed, evidence, attempt count.

Never repeat an unchanged attempt. Re-running an identical command hoping for a different
result is not an iteration; it is a delay with extra steps. (Exception: a suspected flake —
rerun once, and if results differ, flakiness itself becomes the finding.)

## Stop condition

Default cap: 3 materially distinct attempts on the same blocker. Then stop and report:

- What is PROVEN to work (with evidence pointers)
- What remains broken (exact failing criterion + latest output)
- Evidence from each attempt (what each ruled out — failed attempts are information)
- Most likely remaining cause
- The SMALLEST user decision, credential, environment change, or external dependency that
  would unblock — phrased so the user can act in one step

Exceeding the cap is allowed only when ALL hold: each iteration is making measurable progress;
no user action is required; the remaining work is clearly in scope; the next attempt is
meaningfully different from all prior ones. "Iterate until success" is never license for an
unbounded loop — if you can't articulate what's different about attempt N+1, you're done.

## Failure taxonomy — match the response to the failure

- Test fails, implementation looks right → determine which is wrong FIRST. Never bend code to
  satisfy a wrong test; fixing the test is a legitimate correction (record it as a decision).
- Worker returns confident but unevidenced success → treat as unverified; sample its claims
  yourself before any repair work based on them.
- Worker contradicts another worker → arbitrate with your own inspection of the disputed
  fact; the repo is the referee, not seniority of report.
- Environment/tooling failure (missing dep, sandbox limit, network) → distinguish from code
  failure; report as BLOCKED with the unblock step, don't burn attempts on it.
- Flaky evidence (passes sometimes) → the flake is the bug until shown otherwise; stabilize
  or quarantine before trusting any green run through it.
- Scope discovered too big mid-flight → stop widening silently. Re-cut the contract: ship the
  in-scope core, ledger the remainder, tell the user what moved and why.
