# ⑧ Card registration placement

> 🔴 **REVERSED — Sean, 2026-08-26.** His words: *「this card thing should be an onboarding thing.
> the entire reason behind why i want the card registration to come before the run is to mentally
> separate money leaving from the actual run service.」*
>
> **The card step moves INTO onboarding.** The 2026-08-13 agreement below is superseded and kept
> in full, because its three reasons are still the real costs of this move and a later reader
> needs to see what was traded, not just what was chosen.
>
> **His axis is one the original argument never considered.** The three reasons below optimise for
> CONVERSION (reason 1) and for CONSENT QUALITY (reasons 2-3). He is optimising for something else
> entirely: the *perceived relationship* between paying and the service. Putting the card moment
> next to the booking couples them — the owner feels they are paying for this run. Putting it at
> signup makes it account setup, and the run afterwards feels free at the point of use. That is a
> positioning decision and it is his to make; it does not refute reasons 1-3, it outranks them.
>
> **What it costs, stated so it is not discovered later:**
> - **Reason 1 stands and is now a bill we choose to pay.** A card ask before any delivered value
>   is a real drop-off point, and it lands on every signup including people who never book.
> - **Reason 3 is the one with legal weight and it is NOT automatically satisfied.** Under price
>   invisibility this screen is the only place an owner consents to actuals-based charging, and
>   memo ②'s "no per-charge notice" defence leans on that consent having happened somewhere real.
>   Onboarding is exactly where reason 3 warned it would be *buried between 「add your dog」 and
>   「allow notifications」 where nobody reads*. **So the move is only safe if the card step is a
>   DELIBERATE FULL SCREEN carrying the consent sentence — never a row, a checkbox, or a squeezed
>   field.** That constraint is now load-bearing rather than stylistic.
> - **It reaches NEW USERS ONLY.** `app/app/index.tsx:83-98` routes an owner with ≥1 dog straight
>   to home, so nobody already in the app ever sees onboarding again, and nothing backfills. For
>   every existing account the arrears path remains the only route — which is why it still gets
>   built (§F.1's 「allow them to book but make sure they pay afterwards」).
> - **It does NOT become a hard gate.** A card can be declined, expire, or be skipped, and his
>   F.1 ruling says booking stays open regardless. Onboarding is where we ASK; the after-the-run
>   collection path is still what guarantees payment.
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
