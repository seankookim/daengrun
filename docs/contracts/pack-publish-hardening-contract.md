# Pack publish hardening — 0160/0161 contract (B1: the 0159 REJECT/11 fix pass)

Backend master session, 2026-08-31. This contract binds the server lane and the client lane of
one landing. The codex verdict on 0159 is REJECT/11 (`docs/decisions/2026-08-28-codex-verdicts.md`
§0159); 0159 is on trunk and NOT deployed; production is at 0156. Findings #6/#9 (entry doors)
were closed by the UI session's U2 (`1cccaea`). Everything else is this landing.

## Measured foundations (production, 2026-08-31 — do not re-derive, they were observed)

1. **`PrivateOnly: This project only allows private channels`** — a public-channel join is
   refused by the deployed project. The trunk client's two public `supabase.channel(topic)` calls
   (geo.ts:539, 561) could never have joined. The private flip is mandatory, not hygiene.
2. **Partition janitor wakes on socket connect.** Idle production had 7 daily partitions on
   `realtime.messages` ending 2026-08-29 (a 2-day gap — an insert would have failed). Holding one
   anon socket open for ~75 s took it to 12 partitions, newest `messages_2026_09_03`. So
   broadcast-from-DB works whenever any viewer is connected, and first-wake joins can fail with
   `MissingPartition` then succeed on the client's auto-rejoin.
3. **`postgres` has BYPASSRLS = true and INSERT privilege on `realtime.messages`** — a
   postgres-owned SECURITY DEFINER can insert regardless of policies.
4. **`realtime.send(payload, event, topic, private)` exists and SWALLOWS EVERY ERROR** (deployed
   prosrc: `EXCEPTION WHEN OTHERS THEN RAISE WARNING`, returns void). A send that fails leaves no
   client-visible signal. Delivery was OBSERVED (diag row landed, then removed).
5. 🔴 **Same-statement snapshot trap, measured here:** `select realtime.send(...), (select
   count(*) from realtime.messages ...)` returns 0 — the count reads the statement-start
   snapshot and structurally cannot see the insert. Any verify-read (in the RPC AND in every
   suite pin) must be a LATER statement. A pin that counts in the send's own statement is
   green-blind by construction.
6. `realtime.send` keeps a caller-supplied `payload->>'id'` in the payload but the ROW id is
   always its own `gen_random_uuid()` — verify by `payload->>'id'`, never by row id.
7. Realtime-js (installed 2.112.4) **dedupes channels by topic**: `supabase.channel(t)` returns
   the existing channel for `t`; the second call's config is DISCARDED and a second
   `.subscribe()` on a joining/joined channel registers no status callback. Flipping `private`
   on one of two same-topic calls is a no-op.

## The design in one paragraph

Pack positions are published by a new RPC, `club_pack_publish`, which re-checks membership and
the window on EVERY call, authors the payload entirely server-side (`profileId` = `auth.uid()`,
name from `profiles`), broadcasts via `realtime.send`, and verify-reads its own row (foundation
4/5) so failure is a refusal the client can render honestly. Client socket writes to pack topics
become impossible: the `pack channel write` policy is DROPPED and `channel_allowed`'s pack-write
arm removed (deny-by-no-policy). The subscriber side stays a private broadcast channel (read
policy unchanged), now joined with `REALTIME_PRIVATE` through ONE ref-counted channel per topic.
The map keys peers on the server roster and takes names/icons from it; the payload contributes
only position + freshness. This closes #4 structurally (no client-authored identity anywhere in
the pipeline), #2's write side completely (nothing is cached — every publish is re-gated), #3
(the publisher channel no longer exists; one subscriber channel remains), #7 (share status =
the last RPC's verified result), #8 (no publisher channel to race; the remaining hook cleanup is
an alive-flag), #5 (roster-bounded Map + eviction), #10 (masthead binds `roster.clubName`).

**#2 read-side residual, documented as the design call:** a subscriber's read authorization is
cached per socket, so a socket that joined during the window keeps RECEIVING after it closes —
but reads are public by Sean's ruling (2026-08-28, 「total public」), and post-window there is
nothing to receive because every publisher is refused per-publish server-side. The write side —
the side that matters — has no cache in the path at all.

## Server lane (migration `0160_pack_publish_hardening.sql`, suite `191`, labels `0160-*`)

### §A `club_pack_publish(p_session uuid, p_lat double precision, p_lng double precision) → jsonb`

- `plpgsql volatile security definer`, in-body `set search_path = public, pg_temp`. Explicit
  `revoke ... from public, anon; grant ... to authenticated, service_role` in this file.
- Flat return, whitelisted: `{ok: boolean, refusal: text|null}`. Refusal vocabulary (exact):
  `not_signed_in` · `not_checked_in` · `window_closed` · `bad_position` · `too_fast` ·
  `not_delivered`. Party gate before state gate, in this order:
  1. `v_uid := auth.uid()`; null → `not_signed_in`.
  2. Membership: a `session_people` row with `session_id = p_session and profile_id = v_uid and
     attendance = 'checked_in' and checked_in_at is not null` → else `not_checked_in` (missing
     session and foreign session answer identically). ⚠ This conjunction (BOTH attendance and
     stamp) is deliberately the roster's own row-set predicate (0159:367-368), which makes
     0159 §B's claim 「the roster is exactly the write set」 TRUE by construction — it is false
     today (window ② vs write-arm divergence found by scout). Say this in a comment.
  3. Window: `_club_pack_window(p_session) is not true` → `window_closed`.
  4. Coords: null, out of [-90,90]/[-180,180], or exactly (0,0) → `bad_position`.
  5. Throttle: `club_pack_publish_marks.last_at > now() - interval '2 seconds'` → `too_fast`.
     The mark is written ONLY on success.
  6. Payload, authored here and nowhere else: `jsonb_build_object('id', v_msg_id, 'profileId',
     v_uid, 'name', coalesce(profiles.name, '참가자'), 'lat', p_lat, 'lng', p_lng, 'at',
     <now() as ISO-8601 UTC with Z>)`. `v_msg_id := gen_random_uuid()`.
  7. `perform realtime.send(v_payload, 'pos', 'pack-' || p_session::text, true);`
  8. Verify-read (LATER statement, foundation 5/6): `exists(select 1 from realtime.messages
     where topic = v_topic and event = 'pos' and payload->>'id' = v_msg_id::text)` → else
     `not_delivered`.
  9. Upsert the mark; return `{ok: true, refusal: null}`.
- Header comments must state the #2 and #4 design decisions (the paragraph above, compressed).

### §B `channel_allowed` — REPLACE (re-state the full ACL in this file; `check-definer-acl` law)

Remove the pack WRITE arm (0159:233-241). `v_family='pack' and p_op='write'` now falls through
to false. Keep the pack READ arm and everything else byte-equal to 0159's version. Comment:
writes go through `club_pack_publish`; a socket write has no policy to admit it.

### §C policies

`drop policy if exists "pack channel write" on realtime.messages;` (guarded by the same
`to_regclass` check 0159 uses). `pack channel read` unchanged. Policy total goes 5 → 4.

### §D `club_pack_map_roster` — REPLACE (re-state ACL) adding `clubName`

One new top-level key `clubName` (`clubs.name` via `club_sessions.club_id`), present whether or
not the window is open. Everything else byte-equal. (#10's server half — the masthead binds this.)

### §E `club_pack_publish_marks`

`(profile_id uuid primary key, last_at timestamptz not null)`. Enable RLS, create NO policies,
and explicitly `revoke all ... from anon, authenticated` (default-privilege hygiene — the same
law as 0161). Grant nothing; only the definer touches it.

### §F VERIFY block — house form ONLY (`is distinct from`, never a bare `IF has_*`)

Assert: the 5 functions definer + in-body search_path; `club_pack_publish` executable by
authenticated and NOT by anon; `channel_allowed`/`_club_pack_window` still sealed;
`pack channel write` ABSENT and `pack channel read` present (policy total 4); roster source
contains `clubName`; marks table `relrowsecurity` true and client privileges absent. Source
checks comment-stripped (`regexp_replace(prosrc, '--[^\n]*', '', 'g')`).

### Suite 191 (`0160-*` labels) — new pins, all mutation-verified

Fixtures: BUILD YOUR OWN sessions/users (suite 190 leaves its fixtures and probe rows in place;
do not count anything on a topic you did not create). `now()` is frozen per transaction — the
throttle's pass-after-wait arm is exercised by rewinding the mark row, not by waiting.

- Happy path: checked-in member publishes → `{ok:true}`; verify in a SEPARATE statement the row
  landed with `event='pos'`, `private=true`, correct topic, and payload key set EXACTLY
  `[at, id, lat, lng, name, profileId]`, `profileId` = the caller.
- Identity is structural: two different callers → each row carries its OWN uid; there is no
  argument that can move it (say so in prose; the signature is the proof).
- Refusal matrix: no JWT → `not_signed_in` · stranger → `not_checked_in` · rsvp-not-checked-in →
  `not_checked_in` · a row in the DIVERGENCE ZONE (`attendance='checked_in'`, `checked_in_at`
  NULL — insert it directly) → `not_checked_in` (this is the fixture that can see the
  conjunction; a fixture where both halves agree cannot) · `status='done'` → `window_closed` ·
  (0,0) and out-of-range → `bad_position` · second call same txn → `too_fast`, and after
  rewinding the mark 3 s → ok.
- Boundary: `set local role authenticated` + JWT claim of a checked-in member → direct INSERT
  into `realtime.messages` with a pack topic must be REFUSED (no policy admits it).
- Source pin (comment-stripped): `club_pack_publish` prosrc contains `realtime.send` AND a
  read of `realtime.messages` (the verify-read — the only detector for the swallow class).
- Mutation battery (each plant `&&`-chained, asserted landed, CONTROL first and last):
  window check removed · membership conjunct removed · `checked_in_at` half-conjunct alone
  removed (the divergence fixture reddens) · profileId hardwired to a constant (two-caller pin
  reddens) · verify-read removed (source pin reddens) · throttle removed · coord guard removed ·
  a permissive INSERT policy re-added (boundary pin reddens) · 0159's pack-write arm restored in
  `channel_allowed` (updated 190 pin reddens) · `clubName` dropped from roster.

### Suite 190 updates (same slice, each with a WHY comment naming 0160)

- `0159-P1` INVERTS: pack write via `channel_allowed` is now false for EVERYONE including the
  checked-in host. `0159-P2` stays (still false — its arms are unchanged truths). `0159-P3`'s
  write-true control INVERTS. `0159-E1`'s 「guest INSERT must succeed」 INVERTS to refused.
  `0159-W1` policy count 5→4 and asserts `pack channel write` ABSENT.
- `0159-W2`: rewrite all 9 bare `IF has_function_privilege` arms to the house
  `is distinct from` form (the file's own header at S:13-17 claims this discipline; make it true).
- Header note answering codex #11 honestly: the read controls' second door is E2 (boundary via
  `realtime.messages` as anon); the write controls now live in suite 191 through a different
  oracle entirely (RPC + table row). Socket-level behaviour (join caching, private handshake)
  remains structurally invisible to a SQL harness — that is a property of the shim, stated as
  prose, not pinned.
- `143 W1`: policy total 5→4 (same WHY comment).

### Shim (`00_shim.sql`)

Add `realtime.send` mirroring the deployed prosrc (id-embed into payload, `SET LOCAL
realtime.topic`, INSERT, `EXCEPTION WHEN OTHERS THEN RAISE WARNING`) — copied from production
2026-08-31, say so in a comment. The shim's `realtime.messages` is unpartitioned; the
`not_delivered` arm is therefore UNREACHABLE in the harness — that limitation is PROSE in suite
191's header (an unfalsifiable pin must not be written), and the verify-read's existence is
guarded by the source pin instead.

### Drift fixes (comment-only, same slice)

- `190` S:1 header `187:` → `190:` · 0159's in-file 「suite 187」 references stay (landed
  migration, do not edit) — fix only living files: `harness.sh:231` (the suite-187 line's pin
  labels are `0156-G*`, not `0159-G*`) and `harness.sh:234` (`0156` → `0159`), plus the
  `143`/`98`/`99` comment references to 「0156 팩 지도」 → 0159 where those files are already
  being edited for pin changes; leave untouched files untouched.

### Migration `0161_billing_keys_client_grants.sql`, suite `192` (`0161-*`)

Revoke ALL client privileges on `billing_keys` from `anon` and `authenticated`, mirroring
`billing_key_revocations`. Verified before claiming: RLS on since 0080:110 with zero policies;
only edge functions (service_role) read it. Pins (house form): the four
`has_table_privilege` arms false for both roles; `service_role` SELECT still TRUE (the control
that fails on over-reach); `relrowsecurity` true. Mutation: revoke deleted → grant pins redden
(the two-sided proof the fixture starts where production starts — the shim's default privileges
DO grant these, measured in `00_shim.sql:82-95`). VERIFY block in-file, house form.

### Gates for the server lane

Harness: measure the BASELINE first on this merged tree (the prose 1128 is stale — 0156/187
merged after it; expect ~1135 but MEASURE), then after; the delta must equal exactly the pins
added, and say both numbers. `node scripts/check-definer-acl.mjs` (0160 re-replaces functions —
ACLs re-stated in-file). Count pass/fail across the WHOLE harness output, never `tail`.

## Client lane (same landing; hook signature FROZEN — three live callers: map, companion, run)

### `app/src/lib/api.ts` (SHARED — append-only, far from existing mappers)

- `packPublish(sessionId, lat, lng)` → `supabase.rpc('club_pack_publish', { p_session:
  sessionId, p_lat: lat, p_lng: lng })` with the inline object literal (check-rpc-contracts
  scans only api.ts). Map the flat return; on PostgREST `PGRST202` (RPC not yet deployed) return
  `{ok:false, refusal:'not_deployed'}` rather than throwing — the client stays honest across
  the land→deploy window.
- `fetchPackRoster(sessionId)` → `supabase.rpc('club_pack_map_roster', { p_session })`, typed
  flat: `{sessionId, status, scheduledAt, meetupPoint, windowOpen, topic, clubName, people:
  [{profileId, name, role, isHost, isRunner}]}`.

### `app/src/lib/geo.ts` (pack section + one named exception)

- `subscribePack`: joins with `REALTIME_PRIVATE` through a NEW module-level ref-counted
  per-topic registry (modeled on api.ts:3097-3160 `sharedWatchers` — await an in-flight
  teardown before rejoining the same topic; foundation 7 is why a registry, not a second
  channel). The dropped-guard also suppresses the teardown's own `CLOSED` status so unmount
  does not fire `onState('error')`.
- DELETE `createPackPublisher` entirely (the RPC replaces it; its race dies with it).
- `createPosPublisher` (run2 fan-out): add the `pubCh !== ch`-style generation guard that
  `publishPos` already has — same finding sentence (#8), second observable site, behaviour
  otherwise unchanged. (Announced to the UI session; their run-screen line calls it via
  usePackShare — no signature change.)
- REWRITE the stale comment block at geo.ts:499-513: the world it describes ended (0159 landed;
  PrivateOnly is enforced — measured; the publisher is an RPC now).

### `app/src/lib/pack.ts` (pure module — every change pinned in pack.test.cjs)

- Keep `parsePackPos` as the belt (payloads are server-authored now, still validated).
- `mergePeer` gains an `allowed: Set<string> | null` argument (null = allow all, for tests):
  a payload whose `profileId` is not in the roster set is DROPPED. Map size is thereby bounded
  by |roster|.
- New `prunePeers(peers, nowMs)`: evict entries older than `PACK_PEER_EVICT_MS` (10 min);
  referentially stable when nothing prunes (same-Map return, like mergePeer's unchanged path).
- Roster display precedence: name/icon come from the ROSTER person, position/freshness from the
  payload. Expose a pure helper if the screen needs one.

### `app/src/lib/use-pack-share.ts`

- Tick every 3 s (keep `PACK_PUB_MIN_MS`): read `getLiveLastFix()`; no fix / stale →
  `sharing=false` locally; else `await packPublish(...)` → `ok` → true; `too_fast` → keep
  previous value; any other refusal (incl. `not_deployed`, `not_delivered`) → false. An
  `alive` flag guards the in-flight await across unmount. No channel, no publisher object.
- Hook SIGNATURE and return type (`boolean | null`) unchanged — three live call sites.
- Fix the stale header (the run-screen line IS wired — U2 `1cccaea`).
- `packIdentity` unchanged.

### `app/app/club/map/[sid].tsx`

- Fetch the roster on mount and every 30 s while mounted (alive-guarded — the screen's
  `loadSession` lacks one; add it there too, it is in-claim). Key/filter peers by roster ids
  (pass the Set to `mergePeer`), render names/icons from roster, prune on the existing 5 s age
  tick.
- Masthead: `roster.clubName ?? '팩 지도'`; DELETE the `clubName` URL param entirely (#10).
- The share line keeps its binding to `usePackShare` (semantics are now honest upstream).
- Anon viewers: `club_session_detail` is authenticated-only (scout §9) — roster is the
  anon-safe source; do not add new dependence on `detail`.

### Client gates

`./node_modules/.bin/tsc --noEmit` · `check-rpc-contracts` (should go +2 calls — say the
before/after counts; the delta is the positive control) · `check-route-native-imports` ·
`check-device-clock` (no new device-clock reads; `at` handling stays epoch-delta) ·
`npm test` counted across the WHOLE chain (`grep -c '^PASS'`/`'^FAIL'`, exit code — never
`tail`), with pack.test.cjs updated for every pack.ts change in the same commit.

## Landing & deploy protocol

One landing for 0160 + client (single commit, explicit pathspecs), 0161 its own commit, same
push. Read both back from origin. Codex review (frozen git-initialized export, FINDINGS/VERDICT
digit detector, streams split) BEFORE any deploy; on REJECT, fix and re-freeze. Deploy = one
`supabase db push` applying 0159+0160+0161 together, then `supabase migration list --linked`,
prosrc/policy/ACL read-backs, and the production controls (roster as anon over PostgREST; RPC
refusal as anon). Announce to the announcer before the push. GitHub CI is informational only.
