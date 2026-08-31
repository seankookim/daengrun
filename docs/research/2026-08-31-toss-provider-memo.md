# Toss provider memo — the two questions gating findings 3 & 4 (2026-08-31)

Audience: the backend session designing the fix for codex findings 3/4/6
(`docs/reviews/2026-08-28-codex-billing-chain.md`). Purpose: separate what Toss's official
documentation already answers (design to it now) from what only a support ticket or a sandbox
experiment can settle (do not design around by guessing — the review's own instruction).

Evidence discipline: every claim below carries its source. Doc claims cite the URL they were read
from; repo claims cite `file:line`. Anything not directly stated in a source is marked INFERENCE
or UNKNOWN and stays that way.

**Ref basis for handler citations:** every `register-billing-key/handler.ts` and
`revoke-billing-keys/handler.ts` line number in this memo is against
`origin/rescue/wip-0157-billing-hardening-2026-08-28` (the adopted 0157 tree), NOT trunk — trunk's
register handler has the issue call at `:189` and no `billing_key_revocations_outstanding_uq`.

Two methodology caveats up front: (1) the `/reference` page reads (DELETE section shape, absence
of an Idempotency-Key row there) came via WebFetch summarization — read twice, consistent — not
raw HTML. (2) ⚠ Measured by this memo's own audit: **WebFetch summarization of the 3.0 MB
error-codes page returns FALSE ABSENT** for `ALREADY_REMOVED_BILLING_KEY` and
`BILLING_KEY_NOT_FOUND` — for absence claims on large Toss pages, only a raw-HTML fetch counts;
the audit re-verified this memo's error-code claims against raw HTML (curl), where both strings
appear (the former 115×, only ever as a bare enum).

---

## §1 The two questions, verbatim, with repo citations

Both halves live in ONE still-open bullet of the codex review, repeated verbatim in the handoff:

> "can Toss replay or look up a billing-key issuance by a persisted idempotency
> key, and what does a repeated DELETE return?"
> — `docs/reviews/2026-08-28-codex-billing-chain.md:127-131`; same text at
> `docs/session-handoff.md:340-344`

- **Q1** — can Toss **replay or look up** a billing-key **issuance** by a persisted idempotency
  key? (Drives finding 3, and most of finding 4.)
- **Q2** — what does a **repeated DELETE** of a billing key return? (Drives finding 6 and the
  revoke worker's success posture; detection economics for finding 4.)

Status in the repo: the review says the answer "decides the recovery protocol" and is
"not a thing to design around by guessing"
(`docs/reviews/2026-08-28-codex-billing-chain.md:127-131`); Recommendation 2 puts it on the
critical path — findings 3 and 4 must close before `card_registration_live_since` is ever set,
and "the fix shape is unknown until it is answered" (`:142-146`). The handoff says the question
is UNOWNED: "Nobody owns it yet." (`docs/session-handoff.md:340-344`). The review's open-question
bullet attributes it to findings 3 and 6; both documents agree findings 3 and 4 gate the flag.

Explicitly NOT one of these questions (do not miscount it as a third Toss question): the review's
other open bullet — edge-instance affinity of the isolate-local registration nonce between
`prepare` and `issue` ("The registration nonce is isolate-local memory.",
`docs/reviews/2026-08-28-codex-billing-chain.md:132-134`;
`supabase/functions/register-billing-key/handler.ts:43-62`). That is a Deno Deploy question with
its own fix shape (durable nonce), separate from both provider questions.

---

## §2 What the official docs answer

### 2a. The idempotency-key mechanism (applies to Q1's replay half)

| # | Doc claim | Quote (<15 words) | Source |
|---|---|---|---|
| 1 | Every POST-method API accepts the Idempotency-Key header | 「모든 POST 메서드 API는 요청에 멱등키 헤더를 추가해서 사용할 수 있습니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 2 | Non-POST methods are covered only by a blanket "self-guarantee idempotency" sentence — no per-endpoint semantics | 「그 외 메서드는 자체적으로 멱등성을 보장합니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 3 | The header on a GET is explicitly ignored (only GET is named; DELETE is not) | 「GET 요청에 추가하는 멱등키 헤더는 무시됩니다」 | https://docs.tosspayments.com/reference/using-api/authorization |
| 4 | English guide frames the header as POST-only too | "ensure API POST requests are only made once" | https://docs.tosspayments.com/en/api-guide |
| 5 | A key is valid 15 days from first use | 「처음 요청에 사용한 날부터 15일간 유효합니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 6 | A replayed request is not re-executed; the first response is returned again | 「첫 번째 요청 응답과 같은 응답을 보내줍니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 7 | English guide: error responses are also replayed on key reuse | "the same response ... even in the case of an error" | https://docs.tosspayments.com/en/api-guide |
| 8 | Dedupe tuple is (key, API key, API address, HTTP method) — the request BODY is not part of the documented match | 「멱등키와 API 키, API 주소, HTTP 메서드 조합」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 9 | Reusing a key string across different API key / URL / method is explicitly fine | 「HTTP 메서드가 다르다면 같은 멱등키를 사용해도 괜찮습니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 10 | Concurrent replay while the first request is processing → HTTP 409 | 「HTTP `409 - IDEMPOTENT_REQUEST_PROCESSING` 에러가 돌아옵니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 11 | Key >300 chars → 400 INVALID_IDEMPOTENCY_KEY; keys should be random unique values (UUID), max 300 | 「300자보다 길면 HTTP `400 - INVALID_IDEMPOTENCY_KEY`가 돌아옵니다」 | https://docs.tosspayments.com/guides/using-api/idempotency-key |
| 12 | No idempotency-key LOOKUP API is documented on any page checked (Korean guide, headers reference, English guide, Core API reference) | — (absence claim) | https://docs.tosspayments.com/guides/using-api/idempotency-key + /reference |
| 13 | Where the header applies, the docs do call it out — the payment-cancel (POST) reference advertises it for safe retries | 「멱등키를 요청 헤더에 추가하면 중복 취소 없이 안전하게 처리됩니다」 | https://docs.tosspayments.com/reference |

**What this answers for Q1 (replay half), at documentation level:**
`POST /v1/billing/authorizations/issue` is a POST, and claim 1 says ALL POST-method APIs accept
the header. So the docs support: send a persisted `Idempotency-Key` on issuance → within 15 days,
an identical retry (same key, same API key, same URL, same method) returns the first response —
including, per claim 6, the original `billingKey` if the first request succeeded. That is the
strongest doc-level statement available. It is a GENERAL statement; the issuance endpoint is not
individually called out the way payment-cancel is (claim 13), and no page was found asserting
replay for this endpoint specifically. Treat it as "doc-supported, per-endpoint unverified" —
sufficient to design the persisted-intent shape now (§4), with experiment E3 (§3) as the
confirmation gate before `card_registration_live_since` is set.

**What this answers for Q1 (lookup half):** nothing positive. No lookup-by-idempotency-key API,
no list-billing-keys, no get-billing-key-by-customerKey appears anywhere checked (claim 12).
Absence of documentation, not proof of nonexistence → §3, support ticket.

### 2b. The DELETE endpoint (Q2)

| # | Doc claim | Quote (<15 words) | Source |
|---|---|---|---|
| 14 | Endpoint: `DELETE /v1/billing/{billingKey}` (section 빌링키 삭제, operationId `deleteBillingKey`), path param only, no request body | 「빌링키 삭제 DELETE /v1/billing/{billingKey}」 | https://docs.tosspayments.com/reference#빌링키-삭제 |
| 15 | Documented success: HTTP 200 with an EMPTY body | 「비어있는 body에 200 응답만 내려갑니다.」 | https://docs.tosspayments.com/reference#빌링키-삭제 |
| 16 | Its reference section lists no Idempotency-Key header — per docs the endpoint does NOT honor the header | — (absence claim; see methodology caveat) | https://docs.tosspayments.com/reference#빌링키-삭제 |
| 17 | Failures return a `{code, message}` error object; the section defers to the shared auto-payment error list and states NOTHING about repeat-delete behavior | 「code, message로 이루어진 error 객체가 내려갑니다.」 | https://docs.tosspayments.com/reference#빌링키-삭제 |
| 18 | Curated per-endpoint error list (x-errors) for `deleteBillingKey` is exactly: 400 INVALID_REQUEST · 400 INVALID_BILL_KEY_REQUEST · 400 BILLING_KEY_NOT_FOUND · 404 NOT_FOUND_BILLING | 「BILLING_KEY_NOT_FOUND … 빌링키가 존재하지 않습니다」 | https://docs.tosspayments.com/reference/error-codes |
| 19 | `ALREADY_REMOVED_BILLING_KEY` exists in the platform-wide catalog — but ONLY as a bare enum string: no message, no HTTP status, no endpoint attribution anywhere | `"BILLING_KEY_NOT_FOUND","ALREADY_REMOVED_BILLING_KEY"` | https://docs.tosspayments.com/reference/error-codes |
| 20 | Methodology: the embedded OpenAPI data dumps the full platform error catalog identically into every status block of every operation — only the curated x-errors arrays are per-endpoint evidence | — | https://docs.tosspayments.com/reference (embedded spec, parsed deleteBillingKey op) |
| 21 | No rate limit documented for this endpoint; FORBIDDEN_CONSECUTIVE_REQUEST (403) is curated only for two payment GETs and payment-cancel — not for this DELETE | 「반복적인 요청은 허용되지 않습니다.」 | https://docs.tosspayments.com/reference/error-codes |
| 22 | Deletion is framed purely as hygiene for unused keys; optional | 「사용하지 않는 빌링키는 빌링키 삭제 API로 삭제할 수 있습니다.」 | https://docs.tosspayments.com/guides/v2/billing/integration-api |
| 23 | Only lifecycle statement: a billing key's validity equals the linked card's expiry; nothing on resurrection/re-issuance of a deleted key's id (zero hits for 재발급/복구/다시 발급/삭제된 빌링키) | 「빌링키의 유효기간은 … 카드 유효기간과 같습니다.」 | https://docs.tosspayments.com/guides/v2/billing/integration-api |
| 24 | Release notes contain zero entries about this endpoint's semantics | — (absence claim) | https://docs.tosspayments.com/resources/release-note |
| 25 | Source hygiene: `docs-pay.toss.im/reference/billing/remove` is Toss **Pay** (a different product), not Toss **Payments** — surfaced in search, must not be cited for the PG | — | https://docs-pay.toss.im/reference/billing/remove |

**What this answers for Q2:** the endpoint's shape and happy path (claims 14–15), and that
idempotency-by-header is structurally unavailable on it (claims 1–3, 16; already reflected at
`supabase/functions/_shared/toss.ts:55-57`, which deliberately sends no key on the revoke call).
**It does NOT answer the question itself.** The blanket sentence (claim 2) says non-POST methods
self-guarantee idempotency — which SUGGESTS a repeat DELETE is safe — while the catalog's
`ALREADY_REMOVED_BILLING_KEY` enum (claim 19) suggests the opposite. Both are inference from
opposite directions; the reference section is silent (claim 17). Q2 stays open → §3.

---

## §3 What remains genuinely unanswered — support ticket and sandbox experiments

Nothing in this section may be treated as answered. Each item names the exact experiment (test
keys / sandbox — NOT run for this memo, and none of these calls have been made) or the support
question. Standing caveat on all experiments: **sandbox observation is behavior on the day it was
run, not contract** — anything load-bearing that an experiment reveals should also be confirmed
in writing by Toss support before the registration flag flips.

### Q1 — issuance replay/lookup

- **U1. Does retain-and-replay actually apply to `POST /v1/billing/authorizations/issue`?**
  Doc-supported generally (§2a claim 1) but never stated per-endpoint. The repo already RELIES on
  this behavior for billing charges (`supabase/functions/_shared/toss.ts:102-106` — "Toss retains
  a key for 15 days and REPLAYS the first response"); whether it holds for issuance is exactly the
  unverified half of Q1.
  **Experiment E3 (sandbox):** (1) obtain a fresh authKey via a STANDALONE page using Toss test client keys (never by flipping card_registration_live() in the app — the flag stays shut; the SDK docs page hosts a copyable widget) — a fresh
  `authKey` + `customerKey`; (2) `POST /v1/billing/authorizations/issue` with a minted UUID
  `Idempotency-Key: K`, record the full response (contains `billingKey` B1); (3) repeat the
  byte-identical request with the same K.
  Step 3 returns the identical first response with the same B1 and no second key is issued (check:
  a subsequent charge on B1 works; no other key exists for that customerKey) → **replay works on
  issuance** (Q1 answer A). Step 3 executes fresh or returns a spent-authKey refusal → replay does
  NOT cover issuance → answer C unless a lookup API exists.
- **U2. Does any read-only LOOKUP exist** — query a request by idempotency key, or
  list/get billing keys by `customerKey`? Not documented anywhere checked (§2a claim 12); absence
  of documentation is not proof of nonexistence. **Not experimentable** (you cannot probe an
  endpoint you cannot name) → **support ticket, question 1:** "Is there any API to look up a
  billing-key issuance by its Idempotency-Key, or to list billing keys for a customerKey?"
- **U3. Replay after the issued key is later DELETEd:** does the same K still replay the original
  200-with-billingKey after B1 is destroyed? Matters because a recovery sweep's replayed 200 must
  not be read as "key is live".
  **Experiment E3b (extends E3):** after E3, `DELETE /v1/billing/{B1}`, then re-POST with K again.
  Replayed original 200 → the sweep must treat a replayed response as "what happened then", never
  "state now". An error → record its code.
- **U4. Replay with a DIFFERENT body on the same key/endpoint:** the documented dedupe tuple
  omits the body (§2a claim 8), which SUGGESTS the cached response returns regardless of body —
  inference, not doc text; no Stripe-style "key reused with different parameters" error is
  documented.
  **Experiment E4:** repeat E3 step 3 with the same K but a different `customerKey` in the body.
  Cached first response returned → body truly ignored (a sweep MUST therefore guarantee it
  replays only its own intent's key, since Toss will not catch a mismatch). An error → record it.
- **U5. What does a FRESH issuance POST with a spent/expired authKey return?** This is the
  "original request never reached Toss" arm of the recovery sweep — the refusal code is what lets
  the sweep close an intent as dead-nothing-issued.
  **Experiment E5:** mint a new key K2 (never sent), POST issue with an authKey already consumed
  in E3. Record the exact `{code, message}` + HTTP status.
- **U6. Are ERROR responses replayed per the Korean docs too?** Only the English guide says so
  (§2a claim 7); the Korean 멱등키 guide is silent. E5 followed by an identical re-POST of K2
  settles it observationally; **support ticket, question 2** confirms it contractually.

### Q2 — repeated DELETE

- **U7. What does `DELETE /v1/billing/{billingKey}` return for an ALREADY-deleted key?** Docs
  silent (§2b). If an error: is it `ALREADY_REMOVED_BILLING_KEY` (bare enum, no status/message
  anywhere — §2b claim 19) or `BILLING_KEY_NOT_FOUND`?
  **Experiment E1 (the decisive one):** (1) issue a test billing key; (2) DELETE it — expect 200
  empty body; (3) send the byte-identical DELETE again. Outcomes:
  - second 200 → **idempotent success** (Q2 answer A);
  - error body with `ALREADY_REMOVED_BILLING_KEY` → **distinguishable "already gone"** (answer B);
    record its HTTP status and message — undocumented anywhere;
  - `BILLING_KEY_NOT_FOUND` / `NOT_FOUND_BILLING` → ambiguous with never-existed; run E2.
- **U8. Never-existed vs formerly-valid-deleted:** which code fires for a well-formed but
  never-issued billingKey? The curated list offers BILLING_KEY_NOT_FOUND (400) and
  NOT_FOUND_BILLING (404) with no stated trigger conditions for either (§2b claim 18).
  **Experiment E2:** DELETE a syntactically plausible, never-issued billingKey; compare the code
  against E1 step 3. Same code → "already deleted" is NOT distinguishable from "never existed"
  (weakens answer B to answer A-or-C); different codes → full answer B.
- **U9. Idempotency-Key header ON a DELETE — ignored (as documented for GET) or rejected?** Docs
  only name GET as ignoring it (§2a claim 3). Fold into E1: send the header on one of the
  DELETEs; a 200 means ignored-or-honored, a 4xx means rejected. Low stakes (the worker sends
  none), worth one data point.
- **U10. Rate limit / lockout on repeated DELETEs:** not documented for this endpoint (§2b claim
  21) — absence of documentation is not absence of enforcement. E1/E2's handful of calls cannot
  falsify a limit; **support ticket, question 3.**
- **U11. Can a deleted billingKey id ever RECUR (resurrection / re-issuance of the same value)?**
  Docs silent (§2b claim 23). Not experimentable in bounded time → **support ticket, question 4.**
  Matters for whether `billing_key_revocations` rows can be keyed on the bare key value forever.

### Cross-cutting

- **U12. Does a CHARGE against a deleted key return a distinguishable "key absent" code?** Never
  asked anywhere yet (reproducible: `git grep -i 'idempotency' origin/redesign-v4 origin/rescue/wip-0157-billing-hardening-2026-08-28 -- supabase docs` returns no support-ticket artifact). This is what would let the charge path recognize finding 4's
  end state (Postgres-current, Toss-destroyed) as "re-register your card" instead of an
  unexplained decline.
  **Experiment E6:** after E1, POST a test billing charge against the deleted B1; record the
  exact code.
- **U13. Sandbox-vs-live parity** for everything above → **support ticket, question 5:** "Do
  test-key (sandbox) responses for the billing issue/delete endpoints match live behavior,
  including error codes?"
- **U14. Ownership:** asking Toss is still UNOWNED (`docs/session-handoff.md:340-344`, still true
  as far as this worktree shows). This memo does not change that; it only makes the ticket
  writable in one sitting.

**Suggested single support ticket** (so it is one ask, not five): questions U2, U6, U10, U11, U13
verbatim from above, plus "what is the documented response of `DELETE /v1/billing/{billingKey}`
when the key was already deleted, and what are the HTTP status and message of
`ALREADY_REMOVED_BILLING_KEY`?" (U7 in contractual form).

---

## §4 Fix-design implications per finding, per branch

### Design-now core (correct under EVERY branch — the backend need not wait for §3)

1. **Persist an issuance intent BEFORE calling Toss.** Today the issuance `Idempotency-Key` is a
   per-attempt `crypto.randomUUID()` minted inside `tossBillingIssue` and persisted nowhere — it
   dies with the isolate (`supabase/functions/_shared/toss.ts:168-179`, `:175`), and
   `registerBillingKey` calls `tossBillingIssue` at
   `supabase/functions/register-billing-key/handler.ts:222` with nothing durable written first
   (everything before it is a read, `:190-198`; a thrown issue call propagates with no
   compensation — `compensateUntrackedKey` runs only after a failed swap, `:262`, i.e. only when
   the response WAS received). **Every Q1 branch (A, B, and C) starts with the same move:** mint
   the key server-side, write an intent row (uid, customer_key, minted key, state='issuing')
   before `:222`, fail closed if that write fails, and pass the persisted key into
   `tossBillingIssue`. Under A the row enables replay recovery; under B it is what a lookup is
   keyed on; under C it IS the durable record finding 3 demands ("no durable record before Toss
   is called", `docs/reviews/2026-08-28-codex-billing-chain.md:35`), converting "in neither table
   nor queue" into "named by an unresolved intent". Build it immediately.
2. **Key discipline from the docs** (all §2a): key ≤300 chars, UUID-shaped (claim 11); one key
   per intent, never reused across intents (claims 8–9 make cross-endpoint reuse technically
   safe, but the dedupe tuple omitting the body means Toss will NOT catch a body mismatch —
   pending U4, assume the cached response comes back regardless of body, so the key must uniquely
   name the intent); a recovery re-POST must be byte-identical to the original.
3. **15-day clock on the intent row** (claim 5): replay is only doc-supported for 15 days from
   first use. The recovery sweep must resolve intents well inside that window, and an intent
   still unresolved near day 15 must ESCALATE to a human/support path rather than re-POST —
   past expiry a re-POST is a fresh execution, and whether it refuses (spent authKey, U5) or
   executes is exactly what must not be guessed.
4. **Sweep must handle 409 `IDEMPOTENT_REQUEST_PROCESSING`** (claim 10) as "first request still
   in flight — back off and retry", a state the current code never sees because it never reuses
   a key.
5. **Replayed errors are terminal** (claim 7, English guide; Korean confirmation pending U6): if
   the first request errored, the same error comes back on that key for the 15-day replay window (after expiry a re-POST is a fresh execution — core #3) — the sweep must
   close such an intent on the replayed error, not loop on it.
6. **No idempotency header on the DELETE side, ever** (claims 1–3, 16): already the code's
   posture (`_shared/toss.ts:55-57` — 「멱등키 헤더는 **POST 전용**이고」; an earlier version
   copied 12 chars of the credential into the header, `:144-149`). Q2 can only be answered by
   the DELETE's documented response semantics, never by adding a key to it.

### Finding 3 (HIGH — no durable record before Toss is called; arms on the registration flag
alone; `docs/reviews/2026-08-28-codex-billing-chain.md:35`, `:12-14`)

| Q1 branch | Status | Fix shape |
|---|---|---|
| **A — replay works on issuance** | Doc-supported generally (§2a claim 1); per-endpoint UNVERIFIED until E3 | Intent row (core §1 above) + recovery sweep re-POSTs the same authKey+customerKey+key on any lost response. Replay → original response → billingKey recovered → complete the swap or enqueue revocation. Original never reached Toss → retry executes fresh (fine — first execution) or gets a spent/expired-authKey refusal (U5's code) → nothing was issued → intent closed dead. Every arm resolves; finding 3's window closes to "recovered on next sweep" (design implied by `handler.ts:222` + `toss.ts:168-179`). Caveat from U3: a replayed 200 is history, not liveness — the sweep must still reconcile against `billing_keys` before acting. |
| **B — a lookup API exists** | UNKNOWN (U2; support ticket) | Same intent row; recovery QUERIES instead of re-POSTing — strictly safer (zero risk of a fresh execution): read the outcome, then store the key or enqueue its revocation. The review's "query instead of guessing" shape (`review:127-131`). |
| **C — neither replay nor lookup** | The fallback if E3 fails and support says no | Finding 3 cannot be made machine-recoverable. Honest design: the fail-closed pre-flight intent row (already built per core §1) + escalation keyed on `toss_customer_key` — which the existing last-resort confession log already names as "what a provider-side reconciliation must be keyed on" (`handler.ts:163-174`). Fully closing finding 3 then requires Toss support involvement per incident; this is why guessing is forbidden. |

**Backend can start now:** the intent row, the sweep skeleton, the 15-day/409/replayed-error
handling (core §2–5) are branch-independent. Only the sweep's RESOLUTION arm (re-POST vs query
vs escalate) waits on E3/U2.

### Finding 4 (HIGH — ambiguous swap compensation can revoke the key it just stored;
`docs/reviews/2026-08-28-codex-billing-chain.md:36`)

Current shape (rescue branch): on swap error the handler runs `compensateUntrackedKey` then
throws (`handler.ts:255-263`). Compensation is deliberately ENQUEUE-FIRST, and the outbox path
can never destroy a stored key — `claim_billing_key_revocations` abandons any outstanding row
whose key is currently in `billing_keys` (0143 §B belt,
`supabase/migrations/0143_revocation_live_key_belts.sql:186-191`). The SURVIVING finding-4 arm is
the inline `tossBillingRevoke` fallback taken only when the outbox is unreachable
(`handler.ts:150-157`), self-described as possibly "destroying a key the swap actually stored"
(`:146`).

| Q1 branch | Fix shape |
|---|---|
| **A or B** | Delete the inline blind-DELETE arm outright. With a persisted pre-call intent the key is never "untracked": when the durable store is down, the correct move becomes "do nothing now — the recovery sweep resolves later against `billing_keys` via 0143 §B" instead of guessing at Toss while blind (`handler.ts:139-157`, `:129-137`). |
| **C** | The inline arm remains a documented judgment call: destroy a possibly-stored key vs leave an untracked live credential. Keep it, keep the confession log, and record the trade-off in the handler comment. |

Q2's contribution to finding 4 is **detection economics only**: a distinguishable "key absent"
answer (Q2-B) makes an executed revoke self-reporting about whether the key existed — but DELETE
can never serve as a read-only probe, since it destroys on hit. U12 (charge-against-deleted-key
code) is what would make the finding-4 end state recognizable on the charge path as
"re-register your card".

### Finding 6 / revoke worker (repeated DELETE by construction; `handler.ts:64-68`,
`revoke-billing-keys/handler.ts:67-73`)

Repeat DELETEs are structural, not just bugs: a worker that DELETEd at Toss and crashed before
reporting leaves a leased 'processing' row; lease expiry re-claims it and a second DELETE is
sent. The claim-token CAS protects only the RECORD; it cannot deduplicate the provider call.
Current forced posture (`revoke-billing-keys/handler.ts:49-66`): only 2xx is success (`:54`),
404 is failure labeled wrong-URL (`:60`), thrown = retry, 8 attempts → abandoned → pages a human
(0155). The worker's own comment records the gap: 「이미 삭제된 키의 응답을 규정하지 않는다」.

| Q2 branch | Fix shape |
|---|---|
| **A — repeat DELETE is idempotent 2xx** (suggested by §2a claim 2; UNVERIFIED until E1) | Worker can blind-retry: crash-repeat DELETE returns 2xx, row closes 'done' honestly; the false-abandoned-via-double-delete class disappears; 0157's `billing_key_revocations_outstanding_uq` (`register-billing-key/handler.ts:91`) becomes defence-in-depth rather than load-bearing; 2xx-only posture stays as-is; 404 remains purely a wrong-URL signal. |
| **B — distinguishable "key absent" code** (suggested by §2b claim 19; UNVERIFIED until E1/E2 — and E2 must show it differs from never-existed) | Map that CODE **matched in the response body, never the bare 404 status** — a wrong URL also 404s; `NOT_FOUND_HTTP_METHOD` burned the first version of this worker: the outbox drained 100% clean while deleting zero keys (「성공 탐지기가 실패 상태와 정확히 일치했다」, `_shared/toss.ts:128-146`; `revoke-billing-keys/handler.ts:44-61`) — to "obligation already discharged → done". Restores the "already deleted = purpose achieved" reading safely, collapses the false-abandoned class, and lets crashed-worker repeats and doubly-enqueued rows self-resolve instead of paging humans. |
| **C — stays undocumented/ambiguous** (if E1 is inconclusive AND support won't commit) | Current conservative design becomes permanent: 2xx-only success, retry-then-abandon paging humans who cannot distinguish "key still live" from "key already gone" without asking Toss, `outstanding_uq` staying load-bearing. This is exactly the "design around by guessing" state the review forbids as a basis for turning registration on (`review:127-131`). |

**Observability tie-in (0150):** the due predicate `attempts < 8`
(`supabase/migrations/0150_revocation_tick_is_answerable.sql:302-305`, `:413-415`) is what drops
abandoned rows out of `due_now` — so the Q2 answer decides whether the abandons the system pages
about are real outstanding obligations or already-discharged ones. Under Q2-B, some historical
abandons become retro-classifiable as discharged.

### Non-blocking context

- Neither finding is already fixed on the rescue branch: the reviewed freeze `719d2d5` already
  contained enqueue-first `compensateUntrackedKey`; the only post-review register-handler delta
  is the 0157 `outstanding_uq` acceptance (+33 lines) plus a constant-time-compare note in the
  revoke worker (git diff `719d2d5..origin/rescue/wip-0157-billing-hardening-2026-08-28`).
  0157 narrows finding 6; findings 3/4 remain open pending the provider answers.
- The codex raw log was not committed (`review:6-7`), so whether codex's full finding text for
  3/4 carries additional fix-shape constraints beyond the review summary cannot be checked from
  the repo. UNKNOWN; low expected value, but noted.
- Everything is latent today: both money flags NULL, 0 billing keys (`review:12-14`, `:35`).
  This memo is critical-path work for flipping `card_registration_live_since`, not incident
  response.
