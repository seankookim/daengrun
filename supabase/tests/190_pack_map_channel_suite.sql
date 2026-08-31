-- ═══ 190: 팩 지도 채널 (0159) — 0159-S1~S5 · R1~R3 · P1~P3 · E1~E3 · M1~M3 · W1~W3 · N1 ═══════
--
-- ⚠ [0160, 2026-08-31] The header said `187:` — this file has been `190_…` since the renumber
--   (b12b4a7). Comment-only drift, fixed while the file was open for the pin changes below.
--
-- ═══ 🔴 WHAT 0160 CHANGED IN THIS FILE, AND WHY EACH PIN MOVED ══════════════════════════════
-- 0159 was reviewed by codex and came back **REJECT with 11 findings**
-- (`docs/decisions/2026-08-28-codex-verdicts.md` §0159); it is on trunk and was never deployed.
-- 0160 answers the server half. The one structural change: **a socket may no longer WRITE a pack
-- topic at all.** Publishing goes through the RPC `club_pack_publish`, which re-gates party and
-- window on EVERY call — because realtime authorization is CACHED PER SOCKET (codex #2), so a
-- policy evaluated once at join can never close a window — and authors the payload server-side,
-- which is what makes 「a publisher cannot claim another member's identity」 structural rather
-- than a client convention (codex #4).
--
-- So `channel_allowed(pack-…, <anyone>, 'write')` is now **false for everyone, the checked-in
-- host included**, and `pack channel write` no longer exists. Four pins here asserted the
-- opposite, correctly, and are INVERTED with this comment naming 0160:
--   · `0159-P1` — was 「five kinds of checked-in participant MAY publish」, now 「nobody may」.
--   · `0159-P3` — its write-true positive control (the neighbour session's checked-in host).
--   · `0159-S5` — its 동반 owner's write-true arm.
--   · `0159-E1` — its 「the checked-in guest's INSERT succeeds」 boundary arm.
--   · `0159-W1` — policy total 5 → 4, and `pack channel write` asserted ABSENT.
--   · `0159-M3` — the roster's top-level key set gains `clubName` (0160 §D, codex #10) and
--     `serverNow` (0160 §D, /autoplan addendum item 1c — the viewer's clock offset, needed now
--     that every broadcast `at` is stamped by the server). 7 keys → 9.
-- ⚠ **A PIN THAT REVERSED IS NOT A PIN THAT WAS WEAK.** P1/E1 described the shipped behaviour
--   accurately; the behaviour they described was the defect. Reversing them is the testing
--   working, and it is recorded as a reversal rather than quietly rewritten.
--
-- 🔴 **CONSEQUENCE FOR THE CONTROL PAIRS, AND IT IS AN HONEST LOSS ON THIS SIDE.** P1/P2 were a
--   pair because one was blind to a write side admitting everybody and the other to one admitting
--   nobody. With the write door gone, both arms now assert FALSE and the pair collapses into one
--   claim printed twice — exactly the failure CLAUDE.md names. **The write controls now live in
--   suite 191 through a different oracle entirely** (`club_pack_publish` + the row it lands in
--   `realtime.messages`): `0160-A1` is blind to an RPC that admits everybody, `0160-A3` to one
--   that admits nobody, and no constant satisfies both. P1/P2 here are kept as the socket door's
--   *deny* regression, which is a smaller and true sentence.
--
-- ⚠ **codex #11, answered honestly rather than closed.** The finding was that this file's
--   「boundary」 cannot observe socket-level failures and that R1/R2 + P1/P2 share the
--   `channel_allowed` oracle. Half of it is now fixed: the read controls' second door is `E2`
--   (an anon SELECT at the `realtime.messages` boundary, the only pin in the repo that can see
--   the `pack channel read` POLICY), and the write side moved to a different oracle in 191.
--   The other half is NOT fixed and cannot be from SQL: **join caching, the private-channel
--   handshake and `PrivateOnly` enforcement are properties of the realtime SERVER, and this
--   harness has a shim table where production has a socket.** That is a limitation stated as
--   prose. It is not written as a pin, because a pin whose arms cannot fail is an unfalsifiable
--   guard doing prose's job — 0160 answers it by DESIGN instead (a cached join now authorizes
--   nothing, because there is nothing to authorize).
--
-- 🔴 THE PROPERTY THIS FILE OWNS, in one sentence: **the READ side is public by ruling and the
--    WINDOW is the only thing that bounds it**, so every pin that matters here is either (a) an
--    execution proving `anon` really is admitted, or (b) a mutation on the window / the write
--    side that has something to catch. A public read policy has no interesting denial to test;
--    if the whole battery only reddened on 「a stranger got in」 it would be measuring nothing,
--    because a stranger getting in IS the feature.
--
-- ⚠ **PIN LABELS ARE SLICE-PREFIXED** (`0159-…`, CLAUDE.md). `S`/`R`/`P`/`E`/`M`/`W`/`N` collide
--   with three other suites' unprefixed labels; the prefix owns the namespace instead of sharing it.
--
-- ⚠ **EVERY PREDICATE ASSERTION IS `is not true` / `is not false`, NEVER a bare `if f(...)`.**
--   plpgsql skips an `IF` on a NULL predicate in BOTH directions, so a helper that returns NULL
--   instead of false leaves every arm silent — and every arm in this file exists to notice
--   something MISSING, which is precisely the shape that collapse kills (CLAUDE.md, measured on
--   the announcer's own S10 and on four of ui6's pins within the hour).
--
-- ⚠ **THE CONTROL PAIRS, named the way CLAUDE.md asks — state the failure mode each arm is blind
--   to; identical lists mean one control printed twice.**
--     · `0159-R1` (public read admits everyone incl. anon) is blind to a channel that is ALWAYS
--       open. `0159-R2` (read is false while the window is closed) is blind to a channel that is
--       always shut. A predicate hard-wired to `true` reddens R2 only; hard-wired to `false`
--       reddens R1 only. No single constant satisfies both.
--     · `0159-P1` (a checked-in participant MAY publish) is blind to a write side that admits
--       everybody. `0159-P2` (rsvp-not-checked-in / stranger / anon may NOT) is blind to a write
--       side that admits nobody. Same argument, on the other door.
--     · `0159-E2` is the ONLY pin in the repo that can see the `pack channel read` POLICY at all.
--       0108's `party channel read` has no topic guard, so an AUTHENTICATED reader reaches a
--       `pack-` topic through it with the identical answer — dropping `pack channel read` is
--       invisible to every authenticated arm and kills exactly the public half of the ruling.
--       That is why E2 executes as `anon` at the boundary rather than asserting a predicate.
--
-- ═══ THE MUTATION BATTERY, MEASURED 2026-08-28 ═══════════════════════════════════════════════
-- ⚠ **[0160, 2026-08-31] THIS TABLE IS THE 0159-ERA MEASUREMENT AND IS KEPT AS THE RECORD OF
--   WHAT WAS OBSERVED THEN, NOT AS A CLAIM ABOUT TODAY.** Its baseline (1128) predates 0154/0155/
--   0156/0160/0161, and the rows touching the WRITE side (M2, M2c, M7, M13) describe a door 0160
--   removed — M7's 「weaken write to mere membership」 has nothing left to weaken. The read-side
--   rows (M3~M6, M8, M10~M12) still describe live behaviour. 0160's own battery, against 0160's
--   own baseline, is recorded in `191_pack_publish_suite.sql`. A measurement's write-up outlives
--   the thing measured, so it is dated rather than deleted.
-- Baseline **1107 → 1128 (+21 = exactly the pins in this file)** — the positive control that this
-- suite RAN rather than being silently skipped from `harness.sh`'s manifest.
-- ⚠ Every plant was `&&`-CHAINED to its harness run, so a plant that failed its own
--   `assert count == 1` yields NO ROW rather than a plausible green one. Every row below printed,
--   so every mutation genuinely landed. CONTROL was observed clean BEFORE any row was read
--   (1128/0) and again after (1128/0), with the tree restored from the index.
--
-- | # | mutation | result |
-- |---|---|---|
-- | CONTROL | none | **1128/0** — observed first, so the deltas mean something |
-- | M1  | delete the `anon` role from `pack channel read` | **APPLY ABORTS** at §E VERIFY |
-- | M1b | same, both VERIFY arms removed | 1126/2 = `0159-W1` + **`0159-E2`** |
-- | M2  | rename `pack channel write` | APPLY ABORTS at §E VERIFY. ⚠ **AND THE PLANT WAS WRONG** — a rename leaves the DOOR open with a different name, so it measured the policy's NAME. Re-done as M2c |
-- | M2c | genuinely REMOVE the write policy block, VERIFY arms removed | 1125/3 = `143 W1` + `0159-W1` + **`0159-E1`** (the guest's INSERT is refused at the boundary — the door, not the name) |
-- | M3  | window ② deleted (「somebody checked in」) | 1125/3 = `0159-S1`·`S5`·`R3` |
-- | M4  | window ④ deleted (the clock band) | 1127/1 = **`0159-S4` alone** |
-- | M5  | window ③ deleted (러닝 종료) | 1127/1 = **`0159-S3` alone** |
-- | M6  | window ① deleted (session status) | 1124/4 = `0159-S2`·`R2`·`E2`·`M2` |
-- | M7  | 🔴 WRITE weakened from `checked_in` to mere membership | 1127/1 = **`0159-P2` alone** |
-- | M8  | public READ made unconditional (`return true`) | 1123/5 = `0159-S1`·`S3`·`R2`·`R3`·`E2` — and **NOT `R1`** |
-- | M9  | revoke `my_channel_allowed` from `anon` | **APPLY ABORTS** at §E VERIFY |
-- | M9b | same, VERIFY arm removed | the harness **DIES** at `143` with a top-level 42501 — see the note below |
-- | M10 | 「simplify」 §B's guard split back to 0108's single line | 1124/4 = `0159-S5`·`R1`·`W3`·`E2` |
-- | M11 | widen the public roster with `avatarUrl` | 1127/1 = **`0159-M3` alone** |
-- | M12 | disclose names while the window is CLOSED | 1127/1 = **`0159-M2` alone** |
-- | M13 | WRITE returns false for everybody | 1124/4 = `0159-S5`·**`P1`**·`P3`·`E1` — and **NOT `P2`** |
-- | M14a| `club_pack_map_roster` → SECURITY INVOKER | **APPLY ABORTS** at §E VERIFY |
-- | M14b| same, §E's definer arm removed | 1126/2 = **`0159-W2`** + `M1` |
--
-- 🔴 **THE TWO CONTROL PAIRS ARE MEASURED, NOT ASSERTED, and that is the point of M8 and M13.**
--   · M8 (always open) reddens `R2` and **leaves `R1` green**; M10 (shut for anon) reddens `R1`.
--     No single constant satisfies both, so R1/R2 is a real pair rather than one pin printed twice.
--   · M7 (admits everybody) reddens **`P2` alone**; M13 (admits nobody) reddens **`P1`** and leaves
--     `P2` green. Same argument on the write door. Both were run precisely because CLAUDE.md's
--     test is 「name the failure mode each arm is blind to」 — and a named pair that was never
--     measured is a claim about a pin, not a measurement of one.
--
-- 🔴 **FOUR MUTATIONS ABORT THE APPLY, WHICH MEASURES §E's VERIFY AND NOT THIS SUITE.** That is
--   the three-proposition discipline: 「the hole is real」, 「a pin notices」 and 「the fix closes it」
--   are different claims. Each was therefore re-run with its own VERIFY arm removed (M1b, M2c,
--   M9b, M14b) so a SUITE pin had to catch it alone — because a property checked at apply and
--   never pinned is protected exactly until someone recreates the function.
--
-- ⚠ **M9b's result is honest rather than tidy, and it is worth knowing before deploying.** With
--   `anon` revoked, the harness does not report a failing pin — it DIES at suite 143 with a
--   top-level 42501. Cause, and it is a real property of this design: `pack channel read` is the
--   first policy on `realtime.messages` whose role list contains `anon`, so an anonymous SELECT
--   now EVALUATES a policy that calls `my_channel_allowed`. Without the grant that call raises
--   instead of denying. It is the loud direction of failure, not the silent one, and three
--   independent things stand in front of it (§E VERIFY aborts the apply · `0159-W2` · the
--   two-sided arms added to `98 H9` and `99 S1`). ⚠ **OBSERVED in the control run: with the grant
--   present, anon SELECTs on `chat-`/`bk-`/`club-chat-` topics still return 0 rows cleanly —
--   143 E1/E2/E3's anon arms are green — so the new policy does not break the four old families.**
--
-- ⚠ **M2's first form is recorded rather than quietly fixed.** Renaming a policy and calling it
--   「removed」 is exactly the class this repo keeps paying for: the plant landed, the assertion
--   passed, the apply aborted for a plausible-looking reason, and the row would have read as
--   「the write door is pinned」 while nothing about the door had been tested.
--
-- ⚠ **`_fail` args are pre-computed into `v_msg`, never a subquery** (the 110 header law).
-- ⚠ `now()` is FROZEN inside this do-block: the whole file is one transaction. Nothing here
--    asserts that a timestamp moved; the window arms move `scheduled_at` instead, which is an
--    observable.

do $$
declare
  v_host uuid; v_runner uuid; v_owner uuid; v_comp uuid; v_guest uuid;
  v_rsvp uuid; v_stranger uuid;
  v_club uuid; v_ses uuid; v_ses2 uuid;
  v_dog uuid; v_cdog uuid; v_sd uuid; v_bk uuid;
  v_topic text; v_topic2 text; v_sched timestamptz;
  v_j jsonb; v_p jsonb; v_keys text[];
  v_n int; v_bad text; v_msg text; v_ok boolean;
begin
  -- ═══════════ fixtures — the shipped path wherever one exists ═══════════
  v_host    := t_user('pk_host',    'runner');
  v_runner  := t_user('pk_runner',  'runner');
  v_owner   := t_user('pk_owner',   'owner');    -- delegates a dog
  v_comp    := t_user('pk_comp',    'owner');    -- 동반: walks their own dog
  v_guest   := t_user('pk_guest',   'owner');    -- dogless guest (Sean: a guest is a member)
  v_rsvp    := t_user('pk_rsvp',    'owner');    -- joins and never shows up
  v_stranger:= t_user('pk_stranger','owner');    -- not in this session at all

  insert into clubs (name, district, status, host_profile_id)
    values ('PK클럽', '반포동', 'active', v_host) returning id into v_club;

  -- inside session_checkin's band (0030:251) so the shipped check-in RPC is usable
  v_sched := now() + interval '30 minutes';
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host, v_sched, 'PK 집결지') returning id into v_ses;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host, v_sched, 'PK 집결지2') returning id into v_ses2;

  insert into session_people (session_id, profile_id, role) values
    (v_ses, v_host,   'host_runner'),
    (v_ses, v_runner, 'handling_runner'),
    (v_ses, v_owner,  'owner_attending'),
    (v_ses, v_comp,   'owner_attending'),
    (v_ses, v_guest,  'owner_attending'),
    (v_ses, v_rsvp,   'owner_attending');
  insert into session_people (session_id, profile_id, role) values (v_ses2, v_host, 'host_runner');

  -- a delegated pairing WITH a booking, so ③ (러닝 종료) has something to stamp
  v_dog := t_dog(v_owner, 'PK-위탁견');
  insert into bookings (owner_id, dog_id, runner_id, club_session_id, status, scheduled_at,
                        km, base_fare, distance_fare, total_price)
    values (v_owner, v_dog, v_runner, v_ses, 'active', v_sched, 3, 7900, 9000, 16900)
    returning id into v_bk;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                            custody, approval, booking_id)
    values (v_ses, v_dog, v_owner, v_runner, 'runner_delegated', 'approved', v_bk)
    returning id into v_sd;
  -- a 동반 dog, so the 동반 owner is a real participant type and not a stand-in
  v_cdog := t_dog(v_comp, 'PK-동반견');
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                            custody, approval)
    values (v_ses, v_cdog, v_comp, v_comp, 'owner_handled', 'auto');

  v_topic  := 'pack-' || v_ses::text;
  v_topic2 := 'pack-' || v_ses2::text;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-S1] THE ANTI-INACTION PROPERTY: a session that EXISTS is not a session that is
  --           HAPPENING. Nobody has checked in yet, so the map must be shut — for everyone,
  --           the host included. Then the shipped check-in RPC opens it. Both halves are here
  --           because either alone is satisfiable by a constant.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  if _club_pack_window(v_ses) is not false
    then v_bad := v_bad || ' 아무도 체크인하지 않았는데 창이 열려 있다(생성 즉시 열리는 위치 피드)'; end if;
  if channel_allowed(v_topic, null,   'read') is not false
    then v_bad := v_bad || ' 시작 전인데 익명 읽기가 통과'; end if;
  if channel_allowed(v_topic, v_host, 'read') is not false
    then v_bad := v_bad || ' 시작 전인데 호스트 읽기가 통과'; end if;

  -- the shipped path, as five different participant kinds
  perform set_config('request.jwt.claim.sub', v_host::text,   true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_runner::text, true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_owner::text,  true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_comp::text,   true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_guest::text,  true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', '', true);
  -- v_rsvp deliberately never checks in

  if _club_pack_window(v_ses) is not true
    then v_bad := v_bad || ' 다섯 명이 체크인했는데 창이 안 열린다'; end if;
  -- the OTHER session had nobody check in — a per-session window, not a global switch
  if _club_pack_window(v_ses2) is not false
    then v_bad := v_bad || ' 체크인 없는 옆 세션의 창까지 열렸다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-S1 창은 체크인으로 열린다 — 세션 생성만으로는 닫혀 있고(익명·호스트 둘 다 거절), 실제 체크인 뒤에 열리며, 체크인이 없는 옆 세션은 계속 닫혀 있다');
  else v_msg := v_bad; call _fail('pkmap','0159-S1 체크인 창', v_msg); end if;

  -- ═══════════ [0159-S2] 세션 종료 / 취소가 닫는다 (호스트의 확정적 종료 신호) ═══════════
  v_bad := '';
  update club_sessions set status = 'done' where id = v_ses;
  if _club_pack_window(v_ses) is not false then v_bad := v_bad || ' 세션 종료(done) 후에도 창이 열려 있다'; end if;
  update club_sessions set status = 'cancelled' where id = v_ses;
  if _club_pack_window(v_ses) is not false then v_bad := v_bad || ' 취소된 세션의 창이 열려 있다'; end if;
  update club_sessions set status = 'full' where id = v_ses;
  if _club_pack_window(v_ses) is not true  then v_bad := v_bad || ' full 세션의 창이 닫혀 있다(정원이 찬 것은 종료가 아니다)'; end if;
  update club_sessions set status = 'open' where id = v_ses;      -- restore
  if v_bad = '' then call _pass('pkmap','0159-S2 세션 종료(done)와 취소가 창을 닫고, full 은 닫지 않는다');
  else v_msg := v_bad; call _fail('pkmap','0159-S2 세션 상태', v_msg); end if;

  -- ═══════════ [0159-S3] 호스트의 러닝 종료가 닫는다 ═══════════
  -- ⚠ `bookings.run_ended_at` on a CLUB booking has exactly one writer: club_end_pack_runs
  --   (0144:456). end_run_tx — the only other writer, 0083:441 — raises `club_out_of_scope` on
  --   any booking carrying a club_session_id (0083:383). So this stamp IS 러닝 종료 and this pin
  --   is not a proxy for it. The stamp is applied directly rather than through the RPC because
  --   0144's own suite (176) owns that function's behaviour; what 0159 owns is the CONSEQUENCE.
  v_bad := '';
  update bookings set run_ended_at = now() where id = v_bk;
  if _club_pack_window(v_ses) is not false
    then v_bad := v_bad || ' 러닝 종료 스탬프 뒤에도 창이 열려 있다'; end if;
  if channel_allowed(v_topic, null, 'read') is not false
    then v_bad := v_bad || ' 러닝 종료 뒤에도 익명 읽기가 통과(공개 위치 피드가 안 닫힌다)'; end if;
  -- ⚠ [0160] This arm still holds but no longer measures the WINDOW: socket write is false for
  --   everyone now, whatever the window says. What 러닝 종료 closes on the publish side is owned
  --   by suite 191 `0160-A4`, which drives the RPC after the stamp and reads `window_closed`.
  if channel_allowed(v_topic, v_runner, 'write') is not false
    then v_bad := v_bad || ' 러닝 종료 뒤에도 러너가 소켓으로 발행할 수 있다'; end if;
  update bookings set run_ended_at = null where id = v_bk;        -- restore
  if _club_pack_window(v_ses) is not true then v_bad := v_bad || ' 스탬프를 지웠는데 창이 안 돌아온다(핀이 다른 걸 재고 있다)'; end if;
  if v_bad = '' then call _pass('pkmap','0159-S3 러닝 종료(club 부킹의 run_ended_at)가 읽기·쓰기 양쪽을 닫는다 — 그리고 스탬프를 되돌리면 창이 돌아온다(이 핀이 재는 것이 그 스탬프임을 보이는 역방향 통제)');
  else v_msg := v_bad; call _fail('pkmap','0159-S3 러닝 종료', v_msg); end if;

  -- ═══════════ [0159-S4] 시계 상한 — 오직 무행동에 대한 방어 ═══════════
  -- Everything else in the window is a host tap that may never happen, and check-in is
  -- monotonic. Without this band one forgotten 세션 종료 leaves a PUBLIC live-location channel
  -- open forever. The band is `session_checkin`'s own (0030:251-253), copied, not invented.
  v_bad := '';
  update club_sessions set scheduled_at = now() - interval '7 hours' where id = v_ses;
  if _club_pack_window(v_ses) is not false
    then v_bad := v_bad || ' 예정 시각 +6h 를 지났는데 창이 열려 있다(아무도 종료를 안 눌러도 닫혀야 한다)'; end if;
  update club_sessions set scheduled_at = now() + interval '3 hours' where id = v_ses;
  if _club_pack_window(v_ses) is not false
    then v_bad := v_bad || ' 예정 시각 -2h 이전인데 창이 열려 있다'; end if;
  update club_sessions set scheduled_at = v_sched where id = v_ses;   -- restore
  if _club_pack_window(v_ses) is not true then v_bad := v_bad || ' 예정 시각을 되돌렸는데 창이 안 돌아온다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-S4 시계 상한 — 예정 +6h 를 넘기면 아무도 종료를 누르지 않아도 닫히고, -2h 이전에는 아직 열리지 않는다(체크인 창과 같은 밴드)');
  else v_msg := v_bad; call _fail('pkmap','0159-S4 시계 상한', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-S5] 🔴 AN ALL-동반 (Mode A) PACK IS LIVE. This is the requirement that rules out the
  --           obvious window, and it was raised as a requirement rather than discovered here.
  --
  -- The natural derived signal for 「a pack is running」 is `exists(a booking of this session with
  -- status 'active' and an unended run)`. It is **delegated-only**: `club/companion/[sid].tsx`
  -- (the owner walking their OWN dog) has no publisher and writes no server row until the walk
  -- ENDS, so a session where everybody walks their own dog evaluates to FALSE while it is
  -- physically happening. That window would render the exact pack Sean described — 「everyone
  -- should see everyone else」 — as blank, and say it was not running.
  --
  -- 0159's window is keyed on CHECK-IN, which every participant kind performs, so it does not
  -- have that hole. This pin is the proof rather than the claim: a session whose only dog is
  -- `owner_handled`, with no booking anywhere, is LIVE for read and for publish.
  -- ⚠ It also pins conjunct ③'s vacuity in the right direction: 「no delegated pairing carries
  --   run_ended_at」 is trivially TRUE when there are no delegated pairings, and it must be — the
  --   opposite reading (「the pack ended」) would close every Mode-A session permanently.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  declare
    v_a_host uuid; v_a_own uuid; v_a_ses uuid; v_a_dog uuid; v_a_topic text;
  begin
    v_a_host := t_user('pk_a_host', 'runner');
    v_a_own  := t_user('pk_a_own',  'owner');
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (v_club, v_a_host, v_sched, 'PK 동반 전용') returning id into v_a_ses;
    insert into session_people (session_id, profile_id, role) values
      (v_a_ses, v_a_host, 'host_runner'), (v_a_ses, v_a_own, 'owner_attending');
    v_a_dog := t_dog(v_a_own, 'PK-동반전용견');
    insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                              custody, approval)
      values (v_a_ses, v_a_dog, v_a_own, v_a_own, 'owner_handled', 'auto');
    v_a_topic := 'pack-' || v_a_ses::text;

    -- the derived signal that would have been wrong, measured rather than asserted
    select count(*) into v_n from bookings b where b.club_session_id = v_a_ses;
    if v_n <> 0 then v_bad := v_bad || ' 동반 전용 세션에 부킹이 있다(픽스처가 이 클래스를 대표하지 못한다)=' || v_n; end if;

    if _club_pack_window(v_a_ses) is not false then v_bad := v_bad || ' 체크인 전인데 동반 전용 세션의 창이 열려 있다'; end if;
    perform set_config('request.jwt.claim.sub', v_a_own::text, true);  perform session_checkin(v_a_ses);
    perform set_config('request.jwt.claim.sub', v_a_host::text, true); perform session_checkin(v_a_ses);
    perform set_config('request.jwt.claim.sub', '', true);

    if _club_pack_window(v_a_ses) is not true
      then v_bad := v_bad || ' 🔴 위탁견이 하나도 없는 동반 전용 팩이 살아 있지 않다 — 창이 위탁 러닝에 매여 있다'; end if;
    if channel_allowed(v_a_topic, null,    'read')  is not true then v_bad := v_bad || ' 동반 전용 팩의 공개 읽기가 거절된다'; end if;
    -- [0160] INVERTED. This arm read `is not true` — the 동반 owner could publish through the
    -- socket. 0160 removed the pack WRITE arm entirely (publishing is the `club_pack_publish`
    -- RPC), so the socket door is shut for them too. Their ability to publish AT ALL is owned by
    -- suite 191 `0160-A1`, which drives the RPC and reads the row it lands.
    if channel_allowed(v_a_topic, v_a_own, 'write') is not false then v_bad := v_bad || ' 0160 이후에도 소켓 쓰기 팔이 동반 보호자를 받아준다'; end if;
    if channel_allowed(v_a_topic, v_owner, 'write') is not false then v_bad := v_bad || ' 다른 세션의 참가자가 동반 전용 팩에 발행한다'; end if;
    -- and the roster names both of them
    v_j := club_pack_map_roster(v_a_ses);
    select count(*) into v_n from jsonb_array_elements(v_j->'people');
    if v_n <> 2 then v_bad := v_bad || ' 동반 전용 팩의 로스터가 2명이 아니다=' || v_n; end if;
  end;
  if v_bad = '' then call _pass('pkmap','0159-S5 위탁견이 하나도 없는 동반(Mode A) 전용 팩도 살아 있다 — 부킹이 0개인 세션에서 창이 열리고, 공개 읽기가 통과하며, 로스터가 두 사람을 명명한다(0160 이후 소켓 쓰기는 동반 보호자에게도 닫혀 있고, 그들이 실제로 발행할 수 있다는 것은 191 0160-A1 이 RPC 로 잰다). 「active 부킹이 있는가」를 창으로 삼았다면 이 세션은 산책 중에 빈 지도였을 것이다');
  else v_msg := v_bad; call _fail('pkmap','0159-S5 동반 전용 팩', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-R1] READ IS PUBLIC. Sean 2026-08-28: 「everyone should see everyone else on the map
  --           … total public」. This is the ruling as an executable assertion — a NULL uid (an
  --           anonymous client) and a person with no relationship to the session are BOTH
  --           admitted, and that is correct, not a leak.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  if channel_allowed(v_topic, null,       'read') is not true then v_bad := v_bad || ' 익명(null uid) 읽기가 거절된다 — 공개 판결이 안 실렸다'; end if;
  if channel_allowed(v_topic, v_stranger, 'read') is not true then v_bad := v_bad || ' 무관한 사용자 읽기가 거절된다'; end if;
  if channel_allowed(v_topic, v_rsvp,     'read') is not true then v_bad := v_bad || ' 체크인 안 한 참가자 읽기가 거절된다'; end if;
  if channel_allowed(v_topic, v_guest,    'read') is not true then v_bad := v_bad || ' 게스트 읽기가 거절된다'; end if;
  if channel_allowed(v_topic, v_host,     'read') is not true then v_bad := v_bad || ' 호스트 읽기가 거절된다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-R1 읽기는 공개다 — 익명·무관한 사용자·미체크인 참가자·게스트·호스트 전부 입장(Sean 2026-08-28 「total public」)');
  else v_msg := v_bad; call _fail('pkmap','0159-R1 공개 읽기', v_msg); end if;

  -- ═══════════ [0159-R2] 창이 닫히면 읽기도 닫힌다 — R1 의 짝 통제 ═══════════
  -- R1 alone is satisfied by a predicate hard-wired to `true`; this arm is the one that is not.
  v_bad := '';
  update club_sessions set status = 'done' where id = v_ses;
  if channel_allowed(v_topic, null,       'read') is not false then v_bad := v_bad || ' 종료된 세션의 익명 읽기가 통과'; end if;
  if channel_allowed(v_topic, v_stranger, 'read') is not false then v_bad := v_bad || ' 종료된 세션의 무관 읽기가 통과'; end if;
  if channel_allowed(v_topic, v_host,     'read') is not false then v_bad := v_bad || ' 종료된 세션의 호스트 읽기가 통과'; end if;
  update club_sessions set status = 'open' where id = v_ses;      -- restore
  if v_bad = '' then call _pass('pkmap','0159-R2 창이 닫히면 읽기도 닫힌다 — 호스트조차 못 들어간다(R1 과 짝, 상수 술어로는 둘 다 만족할 수 없다)');
  else v_msg := v_bad; call _fail('pkmap','0159-R2 닫힌 창의 읽기', v_msg); end if;

  -- ═══════════ [0159-R3] 형식·치환·존재하지 않는 세션은 닫힌다 ═══════════
  v_bad := '';
  if channel_allowed('pack-not-a-uuid', null, 'read') is not false          then v_bad := v_bad || ' 형식 오류 토픽 통과'; end if;
  if channel_allowed(v_topic || '-x',   null, 'read') is not false          then v_bad := v_bad || ' 꼬리 붙은 토픽 통과'; end if;
  if channel_allowed('pack-' || gen_random_uuid()::text, null, 'read') is not false then v_bad := v_bad || ' 존재하지 않는 세션 토픽 통과'; end if;
  if channel_allowed(v_topic2, null, 'read') is not false                   then v_bad := v_bad || ' 시작 안 한 옆 세션 토픽 통과(치환)'; end if;
  if channel_allowed('pack-' || v_bk::text, null, 'read') is not false      then v_bad := v_bad || ' 부킹 id 를 세션 id 자리에 넣어도 열린다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-R3 잘못된 형식·꼬리·없는 세션·옆 세션·부킹 id 치환 전부 거절(공개여도 아무 uuid 나 열리지는 않는다)');
  else v_msg := v_bad; call _fail('pkmap','0159-R3 읽기 페일클로즈', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-P1] 🔴 **INVERTED BY 0160, and this is the sharpest edit in the file.** It read 「five
  --           kinds of checked-in participant MAY publish through the socket」 — a true and
  --           load-bearing sentence under 0159, and the thing codex #2/#4 rejected. Realtime
  --           authorization is CACHED PER SOCKET, so that policy was evaluated once at join and
  --           never again: a participant who joined checked-in kept publishing after 세션 종료.
  --           0160 removes the socket write door outright; the publisher is the RPC
  --           `club_pack_publish`, re-gated on every call. So the sentence here is now 「the
  --           socket admits NOBODY, the checked-in host included」.
  -- ⚠ Their ability to publish at all — the positive control that stops this suite proving a dead
  --   feature — moved to suite 191 (`0160-A1`/`0160-A2`), which drives the RPC as five different
  --   participants and reads the row each call lands in `realtime.messages`. That is a different
  --   ORACLE, not a rephrasing of this one.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  if channel_allowed(v_topic, v_host,   'write') is not false then v_bad := v_bad || ' 호스트가 소켓으로 발행할 수 있다(0159 의 쓰기 팔이 살아 있다)'; end if;
  if channel_allowed(v_topic, v_runner, 'write') is not false then v_bad := v_bad || ' 담당 러너가 소켓으로 발행할 수 있다'; end if;
  if channel_allowed(v_topic, v_owner,  'write') is not false then v_bad := v_bad || ' 위탁 보호자가 소켓으로 발행할 수 있다'; end if;
  if channel_allowed(v_topic, v_comp,   'write') is not false then v_bad := v_bad || ' 동반 보호자가 소켓으로 발행할 수 있다'; end if;
  if channel_allowed(v_topic, v_guest,  'write') is not false then v_bad := v_bad || ' 개 없는 게스트가 소켓으로 발행할 수 있다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-P1 [0160 에서 뒤집힘] 소켓 쓰기 팔은 사라졌다 — 체크인한 참가자 다섯 종류(호스트·담당 러너·위탁 보호자·동반 보호자·게스트) 전부 channel_allowed(…,write)=false. 조인 시점에 한 번 평가되고 마는 정책으로는 창을 닫을 수 없기 때문이고(codex #2), 발행은 매 호출 재검사하는 club_pack_publish RPC 로 옮겼다. 그들이 실제로 발행할 수 있다는 긍정 통제는 191 0160-A1/A2 가 다른 오라클로 소유한다');
  else v_msg := v_bad; call _fail('pkmap','0159-P1 소켓 쓰기 부재', v_msg); end if;

  -- ═══════════ [0159-P2] 쓰기는 공개가 아니다 ═══════════
  -- 🔴 The RSVP arm was the load-bearing one. Session membership is SELF-SERVE: session_rsvp gates
  --    on 「session open / seats left / your own dog」 and on nothing else (0134:53-61), and
  --    club_sessions is `select using (true)` (0030:133). So 「a member of this session」 means
  --    「anyone who found an open session and tapped 참가」 — a predicate that READS like a
  --    membership check and is not one.
  -- ⚠ **[0160] KEPT, AND ITS WEAKNESS SAID OUT LOUD.** Under 0159 this was P1's control pair:
  --    weakening the write predicate from `checked_in` to mere membership reddened here and
  --    nowhere else. With the write arm removed, every arm below is false for the same reason
  --    every arm of P1 is false, so **P2 no longer discriminates anything P1 does not** — it is
  --    one claim printed twice, which is precisely what CLAUDE.md says a control must not be. It
  --    stays because the sentence is still true and a future 「restore the write arm」 must trip
  --    something, but it is NOT counted as a control. The membership-vs-checked-in distinction is
  --    owned by suite 191 `0160-A3`, whose RSVP-only and divergence-zone fixtures sit exactly
  --    where the two candidate predicates disagree.
  v_bad := '';
  if channel_allowed(v_topic, v_rsvp,     'write') is not false then v_bad := v_bad || ' 참가만 하고 체크인 안 한 사람이 발행한다(자율가입 구멍 — 가짜 점을 원격에서 밀어넣을 수 있다)'; end if;
  if channel_allowed(v_topic, v_stranger, 'write') is not false then v_bad := v_bad || ' 세션과 무관한 사용자가 발행한다'; end if;
  if channel_allowed(v_topic, null,       'write') is not false then v_bad := v_bad || ' 익명이 발행한다(읽기는 공개지만 쓰기는 아니다)'; end if;
  if v_bad = '' then call _pass('pkmap','0159-P2 참가만 한 사람·무관한 사용자·익명은 소켓으로 발행하지 못한다. ⚠ 0160 이후 이 팔들은 P1 과 같은 이유로 false 이므로 더 이상 통제 쌍이 아니다 — 「멤버 vs 체크인」 구분은 191 0160-A3 가 소유한다');
  else v_msg := v_bad; call _fail('pkmap','0159-P2 발행 부정 통제', v_msg); end if;

  -- ═══════════ [0159-P3] 토픽 치환 — 이 세션의 참가자가 옆 세션에 발행하지 못한다 ═══════════
  v_bad := '';
  -- open the neighbour's window so this arm measures the PARTY predicate, not the window
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  perform session_checkin(v_ses2);
  perform set_config('request.jwt.claim.sub', '', true);
  if _club_pack_window(v_ses2) is not true
    then v_bad := v_bad || ' 옆 세션의 창을 못 열었다(이 핀은 창이 아니라 당사자를 재야 한다)'; end if;
  -- [0160] INVERTED. This was the positive half of the substitution pin — 「the neighbour's own
  -- checked-in host MAY publish there」 — and it is false now for everyone. The positive control
  -- (a checked-in host of session B publishes to B's topic, and a member of A cannot) moved to
  -- suite 191 `0160-A7`, which drives the RPC and compares the rows it lands per topic; that is
  -- the only place the substitution can still be measured with a working positive arm.
  if channel_allowed(v_topic2, v_host,   'write') is not false then v_bad := v_bad || ' 0160 이후에도 옆 세션의 호스트가 소켓으로 발행할 수 있다'; end if;
  if channel_allowed(v_topic2, v_runner, 'write') is not false then v_bad := v_bad || ' 이 세션의 러너가 옆 세션 토픽에 발행한다'; end if;
  if channel_allowed(v_topic2, v_guest,  'write') is not false then v_bad := v_bad || ' 이 세션의 게스트가 옆 세션 토픽에 발행한다'; end if;
  -- the READ side still discriminates by session and is the surviving positive/negative pair here
  if channel_allowed(v_topic2, null, 'read') is not true  then v_bad := v_bad || ' 창이 열린 옆 세션의 공개 읽기가 거절된다(긍정 통제)'; end if;
  if v_bad = '' then call _pass('pkmap','0159-P3 [0160 에서 절반 뒤집힘] 소켓 쓰기는 어느 세션의 누구에게도 열려 있지 않고, 읽기는 창이 열린 그 세션에 대해서만 열린다(창을 실제로 열어 두고 잰다 — 이 팔이 재는 것은 창이 아니라 토픽↔세션 결합이다). 발행의 토픽 결합은 191 0160-A7 이 RPC 로 소유한다');
  else v_msg := v_bad; call _fail('pkmap','0159-P3 토픽 치환', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- THE BOUNDARY — real SELECT/INSERT on realtime.messages, which is where the POLICY lives.
  -- Everything above pins the RULE; a rule with no policy is a green predicate and a dead map.
  -- Probe rows are seeded as superuser (bypasses RLS) so the SELECT leg is measured alone —
  -- realtime's own join check is exactly this: insert a broadcast probe for the topic, read it
  -- back as the caller, a returned row admits the join.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  insert into realtime.messages (topic, extension, payload, private) values
    (v_topic, 'broadcast', '{}'::jsonb, true),
    (v_topic, 'presence',  '{}'::jsonb, true);

  -- ---------- [0159-E1] authenticated at the boundary ----------
  v_bad := '';
  perform set_config('realtime.topic', v_topic, true);
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_topic and extension = 'broadcast';
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' 체크인한 게스트의 SELECT 가 경계에서 0행=' || v_n; end if;
  -- a total stranger reads it too. That IS the ruling.
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_topic and extension = 'broadcast';
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' 무관한 로그인 사용자의 SELECT 가 0행 — 공개 판결이 경계에서 안 실렸다=' || v_n; end if;
  -- and the same stranger may NOT publish
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":37.5,"lng":127.0}'::jsonb, true);
    v_bad := v_bad || ' 무관한 사용자의 INSERT(가짜 점 주입)가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  -- 🔴 [0160] INVERTED, and this is the boundary half of the whole slice. This arm read 「the
  -- checked-in guest MAY publish」 and was the positive control for the write door. 0160 DROPPED
  -- `pack channel write`, so a pack-topic INSERT now matches NO policy at all and RLS refuses it
  -- — for a checked-in participant exactly as for a stranger. Deny-by-no-policy is the shape a
  -- cached join cannot re-open, which is what codex #2 asked for.
  -- ⚠ The positive control did not disappear, it MOVED: suite 191 `0160-B1` puts the identical
  --   checked-in caller through `club_pack_publish` in the same breath as this refusal, so
  --   「the door is shut」 and 「the feature still works」 are still both measured — just not both
  --   through this door.
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":37.5,"lng":127.0}'::jsonb, true);
    v_bad := v_bad || ' 체크인한 참가자의 소켓 INSERT 가 경계에서 통과했다(pack channel write 가 아직 있다)';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  -- ⚠ Kept as a belt after 0160: both INSERT arms above are now expected to be refused, so this
  --   normally deletes nothing. It stays so that E2's `= 1` remains an assertion about the POLICY
  --   and never about how many arms ran before it — a pin whose number depends on a neighbouring
  --   pin is testing the neighbour (found the hard way when E2 reported 2).
  delete from realtime.messages where topic = v_topic and payload ? 'lat';
  if v_bad = '' then call _pass('pkmap','0159-E1 [0160 에서 뒤집힘] 경계 실측(authenticated) — 체크인 참가자와 무관한 사용자 둘 다 SELECT 1행(공개 읽기는 그대로), 그리고 **둘 다 INSERT 거절**: pack channel write 가 사라져 팩 토픽 쓰기를 받아줄 정책이 하나도 없다. 참가자가 실제로 발행할 수 있다는 긍정 통제는 191 0160-B1 이 같은 사용자로 RPC 를 통해 소유한다');
  else v_msg := v_bad; call _fail('pkmap','0159-E1 경계 authenticated', v_msg); end if;

  -- ---------- [0159-E2] 🔴 anon at the boundary — the ONLY pin that can see `pack channel read`
  -- 0108's `party channel read` has no topic guard, so an AUTHENTICATED reader reaches a pack
  -- topic through it with the identical answer. Dropping `pack channel read` therefore reddens
  -- NOTHING on any authenticated arm and silently deletes the public half of the ruling. This
  -- pin executes as `anon`, which that policy is the only door for.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_topic and extension = 'broadcast';
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' 로그인하지 않은 클라이언트의 SELECT 가 0행 — 공개 지도가 익명에게 안 열린다=' || v_n; end if;
  -- anon publishes nothing
  set local role anon;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_topic, 'broadcast', '{"lat":0,"lng":0}'::jsonb, true);
    v_bad := v_bad || ' 익명 INSERT 가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  -- and when the window shuts, anon loses it too
  update club_sessions set status = 'done' where id = v_ses;
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_topic and extension = 'broadcast';
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 세션 종료 뒤에도 익명 SELECT 가 통과=' || v_n; end if;
  update club_sessions set status = 'open' where id = v_ses;      -- restore
  if v_bad = '' then call _pass('pkmap','0159-E2 경계 실측(anon) — 로그인하지 않은 클라이언트가 SELECT 1행으로 입장하고(pack channel read 를 볼 수 있는 유일한 핀), 발행은 거절되며, 세션이 종료되면 익명도 0행이 된다');
  else v_msg := v_bad; call _fail('pkmap','0159-E2 경계 anon', v_msg); end if;

  -- ---------- [0159-E3] presence 프로브는 닫혀 있고, 옛 네 가족은 익명에게 그대로 닫혀 있다 ----
  -- §B moved `channel_allowed`'s uid guard below the regex so the public pack arm could be
  -- answered without an identity. This is the regression arm for that move: if the guard were
  -- DELETED rather than moved, a NULL uid would fall through into the other families.
  v_bad := '';
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_topic and extension = 'presence';
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' presence 프로브가 익명에게 열려 있다(아무도 presence 를 쓰지 않는 방)=' || v_n; end if;
  if channel_allowed('run2-'      || v_bk::text,  null, 'read') is not false then v_bad := v_bad || ' 익명이 run2 방에 들어간다(uid 가드가 사라졌다)'; end if;
  if channel_allowed('bk-'        || v_bk::text,  null, 'read') is not false then v_bad := v_bad || ' 익명이 bk 방에 들어간다'; end if;
  if channel_allowed('club-chat-' || v_ses::text, null, 'read') is not false then v_bad := v_bad || ' 익명이 클럽 채팅방에 들어간다'; end if;
  if channel_allowed('chat-'      || v_bk::text,  null, 'read') is not false then v_bad := v_bad || ' 익명이 채팅방에 들어간다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-E3 presence 프로브는 닫혀 있고, uid 가드를 아래로 옮긴 뒤에도 run2·bk·club-chat·chat 네 가족은 익명에게 그대로 닫혀 있다(가드가 삭제된 게 아니라 이동했음을 재는 회귀 핀)');
  else v_msg := v_bad; call _fail('pkmap','0159-E3 가족 격리', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-M1] 로스터 — 익명이 부를 수 있고, 값이 맞다. ⚠ VALUES, not a key set: a body returning
  --           constant NULLs passes a key-set check (0065 W6's recorded near-miss).
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  begin
    v_j := club_pack_map_roster(v_ses);
  exception when others then
    v_j := null; v_bad := v_bad || ' 익명이 로스터를 부르지 못했다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_j is not null then
    if (v_j->>'windowOpen')::boolean is not true then v_bad := v_bad || ' windowOpen 이 true 가 아니다'; end if;
    if v_j->>'topic' is distinct from v_topic     then v_bad := v_bad || ' topic 문자열이 pack-<sessionId> 가 아니다=' || coalesce(v_j->>'topic','(null)'); end if;
    select count(*) into v_n from jsonb_array_elements(v_j->'people');
    if v_n <> 5 then v_bad := v_bad || ' 체크인한 5명이 아니다=' || v_n; end if;
    -- the RSVP-only member must NOT be named publicly
    select count(*) into v_n from jsonb_array_elements(v_j->'people') e where e->>'profileId' = v_rsvp::text;
    if v_n <> 0 then v_bad := v_bad || ' 체크인 안 한 참가자가 공개 로스터에 이름이 실렸다'; end if;
    -- the icon bit, both ways
    select e->>'isRunner' into v_msg from jsonb_array_elements(v_j->'people') e where e->>'profileId' = v_runner::text;
    if v_msg is distinct from 'true' then v_bad := v_bad || ' 담당 러너의 isRunner 가 true 가 아니다=' || coalesce(v_msg,'(없음)'); end if;
    select e->>'isRunner' into v_msg from jsonb_array_elements(v_j->'people') e where e->>'profileId' = v_guest::text;
    if v_msg is distinct from 'false' then v_bad := v_bad || ' 개 없는 게스트의 isRunner 가 false 가 아니다=' || coalesce(v_msg,'(없음)'); end if;
    select e->>'isHost' into v_msg from jsonb_array_elements(v_j->'people') e where e->>'profileId' = v_host::text;
    if v_msg is distinct from 'true' then v_bad := v_bad || ' 호스트의 isHost 가 true 가 아니다=' || coalesce(v_msg,'(없음)'); end if;
    select e->>'name' into v_msg from jsonb_array_elements(v_j->'people') e where e->>'profileId' = v_comp::text;
    if v_msg is distinct from 'pk_comp' then v_bad := v_bad || ' 동반 보호자의 이름이 서버 값이 아니다=' || coalesce(v_msg,'(없음)'); end if;
  end if;
  if v_bad = '' then call _pass('pkmap','0159-M1 로스터는 익명이 부를 수 있고 값이 맞다 — 체크인한 5명만(참가만 한 사람은 이름조차 없다), 담당 러너 isRunner=true·게스트 false·호스트 isHost=true, 이름은 서버의 profiles 값(브로드캐스트 페이로드가 아니라 이것이 진실이다)');
  else v_msg := v_bad; call _fail('pkmap','0159-M1 로스터 값', v_msg); end if;

  -- ═══════════ [0159-M2] 창이 닫히면 이름을 내주지 않는다 + 없는 세션은 not_found ═══════════
  v_bad := '';
  update club_sessions set status = 'done' where id = v_ses;
  v_j := club_pack_map_roster(v_ses);
  if (v_j->>'windowOpen')::boolean is not false then v_bad := v_bad || ' 종료된 세션인데 windowOpen 이 false 가 아니다'; end if;
  select count(*) into v_n from jsonb_array_elements(v_j->'people');
  if v_n <> 0 then v_bad := v_bad || ' 창이 닫혔는데 사람 이름이 공개된다=' || v_n; end if;
  update club_sessions set status = 'open' where id = v_ses;      -- restore
  v_j := club_pack_map_roster(v_ses);
  select count(*) into v_n from jsonb_array_elements(v_j->'people');
  if v_n <> 5 then v_bad := v_bad || ' 창을 되돌렸는데 사람이 안 돌아온다=' || v_n; end if;
  begin
    perform club_pack_map_roster(gen_random_uuid());
    v_bad := v_bad || ' 존재하지 않는 세션이 not_found 를 안 낸다';
  exception when others then
    if sqlerrm <> 'not_found' then v_bad := v_bad || ' 존재하지 않는 세션의 오류가 not_found 가 아니다=' || sqlerrm; end if;
  end;
  if v_bad = '' then call _pass('pkmap','0159-M2 창이 닫히면 people=[] 이고 windowOpen=false 만 답한다(이름은 산책 중에만 공개된다) · 되돌리면 돌아온다 · 없는 세션은 not_found');
  else v_msg := v_bad; call _fail('pkmap','0159-M2 닫힌 로스터', v_msg); end if;

  -- ═══════════ [0159-M3] 공개 로스터가 내주지 않는 것 — 키 집합을 고정한다 ═══════════
  -- Sean's round-two answer scoped 「public」 to the MAP and left phones on the narrower
  -- host-only rule. A later session widening this projection 「while they are in there」 is
  -- exactly what this pin is for: the person object's key set is FIXED, so an added key fails.
  v_bad := '';
  v_j := club_pack_map_roster(v_ses);
  -- [0160] 7 keys → 9, and BOTH additions are named here because a frozen set that moves without
  -- a reason is not frozen:
  --   · `clubName` (0160 §D, codex #10 — the masthead was rendering a club name taken from a URL
  --     parameter, unbound to the session, so a deep link could title someone else's walk with
  --     any string);
  --   · `serverNow` (0160 §D, /autoplan addendum item 1c — every broadcast `at` is now stamped by
  --     the SERVER, so a viewer's own clock skew is the single point of failure: a phone 15 s slow
  --     reads every marker as future-dated, the freshness rule refuses all of them, and the map is
  --     silently empty. The screen computes `offset = serverNow - Date.now()` per fetch).
  -- The pin's PROPERTY is unchanged — the key set is FIXED so a later widening has to argue with a
  -- pin — and only the frozen set moved, because a slice deliberately added two keys and said so.
  -- Their VALUES (clubName = `clubs.name` and distinct per club; serverNow = the server's now in
  -- the payload's own ISO-8601 UTC spelling; both present with the window open AND closed) are
  -- owned by suite 191 `0160-M1`; this arm owns the key set only, and neither is evidence for the
  -- other.
  select array_agg(k order by k) into v_keys from jsonb_object_keys(v_j) k;
  if v_keys is distinct from array['clubName','meetupPoint','people','scheduledAt','serverNow','sessionId','status','topic','windowOpen']
    then v_bad := v_bad || ' 최상위 키 집합이 바뀌었다=' || coalesce(array_to_string(v_keys,','),'(null)'); end if;
  select v_j->'people'->0 into v_p;
  select array_agg(k order by k) into v_keys from jsonb_object_keys(v_p) k;
  if v_keys is distinct from array['isHost','isRunner','name','profileId','role']
    then v_bad := v_bad || ' 사람 객체의 키 집합이 바뀌었다=' || coalesce(array_to_string(v_keys,','),'(null)'); end if;
  -- and the four words that must never appear anywhere in the payload
  if v_j::text ~* '"?phone' then v_bad := v_bad || ' 공개 로스터에 phone 이 들어 있다(Sean: phones stay host-only)'; end if;
  if v_j::text ~* 'avatar'  then v_bad := v_bad || ' 공개 로스터에 avatar 가 들어 있다'; end if;
  if v_j::text ~* 'booking' then v_bad := v_bad || ' 공개 로스터에 booking 이 들어 있다'; end if;
  if v_j::text ~* '"lat"|"lng"' then v_bad := v_bad || ' 공개 로스터에 좌표가 들어 있다(위치는 채널에만 있고 postgres 를 지나지 않는다)'; end if;
  if v_bad = '' then call _pass('pkmap','0159-M3 [0160] 공개 로스터의 키 집합은 고정이다 — 최상위 9키(0160 이 clubName 과 serverNow 를 더했다), 사람 5키, 그리고 phone·avatar·booking·좌표는 어디에도 없다(전화는 호스트 전용이라는 Sean 의 2차 답변이 여기서 실행 가능해진다)');
  else v_msg := v_bad; call _fail('pkmap','0159-M3 로스터 키 집합', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0159-W1] 배선 — 정책이 있고, 모양이 맞고, 0108 의 셋은 그대로다
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*) into v_n from pg_policies
   where schemaname='realtime' and tablename='messages' and policyname='pack channel read'
     and cmd='SELECT' and 'anon' = any(roles) and 'authenticated' = any(roles);
  if v_n <> 1 then v_bad := v_bad || ' pack channel read(SELECT, anon+authenticated)가 없다=' || v_n; end if;
  -- 🔴 [0160] INVERTED — `pack channel write` is DROPPED (0160 §C). It read `<> 1` here. A pack
  -- topic INSERT now matches no policy at all, which is the only shape a cached socket join
  -- cannot re-open. This arm asserting ABSENCE is what makes 「someone quietly re-adds the write
  -- door」 a red run rather than a silent regression.
  select count(*) into v_n from pg_policies
   where schemaname='realtime' and tablename='messages' and policyname='pack channel write';
  if v_n <> 0 then v_bad := v_bad || ' pack channel write 가 아직 있다(0160 이 지운 소켓 쓰기 문이 돌아왔다)=' || v_n; end if;
  -- the surviving pack policy must stay fenced to the family, or it becomes a second door for
  -- run2/chat/bk/club-chat
  select count(*) into v_n from pg_policies
   where schemaname='realtime' and tablename='messages' and policyname = 'pack channel read'
     and (coalesce(qual,'') || coalesce(with_check,'')) like '%pack-%%';
  if v_n <> 1 then v_bad := v_bad || ' pack channel read 가 pack-%% 로 울타리 쳐져 있지 않다=' || v_n; end if;
  -- 0108's three, untouched
  select count(*) into v_n from pg_policies
   where schemaname='realtime' and tablename='messages'
     and policyname in ('party channel read','run channel read','run channel write');
  if v_n <> 3 then v_bad := v_bad || ' 0108 의 정책 3개가 온전하지 않다=' || v_n; end if;
  -- [0160] 5 → 4. The property is unchanged (「nobody adds a policy nobody discussed」); only the
  -- number moved, because a slice deliberately removed one and said so. 143 W1 counts the same
  -- total and is updated in the same slice.
  select count(*) into v_n from pg_policies where schemaname='realtime' and tablename='messages';
  if v_n <> 4 then v_bad := v_bad || ' realtime.messages 정책 수가 4가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkmap','0159-W1 [0160] 배선 — pack channel read(SELECT/anon+authenticated) 하나만 남고 pack-%% 울타리 안, **pack channel write 는 부재**(소켓 발행 문이 없다), 0108 의 셋은 그대로, 총 4개');
  else v_msg := v_bad; call _fail('pkmap','0159-W1 배선', v_msg); end if;

  -- ═══════════ [0159-W2] ACL 과 함수 형상 — VERIFY 블록이 apply 때 재는 것을 상시 핀으로도 ═══════
  -- ⚠ A property checked at apply and never pinned is protected exactly until someone recreates
  --   the function (CLAUDE.md). 0159 §E / 0160 §F and this pin are the same assertions in two
  --   places on purpose, and neither is evidence for the other.
  -- 🔴 **[0160, answering codex #11] ALL TEN ARMS REWRITTEN FROM `if has_*` TO `is distinct from`.**
  --    `has_function_privilege` can return NULL, and plpgsql does not take an `IF` on a NULL
  --    predicate in EITHER direction — so a bare `if has_*` is SILENT in exactly the case an ACL
  --    pin exists for (the S10 class; measured on four of ui6's pins in one hour). This file's own
  --    header at S:13-17 claimed the discipline while ten arms here violated it. codex found it;
  --    this makes the claim true. ⚠ Note the two directions are NOT symmetric: a 「must be shut」
  --    arm is `is distinct from false` (NULL is a failure to prove closure) and a 「must be open」
  --    arm is `is distinct from true` (NULL is a failure to prove the grant).
  v_bad := '';
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public'
     and p.proname in ('_club_pack_window','club_pack_map_roster','channel_allowed','my_channel_allowed')
     and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') like '%pg_temp%';
  if v_n <> 4 then v_bad := v_bad || ' definer + 본문 search_path 4개가 아니다=' || v_n; end if;
  if has_function_privilege('anon','channel_allowed(text,uuid,text)','execute') is distinct from false
    then v_bad := v_bad || ' anon 이 임의 uid 로 channel_allowed 를 부를 수 있다(당사자 프로브)'; end if;
  if has_function_privilege('authenticated','channel_allowed(text,uuid,text)','execute') is distinct from false
    then v_bad := v_bad || ' authenticated 가 임의 uid 로 channel_allowed 를 부를 수 있다'; end if;
  if has_function_privilege('anon','_club_pack_window(uuid)','execute') is distinct from false
    then v_bad := v_bad || ' anon 이 _club_pack_window 를 직접 부를 수 있다(로스터를 거치라는 결정이 무너진다)'; end if;
  if has_function_privilege('authenticated','_club_pack_window(uuid)','execute') is distinct from false
    then v_bad := v_bad || ' authenticated 가 _club_pack_window 를 직접 부를 수 있다'; end if;
  if has_function_privilege('anon','my_channel_allowed(text,text)','execute') is distinct from true
    then v_bad := v_bad || ' anon 이 my_channel_allowed 를 못 부른다(공개 읽기가 죽는다)'; end if;
  if has_function_privilege('authenticated','my_channel_allowed(text,text)','execute') is distinct from true
    then v_bad := v_bad || ' authenticated 가 my_channel_allowed 를 못 부른다(0108 의 세 방이 죽는다)'; end if;
  if has_function_privilege('anon','club_pack_map_roster(uuid)','execute') is distinct from true
    then v_bad := v_bad || ' anon 이 club_pack_map_roster 를 못 부른다'; end if;
  if has_function_privilege('authenticated','club_pack_map_roster(uuid)','execute') is distinct from true
    then v_bad := v_bad || ' authenticated 가 club_pack_map_roster 를 못 부른다'; end if;
  -- 0108 §6's seal must survive this file's create-or-replace of its neighbours
  if has_function_privilege('authenticated','run_channel_allowed(text,uuid,text)','execute') is distinct from false
    then v_bad := v_bad || ' 0103 오라클(run_channel_allowed)이 다시 열렸다'; end if;
  if v_bad = '' then call _pass('pkmap','0159-W2 [0160: 열 팔 전부 is distinct from 로 — bare IF 는 NULL 에서 침묵한다, codex #11] ACL — 네 함수 전부 definer+본문 search_path, 임의 uid 프로브는 양 롤에 닫혀 있고 _club_pack_window 는 서버 전용, my_channel_allowed 와 club_pack_map_roster 는 anon+authenticated 에 열려 있으며 0103 오라클은 계속 닫혀 있다');
  else v_msg := v_bad; call _fail('pkmap','0159-W2 ACL', v_msg); end if;

  -- ═══════════ [0159-W3] anon 확장의 경계 — 열어준 것이 정확히 무엇인지 재는 핀 ═══════════
  -- 0159 grants `my_channel_allowed` to anon, which 0108 deliberately did not. This pin owns the
  -- sentence 「that grant opened the pack family and nothing else」: as anon, the wrapper answers
  -- TRUE for a live pack topic and FALSE for all four older families, because auth.uid() is NULL
  -- and §B's identity guard denies. Without this arm the grant's blast radius is unmeasured.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  begin
    select my_channel_allowed(v_topic, 'read')                   into v_ok;
    if v_ok is not true  then v_bad := v_bad || ' 익명 래퍼가 살아 있는 pack 토픽에 false'; end if;
    select my_channel_allowed(v_topic, 'write')                  into v_ok;
    if v_ok is not false then v_bad := v_bad || ' 익명 래퍼가 pack write 에 true'; end if;
    select my_channel_allowed('run2-' || v_bk::text, 'read')     into v_ok;
    if v_ok is not false then v_bad := v_bad || ' 익명 래퍼가 run2 에 true'; end if;
    select my_channel_allowed('bk-' || v_bk::text, 'read')       into v_ok;
    if v_ok is not false then v_bad := v_bad || ' 익명 래퍼가 bk 에 true'; end if;
    select my_channel_allowed('chat-' || v_bk::text, 'read')     into v_ok;
    if v_ok is not false then v_bad := v_bad || ' 익명 래퍼가 chat 에 true'; end if;
    select my_channel_allowed('club-chat-' || v_ses::text,'read') into v_ok;
    if v_ok is not false then v_bad := v_bad || ' 익명 래퍼가 club-chat 에 true'; end if;
  exception when others then
    v_bad := v_bad || ' 익명 래퍼 호출 실패 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('pkmap','0159-W3 익명에게 연 것은 pack 읽기 하나뿐 — 같은 래퍼로 pack write·run2·bk·chat·club-chat 은 전부 false(uid 가 NULL 이라 신원 가드가 거절한다)');
  else v_msg := v_bad; call _fail('pkmap','0159-W3 anon 확장 경계', v_msg); end if;

  -- ═══════════ [0159-N1] 입력 가드 — 분리된 두 가드가 둘 다 살아 있다 ═══════════
  -- §B split 0108's opening guard: topic/op stayed, uid moved below the regex. If someone
  -- 「simplifies」 it back into one line above the regex, the public pack read dies; if someone
  -- deletes the uid half, E3 goes red. This arm owns the rest of the guard surface.
  v_bad := '';
  if channel_allowed(null,    v_host, 'read')   is not false then v_bad := v_bad || ' null 토픽 통과'; end if;
  if channel_allowed(v_topic, v_host, null)     is not false then v_bad := v_bad || ' null op 통과'; end if;
  if channel_allowed(v_topic, null,   null)     is not false then v_bad := v_bad || ' null uid + null op 통과'; end if;
  if channel_allowed(v_topic, v_host, 'delete') is not false then v_bad := v_bad || ' 알 수 없는 op 통과'; end if;
  if channel_allowed(v_topic, null,   'delete') is not false then v_bad := v_bad || ' 익명 + 알 수 없는 op 통과(pack 팔이 op 를 안 본다)'; end if;
  if channel_allowed('pack' || v_ses::text, null, 'read') is not false then v_bad := v_bad || ' 하이픈 없는 pack 토픽 통과'; end if;
  if channel_allowed('run-' || v_bk::text,  v_host, 'read') is not false then v_bad := v_bad || ' 은퇴한 run- 네임스페이스 통과'; end if;
  if v_bad = '' then call _pass('pkmap','0159-N1 입력 가드 — null 토픽·null op·알 수 없는 op(익명 포함)·하이픈 없는 pack·은퇴한 run- 전부 거절. pack 읽기 팔이 op 검사 위로 올라가지 않았음을 재는 핀');
  else v_msg := v_bad; call _fail('pkmap','0159-N1 입력 가드', v_msg); end if;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
