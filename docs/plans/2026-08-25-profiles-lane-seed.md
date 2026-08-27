# Profiles lane — SEED ONLY (not a spec, not designed)

**Status: ACTIVE — un-parked 2026-08-27 by Sean:** 「for the tap for profile, yes make it like instagram」, with his Instagram screenshots as the model (profile editor WITHOUT the avatar row). Exposing profile_id on the board is his explicit ruling, overruling contract R8. *(First un-park attempt silently no-opped on a stale pattern — the replace targeted 「Status: **PARKED**」 and the file says 「**Status: PARKED.**」. Asserted this time.)* This file exists so a ruling is not lost, and so nobody bolts it onto
club-v2. It contains one verbatim quote and a short list of what a real spec would have to
answer. **Nothing here is designed. Nothing here is proposed. Nothing here is scoped.**

---

## The seed — Sean, 2026-08-25 (sixth round, verbatim)

Relayed via ui6-a5's round-4 lab feedback channel; the full paragraph and its recording
mechanism are in `docs/decisions/2026-08-25-console-rulings.md:158-165` (this is one sentence
lifted from it, unaltered):

> "also, clicking on each names should go to their profiles with their posts (like instagram)."

Its neighbours in the same paragraph — the pack model, host approval, pair reallocation — are
club-v2 rulings and were amended into
`docs/plans/2026-08-25-club-delegation-spec-v2.md`. **This one was not**, deliberately:

Disposition (recording session — NOT his words, per
`docs/decisions/2026-08-25-console-rulings.md:181-183`): *"the first words of his deferred
community/account commentary; a NEW spec lane, not a club-v2 bolt-on. Parked as its own future
spec with this verbatim as the seed."*

## Why it is not a club-v2 bolt-on

Stated as the reason for parking, not as design:

1. **The subject is a person across the product, not a row on one board.** A profile with posts
   is an account-level surface — it outlives any session and is reachable from chat, the
   leaderboard, the community feed, and the runner-profile route as much as from the club board.
   The club board would be one entry point among several.
2. **"Posts" is a content system that does not exist.** The repo has no user-authored post
   object, no feed of one, no moderation path, and no reporting path. Club-v2 creates none of
   these and must not acquire them by association.
3. **It is a privacy decision, not a rendering decision.** The club member board is already
   effectively public by Sean's own ruling #9 (`docs/decisions/2026-08-25-console-rulings.md:19`),
   and the S2 contract's whole design constraint is that the board publishes to the neighbourhood
   (`docs/contracts/club-board-s2-contract.md:32-47`). Making a board name a tappable link into a
   richer personal surface widens what that publication reaches. That widening needs its own
   consent design and its own card — it is exactly the class the S2 contract warns about at
   trap T7 (`docs/contracts/club-board-s2-contract.md:523-525`): *"the pressure to widen will
   arrive wearing his words."*
4. **A partially-shipped version is worse than none.** A tappable name that opens a mostly-empty
   screen is a dead-end under the honesty laws.

## What already exists, so the future spec starts from facts and not from scratch

Cited, not designed:

- `app/app/runner-profile/[id].tsx` — a runner-facing profile route exists today. Whether the
  new lane extends it or supersedes it is the future spec's first question, not an assumption.
- `app/app/community.tsx`, `app/app/compose.tsx`, `app/app/leaderboard.tsx` — the closest
  surfaces to "posts" that exist. Their actual data model must be read before anything is
  proposed; nothing here claims what they hold.
- Sean's parked ruling #9 comment, same decision file, line 19 (verbatim): *"always fine; it's
  like a public dashboard. may extend it to live ranked dashboard in community."* That idea and
  this one are neighbours and probably belong to the same lane.

## What the future spec must answer before it proposes anything

Questions, not answers:

1. Whose profiles — owners, runners, both, guests?
2. What is a "post" — is it authored, or is it derived from runs/receipts the product already
   produces?
3. Who may see a profile — anyone signed in, club members, the neighbourhood, only parties to a
   shared session?
4. Does an owner get to opt out, and what does a name render as when they have?
5. What is the moderation and reporting path, and who operates it?
6. Does this supersede `runner-profile/[id]` or sit beside it?

**None of these is answered here. This is a seed.**
