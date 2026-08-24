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
