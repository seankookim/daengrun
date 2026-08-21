# Pre-charging checklist — everything that must be true before `set_payments_live_since`

**Owner: money.** Sean owns every credential *value* here; this file owns knowing which ones, in
what order, and how to tell whether each one actually landed.

Written 2026-08-14, after `0076`–`0094` reached production. **Every line below is measured, and
each item says how**, because the whole failure class this file exists to prevent is a config
fact that was inferred rather than read.

---

## 0. The one-line state

**Charging is off, the machine is deployed and running, and it is inert at four INDEPENDENT
layers.** Turning it on is not one switch — it is three secrets and then one switch, in that
order, and the order is load-bearing.

The independence is the point, and it is a stronger claim than any single flag:

| layer | measured state | what it alone prevents |
|---|---|---|
| `TOSS_SECRET_KEY` unset | absent from `secrets list` | no charge call can be made at all |
| `CRON_COLLECT_KEY` unset | absent from `secrets list` | the function refuses every batch request (503) |
| Vault `charge_dispatch` absent | `vault.decrypted_secrets` → **0 rows** | nothing ever calls the function |
| `payments` empty | 0 rows | the dispatch job exits before it looks at anything |

**No single mistake starts charging.** Restoring any one of these four leaves the other three
holding. That is worth knowing precisely because the opposite reassurance — "the flag is off" —
is one row in one table, and a single `update` away from being wrong.

⚠ **The cron jobs are ON and running right now.** All 17 scheduled jobs are active in production,
including `dispatch-due-charges` (`4-59/5 * * * *`) and `sweep-settled-charges` (`2-57/5 * * * *`).
They fire every five minutes and do nothing, by gate rather than by absence. Seeing them in
`cron.job` is not a sign that something was switched on early.

---

## 1. Measured state

    supabase secrets list          → exactly 7, all SUPABASE_* platform defaults
    supabase functions list        → collect-charges v1, verify_jwt:false, ACTIVE
    ops_flags                      → payments_live_since NULL · return_seal_since NULL
    billing_keys                   → 0 rows
    payments                       → 0 rows

Read directly, not relayed. `ops_flags` was read with `is.null` / `not.is.null` counts rather
than by eyeballing a JSON `null`, because those are different claims.

---

## 2. Blocking items

### 2.1 🔴 `TOSS_SECRET_KEY` is not set — Sean

**Not on the roster's list, and it is the biggest one.** `_shared/toss.ts` reads it; without it
no charge can be *attempted*, batch or owner-initiated. Every other item here is about reaching
the charge call. This one is the call.

    verify:  supabase secrets list | grep TOSS_SECRET_KEY     # currently: no match

⚠ Which key matters: a TEST key exercises the whole path against Toss's sandbox and settles
nothing real. The live key requires the 사업자등록 → 통신판매업 → Toss contract chain with
자동결제 심사 in the same application. **Do the sandbox matrix on the test key first**; the flag
and the key are independent switches and there is no reason to move both at once.

### 2.2 🔴 `CRON_COLLECT_KEY` is not set — Sean

The edge function's half of the batch gate.

    verify:  supabase secrets list | grep CRON_COLLECT_KEY    # currently: no match

**Its absence is safe, and deliberately so.** `handler.ts:63` refuses to authenticate against an
unset secret (`if (!expected) throw 503`) rather than letting `null === null` turn a
misconfigured deploy into an open batch-charging endpoint. Verified against production, not just
read — see §4.

### 2.3 🔴 Vault secret `charge_dispatch` is absent — Sean · **MEASURED**

`dispatch_due_charges` (`0080:1259`, cron `4-59/5 * * * *`) does **not** read an environment
variable. It reads a Postgres **Vault** secret:

    select decrypted_secret from vault.decrypted_secrets where name = 'charge_dispatch';
    → must be {"url": "https://<ref>.supabase.co/functions/v1", "cron_key": "<same value as CRON_COLLECT_KEY>"}

**So the cron key must exist in TWO places with the SAME value** — the Vault secret (who calls)
and the function's env (who answers). Nothing in the system checks that they agree. A mismatch is
the quietest failure mode available here: the cron fires, the function returns 401, and the ladder
is dead while every dashboard looks configured. **Set them from one copied value, in one sitting.**

**Measured empty:**

    supabase db query --linked "select name, created_at from vault.decrypted_secrets"
    → []      # zero secrets of any name, so charge_dispatch does not exist

Names and timestamps only — never `decrypted_secret`. There is no reason to read a secret's value
to know whether it exists, and every reason not to.

📌 **The general lesson, which outlives this item.** I first recorded Vault as "unverified, not
reachable" because I was probing through PostgREST, where the `vault` schema is invisible.
`supabase db query --linked` connects as a **login role** instead of going through PostgREST — the
same reason it also sees past RLS. **When a production question comes back "not reachable", check
whether you were asking through the wrong door before writing it down as unknowable.** Found by
the announcer session, who simply tried the other door.

### 2.4 🟡 `OPS_PROFILE_ID` is not set — Sean

`0084`'s ops alerting resolves its recipient through this. Not a charging blocker: charges work
without it. It is an *observability* blocker — with it unset, the reconciliation arms fire into
nothing, which is exactly the state you do not want during the first live week.

    verify:  supabase secrets list | grep OPS_PROFILE_ID      # currently: no match

### 2.4-bis 🟡 `ops_recipients` has 0 rows — the other half of 2.4

`OPS_PROFILE_ID` unset is one half; the recipients table being empty is the other, and either
alone is enough to make every ops signal land nowhere. Today that means `0084`'s reconciliation
arms **and** custody's `0096`/`0097` detection all fire into a `console.error`. Recipient choice is
Sean's, wiring is custody's — it is on this list because "ops routing populated" is a pre-flip
condition for money even though neither half is money's to build.

    verify:  select count(*) from ops_recipients;      # currently: 0

### 2.5 🟡 `billing_keys` is empty — product decision, not config

Zero owners have a registered card. The first live run will therefore hit "no billing key" rather
than a decline. That path exists and is honest, but **decide what the owner sees before it happens
to a real person**, not after. Card registration placement is already ruled
([card-registration-placement.md](decisions/card-registration-placement.md)); this is the
consequence of it not being built yet.

### 2.6 ⚪ The flag itself — Sean, LAST

    select set_payments_live_since('<a future timestamp>');

`0084` refuses any value `<= now()` (`cutover_must_be_future`), deliberately `<=` and not `<`
because `now()` is transaction-start time. **This is why nothing can be back-billed**: the sweep
scopes on `runs.ended_at >= since`, so the 9 already-finished runs are permanently outside the
window. Do not try to "catch up" by backdating — the setter will refuse, and that refusal is the
feature.

---

## 2-ter. The historical data state — read this before you diagnose anything

Measured 2026-08-14. None of it is a defect; all of it will look like one to someone reading a
single query.

- **`ledger_items` has 8 rows, not 0** (2026-07-28 → 08-11, 8 distinct bookings). The money
  surface is not an empty table. It matches the 8 `completed` bookings exactly.
- **`runs.settled_at` is NULL for all 9 runs, including the 8 that are settled and have ledger
  rows.** `settle_run_tx` writes `settled_at = now()` at `0083:112`, but these runs predate 0083 —
  they were settled by an earlier version that did not have the column in its write list. **So
  "settled_at is null" does NOT mean unpaid on historical rows; the ledger row is the evidence.**
  This is exactly why `0097` checks ledger-absence *and* `settled_at is null` rather than either
  alone, and why REGISTRY's shared-object note says ledger presence is not a settlement anchor.
- **No cutover consequence.** `sweep_settled_without_payments` anchors on `settled_at` *and*
  scopes on `ended_at >= payments_live_since`, and the setter refuses a past timestamp — so every
  one of these rows is outside the window by construction, twice over.
- **The one `incident_review` booking is a CLUB booking.** Its run ended 2026-07-30 with no ledger
  row, which reads like §0h biting today. It is not: clubs settle through `club_release_payouts`
  (0045/0072), a different path, and `0097` excludes `club_session_id is not null` deliberately.
  **`ops_unsettled_runs()` returning 0 is correct**, verified by calling it against production.
  ⚠ Do not "fix" that exclusion — it would report every club booking as an unpaid marketplace run.
- **There is therefore no unpaid marketplace runner in production today**, which is the same
  conclusion as before but now rests on the right evidence. My earlier version of this check read
  `bookings.run_ended_at` where it should have read `runs.ended_at` — two different columns, and
  the booking's was null while the run's was set.

## 3. Things that look alarming and are not

Listed because each one has already cost someone a second look.

- **`dispatch-due-charges` fires every 5 minutes right now.** It is not erroring. It exits at the
  *first* gate — `0080:1214`, `if v_due = 0 then return 0`, which sits BEFORE the Vault read at
  `0080:1218` — because `payments` is empty. It never reaches the Vault read and makes **no HTTP
  call at all**. The roster's "collect-charges gets a 503 from every sweep" describes a state we
  are not in; nothing is being called.
- **Even when it does reach the Vault read, an absent secret is a NOTICE and a `0`,** not an
  error, and the whole read is exception-guarded so the cron job cannot die from it. That is
  deliberate: the function's own comment calls the absent case "the correct pre-cutover state". A
  scheduled job that silently returns 0 is normally a smell; here it is the design, which is why
  it is written down rather than left to be rediscovered as a bug.
- **`collect-charges` runs with `verify_jwt:false`.** Correct, and necessary: pg_net calls it
  without a JWT. The owner path is not exposed by this — see §4.
- **It was deployed from a worktree named for git cleanup.** Odd provenance, identical content:
  I downloaded the deployed source and diffed all five files (`index.ts`, `handler.ts`,
  `_shared/ctx.ts`, `_shared/toss.ts`, `_shared/charge.ts`) against trunk. **Byte-identical.**
  The concern is process, not what is running.
- **9 runs have `ended_at` and no payments row.** Outside the cutover window by construction (§2.6).

---

## 4. Auth-model review — `collect-charges` (requested before charging is enabled)

**Verdict: sound. Probed against production, not read.**

Two modes, selected by the presence of `X-Cron-Key`:

| request | expected | measured |
|---|---|---|
| no JWT, no cron key → owner path | 401 | **401** `{"error":"unauthorized"}` |
| bogus `X-Cron-Key` → batch path, secret unset | 503 | **503** `수금 배치가 설정되지 않았어요` |
| **empty** `X-Cron-Key` → the `"" === ""` case the code comment warns about | must not authenticate | **503** |
| `payments` row count after all three probes | 0 | **0** |

The third row is the one worth keeping: an attacker chooses which branch to enter by including or
omitting a header, so both branches must stand on their own, and the empty-header case is the one
a naive guard gets wrong.

`verify_jwt:false` does not weaken the owner path. Platform JWT verification is off, so the
function's own `caller()` (`_shared/ctx.ts:31`) is the entire defense — and it validates
server-side via `db.auth.getUser(jwt)`, throwing 401 on an empty or bad token rather than
trusting a claim. Confirmed by probe 1.

**One hardening item, low severity, not a blocker:** `cronKey !== expected` is not a
constant-time comparison. Over the public internet, network jitter swamps the timing signal, so
this is a hygiene item rather than a live risk — worth a `timingSafeEqual` when someone is next in
this file, not worth its own slice.

---

## 4-bis. What is TRUE about charging, for the UI slice

Written for whoever fixes the payment surface under Sean's option A. **This is the money owner's
statement of fact; build against it rather than against the code's intent.**

**Today, and until `payments_live_since` is set:**

- **Nothing is charged, ever, by any path.** Not at booking, not at run end, not later. Four
  independent layers (§0), and the `payments` table has zero rows.
- **No card is stored for anybody.** `billing_keys` is empty. There is no owner with a payment
  method on file, so "your card" refers to nothing for every user alive.
- **The runner IS credited.** `ledger_items` has real rows for completed runs — the runner-side
  ledger is live and truthful. Do not let a "payments are off" message imply the runner was not
  recorded as owed.
- **Money moves by manual transfer, arranged off-app.** That is the pilot, not a fallback.

**What the screen may NOT say**, because none of it is true:
- 결제 완료 / 자동 결제 / 결제 수단 — there is no payment, no automation, no method.
- Any card CTA that does not open a working register flow. `payments.tsx:26` already refuses this
  one and says why; keep that discipline.
- Any owner-facing "charged" or "paid" state derived from anything other than a real `payments`
  row. There are none, so there is nothing to derive.

**What it MAY say, bound to real fields:**
- The booking's own frozen price (`bookings.total_price` and its components) — that is a real
  number about what the run costs, and it is not a claim that anything was charged.
- That payment is arranged directly during the pilot, in whatever words the copy owner picks.
- The existing 준비 중 empty state, which is honest as written.

⚠ **The trap to avoid is the tempting one:** showing a total and letting placement imply it was
collected. An amount next to a date, on a screen called 결제 관리, reads as a receipt whether or
not the word appears. If the screen shows an amount, it has to say what happened to it.

**When the flag flips, this section is wrong** and the payment surface becomes the real thing.
Whoever moves the flag should come back here — it is listed in §5 for that reason.

## 5. First ten minutes after the flip

Run in this order; stop at the first surprise.

1. `select payments_live_since from ops_flags;` — confirm it is what you set, and in the future.
2. Wait for one `dispatch-due-charges` tick (≤5 min). `select count(*) from payments;` — still 0
   is correct until a run ends after the cutover.
3. End one real run. `select status, raw->>'kind', amount from payments order by created_at desc limit 1;`
4. If it is `failed`, read `raw->>'last_error'` before retrying anything — the retry ladder is
   0/+1h/+24h and a manual retry consumes a rung.
5. `select count(*) from payments where status = 'failed';` — a number >1 in the first hour means
   the ladder is walking, and that is the moment to stop and read rather than to wait.

⚠ **Do not smoke the machine by calling `collect-charges` directly.** It mints and charges. The
honest test is a real run ending after a real cutover.

## Hard blockers added 2026-08-21 (0116 landing review — do not flip without these)

- [ ] **The club-fee slice has LANDED AND DEPLOYED** (held follow-up of 0116 §B, spec in
  REGISTRY row 0116). Until it lands: club cancel/no-show fees are computed into
  `club_fee_items` only — `bookings.cancel_fee` stays empty, no intent is ever minted, the
  runner's share reaches no ledger. Flipping charging without this slice means club
  cancellations silently cost nobody anything. Sean's ladder ruling (2026-08-21: club rules
  as written) is recorded; the slice builds against it.
- [ ] **Incident settlements and `runs.settled_at` are reconciled** (0116 review finding 3):
  `club_incident_settle` writes a legitimate settlement and never stamps `settled_at`, so the
  post-0116 sweep will silently never record incident-settled runs. Fine while every incident
  is provisionally waived; NOT fine the day that policy changes. Before flip: either stamp the
  authoritative event in the incident path, or encode + monitor an explicit waiver outcome.
