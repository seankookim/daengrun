# Contract — run-end two-phase stop (codex GPS finding 4)

**Source:** `docs/reviews/2026-08-28-codex-runend-money.md` HIGH-4 (~lines 93-100).
**Explicitly NOT closed by 0156** — its own header: "It does NOT close finding 4 itself — the
stale-trace race needs a two-phase stop … Do not read this migration as closing 4"
(`0156:21-24`). [measured]
**Live money, un-flag-gated:** owner COLLECTION is flagged (`settle-run/handler.ts:320-322`,
`skipped_not_live` while `ops_flags.payments_live_since` is NULL); the runner's `ledger_items`
row is not (`0083:754`). [measured]
**Reachable today though it was not on 2026-08-28:** codex HIGH-3 said `club_end_pack_runs` had
zero client callers; Sean ruled 「Wire it」 (`docs/decisions/2026-08-31-sean-rulings.md:19-28`) and
it IS wired — `app/app/club/console/[sid].tsx:438` → `api.ts:4327`. [measured]
Every claim is **[measured]** (read in this tree) or **[inferred]**.

## §1 The defect

The host's 러닝 종료 freezes and prices whatever trace has reached the server, while the runner's
device is holding up to a full upload interval of real GPS that has not been sent yet — and the
booking stays `active`, so that tail lands in `runs.trace` after the price is immutable and is
paid for by nobody. Concretely, with the host tapping at **12:00:00**:

| t | what happens | citation |
|---|---|---|
| 11:59:02 | last successful `saveClubRunTrace` — the 60 s tick. Server `runs.trace` ends at t=11:59:00 | `club/run/[sid].tsx:278`, timer `:285` [measured] |
| 11:59:02→12:00:00 | ~29 fixes land in geo.ts's in-memory buffer via the background task. **`bgTrack.ts` does no network** ("No arithmetic, no network", `bgTrack.ts:8-9`, `:29`); fix cadence is `distanceInterval: 5 / timeInterval: 2000` (`geo.ts:245-246`). Nothing reaches the server | [measured] |
| 12:00:00 | host taps → `endPackRuns` → `club_end_pack_runs` (`0144:290`). `v_at := now()` (`0144:349`); derivation at `0144:427` over `v_trace` — which simply **does not contain** the 58 s. 0156's `t <= now()+60` bound (`0156:170`, `:179-180`) is irrelevant: the points are absent, not out of window | [measured] |
| 12:00:00 | freeze writes `runs.actual_km/duration_sec/end_reason` (`0144:448-455`) and `bookings.run_ended_at` (`0144:456`). Booking **status stays `active`** — only `settle_run_tx` moves it (`0083:720`) | [measured] |
| 12:01:02 | next tick uploads the whole buffer; `0156:96-99` appends every point with `t > last_t`. `_guard_run_cols`'s 「종료 후 동결」 arm (`0083:295`) does **not** bite — it is gated on `current_user in ('authenticated','anon')` (`0083:286`) and `club_save_run_trace` is SECURITY DEFINER (`0156:53`). The tail lands, after the price | [measured] |
| 12:0x | runner taps 완주로 종료 → `doSettle` (`[sid].tsx:292`) sends its own larger `actual_km`; `settle-run:90` sees `run_ended_at`, reads the frozen row (`:264-280`), logs 「body ignored (frozen)」 (`:96-99`), prices the truncated km (`:128`) | [measured] |

**Size.** Bounded by the billable speed gate — 8 m/s (`0156:196`, `geo.ts:105`) — so ≤480 m over
60 s, ~180 m at a realistic dog pace. Priced per km by `compute_runner_payout`
(`settle-run/handler.ts:163`, arithmetic in 0101 §A); `handler.ts:150`'s comment quotes 3,000/km,
so ~540–1,440원 per run. [inferred — the gates and that comment, not 0101's live coefficients]

**60 s is the FLOOR, not the ceiling.** The upload is a React Native `setInterval` owned by this
screen (`[sid].tsx:285`) and the screen has **no board poll at all** — `load()` runs only on
`useFocusEffect` (`:164`) and after a settle (`:342`). [measured] A network failure sets `saveLag`
with no retry queue (`:280-282`); the next fired tick re-sends the whole buffer, so nothing is lost
— *if* a tick fires. Whether a JS timer fires while backgrounded under the location background mode
is **not determinable from source**. [inferred] Meanwhile `[sid].tsx:582` renders
「실측 {km}km · … — 이 기록으로 정산돼요」 off the **local**, larger km. [measured]

## §2 The invariant

> **A run's priced distance is derived from a trace that can no longer change, and no ledger row
> exists for a run whose trace is still changing.**

## §3 The design — two-phase stop

### Phase 1 — the host tap marks the run `stopping`. It must NOT stamp `run_ended_at`.

A new column (`bookings.run_stopping_at`). **Not `run_ended_at`**, for two measured reasons:
(i) `settle-run/handler.ts:90` keys the entire frozen path on it, and `readFrozenRun` (`:264-280`)
does `Number(data.actual_km)` — **`Number(null) === 0`** — with every band/floor check skipped on
that path (`:133-144`); stamping it before km exists turns an under-payment into a **0 km
settlement**. (ii) `0159:148-154` closes the pack map channel for club bookings on
`run_ended_at is not null` (`0159:58-63` argues that uniqueness); stamping it at phase 1 kills the
owner's live map before the run is over. `run_ended_at` therefore keeps its exact current
meaning: **the numbers are frozen.**

### (a) refuse, or (b) bounded drain — recommendation: **(b), with (a) as the window's terminator.**

Drain for **90 seconds** from the tap: `club_save_run_trace` keeps accepting for a booking in
`stopping` until `now() > run_stopping_at + 90s`, then refuses with a typed `run_stopping`. Pure (a)
throws away a full upload interval of *real, honest* GPS on every run and under-pays every runner
by design — the defect's own direction, made permanent. 90 s and not 60 s because the client
re-sends the **whole** buffer each tick (`build(trace.current)`, `[sid].tsx:275`; server appends by
`t > last_t`, `0156:96-99`), so one tick inside the window suffices — and a tap landing 1 s after a
tick needs 59 s plus a round trip, which 60 s gives no margin for. (a) still ships, as the window's
closing rule: a late tail is refused **by name**, never silently dropped.

**A stationary phone** keeps producing fixes (`pausesUpdatesAutomatically: false`, `geo.ts:249`,
which exists precisely so iOS does not stop delivering) and drains normally; 0156's coverage gate
(`:156`, `:208`) leaves it at a true `0.00`, not NULL. [measured] **An offline or suspended phone**
drains nothing: phase 2 fires anyway on expiry, derives over whatever exists, and the coverage gate
returns NULL → `blocked/no_trace` (`0144:433`), no ledger row. What happens next is §8 Q3.

### Phase 2 — a **cron sweep**, idempotent, not the client's ack.

The screen has no poll (`:164`, focus-only), so a backgrounded phone never learns the run is
stopping and can never ack; an ack-triggered phase 2 would strand every run whose runner's phone is
in a pocket — the ordinary case. A sweep answers **inaction**, which is what this repo's doctrine
requires. A client flush-and-ack may run phase 2 **early** for that run as an optimization; both
doors take the booking row lock and both are `where run_stopping_at is not null and run_ended_at is
null`, so a second tick matches zero rows. Phase 2 derives km, writes the freeze (`0144:448-456`'s
two statements, both or neither), and only then releases settlement.

### What the ledger says while a run is `stopping`

**Nothing — and it says so.** No `ledger_items` row is written and settlement is **refused by
name**, never priced at 0. The runner's end modal renders 「기록을 확정하고 있어요 — 잠시 뒤 정산할
수 있어요」, submit disabled with the reason visible; the amount shows pending, not `0원`. The
owner's report shows 확정 중, not a distance. **Loading is not 0** — and §3's `run_ended_at`
argument is exactly where a `Number(null) === 0` would manufacture one.

## §4 Signatures and meanings that change — with callers enumerated

**Grep basis:** `grep -rn "club_save_run_trace|_club_derive_run_km|club_end_pack_runs" app/ supabase/functions/`.
**Zero edge-function callers of any of the three.** [measured]

1. **`club_save_run_trace(uuid, jsonb) returns int`** (`0156:52`) — gains a typed refusal; a raise
   is now reachable where only a `0` was. *Callers:* `api.ts:4428-4429` (`saveClubRunTrace`) →
   `club/run/[sid].tsx:278` (60 s tick) and `:331` (inside `doSettle`). `api.ts:2502`'s
   `saveRunTrace` is a **direct table update on the marketplace path**, not this RPC. [measured]
   🔴 **Widened meaning, correct caller, no edit — §④.** `[sid].tsx:280-282` catches *every* failure
   into `setSaveLag(true)`, rendering 「트레이스 저장이 밀리고 있어요 — 신호가 잡히면 자동
   재시도해요」 (`:453`). A **permanent** refusal shown as 「will retry automatically」 is a lie the
   client tells with no change on our side. Fixed in the same slice.

2. **`club_end_pack_runs(uuid) returns jsonb`** (`0144:290`) — `ended[]` carries `km`/`durationSec`
   (`0144:508-514`); phase 1 does not know them. *Callers:* `api.ts:4327-4328` (typed
   `PackRunEndResult`, `api.ts:4326`; `PackRunEnded.km: number` **non-null** at `api.ts:4323`) →
   `club/console/[sid].tsx:438` (host) and the backup-host arm (`:453-480`). [measured]
   Keep the three-list shape; add a `phase`; make `km`/`durationSec` explicitly **`null`** at
   phase 1 — never `0`. `api.ts:4323`'s type must widen and the console must render 「확정 중」.

3. **`_club_derive_run_km(jsonb, timestamptz)`** (`0156:135`) — *sole caller* `0144:427`; revoked
   from every role (`0156:213-214`), so no client or edge caller exists. [measured]
   🔴 **Highest-risk item in the slice.** 0156's argument for not threading a cutoff is, verbatim,
   that the function "is called only from `club_end_pack_runs` inside the freeze transaction, so
   `now()` here IS the host's tap" (`0156:16-20`, `:162-164`). **Two-phase makes that false** —
   phase 2 runs 90+ s later, so `now()` is the *sweep's* clock and 0156's money guard silently
   widens the paid window by the whole drain. The cutoff **must** become a parameter (signature
   change, new `create or replace`, its own explicit ACL), or 0156's guard is reverted by a file
   that never mentions it.

4. **`club_delegation_board` → `runEnded`** (`0147:145`, projects `run_ended_at is not null`; type
   `api.ts:4218`). Today it means **「the numbers are frozen」**. *Consumers:*
   `club/run/[sid].tsx:300` (`!d.runEnded && trackMode === 'denied'` gates the settle refusal) ·
   `:594` (`endTarget?.runEnded` gates the early-end reasons) · `club/console/[sid].tsx:335-336`
   (`packRunning`/`packOther`). [measured]
   🔴 **Do NOT widen it to cover `stopping`** — add a separate `runStopping`. Widening lets `:300`
   permit a GPS-denied settle while no server numbers exist, and makes `:594` hide the early-end
   reasons for a run that is not frozen. Both callers correct, both broken with no edit.

5. **`settle-run/handler.ts:90`** — two states (null → client numbers; stamped → frozen) must
   become three. Without the third the drain window is settleable and, since `run_ended_at` is
   still NULL there, settles at the **client's** numbers — the defect moved, not fixed. [measured]

6. **`settle_run_tx`** (`0083:696` `run_not_ended`, `:709-717` §6-ⓔ) — a `stopping` booking needs a
   **new** code (`run_stop_pending`). Reusing `run_not_ended` renders 「앱을 최신 버전으로
   업데이트해주세요」 (`settle-run:216`) and sends the runner chasing a version that changes
   nothing. [measured]

7. **`supabase/tests/176_club_pack_run_end_suite.sql:799`** — P9 ⓒ records the post-tap trace
   window **as measured current behaviour**; (a)'s refusal makes it false. Updated in the **same
   slice**, with a comment saying why and naming the pin that owns the new property.

## §5 Refusal / error map

| name | Korean copy | raised by | rendered where |
|---|---|---|---|
| `run_stopping` | 「업로드가 늦었어요 — 마지막 구간은 반영되지 않아요」 | `club_save_run_trace`, after the drain window | `club/run/[sid].tsx` — **its own banner**, NOT the `saveLag` one (`:451-455`) |
| `run_stop_pending` | 「기록을 확정하고 있어요 — 잠시 뒤 정산할 수 있어요」 | `settle_run_tx` / `settle-run` (409) | end modal (`[sid].tsx:569-640`), submit disabled with the reason visible |
| `stop_pending` (new `blocked.reason`) | 「기록을 모으는 중이에요 — 곧 확정돼요」 | `club_end_pack_runs` phase 1 | host console result list (`console/[sid].tsx:438` → `endResult`) |
| `no_trace` (existing, `0144:433`) | 「GPS 기록이 없어 거리를 확정하지 못했어요」 | phase 2 / `club_end_pack_runs` | same console result list |
| `trace_future_fix` (existing, `0156:72`) | 「기기 시각이 맞지 않아요 — 시간을 자동으로 맞춘 뒤 다시 시도해주세요」 | `club_save_run_trace` | `club/run/[sid].tsx`, own banner — today it is laundered into `saveLag` |
| `impossible_speed` · `trace_out_of_order` (existing, `0156:79,82,108`) | unchanged | `club_save_run_trace` | stay in the `saveLag` banner — these genuinely are retryable |

## §6 Pins (8) — each with the mutation that reddens it

Labels are slice-prefixed `RUNSTOP-`. Every source-reading arm strips comments
(`regexp_replace(prosrc, '--[^\n]*', '', 'g')`) and carries a loud `NO-SOURCE(<fn>)` arm; every
assertion is an exact boolean (`is not true` / `is distinct from`), never a bare `IF`.

- **P1 (the money).** A point uploaded *inside* the window is priced into `runs.actual_km`.
  *Mutation:* run phase 2 at phase-1 time (no drain) → reddens.
- **P2 (the refusal).** A point uploaded *after* the window raises `run_stopping` and `runs.trace`
  does not grow. *Mutation:* restore `0156:88`'s selector to `b.status = 'active'` alone → reddens.
- **P3 (CONTROL — a 「refuse everything」 fix cannot pass).** During the OPEN window the RPC still
  ACCEPTS and the trace grows. P2 is blind to over-refusal, P3 to over-acceptance — **different
  blindness lists, so this is a real control pair**, not one measurement printed twice.
  *Mutation:* refuse every post-tap point → reddens P3 alone.
- **P4 (INACTION).** Host taps; the phone never uploads again and never settles. *Before the
  sweep:* `runs.actual_km` NULL, `bookings.run_ended_at` NULL, **zero `ledger_items` rows**, and a
  settle raises `run_stop_pending`. *After the sweep (T+90 s):* `run_ended_at` stamped and
  `actual_km` derived over the trace that existed — or `blocked/no_trace` (`0144:433`) with **still
  zero ledger rows**. *Mutation:* unregister the sweep → the after-arm reddens.
- **P5 (0156 does not widen).** Phase 2's window ends at the **tap**, not the sweep's `now()`.
  Fixture point is dated *between* tap and sweep — the set where old and new rules **disagree**, or
  the pin tests the fixture. *Mutation:* revert the threaded cutoff to `now()` → reddens.
- **P6 (idempotence, as a delta it caused).** The pin runs phase 2 **twice itself** and compares
  its own before/after — not a count inherited from a fixture. *Mutation:* drop the
  `run_ended_at is null` conjunct → reddens.
- **P7 (`run_ended_at` keeps its meaning).** During `stopping` it **is NULL**, so
  `_club_pack_window` (`0159:148-154`) still reports the map OPEN and `settle-run:90`'s frozen path
  is not armed. *Mutation:* make phase 1 stamp it → reddens, naming both consequences.
- **P8 (the guard's PRECONDITION, not its branch).** Phase 2 takes the booking row lock **before**
  reading `run_stopping_at`. *Mutation:* remove the `for update` — not the branch → reddens.

⚠ Each battery run is `&&`-chained to its plant, so a failed plant yields **no row**, never a green
one. Record the suite's before/after pin totals: a delta ≠ 8 means the suite never ran.

## §7 What does NOT change

- 🔴 **No flag gate, deliberately.** This path writes `ledger_items` today with
  `payments_live_since` NULL (`settle-run:320-322`, `0083:754`); a flag on the fix would leave the
  defect live in exactly the state it is live in now.
- 0156 §A's 1-hour ingest slack (`0156:59`, `:71-73`), and §B's `started_at <= t <= cutoff` window
  in **shape** — only the cutoff's **source** moves from `now()` to the threaded tap (§4.3).
- 0156's 300 s coverage gate (`:156`, `:208`) — unchanged, and still **Sean's to rule on**
  (`0156:43-47`).
- `club_end_pack_runs`'s three-lists return (`0144:281-285`), per-pairing subtransaction, the
  host-OR-backup gate (`0144:340-343`), the one-clock `v_at` (`0144:349`).
- `settle_run_tx` §6-ⓔ (`0083:709-717`) — the new refusal raises earlier, separately.
- `_club_derive_run_km` stays revoked from every role (`0156:213-214`).
- The marketplace path — `end_run_tx`, `api.ts:2502`'s `saveRunTrace`, `_guard_run_cols`'s
  `authenticated` arm (`0083:286`) — untouched.

## §8 Open questions — Sean's, with recommendations

**Q1 · Drain window.** (i) 60 s · (ii) **90 s** · (iii) 180 s. **Recommend (ii)** — 60 s is the
tick interval itself and leaves no margin for a tap landing just after a tick; 180 s buys almost
nothing (a phone that missed two ticks has missed the window) and delays every owner's 반환.

**Q2 · A tail arriving after the freeze — credited retroactively?** (i) **never, refused by name
and shown to the runner** · (ii) ops-only manual adjustment · (iii) automatic re-derivation and a
ledger correction. **Recommend (i), with (ii) available.** (iii) re-opens a priced ledger row and
this repo has no shape for that. Honest cost of (i): an offline phone can lose a genuinely long
tail, and the remedy is a human adjustment — which is why the refusal must be **visible** (§5)
rather than a swallowed error.

**Q3 · Phone offline for the whole window — who owns the money?** (i) `blocked/no_trace` and the
runner settles by **their own client numbers** — restoring exactly the client-priced ledger this
slice exists to remove · (ii) it stays `stopping` behind an explicit ops surface until a human
acts. **Recommend (ii).** (i) falls back to the defect precisely where we have the least evidence.
This is a money decision and I am not making it.

**Q4 · Sweep granularity.** A 60 s cron makes the real window 90–150 s. **Recommend** accepting the
jitter and pinning only the **lower** bound (never freeze before `tap + 90 s`).

## Could not be determined from source

- Whether a React Native `setInterval` fires while backgrounded under the location background mode
  — decides whether real server lag is 60 s or unbounded. **Does not block the design** (phase 2
  answers inaction either way), but it decides how often Q3's branch fires.
- Whether `ops_flags.payments_live_since` is still NULL on production today — I read the code path,
  not the row; the 2026-08-28 review measured it NULL.
- Which scheduler hosts the phase-2 sweep (`pg_cron` vs edge cron) — I did not read the cron
  registry, and this repo's `net` hygiene history means the choice is not free.
- The real distribution of tap-to-last-upload lag on hardware.
