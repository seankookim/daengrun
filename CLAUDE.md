# daengrun (도그스하이) — standing instructions for Claude sessions

RN/Expo + Supabase dog-running marketplace. Banpo pilot. PMF gate: M1 rebooking 60%.
Session bridge: **read `docs/session-handoff.md` fully before doing anything** — it holds current state, pending items, and this sprint's decisions. This file holds the permanent laws.

## Language

**English everywhere except in-app content.** Replies, docs, plans, code comments, and commit
messages are English. The ONLY Korean is what a user reads inside the product: UI copy, button
labels, notification titles/bodies, error strings, and user-facing legal documents (개인정보처리방침,
이용약관). Korean product terms stay Korean when quoted in English prose (하이 포인트, 인계, 정산).

Changed 2026-08-08 (Sean). Older files still carry Korean comments — do not mass-rewrite them;
convert opportunistically when you are already editing a file for another reason.

## Operations — Sean-only

**Changed 2026-08-10 (Sean): Claude may run `supabase db push`, `supabase functions deploy`, and
`git push`.** Conditions that still hold:

- Gates green first — tsc, check-rpc, and the SQL harness for anything touching migrations. Never
  deploy on a red or unrun gate.
- Never push from a worktree carrying an unfinished migration; `db push` applies every pending
  local file.
- Verify after, don't assume: `supabase migration list` after a push, the anon-definer check after
  a security migration, and read back what actually landed.
- **The same law covers `git push`, and it was learned the hard way (2026-08-25).** A push
  SUCCEEDING is a claim; `git show origin/<branch>:<path>` is the fact. A session scripted
  `git push … | grep -q "redesign-v4 -> redesign-v4"` as its success test — and a REJECTED push
  prints `! [rejected]  redesign-v4 -> redesign-v4 (non-fast-forward)`, which **contains that exact
  string**. The detector matched its own failure message and reported PUSHED on a push that never
  landed; a peer found it by reading the file on origin. Two rules fall out: **(a)** confirm a
  landing by reading the ARTIFACT back from origin, never by parsing the tool's report — the same
  substitution as reading a pin's green as proof of the property it was meant to prove; **(b)** a
  detector whose success pattern is a SUBSTRING of its failure output is not a weak check, it is
  anti-correlated with the thing it tests in precisely the case that matters. (An audit of all six
  of that session's claimed pushes found five genuinely landed and one not — audit the whole set
  when a detector is found broken, never just the instance someone caught.)
- Announce what you ran and what it changed. Say plainly if something failed.
- **Still Sean-only, and not because of policy:** anything requiring a credential's *value* — the
  APNs `.p8`, App Store Connect, a PG contract, 사업자등록. Claude may use credentials already
  configured on the machine, but never types, copies, or relays a secret's value.
- Product decisions with real-world consequences (wiping production accounts, changing what users
  are told about safety) stay Sean's call even when the command is trivial.

Never claim device-visual success — verify on the simulator, or say it is unverified.

Never claim device-visual success — Sean smoke-tests on hardware. Provide a smoke list instead.

## Honesty laws (product)

No mockups, fake numbers, or fabricated data in the app: bind real fields or omit the element. Failures are shown as failures (no silent catch → happy UI). Loading is not 0. No dead buttons — every visible action has a real route/effect in every state. When display vocabulary flattens server states (STATUS_MAP), gate logic and badges on `rawStatus`. Celebration animations play once per entity (module-level Set idiom, see `sealStampFresh`/`_patchPopSeen` in api.ts) and never replay on re-entry hydration.

HTML labs in `docs/labs/` are the sanctioned mockup arena: numbered variants, Sean picks by number, implementation then binds real fields only.

## Code review — codex is a standing gate (Sean, 2026-08-25)

**「always check in with codex for code.」** Every code slice gets a codex pass before it is
called done — not only migrations and not only when someone remembers.

**The invocation, and the model is Sean's (2026-08-25): `gpt-5.6-sol` at `xhigh`, NOT
`gpt-5.2-codex`.**

```
codex exec --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=xhigh "<prompt>"
```

Pointed at the actual diff, with the house laws and the specific failure modes that slice could
have. Verified working on this machine (codex-cli 0.147.0).

### 🔴 A codex run is DONE when a VERDICT is in the file — not on exit status, and never on log size

Measured 2026-08-26 across two sessions' full sets, after codex hit an account usage limit:

| run | log size | verdict | what it was |
|---|---|---|---|
| spec session, 0128 | 739 KB | ✅ present | **genuine** |
| spec session, 0129 | 4 KB | ✗ none | burned — *obvious* |
| ui6, client review | **1.4 MB** | ✗ none | burned |
| ui6, server review | **1.25 MB** | ✗ none | burned |
| ui6, #17 fix | 446 KB | ✗ none | burned |

**Two failure disguises, and both defeat the obvious check.** One returns **exit code 0** with an
empty verdict — a tool reporting success for a review that never happened. The other burns the
entire READ, dies at the emit step, and leaves a **huge** log.

**⚠ SIZE IS ANTI-CORRELATED WITH SUCCESS IN EXACTLY THE CASE THAT BITES.** The 4 KB failure is
obvious at a glance; the 1.4 MB failures are indistinguishable from — and *larger than* — the
739 KB genuine success, because the size measures precisely the reading that got burned. **A large
log with no verdict is the CHARACTERISTIC failure, not a reassuring sign.** A heuristic that works
on the trivial case and inverts on the expensive one is worse than none.

So: grep the artifact for a verdict, every time.

🔴 **AND THE VERDICT-GREP ITSELF HAS A THIRD DISGUISE — MEASURED 2026-08-26, ON THE RUN THAT
WAS CHECKING FOR IT.** `codex exec` **echoes the prompt into the log**. A review prompt that ends
「Begin the last section with the literal line: "VERDICT: <APPROVE|APPROVE-WITH-FIXES|REJECT>"」
puts the string `VERDICT:` in the artifact **whether or not codex ever answered**. Measured: a
4.6 KB log, exit code **0**, `grep -c 'VERDICT:'` → **1**, and the single hit was line 65 — the
prompt's own instruction — with the real tail being
`ERROR: You've hit your usage limit … try again at 3:56 PM`. **The check this section exists to
mandate reported a verdict on a review that never ran.**

Same family as the push-detector and the comment-quoting-removed-code laws, and it is the third
time this shape has cost something: **a detector whose pattern appears in BOTH the answered and
unanswered states is not weak, it is uninformative.** Here it is worse than uninformative — the
pattern is guaranteed present by the very act of asking, so the check is *anti*-correlated with
having asked properly: the more explicitly you demand a verdict, the more certainly your grep
finds one.

**The detector that works — match a verdict VALUE, never the word:**
```
grep -cE 'VERDICT: (APPROVE|APPROVE-WITH-FIXES|REJECT)\b' <log>     # 0 = no review happened
```
The angle-bracket placeholder `<APPROVE|…>` cannot match it, so the prompt echo is excluded by
construction rather than by remembering to exclude it.

🔴 **v3 OF THIS LAW — THE VALUE-MATCH IS ALSO DEFEATED IF THE PROMPT ENUMERATES THE VALUES.**
Measured 2026-08-27, twice in one hour by two independent agents: their prompts said 「end with
VERDICT: APPROVE, APPROVE-WITH-FIXES or REJECT」 — spelling out the literal values — so the echo
contained real `VERDICT:`-adjacent value strings and `grep -cE 'VERDICT: (APPROVE|…)\b'` returned
**3 on runs that produced nothing** (one a 1MB burned log). A detector whose pattern the prompt
guarantees can never fail. **The prompt MUST use the X-placeholder form and never spell the
values in a `VERDICT:`-prefixed line**: 「End with the literal line VERDICT: X where X is one of
APPROVE, APPROVE-WITH-FIXES, REJECT」 — the echo then contains only `VERDICT: X`, which the
value-match cannot hit. If you inherit a log whose prompt enumerated values, the count is
uninformative; only the POSITION of the hits (past the prompt block) settles it.

⚠ **v3 REFINED (b6's audit of 17 runs, sharper than 「never enumerate」):** the mechanism is that
**the placeholder must OCCUPY THE VALUE POSITION** — `VERDICT: <A|B|C>` cannot value-match because
`<` sits where the value must be, while values enumerated in PROSE (「answer VERDICT: APPROVE or
VERDICT: REJECT」) echo as real matches. A reviewer still needs to know the options; the
angle-bracket or X-placeholder form tells them and stays undetectable.
**And capture the streams SEPARATELY** (`> out.log 2> err.log`): b6 measured across 17 runs that
the ECHO lands on stderr and the ANSWER on stdout — walled runs were value-match 0 on stdout AND
bare-word 1 on stderr, so either alone catches it. ⚠ Attribution honest: measured by b6 on their
runs; my own logs merge streams (`2>&1`) so I could not independently confirm — which is itself
the reason to split: a merged log destroys the discriminator. **And still check for the usage-limit line
positively** (`grep -i 'usage limit'`) — a quota wall is the single most common cause, it is
invisible in the exit status, and two sessions hit it within one hour on 2026-08-26.
 And when a set of runs is in question, **audit the
whole set** — ui6 reported one burned run and found three; the spec session audited its own and
found one of three. Neither number was visible without looking.

⚠ **THE LAW ABOVE IS NARROWER THAN THE TRUTH, and the general form was measured twice, on two
different invocation shapes, by two sessions within the hour.** `codex exec` echoes the **entire
prompt**, so it is not `VERDICT:` that is unsafe — **every token you put in the prompt is
unsafe to grep for.**

| run | shape | prompt | log | genuinely codex |
|---|---|---|---|---|
| 0131 review | prompt-as-**argv**, `-C`, review mode | 3,753 B | 4,667 B | **914 B** (banner, workdir, 2 error lines) — 47 of 63 log lines are the prompt |
| roster consult | prompt-on-**stdin**, consult mode | 4,751 B | 5,612 B | **~861 B** — 3 prompt-unique strings each hit once |

Different subcommand shape, different mode, same result: **~80–85% of a burned log is your own
question read back to you.** So the rule is not "grep for a verdict value instead of the word" —
that is only the instance with a gate attached. The rule is:

> 🔴 **Never confirm that codex answered by grepping for anything you asked for. Match only
> strings codex can produce and you did not write** — a verdict VALUE (`APPROVE` /
> `APPROVE-WITH-FIXES` / `REJECT`, never the `<A|B|C>` placeholder), a `file:line` citation, a
> finding count. If your prompt contains the pattern, the check passes by construction and is
> anti-correlated with having asked rigorously.

⚠ `< /dev/null` still matters and did its job: my run printed `Reading additional input from
stdin...` and **returned** instead of wedging, which is the failure §announcer-10.9 describes.
It prevents the hang; it does not prevent the echo.

⚠ **AND CONFLATING THE TWO COSTS A RUN AGAINST AN ALREADY-EXHAUSTED QUOTA.** Measured 2026-08-26
by the peer, self-corrected: their first attempt already carried `< /dev/null`, printed
`Reading additional input from stdin...`, emitted `thread.started` and **returned** — so it was
never the wedge. They recognised a known-bad symptom, **named it as the wedge, and re-ran**,
burning a second invocation against a quota that was already spent. **Both attempts were the
usage wall the entire time, and the answer was sitting in the tail of the first log.**
The rule that falls out is small and general: **when you meet a symptom you have a name for,
read the tail before you act on the name.** A familiar symptom is a hypothesis, not a diagnosis —
and `Reading additional input from stdin...` is printed on the ordinary path, so it carries no
information about whether anything went wrong.

⚠ Consequence for honesty, which is the part that costs something: **do not tell anyone a slice is
"under codex review" until a verdict exists.** On 2026-08-26 a client fix was pushed with that claim
attached and the review had already died; the correction had to be volunteered, because nothing
else would have surfaced it.

Why it is a gate and not a nicety, from this week's measurements: a slice can be **896/0 on the
harness with four green client gates and still be wrong** — those numbers answer "did I break a
pin", never "does this disclose only what it must". Codex reads cold, with no author reasoning,
which is the one thing an author cannot do for themselves. Pair it with an EXECUTING reviewer on
anything security- or privacy-shaped: codex catches wrong reasoning and missing cases, an executing
agent catches what actually happens — on 0128 the two disagreed, and the disagreement was the
finding (codex found a leak that arms in the future; execution found three defects reachable today,
one of them a permanent disclosure by inaction).

🔴 **A RUN THAT NEVER STARTED LOOKS EXACTLY LIKE A RUN STILL WORKING — AND A TWO-STATE
DETECTOR CANNOT TELL THEM APART** (announcer, measured 2026-08-27, 40 minutes lost and reported
to the human three times as 「still reading」). `codex exec -C <dir>` where `<dir>` is not a git
repo returns **immediately** with `Not inside a trusted directory and --skip-git-repo-check was
not specified` — 115 bytes of stderr, nothing on stdout, exit non-zero, no process. My watcher
polled for exactly two states, **a verdict value** and **`usage limit`**, so the third state —
*refused to start* — matched neither and read as 「long read in progress」. I narrated
`out=0B` out loud on four separate checks without acting on it.
**Three rules, and the second is the general one:**
**(a)** A frozen `git archive` export is the right way to stop mid-read drift, but codex will not
read a non-repo — `git init && git add -A && git commit` inside the export keeps the freeze AND
satisfies the trust check.
**(b)** ⚠ **A detector must enumerate the FAILURE states, not the success state plus one known
failure.** Poll for a verdict, for a quota wall, AND for 「process gone with no verdict」 — the
last one costs `pgrep` and catches every death cause at once, including ones nobody has met yet.
**(c)** **Byte count over time is the cheapest liveness signal available and it was on my screen
the whole time**: genuine runs climbed 384KB → 545KB → 635KB; this one sat at 0. ⚠ Note the
stream split (§codex v3): the READING lands on stderr and only the ANSWER on stdout, so **watch
stderr for liveness and stdout for the verdict** — a stalled stderr is the tell, not an empty
stdout.
⚠ And the same day, my *refusal* detector false-positived: `grep -qiE "not inside a trusted|
error:"` matched codex's benign startup warning `ERROR codex_models_manager: failed to load
models cache`, so a healthy run was declared REFUSED. **Match the specific refusal sentence, never
a bare `error:`** — third detector-shaped miss of one day, all mine.

🔴 **THE VERDICT DETECTOR, FINAL FORM: ASK FOR A DIGIT** (ui6, 2026-08-27 — strictly better than
the placeholder rule it replaces). Have the reviewer end with TWO lines:
```
FINDINGS: <n>
VERDICT: <one of APPROVE, APPROVE-WITH-FIXES, REJECT>
```
and detect with `grep -cE '^FINDINGS: [0-9]+'`. The prompt contains the literal `<n>`, which
**cannot match a digit**, so the echo is excluded BY CONSTRUCTION rather than by remembering to
exclude it — and the count is a thing only codex can produce. ⚠ **This also corrects my own law's
scope, in ui6's words: the general form is 「never grep for anything you WROTE」, not 「never write
it」.** Spelling the three verdict words in the prompt is fine and helps the reviewer use the right
vocabulary; what must never happen is grepping for a string your own prompt guarantees. Pair it
with the positive checks (`usage limit`, `trusted directory`) and the three-state watcher.
⚠ And **re-freeze the export before each round**: an export that predates your own landings is
reviewing a tree that is not trunk — the staleness problem wearing a freeze's costume.

🔴 **TREATING A FINDING AS NARROWER THAN ITS OWN SENTENCE IS THE SAME ERROR AS READING A GREEN
AS BROADER THAN ITS OWN SENTENCE — RUN BACKWARDS** (ui6, 2026-08-27; the exact inverse of this
file's most-repeated law, and it cost a real defect rather than a pin gap). A reviewer wrote 「a
token must not outlive its row's decision」. ui6 fixed **the one abandon path they were looking
at** — which turned out to be the path where the fix is a **NO-OP**, because that path runs at
`attempts = 0` where the token is already NULL. **The two paths abandoning rows that hold a LIVE
token were untouched**, and they fail in two different ways that neither implies:
one loses the RECORD (a crashed worker's late report CAS-matches the surviving token and flips
`abandoned → done`, so **the ledger states a key was revoked that the system deliberately refused
to revoke**, and `done` is terminal so the refusal's reason goes with it); the other loses the
VISIBILITY that the same slice had just bought (a late `false` flips a stranded row to `failed`,
which no state predicate excludes from claiming — **the sweep that surfaced the row is undone by
the very worker whose crash created it**).
**The rule: a finding's SENTENCE is the property; the site the reviewer cited is one place that
property happens to be observable.** Enumerate every site the sentence covers before calling it
closed — and be most suspicious when the site you fixed was easy, because a fix that changes
nothing is indistinguishable from a fix that works.

🔴 **A PIN THAT INHERITS ANOTHER PIN'S SETUP AND ASSERTS A FACT ABOUT THAT SETUP IS TESTING THE
SETUP** (ui6, same slice). Their `175 V2` read a row count and expected 1 — a number V1's fixture
produces **whether or not the behaviour under test ever ran**. Rewritten to perform the action
itself and compare before to after, so its number is a **delta it caused** rather than a state it
found. ⚠ Neighbour of the fixture-agreement law: there the fixture could not distinguish two
rules; here the assertion could not distinguish 「the code ran」 from 「the setup already looked like
this」. **Test: if you deleted the behaviour entirely, would this pin's number change?**

🔴 **A CONTROL THAT READS THE SAME VARIABLE THROUGH THE SAME OPERATOR IS NOT A SECOND
MEASUREMENT — IT IS THE FIRST ONE PRINTED TWICE** (announcer's S10, named by ui6). S10's oracle arm
had two CONTROL arms added specifically so a helper hard-wired to one answer could not pass — and
all three collapsed on NULL **together**, because all three were bare `IF helper(...)`. A control's
entire purpose is to be INDEPENDENT of the thing it controls; sharing an operator destroys that
while leaving both arms looking different on the page.
⚠ **This is 「agreement between two sessions is the same claim counted twice」 one level down, inside
a single pin — and harder to see there**, because both arms are yours, you wrote them minutes
apart, and they read as deliberate diversity. **The test: name the failure mode each arm is blind
to. If the lists are identical, you have one control.** ui6 then ran this question against their own
`W2`/`W3` and measured a genuine pass — accept-all reddens W2 only, refuse-all reddens W3 only, so
no single hard-wired answer satisfies both — which is what a real control pair looks like, and they
noted they had been calling W3 a control on the strength of having *named* it one.

🔴 **NULL COLLAPSES EVERY `IF`-BASED PIN INTO SILENCE — AND THE PINS THIS KILLS ARE EXACTLY THE
PINS WHOSE JOB IS TO NOTICE SOMETHING MISSING** (codex found it in the announcer's S10; ui6 then
applied it to their own work within the hour and found **four more**, measured rather than
reasoned). plpgsql does not take an `IF` on a NULL predicate, so any pin shaped
`if <expr> then v_bad := …` is **silent** whenever `<expr>` is NULL.
Measured, ui6's set: pointing `180 W1/W6` at a function name that does not exist gave **1061/0,
both green** — `prosrc` is NULL, `position(… in NULL)` is NULL, no arm fires, the failure string
stays empty. Same collapse in `167 G0` (three arms, `v_txt !~ '…'`), `174 L6` (five arms), and
`169 P19/P20/P21` (`not like`). And in the announcer's `S10`, whose two extra CONTROL arms —
added specifically so a hard-wired helper could not pass — shared the blind spot they existed to
catch: a helper returning NULL for everything passes all three.
⚠ **ui6's sentence is the one to keep, because it explains why the class survives review: *every
one of these is a pin whose entire job is to notice that something is MISSING, and every one was
silent about the most complete version of missing.* The pin READS as paranoid, so nobody asks what
it does when the paranoia is warranted.**
**Fixes:** assert exact booleans (`is not true` / `is distinct from true`), never a bare `IF`; and
for source pins, fail loudly on absence — ui6's `NO-SOURCE(<fn>)` arm. **Audit the whole set when
you find one** (the standing law): one instance found four.

🔴 **WHY THE COMMENT-MATCHING CLASS IS STRUCTURAL, NOT A LAPSE — `prosrc` IS SOURCE PLUS OUR OWN
PROSE, SO THE INSTRUMENT INVERTS UNDER DILIGENCE** (ui6, 2026-08-27, after the same defect appeared
in both sessions' files within one hour, each found by a cold reader rather than its author). Their
formulation, kept verbatim in substance: **we both reached for the artifact closest to the truth —
the deployed function body — and it is the one artifact that carries our own comments inside it.**
Reading `prosrc` is right. Reading it un-stripped means **the more carefully you document a guard,
the more certainly your check passes**: a check for CALLING a function is satisfied by a comment
EXPLAINING it, and the better the explanation, the more surely. Neither party made a mistake of
care; both did the diligent thing with an instrument that rewards documentation as if it were
implementation. **So the fix cannot be 「be careful」 — it must be mechanical: strip comments from
`prosrc` before every match, in every source-reading check, not only the one someone caught.**

🔴 **A SOURCE PIN THAT MATCHES PROSE IS MEASURING THE DOCUMENTATION** (ui6, 2026-08-27 — third
instance of the comment-matching law this week and **the first one INSIDE a pin written to enforce
rigour**). Their `W6` asserted 「the lock precedes the gate」 by searching `prosrc` for the gate's
name, and failed on a correct function — because `card_registration_live()` appears in **0148's own
comment explaining the fix**, ~300 characters ahead of the real call. The pin was reading the
migration's prose as if it were its code.
**Fix, and it belongs in every source-reading pin: strip comments from `prosrc` before matching** —
`regexp_replace(prosrc, '--[^\n]*', '', 'g')` at minimum. Same family as the definer-ACL and
push-detector laws: a pattern present in both the fixed and unfixed states is uninformative, and a
comment that explains a fix guarantees the pattern is present.

🔴 **A PIN WHOSE FIXTURE CANNOT DISTINGUISH TWO RULES IS TESTING THE FIXTURE, NOT THE RULE**
(ui6, same battery, and the subtler of the two). Reverting a predicate from `attempts > 0` back to
`state = 'processing'` reddened **only the source pin** — because the fixture row was literally
`processing`, a state on which the OLD rule and the NEW rule AGREE. A behavioural pin can only see
a predicate change when its fixture sits where the two predicates **diverge**. The repair was to
add a `done`-row arm (claimed but not processing — and the worst real case, since `done` means the
external DELETE definitely landed). **Practical form: when you change a predicate, write down the
set of rows where old and new disagree, and make sure a fixture is IN that set.** An unchanged
green after a predicate change usually means the fixture never left the agreement zone.

⚠ **A PIN THAT REVERSED IS NOT A PIN THAT WAS WEAK** (ui6). Their `175 V3` asserted that an
expired-lease row gets abandoned and its key becomes current — measured, mutation-verified, and
**wrong**, because the behaviour it correctly described was itself the defect. Worth separating in
any ledger: a pin can be rigorous, honest, and load-bearing while pinning a bug. Reversing it is
not an admission that the testing was sloppy; it is the testing working. Do not let 「we had to
flip a pin」 become evidence against the practice that produced it.

🔴 **MUTATE THE GUARD'S PRECONDITION, NOT ONLY WHAT THE GUARD DOES** (ui6, 2026-08-27, found by
a cold reader in code ui6 had written that day and described as closed — then reproduced by the
announcer in 0131 within the hour by applying it). Their battery mutated a refusal BRANCH and
never the **lock that makes the branch's input observable**: removing `if v_busy` reddens the pin;
removing the `for update` that makes `v_busy` true does not. **A battery that only attacks the
branch will always miss the lock** — and the lock was the thing they had written three paragraphs
arguing was load-bearing.
**The same shape, found immediately in 0131 by asking the question of my own battery:** every pin
in `164` attacked the helper's ARMS (its predicate). The facts that make those arms mean anything
— `prosecdef`, the in-body `search_path`, the ACL — were checked ONLY by the migration's VERIFY
block. **A property checked at apply and never pinned is protected exactly until someone recreates
the function.** New standing pin `0131-G4` covers the helper's own shape; measured: planting
`security invoker` aborts the apply at VERIFY (so that plant measures the VERIFY, not the suite),
and the same plant WITH the VERIFY arm removed reddens `0131-G4` alone.
**The practical question to ask of any battery:** list what the guard READS, not only what it
DOES, and mutate each of those. Locks, `prosecdef`, `relrowsecurity`, an ACL, a trigger's
`tgenabled`, a manifest registration — every one is a precondition whose removal silently disarms
a guard that still looks present.

🔴 **A MUTATION THAT REDDENS NOTHING HAS TWO VERY DIFFERENT CAUSES — AND THE HONEST WORK IS
TELLING THEM APART** (agent + ui6, 2026-08-27; ui6's phrasing, because it is the clearest anyone
has managed). Either **the pin is blind**, or **the property is not separately observable through
this door**. They look identical in a battery table — one green row — and the temptation in both
cases is to reshape the pin until something reddens, which manufactures coverage.
Worked example, measured: deleting any ONE of `custodian_profile_id` /
`responsible_profile_id` / `current_runner_profile_id` from 0131's helper reddens **nothing**
(1053/0). Not because the pins are weak — because `session_transfer_accept` (`0058:143-149`)
assigns all three **in one UPDATE**, so no single deletion is observable through any reachable
fixture. The honest conclusion, written into the suite as a GAP rather than recorded as a pass:
**S6/S7 prove the disjunction ADMITS, not that each arm is load-bearing.**
**The rule:** when a mutation reddens nothing, work out WHY before touching the pin. If the answer
is 「the product cannot produce a state where this arm matters alone」, that is a fact about the
system and belongs in the suite as a named gap. If the answer is 「nothing looks at this」, the pin
is blind and owes a repair — and per the mid-battery law, a repair written while staring at the
mutation must then be re-attacked by a head that never saw it.

⚠ **PIN LABELS COLLIDE THE SAME WAY MIGRATION NUMBERS DO, AND THERE IS NO `ls-tree` FOR THEM**
(2026-08-27). Two parallel slices both added an `S6` to `164_scoped_read_policies_suite.sql` —
neither careless, and only the merge could see it. It is **worse than a number collision in one
respect**: a duplicate number breaks a push loudly, while a duplicate label breaks a **battery
record nobody reads until they need it**, which is precisely when ambiguity costs most.
Mitigation that needs no coordination (ui6's): **prefix pin labels by SLICE, not by sequence** —
`0131-S6` rather than `S6` — so the namespace is owned instead of shared.

🔴 **A GUARD WITH NO PIN IS INVISIBLE FROM BOTH DIRECTIONS, AND THE ONLY DETECTOR IS DELETING IT**
(announcer's miss, sharpened by ui6 into the form worth keeping, 2026-08-27). Round 3 of 0131
added `p_uid is not distinct from auth.uid()` to stop a helper being an arbitrary-pair membership
oracle. **Deleting it left the entire suite green** — for a full round. The inversion is what
makes this its own entry: most of this file catalogues pins that PASS FOR THE WRONG REASON, which
at least leaves a wrong-looking artifact. Here the suite is green **because the guard works** and
also green **because nothing checks it, and the two states are identical** until someone removes
it. **The only available detector is the deletion — so this class can only ever be found by doing
the thing that feels unnecessary.** Practical rule: when you ADD a conjunct to close a hole, the
same commit owes a mutation that deletes exactly that conjunct. Not the battery later — the same
commit.

🔴 **A MEASUREMENT'S WRITE-UP OUTLIVES THE THING MEASURED** (both sessions, same day, two shapes).
Mine: a battery block claiming 「this mutation reddens S5 alone」, still true when written, falsified
by a pin I ADDED afterwards and never re-ran. ui6's: a suite baseline quoted as 33/33/34 from a
truncated standalone run, corrected to 32/32/33 against the full log. Same substitution as a push
report standing in for the file on origin, one level up — **the record drifting from the artifact.**
**The fix is one sentence: re-run after the LAST edit, not after the last INTERESTING edit.** A
record that is stale in the safe direction is the most durable kind of wrong, because nothing ever
contradicts it.

🔴 **BEFORE PAYING TO MEASURE AN UNKNOWN, CHECK WHETHER IT IS LOAD-BEARING — DELETING THE
DEPENDENCY DELETES THE QUESTION** (ui6, 2026-08-27; a method, not a fix, and the best move anyone
made this week). The open question was 「does this build's Hermes honour `Intl`'s `timeZone`, or
accept it and silently ignore it?」 — unanswerable from source, and the obvious next step was to
get a device and run a snippet. Instead they asked what the answer would CHANGE: it only matters
while the code depends on Intl. Converging every live date path onto `kst.ts` (fixed +9 offset, no
Intl, Korea has no DST) took the baseline **12 → 1**, and the one survivor is a screen nothing
routes to. **The measurement is now unnecessary for all reachable code.** Verified independently
here: exactly one non-comment `Intl.DateTimeFormat` remains in `app/` + `src/`, on that dead
screen.
**The generalisation:** an expensive unknown deserves 「what does the answer change?」 before it
deserves a measurement plan. Sometimes the cheapest way to close a question is to make it
irrelevant. ⚠ The equality proof is what made this safe rather than reckless — every converted
expression compared against the old real-ICU branch over 284,070 comparisons across four zones,
0 mismatches, with the harness itself control-tested twice (a `+1000 ms` plant produced 2
mismatches; reverting to the old catch produced **62,262 mismatches under New_York and 0 under
Seoul** — the class's signature in one line). A conversion claiming 「equivalent」 without a
control-tested differential is a rewrite, not a proof.

🔴 **A `try`/`catch` FALLBACK THAT RENDERS DIFFERENT WORDS IS TWO PRODUCTS, CHOSEN BY AN
UNMEASURED RUNTIME FACT** (ui6, same slice). `payments.tsx`'s Intl `try` rendered
`2026년 8월 26일` and its `catch` rendered `2026. 8. 26` — **one field, two different sentences,
selected by whether an API happened to throw on that device.** Nobody chose that; it is the shape
a fallback takes when it is written for the mechanism instead of the copy. Every other catch in
that family differed only by clock. ⚠ Generalise past dates: **any `catch` that produces
user-visible text is a second product surface** and owes the same copy review as the first — and
the divergence is invisible in review precisely because both branches look correct in isolation.

🔴 **A GATE WITH A FALSE NEGATIVE IS STRICTLY WORSE THAN NO GATE — AND A NEW DETECTOR'S FIRST
OBLIGATION IS TO DISAGREE WITH A CRUDE VERSION OF ITSELF** (ui6, measured 2026-08-27, caught in
their own gate before it shipped). Their `check-device-clock` comment-stripper treated a template
literal as one opaque string, so `` `${d.getHours()}` `` was blanked along with the prose around
it — and this codebase formats nearly every date inside a template. **The gate reported 3 hits
where a raw grep found 12, and printed a tidy, confident list of the 3.**
**Why this is its own law and not another instance of the green-means-nothing family:** everything
else catalogued here is a green that means LESS than it claims. This is a green that means the
OPPOSITE — it converts 「nobody checked」 into 「something checked and found nothing」, and it would
have shipped as infrastructure every later session trusted. A missing gate leaves a gap someone
can still notice; a lying gate closes the gap in everyone's mind.
🔴 **A GRANT IS NOT A DOOR — CHECK REACHABILITY BEFORE YOU CALL SOMETHING EXPOSED** (announcer
claimed it, ui6 refuted it, both measured on production, 2026-08-27). Measured and TRUE: `anon`
holds `USAGE` on `net` and `SELECT` on `net._http_response` **and** on `net.http_request_queue` —
the request side, whose `headers` carry `X-Cron-Key` and an `Authorization` bearer. From that I
told the human 「anyone holding your public key can read it」. **False.** The anon key talks to
PostgREST, and PostgREST's schema allowlist is `public, graphql_public`:
```
GET /rest/v1/http_request_queue   Accept-Profile: net   [our own anon key]
→ HTTP 406  PGRST106  "Only the following schemas are exposed: public, graphql_public"
```
⚠ **And run the CONTROL, or the 406 proves nothing** — the same key against `public.clubs` returns
**200**, which is what makes the refusal attributable to the allowlist rather than to a bad key.
**The accurate sentence is 「a needless grant sitting behind one config line」, not 「a live
exposure」 — and the gap between those two sentences is the gap between an incident and a hygiene
item.** A privilege bit is a fact about the database; reachability is a fact about the deployment,
and only the second one decides what you tell a human.
⚠ **It is still worth removing, for the reason that makes it hygiene rather than nothing:** the
allowlist is a CONFIG, not an invariant. One schema added to the exposed list and it arms with no
code change and nothing that fails. Removing the grant converts 「protected by a setting」 into
「protected by not being granted」.
⚠ **And a transient table measures clean by hand, always** (ui6): `net.http_request_queue` holds
rows only while a request is in flight, so both of us found it empty and neither emptiness meant
anything. **A table populated only during an operation cannot be assessed by looking at it between
operations** — reason about what transits it, not about what is sitting in it.

🔴 **THE NUMBER THAT FLATTERS YOUR FINDING IS THE ONE YOU DON'T AUDIT** (ui6, 2026-08-27,
self-corrected within the hour — and the two halves happened in ONE message, which is what makes
it worth its own entry). They reported 「412 dim text elements across 47 screens」 as a design-debt
finding. On opening the worst file to start work, the real breakdown was: **11 of 20 were
`placeholderTextColor` — which MUST be dim, and making them ink would be a DEFECT** — plus a
status dot's `backgroundColor`, a component `tone` prop, and three exempt Latin kickers. About
four were actual dim Korean prose.
**What went wrong is one substitution: they measured `color: paper.dim` and reported it as 「dim
text」.** Different propositions — the pattern matches placeholders, dots, borders and tone props,
none of which are prose. This file's own most-repeated law (*state the sentence your measurement
licenses, then check it is the one you needed*), committed by its author an hour after writing it
into a REGISTRY row.
⚠ **THE ASYMMETRY IS THE LESSON, and it was visible in the same message:** they flagged a
**false ZERO** from an over-aggressive filter in one paragraph and shipped an **inflated 412** in
the next. One number was too low because a filter dropped real hits; the other too high because no
filter dropped irrelevant ones. **They audited the direction that produced a suspicious zero and
not the direction that produced an impressive finding** — because a big number reads as a finding
and a zero reads as a problem. **Audit findings that flatter you at least as hard as findings that
embarrass you.**
⚠ **And the honest end state is 「unknown」, not a corrected number.** Filtering to a dim colour in
a style that also sets `fontSize` gives ~209 — still an upper bound, because decorative kickers and
genuinely skippable metadata are *correctly* dim. **The violation count cannot be produced by grep
at all**, since the question is 「may the customer skip this?」 and no pattern answers it. Replacing
one confident number with another confident number would have been the same error at a smaller
magnitude. ⚠ Announcer re-measured independently and got **386**, not 412 or 209 — three patterns,
three numbers, none of them the answer, which is itself the argument.
**Consequence, and it strengthens rather than weakens the decision it informed:** an agent handed
the 412 list would have turned 29 placeholders ink and made every form look pre-filled. The
per-screen human judgment is not caution; it is the only thing that produces a correct answer.

⚠ **THE NOISE FILTER IS THE MOST DANGEROUS PART OF A SWEEP, AND IT FAILS AS A CLEAN RESULT** (ui6,
2026-08-27). Sweeping for buttons missing the 3D lip, their first pass excluded lines matching
`bar|card|chip|badge` **to cut noise** — and returned **0 candidates**. The exclusion was matching
style **NAMES** (`ctaBar`, `payCard`) while the intent was style **ROLES**: a `ctaBar` is a button.
**The filter removed the answer and reported it as a clean sweep.** A zero from a filtered sweep is
the single easiest false negative to produce and the hardest to doubt, because zero findings reads
as good news. **Rule: every exclusion in a sweep must be justified against ROLE, verified on a
sample of what it drops, and a zero result must be re-derived without the filter before it is
believed.**

**THE STANDING RULE:** before trusting a detector you just wrote, run the crudest possible version
beside it and **explain every difference in BOTH directions** — the hits it adds and the hits it
drops. ui6's now matches the raw grep at 12 and correctly excludes the 2 comment-only lines the
crude version over-counts, and every one of those deltas is accounted for. Same discipline as
reading the artifact instead of the tool's report, turned on the tool you are building.
⚠ **Corollary, same slice, same day:** their first draft also swept `toLocaleString`, which flagged
~30 correct MONEY renderings. They measured before deciding — **60 call sites, ZERO passing a date
option** — so including it buys nothing and costs the gate its life to noise. That is the
147-vs-82 `check-definer-acl` lesson applied BEFORE shipping instead of after. A gate that cries
about correct code is `--no-verify`'d within a day and then protects nothing while everyone
believes it is on.

🔴 **A TIMEZONE BUG IS INVISIBLE TO A UTC-ONLY TEST ARM — THE ARM MUST BE A ZONE THAT DISAGREES**
(ui6, measured 2026-08-27 on the club pass ticket). Planting the original device-clock read back
reddens **17 pins under `America/New_York` and ZERO under `Asia/Seoul`** — and a UTC arm would
also have passed, because UTC and KST agree on the WEEKDAY for an evening session. So a suite can
be green, thorough, and structurally incapable of seeing the entire class. The runner needs an arm
in a zone that genuinely disagrees (New_York), not merely a non-Seoul one.
⚠ **And the grep for this class both OVER- and UNDER-counts, so a blanket sweep is worse than
none**: `\.get(Day|Hours|Minutes)\(` MISSES `toDateString()` and `toLocaleDateString`/
`toLocaleString` called without a `timeZone` option (`api.ts:3079` was invisible to it), and
FALSE-POSITIVES on the epoch-safe `getTime()` family. Triage each site by where its Date came
from; never mass-replace.
⚠ **The costly shape is not a wrong label — it is SILENT FEATURE LOSS.** `owner/report.tsx:101`
builds `hhmm` device-locally and line ~102 is `if (!REQUEST_SLOTS.includes(hhmm)) return null;`
(verified at source, independently of the report): off-KST the match simply fails and the
「다음 주 같은 시간」 panel **never renders at all**. Nothing looks broken, so nobody reports it —
the mis-rendered ticket is the visible half of a class whose expensive half is invisible.
⚠ **Prefer converging on `kst.ts` (fixed +9, no Intl, Korea has no DST) over auditing the
Intl-fallback family.** Several sites are correct in the `try` and device-local in the `catch`,
and whether those catches ever run on Hermes-without-ICU is unresolved — with a THIRD possibility
nobody has excluded: an Intl that ACCEPTS `timeZone` and silently IGNORES it, which would make the
`try` branch wrong and the catch never fire. Converging **removes the question instead of
answering it**; that is cheaper than the one measurement it would take to settle, and it stays
settled.

🔴 **THE MIGRATION-NUMBER CHECK IS THREE-SIDED, NOT TWO — AND THE THIRD SIDE GROWS AS WE USE MORE
AGENTS** (ui6, measured 2026-08-27, caught before it cost a rename). REGISTRY row · remote
branches · **LOCAL WORKTREE BRANCHES**. Measured: `0144`/`0145` and suites `176`/`177` read **FREE
on every remote branch** while being actively held in two UNPUSHED agent worktrees — `ls-remote`
structurally cannot see them, only `git branch -a --format='%(refname)'` + `ls-tree` per ref does.
An agent fleet holds numbers in unpushed trees by design, so this side is now the LIKELIEST
collision surface, not the rarest.
**And re-read at COMMIT time, not only at claim time** (ui6's own agent did this and turned a
40-reference rename into a no-op): claim-time answers 「is this taken now」, the pre-push hook
answers 「too late」, and the commit-time re-read is the only check that fires while the fix is
still one command.

## Three ways a green means nothing (ui6, measured 2026-08-27 — all three in one stretch)

🔴 **① A SUITE NOT LISTED IN `harness.sh`'s MANIFEST SILENTLY DOES NOT RUN.** Five pins added,
harness returned **998/0 — the identical number as before**, and it was nearly filed as proof the
pins passed. The migration globbed and applied; only the suite was skipped. **A green whose PIN
COUNT did not move is not a green** — the count is the only thing that distinguishes 「your pins
passed」 from 「your pins were never executed」. Record the before/after totals of every slice that
adds pins, and if the delta ≠ the number you added, find out why BEFORE reading anything else.

🔴 **② A BATTERY THAT REDDENS NOTHING AND A BATTERY THAT NEVER RAN ARE INDISTINGUISHABLE IN A
SUMMARY TABLE — and the second one reads as success.** Four mutation runs came back blank because
a copied `.pgtest` left a broken data dir and every run died at the shim; a delta was nearly read
off it. Same family as §sed-exits-0 (a plant that never planted) one level up: there, the mutation
was absent; here, the whole RUN was. **Assert the run happened** — a nonzero pin total, a known-red
control, anything that could not be produced by a dead harness — before reading any row of a
battery table.

🔴 **③ A DELTA MEANS NOTHING UNTIL THE CONTROL IS OBSERVED CLEAN.** A Deno mutation lab's control
was already red before any mutation (three suites read files outside `functions/`), so every
「mutation → red」 row was measuring the lab, not the code. Run the control FIRST and look at it.
Same law as 「a control that cannot fail is not a control」, in the mirror: a control that cannot
PASS is equally uninformative.

🔴 **④ WIDENING A SQL RETURN'S *MEANING* BREAKS A CORRECT CALLER WITH NO EDIT TO THE CALLER**
(ui6, 2026-08-27, found by themselves). `swapped=false` had exactly one cause, so the handler
mapped it to `403 no_profile` and was right every time. A migration added two more causes — and
that same mapping then tells an owner with a perfectly good account that they have no profile.
**Nothing in the TypeScript looks wrong afterwards, no gate fails, and no grep finds it**, because
nothing changed on the client side; the DEFECT IS THE UNCHANGED LINE. The fix shape is to return a
`refusal` reason and map each one, with an absent reason failing CLOSED. ⚠ The general obligation:
when a slice widens what a boolean or enum can mean, the callers of that value are part of the
slice's blast radius even though the slice does not touch them — enumerate them by hand, because
no tool will point at them.

## Commit gate

🔴 **NEVER READ A TEST RESULT THROUGH `tail`. `npm test` IS A CHAIN AND `tail -1` PRINTS ONE
SUITE'S SUMMARY** (measured 2026-08-26, by two sessions independently, on their own runs). I quoted
「30 pass / 0 fail」 all session; the real run is **568 PASS / 0 FAIL** across four suites — the 30
is the LAST suite alone. A peer quoted the same 30 and measured 576 on theirs. **Nothing was hidden
either time** (exit 0, zero FAIL), which is exactly why it survives: the number is wrong in the
*safe* direction, so no failure ever contradicts it.
**Read the exit code, and count across the whole output:**
```
npm test > /tmp/t.log 2>&1; echo $?      # 0 is the claim that matters
grep -c '^PASS' /tmp/t.log ; grep -c '^FAIL' /tmp/t.log
```
⚠ Same family as filtering a harness run through `tail -3`, which discards **which pin** failed —
done here the same day. **A filter that truncates output is a filter that can hide the answer; if
you are about to report a number, do not let a pipe choose which one.**



Before every commit, from `app/`: `./node_modules/.bin/tsc --noEmit`, `node scripts/check-rpc-contracts.mjs`,
`node scripts/check-route-native-imports.mjs`, and `node scripts/check-definer-acl.mjs` — all must pass.
(`check-embed-fk.mjs` and `check-auth-surface.mjs` run in the same family.)

**`check-device-clock.mjs` (added 2026-08-27)** refuses a client module that reads the DEVICE clock
for a KST fact — `getDay`/`getHours`/`toDateString`/`toLocaleDateString` without a `timeZone`. It
exists because **the test suite structurally cannot reach the thing it needs to prove**: `app/test/*.cjs`
can import `kst.ts` and cannot import a `.tsx` route module, so re-planting a device-local read into
any of the nine screens the KST slice just fixed reddens **nothing**. The 33 KST pins prove the
primitives; they say nothing about whether a screen calls them. Same source-vs-runtime division as
`check-definer-acl` beside 98 H1 — **and the same warning: neither is evidence for the other.**

⚠ **A Seoul-only test run cannot catch this class at all.** Measured on the fix: re-planting the bug
reddens 25 pins under `America/New_York` and **ZERO under `Asia/Seoul`**, because UTC and KST agree on
the weekday for an evening session. That is why the whole class shipped unnoticed, and why
`app/test/run-kst-tests.sh` runs three zones. A green on developer hardware in Seoul is worth nothing here.

⚠ **Two narrowings are load-bearing and a future session must not "simplify" them back.** (a) `getTime()`
and `getTimezoneOffset()` are not matched — they are epoch-safe, and flagging them cries on correct
code. (b) `toLocaleString` is not matched: it is ambiguous between `Date` and `Number`, and this repo
uses it for MONEY — **measured 60 call sites, ZERO passing a date option**, so including it flagged ~30
correct price renderings on the gate's first run. That is the `check-definer-acl` 147-vs-82 failure
re-enacted, caught before it shipped. `toLocaleDateString`/`toLocaleTimeString` are Date-only and stay.

🔴 **Its first version had a FALSE NEGATIVE and the way it was caught is the transferable part.** The
comment-stripper treated a template literal as one opaque string, so `` `${d.getHours()}` `` was blanked
with the text around it — and this codebase formats nearly every date inside a template. The gate
reported **3 hits where the raw grep found 12**, while printing a confident list. **A gate with a false
negative is worse than no gate: it converts 「nobody checked」 into 「something checked and found
nothing」.** It was caught only by diffing the gate's count against the raw grep's *before* trusting it —
the same discipline as reading an artifact instead of a tool's report. **Do that for every new detector.**

⚠ Comments are stripped before matching, deliberately: two of the fourteen raw hits were comments
*documenting this very bug*, including `kst.ts`'s own header. Per the standing comment-quoting law,
documenting a fix and failing to make it would otherwise look identical. Mutation-verified six ways,
and the arm that matters is the control: **a comment quoting the removed code does NOT redden it.**

The 12 known sites are frozen in `check-device-clock-baseline.txt`; a stale entry also fails, so the
ledger shrinks honestly. Ten of the twelve are ONE open question — the Intl-fallback family — which
source cannot settle and which needs a single Hermes measurement **on a non-Seoul device**; the
baseline file carries the snippet. Escape hatch: `// device-clock-ok: <reason>` on the line, and a
bare marker with no reason is refused.

**`check-definer-acl.mjs` (added 2026-08-25)** refuses a SECURITY DEFINER `create or replace` whose
function was FIRST defined in a different file, in a file that does not itself set the ACL — the
"relying on grant preservation" class. On an apply where the function is absent, that statement is a
CREATE and the definer is born PUBLIC-executable (0116:636). ⚠ **The narrowness IS the feature and a
future session must not "simplify" it back:** the crude form — every definer recreation needs a
same-file revoke — flags **147 of 239** occurrences, because a function whose ACL is set by the file
that first defined it is entirely correct. A gate that cries 147 times is `--no-verify`'d within a
day and then protects nothing while everyone believes it is on. The **81 real pre-existing
occurrences** are frozen in `check-definer-acl-baseline.txt`; the gate's job is the 82nd. A stale
baseline line ALSO fails (delete it) so the ledger shrinks honestly and cannot silently absorb a
regression on a function someone just fixed. ⚠ This gate reads SOURCE because the harness cannot see
this class at all — migrations there apply in numeric order from scratch, so preservation always
holds and a runtime ACL sweep is green no matter how many files rely on it. The runtime sweep beside
98 H1 and this gate prove different things; **neither is evidence for the other.**
⚠ **To test a hypothetical, never edit a live migration** — even transiently, even restoring from a
copy taken seconds earlier: that is a read-modify-write with a multi-second window, and a subagent
editing the same file loses its work silently inside it (measured 2026-08-25, while testing this very
gate). Point the gate at a copy instead: `MIGRATIONS_DIR=/tmp/whatever node scripts/check-definer-acl.mjs`.

The third one (added 2026-08-13) refuses a module-scope import of a native-only package from
anything a route can reach. Expo Router evaluates **every** route module at launch, so such an
import crashes the app on the home screen before the feature is ever opened — which is exactly
what happened: `toss-sheet.tsx` imported the Toss SDK at top level, the `react-native-webview`
pod was missing, and every binary from that tree died with `RNCWebViewModule` missing. A feature
flag cannot help (a flag gates behaviour; an import is evaluated at registration), an internal
`if (…) return null` cannot help, and neither can a dev route's `if (!__DEV__) return <Redirect/>`
— **a dev-only screen can crash a production launch.** The fix shape is `*-impl.tsx` plus a
guarded `lazy()` wrapper; `src/components/toss-sheet.tsx` is the worked example.

## Branches — the trunk is `redesign-v4`

- **`redesign-v4` is the trunk and the GitHub default branch. `main` is DELETED** (Sean,
  2026-08-13: *"sure delete main if thats safe"*). It was 269 commits behind with migrations
  ending at `0036`, and every stale worktree that day traced back to sessions landing there by
  default. Deleting it converts a convention people had to remember into a constraint the tool
  enforces: **cutting from `main` now fails loudly instead of silently producing a stale tree.**
  Recoverable if ever wanted — its tip is an ancestor of the trunk:
  `git push origin f50260edb5d5b84490942f39651169f3bb433e72:refs/heads/main`.
- **Base every new worktree on `origin/redesign-v4`.** This is the one to get right *every
  time* — it is what actually caused the stale worktrees, and it now fails loudly if you don't.
- **`git remote set-head origin -a` — ONCE PER CLONE, not per worktree, and only in a clone
  that predates the default change.** `refs/remotes/origin/HEAD` is cached locally and does NOT
  follow a remote default-branch change, so until it is repointed anything resolving
  `origin/HEAD` silently means the dead branch. **A `git fetch` does NOT do it** — the ref is
  written at clone time and by `set-head`, and by nothing else (measured 2026-08-13: repeated
  fetches after the default flipped still returned `refs/remotes/origin/main`). Never soften
  this to "or after a fetch." Remote-tracking refs live in the **common** git dir
  (`git rev-parse --git-common-dir`), so every worktree of a clone inherits one run. This clone:
  already done and pruned.
- **A separate clone also needs `git fetch --prune`** once, to drop its stale `origin/main`
  remote-tracking ref.
- **Evidence the constraint works** (2026-08-13): a worktree cut AFTER `main` was deleted came
  up at trunk, 0 behind, seeing migration `0085`. Its own predecessor's two worktrees — same
  track, same day — were **269 behind at `0036`**, because they had been cut from `main`.
  Nobody had to remember a rule; the deletion made the wrong move impossible.
- This was all true in practice for weeks while written down nowhere, so every new session
  rediscovered it by getting bitten — the same class of failure as a ruling that lives only in
  an unpushed file.

## Migrations & security (server)

- ⚠ **A reviewer must attack INACTION, not only transitions.** Measured 2026-08-25 on 0128: two
  independent reviewers (codex + an executing agent) each enumerated every way a state could END —
  cancel, incident, transfer, force-close — and both missed the defect, because it arrives when
  **nobody does anything**. An owner stamps the return, the runner never taps, and a
  live-reading address grant stays open forever; no transition list can reach a state nobody
  transitions out of. Two consequences: (1) for any grant justified as "it closes when X happens",
  ask **what if X never happens** — and prefer a conjunct keyed to a fact that has already occurred
  (the counterparty's stamp) over a clock, which must choose between stranding a slow actor and
  leaving a stale grant open; (2) prefer `<> 'terminal'` over a phase ALLOW-LIST — the same 0128
  review found a runner stranded mid-custody because an allow-list did not name a phase a shipped
  RPC could reach. A list enumerates what someone thought of.
- Any migration or security-relevant change requires the adversarial cycle: scout → contract → implement → adversarial review where reviewers EXECUTE attacks → test pins → revise → verify. Harness: `supabase/tests/harness.sh` (container: PG16 at tests/.pgtest; pg_ctl must start in the same shell invocation). All pins must pass; new behavior gets mutation-verified pins.
- 🔴 **A COMMENT THAT QUOTES THE CODE IT REPLACED MATCHES EVERY GREP THAT HUNTS FOR THAT CODE**
  (2026-08-26, found by a peer verifying its own fix). Documenting-a-fix and failing-to-fix look
  IDENTICAL to `grep -c`. Measured both directions in one afternoon on the same function:
  **(a)** console #17's cap was removed from `fetchRunnerJobs` while the owner's `fetchMyBookings`
  kept it — and the comment citing Sean's 「keep everything」 AND describing the owner's symptom
  sat in the RUNNER function, 3,000 lines away. **A comment that names the symptom is the
  strongest possible false green: it reads as proof to every later grep.** **(b)** verifying the
  real fix, a grep inside the right function returned 1 — the hit was the new comment quoting the
  removed line — and for a moment read as 「the push did not land」. **So: verify against
  EXECUTABLE lines, never raw text**

  🔴 **AND A COLUMN NAME IS A SUBSTRING OF EVERY LONGER COLUMN NAME CONTAINING IT — anchor the
  word, or the grep answers a question you did not ask** (2026-08-26, fourth instance of this shape
  in one day and the only one that changed a DECISION). I reported that `club_release_payouts`
  「references `custody` and `payout_state`, so it is custody-aware」 and recommended against a
  production write on that basis. Measured on the deployed function:
  `prosrc ~ '[^_]custody[^_]'` → **false**. The only match was **`custody_phase`** — a different
  column with a different domain (`with_custodian|outbound_pending|…`) from `custody`
  (`owner_handled|runner_delegated`). A peer overturned it in one query.
  The true answer, in the checkable form: **provably blind by `payout_state = 'payable'`
  (`0072:227`)** — and doubly so, because `_club_compute_axes`'s FIRST branch forces
  `payout_state='none'` for `owner_handled`, under a live `BEFORE INSERT OR UPDATE` trigger
  (`club_v1_axes_sync`), so every write recomputes it and `'payable'` is unreachable. Blind by
  construction, not by filter ordering.
  ⚠ **「by construction」 WAS DOING WORK NO OBSERVATION SUPPORTED. Corrected the same day, and the
  correction is a template for any claim of that form** — a peer took my own list of unclosed paths
  as a coordinate and read the deployed trigger body. The honest form is a LADDER, not a verdict,
  because three of these four rungs are reads and only one is an observation:

  | path by which `owner_handled` could reach `payout_state='payable'` | epistemic status |
  |---|---|
  | INSERT | **OBSERVED** — a hand-written row returned `payout_state = none` having never been given one |
  | UPDATE | **READ from the deployed trigger** — `BEFORE INSERT OR UPDATE`, **no `WHEN` clause**, and the assignment is unconditional. Not observed |
  | custody flip `runner_delegated → owner_handled` on a row already `payable` | **READ** — `_club_sync_axes_tg` calls `_club_compute_axes(**new**)`, so the flip's own UPDATE takes the `owner_handled` branch and forces `'none'` in the same statement. The value cannot ride across |
  | trigger disabled · `session_replication_role` | **CLOSED** — two independent kinds of evidence, see below |

  Verified independently against production `prosrc` before adopting: `payout_state := j->>'payout_state'`
  **unconditional** (`payout_guarded=false`) while `service_reason := coalesce(…, new.service_reason)`
  in the SAME function is **guarded** — so the author knew how to preserve a caller's value and chose
  not to here. ⚠ **That contrast is load-bearing: an unguarded assignment that reads like an oversight
  is exactly what a later session "tidies".** It is deliberate. Leave it.
  🔴 **`pg_get_triggerdef()` DOES NOT PROVE A TRIGGER IS ENABLED — it renders a DISABLED trigger
  identically. Check `pg_trigger.tgenabled`.** (Found by codex, 2026-08-26, as a defect in a peer's
  *evidence method* rather than in any code — the more useful kind of review finding.) A definition
  read wearing the costume of a state check: it answers 「what shape is this trigger」 while being
  quoted for 「is this trigger firing」. And it is not theoretical — **the suites in this repo do
  disable this trigger**, so DISABLED is a state it genuinely enters. Values: `O` origin/enabled ·
  `D` disabled · `R` replica-only · `A` always.
  **The standing check, run at WRITE time against production and never off a migration file:**
```
select tgname, tgenabled, pg_get_triggerdef(oid)
from pg_trigger where tgrelid = '<table>'::regclass and not tgisinternal;
```
  `tgenabled` is the **state**; the def is only the **shape**. Run it before any hand-written
  production row, on any table.
  ⚠ **How the fourth rung actually closed is the model:** codex enumerated six bypass paths in
  **migration source** and found none; the live check returned **`tgenabled = 'O'`**. Those are
  **different kinds of evidence** — source says 「nothing in the repo turns it off」, live says
  「it is on right now」 — and neither implies the other. They agreed, which is worth more than
  either alone, and is precisely why the run was worth the quota *after* the answer was already
  believed.

  🔴 **The general rule: write the rung, not the verdict.** 「By construction」, 「provably」, 「cannot」
  are verdicts, and a verdict lets three read-only rungs borrow the status of the one that was
  measured. Say which rung each claim stands on, and an open rung stays visibly open.
  ⚠ The damage was not the wrong grep — it was that I turned it into a **recommendation to Sean**
  while flagging it as only 「probably」 safe. Hedging language does not make an unverified premise
  safe to act on; it just makes the error harder to challenge. **When a claim is load-bearing for
  advice, the one-query check is not optional** — and `~ '[^_]col[^_]'` or `\mcol\M` costs the
  same as `~ 'col'`. (`grep -vE '^\s*(//|\*|/\*)'` before counting), and treat a
  symptom-naming comment as evidence of nothing. Same family as the substring-detector law in
  §Operations: a check whose pattern appears in both the fixed and unfixed states is not weak, it
  is uninformative.
- 🔴 **WHAT THE DATABASE SHOWS IS NOT WHAT THE PRODUCT MEANS** (2026-08-26). `count(*) = 11`
  answers 「how many ROWS」 and was read as 「how many USERS」 — then shipped downstream as a design
  constraint (「the empty state is permanent for the current cohort」) and as a scale argument
  (「not urgent at 11 accounts」, 「the funnel cost is small」). Sean: 「the existing ones are fake so
  it's fine」. **The real user count was zero**, so every 「small enough not to matter yet」 argument
  built on 11 was rhetorical rather than load-bearing. ⚠ The damage was not the wrong number — it
  was that a PEER had already accepted the inference and was building on it, which is the
  amplification the endorsement law above describes. Ask the human what a row MEANS before making
  it a premise: a fixture, a churned account and a live user are indistinguishable in a count.
- 🔴 **A HEDGE DOES NOT MAKE A LOAD-BEARING PREMISE SAFE — IT MAKES THE ERROR HARDER TO
  CHALLENGE** (2026-08-26; the mechanism was a substring grep, but this is what let it survive
  contact with a decision, and it generalises past that instance). I could not prove a money
  cron ignored a row shape, said so explicitly — 「very likely」, 「I will not upgrade this to
  safe」 — and then **recommended against a production write on that basis**. The hedge was
  honest and it was worthless: **a claim labelled 「probably」 that a decision then rests on is
  doing the full work of a certainty while wearing the costume of a doubt.** It also armours
  itself, because it already looks appropriately uncertain, so the next reader has no reason to
  attack it. A peer overturned it in **one query** — at the exact spot I had marked as my own
  soft point.
  **Two rules fall out, and the second is the useful one:**
  **(a)** The moment an unproven claim becomes the reason for advice, it stops being a hedge and
  becomes a premise — verify it *then*, not when someone challenges it. If it is too expensive to
  verify, the advice must be 「I don't know」, not 「probably, so don't」.
  **(b)** ⚠ **A peer naming their own uncertainty is the cheapest available pointer at what to
  check first.** Read a self-flagged soft spot as a COORDINATE, not as a reason to be careful —
  it is the one place in a report where someone has already done the work of locating the
  weakness for you. (Their words, from the session that overturned mine.)

- 🔴 **A GREEN LIGHT IS EVIDENCE FOR EXACTLY ONE SENTENCE — write that sentence down, then check
  it is the one you needed** (2026-08-25; this shape appeared FIVE times in one afternoon across
  two lanes, and the people finding it were the same people committing it). Instances, all
  measured: a harness green on a partial-apply ACL hole it *structurally cannot reach*, because
  migrations always apply in numeric order from scratch · a pin sweeping ARGNAMES for
  fee/gross/commission, read as a money-surface guard, green on a PUBLIC definer · a "schema-wide"
  caller scan restricted to the `public` namespace while calling itself schema-wide · a control
  whose two arms read the SAME files through a symlink, so it could not have failed · a push
  detector whose success pattern was a substring of its own rejection message.
- **The mutation discipline that fixes it — THREE propositions, not one.** For any guard worth
  having, "the hole is real", "the pin notices something", and "the fix closes it" are three
  different claims, and a single mutation proves only the middle one — the weakest, and the one
  most often mistaken for the other two. So plant the failure **without** the fix (does the hole
  actually reproduce?) and **with** it (is it actually closed?). Worked example, 0127's Critical:
  M10 planted the absent-function path unfixed and the migration aborted on `acl==X/postgres` —
  the hole itself, not a pin's opinion of it; M11 ran the same path fixed and passed with
  `pub=false`. **A control that cannot fail is not a control**, and ⚠ **`sed` EXITS 0 WHEN IT MATCHES NOTHING — so `sed … || fallback` never runs the
  fallback, and a mutation you believe you planted may never have been planted** (measured
  2026-08-26, while mutation-testing a flaky pin: the run came back green and I nearly recorded it
  as 「the guard held」 when in fact the file was untouched). **Assert the mutation LANDED before
  running the battery** — `assert s.count(old)==1` in a python edit, or grep the mutated file — and
  treat a green mutation run as suspect until the plant itself is verified, and a battery that only ever
  reddens pins has measured your test suite, not your system.
- ⚠ **AND A PIN ADDED MID-BATTERY IS THE PIN MOST LIKELY TO BE SHAPED TO THE MUTATION RATHER THAN
  TO THE PROPERTY** (2026-08-26, handed over by a peer reviewing 0128). When a mutation reddens
  nothing, the honest response is to add an arm — but the arm you write while staring at that
  specific mutation tends to assert *the thing that mutation broke* instead of *the property the
  conjunct is there to hold*. It then passes the re-run by construction. **A blind spot that MOVES
  is worse than one that stays, because the second version looks tested.** So a repaired pin owes
  a second, independent check: state the property WITHOUT reference to the mutation, then ask a
  head that never saw the mutation whether the pin establishes it. Worked example: 0128's battery
  missed twice of six and both repairs were re-attacked by a reviewer briefed on precisely this.

  🔴 **AND THE ASSERTION MUST *GATE* THE RUN, NOT MERELY PRECEDE IT — measured by ui6, 2026-08-27,
  and this is an amendment to the rule directly above rather than a repeat of it.** They followed
  it exactly: their planter carried `assert s.count(old) == 1`. It was **necessary and not
  sufficient.** A quote-escaping bug made the plant fail, the assertion fired, python printed a
  traceback — **and the harness ran anyway and printed a perfectly plausible `1061 pass / 0 fail`
  row for a mutation that did not exist.** Two rows of their battery table were fiction, sitting in
  the column that reads as evidence, beside real rows. **An unlanded plant reports as 「the guard
  held」**, and the traceback scrolls past above a tidy table that is what anyone would quote.
  **The fix is one character of shell: `&&`-chain the run to the plant**, so a failed plant yields
  **no row at all** rather than a green one:
  ```
  python3 plant.py && (cd supabase/tests && bash harness.sh > run.log 2>&1); echo "exit=$?"
  ```
  ui6's framing is the reason this is its own entry: **「assert the plant landed」 is a check that
  REPORTS; 「make the run impossible unless it landed」 is a constraint that PREVENTS** — the same
  distinction as deleting `main` instead of asking people to remember not to branch from it, one
  layer down.
  ⚠ **Announcer audited its own set on hearing this**: every plant this session printed its
  confirmation line before its harness invocation, so no fiction rows are in the recorded
  batteries — but the STRUCTURE was ungated in every one of them. A set that happens to be clean
  under a vulnerable structure is luck, not method, and it is exactly the kind of luck that runs
  out on the run you most need to trust.

- New security-definer functions MUST have `set search_path = public, pg_temp` in the function body — ALTER-applied config is reset by `create or replace` (measured). Test 98 H1 watches the whole schema and fails the harness on any omission.
- **A `create or replace` that RELIES on grant preservation is a latent PUBLIC-EXECUTE hole. Write the `revoke` explicitly, every time** (2026-08-25, found by a blind reviewer, then confirmed as a CLASS in shipped code). `create or replace` preserves owner and ACL **only if the function already exists**; where it does not — a partial prior apply, a branch that never ran the creating migration, a rebuilt environment — it is a plain CREATE, and 0116:636 already records that new functions inherit **PUBLIC EXECUTE by default**. A `SECURITY DEFINER` born PUBLIC-executable is the worst shape this repo can produce. Found in 0127 (the restored recurring cron), then the same check against shipped code found `0121:240`'s `club_incident_settle_quote` — a money-returning definer with no revoke while **all six of its siblings in the same file have one** (0121:50, 75, 94, 185, 205, 434). Production measured correct there, because the creating migration ran first and preservation held; it is latent, not breached, and the obligation rides the next money-path slice touching it rather than a churn migration.
  ⚠ **Two green harnesses were green on this.** Neither 885/0 nor 844/0 checked owner, ACL or `prosecdef` on a recreated function, and 156's P15 sweep — which reads as a money-surface guard — sweeps ARGNAMES for fee/gross/commission and is green on a PUBLIC definer. That is a pin proving exactly what it says; the error was reading its green as broader than its sentence. **The durable guard is schema-wide, never per-function** — a per-function ACL pin only catches the function you already suspected, which by definition is not the one that bites you. The sweep lives beside 98 H1 (same standing-invariant shape, same file): every `public` SECURITY DEFINER asserted against an explicit ACL allowlist, and **every allowlist entry carries its reason** — widening the list to get green is how this guard dies.
- Views change via `create or replace` only (grant preservation) — never DROP.
- Party gate before state gate in RPCs; flat whitelisted returns.
- **Migration and suite numbers come from the REMOTE tip, never from a doc.** Several sessions
  work this repo at once and each one claims numbers. Resolve immediately before you write the
  file: `git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3`
  (same for `supabase/tests/`). Never trust a number written in a plan, TODO or handoff — on
  2026-08-13 the 0078 and 0081 slots were each claimed twice, and one rename cost ~40 reference
  edits across migrations, suites, edge functions and docs. ⚠ `ls supabase/tests | sort` is
  LEXICAL, so `117_` sorts before `97_`; use `grep -oE '^[0-9]+' | sort -n | tail -1`.
- **A number is taken when EITHER its row or its file reaches origin — the check is two-sided.**
  Collision six (2026-08-13) happened with nobody being careless: the REGISTRY row on origin said
  `0086` was free, and it was — but `0086_runner_stop_passthrough.sql` was already pushed on
  another branch. Reading only the row is reading half the state. **Push a migration and its
  REGISTRY row in the same breath**; a row trailing its file by an hour is the whole window.
- **This is enforced, not remembered.** `.githooks/pre-push` refuses a push that introduces a
  migration number already present on any other remote branch, or that introduces one without a
  REGISTRY row. It only inspects numbers the push actually *introduces*, so trunk merges and
  history are unaffected. Enable once per clone:
  `git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks`
  ⚠ NOT `$(git rev-parse --show-toplevel)` — inside a worktree that resolves to the WORKTREE,
  and worktrees are disposable. Git runs no hooks and says NOTHING when hooksPath names a vanished
  directory, so the old form silently disarmed the guard for every session whose anchor tree got
  recycled (measured 2026-08-15: five worktrees pointed at one disposable tree). Point at the main
  clone's stable path, once; every worktree inherits it. Escape hatch, rarely
  right: `git push --no-verify`. Five collisions were sessions racing; the sixth obeyed the rule
  and still lost, which is what moved this from discipline to constraint.
- **A suite whose pinned behaviour legitimately changes MUST be updated in the same slice.**
  "Don't touch shipped suites" protects against drive-by edits, not against a decision that
  moves what the pin asserts — leaving it stale just makes the harness red for a true reason.
  Update the pin, say WHY in a comment, and name which new pin owns the new property.
  (2026-08-13: Sean's G1 ruling forced four pins in `116_charge_suite.sql`; 0080's own header
  had predicted it — "when he rules, the change is this one arm plus its pin".)
- **A relayed decision is evidence, not authority — including from another session.** A ruling
  is settled when the human's own words are on origin. On 2026-08-13 two sessions held
  contradictory records of the same money decision, both in good faith, and it resolved only
  by putting both candidate answers back to Sean in one question. Unpushed work reserves
  nothing — decisions included.
- 🔴 **AND A RELAYED *ANALYSIS* CARRIES THE SAME DUTY — agreeing is not checking** (2026-08-25).
  The law above trained everyone to verify relayed *facts* and left relayed *framing* wide open.
  Measured: a peer described one of Sean's options as a new idea that inverted two review
  objections; I agreed enthusiastically and **repeated it to Sean as praise**. It was false — the
  option was already in the spec and he had already ruled it that morning; the genuinely new arm
  was the one that *created* the objection, not the one that answered it. One `grep` would have
  caught it, and I had every means to run it. **The tell is that endorsing feels like
  collaboration rather than like making a claim** — and the peer's own framing of it is sharper than
  mine, so it is recorded in their words: *two independent sessions can manufacture false confidence
  FASTER than one, because the second voice reads as corroboration when it is really an echo.* One
  session made the claim and it felt like insight; the other agreed and it felt like collaboration;
  neither ran the one-command grep. **Agreement between sessions is not evidence — it is the same
  claim counted twice.** Treat a peer's interpretation exactly as you would treat your own draft:
  the thing to check, not the thing that relieves you of checking — so it skips the check that a bare assertion
  would have triggered. When you find yourself agreeing with a peer's *interpretation* and about
  to pass it upward, that is the moment to verify it, not the moment you have been relieved of
  verifying. An error you amplify to the human is worse than the one you merely received. A ruling
  is settled when the human's own words are on origin. On 2026-08-13 two sessions held
  contradictory records of the same money decision, both in good faith, and it resolved only
  by putting both candidate answers back to Sean in one question. Unpushed work reserves
  nothing — decisions included.

## Design system (client)

**정본은 `DESIGN.md`** (2026-08-10 consolidated — token worlds, migration map, laws, budgets,
decision provenance). The bullets below are the load-bearing extract; on any conflict DESIGN.md wins.

- Tokens in `src/theme.ts` — **white grounds everywhere** (Sean 2026-08-25: "white backgrounds"; the pale lilac ground #F4F2FB and its tinted wells/hairlines retired product-wide, DESIGN.md §2 amendment). Surviving: head #221E3D, accent #6C5CE7 (accent ONLY — never a ground or wash), coral #F0765A, coralDeep #E45F41, night #1C1837 (ceremony world, deliberate keep). No swamp/forest greens (retired palette).
- Detail-text floor: **15pt** — ⚠ **corrected 2026-08-26; this line said 14 and had been stale since
  2026-08-25**, when Sean raised it with a screenshot of owner home (「some parts of the home screen
  has very small font text sizes; not acceptable and are illegible」). `DESIGN.md:145` carried the
  ruling and this extract did not, while the paragraph directly above says *「on any conflict
  DESIGN.md wins」* — so the file contradicted itself and the wrong half is the one a new session
  greps. Same failure class as the 「Sean pushes」 line that sat stale for eleven days.
  Exempt only: letterspaced uppercase **latin** kickers, serial/MRZ strings, glyphs — **Korean text
  never rides the kicker exemption** (`DESIGN.md:150`).
  ⚠ **Raising a floor is not a find-and-replace**: on owner home, moving kickers to the bare minimum
  would have preserved an inverted hierarchy, so they went to 19 (`DESIGN.md:147-152`). And the club
  world is uniformly still at 14 — `clubText.stateStrong/body/dim/vkTitle` and `mastSub`
  (`club-ui.tsx:360-377`), plus ~52 sites in `club/session/[sid].tsx`. **A new club screen written
  at 14 「to match its neighbours」 ships below the floor on day one; written at 15 it is visibly out
  of step with everything adjacent.** That is a director's call with a blast radius of all eight
  club screens, not an implementer's.
- Display fonts: Black Han Sans once per screen (useDisplayFont). Oswald numerals (useNumFont) require explicit lineHeight ≥1.2× ("BUG A" — ascenders clip without it).
- Holo foil budget: monogram + one ticket edge per surface, no more.
- Small white text never sits directly on coral/sage — use an ink plate (≥4.5:1).
- Roomy screens get big primary buttons.
- GO disc color law (owner home): coral = user's turn (idle GO / LIVE), blue family = waiting (searching/directed), sage = ready (confirmed/handoff). Hero card background carries a ~95% white wash of the current state color (GO_TINT).

## DO-NOT-REFACTOR

- **Fitness** collapsing hero (`owner/fitness.tsx`): pinned absolute overlay + ScrollView paddingTop reservation + transform/opacity native-driver only. No height/layout animation. No backgroundColor animation (non-native driver). 54-dot ring layers stay hardware-textured; center layer is separate and fades via centerOpacity.
  ⚠ **Owner-home's hero was REMOVED from this freeze on 2026-08-19 (Sean: "A").** He chose home lab ⑧ v2, which retires the GO disc and its collapse; the state law the disc carried (coral = your turn · blue = waiting · sage = ready) now rides the number of buttons + an alert line. The freeze stays for fitness only.
- Meetup screens: stage machine, polling, confirmHandoff flow are frozen; styling changes only. Seals fill on server truth only.
- Availability definitions are deliberately 3 distinct predicates — do not unify.

## Process — gstack sprint

Adopted from garrytan/gstack as the process layer. Each engagement runs Think (scout the real state; challenge the premise) → Plan (scope, contracts, arbitration) → Build (scoped Opus subagents via precision-director) → Review (adversarial, reviewers execute attacks) → Test (commit gate + harness where applicable) → Ship (commit each verified slice **and push it**) → Reflect (retro note in the handoff). Office-hours format for strategy questions; plan-ceo-review ceremony (user picks via structured options) before expansions.

⚠ **Corrected 2026-08-21 (Sean).** This line read *“Ship (commit; Sean pushes)”* and had been stale since **2026-08-10**, when Sean granted Claude `git push` (§Operations — Sean-only). It contradicted two other parts of this same file and cost at least one session a round trip asking for permission it already had. **Ship means push.** Commit each verified slice against green gates and push it the same session — do not sit on a batch. Work that exists only in a worktree is invisible to every other session and to the announcer's stranded-work sweeps, and it *reserves nothing* (the same reason a relayed decision isn't settled until the words are on origin). A 729-line uncommitted migration was nearly destroyed this way. Branch short-lived from current trunk; the conditions in §Operations — gates green first, never from a worktree carrying an unfinished migration, verify after — all still hold.

## gstack

Use the /browse skill from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.

Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup` (requires bun).

Available gstack skills:
/office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

🔴 **If this session's job is coordination rather than building — announcing, routing between
chats, allocating work, holding Sean's decision queue — invoke `/announcer` FIRST, before
anything else.** It carries the verification discipline that five parallel sessions cost a day to
learn, and a coordinating session that skips it repeats them. Any session titled "announcer",
opened to replace one, or asked to "tell the others" is that session.

**Every session should reach for skills proactively, without being asked** — from gstack
(`/autoplan` before a substantial slice · `/review` before pushing · `/qa` and `/canary` after
anything reaches an environment · `/investigate` on a live defect · `/retro` and
`/document-release` when a phase closes) and from **addyosmani's agent-skills**
(`agent-skills@addy-agent-skills`, 24 skills: `test-driven-development`,
`spec-driven-development`, `incremental-implementation`, `planning-and-task-breakdown`,
`code-review-and-quality`, `debugging-and-error-recovery`, `security-and-hardening`,
`observability-and-instrumentation`, `performance-optimization`, `git-workflow-and-versioning`,
`ci-cd-and-automation`, `documentation-and-adrs`, `context-engineering`,
`doubt-driven-development`, `frontend-ui-engineering`, `browser-testing-with-devtools`,
`api-and-interface-design`, `code-simplification`, `deprecation-and-migration`,
`shipping-and-launch`, `source-driven-development`, `interview-me`, `idea-refine`,
`using-agent-skills`). Spawn Opus 5 subagents and let them delegate further — but a subagent's
finding is a snapshot, so re-read before acting on it, and claim shared surfaces in REGISTRY's
in-flight table (path-keyed, tree named) before a subagent edits one.

🔴 **A REBASE CAN COMMIT CONFLICT MARKERS, SILENTLY — GREP THE FILE, NOT THE EXIT STATUS**
(measured 2026-08-26 on `REGISTRY.md`, and verified by a peer who said they would have walked
into it).

`git add <file>` + `git rebase --continue` does **not** check that the file still contains
`<<<<<<<`. A resolver script whose pattern does not match the marker shape leaves them in place,
the `add` stages them, the rebase reports **success**, and the commit lands with three conflict
markers inside a file every slice reads. Measured: the resolve was a regex, the regex missed, its
own assertion fired — and the commit happened anyway, because the assertion was in the resolver
and the commit was a separate command.

**REGISTRY.md is where everyone will meet this**, because it is the one file every migration slice
touches, so every parallel slice conflicts on it and every one of those conflicts is resolved in a
hurry at the end of a long task.

**The check, and it is three shapes not one** — a resolver that strips `<<<<<<<` and `>>>>>>>` but
leaves the bare `=======` produces a file that greps clean on the obvious pattern:
```
grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file>     # must be 0, BEFORE the commit
```
Same family as every other law in this file: the tool's report is a claim, the artifact is the
fact. And the same remedy — **read the file back from origin after the push** — is what catches it
if the pre-commit grep is forgotten.

⚠ **A number collision has the same shape and the same only-fix.** Two-sided at claim time is
CORRECT and can still lose, because it answers 「is this number taken **now**」 while the question
that bites is 「will it be taken **when I push**」. Measured 2026-08-26: `0135`/suite `168` were
free at claim, another session landed them during the build, and the push 「succeeded」 — onto a
trunk where `ls-tree` returned *their* filename in my slot. Nothing in the claim-time check could
have seen it. **Read the artifact back from origin after every push; renumber from there.**

🔴 **`git add … && git commit` IS UNSAFE WHILE ANY OTHER AGENT CAN WRITE YOUR TREE — use
`git commit -- <explicit paths>`** (added 2026-08-25; failure measured, fix measured).

**Two agents in one worktree share ONE git index.** `git add <named paths>` controls what you
ADD; it does not un-stage what someone else already staged. A commit naming three files can
silently carry another agent's staged work — including `git rm` deletions, which leave no dirty
file behind to notice afterwards. It happened here: a suite-header commit swallowed four
client-file deletions from a different slice, under a message that mentions none of them. **The
tree was correct and only the attribution was wrong, which is exactly why nobody catches it** —
no failing gate, no conflict, no dirty file, no symptom. The subagent reported it; the author
did not notice and would not have.

The claims table above cannot help: claims stop two sessions editing the same PATH, and here the
paths never overlapped. The collision is in the INDEX, not the files.

**THE FIX — mechanical, measured in a scratch repo on 2026-08-25:**
```
git commit -m "msg" -- path/one path/two      # commits ONLY those paths
```
With another agent's modification AND deletion sitting staged, `git add mine && git commit`
produced a 3-file commit; `git commit -- mine` produced a 1-file commit **and left the other
agent's staged work still staged**, untouched, for them to commit themselves. Prefer it always —
it costs nothing when you are alone in the tree.

⚠ **NEW FILES: `git add` it first, then still put the pathspec on the COMMIT.** The pathspec form
**fails on an untracked file** — `error: pathspec 'new.md' did not match any file(s) known to
git`. Measured in a scratch repo, all four cases: the failure is **loud and harmless** (it aborts,
changes nothing, leaves the index exactly as it was), `git commit -a -- <path>` is refused outright
(`fatal: paths … with -a does not make sense`), and `git add <path>` **then**
`git commit -m … -- <path>` commits ONLY that path while another agent's staged stray **stays
staged** for its owner. **The pathspec on the COMMIT is what excludes their work — the `add` is
only registration.** This matters more than it looks: a session that hits the error and "falls
back" to plain `git add` + `git commit` lands straight in the bug this rule exists to prevent,
now with a false sense of safety. Found within an hour of the rule being written, by a peer whose
fallback re-pushed a stale cherry-pick — benign by luck, not by design.

⚠ **Know exactly what the pathspec form does, because its trap is in the same family as the bug
it fixes:** it commits each named path's **WORKING-TREE** state and ignores the rest of the
index. That is precisely why it is safe here — and precisely why it **must never be used to land
a `git add -p` partial stage.** Measured separately (2026-08-25): with `staged-version` staged
and `worktree-version` on disk, `git commit -- mine.txt` landed **worktree-version** and left the
index clean — the deliberately staged subset was silently discarded, no warning. So: pathspec
form when another agent can write your tree; plain `git add` + `git commit` when you are alone
and staging a deliberate partial. Never the two habits mixed.

⚠ **"It's only a reviewer, it can't write" is FALSE and is the belief that produced this bug.**
An agent type without Edit/Write but **with Bash can write** — `echo >`, `git add`, `git commit`
all run in your tree. A peer audited its own day, reported its reviewers "read-only by
construction", then corrected itself: its `precision-reviewer` carries Bash, so its clean result
measured that agent's BEHAVIOUR, not its capability. The criterion is **"can this agent write to
my tree?", where Bash counts as YES** — never "does its type list Edit/Write". The only genuine
by-construction safety is a sandbox that refuses writes (`codex exec -s read-only`); everything
else is discipline, and by this file's own law discipline fails eventually.

**The durable form, when you can pay for it:** give write-capable or Bash-carrying agents their
OWN worktree (`isolation: "worktree"`), so the index they share is not the index you commit
from. Then the timing question stops existing instead of having to be remembered.

🔴 **AND THE SAME HAZARD IS IN THE WORKING TREE, NOT ONLY THE INDEX — never write to a file an
agent currently owns, not even transiently.** Added within the hour by the author of the rule
above, who then did exactly this: to test a gate, appended a line to a migration a subagent was
actively editing, ran the check, and restored the file from a copy taken seconds earlier. **A
copy-modify-restore is a read-modify-write with a multi-second window**, and any edit the agent
lands inside it is overwritten with older text — silently, no conflict, no error, and the file
still looks plausible afterwards. "It looks present" is not "nothing was lost"; only the agent
knows what it had written, so TELL IT and let it verify rather than inspecting the file yourself
and concluding you got away with it. The correct move costs nothing: **run the check against a
copy outside the worktree.** A scratch dir with the script and a symlink to `supabase/` resolves
the same relative paths and touches nothing anyone owns.

- Product ideas/brainstorming → /office-hours
- Strategy/scope → /plan-ceo-review
- Architecture → /plan-eng-review
- Design system/plan review → /design-consultation or /plan-design-review
- Full review pipeline → /autoplan
- Bugs/errors → /investigate
- QA/testing site behavior → /qa or /qa-only
- Code review/diff check → /review
- Visual polish → /design-review
- Ship/deploy/PR → /ship or /land-and-deploy
- Save progress → /context-save · Resume → /context-restore
- Author a backlog-ready spec/issue → /spec

Project-specific: `/autoplan` is the standing gate for **any migration or money-path change**
(0059 doctrine). Its subagents are read-only reviewers — they do not replace the harness.

## Git hygiene (Cowork cloud sessions)

The device mount cannot unlink files: stale `.git/index.lock` survives even `git status`. Before EVERY git command: `mv .git/*.lock _to_delete/git-locks/<unique-name>` (never `rm`, never in a `&&` chain that aborts on mv failure). Staged file transfers must be md5-verified against the device; recently-changed files travel via base64 through device_bash, not the staging cache (proven stale 4×).

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
