-- ═══ 164 scoped read policies — 0131 pins (S1-S5·S5b·S6-S9 · R1 · G1-G3) ═══
-- What this suite pins: that the four club session tables whose only read policy was
-- `(auth.uid() IS NOT NULL)` now admit exactly the people who belong to that session, that they
-- still admit those people (a policy admitting nobody is green on every denial arm while four
-- features are dead), that the one real client caller keeps working, and — the durable one —
-- that NO public table anywhere carries that predicate again.
--
-- ⚠ POSITIVE CONTROLS ARE NOT OPTIONAL HERE (140's law, and 0131's own risk). The failure mode
--   of a scoping migration is not "too wide", it is "too narrow and nobody noticed until a screen
--   was empty in production". S2 is the arm that would catch that; S1 alone cannot.
-- ⚠ G1 is SCHEMA-WIDE ON PURPOSE. A per-table pin only catches the table you already suspected,
--   which is by definition not the one that bites you — and this defect was already copied FOUR
--   times before anyone looked. G1 is what makes the fifth occurrence fail instead of ship.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  v_host uuid; v_member uuid; v_owner uuid; v_runner uuid; v_runner2 uuid; v_stranger uuid;
  v_noshow uuid; v_exowner uuid; v_exdog uuid; v_pendowner uuid; v_penddog uuid;
  v_club uuid; v_ses uuid; v_ses2 uuid; v_rt uuid; v_rt2 uuid; v_dog uuid; v_sp_id uuid;
  v_n int; v_pre int; v_bad text; v_msg text;
begin
  -- ---------- fixtures: one session, four people who belong, one who does not ----------
  v_host     := t_user('sr_host', 'runner');
  v_member   := t_user('sr_member', 'owner');
  v_owner    := t_user('sr_owner', 'owner');
  v_runner   := t_user('sr_runner', 'runner');
  v_stranger := t_user('sr_stranger', 'owner');

  insert into clubs (name, district, status, host_profile_id)
    values ('SR클럽', '반포동', 'active', v_host) returning id into v_club;
  -- format='mixed' + a real delegation capacity: the fixture session must be one the delegate
  -- RPC would accept, or S5b's real-lifecycle pending row is unreachable (measured: the default
  -- format made session_delegate_dog raise format_closed — the lifecycle refusing a fixture, again)
  v_rt := t_route('SR 코스');
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, route_id, format, delegated_dog_capacity)
    values (v_club, v_host, now() + interval '2 hours', 'SR 집결지', v_rt, 'mixed', 8) returning id into v_ses;

  insert into session_people (session_id, profile_id, role, attendance)
    values (v_ses, v_member, 'owner_attending', 'rsvp') returning id into v_sp_id;
  insert into session_runner_assignments (session_id, runner_profile_id, delegated_capacity, status)
    values (v_ses, v_runner, 2, 'committed');
  -- 🔴 [battery M-a, 2026-08-26] S3's ⓒ arm was STILL masked after the codex repair, one level
  -- deeper: v_runner is also `responsible_profile_id` on the dog, so helper arm ⓓ admitted him and
  -- deleting ⓒ reddened NOTHING (977/0). Fixing masking-by-direct-policy-arm and leaving
  -- masking-by-another-HELPER-arm is the same error twice. v_runner2 exists to hold exactly ONE
  -- path: an assignment row and nothing else — no dog role, no session_people row.
  v_runner2 := t_user('sr_runner2', 'runner');
  insert into session_runner_assignments (session_id, runner_profile_id, delegated_capacity, status)
    values (v_ses, v_runner2, 1, 'committed');
  v_dog := t_dog(v_owner, 'SR-dog');
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody, approval)
    values (v_ses, v_dog, v_owner, v_runner, 'runner_delegated', 'approved');
  -- 🔴 [battery M-b] NEAR-RELATION fixtures. Restoring the WIDE predicate reddened NOTHING
  -- (977/0) — the narrowing codex demanded was entirely UNPINNED. S1 only ever tested a clean
  -- stranger, which says nothing about the people who are almost members. These two are exactly
  -- the classes codex named: a host-marked no-show, and an owner whose delegation is over.
  v_noshow := t_user('sr_noshow', 'owner');
  insert into session_people (session_id, profile_id, role, attendance)
    values (v_ses, v_noshow, 'owner_attending', 'no_show');
  v_exowner := t_user('sr_exowner', 'owner'); v_exdog := t_dog(v_exowner, 'SR-전견');
  -- responsible_profile_id is NOT NULL; the host holds it on a rejected row. ⚠ Note what the
  -- axes trigger does here unprompted: it stamps service_state='ended' on the rejected row, which
  -- is precisely the conjunct arm ⓓ tests. The fixture is therefore not asserting a hand-set flag
  -- — it is asserting the state the product itself produces on rejection.
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody, approval)
    values (v_ses, v_exdog, v_exowner, v_host, 'runner_delegated', 'rejected');
  insert into participant_activities (session_id, person_id, source, km)
    values (v_ses, v_sp_id, 'self_reported', 3.2);

  -- ---------- R1's population, built through the REAL lifecycle — NO FALLBACK ----------
  -- Codex round 2: the round-1 fixture inserted attendance='checked_in' directly and fell back to
  -- a raw status update when finish refused — 「lifecycle-real」 by assertion, not by construction.
  -- Now every step is the real RPC and ANY refusal fails the pin loudly: a fixture the product
  -- refuses to produce is information, not an inconvenience.
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_rt2 := t_route('SR 종료 코스');
  v_ses2 := club_create_session(v_club, now() + interval '90 minutes', 'SR 종료 집결지', v_rt2, 8, 'mixed');
  perform session_runner_commit(v_ses2); perform session_checkin(v_ses2);
  perform set_config('request.jwt.claim.sub', v_member::text, false);
  perform session_rsvp(v_ses2, null);          -- dogless RSVP, the 0134 path
  perform session_checkin(v_ses2);             -- self-service check-in (0030:245)
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform club_finish_session(v_ses2);         -- refusal here = _fail, never a direct update
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [S1] the stranger: a logged-in account with no relationship reads NOTHING ----------
  -- This is the whole point of 0131. Before it, every count below was > 0.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  select count(*) into v_n from session_dogs               where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_dogs=' || v_n; end if;
  select count(*) into v_n from session_people             where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_people=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_runner_assignments=' || v_n; end if;
  select count(*) into v_n from participant_activities     where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' participant_activities=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S1 무관한 로그인 사용자는 네 테이블 모두 0행');
  else v_msg := '무관한 사용자가 읽는다:' || v_bad; call _fail('srp','S1 무관한 사용자 차단', v_msg); end if;

  -- ---------- [S2] POSITIVE CONTROL: the member still reads all four ----------
  -- Without this arm, a policy that admits nobody passes S1 perfectly.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  set local role authenticated;
  select count(*) into v_n from session_dogs               where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' session_dogs=' || v_n; end if;
  select count(*) into v_n from session_people             where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' session_people=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' session_runner_assignments=' || v_n; end if;
  select count(*) into v_n from participant_activities     where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' participant_activities=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S2 세션 참가자는 네 테이블을 그대로 읽는다 (양성 대조)');
  else v_msg := '참가자가 못 읽는다 (화면이 빈다):' || v_bad; call _fail('srp','S2 참가자 양성 대조', v_msg); end if;

  -- ---------- [S3] each helper branch, ISOLATED ----------
  -- 🔴 [codex REJECT 2026-08-26] The first S3 claimed 「three separate membership paths」 and was
  -- FALSE. It read `session_dogs` as the owner and as the runner — but that policy has DIRECT arms
  -- (`owner_profile_id = auth.uid()`, `current_runner_profile_id = auth.uid()`), so both were
  -- admitted without the helper ever being consulted. Deleting a helper branch left it green.
  -- Only the host genuinely isolated anything. I asserted the opposite in the suite header and in
  -- the harness registration.
  -- ⚠ THE FIX IS THE TABLE, NOT THE PERSON: read a table where that person has NO direct arm, so
  -- the helper is the only thing that can admit them. `session_people` has exactly one direct arm
  -- (`profile_id = auth.uid()`), so for a dog-owner and for a committed runner it is pure helper.
  v_bad := '';
  -- ⓐ host — no direct arm on session_people at all
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' ⓐ호스트(session_people)=' || v_n; end if;
  reset role;
  -- ⓒ assignment-ONLY runner reading session_people. ⚠ v_runner is deliberately NOT used here:
  --   he is also the dog's responsible_profile_id, so arm ⓓ admits him and deleting ⓒ reddens
  --   nothing — measured, M-a. v_runner2 holds an assignment and nothing else.
  perform set_config('request.jwt.claim.sub', v_runner2::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' ⓒ배정전용러너(session_people)=' || v_n; end if;
  reset role;
  -- ⓓ delegating owner reading session_people: likewise no row of his own there, so only the
  --   helper's live-dog branch can admit him
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' ⓓ위탁보호자(session_people)=' || v_n; end if;
  reset role;
  -- ⓑ the attending member reading session_runner_assignments: no direct arm there either
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  set local role authenticated;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' ⓑ참가자(assignments)=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S3 헬퍼 네 갈래를 각각 고립 검증 — 직접 arm이 없는 테이블에서 읽어 헬퍼만이 통과시킬 수 있게 했다 (ⓐ호스트 ⓑ참가자 ⓒ배정러너 ⓓ위탁보호자)');
  else v_msg := '헬퍼 갈래가 막혔다:' || v_bad; call _fail('srp','S3 헬퍼 갈래 고립', v_msg); end if;

  -- ---------- [S5] the NEAR relations — the class S1 never tested ----------
  -- ⚠ This is the pin the codex REJECT was actually about. S1 proves a person with NO relationship
  -- is denied; it says nothing about someone the session almost admits. Without S5 the entire
  -- narrowing (no_show excluded, dead delegations excluded) is unpinned — measured: restoring the
  -- wide predicate left the suite at 977/0.
  v_bad := '';
  -- ⚠ THIS ARM'S PROPOSITION FLIPPED with the codex round-2 fix, and the flip is documented per
  -- the suite-update law. Round 1 excluded `no_show` from membership and this arm pinned the
  -- DENIAL. Codex rejected the exclusion — attendance is a claim, not a revocation, nothing can
  -- even write `no_show` (host-removal ⛔ PARKED), and a host punishment lever is the wrong shape.
  -- So: a no_show person IS still a member and READS. Sean's 「let the host mark no-shows」 answer
  -- belongs to the parked feature and re-opens membership semantics only if that un-parks.
  perform set_config('request.jwt.claim.sub', v_noshow::text, true);
  set local role authenticated;
  select count(*) into v_n from session_dogs where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' no_show 멤버가 session_dogs를 못 읽는다=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 2 then v_bad := v_bad || ' no_show 멤버가 assignments를 못 읽는다=' || v_n; end if;
  reset role;
  perform set_config('request.jwt.claim.sub', v_exowner::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 거절된 위탁 보호자가 session_people을 읽는다=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 거절된 위탁 보호자가 assignments를 읽는다=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S5 경계 — no_show는 여전히 멤버로 읽고(출석은 주장이지 박탈이 아니다), 위탁이 거절된 보호자는 0행');
  else v_msg := v_bad; call _fail('srp','S5 근접 관계 차단', v_msg); end if;

  -- ---------- [S5b] THE ROUND-3 CRITICAL, pinned via the real RPC ----------
  -- `session_delegate_dog` makes the OWNER the pending row's responsible_profile_id, so before
  -- the round-4 factoring, this exact person read all four tables through the pointer arms while
  -- their delegation sat unapproved. Real lifecycle, no INSERT.
  v_pendowner := t_user('sr_pend', 'owner'); v_penddog := t_dog(v_pendowner, 'SR-대기견');
  perform set_config('request.jwt.claim.sub', v_pendowner::text, true);
  perform session_delegate_dog(v_ses, v_penddog, t_consent());
  set local role authenticated;
  v_bad := '';
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 대기 위탁 보호자가 session_people을 읽는다=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 대기 위탁 보호자가 assignments를 읽는다=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S5b 대기(pending) 위탁 보호자는 아직 멤버가 아니다 — 실제 delegate RPC로 만든 행, responsible 포인터가 자기 자신인데도');
  else v_msg := v_bad; call _fail('srp','S5b 대기 위탁 보호자', v_msg); end if;

  -- ---------- [S4] anon reads nothing ----------
  -- anon holds table-level SELECT grants on all four (Supabase default); RLS is the only thing
  -- standing between it and these rows, which is exactly why this arm is written down.
  -- ⚠ THIS ARM CHANGED 0131. At PUBLIC scope it did not return 0 — it RAISED
  -- `permission denied for function _club_session_member` (42501), because the planner calls the
  -- helper before the `auth.uid() is not null` conjunct and an OR chain gives no short-circuit
  -- promise. The migration now scopes all four policies `to authenticated`, so anon matches no
  -- permissive policy and RLS returns empty without calling anything. A `count(*)` assertion is
  -- the right shape precisely because it distinguishes 0-rows from raises: the raise aborts the
  -- suite loudly under ON_ERROR_STOP rather than reading as a pass.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  select count(*) into v_n from session_dogs           where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_dogs=' || v_n; end if;
  select count(*) into v_n from session_people         where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_people=' || v_n; end if;
  select count(*) into v_n from participant_activities where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' participant_activities=' || v_n; end if;
  -- 🔴 [codex REJECT 2026-08-26] 이 줄이 없었다. S4는 네 테이블을 검사한다고 말하면서
  -- session_runner_assignments를 빼먹었고, 하네스 등록문에도 「네 테이블 모두」라고 적혀 있었다.
  -- 내가 내 자신의 핀에 대해 한 거짓 주장이다.
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' session_runner_assignments=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S4 비로그인(anon)은 0행 — 테이블 GRANT가 열려 있어도 RLS가 막는다');
  else v_msg := 'anon이 읽는다:' || v_bad; call _fail('srp','S4 anon 차단', v_msg); end if;

  -- ---------- [R1] the one REAL client caller still works ----------
  -- app/src/lib/api.ts fetchStampStats (fetchStampStats) counts session_people filtered by profile_id.
  -- Its own comment says the filter is a correctness requirement BECAUSE the RLS was open.
  -- 0131 must not turn that count into 0 — that would silently zero the 도장 벽.
  -- 🔴 [codex REJECT] 이 핀은 `where profile_id = v_member`만 셌다. 진짜 호출자
  -- (api.ts fetchStampStats fetchStampStats)는 `attendance='checked_in'` 이고 club_sessions에 조인해
  -- `status='done'`까지 요구한다. 그래서 rsvp 행만 통과시키는 정책 변형이 R1을 초록으로 둔 채
  -- 모든 도장 카운트를 0으로 만들 수 있었다 — 「초록불은 딱 한 문장의 증거」의 교과서 사례.
  -- 이제 호출자의 술어를 그대로 실행하고, 정책 앞뒤를 **비교**한다 (계약이 요구한 pre/post).
  perform set_config('request.jwt.claim.sub', '', true);
  select count(*) into v_pre from session_people sp join club_sessions cs on cs.id = sp.session_id
   where sp.profile_id = v_member and sp.attendance = 'checked_in' and cs.status = 'done';
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people sp join club_sessions cs on cs.id = sp.session_id
   where sp.profile_id = v_member and sp.attendance = 'checked_in' and cs.status = 'done';
  reset role;
  if v_pre = 0 then
    v_msg := '모집단이 비었다 (pre=0) — 공허한 초록. 정책이 아니라 픽스처가 깨진 것이다';
    call _fail('srp','R1 실제 호출자 보존', v_msg);
  elsif v_n = v_pre then
    v_msg := 'pre=' || v_pre || ' post=' || v_n
             || ' · 종료 경로: club_finish_session (폴백 없음)';
       call _pass('srp','R1 fetchStampStats의 실제 술어가 정책 전후로 같은 수를 센다 — ' || v_msg);
  else v_msg := 'pre=' || v_pre || ' post=' || v_n || ' — 정책이 도장 벽을 깎았다';
       call _fail('srp','R1 실제 호출자 보존', v_msg); end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ROUND-4 BLOCKING FINDING 2 — the LIVE non-owner dog-pointer path, and the liveness conjunct
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Codex round 4, in substance: 「The live non-owner dog-pointer path and its liveness gate are
-- unpinned. S3's ⓓ fixture tests only an approved OWNER. It never proves that a dog-only
-- non-owner custodian_profile_id, responsible_profile_id or current_runner_profile_id is
-- admitted. Conversely, deleting only `service_state is distinct from 'ended'` also leaves the
-- suite green: the rejected fixture's owner is denied by the approval test, while its non-owner
-- pointers are unexercised.」 Both halves were true; both are measured by S6-S9 below.
--
-- 0131 arm ⓓ is TWO propositions welded into one exists():
--     service_state is distinct from 'ended'
--       AND ( owner AND approval in (approved, auto)   OR   NOT owner AND uid in (three pointers) )
-- S3 ⓓ and S5b between them cover the OWNER disjunct in both directions. Nothing covered the
-- NON-OWNER disjunct at all — and nothing could cover the LIVENESS conjunct through an owner,
-- because on an owner row the approval test decides the same question first and hides it.
-- S8 is that conjunct's own pin: its subject is admitted by the pointer arm one statement
-- earlier and refused afterwards with every pointer unchanged, so liveness is the only thing
-- that can account for the difference.
--
-- ── WHY THESE FIXTURES AND NOT SIMPLER ONES — three reachability facts, MEASURED ────────────
--  1. **A club runner who is assigned a dog ALWAYS holds a `session_runner_assignments` row**, so
--     the assigned runner can never be a pointer-only subject. `session_proposal_respond`
--     (0047:169-176) compares the load against `(select delegated_capacity … status='committed')`
--     wrapped in `coalesce(…, 0)`, so an uncommitted runner has capacity 0 and the accept raises
--     `runner_cap_full`. The one person the lifecycle hands a dog WITHOUT any session membership
--     is the **emergency transferee**: `session_transfer_accept` (0058:118-127) checks the tier
--     cap and the physical load and never asks whether the receiver belongs to the session.
--     That is why every subject below arrives through `session_transfer_initiate/accept`.
--  2. **The three pointers cannot be separated for a non-owner.** `session_transfer_accept`
--     (0058:143-149) assigns `custodian_profile_id`, `responsible_profile_id` and
--     `current_runner_profile_id` in one UPDATE, and no shipped RPC gives a non-owner one of the
--     three alone. A pin isolating a single pointer would need a row the product cannot make, so
--     the reachable shape is pinned instead and the limitation is written here rather than faked
--     (⚠ consequence, stated so no later reader over-reads a green: S6/S7 prove the DISJUNCTION
--     admits, not that each of the three arms is separately load-bearing).
--  3. **There is no reachable state with a non-null `custodian_external` and a LIVE dog.** The
--     only statement in the schema that writes it non-null is `session_transfer_accept`'s
--     external branch (0058:193), and both routes into that branch leave the booking
--     `incident_review` (from picked_up/active, 0058:163-166) or `completed` — which
--     `_club_compute_axes` (0048:723-735, 0048:740-747) maps to `service_state = 'ended'`.
--     Measured on the fixture, not read off the source: S9 ⓐ asserts the ended-ness it found.
--     S9 therefore carries a source arm as well as a behavioural one, and says why.

-- ── MUTATION BATTERY — PREDICTED, THEN MEASURED. Eight runs, 2026-08-27. ───────────────────
-- Each plant is applied ALONE as a trailing migration (`0900_mut_*.sql`) inside a COPY of
-- `supabase/` OUTSIDE the worktree — never by editing 0131, which another session owns and which
-- a copy-modify-restore would silently overwrite. Appending AFTER 0131 also keeps 0131's own
-- VERIFY block from aborting the apply before any pin can run. Every plant is a python edit that
-- asserts `count(anchor) == 1` and then reads the ARTIFACT back, because `sed` exits 0 on no-match
-- and a plant you believe you made may never have been made.
-- ⚠ THE CONTROL WAS OBSERVED CLEAN FIRST: the untouched lab is 1053/0, identical to the worktree.
-- A delta measured against an unobserved control measures the lab, not the code.
--
--   R0  control, no plant                              1053/0   RED = []
--   R1  M1 (liveness conjunct deleted) against the      1049/0   RED = []  🔴 CODEX'S CLAIM,
--       PRE-CHANGE suite                                          REPRODUCED — the hole is real
--                                                                 and it was invisible
--   R2  M1 against THIS suite                          1051/2   RED = [S8, S9]. S8 names the
--       damage rather than swapping a token: 「an ended dog's pointer reads session_people=2,
--       assignments=2, participant_activities=3」. S9 reddens too, on its profile-backed external
--       custodian — a second, independent subject for the same conjunct.
--   R3  M2 (whole NOT-owner pointer disjunct deleted)  1050/3   RED = [S6, S7, S8 ⓐ] — all three
--       report 「cannot read = 0」, i.e. the arm is gone, not that a denial changed shape.
--   R4  M3 (only `custodian_profile_id` deleted)       1053/0   RED = []  ⚠ THE DOCUMENTED
--       LIMITATION, MEASURED RATHER THAN ASSERTED. Reachability fact 2 above: the three pointers
--       move in one UPDATE, so a live non-owner holds all three and dropping one changes nothing
--       any fixture can see. Written down as a gap instead of papered over with an INSERT the
--       product cannot make.
--   R5  M4 (`p_uid is distinct from owner` deleted)    1052/1   RED = [S5b] — the round-3 critical
--       still has exactly one owner, and it is not one of the new pins.
--   R6  M5 (a `custodian_external` name-matching        1052/1   RED = [S9], via ⓒ ONLY. ⓑ stays
--       disjunct ADDED — the property S9 holds is an              green, exactly as S9's own
--       ABSENCE, so its mutation is an addition)                  comment predicts.
--   R7  M6 = M5 + M1 together                          1051/2   RED = [S8, S9 via ⓑ AND ⓒ] — with
--       liveness no longer masking, the name twin really does read all four (session_dogs=1,
--       session_people=2, assignments=2, participant_activities=3). So S9 ⓑ is a LIVE control
--       that this fixture cannot exercise today, not a dead arm.

-- ── the fixture factory: one pairing, driven through the real RPC chain to a LIVE custody ────
-- Each call builds its own club, session, host, runner, owner, dog and route, because
-- `_club_runner_load` counts a certified runner's completed pairings forever against a cap of 1
-- (0037:39, 0047:57) and two fixtures sharing a runner would refuse each other.
-- Stops at `picked_up` with the run started: `service_state = 'in_service'`, custody with the
-- runner. Everything the pins need beyond that point they do with the real RPC themselves.
create or replace function t164_pair(p_tag text) returns jsonb
language plpgsql as $$
declare
  v_host uuid; v_runner uuid; v_owner uuid; v_dog uuid; v_route uuid;
  v_club uuid; v_sess uuid; v_sd uuid; v_bk uuid; v_km numeric;
begin
  v_host   := t_user('t164h_' || p_tag, 'runner');
  v_runner := t_user('t164r_' || p_tag, 'runner');
  v_owner  := t_user('t164o_' || p_tag, 'owner');
  v_dog    := t_dog(v_owner, '위탁견' || p_tag);
  v_route  := t_route('t164 코스 ' || p_tag);
  select km into v_km from routes where id = v_route;

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_club := club_request_district('t164' || p_tag);
  perform club_claim_host(v_club);
  v_sess := club_create_session(v_club, now() + interval '90 minutes', 't164 집결지', v_route, 8, 'mixed');
  perform session_runner_commit(v_sess);
  perform session_checkin(v_sess);
  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform session_runner_commit(v_sess);
  perform session_checkin(v_sess);

  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_sd := session_delegate_dog(v_sess, v_dog, t_consent());
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_bk := session_pay_delegation(v_sd, 't164-idem-' || p_tag, true);
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform session_assign_dog(v_sd, v_runner);
  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform session_proposal_respond(v_sd, true);

  -- The door handoff. There is no SQL RPC for it: the client calls the `transition-booking` edge
  -- function, which runs as service_role. `_guard_booking_cols` (0058:143) blocks
  -- authenticated/anon and lets every server role through, and `enforce_booking_transition`
  -- (0066:40) still validates confirmed → picked_up — so this UPDATE from the harness's postgres
  -- session IS that path rather than a way around it. Same write 163 and 107 use.
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
   where id = v_bk;
  update bookings set status = 'picked_up' where id = v_bk;
  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform club_start_delegated_runs(v_sess);
  perform set_config('request.jwt.claim.sub', '', false);

  return jsonb_build_object('host', v_host, 'runner', v_runner, 'owner', v_owner, 'dog', v_dog,
    'session', v_sess, 'session_dog', v_sd, 'booking', v_bk, 'km', v_km);
end $$;
revoke execute on function t164_pair(text) from public, anon, authenticated;

do $$
declare
  f_live jsonb; f_end jsonb; f_ext jsonb;
  v_t1 uuid; v_t2 uuid; v_e uuid; v_auth uuid; v_twin uuid;
  v_state text; v_state2 text; v_phase text; v_ext text; v_ctype text;
  v_cust uuid; v_resp uuid; v_curr uuid; v_cust2 uuid; v_resp2 uuid; v_curr2 uuid;
  v_n int; v_bad text; v_msg text; v_src boolean;
begin
  -- enabled HERE and not inherited from suite 50's side effect (117's precedent, 163's practice)
  update club_flags set enabled = true where name = 'club_delegation_v2';

  -- ── the LIVE pairing, then the emergency transferee who owns NOTHING but the pointers ──────
  -- A refusal anywhere in here aborts the suite loudly under ON_ERROR_STOP, and that is the
  -- correct outcome: a fixture the product refuses to produce is information, not an obstacle.
  f_live := t164_pair('lv');
  v_t1 := t_user('sr_xferee', 'runner');   -- certified ⇒ cap 1; never committed, never checked in
  perform set_config('request.jwt.claim.sub', f_live->>'runner', false);
  perform session_transfer_initiate((f_live->>'session_dog')::uuid, 'runner', v_t1, null, '주행 중 러너 교대');
  perform set_config('request.jwt.claim.sub', v_t1::text, false);
  perform session_transfer_accept((f_live->>'session_dog')::uuid, null);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [S6] an accepted runner-only TRANSFEREE is admitted ----------
  -- PROPOSITION (stated before the assertions and without reference to any mutation): a person
  -- who holds one of `session_dogs`'s non-owner pointers on a LIVE dog, and who has no session
  -- membership of any other kind — no session_people row, no runner assignment, not the host and
  -- not the backup host — is admitted to that session's tables by `_club_session_member`.
  -- The reader is measured on `session_people` and `session_runner_assignments`, where they hold
  -- no row and therefore no DIRECT policy arm can admit them: the helper is the only thing that
  -- can. `session_dogs` is deliberately NOT the evidence table — its policy has its own
  -- `current_runner_profile_id = auth.uid()` arm (0131:207) and would be admitted without the
  -- helper ever being consulted, which is the exact mistake codex rejected S3's first draft for.
  begin
    v_bad := '';
    select service_state, custodian_profile_id, responsible_profile_id, current_runner_profile_id
      into v_state, v_cust, v_resp, v_curr
      from session_dogs where id = (f_live->>'session_dog')::uuid;
    if v_state = 'ended' then v_bad := v_bad || ' 전제: 개가 이미 ended(' || v_state || ')'; end if;
    if v_t1 = (f_live->>'owner')::uuid then v_bad := v_bad || ' 전제: 인수 러너가 보호자와 동일인'; end if;
    if v_cust is distinct from v_t1 or v_resp is distinct from v_t1 or v_curr is distinct from v_t1 then
      v_bad := v_bad || ' 전제: 세 포인터가 인수 러너를 가리키지 않는다'; end if;
    select count(*) into v_n from session_people
      where session_id = (f_live->>'session')::uuid and profile_id = v_t1;
    if v_n <> 0 then v_bad := v_bad || ' 전제: 인수 러너에게 session_people 행이 있다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments
      where session_id = (f_live->>'session')::uuid and runner_profile_id = v_t1;
    if v_n <> 0 then v_bad := v_bad || ' 전제: 인수 러너에게 배정 행이 있다=' || v_n; end if;
    if exists (select 1 from club_sessions s where s.id = (f_live->>'session')::uuid
                 and (s.host_profile_id = v_t1 or s.backup_host_profile_id = v_t1)) then
      v_bad := v_bad || ' 전제: 인수 러너가 호스트/백업 호스트다'; end if;
    perform set_config('request.jwt.claim.sub', v_t1::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_live->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' 인수 러너가 session_people을 못 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_live->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' 인수 러너가 assignments를 못 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_live->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' 인수 러너가 participant_activities를 못 읽는다=' || v_n; end if;
    reset role;
    if v_bad = '' then call _pass('srp','S6 the live non-owner POINTER arm admits: a real session_transfer_accept (0058:104) hands an emergency transferee the dog and all three pointers while giving them no session_people row, no runner assignment and no host role — and that person reads session_people, session_runner_assignments and participant_activities, none of which has a direct policy arm they could satisfy, so the helper is the only thing that can have admitted them. This is the disjunct S3 ⓓ never tested: its subject was the approved OWNER, who is judged by the owner arm alone');
    else v_msg := v_bad; call _fail('srp','S6 비소유 포인터 arm 양성', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('srp','S6 비소유 포인터 arm 양성', sqlerrm);
  end;

  -- ── the same dog, one more real step: a second transfer nobody has accepted yet ────────────
  v_t2 := t_user('sr_xfer_target', 'runner');
  perform set_config('request.jwt.claim.sub', v_t1::text, false);
  perform session_transfer_initiate((f_live->>'session_dog')::uuid, 'runner', v_t2, null, '2차 교대 요청');
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [S7] the current custodian MID-TRANSFER is still admitted ----------
  -- PROPOSITION: while a custody transfer is pending, the person the row still names as
  -- `custodian_profile_id` — who is not the dog's owner — keeps reading the session; and the
  -- person the transfer is OFFERED to does not, because an offer is not a pointer.
  -- Why it is worth its own pin next to S6: `transfer_pending` is the phase this repo has already
  -- been bitten by once (0129's 「a phase list strands a dog」), it is the phase in which somebody
  -- is physically holding an animal, and a future narrowing of arm ⓓ to a custody-phase list
  -- would close it while every other pin here stayed green.
  begin
    v_bad := '';
    select service_state, custody_phase, custodian_profile_id
      into v_state, v_phase, v_cust
      from session_dogs where id = (f_live->>'session_dog')::uuid;
    if v_phase <> 'transfer_pending' then v_bad := v_bad || ' 전제: custody_phase=' || v_phase; end if;
    if v_state = 'ended' then v_bad := v_bad || ' 전제: 개가 ended'; end if;
    if v_cust is distinct from v_t1 then v_bad := v_bad || ' 전제: custodian_profile_id가 인계 중 러너가 아니다'; end if;
    if v_cust = (f_live->>'owner')::uuid then v_bad := v_bad || ' 전제: custodian이 보호자다'; end if;
    perform set_config('request.jwt.claim.sub', v_t1::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_live->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' 인계 중 custodian이 session_people을 못 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_live->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' 인계 중 custodian이 assignments를 못 읽는다=' || v_n; end if;
    reset role;
    -- ⓑ the OFFER is not membership: the pending target holds no pointer and must read nothing
    perform set_config('request.jwt.claim.sub', v_t2::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 이양 대상(수락 전)이 session_people을 읽는다=' || v_n; end if;
    select count(*) into v_n from session_dogs where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 이양 대상(수락 전)이 session_dogs를 읽는다=' || v_n; end if;
    reset role;
    if v_bad = '' then call _pass('srp','S7 transfer_pending ADMITS its custodian — a real session_transfer_initiate (0057:304) leaves the phase at transfer_pending with a NON-OWNER still named as custodian_profile_id, and that person keeps reading the session while they are holding the animal. ⓑ and the person the dog is being OFFERED to reads nothing until they accept: pending_transfer is a proposal, not a pointer. A future rewrite of arm ⓓ into a custody-phase allow-list closes ⓐ and nothing else in this suite would notice');
    else v_msg := v_bad; call _fail('srp','S7 인계 중 custodian 양성', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('srp','S7 인계 중 custodian 양성', sqlerrm);
  end;

  -- ── a second pairing, ended for real, so the liveness conjunct has a subject of its own ────
  f_end := t164_pair('en');
  v_e := t_user('sr_endxferee', 'runner');
  perform set_config('request.jwt.claim.sub', f_end->>'runner', false);
  perform session_transfer_initiate((f_end->>'session_dog')::uuid, 'runner', v_e, null, '주행 중 러너 교대');
  perform set_config('request.jwt.claim.sub', v_e::text, false);
  perform session_transfer_accept((f_end->>'session_dog')::uuid, null);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [S8] an ENDED dog's non-owner pointer is DENIED — the liveness conjunct's pin ----------
  -- PROPOSITION: when a dog's service has ENDED, the pointers it still carries stop admitting
  -- anyone to the session. The subject is the same person in both halves, holding the same three
  -- pointers in both halves, and the pin asserts that equality — so the only conjunct that can
  -- account for the difference is `service_state is distinct from 'ended'`. Without that
  -- attribution the arm would be worthless: a subject who was never admitted proves nothing about
  -- what refused them.
  -- The dog is ended by `t_settle(…, 'completed')` — the settlement the run itself performs — not
  -- by writing an axis. `session_dogs`'s axis columns are DERIVED (club_v1_axes_sync rewrites them
  -- on every write), so a hand-set service_state would be overwritten by the same statement.
  begin
    v_bad := '';
    -- ⓐ LIVE: the subject IS admitted, by the pointer arm and nothing else
    select service_state, custodian_profile_id, responsible_profile_id, current_runner_profile_id
      into v_state, v_cust, v_resp, v_curr
      from session_dogs where id = (f_end->>'session_dog')::uuid;
    if v_state = 'ended' then v_bad := v_bad || ' 전제: 정산 전인데 이미 ended'; end if;
    if v_e = (f_end->>'owner')::uuid then v_bad := v_bad || ' 전제: 인수 러너가 보호자다'; end if;
    select count(*) into v_n from session_people
      where session_id = (f_end->>'session')::uuid and profile_id = v_e;
    if v_n <> 0 then v_bad := v_bad || ' 전제: 인수 러너에게 session_people 행이 있다'; end if;
    select count(*) into v_n from session_runner_assignments
      where session_id = (f_end->>'session')::uuid and runner_profile_id = v_e;
    if v_n <> 0 then v_bad := v_bad || ' 전제: 인수 러너에게 배정 행이 있다'; end if;
    perform set_config('request.jwt.claim.sub', v_e::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_end->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' ⓐ살아있는 동안 session_people을 못 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_end->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' ⓐ살아있는 동안 assignments를 못 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_end->>'session')::uuid;
    if v_n <> 2 then v_bad := v_bad || ' ⓐ살아있는 동안 participant_activities를 못 읽는다=' || v_n; end if;
    reset role;
    -- the service ends the way the product ends it
    perform set_config('request.jwt.claim.sub', '', true);
    perform t_settle((f_end->>'booking')::uuid, 'completed', (f_end->>'km')::numeric, 1800);
    select service_state, custodian_profile_id, responsible_profile_id, current_runner_profile_id
      into v_state2, v_cust2, v_resp2, v_curr2
      from session_dogs where id = (f_end->>'session_dog')::uuid;
    if v_state2 <> 'ended' then v_bad := v_bad || ' 전제: 정산 후 service_state=' || coalesce(v_state2,'NULL'); end if;
    -- THE ATTRIBUTION: nothing but liveness moved
    if v_cust2 is distinct from v_cust or v_resp2 is distinct from v_resp or v_curr2 is distinct from v_curr then
      v_bad := v_bad || ' 귀속 실패: 포인터도 함께 바뀌었다 (' || coalesce(v_cust::text,'∅') || '→' ||
        coalesce(v_cust2::text,'∅') || ' / ' || coalesce(v_resp::text,'∅') || '→' || coalesce(v_resp2::text,'∅') ||
        ' / ' || coalesce(v_curr::text,'∅') || '→' || coalesce(v_curr2::text,'∅') || ')'; end if;
    if v_cust2 is distinct from v_e then v_bad := v_bad || ' 귀속 실패: 종료 후 custodian이 대상자가 아니다'; end if;
    -- ⓑ ENDED: the same person, the same pointers, and now nothing
    perform set_config('request.jwt.claim.sub', v_e::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_end->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓑ종료된 개의 포인터로 session_people을 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_end->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓑ종료된 개의 포인터로 assignments를 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_end->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓑ종료된 개의 포인터로 participant_activities를 읽는다=' || v_n; end if;
    -- ⓒ and the honest half: the dog ROW itself stays visible, through the POLICY's own direct
    --   pointer arm (0131:204-207), which is not the helper and is not what S8 is about. Written
    --   down so a later reader does not take S8's green as 「the ex-custodian sees nothing」.
    select count(*) into v_n from session_dogs where id = (f_end->>'session_dog')::uuid;
    if v_n <> 1 then v_bad := v_bad || ' ⓒ자기 담당이었던 개 행마저 사라졌다=' || v_n; end if;
    reset role;
    if v_bad = '' then call _pass('srp','S8 THE LIVENESS CONJUNCT, with attribution — the same emergency transferee, holding the same three pointers, reads the session while the dog is in service and reads NOTHING once a real settlement (t_settle completed) ends it. The pin asserts the three pointer values are byte-identical across the transition and that the subject is still not the owner, so `service_state is distinct from ended` is the only conjunct that can explain the change: deleting it alone must redden this pin, which is precisely what round 4 measured as impossible before. ⓒ the dog row itself is still visible to that person through the POLICY (0131:207), not through the helper — what closes is the SESSION-WIDE read');
    else v_msg := v_bad; call _fail('srp','S8 종료된 개의 포인터 차단', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('srp','S8 종료된 개의 포인터 차단', sqlerrm);
  end;

  -- ── a third pairing, handed to an EXTERNAL custodian by the real ritual ────────────────────
  f_ext := t164_pair('ex');
  v_auth := t_user('sr_authperson', 'owner');          -- profile-backed external custodian
  v_twin := t_user('반포구청 안전과', 'owner');          -- a profile whose NAME is the external string
  perform set_config('request.jwt.claim.sub', f_ext->>'runner', false);
  perform session_transfer_initiate((f_ext->>'session_dog')::uuid, 'authorized_person', v_auth,
                                    '반포구청 안전과', '현장 인계');
  perform session_transfer_accept((f_ext->>'session_dog')::uuid,
                                  jsonb_build_object('attestation', 'ops-164'));
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- [S9] `custodian_external` is a STRING, never an identity ----------
  -- PROPOSITION: the external custodian a dog is handed to is a name, and nothing about that name
  -- can become an authenticated identity — a profile that happens to be called the same thing is
  -- not a member of that session, and the membership predicate never consults the column at all.
  -- ⚠ HONEST ABOUT WHAT EACH ARM PROVES. ⓐ measures the state the product can actually reach and
  -- finds it ENDED — every route into the external branch leaves the booking `incident_review` or
  -- `completed`. So ⓑ's denial is OVER-DETERMINED: liveness alone would refuse the twin even if
  -- the helper did consult the name. That is why ⓒ is here and why it is the arm that carries the
  -- proposition: it asserts the shipped predicate's EXECUTABLE source never mentions the column,
  -- so no state — reachable today or not — can turn that string into a member. Comment lines are
  -- stripped before matching, because a comment quoting a removed line matches every grep that
  -- hunts for it; and the match is word-anchored, because a bare `custodian` substring would also
  -- hit `custodian_profile_id`, which the helper does and must consult.
  begin
    v_bad := '';
    select service_state, custodian_type, custodian_external, custodian_profile_id
      into v_state, v_ctype, v_ext, v_cust
      from session_dogs where id = (f_ext->>'session_dog')::uuid;
    -- ⓐ the reachable external-custody row, described exactly as it came out of the RPC
    if v_ext is distinct from '반포구청 안전과' then
      v_bad := v_bad || ' 전제: custodian_external=' || coalesce(v_ext,'NULL'); end if;
    if v_ctype is distinct from 'authorized_person' then
      v_bad := v_bad || ' 전제: custodian_type=' || coalesce(v_ctype,'NULL'); end if;
    if v_cust is distinct from v_auth then
      v_bad := v_bad || ' 전제: custodian_profile_id가 지정 인수자가 아니다'; end if;
    if v_state is distinct from 'ended' then
      v_bad := v_bad || ' 전제 변화: 외부 커스터디 행이 살아있다(' || coalesce(v_state,'NULL') ||
               ') — S9 ⓑ의 과결정 설명이 더 이상 사실이 아니므로 이 핀을 다시 쓸 것'; end if;
    -- ⓑ the name twin is nobody
    perform set_config('request.jwt.claim.sub', v_twin::text, true);
    set local role authenticated;
    select count(*) into v_n from session_dogs where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 동명이인이 session_dogs를 읽는다=' || v_n; end if;
    select count(*) into v_n from session_people where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 동명이인이 session_people을 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 동명이인이 assignments를 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 동명이인이 participant_activities를 읽는다=' || v_n; end if;
    reset role;
    -- and the profile-backed external custodian: a real pointer on a dead dog reads no session
    perform set_config('request.jwt.claim.sub', v_auth::text, true);
    set local role authenticated;
    select count(*) into v_n from session_people where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 외부 인수자가 session_people을 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_ext->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' 외부 인수자가 participant_activities를 읽는다=' || v_n; end if;
    reset role;
    -- ⓒ the arm that actually carries the proposition
    select coalesce(bool_or(s.l ~ '\mcustodian_external\M'), false) into v_src
    from (select unnest(string_to_array(p.prosrc, E'\n')) as l from pg_proc p
           where p.oid = 'public._club_session_member(uuid,uuid)'::regprocedure) s
    where btrim(s.l) not like '--%';
    if v_src then v_bad := v_bad || ' 헬퍼 실행부가 custodian_external을 참조한다'; end if;
    if v_bad = '' then call _pass('srp','S9 an external custodian is a STRING, not an identity — a real authorized_person transfer lands custodian_external as free text beside a profile-backed custodian_profile_id, and a profile whose NAME is exactly that string reads 0 from all four tables. ⓐ records the state the product can actually reach and it is ENDED (every route into the external branch leaves the booking incident_review or completed), so ⓑ is over-determined and says so; ⓒ is the arm that carries the claim — the shipped predicate has no reference to custodian_external on any EXECUTABLE line (comments stripped, word-anchored so custodian_profile_id is not miscounted), so the string cannot admit anyone in any state, including one no RPC can reach yet');
    else v_msg := v_bad; call _fail('srp','S9 외부 커스터디언 문자열', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('srp','S9 외부 커스터디언 문자열', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ═══ standing guards — schema-wide, outside the fixture block ═══
do $$
declare v_n int; v_list text; v_msg text; v_pub boolean;
begin
  -- ---------- [G1] no public table carries the open read predicate. ANYWHERE. ----------
  -- Allowlist is EMPTY and every future entry must carry its reason inline — widening this list
  -- to get green is how this guard dies (the 98 H1 / P15 lesson, stated in CLAUDE.md).
  select count(*), coalesce(string_agg(c.relname || '.' || p.polname, ', ' order by c.relname), '')
    into v_n, v_list
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and p.polcmd in ('r', '*')
    and pg_get_expr(p.polqual, p.polrelid) = '(auth.uid() IS NOT NULL)';
  if v_n = 0 then call _pass('srp','G1 스키마 전체 — (auth.uid() IS NOT NULL) 읽기 정책 0건');
  else v_msg := v_n || '건 남아 있다: ' || v_list;
       call _fail('srp','G1 열린 읽기 술어 스키마 전체 스윕', v_msg); end if;

  -- ---------- [G3] row security is ON for all four — the disabled-RLS drift guard ----------
  -- Codex round 2's sharpest finding: a table with RLS DISABLED passed the migration's own checks
  -- while every row sat open, because counting policies proves nothing about a table where
  -- policies are inert. This is the STANDING half; 0131's A/D blocks are the apply-time half.
  -- a MISSING table would make a not-rowsecurity sweep vacuously green (codex round 3) —
  -- existence is asserted first, so G3's green means 「all four exist AND all four are RLS-on」
  select count(*) into v_n
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities');
  if v_n <> 4 then
    v_msg := '테이블이 ' || v_n || '/4개만 존재한다';
    call _fail('srp','G3 RLS 활성 스윕', v_msg); return;
  end if;
  select count(*), coalesce(string_agg(c.relname, ', ' order by c.relname), '') into v_n, v_list
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
    and not c.relrowsecurity;
  if v_n = 0 then call _pass('srp','G3 네 테이블 모두 row security ON — 꺼진 테이블에서 정책은 무력하다');
  else v_msg := v_n || '개 테이블이 RLS OFF: ' || v_list; call _fail('srp','G3 RLS 활성 스윕', v_msg); end if;

  -- ---------- [G2] the membership helper is not a public oracle ----------
  -- It answers "is this uid in this session" for ARBITRARY uid/session. PUBLIC execute on it
  -- would be a membership probe for anyone holding two UUIDs — the 0049 _club_shell_access rule.
  select has_function_privilege('public', 'public._club_session_member(uuid,uuid)', 'execute')
    into v_pub;
  if v_pub is not true then call _pass('srp','G2 _club_session_member는 PUBLIC 실행 불가');
  else v_msg := '_club_session_member가 PUBLIC 실행 가능 — 임의 uid 멤버십 오라클';
       call _fail('srp','G2 헬퍼 ACL', v_msg); end if;
end $$;
