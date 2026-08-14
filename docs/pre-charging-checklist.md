# Pre-charging checklist — everything that must be true before `set_payments_live_since`

**Owner: money.** Sean owns every credential *value* here; this file owns knowing which ones, in
what order, and how to tell whether each one actually landed.

Written 2026-08-14, after `0076`–`0094` reached production. **Every line below is measured, and
each item says how**, because the whole failure class this file exists to prevent is a config
fact that was inferred rather than read.

---

## 0. The one-line state

**Charging is off, the machine is deployed, and it is inert at four independent layers.** Turning
it on is not one switch — it is three secrets and then one switch, in that order, and the order
is load-bearing.

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

### 2.3 🔴 Vault secret `charge_dispatch` — Sean · **UNVERIFIED, and the roster is wrong about this one**

`dispatch_due_charges` (`0080:1259`, cron `4-59/5 * * * *`) does **not** read an environment
variable. It reads a Postgres **Vault** secret:

    select decrypted_secret from vault.decrypted_secrets where name = 'charge_dispatch';
    → must be {"url": "https://<ref>.supabase.co/functions/v1", "cron_key": "<same value as CRON_COLLECT_KEY>"}

**So the cron key must exist in TWO places with the SAME value** — the Vault secret (who calls)
and the function's env (who answers). Nothing in the system checks that they agree. A mismatch is
the quietest failure mode available here: the cron fires, the function returns 401, and the ladder
is dead while every dashboard looks configured. **Set them from one copied value, in one sitting.**

I could not read Vault over PostgREST, so its presence is the one item on this page I have **not**
measured. Sean or trust can settle it with the query above.

### 2.4 🟡 `OPS_PROFILE_ID` is not set — Sean

`0084`'s ops alerting resolves its recipient through this. Not a charging blocker: charges work
without it. It is an *observability* blocker — with it unset, the reconciliation arms fire into
nothing, which is exactly the state you do not want during the first live week.

    verify:  supabase secrets list | grep OPS_PROFILE_ID      # currently: no match

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

## 3. Things that look alarming and are not

Listed because each one has already cost someone a second look.

- **`dispatch-due-charges` fires every 5 minutes right now.** It is not erroring. It exits at the
  *first* gate — `if v_due = 0 then return 0` — because `payments` is empty. It never reaches the
  Vault read, and it makes **no HTTP call at all**. The roster's "collect-charges gets a 503 from
  every sweep" describes a state we are not in; nothing is being called.
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
