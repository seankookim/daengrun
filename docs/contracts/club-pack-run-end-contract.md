# 러닝 종료 — the club pack run-end. Contract.

**Status: CONTRACT ONLY. No migration and no suite were written by this session.** Migration and
suite numbers are deliberately absent: they come from the remote tip at build time
(`git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3`), never
from this file. At the moment of writing, origin/redesign-v4 is at migration `0128` / suite `162`,
and `0129`/`163` are CLAIMED by this same tree (`REGISTRY.md:188`) but are **untracked working-tree
files** — so this slice is at least `0130`/`164` and must re-resolve.

**Provenance.** Sean, 2026-08-25, round 7, verbatim on trunk at
`docs/plans/2026-08-25-round6-picks-and-live-map.md:207-215`:

> "for the host the run end and a session end should be separate things. the run end applies once
> the pack arrives at the ending point and once that is clicked it ends all the other runners' runs
> and syncs so they all see their respective records and cards and etc on their screens so that they
> can move on to the transfer etc. the session end button is something that follows afterwards …"

and the plan's own table (`:224-225`):

| Action | When | What it does |
|---|---|---|
| **러닝 종료 (RUN END)** | the pack reaches the finish point | **ends EVERY runner's run at once** and syncs, so each runner lands on their own record/card and can proceed to the transfer |
| **세션 종료 (SESSION END)** | after, as supervision | closes the session, shown with the pair list and each pair's live status |

This contract covers **러닝 종료 only** — the server capability. 세션 종료 already exists and is not
touched. The supervision board (R7-2), the owner's "can't make it" alert and the three-party chat
(R7-3) are named in §10 as explicitly out of scope.

---

## 0. What was measured, including where the brief that commissioned this was wrong

Every claim below was read at source in this tree. Three of the premises handed to this session were
inaccurate and the corrections change the design, so they are recorded first.

### 0.1 CONFIRMED

- **`end_run_tx` takes ONE booking and refuses clubs.** `0083_run_end_flow.sql:353` (signature),
  and `0083:383`: `if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;`
  preceded by `0083:382` — `-- ── marketplace only (plan §7: "clubs are out of scope" is not a
  server guard)`. Its comment calls it the marketplace freeze (`0083:26`, `0083:841-847`).
- **There is no fan-out over runs anywhere, and no host-initiated run action at all.** Verified by
  reading every function that writes a run-lifecycle column.
- **No club booking can carry `bookings.run_ended_at`.** The column is declared at `0083:164` and
  written in exactly one place, `0083:441` (`update bookings set run_ended_at = v_now …`), inside
  `end_run_tx`, which refuses clubs at `0083:383`.

### 0.2 REFUTED — `club_finish_session` does far more than one UPDATE, and 0031 is six definitions stale

The brief cited `club_finish_session` (`0031:107`) as *"exactly one thing — `update club_sessions
set status = 'done'`"*. That describes the **0030/0031-era body**. The function is
create-or-replaced seven times: `0030:268`, `0031:107`, `0037:283`, `0038:257`, `0045:339`,
`0048:392`, and **the live definition is `0118_club_cancel_fee_collection.sql:1102`**. What it does
today, in order:

1. `0118:1115-1119` — party gate FIRST, host-only, row locked:
   `select * into s from club_sessions where id = p_session and host_profile_id = auth.uid() for update;`
   → `not_host_or_closed` on both "not found" and "wrong status" (one answer, no existence oracle).
2. `0118:1121` — `if _club_dogs_unresolved(p_session) > 0 then raise exception 'dogs_not_returned'; end if;`
3. `0118:1122-1127` — `incident_unassigned` if any unresolved incident has `case_owner is null`.
4. `0118:1129` — `update club_sessions set status = 'done'`.
5. `0118:1136-1147` — recap feed post + participant notifications (checked-in ≥ 1 only).
6. `0118:1149-1152` / `:1250` — refunds every un-run booking with `cancel_reason = 'club_not_picked_up'`.
7. `0118:1156-1249` — the R1C no-show fee (three gates, all in the WHERE).
8. `0118:1255-1263` — the host fee, **conditional on at least one `completed` booking existing**.

Steps 2, 6, 7 and 8 all matter to this slice, and step 8 is the one this design puts at risk (§7.3).
It remains true, and is the load-bearing part of the brief's claim, that **`club_finish_session`
never touches a run or a booking's run state** — it refunds and it closes; it does not end a run.

### 0.3 REFUTED — there IS a club run-end today. It is the SETTLE, and it is the money event.

The brief's conclusion ("there is no club run-end primitive to fan out over") is right about the
*fan-out* and wrong about the *primitive*. Measured chain:

- `app/app/club/run/[sid].tsx:264` — the **runner's** club run screen calls `settleRun(...)`, once
  **per dog**, computing that dog's km client-side by summing its own uploaded trace
  (`[sid].tsx:255-262`).
- `settle-run/handler.ts` has **no club branch at all** (verified end to end). It asks SQL for the
  price — `handler.ts:150-155` calls `compute_runner_payout`, live body
  `0102_payout_commission_guard.sql:41-121` — and passes the six returned numbers verbatim into
  `settle_run_tx` (`handler.ts:173-184`). `handler.ts:132-139`: *"THE PRICE COMES FROM SQL. ALL OF IT."*
- `settle_run_tx` (live body `0083:628`) skips the return seal for clubs — `0083:681`
  `if v_club is null then`, with `0083:678-680` explaining *"Clubs keep their own custody machinery …
  so the gate is marketplace-only"* — and then, at **`0083:720`**, executes the ONLY live writer of
  `completed` in the repo: `update bookings set status = 'completed' where id = p_booking and status = 'active';`
- That UPDATE fires `club_custody_transition_v2` (`0045:64-65`) → `_club_custody_transition_v2`
  (`0045:34`, never redefined since), whose completed arm at **`0045:55-60`** is the club's whole
  return doctrine:
  ```
  elsif new.status = 'completed' then
    -- [R2 핵심] 정산 ≠ 반환: 국면만 반환 대기, 커스터디는 러너 유지, 정산액은 earned
    update session_dogs set
      custody_phase = 'return_pending',
      payout_state = case when payout_state = 'none' then 'earned' else payout_state end
    where id = v_sd.id and custodian_type = 'runner';
  ```
- And `settle_run_tx` writes the runner's ledger row unconditionally — `0083:754-755`,
  `insert into ledger_items (...)`, **no club guard** — and `settle-run` then charges the owner
  through the same generic path (`handler.ts:221` → `handler.ts:296-300` `mint_settle_charge_intent`
  → `0084:288-289` → `compute_owner_charge`, `0080:236-297`, which reads only booking columns and
  knows nothing about clubs). `0081_club_money_gates.sql:22-31` says it in its own words: *"Club
  bookings really do reach the charge branch; nothing about the club path is excluded from it at any
  point."*

**Therefore: today, "ending a club run" and "paying for a club run" are the same server call.**
That single sentence is the constraint the whole design turns on, and it is why the naïve fan-out —
"host taps, server settles everyone" — is the one shape that must not be built (§4.1).

### 0.4 REFUTED — the shipped host party gate is NOT uniformly "host + backup host"

The brief asked for a gate "consistent with the shipped pattern". There are **two** shipped
patterns, each with a written reason:

- **Session mutations are host-only, deliberately.** `club_finish_session` `0118:1113-1114`:
  *"PARTY GATE FIRST. This fixture also remains NULL-safe when `backup_host_profile_id` is NULL:
  only the named host owns this mutation."* Same for `club_cancel_session` (`0038:234-236`),
  `session_approve_dog` (`0084:620`), `session_assign_dog` (`0038:28`), `session_propose_dog`
  (`0048:452`).
- **The live, on-the-ground custody action admits the backup host, and says why.**
  `session_host_force_resolve`, live body `0070_incident_accountability.sql:171`, gate at
  `0070:195-196`, with the reason at `0070:191-193`: *"백업 호스트도 부른다. 종전엔 호스트만이었는데,
  그러면 이 RPC는 **가장 흔한 클럽 모양에서 아무도 못 쓴다**: 소규모 클럽의 호스트가 곧 러너라
  self_override로 막히고, 백업은 not_host로 막혔다 — … (독립 리뷰가 실행해서 증명)."*

§5 picks between them on the merits rather than inheriting either by default.

### 0.5 Facts the design depends on, each verified

| Fact | Citation |
|---|---|
| `custody_phase` ∈ `with_custodian`/`outbound_pending`/`transfer_pending`/`return_pending`/`resolved` | `0040:47-48`, widened `0045:18-20` |
| `outbound_pending` is declared but **never written** by anything | exhaustive grep: only the two CHECKs, `0045:332`, and one client list |
| `payout_state` ∈ `none`/`earned`/`payable`/`released`/`void`, and **carries no amount** | `0040:33-34`; `session_dogs` has no money column |
| `released` disburses nothing — `payouts` has **zero writers** in the repo | `0045:421` (「모의 시대엔 상태 전이만」); `REGISTRY.md:157` |
| The club owner is **not** prepaid; money moves at the run's end | `0081:210-217` — *"It is NOT a record that money moved"* |
| `_club_dogs_unresolved` blocks 세션 종료 while any phase is `outbound_pending`/`transfer_pending`/`return_pending` | `0045:328-336` |
| Return needs `return_pending`; terminal is `_club_finalize_return` → `resolved` + `earned→payable` | `session_confirm_return` `0069:84`, gate `0069:96`; `_club_finalize_return` live at `0070:343`, writes `0070:369-374` |
| The pack run **start** is the RUNNER's own fan-out over their own dogs — not the host's | `club_start_delegated_runs` live at `0050:169`, selector `0050:176`: `b.runner_id = auth.uid()` ⚠ `0087:313` describes this function as "host-gated". **That comment is wrong**; the predicate is the runner's. |
| `end_run_tx` has **zero callers** anywhere in the repo | grep; `docs/session-handoff-run-end-flow.md:20` |
| `confirmed → picked_up` has **no SQL RPC** — it is the edge function | `supabase/functions/transition-booking/index.ts:322` |
| `host_fee_krw` is **0** today, `[Sean 미확정]` | `0048:19` |
| Feature flag for the whole club v2 machine | `_club_require_v2()` `0043:20`, raises `feature_disabled` |

---

## 1. What "ending a run" means for a club pairing

For the marketplace, 0083 split one event into three facts: the **service stop** (`run_ended_at` +
the frozen `runs` row), the **return seal** (`settlement_ready_at`), and the **settlement**
(`settled_at`, the ledger). For clubs, 0045 had already split settlement from return —
`0045:2-3`: *"러닝 종료(completed)는 더 이상 커스터디를 보호자에게 돌리지 않는다. 정산 = 돈 계산일
뿐."*

But 0045 split the wrong pair for this ruling. It separated **정산 ≠ 반환** and left **종료 = 정산**
welded together: the club machine has no representation of "the run is over" other than
`bookings.status = 'completed'`, which only the money transaction writes.

**Sean's ruling is what forces the second split.** 러닝 종료 must be true for a pairing whose runner
has not settled — whose phone is in a pocket, or dead. So the slice owes, in this order:

1. **A club run-end fact** — a server-side truth that this pairing's run is over, independent of
   whether money has been computed. *This does not exist and is the first thing owed.*
2. **A host fan-out over that fact** — one tap, N pairings, best-effort, with a remainder.

Concretely, "ending a run" for a club pairing means exactly four things, and deliberately not a
fifth:

- ⓐ the pairing carries a **run-end stamp** (when, and by whom);
- ⓑ its `custody_phase` becomes `return_pending` — the dog is still the runner's responsibility,
  and the transfer is now the next step (this is what Sean's *"so that they can move on to the
  transfer"* requires: both club return RPCs refuse any other phase, `0069:96` / `0069:151`);
- ⓒ its `payout_state` advances `none → earned` — a state, not an amount (`0040:33-34`);
- ⓓ its open `dog_run_segments` row closes (today done by `_club_close_segments_tg`, `0050:230`,
  on the `completed` UPDATE);
- ⓔ **and NOT the money.** No ledger row, no charge intent, no `end_reason`, no `actual_km`.

---

## 2. The three candidate shapes, and why the middle one is adopted

### ARM 1 — the fan-out drives `bookings.status → 'completed'` itself

Attractive because every downstream derivation in the club machine already keys on `completed`, so
nothing would need re-keying: the 0045 trigger, `_club_close_segments_tg`, `session_transfer_accept`
and `_club_dogs_unresolved` all keep their present meaning for free.

**REJECTED — it silently unpays every club runner.** `settle_run_tx`'s double-settle lock is
`update bookings set status = 'completed' where id = p_booking and status = 'active'; … if v_claimed
= 0 then raise exception 'not_active';` (`0083:720-724`). If the host's tap has already claimed
`completed`, the runner's own settle raises `not_active`: **no ledger row, no pay, and the club
runner's screen shows a failure it cannot clear.** Repairing that means re-creating `settle_run_tx`
— the shared marketplace money transaction, and the exact object `0086 §B` names as the
silent-collision class in its worst form (`0086:124-146`). Rewriting the whole marketplace's
double-settle lock to accommodate a club button is not proportionate.

⚠ **0083's own design is the argument against ARM 1.** The marketplace run-end deliberately does
*not* move `bookings.status` — it stamps `run_ended_at` and leaves the booking `active` through the
entire 귀가 leg (`0083:441`; and `0128:20-22` records the consequence: a marketplace booking is
still `active` through its whole return leg). The house shape for "the run ended" is a **separate
stamp**, not a status move. The club fan-out should mirror `end_run_tx`, not `settle_run_tx`.

### ARM 2 — the fan-out writes a club run-end stamp and the custody facts; `bookings.status` stays `active` ✅ ADOPTED

The runner's settle is **completely unchanged**: it still claims `active → completed`, still prices
from the runner's own numbers on the runner's own device, still writes the ledger. The host's tap
declares the moment; the runner's settle declares the distance and the reason.

**The price of ARM 2 is real and is stated here rather than discovered later: three shipped club
functions derive custody from `bookings.status = 'completed'`, and all three break the moment
custody can reach `return_pending` before the status does.** They are preconditions of this slice,
not follow-ups (§3).

### ARM 3 — the fan-out settles everyone, deriving each km from `runs.trace`

The server does hold each club runner's own validated trace (`club_save_run_trace`, `0050:201-224`,
which rejects `impossible_speed`), and the club client's own km is computed from the same points it
uploads a line earlier (`[sid].tsx:255-263`) — so a server-side derivation would not be as alien as
it first sounds.

**REJECTED, and this is the sharpest rejection in the contract.** Under §0.3, settling is charging:
one host tap would write N runner ledger rows (`0083:754-755`) and mint N owner charge intents
(`handler.ts:296-300`). A host who taps 러닝 종료 two kilometres early would bill N owners for a run
that had not happened, on numbers no runner declared. It also invents a second pricing basis for the
same product — `0083:0§①` already records that `actual_km` is the client's in-memory number and
never the trace, and *"the same run priced differently depending on who ended it"* is the worst
outcome available here. If Sean ever wants it, it needs the full money-path review and its own
mint-side pins; it is not this slice. (§11 OPEN-1.)

---

## 3. The three re-keyings ARM 2 requires — preconditions, in-slice

Each is a club-only function; each is re-created **from its newest definition on origin**, named
here by migration:line, per `0086 §B`'s rule for the next author. None of them is `settle_run_tx`,
`end_run_tx`, `confirm_return_tx` or any marketplace object.

### R-1 — `_club_custody_transition_v2`, newest at `0045:34`

Its completed arm (`0045:55-60`) must not knock a pairing **backwards** when the runner's settle
lands after the host's tap. Narrow the arm's WHERE to the state it actually means:

```
where id = v_sd.id and custodian_type = 'runner' and custody_phase = 'with_custodian'
```

- **This is a no-op for every path reachable today.** Today `completed` always arrives while the
  phase is `with_custodian`, so the narrowed arm matches exactly the same rows.
- **A `resolved` pairing was already safe** and this must be stated so nobody "fixes" it twice:
  `_club_finalize_return` sets `custodian_type = 'owner'` (`0070:369`), so the existing
  `custodian_type = 'runner'` clause already makes the re-fire match zero rows. Verified, not assumed.
- **A `transfer_pending` pairing was NOT safe.** `custodian_type` is still `'runner'` during a
  pending transfer, so a late settle would overwrite `transfer_pending` with `return_pending` while
  `pending_transfer` stayed populated — and `session_transfer_accept` then refuses with
  `no_pending_transfer` (`0058:116`), stranding a dog mid-handover. Unreachable today (status can
  only reach `completed` once, and it does so before any transfer); reachable the moment ARM 2 ships.

⚠ **This edit invalidates a premise `0129` pins.** `0129_club_return_address_arm_fix.sql:298` freezes
this function's body by md5 (`K_TRANSITION`) and aborts at `0129:464` if it differs, precisely
because `booking_pickup_address`'s club arm keys on the phase this trigger sets. On a
rebuild-from-scratch apply, 0129 runs first and still passes, so nothing aborts — which is worse,
not better: the guard silently stops describing the shipped body. **This slice must update
`K_TRANSITION` to the new md5 in a forward migration and say why in its header.** Leaving it stale
is the "green light is evidence for exactly one sentence" failure with the sentence quietly changed
underneath it.

### R-2 and R-3 — `session_transfer_accept` (`0058:104`) and `session_transfer_cancel` (`0058:208`)

Both derive the phase to restore from the booking's status:

- `0058:143-145` — `custody_phase = case when exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'completed') then 'return_pending' else 'with_custodian' end`
- `0058:234` — the same expression in the cancel path.

Under ARM 2 a pairing whose run ended but whose runner has not settled is `active`, so both would
restore `with_custodian` — and a dog in `with_custodian` cannot be returned (`0069:96`
`not_return_pending`). The escape is `session_host_force_resolve`, which would open an S2 incident
and move the booking to `incident_review` — i.e. the product's answer to "a runner handed a dog to
another runner after the run" would be to open an incident. Unacceptable.

**Both expressions are re-keyed to the run-end fact**, with the status arm kept as a disjunct so
historical rows (run-ended-by-settle, no stamp) keep their present answer:

```
case when sd.run_ended_at is not null
       or exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'completed')
     then 'return_pending' else 'with_custodian' end
```

### Not re-keyed, deliberately

- `_club_dogs_unresolved` (`0045:328-336`) — unchanged. It already counts `return_pending` as
  unresolved and already counts `picked_up`/`active`/`completed` bookings, so after a fan-out every
  pairing blocks 세션 종료 until its return is confirmed. **That is exactly Sean's ordering** (run end
  → transfers → session end) and it falls out with no edit at all.
- `_club_close_segments_tg` (`0050:230`) — unchanged. The fan-out closes segments itself with the
  same `where left_at is null` predicate, so the trigger's later run is an idempotent no-op.
- `0118:1255-1263` host fee — **named, not fixed.** ARM 2 breaks the invariant `resolved ⇒ completed`
  (a pairing can resolve via `session_custody_override` while its runner never settles), and the host
  fee's existence probe asks for a `completed` booking. It is inert today because `host_fee_krw` is
  `0` (`0048:19`, `[Sean 미확정]`). **Obligation: the slice that sets `host_fee_krw > 0` re-keys that
  probe in the same breath.** Recorded here so it is not rediscovered in an incident.

---

## 4. The function

```
club_end_pack_runs(p_session uuid) returns jsonb
```

`security definer`, `set search_path = public, pg_temp` **in the body** (98 H1's law — ALTER-applied
config is reset by `create or replace`). `revoke execute … from public, anon;` then
`grant execute … to authenticated;` — **written explicitly in this file, every time**, never relying
on grant preservation (`0116:636`; `check-definer-acl.mjs`). No `service_role` grant: this is a
client-facing host RPC, and the explicit grants ARE the allowlist.

### 4.1 Order of operations — party gate before state gate

```
1. _club_require_v2()                                    → feature_disabled      (0043:20)
2. auth.uid() is null                                    → not_signed_in
3. select … from club_sessions where id = p_session for update
   ⚠ if not found → not_host          (identical answer to "not your session": no existence oracle,
                                        0070:186-189 / 0067:131-135)
4. auth.uid() is distinct from s.host_profile_id
   and auth.uid() is distinct from s.backup_host_profile_id
                                                          → not_host             (§5)
5. s.status not in ('open','full')                        → session_closed
6. re-read every candidate pairing UNDER the session lock (0044's lesson, 0057:317)
7. per pairing: its own subtransaction (§6)
```

Steps 1-5 are the party/feature/session gates and they raise. Step 7 never raises out of the
function: a pairing that cannot end is reported, not thrown (§6).

⚠ **The gate at step 4 uses `is distinct from`, not `auth.uid() in (host, backup)`.** The `in` form
folds to NULL when `backup_host_profile_id` is NULL and `not (NULL)` never fires — the fail-open
this repo has already shipped twice (`0072:117-121`, *"110 S2가 즉시 빨개져 잡았다"*; `0116:410`).
`0070:195-196` is the exact idiom to copy.

### 4.2 The candidate set, and the three verdicts

A pairing is a `session_dogs` row with `custody = 'runner_delegated'`, `session_id = p_session`,
`booking_id is not null`. For each, under the session lock and a `select … for update` on the
`session_dogs` row:

| Verdict | Condition | Effect |
|---|---|---|
| **ended** | booking status `active`, `custody_phase = 'with_custodian'`, `run_ended_at is null` | ⓐⓑⓒⓓ of §1 applied |
| **skipped** | `run_ended_at is not null` → `already_ended` · booking status not `active` → `not_active` · booking already `completed` → `already_ended` | nothing written |
| **blocked** | an unresolved incident names this dog or this booking → `incident_open` · `custody_phase = 'transfer_pending'` → `transfer_in_flight` · row lock unavailable within `lock_timeout` → `locked` | nothing written |

The incident predicate is the shipped one, copied not reinvented — `club_release_payouts`'s
second-defence-line probe, `0072:239-244`:

```
exists (select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
        where i.state <> 'resolved' and i.session_id = sd.session_id
          and ((s.subject_type = 'dog'     and s.subject_id = sd.dog_id)
            or (s.subject_type = 'booking' and s.subject_id = sd.booking_id)))
```

**skipped vs blocked is the load-bearing distinction and it must not collapse into one list.**
`skipped` means "nothing to do here" — the screen says nothing. `blocked` means "this dog's run did
not end and somebody must act" — the screen must say so by name. Merging them is precisely the
"silent catch → happy UI" the honesty law forbids.

### 4.3 Schema

```
alter table session_dogs
  add column run_ended_at timestamptz,
  add column run_end_by   uuid references profiles(id);

alter table club_sessions
  add column run_ended_at timestamptz;   -- the session-level fact the live map and the board read
```

- **`session_dogs`, not `bookings`, and this is not a style choice.** Writing
  `bookings.run_ended_at` would arm `settle_run_tx`'s §6-ⓔ freeze check (`0083:709-717`): with
  `v_run_ended` non-null and `runs.actual_km` still NULL, `round(p_actual_km,2) is distinct from
  v_fz_km` is TRUE and **every club settle would raise `frozen_measurement_mismatch` forever.**
  Measured by reading; it is the deadlock 0083's own header calls out in red.
- **The pairing is the right grain.** A club runner may hold several dogs; each is its own booking,
  its own segment and its own money. `club_sessions.run_ended_at` is the session fact (set the first
  time any pairing ends, never overwritten).
- **`runs.ended_at` is NOT written by the fan-out.** For clubs the settle's upsert lets
  `excluded` win — `0083:743`: *"정지 스탬프가 없는 행(레거시·클럽 경로)은 0028 그대로 excluded가
  이긴다"* — so a stamp written here would simply be overwritten with the settle time. Leaving it
  alone keeps one clock honest instead of making two disagree. **Residual, named:** club
  `runs.ended_at` continues to mean *settle time*, while the honest stop time lives on
  `session_dogs.run_ended_at`. Any report that shows a club run's duration must read the latter.
  (§11 OPEN-3.)
- Both tables carry a **SELECT-only** RLS policy and no other — `club_sessions` at `0030:133`,
  `session_dogs` at `0030:136`, and no `for insert` / `for update` / `for all` policy exists on
  either anywhere in the tree (grepped). So these columns are server-authored by construction.

### 4.4 Notifications

Per ended pairing, mirroring `club_start_delegated_runs`'s shape (`0050:194-197`): the **owner** is
told the run ended and the transfer is next; the **runner** is told their run was ended by the host
and their record is ready. Both inside the same subtransaction as the pairing they describe — a
notification for a pairing that did not end is a lie, and it must roll back with it.

---

## 5. Party gate — host **and backup host**. Recommended, against `club_finish_session`'s posture.

Both shipped postures are legitimate (§0.4). The tie is broken on the shape of *this* action:

- 러닝 종료 is **live, at the finish line, time-critical, and the host is very often running with a
  dog themselves.** That is verbatim the situation `0070:191-193` describes when it widened
  `session_host_force_resolve` to the backup host after an independent reviewer *executed* the case
  and proved the host-only gate made the RPC unusable in the most common club shape.
- 세션 종료 is administrative, unhurried, and closes a ledger. `0118:1113-1114`'s host-only posture
  is right there and is **not changed by this slice**.
- The blast radius is bounded and self-correcting: the backup host is not a stranger — they must be a
  **committed runner** of that session (`0047:312`, `backup_not_committed`) and cannot be the host
  (`0047:309`). A wrong tap ends runs that were going to end within minutes anyway; it moves no
  money (§7) and every affected pairing is visible on the board.

Rejected alternatives: **host-only** (leaves the commonest club shape with a button nobody can press
when it matters, the exact defect 0070 fixed); **any committed runner** (the run-end is a supervision
act over other people's pairings — 0067:64-67's reasoning that "has a record here" is the wrong
authority for an action that freezes state applies directly).

`club_assume_host` (`0047:326`) remains the escalation for a host who is unreachable and has no
backup — named here so the gate's narrowness has a stated remedy.

---

## 6. The partial fan-out — argued both ways, then decided

**Framing first: this session was handed the coordinating session's reading (best-effort with a
remainder) and reaches the same conclusion. That agreement is not evidence** — by this repo's own
law, agreement between sessions is the same claim counted twice. The argument below was constructed
from the shipped code, and the conclusion would have been the same had the brief argued the
opposite.

### ARM A — atomic-or-nothing

*For.* One outcome, one sentence on screen, no partial-state vocabulary to design, no remainder for
the client to render, no chance of a host believing more ended than did. Transactionally trivial:
one `raise` and the whole thing rolls back.

*Against, and it is decisive.* One runner mid-incident means **nobody's** run ends. N owners are
standing at the finish point with their dogs behind them and the transfer is closed for all of them,
because one unrelated pairing has an open case. The host's only remedy is to resolve an incident on
the spot — the one thing that cannot be done quickly, by design (`club_incident_resolve` requires a
settlement first, `0072:276-283`). And the failure is shaped exactly like the one 0118 measured on
this same surface: `0118:64` records an emptied config key raising inside a session-wide loop and
*"roll[ing] the WHOLE"* thing back, with a session's worth of refunds lost. The repo has already
paid for this lesson once.

There is also no honesty gain. Atomicity does not make the outcome truer — it makes it *uniformly
absent*, and the host still has to be told why, so the vocabulary has to exist anyway.

### ARM B — best-effort with an explicit remainder ✅ RECOMMENDED

*For.* **The blast radius of a failure becomes proportional to the failure.** One dog with an open
incident blocks exactly one dog. Every other pairing ends, every other owner receives their dog, and
the host is told, by name, which one did not and why. That proportionality is the property; the
partial outcome is the cost of having it.

*Against, honestly stated.* The host's tap now has a compound result, so **the screen may no longer
say "러닝 종료 완료" unconditionally** — it must state the remainder or it is lying, and that copy is
part of this slice's obligation, not a follow-up (§6.3). It also introduces a state the product has
not had before: a session in which some runs have ended and some have not. §6.4 shows that state is
already legible with no new vocabulary.

**Decision: ARM B.**

### 6.1 Transaction shape — per-pairing subtransactions, one commit

```
for each candidate loop
  set_config('lock_timeout','2000',true);
  begin
    -- select … for update; re-check the verdict UNDER the lock; write ⓐⓑⓒⓓ; notify
  exception when others then
    -- classify into `blocked`, raise warning, continue
  end;
end loop;
```

This is the shipped per-row idiom (`0117:1213` and the r17 contract's §1.3 restatement), **not** the
per-row-COMMIT procedure form. A club session is a handful of pairings tapped once, not a 50-row
cron tick — the lock-convoy problem the r17 contract exists to solve does not apply, and a
procedure that COMMITs cannot be called from a `DO` block, which would make the suite fixtures
harder for no benefit. Stated so a future session does not "upgrade" it without a reason.

⚠ `exception when others` catches everything, including a bug. Every caught pairing is classified
into `blocked` with its SQLSTATE recorded in the returned object **and** a `raise warning`, so a
genuine defect surfaces in the log rather than being laundered into "one dog couldn't end".

### 6.2 The remainder — what is returned to the caller

```jsonc
{
  "session":   "<uuid>",
  "at":        "2026-08-26T09:14:22Z",     // the run-end moment (one clock for the whole tap)
  "ended":     [ { "sdId": "…", "bookingId": "…", "runnerId": "…", "dogId": "…" } ],
  "skipped":   [ { "sdId": "…", "reason": "already_ended" | "not_active" } ],
  "blocked":   [ { "sdId": "…", "reason": "incident_open" | "transfer_in_flight" | "locked",
                   "incidentId": "…" /* present only for incident_open */ } ]
}
```

- **Three lists, never a count.** A count cannot be rendered honestly (`3 of 4` does not say which)
  and cannot be acted on.
- **`at` is one timestamp for the whole tap**, computed once. Per-pairing `now()` inside one
  transaction returns the same value anyway; naming it makes the invariant explicit and testable.
- **Flat, whitelisted keys** (repo law). No nested booking rows, no runner names — the board already
  reads the roster.
- **A second tap returns `ended: []` with everything in `skipped/already_ended`, and is NOT an
  error.** 0083's own words for the marketplace stop, applied here: *"a second stop is not an error,
  it is the same stop"* (`0083:386-388`).
- **`blocked` is a report, not a refusal.** The call succeeds. The host is not blocked from anything
  — least of all from 세션 종료, which has its own gates (`dogs_not_returned`, `incident_unassigned`)
  and is the correct place for that refusal.

### 6.3 What the screen may honestly promise

| Outcome | What the screen may say | What it may NOT say |
|---|---|---|
| all pairings ended | 「러닝 종료 — N팀 모두 종료됐어요」 | — |
| some blocked | 「N팀 종료 · M팀은 아직이에요」 **plus the blocked pairs listed by dog name with their reason**, and an action per row (open the case for `incident_open`; nothing to tap for `transfer_in_flight` beyond waiting) | 「러닝 종료 완료」 · any all-clear · a bare count with no names |
| nothing ended | the reason, per pair. Never a generic failure | 「종료 실패」 alone |
| second tap | 「이미 종료됐어요」 | an error |

The one promise the screen may make in every case: **the pairs in `ended` can proceed to the
transfer right now.** That is exactly what ⓑ bought, and it is the only claim the server has
actually established.

### 6.4 Why a partial fan-out needs no new state vocabulary

A pairing that did not end is `with_custodian` with a live booking — which `_club_dogs_unresolved`
already counts as unresolved (`0045:332-335`), so 세션 종료 already refuses. The supervision board
(R7-2) needs no third status: **`run_ended_at is null` on a delegated pairing IS "still running"**,
and it is the same column the board's other columns hang off. The partial outcome is legible in the
data the board was going to read anyway.

---

## 7. Money — read this section before approving anything

### 7.1 The fan-out mints nothing and moves no ledger row

Under ARM 2 the host's tap writes: two timestamps, `custody_phase`, `payout_state`,
`dog_run_segments.left_at`, and notifications. It does **not** call `settle_run_tx`, does not touch
`ledger_items`, does not call `mint_settle_charge_intent`, does not compute or store a km, a
`end_reason`, or a fare. **The host declares WHEN; the runner declares WHAT.** That sentence is the
money law of this slice and every review should test the design against it.

### 7.2 But it IS on the money path, and here is exactly how far

`payout_state: none → earned` is a step on the club payout state machine
(`none → earned → payable → released`). It carries no amount (`0040:33-34`; `session_dogs` has no
money column) and `released` disburses nothing (`payouts` has zero writers — `REGISTRY.md:157`;
`0045:421` 「모의 시대엔 상태 전이만」). What the fan-out changes is **when** `earned` is reached: today
at settle, after this at run-end. Downstream, `_club_finalize_return` still requires `earned` to
reach `payable` (`0070:374`) and `club_release_payouts` still requires `payable` + `resolved` +
no unresolved incident (`0070:149-151`, `0072:239-244`). None of those predicates changes.

**Therefore this slice takes the money-path review and gets money pins (§8, P6-P8), and it does not
need a fare, a rate, or a Sean pricing ruling.**

### 7.3 The one invariant this breaks, named loudly

Today `resolved ⇒ completed` holds by construction: the only way to `resolved` is through
`return_pending`, and the only way to `return_pending` is through `completed`. **ARM 2 breaks it.**
A pairing whose runner never settles (dead phone, uninstalled app) can now be ended by the host,
resolved by `session_custody_override` (`0070:243`, host-witnessed), and reach `payable` and
`released` **with no `ledger_items` row ever written**.

- **Not a leak today**, and the reason is specific rather than comforting: `released` disburses
  nothing, so "released with nothing to release" is a state-honesty defect, not a money loss.
- **It becomes a leak the day `payouts` gets a writer.** Recorded as a standing obligation on that
  slice: *whatever disburses must join `ledger_items`, not `payout_state`.*
- **Second consequence, already covered:** `0118:1255-1263`'s host fee asks for a `completed`
  booking; see §3's "not re-keyed, deliberately", and the obligation on whoever sets
  `host_fee_krw > 0`.

### 7.4 What does NOT change

`compute_runner_payout` (`0102:41-121`), `compute_owner_charge` (`0080:236-297`),
`mint_settle_charge_intent` (`0084:288`), `settle-run/handler.ts`, `settle_run_tx`, `club_fare`,
`club_fee_items`, `club_incident_settle`, the cancel/no-show ladder, and the pre-cutover posture
(`payments_live_since` NULL → `skipped_not_live`, `0084:261`) are all untouched. A club run is still
priced from the runner's own device at the runner's own settle, exactly as today.

---

## 8. Idempotency and concurrency

| Race | Resolution | Why |
|---|---|---|
| **Two host taps** | second returns `ended: []`, everything in `skipped/already_ended`, no error | `run_ended_at is null` is re-checked under the `session_dogs` row lock; the session `for update` serialises the two calls entirely |
| **Host tap ⟷ that runner's own settle** | whichever commits first wins; the other is a no-op | The settle claims `active → completed` (`0083:720`) and the fan-out never touches status, so **both can succeed in either order without conflict**. If the settle lands first, the 0045 trigger has already set `return_pending`; the fan-out sees `custody_phase <> 'with_custodian'` and reports `already_ended`. If the fan-out lands first, the settle still finds `active` and pays normally, and R-1's narrowed arm makes the trigger's re-fire a no-op. **This is the property ARM 2 was chosen for.** |
| **Host tap ⟷ incident open** | serialised by the session lock (`club_incident_open` takes it) | Incident first → that pairing is `blocked`, named, with its `incidentId`. Fan-out first → the run has ended and the case is now a return-phase case, which is a shape 0045 already handles (clinic/authority transfers are legal only in the return phase, `0057:322-326`). Honest either way. |
| **Host tap ⟷ transfer in flight** | `transfer_pending` → `blocked`/`transfer_in_flight` | Ending a run mid-handover would write a phase the accept path then contradicts. The transfer completes in seconds; the host taps again. |
| **Host tap ⟷ `session_host_force_resolve`** | serialised by the session lock; force-resolve moves the booking to `incident_review` | A force-resolved pairing is not `active`, so the fan-out reports `not_active`. Correct: that dog's run was ended by a case, not by the pack. |
| **Host tap ⟷ `club_finish_session`** | both take `club_sessions for update`; whichever is second sees the other's effect | If finish wins, the fan-out's step-5 gate raises `session_closed`. If the fan-out wins, finish raises `dogs_not_returned` — which is right: runs just ended, nothing is returned yet. |
| **Host tap ⟷ owner cancel** | `session_cancel_delegation` refuses on an open incident (`0124:65-71`) and on handed-off bookings; a `picked_up`/`active` booking is past cancellation | No new interaction. |

**Idempotency key:** `session_dogs.run_ended_at is null`, evaluated under the row lock. Not a
returned token, not a client-supplied nonce, not a count — the same shape as `0083:386-388`.

---

## 9. Refusal tokens

New tokens, all in the shipped vocabulary style (bare lowercase, no sentence, `using detail` for the
Korean the client may render):

| Token | Raised when |
|---|---|
| `not_host` | caller is neither host nor backup host — **and also when the session does not exist**, deliberately identical (`0070:186-189`'s law) |
| `session_closed` | session status not in `('open','full')` |
| `feature_disabled` | `_club_require_v2()` (`0043:22`), reused unchanged |
| `not_signed_in` | reused unchanged |

Per-pairing **reasons** (`already_ended`, `not_active`, `incident_open`, `transfer_in_flight`,
`locked`) are **data in the returned object, not exceptions.** They are deliberately distinct
strings from the exception vocabulary so a reader can never confuse a report with a refusal.

⚠ **`club_out_of_scope` is not used here.** It is the *marketplace* side refusing a club booking
(`0083:383`, `0096:122`, `0089:104`, `0117:415`); no club function raises it, and borrowing it would
invert its meaning.

---

## 10. What this slice does NOT do

- **It does not build 세션 종료.** `club_finish_session` (`0118:1102`) is untouched — same host-only
  gate, same `dogs_not_returned`, same refunds, same no-show fee, same host fee.
- **It does not price, settle, mint, charge, or move a ledger row** (§7).
- **It does not touch any marketplace object**: not `end_run_tx`, `settle_run_tx`,
  `confirm_return_tx`, `force_return_tx`, `start_run_tx`, `compute_owner_charge`,
  `compute_runner_payout`, `settle-run`, `transition-booking`, or `ops_flags`.
- **It does not write `bookings.run_ended_at`, `runs.ended_at`, `runs.actual_km`, `runs.end_reason`
  or `runs.settled_at`** (§4.3).
- **It does not add a `bookings` status or a transition-map edge.**
- **It does not build the supervision board (R7-2)** — its read model, its per-pair status
  vocabulary, and its on-site/home mode column are a separate slice. §6.4 establishes that this
  slice leaves the board's data legible without new vocabulary; that is the whole of its
  contribution to R7-2.
- **It does not build the owner's "can't make it" alert or the three-party chat (R7-3).** The plan
  already measured that no such chat scope exists (`0108:25-27` — three shipped scopes, none of them
  host+runner+one-owner).
- **It does not decide, read, or write `return_mode`.** That column does not exist on trunk; it
  arrives with `0129` (`0129:141-147`), which is untracked in this tree. The fan-out is
  mode-agnostic by construction: it ends runs, and where the dog goes next is the transfer's
  question.
- **It does not build a client screen.** The lab swap (러닝 종료 into the map's thumb, 세션 종료 onto
  the list screen) is ui6's, per the plan's own routing (`:267`).
- **It does not add a sweep, a cron, or an expiry** for a session whose runs were never ended.
  Deliberate: there is no honest default end time for a run nobody declared, and inventing one is
  how a fabricated `actual_km` gets into a ledger. A stranded pairing is `session_host_force_resolve`'s
  job, and that function already exists.

---

## 11. ANSWERED — SEAN, 2026-08-26 05:02–05:03Z. This section is CLOSED 4/4.

⚠ **The four 「Recommended:」 notes that stood here are SUPERSEDED and have been removed rather
than left beside the rulings.** One of them was overruled, and a recommendation sitting next to
the ruling that beat it is how a later session builds the wrong thing while believing it read the
contract. Verbatim record: `docs/decisions/2026-08-25-console-rulings.md`.

| # | question | **RULED** | vs. recommendation |
|---|---|---|---|
| 1 | derive each runner's numbers server-side, or wait for their phone? | **`Compute it server-side`** | ⚠ **overruled** (had recommended: wait) |
| 2 | may the backup host press 러닝 종료? | **`Yes`** | as recommended |
| 3 | duration measured to the host's 러닝 종료 or the runner's own settle? | **`The host's tap`** | as recommended |
| 4 | a pair blocked by an open case — run-end screen or session-end board? | **`On the run-end screen`** | as recommended |

### 11.1 🔴 Why #1 is not merely an override — the recommendation was incoherent with #3

Read #1 and #3 together, which the card group failed to do at authoring time. **If the recorded
duration is defined by the host's tap (#3), then waiting for each runner's phone (#1 as
recommended) produces distance and time keyed to a DIFFERENT INSTANT than the one being
recorded** — each runner's own settle moment, which is precisely the drift #3 exists to remove.
Server-side derivation at the tap makes duration and distance describe the same instant. **The
ruling is the coherent pair; the recommendation was not.** Recorded because a contract that says
only 「overruled」 teaches the next reader the wrong lesson.

### 11.2 The objection that SURVIVES, and it was never about derivation

The stated hazard was 「one host tap writes N ledger rows and, post-cutover, charges N owners'
cards」. **That is an objection to COUPLING derivation to charging, not to deriving.** The two are
separable and this contract now requires them separated:

- 러닝 종료 ends the pack, and derives each runner's distance/time **from that runner's own
  uploaded trace**, stamped to the host's tap.
- **The charge remains its own gated step**, exactly as today. No single button press bills a
  group of people, at any point, before or after the charging cutover.

⚠ If a later slice collapses these two steps 「for simplicity」, this subsection is the record that
the collapse was never what was decided — and `packend-numbers` will be cited as authorising it,
because it looks like it does.

### 11.3 The backup-host asymmetry is DELIBERATE — do not normalise it

`packend-backup = Yes` (backup may end the walk) sits beside `backup-powers = Host only`
(backup may NOT remove a member), ruled thirty-five seconds apart. **This is not an
inconsistency to tidy.** Ending the walk is a practical act by whoever is standing at the finish
line; removing a person and closing the session are authority. 세션 종료 stays host-only.

---

## 12. Suite plan

New suite, number resolved from origin at build time. Style: sibling of 110/117 —
`_pass('pke',…)`/`_fail('pke',…)`, one `begin … exception` per case, `_fail` arguments pre-computed
into `v_msg` and **never a subquery** (110's law: a subquery in a `CALL` argument raises only on the
failure path, sits green forever, and when it fires it rolls back the fixture the pin already wrote).

### 12.1 Fixtures — reachable by the lifecycle, and the one place that is impossible

**No pin may `insert into session_dogs` or `update session_dogs set custody_phase = …` to reach a
state.** Every custody fact must be produced by the machine that produces it in production, or the
suite measures its own fixtures. The reachable chain, all verified:

```
session_delegate_dog        (0048:89)    → session_dogs, approval pending
session_approve_dog         (0084:610)   → approved
session_pay_delegation      (0081:122)   → mints the booking at 'matching'
session_propose_dog         (0047:69)    → proposal
session_proposal_respond    (0057:104)   → 'confirmed', runner_id set
        ⚠ confirmed → picked_up          → NO SQL RPC EXISTS
club_start_delegated_runs   (0050:169)   → 'active', runs row, dog_run_segments row
```

⚠ **The one gap, stated rather than papered over.** `confirmed → picked_up` lives entirely in
`supabase/functions/transition-booking/index.ts:322` (`await set({ status: "picked_up" })`) — there
is no SQL entry point. The suite therefore performs **that exact UPDATE and nothing more**, with a
comment naming the file:line it stands in for. That is still lifecycle-reachable in the sense that
matters: the update fires `club_custody_transition_v2` (`0045:64`), and every custody fact the pins
then read is written by the trigger, not asserted by the fixture. **A pin that reaches
`with_custodian` by writing `with_custodian` is worthless here** — the trigger is half of what this
slice changes.

Fixture shape: one session, one host, one backup host, **three runners** (never one — a fan-out
suite with a single runner cannot tell "ends every runner's runs" from "ends my own", which is
exactly the property Sean asked for), one runner holding **two dogs** (so per-pairing grain is
exercised), one dog reserved for the incident arm.

### 12.2 Pins — the proposition each one holds

| Pin | Proposition |
|---|---|
| **P1** | One host tap ends **every** runner's runs — including runners the host is not, and including a runner's second dog. After the tap, all pairings carry `run_ended_at`, `custody_phase = 'return_pending'`, `payout_state = 'earned'`, and a closed `dog_run_segments` row. |
| **P2** | The party gate is host **and** backup host, and it is NULL-safe: a random signed-in member gets `not_host`; a **nonexistent session id gets the same `not_host`** (no existence oracle); the backup host succeeds; and with `backup_host_profile_id` NULL a stranger still gets `not_host` (the `in (…)` fail-open would let them through). |
| **P3** | Party gate precedes state gate: a non-host calling on a `done` session gets `not_host`, never `session_closed`. |
| **P4** | Idempotence: the second tap returns `ended: []`, every pairing in `skipped/already_ended`, **no exception**, and `run_ended_at` is unchanged (the first tap's timestamp, not the second's). |
| **P5** | Partial fan-out: with one dog carrying an unresolved incident, the other pairings **end**, the incident pairing appears in `blocked` with `incident_open` and its `incidentId`, and its `custody_phase`/`payout_state`/`run_ended_at` are **untouched**. The all-or-nothing behaviour would fail this pin. |
| **P6** | 💰 The fan-out writes **no money**: zero new `ledger_items` rows, zero new `payments` rows, zero new `club_fee_items` rows, and `runs.actual_km` / `runs.end_reason` / `runs.settled_at` still NULL, for every pairing. |
| **P7** | 💰 The runner's settle still works **after** the host ended the run: `settle_run_tx` claims `active → completed`, writes exactly one `ledger_items` row, and `payout_state` stays `earned` (not double-advanced). The ARM 1 failure (`not_active`, runner never paid) fails this pin. |
| **P8** | 💰 Order-independence: a pairing settled **before** the tap is reported `already_ended` and its `custody_phase` is not disturbed; a pairing settled **after** the tap ends up in the same terminal state as one settled before. One run, one outcome, either order. |
| **P9** | R-1: after the host tap, a runner-to-runner transfer (`session_transfer_initiate` → `session_transfer_accept`) leaves the new custodian in `return_pending` and `session_confirm_return` succeeds. Without R-2 the new custodian lands in `with_custodian` and the return raises `not_return_pending` — **the stranded-dog path**. |
| **P10** | R-1's knock-back guard: a settle landing while the phase is `transfer_pending` does **not** overwrite it. Both directions: `resolved` is also not knocked back (this arm is green before the fix too — it is pinned so the reason, `custodian_type = 'owner'` at `0070:369`, is recorded rather than rediscovered). |
| **P11** | The session close ordering Sean specified: immediately after 러닝 종료, `club_finish_session` raises `dogs_not_returned`; after every pair confirms return, it succeeds. |
| **P12** | ACLs and sealing: `club_end_pack_runs` has `set search_path = public, pg_temp` **in its body** (`prosecdef` + `proconfig` asserted), is revoked from `public`/`anon`, granted to `authenticated` only, and has no `service_role` grant. Schema-wide definer ACL sweep unchanged (98 H1 family). |
| **P13** | `_club_require_v2()` gates it: with `club_delegation_v2` off, the call raises `feature_disabled` and writes nothing. |

### 12.3 Mutation battery — which pin reddens for each mutation

**Three propositions, not one** (house law): for the arms that close a hole, the battery plants the
failure **without** the fix (does the hole reproduce?) *and* **with** it (is it closed?). A control
that cannot fail is not a control.

| # | Mutation | Predicted red set |
|---|---|---|
| M1 | Scope the candidate query to `b.runner_id = auth.uid()` (i.e. build `club_start_delegated_runs`'s selector by mistake, `0050:176`) | **[P1]** — and *only* P1 with a single-runner fixture, which is why §12.1 mandates three |
| M2 | Drop the backup host from the gate (host-only, `0118:1115`'s shape) | [P2] |
| M3 | Write the gate as `not (auth.uid() in (s.host_profile_id, s.backup_host_profile_id))` | [P2] — the NULL fail-open arm alone |
| M4 | Move the session-status check above the party check | [P3] |
| M5 | Drop the `run_ended_at is null` re-check under the row lock | [P4] |
| M6 | Replace the per-pairing subtransaction with a bare loop that lets the incident case raise (**= ARM A, atomic-or-nothing**) | [P1, P5] — P1 because *nothing* ends |
| M7 | Merge `skipped` and `blocked` into one list | [P5] |
| M8 | Have the fan-out call `settle_run_tx` per pairing (**= ARM 3**) | [P6, P7] |
| M9 | Have the fan-out set `bookings.status = 'completed'` (**= ARM 1**) | [P7] — `not_active`, the runner is never paid |
| M10 | Write `bookings.run_ended_at` instead of `session_dogs.run_ended_at` | [P7] — `frozen_measurement_mismatch` at `0083:709-717` |
| M11 | Revert R-2 (`session_transfer_accept` back to the `status='completed'` derivation, `0058:143-145`) | [P9] |
| M12 | Revert R-1 (the trigger arm back to `0045:55-60` unnarrowed) | [P10] |
| M13 | Advance `payout_state` unconditionally (drop the `case when payout_state = 'none'` guard) | [P8] |
| M14 | `grant execute on club_end_pack_runs to service_role` | [P12] |
| M15 | Write `set search_path` via `ALTER FUNCTION` instead of in the body | [P12] (98 H1 family) |
| M16 | Delete the `_club_require_v2()` call | [P13] |

**Hole-reproduction controls (planted WITHOUT the fix), each run alone:**

- **C1** — apply the fan-out but **omit R-2**, then drive P9's transfer chain. Expect
  `not_return_pending` from `session_confirm_return`: the stranded dog, reproduced as a raise, not
  as a pin's opinion of one. Then apply R-2 and re-run: the return succeeds.
- **C2** — apply the fan-out but **omit R-1**, then drive: tap → `session_transfer_initiate` →
  runner settles. Expect `custody_phase` observed as `return_pending` with `pending_transfer`
  non-null, and `session_transfer_accept` raising `no_pending_transfer` (`0058:116`). Then apply R-1
  and re-run: phase stays `transfer_pending`, accept succeeds.
- **C3 (a control that CAN fail)** — run the full battery with the fan-out present but **never
  called**. Expect the baseline green, unchanged. A red here means a pin is measuring a fixture, not
  the function.

⚠ Every number in §12.3 is a **prediction written before measurement.** Reproduce this table
verbatim in the suite header so the measuring session can contradict it, and record what was
actually observed beside it.

⚠ **Do not edit a live migration to plant a mutation**, even transiently — point the checker at a
copy outside the worktree (`MIGRATIONS_DIR=… node scripts/check-definer-acl.mjs`), and stage every
fix with `git add` **before** a scripted battery, because `git checkout --` restores the index.

---

## 13. Build order

1. Resolve the migration and suite numbers **from origin**, both sides (the file *and* the REGISTRY
   row), and push the row with the file.
2. Schema (§4.3) + R-1/R-2/R-3 (§3) + `club_end_pack_runs` (§4) — **one migration.** R-1/R-2/R-3 are
   preconditions: shipping the function without them creates the stranded-dog path C2 reproduces.
3. Update `0129`'s `K_TRANSITION` md5 in the same file, with the reason in the header (§3 R-1).
4. Suite (§12), then the battery, then the controls.
5. `/autoplan` — standing gate for any migration or money-path change (0059 doctrine), and §7 puts
   this on the money path.
6. Commit gate from `app/`: `tsc --noEmit`, `check-rpc-contracts.mjs`,
   `check-route-native-imports.mjs`, `check-definer-acl.mjs`. Harness green with the new pins.
7. The client half (the RPC binding, the run-end screen, the remainder copy of §6.3) is **atomic with
   this migration in the sense that matters**: the migration is safe to land alone (the function
   simply has no caller, exactly as `end_run_tx` has none today), but the button must not ship
   before the copy can state a partial outcome.
