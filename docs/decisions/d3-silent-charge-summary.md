# ② D-3 — Silent charging: is one-time consent enough?

**Status: ✅ RULED BY SEAN 2026-08-13 — option A: ACCEPT AS-IS. Nothing to build.**
No per-charge push **and no monthly summary**. Price shown once at request, card-link
consent covers actuals-based charging, receipts on demand, exceptions loud.

> ⚠ **THE MONTHLY-SUMMARY SLICE IS CANCELLED, NOT DEFERRED.** An earlier version of this
> memo recorded option B (monthly in-app summary) as adopted and spec'd it in detail —
> immutable `(owner, period)` statement rows, KST bucketing, amount-free push, typed tap
> routing, a disengaged-owner recurring pause. **Sean declined all of it.** That spec is
> struck below and must not be inherited as a green light by a cutover-slice builder.
> Recorded loudly because this is the single highest-waste error in the whole memo set:
> the ruling was made in the charge-slice session and sat unpushed on one laptop while
> this directory told every session B was adopted.

## What was decided and why

The T5 hole is real — an owner with card-issuer notifications off is charged with no
in-app signal. Sean accepted that exposure rather than trading away the price-invisibility
doctrine the token model was abandoned in favour of. The mitigations that already exist
and stay: `/payments` 결제 관리, booking-detail 결제 내역, loud decline/debt/lock states,
and the card issuer's own 승인 알림.

## What survives the ruling

- **The counsel question is NOT cancelled.** It changes role: it is now *validation of a
  chosen direction* rather than a fork. Ask specifically about 전자상거래법 정보 제공
  duties, 여신전문금융업법 자동결제 disclosure, and whether the 자동결제 심사 itself
  imposes notification terms. If counsel says per-charge or periodic notice is mandatory,
  this ruling is revisited — legal obligation outranks doctrine.
- **The 전자상거래법 footer stays mandatory** (사업자 정보 + 통신판매업 신고번호) on the
  payment surfaces the day those numbers exist. A legal requirement of the screen, not a
  design choice. Omitted today rather than faked, because the numbers don't exist until
  사업자등록 lands.

## ~~Cancelled spec (struck — do not build)~~

~~Monthly in-app summary: immutable statement row unique on `(owner_id, period)`, KST
bucketing (pg_cron runs UTC), gross + cancel fees by confirmation time, refunds as their
own line in the next statement, amount-free push body because 0024's trigger pushes the
body verbatim with sound, typed tap routing (system-kind notifications dead-end today),
recurring generation pause after 8 completed runs with zero app opens.~~

Kept visible rather than deleted so that if counsel later forces a periodic notice, the
design work is not redone from scratch — but it is **not authorised** today.

## Options as they were put

| # | Response | Cost |
|---|---|---|
| **A** | **Accept as-is — RULED** | Zero. Depends on counsel agreeing. |
| B | Per-charge push | Small build; costs the Kakao-T invisibility deliberately chosen. |
| C | Monthly summary | Small-medium; keeps per-run invisibility, satisfies a "must be told" reading. |
