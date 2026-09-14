# club-v2 labs — index

The sanctioned mockup arena for the club-v2 screens. Each lab is a self-contained HTML file:
phone frames at 390×844, numbered variants ①②③ side by side, one line of rationale each.
**Sean picks by number.** Implementation then binds real fields only — an element with no field
is drawn as omitted inside the lab, never invented at build time.

There is no `docs/labs/README.md`; this file indexes the club-v2 family only.

## Awaiting a pick — added 2026-09-15

| lab | what it decides | spec / ruling it binds to | pick |
|---|---|---|---|
| [`club-v2-chat-tiers-lab.html`](club-v2-chat-tiers-lab.html) | how the tier boundary is drawn to the signed-up-but-unpaid **reader** — the composer's seat is filled, never disabled | rulings 2026-08-31 §4 (OPEN-B three-tier) · spec v2 §9 · `0049_session_shell.sql` | ⬜ |
| [`club-v2-hold-lab.html`](club-v2-hold-lab.html) | countdown prominence **and** expiry copy for the 20-minute hold, judged as one pair | rulings 2026-08-31 §4 (OPEN-A 「Hold ~20 min」) · `0043_payment_separation.sql` | ⬜ |
| [`club-v2-host-setup-lab.html`](club-v2-host-setup-lab.html) | the control vocabulary of the **host's** session setup — segmented vs list vs cards | spec v2 §16.7 / §16.7a · §10.2a · §6.4 · `0037`, `0129` | ⬜ |
| [`club-v2-pack-map-lab.html`](club-v2-pack-map-lab.html) | viewer-counter placement and roster-strip density on the public pack map | Sean 2026-08-28 「total public」 · 2026-08-31 「Yes, add counter」 · `0159`, `0160` | ⬜ |

### Three things these four labs report upward rather than draw

1. **The tier-② server does not exist.** `club chat read` (0049:78-83) admits `host`/`full` only,
   and `_club_shell_access` grades `full` on **approval**, not payment — so an approved-unpaid
   owner can already post today, and a merely-signed-up one cannot read. Both arms move, in
   opposite directions, and the write arm is a *narrowing of a shipped right*.
2. **「Access ends with the hold」 is not what the code does.** `_club_shell_access` never reads
   `hold_status`. Per the ruling's own instruction this goes back as a console question rather
   than being settled by a drawing.
3. **The viewer counter has no reader.** `pack_map_roster_reads` is RLS-on with zero policies and
   revoked from `anon`/`authenticated`; 0160's own comment says 「nothing reads it but a human with
   a psql prompt」. Placement is pickable now; the value needs one small definer.

## Already in the arena

Listed for orientation only — **their pick status is not recorded here**, because this file's
author did not verify it and a guessed ⬜ would be a false green in documentation.

- `club-v2-pick-lab.html` — 러너 픽 (start list · wait · confirmed stub)
- `club-v2-board-lab.html` — the delegation board
- `club-v2-console-lab.html` — the host console
- `club-v2-run-lab.html` — the run screen
- `club-v2-setup-lab.html` — **the OWNER's sign-up setup flow** (r5). Not superseded by
  `club-v2-host-setup-lab.html`: that one is the host's counterpart, and the two meet only at
  `pickup_mode`/`return_mode`, which the **owner writes** and the **host only reads**.
- `club-v2-livemap-lab.html` — the HOST's live map, run-end branch and session pass (r6+r7). Not
  superseded by `club-v2-pack-map-lab.html`: different gate (host vs anon-public), different
  function, different audience.
