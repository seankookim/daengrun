# gstack × daengrun — invocation guide + applicability map (2026-08-05)

Source of truth: Sean's clone at `~/.claude/skills/gstack` (his Mac) · cloud mirror `/tmp/gstack`. Verified against the actual `./setup` script, not memory.

## How invocation works

`./setup` links every directory containing a `SKILL.md` (55 of them) into `~/.claude/skills/` as a **top-level skill**, plus a root router skill named `gstack`. Naming depends on the choice made during setup: flat (`/office-hours`) or prefixed (`/gstack-office-hours`).

**On Sean's Mac, in Claude Code:**

- `ls ~/.claude/skills | head -30` — see which naming your setup chose.
- Type `/` and search — every gstack skill is a slash command: `/office-hours`, `/plan-ceo-review`, `/investigate`, `/retro`, `/cso`, `/spec`, `/design-shotgun`… (add `gstack-` prefix if that's what setup installed).
- **Don't remember names? `/gstack` is a router** — invoke it and describe the task; it sends you to the right skill.
- **Auto-triggers**: each skill declares trigger phrases in its frontmatter — saying "brainstorm this" or "is this worth building" fires `/office-hours` without the slash; "which gstack skill fits this?" fires the router.

**In Cowork cloud sessions (this one):** `~/.claude` on the Mac is not visible, so the skills never appear as invocable units here. Claude executes the methodology from the mirrored source instead — sprint phases labeled Think → Plan → Build → Review → Test → Ship → Reflect. If we want them native in Cowork, the pure-methodology skills can be packaged as `.skill` files and saved to Sean's account (say the word).

## Applicability map (55 skills, classified)

### In active use — methodology executed in our sessions

| skill | daengrun usage |
|---|---|
| `office-hours` | premise-challenge strategy docs (rewards doc = this format) |
| `plan-ceo-review` | expansion opt-in ceremonies — the structured A/B/C decisions Sean answers |
| `investigate` | root-cause debugging Iron Law (no fix before reproduced cause) |
| `retro` | Reflect notes in session-handoff §2b at batch ends |
| `review` | pre-landing review ≈ our adversarial reviewer (executes attacks) |
| `spec` | vague intent → executable contract, the precision-director contract step |

### Applicable, not yet used — candidates

`cso` (OWASP/STRIDE security mode — worth running before the next migration wave) · `design-shotgun` (multi-variant design board — literally our HTML-lab pattern, could replace hand-rolled labs) · `design-review` / `plan-design-review` / `plan-eng-review` / `plan-devex-review` (interactive plan critiques) · `diagram` (mermaid/excalidraw triplets) · `document-generate` · `learn` (project learnings ledger ≈ our workflow-rules memory, but in-repo) · `health` (code quality dashboard) · `autoplan` (runs all four reviews sequentially with auto-decisions) · `careful` / `guard` / `freeze` / `unfreeze` / `context-save` / `context-restore` (local-session guardrails — useful in Sean's local Claude Code, not in cloud).

### Not applicable to daengrun

- **Web deploy/browser stack** (we're a native RN app; pushes are Sean-only by law): `browse`, `qa`, `qa-only`, `benchmark`, `canary`, `land-and-deploy`, `landing-report`, `setup-deploy`, `ship`, `scrape`, `skillify`, `setup-browser-cookies`, `open-gstack-browser`, `pair-agent`.
- **iOS-native family** (`ios-clean/design-review/fix/qa/sync`): targets SwiftUI/Xcode with a DebugBridge SPM package — our RN/Expo stack can't host it. The *concept* of live-hardware design QA is what Sean's manual smoke already is.
- **Other hosts/tools**: `codex` (OpenAI CLI wrapper), `benchmark-models`, `make-pdf` (Cowork has its own), `gstack-upgrade` (run on the Mac clone).
- **gbrain** (`setup-gbrain`, `sync-gbrain`): a separate-repo mod making skills brain-aware — **not installed, not studied**. If Sean wants it, that's its own setup session.

## Honest understanding statement

Internalized and executing: the sprint ethos + the six tier-1 ceremonies. Verified today from source: the installer, naming, router, trigger mechanics. Read at description level only: most of tier 2. Skimmed only: the web-deploy family. Not studied: gbrain, the browse binary internals, the benchmark harness. This file is the boundary — anything below tier 1 gets read in full before first use.
