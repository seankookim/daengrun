# 0118 independent verification + fleet corrections — 2026-08-24

Written by the session that read `docs/session-handoff.md` and re-verified it. Everything below is
tagged: **[measured]** I ran it · **[verified-code]** I read the committed blob · **[reported]** an
agent said so and I did not confirm · **[predicted]** inference, labelled as such.

---

## 1. Corrections to the 2026-08-21 handoff

Three of its lines are wrong. All three were written in good faith and went stale or looked at the
wrong object.

**(a) "0118 … NEVER MEASURED — no harness has ever run on it" is FALSE. [measured]**
The REGISTRY row on `claude/club-fee-slice` claims a full measurement, and the claim reproduces:

| Check | Row claims | I measured | Match |
|---|---|---|---|
| slice present | 739/0 | **739/0**, 8 `[ccf]` pins P1–P8 green | ✅ |
| slice removed | 731/0 | **731/0**, zero `[ccf]` pins | ✅ |
| P1 platform_fee 0→v_plat | 736/3 [P1,P2,P4] | **736/3**, same three | ✅ |
| P5 drop `owner_profile_id = auth.uid()` | 738/1 [P5] | **738/1** | ✅ |
| P8 drop in-body `search_path` | 737/2 [98 H1, ccf P8] | **737/2**, `[hard] H1` + `[ccf] P8` | ✅ |
| P6 first-writer `=0`→`true` | 738/1 [P6] | **738/1** | ✅ |
| P7 drop sixth UNION arm | 738/1 [P7] | **738/1** | ✅ |
| delete `comp:` advisory lock | author PREDICTED [P6]; row records MEASURED 737/2 [P2,P6] | **737/2 [P2,P6]** | ✅ |

8 full harness runs, `git checkout -- .` between each with a clean-tree verify, every mutation
grep-proven present before its run. **6 of 20 mutations re-run — the other 14 are corroborated by
sample, not independently verified.**

The decisive evidence is the last row: the row records a case where its own author's prediction was
**wrong** and reports the measured value instead. My independent run landed on the measured value,
not the predicted one. A fabricated record does not invent a miss against itself.

**(b) "Counsel-brief de-staling PRODUCED NOTHING. `claude/wf-docs` has 0 commits" — wrong branch. [measured]**
The work is on **`claude/wf-docs-unblock`**: 9 commits dated 2026-08-21, 13 doc files, every blob
absent from trunk. It includes both counsel briefs — `docs/biz/location-law-counsel-brief.md` and
`docs/legal/contract-status-counsel-brief.md` — i.e. the artifact with a legal clock on it.
It was on **no remote**. I pushed it to origin today; it is no longer at risk.

**(c) Trunk tip.** The status table says `168d29f`; trunk is `2bbaa4a`. The doc was amended after its
own table was written. Harmless, but do not cite the table for trunk state.

---

## 2. 0118 is measured — and it is NOT landable. Three blind reviewers, all FIX-FIRST.

A fresh Codex voice and two Claude lenses (money, security) reviewed the code without access to
`REGISTRY.md` or any handoff. **All three independently found the same blocker.**

### BLOCKER 1 — `club_finish_session` charges a 20% no-show fee with no time and no attendance gate
Found by all three, from three different angles. **[verified-code]** — I confirmed it myself against
the committed blob at `d1a9ea4`.

The money predicate (`0118:672-673`) is exactly:
```sql
where b.club_session_id = p_session and b.status = 'confirmed' and b.runner_id is not null;
```
Grepping the whole function (`0118:613-690`) for `scheduled_at|now()|clock_timestamp|checked_in_at`
returns **two hits, neither in the money path**: a recap headline count 28 lines earlier, and a
`scheduled_at` used as display meta in a feed post.

Consequences, each named by a different reviewer:
- **Time.** A host can close *tomorrow's* session today and every owner is charged 20% for a no-show
  that has not had the chance to occur. The suite pins the exploit rather than refusing it — its
  fixture builds a session **90 minutes in the future** and asserts the fee exists.
- **Attendance.** An owner who **checked in and handed over the dog** is billed, and the runner who
  walked away is *credited* the supply half — `session_dogs.checked_in_at` is read for the headline
  and then ignored for the money.
- **Escalation.** Post-flip this mints a real intent; three declines then lock the owner out of all
  future booking via `owner_has_unsettled_charge`.

The missing time gate is inherited from `0045`, but 0045 charged nothing. **0118 is what attaches
money to it**, so it is 0118's to fix.

### BLOCKER 2 — `club_config` is not the single source of truth [verified-code]
Sean's ruling was *"Use the club rules as written"*, with club_config as the only source. Four sites
copy the ruled numbers into code as live fallbacks:
```
0118:362  coalesce(club_cfg('fee_platform_split_pct'), 50)
0118:450  coalesce(club_cfg('cancel_post_accept_pct'), 20)
0118:556  coalesce(club_cfg('cancel_post_accept_pct'), 20)
0118:559  coalesce(club_cfg('cancel_free_hours'), 24)
0118:560  coalesce(club_cfg('cancel_late_pct'), 10)
```
`club_config.value_num` is **nullable** and `club_cfg` is a bare select (`0048:24-26`), so these are
reachable paths, not dead defence: NULLing `cancel_late_pct` does **not** fail closed — owners are
still charged 10%. (`0118:676`'s `coalesce(club_cfg('host_fee_krw'), 0)` is *not* a violation — it
falls back to zero, which fails closed.)

### Other findings, not blockers
- **[major]** the new CHECK constraint evaluates to NULL and accepts the row — trap class (b) again.
- **[major]** the ladder decision and the persisted fee event read two different clocks.
- **[major]** suite 153's party-gate pins run as database owner, so they would stay green if either
  RPC lost `SECURITY DEFINER` or gained a client grant. A pin that cannot fail is not a pin.
- **[major]** the sweep's cron registration can fail silently and nothing else calls it.
- **[minor]** `_club_try_mint_cancel_fee` reports success and clears the ops failure queue when
  nothing was minted.

### Two findings deliberately NOT treated as defects
The reviewing agent argued against Codex on both, and I agree with its reasoning:
- **Unaccepted late cancel sends 100% to platform.** With no accepted runner there is no runner share
  and no profile to accrue to; the suite asserts this deliberately. **This is a question for Sean,
  not a bug** — the ruling says 50/50 and never named the no-runner case.
- **`not exists (ledger_items where booking_id)` idempotency.** Weak, but it is a byte-level copy of
  the shipped house pattern in `0085:81`, and `ledger_items` has no unique key by design across eight
  writers. Fixing it properly is its own slice.

---

## 3. The flag-window question was built on a premise that does not hold [reported, spot-verified]

I was going to ask Sean to choose between flipping the late-protocol flag at deploy (A) or teaching
the client to read it (B). **The investigating agent refuted the premise**: the shipped lateness copy
never claims the server is acting — three branches say the opposite and a fourth hands the action to
the user. So the flag window costs nothing, and **option C (deploy with the flag NULL, change nothing)
is available for free.**

**But it found a real deploy-day defect that neither A nor B addresses. [verified-code]**
`app/src/store.ts:228-235` (`cancelFeeRateFor`) is a client-side mirror of the 0066 ladder and returns
`enrouteFeeRate` **unconditionally** for any `runner_enroute` row. It knows nothing about 0117's new
waiver arm. The moment 0117 lands, for a stale en-route booking past the ceiling:

- `owner/schedule.tsx:706` prints "취소 수수료 (50%) 12,450원"
- `:712` promises the fee goes **전액** to the runner as compensation
- the server takes **0** and records **no** runner compensation
- `:744` then prints "청구되는 금액은 없어요" — two consecutive screens contradicting each other

`quote_cancel_fee` was built for exactly this (Sean reversed 0066's no-client-quote posture on
2026-08-21), and there are **zero client call sites** — only a comment at `schedule.tsx:167` recording
the swap as owed "in the same window as the 0117 deploy". **[verified-code]**

⚠ A client session IS actively building late-booking client work right now (worktree
`daengrun-redesign-v4-77ea99`, committed `0c9745b` at 10:34 today, unpushed at time of writing).
Any statement that "no branch is building the stage-2 client surface" is true of origin only.

---

## 4. Fleet hygiene executed today

**Removed** (each proven: HEAD an ancestor of trunk, residual diff junk-verified by hand — a mode
bit, one `.gstack/` line, an already-archived handoff): 10 worktrees, 15 → 6 remaining.
**Deleted** `claude/korean-games-planning-dfc80b` — all 11 commits are byte-identical patches already
on trunk under different SHAs (rebased), verified commit-by-commit.

**Method note worth keeping.** My own first sweep called those 11 commits "stranded, nowhere on
origin". Both methods I used — a patch-id sweep and `git branch -r --contains` — compared only
against branches *ahead of trunk* and against exact SHAs, so **neither could see content that had
been rebased into trunk itself**. The right check is patch-id against trunk's own history. My
conclusion (superseded) happened to be right; I reached it by spot-checking one function, not by the
sweep. A sweep with a blind spot that returns the right answer is still a sweep with a blind spot.

**Protected and untouched:** the four slice branches, `claude/wf-docs-unblock` (now pushed), and the
worktrees `daengrun-redesign-v4-77ea99` (live, another session committing into it),
`client-redesign-v4-work-3e224f`, `handoff`, `measure-0118`.

⚠ **A "merged branch" does not make its worktree disposable.** `daengrun-redesign-v4-77ea99`'s branch
is fully merged to trunk while the tree held 322 uncommitted unique lines. A merged→disposable rule
would have destroyed them. Also note the branch `claude/daengrun-redesign-v4-77ea99` and the
*directory* of the same name are **unrelated** — the directory is checked out on a different branch.

---

## 5. What needs Sean

1. **0118 blocker 1** — the no-show fee needs a gate. Which evidence: time (`scheduled_at` passed),
   attendance (`checked_in_at`), or both? This is a policy question, not just a patch.
2. **0118 blocker 2** — confirm the four coalesce fallbacks should be replaced by a loud failure
   (`missing_club_config:<name>`) so config is genuinely the single source.
3. **Unaccepted late cancel** — the ruling says 50/50 and never named the no-runner case. Does the
   supply half go to platform, or is the fee 10% total with no split?
4. **Reason privacy (0117)** — he authorized *asking* and *storing*. He was not asked about the
   counterparty reading the text, nor about it surviving account deletion. Both are true in the code.
   The window is open *only until the flag flips* — free now, a redaction against write-once tables
   later. See the decision brief in this session's workflow output.
5. **The 0117 client mirror** — the cancel-fee quote swap is unstarted and is a genuine deploy-day
   blocker, independent of the flag question.

---

# PART 2 — Sean's rulings, what shipped, and what the fleet found

Appended the same day, after the verification above turned into work.

## 6. Sean's rulings — verbatim

> **"1C, 2A, 4B — do it, and scope 5."** [end of his words]

> **"fix both and re-measure, ship strict on grace, and sure on ui6. off for break, keep going"** [end of his words]

Decoded, with what each now binds:

| # | Ruling | Binds |
|---|---|---|
| **1C** | the club no-show fee needs **both** gates — time AND attendance | `club_finish_session`'s fee arm only; the session must still finish and still refund |
| **2A** | `club_config` is the single source; a missing value fails **loud** (`missing_club_config:<name>`) | the four ladder sites; `host_fee_krw` stays `coalesce(...,0)` because it fails CLOSED |
| **4B** | a party reads only their **own** stop-reason | `fetch_checkin` / `answer_checkin` §7 |
| **grace** | **ship STRICT** — no grace interval on the time gate | a host finishing at `scheduled_at + 1s` bills every un-handed-off owner. If that ever changes it is one term plus one config key. Decision, not oversight. |
| **ui6** | allocation of R2/R3/R5/R6/R7/R8/R9/R17 to the client session **confirmed** | settled in his own words, not by relay |

**Still unruled and still blocking:** R11 (the 10% tier pays an absent runner ₩1,245 while charging
the wronged owner ₩2,490 — the stalemate rule inverted) · R13 (does the stalemate rule cover granted
km?) · R12 (what is the runner *told* when the ceiling waives their 50%?) · §4.2 · the 0118
unaccepted-late-cancel split (his ladder ruling says 50/50 and never named the no-runner case).

## 7. 4B — LANDED

`origin/claude/late-booking-server-stage2` @ **`9aaeb7b`**, harness **785/0**.

`fetch_checkin` now emits `owner_has_reason` / `runner_has_reason` to **both** readers and merges the
caller's own text back in. The counterparty's key is **absent, not null** — `runner_reason: null` sent
to the owner would be a false statement about the record in exactly the case where a reason was given,
and would contradict the boolean beside it.

Mutation-verified twice: reverting the narrowing reds **L48 and L48b together**; breaking *only* the
inheritance (`answer_checkin` re-adding the keys while `fetch_checkin` stays narrowed) reds **L48b
alone** — which is what proves L48b is not a duplicate of L48. The leak assertion greps the whole
serialized payload, not just the key: its failure text quotes the planted token verbatim.

⚠ **L20's prose was corrected, not its assertions.** It claimed the reason renders "to the parties",
but every read it performs is under the author's own JWT. The word was wrong when written, and that
was the hole: **no shipped pin ever set the JWT to the counterparty in either direction**, so 4B could
have been reverted with the suite staying green.

## 8. 0118 — BLOCKED, in a fix round. The gate was inert.

The 1C attendance gate read `session_dogs.checked_in_at`. That column is **unproducible for a
delegation-only owner**, verified at source:

- `session_checkin` (`0030_hi_club.sql:254-259`) raises `not_joined` unless a `session_people` row
  exists, and only then stamps `checked_in_at`.
- `session_delegate_dog` (`0048:135-153`) deliberately creates none —
  `[R4] 멤버십 자동 가입 폐지 — RSVP/위탁 ≠ 가입 (가입은 club_join 명시 행위)`.

So the gate was inert for exactly the population 1C exists to protect: the owner who handed over their
dog is still billed 20%, the runner who walked away is still credited the supply half.

**And the pin passed anyway** — P10's fixture called `session_rsvp` first, manufacturing the membership
row a real delegating owner never has. A pin passing for the wrong reason, past an explicit instruction
to guard against exactly that. A blind reviewer caught it.

**Second defect, an interaction between the two rulings:** 2A's `club_cfg_required` raises *inside*
`club_finish_session` with no handler, so a NULL ladder key rolls the whole transaction back — the
session never reaches `done` and the refunds never commit. 1C requires finish+refund to survive. Being
fixed by making the bad state **unreachable** (refuse NULL on the four ruled names at write time)
rather than by catching the exception, which would reintroduce the silent fallback 2A removed.

⚠ **The methodological lesson, which cost this round:** the reviewer proposed
`bookings.owner_confirmed_handoff_at` as the replacement. Its only writer is an *edge function*
(`transition-booking/index.ts:314`), and whether a club booking's client ever calls `confirm_handoff`
could not be established by reading. **A replacement signal is being established empirically — by
driving the real RPCs in the harness — before anything is written.** Installing a second unproducible
signal would reproduce the same bug one column over. *A gate reading an unproducible column is worse
than no gate, because it looks closed.*

## 9. Cross-session — what the fleet exchange actually produced

**A pin-label collision, caught before it entered history.** Two sessions independently claimed
`[L47]` in `152_late_booking_suite.sql`, an hour apart, both cut from `e132b3d` where L46 was the
highest. The pushed one kept it; mine moved to **L48/L48b**. Worth recording because of the failure
mode: **a duplicate `[L47]` would NOT have failed the harness.** Two arms report under one name, the
suite passes, and every future mutation map citing `RED=[L47]` is ambiguous forever. It corrupts the
record rather than the code. The other session is adding a pin-label uniqueness assertion — as its own
pin, so it runs even when everything else passes.

**A harness claim, narrowed.** The broadcast form was "harness.sh connects as `PGUSER=postgres`, so no
privilege bug of this class can surface." Too broad: most ACL pins here are `has_function_privilege`
**catalog lookups**, which take the role as an argument, are correct regardless of connected role, and
cannot be plan-cached because nothing is planned. The surviving claim is narrower and real: **an arm
that proves a privilege by EXECUTING as another role can be vacuous**, because EXECUTE is checked at
parse time and plpgsql caches plans per session. `discard plans` appears in **zero** suites. Sweep
target is the `set local role` cluster in `100_wave3_suite.sql`, not every privilege pin. Both trunk
records were corrected by their author.

**A relayed allocation, held as evidence until confirmed.** A peer reported that Sean had assigned
them eight findings. Rather than drop the item or treat it as settled, it went back to him as a
one-word confirmation — cost him one word, could not ask him something already answered, and could not
record an allocation he never made. He confirmed.

## 10. Owed, not done

- **REGISTRY rows are stale.** 0117's row predates 4B by four pins; 0118's mutation-map header still
  says the shipped map "has NOT been re-measured" — it now has been (742/0 plus this fix round).
  Deliberately not touched while another session is pushing to 0117.
- **R20** (three RPCs answer `not_party` where `quote_cancel_fee` answers `not_found` — an enumeration
  oracle) is unowned. Declined for 4B on purpose: LOW, pre-existing repo-wide in shipped
  `confirm_return_tx`, and it moves three shipped assertions. Do not expand a ruled slice with an
  unruled consistency fix.
- **The 0117 client mirror** (`store.ts:228-235` returns 50% for any `runner_enroute` row, knowing
  nothing about 0117's waiver arm) is scoped but unstarted, and is a genuine deploy-day blocker.

---

# PART 3 — the slot-based ruling and the autonomy grant

**Sean, 2026-08-24 (after the supply-comp explainer):**
> **"go ahead with that and all other queues. i gave you fable, so use it to orchestrate workflow with opus 5 models"** [end of his words]

Decoded:
- **Supply compensation is SLOT-BASED.** The runner's half of a club fee compensates the *held slot*,
  not attendance. Consequences: the both-parties-no-show credit is CORRECT behaviour and comes off
  the queue · R5-class timer cuts against a runner who held a slot are unambiguously defects (already
  fixed by ui6) · the unaccepted-late-cancel supply half has no basis when no slot was held — the
  **relabel** ships now (honesty law: the row must not claim to compensate supply that never existed);
  whether the owner should then pay 5% instead of 10% stays queued as the one remaining money number.
- **"all other queues"** = proceed on the queue items carrying a documented recommendation, marked 🔵
  under this blanket grant: R10 (allow-list source filter), R11 (hoist `cancel_moves_no_money` above
  the tier split), R12 (the runner's push names the waiver rule), R13 (verify-then-apply — ui6's L37
  may already encode the recommended shape). **Still genuinely his, not proceeding:** §4.2 (no
  recommendation exists), the 5% question above, and the handoff-durability column (documented
  residual stands).
- **Orchestration**: session model is Fable; all workflow agents run **Opus 5** explicitly.

Round 3 of 0118 landed at `206bb1f`, **745/0**, 7 mutations + 1 control, zero theatre. The final
blind review of round 3 died on a 529 server overload — it is superseded by the round-4 review,
which reads the same diff plus the slot-based edits.
