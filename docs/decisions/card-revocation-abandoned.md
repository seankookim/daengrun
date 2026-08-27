# Card revocation: who is told when it gives up

**Status: OPEN — needs Sean.** Open queue item #4 in `docs/session-handoff.md`.
Scouted 2026-08-27 against the deployed database and the deployed edge functions, not against
the migration files alone.

**Not a live incident, and here is exactly when it arms.** OBSERVED on the linked production
project, 2026-08-27:

| fact | value |
|---|---|
| `select count(*) from billing_keys` | **0** |
| `select count(*) from billing_key_revocations` | **0** (of which `abandoned`: **0**) |
| `ops_flags.card_registration_live_since` | **NULL** — registration refuses, server-side |
| `ops_flags.payments_live_since` | **NULL** |
| `billing_key_dispatch_ticks` | 11 rows, **all `idle`**, 06:38→08:18 UTC today |
| cron `revoke-billing-keys` | `8-58/10 * * * *`, **active** |
| edge fn `revoke-billing-keys` | **ACTIVE**, version 2, `verify_jwt: false` |
| `supabase migration list --linked` | local == remote through **0152** |

So: the whole machine is deployed and running, it has never had a single row to work on, and
it cannot get one until Sean sets `card_registration_live_since`. **This arms the day card
registration is switched on, and not before.** Every hour it stays off, this decision stays free.

⚠ One consequence of that: the first real revocation is also the **first live test of the cron
key**. All 11 ticks so far were `idle`, which means `dispatch_billing_key_revocations()` returned
early and never called the endpoint — nothing here has ever proved the `X-Cron-Key` handshake
works in production. 0150 makes a rejected tick *recordable*; it does not make it *noticed*.

---

## (a) The lifecycle, as it actually is

### What creates a row — five reasons, not one

| `reason` | written by | who the person is |
|---|---|---|
| `replaced` | `billing_key_swap` (`0148:106-107`) | a live owner who tapped 「카드 바꾸기」 |
| `account_deleted` | `delete_my_account_tx` (patched by `0138 §F`) | **someone who left** |
| `orphaned_by_deletion` | `billing_key_swap` (`0148:51-53`) | someone who left mid-registration |
| `gate_closed` | `billing_key_swap` (`0148:71-72`) | a live owner refused by the rollout gate |
| `issued_unpersisted` | `register-billing-key/handler.ts:82` | a live owner whose swap did not persist |

VERIFIED on production (comment-stripped `prosrc`): `delete_my_account_tx` contains exactly one
`enqueue_billing_key_revocation(p_uid, 'account_deleted')` and exactly one
`delete from billing_keys`, and **the enqueue precedes the delete** — the ordering `0138 §F`
argues for is the ordering that is deployed. OBSERVED.

**This matters for the decision and the handoff does not say it: only two of those five are a
person asking to be gone.** `replaced` and `gate_closed` are live account-holders we can still
reach. `account_deleted` and `orphaned_by_deletion` are people we structurally cannot contact
(see §(c)).

### The ladder

1. A row lands `pending`, `attempts = 0`. READ — `0138:26-38`.
2. Cron `revoke-billing-keys` fires every 10 minutes (`0138:287`, schedule confirmed live).
   `dispatch_billing_key_revocations()` counts what is due, writes a tick row, and `net.http_post`s
   the edge function. READ — `0150:296-330`.
3. The edge function checks `X-Cron-Key` (503 if unset, 401 if wrong —
   `revoke-billing-keys/handler.ts:24-27`), then calls `claim_billing_key_revocations` (`:29`).
4. The claim sets `state='processing'`, a **5-minute lease**, a `claim_token`, and
   `attempts = attempts + 1`. Only rows with `attempts < 8` are eligible. READ — `0149:68-79`,
   VERIFIED deployed.
5. The worker sends `DELETE /v1/billing/{billingKey}` to Toss (`_shared/toss.ts:147-153`).
   **Only 2xx is success** — 404 is deliberately a failure (`handler.ts:40-50`), because a
   previous version read 404 as "already gone" while the real cause was a wrong URL, and the
   outbox emptied itself perfectly without deleting one key.
6. `report_billing_key_revocation` compare-and-sets on the token:
   `done` if ok · `abandoned` if `attempts >= 8` · `pending` otherwise. VERIFIED against deployed
   `prosrc`.
7. **8 attempts at 10-minute spacing. No backoff.** A row that fails every time is `abandoned`
   roughly **70–80 minutes** after it was enqueued. INFERRED from the cap (`attempts < 8`) and the
   live schedule (6 ticks/hour) — arithmetic, not a measurement.

### The states, and what each means on each side

| state | our database | Toss's side |
|---|---|---|
| `pending` | outstanding order, nobody holding it | key still LIVE |
| `processing` | a worker holds a 5-minute lease | a DELETE may be in flight |
| `done` | closed | Toss returned 2xx — key destroyed |
| `abandoned` | **terminal, and the row is the only record** | **key state UNKNOWN — most likely still LIVE** |
| `failed` | in the CHECK domain and **written by nothing** | — |

⚠ `failed` is dead vocabulary. VERIFIED: `report_billing_key_revocation`'s deployed body writes
only `done`, `abandoned`, `pending`; no other statement in any deployed function writes `'failed'`
to this table. The two reachable terminal states are `done` and `abandoned`. (0149's header
reasons about a late report flipping a row to `failed`; that path does not exist in the deployed
code, because the same report that would set it also sees `attempts >= 8` and writes `abandoned`.)

### Four ways to reach `abandoned`, only one of which is "we tried and failed"

| # | site | meaning |
|---|---|---|
| 1 | `report_billing_key_revocation`, `attempts >= 8` | **the give-up.** Toss refused or was unreachable eight times |
| 2 | `claim_…`, belt 2 (`0149:44-51`) | the key is somebody's card right now — deliberately NOT revoked |
| 3 | `claim_…`, cap sweep (`0149:57-66`) | a worker crashed at the cap; surfaced rather than left invisible |
| 4 | `billing_key_swap` (`0148:111-118`) | a never-claimed key became current again |

**Only #1 and #3 are failures.** #2 and #4 are the system working correctly. Any alert built on
"an `abandoned` row appeared" that does not read `last_error` will page on healthy behaviour —
which is the fastest way to get an alert muted. `last_error` carries a distinct sentence for each
site (`0149:47`, `0149:60-61`, `0148:114`), so the distinction is available; it just has to be used.

### What happens next

Nothing. The row sits there.

---

## (b) Where the handoff was right, and where it was not

### Right

- ✅ **「The local card row IS deleted (`0115:535`)」** — exact. `0115:535` is
  `with d as (delete from billing_keys where profile_id = p_uid returning 1)`, and `0138 §F`
  inserts the enqueue immediately above it. VERIFIED on production, not just in the file.
- ✅ **「After 8 failed attempts a row lands in `abandoned`」** — 8 is the cap, in
  `claim_billing_key_revocations` (`attempts < 8`) and `report_billing_key_revocation`
  (`attempts >= 8`). VERIFIED against deployed bodies.
- ✅ **「Zero keys and zero rows exist today」** — OBSERVED, table above.
- ✅ **「Toss could still hold a live authority to charge」** — accurate. `abandoned` from cause #1
  means eight non-2xx answers; nothing in our data licenses the sentence "the key is gone".

### Not right, or not precise enough

- 🔴 **「nothing reads it」 is nearly true and the near-miss is the trap.** There *is* one reader
  of `billing_key_revocations`: the view `billing_key_dispatch_health` (`0150:398`), whose
  `due_now` column (`0150:413-415`) counts `pending` plus expired-lease `processing` — and
  **structurally excludes `abandoned`**. OBSERVED: the view exists on production and returns
  `due_now: 0` today. So the one dashboard-shaped object in this family will report the queue as
  clean *precisely because* rows were given up on. That is worse than no reader, and it is the
  shape a future session is most likely to trust. A reader that cannot see the failure state is
  not a partial reader; it is a false green with a column name.
- ⚠ **「someone who asked to be gone」 covers 2 of 5 reasons.** The other three
  (`replaced`, `gate_closed`, `issued_unpersisted`) are live account-holders. Framing the whole
  item as a deletion-promise problem hides the fact that the *most likely* abandoned row in
  practice — a mass failure from a bad URL or a wrong cron key — will be `replaced` rows belonging
  to people who are still using the app and are trivially reachable.
- ⚠ **The REGISTRY rows for 0138 and 0148 say「NOT DEPLOYED. Production 0130」.** Stale: production
  is 0152 and every one of these migrations is live (OBSERVED via `migration list --linked`). Not
  this decision's problem, but any session that reads REGISTRY for deployment state will be wrong.
- ⚠ **「a policy call」 understates one arm.** For `account_deleted`, "message the person" is not a
  policy choice we can simply make — see §(c). It requires *retaining a contact address past
  deletion*, which is itself a legal question.

---

## (c) What the user is told today, and whether it is honest

### There is no "remove my card" button at all

SEARCHED the whole client for a card-removal affordance (`카드 삭제`, `카드 해지`, `removeCard`,
`deleteCard`, `카드 연결 해제`) — **zero hits.** `app/app/payments.tsx` offers exactly two card
actions: 「카드 바꾸기」 (`:216`) and 「카드 연결하기」 (`:238`). The only way to make us stop
holding a card is to delete the account.

So the question "what is a user told when they ask to remove their card" resolves to: **what is
a user told when they delete their account.**

### The deletion copy, verbatim

`app/src/components/delete-account-sheet.tsx:331-332`:

> 지워지는 것
> 프로필, 강아지 사진, 주소, **결제수단**, 알림, 피드 글

`:344-345`:

> 예약·결제·정산 기록은 전자상거래법에 따라 보관돼요. 이름은 '탈퇴한 사용자'로 바뀌고
> 연락처·사진은 지워져요.

**Is it honest given the failure path?** Narrowly yes, and only narrowly. 「결제수단」 in a list
of things this app holds most naturally reads as *our* stored payment method, and our row is
genuinely deleted, unconditionally, in the same transaction (`0115:535`). The sentence makes no
claim about Toss. A user who understood the architecture could not call it false.

But no user understands the architecture, and 「지워지는 것」 is a promise of destruction, not of
local record-keeping. If revocation is abandoned, the sentence a Korean reader took from that
screen — *my card is gone* — is not what happened. **The copy is defensible and the outcome is
not.** That gap is the whole of this decision.

### Why "just tell them" is impossible for the case that matters

After a completed deletion the system retains **no channel to the person**. All READ from source
and all deployed:

- `notifications` rows deleted — `0115:518`
- `push_tokens` deleted — `0115:520` (and the push bridge reads `push_tokens`, `0024:20-40`)
- `profiles.phone` nulled — `0115:421`
- the auth user is deleted, taking the email — `delete-account/handler.ts:146`
- `account_deletions` keeps `profile_id`, counts, forfeitures — **no contact field** (`0115:167-180`)

Telling a deleted user that their card could not be revoked therefore requires **deliberately
retaining a contact address past deletion, for the sole purpose of reporting a failure to
delete**. That is a coherent thing to do and it is not obviously the privacy-preserving choice.
It is a lawyer question, not an engineering one.

For `replaced` / `gate_closed` / `issued_unpersisted`, none of this applies — the account is
alive and a `notifications` insert already reaches the phone through the existing trigger.

---

## (d) The options

Three, plus a copy question that is independent of all three.

| | **A — a queue Sean reviews** | **B — Sean is alerted** | **C — the user is told** |
|---|---|---|---|
| **What the user experiences** | Nothing. Identical to today. The failure is repaired silently, or not at all, depending on whether Sean looks. | Nothing directly — but the repair is fast, so the window where a live key exists is hours instead of unbounded. | A push (live accounts only): "we could not remove your card at the payment provider; here is what to do." For deleted accounts: **nothing is possible** without retaining a contact. |
| **What Sean does operationally** | Remembers to run a command. There is no forcing function — the failure mode is that nobody looks for six months. | Gets a push/notification when a real abandon lands; opens the Toss dashboard and deletes the key by hand. | Same as B, plus he must be ready for support replies from people who have already left. |
| **Build cost** | **Smallest.** Add an `abandoned_now` / `abandoned_24h` column to `billing_key_dispatch_health` (`0150:398`, a `create or replace view` — grants preserved, no DROP) and a ~80-line `scripts/revocation-ops.mjs` on the exact `scripts/runner-ops.mjs` pattern (service key, PostgREST, read-only). One migration, one script, pins for the new column. | **A, plus** a notification path. Cheapest honest version: insert a `notifications` row against Sean's own profile id from the claim function's abandon sites — the existing `notify_push` trigger (`0024:20`) then pushes it with zero new infrastructure. Needs cause-filtering (`last_error`) so belts #2/#4 never page, and a config home for his profile id (`docs/decisions/ops-profile-id-vs-admin-role.md` is the existing argument about that seam). | **B, plus** user-facing Korean copy, a new notification `kind`, and — for deleted accounts — a retention decision and a policy change. Largest by a wide margin, and one arm of it is blocked on counsel. |
| **Legal / consumer-protection exposure of NOT doing it** | The exposure is unchanged from today: a 개인정보보호법 제37조 / 제21조 destruction request that we told the user was executed, was not fully executed at our 수탁자, **and nobody at the company ever learned that.** "We had no process to notice" is materially worse than "we noticed and fixed it late". Option A converts it into the latter *only if* someone actually looks. | Removes the "nobody could have known" version entirely. A dated abandoned row plus a dated alert plus a manual revocation is a defensible record. | The strongest position — the data subject is informed that their request was not fully executed — and the only one that plausibly satisfies a strict reading of a notification duty, if counsel says one exists. |

**Not an option, but it must be said:** `docs/legal/privacy-policy.md`'s 처리위탁 table (`:124-127`)
lists Supabase, Expo and 네이버클라우드플랫폼 and **does not list 토스페이먼츠 at all**. That is
correct today (zero keys, gate closed) and becomes false the moment card registration opens,
independently of which option below is chosen. Whoever flips `card_registration_live_since` owns
that row.

### The copy question, independent of A/B/C

Should 「지워지는 것 … 결제수단 …」 stay as it is? Two answers:

- **Leave it.** It is true of our data, and hedging it (「저장된 결제수단은 지워요. 결제사에
  등록된 정보는 별도로 요청해 주세요」) makes a clean promise sound conditional and pushes work
  onto the user for a case that will almost never happen.
- **Hedge it.** A promise you cannot always keep should not be stated unconditionally, and the
  cost of hedging is one line of Korean.

This is genuinely separable from A/B/C and can be decided at any time.

---

## THE QUESTION FOR SEAN

> When we fail to delete someone's card from Toss — we tried eight times over about an hour and
> the payment company would not do it — **who finds out?**

Pick one:

- **① Nobody, until I go look.** I get a command I can run (`node scripts/revocation-ops.mjs`)
  that shows every give-up and why. Nothing interrupts me. If I don't run it, nobody knows.
- **② Me, when it happens.** The app pushes me a notification the moment a real failure lands,
  and I delete the key by hand in the Toss dashboard. Roughly a day of work more than ①.
- **③ Me and the customer.** ②, plus we tell the person their card could not be removed —
  which we can only do if they still have an account. **For someone who deleted their account we
  currently have no way to reach them at all**, so telling them means keeping their email or phone
  after they left, on purpose, which is its own privacy question for the lawyer.

Two smaller things, decidable now or later:

- **The screen currently promises 「지워지는 것 … 결제수단 …」.** Leave it, or soften it?
- **Whichever you pick, none of it matters until you turn card registration on.** Nothing is
  broken today: zero cards exist, zero rows exist, the switch is off.

---

## (e) Does this belong in the lawyer email?

**No — do not delay `docs/legal/counsel-email.md` for it** (that email is scoped to
위치기반서비스 registration and is already the oldest blocker); but option ③ contains one
question only counsel can answer — *may we retain a contact address after account deletion in
order to notify the person that their deletion request was not fully executed at a 수탁자?* —
and that question belongs in the payments/PG round alongside the missing 토스페이먼츠 row in the
처리위탁 table, both of which come due before `card_registration_live_since` is ever set.
