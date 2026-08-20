# Contract — in-app account deletion (App Store 5.1.1(v) · PIPA 제37조)

> ## ⚠ AS DEPLOYED — 2026-08-20, verified live. Where this file disagrees below, THIS is what shipped.
>
> - **TWELVE state refusal tokens**, not eleven: `club_custody_owner` was split out of `club_custody`
>   (a holder can finish the handoff; an owner whose dog is out cannot, and a refusal must name a remedy
>   its reader can perform). `not_authenticated` is the party gate, returns **401**, and is NOT a state token.
> - **`bank_accounts` is CONDITIONAL, not an unconditional DELETE** (Sean's O-7 "A-intact-when-owed"):
>   deleted only when the runner has no `ledger_items`; kept **INTACT, not anonymised** when they have
>   earnings, on the ledger's retention basis. The RPC reports `bank_kept` (own boolean key, default false).
>   ⚠ §A.2.e, §B.3 and §C.1.b ④ below still describe the unconditional delete — they are superseded here.
>   `unpaid_payout` remains a token but is **knowingly inert**: nothing writes `payouts` (queue §0-duodecies).
> - **Live verification is §E.4, not §E.8** — there is no §E.8 in this contract (the announcer briefed the
>   probe with the wrong section id, copied from the other two contracts; the probe caught it).
> - Verified on production 2026-08-20, 38/38 assertions, five throwaway accounts created and removed, zero
>   collateral: 409 `{"error":"active_booking"}` (one key, bare token) · 400 `confirm_required` · a body-supplied
>   uid IGNORED (the caller was tombstoned, the named victim byte-identical) · happy path tombstone with the
>   auth user GONE and `toss_customer_key` kept · `bank_kept:true` with the row byte-identical (hex-compared,
>   non-ASCII included) and `bank_kept:false` with the row gone · stale JWT → 401 · cleanup verified empty.

**Status: CONTRACT ONLY, REVISION 2 — reviewed adversarially, repaired, cleared to build.**
Nothing is built. Nothing is deployed. No migration file exists yet. Revision 2 applies all 16
findings from the executed review of §C; the verdict, the finding index and the six 🔵 decisions
taken there are in **§H (Review log)** at the end — **read §H before §C** if you are the
implementer, because five of the findings changed what §C says to do.
Written by a read-only scout under Sean's overnight grant, decision **O-6**
(`docs/decisions/awaiting-sean.md` §0-septendecies: *"build it"*), following the same
"contract first, attack it, then build" rule as `docs/contracts/pay-after-run-contract.md`.

**Worktree:** `.claude/worktrees/announcer-v3-handoff-f0774a` at trunk **`b84761d`**.
**Production:** `zjabnywjpvpgmtajygqy`, **SELECT-only**. No edge function was invoked, no row was
written, no `delete` was executed anywhere. Every claim marked **MEASURED** was executed against
production on 2026-08-19/20; **READ** means code-verified only; anything else is labelled inference.

---

## 0. The finding that matters, before anything else

**`profiles.id → auth.users(id) ON DELETE CASCADE` is the single edge that turns
`auth.admin.deleteUser(uid)` into a 33-path cascade through the whole schema** (MEASURED, §A.2).
Along those paths it **silently destroys five classes of record the product is required to keep**:

| Destroyed by cascade | Path | Why it must not be destroyed |
|---|---|---|
| `payment_attempts` | `profiles > dogs > session_dogs > payment_attempts` | **money** — the attempt/idempotency trail behind club charges (`kind`, `idempotency_key`, `result`) |
| `delegation_consents` | `profiles > dogs > session_dogs > delegation_consents` | **consent evidence** — `doc_id`, `doc_version`, `accepted_at`, `photo_consent`, `custody_ack`; also holds a **third party's** `pickup_contact` / `emergency_contact` |
| `dog_custody_events` | `profiles > dogs > session_dogs > dog_custody_events` | **custody chain** — the record of who held the dog when, i.e. the evidence in an incident |
| `gate_code_access_log` | `profiles > addresses > gate_code_access_log` | **access audit log** — the house idiom the privacy policy's §8 안전조치 rests on, and the model the readiness review names for the missing 위치정보 ledger |
| `runner_applications` | `profiles > runner_applications` | **runner consent evidence** — `0062:81-83` makes the three consents `not null check(...)`; §13.2 ③ scores them as the one thing legal got *right* |

Plus one silent mutilation rather than deletion: **`club_fee_items.session_dog_id` is `ON DELETE
SET NULL`** (MEASURED) — the club fee row survives with its subject pointer nulled, which is
worse than either keeping or deleting it, because the row still reads as valid money.

**And in the other direction the same call is unusable anyway**: `bookings.owner_id` is
`NO ACTION`, so `auth.admin.deleteUser()` on any user who has ever booked **aborts the whole
transaction with an opaque FK violation**. MEASURED across all 10 production profiles: exactly
**one** (`0186ede6…`, an e2e leftover) would delete cleanly today; the other nine are blocked or
partially destructive.

So the naive implementation — "call `auth.admin.deleteUser` and let the FKs sort it out" — is
wrong in both directions at once: it refuses for real users and destroys legal records for the
few it accepts. **§C.1's first act is therefore to remove that edge**, which converts every
silent cascade into an explicit, named, reviewable delete list.

⚠ **Second-order consequence, and it must not be missed.** Removing the edge also disarms the one
protection the schema already had: `km_ledger.profile_id` / `km_lots.profile_id` are
`ON DELETE RESTRICT` (MEASURED), placed deliberately by `0075_km_ledger.sql:105` with the comment
*"계정 삭제는 명시적 close-out(잔액 소각 원장 기록) 후에만"*. That RESTRICT fires on **profiles**
deletion. Once `profiles` is no longer deleted, **it never fires again** — so the km close-out gate
must be re-expressed explicitly in the RPC's state gate (§C.1.b) or it is silently lost.

🔴 **Third-order, and it is the finding that the adversarial review actually executed (F1/F2).**
Dropping the `profiles` edge is necessary but **not sufficient**: the same class of defect
reappears one hop down, at `addresses`. The first draft of §C.1.b ④ deleted `addresses`
explicitly — and `gate_code_access_log.address_id references addresses **on delete cascade**`
(`0001_init.sql:132`). The reviewer executed the written delete list in the harness against a
seeded user: **`gate_code_access_log` went 1 row → 0 rows.** The explicit delete list reproduced,
by hand, exactly the destruction §0 exists to prevent. And in the other direction the same
statement aborts: `bookings.address_id` (`0001:170`), `gear_claims.shipped_to` (`0001:333`) and
`recurring_series.address_id` (`0026:18`) are all **NO ACTION** into `addresses`, so the delete
raises `23503` for any user who has ever booked — i.e. for every real user.

🔵 **DECISION: `addresses` is KEEP+ANON, not DELETE.** The row survives with every locating field
redacted (§C.1.b ③). With that one change the reviewer re-executed the full deletion against the
same seeded user and measured a **clean run with an empty row-count diff** on every retention
table. The lesson generalises and is why §D.N6 had to be rewritten as a recursive closure: *the
delete list is itself a cascade source, and it must be closed over the same way the FK graph is.*

---

## A. Measured state

### A.1 What exists today

- **The client has no deletion path.** `app/app/settings.tsx:89` renders
  `<InfoRow label="계정 삭제" value="문의로 처리" />` inside a `준비 중` card at `opacity: 0.55` —
  an honest, inert label under the honesty laws, and exactly the shape App Store Review Guideline
  5.1.1(v) exists to reject. READ.
- **Sign-in is Kakao OAuth only** (`app/app/login.tsx:39-70`, PKCE via `expo-web-browser`; the
  email-OTP door was removed by Sean's 2026-08-15 ruling "b"). ⚠ Note the path: `app/app/login.tsx`,
  **not** `app/app/(auth)/login.tsx`. Server-side, `external_email_enabled` is still `true`
  (`supabase/auth-surface.expected.json:3`) — email OTP is still accepted by the anon key. READ.
- **Sign-out is one line** — `app/src/auth-context.tsx:29`,
  `signOut: async () => { await supabase.auth.signOut(); }`. There is no server-side session
  revocation path anywhere. READ.
- **MEASURED identity mapping:** `auth.identities` holds 10 `email` rows and **1 `kakao`** row,
  one identity per user. `identities.user_id → auth.users` is `ON DELETE CASCADE`, so deleting the
  auth user drops the Kakao link and a re-signup with the same Kakao account **mints a fresh
  `auth.users.id`**. It does not resurrect the old profile. (§D.P5 pins this.)
- **No account-level anonymisation idiom exists.** The only soft-delete in the repo is
  chat-scoped: `0049_session_shell.sql:71,123` —
  `update club_chat_messages set deleted_at = now(), body = null, media_path = null`. That
  null-the-content-keep-the-row shape is the house precedent this contract extends to `profiles`.
  READ.
- **`profiles` has no `deleted_at` column** (MEASURED) — the migration must add one.
- **Only `service_role` can delete a profile.** MEASURED `role_table_grants` on `public.profiles`:
  `service_role: DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE` and **nothing for
  `anon` or `authenticated`** (they hold column-level SELECT/UPDATE only, per `0088`/`0091`).
  There is also **no `DELETE` RLS policy on `profiles`** — the four policies are
  `profiles self read` / `self write` / `self insert` / `public runner read` (MEASURED). A client
  cannot delete its own row by any route, which is why this needs a server component at all.
- **No `DELETE` triggers exist on `profiles`, `dogs`, `addresses`, or `runners`** (MEASURED — the
  only triggers are `touch_updated_at` and the column guards). Nothing blocks or audits a delete.

### A.2 The FK graph from `auth.users` / `profiles` outward

**MEASURED, `pg_constraint` on production.** The full public+storage graph is **142 FK edges**; the
subgraph touching identity is **67 edges** — 9 into `auth.users` (8 internal `auth.*` + `profiles`)
and **58 into `profiles`**. Reachability by CASCADE from `profiles` closes over **33 table-paths**
at depth ≤ 3.

**Legend for "what must happen":** `CASCADE-OK` = correct to destroy · `DELETE` = the RPC deletes
it explicitly · `KEEP` = must survive, row untouched · `KEEP+ANON` = row survives, PII nulled ·
`REFUSE` = presence blocks deletion until resolved.

#### A.2.a — `auth.users` children (9)

| Table | Column | ON DELETE | What must happen |
|---|---|---|---|
| `auth.identities` | `user_id` | CASCADE | CASCADE-OK — drops the Kakao link, frees re-signup |
| `auth.sessions` | `user_id` | CASCADE | CASCADE-OK |
| `auth.mfa_factors` | `user_id` | CASCADE | CASCADE-OK |
| `auth.one_time_tokens` | `user_id` | CASCADE | CASCADE-OK |
| `auth.oauth_authorizations` | `user_id` | CASCADE | CASCADE-OK |
| `auth.oauth_consents` | `user_id` | CASCADE | CASCADE-OK |
| `auth.webauthn_challenges` | `user_id` | CASCADE | CASCADE-OK |
| `auth.webauthn_credentials` | `user_id` | CASCADE | CASCADE-OK |
| **`public.profiles`** | **`id`** | **CASCADE** | 🔴 **MUST BECOME NO-FK** — see §0 and §C.1.a |

#### A.2.b — `profiles` children, the 18 that CASCADE today

| Table | Column | ON DELETE | What must happen | Why |
|---|---|---|---|---|
| `addresses` | `owner_id` | CASCADE | 🔴 **KEEP+ANON** | **was DELETE; F1/F2 changed it.** `gate_code_access_log.address_id` is CASCADE into it (`0001:132`) and `bookings.address_id`/`gear_claims.shipped_to`/`recurring_series.address_id` are NO ACTION into it — deleting destroys the audit log *and* aborts. Redact the locating columns instead (§C.1.b ③) |
| `billing_keys` | `profile_id` | CASCADE | **DELETE** | the stored Toss billing key; deleting it is required, not merely allowed |
| `booking_declines` | `runner_profile_id` | CASCADE | **DELETE** | operational noise |
| `club_acks` | `profile_id` | CASCADE | **KEEP** | acknowledgement evidence (`acked_at`, `escalated_at`) — was a consent record, cascade destroyed it |
| `club_interest` | `profile_id` | CASCADE | **DELETE** | marketing signal |
| `club_members` | `profile_id` | CASCADE | **DELETE** | membership ends with the account |
| `club_test_accounts` | `profile_id` | CASCADE | **DELETE** | a feature-flag allowlist row; see §C.4 |
| `dogs` | `owner_id` | CASCADE | **KEEP+ANON** | 🔴 its cascade is the money/consent path — see A.2.d |
| `emergency_contacts` | `profile_id` | CASCADE | **DELETE** | third-party name+phone; must go |
| `feed_comments` | `author_id` | CASCADE | **DELETE** | user's own UGC |
| `feed_likes` | `profile_id` | CASCADE | **DELETE** | user's own UGC |
| `feed_posts` | `author_id` | CASCADE | **DELETE** | user's own UGC (cascades to its own comments/likes — correct) |
| `ops_recipients` | `profile_id` | CASCADE | **DELETE** | ops routing |
| `owner_la_tokens` | `profile_id` | CASCADE | **DELETE** | APNs Live-Activity device tokens |
| `push_tokens` | `profile_id` | CASCADE | **DELETE** | privacy policy §5 promises push tokens die at 탈퇴 |
| `runner_applications` | `profile_id` | CASCADE | 🔴 **KEEP+ANON** | **consent evidence** — `0062:81-83` `not null check(...)`; §13.2 ③. (F10 upgraded this from bare KEEP: the row also holds a phone number and three free-text essays. Redact those, keep the consents — §C.1.b ③) |
| `runners` | `profile_id` | CASCADE | **KEEP+ANON** | its own NO-ACTION children hold money; see A.2.e |
| `session_people` | `profile_id` | CASCADE | **KEEP** | cascades to `participant_activities` (club-session activity record) |

#### A.2.c — `profiles` children that block or restrict today (40)

`NO ACTION` unless noted. These are the edges that make `auth.admin.deleteUser()` abort.

| Table.column | What must happen |
|---|---|
| `bookings.owner_id` | **KEEP** — 전자상거래법 계약·결제 기록 (privacy policy §5 row 2) |
| `chat_messages.sender_id` | **KEEP+ANON** (author becomes the tombstone; body decided in §C.1.c) |
| `reviews.author_id` | **KEEP+ANON** — the counterparty's rating must survive |
| `notifications.profile_id` | **DELETE** — delivery log, no retention duty |
| `slot_holds.owner_id` | **DELETE** — ephemeral |
| `recurring_series.owner_id` | 🔴 **REFUSE-then-KEEP** (F13; was "REFUSE-then-DELETE", which is not expressible). `0111:192` **revoked insert/update/delete on `recurring_series` from `anon, authenticated`** and re-granted `update (paused)` only — *pause is the only verb that exists*. So the gate is `paused = false` → refuse, and after the user pauses, the row is **kept**, not deleted. It also holds `address_id` into `addresses` (NO ACTION), which is a second reason `addresses` must be KEEP+ANON (F1/F2) |
| `cards_owned.profile_id` | **DELETE** — collectible state |
| `gear_claims.profile_id` | **KEEP** — fulfilment/shipping record |
| `miles_ledger.profile_id` | **KEEP** — points ledger (마일리지) |
| `km_ledger.profile_id` **[RESTRICT]** · `km_lots.profile_id` **[RESTRICT]** · `km_lots.granted_by` | **REFUSE while balance ≠ 0**, then **KEEP** — 0075's close-out; ⚠ RESTRICT stops firing once §C.1.a lands |
| `incidents.reporter_id` | **REFUSE while unresolved**, then KEEP |
| `club_incidents.opened_by` / `.case_owner` · `club_incident_evidence.created_by` | **REFUSE while `resolved_at is null`**, then KEEP |
| `club_fee_items.recipient_profile_id` | **KEEP** — money |
| `club_chat_messages.sender_id` / `.recipient_profile_id` | **KEEP+ANON** |
| `club_phone_access_log.viewer_profile_id` / `.target_profile_id` | **KEEP** — access audit log (`0049:156`) |
| `clubs.host_profile_id` · `club_series.host_profile_id` · `club_sessions.host_profile_id` / `.backup_host_profile_id` / `.original_host_profile_id` | **REFUSE while a future session exists** (§C.1.b), then KEEP |
| `session_dogs.*` (5 cols: `owner_profile_id`, `responsible_profile_id` `0030:83,85`; `current_runner_profile_id`, `custodian_profile_id` `0040:41,45`) · `assignment_events.*` (2) · `dog_custody_events.*` (3) · `dog_run_segments.runner_profile_id` | **KEEP** — custody/assignment evidence. 🔴 **These columns are also a STATE GATE input, not only a retention class** — see `club_custody` in §C.1.b ② (F3) |
| `session_runner_assignments.runner_profile_id` (`0030:95`, → `runners`) | **KEEP** — and a state-gate input: a `committed` assignment on a future session refuses (`club_assignment`, F3) |
| `delegation_consents.owner_profile_id` | **KEEP** — consent evidence |
| `routes.checked_by` / `.verified_runner_id` | **KEEP** — route provenance |
| `booking_declines.runner_profile_id` | (CASCADE, listed above) |

#### A.2.d — the `dogs` sub-cascade (depth 2–3), the money path

MEASURED closure: `profiles > dogs > session_dogs > {assignment_events, delegation_consents,
dog_custody_events, dog_run_segments, payment_attempts}`, plus
`club_fee_items.session_dog_id [SET NULL]`.

`dogs` is itself blocked by `bookings.dog_id`, `delegation_consents.dog_id`,
`participant_activities.dog_id`, `recurring_series.dog_id` (all NO ACTION) — so for a user with
bookings the delete aborts, and **only for a user with club sessions but no direct bookings does
the cascade actually reach `payment_attempts` and fire.** That narrow window is precisely the
dangerous one: it succeeds silently.

#### A.2.e — the `runners` sub-cascade (depth 2)

`profiles > runners > {runner_availability_rules, runner_availability_exceptions,
runner_booking_rules, runner_documents, runner_gear}` — all CASCADE. `runner_documents` is
identity/verification evidence and should be **DELETE**d deliberately, not cascaded, once the
runner's payouts are settled.

`runners` is blocked by `bookings.runner_id`, `ledger_items.runner_id`, `payouts.runner_id`,
`bank_accounts.runner_id`, `drops.runner_id`, `boosts.runner_id`, `slot_holds.runner_id`,
`gate_code_access_log.runner_id`, `session_runner_assignments.runner_profile_id` (all NO ACTION).
**`ledger_items` and `payouts` are the runner's pay record and must be KEEP.** None of this
matters for the delete itself, because `runners` is KEEP+ANON — but two of those children get
verdicts of their own:

- 🔵 **`bank_accounts` — CONDITIONAL (Sean, 2026-08-20, O-7 "A-intact-when-owed"; SUPERSEDES the F9 unconditional DELETE below): deleted ONLY when the runner has no `ledger_items`; when they have earnings the row is KEPT INTACT — not anonymised — on the same retention basis as the ledger, ending when they are paid. The RPC reports it as `bank_kept` in the flat result (default false). NO balance gate: `ledger_items` has no paid marker and `payouts` has zero writers, so "unpaid" is uncomputable and a gate on lifetime earnings could never clear — trapping the runner and re-opening 5.1.1(v); `unpaid_payout` therefore remains a token but is knowingly inert.** Superseded text follows: DELETE (F9), in §C.1.b ④, and only after the `unpaid_payout` gate has
  cleared.** `0001:277-283`: `runner_id` PK → `runners`, `bank text not null`,
  `account_enc text not null`, `holder text not null`, `verified_at`. **No retention duty covers
  it**: 전자상거래법 제6조 keeps the *payout record* (`payouts`, `ledger_items`), and those rows
  are self-contained — none of them joins `bank_accounts` to be meaningful. What it holds is a
  live payment instrument plus a real person's name. It is the runner-side twin of `billing_keys`,
  which nobody hesitated over. **Why not KEEP+ANON:** anonymising it means nulling `account_enc`
  and `holder`, at which point the row is `(runner_id, bank, verified_at)` — a fact of no value to
  anyone, occupying a PK that a re-signup can never reuse anyway (a re-signup mints a new uid,
  §D.P5). ⚠ The reviewer executed this and confirmed **the encrypted secret survives the whole
  written procedure** if it is not named: `account_enc` is opaque to every KEEP/ANON rule in §C.1.b
  ③ because nothing in ③ looks at `bank_accounts` at all. Deleting it is the only thing that
  removes it. Ordering matters: it goes in ④ (after ② proved no payout is outstanding), never
  before the gate.
- **`drops` / `boosts`** — see the 마일리지 ruling at F11 in §C.1.b ②/④.

### A.3 Production census (MEASURED)

`auth.users` **11** · `profiles` **10** (one auth user has no profile) · `bookings` 28 ·
`runs` 9 · `ledger_items` 8 · `payments` 0 · `payment_attempts` 7 · `billing_keys` 0 ·
`km_ledger` 0 · `km_lots` 0 · `gate_code_access_log` 0 · `delegation_consents` 4 ·
`dog_custody_events` 10 · `runner_applications` 0 · `club_test_accounts` **9** ·
`storage.objects` 3 · `chat_messages` 1 · `reviews` 1 · `notifications` 166 · `dogs` 3 ·
`addresses` 1.

Per-profile blocker census (MEASURED): `aa73ce8a…` (`s4kim2025`, Sean) holds **all 28 bookings,
8 ledger_items, 162 notifications** — under the state gate his own account is correctly
undeletable. **Nine of ten profiles are in `club_test_accounts`.** The single non-test row is
`0186ede6…` (`e2e-owner`), and it is the only profile that would delete cleanly today.

### A.4 Storage — two buckets, one path convention, one trap

READ + MEASURED policies.

- **`avatars`** — `public = true` (`0006_avatars.sql:4-6`). Policies: `avatar public read`
  (`using (bucket_id = 'avatars')`, **role `public` — anon reads everything**), and
  insert/update/delete gated on `auth.uid()::text = (storage.foldername(name))[1]`.
  Holds `{uid}/avatar.jpg`, `{uid}/gallery/*`, `{uid}/gear/*`, `{uid}/club-{id}.jpg`
  (`0064_private_media.sql:9-15`).
- **`media`** — `public = false` (`0064:50-52`). Owner writes gated the same way; `media party read`
  (`0064:80-106`) delegates visibility to the referencing row via a `case` on path segment 2.
  Paths: `{uid}/dogs/…`, `{uid}/runs/{bookingId}/…`, `{uid}/chat/{threadId}/…`,
  `{uid}/clubchat/{sessionId}/…`.
- **Owner identification is uniform: every object a user owns lives under `{uid}/`** in both
  buckets. There is no `owner` column dependency. READ, all five client writers, and they are the
  complete set (`grep storage.from` over `app/src/lib/api.ts`):

  | Writer | Path | Bucket |
  |---|---|---|
  | `uploadAvatar` (`api.ts:2115`) | `{uid}/avatar.jpg` | `avatars` |
  | `uploadDogPhoto` (`api.ts:349`) | `{uid}/dogs/{dogId}.jpg` | `media` |
  | `uploadRunPhoto` (`api.ts:1861`) | `{uid}/runs/{bookingId}/{ts}.jpg` | `media` |
  | `sendChatPhoto` (`api.ts:2430`) | `{uid}/chat/{threadId}/{ts}.jpg` | `media` |
  | club chat photo (`api.ts:3228`) | `{uid}/clubchat/{sessionId}/{ts}.jpg` | `media` |

- 🔴 **`{uid}/` is therefore NOT the sweep unit (F5).** Three of those five prefixes are the media
  half of rows this contract **keeps**: `runs/**` hangs off `runs`/`bookings` (KEEP), `chat/**` off
  `chat_messages` (KEEP+ANON, body deliberately not nulled — §C.1.b ③), `clubchat/**` off
  `club_chat_messages` (same). Sweeping `{uid}/%` would leave every one of those rows pointing at
  an object that no longer exists — which is precisely the **SET NULL mutilation §0 condemns**,
  arrived at from the storage side instead of the FK side: a row that still reads as valid
  evidence and silently is not. The sweep set is fixed in §C.1.c step 4 and pinned in §D.P3.
- 🔴 **THE TRAP (MEASURED).** `storage.objects` carries a `BEFORE DELETE STATEMENT` trigger
  `protect_objects_delete → storage.protect_delete()`, whose body is:

      IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
          RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'

  **A definer RPC therefore cannot `delete from storage.objects`** — it raises `42501` even for
  `service_role`. Object removal must go through the **Storage API** from the edge function
  (`admin().storage.from(bucket).remove([...])`). `SELECT` on `storage.objects` is unaffected, so
  enumerating `name like uid || '/%'` in SQL and removing via the API is the workable shape.
- ⚠ `0109_revoke_truncate.sql:273` records that `storage.objects` / `storage.buckets` still grant
  `TRUNCATE/TRIGGER/REFERENCES` to `anon`/`authenticated` (grantor `supabase_storage_admin`,
  unrevocable by migration). Out of scope here; noted so it is not rediscovered as new.

### A.5 The edge-function pattern this must follow

READ, `supabase/functions/_shared/ctx.ts` (53 lines, the whole contract):

    export function admin(): SupabaseClient {
      return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    }

    export async function caller(req: Request, db: SupabaseClient): Promise<string> {
      const jwt = req.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
      const { data, error } = await db.auth.getUser(jwt);
      if (error || !data.user) throw new HttpError(401, "unauthorized");
      return data.user.id;
    }

    export function handle(fn: (req: Request) => Promise<unknown>) { … }

- Every function runs **entirely as service role**; there is **no anon client anywhere**, so RLS
  does not stand behind the code and each function checks ownership by hand
  (`create-booking-hold/handler.ts:82-97`, `403 "forbidden"` with a deliberately identical message
  for "not found" and "not yours" — no enumeration oracle).
- Errors are **stable machine tokens**, not prose (`"runner_id_not_accepted_here"` at
  `handler.ts:61`). This contract's tokens are fixed in §C.1.b.
- **No CORS anywhere** — zero hits for `cors|Access-Control|OPTIONS` across `supabase/functions/`.
  The client is React Native via `functions.invoke`. Do not add CORS.
- Wiring: logic in `handler.ts`, three-line `index.ts`
  (`Deno.serve(handle((req) => fn(req, admin())));`) **so the test can import the handler**.
- Client side, `app/src/lib/api.ts:382-385` is the representative call:

      const { data, error } = await supabase.functions.invoke('create-booking-hold', { body: p });
      if (error || data?.error) throw await fnError(error, data);

  `fnError` (`api.ts:13-23`) recovers the server token from **both** a 200-with-`{error}` and a
  non-2xx `FunctionsHttpError` body. Reuse it unchanged.
- **No edge function currently touches `auth.admin.*`** — that is new surface. Only test/ops
  scripts do (`app/scripts/e2e-party-channels.mjs:72`, `scripts/wipe-test-data.mjs:51`).

### A.6 Numbering (re-resolve before writing the file)

MEASURED against `origin/redesign-v4` **and every remote branch** on 2026-08-20: migrations reach
**0112**, suites reach **147**. Next free = **`0113`**, suite **`148`**. Per CLAUDE.md this is a
snapshot, not a reservation — re-run `git fetch && git ls-tree --name-only origin/redesign-v4
supabase/migrations/ | tail -3` immediately before creating the file, and push the migration and
its REGISTRY row in the same breath.

---

## B. Requirements

### B.1 Apple, App Store Review Guideline 5.1.1(v)

An app that supports account creation must let the user **initiate deletion of the account from
inside the app**. The controlling points, and how each is satisfied here:

| Requirement | This contract |
|---|---|
| Initiation must be **in-app**, not "contact us" | §C.2 — `settings.tsx:89` becomes a live row |
| The control must be **findable** (not buried) | §C.2 — it moves out of the `준비 중` card into the account actions card |
| A **confirmation** step is permitted | §C.2 — a confirm sheet that names what is kept and why |
| Deletion **may take time** to complete | not used — §C.1 completes synchronously |
| It must delete the **account**, not merely deactivate it | §C.1.d — `auth.admin.deleteUser(uid)` is a hard delete; the auth row, all `auth.identities`, and all sessions are gone. The user cannot sign in again, ever, with that account |
| **Legally required records may be retained** if the user is told | §C.2 copy names them; §B.3 lists them with the statute |

**Explicitly declared for the reviewer**: what survives is not the account. It is a **tombstone
row with no credentials, no identity, and no login path**, plus money and consent records the user
is told about. Nothing that survives can be signed into or recovered.

🔴 **Where the real 5.1.1(v) risk actually sits — the adversarial review's framing, kept verbatim
in substance.** The tombstone design **satisfies** the guideline and no finding disturbed that:
`auth.users` is hard-deleted, every `auth.identities` row goes with it, and there is no route back
in. The exposure is not the tombstone's *existence* — it is the tombstone being **visible as the
departed person**. An App Store reviewer who deletes an account and then finds the same avatar in
a runner list, the same handle claimable-but-taken, or the same photo in a chat thread, is looking
at something that reads as deactivation no matter what the database did. **F5, F7 and F8 are all
that risk, from three directions**: F7 keeps the storefront view from listing a tombstoned runner
(and the view, not the policy, is where that must happen — a definer view never consults RLS);
F8 makes the counterparty see **탈퇴한 사용자** rather than a blank or a stale cached name; F5
stops the sweep from deleting the *evidence* media while making sure the *identity* media
(avatar, gallery, dog photos) is actually gone. Each is a compliance surface, not a polish item —
which is why all three are BLOCK and not nice-to-have.

⚠ Apple also expects deletion not to be gated behind an unreasonable obstacle. The state gate in
§C.1.b refuses **only** on states the user can themselves clear (finish or cancel the run, settle
the charge, close the club series) and every refusal returns copy telling them exactly what to do.
A refusal that a user cannot act on would be a rejection risk — §D.N2 pins that every refusal token
has an actionable message.

### B.2 PIPA — 개인정보 보호법 제37조 (처리정지·동의철회) and 제36조 (삭제)

Satisfiable today by the manual support path, per the readiness review's own scoring
(`docs/legal/readiness-review-2026-08-19.md` §6-quinquies ⑥: *"the legal finding here is mild"*).
This build does not create a new PIPA duty — it **honours** the promise the privacy policy already
makes at §7 (*열람·정정·삭제·처리정지 … 회원 탈퇴를 통해 … 철회*) and §5 (`계정 정보 | 회원 탈퇴
시까지`), which today describe a process that does not exist in the app.

제36조 제1항 단서 / 제37조 제2항: deletion may be refused **to the extent another statute requires
retention** — which is the hook §B.3 hangs on, and the reason the confirm sheet must *name* the
retained categories rather than gesture at them.

### B.3 Retention duties that FORBID deletion — what is kept, and under what

| Kept | Statute / source | Cited |
|---|---|---|
| `bookings`, `payments`, `ledger_items`, `payouts`, `club_fee_items`, `gear_claims` | 전자상거래법 제6조 + 시행령 제6조 — 계약·청약철회 5년, 대금결제·재화공급 5년, 소비자불만·분쟁처리 3년 | privacy policy §5 row 2 (`예약·결제·정산 기록 | 관련 법령이 정하는 기간`) |
| `payment_attempts` | same — it is the attempt/idempotency trail behind those charges | §0 |
| `miles_ledger`, `km_ledger`, `km_lots` | the **rows** are kept in every case. ⚠ The **balances** are not symmetric (F11): 마일리지 is non-transferable with no cash-out, so the balance is **forfeit** on deletion and disclosed in the confirm sheet — no gate. `km_lots` carries `won_paid`, *"고객이 이 로트에 실제로 낸 ₩"* (`0075:113`), so `0075:105`'s explicit **close-out** gate stays and is re-expressed as the `km_balance` token (§C.1.b ②) | readiness-nonlocation §12 |
| `delegation_consents`, `club_acks`, `runner_applications` | consent **evidence** — the thing that proves consent was given, at a version, at a time. Deleting the evidence of consent is not honouring a withdrawal of consent | §13.2 ③ |
| `gate_code_access_log`, `club_phone_access_log` | access audit records (privacy policy §8 안전조치) | `0001:130`, `0049:156` |
| `dog_custody_events`, `dog_run_segments`, `assignment_events`, `session_dogs` | custody and duty-of-care evidence in an incident; 제6조2/제11조 exposure per readiness-nonlocation §9 | §A.2.d |
| `incidents`, `club_incidents`, `club_incident_evidence` | dispute record | §A.2.c |
| **위치정보 이용·제공 사실 확인자료 — the ledger that does not exist yet** | 위치정보법 **제16조** (automatic recording duty) + 안전조치 기준 ≥ **6개월** | privacy-policy header note 4; §13.2 ④ |

🔴 **The forward-looking clause, and it is the reason this contract is worth writing now.** The
location access ledger is **absent** (§13.2 ④, MEASURED by the legal audit). When §0-sexdecies (b)
builds it, it will naturally be written as `profile_id uuid references profiles(id)`. **If it is
written `on delete cascade`, this deletion path destroys a record 위치정보법 제16조 requires to be
kept for six months** — exactly the way `gate_code_access_log` is destroyed today. §D.N6 pins the
whole-schema rule so the next ledger cannot land wrong.

⚠ Also unbuilt and interacting: `runs.trace` has **no purge job** (§13.2 ⑤; 위치정보법 시행령
제26조의2 caps 개인위치정보 at one year). Account deletion is **not** that purge — `runs` is
reached only through `bookings`, which is KEEP. This contract deliberately does **not** delete
`runs.trace`; §0-sexdecies (a) owns that, on a TTL, for every run, not only deleted accounts.

### B.4 What the privacy policy must be updated to say

Not a code change, but it lands in the same slice or the app tells a truth the policy contradicts:
§5's `계정 정보 | 회원 탈퇴 시까지` becomes accurate for the first time, and §7's 앱 내 설정 route
becomes real. The retention row needs the concrete 전자상거래법 periods the drafter left as a
placeholder (`privacy-policy.md:116-117`). **That is counsel's call, not ours** — §F.

---

## C. Target end state [REC]

### C.0 Edge function, not RPC alone — and why

**[REC] an edge function `delete-account` that calls a definer `delete_my_account_tx(uid)`.** Not
an RPC alone. The reason is mechanical, not stylistic: **the `auth.users` row can only be removed
by the Auth admin API / service role**, and there is no in-database call for it. A definer RPC can
do the SQL half but cannot finish the job, so a definer-only design would leave a credentialed,
signable-into account behind — which fails 5.1.1(v)'s "delete, not deactivate" limb. Equally,
**an edge-function-only design is wrong**: the SQL half is a dozen writes that must be atomic, and
edge functions have no transaction. Hence the split, which is also the house shape
(`start_run` → `start_run_tx`, pinned at `_test/start_run_test.ts:19-59`: *"Deno writes no runs
row"*).

Division of labour, fixed:

| Step | Where | Why there |
|---|---|---|
| verify JWT → uid | edge fn, `caller(req, db)` | only place with the request |
| state gate + tombstone + explicit deletes | **definer `delete_my_account_tx(uid)`, one transaction** | atomicity; `party gate before state gate` |
| enumerate + remove storage objects | edge fn, Storage API | `storage.protect_delete` forbids SQL deletes (§A.4) |
| `auth.admin.deleteUser(uid)` | edge fn | no in-DB equivalent |
| flat result | edge fn | `handle()` wraps it |

### C.1 Server

#### C.1.a Migration `0113_account_deletion.sql` (number re-resolved per §A.6)

1. **Drop `profiles_id_fkey`.** [REC] This is the load-bearing change and it must be argued in the
   file header, because dropping an FK to `auth.users` looks wrong at a glance:
   - It is what makes the tombstone possible at all. `profiles.id` is the PK and `NOT NULL`, so
     `SET NULL` is impossible and `NO ACTION` would block the auth delete. **Drop is the only
     shape that lets the auth row go while the tombstone stays.**
   - It converts **33 silent cascade paths into zero**, so every deletion becomes an explicit,
     reviewable list in one function — which is the whole finding of §0.
   - Its insert-time integrity is **redundant**: `profiles self insert` is
     `with check (auth.uid() = id)` (MEASURED), so a profile row can only ever be created for a
     live authenticated user. The FK was never the thing enforcing that.
   - ⚠ It **disarms the `km_lots`/`km_ledger` RESTRICT** (§0). The header must say so and point at
     the replacement gate in `delete_my_account_tx`.
   - ⚠ It leaves `dogs`, `addresses`, `runners` etc. still `CASCADE` **from `profiles`** — harmless,
     because the tombstoned profile row is never deleted. Do **not** also drop those.
2. `alter table profiles add column deleted_at timestamptz` (+ a partial index if any read path
   needs it).
2b. 🔴 **Visibility, and the first draft got it backwards (F6/F7/F8).** The draft said
   *"`profiles public runner read` should gain `and p.deleted_at is null`"*. **Do NOT do that.**
   That policy (`0002_rls.sql:56-58`) is the *only* row-visibility route a counterparty has to a
   runner's `profiles` row; adding `deleted_at is null` to it makes the tombstone invisible, and
   §D.N5 — *"a kept review authored by a tombstone renders as 탈퇴한 사용자"* — becomes
   **unreachable, not merely unpinned**. The reviewer executed it: with the clause added, a
   counterparty selecting the review author's profile got **0 rows**, so the client renders a
   blank author, not 탈퇴한 사용자. And the same probe showed the opposite hole in the other
   direction: `available_runners` still listed the tombstoned runner, because the *view* never
   consulted the policy at all — a definer view reads as its owner and RLS never executes
   (0112 §0b, the lesson bought at cost the week before). Two changes, both narrow:

   **(a) Hide the tombstone from the marketplace in the VIEW, not in the policy.**

       -- view law: create or replace ONLY, never DROP — grants are preserved
       -- (0015:41 `grant select on available_runners to authenticated`)
       create or replace view available_runners as
       select r.profile_id, p.name, p.district, p.avatar_url, r.tier, r.bio,
              r.avg_pace_sec_per_km, r.total_runs, r.respond_rate_pct
       from runners r join profiles p on p.id = r.profile_id
       where r.online
         and r.tier <> 'applicant'
         and p.deleted_at is null            -- ← the whole change
         and not exists ( … unchanged busy-runner clause … );

   `online = false` is still set by §C.1.b ③ and is kept **as belt, not as the mechanism** — a
   tombstone must not depend on a mutable boolean the runner-side code also writes. Pinned in
   §D.N5 at the view, with a mutation arm: remove the clause, the pin goes red. ⚠ The same
   question must be asked of `marketplace_open_requests` (0056) — it projects *owners*, not
   runners; §D.N5 pins it too rather than assuming.

   **(b) Add a narrow tombstone read policy so the counterparty can see the name at all.**

       create policy "profiles tombstone read" on profiles for select to authenticated
         using (deleted_at is not null);

   Scope, stated precisely because a policy **cannot** be per-column: what this exposes is the
   intersection of the policy and the existing column grant, and the column grant is the narrow
   half — `grant select (id, name, handle, avatar_url, district) on profiles to authenticated`
   (`0088:135`). So an authenticated caller can read **id, name, handle, avatar_url, district** of
   a tombstone and nothing else; `phone` and `toss_customer_key` are outside the grant and stay
   unreadable (`0088:142-146`). And on a tombstone those five are already
   `('탈퇴한 사용자', null, null, null)` by §C.1.b ③ — **the policy hands out the redaction, which
   is the point.** `anon` gets nothing: it holds no column grant on `profiles` after 0088/0093,
   and the policy is `to authenticated`.

   Net effect, which is what F6-F8 were actually about: a tombstoned **owner** (the author of a
   kept review) and a tombstoned **runner** both render to their counterparty as
   **탈퇴한 사용자** — and neither appears in the storefront.
3. `create table account_deletions` — the ops/access log. Not FK'd to `profiles` (the row must
   outlive everything): `id`, `profile_id uuid not null`, `requested_at`, `completed_at`,
   `auth_deleted boolean`, `counts jsonb` (rows deleted per table), `storage_removed int`,
   `forfeited_miles int`, `forfeited_drops int` (F11), `reason text`. RLS enabled, **zero
   policies** — the `club_test_accounts` ops-only idiom (`0044_r1_hardening.sql:16-21`, named as
   the pattern to copy at `docs/plans/runner-funnel-plan.md:200`).
4. `create or replace function delete_my_account_tx(p_uid uuid) returns jsonb` —
   `security definer`, **`set search_path = public, pg_temp` written in the body** (ALTER-applied
   config is reset by `create or replace`; test 98 H1 watches the whole schema).
   `revoke execute from public, anon, authenticated; grant execute to service_role;` — the edge
   function is the only caller, so `authenticated` must **not** hold it.
5. Suite `148_account_deletion_suite.sql` with the pins from §D.

#### C.1.b `delete_my_account_tx(p_uid uuid)` — order of operations

**Party gate before state gate**, per the standing law:

    -- ① PARTY GATE
    if p_uid is null then raise exception 'not_authenticated'; end if;
    if not exists (select 1 from profiles where id = p_uid) then
        return jsonb_build_object('ok', true, 'already', true);   -- idempotent, no oracle
    end if;
    if exists (select 1 from profiles where id = p_uid and deleted_at is not null) then
        return jsonb_build_object('ok', true, 'already', true);   -- idempotent
    end if;

**② STATE GATE.** Each check raises a **stable token**; the client renders Korean copy keyed on it.
Refuse while any of these hold:

| Token | Condition |
|---|---|
| `active_booking` | a `bookings` row with `owner_id = p_uid` **or** `runner_id = p_uid` whose `status` is in `('draft','quoted','payment_hold','matching','runner_pending','confirmed','runner_enroute','picked_up','active','incident_review','refund_pending')` |
| `active_run` | a `runs` row on such a booking with `ended_at is null` |
| `unsettled_run` | a `runs` row on the user's booking with `ended_at is not null and settled_at is null` |
| `unsettled_payment` | a `payments` row on the user's booking whose `status` is not a terminal success/cancel value |
| `unpaid_payout` | a `payouts` row for `runner_id = p_uid` with `paid_at is null` |
| `km_balance` | `sum(km_lots.km_remaining) > 0` for `p_uid` — **the replacement for the RESTRICT that §C.1.a removes** |
| `open_incident` | `incidents` (reporter or booking party) or `club_incidents` (`opened_by`/`case_owner`) with `resolved_at is null` |
| `active_recurring` | 🔴 **(F13)** a `recurring_series` row with `owner_id = p_uid` **and `paused = false`**. "Still active" was not expressible: `0111:192` revoked client delete, `0111:193` granted `update (paused)` only, so `paused` **is** the definition and pausing **is** the remedy the copy must name. The row is then **KEPT** |
| `club_host_duty` | 🔵 **(F3, widened)** `clubs.host_profile_id` · `club_series.host_profile_id` · `club_sessions.host_profile_id` **· `club_sessions.backup_host_profile_id` · `club_sessions.original_host_profile_id`** on a session not yet ended. The last two were listed in §A.2.c as KEEP columns and silently dropped from the gate — a backup host is a person the session is *relying on*, and an original host is who the escalation path falls back to |
| 🔴 `club_custody` | **(F3, NEW — the one that was executed)** a `session_dogs` row where `p_uid` is `responsible_profile_id` (`0030:85`) **or** `custodian_profile_id` (`0040:45`) **or** `current_runner_profile_id` (`0040:41`), and `checked_out_at is null` (`0030:89`) |
| 🔴 `club_assignment` | **(F3, NEW)** a `session_runner_assignments` row with `runner_profile_id = p_uid` and `status = 'committed'` (`0030:95-97`) joined to a `club_sessions` row with `scheduled_at > now()` and `status in ('open','full')` |

🔴 **Why F3 is a BLOCK and not a nice-to-have.** The reviewer seeded a runner who was **holding
another owner's dog at that moment** — `session_dogs.custody = 'runner_delegated'`,
`responsible_profile_id` = the runner, `checked_in_at` set, `checked_out_at is null` — and ran the
gate as written. **All nine tokens passed.** The account deleted, the session_dogs row survived
(correctly, it is custody evidence), and the responsible party for a live dog became a tombstone
with no push token and no phone. Every existing arm was booking-shaped or money-shaped; the club
path has custody without a `bookings` row (`session_dogs.booking_id` is nullable — `0030:86`,
*"위탁견만"*), so nothing in the booking family could ever have caught it. This is the same
failure mode as §0 one layer up: the gate enumerated the paths someone remembered.

⚠ **No 마일리지 gate — 🔵 DECISION (F11), and the asymmetry with `km_balance` is deliberate.**
There is **no** `miles_balance` token and none should be added. 마일리지 (`miles_ledger`,
`0001:299-306`) is a **non-transferable promotional balance with no cash-out path** — nothing in
the product converts 하이 포인트 to money, so forfeiting it on departure creates no 잔여 재산 to
settle and no 환급 duty. Deletion therefore **forfeits** the miles balance and any **unopened**
`drops`/`boosts`, and the counts go into `account_deletions` (`forfeited_miles`,
`forfeited_drops`) so a support question has an answer. The user is told before, not after — the
confirm sheet carries *"하이 포인트와 미개봉 드롭은 소멸해요"* (§C.2 ②).

**`km_balance` keeps its gate for the opposite reason, and the difference is one column.**
`km_lots.bucket in ('paid','granted')` with **`won_paid` — "고객이 이 로트에 실제로 낸 ₩"**
(`0075:113`). A `paid` lot is **money the customer handed us that we have not yet delivered
against**; `0075:105` requires an explicit close-out (잔액 소각 원장 기록) before the account
goes, and that requirement long predates this contract. Miles are issued *by us, for free*; km is
*bought from us, with cash*. Forfeiting the first is a product rule; forfeiting the second would
be keeping someone's money. Stated here so the asymmetry reads as a decision and not as an
oversight in either direction.

⚠ Anonymous callers cannot reach this function at all (no `anon` grant, and the edge function 401s
first) — §D.N3 pins both arms.

**③ ANONYMISE (tombstone).** `profiles.name` is **`NOT NULL`** (MEASURED) so it cannot be nulled:

    update profiles set
      name       = '탈퇴한 사용자',
      handle     = null,      -- frees the handle: profiles_handle_lower_uniq is partial, WHERE handle IS NOT NULL (MEASURED)
      phone      = null,
      avatar_url = null,
      district   = null,
      deleted_at = now()
    where id = p_uid;

`toss_customer_key` is `NOT NULL` **and uniquely indexed** (MEASURED) — **keep it**. It is a random
uuid, pseudonymous on its own, and it is the join to the Toss-side record behind kept `payments`.
`role` is kept (it is `owner`|`runner`, no privilege derives from it — `0091:51`).

Then anonymise the authored rows that must survive:
- `runners` → null `bio`, `photos = '{}'`, `online = false`, `tier` left alone (a tombstoned
  runner must stop appearing — handled by §D.N4's `deleted_at is null` on the read path, not by
  mutating tier, which would corrupt historical `is_active_runner()` reasoning).
- `chat_messages.sender_id` and `club_chat_messages.sender_id`: **[REC] keep the row, keep the
  author pointer (it now points at the tombstone), do NOT null the body.** The counterparty's
  thread must stay readable and a chat log is dispute evidence per privacy policy §2
  (`안전·분쟁 대응`). This is the same call `0049:123` made in the other direction for a
  *user-initiated* message delete, and the distinction is deliberate: deleting one's own message is
  a content act; leaving an account is not a licence to redact the other party's conversation.
  🔵 **Product call under the grant.** If counsel disagrees, the alternative is `body = null` and
  `media_path = null` on the departing user's own messages only — one line, and §D.N5 pins that the
  thread still renders either way.
- `reviews.author_id`: **keep the row and the pointer.** The rating belongs to the *subject*, not
  the author; nulling it would let a user erase a runner's history by leaving. The author renders
  as `탈퇴한 사용자` through the tombstone — **which only works because of §C.1.a 2b(b)**; without
  the tombstone read policy the author row is invisible to the counterparty and the review renders
  blank. 🔵 Same class of call.

🔴 **`addresses` — KEEP+ANON, written out (F1/F2).** This is the statement that replaces the
`delete from addresses` the reviewer executed and measured destroying `gate_code_access_log`.
Columns are the real ones, from `0001_init.sql:117-128` plus `0065`:

    update addresses set
      label         = '삭제된 주소',   -- NOT NULL (0001:120) — cannot be nulled, must be replaced
      addr          = '삭제된 주소',   -- NOT NULL (0001:121) — same
      detail        = null,            -- the pickup note, 0073's one editable column
      gate_code_enc = null,            -- the encrypted door code — the point of the exercise
      lat           = null,
      lng           = null,            -- both, together: `addresses_latlng_shape` (0065:28-32) is
                                       -- `(lat is null) = (lng is null)`, so a half-pair is a
                                       -- constraint violation, not a silent half-redaction
      is_default    = false
    where owner_id = p_uid;

`id`, `owner_id` and `created_at` are kept — they are what `gate_code_access_log.address_id`,
`bookings.address_id`, `gear_claims.shipped_to` and `recurring_series.address_id` point at. **After
this statement the row locates nothing and identifies nobody**, and the audit log that says *who
opened this door and when* still resolves — which is exactly what 위치정보 and 안전조치 need it to
do. ⚠ Note `label`/`addr` are `NOT NULL`, so "null the address" is not implementable as written
anywhere; the placeholder is load-bearing and must be a constant, never the old value.

🔴 **`dogs` — KEEP+ANON, written out (F16).** `dogs` stays because deleting it is the path to
`payment_attempts` (§A.2.d). The decision on each column, from `0001:37-54` + `0010:2` + `0033:6`:

    update dogs set
      photo_url = null,   -- 0010:2 — the photo, and the object it names is swept (§C.1.c step 4)
      memo      = null,   -- 0001:45 "러너에게 전달되는 성향 메모" — free text, may name people,
                          --   places, a vet, a household routine. The one true PII field here
      photos    = '{}'    -- if present on this tree; the array form of the same thing
    where owner_id = p_uid;

🔵 **`name` is KEPT, deliberately, and not replaced with a placeholder.** A kept `bookings` row is
a 전자상거래법 계약 record whose subject is *this dog*; `'탈퇴한 사용자의 반려견'` on every dog of
a multi-dog owner collapses three distinct contracts into one indistinguishable string, and the
counterparty runner's own history ("나비 3회") becomes unreadable. A dog's given name is weak
personal data about an animal, not about the departing human — and the human it *could* identify
is already a tombstone. `breed`, `birth_date`, `weight_kg`, `neutered`, `vaccinations`,
`cumulative_km`, `fitness_age` are kept: they are the duty-of-care facts an incident review reads.
`collar` (`0033:6`) is kept — it is a colour, not an identifier.

🔴 **`runner_applications` — KEEP+ANON (F10), and the schema forces the shape.** The verdict in
§A.2.b said KEEP with no redaction, which leaves a phone number and three free-text essays sitting
in a table nobody thinks of as PII. Redact the contact and narrative fields, keep the evidence:

    update runner_applications set
      contact_phone      = null,
      contact_window     = null,
      contact_kakao      = '[탈퇴]',                 -- ⚠ NOT null — see below
      bio                = '탈퇴로 삭제된 항목입니다',   -- ⚠ NOT null — see below
      running_experience = '탈퇴로 삭제된 항목입니다',
      dog_experience     = '탈퇴로 삭제된 항목입니다'
    where profile_id = p_uid;

⚠ **"null them" is not implementable and the file must say why**, or the first implementer will
write `= null` and hit a constraint at 3am. `0062:70-72`: `bio`, `running_experience` and
`dog_experience` are each `text NOT NULL check (char_length(btrim(…)) between 10 and …)` — a null
fails the NOT NULL and a short placeholder fails the CHECK, so the replacement string must be
**≥ 10 characters after btrim** (the one above is 13). And `0062:96-97`,
`constraint runner_app_contact_present check (coalesce(btrim(contact_kakao), btrim(contact_phone),
'') <> '')` — **nulling both contacts violates it**, so exactly one must survive as a non-empty
non-identifying constant. `contact_kakao` carries the placeholder because a redacted phone column
that still matches `^01[0-9]{8,9}$` would be worse than useless. The alternative — relaxing the
constraint in `0113` — is deliberately **not** taken: the constraint is right for live
applications, and account deletion should not weaken a check for everyone to serve one row.

**KEPT on that row, and this is the whole reason it is KEEP+ANON rather than DELETE:**
`consent_terms`, `consent_privacy`, `consent_id_check` (`0062:81-83`, each `not null check(…)` —
they cannot be false), `created_at`/`updated_at`/`reviewed_at`/`decided_at`, `state`,
`attempt_no`, `decided_by`, `decided_note`, `reject_reason`, `is_hard_bar`, and the operational
payload (`district`, `avg_pace_sec_per_km`, `max_dog_weight_kg`, `service_radius_km`,
`specialties`). That set is the **consent evidence §13.2 ③ scores as the one thing legal got
right**: *which* consents, at *what* time, in *what* state. Redacting the narrative does not touch
it.

**④ DELETE the rows that may go**, child-first (reuse the `scripts/wipe-test-data.mjs:43-49`
ordering discipline — that list is the house precedent for FK-safe ordering, and this function's
list is the same idea narrowed to one user):

    notifications, push_tokens, owner_la_tokens, slot_holds, booking_declines,
    feed_likes, feed_comments, feed_posts, cards_owned,
    emergency_contacts, billing_keys, bank_accounts,
    boosts, drops (opened_at is null only),
    club_interest, club_members, club_test_accounts, ops_recipients,
    runner_documents, runner_gear, runner_availability_exceptions,
    runner_availability_rules, runner_booking_rules

**Three changes from the first draft, all of them findings:**

- 🔴 **`addresses` is GONE from this list (F1/F2).** It is KEEP+ANON, redacted in ③. Deleting it
  destroyed `gate_code_access_log` (CASCADE, `0001:132`) — executed, 1 row → 0 — and aborted with
  `23503` for any user with a booking, a gear claim or a series (`0001:170`, `0001:333`,
  `0026:18`). With it removed and ③'s redaction in place, the reviewer re-executed the whole
  procedure and measured **an empty row-count diff across every retention table**.
- 🔵 **`bank_accounts` is ADDED (F9)** — the runner-side payment instrument plus a real holder
  name; `account_enc` survives every rule in ③ because nothing in ③ looks at the table. Rationale
  and the "why not KEEP+ANON" argument are in §A.2.e. **Ordering: strictly after ②'s
  `unpaid_payout` arm has passed** — the account may not shed its payout destination while a
  payout is owed to it.
- 🔵 **`boosts` and unopened `drops` are ADDED (F11)** — the forfeit half of the 마일리지 ruling.
  `boosts` (`0001:319-324`) is a time-boxed visibility window and means nothing without a live
  runner. `drops` are deleted **only where `opened_at is null`** (`0001:315`): an unopened drop is
  a thing that never happened, while an **opened** drop is kept because its `contents` is the
  explanation of a `miles_ledger` credit, and an unexplained ledger entry is worse than a kept
  one. Count the deleted unopened drops into `account_deletions.forfeited_drops`.

**Not in the list, and each for a stated reason:** `dogs` is KEEP+ANON (deleting it reaches
`payment_attempts`, §A.2.d, and a kept `booking` pointing at a vanished dog is an orphan the
marketplace views would have to special-case) · `addresses` KEEP+ANON (above) ·
`runner_applications` KEEP+ANON (③) · `miles_ledger` KEEP (the ledger survives; the *balance* is
forfeit — a forfeit is a fact about a balance, not a licence to erase the ledger that proves it).

**⑤ LOG** into `account_deletions` with per-table counts plus `forfeited_miles` (the 마일리지
balance at deletion, `sum(delta)` over `miles_ledger` for `p_uid`) and `forfeited_drops`, then
`return jsonb_build_object('ok', true, 'deleted', <counts>, 'kept', <categories>, 'forfeited',
<{miles, drops}>)` — **flat, whitelisted, no row contents**. ⚠ `account_deletions.auth_deleted` is
**not** written here — the transaction cannot know whether the auth delete will succeed; the edge
function owns that column (§C.1.c step 5, F15).

#### C.1.c `supabase/functions/delete-account/{index.ts,handler.ts}`

    // index.ts — three lines, so the test can import the handler
    Deno.serve(handle((req) => deleteAccount(req, admin())));

`handler.ts`:
1. `const uid = await caller(req, db);` → 401 `unauthorized` on a bad/absent JWT.
2. Require an explicit body acknowledgement — `{ confirm: "DELETE" }` — else
   `HttpError(400, "confirm_required")`. A stray invoke must not delete an account.
3. `db.rpc("delete_my_account_tx", { p_uid: uid })`. Any raised token surfaces as
   `HttpError(409, <token>)` so the client can key copy on it.
4. **Only if the RPC succeeded**: enumerate storage and remove **only the deletable prefixes**
   (Storage API, never SQL — §A.4). 🔴 **F5 — `{uid}/%` is the wrong pattern.** The sweep set:

   | Sweep | Bucket | Why |
   |---|---|---|
   | `{uid}/avatar.jpg` | `avatars` | profile photo; `avatar_url` is nulled in ③ |
   | `{uid}/gallery/**` | `avatars` | owner gallery (`0064:9-15`) |
   | `{uid}/gear/**` | `avatars` | gear photos |
   | `{uid}/dogs/**` | `media` | dog photos; `dogs.photo_url` is nulled in ③ |

   | **EXCLUDED** | Bucket | Why it must survive |
   |---|---|---|
   | `{uid}/runs/**` | `media` | run evidence hanging off KEEP `runs`/`bookings` |
   | `{uid}/chat/**` | `media` | `chat_messages.media_path` — KEEP, body deliberately not nulled |
   | `{uid}/clubchat/**` | `media` | `club_chat_messages.media_path` — same |

   Removing an excluded prefix would leave a kept row pointing at an object that is gone: a
   message that renders as a broken image, a run whose photos 404. That is the **SET NULL
   mutilation §0 condemns**, reached from the storage side — the row still reads as valid evidence
   and is not. Enumerate with `select name from storage.objects where bucket_id = ? and name like
   ?` once per pattern (`SELECT` on `storage.objects` is unaffected by `protect_delete`), then
   `db.storage.from(bucket).remove(batch)` in chunks. Failure here is **logged and reported, not
   fatal**: the account must still be deleted, and leftovers are swept by a follow-up. Report the
   count in the result. Pinned by §D.P3, which now has **two arms — a negative and a positive.**
5. `await db.auth.admin.deleteUser(uid)` — hard delete (no `shouldSoftDelete`).
   **Then, and only here, write `account_deletions.auth_deleted`** — `true` on success, `false` on
   failure, returning **202 `auth_delete_pending`** (⚠ AS BUILT: the implementation uses 202/`auth_delete_pending`, not the 500/`auth_delete_failed` this contract first specified — nothing FAILED, the data is redacted as promised and the retry UI renders "pending". **There is ONE token; ui2 keys its copy on `auth_delete_pending`.**). 🔴 **F15 moved this out of the RPC.** The
   transaction in §C.1.b commits before the auth call is even attempted, so a column it wrote
   would be a claim about the future; the edge function is the only place that knows the answer.
   The client must never be told the account is gone while the credential still exists.

   🔴 **The retry path, which the first draft left undefined (F15).** `auth_delete_pending` (as built; see above) is a
   **real, reachable, durable state**, not an error message: the profile is already tombstoned and
   the transaction already committed, so the user is left with a redacted account they can still
   sign into. It needs a UI, and ui2 owns it:
   - Copy: **"탈퇴 처리 중 — 잠시 후 다시 시도해주세요."** Not "실패했어요" (their data *is*
     redacted; nothing was lost) and not a success screen (the credential lives).
   - **The row stays tombstoned.** No rollback, no un-anonymise. `deleted_at` stays set.
   - The button **retries the auth delete only** — a second invoke hits §C.1.b ①'s
     `already: true` short-circuit, skips the whole SQL half, and goes straight to step 5. This is
     why the idempotent short-circuit is load-bearing rather than defensive.
   - **Sweeper for stuck rows: 🔵 there is none, and that is a decision.** A row with
     `completed_at not null and auth_deleted = false` is a live credential on a redacted account —
     it must not sit unnoticed. But a cron is new surface (a scheduled function, its own auth, its
     own failure mode) for a pilot with 10 accounts, and a cron that calls
     `auth.admin.deleteUser` on a table-driven list is the most dangerous job in the repo. For the
     pilot: an **ops script**, `app/scripts/sweep-stuck-deletions.mjs`, in the
     `e2e-party-channels.mjs` shape — lists the stuck rows, requires an explicit uid argument to
     act on one, gated behind `E2E_ALLOW_REMOTE`-style opt-in. Run by hand when the row appears.
     **Revisit at real scale**, exactly like the grace period (§C.2). Recorded so the absence is a
     decision, not an omission.
6. `return { ok: true, deleted: …, storage_removed: n, forfeited: {miles, drops}, kept: [...] }`
   — flat.
7. **Idempotent**: a second call 401s (the JWT is dead) or, with a still-valid cached JWT, hits the
   `already: true` short-circuit. Never a 500.
8. **No CORS** (§A.5).

### C.2 Client (ui2)

**Do not start before §E.1–E.2 are deployed.** Owned by ui2, not by this scout.

1. `app/app/settings.tsx:89` — the `계정 삭제 | 문의로 처리` InfoRow **leaves the `준비 중` card**
   and becomes a real `Pressable` action row in the actions card, styled like 로그아웃
   (`color: '#d84a2f'`). The `준비 중` card keeps `알림 설정` only.
2. **Confirm sheet** — a real sheet, not `Alert.alert`, because it has to carry copy. It must state,
   in this order: (a) this is irreversible and you cannot sign back in; (b) **what is deleted**
   (프로필, 강아지 사진, 주소, 결제수단, 알림, 피드 글); (c) 🔵 **what is forfeited** —
   *"하이 포인트와 미개봉 드롭은 소멸해요."* (F11: no gate, so the disclosure **is** the
   protection — this line is not optional copy, it is the reason the gate can be absent);
   (d) **what is kept and why** — *"예약·결제·정산 기록은 전자상거래법에 따라 보관돼요. 이름은
   '탈퇴한 사용자'로 바뀌고 연락처·사진은 지워져요."*; (e) a typed or held confirmation, then the
   destructive button. ⚠ (c) must sit **above** the confirmation control, not below it.
3. **Refusal states are first-class.** Every `409` token gets Korean copy that says what to do
   (`active_booking` → *"진행 중인 예약이 있어요. 예약을 마치거나 취소한 뒤 다시 시도해주세요."*;
   `active_recurring` → *"정기 러닝이 켜져 있어요. 정기 러닝을 일시정지한 뒤 다시 시도해주세요."*
   — **pause, not cancel**, per F13/`0111:193`; `club_custody` → *"지금 맡고 있는 강아지가 있어요.
   인계를 마친 뒤 다시 시도해주세요."*; `club_assignment` → *"확정된 클럽 러닝 배정이 있어요.
   배정을 철회한 뒤 다시 시도해주세요."*). Under the honesty laws a refusal is shown as a refusal
   — **no silent catch, no happy UI**. **TWELVE tokens, twelve copy entries** (⚠ AS BUILT: `club_custody_owner` was split out of `club_custody` — a runner holding a dog can finish the handoff, an owner whose dog is out cannot, and a refusal must name a remedy its reader can perform; the client renders by token and encodes no count) (§D.N2 pins the set
   equality, and F3 added two of them).
3b. 🔴 **`auth_delete_pending` is a screen, not a toast (F15).** ⚠ AS BUILT: **HTTP 202, token `auth_delete_pending`** — there is ONE token (the "500 `auth_delete_failed`" this section first specified was superseded; see :777 and the handler). A 202 with that token means the
   data is already redacted and the credential is not yet gone. Render
   **"탈퇴 처리 중 — 잠시 후 다시 시도해주세요."**, keep the user signed in (the JWT is still
   needed for the retry), and offer one button that re-invokes `delete-account` — which
   short-circuits past the SQL half and retries only the auth delete. Do **not** show the success
   flow, do **not** sign out, and do **not** offer to "undo": there is no un-tombstone path and
   promising one would be a lie. This is the only state in the feature where the user sees their
   own account after it has been redacted.
4. On success: `await signOut()` then `router.dismissTo('/login')` — mirroring the existing
   로그아웃 handler at `settings.tsx:66-71`. Sign-out **after**, never before (the JWT is needed).
5. Loading is a real pending state, not `0`. The call takes seconds.
6. Reuse `fnError` (`api.ts:13-23`) unchanged so the token survives both error shapes.

**Grace period — 🔵 decided under the grant: NO grace period. Immediate deletion.** Apple permits a
clearly-communicated delay, so this is a product call, not a compliance one. For the pilot,
immediate wins on three grounds: (a) a 14-day window means the auth row survives, so
"deactivated, not deleted" becomes an argument with a reviewer we do not need to have; (b) it needs
a cron, a reversal path, a "you are pending deletion" state in every screen, and a re-login story —
all new surface for a product with 10 accounts; (c) it contradicts the confirm-sheet copy above,
which is stronger for being unqualified. **Revisit at real scale**, where accidental deletion has a
cost. Recorded so the absence is a decision, not an omission.

### C.3 What is NOT touched

- **Club money**: `club_fee_items`, `payouts`, `ledger_items`, `payments` — read by the state gate,
  never written. ⚠ **`bank_accounts` is NO LONGER on this list (F9)** — it is deleted in §C.1.b ④
  after `unpaid_payout` clears. It was never money *record*, it was a payment *instrument*; the
  first draft filed it with the ledgers by association and that is how `account_enc` survived the
  whole procedure in the reviewer's run.
- **Settle**: `settle_run_tx`, `settle-run`, `collect-charges`, `confirm-payment` are untouched.
  The state gate *refuses* while settle is pending rather than racing it.
- **`runs` and `runs.trace`** — kept. The location TTL is §0-sexdecies (a)'s job, on every run.
- **`bookings`** — no column is written. Not `status`, not anything. (`_guard_booking_cols` would
  not fire for a definer, which is exactly why the rule has to be stated rather than relied upon.)
- **The frozen surfaces**: meetup stage machine, polling, `confirmHandoff`; owner-home/fitness
  collapsing heroes. Untouched.
- **`is_active_runner()` / `runners.tier`** — not mutated (§C.1.b ③).

### C.4 `club_test_accounts` and the PR-0 test owner

- **`club_test_accounts` rows must be deleted with the account** (they cascade today; §C.1.b ④
  makes it explicit). The row is a feature-flag allowlist consumed by `_club_require_v2()`
  (`0044:23-30`), not a record of anything. Leaving it would grant club-v2 to a tombstone.
- **The PR-0 test owner must NOT be special-cased, and must NOT be blocked by name.** It is
  `aa73ce8a…` = `s4kim2025` = **Sean's own account** (`docs/handoff-client.md:223`), holder of all
  28 bookings and 8 ledger_items. **The state gate already refuses it** on `active_booking` /
  `unsettled_*` — which is the correct answer arrived at by the general rule. Adding a
  `club_test_accounts`-based exemption would be a rule nobody can see, and would mean the one
  account most likely to be used to test the feature is the one account that behaves differently.
  🔵 **Decision under the grant: no special case.** If Sean wants to test the happy path, the
  e2e probe (§E.4) mints a throwaway user; that is what it is for.
- **The 9 test profiles are the deletion feature's own test fixtures** — do not clean them up as
  part of this slice.

---

## D. Attack pins

Suite `148_account_deletion_suite.sql` (number per §A.6). Every pin **mutation-verified**: break
the implementation, watch the pin go red, restore.

⚠ **This whole section was re-derived after the review, not patched.** The reviewer's instruction
was explicit: re-run the pin list against the repaired N6. Every pin below now names the corrected
table sets — `addresses` KEEP+ANON not DELETE (F1/F2), `bank_accounts` in the delete list (F9),
eleven state-gate tokens not nine (F3), four storage prefixes not `{uid}/%` (F5), and the
view+policy split for visibility (F7/F8). A pin that still asserted the old sets would be green on
a wrong implementation, which is the failure mode N6 itself was written against.

### Negative — these must be refused

- **N1 — A cannot delete B.** Call `delete_my_account_tx(B)` while `request.jwt.claim.sub` is A;
  and invoke the edge function with A's JWT and a body naming B. **The uid must come only from
  `caller()` — never from the body.** Pin that the function takes no user id parameter from the
  request at all.
- **N2 — every state-gate arm refuses, and every refusal is actionable. ELEVEN arms, not nine.**
  One per token in §C.1.b ②: `active_booking` (each of the 11 statuses), `active_run`,
  `unsettled_run`, `unsettled_payment`, `unpaid_payout`, `km_balance`, `open_incident`,
  `active_recurring`, `club_host_duty`, **`club_custody`**, **`club_custody_owner`**, **`club_assignment`**. Plus a pin that
  the token set in the SQL and the copy map in the client are the **same set** — a token with no
  copy is a dead-end refusal and an Apple rejection risk (§B.1).
  - **N2-a (F13):** the `active_recurring` arm must seed `paused = false` and assert that setting
    `paused = true` clears it — pinning that **pause is the remedy**, because delete is not a verb
    the client holds (`0111:192-193`). A mutation that gates on some other "active" notion goes red.
  - **N2-b (F3), and this is the arm the review was bought with:** seed a runner **currently
    holding another owner's dog** — `session_dogs` with `custody = 'runner_delegated'`,
    `responsible_profile_id` = the runner, `checked_in_at` set, `checked_out_at is null` — and
    assert `club_custody`. The reviewer executed the nine-token gate against exactly this fixture
    and **all nine passed**; the account deleted while the dog was out. Mutation-verify by
    setting `checked_out_at` and watching the deletion proceed.
  - **N2-c (F3):** a `session_runner_assignments` row `status = 'committed'` on a `club_sessions`
    row with `scheduled_at > now()` → `club_assignment`; a `withdrawn` row, or a past session,
    does not refuse.
  - **N2-d (F3):** `club_host_duty` fires on **`backup_host_profile_id`** and on
    **`original_host_profile_id`**, not only `host_profile_id` — two separate arms, because a
    single-column implementation passes a single-column pin.
  - **N2-e (F11) — the negative that guards a decision rather than a bug:** assert there is **no**
    `miles_balance` token and that a user with a positive 마일리지 balance **deletes successfully**.
    Forfeiture is the ruling; a future well-meaning "surely we should block on points too" turns
    this red and has to argue with §C.1.b ②'s asymmetry paragraph instead of quietly landing.
- **N3 — `anon` is refused twice.** (a) `set local role anon; select delete_my_account_tx(…)` →
  permission denied on the *function* (no grant). (b) `functions.invoke('delete-account')` with no
  Authorization header → `401 unauthorized`. Both arms, because §A.5 shows a read path can be
  closed by something other than the wall you are looking at.
- **N4 — no definer breaks on a tombstone.** After tombstoning a profile, **execute** every
  security-definer function that joins `profiles`. 🔴 **The list in the first draft was wrong in
  two ways (F12)** — it said *"the four `_owner_la_*` triggers"* and there are **three**
  (`_owner_la_booking_tg` `0063:320`, `_owner_la_run_end_tg` `0083:1245`, `_owner_la_trace_tg`
  `0063:272`; the fourth name was a miscount of the helper functions `_owner_la_push`,
  `_owner_la_trace_km`, `_owner_la_fmt_*`, `_owner_la_window_pace`, `_owner_la_pace_state`, none
  of which touch `profiles`), and it **omitted `notify_chat_message`** entirely. Corrected list:
  `_club_delegation_board_impl`, `club_demand_board`, `club_overview`, `club_session_detail`,
  `club_session_roster`, `incident_contact`, `leaderboard_runners_weekly`, `runner_app_approve`,
  `runners_available_for`, `session_proposal_respond`, `session_propose_dog`, `set_my_handle`,
  `owner_la_sweep_stale`, **`notify_chat_message`**, and the **three** `_owner_la_*` triggers via
  their triggering writes. Pin: none raises, none returns null-name garbage.
  - **N4-a (F12) — `notify_chat_message` gets its own arm and its own assertion.** It is a
    definer trigger on `chat_messages` (`0090:42-106`) that does
    `select p.name into v_name from profiles p where p.id = new.sender_id` and then writes
    `coalesce(v_name, '상대방') || '님이 메시지를 보냈어요'` into `notifications.body`. It is
    reachable *after* deletion because the tombstoned user's thread stays open and the
    counterparty keeps writing into it — and because `profiles.name` is NOT NULL and is set to
    `'탈퇴한 사용자'`, the `coalesce` never fires and the correct push is
    **"탈퇴한 사용자님이 메시지를 보냈어요"**. Pin that string exactly. It degrades gracefully by
    construction rather than by luck, and pinning it is what stops a future "null the name"
    refactor from silently producing `'상대방님이…'` or a null-concat.
- **N5 — the counterparty is unharmed, and the tombstone is visible-but-redacted (F7/F8).** Four
  arms, because the reviewer's execution showed the first draft failed two of them in opposite
  directions:
  - **(a) chat still renders.** A thread with one tombstoned party still renders for the other
    party (`chat_messages` + `chat_threads` read path), body intact.
  - **(b) the storefront does NOT list the tombstone.** Select from **`available_runners`** as an
    authenticated counterparty after tombstoning an online runner → **0 rows**. Pin at the *view*
    (`0015`, re-created per §C.1.a 2b(a)), and mutation-verify by removing
    `and p.deleted_at is null` — the pin must go red. ⚠ A pin written against
    `profiles public runner read` instead would be **green on a leaking implementation**: the view
    is definer and never consults RLS (0112 §0b). Second arm: `marketplace_open_requests` (0056),
    same question asked of the owner-side projection rather than assumed.
  - **(c) the counterparty CAN still read the tombstone's name.** As an authenticated
    counterparty, select `id, name, handle, avatar_url, district` for the tombstoned profile →
    **1 row**, `name = '탈퇴한 사용자'`, the rest null. This is the arm that fails if anyone adds
    `deleted_at is null` to `profiles public runner read`; it is the direct pin on §C.1.a 2b(b).
    Negative half in the same arm: `phone` and `toss_customer_key` are **not** selectable
    (outside the column grant, `0088:135`), and `anon` gets **0 rows** (policy is
    `to authenticated`).
  - **(d) a kept `review` authored by a tombstone renders with `탈퇴한 사용자`**, and the
    *subject's* aggregate rating is unchanged. Executed evidence for why this needs (c): with the
    naive policy change, a tombstoned **owner** who had authored a review was invisible — the
    reviewer measured **0 rows** for the author lookup, so the review rendered with a blank
    author, which is neither honest nor 5.1.1(v)-safe.
- 🔴 **N6 — REWRITTEN AS A RECURSIVE CLOSURE (F4). The pin as first written was RED on a correct
  implementation and BLIND to the defect that actually shipped in the draft.** Both halves were
  measured by the reviewer:
  - **It was red on correct code.** The old form failed *"any FK into `profiles` or `auth.users`
    that is CASCADE or SET NULL on a table in the retention set"*, and listed `club_acks` and
    `runner_applications` in that set. But `club_acks.profile_id` and
    `runner_applications.profile_id` **are** `on delete cascade` today — and this design **keeps
    them that way on purpose**, because the `profiles` row is never deleted. The pin flagged the
    design's own intent as a violation.
  - **It was blind to the real one.** `gate_code_access_log` was in the set, but its dangerous
    edge is **not** into `profiles` — it is `address_id references addresses on delete cascade`
    (`0001:132`). A pin that only inspects edges terminating at `profiles`/`auth.users` cannot see
    a two-hop path, which is exactly how the draft's own delete list destroyed the row.

  **The corrected pin, stated as an algorithm** (still test-98-H1-shaped, still whole-schema):

      -- roots: profiles, auth.users, PLUS every table named in the RPC's ④ delete list
      -- edge:  a FK child->parent whose ON DELETE is CASCADE or SET NULL
      -- closure: recursive descent from roots over those edges, unbounded depth
      -- FAIL if any table in the retention set is reachable in that closure
      -- EXEMPT: an edge whose parent is `profiles` AND whose child is in the
      --         never-deleted-parent exemption list {club_acks, runner_applications}

  Three properties the implementation must have, each with a stated reason:
  1. **Recursive, not depth-1.** `gate_code_access_log` sits two hops out
     (`delete list > addresses > gate_code_access_log`) and the unbuilt 위치정보 ledger will very
     likely sit two or three. Depth-1 is why the first version could not see its own bug.
  2. **The RPC's ④ delete list is a root set.** This is the generalisation the whole review turned
     on: *an explicit delete is a cascade source too.* Any table the delete list can reach by
     CASCADE/SET NULL is flagged, which is what would have caught `delete from addresses` at
     harness time instead of at execution time.
  3. **The `profiles`-terminal exemption is narrow and named.** `club_acks.profile_id` and
     `runner_applications.profile_id` are exempt **only** because their parent is the row this
     design never deletes — the design keeps them. The exemption list is a literal two-name list in
     the pin, not a predicate: a third table joining it must be an argued edit.

  **Retention set** (unchanged in membership, corrected in use): `ledger_items`, `payments`,
  `payouts`, `payment_attempts`, `club_fee_items`, `km_ledger`, `km_lots`, `miles_ledger`,
  `gear_claims`, `bookings`, `delegation_consents`, `club_acks`, `runner_applications`,
  `dog_custody_events`, `dog_run_segments`, `assignment_events`, `session_dogs`,
  `gate_code_access_log`, `club_phone_access_log`, `incidents`, `club_incidents`,
  `club_incident_evidence`, `runs`, **and any table whose name matches `%access_log`**.

  🔴 **The `%access_log` wildcard, and the pin's stated reason must be written into the suite
  header verbatim.** The unbuilt 위치정보 이용·제공 사실 확인자료 ledger (위치정보법 제16조,
  ≥ 6 months) will be named something like `location_access_log`, and **the natural shape for it is
  not `profile_id references profiles` — it is `address_id references addresses on delete
  cascade`**, copied from the one existing house precedent for an access ledger,
  `gate_code_access_log` (`0001:130-136`). A wildcard that only inspects `profiles` edges would
  wave it straight through. The wildcard + the recursive closure + `addresses` being reachable
  from the delete list are three things that must all hold for that ledger to be caught, and the
  suite header must say so — otherwise the next person simplifies one of the three.
- **N7 — no orphan.** After a full deletion, no kept row references a `profiles.id` **or an
  `addresses.id`** that does not exist. The `addresses` half is new and is the direct pin on
  F1/F2: `bookings.address_id`, `gear_claims.shipped_to`, `recurring_series.address_id` and
  `gate_code_access_log.address_id` all still resolve after deletion. Mutation-verify by putting
  `addresses` back into the ④ delete list — the pin must go red (it did: 1 row → 0).
- **N8 — `storage.objects` is never deleted by SQL.** Pin that `delete_my_account_tx` contains no
  `delete from storage.` — the trigger would raise `42501` mid-transaction and roll back a
  half-done deletion (§A.4).

### Positive — these must work

- **P1 — a clean user deletes end to end, and the row-count diff is empty.** Mint a user with a
  dog, an address, a **gate_code_access_log row against that address**, a push token, a feed post,
  a completed+settled booking. Snapshot `count(*)` over the whole retention set. Delete. Assert:
  `auth.users` row **gone**; `auth.identities` gone; `profiles` row **present** with `deleted_at`
  set; `bookings` row **present** and byte-identical; `ledger_items` present; **and the retention
  set's row counts are unchanged, table by table**. The count-diff form is the reviewer's own
  instrument and it is what turned F1/F2 from an argument into a measurement — keep it as the
  pin's shape, not just its intent.
- **P2 — the tombstone is actually a tombstone, on all four tables.**
  - `profiles`: `name = '탈퇴한 사용자'`, `handle is null`, `phone is null`, `avatar_url is null`,
    `district is null`, `toss_customer_key` **unchanged**, `deleted_at` set.
  - **`addresses` (F1/F2):** row **present**, `gate_code_enc is null`, `detail is null`,
    `lat is null and lng is null` (**both**, or `addresses_latlng_shape` would have rejected the
    update — assert the pair, not one side), `addr` and `label` are the constant placeholder and
    **not** the original value.
  - **`dogs` (F16):** row **present**, `photo_url is null`, `memo is null`, **`name` unchanged**
    (assert equality against the seeded name — a future "anonymise the dog too" turns this red and
    has to argue with §C.1.b ③'s multi-dog/contract-identity reason).
  - **`runner_applications` (F10):** row **present**, `contact_phone is null`,
    `contact_window is null`, `contact_kakao = '[탈퇴]'`, the three narrative columns replaced,
    and **`consent_terms`/`consent_privacy`/`consent_id_check` still true with `created_at`
    unchanged**. Mutation arm: attempt `bio = null` in a savepoint and assert it **raises** — the
    pin then documents the NOT NULL/CHECK reality (`0062:70-72`) instead of leaving it as prose.
  - **`bank_accounts` (F9):** row **GONE**. Explicitly assert absence rather than inferring it
    from the delete list — this is the row whose `account_enc` survived the reviewer's run.
- **P3 — storage: the deletable prefixes are empty and the evidence prefixes are untouched
  (F5).** Two arms, and the second is the new one:
  - **Negative:** no `storage.objects` row remains under `{uid}/avatar.jpg`, `{uid}/gallery/%`,
    `{uid}/gear/%` (bucket `avatars`) or `{uid}/dogs/%` (bucket `media`). Deno-side assertion that
    `remove()` was called with exactly the enumerated paths.
  - 🔴 **Positive:** after deletion, a `chat_messages` row's `media_path` **still resolves** —
    the object under `{uid}/chat/{threadId}/…` is present in `storage.objects` and a signed URL
    for it succeeds. Same assertion for `{uid}/runs/%` and `{uid}/clubchat/%`. Mutation-verify by
    widening the sweep to `{uid}/%`: the pin must go red. Without this arm the "empty storage"
    pin rewards the wrong implementation — a sweep that deletes everything passes it perfectly
    while quietly creating the dangling-pointer mutilation §0 condemns.
- **P4 — the handle is freed.** A new user can claim the deleted user's old handle via
  `set_my_handle` (this works only because `profiles_handle_lower_uniq` is partial — MEASURED).
- **P5 — re-signup with the same Kakao identity works and is a new account.** MEASURED mechanism:
  `auth.identities.provider = 'kakao'`, `provider_id` = the Kakao user id, `user_id → auth.users`
  CASCADE. After deletion the identity row is gone, so the next `signInWithOAuth({provider:
  'kakao'})` mints a **new `auth.users.id`**. Pin: new uid ≠ old uid, and the old tombstone is not
  adopted. ⚠ Production has exactly **one** Kakao identity, so this arm is the least-exercised
  path in the whole contract and is the one to verify live (§E.4).
- **P6 — idempotent, and the retry path works (F15).** Second call → `already: true` or `401`,
  never 500, never a second `account_deletions` row with `auth_deleted = true`. **New arm:** with
  `auth_deleted = false` on the existing row and a still-valid JWT, a retry must take the
  `already: true` short-circuit through the SQL half **and still call
  `auth.admin.deleteUser`** — i.e. the retry is not a no-op. Assert the row flips to
  `auth_deleted = true` and that no second `account_deletions` row is inserted. Also pin the
  §G-6 arm: an `auth.users` row with **no** `profiles` row deletes cleanly (production has one —
  MEASURED, 11 vs 10).
- **P7 — the log is written, including the forfeits.** One `account_deletions` row with non-zero
  `counts`, `completed_at`, `storage_removed`, and **`forfeited_miles` / `forfeited_drops`
  matching the seeded balance and unopened-drop count** (F11). `auth_deleted` is written by the
  edge function, not the RPC (F15) — assert it is null/absent immediately after the transaction
  and set only after step 5.

### Deno test plan — `supabase/functions/_test/delete_account_test.ts`

House style (`_test/start_run_test.ts:19-59`): `FakeDb` from `_test/fakedb.ts`, no network, assert
on `db.log` (`"rpc:<name>"` / `"insert:<t>"` / `"update:<t>"`), `db as never` cast, `assertRejects`
against `HttpError`, English-sentence test names. `deno test -A supabase/functions/_test/`.

1. `"delete-account: the uid comes from the JWT — a body-supplied id is ignored"` — seed a body
   with someone else's id, assert the rpc was called with the caller's uid.
2. `"delete-account: no Authorization header → 401 unauthorized"`.
3. `"delete-account: a missing confirm → 400 confirm_required, and no rpc is called"` — assert
   `db.log` contains no `rpc:delete_my_account_tx`.
4. `"delete-account: the RPC's refusal token reaches the client as a 409"` — rpc returns
   `active_booking`, assert `HttpError` status 409 and the token verbatim.
5. `"delete-account: Deno deletes no application row — every delete goes through the tx"` — the
   `start_run` invariant, restated: assert `db.log` has **zero** `delete:` entries against public
   tables, only `rpc:delete_my_account_tx` plus storage calls.
6. `"delete-account: storage failure does not abort the deletion"` — `remove()` throws; assert
   `auth.admin.deleteUser` is still called and the result reports `storage_removed: 0`.
7. `"delete-account: auth.admin.deleteUser failure returns 202 auth_delete_pending, and the log row
   records it"` — assert the result does **not** claim success **and** that
   `update:account_deletions` with `auth_deleted = false` appears in `db.log` **after**
   `rpc:delete_my_account_tx`, never inside it (F15).
8. `"delete-account: order is tx → storage → auth"` — assert `db.log` index order.
   🔴 **F14 — the stated reason was wrong and had to be corrected, because a wrong reason for a
   right rule is what gets the rule refactored away.** The old note said *"after the auth user is
   gone, the JWT that authorised the enumeration is dead."* It does not: **the enumeration and the
   removal both run on `admin()`**, which is `createClient(SUPABASE_URL,
   SUPABASE_SERVICE_ROLE_KEY)` (`_shared/ctx.ts:22-27`) — a service-role client that holds no user
   JWT at all. The caller's JWT is used **once**, by `caller(req, db)` (`ctx.ts:30-35`), to
   establish `uid`, and is never touched again. Deleting the auth user does not revoke it.
   **The rule is still right, for a different reason: orphan avoidance.** Storage objects are keyed
   by `{uid}/` and nothing else — there is no `owner` column, no FK, no trigger, and no cascade
   from `auth.users` into `storage.objects`. Once the auth row is gone, `uid` survives only in the
   tombstoned `profiles.id` and in the edge function's local variable; if the function dies between
   the auth delete and the sweep, the objects are unreferenced bytes that only a manual prefix scan
   will ever find again. Doing storage first means the worst case is *"objects removed, auth delete
   retried"* — which §C.1.c step 5's retry path handles — instead of *"account gone, objects
   orphaned forever"*, which nothing handles.
9. `"delete-account: the sweep never touches runs, chat or clubchat"` (F5) — assert the paths
   passed to `remove()` contain no `/runs/`, `/chat/` or `/clubchat/` segment, and that the four
   deletable prefixes were each enumerated. This is the Deno-side twin of §D.P3's positive arm;
   it catches a `{uid}/%` regression without needing a live bucket.

---

## E. Ordering and deploy

Strictly sequenced; each step verified before the next.

1. **E.1 — Migration.** Write `0113_account_deletion.sql` (**re-resolve the number first**, §A.6) +
   suite `148_account_deletion_suite.sql`. Run the harness (`supabase/tests/harness.sh`; PG16 at
   `tests/.pgtest`, `pg_ctl` in the same shell invocation). **All pins green, new ones
   mutation-verified.** Then `/autoplan` — it is the standing gate for any migration touching a
   money path, and this one reads every money table.
2. **E.2 — Deploy the migration.** `bash scripts/deploy-migrations.sh` (dry-run) →
   `bash scripts/deploy-migrations.sh --push 0113_account_deletion.sql`. The script cuts a detached
   worktree at `origin/redesign-v4` and refuses unless the pending set equals exactly what you
   named. Push the migration **and its REGISTRY row in the same breath** (CLAUDE.md; collision six).
   Verify: `supabase migration list --linked`, then the anon-definer check
   (`delete_my_account_tx` must **not** be executable by `anon`/`authenticated`).
3. **E.3 — Deploy the function.** `supabase functions deploy delete-account`. Verify with
   `supabase functions list` (version bumped) — git's silence is not evidence of what is deployed.
   Re-run `deploy` once as the parity oracle ("No change found").
4. **E.4 — Verify live with a throwaway user.** A self-cleaning probe in the
   `app/scripts/e2e-party-channels.mjs` shape: `svc.auth.admin.createUser` → seed profile, dog,
   address, push token, a completed+settled booking → sign in as that user with the **anon** key →
   `functions.invoke('delete-account', { body: { confirm: 'DELETE' } })` → assert `auth.users` gone,
   `profiles` tombstoned, `bookings` intact, **`addresses` present-and-redacted with its
   `gate_code_access_log` row still resolving** (F1/F2), **`bank_accounts` gone** (F9), **avatar and
   dog photos gone while a seeded `{uid}/chat/…` object still resolves** (F5) → `finally` block
   removes anything left. Gate it behind `E2E_ALLOW_REMOTE=1` exactly as that script does at
   line 9. **Add three negative arms in the same probe**: a throwaway user with an open booking
   must get `409 active_booking`; one holding a delegated dog (`session_dogs.checked_out_at is
   null`) must get `409 club_custody` (F3); one with `recurring_series.paused = false` must get
   `409 active_recurring` and then succeed after pausing (F13).
   ⚠ Run the Kakao re-signup arm (§D.P5) manually on device — it cannot be scripted.
5. **E.5 — Client (ui2), only now.** §C.2. Commit gate from `app/`: `tsc --noEmit`,
   `check-rpc-contracts.mjs`, `check-route-native-imports.mjs`. Then `/design-review` on the confirm
   sheet and `/qa` on the refusal states.
6. **E.6 — Privacy policy §5/§7.** Update in the same slice so the app and the policy agree
   (§B.4). The concrete 전자상거래법 periods stay a placeholder until counsel fills them (§F).
7. **E.7 — Update `docs/legal/readiness-review-2026-08-19.md` §13.2 ⑥ and ⑩** from ❌/🟡 to their
   new state, and strike §0-septendecies from `docs/decisions/awaiting-sean.md`. A ruling that
   ships without its scoreboard being updated is how the same question gets re-asked.

**Not in this slice, and named so nobody assumes it:** the `runs.trace` TTL and the
위치정보 이용·제공 사실 확인자료 ledger (§0-sexdecies) — but **N6 must land with this slice**, so
that ledger cannot be built with a cascading FK.

---

## F. Facts only Sean holds

Genuine lookups only. **There are none that block the build.** Two that block *publication*:

1. 🔵 **The concrete 전자상거래법 retention periods** for privacy-policy §5
   (`privacy-policy.md:116-117` is an explicit placeholder). Counsel's, not Sean's, and it gates
   the policy update in E.6 — **not** the code. The confirm-sheet copy can name the categories
   without naming the year counts.
2. 🔵 **Whether kept `chat_messages` bodies and `reviews` authored by a departed user are
   acceptable retention** (§C.1.b ③). Decided under the grant as **keep**, with the one-line
   alternative specified. Worth a sentence to counsel alongside the §11 question already queued.

Product calls decided under the grant, marked 🔵 and listed here so they are visible as decisions:
**no grace period** (§C.2) · **no special case for the PR-0 test owner** (§C.4) · **chat and review
rows are kept, not redacted** (§C.1.b ③).

Added by the announcer at the adversarial review, same standing, same visibility:

- 🔵 **`addresses` is KEEP+ANON, not DELETE** (F1/F2, §C.1.b ③) — forced by executed evidence, but
  the *shape* of the redaction (placeholder `label`/`addr` rather than relaxing the NOT NULLs) is
  a call.
- 🔵 **`bank_accounts` is DELETE, not KEEP** (F9, §A.2.e) — no retention duty covers a payment
  instrument; the payout record that *is* covered stands alone without it.
- 🔵 **마일리지 and unopened drops are FORFEIT, with no gate** (F11, §C.1.b ②/④) — legal tonight
  because 하이 포인트 is non-transferable with no cash-out; **the confirm-sheet line is the
  protection**, so it is contractual copy, not suggested copy. `km_balance` keeps its gate; the
  asymmetry is argued in §C.1.b ②. ⚠ **This one is worth a sentence to counsel** alongside the §11
  question already queued — not because it blocks (it does not), but because forfeiture of a
  promotional balance is the kind of thing a 약관 clause should already say and ours may not.
- 🔵 **Visibility is fixed in the VIEW plus a narrow tombstone policy, not by narrowing
  `profiles public runner read`** (F6/F7/F8, §C.1.a 2b).
- 🔵 **`dogs.name` is kept** (F16, §C.1.b ③).
- 🔵 **No sweeper cron for `auth_delete_pending` rows — an ops script instead** (F15, §C.1.c 5).

---

## G. Contradictions between artifacts

1. **The privacy policy promises a 탈퇴 that does not exist.** §5 (`계정 정보 | 회원 탈퇴 시까지`)
   and §7 (*앱 내 설정 … 을 통해 요청*) describe an in-app route; `settings.tsx:89` says
   `문의로 처리`. The readiness review (§6-quinquies ⑥) resolves it in the policy's favour — the
   policy is describing a manual process, not a fiction — but **the app and the policy still say
   different things about where the control is**, and only E.6 closes that.
2. **§13.2 ⑥ and ⑩ disagree on how bad this is.** ⑥ is ❌ (*"there is no account deletion"*); ⑩ is
   🟡 partial (*"cancellation/refund exist; account deletion does not"*). Same fact, two scores.
   Both flip together in E.7.
3. **`0075:105`'s premise no longer holds after §C.1.a.** Its comment says
   *"계정 삭제는 명시적 close-out 후에만 — 그 경로는 컷오버 슬라이스가 만든다"* and enforces it with
   `ON DELETE RESTRICT` on `profiles`. This contract **is** that path, but it stops deleting
   `profiles`, so the RESTRICT silently stops enforcing. The migration header must amend 0075's
   comment in the same file — a guard whose premise moved is worse than no guard.
4. **`scripts/wipe-test-data.mjs` and this feature disagree about what a user is.** The wipe script
   keeps accounts/profiles/dogs and deletes bookings; this deletes the account and keeps the
   bookings. Both are right for their job, and the FK ordering at `:43-49` is reusable — but the
   script's header says *"프로덕션 전환 후엔 이 스크립트를 삭제할 것"*, which has not happened, and
   it is now one of two things in the repo that delete user data. Worth an explicit note there.
5. **`club_test_accounts` is both an ops allowlist and, in practice, the pilot's user census.**
   Nine of ten production profiles carry the row (MEASURED). Any future "delete all test accounts"
   ops action would, with an account-deletion path now built, be one command away from deleting
   Sean's own account and every booking's owner. Not this slice's problem; recorded because this
   slice is what makes it reachable.
6. **`auth.users` (11) ≠ `profiles` (10)** — one auth user has no profile row (MEASURED). The party
   gate's `already: true` short-circuit handles it correctly (no profile → nothing to tombstone →
   proceed to `auth.admin.deleteUser`), but it must be *deliberately* handled, not accidentally:
   pin it as an arm of D.P6.
7. **Email auth is closed in the client and open on the server.** `login.tsx` offers Kakao only;
   `auth-surface.expected.json:3` records `external_email_enabled: true` and the drift check is
   intentionally red. It does not change this contract — deletion is provider-agnostic — but a
   reviewer testing "delete then re-create" may reach a door the product no longer shows.

---

## H. Review log — adversarial review of §C, 2026-08-19

**Verdict: FIX-CONTRACT-FIRST. Architecture CONFIRMED.** The reviewer executed §C.1.b in the
harness against seeded fixtures — not read it — and returned **16 findings**, of which **5 were
BLOCK**. Nothing in the split (edge function + definer transaction), the tombstone design, the
anonymise-then-delete ordering, or the party-gate-before-state-gate shape was disturbed. Every
finding below is applied above; this log is the index, not the argument.

| # | Severity | Finding | Where it landed |
|---|---|---|---|
| **F1** | BLOCK | ④ deleted `addresses`; `gate_code_access_log.address_id` is CASCADE (`0001:132`) — **executed: 1 row → 0** | §0, §A.2.b, §C.1.b ③/④ |
| **F2** | BLOCK | the same delete **aborts** anyway — `bookings.address_id`, `gear_claims.shipped_to`, `recurring_series.address_id` are NO ACTION into `addresses` | same |
| **F3** | BLOCK | state gate missed club custody entirely — **a runner holding another owner's dog RIGHT NOW passed all nine tokens**; `backup_host_profile_id`/`original_host_profile_id` also unguarded | §C.1.b ②, §D.N2-b/c/d |
| **F4** | BLOCK | N6 was **RED on a correct implementation** (`club_acks`/`runner_applications` are CASCADE by design) and **BLIND** to `gate_code_access_log`'s two-hop path | §D.N6, rewritten as a recursive closure |
| **F5** | BLOCK | `{uid}/%` sweep would delete run/chat/clubchat media that kept rows point at — the SET NULL mutilation §0 condemns, reached from the storage side | §A.4, §C.1.c 4, §D.P3 (two arms) |
| **F6** | 🔵 | do **not** add `deleted_at is null` to `profiles public runner read` — it makes N5 unreachable (**executed: author lookup → 0 rows**) | §C.1.a 2b |
| **F7** | 🔵 | hide the tombstone in the **view** (`create or replace view available_runners … and p.deleted_at is null`) — the view is definer and never consulted RLS (0112 §0b); `online = false` kept as belt | §C.1.a 2b(a), §D.N5(b) |
| **F8** | 🔵 | add a narrow `profiles tombstone read` policy; a policy cannot be per-column, so it is paired with the existing grant `(id, name, handle, avatar_url, district)` (`0088:135`) — and those five are already nulled on a tombstone | §C.1.a 2b(b), §D.N5(c) |
| **F9** | 🔵 | `bank_accounts` → **DELETE** in ④ after `unpaid_payout` clears; `account_enc` survived the whole written procedure | §A.2.e, §C.1.b ④, §C.3 |
| **F10** | — | `runner_applications` → KEEP+ANON; ⚠ NOT NULL + CHECK constraints (`0062:70-72`, `:96-97`) make "null them" impossible — placeholders, argued | §C.1.b ③, §D.P2 |
| **F11** | 🔵 | 마일리지/drops/boosts: **no gate — forfeit, disclose, log**; `km_balance` keeps its gate (`won_paid`, `0075:113`). Asymmetry stated in both directions | §B.3, §C.1.b ②/④, §C.2 ②, §D.N2-e |
| **F12** | — | N4's definer list: **three** `_owner_la_*` triggers, not four; `notify_chat_message` was missing and degrades to `탈퇴한 사용자님이 메시지를 보냈어요` | §D.N4, N4-a |
| **F13** | — | `active_recurring` = `paused = false`, and the row is **KEPT** — `0111:192` revoked client DELETE, `:193` granted `update (paused)` only. "REFUSE-then-DELETE" was never expressible | §A.2.c, §C.1.b ②, §C.2 ③ |
| **F14** | — | Deno test 8's rationale was wrong — enumeration runs on `admin()` (`ctx.ts:22-27`), not on the caller's JWT. Storage-before-auth is still right, for **orphan avoidance** | §D Deno plan 8 |
| **F15** | — | `account_deletions.auth_deleted` moves into the edge function after step 5; `auth_delete_pending` (as built) becomes a defined UI state with a retry; **no cron — an ops script**, stated as a decision | §C.1.c 5, §C.2 3b, §D.P6/P7 |
| **F16** | 🔵 | write the `dogs` UPDATE explicitly: null `photo_url`/`memo`, **keep `name`** (multi-dog owners; kept-booking identity) | §C.1.b ③, §D.P2 |

**The 🔵 decisions taken at this review** — all also listed in §F, where the other product calls
live: `addresses` KEEP+ANON · `bank_accounts` DELETE · 마일리지 forfeit with no gate while `km`
keeps its close-out gate · visibility fixed in the view plus a narrow tombstone policy, never by
narrowing the runner-read policy · `dogs.name` kept · no sweeper cron, an ops script instead.

**The one sentence worth carrying out of this review**, because it generalises past this feature:
§0 said an implicit cascade is a delete nobody reviewed. F1 showed the converse is equally true.
**An explicit delete list is itself a cascade source, and it must be closed over exactly like the
FK graph.** That is why N6 is now recursive and why the RPC's own ④ list is one of its roots.

**Status: implement as designed after these.** No further contract round is asked for. §E's
ordering is unchanged, and §E.1's harness run is where the sixteen become measurements again.
