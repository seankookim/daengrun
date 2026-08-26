# ⑧ Card registration placement

> 🔴 **SETTLED — Sean, 2026-08-26, third and final position this day.** His words:
> *「card registration should come once and that first time should be at the place where after all
> preferences have been filled in and runners have been selected and routes have been selected and
> before the actual request to the runner is sent. after that first run, there should be no card
> whatever, and the card should be changeable and manageable in settings.」*
>
> **Placement: the LAST gate of the first booking.** Not onboarding, and not the top of the
> booking flow — the seam is `owner/request.tsx`'s `pay()`, after the dog gate and the slot gate
> and immediately before `createBookingHold` (`:536`). Everything is already chosen at that point:
> dog, route, runner, time, add-ons. The card screen is the final thing between the owner and the
> request going out.
>
> **Once, then never again.** First booking only. Afterwards there is no card step anywhere in the
> flow; the card is changed and managed in 설정 › 결제 관리 (`payments.tsx`), which already exists.
>
> ⚠ **Two earlier positions were recorded on this branch today and BOTH are superseded by this
> one** — an onboarding step (reversed), and before that the original 2026-08-13 「inline at first
> booking」. They are kept below rather than deleted because the reasoning is what carries forward.
>
> **This position is stronger than either on the ORIGINAL document's own three criteria, which is
> worth stating because it means nothing was traded away to get it:**
> - **Reason 1 (drop-off) is best served here, not merely tolerated.** The ask lands at PEAK
>   INTENT — after the owner has picked a dog, a route, a runner and a time. Onboarding asked
>   before any of that investment existed; the top of the booking flow asked before most of it.
> - **Reason 2 (post-pay is an easier ask, but only where the user already wants a run) is
>   satisfied exactly.** They want this specific run, right now.
> - **Reason 3 (consent must happen somewhere real) is satisfied structurally.** This is a
>   deliberate blocking moment, not a row buried between two other onboarding fields — which is
>   the failure mode reason 3 named and the reason the onboarding position was risky.
>
> **And it still serves the reason he gave for moving it in the first place** — 「mentally separate
> money leaving from the actual run service」. The card moment happens BEFORE the run exists, and
> then never again: no run is ever interrupted by a payment step, and after the first booking the
> owner never sees a card screen in a flow at all.
>
> **Consequences for the build:**
> - The gate is 「no billing key」, not 「first booking」 — those coincide for a new owner and diverge
>   when a card is later removed or expires. Keying on the card is the honest predicate; keying on
>   a booking count would let a card-less owner through on their second attempt.
> - It is NOT a hard refusal. §F.1 stands: 「allow them to book but make sure they pay afterwards」.
>   The screen carries a quiet way past it, and the after-the-run collection path remains what
>   guarantees payment — for skippers, for expired cards, and for every account that predates this.
> - `payments.tsx` keeps ownership of change/manage. This slice adds the first-time gate and the
>   card-link screen itself; it does not build a second management surface.
>
> ---
>
> **SUPERSEDED, preserved verbatim:**

**Status: ⛔ SUPERSEDED 2026-08-26 (was: ✅ AGREED — inline at first booking).** Authored in the charge-slice session;
ported here at consolidation (text preserved).

**Placement: inline at first booking, plus one skippable soft prompt at the end of onboarding.**

Three reasons, in increasing order of weight:
1. A card ask before any delivered value is the most reliable drop-off point in consumer
   onboarding, and we would pay it against users who may never book.
2. Post-pay makes the ask *weaker* than normal — "카드를 연결해두면 러닝이 끝난 뒤 결제돼요" is
   much easier to accept than a prepayment — but only if it is said where the user already wants
   a run.
3. **Under price invisibility, the card-link screen is the only place the owner consents to
   actuals-based charging.** That makes it a consent moment, not a settings chore, and it must
   not be buried between "add your dog" and "allow notifications" where nobody reads. This is
   also what memo ② leans on: A (no per-charge notice) is defensible *because* consent happened
   somewhere real.

Consequence for the card-register slice (blocked on Sean's Ⓐ lab pick): it is a deliberate
one-step sheet with real consent copy, reachable from first booking AND from the club refusal
(ruling ⑤) AND from 설정 › 결제 관리 — not an onboarding step.

---
