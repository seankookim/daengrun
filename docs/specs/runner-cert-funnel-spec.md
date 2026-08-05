# Runner Certification Funnel — design spec

**Status:** design-only. No migration code here. The next session builds this through the
5-agent adversarial cycle (scout → contract → implement → adversarial review → test pins → verify).

**Written:** 2026-08-05, alongside the honest repaint of `app/app/runner/apply.tsx`.
That repaint deleted a fabricated personal funnel (`store.ts:applyStatus`) and replaced it with
server truth + a static process explainer + an explicit `준비 중` for personal step tracking.
This spec is the thing that lets that `준비 중` be deleted honestly.

**Prior art check:** `docs/runner-recruitment.md` does **not** exist on this mirror (`docs/` contains
only `biz/` (empty), `gstack/`, `labs/`, `session-handoff.md`). Nothing was inherited; everything
below is derived from the migrations, the edge functions, and the client.

---

## Table of contents

1. [Ground truth — what exists today](#1-ground-truth--what-exists-today)
2. [Pre-existing holes this work must close](#2-pre-existing-holes-this-work-must-close)
3. [State machine](#3-state-machine)
4. [Schema design](#4-schema-design)
5. [Security](#5-security)
6. [Integration](#6-integration)
7. [Scope for the 5-agent cycle](#7-scope-for-the-5-agent-cycle)
8. [Open questions for Sean](#8-open-questions-for-sean)

---

## 1. Ground truth — what exists today

### 1.1 Schema already present (`0001_init.sql`)

`runners` (PK `profile_id` → `profiles`) already carries funnel-shaped columns:

| column | today's reality |
| --- | --- |
| `tier runner_tier` — enum `applicant \| certified \| veteran \| master` | **The only gate that matters.** Every marketplace predicate reads it. |
| `funnel_step funnel_step` — enum `info \| kyc \| education \| trial \| certified` | Written once by the client bootstrap, read by nothing. Dead. |
| `identity_verified`, `insurance_active`, `trainer_certified` booleans | Written once by the client bootstrap (`identity_verified: true`), read by nothing. |
| `education_modules_done int` (`/6`) | Never written, never read. |
| `total_runs`, `total_km` | **Real.** Incremented inside `settle_run_tx` (0020/0025/0028). |
| `commission_rate numeric` | **Real.** `settle-run/index.ts` reads it to compute payout. |

`runner_documents` (id, `runner_id`, `kind` ∈ `id_card | criminal_record | trainer_cert`,
`storage_path`, `verified_at`) exists and is unused by the client. Its comment claims
*"인증 후 원본 파기 정책"* — a policy nothing implements.

### 1.2 What certification gates today

Exactly one predicate, `runners.tier <> 'applicant'`, in these places:

- `0002_rls.sql:57` — `profiles public runner read` (an applicant's name/avatar stay private)
- `0002_rls.sql:69` — `runners public read` (storefront)
- `0003_availability.sql:85` — `count_available_runners` (+ `online`)
- `0004_open_requests.sql:4-21` — `is_active_runner()`, used by the open-pool RLS and later by
  `marketplace_open_requests` (0042:44, 0056:68)
- `0015_available_runners.sql:28`, `0054:104`, `0055:84` — `runners_available_for` candidate pool
  (+ `online = true`)
- `0030_hi_club.sql:164-165`, `0043:51`, `0048:179` — club-side "certified runner only" gates

**Consequence for this design:** certification has exactly one integration point with the
marketplace — *raising `runners.tier` from `applicant` to `certified`*. Nothing else needs to change,
and nothing else *should*. CLAUDE.md's availability law ("3 distinct predicates — do not unify")
applies in the mirror direction here: do not add a second, competing certification predicate.

### 1.3 What does not exist

- **No application record.** There is nowhere to store "this person is at KYC".
- **No admin/ops role.** `user_role` is `('owner','runner')` and nothing else. The nearest things to
  an ops concept: service-role edge functions (`_shared/ctx.ts:admin()`), the allowlist table
  `club_test_accounts` (0044:16 — RLS enabled, *no policies*, service role only), and feature flags
  `club_flags` (0040:159).
- **No tier promotion anywhere.** No migration ever writes `tier`. Today it is set once by the
  client bootstrap and never changes. Both client-side ladders (`runner/home.tsx` 30/100 runs,
  the now-retired mock's 250/1000 runs) are unbacked.
- **No private storage bucket.** Only `avatars` exists, and it is `public: true` (0006). KYC
  documents must never touch it.
- **No education content, no evaluator pool, no KYC provider.**

---

## 2. Pre-existing holes this work must close

These are live today and are the first thing an adversarial reviewer will find. They are listed
first because the funnel is meaningless while they stand — a funnel that ends in "tier = certified"
is theatre if any authenticated user can write that value themselves.

**H-1 — self tier escalation.** `0002_rls.sql:70`:
`create policy "runners self write" on runners for update using (profile_id = auth.uid())`.
No `with check`, no column restriction, and Supabase grants `UPDATE` on public tables to
`authenticated`. Any signed-in runner can set `tier = 'master'` and `commission_rate = 0` on their
own row from the client SDK. That is simultaneously a certification bypass and a payout attack
(`settle-run` trusts `commission_rate`). It also lets a runner set `total_runs` / `total_km`
directly, forging the numbers the repainted 인증 센터 now presents as server truth.

**H-2 — self-verified KYC documents.** `0002_rls.sql:73` grants `for all` on `runner_documents` to
the owning runner, including `UPDATE` of `verified_at`. An applicant can mark their own ID as
verified.

**H-3 — client-minted certification.** `api.ts:302 ensureRunner()` inserts
`tier: 'certified', funnel_step: 'certified', identity_verified: true` for anyone who enters runner
mode (`app/index.tsx:39`). It is honestly commented as a loop-test shim, but it is the production
path. The insert policy (`0002:71`) only checks `profile_id = auth.uid()`.

**Recommendation:** ship the hardening as its own migration (see §7.1) and treat it as independently
valuable — it can land before the funnel tables if the cycle needs to be split. Deploy-order
coupling with the client (`ensureRunner` must stop minting `certified`) follows the 0056 precedent:
state the coupling explicitly in the migration header.

---

## 3. State machine

### 3.1 States

One enum, `runner_app_state`, on one row per application attempt.

| state | meaning | who is waiting on whom |
| --- | --- | --- |
| `draft` | Row exists, basic info incomplete. | applicant |
| `info_submitted` | Basic info accepted by the server. | applicant (must upload docs) |
| `kyc_pending` | Required identity artifacts submitted. | **ops** |
| `kyc_passed` | Identity accepted. Education unlocked, not started. | applicant |
| `education_in_progress` | ≥1 module attempt recorded, not all required modules passed. | applicant |
| `education_passed` | Server recomputed: every required module in the pinned catalog version passed. | applicant/ops (trial scheduling) |
| `trial_scheduled` | A trial run with an assigned evaluator exists at a time. | evaluator |
| `trial_passed` | Evaluation submitted with a passing result. | **ops** (final approval) |
| `certified` | Terminal success. `runners.tier` raised to `certified`. | — |
| `kyc_rejected` | Terminal failure at KYC. Carries a reason code and a soft/hard flag. | — |
| `trial_failed` | Terminal failure at trial. | — |
| `withdrawn` | Applicant pulled out. | — |

**Why `kyc_passed` and `education_in_progress` are separate states** even though the applicant sees
one waiting room: the *actor* differs. `kyc_passed` is written by ops; `education_in_progress` is
written as a side effect of the applicant's first module submission. Collapsing them would force the
education RPC to distinguish "first attempt" by inspecting progress rows, and would make the screen
unable to say *"교육을 시작할 수 있어요"* vs *"교육 진행 중"* without a second query. Same reasoning as
the availability law: distinct predicates, distinct owners, don't unify.

**Why `trial_passed` is separate from `certified`:** the evaluator is a runner, not ops. If the
evaluator's write also raised `runners.tier`, then compromising or socially-engineering one veteran
runner would mint certified runners. The final tier raise stays a service-role action with a human
decision recorded.

### 3.2 Transitions

`actor` = who initiates. `enforcement` = where the rule lives. **No transition is a client-supplied
`state` value.** The client never writes `state`; it calls a function that computes the next state.

| # | from | to | trigger | actor | enforcement |
| --- | --- | --- | --- | --- | --- |
| T1 | — | `draft` | opens 인증 센터, taps 지원 시작 | applicant client | RLS insert: `profile_id = auth.uid()` **with check** `state = 'draft'` (mirrors `bookings owner insert`, 0002:95) + partial-unique "one active application" |
| T2 | `draft` | `info_submitted` | submits district / pace / max dog weight / specialties | applicant | definer RPC — validates required fields present and in range |
| T3 | `info_submitted` | `kyc_pending` | submits required identity artifacts | applicant | definer RPC — counts `runner_documents` rows of required kinds for this attempt; the RPC, not the client, decides completeness |
| T4 | `kyc_pending` | `kyc_passed` | ops verifies | **ops** | edge fn (service role) → definer RPC revoked from `authenticated` |
| T5 | `kyc_pending` | `kyc_rejected` | ops rejects, with reason code + soft/hard | **ops** | same as T4 |
| T6 | `kyc_passed` | `education_in_progress` | first module attempt recorded | applicant | definer RPC `complete_module` — advances state as a side effect |
| T7 | `education_in_progress` | `education_passed` | last required module passes | **server** | same RPC recomputes pass over the catalog version pinned on the application; never a client claim |
| T8 | `education_passed` | `trial_scheduled` | trial booked with an evaluator | applicant proposes, ops/evaluator confirms | definer RPC; evaluator eligibility checked server-side (tier ∈ {veteran, master} or ops) |
| T9 | `trial_scheduled` | `trial_passed` / `trial_failed` | evaluator submits evaluation | evaluator | definer RPC party-gated on `evaluator_profile_id = auth.uid()`; `hard_stop` forces `trial_failed` regardless of scores |
| T10 | `trial_passed` | `certified` | ops final approval | **ops** | edge fn — **the only writer that may raise `runners.tier`**; idempotent |
| T11 | any non-terminal | `withdrawn` | applicant withdraws | applicant | definer RPC |
| T12 | any non-terminal | `kyc_rejected` / `trial_failed` | ops hard-stops an application out of band (safety report, fraud) | **ops** | edge fn; reason recorded |
| T13 | `kyc_rejected` (soft) / `trial_failed` / `withdrawn` | new row in `draft` | re-application | applicant | definer RPC — enforces cooldown, attempt cap, and the hard-bar flag; **new row**, old row retained |

Nothing transitions backwards. The only way "back" is T13, which creates a new attempt with
`attempt_no = previous + 1`. Rejected attempts are never mutated — they are the audit trail.

### 3.3 Re-application policy

- **One active application per profile.** Partial unique index on `profile_id` where `state` is not
  terminal. This is the structural defence against parallel-attempt laundering.
- **Soft vs hard rejection.** `kyc_rejected` carries `is_hard_bar boolean`. Hard bar (fraud,
  disqualifying record — *if* such a criterion is even lawful, see §6.4) → no re-application, ever.
  Soft (blurry document, expired ID, missing artifact) → immediate re-application allowed.
- **Cooldown + cap.** `trial_failed` → cooldown then retry, with a cap. Exact numbers are Sean's
  call (§8, Q5); the design only requires that both are *server-enforced on T13*, not client copy.
- **Withdrawn** → immediate re-application, no cooldown, but counts against the attempt cap so
  withdraw/re-create cannot be used to reset a cooldown.

### 3.4 Invariants a reviewer should be able to state

- `runners.tier = 'certified'` ⟺ a `certified` application exists for that profile (after this work
  ships; pre-existing rows are grandfathered by the migration and that fact is recorded).
- At most one non-terminal application per profile.
- `education_passed` is never true unless the progress rows say so under the *pinned* catalog version.
- Every state change has exactly one event row.

---

## 4. Schema design

Described in prose and column tables. DDL is the implementer's job, under the migration laws
(§5.5).

### 4.1 `runner_applications`

| column | notes |
| --- | --- |
| `id` uuid PK | |
| `profile_id` uuid → `profiles` on delete cascade | not the `runners` row: an applicant may have no `runners` row yet (and after H-3 is closed, shouldn't) |
| `state` runner_app_state, default `draft` | never client-written |
| `attempt_no` int, default 1 | |
| `education_catalog_version` int | pinned at T6 (first module attempt), not at T1 — see §4.2 |
| basic-info payload: `district`, `avg_pace_sec_per_km`, `max_dog_weight_kg`, `specialties` | mirrors the corresponding `runners` columns; **copied into `runners` at T10, not before**, so an in-flight application never leaks into the storefront |
| `last_decision_reason` text | applicant-visible copy for the current rejection; the full history lives in the event table, which the applicant cannot read |
| `is_hard_bar` boolean, default false | |
| `created_at`, `updated_at` | `updated_at` via the existing `touch_updated_at()` trigger idiom (0002:5) |

Deliberately **not** included: per-state timestamp columns (`kyc_passed_at`, `education_passed_at`,
…). Every one of them is a second copy of a fact the event table already owns, and every nullable
timestamp is a place for the UI to render a date that doesn't correspond to the state. Timeline
rendering reads the event projection.

Constraints: partial unique index on `profile_id` for non-terminal states; check that
`is_hard_bar` implies a terminal rejected state.

### 4.2 Education progress — table, not jsonb

Two tables:

- **`runner_education_modules`** (catalog): `module_key`, `catalog_version`, `title`, `required`
  boolean, `pass_score`, `sort_order`. PK `(module_key, catalog_version)`.
- **`runner_education_progress`** (attempts): `application_id`, `module_key`, `attempt_no`, `score`,
  `passed`, `answers jsonb`, `created_at`. PK `(application_id, module_key, attempt_no)`.

**The argument.** A single `education jsonb` column on the application is the obvious shortcut and
it is wrong here for five reasons:

1. **Lost updates.** Two module submissions racing on one jsonb column silently clobber each other.
   Composite-PK rows can't (and the `booking_declines` precedent, 0056, shows the house style:
   *the composite PK is the idempotency*).
2. **The pass decision must be a set difference, not a count.** "All required modules of version V
   are passed" is a join against the catalog. Against jsonb it becomes a count of a blob the client
   could have shaped — precisely the class of fabrication the apply.tsx repaint just removed
   (`education_modules_done int` sitting unwritten in `runners` is the same shortcut, one level down).
3. **Content changes without migrations.** New modules are catalog rows, and `catalog_version`
   pinned on the application means adding a module doesn't retroactively un-pass anyone. With jsonb
   there is no version to pin against.
4. **Replay is auditable.** Retries are rows with `attempt_no`, so "submitted module 3 forty times
   until it passed" is visible and cappable. In jsonb it is one overwritten field.
5. **RLS granularity.** Per-row policies let the applicant read their own attempts while the
   catalog's `pass_score` stays server-side. A jsonb blob is all-or-nothing.

`answers jsonb` inside a progress row is fine: opaque payload, carries no gate.

### 4.3 `runner_trial_evaluations`

| column | notes |
| --- | --- |
| `id` uuid PK, `application_id` → `runner_applications` | |
| `evaluator_profile_id` → `profiles` | eligibility (tier ∈ {veteran, master} or ops allowlist) checked in the RPC, not by FK |
| `scheduled_at`, `booking_id` (nullable → `bookings`) | nullable because whether the trial rides on a real paid booking is unresolved (§8, Q3) |
| rubric as **columns**, not jsonb: `leash_control`, `dog_handling`, `safety_protocol`, `punctuality`, `communication` (each 1–5) | columns because the pass rule is a server predicate over them; a jsonb rubric makes the predicate unpinnable in the harness |
| `hard_stop` boolean + `hard_stop_reason` | any safety violation forces `fail` regardless of scores; check constraint ties `hard_stop = true` to `result = 'fail'` |
| `result` ∈ `pass \| fail \| no_show`, `notes`, `decided_at` | |

One evaluation row per scheduled trial; a re-trial is a new application attempt (T13), not a second
row on the same one.

### 4.4 KYC artifacts

Reuse `runner_documents` — the table already exists with the right `kind` vocabulary — but it needs:

- an `application_id` FK (documents belong to an *attempt*, not to a person forever),
- policy surgery (H-2): applicant may `insert` and `select` own rows; `verified_at` is ops-only,
- a **new private storage bucket** (`runner-docs`, `public: false`). Path convention `{uid}/{application_id}/{kind}`,
  owner-folder insert following the 0006 pattern, **no public read policy**, ops reads via a signed
  URL minted by an edge function. Never `avatars` — that bucket is world-readable.

### 4.5 Tier derivation — `tier` stays on `runners`

`runners.tier` remains the single certification gate. It is *not* derived at read time from the
application table, because:

- ~12 predicates across 10 migrations read `runners.tier` directly, including
  `marketplace_open_requests`, whose 17-column shape is pinned by test 98 H6 and can only change via
  `create or replace` (grant preservation).
- A derived gate would put a join to an application table inside the open-pool view and inside
  `is_active_runner()`, which is called in RLS policies — a correctness and cost regression for
  every request-list read.

So: the application funnel **writes** `tier` exactly once (T10), server-side, and everything else
keeps reading the same column it reads today. The funnel table is the *history*; `runners.tier` is
the *capability*. Harness pin C7 (§7.2) exists specifically to stop a future implementer from
"simplifying" this into a derived gate.

`runners.funnel_step` / `identity_verified` / `education_modules_done` become **deprecated**: stop
writing them, comment them as superseded, leave the columns (dropping enum-typed columns mid-pilot
buys nothing). Two funnel truths would drift, and the drifted one is the one the UI would render.

### 4.6 Audit — `runner_application_events`

`application_id`, `from_state`, `to_state`, `actor_profile_id`, `actor_kind`
(`applicant | ops | evaluator | system`), `reason`, `payload jsonb`, `created_at`.

Follows the `assignment_events` / `dog_custody_events` idiom (0040:51): **RLS enabled, no policies
at all** — the table is unreadable to every client role, and access is exclusively through a definer
projection that returns a flat whitelist (state, timestamp, applicant-safe reason). Ops actor
identity and internal notes never cross that boundary.

Why an event table is non-optional here: this funnel makes a *safety* claim about people who will be
alone with someone's dog. "Who certified this runner, when, on what evidence" must survive the
runner's own subsequent edits, and it must survive a rejected applicant's re-application.

---

## 5. Security

### 5.1 How this codebase models "admin" (and how to match it)

There is no admin role, and this spec does **not** introduce one into `user_role` — that enum is
read by the client's role-switch (`store.ts:session.role`, `my.tsx`), and widening it changes
semantics far outside this feature.

Match the existing three-part pattern instead:

1. **Allowlist table** `ops_operators` (`profile_id` PK, `note`, `added_at`) — RLS enabled, **no
   policies**, so only the service role can read or write it. Exact shape of `club_test_accounts`
   (0044:16).
2. **Edge function** `runner-cert-ops` using `_shared/ctx.ts`: `admin()` for the service client,
   `caller(req, db)` to authenticate the JWT, then a membership check against `ops_operators`, then
   the transition. This is where "is this person ops" is answered — once, in one place.
3. **Definer RPCs for the ops transitions are revoked from `anon` and `authenticated`** and granted
   to no client role, so the edge function is the only caller. Precedent: `_club_require_v2()`
   (0044:23, revoked from all three) and `settle_run_tx` (0020:110, service-role only).

A `_cert_require_ops()` internal helper mirroring `_club_require_v2()` is the natural in-database
expression if any ops transition ends up callable in-database.

### 5.2 RLS policy set

| table | select | insert | update | delete |
| --- | --- | --- | --- | --- |
| `runner_applications` | self (`profile_id = auth.uid()`) | self, **with check `state = 'draft'`** | **none for clients** — every mutation is a definer RPC | none |
| `runner_education_modules` | authenticated read of the catalog (title/order/required only — `pass_score` must not be client-readable, so expose via a projection view rather than the base table) | none | none | none |
| `runner_education_progress` | self via the owning application | **none** — submissions go through the scoring RPC | none | none |
| `runner_trial_evaluations` | self (applicant, whitelisted columns via projection) + evaluator own rows | none | none | none |
| `runner_application_events` | **none at all** — definer projection only | none | none | none |
| `runner_documents` | self | self, tied to own non-terminal application | **ops only** (this replaces the current `for all`, H-2) | self, only while `state ∈ {draft, info_submitted}` |
| `ops_operators` | none | none | none | none |

Deliberate asymmetry worth naming in the migration comment: the applicant can *create* an
application row directly (cheap, self-scoped, mirrors `bookings owner insert`) but can never
*update* one. Every field they think they're editing is written by an RPC that also decides the
state. This removes the entire "client writes a state string" attack class by construction rather
than by validation.

### 5.3 Transitions that must be server-side

| transition | why it cannot be client-writable |
| --- | --- |
| T4/T5 (KYC decision) | It is the identity claim itself. |
| T7 (`education_passed`) | The client must never assert a pass. Scoring happens server-side against catalog `pass_score`; the client posts answers, not results. |
| T9 (trial result) | Party gate on the evaluator, plus `hard_stop` semantics. |
| **T10 (`certified` + tier raise)** | This is the money and safety boundary. Also the *only* place `runners.tier` may be raised — enforced by the H-1 hardening, which removes tier from the client-writable column set entirely. |
| T13 (re-application) | Cooldown, attempt cap, and hard-bar are server facts. |

T2/T3/T6/T11 are applicant-initiated but still go through definer RPCs, because each one computes a
state as a side effect. The rule is uniform: **clients call verbs, never write states.**

### 5.4 Attack surfaces a reviewer must actually execute

Not "consider" — execute, per CLAUDE.md's adversarial-cycle law.

**State skipping**
- Direct `update runner_applications set state = 'certified'` as `authenticated`. Must fail (no
  update policy).
- Call each transition RPC from every other state. Each must raise, and the error must not reveal
  the current state of someone else's application.
- Call an ops RPC directly as `authenticated` (must be revoked), and as `anon`.
- Insert an application row with `state = 'kyc_passed'` (must fail the `with check`).

**Tier / payout escalation (H-1 regression guard)**
- `update runners set tier = 'master'` as self. Must fail after hardening.
- `update runners set commission_rate = 0` as self. Must fail.
- `update runners set total_runs = 9999` as self. Must fail (it is the number the 인증 센터 renders
  as server truth).
- `insert into runners (profile_id, tier) values (auth.uid(), 'certified')`. Must fail the check.

**KYC forgery**
- `update runner_documents set verified_at = now()` as the owning runner. Must fail (H-2).
- Insert a document row whose `storage_path` points into another user's folder — the RPC must
  validate the path prefix, not just the row's `runner_id`.
- Submit T3 with zero documents / with a document belonging to a previous rejected attempt.
- Read the private bucket without a signed URL; read another applicant's object.

**Education replay**
- Submit the same module repeatedly until a pass — verify the attempt cap and that the pass rule
  uses best-of / latest per the chosen policy consistently.
- Submit a `module_key` that is not in the pinned catalog version, or not `required`.
- Submit a module for another applicant's `application_id`.
- Ops adds a new required module mid-flight: an already-`education_passed` application must not
  silently regress (catalog version pinning), and an in-flight one must behave per an explicitly
  pinned decision.
- Post `passed: true` / a `score` above the max directly in the RPC payload.

**Evaluator forgery**
- A `certified` (non-veteran) runner submits an evaluation.
- An evaluator evaluates their own application.
- An evaluator evaluates an application they were not assigned to.
- Submit `result = 'pass'` together with `hard_stop = true`.

**Oracle probing** (the 0055 lesson)
- Call every RPC with a foreign `application_id` and confirm the *party gate fires before the state
  gate*, so "not yours" and "wrong state" are indistinguishable to an attacker enumerating IDs.
- Confirm no projection leaks applicant profiles before certification — `profiles public runner read`
  (0002:57) currently hides applicants, and the new projections must not undo that.

**Idempotency & races**
- Double-fire T10 (two ops clicks): one tier raise, one event row.
- Concurrent T6 on two modules (the 2-connection race harness, `90_race_check.sh`, is the precedent).
- T13 racing itself to create two active applications (partial unique index must catch it).

**Definer hygiene**
- `pg_temp` shadowing of any table referenced inside a new definer function (0055 §3 / adversarial
  review P2). Test 98 H1 already sweeps the whole schema for missing in-body `search_path` and will
  fail the harness on any new omission — but the reviewer should still attempt an actual shadowing
  exploit against at least one new function to prove the sweep is meaningful.

### 5.5 Migration laws that apply (from CLAUDE.md)

- Every new security-definer function sets `search_path = public, pg_temp` **in the function body**
  (ALTER-applied config is reset by `create or replace`). Test 98 H1 enforces this globally.
- Views change via `create or replace` only — never DROP (grant preservation).
- Party gate before state gate in every RPC; flat whitelisted returns, never `select *` of an
  application row.
- Existing migration files are never edited; everything lands in new numbered files.

---

## 6. Integration

### 6.1 What `apply.tsx` binds to, per state

The repainted screen (2026-08-05) has three sections. Section ① is already live server truth and
does not change. Sections ② and ③ are where the funnel lands: today ② is a static explainer and ③
says `준비 중`. The mapping below is what deletes that `준비 중` honestly.

| application state | § ② 인증 절차 renders | § ③ renders | CTA route |
| --- | --- | --- | --- |
| *(no application row)* | static explainer, unchanged | "지원을 시작할 수 있어요" | `지원 시작` → T1 + basic-info form |
| `draft` | steps 01–05, 01 marked *in progress* from **server** state | resume prompt | basic-info form (T2) |
| `info_submitted` | 01 done, 02 next | "신원 서류를 올려주세요" | document upload (T3) |
| `kyc_pending` | 02 in review | "심사 중이에요" + submitted timestamp from the event projection | none (no dead button — an ops-side wait has no user action) |
| `kyc_rejected` (soft) | 02 rejected | `last_decision_reason` verbatim | `다시 지원하기` → T13 |
| `kyc_rejected` (hard) | 02 rejected | terminal copy, no re-apply | 문의 → `/settings` |
| `kyc_passed` | 03 unlocked | "안전 교육을 시작할 수 있어요" | 교육 시작 → module screen |
| `education_in_progress` | 03 in progress, **real** `n/m` from progress rows joined to the pinned catalog | "이어하기" | module screen (T6) |
| `education_passed` | 03 done, 04 next | trial scheduling status | 시범 러닝 신청 (T8) — or, if evaluator supply is manual, 문의 → `/settings` |
| `trial_scheduled` | 04 scheduled | date + evaluator display name | booking/session detail if the trial rides a real booking |
| `trial_passed` | 04 done, 05 pending | "최종 승인 대기 중" | none |
| `trial_failed` | 04 failed | reason + cooldown expiry (server-computed) | `다시 지원하기` when eligible |
| `certified` | all 5 done | § ① already shows the tier — ③ collapses to a one-line completion note | none |
| `withdrawn` | static explainer | "지원을 취소했어요" | `다시 지원하기` |

Honesty rules carried forward into the bound version (these are the rules the repaint established
and the next implementer must not regress):

- **Loading is not 0** — `loaded` flag stays separate from `null` data; "no application" and "not
  loaded yet" render differently.
- **Failures render as failures** — the error box, not a silent fallback to the empty state.
- **No dead buttons** — states whose next actor is ops render *no CTA*, not a disabled one.
- **`n/m` progress only from progress rows.** Never from `runners.education_modules_done`.
- The static explainer copy survives as the no-application rendering; it is the honest default, not
  a placeholder to delete.

### 6.2 Matching / availability

Unchanged by design. The only write is T10's tier raise, after which the runner automatically
appears in:

- `runners_available_for` (0055) — subject to `online = true` and the slot-conflict predicate,
- `marketplace_open_requests` (0042/0056) via `is_active_runner()`,
- `count_available_runners` (0003),
- the storefront reads (`profiles public runner read`, `runners public read`).

Two consequences worth stating so nobody "fixes" them later:

1. A newly certified runner has `total_runs = 0` and would be invisible under a pure top-10 sort.
   That cold-start deadlock was already solved by the 8+2 rookie slots (0055 §1–2). **The funnel does
   not need its own visibility boost**, and adding one would double-count.
2. `online` defaults to `false` (0001:76). Certification makes a runner *eligible*, not *visible*.
   The certified-state UI should say so, or the runner will believe the funnel is broken.

### 6.3 Ops reality for the pilot

One operator (Sean). Two options:

- **(a) Supabase Studio + service-role RPC.** Zero UI to build. Ops calls the transition function
  from the SQL editor or through the edge function with a service key. Recommended for the pilot —
  it matches the "Sean-only operations" law in CLAUDE.md (db push / functions deploy / git push are
  already his).
- **(b) A gated in-app ops route.** Precedent exists (`settings.tsx:65` renders a `__DEV__`-gated dev
  route, double-gated at the screen). More work, and it puts an ops surface inside the consumer app
  during a pilot with a handful of runners.

Either way the ops action must go through the same edge function, so that the event row and the
idempotency guard are unavoidable. Reviewing KYC *is manual for the pilot* — that is a stated design
decision, not a gap, and the honest screen copy should reflect it.

### 6.4 Legal handling of 범죄경력회보서 — open question, not a design

`runner_documents.kind` already contemplates `criminal_record`, and the retired mock screen printed
*"신원 서류는 암호화 보관되며 인증 완료 후 원본은 파기돼요"* — a claim nothing implements.

This spec deliberately does **not** design collection, retention, viewer restriction, or destruction
for criminal-record certificates, and does not offer a legal opinion. What it does is flag the
concrete unknowns Sean must resolve with counsel before any migration touches this artifact:

- whether a private platform may lawfully require this document from runners at all, and under what
  consent basis;
- who may lawfully view it, and whether daengrun should instead receive only a pass/fail from a
  third party that holds the document;
- retention and destruction obligations, and whether the existing "destroy the original after
  certification" claim is a requirement or an invention;
- whether any of this changes the answer for the pilot's small N.

Until that is answered, the implementable subset is: identity documents only, private bucket,
ops-only `verified_at`, and **no product copy asserting a retention policy that does not exist**.

---

## 7. Scope for the 5-agent cycle

### 7.1 Estimated migration list

| file | contents | note |
| --- | --- | --- |
| `0057_runner_cert_hardening.sql` | Close H-1/H-2/H-3: restrict `runners self write` (tier, commission_rate, total_runs, total_km not client-writable), force `tier = 'applicant'` on client insert, split `runner_documents` policies so `verified_at` is ops-only, grandfather existing certified rows. | **Independently valuable — should land first.** Client deploy-order coupling: `ensureRunner()` must stop minting `certified` (0056 precedent for stating this in the header). |
| `0058_runner_cert_funnel.sql` | `runner_app_state` enum; tables `runner_applications`, `runner_education_modules`, `runner_education_progress`, `runner_trial_evaluations`, `runner_application_events`, `ops_operators`; indexes incl. the partial-unique active-application index; RLS enable + the §5.2 policy set; private `runner-docs` bucket + storage policies. | |
| `0059_runner_cert_transitions.sql` | Definer RPCs for T2/T3/T6/T8/T9/T11/T13 + ops-only T4/T5/T10/T12 (+ `_cert_require_ops()`); the applicant-facing event/timeline projection; module-catalog projection that hides `pass_score`. All with in-body `search_path`, party-gate-before-state-gate, flat returns. | Split from 0058 so the adversarial reviewer can attack the tables' policies and the functions' gates as separate surfaces. |

A fourth file appears only if the trial run rides on the real `bookings` loop (§8, Q3) — that would
touch the booking transition trigger and needs its own contract.

Deprecation of `runners.funnel_step` / `identity_verified` / `education_modules_done` is a comment +
"stop writing" change, folded into 0057.

### 7.2 Harness pin families

New suite `99_cert_funnel_suite.sql`, wired at the end of `harness.sh` after 98, following the
95/96/97/98 style (definer/view paths via the `request.jwt.claim.sub` GUC; real RLS paths via
`set local role authenticated` with an unconditional `reset role`; seed bookings closed as `expired`
so the open pool isn't polluted).

| family | pins |
| --- | --- |
| **C1 state machine** | full legal walk `draft → certified`; every illegal transition raises; no backwards edges |
| **C2 write sealing** | `authenticated` cannot update `runner_applications.state`, `runners.tier`, `runners.commission_rate`, `runners.total_runs`, `runner_documents.verified_at`; cannot insert an application in a non-draft state; cannot insert a `certified` runners row — **mutation-verified** (flip each policy and confirm the pin fails) |
| **C3 education** | replay idempotency; attempt cap; pass recomputed against the pinned catalog version; unknown/non-required module rejected; client-supplied `passed` ignored |
| **C4 trial** | non-evaluator rejected; self-evaluation rejected; unassigned evaluator rejected; `hard_stop` forces fail |
| **C5 re-application** | one active application (partial unique index); cooldown; attempt cap; hard bar blocks forever; withdraw→recreate does not reset cooldown |
| **C6 oracle** | party gate fires before state gate — identical error text for "foreign application" and "foreign application in the right state"; no applicant profile leakage |
| **C7 gating mirror** | a `certified` runner appears in `runners_available_for` / `marketplace_open_requests` / `count_available_runners`; an applicant does not — **this pin exists to stop a future refactor from moving the gate off `runners.tier`** |
| **C8 idempotency & race** | double T10 = one tier raise + one event; concurrent module submissions (2-connection, `90_race_check.sh` precedent); concurrent T13 |

Existing pins that must stay green and should be re-read before touching anything: **98 H1**
(whole-schema definer `pg_temp` sweep — it will fail automatically on a careless new function),
**98 H6** (17-column name+order shape of `marketplace_open_requests`), **97 V10** (flat 9-column
return shape of `runners_available_for`).

### 7.3 Edge function changes

| function | change |
| --- | --- |
| `runner-cert-ops` (new) | ops-only transitions T4/T5/T10/T12. `_shared/ctx.ts` `admin()` + `caller()` + `handle()`; `ops_operators` membership check; calls the revoked definer RPCs; idempotent. |
| `runner-cert-docs` (new, or folded into the above) | mints signed upload URLs for the private `runner-docs` bucket and signed read URLs for ops. |
| `transition-booking` | unchanged unless the trial rides a real booking. |
| `settle-run` | unchanged, but note it reads `commission_rate` — H-1's fix is what makes that read trustworthy. |

### 7.4 Client work (separate slice, after the server lands)

- `api.ts`: `ensureRunner()` stops minting `certified` / `identity_verified`; new fetchers for the
  application projection, module catalog, and progress; RPC calls for T2/T3/T6/T8/T11/T13. Note
  `scripts/check-rpc-contracts.mjs` is a commit gate — every new `supabase.rpc(...)` must match a
  migration signature.
- `apply.tsx`: bind §6.1's table. The existing static explainer stays as the no-application state.
- A module screen and a document-upload screen (both new).
- `my.tsx` menu subtitle already reads `내 러너 레코드 · 인증 절차 안내`; revisit when the funnel is live.

---

## 8. Open questions for Sean

**Q1 — KYC provider.** PASS / NICE / Toss identity verification, or manual document review for the
pilot? This decides whether T4 is an API callback or a human in Studio, and whether `phone` on
`profiles` becomes a verified field. Cost and contract lead time matter more than the code here.

**Q2 — Education content source.** Who writes the modules, and how many? Text + quiz, or video?
Pass score? Is there existing 안전 교육 material (the app has a `/safety` screen) to build on, or is
this net-new authoring? Does certification expire and require re-certification?

**Q3 — Trial-run evaluator supply.** There are zero veteran runners today, so the first cohort has
no evaluator. Options: Sean evaluates the first N personally; the trial runs as a real paid booking
(needs the dog owner's informed consent, insurance posture, and a decision on who pays); or a staged
run with a staff dog. This is the single biggest blocker to a working funnel and it is an operations
question, not a schema question.

**Q4 — 범죄경력회보서 legal handling.** See §6.4. Requires counsel, not engineering. Until answered,
the funnel ships with identity documents only and no retention claims in the UI.

**Q5 — Re-application numbers.** Cooldown after `trial_failed`; attempt cap; what constitutes a hard
bar (permanent). The design enforces whatever numbers you pick, server-side; it just needs the
numbers.

**Q6 — The tier ladder.** Three unbacked ladders currently coexist: the enum
(`applicant/certified/veteran/master`), `runner/home.tsx`'s "30 runs → veteran, 100 → master,
잠정", and the retired mock's "250 / 1,000 runs + ★4.8". None is enforced anywhere. Either pick real
criteria and put promotion server-side (a scheduled job or a `settle_run_tx` side effect), or accept
that the honest screen keeps saying 준비 중 about promotion. Note that `commission_rate` is a free
column today — tier and commission are not actually linked in code, only in a comment.

**Q7 — Ops surface for the pilot.** Studio + service-role RPC (recommended), or a gated in-app ops
route?

**Q8 — Applicant visibility.** Today `profiles public runner read` hides an applicant's name and
avatar entirely until `tier <> 'applicant'`. Should an in-flight applicant be visible anywhere
(e.g. a "지원 중" state in a community surface), or does the current full-invisibility remain the
policy? Full invisibility is the safer default and this spec assumes it.
