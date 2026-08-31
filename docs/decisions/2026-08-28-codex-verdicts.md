# Codex verdicts — 2026-08-28 evening run (gpt-5.6-sol, xhigh, frozen export of trunk @ 18c17da)

Three slices had shipped with **no verdict** (usage walls, recorded honestly at the time). The
owed reviews ran tonight after the 20:19 lift. All three runs are genuine: `FINDINGS: <digit>`
detector hit on stdout, streams split, no trust-refusal, prompt echo excluded by construction.
Raw logs: announcer scratchpad `out-0154.log` / `out-0155.log` / `out-0159.log`.

| slice | verdict | findings | deployed? |
|---|---|---|---|
| 0154 phone collection switch + suite 185 | **REJECT** | 7 | **YES** (in production) |
| 0155 abandoned revocation reported + suite 186 | **REJECT** | 6 | **YES** (in production) |
| 0159 pack map channel + suite 190 + client pack files | **REJECT** | 11 | no — **must not deploy until fixed** |

**Exposure honesty:** the deployed REJECTs are not live fire today — phone collection and card
registration gates are verifiably shut by default (suite 185 G1's four-state check), and 0155's
worst finding "fires only once real revocations exist." The verdicts are **arming gates**: they
must be cleared before the corresponding ops flags ever flip.

## 0154 — REJECT, 7 findings (owner: phone/ops-flag surface)

1. CRITICAL — non-host participants can read phones: `_club_phone_visible` (0049:180-190) is
   bidirectional host↔everyone and `club_session_roster` (0053:403-430) embeds numbers for every
   `full` participant. ⚠ Whether guest→host phone visibility is intended is **Sean's product
   call** — the ruling on file says "phones stay host-only" but predating machinery is wider.
2. HIGH — a dogless guest can stay admitted forever without entering a phone; nothing enforces
   requiredness after RSVP (0134:112-131), and suite 185 has no session fixture for it.
3. CRITICAL — the collection switch gates only WRITES (0154:139-145); visibility paths
   (`_club_phone_visible`, roster) never consult `phone_collection_live()` — numbers written via
   0133/service_role are returnable while the flag is closed.
4. CRITICAL — `incident_contact` (0088:238-270) returns both booking parties' phones to either
   party once profiles.phone populates. (1:1 booking surface, predates slice — same Sean call
   as #1.)
5. MEDIUM — party-before-state in `set_my_phone` implemented but unpinned (no signed-out,
   closed-gate fixture asserting `not_signed_in`).
6. MEDIUM — W1 uses bare `IF has_*` (NULL-silent) and can't prove 0154 owns the ACL (0133 set it;
   CREATE OR REPLACE preserves it).
7. HIGH — **verified at source by announcer**: suite G1 `delete from ops_flags` + reinsert of
   only `(id, updated_at)` destroys every sibling ops switch; G4 restores only the phone field.
   Snapshot/restore the whole row.

## 0155 — REJECT, 6 findings (owner: billing/revocation surface — ui6's world)

1. CRITICAL — lone stranded row at attempts=8 is unreachable: dispatcher counts only
   `attempts < 8`, records idle, never invokes the worker, so the cap-sweep inside
   `claim_billing_key_revocations()` never runs. Suite's B1 bypasses the dispatcher.
2. CRITICAL — empty alert roster is permanently recorded as alerted: `alerted_at` stamps with
   zero notifications inserted; dedupe guard then blocks retry forever. Provisioning a recipient
   later sends nothing.
3. HIGH — late report with NULL token can rewrite terminal rows: reporter UPDATE lacks
   `state='processing'` and NULL p_token matches a cleared claim_token → `abandoned→done` while
   the key is live. Three-arg/default-NULL call shape is still actively tested in repo.
4. HIGH — pre-0155 abandoned rows (NULL new column) classify as `abandoned_benign` forever;
   absence of classification fails OPEN.
5. MEDIUM — deleting report-side `claim_token = null` leaves the whole suite green (A1 never
   reads the token or replays it).
6. MEDIUM — cap sweep's `lease_until < now()` guard has no live-lease control; deleting it
   reddens nothing.

## 0159 — REJECT, 11 findings (owner: announcer client half + server; DO NOT DEPLOY yet)

1. CRITICAL — **verified at source**: geo.ts:539,561 create pack channels WITHOUT
   `REALTIME_PRIVATE` while 0159's policies bind private joins only. Deliberate at write time
   (server half didn't exist — geo.ts:501-513 says so and names the switch as handover); now
   that 0159 is on trunk the client must flip BEFORE deploy, else the gate is decorative
   (public channels allowed) or the feature is dead (private_only).
2. CRITICAL — realtime authorization is cached per connection: the live-window conjuncts are
   checked at join, not per broadcast — a participant who joins checked-in can keep publishing
   after done/cancel/revocation until socket refresh. Suite's post-mutation calls simulate fresh
   authorization, not an existing socket.
3. HIGH — map screen opens two channels with the same topic (usePackShare + subscribePack);
   realtime-js allows one active subscription per topic — publisher can evict the receive
   channel. Needs one shared/ref-counted channel.
4. CRITICAL — payload identity forgeable: client never calls `club_pack_map_roster`; a
   checked-in attacker can publish another member's profileId/name with a newer timestamp.
   Sender identity needs structural server-side binding.
5. HIGH — unbounded peer Map: unique profileIds retained forever, full-Map clone per message —
   memory/CPU DoS. Test pins filtered output only, not eviction.
6. HIGH — delegated runners on club/run/[sid] don't publish (known unwired entry point — routed
   to b6) → "everyone sees everyone" is violated for them.
7. MEDIUM — "내 위치 공유 중" set from local GPS state before publish resolves; publisher may be
   unjoined/denied/offline. Honesty law: bind real publisher state.
8. MEDIUM — publisher cleanup races async subscribe in geo.ts:562-574 (no stopped guard).
9. HIGH — no product entry point to /club/map/<sid> at all (deep-link only) — known, routed
   to b6 with #6.
10. MEDIUM — masthead renders clubName from URL param unbound to session (spoofable deep link).
11. HIGH — suite 190's SQL "boundary" cannot observe socket-level failures (#1/#2/#3); R1/R2 and
    P1/P2 controls share the `channel_allowed` oracle; ACL pins use bare `IF has_function_privilege`
    (NULL-silent) — the S10 class again.

## 2026-08-31 addendum — the two remaining deployed-unreviewed slices (announcer runs)

Fresh frozen export @ trunk `91431c8`. Same detectors, one refinement measured on this very run:
**a positive failure-check (`usage limit` / `trusted directory`) that greps the WHOLE stderr
matches CLAUDE.md's own codex section when codex reads the repo** — 5 false hits here beside a
genuine verdict. Match failure strings only in the final ERROR lines (`tail -3`), or read the
stdout digit-detector first; stderr content includes every repo file codex opens.

| slice | verdict | findings |
|---|---|---|
| 0153 board-impl-not-for-clients + suite 184 | **REJECT** | 2 |
| 0156 gps_trace_bounds | walled at 101k tokens (「try again at 6:09 PM」) — retry scheduled; **UNREVIEWED** | — |

### 0153 — REJECT, 2 findings

The slice's own revoke chain is CLEAN (verified through 0159: last inner definition 0147, no
later regrant; suite 184 pins both directions). Both findings are about the OUTER wrapper:

1. HIGH — the outer definer (`0052:149`) does not own its security envelope: `search_path =
   public` only (no pg_temp, not in-body-first), grant to authenticated with no PUBLIC/anon
   revoke — a baselined debt (`check-definer-acl-baseline.txt:51`). Partial-apply/restored
   environment recreates it PUBLIC-executable and suite 184's outer check still passes
   (authenticated inherits PUBLIC). Fix shape: forward wrapper redefinition with in-body
   search_path + same-file revoke/grants; verify PUBLIC/anon/authenticated separately.
2. MEDIUM — the wrapper computes `p_access = 'none'` and then calls the inner function anyway:
   any authenticated stranger with a session UUID reads openIncidents/unassignedIncidents
   (0147:84) and paid-dog/present-runner counts (0048:378). ⚠ **Ruling context:** Sean's
   2026-08-28 total-public ruling plausibly makes the DISCLOSURE itself acceptable — but the
   code's own access model says 'none' and then ignores itself, which is an honesty defect
   either way. Fix direction (minimal whitelist for `none`, or drop the pretense and make
   public-by-design explicit) is the backend's call within the ruling; no console question
   needed unless they think the ruling doesn't cover incidents.

Owner: backend session (both findings live in 0052's wrapper — same file family as its queued
`session_set_backup` gate conversion; natural one-slice bundle).

- **0159 deploy gate:** client private-flag fix (geo.ts:539,561) + findings 2-5 triage BEFORE
  `db push` of 0159. The migration being on trunk is fine; deploying it is not.
- **Flag-flip gates:** 0154/0155 findings must be cleared before phone collection or card
  registration ops flags are armed. Until then production exposure is nil (gates verified shut).
- Two findings (0154 #1/#4) are product calls for Sean, not defects to fix unilaterally: does
  guest↔host phone visibility and incident_contact's both-party disclosure survive the
  "phones stay host-only" ruling?
