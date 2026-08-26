# Audit — 맹견 Slice B readiness · definer-ACL schema health

**Date** 2026-08-26 · **Tree** `.claude/worktrees/club-delegation-spec-v2-a41fbc` (branch
`claude/club-delegation-spec-v2-a41fbc`) · **Scope** read-only with respect to code. The only file
this session created is this report.

**Evidence discipline used here.** Every claim below is tagged:
- **[M]** — I ran the command / read the source line in this session. The output is reproduced.
- **[I]** — inferred from source I read, not executed. Stated as inference.
- **[R]** — relayed: another session's recorded measurement, cited as theirs, not re-measured by me.
- **[U]** — could not establish. Listed in full in §C.

One finding in this report is a **correction of my own first answer** (§B-5, `_distance_band`): a
parser I wrote produced a hypothesis and reading the source refuted it. It is left visible rather
than swapped out.

**Amended after first commit.** The report was committed with production state listed as
unverified, because `supabase db query --linked` returned nothing on its first attempt. It
succeeded on retry, and §A-1, §B-3, §B-4b and §C now carry **my own** production measurements in
place of relayed ones. The superseded `[U]` entries are struck through rather than deleted, so the
sequence — committed honestly unverified, then verified — stays legible.

---

## §0. Ranked summary — what blocks what

| # | Finding | Blocks | Whose move |
|---|---------|--------|------------|
| 1 | **The Slice B distribution gate measures EMPTY.** 0 EAS builds ever, 0 OTA updates ever, only 1 of the 4 declared channels exists. **[M]** | Nothing — the gate is satisfied on the EAS surface | Sean confirms one fact (§A-3) |
| 2 | **The contract's fixture-unwind list is incomplete and its failure mechanism is wrong.** Suite **161** must be unwound too and the contract does not name it; the 113/139/146/149 failures are **uncaught aborts**, not "caught pin failures". **[M]** | Slice B authoring | Engineering, no decision needed |
| 3 | `seed.sql` is **not** a harness file — its reference breaks `supabase db reset`, a different surface than the contract implies. **[M]** | Slice B completeness | Engineering |
| 4 | Definer-ACL gate is **green**, baseline is **exactly 81**, and an **independently written scanner reproduces the set exactly — 81/81, zero extras, zero misses**. **[M]** | Nothing | — |
| 5 | `0121:240` `club_incident_settle_quote` — **confirmed still true, still latent, nothing since 0121 has touched it.** Baselined at line 87; **live ACL measured, PUBLIC absent**. **[M]** | Nothing | Rides the next money-path slice (already recorded) |
| 4b | **Production sweep measured directly: 219 public definers, 0 PUBLIC-executable, 0 anon-executable, 0 NULL-ACL.** All 81 baselined occurrences are latent, not breached. **[M]** | Nothing | — |
| 6 | **Three latent gate blind spots** (schema-qualified headers · plain `create function` · the 400-char window). All three measured **empty in the current corpus** — they are gaps, not misses. **[M]** | Nothing today | Decision: harden the gate or record the gap (§B-5) |
| 7 | `check-definer-acl.mjs` comment says *"this gate's job is the 84th"*; the baseline is 81 and CLAUDE.md says *the 82nd*. **[M]** | Nothing | Trivial doc fix |

---

# AUDIT 1 — is 맹견 Slice B ready, and what exactly does it need?

## A-1. What Slice B must drop — enumerated by name, each verified present

Source of truth is `0119` (creates) and `0127` (deliberately keeps). All line references **[M]**.

| Object | Kind | Created | Still present |
|---|---|---|---|
| `dog_dangerous_status` | enum type (`undeclared`/`declared_none`/`declared_dangerous`) | `0119:130` | Yes — `0127`'s VERIFY **aborts the migration** if it was dropped (`0127:629-630`, *"0127 OVER-REACH: the dog_dangerous_status enum was dropped — that is Slice B"*) |
| `dogs.dangerous_status` | column, `not null default 'undeclared'` | `0119:133` | Yes — `0127:624`, `0127:639` |
| `dogs.dangerous_basis` | column, `text` nullable | `0119:134` | Yes — same |
| `dogs.dangerous_declared_at` | column, `timestamptz` nullable | `0119:135` | Yes — same |
| `dogs_dangerous_basis_pairs_with_status` | table CHECK constraint | `0119:141-143` | Yes — `0127:619` asserts it by name |

**All five objects additionally VERIFIED LIVE IN PRODUCTION by me. [M]** `supabase db query
--linked` failed on its first attempt (it was initialising a login role) and succeeded on retry;
the audit originally carried this as unverified, and the measurement below replaced that:

```
column_name           | data_type                   | is_nullable
----------------------+-----------------------------+------------
dangerous_basis       | text                        | YES
dangerous_declared_at | timestamp with time zone    | YES
dangerous_status      | USER-DEFINED                | NO

k             | v
--------------+---------------------------------------
check         | dogs_dangerous_basis_pairs_with_status
enum          | dog_dangerous_status:e                  ← typtype 'e' = real enum
```

That matches `161`'s P6 signature assertion (`161:858-860`) exactly, including the `NOT NULL` on
`dangerous_status` and the `USER-DEFINED` (enum) type. **The Slice A boundary is holding in
production, measured directly rather than inferred from the migration text or relayed from a
handoff.**

**Riders that must come out with them** (these are the "any comment/constraint/index that rides
them" the brief asked for) **[M]**:

- **Three column comments, and they are the *rewritten* ones, not 0119's.** `0127:354`, `0127:365`,
  `0127:373` each re-issue `comment on column dogs.dangerous_*`, because 0119's originals asserted
  behaviour that is now false. Slice B drops the columns, which drops these implicitly — but they
  are the current text and anyone diffing against `0119` will find the wrong strings.
- **No index rides these columns.** **[M]** — no `create index` in `0119` or `0127` names any of
  the three; the only constraint is the pair-CHECK above.
- **`0127:361` is a written instruction to Slice B** inside `dangerous_status`'s own comment: it
  names all three columns plus the enum as the drop set, conditioned on "once ZERO…".

**Inference, stated as such [I]:** the enum cannot be dropped before the column, because
`161:101-102` records the dependency graph refusing exactly that — *"cannot drop type
dog_dangerous_status because other objects depend on it / column dangerous_status of table dogs"*.
Slice B's statement order is therefore CHECK → columns → type, and a `drop type` first will abort.

## A-2. The fixture unwind — the measured list differs from the contract's

The contract (`docs/contracts/maenggyeon-gate-removal-contract.md` §4) predicts the drop reddens
`10/seed/113/139/146/149` in two mechanisms. **The measured list has two more entries and one of
the two mechanisms is wrong.**

### Measured reference set (whole `supabase/` tree, counts per file) **[M]**

```
33  supabase/migrations/0119_dangerous_breed_gate.sql     (the defining migration)
19  supabase/migrations/0127_remove_dangerous_breed_gate.sql
 1  supabase/migrations/REGISTRY.md
 2  supabase/seed.sql
 1  supabase/tests/10_settle_suite.sql
 3  supabase/tests/113_km_ledger_suite.sql
 2  supabase/tests/139_run_channel_rls_suite.sql
 3  supabase/tests/146_booking_entry_suite.sql
 2  supabase/tests/149_party_active_suite.sql
37  supabase/tests/154_dangerous_breed_suite.sql          ← NOT in the contract's list
42  supabase/tests/161_breed_gate_removal_suite.sql       ← NOT in the contract's list
```

### The two the contract misses

**① Suite 161 — the live one, and the one that matters.** `161_breed_gate_removal_suite.sql` is
**registered in the harness at `harness.sh:207`** **[M]** and its pin **P6 is the slice boundary
asserted in the over-removal direction**: it fails deliberately if the columns go early.

- `161:846` and `161:856` — counts and shapes the three columns by name.
- `161:858-860` — asserts the exact column signature string,
  `dangerous_status:dog_dangerous_status NOT NULL:'undeclared'::dog_dangerous_status | dangerous_basis:text NULL:<no default> | dangerous_declared_at:timestamp with time zone NULL:<no default>`.
- `161:868-869` — asserts the enum exists **as an enum type**, failing with
  「🔴 dog_dangerous_status가 이넘 타입으로 존재하지 않는다 — Slice B가 앞당겨졌다」
  (*"…Slice B was pulled forward"*).
- `161:879-880` — asserts `dogs.dangerous_status` still has type `public.dog_dangerous_status`.
- `161:349/353/359/365/367/374` — P2's write arms use the columns as fixtures.

This is not an oversight in 161 — it is a designed tripwire, and it is doing its job. But it means
**Slice B's landing must rewrite or retire 161's P6 in the same slice**, under the standing law
*"a suite whose pinned behaviour legitimately changes MUST be updated in the same slice"*
(CLAUDE.md). The contract predates 161 (161 was created *by* Slice A), which is why the list is
stale — the stale-list risk the contract itself warns about, realised.

**② Suite 154 — needs no action, and that should be written down so nobody does any.** 154 carries
37 references but is **absent from `harness.sh`** **[M]** (grep of harness.sh for `154_dangerous`
returns nothing). `0127`'s header records the reasoning at `0127:50-56`: the file is kept on disk
on purpose as the readable record, retirement *is* the harness dropping the line. Slice B should
touch it only to note it, not to edit it.

### The mechanism the contract gets wrong

The contract says: *"`t_dog`/seed are `language sql` (parse-time death), the 113/139/146/149
inserts sit in DO blocks where a missed column is a **caught pin failure** — both red, different
shapes."*

**Half of that is right. The 113/139/146/149 half is wrong, and wrong in the more disruptive
direction.** **[M]**

| Suite | Line | Enclosing block | Nearest handler | Actual mechanism |
|---|---|---|---|---|
| `10_settle_suite.sql` | `:24` | `t_dog`, `language sql` | n/a | **Parse-time death at `create or replace function`** — matches the contract |
| `seed.sql` | `:19` | top-level statement | n/a | Plain statement error (see A-2③) |
| `113_km_ledger_suite.sql` | `:102` | outer `begin` of `do $$` opened at `:87` (outer `begin` at `:96`) | inner `begin` starts `:118`, handler `:128` — **after** the insert | **Uncaught** |
| `139_run_channel_rls_suite.sql` | `:32`,`:33` | outer `begin` of `do $$` at `:13` (outer `begin` `:17`) | first inner `begin` at `:83` | **Uncaught** |
| `146_booking_entry_suite.sql` | `:176-178` | outer `begin` of `do $$` at `:154` (outer `begin` `:168`) | first inner `begin` at `:198` | **Uncaught** |
| `149_party_active_suite.sql` | `:180-181` | outer `begin` of `do $$` at `:155` (outer `begin` `:167`) | first inner `begin` at `:253` | **Uncaught** |

In all four the fixture insert sits in the **outer** block, textually **before** the first inner
`begin … exception` — so an `undefined_column` propagates out of the DO block. It is not caught and
it does not become a `_fail` pin.

**Why that matters more than a naming quibble** — `harness.sh:115-123` **[M]**:

```
suite() {
  local out
  out=$(psql -v ON_ERROR_STOP=1 -q -f "$1" 2>&1)
  if [ $? -ne 0 ]; then
    echo "❌ SUITE PARSE/EXEC FAILED: $1"
    echo "$out" | grep -v NOTICE | head -12
    exit 1
  fi
}
```

`exit 1` — the harness **stops dead at the first affected suite**. And `10_settle_suite.sql` is
registered at `harness.sh:124`, the **first** of the affected files in run order, where the failure
is a `language sql` parse-time death of `t_dog`.

**Consequence for Slice B, and it changes how the work is sequenced [I]:** you will never see
113/139/146/149/161 go red. You get one red — suite 10 — fix it, get one more, fix it, and so on,
five round trips of a full harness rebuild each. **The fixture unwind must therefore be authored
as one complete edit across all six files up front, from the measured list above, not iteratively
red-by-red.** The contract's "both red, different shapes, stated so nobody generalizes" framing
invites exactly the iterative approach that does not work here.

### ③ `seed.sql` is a different surface from the other five

`supabase/seed.sql:17-19` **[M]** writes `dangerous_status` on the local seed dog. **`seed.sql` is
not run by the harness** — grep of `harness.sh` for `seed` returns only the English word "seeds"
inside a comment on line 178 **[M]**. So its breakage lands on `supabase db reset` / local dev
bring-up, not on the harness score. The contract groups it with `t_dog` under "both red"; it is a
real edit but it will never appear in a harness number, so it is the one most likely to be
forgotten.

## A-3. The distribution gate — measured, and it is EMPTY

`app/eas.json` declares four channels **[M]**: `development` (:build.development.channel),
`preview`, `testflight`, `production`. `app.json` **[M]**: `updates.url =
https://u.expo.dev/0436bc27-2933-4627-a0bf-9527e65c1ad9`, `updates.fallbackToCacheTimeout = 0`,
`runtimeVersion.policy = "fingerprint"`, `owner = "seankookim"`.

**The evidence is obtainable here. It did not require Sean.** The EAS CLI on this machine is
already authenticated **[M]**:

```
$ npx eas whoami
seankookim
seankookim@uchicago.edu
Accounts:
• seankookim (Role: Owner)
• seankookims-team (Role: Owner)
```

That is a credential already configured on the machine, which CLAUDE.md §Operations permits using
(no secret value was read, typed or relayed). Measured:

```
$ npx eas channel:list --non-interactive --json
{ "currentPage": [ { "name": "testflight",
                     "createdAt": "2026-08-19T01:17:55.287Z",
                     "isPaused": false,
                     "updateBranches": [ { "name": "testflight", "updateGroups": [] } ] } ] }

$ npx eas build:list --non-interactive --limit 20 --json
total builds returned: 0
```

**Three facts fall out [M]:**

1. **Zero EAS builds have ever been produced for this project.** Not zero recent — zero, full stop.
2. **Only one of the four declared channels exists on EAS** (`testflight`). `development`,
   `preview` and `production` have never been created — EAS creates a channel on first build or
   update against it, so their absence is itself evidence nothing was ever shipped to them.
3. **`testflight` has `updateGroups: []` — zero OTA updates ever published.** The OTA fleet is
   empty, so `fallbackToCacheTimeout: 0` has nothing to serve and the non-atomic-OTA hazard the
   contract was written around **has no population to apply to**.

**Therefore the precondition 「zero installed bundles reference `dangerous_status`」 is satisfied
vacuously on the entire EAS surface.** There is no distribution to wait out.

### What this does NOT cover — and it is small, and it is Sean's, and it is one sentence

Two residual surfaces are invisible to EAS **[I]**, and both are Sean's to confirm because both
concern binaries or accounts only he has:

- **Locally-built binaries.** `npx expo run:ios` (the CLAUDE.md-documented build path, incl. the
  `LANG`/`LC_ALL` note in memory) produces a binary on a device or simulator without touching EAS.
  A dev build on Sean's own phone from before Slice A landed would still contain
  `DOG_SELECT`'s two columns.
- **App Store Connect / TestFlight submissions made outside EAS.** CLAUDE.md §Operations names App
  Store Connect as Sean-only *because it needs a credential's value*, so I did not and cannot
  check it. The `testflight` **channel** exists (created 2026-08-19) while **zero builds** exist,
  which is consistent with a build profile that was configured but never run — but I did not
  measure App Store Connect and I am not inferring its state from a channel record.

**🔵 DECISION — Sean's, and it is a confirmation rather than work.** The question to put to him is
one sentence: *"Has any 도그스하이 binary ever reached a device other than your own dev phone —
TestFlight, App Store, or a build you sideloaded for someone else?"* If the answer is no, the
contract §0 measurement is complete, the result is recorded in Slice B's header as measured above,
and **Slice B is unblocked today**. If the answer is yes, the residual set is exactly "binaries
Sean can name", not an unbounded fleet.

This is the finding that changes Slice B's status: it was carried as *blocked on a measurement
nobody had done*. The measurement is now done and it is empty. What remains is not work — it is a
yes/no from Sean.

## A-4. Anything else still referencing the feature

**Client — clean. [M]** A sweep of `app/` for
`dangerous_status|dangerous_basis|dangerous_declared_at|dangerousRefusalFrom|dangerous-copy|DangerousStatus|DangerousBasis|맹견`
returns **zero hits**. The deleted module and its test chain are confirmed gone:
`app/src/lib/dangerous-copy.ts`, `app/test/dangerous-copy.test.cjs`,
`app/test/run-dangerous-copy-tests.sh` all `No such file or directory` **[M]**.

**Edge functions — clean. [M]** A sweep of `supabase/functions/` for `dangerous|맹견` returns two
hits, both the ordinary English adjective in unrelated retry-ladder comments
(`_test/collect_charges_test.ts:474`, `:669`). No token mapping, and
`_test/booking_danger_token_test.ts` is absent.

**Server — only the five objects in §A-1, plus the fixtures in §A-2, plus prose.** The one
`REGISTRY.md` hit is the 0119 row's description **[M]**.

**So Slice B's surface is: 1 migration + 6 fixture files (5 suites + seed.sql) + 161's P6.** The
client and edge halves of the removal are fully complete.

---

# AUDIT 2 — definer-ACL health across the schema

## B-1 & B-2. The gate runs green; the baseline is exactly 81 and every line is live

**[M]**, from `app/`:

```
$ node scripts/check-definer-acl.mjs
✅ definer 재생성 ACL — 새 보존 의존 없음 (기준선 81건 그대로, 마이그레이션 127개)
EXIT CODE = 0
```

Baseline file line count **[M]**: `87` total lines, **`81` non-comment non-blank** — matching the
gate's reported `기준선 81건`.

**What that green proves, in one sentence, per the standing law.** Reading `check-definer-acl.mjs`
**[M]**, the success branch requires `fresh.length === 0 && stale.length === 0`. So the sentence is:

> *Across the 127 migration files on disk, the set of "SECURITY DEFINER `create or replace` whose
> function was first defined in a different file, in a file issuing no matching `revoke execute on
> function <fn>(`" is **exactly** the 81 keys frozen in the baseline — no new member, and no
> baseline line whose occurrence has disappeared.*

**What it does NOT prove**, and the gate's own header says so **[M]**: it does not prove any ACL is
*correct*; it does not see dynamic SQL; it does not see a grant deliberately issued from a later
migration; and it reads **source**, so it says nothing about any live database. The runtime sweep
(`98 H1`/`H9`) and this gate prove different things and neither is evidence for the other.

**One measured detail worth recording:** the gate scanned **127** files, and the tree holds 126
tracked `.sql` migrations plus one untracked — `supabase/migrations/0129_club_return_address_arm_fix.sql`,
another session's in-flight file **[M]**. So the green includes 0129, which is not on origin. That
is the gate behaving correctly (it reads the directory, not the index), but a reader should not
take this green as a statement about trunk.

## B-2b. Independent reproduction — an actual control, not the same claim twice

Per the standing law that agreement is not evidence, I did not simply re-read the gate's output. I
wrote a **separately-parsed** scanner (`scratchpad/indep-sweep.mjs`) that differs from the gate on
purpose:

- strips **block** comments `/* … */` as well as line comments (the gate strips only line comments)
- accepts `create function` as well as `create or replace function`
- accepts and normalises **schema-qualified** names (`public.fn`)
- detects `security definer` anywhere between a header and the **next header** — no 400-char window
- accepts schema-qualified `revoke`, and `revoke all` as well as `revoke execute`

Run with the gate's own strict ACL rule (revoke-only), against the same corpus **[M]**:

```
files scanned       : 127
independent findings: 81
gate baseline size  : 81

--- in MINE but NOT in baseline (new instances the gate may be missing) ---
  (none)
--- in baseline but NOT in mine (parsing divergence) ---
  (none)
```

**Exact set equality, 81/81, from an independently written parser.** That is the strongest
statement available from source about B-4.

**A deliberate negative control that fired.** I first ran the same scanner with a *looser* ACL rule
that accepted a `grant` as evidence the file "set the ACL". It produced **53** findings — 28 fewer
than the baseline **[M]**. The 28 (e.g. `0037_club_delegation.sql:club_create_session`,
`0052_audit_gates.sql:club_incident_resolve`) are files that issue a `grant execute … to
authenticated` but **no** `revoke … from public`. **The gate is right and my looser rule was wrong**,
and this is worth stating explicitly because "there is a grant, so the ACL is handled" is the
intuitive misreading:

**[M] measured in an isolated scratch PG16 cluster** (own datadir, own socket, nothing in the repo
touched), replicating `00_shim.sql:73`'s default-privileges line and `0037:362`+`:461`'s exact
shape — a fresh signature created via `create or replace`, granted to `authenticated`, never
revoked:

```
proacl              | =X/postgres postgres=X/postgres service_role=X/postgres authenticated=X/postgres
PUBLIC can execute? | true
anon can execute?   | true
H9 would flag it?   | true
```

`=X/postgres` is the PUBLIC entry. **A grant does not displace PUBLIC; only a revoke does.** Any
future proposal to soften the gate to "a grant counts" would reopen the whole class.

## B-3. `0121:240` `club_incident_settle_quote` — confirmed, and still only latent

**Verified true, exactly as recorded. [M]** Full ACL map of `0121_runner_money_strip.sql`:

```
 29 create or replace function my_ledger_rows()              →  50 revoke  ·  51 grant
 59 create or replace function my_week_stats()               →  75 revoke  ·  76 grant
 81 create or replace function my_booking_nets(uuid[])       →  94 revoke  ·  95 grant
169 create or replace function my_run_net_coeffs(uuid[])     → 185 revoke  · 186 grant
193 create or replace function my_ledger_total()             → 205 revoke  · 206 grant
240 create or replace function club_incident_settle_quote(…) →  ✗ NO REVOKE, NO GRANT
333 create or replace function club_incident_settle(…)       → 434 revoke  · 435 grant
```

Line 243 confirms `language plpgsql stable security definer set search_path = public, pg_temp`
**[M]**. The six sibling revoke lines are **50, 75, 94, 185, 205, 434** — matching CLAUDE.md's
citation verbatim. (`0121:229` is a seventh revoke, but for `club_fare(numeric)`, a different
function, not one of this file's definer recreations.)

**Still latent, and nothing since 0121 has touched it. [M]** Exhaustive grep of every migration for
`club_incident_settle_quote`:

```
0072_incident_settlement.sql:52   create or replace   ← FIRST definition
0072_incident_settlement.sql:94   revoke   ·  :95 grant        ✓ correct
0080_charge_machine.sql:1017      (caller only)
0116_flip_blockers.sql:413        create or replace
0116_flip_blockers.sql:480        revoke   ·  :481 grant       ✓ correct
0121_runner_money_strip.sql:240   create or replace            ✗ no ACL
0121_runner_money_strip.sql:372   (caller)  ·  :485 comment
```

**Nothing at 0122–0129 recreates it or alters its grants.** It **is** carried in the gate baseline
at `check-definer-acl-baseline.txt:87` (`0121_runner_money_strip.sql:club_incident_settle_quote`)
**[M]**, so the gate knows about it and it is frozen debt, precisely as documented. It is also
recorded on the 0121 REGISTRY row, which I verified reads *"⚠ LATENT ACL HOLE… production VERIFIED
CLEAN, no action taken on the deployed migration"* **[M]**. **No fix attempted — it belongs to
another lane.**

**Latency CONFIRMED IN PRODUCTION by me, not relayed. [M]** Live ACL of the function itself:

```
club_incident_settle_quote:
  postgres=X/postgres  authenticated=X/postgres  service_role=X/postgres   secdef=true
```

There is **no bare `=X/postgres` entry**, which is the PUBLIC grant — so PUBLIC cannot execute it,
and `prosecdef` is still true. This is exactly the "latent, not breached" state CLAUDE.md records,
now measured in this session rather than taken from the 0121 row. The hole remains reachable only
on an apply path where `0072`/`0116` never ran; production is not such a path.

**A sharpening worth adding to the record [M]:** this is not "nobody ever set this function's ACL".
`0072` set it and `0116` — the *immediately preceding* recreation of the **same** function — also
set it, correctly, at `:480-481`. `0121` is the third recreation and the first to drop the pair.
That makes it a regression against an established local pattern, not an omission in a file that
never had one, which slightly raises the priority of the eventual fix relative to the other 80.

## B-4. Sweep for NEW instances — none, plus a broader class checked

**New instances of the gate's exact class: ZERO** — established two independent ways in §B-2b
(the gate's own run, and my separately-parsed scanner reaching exact set equality).

Because the gate's class is narrow by design, I also swept the **adjacent and strictly more severe**
class: *a SECURITY DEFINER that never receives an explicit revoke in **any** migration* — which, per
the scratch-cluster measurement above, is PUBLIC-executable on **every** apply path, not merely a
partial one.

**[M]** Precise sweep (definer qualifier required to appear *before* the body opener `as $$` /
`begin atomic`, which is the accurate test):

```
distinct function headers scanned : 427
distinct SECURITY DEFINER fns     : 224
definers never explicitly revoked : 74

>>> of those, FIRST DEFINED AFTER 0058: 0
```

**All 74 are first defined at or before `0058`** — and `0057`/`0058` carry a **dynamic bulk revoke**
that covers exactly them. `0057_security_hardening.sql:68-85` **[M]** loops
`pg_proc` where `pronamespace='public' and prosecdef and prokind='f'`, excluding extension-owned and
non-owned functions, and executes:

```sql
execute format('revoke execute on function %s from public, anon', r.sig);
if had_auth then execute format('grant execute on function %s to authenticated', r.sig); end if;
```

`0058_security_hardening_2.sql:305-306` repeats it. **This is dynamic SQL — precisely what the gate's
header says it cannot see** — and it is the mechanism that makes the pre-0058 grant-without-revoke
files safe in a full apply, and therefore the reason `98 H9` can be green.

**The headline positive finding: since `0058`, zero SECURITY DEFINER functions have been introduced
without an explicit revoke.** The discipline has held across 71 migrations. That corroborates H9's
green from source, independently of running the harness.

## B-4b. Production-side sweep — measured directly, and it is clean

The source sweep above says what *every apply path* should yield. This says what the live database
actually holds. **[M]**, run by me against the linked project:

```sql
select count(*)                                                           as total_public_definers,
       count(*) filter (where has_function_privilege('public', p.oid,'execute')) as public_executable,
       count(*) filter (where has_function_privilege('anon',   p.oid,'execute')) as anon_executable,
       count(*) filter (where p.proacl is null)                           as null_acl_default_public
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f';
```

```
total_public_definers | public_executable | anon_executable | null_acl_default_public
----------------------+-------------------+-----------------+------------------------
                  219 |                 0 |               0 |                       0
```

**219 SECURITY DEFINER functions in `public`; zero executable by PUBLIC; zero executable by `anon`;
zero carrying a NULL (default-PUBLIC) ACL.** This uses H9's own predicate against production, so
it is the strongest available statement about the deployed schema — and unlike H9 it did not
require running the harness.

**The one sentence this proves, and the one it does not.** It proves *the currently deployed
database has no PUBLIC- or anon-executable definer*. It does **not** prove the 81 baselined
recreations are safe, because their hole opens only on an apply path production is not — a partial
prior apply, a rebuilt environment, a cherry-picked slice. Source (the gate) and runtime (this
sweep) remain two different propositions, and this measurement is evidence for exactly one of them.

**⚠ A number in the repo's own docs is off by two.** `check-definer-acl.mjs`'s header states
production carries *"221 SECURITY DEFINER functions in `public`, 221 explicitly scoped"*;
`98_hardening_suite.sql:108` says *"All 219 `public` definers in the built schema"*. **My live
count is 219** — matching H9's figure, not the gate header's. The discrepancy is small and the
*property* (zero public-executable) is confirmed either way, so this is a bookkeeping note, not a
finding. It is recorded because the gate header's 221 is presented as a measurement.

## B-5. Three latent blind spots in the gate — measured empty today

Reading `check-definer-acl.mjs`'s regexes **[M]** and probing each against the corpus:

| Blind spot | Why the gate cannot see it | Measured in corpus today |
|---|---|---|
| **Schema-qualified header** — `create or replace function public.foo(` | `HEADER = /create\s+or\s+replace\s+function\s+([a-z0-9_]+)\s*\(/` has no `.` in the class, so a dotted name never matches | **0 occurrences** **[M]** |
| **Plain `create function`** (non-replace) | header regex requires `or\s+replace` | **0 occurrences** **[M]** |
| **400-char qualifier window** — `const window = code.slice(m.index, m.index + 400)` | a definer whose `security definer` sits past 400 chars is classified as *not a definer* and skipped entirely | **3 headers exceed 400** **[M]**: `0123 _distance_band` (894), `0062 _rf_is_client_role` (542), `0062 runner_apply_submit` (473) — **none is an active miss** (see below) |

**Disposition of the three window cases [M]:** `_rf_is_client_role` and `runner_apply_submit` are
both first defined in `0062` and both **do** carry explicit revokes there (`0062:312`, `0062:270`),
so neither is in the class regardless of the window.

**And a correction of my own earlier conclusion, left visible.** My first (looser) parser reported
`_distance_band` as a post-0058 SECURITY DEFINER with no revoke anywhere — which would have been a
live PUBLIC-executable definer and the most severe finding in this audit. **Reading the source
refuted it** — `0123_runner_base_distance.sql:576-577` **[M]**:

```sql
create or replace function _distance_band(p_m double precision) returns text
language sql immutable as $$
```

It is `language sql immutable`, **not** a definer at all; my next-header boundary had absorbed a
`security definer` belonging to later text. The corrected sweep (qualifier must precede the body
opener) returns **0** post-0058 unrevoked definers. Recorded here rather than silently dropped
because the failure mode — a scanner producing a confident hypothesis that source reading destroys
— is exactly the class this repo's laws are about, and because a reader of the corrected number
deserves to know it replaced a wrong one.

**🔵 DECISION — engineering's, not Sean's.** All three gaps are currently empty, so nothing is
broken. The choice is whether to (a) harden the three regexes now, (b) record the gaps in the
gate's own header (which already has a "WHAT THIS GATE CANNOT SEE" section that does **not** list
them), or (c) leave it. My read: **(b) at minimum** — the header's existing candour list is what a
future session will trust, and a gap absent from it reads as covered. Hardening the schema-qualified
case is two characters and cannot produce false positives; the 400-char window is the one with a
real cost/benefit argument, since widening it risks absorbing a *neighbouring* function's qualifier
— which is precisely the bug my own parser hit above.

## B-6. Documentation defect

`check-definer-acl.mjs` **[M]**: *"…the 81 are FROZEN in `check-definer-acl-baseline.txt` and this
gate's job is **the 84th**."* With 81 baselined, the gate's job is the **82nd**, which is what
CLAUDE.md says. Cosmetic, but it is in the file's load-bearing explanation of why the baseline is
not laziness, and a wrong count there invites a reader to think three occurrences are unaccounted
for.

---

# §C. What I could NOT establish

Listed as unverified rather than asserted.

1. ~~**Production state of the three columns / CHECK / enum.**~~ **RESOLVED — now [M].** The first
   `supabase db query --linked` attempt returned nothing (it was initialising a login role); a
   retry succeeded. All five objects are verified live in §A-1, and `club_incident_settle_quote`'s
   live ACL in §B-3. This item is left visible rather than deleted because the audit was committed
   while it was genuinely unverified, and the sequence matters more than a tidy list.

2. **Whether `98 H9` is currently green *in the harness*. [U] — still open, and deliberately so.**
   I did not run the harness: CLAUDE.md's fleet law (parallel runs braid on one postmaster and
   produce phantom reds) makes an unannounced run irresponsible while other sessions are active in
   this tree. H9's *content* I read and verified **[M]** (`98_hardening_suite.sql:115-127`,
   predicate `has_function_privilege('public'|'anon', oid, 'execute')`, allowlist array **empty**).
   ⚠ **My §B-4b production sweep is NOT a substitute for this, and must not be read as one** — H9
   asserts the property of *the schema the harness builds from scratch*; §B-4b measured *the
   deployed database*. Those are two different databases and two different sentences. The
   production one is clean; the harness one remains **[R]** from `98:108`'s comment, corroborated
   only indirectly by my §B-4 source sweep.

3. **App Store Connect / TestFlight actual install base. [U]** Sean-only by credential. See §A-3.

4. **Locally-built (`expo run:ios`) binaries on any device. [U]** Not visible to EAS by
   construction. See §A-3.

5. **Whether 0127 is deployed to production. [R], not [M].** The task brief asserted it; I did not
   re-measure it (same blocked path as item 1). `docs/session-handoff.md:34` records
   *"Production | **0127 head — 맹견 gate REMOVED and LIVE**"* with a `[verified-now]` tag, and
   `harness 886/0` on the merged tree. I confirmed **[M]** only that
   `0127_remove_dangerous_breed_gate.sql` is present on `origin/redesign-v4`.

6. ~~**Whether the 81 baselined occurrences are individually still latent-only in production.**~~
   **RESOLVED at the aggregate level — now [M].** §B-4b measures production directly: **219 public
   definers, 0 PUBLIC-executable, 0 anon-executable, 0 NULL-ACL.** So *no* baselined occurrence is
   breached in production; all 81 are latent, which is what the gate header claimed and what I can
   now assert from my own measurement rather than relaying.
   **Still [U]:** I did not check the 81 *individually* — the aggregate zero makes a per-function
   walk redundant for the safety question, but it means I cannot speak to any single one beyond
   `club_incident_settle_quote`, which I did check (§B-3).
   ⚠ My source-corpus count of **224** distinct definers **[M]** does not equal the live **219**
   **[M]**. Plausibly functions dropped later in the chain, or created outside migrations — **I did
   not reconcile it and I am not claiming the numbers agree.** Anyone using either figure as a
   denominator should reconcile it first.

---

# §D. Recommended next actions

**Slice B — ready to author, pending one confirmation from Sean.**

1. **Ask Sean the one-sentence question in §A-3.** This is the only thing standing between the
   contract's §0 measurement and "complete". Not work — a yes/no.
2. Author Slice B against the **measured** unwind list, all files in one edit (§A-2): the migration
   (CHECK → 3 columns → enum, in that order) · `10_settle_suite.sql:24` · `seed.sql:19` ·
   `113:102,429,458` · `139:32,33` · `146:176,177,178` · `149:180,181` · **and 161's P6**, whose
   pinned property legitimately inverts and which must be rewritten in the same slice with a
   comment saying why and which pin now owns the boundary.
3. Record the §A-3 EAS measurement verbatim in Slice B's header, as contract §0 requires.
4. Resolve the migration number two-sided against origin at authoring time — **do not** take a
   number from this report. 0128 is on origin and 0129 exists untracked in this tree **[M]**.

**Definer-ACL — nothing blocking.**

5. `0121:240` stays as recorded debt, riding the next money-path slice that touches it. No action
   in this audit.
6. **Decision (engineering):** the §B-5 blind spots — at minimum add them to the gate's own
   "WHAT THIS GATE CANNOT SEE" section, which currently does not mention them.
7. Fix the "84th" → "82nd" comment (§B-6).
