# Q4 — the handoff CTA fires one state too late (owner home)

**Status: 📋 AWAITING SEAN — one question, two candidate answers, both spelled out below.**
Queued as P4 of `docs/plans/2026-08-20-client-gap-straightening.md:29` and as Q4 at :137.
Written 2026-08-20 (night) by the client session in the main checkout
(`laughing-elgamal-a1fcc3`), under the second overnight grant.

**Why this is in front of you rather than already built.** The grant says decide independently,
and I would have. But two separate sessions carved *this specific item* out for your ruling on
this same day, and you accepted that carve-out. A general "keep going" does not reverse a
specific "wait" — that is the shape of reasoning the money set already paid for once
(*a relayed decision is evidence, not authority*). So it is queued, not shipped. **The answer
is one word and I have written both versions of the code path underneath it.**

---

## The question, in one line

On owner home, when the runner has **arrived at the pickup point and is standing there waiting
for you**, the screen renders calm and the coral 「인계하기」 button is not shown. It appears
**after** the handoff is already finished. Should home light up at arrival instead?

---

## What is actually true in the server (verified, not remembered)

The server is not wrong here and does not need to change. Its design is deliberate and documented
in its own comments:

| step | what the server stores | `bookings.status` |
|---|---|---|
| runner sets off | — | `runner_enroute` |
| **runner arrives at pickup** | **`arrived_at` timestamp** | **still `runner_enroute`** |
| one side taps 인계 확인 | that side's `*_confirmed_handoff_at` | still `runner_enroute` |
| **both** sides have tapped | — | → `picked_up` |

- Arrival is **a timestamp, not a state**, on purpose. `transition-booking/index.ts:275-277`
  says why in as many words: *"상태를 건드리면 보험·정산 기점이 앞당겨진다"* — moving the status
  at arrival would drag the insurance and settlement basis earlier. **Do not "fix" that.**
- `picked_up` requires **both** confirmations (`confirm_handoff` arm, re-reads fresh and only then
  sets `picked_up`). So `picked_up` means *the handoff is done*, not *do the handoff*.

## Where the client goes wrong

`STATUS_MAP` (`app/src/lib/api.ts:732-748`) flattens the seven server states into six display
words. Two rows matter:

```
runner_enroute: 'confirmed',   ← arrival is invisible here: enroute and arrived are the same word
picked_up:      'handoff',     ← "handoff" means handoff FINISHED
```

Home then derives its hero state from that flattened word (`app/app/owner/home.tsx:231-237`):
`liveNext?.status === 'handoff' ? 'handoff'`. So the coral 「인계하기」 call-to-action is bound to
`picked_up` — **the state that means the dog has already changed hands.** And the moment that
genuinely needs the owner — runner standing at the pickup point — is `runner_enroute`, which home
renders as the calm 'confirmed' state, identical to a booking whose runner has not left home yet.

This is a textbook instance of the law already in CLAUDE.md: *when display vocabulary flattens
server states (STATUS_MAP), gate logic and badges on `rawStatus`.* Home gates on the flattened
word. `rawStatus` is already carried on every booking (`api.ts:3969`, with a comment saying it
exists for exactly this purpose) and is simply unused here.

## The fact that makes this narrower than it looks

**The meetup screen already implements the rule I am asking about, and already has your sign-off
on it.** `app/app/owner/meetup.tsx:335-338`:

```
앰버 = 아직 내 차례가 아님 · 코랄 = 내 차례. 도착은 스테이지가 아니라 arrivedAt이
결정한다 (머신 매핑은 동결) — 코랄은 arrivedAt이 참일 때만 켜진다.
```

Coral there turns on **only when `arrivedAt` is true**. So the app currently holds two different
answers to the same question on two screens one tap apart: meetup says *coral = the runner is here,
your turn*; home says *coral = the handoff is over*. **This is less "should we add a feature" and
more "home is the one screen not following the rule."**

---

## The two candidate answers

### A — gate home on arrival (recommended)

Home's coral CTA fires at `rawStatus === 'runner_enroute' && arrivedAt`. `picked_up` stops being
a call to action and becomes a calm "인계 완료 — 곧 러닝이 시작돼요" state, which is what it
actually means.

- **For:** removes the contradiction with meetup; puts the loudest thing on the screen at the one
  moment the owner is physically needed; kills a CTA that currently asks for an action already
  completed (a dead button in the honesty-law sense — it routes somewhere real but the ask is
  false). Directly serves your standing steer, *"ease of click in flow for a smooth path to a
  live run."*
- **Against:** the owner is likely already inside meetup when the runner arrives (they got a push),
  so home's version of this may fire mostly for people who backed out to home. It is a smaller win
  than it looks.
- **Server change: none.** Client-only.

### B — leave it, and fix only the false ask

Keep home calm through arrival; change only the `picked_up` copy so it stops saying 인계하기 when
the handoff is finished.

- **For:** smallest possible change, zero risk to the frozen meetup flow, and it fixes the part
  that is unambiguously a lie without adding a new attention-grabber to home.
- **Against:** leaves home and meetup disagreeing about what coral means, which is the kind of
  inconsistency that costs a user trust once and never announces itself.

**My recommendation: A**, with B's copy fix included in it (A needs it anyway — under A,
`picked_up` still needs its own calm wording). If you want the minimum tonight, B is safe and
does not foreclose A.

---

## What it costs to build, either way

The plumbing is identical for A and B and is **purely additive**: `fetchMyBookings` does not
select `arrived_at` today, so home cannot see arrival at all. Add the column to that select and
thread `arrivedAt` onto the `Booking` type. No existing caller changes behaviour — the shape
already exists one function away as `BookingSync` (`api.ts:1026-1046`), which meetup uses.

Then A is a one-line change to the `goState` ternary at `home.tsx:231`; B is a copy change.

⚠ **Frozen-zone note:** this touches home only. `owner/meetup.tsx`'s stage machine and
`confirmHandoff` flow are frozen and **must not** be edited for this — meetup is already correct.
Whoever builds it should prove the frozen ranges byte-identical the way `2ddac83` did.

## Related, and deliberately NOT bundled

`no_show` is a legal transition from `confirmed` (`0001:205`) that **nothing anywhere sets** —
no edge function writes it. If a runner never arrives, there is no state for it. That is a real
gap and it is the mirror image of this one, but it is server work and needs its own question.
Queued separately as Q5.
