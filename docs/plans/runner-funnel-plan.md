# Runner application + certification funnel — scout fact sheet and build contract

**Scope:** minimum viable applicant → certified path for the 22-runner Banpo pilot, where Sean
personally vets every runner. Manual ops certification is the design, not a gap.
**Written:** 2026-08-08. **Branch:** `redesign-v4`, HEAD `4a2277a`. **Harness baseline:** 246/0
(re-run and confirmed during this scout).
**Blocks:** `docs/launch-checklist.md` §0-1 and §3 — the #1 of two things blocking a first paying
customer.

**Relationship to `docs/specs/runner-cert-funnel-spec.md`:** that spec (2026-08-05, 621 lines) is
the full-product design — 12 states, education catalog with versioned modules, an evaluator pool,
a private KYC bucket, an `ops_operators` allowlist, and three migrations. This plan is the **pilot
subset** of it. Where they differ, this plan wins for the pilot and the spec stays as the upgrade
path. The spec is also **stale in two places**, corrected in §1.6 below.

---

## 0. Decisions (the short version)

| # | Decision | Why |
| --- | --- | --- |
| D1 | **New `runner_applications` table**, not `runners.funnel_step` transitions | §3.1 argues it in full. Short form: an application is a *decision with a reason and an attempt history*; `funnel_step` has nowhere to put a reason, a decision time, or attempt 2. |
| D2 | 5 states: `submitted → under_review → approved \| rejected`, plus `withdrawn` | Matches what one operator on a video call actually does. No `draft` (the form is client-local until submit), no education/trial states. |
| D3 | `runners.tier` stays the **only** certification gate; the funnel writes it exactly once, at approval | ~12 predicates in 10 migrations read `runners.tier` directly (§1.2). A derived gate would put a join inside RLS policies. |
| D4 | Ops surface = **service-role node script** `scripts/runner-ops.mjs` + a documented SQL-editor runbook fallback | It is exactly how Sean does one-off ops today (`scripts/seed-runners.mjs`, `wipe-test-data.mjs`). No edge function, no `ops_operators`, no in-app admin screen for one operator. |
| D5 | **No identity-document upload in scope** | The only storage bucket is `avatars`, `public: true` (`0006_avatars.sql:5`). A KYC document there is world-readable by URL. And no 개인정보처리방침 exists yet (`launch-checklist.md` §1). Sean sees the ID on the video call. |
| D6 | **P0 hardening ships first, in its own migration:** the `runners` INSERT self-promotion hole | Verified live during this scout (§1.4). Any signed-in user with no `runners` row can insert `tier='master', commission_rate=0, identity_verified=true` and become instantly bookable. The funnel is theatre until this closes. |
| D7 | Two migrations: `0061_runner_apply_seal.sql`, `0062_runner_applications.sql` | 0061 is independently valuable and can land alone if the funnel slips. Separate attack surfaces for the adversarial reviewer. |
| D8 | New harness suite `101_runner_funnel_suite.sql` | 100 is taken by `100_wave3_suite.sql`. |
| D9 | `safety.tsx:150` copy is rewritten to describe the manual video-call vetting truthfully | Exact Korean in §7. |

---

# PART I — FACT SHEET

Every claim below is `file:line` cited. **[FACT]** = read in the code or executed against the
harness DB. **[INFERENCE]** = my reading of consequences.

## 1.1 `runners` schema — every column and its writer

Defined once, in `supabase/migrations/0001_init.sql:57-79`. Two later `alter table`s:
`0007_runner_photos.sql:2` adds `photos text[] not null default '{}'`;
`0059_take_rate_33.sql:14` changes `commission_rate` default to `0.33` (existing rows keep 0.20).

| column | default | who writes it today | **[FACT]** |
| --- | --- | --- | --- |
| `profile_id` uuid PK → `profiles` | — | client insert (`api.ts:354-370 ensureRunner`) | |
| `tier runner_tier` | `'applicant'` | **nobody, ever, after insert.** No migration and no edge function raises it. | `0001:59` |
| `funnel_step funnel_step` | `'info'` | client insert only (`api.ts:365`), read by **nothing** | dead column |
| `bio`, `specialties`, `avg_pace_sec_per_km`, `service_radius_km`, `max_dog_weight_kg`, `online`, `photos` | — | client (storefront surface, explicitly allowed by `0057:476`) | |
| `identity_verified` | `false` | client insert hardcodes `false` (`api.ts:367`); nothing ever sets `true` | |
| `insurance_active`, `trainer_certified`, `education_modules_done` | `false/false/0` | **never written by anything** | |
| `total_runs`, `total_km`, `completion_rate` | `0/0/null` | `settle_run_tx` (definer, service-role) | real |
| `compliance_pct`, `respond_rate_pct` | null | never written | |
| `commission_rate` | `0.33` (0059) | never written after insert; **read by `settle-run` to compute payout** | real money |
| `created_at`, `updated_at` | now() | `touch_updated_at()` trigger, `0002_rls.sql:5,11` | |

Enums (`0001:16-17`):
`runner_tier = ('applicant','certified','veteran','master')`,
`funnel_step = ('info','kyc','education','trial','certified')`.

**Convention note [FACT]:** no `create type` has been added since `0001_init.sql`. Every status
column since `0030_hi_club.sql` is `text ... check (x in (...))` — e.g. `0030:13,62,87`. The new
funnel state column follows that house style, not a new enum.

`runner_documents` (`0001:81-88`): `id`, `runner_id → runners`, `kind` (`id_card | criminal_record
| trainer_cert`), `storage_path`, `verified_at`. **Unused by any client code** (no reference in
`app/`). Its comment claims a 원본 파기 policy that nothing implements.

## 1.2 RLS on `runners`, and every consumer of `tier` / `funnel_step`

### RLS policies (`0002_rls.sql`, amended by `0057_security_hardening.sql`)

| policy | definition | file:line |
| --- | --- | --- |
| `runners public read` | `select using (tier <> 'applicant' or profile_id = auth.uid())` | `0002:69` |
| `runners self write` | `update using (profile_id = auth.uid()) with check (profile_id = auth.uid())` | replaced at `0057:482-485` |
| `runners self insert` | `insert with check (profile_id = auth.uid())` — **nothing else** | `0002:71`, never amended |
| *(no delete policy)* | delete silently affects 0 rows | verified in §1.4 |
| `profiles public runner read` | `select using (exists (… r.tier <> 'applicant'))` — an applicant's name/avatar stay private | `0002:56-58` |
| `runner docs self` | `for all using (exists (… r.profile_id = auth.uid() and = runner_documents.runner_id))` | `0002:73-75` |

Column governance is a trigger, not the policy: `_guard_runner_cols()` (`0057:487-513`) raises
`runner_protected_columns` when `current_user in ('authenticated','anon')` and any of
`tier, funnel_step, identity_verified, insurance_active, trainer_certified, education_modules_done,
total_runs, total_km, completion_rate, compliance_pct, respond_rate_pct, commission_rate` changes.
It is attached **`before update` only** (`0057:512`). `_guard_runner_doc_verify()` (`0057:521-540`)
seals `runner_documents.verified_at` on **insert or update** — the correct shape, and the proof
that "insert too" was a conscious choice there and an omission on `runners`.

**Can a runner update their own tier? [FACT] No** — `_guard_runner_cols` blocks it, and harness pin
`99_security_suite.sql:169-205` (S4) is mutation-verified against `drop trigger _guard_runner_cols`.
**Can a user *insert* their own tier? [FACT] Yes. See §1.4.**

### Every consumer of `tier`

Server (`tier <> 'applicant'` unless noted):

| consumer | file:line | what breaks for an `applicant` |
| --- | --- | --- |
| `profiles public runner read` | `0002:56-58` | name/avatar invisible to everyone |
| `runners public read` | `0002:69` | storefront row invisible (own row still readable) |
| `count_available_runners()` | `0003_availability.sql:79-88` (+ `online`) | never counted in "러너 N명 가능" |
| `is_active_runner()` | `0004_open_requests.sql:4-10` | → `runners see open requests` (`0004:12`) and `dogs visible on open requests` (`0004:16`) return **zero rows** |
| `available_runners` view | `0015_available_runners.sql:14-28` (+ `online`) | excluded |
| `runners_available_for()` | `0054_availability_gating.sql:100-104`, re-defined `0055_definer_hardening.sql:80-84` | excluded from the owner's 지명 list |
| `marketplace_open_requests` | via `is_active_runner()`, `0042:44`, `0056:68` | empty request feed |
| club gates | `0030_hi_club.sql:164-165` (`not_certified_runner`), `0030:212`, `0043_payment_separation.sql:51`, `0048_consents_fees_viability.sql:179` | cannot host or take club delegation |
| `_club_runner_cap()` | `0037_club_delegation.sql:36-44` | `certified → 1, veteran → 2, master → 2, else 0` |
| board tier label | `0039:34`, `0043:483`, `0045:662`, `0047:674`, `0048:612`, `0052:64`, `0053:256` | label only |
| `transition-booking` | `supabase/functions/transition-booking/index.ts:51, 105` | `403 인증 러너만 오픈 요청을 수락할 수 있어요` |

Client:

| consumer | file:line |
| --- | --- |
| `fetchCertifiedRunners()` — `.neq('tier','applicant').eq('online', true)` | `app/src/lib/api.ts:526-527` |
| tier → Korean label (3 sites) | `api.ts:537, 567, 589` |
| `fetchMyRunnerStatus()` — **falls back to `tier: 'certified'`** when signed out or no row | `api.ts:1220, 1227` |
| `fetchMyRunnerCert()` — honest `null` when no row | `api.ts:1238-1252` |
| runner storefront profile | `api.ts:1456, 1477` |
| runner home bib/kicker/footer labels | `runner/home.tsx:157, 289, 332, 345, 374, 809` |
| runner home tier ladder ("베테랑까지 30회 / 마스터 100회 · 잠정") | `runner/home.tsx:632-641` |
| 인증 센터 tier card | `runner/apply.tsx:22, 97-101` |

**Consumers of `funnel_step`: [FACT] exactly one write (`api.ts:365`) and zero reads.** It is a
dead column protected by a guard.

**[INFERENCE]** The net effect stated in the launch checklist is correct and now doubly confirmed:
with no promotion path, every real runner sits at `applicant`, so `fetchCertifiedRunners` and
`runners_available_for` return empty, `is_active_runner()` is false for everyone, and
`transition-booking:105` rejects every accept. The marketplace has no supply *by construction*.

## 1.3 Client state: apply / home / role selection

**`app/app/runner/apply.tsx` (full file read).** Repainted 2026-08-05 as an honest brochure. Three
sections: ① server truth from `fetchMyRunnerCert()` (tier, total runs, total km, commission rate,
with loading / error / no-row states all distinct); ② a **static 5-step explainer** whose own lede
says "내가 어디까지 왔는지를 표시하는 목록이 아니에요"; ③ a `준비 중` block ending in the only CTA on
the screen — `router.push('/settings')` labelled 인증 절차 문의하기. **[FACT] There is no submit,
no form, and no write of any kind on this screen.** Its header comment already names
`docs/specs/runner-cert-funnel-spec.md` as the thing that lets ③ be deleted honestly.

**Entry points to it:** `app/app/my.tsx:147` — `러너 인증 센터 · 내 러너 레코드 · 인증 절차 안내` →
`/runner/apply`. That is the only route in.

**Role selection.** `app/app/index.tsx:24-42` — full-bleed two-button screen. Tapping 러너예요
upserts `profiles.role = 'runner'`, then calls `ensureRunner()`, then routes to `/runner/home`.
`ensureRunner()` (`api.ts:354-375`) inserts `tier:'applicant', funnel_step:'info',
avg_pace_sec_per_km:420, identity_verified:false, online:true`, plus 7 availability rules
(06:00–22:00 daily) and a `runner_booking_rules` row. Its comment (`api.ts:350-353`) is explicit
that entering runner mode must not pass certification — the honest fix landed with 0057 K-3.

**What a signed-up runner sees today at `/runner/home` [FACT]:**
- `fetchMyRunnerStatus()` defaults `tier: 'certified'` (`api.ts:1220, 1227`), and the screen's
  initial state is also `tier: 'certified'` (`home.tsx:157`). So before the fetch resolves — and
  forever, if the user is signed out — the bib, kicker and footer read **인증 러너**.
- The tier ladder (`home.tsx:632-641`) renders "베테랑까지 러닝 30회" to someone who is not certified.
- The request queue is empty, because `is_active_runner()` is false, and the empty state
  (`home.tsx:586-589`) says **"지금은 새 요청이 없어요 — 오는 대로 여기에 떠요"**. `ensureRunner` set
  `online: true`, so the applicant gets the optimistic branch of that ternary. **[INFERENCE] This is
  a false statement**: no request will ever arrive at this tier. It is the "loading ≠ empty" law
  applied one level up — *ungated* is being rendered as *quiet*.

## 1.4 P0 — verified live self-promotion hole (INSERT)

`runners self insert` (`0002_rls.sql:71`) checks only `profile_id = auth.uid()`. `_guard_runner_cols`
is `before update` (`0057:512`). Supabase default privileges grant `INSERT` on public tables to
`authenticated` (modelled in `supabase/tests/00_shim.sql:57`).

**[FACT] Executed against the harness DB at HEAD (`role authenticated`, fresh profile, no runners row):**

```
PROBE-1 INSERT SUCCEEDED  → tier=master  commission_rate=0.000  identity_verified=t
PROBE-2 visible to a stranger through "runners public read": 1 row
PROBE-3 self-DELETE: 0 rows affected, no error (no delete policy) — the row is permanent
```

The inserted row also carried `total_runs=9999, total_km=99999, insurance_active=true,
funnel_step='certified'`. Consequences, all immediate:

- `transition-booking:105` passes → the account can accept open requests.
- `settle-run` reads `commission_rate = 0` → the platform takes nothing; the runner is paid 100%.
- `_club_runner_cap` returns 2 → full club delegation capacity.
- `fetchCertifiedRunners` and `runners_available_for` list the account to owners as 마스터 with
  9,999 runs.

Cost of the attack: one free signup (it must be an account with **no** `runners` row, so the
attacker simply does not tap 러너예요 first). This is a certification bypass, a payout theft, and a
safety-claim forgery in one statement. **It must land before, or with, anything else in this plan.**

## 1.5 Ops and admin surfaces that exist today

**[FACT] There is no admin role, no admin screen, and no ops dashboard.** `user_role` is
`('owner','runner')` (`0001:7`). The nearest things:

| surface | file:line | shape |
| --- | --- | --- |
| service-role node scripts — **how Sean actually does one-off ops** | `scripts/seed-runners.mjs`, `scripts/wipe-test-data.mjs`, `scripts/diag.mjs`, `app/scripts/e2e-club.mjs` | read `SUPABASE_SERVICE_ROLE_KEY` from root `.env`, `fetch` against `/rest/v1/…` and `/auth/v1/admin/…` |
| allowlist table with RLS enabled and **zero policies** (service-role-only by construction) | `club_test_accounts`, `0044_r1_hardening.sql:16-21` | the house idiom for "ops-only data" |
| definer function revoked from every client role | `_club_require_v2()`, `0044:23-30` | `revoke execute … from public, anon, authenticated` |
| edge functions with a service client | `supabase/functions/_shared/ctx.ts` — `admin()`, `caller(req, db)`, `handle(fn)`, `HttpError` | 4 functions deployed |
| `__DEV__`-gated in-app dev routes | `app/app/dev/club-lab.tsx`, `pay-lab.tsx`, linked from `settings.tsx` | double-gated labs, not ops |

Runbooks: `CLAUDE.md` — "`supabase db push`, `supabase functions deploy`, and `git push` are
performed by Sean ONLY… SQL goes to the SQL editor; shell commands to the terminal."
`docs/session-handoff.md` carries a per-wave deploy queue.

**⚠ [FACT] `scripts/seed-runners.mjs:27-32` mints six runners at `veteran/certified/master` with
fabricated `runs`, `km`, `respond` values, directly via the service role.** If any of those rows are
in the production project, they are bookable runners who passed nothing. See §7 and §10.

## 1.6 Storage — every existing upload path

**[FACT] There is exactly one bucket: `avatars`, `public: true`** (`0006_avatars.sql:4-6`). RLS on
`storage.objects`: world-readable select for the bucket (`0006:9-10`); insert/update/delete gated on
`auth.uid()::text = (storage.foldername(name))[1]` (`0006:12-27`) — own top folder only.

Client idiom (11 call sites in `api.ts`): `expo-image-picker` → base64 → `b64ToBytes` →
`supabase.storage.from('avatars').upload(path, …)` → `getPublicUrl(path)` → store the URL in a
column. Representative: `api.ts:184-193` (dog photo, path `{uid}/dogs/{dogId}.jpg`), also
`api.ts:1312, 1341, 1544, 1588, 1888, 2517`. Pickers: `chat.tsx:66-73`,
`club/session/[sid].tsx:457-467`.

`0053_audit_followups.sql:22-30` already plans a private `club-run-photos` bucket + signed URLs and
explicitly **defers** it as "a large job touching every media path". Nothing has been built.

**[INFERENCE]** Any identity document uploaded with the existing idiom would be world-readable at a
guessable URL. A private bucket, a signed-upload RPC, an ops signed-read path, and a retention
policy are a whole slice — and they sit behind the unanswered legal question (`launch-checklist.md`
§1 `[legal]`; spec §6.4). Hence D5.

## 1.7 Harness conventions and the migration law

`CLAUDE.md` — Migrations & security:
- Any migration or security-relevant change requires the **adversarial cycle**: scout → contract →
  implement → adversarial review *where reviewers EXECUTE attacks* → test pins → revise → verify.
- New security-definer functions **must** carry `set search_path = public, pg_temp` **in the function
  body** — ALTER-applied config is reset by `create or replace`. `98 H1` sweeps the whole schema.
- Views change via `create or replace` only — never DROP (grant preservation).
- Party gate before state gate in RPCs; flat whitelisted returns.
- Existing migration files are never edited.
- Commit gate: `cd app && ./node_modules/.bin/tsc --noEmit` **and** `node scripts/check-rpc-contracts.mjs`.
  The latter (`app/scripts/check-rpc-contracts.mjs`) parses `create or replace function` out of the
  migrations and matches every `supabase.rpc(...)` in `api.ts` — so every new RPC must be declared
  with `create or replace function`.

Harness (`supabase/tests/harness.sh`): applies `00_shim.sql` then every migration in order, then each
suite in numeric order, then prints `_t` and fails on any red. **[FACT] Re-run during this scout:
246 pass / 0 fail.** Invocation on Sean's Mac:

```
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
cd /Users/sean/dev/daengrun/supabase/tests && bash harness.sh
```

Suite conventions, from `100_wave3_suite.sql` (the model to copy):
- Header block naming each pin's **single revert that turns it RED**, with ✔ on the ones actually
  executed. This is the mutation-proof convention.
- Helpers from `10_settle_suite.sql`: `_pass(suite, name)`, `_fail(suite, name, detail)`,
  `t_user(name, role)`, `t_dog(owner, name)`, `t_route(name)`.
- Definer/view paths: stay `postgres`, switch identity with
  `set_config('request.jwt.claim.sub', uid, …)`. Real RLS paths: `set local role authenticated` with
  an **unconditional `reset role`** in the exception handler.
- Each case in its own `begin … exception when others then` so one failure cannot abort the suite.
- `now()`-independent fixtures use a fixed future window; seed bookings are closed as `expired` so
  the open pool is not polluted.

**Next free suite number: `101`** (100 is `100_wave3_suite.sql`). Wire it in `harness.sh` after the
`100_…` line, before the final `psql -c "select …"` reporting block.

## 1.8 `docs/runner-recruitment.md` vs the code

The doc's real-life funnel (`runner-recruitment.md`, "The funnel (both audiences)"):

```
See post/crew session → info session RSVP (form) → pace test + dog-handling onboarding
→ 신원인증 + insurance enrollment → CERTIFIED (badge, bib, patch, Strava club)
→ first run within 7 days (assign manually if needed) → active
```

Targets: **20–30 certified runners in the launch 동 before demand launch**; supply model needs ~22
certified for 50 paying dogs (`runner-recruitment.md` §0). Funnel targets: 80+ RSVPs → 50 pace-test
takers → 25–30 certified. "Instrument every step. Expected drop-offs are the product… Report 'X%
통과' publicly — rejection rate is marketing." Certification is deliberately framed as **a credential,
not a job**.

**Reconciliation [INFERENCE]:**

| doc step | code today | this plan |
| --- | --- | --- |
| info session RSVP (form) | nothing | out of scope — Sean runs it on Instagram/DM, per §4 of the doc |
| pace test + dog-handling onboarding | nothing | **the video call**; recorded as `decided_note` on the application |
| 신원인증 | `identity_verified` hardcoded `false`, never written | set `true` **by the approval RPC**, meaning "an operator checked the ID on camera" — and the product copy says exactly that (§7) |
| insurance enrollment | `insurance_active` never written; `safety.tsx:151` says 협의 중 | out of scope, copy already honest |
| CERTIFIED (badge/bib/patch/Strava) | tier label + bib UI exist on `runner/home.tsx` | tier raise makes the existing UI true; physical goods are Sean's ops |
| first run within 7 days | manual assignment already possible (owner 지명) | out of scope |
| "instrument every step", rejection rate as marketing | nothing | the application table **is** the instrument: `state`, `attempt_no`, `created_at`, `decided_at` give pass rate and time-to-decision for free. Named as a deliberate benefit of D1. |

The 5-step explainer currently on `apply.tsx:26-32` (기본 정보 / 신원 확인 / 안전 교육 / 시범 러닝 /
인증 완료) describes the **aspirational** funnel, and `funnel_step`'s enum encodes the same five. The
pilot's real process is three steps: 지원서 → 화상 통화(신분증 + 개 경험 확인) → 승인. **The explainer
copy must be brought down to the real process** (§6.2) — a 5-step brochure over a 3-step reality is
the same class of lie the 2026-08-05 repaint removed.

## 1.9 Where the spec is stale

1. **Spec §2 H-1** claims `runners self write` has no `with check` and a runner can set
   `tier='master'` / `commission_rate=0` by UPDATE. **Fixed since**, by `0057:482-513` + pin S4
   (`99_security_suite.sql:169-205`). The *remaining* hole is INSERT (§1.4) — which the spec does
   flag in passing under §5.4 ("insert into runners … values (auth.uid(), 'certified')") but files
   under a migration (`0057_runner_cert_hardening.sql`) that was written and shipped **without** it.
2. **Spec §2 H-2** (self-verified documents) is **fixed** by `_guard_runner_doc_verify`
   (`0057:521-540`) + pin S5.
3. **Spec §2 H-3** (`ensureRunner` minting `certified`) is **fixed** — `api.ts:364-367` now inserts
   `applicant` / `identity_verified: false`.
4. **Spec preamble** says `docs/runner-recruitment.md` does not exist. **It exists** and is the
   ops source of truth (§1.8).
5. Spec §7.1 proposes migration numbers 0057–0059, all now taken. Renumber to 0061/0062.

---

# PART II — BUILD CONTRACT

## 2. Migration `0061_runner_apply_seal.sql` — P0, ships first

Independently valuable; no client change is required for it to be safe to deploy (see the
compatibility proof below).

### 2.1 Extend the column guard to INSERT

`create or replace function _guard_runner_cols()` (same name — 0057's trigger keeps pointing at it),
then re-create the trigger as `before insert or update on runners`. Body shape, following
`_guard_runner_doc_verify` (`0057:521-540`) which already handles both operations:

- `if current_user not in ('authenticated','anon') then return new; end if;` — service role, definer
  RPCs and `postgres` pass through, exactly as 0057 documents for `settle_run_tx`.
- `if tg_op = 'INSERT'` → raise `runner_protected_columns` unless **every** protected column equals
  its server default:
  `tier = 'applicant'`, `funnel_step = 'info'`, `identity_verified = false`,
  `insurance_active = false`, `trainer_certified = false`, `education_modules_done = 0`,
  `total_runs = 0`, `total_km = 0`, `completion_rate is null`, `compliance_pct is null`,
  `respond_rate_pct is null`, `commission_rate = 0.33`.
  Use `is distinct from` throughout so a client-sent NULL cannot slip past an `=` comparison.
- `elsif tg_op = 'UPDATE'` → the existing 0057 comparison list, unchanged.
- Korean `using detail` preserved: `'등급·수수료율·실적·검증 상태는 서버만 정해요 — 클라는 스토어프런트 필드만'`.

**Client compatibility proof [FACT]:** `ensureRunner()` (`api.ts:360-370`) sends exactly
`profile_id, tier:'applicant', funnel_step:'info', avg_pace_sec_per_km:420,
identity_verified:false, online:true`. Every protected value it sends equals the default; every
protected value it omits takes the default. **The current shipped client passes the new INSERT
guard unchanged** — so 0061 can be pushed before the client slice with no deploy-order coupling.
Pin F1's positive control asserts this and will go red if a future implementer tightens it further.

Do **not** re-write `runners self insert` as a column-listing `with check`. A blacklist trigger is
what 0057 §6 deliberately chose (so that legitimate storefront columns like `photos` are never
accidentally sealed), and splitting the mechanism across a policy and a trigger gives a future
reviewer two places to look.

### 2.2 Deprecate the dead funnel columns

Comment-only, no drops (dropping enum-typed columns mid-pilot buys nothing):

```sql
comment on column runners.funnel_step is
  'DEPRECATED 0061 — superseded by runner_applications.state (0062). Written once by ensureRunner, read by nothing. Do not add readers.';
comment on column runners.education_modules_done is
  'DEPRECATED 0061 — no education modules exist in the pilot. Never written.';
comment on column runners.identity_verified is
  'Written ONLY by runner_app_approve (0062) = an operator checked the ID on a video call. Not an automated 본인인증.';
```

## 3. Migration `0062_runner_applications.sql`

### 3.1 D1 argued: a table, not `funnel_step` transitions

**The case for `funnel_step` on `runners`** (the cheap option): the column and its enum already
exist; RLS and the column guard already cover it; zero new tables; a state machine over one column
is trivially auditable.

**Why it loses:**

1. **Nowhere to put the decision.** A rejection needs a reason the applicant reads verbatim, a
   decided-at, an operator handle, and a hard-bar flag. On `runners` these become four new columns
   on the *storefront capability record* — the same row that `runners public read` exposes to every
   owner (`0002:69`). A rejection reason must never sit one policy mistake away from public.
2. **No attempt history.** `funnel_step` is one slot. Re-application overwrites the previous
   decision, so "who was rejected, why, and did they re-apply" is unanswerable — and
   `runner-recruitment.md` §2 makes drop-off instrumentation an explicit product requirement.
3. **The row does not exist yet at apply time.** A `runners` row appears only after tapping 러너예요
   (`index.tsx:37`). Making the application live on `runners` forces "enter runner mode" to precede
   "apply", which is the exact confusion the 0057 K-3 comment warns about.
4. **The enum is the wrong vocabulary and cannot be fixed cheaply.** `funnel_step` is
   `info|kyc|education|trial|certified` — it has no `rejected` and no `withdrawn`, and the pilot has
   no education or trial step at all. Adding values means `alter type … add value`, against the house
   convention (§1.1: nothing since 0001 has created or extended an enum).
5. **Sealing granularity.** A separate table can have **zero client policies** and be reachable only
   through a definer projection (the `assignment_events` / `club_test_accounts` idiom, `0044:16-21`),
   so ops notes and applicant contact details are unreachable by construction. On `runners` the
   applicant can already `select` their own row, so any column added there is client-readable.

**What stays on `runners`:** `tier`, as the single capability gate (D3). The application table is the
*history*; `runners.tier` is the *capability*. Pin F11 exists specifically to stop a future refactor
from deriving the gate from the application table and putting a join inside `is_active_runner()`.

### 3.2 Table

```sql
create table runner_applications (
  id                    uuid primary key default gen_random_uuid(),
  profile_id            uuid not null references profiles(id) on delete cascade,
  attempt_no            int  not null default 1,
  state                 text not null default 'submitted'
                          check (state in ('submitted','under_review','approved','rejected','withdrawn')),

  -- applicant payload. Copied into `runners` ONLY at approval, so an in-flight
  -- application can never leak into the storefront.
  district              text    not null check (char_length(btrim(district)) between 1 and 40),
  avg_pace_sec_per_km   int     not null check (avg_pace_sec_per_km between 180 and 900),
  max_dog_weight_kg     numeric(4,1) not null check (max_dog_weight_kg between 1 and 80),
  service_radius_km     numeric(3,1) not null default 3 check (service_radius_km between 0.5 and 20),
  specialties           text[]  not null default '{}' check (array_length(specialties,1) is null or array_length(specialties,1) <= 6),
  bio                   text    not null check (char_length(btrim(bio)) between 10 and 500),
  running_experience    text    not null check (char_length(btrim(running_experience)) between 10 and 1000),
  dog_experience        text    not null check (char_length(btrim(dog_experience)) between 10 and 1000),

  -- contact for the vetting call (personal data — see §3.6)
  contact_kakao         text check (contact_kakao is null or char_length(btrim(contact_kakao)) between 1 and 60),
  contact_phone         text check (contact_phone is null or contact_phone ~ '^01[0-9]{8,9}$'),
  contact_window        text check (contact_window is null or char_length(contact_window) <= 200),
  consent_terms         boolean not null check (consent_terms),
  consent_privacy       boolean not null check (consent_privacy),
  consent_id_check      boolean not null check (consent_id_check),

  -- ops decision
  reviewed_at           timestamptz,
  decided_at            timestamptz,
  decided_by            text,          -- self-declared operator handle; NOT an authenticated identity (§3.5)
  decided_note          text,          -- ops-internal. NEVER crosses the applicant projection.
  reject_reason         text,          -- applicant-visible, verbatim
  is_hard_bar           boolean not null default false,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint runner_app_contact_present
    check (coalesce(btrim(contact_kakao), btrim(contact_phone), '') <> ''),
  constraint runner_app_reject_reason
    check (state <> 'rejected' or coalesce(btrim(reject_reason),'') <> ''),
  constraint runner_app_hard_bar_terminal
    check (not is_hard_bar or state = 'rejected'),
  constraint runner_app_decided_shape
    check ((state in ('approved','rejected')) = (decided_at is not null))
);

create unique index runner_app_one_active on runner_applications (profile_id)
  where state in ('submitted','under_review');
create unique index runner_app_attempt on runner_applications (profile_id, attempt_no);
create index        runner_app_queue  on runner_applications (state, created_at)
  where state in ('submitted','under_review');

create trigger t_runner_app_touch before update on runner_applications
  for each row execute function touch_updated_at();   -- 0002_rls.sql:5

alter table runner_applications enable row level security;
-- NO POLICIES AT ALL. Reads go through runner_my_application(); writes go through the RPCs below.
-- Same idiom as club_test_accounts (0044:16-21) and the assignment/custody event tables.
```

**Why per-state timestamps here, when the spec argued against them (spec §4.1):** the spec paired
that argument with a mandatory `runner_application_events` table. For one operator and five states,
three timestamps (`created_at` = submitted, `reviewed_at`, `decided_at`) carry every fact an event
table would, and `runner_app_decided_shape` makes a timestamp that disagrees with the state
impossible to write. **Upgrade path, recorded so it is a decision and not an omission:** the moment a
second operator exists, or a state can be re-entered, add `runner_application_events` (RLS on, no
policies) and stop trusting the timestamps.

### 3.3 Applicant RPCs — granted to `authenticated`, revoked from `anon`

All three: `security definer`, `set search_path = public, pg_temp` **in the body**, first statement
`if auth.uid() is null then raise exception 'not_signed_in'; end if;` (NULL-safe — never compare
against a possibly-NULL `auth.uid()` and rely on the row simply not matching).

**`runner_apply_submit(p_district text, p_pace int, p_max_weight numeric, p_radius numeric,
p_specialties text[], p_bio text, p_running_exp text, p_dog_exp text, p_contact_kakao text,
p_contact_phone text, p_contact_window text, p_consent_terms boolean, p_consent_privacy boolean,
p_consent_id_check boolean) returns uuid`

Order of checks (each raises a distinct token, all about the *caller's own* data, so none is an
enumeration oracle):
1. `not_signed_in`
2. consents: any of the three `is distinct from true` → `consent_required`
3. `exists (… profile_id = auth.uid() and state in ('submitted','under_review'))` → `already_applied`
4. `exists (… state = 'rejected' and is_hard_bar)` → `application_barred`
5. `(select tier from runners where profile_id = auth.uid()) is distinct from 'applicant'` **and the
   row exists** → `already_certified` (idempotence for a runner who is already through)
6. `v_attempt := coalesce(max(attempt_no), 0) + 1`; `if v_attempt > 3 then raise 'attempt_cap_reached'`
7. insert, `returning id`

The check constraints do the field validation; the RPC does not duplicate them. A constraint
violation surfaces as a Postgres error — acceptable, because the client form validates the same
ranges before submitting and the constraint is the backstop, not the UX.

**`runner_apply_withdraw(p_application uuid) returns void`** — **party gate before state gate**:

```
select state into v_state from runner_applications
  where id = p_application and profile_id = auth.uid();
if not found then raise exception 'not_found'; end if;          -- identical for "no such row" and "not yours"
if v_state not in ('submitted','under_review') then raise exception 'not_withdrawable'; end if;
update … set state = 'withdrawn' where id = p_application;
```

Pin F6 asserts the two error strings are byte-identical, so an attacker cannot enumerate which
application ids exist.

**`runner_my_application() returns table(id uuid, state text, attempt_no int, submitted_at
timestamptz, reviewed_at timestamptz, decided_at timestamptz, reject_reason text, is_hard_bar
boolean, can_reapply boolean)`** — `stable security definer`, latest attempt only
(`order by attempt_no desc limit 1`), 0 rows = never applied.

Flat whitelist, enumerated so a reviewer can diff it: **`decided_by`, `decided_note`,
`contact_phone`, `contact_kakao`, `contact_window`, and the whole payload are absent.** Never
`select *`. `can_reapply` is computed server-side:
`state in ('rejected','withdrawn') and not is_hard_bar and attempt_no < 3`.

### 3.4 Ops RPCs — revoked from `public, anon, authenticated`

Each begins with a belt-and-braces in-body check mirroring the guard-trigger idiom, so the seal
survives a mis-applied grant:

```
if current_user in ('authenticated','anon') then raise exception 'ops_only'; end if;
if coalesce(btrim(p_operator), '') = '' then raise exception 'operator_required'; end if;
```

and ends with `revoke execute on function … from public, anon, authenticated;` (precedent:
`_club_require_v2`, `0044:30`). `service_role` retains EXECUTE through Supabase default privileges
(modelled at `00_shim.sql:64-66`).

| function | from → to | writes |
| --- | --- | --- |
| `runner_app_review(p_application uuid, p_operator text)` | `submitted → under_review` | `reviewed_at = now()`, `decided_by = p_operator` |
| `runner_app_approve(p_application uuid, p_operator text, p_note text)` → `uuid` | `submitted\|under_review → approved` | see below |
| `runner_app_reject(p_application uuid, p_operator text, p_reason text, p_hard_bar boolean default false)` | `submitted\|under_review → rejected` | `decided_at`, `decided_by`, `decided_note`, `reject_reason` (required non-empty), `is_hard_bar` |

**`runner_app_approve` is the only function in the schema that may raise `runners.tier`.** Body:

1. load the application `for update`; `not_found` if absent.
2. **idempotent**: `if state = 'approved' then return profile_id;` — no second write, no error, no
   second `decided_at`. Two ops clicks are one approval.
3. `if state not in ('submitted','under_review') then raise exception 'not_approvable'; end if;`
4. `insert into runners (profile_id) values (v_profile) on conflict (profile_id) do nothing;` —
   covers an applicant who never tapped 러너예요. Runs as the definer (`postgres`), so both RLS and
   the guard trigger pass through, exactly as 0057 documents for `settle_run_tx`.
5. `update runners set tier = 'certified', identity_verified = true,
   district-derived storefront fields (bio, specialties, avg_pace_sec_per_km, service_radius_km,
   max_dog_weight_kg) := the application payload, updated_at = now() where profile_id = v_profile;`
   Also `update profiles set district = a.district where id = v_profile and district is null;`
6. `update runner_applications set state = 'approved', decided_at = now(), decided_by, decided_note`.

**Three things approval deliberately does NOT do**, each with a pin (F9):

- **It does not touch `online`.** `online` is a switch the runner owns; the server never flips a
  user's switch. `ensureRunner` sets it `true` for anyone who entered runner mode, so most approvals
  are immediately visible; a runner who turned it off stays off. The 인증 센터 says which one is true
  (§6.2). *Operational consequence for Sean:* an approved runner who never entered runner mode has
  `online = false` from the table default and will not appear in `fetchCertifiedRunners`
  (`api.ts:527`) until they open the app. That is honest supply, and it is in the manual-ops
  checklist (§10).
- **It does not touch `commission_rate`.** 33% flat (`0059:14`); tier and commission are not linked
  in code, only in a stale `0001:75` comment.
- **It does not touch `total_runs` / `total_km`.** Those belong to `settle_run_tx`. A newly certified
  runner has 0 runs and is carried by the 8+2 rookie slots already built into
  `runners_available_for` (`0055` §1-2) — the funnel must not add a second visibility boost.

### 3.5 Security laws this must satisfy — reviewer checklist

| law | where it applies | how a reviewer checks it |
| --- | --- | --- |
| `set search_path = public, pg_temp` **in the body** of every new definer function | all 6 RPCs | `98 H1` sweeps the schema and fails the harness automatically; F13 names the 6 explicitly. Also attempt an actual `pg_temp` shadowing exploit against `runner_app_approve` to prove the sweep is meaningful (the 0055 §3 lesson). |
| NULL-safe auth comparison | every applicant RPC | explicit `if auth.uid() is null then raise 'not_signed_in'`; never rely on `profile_id = auth.uid()` silently matching nothing. Every protected-column comparison in 0061 uses `is distinct from`. |
| enumeration-oracle-free errors | `runner_apply_withdraw`, all 3 ops RPCs | party gate **before** state gate; `not_found` is byte-identical for "no such id" and "not yours". Pin F6 compares the two `sqlerrm` strings for equality. |
| revoke from public/anon | all 6 | applicant RPCs: `revoke … from public, anon` + `grant execute … to authenticated`. Ops RPCs: `revoke … from public, anon, authenticated` and no grant. Pin F8. |
| **no self-promotion path** | `runners` | UPDATE: sealed by `_guard_runner_cols` since 0057, pinned by `99 S4` — **verified during this scout**. INSERT: **open today, closed by 0061 §2.1**, pinned by F1. DELETE: no policy, 0 rows affected — verified in §1.4. `runner_applications`: zero client policies, so `update … set state='approved'` fails with 0 rows; pinned by F3. |
| flat whitelisted returns | `runner_my_application()` | 9 declared columns; runtime key set asserted to exclude `decided_note`, `decided_by`, `contact_*`. Pin F7, in the shape-pin style of `100_wave3_suite` W6. |
| views via `create or replace` only | n/a — this plan adds no views | — |
| existing migration files never edited | 0061/0062 are new files | — |
| adversarial cycle | the whole slice | reviewers **execute** the attack list in §8.3 |

### 3.6 Personal data — an explicit precondition, not a footnote

`contact_phone` / `contact_kakao` / `contact_window` are personal data collected from real people.
`docs/launch-checklist.md` §1 records that **no 개인정보처리방침 exists** and that the
위치기반서비스사업 신고 has not been filed. **[INFERENCE]** Collecting contact details through this
form before a privacy policy is published is a compliance problem, not an engineering one.

Contract: the form ships with (a) three explicit consent checkboxes stored on the row
(`consent_terms`, `consent_privacy`, `consent_id_check`, all `check (…)`-forced true), (b) an
in-form notice naming exactly what is collected, why, and for how long, and (c) **`consent_privacy`
must link to a real published policy**. Until that policy exists, the honest pilot fallback is to
collect only a KakaoTalk ID and no phone number, and to say in the form that Sean will contact them
there. `runner_app_contact_present` allows either one.

## 4. Ops surface — D4 in detail

**`scripts/runner-ops.mjs`**, modelled line-for-line on `scripts/seed-runners.mjs`: load root `.env`,
require `SUPABASE_SERVICE_ROLE_KEY`, `fetch` against `${URL}/rest/v1/rpc/<fn>` with
`apikey`/`Authorization` set to the service key.

```
node scripts/runner-ops.mjs list                                  # queue: submitted + under_review, oldest first
node scripts/runner-ops.mjs show <application_id>                 # full row incl. contact + payload
node scripts/runner-ops.mjs review  <application_id> --by sean
node scripts/runner-ops.mjs approve <application_id> --by sean --note "video call 2026-08-14, ID checked, 5km 24:10"
node scripts/runner-ops.mjs reject  <application_id> --by sean --reason "..." [--hard]
```

`list`/`show` read the table directly (service role bypasses RLS). The three mutating commands call
the revoked RPCs, so **the script cannot do anything the RPC would not do** — no raw `update`
statements, no path around the state machine. `--reason` is printed back with a confirmation prompt
before sending, because it is shown verbatim to a human.

**SQL-editor runbook fallback** (for when the script is not to hand — `CLAUDE.md`: SQL goes to the
SQL editor):

```sql
-- queue
select id, profile_id, attempt_no, state, district, contact_kakao, contact_phone, contact_window, created_at
from runner_applications where state in ('submitted','under_review') order by created_at;

select runner_app_review ('<id>', 'sean');
select runner_app_approve('<id>', 'sean', 'video call 2026-08-14, ID checked');
select runner_app_reject ('<id>', 'sean', '반포 활동 지역이 아니에요 — 서비스 지역이 열리면 다시 알려드릴게요', false);
```

**Rejected alternatives, recorded:** an **edge function** (`runner-cert-ops`, as the spec proposed)
adds a `supabase functions deploy` step to every iteration and an auth layer that has nothing to
authenticate — there is one operator and he holds the service key. An **in-app ops route** puts an
admin surface inside the consumer app during a pilot with 22 runners. An **`ops_operators` allowlist**
answers "which operator" — a question with one answer today. All three become right the moment a
second operator exists; that is the documented upgrade path, and `decided_by` is the seam
(it is a self-declared string today, and the plan says so rather than pretending it is an identity).

## 5. Not in scope

Each line is a decision, with its reason and its unblocking condition.

| out of scope | why | unblocked by |
| --- | --- | --- |
| Identity **document upload** (신분증 사진, 범죄경력회보서) | only bucket is `avatars`, `public: true` (`0006:5`); a private bucket + signed upload/read + retention is its own slice (`0053:22-30` already defers exactly this) | a private-bucket slice **and** the legal answer |
| 범죄경력회보서 handling | `[legal]` — lawfulness of collection, who may view, retention/destruction. `runner_documents.kind` contemplates it and the retired mock claimed a destruction policy nothing implements | counsel |
| Automated 본인인증 (PASS / NICE / Toss) | cost and contract lead time; 22 runners do not justify it. `identity_verified` means "an operator checked the ID on a call", and the copy says so (§7) | after the pilot |
| Safety **education modules** + quiz scoring + catalog versioning | spec §4.2 designs it well; there is no content to teach yet (`runner-recruitment.md` lists it as an in-person onboarding step) | authored content |
| **Trial run + evaluator pool** | there are zero veteran runners, so the first cohort has no evaluator (spec §8 Q3). Sean's video call *is* the trial for the pilot | a certified cohort |
| **veteran / master promotion** | `runner/home.tsx:632-641` shows an unbacked 30/100-run ladder marked 잠정; three unbacked ladders coexist (spec §8 Q6) | a criteria decision from Sean |
| `runner_application_events` table | 5 states, one operator; three timestamps + a shape constraint carry it (§3.2) | a second operator |
| `ops_operators`, ops edge function, in-app ops screen | §4 | a second operator |
| Insurance enrollment (`insurance_active`) | `safety.tsx:151` already says 협의 중 — honest | a signed policy |
| Push notification on decision | `0024_push.sql` exists, so it is cheap, but Sean is on a call with these 22 people anyway. Optional stretch; if built, it must be a real send with a real failure path | — |
| Info-session RSVP form, pace test recording, bib/patch fulfilment | Sean's ops per `runner-recruitment.md` §2, §4 | — |

## 6. Client contract

Sequenced **after** 0061 + 0062 are pushed. `apply.tsx` calls RPCs that must already exist —
`app/scripts/check-rpc-contracts.mjs` is a commit gate and will fail otherwise.

### 6.1 `api.ts`

New: `submitRunnerApplication(form)` → `supabase.rpc('runner_apply_submit', …)`;
`withdrawRunnerApplication(id)`; `fetchMyRunnerApplication()` → `runner_my_application()`, returning
`RunnerApplication | null` where **null strictly means "no row"** (never a fallback for an error).

Error mapping in the `api.ts` house style (`fetchAvailableRunnersFor`, `api.ts:556-562`: behaviour
instructions, not raw tokens):

| token | Korean |
| --- | --- |
| `not_signed_in` | `세션이 만료된 것 같아요 — 다시 로그인해주세요` |
| `already_applied` | `이미 접수된 지원서가 있어요` |
| `application_barred` | `이 계정으로는 다시 지원할 수 없어요 — 문의해주세요` |
| `already_certified` | `이미 인증된 러너예요` |
| `attempt_cap_reached` | `지원은 3번까지 할 수 있어요 — 문의해주세요` |
| `consent_required` | `필수 동의 항목을 확인해주세요` |
| `not_found` / `not_withdrawable` | `지원서를 찾을 수 없거나 지금은 취소할 수 없어요` |

**Two honesty fixes to existing code, both required by this slice:**

1. `fetchMyRunnerStatus()` (`api.ts:1216-1231`) returns `tier: 'certified'` when the user is signed
   out or has no `runners` row. Change `MyRunnerStatus.tier` to `string | null`, return `null` in
   both of those cases, and let the caller render the not-yet-known state. This is the same
   distinction `fetchMyRunnerCert` already draws deliberately (`api.ts:1234-1237`).
2. `runner/home.tsx:157` seeds component state with `tier: 'certified'` — same lie, one layer up.
   Seed `null` and add a `loaded` flag.

### 6.2 `/runner/apply` — the 인증 센터 becomes a real funnel

Section ① (server record) is unchanged. Section ② (the 5-step explainer, `apply.tsx:26-32`) is
**rewritten to the pilot's actual 3 steps** — see §1.8; a 5-step brochure over a 3-step process is
the same class of fabrication the 2026-08-05 repaint removed. Section ③ (`준비 중`) is replaced by
the state-bound block below, and the `/settings` CTA survives only where 문의 is genuinely the next
action.

| state | ③ renders | CTA | notes |
| --- | --- | --- | --- |
| not loaded | `지원 현황을 불러오는 중이에요…` | none | loading ≠ empty |
| load failed | error box with the real message | 다시 시도 | failures render as failures |
| no row | 지원 안내 + what the call covers | **`러너 지원서 작성`** → form | this is the screen's first real submit |
| `submitted` | `지원서가 접수됐어요` + submitted date | `지원 취소` (real: `runner_apply_withdraw`) | **no approval CTA** — the next actor is ops, and a disabled button is a dead button |
| `under_review` | `검토 중이에요` + reviewed date | `지원 취소` | |
| `approved` | `인증이 끝났어요` + tier from ① | none, **plus one line bound to the real `online` value** | see copy in §7.2 |
| `rejected`, soft | `이번엔 승인되지 않았어요` + `reject_reason` **verbatim** | `다시 지원하기` iff `can_reapply` | |
| `rejected`, hard | same + terminal line | `문의하기` → `/settings` | |
| `withdrawn` | `지원을 취소했어요` | `다시 지원하기` iff `can_reapply` | |
| cap reached | `지원은 3번까지 할 수 있어요` | `문의하기` | `can_reapply=false` with `is_hard_bar=false` |

The form: 활동 지역, 평균 페이스, 감당 가능한 최대 체중, 활동 반경, 전문 분야(≤6), 한 줄 소개,
러닝 경력, 반려견 경험, 연락처(카톡 ID 또는 휴대폰), 연락 가능한 시간, 3 consent checkboxes.
Client-side range validation mirrors the check constraints so the constraint is a backstop, never
the UX. Submit shows a real in-flight state and a real failure state.

### 6.3 `/runner/home` for a pending applicant

- **Line 586-589 is the priority fix.** When `tier === 'applicant'`, the empty inbox must not say
  `지금은 새 요청이 없어요 — 오는 대로 여기에 떠요`. Replace with the §7.3 copy and a **real route**
  to `/runner/apply` (an empty state with no explanation and no exit is the honesty failure here,
  not the emptiness itself).
- **Tier ladder (`home.tsx:632-641`)**: do not render the 베테랑까지 30회 progress bar for an
  applicant — it is progress toward a rung above one they have not reached. Replace with the §7.3
  line.
- **Bib / kicker / footer labels** (`home.tsx:332, 345, 374, 809`): while `tier` is null, render a
  neutral `러너`, never 인증 러너.
- Everything else on the screen (earnings, drop trail, availability) already reads real zeros and
  needs no change.

### 6.4 `my.tsx`

`my.tsx:147` subtitle `내 러너 레코드 · 인증 절차 안내` becomes state-aware once the screen is a real
funnel: `지원하기` / `심사 중` / `인증 완료`. Cosmetic; ship with the rest.

## 7. The honesty question — `safety.tsx:150`

**The problem, stated exactly.** `app/app/safety.tsx:150` tells owners:

> `모든 러너는 신원 확인을 거쳐요 (본인인증 고도화 예정)`

while `api.ts:367` hardcodes `identity_verified: false` for every runner ever created, nothing in
the schema ever sets it true, and **no runner has been verified by anything**. The parenthetical
"고도화 예정" makes it worse, not better: it implies a basic check exists and will be upgraded. There
is no check. As written, this is the single strongest false claim in the app, and it is a *safety*
claim made to a person about to hand a stranger their dog.

### 7.1 What must be true before that sentence is honest

All five, and the copy is false if any one fails:

1. **Every bookable runner passed a real check.** `tier <> 'applicant'` ⟹ an `approved`
   `runner_applications` row exists for that profile. Enforced by: `runner_app_approve` is the only
   tier writer (§3.4), the UPDATE seal (`0057`, pin S4), and **the INSERT seal (0061, pin F1)** —
   without which anyone can mint themselves 마스터 (§1.4).
2. **The check is un-forgeable by the runner.** `identity_verified` is in the protected set for both
   UPDATE and INSERT after 0061.
3. **No grandfathered runners.** ⚠ `scripts/seed-runners.mjs:27-32` mints six `certified`/`veteran`/
   `master` runners with fabricated stats via the service role. **If those rows are in the production
   project, the sentence is false the day it ships.** They must be deleted (or demoted to
   `applicant`) before any real owner reads this screen. Verification query in §10.
4. **The stated process is the process actually performed.** If Sean approves anyone without a video
   call and an ID on camera, the copy is false again. `decided_note` is where that is recorded, and
   §10 makes it a required field of the ops step, not a nicety.
5. **The words describe a manual check, not an automated one.** No owner should read
   "신원 확인" and picture PASS. That is the copy change below.

### 7.2 Proposed Korean copy

**`safety.tsx:150` — recommended (two-line desc, matching the 펫보험 row's honest register at
`safety.tsx:151`):**

```tsx
<InfoRow
  glyph="✓"
  title="러너 신원"
  desc="파일럿 기간에는 운영자가 화상 통화로 러너를 직접 만나 신분증을 확인하고 한 명씩 승인해요 — 자동 본인인증(PASS)은 아직 도입 전이에요"
/>
```

Shorter variant if the row must stay one line:

```
운영자가 화상으로 신분증을 확인한 러너만 배정돼요 (자동 본인인증은 도입 전)
```

Both are true the moment §7.1 (1)–(4) hold, and both stop implying an automated check. Neither
promises an upgrade date.

**`/runner/apply`, `approved` state — the two `online`-bound variants (§6.2):**

```
인증이 끝났어요
운영자 확인을 마쳤어요 — 이제 요청을 받을 수 있어요

online === true  → 지금 온라인 상태예요 · 요청이 오면 러너 홈에 떠요
online === false → 온라인으로 켜야 요청이 와요 · 러너 홈에서 켤 수 있어요
```

**`/runner/apply`, section ② — the explainer, cut from 5 aspirational steps to the 3 real ones:**

```
01  지원서    활동 지역 · 평균 페이스 · 감당 가능한 견종 크기와 러닝·반려견 경험을 적어요
02  화상 확인  운영자가 화상 통화로 신분증을 확인하고, 러닝과 반려견 경험을 직접 물어봐요
03  승인      승인되면 등급이 인증 러너가 되고 요청을 받기 시작해요

파일럿 기간에는 운영자가 한 명씩 직접 확인해요 — 자동 심사는 없어요
```

**`/runner/apply`, `submitted` / `under_review`:**

```
submitted     지원서가 접수됐어요
              8월 14일에 접수됐어요 · 운영자가 확인하면 적어주신 연락처로 화상 통화 일정을 알려드려요

under_review  운영자가 확인하고 있어요
              적어주신 연락 가능한 시간에 맞춰 연락드릴게요
```

### 7.3 `/runner/home` applicant copy

```
empty inbox (tier === 'applicant'):
  인증 전에는 요청이 오지 않아요
  인증 센터에서 지원할 수 있어요 ›              ← real route to /runner/apply

tier ladder slot (tier === 'applicant'):
  인증 러너가 되면 등급이 시작돼요
```

## 8. Test plan

### 8.1 Harness — new suite `101_runner_funnel_suite.sql`

Wired into `harness.sh` immediately after the `100_wave3_suite.sql` line. Suite tag `'rf'`. Follows
`100_wave3_suite.sql` exactly: a header block listing **the single revert that turns each pin RED**
with ✔ on the ones actually executed; helpers `t_user`/`t_dog`/`t_route` from `10_settle_suite.sql`;
definer paths via `set_config('request.jwt.claim.sub', …)` as `postgres`; real RLS paths via
`set local role authenticated` with an unconditional `reset role` in every exception handler; each
case in its own `begin … exception when others`; fixtures in a `now()`-independent future window;
any seeded booking closed as `expired` so the open pool is not polluted.

| pin | asserts | single revert → RED |
| --- | --- | --- |
| **F1** insert seal | `authenticated` insert of a `runners` row with `tier<>'applicant'` / `commission_rate<>0.33` / `identity_verified=true` / `total_runs>0` raises `runner_protected_columns`; **positive control: the exact column set `ensureRunner` sends succeeds** | drop the INSERT branch from `_guard_runner_cols` |
| **F2** table sealed | as `authenticated`: `select` from `runner_applications` = 0 rows; `insert`/`update state='approved'`/`delete` all fail or affect 0 rows | add any policy to `runner_applications` |
| **F3** submit happy | RPC creates 1 row, `state='submitted'`, `attempt_no=1`; caller's `tier` still `applicant` | drop the insert from the RPC |
| **F4** one active | second `runner_apply_submit` raises `already_applied`; a direct `postgres` insert of a second non-terminal row violates `runner_app_one_active` (proves the index, not just the RPC) | drop the partial unique index |
| **F5** consent gate | any of the three consents false → `consent_required`; row count unchanged | drop the consent checks |
| **F6** oracle | `runner_apply_withdraw` with (a) a random uuid and (b) another user's real application id produce **byte-identical** `sqlerrm`; both are `not_found`; positive control: own row withdraws | move the state gate before the party gate |
| **F7** projection shape | `runner_my_application()` returns exactly the 9 declared columns; runtime key set contains none of `decided_note`, `decided_by`, `contact_phone`, `contact_kakao`, `bio` | add `decided_note` to the returns table |
| **F8** ops revoke | `authenticated` cannot execute `runner_app_review/approve/reject`; **positive control:** `runner_apply_submit` is executable by `authenticated` | `grant execute on function runner_app_approve … to authenticated` |
| **F9** approve effects | tier → `certified`, `identity_verified` → true, storefront payload copied; **`online` unchanged** (test both true and false); **`commission_rate` unchanged at 0.33**; `total_runs` still 0 | add `online = true` to the approve UPDATE |
| **F10** approve idempotent | second `runner_app_approve` returns the same uuid, writes nothing, leaves `decided_at` unchanged; state stays `approved` | remove the early-return branch |
| **F11** gating mirror | the approved runner appears in `available_runners`, `count_available_runners`, `is_active_runner()`, `runners_available_for`; an applicant appears in none. **This pin exists to stop a future refactor from moving the gate off `runners.tier`.** | change any consumer to read `runner_applications` instead of `runners.tier` |
| **F12** reject | empty reason → `runner_app_reject_reason` violation; `reject_reason` surfaces verbatim in the projection; soft reject → attempt 2 allowed; `--hard` → `application_barred` forever; attempt 4 → `attempt_cap_reached`; tier stays `applicant` throughout | drop `runner_app_hard_bar_terminal` / the barred check |
| **F13** definer hygiene | all 6 new functions have `search_path` in `prosrc`; plus an executed `pg_temp` shadowing attempt against `runner_app_approve` that must fail | remove `set search_path` from one function body (`98 H1` also goes red) |
| **F14** shape constraints | direct `postgres` update to an unknown `state` raises; `is_hard_bar=true` with `state='approved'` raises; `decided_at` set on a `submitted` row raises | drop the corresponding check constraint |

**Mutation-verification protocol** (`100_wave3_suite.sql` header, 2026-08-07): for each pin, apply
*only* that revert on top of an undamaged migration, run the **whole** harness, and confirm exactly
one pin goes red and the count drops by exactly one. Restore and confirm the full count returns.
Baseline before this work: **246/0**.

Pins that must stay green and be re-read before touching anything: `99 S4` (runners UPDATE
governance — the sibling of F1), `99 S5` (document verify seal), `98 H1` (schema-wide definer
`search_path` sweep), `98 H6` (17-column shape of `marketplace_open_requests`), `97 V10` (9-column
shape of `runners_available_for`).

### 8.2 Commit gate and e2e

Commit gate, both required: `cd app && ./node_modules/.bin/tsc --noEmit` and
`node scripts/check-rpc-contracts.mjs`.

E2e, on device after Sean's push (he smoke-tests; never claim device-visual success):

1. New account → 러너예요 → `/runner/home`: bib says 러너 (not 인증 러너) while loading; empty inbox
   says 인증 전에는 요청이 오지 않아요 with a working route to 인증 센터.
2. 인증 센터 → 러너 지원서 작성 → submit → screen flips to 접수됨 with the real submitted date and a
   working 지원 취소, **no approval button anywhere**.
3. `node scripts/runner-ops.mjs list` shows the row → `review` → the applicant screen shows 검토 중.
4. Video call → `approve --note "…"` → applicant screen shows 인증이 끝났어요, ① shows 인증 러너, and
   the `online`-bound line matches the runner's actual toggle.
5. Owner account → find-now → **the runner appears in the list** (structurally empty before this
   slice — this is the whole point).
6. The runner accepts an open request → `transition-booking` returns 200 (403 before).
7. Second account: reject with a reason → reason renders verbatim → 다시 지원하기 creates attempt 2.
8. Third account: reject `--hard` → terminal copy, no 다시 지원하기, 문의 routes to `/settings`.
9. Negative: from the runner client, attempt `update runners set tier='master'` and
   `insert into runners (…, tier:'master')` through the SDK — both must fail.

## 9. Build order

| step | artifact | gate |
| --- | --- | --- |
| 1 | `supabase/migrations/0061_runner_apply_seal.sql` | harness green (F1 alone can be pinned here) |
| 2 | `supabase/migrations/0062_runner_applications.sql` | harness green |
| 3 | `supabase/tests/101_runner_funnel_suite.sql` + one line in `harness.sh` | **246 + new pins, 0 fail**, every pin mutation-verified |
| 4 | adversarial review — reviewers **execute** §8.3 | — |
| 5 | `scripts/runner-ops.mjs` | dry-run against the local harness DB |
| 6 | client: `api.ts` fetchers + the two honesty fixes; `apply.tsx` form + states; `runner/home.tsx` applicant states; `safety.tsx:150` copy | `tsc --noEmit` + `check-rpc-contracts.mjs` |
| 7 | commit locally; hand Sean the deploy queue (§10) | — |

### 8.3 Attacks the adversarial reviewer must execute (not consider)

- `insert into runners (profile_id, tier) values (auth.uid(), 'master')` as `authenticated`, from an
  account with no runners row — **the P0 of §1.4**; must now fail.
- Same insert with `commission_rate = 0`, with `identity_verified = true`, with `total_runs = 9999`.
- `update runner_applications set state = 'approved'` as `authenticated` (0 rows).
- `insert into runner_applications (profile_id, state, …) values (auth.uid(), 'approved', …)`.
- Call `runner_app_approve` / `_reject` / `_review` as `authenticated`, and as `anon`.
- Call `runner_apply_withdraw` / `runner_app_approve` with another user's application id; confirm the
  error is indistinguishable from a nonexistent id.
- Submit while an application is `submitted`; while `under_review`; after a hard bar; as an already
  `certified` runner; a 4th attempt.
- Race two `runner_apply_submit` calls on two connections (`90_race_check.sh` precedent) — exactly
  one must win.
- Double-fire `runner_app_approve` — one tier raise, one `decided_at`.
- `pg_temp` shadowing of `runners` / `runner_applications` against each new definer function.
- Read another applicant's projection by any route; confirm `profiles public runner read`
  (`0002:56-58`) still hides applicants after this change.
- Confirm an approved runner appears in all four gating consumers and a rejected one in none.

## 10. Sean's manual ops

**Preconditions before any real owner sees `safety.tsx`:**

```sql
-- Are there runners in production who passed nothing? (seed-runners.mjs plants 6)
select profile_id, tier, total_runs, created_at from runners where tier <> 'applicant';
```
Every row must correspond to an `approved` `runner_applications` row. Seeded rows are deleted or
demoted to `applicant` first — `scripts/wipe-test-data.mjs` clears bookings/runs/ledger but
**keeps runner identity and tier**, so the demotion is a separate explicit statement.

**Deploy queue** (Sean only — `db push`, `functions deploy`, `git push`):

SQL editor / `supabase db push`:
```
supabase db push        # 0061_runner_apply_seal.sql, 0062_runner_applications.sql
```
No `functions deploy` — this slice changes no edge function. `transition-booking:105` keeps its
`applicant` gate unchanged and starts passing on its own once a runner is approved.

**Per-runner loop (22 times):**

1. Recruit per `docs/runner-recruitment.md` §2 (crews first, then 체대/campus clubs). Publish the
   earnings table, never a slogan.
2. Applicant installs the TestFlight build, taps 러너예요, submits the 지원서.
3. `node scripts/runner-ops.mjs list` → `review <id> --by sean` (the applicant now sees 검토 중).
4. Contact them in their stated window; run the video call: **see the ID on camera**, ask the running
   and dog-handling questions, confirm 반포 활동 지역.
5. `approve <id> --by sean --note "video call YYYY-MM-DD, ID checked, <pace/dog notes>"` — **the note
   is what makes the safety copy true; it is required, not optional.** Or
   `reject <id> --by sean --reason "<the sentence the applicant will read verbatim>"`.
6. Tell the approved runner to open 러너 홈 and check that 온라인 is on — approval deliberately does
   not flip it (§3.4), and `fetchCertifiedRunners` (`api.ts:527`) requires `online = true`.
7. Hand over bib / patch, add to the Strava club (`runner-recruitment.md` §2A).
8. Track pass rate off the table — it is the "X% 통과" number the recruitment plan wants to publish:
   `select state, count(*) from runner_applications group by state;`

**Still open, and not this plan's to answer** (spec §8): re-application cooldown numbers beyond the
3-attempt cap (Q5), the veteran/master criteria (Q6), 범죄경력회보서 legal handling (Q4), and the
privacy policy that `consent_privacy` must link to (`launch-checklist.md` §1).
