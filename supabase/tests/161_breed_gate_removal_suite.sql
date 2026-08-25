-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 161 — 0127 맹견 gate REMOVAL (Slice A). Replaces suite 154, which is retired in the same commit.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean ruled removal twice, the second time with the legal-review context in front of him
-- (`docs/decisions/2026-08-25-console-rulings.md` F1, 2026-08-25 04:39:43Z: "Remove it
-- completely"). 154 pinned the gate; every one of its pins is now false-by-ruling, so its harness
-- line is dropped in this commit and this file takes its place. The file 154 stays on disk as the
-- record of what the gate did — retirement is the harness dropping it, not a deletion.
--
-- ── WHAT THIS SUITE IS FOR ──────────────────────────────────────────────────────────────────
-- A removal has two failure modes and only one of them is loud:
--   · UNDER-removal — a trigger or a caller survives. The worst case is not "the gate still
--     refuses": `dogs_dangerous_declaration` fires on EVERY dogs write, so left behind with its
--     function gone it bricks every dog profile save in the product. P2 is the one-line pin that
--     reds on exactly that, and it is the highest-value pin in this file.
--   · OVER-removal — Slice B smuggled into Slice A. The three columns, the pair CHECK and the
--     enum MUST survive here; that is what lets an old installed bundle keep working while the
--     new one distributes. P6 owns that boundary.
-- The behavioural pins (P1/P2/P5) come first and the catalog pins (P3/P4/P6) re-run 0127's own
-- VERIFY assertions — because a VERIFY runs once, at apply time, and these outlive it: they fail
-- the day someone re-creates one of these objects in a later migration.
--
-- ── EVERY PIN IS WRITTEN BOTH WAYS ──────────────────────────────────────────────────────────
-- A removal suite fails in a characteristic way: "nothing raised" scores green when the write
-- never happened at all. So every arm that asserts a success also asserts its EFFECT — a
-- count(*), a changed value, a surviving row — and every catalog absence is paired with a
-- positive control that the thing which must REMAIN is still there (0111's belts in P4, the
-- columns' writability and the pair CHECK's refusal in P6).
--
-- ── MUTATION MAP — PREDICTED, THEN MEASURED 2026-08-25 ───────────────────────────────────────
-- Each mutation is applied ALONE against the post-0127 schema, by appending its DDL to the END of
-- 0127 (after the VERIFY block, so the VERIFY still passes and the suite sees the mutated schema).
-- 12 runs, baseline 885/0. **ZERO MISSES: no predicted pin stayed green under any mutation.**
-- Seven of nine reddened a strict SUPERSET of the prediction; M7 and M8 landed exactly; M9c was
-- refused by postgres itself. The prediction lines below are left as written — the measurement
-- follows each — because a map edited to match its own results stops being evidence.
-- Three properties the battery established that the predictions did NOT say, all benign but all
-- worth knowing before anyone reads a red run:
--   ⓐ **P6 is the broadest UNDER-removal detector in this file, not the slice-boundary pin its
--      header calls it.** Its trigger-count arm (14/2/1) reds on EVERY trigger re-add — M1 through
--      M6 — because a re-added trigger changes a count, not just a behaviour. Strictly extra
--      sensitivity, but a red P6 does not by itself mean "Slice B ran early".
--   ⓑ **P5 is not isolated from the INSERT trigger.** Under M1 (an INSERT-path mutation) P5 reds,
--      because P5 ⓐ builds its own `t_av_booking` fixture through that same trigger. Its detail
--      then reads as a `_move` failure when the cause is the INSERT gate. So a red P5 ALONE does
--      not name which trigger came back — **P3 is the pin that names it.** Read P3 first.
--   ⓒ **Two detail strings degrade to a raw error under mutation.** P1's and P5's
--      `exception when others` handlers replace the accumulated `v_bad` with bare `sqlerrm`, so
--      under M1/M3 they report the token `dog_dangerous_undeclared` instead of the authored arm
--      message; under M9 the same happens to P6. The pins red correctly — they just name the
--      symptom rather than the diagnosis. Do not "fix" this by removing the handlers: an
--      uncaught raise would abort the whole suite instead of failing one pin.
-- Each mutation is applied ALONE against the post-0127 schema:
--   M1  PREDICTED  re-add `bookings_dangerous_dog` (+ its function + `dog_custody_gate`)
--                  → RED = [P1 ⓐ booking, P3 (trigger name + function names + prosrc)]
--                    (P1 ⓒ also reds: the cron INSERT goes through the same trigger)
--   M2  PREDICTED  re-add `bookings_dangerous_dog_move`  → RED = [P5 ⓐ, P3]
--   M3  PREDICTED  re-add `session_dogs_dangerous_dog`   → RED = [P1 ⓑ, P3]
--   M4  PREDICTED  re-add `session_dogs_dangerous_dog_move` → RED = [P5 ⓑ, P3]
--                  and P5 ⓒ (the ordinary-dog control) stays GREEN — that asymmetry is what names
--                  the cause as the gate rather than as a club rule
--   M5  PREDICTED  re-add `dogs_dangerous_declaration`   → RED = [P2 ⓒ latch, P2 ⓓ stamp, P3]
--                  ⚠ P2 ⓐ/ⓑ (plain insert + rename) stay GREEN with the function present — they
--                  go red only in the half-removal where the TRIGGER survives its FUNCTION, which
--                  P3's named-trigger arm catches first. Both halves are pinned on purpose.
--   M6  PREDICTED  re-add `dogs_dangerous_delete`        → RED = [P2 ⓔ, P3]
--   M7  PREDICTED  re-add `dog_custody_gate` + a synthetic caller function
--                  → RED = [P3 (function-name inventory AND the schema-wide prosrc scan)]
--                    — the mutation nothing else can see, since neither name contains "dangerous"
--   M8  PREDICTED  re-add the ⓕ belt to `generate_recurring_bookings` (needs the gate back, so M7
--                  rides along) → RED = [P4 (functiondef), P3, P1 ⓒ pit-bull series]
--                  and P1's unrelated-series arm stays GREEN — which is the pairing that tells
--                  "the gate is back" apart from "the sweep is dead".
--   M9  PREDICTED  drop one of the three columns / the pair CHECK / the enum (i.e. run Slice B
--                  early) → RED = [P6], and 0127's own VERIFY would already have refused it.
--
-- ── MEASURED (2026-08-25; 12 runs, ~27-33s each, no `[axes] X8` flake in any of them) ─────────
--   M1  MEASURED  RED = [P1, P3, P5, P6]  (881/4)  superset — P5 via ⓑ above; P6 via ⓐ
--   M2  MEASURED  RED = [P5, P3, P6]      (882/3)  superset — P5 ⓐ named it exactly
--   M3  MEASURED  RED = [P1, P3, P6]      (882/3)  superset; P5 stayed GREEN, correctly — the RSVP
--                 insert is `owner_handled`-exempt and this mutation is an UPDATE trigger
--   M4  MEASURED  RED = [P5 (ⓑ only), P3, P6] (882/3) — **the predicted asymmetry held exactly**:
--                 the detail names only 동반→위탁, with no 대조군 line. This is the arm that tells
--                 the gate apart from a club rule, and it behaved as designed.
--   M5  MEASURED  RED = [P2 (ⓒ+ⓓ only), P3, P6] (882/3) — the ⚠ above CONFIRMED: ⓐ/ⓑ green with
--                 the function present. P3's prosrc arm correctly did NOT fire (the declaration
--                 guard calls nothing that 0127 dropped).
--   M6  MEASURED  RED = [P2 (ⓔ only), P3, P6] (882/3) — ⓔ named both halves (the P0001 token AND
--                 the surviving-row count)
--   M7  MEASURED  RED = [P3 only]         (884/1)  **EXACT** — both arms fired: the name inventory
--                 and the schema-wide prosrc scan. The mutation nothing else can see was caught by
--                 the arm authored for it, and by nothing else. This is the pin that earns its keep.
--   M8  MEASURED  RED = [P1, P4, P3]      (882/3)  **EXACT** — P1 named ONLY the 핏불테리어 series
--                 (=0) while the unrelated owner's series still generated, so the pairing in ④
--                 works: it separates "the gate is back" from "the sweep is dead".
--   M9  MEASURED  drop `dogs.dangerous_declared_at` → RED = [P6, P2] (883/2); details are the raw
--                 `column … does not exist`, per ⓒ above
--   M9b MEASURED  drop the pair CHECK → RED = [P6 only] (884/1), with the authored detail
--                 "CHECK이 사라졌다 — Slice B가 앞당겨졌다". Cleanest red in the battery.
--   M9c MEASURED  drop the enum → **GUARD-REFUSED before any pin ran.** Postgres's own dependency
--                 graph refused it at apply time: `cannot drop type dog_dangerous_status because
--                 other objects depend on it / column dangerous_status of table dogs`. The column
--                 that Slice A deliberately keeps IS the guard on the enum — a structural
--                 protection nobody authored, and one Slice B must dismantle in the right order.
--   BLAST RADIUS: across all 11 runs that reached the suites, EVERY ❌ was `[mgn-off]`. No mutation
--   reddened any of the other 884 pins in either direction.
--
-- ── FIXTURE NOTES ───────────────────────────────────────────────────────────────────────────
-- ① Shared state is built at TOP LEVEL, outside every pin: a plpgsql `begin … exception` block is
--    a SUBTRANSACTION, so a catching pin rolls back everything it wrote and later pins then report
--    `not_found` about a fixture that existed a moment ago (151's header, 154's ①).
-- ② EVERY dog in this file that must exercise the removed gate is created as the SHAPE 0119
--    refused hardest: `breed = '핏불테리어'` (0119 §B's screen matched the 핏불 stem) AND
--    `dangerous_status` left at its DEFAULT `undeclared` (0119 §C refused undeclared outright,
--    before the screen was even consulted). One dog, both doors — so no arm here can be green
--    because it happened to pick the one shape the old gate let through.
-- ③ Each arm gets its OWN dog. Sharing one dog across the booking, delegation and recurring arms
--    couples them through the live-overlap guard in `generate_recurring_bookings` and through
--    `session_dogs`'s unique(session_id, dog_id) — a coupled fixture is how one failure paints
--    three red messages that name the wrong thing.
-- ④ P1 ⓒ calls `generate_recurring_bookings()`, which sweeps EVERY series in the database,
--    including those seeded by earlier suites. Its arms are keyed on `series_id`, never on global
--    counts. Both series owners get a `billing_keys` row so the 0080 `no_card` money gate cannot
--    silently suppress generation if an earlier suite left `payments_live_since` set — that would
--    red this pin for a reason that has nothing to do with 맹견.
-- ⑤ The trigger-count numbers in P6 assume the harness list in this commit. 154 created a
--    test-only trigger on `bookings` (`a_mgn_flip_dog_during_recurring_insert`); dropping its
--    harness line is what makes an exact count assertable. Re-registering 154 before this file
--    would red P6 — correctly, since the two suites cannot both be true.
--
-- ── SECOND REVIEW ROUND — codex, blind, 2026-08-25 (AFTER the battery above) ────────────────
-- The mutation map above is left EXACTLY as it was measured; a map edited to match later work
-- stops being evidence, and every one of those 12 runs is still true of the pins it tested. What
-- follows is a second pass by a fresh voice that reviewed this package blind and returned eight
-- ranked findings. Six touched this file. The pins changed, so the map GAINS entries — it does not
-- lose any. New predictions are marked PREDICTED and their measurements follow, same discipline.
--
-- What the second round actually found, in one line each, because a reader deserves the reasons
-- and not just the diff:
--   ① P4 could pass a DEAD FUNCTION. It checked three forbidden substrings, two required ones and
--      a loose `[0111]` in the comment. A stub that returns 0, mentions `owner_has_unsettled_charge`
--      and the ownership-warning literal, and keeps a comment containing `[0111]` satisfied every
--      arm. "The gate is gone" and "the feature is dead" were indistinguishable in the pin whose
--      whole job is to tell them apart. P4 now compares an exact `prosrc` digest and the exact
--      comment digest, plus language, `prosecdef`, volatility, return type, owner and ACL.
--   ② P3 called itself schema-wide while looking only at `public` and only at `prosrc`. Widened to
--      every non-system routine namespace, to `cron.job.command`, and to the refusal TOKENS as
--      well as the function names — and its text now states what it cannot see (dynamic SQL).
--      ⚠ Nothing was actually hiding there: codex searched the chain independently and found no
--      surviving caller. This closed a verification hole, it did not repair a live bug.
--   ③ P1's "unrelated control" was a `declared_none` dog — a state the current client can no longer
--      produce. That is not a defect (see the three-way note in P1: the legacy shape is exactly what
--      makes the discriminator work), but calling it "an unrelated owner's series" hid the fixture.
--      P1 now runs THREE series and says what each one is for.
--   ④ P1's two counts came from ONE `generate_recurring_bookings()` call, in a generator this very
--      landing restores to having NO per-row isolation. One raised INSERT zeroes every count and
--      looks identical to a dead sweep. The exception arm already caught that case; what was missing
--      was saying so, so the pairing is now scoped to non-raising outcomes IN THE PIN TEXT.
--   ⑤ P6 proved item-specific properties with collection counts, and accepted ANY exception as
--      proof the pair CHECK fired. Now: exact trigger NAME sets, exact column types/nullability/
--      default, the enum's ordered labels, the column→enum binding, SQLSTATE 23514 with the
--      constraint's own name, and the written timestamp observed.
--   ⑥ P5's control observed only that no exception occurred — a trigger returning NULL and silently
--      swallowing the UPDATE passed it. It now asserts the control row's END STATE, the same way
--      the subject arms already did.
--   ⑦ P2 was advertised as the detector for a broken ordinary dog write, but five top-level dog
--      inserts ran before it, so a truly corrupt trigger state aborted fixture setup before P2 could
--      report. **P2 NOW RUNS FIRST** — its ordinary INSERT is this suite's first write to `dogs`.
--      It keeps the name P2 (the numbers are names, not an order) so every reference elsewhere,
--      including the measured map above, still resolves.
-- One finding was NOT about this file: the partial-apply ACL hole in 0127 §D. That is fixed in the
-- migration (§D-bis + VERIFY ③-bis) and the standing schema-wide form lives in 98 H9.
--
-- ── SECOND BATTERY — PREDICTED (written before the runs), MEASURED BELOW ────────────────────
-- Same discipline as the first battery: predictions are written first and left unedited afterwards,
-- with the measurement following each. M1-M9c above are untouched. The new pins are the ones the
-- second review produced, so they get their own mutations — a strengthened pin nobody broke on
-- purpose is a claim, not a result.
--   M10 PREDICTED  0127's own absent-function path, WITHOUT the fix: insert
--                  `drop function generate_recurring_bookings();` immediately before §D and comment
--                  out §D-bis's revoke. `create or replace` then runs as a CREATE and the function
--                  is born PUBLIC-executable.
--                  → the HARNESS ABORTS AT 0127 (its VERIFY ③-bis raises); no suite runs.
--   M11 PREDICTED  the same absent-function path WITH §D-bis intact (drop before §D, revoke kept).
--                  → migration applies clean and the whole run is GREEN. This is the arm that
--                  proves the fix WORKS, not merely that VERIFY notices when it is missing — the
--                  two are different claims and only M10 would have tested the second.
--   M12 PREDICTED  change one byte inside the generator body (a comment character).
--                  → RED = [P4 ⓐ digest ONLY]; P4's substring arms and 0127's VERIFY stay green,
--                    which is the whole point: this is the mutation the OLD P4 could not see.
--   M13 PREDICTED  swap a surviving `dogs` trigger for an unrelated one — drop
--                  `club_dog_materiality`, add a no-op trigger — so the COUNT stays 2.
--                  → RED = [P6 ⓔ name set]. Under the old count-only arm this was invisible.
--   M14 PREDICTED  create a routine in a NON-public namespace whose body calls `dog_custody_gate`.
--                  → RED = [P3 widened scan], naming `auth.…`. The old public-only scan saw nothing.
--   M15 PREDICTED  edit one of 0127 §E's three column comments.
--                  → RED = [P6 ⓕ digest for that column].
--   M16 PREDICTED  create a `security definer` function in `public` with the default ACL.
--                  → RED = [98 H9], naming it. Nothing else in the harness watches this.
--
-- ── MEASURED (2026-08-25, second battery; 7 runs, baseline 886/0) ───────────────────────────
--   M10 MEASURED  **EXACT, and it reproduced the hole rather than only the pin.** The harness
--                 ABORTED at 0127 with `ERROR: 0127: generate_recurring_bookings() is EXECUTABLE by
--                 public/anon/authenticated — acl==X/postgres postgres=X/postgres
--                 service_role=X/postgres`. The leading `=X/postgres` IS the PUBLIC grant: on the
--                 absent-function path the definer really is born PUBLIC-executable, exactly as the
--                 review said, and it is not a theoretical reading of the docs. No suite ran, which
--                 is correct — the migration failed closed and rolled back.
--   M11 MEASURED  **EXACT.** Same absent-function path with §D-bis's revoke left in: `✅ 0127`,
--                 **886/0**, and the resulting catalog read back as
--                 `acl=postgres=X/postgres service_role=X/postgres owner=postgres pub=false` —
--                 byte-identical to the normal chain. This is the arm that matters: M10 proves the
--                 VERIFY notices, M11 proves the FIX WORKS. A battery with only M10 would have
--                 shipped a migration that fails closed forever on a path it could have handled.
--   M12 MEASURED  **EXACT.** RED = [P4 ⓐ only] (885/1), naming `md5 기대=050c0b3e… 실제=8594599e…
--                 길이 기대=5335 실제=5336`. One byte, inside a comment in the body. Every other arm
--                 of P4 stayed green, 0127's VERIFY stayed green, and the OLD P4 would have passed
--                 this without a murmur — which is the finding, demonstrated.
--   M13 MEASURED  RED = [P6 ⓔ, r4 F3, r4 F4, r4 F8] (882/4)  superset. P6 named the swap exactly:
--                 `실제: t_dogs_touch, zz_unrelated · 기대: club_dog_materiality, t_dogs_touch`.
--                 **The count stayed 2 throughout**, so the old count-only arm was structurally
--                 blind to this. The three r4 pins are true reds — they depend on the trigger the
--                 mutation dropped — and they are the blast radius, not a miss.
--   M14 MEASURED  **EXACT.** RED = [P3 only] (885/1): `삭제된 객체를 아직 호출하는 루틴이 있다
--                 [auth._zz_caller]`. The old public-only scan could not see a non-public caller at
--                 all; the widened one named it and nothing else moved.
--   M15 MEASURED  **EXACT.** RED = [P6 ⓕ only] (885/1), naming the column and the wrong digest.
--   M16 MEASURED  RED = [98 H9, 99 S1] (884/2)  superset — **and the superset is the result.**
--                 H9 named the offender and its ACL (`_zz_open_definer() [=X/postgres …]`); `99 S1`
--                 reddened too, reporting only a count. S1 has swept `public` definers for
--                 anon-execute since 0057 §1, and `anon` inherits PUBLIC, so the class H9 was
--                 commissioned for was **already guarded**. H9 is kept for the naming, the
--                 allowlist and the stated scope — and its own header now says this out loud
--                 instead of claiming an unwatched class. See 98 H9's OVERLAP note.
--   BLAST RADIUS: across the 6 runs that reached the suites, every ❌ was accounted for — the
--   `[mgn-off]` pin under test, plus M13's three `[r4]` pins which depend on the dropped trigger,
--   plus M16's `[sec] S1`. No mutation moved a pin in the green direction.
--
-- ── SCOPE, STATED HONESTLY ──────────────────────────────────────────────────────────────────
-- These pins prove the SCHEMA half only. The edge function's removed token mapping is proven by
-- the deploy readback and by the deletion of `_test/booking_danger_token_test.ts`; the client half
-- is proven by ui6's landing and by smoke ("save an unchanged dog profile; book a 핏불테리어 dog
-- end to end"). Smoke is smoke — it is never implied to be a pin here.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

do $$
declare
  o_book uuid; o_del uuid; o_move uuid; o_rsvp uuid; o_ctrl uuid; o_ser uuid; o_ser2 uuid;
  o_ser3 uuid; o_dogs uuid;
  hh uuid; rr uuid; rt uuid;
  d_book uuid; d_del uuid; d_move uuid; d_rsvp uuid; d_ser uuid; d_ser2 uuid; d_ser3 uuid; d_ctrl uuid;
  d_tmp uuid; d_stamp uuid; d_kill uuid;
  v_club uuid; v_s uuid; sd_del uuid; sd_rsvp uuid; sd_ctrl uuid;
  b_book uuid; b_move uuid;
  ser_pit uuid; ser_legacy uuid; ser_undecl uuid;
  v_bad text; v_msg text; v_err text; v_def text; v_cmt text; v_left text; v_con text;
  v_n int; v_n2 int; v_n3 int; v_dow int; v_rule jsonb;
  v_stamp constant timestamptz := '2020-01-02 03:04:05+00';
  -- P6 ⓕ writes this fixed value rather than now(), so the arm can assert the EXACT timestamp that
  -- was written instead of merely "not null" — the difference between observing a write and
  -- observing that no exception was raised (codex finding 6's last clause).
  v_stamp6 constant timestamptz := '2021-06-07 08:09:10+00';
  -- ── P4's frozen expectations ───────────────────────────────────────────────────────────────
  -- 🔴 MEASURED, not typed from the file: read out of the harness-built catalog on 2026-08-25
  --    after 0127 applied (`select md5(prosrc), length(prosrc) from pg_proc where oid =
  --    'generate_recurring_bookings()'::regprocedure`). `prosrc` is the body verbatim, so the digest
  --    is deterministic in every environment that applied the same file.
  -- ⚠ IF THIS PIN REDS AND YOU CHANGED THE GENERATOR ON PURPOSE: do not delete the arm and do not
  --    relax it to a substring. Re-read the two values from the catalog, paste them here, and say
  --    in the commit WHY the body moved. That round trip is the entire point — the previous version
  --    of P4 would have stayed green through a rewrite that gutted the function.
  c_gen_src_md5 constant text := '050c0b3ea18e5481db59fa28e90773c9';
  c_gen_src_len constant int  := 5335;
  c_gen_cmt_md5 constant text := '12dda5539af7bbcc8b68b1641493df36';
  c_gen_cmt_len constant int  := 333;
  -- ── P6's frozen expectations (same provenance, same rule) ──────────────────────────────────
  c_cmt_status constant text := '0ad231504865cc879744aa64aa4ca1f5';
  c_cmt_basis  constant text := 'fed7b16a86dab7247e7600e787cbae0f';
  c_cmt_stamp  constant text := 'bd5db3c290cf8fcee3833822ba55c505';
  -- exact trigger NAME sets, not counts. Measured two ways at 0127's authoring (the whole migration
  -- chain including `create constraint trigger`, and the linked project's live pg_trigger) and read
  -- back out of the harness catalog here. A count cannot tell "the right 14" from "any 14".
  c_trg_bookings constant text[] := array[
    '_guard_booking_cols','_guard_booking_insert','booking_cancel_custody_guard',
    'booking_cancel_fee_truth','booking_handoff_stamp_guard','booking_transition',
    'bookings_club_fee_provenance','club_close_segments','club_custody_transition_v2',
    'club_v2_axes_poke','km_release_on_terminal_gate','owner_la_booking','owner_la_run_end',
    't_bookings_touch'];
  c_trg_dogs constant text[] := array['club_dog_materiality','t_dogs_touch'];
  c_trg_session_dogs constant text[] := array['club_v1_axes_sync'];
  v_trg text[];
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- shared seed — TOP LEVEL, outside every pin (fixture note ①)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  o_book := t_user('rmv_o_book', 'owner');
  o_del  := t_user('rmv_o_del',  'owner');
  o_move := t_user('rmv_o_move', 'owner');
  o_rsvp := t_user('rmv_o_rsvp', 'owner');
  -- ⚠ the control dog needs its OWN owner: `session_rsvp` inserts a `session_people` row and
  --   raises `already_joined` on the unique violation (0048:180-186), so one owner cannot RSVP
  --   twice into the same session. Sharing an owner here would red P5 ⓒ for a club-membership
  --   reason and read as "the gate is back".
  o_ctrl := t_user('rmv_o_ctrl', 'owner');
  o_ser  := t_user('rmv_o_ser',  'owner');
  o_ser2 := t_user('rmv_o_ser2', 'owner');
  o_ser3 := t_user('rmv_o_ser3', 'owner');
  o_dogs := t_user('rmv_o_dogs', 'owner');
  hh     := t_user('rmv_host', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr     := t_user('rmv_run',  'runner');
  rt     := t_route('맹견해제 코스');

  -- ⚠ THE ORDER BELOW IS LOAD-BEARING (codex blind review 2026-08-25, finding 8).
  -- P2 runs FIRST — before this suite writes a single row to `dogs`. It used to run fourth, after
  -- five top-level `insert into dogs` fixture lines, and that made its headline claim untrue: the
  -- exact corruption P2 exists to detect (`dogs_dangerous_declaration` surviving with its function
  -- gone, which fails EVERY write to `dogs`) would have aborted the seed above and taken the whole
  -- suite down before P2 ever reported. A detector that its own fixtures trip first detects nothing.
  -- So the seed is split in two: identities and the route here, every dog AFTER P2.
  -- P2 keeps its NAME (the numbers are labels, not an order) so the measured mutation map in this
  -- file's header, and every reference to "P2" elsewhere, still resolves.

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P2] 🔴 THE HIGHEST-VALUE PIN — ordinary writes to `dogs` still work
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `dogs_dangerous_declaration` was `before insert or update on dogs FOR EACH ROW` with no WHEN.
  -- It is the trigger a four-item inventory misses, and left behind with its function dropped it
  -- does not "stop gating" — it fails EVERY insert and update on `dogs`: onboarding, a rename, a
  -- weight edit, every profile save in the product. ⓐ/ⓑ are the one-line pins for that. ⓒ/ⓓ/ⓔ
  -- then pin the three behaviours the trigger pair actively imposed, each of which must now be
  -- gone: the one-way latch, the server-stamped timestamp, and the DELETE latch.
  begin
    v_bad := '';

    -- ⓐ an ordinary insert
    insert into dogs (owner_id, name) values (o_dogs, '새강아지') returning id into d_tmp;
    select count(*) into v_n from dogs where id = d_tmp;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 평범한 강아지 INSERT가 실패했다'; end if;

    -- ⓑ an ordinary rename — and the value really moved (a 0-row UPDATE is not a pass)
    update dogs set name = '이름바꿈' where id = d_tmp;
    select count(*) into v_n from dogs where id = d_tmp and name = '이름바꿈';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 평범한 강아지 UPDATE가 반영되지 않았다'; end if;

    -- ⓒ the one-way latch is GONE. 0119 §F raised `dog_dangerous_declaration_final` on exactly
    --   this write; the columns survive Slice A, so the write itself is still legal SQL and its
    --   only former obstacle was the trigger.
    update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'listed_breed'
     where id = d_tmp;
    v_err := null;
    begin
      update dogs set dangerous_status = 'declared_none', dangerous_basis = null where id = d_tmp;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 declared_dangerous → declared_none이 여전히 거절된다 [' || v_err || '] — 래치가 살아 있다'; end if;
    select count(*) into v_n from dogs
     where id = d_tmp and dangerous_status = 'declared_none' and dangerous_basis is null;
    if v_n <> 1 then v_bad := v_bad || ' 되돌리기가 반영되지 않았다'; end if;

    -- ⓓ the timestamp is no longer server-stamped. 0119 §F ⓑ overwrote whatever the client sent
    --   (null for `undeclared`); with the trigger gone the supplied value survives verbatim. This
    --   arm is what tells "the trigger is gone" apart from "the trigger is present but quiet".
    insert into dogs (owner_id, name, dangerous_declared_at)
      values (o_dogs, '도장강아지', v_stamp) returning id into d_stamp;
    select count(*) into v_n from dogs where id = d_stamp and dangerous_declared_at = v_stamp;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 클라이언트가 보낸 dangerous_declared_at이 여전히 서버 값으로 덮인다 — 신고 트리거가 살아 있다'; end if;

    -- ⓔ the DELETE latch is gone, executed AS the owner (`authenticated`), which is the only role
    --   0119 §F's delete guard refused. As postgres it would have passed even with the guard live,
    --   so this arm must run under the app role or it measures nothing.
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (o_dogs, '삭제대상', 'declared_dangerous', 'designated') returning id into d_kill;
    perform set_config('request.jwt.claim.sub', o_dogs::text, false);
    v_err := null;
    begin
      set local role authenticated;
      delete from dogs where id = d_kill;
    exception when others then v_err := coalesce(sqlstate, '') || '/' || sqlerrm;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_err is not null then
      v_bad := v_bad || ' 🔴 보호자가 맹견 신고된 강아지를 지울 수 없다 [' || v_err || '] — DELETE 래치가 살아 있다'; end if;
    select count(*) into v_n from dogs where id = d_kill;
    if v_n <> 0 then v_bad := v_bad || ' 🔴 DELETE가 예외 없이 아무 행도 지우지 않았다(남은 행=' || v_n || ')'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P2 강아지 쓰기가 평범해졌다 — INSERT·이름 변경이 통과하고(신고 트리거가 남아 있으면 제품의 모든 강아지 저장이 죽는다), 편도 래치가 풀려 declared_dangerous → declared_none이 성공하며, dangerous_declared_at은 더 이상 서버가 덮어쓰지 않고, 보호자(authenticated)가 신고된 강아지를 직접 삭제할 수 있다');
    else v_msg := v_bad; call _fail('mgn-off','P2 강아지 쓰기 정상화', v_msg); end if;
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P2 강아지 쓰기 정상화', v_msg);
  end;

  -- fixture note ②/③ — one dog per arm, every one of them the shape 0119 refused twice over
  insert into dogs (owner_id, name, breed) values (o_book, '예약핏불', '핏불테리어') returning id into d_book;
  insert into dogs (owner_id, name, breed) values (o_del,  '위탁핏불', '핏불테리어') returning id into d_del;
  insert into dogs (owner_id, name, breed) values (o_move, '이동핏불', '핏불테리어') returning id into d_move;
  insert into dogs (owner_id, name, breed) values (o_rsvp, '동반핏불', '핏불테리어') returning id into d_rsvp;
  insert into dogs (owner_id, name, breed) values (o_ser,  '반복핏불', '핏불테리어') returning id into d_ser;
  -- ── P1 ⓒ's TWO controls, and they are deliberately different shapes ──────────────────────
  -- ① the LEGACY control: `t_dog` writes `dangerous_status = 'declared_none'` (10_settle_suite:24).
  --    Named honestly now: that state is one the CURRENT client can no longer produce — nothing in
  --    the app writes it any more, and Slice B removes the fixture line together with the column.
  --    It is kept ON PURPOSE and it is the only shape that can do this job: `declared_none` is the
  --    one value 0119's gate let through, so if the gate came back this series would still
  --    generate. That asymmetry is the discriminator. A current-flow dog cannot be the control,
  --    because under a re-added gate it would fail too and prove nothing.
  d_ser2 := t_dog(o_ser2, '반복평범이(구형 declared_none)');
  -- ② the CURRENT-FLOW control: an ordinary breed at the DEFAULT `undeclared`, i.e. exactly what
  --    the shipping client produces today. Added because two operands only answer two questions.
  --    With three, the reds separate cleanly:
  --      pit=0 · undeclared=0 · legacy=1  → the gate is back (it refuses undeclared, passes 신고완료)
  --      pit=0 · undeclared=0 · legacy=0  → the sweep is dead, and no other arm here means anything
  --      pit=0 · undeclared=1 · legacy=1  → something breed-shaped, not declaration-shaped
  insert into dogs (owner_id, name, breed) values (o_ser3, '반복평범이(현행 미신고)', '푸들')
    returning id into d_ser3;
  -- P5 ⓒ's control dog: ordinary, its own owner (see above), and its custody flip was legal even
  -- under 0119 — which is exactly what makes it a control rather than a second subject
  d_ctrl := t_dog(o_ctrl, '대조평범이');

  -- club stage, mirroring 154's: open, routed, 30h out, no check-in window in play
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('해제동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '30 hours', '해제 집결지', rt, 8, 'mixed');
  perform set_config('request.jwt.claim.sub', '', false);

  -- fixture note ④ — the money gate must not be the thing that decides P1 ⓒ
  insert into billing_keys (profile_id, billing_key) values (o_ser,  'bk_rmv_1')
    on conflict (profile_id) do nothing;
  insert into billing_keys (profile_id, billing_key) values (o_ser2, 'bk_rmv_2')
    on conflict (profile_id) do nothing;
  insert into billing_keys (profile_id, billing_key) values (o_ser3, 'bk_rmv_3')
    on conflict (profile_id) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P1] 🔴 A 핏불테리어 DOG COMPLETES THE WHOLE CUSTODY JOURNEY — book, delegate, recur
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The ruling in one pin: all breeds are accepted, on all three paths a stranger can take the
  -- dog. Each arm asserts the ROW, never just the absence of an exception — an insert that
  -- silently did nothing must not read as "the gate is gone".
  begin
    v_bad := '';

    -- ⓐ marketplace: the shape `create-booking-hold` writes (runner_id NULL, matching)
    b_book := t_av_booking(o_book, d_book, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = b_book;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 마켓 부킹이 생기지 않았다(count=' || v_n || ')'; end if;

    -- ⓑ club: `session_delegate_dog` writes `session_dogs` at custody = 'runner_delegated' long
    --   before any booking exists — 0119 refused here first, at APPLICATION time.
    perform set_config('request.jwt.claim.sub', o_del::text, false);
    sd_del := session_delegate_dog(v_s, d_del, t_consent());
    perform set_config('request.jwt.claim.sub', '', false);
    select count(*) into v_n from session_dogs
     where id = sd_del and dog_id = d_del and custody = 'runner_delegated';
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 클럽 위탁 신청이 접수되지 않았다(count=' || v_n || ')'; end if;

    -- ⓒ cron: THREE series in ONE sweep — the subject and two differently-shaped controls.
    --   154 G6's pairing, extended to a triple after the 2026-08-25 blind review (finding 5).
    --     · ser_pit    핏불테리어 + undeclared   — the subject: the shape 0119 refused twice over
    --     · ser_undecl 평범한 견종 + undeclared  — what the CURRENT client actually produces
    --     · ser_legacy 평범한 견종 + declared_none — the legacy shape 0119's gate LET THROUGH
    --   Why three and not two: two operands answer only "did anything generate". The legacy arm is
    --   the only one that stays green under a re-added gate, so it is what separates "the gate is
    --   back" from "the sweep is dead"; the current-flow arm is what stops this pin from claiming
    --   the control is an ordinary dog of today, which it is not. See the fixture block above.
    v_dow  := extract(dow from ((now() at time zone 'Asia/Seoul') + interval '1 day'))::int;
    v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_dow), 'time', '10:00', 'tz', 'Asia/Seoul');
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o_ser, d_ser, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser_pit;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o_ser2, d_ser2, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser_legacy;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o_ser3, d_ser3, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser_undecl;

    -- 🔴 ATOMICITY, STATED — the three counts below come from ONE function call, and 0127
    --   deliberately restores a generator with NO per-row exception isolation (0127's header 🔴
    --   note). So a single RAISED insert rolls back everything this call wrote and drives all three
    --   counts to zero, which is indistinguishable from a dead sweep BY THE COUNTS ALONE. That case
    --   is not silent — it is the arm immediately below, which reports the exception verbatim — but
    --   the three-way reading further down is only valid for outcomes where the sweep SKIPPED rows
    --   (`continue`, which is what 0119's ⓕ belt did) rather than raised. Read the exception arm
    --   first; if it fired, the counts carry no diagnosis at all.
    v_err := null;
    begin
      perform generate_recurring_bookings();
    exception when others then v_err := sqlerrm;
    end;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 시간별 스윕이 예외로 죽었다 [' || v_err
                     || '] — 이 경우 아래 세 카운트는 전부 0이 되며 아무것도 진단하지 못한다(행별 격리 없음, 0127 의도)'; end if;

    select count(*) into v_n  from bookings where series_id = ser_pit;
    select count(*) into v_n2 from bookings where series_id = ser_legacy;
    select count(*) into v_n3 from bookings where series_id = ser_undecl;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 시리즈가 반복 예약을 만들지 않았다(=' || v_n || ') — 게이트나 벨트가 살아 있다'; end if;
    if v_n2 <> 1 then
      v_bad := v_bad || ' 🔴 구형 declared_none 대조군 시리즈도 생성되지 않았다(=' || v_n2 || ') — 0119의 게이트조차 통과시키던 형상이므로, 원인은 맹견이 아니라 스윕 자체다'; end if;
    if v_n3 <> 1 then
      v_bad := v_bad || ' 🔴 현행 미신고 대조군 시리즈가 생성되지 않았다(=' || v_n3 || ') — 구형 대조군이 살아 있는데 이것만 죽었다면 신고 상태를 보는 무언가가 돌아왔다는 뜻이다'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P1 모든 견종이 받아들여진다 — 핏불테리어 견종에 미신고 상태인 강아지가 마켓 부킹(1건)·클럽 위탁 신청(runner_delegated 행)·반복 예약 생성(1건)을 전부 통과하고, 같은 스윕에서 대조군 두 시리즈(구형 declared_none · 현행 미신고)도 각각 1건 생성된다 (Sean F1 2026-08-25 "Remove it completely"). ⚠ 범위: 세 카운트는 한 번의 함수 호출에서 나오고 복원된 스윕에는 행별 격리가 없다 — 스윕이 raise하면 셋 다 0이 되고, 그 경우는 카운트가 아니라 예외 팔이 진단한다');
    else v_msg := v_bad; call _fail('mgn-off','P1 세 경로 전부 통과', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P1 세 경로 전부 통과', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P3] the NAMED inventory — 0127's VERIFY, re-run as a pin that outlives the migration
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Names one by one, never a pattern: a `%dangerous%` sweep passes while `dog_custody_gate` and
  -- `dog_custody_refusal_detail` sit untouched, and that blind spot IS the silent half-removal.
  -- The last arm is the schema-wide `prosrc` scan — plpgsql carries no dependency records, so a
  -- caller left behind is invisible to the catalog and only fails at the next execution (a cron at
  -- 07 past the hour, or a club application, hours after the migration went green).
  begin
    v_bad := '';

    select string_agg(x.tbl || '.' || x.trg, ', ' order by x.tbl, x.trg) into v_left
      from (values ('bookings',     'bookings_dangerous_dog'),
                   ('bookings',     'bookings_dangerous_dog_move'),
                   ('session_dogs', 'session_dogs_dangerous_dog'),
                   ('session_dogs', 'session_dogs_dangerous_dog_move'),
                   ('dogs',         'dogs_dangerous_declaration'),
                   ('dogs',         'dogs_dangerous_delete')) as x(tbl, trg)
     where exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                    where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
                      and c.relname = x.tbl and t.tgname = x.trg);
    if v_left is not null then v_bad := v_bad || ' 🔴 트리거가 살아남았다 [' || v_left || ']'; end if;

    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_left
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('_guard_dangerous_dog_custody', '_guard_dog_dangerous_declaration',
                         '_guard_dangerous_dog_delete', 'dog_custody_gate',
                         'dog_custody_refusal_detail', '_breed_reads_as_dangerous');
    if v_left is not null then v_bad := v_bad || ' 🔴 함수가 살아남았다 [' || v_left || ']'; end if;

    -- ── the dangling-caller scan, WIDENED (blind review 2026-08-25, finding 3) ────────────────
    -- This arm used to restrict `pg_proc` to `public` while its own pin text said "schema-wide".
    -- Both halves of that sentence were narrower than they sounded: a routine in `auth`, `storage`
    -- or any other non-system namespace calling `public.dog_custody_gate(...)` passed, and so did a
    -- stored cron command, which holds SQL as TEXT and is likewise invisible to the dependency
    -- graph. Widened to every non-system routine namespace here.
    select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname || '.' || p.proname)
      into v_left
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname <> 'information_schema'
       and n.nspname not like 'pg\_%'
       and (p.prosrc like '%dog_custody_gate%'
         or p.prosrc like '%dog_custody_refusal_detail%'
         or p.prosrc like '%_breed_reads_as_dangerous%');
    if v_left is not null then
      v_bad := v_bad || ' 🔴 삭제된 객체를 아직 호출하는 루틴이 있다 [' || v_left || ']'; end if;

    -- a separate failure from the one above: not a CALLER of a dropped function, but an independent
    -- EMITTER of the refusal tokens themselves. The client's mapping for these five is deleted in
    -- the same landing, so a survivor produces a raw P0001 the app renders as an unknown error.
    -- Full token names, never a `dog_dangerous_%` prefix — that prefix would fire on every
    -- legitimate reference to `dangerous_status`, the column Slice A deliberately keeps.
    select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname || '.' || p.proname)
      into v_left
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname <> 'information_schema'
       and n.nspname not like 'pg\_%'
       and (p.prosrc like '%dog_dangerous_undeclared%'
         or p.prosrc like '%dog_dangerous_custody_refused%'
         or p.prosrc like '%dog_dangerous_breed_conflict%'
         or p.prosrc like '%dog_dangerous_declaration_final%'
         or p.prosrc like '%dog_dangerous_declaration_delete_final%');
    if v_left is not null then
      v_bad := v_bad || ' 🔴 클라이언트가 더 이상 해석하지 못하는 맹견 거절 토큰을 아직 뱉는 루틴이 있다 [' || v_left || ']'; end if;

    -- stored cron commands. Guarded rather than assumed: pg_cron is NOT installed in the harness
    -- container (0026 wraps its own `create extension` in an exception handler for the same
    -- reason), so an absent `cron.job` here is an inapplicable check, not a pass. On the linked
    -- project the table exists and this arm is live.
    if to_regclass('cron.job') is not null then
      execute $q$ select string_agg(jobname || ' :: ' || command, ', ' order by jobname)
                    from cron.job
                   where command like '%dog_custody_gate%'
                      or command like '%dog_custody_refusal_detail%'
                      or command like '%_breed_reads_as_dangerous%' $q$ into v_left;
      if v_left is not null then
        v_bad := v_bad || ' 🔴 예약된 cron 명령이 아직 삭제된 객체를 호출한다 [' || v_left || ']'; end if;
    end if;

    if v_bad = ''
      then call _pass('mgn-off','P3 이름으로 확인한 부재 — 0119의 트리거 6개와 함수 6개가 각각 정확한 이름으로 사라졌고(`%dangerous%` 패턴은 dog_custody_gate·dog_custody_refusal_detail을 못 본다 — 그게 조용한 반쪽 제거의 정확한 형태다), 시스템 스키마를 제외한 **모든** 네임스페이스의 루틴 본문과 (설치돼 있다면) cron.job 명령 어디에도 삭제된 객체의 호출이나 다섯 개 거절 토큰의 방출이 남아 있지 않다. ⚠ 범위: 정적 텍스트만 본다 — `execute format(...)`로 조립되는 동적 SQL은 어떤 정적 검사로도 확정할 수 없고 이 핀은 그것을 주장하지 않는다. pg_cron이 없는 하네스에서 cron 팔은 통과가 아니라 비적용이다');
    else v_msg := v_bad; call _fail('mgn-off','P3 이름 인벤토리', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P3 이름 인벤토리', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P4] the restored generator — 0111's body back, with 0111's belts intact
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ REWRITTEN 2026-08-25 after the blind review (finding 2), and the finding was correct.
  -- The previous P4 checked three forbidden substrings, two required substrings, one `proconfig`
  -- entry and a loose `[0111]` in the comment — then its pass text claimed the function "returned
  -- to 0111". **A stub could satisfy every one of those arms**: `begin return 0; end` with a
  -- comment mentioning `owner_has_unsettled_charge` and `dog/address not owned by series owner`
  -- passes a substring check while the recurring feature is dead. That is precisely the confusion
  -- this pin exists to prevent — "the gate is gone" versus "the feature is gone" — and it could not
  -- make the distinction. It also saw nothing of language, `prosecdef`, volatility, return type,
  -- owner, ACL, statement order, or ~99% of the body.
  --
  -- Now it is three layers, and each answers a different question:
  --   ⓐ EXACTNESS — an exact `prosrc` digest, plus its length. `prosrc` is the body verbatim, so
  --      this is a byte-for-byte comparison against 0111's restored text and a stub cannot survive
  --      it. The digest is opaque when it reds, which is why ⓑ is kept.
  --   ⓑ DIAGNOSIS — the old substring arms, unchanged. They are no longer the proof; they are what
  --      turns a red digest into a sentence ("the belt is back" / "a belt that predates 0119 was
  --      lost"). Keeping both is deliberate: exactness without diagnosis is a bad pin to be woken by.
  --   ⓒ CATALOG SHAPE — language, `prosecdef`, volatility, return type, in-body `search_path`,
  --      owner and ACL. A body can be perfect while the function is `security invoker`, owned by
  --      the wrong role, or executable by `anon`. 0127 §D-bis and its VERIFY ③-bis fix that at
  --      apply time; this arm is the standing version that outlives the migration.
  begin
    v_bad := '';
    select pg_get_functiondef('generate_recurring_bookings()'::regprocedure) into v_def;
    if v_def is null then v_bad := v_bad || ' 🔴 generate_recurring_bookings가 없다';
    else
      -- ⓐ EXACTNESS — the byte-for-byte arm. This is the proof; the substrings below are the
      --   diagnosis. A stub cannot reach this digest no matter which literals it mentions.
      select p.prosrc into v_left from pg_proc p
        where p.oid = 'generate_recurring_bookings()'::regprocedure;
      if md5(v_left) <> c_gen_src_md5 then
        v_bad := v_bad || ' 🔴 크론 본문이 0111의 복원본과 바이트 단위로 다르다 (md5 기대='
                       || c_gen_src_md5 || ' 실제=' || md5(v_left)
                       || ' · 길이 기대=' || c_gen_src_len || ' 실제=' || length(v_left)
                       || ') — 길이가 크게 짧으면 스텁이고, 몇 바이트 차이면 누군가 본문을 고쳤다. 어느 쪽이든 이 핀을 느슨하게 만들지 말고 카탈로그에서 값을 다시 읽어 상수를 갱신하며 이유를 커밋에 적을 것'; end if;

      -- ⓑ DIAGNOSIS — kept verbatim from the original P4. No longer load-bearing on its own.
      if v_def like '%dog_custody_gate%' or v_def like '%dog_dangerous_%'
         or v_def like '%recurring custody gate skipped%' then
        v_bad := v_bad || ' 🔴 크론 본문에 0119의 커스터디 벨트가 남아 있다'; end if;
      if v_def not like '%dog/address not owned by series owner%' then
        v_bad := v_bad || ' 🔴 0111 ⓔ 소유권 벨트가 복원되지 않았다 — 제거가 과했다'; end if;
      if v_def not like '%owner_has_unsettled_charge%' then
        v_bad := v_bad || ' 🔴 0080 결제 게이트가 사라졌다 — 제거가 과했다'; end if;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = 'generate_recurring_bookings()'::regprocedure::oid
                      and p.proconfig @> array['search_path=public, pg_temp']) then
      v_bad := v_bad || ' 🔴 search_path가 본문에 없다 (98 H1: ALTER로 붙인 설정은 create or replace가 지운다)'; end if;

    -- ⓒ CATALOG SHAPE — everything a body comparison structurally cannot see.
    -- (scratch vars are reused here on purpose — v_def's substring arms above have already run,
    --  and v_cmt is re-read from obj_description further down.)
    select l.lanname, p.provolatile::text, p.prorettype::regtype::text, pg_get_userbyid(p.proowner)
      into v_left, v_con, v_def, v_cmt
      from pg_proc p join pg_language l on l.oid = p.prolang
     where p.oid = 'generate_recurring_bookings()'::regprocedure;
    if v_left <> 'plpgsql' or v_con <> 'v' or v_def <> 'integer' then
      v_bad := v_bad || ' 🔴 크론의 카탈로그 형상이 0111과 다르다 (language=' || coalesce(v_left,'∅')
                     || ' volatile=' || coalesce(v_con,'∅') || ' returns=' || coalesce(v_def,'∅')
                     || ' · 기대: plpgsql / v / integer)'; end if;
    if not exists (select 1 from pg_proc p where p.oid = 'generate_recurring_bookings()'::regprocedure
                     and p.prosecdef) then
      v_bad := v_bad || ' 🔴 크론이 security definer가 아니다 — 본문이 완벽해도 크론 실행 권한이 달라진다'; end if;
    -- owner: compared to an untouched definer PEER rather than to a hardcoded role name, so the
    -- assertion means the same thing in the harness, in a branch DB and in production.
    select pg_get_userbyid(p.proowner) into v_left from pg_proc p
      where p.oid = 'owner_has_unsettled_charge(uuid)'::regprocedure;
    if v_cmt is distinct from v_left then
      v_bad := v_bad || ' 🔴 크론의 소유자(' || coalesce(v_cmt,'∅') || ')가 손대지 않은 definer 동료 owner_has_unsettled_charge의 소유자('
                     || coalesce(v_left,'∅') || ')와 다르다 — 함수가 없는 DB에 이 파일이 적용되면 create or replace는 CREATE가 되고 소유자는 보존이 아니라 생성된다'; end if;
    -- ACL: the actual hole finding 1 named. 0026:152 revoked these three and 0127 §D-bis repeats
    -- it; if either line is ever dropped and the function is recreated from absent, it is born
    -- PUBLIC-executable and this arm is what says so.
    if has_function_privilege('public',        'generate_recurring_bookings()', 'execute')
       or has_function_privilege('anon',          'generate_recurring_bookings()', 'execute')
       or has_function_privilege('authenticated', 'generate_recurring_bookings()', 'execute') then
      v_bad := v_bad || ' 🔴 security definer 크론이 public/anon/authenticated에게 실행 가능하다 [acl='
                     || coalesce((select array_to_string(p.proacl, ' ') from pg_proc p
                                   where p.oid = 'generate_recurring_bookings()'::regprocedure),
                                 '<null = 기본값 PUBLIC>') || ']'; end if;

    select obj_description('generate_recurring_bookings()'::regprocedure, 'pg_proc') into v_cmt;
    if v_cmt is null then v_bad := v_bad || ' 🔴 크론 함수의 주석이 사라졌다';
    else
      if md5(v_cmt) <> c_gen_cmt_md5 then
        v_bad := v_bad || ' 🔴 크론 주석이 0111:396-401의 복원본과 정확히 같지 않다 (md5 기대='
                       || c_gen_cmt_md5 || ' 실제=' || md5(v_cmt)
                       || ' · 길이 기대=' || c_gen_cmt_len || ' 실제=' || length(v_cmt) || ')'; end if;
      if v_cmt like '%0119%' or v_cmt like '%custody gate%' then
        v_bad := v_bad || ' 🔴 주석이 아직 없는 벨트를 설명한다'; end if;
      if v_cmt not like '%[0111]%' then
        v_bad := v_bad || ' 🔴 주석이 0111:396-401의 복원본이 아니다'; end if;
    end if;

    if v_bad = ''
      then call _pass('mgn-off','P4 크론이 0111로 되돌아왔다 — 본문이 0111 복원본과 **바이트 단위로 동일**하고(prosrc md5 고정), 0119의 벨트 문자열이 하나도 없으며, 0111 ⓔ 소유권 벨트와 0080 결제 게이트는 그대로고, 카탈로그 형상도 plpgsql/definer/volatile/returns int이며, 소유자는 손대지 않은 definer 동료와 같고, public·anon·authenticated 누구도 실행할 수 없으며, search_path는 본문에 있고 주석도 0111의 것과 정확히 같다. ⚠ 이 핀이 없던 동안에는 리터럴 몇 개만 언급하는 빈 스텁도 통과했다 — 「게이트가 사라졌다」와 「기능이 죽었다」를 가르는 게 이 핀의 존재 이유다. ⚠ 복원은 0111의 무-행별-격리 의미까지 되돌린다 — 의도된 결정이며 0127 헤더가 그렇게 말한다');
    else v_msg := v_bad; call _fail('mgn-off','P4 크론 복원', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P4 크론 복원', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P5] the UPDATE paths — the row that MOVES raises nothing 맹견-shaped, for any breed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0119's two `_move` triggers fired on the writes that carry a dog TOWARD a stranger: a runner
  -- being assigned, the status advancing, the arrival and both handoff stamps, and a session_dogs
  -- row changing custody. INSERT-only pins cannot see them, so this pin walks the real sequence
  -- and asserts the row's END STATE — a raise-free UPDATE that changed nothing would be no proof.
  begin
    v_bad := '';
    b_move := t_av_booking(o_move, d_move, rt, null::uuid, now() + interval '26 hours', 5.0, 'matching');

    -- ⓐ the marketplace row moves outward: runner assigned → accepted → stamps → custody
    --   (the order respects 0066's transition map and 0117's stamp guard, which allows stamps
    --    while the status is confirmed/runner_enroute/picked_up/active)
    v_err := null;
    begin
      update bookings set runner_id = rr, status = 'runner_pending' where id = b_move;
      update bookings set status = 'confirmed' where id = b_move;
      update bookings set arrived_at = now() where id = b_move;
      update bookings set owner_confirmed_handoff_at = now(),
                          runner_confirmed_handoff_at = now() where id = b_move;
      update bookings set status = 'runner_enroute' where id = b_move;
      update bookings set status = 'picked_up' where id = b_move;
    exception when others then v_err := sqlerrm;
    end;
    -- The walk stops at `picked_up` deliberately: that is where custody has actually passed to the
    -- stranger, and 0119's own WHEN clause exempted rows already at picked_up/active — so every
    -- write past this point was never gated and would add fixture risk without adding a pin.
    if v_err is not null then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 예약이 진행 중에 거절됐다 [' || v_err || ']'; end if;
    select count(*) into v_n from bookings
     where id = b_move and status = 'picked_up' and runner_id = rr
       and arrived_at is not null
       and owner_confirmed_handoff_at is not null and runner_confirmed_handoff_at is not null;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 예약이 실제로 이동하지 않았다 — 예외가 없는 것과 쓰기가 반영된 것은 다르다'; end if;

    -- ⓑ the club row moves into delegated custody by UPDATE — 0119's side door, refused there,
    --   open here. Seeded as a 동반 row first (which the old INSERT trigger exempted), so this arm
    --   isolates the UPDATE trigger exactly.
    perform set_config('request.jwt.claim.sub', o_rsvp::text, false);
    perform session_rsvp(v_s, d_rsvp);
    perform set_config('request.jwt.claim.sub', '', false);
    select id into sd_rsvp from session_dogs where session_id = v_s and dog_id = d_rsvp;
    if sd_rsvp is null then
      v_bad := v_bad || ' 🔴 동반 RSVP 픽스처가 만들어지지 않았다';
    else
      v_err := null;
      begin
        update session_dogs set custody = 'runner_delegated', responsible_profile_id = hh
         where id = sd_rsvp;
      exception when others then v_err := sqlerrm;
      end;
      if v_err is not null then
        v_bad := v_bad || ' 🔴 동반 → 위탁 커스터디 이동이 거절됐다 [' || v_err || ']'; end if;
      select count(*) into v_n from session_dogs where id = sd_rsvp and custody = 'runner_delegated';
      if v_n <> 1 then
        v_bad := v_bad || ' 🔴 커스터디가 실제로 이동하지 않았다(=' || v_n || ')'; end if;
    end if;

    -- ⓒ CONTROL for ⓑ, and it is a diagnostic one. The same flip on an ORDINARY dog was already
    --   legal under 0119 (declared_none passed the gate), so if ⓑ and ⓒ fail TOGETHER the cause is
    --   structural — a club axis rule or a constraint — and not a surviving 맹견 trigger. Without
    --   this arm a red ⓑ would be read as "the gate is back", which is the wrong repair.
    perform set_config('request.jwt.claim.sub', o_ctrl::text, false);
    perform session_rsvp(v_s, d_ctrl);
    perform set_config('request.jwt.claim.sub', '', false);
    select id into sd_ctrl from session_dogs where session_id = v_s and dog_id = d_ctrl;
    if sd_ctrl is null then
      v_bad := v_bad || ' 대조군 동반 RSVP 픽스처가 만들어지지 않았다';
    else
      v_err := null;
      begin
        update session_dogs set custody = 'runner_delegated', responsible_profile_id = hh
         where id = sd_ctrl;
      exception when others then v_err := sqlerrm;
      end;
      if v_err is not null then
        v_bad := v_bad || ' ⚠ 대조군(평범한 강아지)의 커스터디 이동도 거절됐다 ['
                       || v_err || '] — 원인은 맹견 트리거가 아니라 구조적인 것이다'; end if;
      -- 🔴 ADDED 2026-08-25 (blind review, finding 8). This control used to observe ONLY that no
      --   exception was raised — and "no exception" is not "the write happened". A `before update`
      --   trigger that returns NULL suppresses the row silently: zero rows updated, zero errors,
      --   green control. That is the same failure shape this file's own header warns about for
      --   every other arm ("every arm that asserts a success also asserts its EFFECT"), and the
      --   control was the one place it had been skipped. It now reads back the END STATE, both
      --   columns, exactly as the subject arm ⓑ above does.
      select count(*) into v_n from session_dogs
       where id = sd_ctrl and custody = 'runner_delegated' and responsible_profile_id = hh;
      if v_n <> 1 then
        v_bad := v_bad || ' ⚠ 대조군의 커스터디가 예외 없이 실제로는 이동하지 않았다(=' || v_n
                       || ') — 트리거가 NULL을 반환해 쓰기를 조용히 삼키면 이 형상이 된다'; end if;
    end if;

    if v_bad = ''
      then call _pass('mgn-off','P5 이동 경로도 조용하다 — 핏불테리어 강아지의 예약이 러너 지명·수락·도착·인계 도장 양쪽·픽업(커스터디 이전 지점)까지 아무것도 raise하지 않고 실제로 picked_up에 도달하며, session_dogs의 동반 → 위탁 커스터디 UPDATE도 통과한다 (0119의 두 _move 트리거가 걸려 있던 바로 그 쓰기들). 평범한 강아지의 같은 이동이 대조군으로 함께 실행되고 대조군도 예외 부재가 아니라 **결과 상태**(custody + responsible_profile_id)로 검사되므로, 둘이 같이 붉어지면 원인은 맹견이 아니라 구조적인 것이다. ⚠ 범위: 이 핀은 대조군이 구형 t_dog(declared_none) 강아지라는 사실에 의존하지 않는다 — ⓒ가 가르는 것은 「맹견 트리거」와 「클럽/제약 구조」이지 신고 상태가 아니다');
    else v_msg := v_bad; call _fail('mgn-off','P5 UPDATE 경로', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P5 UPDATE 경로', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P6] 🔴 THE SLICE BOUNDARY — Slice A must NOT have taken the columns
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- This is the OVER-removal direction, and it is the one that costs a deploy-order constraint:
  -- while the columns exist, an installed bundle that still selects or writes them keeps working
  -- and this landing is safe in any order. Slice B drops them only once ZERO bundles reference
  -- them, MEASURED. So here the columns must EXIST and ACCEPT WRITES, the pair CHECK must still
  -- refuse a mismatched pair (a CHECK that exists but no longer constrains is not a CHECK), and
  -- the enum must still be a type. The trigger counts close the same door from the other side:
  -- 14/2/1, measured two ways at authoring (the whole migration chain incl. `create constraint
  -- trigger`, and the linked project's live pg_trigger on 2026-08-25 — identical name lists).
  -- ⚠ REWRITTEN 2026-08-25 after the blind review (finding 6). Every arm here used to prove an
  -- ITEM-SPECIFIC property with a COLLECTION statistic, and one accepted any exception at all as
  -- proof that a named CHECK had fired. Concretely, all of these passed the old version:
  --   · replacing the three columns with `text`-shaped look-alikes (a 3-name count cannot see type)
  --   · replacing the enum with any type of the same NAME (existence was the whole test)
  --   · a completely unrelated error during the malformed-pair UPDATE, read as "the CHECK fired"
  --   · swapping a required surviving trigger for an unrelated one (14/2/1 stays 14/2/1)
  -- The counts are kept — the measured battery showed the trigger-count arm is this file's broadest
  -- UNDER-removal detector (header note ⓐ) — but they are no longer the proof of anything specific.
  begin
    v_bad := '';

    -- ⓐ the three columns by NAME **and by shape**: exact type, nullability, default. A count of
    --   three names says nothing about whether an old installed bundle can still write them.
    select count(*) into v_n from pg_attribute a
     where a.attrelid = 'dogs'::regclass and not a.attisdropped
       and a.attname in ('dangerous_status', 'dangerous_basis', 'dangerous_declared_at');
    if v_n <> 3 then v_bad := v_bad || ' 🔴 세 컬럼이 남아 있지 않다(=' || v_n || ') — Slice B가 앞당겨졌다'; end if;
    select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                        || case when a.attnotnull then ' NOT NULL' else ' NULL' end
                        || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '<no default>'),
                      ' | ' order by a.attnum)
      into v_left
      from pg_attribute a
      left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
     where a.attrelid = 'dogs'::regclass and not a.attisdropped
       and a.attname in ('dangerous_status', 'dangerous_basis', 'dangerous_declared_at');
    if v_left is distinct from
       'dangerous_status:dog_dangerous_status NOT NULL:''undeclared''::dog_dangerous_status'
       || ' | dangerous_basis:text NULL:<no default>'
       || ' | dangerous_declared_at:timestamp with time zone NULL:<no default>' then
      v_bad := v_bad || ' 🔴 세 컬럼의 형상이 0119가 만든 것과 다르다 [' || coalesce(v_left, '∅')
                     || '] — 이름만 같은 컬럼은 구버전 번들에게 같은 컬럼이 아니다'; end if;

    -- ⓑ the enum as a TYPE with its ORDERED labels, and the column actually BOUND to it. "A type
    --   with this name exists" was the old test; a `create type dog_dangerous_status as enum ()`
    --   or a domain over text would have passed it.
    if not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace
                     and typname = 'dog_dangerous_status' and typtype = 'e') then
      v_bad := v_bad || ' 🔴 dog_dangerous_status가 이넘 타입으로 존재하지 않는다 — Slice B가 앞당겨졌다';
    else
      select string_agg(e.enumlabel, ',' order by e.enumsortorder) into v_left
        from pg_enum e join pg_type t on t.oid = e.enumtypid
       where t.typnamespace = 'public'::regnamespace and t.typname = 'dog_dangerous_status';
      if v_left is distinct from 'undeclared,declared_none,declared_dangerous' then
        v_bad := v_bad || ' 🔴 이넘 라벨이 0119의 순서/집합과 다르다 [' || coalesce(v_left,'∅')
                       || '] — 기대: undeclared,declared_none,declared_dangerous'; end if;
    end if;
    if not exists (select 1 from pg_attribute a
                    where a.attrelid = 'dogs'::regclass and a.attname = 'dangerous_status'
                      and a.atttypid = 'public.dog_dangerous_status'::regtype) then
      v_bad := v_bad || ' 🔴 dogs.dangerous_status가 dog_dangerous_status 이넘에 묶여 있지 않다'; end if;

    -- ⓒ the columns still take a write, both values of the pair — and the TIMESTAMP is observed
    --   too, with a fixed value rather than now(), so this arm reads back what was written instead
    --   of merely noting that nothing raised. (0127 dropped the trigger that used to overwrite it;
    --   P2 ⓓ pins that from the other side, on a fresh insert.)
    update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated',
                    dangerous_declared_at = v_stamp6
     where id = d_book;
    select count(*) into v_n from dogs
     where id = d_book and dangerous_status = 'declared_dangerous' and dangerous_basis = 'designated'
       and dangerous_declared_at = v_stamp6;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 남아 있는 컬럼에 쓴 값(짝 + 고정 타임스탬프)이 그대로 읽히지 않는다'; end if;

    -- ⓓ the CHECK: present, and enforcing **as itself**. SQLSTATE 23514 plus the constraint's own
    --   name, via `get stacked diagnostics` — an unrelated error is no longer proof.
    if not exists (select 1 from pg_constraint
                    where conrelid = 'dogs'::regclass
                      and conname = 'dogs_dangerous_basis_pairs_with_status'
                      and contype = 'c') then
      v_bad := v_bad || ' 🔴 dogs_dangerous_basis_pairs_with_status CHECK이 사라졌다 — Slice B가 앞당겨졌다';
    else
      v_err := null; v_con := null;
      begin
        update dogs set dangerous_basis = null where id = d_book;   -- 맹견인데 문이 없다
      exception when others then
        v_err := sqlstate;
        get stacked diagnostics v_con = constraint_name;
      end;
      if v_err is distinct from '23514' then
        v_bad := v_bad || ' 🔴 어긋난 짝이 CHECK 위반(23514)으로 거절되지 않았다 [sqlstate='
                       || coalesce(v_err, '예외 없음') || '] — 아무 예외나 CHECK의 증거로 받지 않는다'; end if;
      if v_con is distinct from 'dogs_dangerous_basis_pairs_with_status' then
        v_bad := v_bad || ' 🔴 거절한 제약의 이름이 다르다 [' || coalesce(v_con, '∅')
                       || '] — 다른 제약이 먼저 걸린 것이라면 짝 CHECK은 검사되지 않은 것이다'; end if;
    end if;

    -- ⓔ the surviving triggers by EXACT NAME SET, then by count. The name set is the proof; the
    --   count is kept because the measured battery showed it is the broadest under-removal
    --   detector in this file (header note ⓐ) — it reds on every trigger re-add.
    select array_agg(t.tgname order by t.tgname) into v_trg
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'bookings';
    if v_trg is distinct from c_trg_bookings then
      v_bad := v_bad || ' 🔴 bookings 트리거 집합이 기대와 다르다 [남는 것: '
                     || coalesce(array_to_string(array(select unnest(v_trg) except select unnest(c_trg_bookings)), ', '), '')
                     || ' · 없는 것: '
                     || coalesce(array_to_string(array(select unnest(c_trg_bookings) except select unnest(v_trg)), ', '), '')
                     || ' · 개수=' || coalesce(array_length(v_trg,1), 0) || '/14]'; end if;
    select array_agg(t.tgname order by t.tgname) into v_trg
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'dogs';
    if v_trg is distinct from c_trg_dogs then
      v_bad := v_bad || ' 🔴 dogs 트리거 집합이 기대와 다르다 [실제: '
                     || coalesce(array_to_string(v_trg, ', '), '∅') || ' · 기대: club_dog_materiality, t_dogs_touch]'; end if;
    select array_agg(t.tgname order by t.tgname) into v_trg
      from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'session_dogs';
    if v_trg is distinct from c_trg_session_dogs then
      v_bad := v_bad || ' 🔴 session_dogs 트리거 집합이 기대와 다르다 [실제: '
                     || coalesce(array_to_string(v_trg, ', '), '∅') || ' · 기대: club_v1_axes_sync]'; end if;

    -- ⓕ the three column COMMENTS, exactly. The columns survive Slice A, so 0119's documentation
    --   survived with them — and all three of those texts were false the moment 0127 dropped the
    --   triggers (「미신고면 위탁이 거절된다」, 「dangerous_declared_at은 서버만 찍는다」). 0127 §E
    --   replaces all three; this arm freezes the replacement. Digests are MEASURED out of the
    --   catalog, same rule as P4: if you change §E on purpose, re-read the values, do not relax
    --   the arm. The directional substrings underneath turn a red digest into a sentence.
    select md5(col_description('dogs'::regclass, a.attnum)) into v_left
      from pg_attribute a where a.attrelid = 'dogs'::regclass and a.attname = 'dangerous_status';
    if v_left is distinct from c_cmt_status then
      v_bad := v_bad || ' 🔴 dogs.dangerous_status 주석이 0127 §E의 것과 다르다 [' || coalesce(v_left,'∅') || ']'; end if;
    select md5(col_description('dogs'::regclass, a.attnum)) into v_left
      from pg_attribute a where a.attrelid = 'dogs'::regclass and a.attname = 'dangerous_basis';
    if v_left is distinct from c_cmt_basis then
      v_bad := v_bad || ' 🔴 dogs.dangerous_basis 주석이 0127 §E의 것과 다르다 [' || coalesce(v_left,'∅') || ']'; end if;
    select md5(col_description('dogs'::regclass, a.attnum)) into v_left
      from pg_attribute a where a.attrelid = 'dogs'::regclass and a.attname = 'dangerous_declared_at';
    if v_left is distinct from c_cmt_stamp then
      v_bad := v_bad || ' 🔴 dogs.dangerous_declared_at 주석이 0127 §E의 것과 다르다 [' || coalesce(v_left,'∅') || ']'; end if;
    for v_con in select unnest(array['dangerous_status','dangerous_basis','dangerous_declared_at']) loop
      select col_description('dogs'::regclass, a.attnum) into v_cmt
        from pg_attribute a where a.attrelid = 'dogs'::regclass and a.attname = v_con;
      if v_cmt is null then
        v_bad := v_bad || ' 🔴 dogs.' || v_con || ' 주석이 아예 없다 — §E는 지우는 게 아니라 바꿔 쓴다';
      elsif v_cmt not like '%0127%' then
        v_bad := v_bad || ' 🔴 dogs.' || v_con || ' 주석에 0127 표식이 없다 — 아직 없는 게이트를 설명하고 있다';
      elsif v_cmt like '%거절된다%' or v_cmt like '%서버만 찍는다%' then
        v_bad := v_bad || ' 🔴 dogs.' || v_con || ' 주석이 아직 0119의 동작(거절 / 서버 도장)을 주장한다'; end if;
    end loop;

    if v_bad = ''
      then call _pass('mgn-off','P6 슬라이스 경계 — 세 신고 컬럼이 **형상까지** 그대로고(타입·NOT NULL·기본값), 이넘은 라벨 순서까지 그대로이며 컬럼이 실제로 그 이넘에 묶여 있고, 컬럼은 고정 타임스탬프를 포함해 쓴 값을 그대로 돌려주며, 짝 CHECK은 **23514 + 자기 이름으로** 어긋난 짝을 거절하고, bookings/dogs/session_dogs의 잔존 트리거는 개수가 아니라 **정확한 이름 집합**(14/2/1)으로 일치하며, 세 컬럼 주석은 0127 §E가 다시 쓴 텍스트와 정확히 같다. 컬럼·CHECK·이넘 제거는 배포 실측 뒤 Slice B의 일이다. ⚠ 범위: 이 핀은 스키마 경계만 본다 — 어떤 설치 번들이 실제로 이 컬럼을 읽는지는 EAS/OTA 실측의 일이고 여기서 증명되지 않는다');
    else v_msg := v_bad; call _fail('mgn-off','P6 슬라이스 경계', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P6 슬라이스 경계', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
