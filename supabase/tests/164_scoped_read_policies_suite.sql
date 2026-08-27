-- ═══ 164 scoped read policies — 0131 pins (S1-S5 · S5b · S6-S10 · R1 · G1-G3 · 0131-G4 · 0131-G5) ═══
-- ⚠ THE INVENTORY IS RE-DERIVED FROM THIS FILE, NEVER FROM MEMORY (codex round 5, finding 6): it
--   read 「S1-S5·S5b·S6-S9 · R1 · G1-G3」 and silently omitted S10 and 0131-G4, both of which this
--   file itself had added. `grep -oE "_pass\('srp','[^ ']*"` prints the true list — 17 pins
--   (0131-G5 added in round 6).
-- What this suite pins: that the four club session tables whose only read policy was
-- `(auth.uid() IS NOT NULL)` now admit exactly the people who belong to that session, that they
-- still admit those people (a policy admitting nobody is green on every denial arm while four
-- features are dead), that the one real client caller keeps working, that the four scoped
-- predicates are STILL the ones 0131 wrote, and — the durable one — that NO public table anywhere
-- carries the old open predicate again.
--
-- 🔴 WHAT THE BEHAVIOURAL PINS DO NOT COVER, STATED IN TERMS OF WHAT THEY ACTUALLY DO (codex round
--   6, finding 4). S1-S10 are FIXTURE-BOUND: each measures what a specific person reads. A policy
--   that gains a new arm naming somebody no fixture is — `or auth.uid() = '<uuid>'::uuid` is the
--   one-line version — leaks every row of all four tables to that person while every behavioural
--   pin stays green, because none of them IS that person. That gap was open through round 5 and was
--   described in this header as if the pins covered it. **It is closed by 0131-G5, which pins the
--   deparsed predicates themselves rather than anyone's reading of them** — measured Q4: the drift
--   is 0 reds without G5 and reddens G5 alone with it.
--   Still open, and named rather than implied: a wider read policy on a table 0131 never touched.
--   G1 sweeps schema-wide but only for the EXACT old string, so a differently-spelled open policy
--   elsewhere is invisible here. That is a schema-wide question, not one of 0131's four.
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
  v_probe boolean;                                          -- S10 exact-boolean probes (round 5, finding 1)
  v_pendsd uuid; v_pendappr text; v_pendown2 uuid; v_pendresp uuid; v_pendstate text;  -- S5b (round 5, finding 3)
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
  -- PROPOSITION, stated before the assertions: `session_delegate_dog` makes the OWNER the pending
  -- row's `responsible_profile_id`, so before the round-4 factoring this exact person read all four
  -- tables through the generic pointer arms while their delegation sat unapproved. Real lifecycle,
  -- no INSERT.
  -- 🔴 [codex round 5, finding 3] THE GREEN MESSAGE ASSERTED THE LIFECYCLE FACTS AND THE PIN NEVER
  -- CHECKED THEM. It said 「pending」 and 「the responsible pointer is themselves」 while measuring
  -- only two denials. If the RPC stopped setting that pointer, S5b would stay green, its stated
  -- claim would be false, and its mutation sensitivity would be gone — silently, all three.
  -- Those facts ARE the reason this pin is interesting, so they are asserted now, and asserted from
  -- the ROW the RPC returned rather than from anyone's reading of 0048.
  -- ⚠ Liveness is asserted too, and it is load-bearing for the ATTRIBUTION: the row is not `ended`,
  -- so arm ⓓ's `service_state is distinct from 'ended'` conjunct is satisfied and cannot be what
  -- refuses this person. The owner/non-owner factoring is the only thing left that can.
  v_pendowner := t_user('sr_pend', 'owner'); v_penddog := t_dog(v_pendowner, 'SR-대기견');
  perform set_config('request.jwt.claim.sub', v_pendowner::text, true);
  v_pendsd := session_delegate_dog(v_ses, v_penddog, t_consent());
  v_bad := '';
  select approval, owner_profile_id, responsible_profile_id, service_state
    into v_pendappr, v_pendown2, v_pendresp, v_pendstate
    from session_dogs where id = v_pendsd;
  if v_pendappr is distinct from 'pending' then
    v_bad := v_bad || ' 전제: approval=' || coalesce(v_pendappr, 'NULL') || ' (대기 상태가 아니다)'; end if;
  if v_pendown2 is distinct from v_pendowner then
    v_bad := v_bad || ' 전제: owner_profile_id가 신청자가 아니다'; end if;
  if v_pendresp is distinct from v_pendowner then
    v_bad := v_bad || ' 전제: responsible_profile_id가 자기 자신이 아니다 — 이 핀이 흥미로운 이유 자체가 사라졌다'; end if;
  if v_pendstate = 'ended' then
    v_bad := v_bad || ' 전제: 대기 행이 이미 ended — 거절 요인이 소유자 분리가 아니라 생존성이 되어 귀속이 무너진다'; end if;
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 대기 위탁 보호자가 session_people을 읽는다=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 0 then v_bad := v_bad || ' 대기 위탁 보호자가 assignments를 읽는다=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S5b 대기(pending) 위탁 보호자는 아직 멤버가 아니다 — 실제 delegate RPC가 만든 행을 되읽어 approval=pending · owner_profile_id=신청자 · responsible_profile_id=신청자 본인 · service_state≠ended 를 모두 단언한 뒤, 그 사람이 session_people과 assignments에서 0행을 읽는다. 생존한 행에서 포인터가 자기 자신을 가리키는데도 거절된다는 것이 요점이고, 이제 그 전제들이 실제로 검사된다');
  else v_msg := v_bad; call _fail('srp','S5b 대기 위탁 보호자', v_msg); end if;

  -- ---------- [S10] THE CALLER-ONLY GUARANTEE — codex round 4, finding 1 ----------
  -- ⚠ RENAMED S6→S10 at merge: an agent closing finding 2 in a parallel worktree added its own
  -- S6-S9 (the pointer-arm family), and two pins answering to one label is a battery record that
  -- cannot be read afterwards. Theirs is contiguous and cited by its own measured table, so mine
  -- moved. A label collision between two correct slices is the file-level twin of the migration
  -- number collision — neither party was careless, and only the merge could see it.
  -- Round 3 bound the helper to `p_uid is not distinct from auth.uid()` so it stops being an
  -- arbitrary-pair membership oracle. That conjunct was then pinned by NOTHING: deleting it left
  -- the whole suite green, because every other pin calls the helper only about itself. A conjunct
  -- nothing can fail on is decoration that reads as coverage — the exact law this repo keeps
  -- paying for, here in the fix I had just added.
  -- Three arms, because one proves nothing: the ORACLE arm is the property, and the two SELF arms
  -- are controls that fail if the bind is over-tight (a helper that answered `false` to everything
  -- would pass the oracle arm alone).
  -- 🔴 [codex round 5, finding 1] ALL THREE ARMS USED A PLAIN `IF`, AND PL/pgSQL TREATS NULL AS
  -- FALSE. `IF NULL THEN` does not execute and neither does `IF NOT NULL THEN`, so a helper that
  -- returned NULL to every question passed all three arms and S10 stayed green while the membership
  -- oracle was wide open in the three-valued direction — the shape a broken predicate is MOST
  -- likely to take, since one NULL conjunct nulls a whole AND-chain. The pin existed to establish
  -- exact FALSE/TRUE and could not see the most probable break: a control that cannot fail.
  -- Every arm is now an exact assertion (`is not false` / `is not true`), so NULL fails all three
  -- BY CONSTRUCTION rather than by anyone remembering, and each message prints the value it got
  -- instead of 「it was truthy」. ⚠ The RLS policies themselves treat NULL as deny, so a NULL-ing
  -- helper fails closed at the four tables — which is exactly why no OTHER pin in this file can
  -- ever see it, and why this one has to.
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  v_bad := '';
  -- ⓐ ORACLE: a stranger asks about a REAL member. Must be false — not an error, false: an
  --   exception would still be an oracle (it distinguishes the pair by which failure it gives).
  begin
    v_probe := _club_session_member(v_ses, v_member);
    if v_probe is not false then
      v_bad := v_bad || ' 낯선 사람이 남의 멤버십을 조회했다 (값=' || coalesce(v_probe::text, 'NULL')
                     || ', 정확히 false여야 한다 — NULL도 오라클이다)';
    end if;
  exception when others then
    v_bad := v_bad || ' 오라클 팔이 예외를 냈다(예외도 신호다): ' || sqlerrm;
  end;
  -- ⓑ SELF-NEGATIVE control: the stranger about themselves — false, for a real reason
  v_probe := _club_session_member(v_ses, v_stranger);
  if v_probe is not false then
    v_bad := v_bad || ' 낯선 사람이 자기 자신을 멤버로 읽었다 (값=' || coalesce(v_probe::text, 'NULL') || ')';
  end if;
  reset role;
  -- ⓒ SELF-POSITIVE control: a real member about themselves — TRUE. Without this arm a helper
  --   hard-wired to `false` would satisfy ⓐ and ⓑ and the pin would certify a broken helper.
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  set local role authenticated;
  v_probe := _club_session_member(v_ses, v_member);
  if v_probe is not true then
    v_bad := v_bad || ' 진짜 멤버가 자기 자신을 못 읽는다 (값=' || coalesce(v_probe::text, 'NULL')
                   || ' — 바인드가 과하게 조였거나 헬퍼가 NULL을 낸다)';
  end if;
  reset role;
  if v_bad = '' then
    call _pass('srp','S10 헬퍼는 호출자 본인만 답한다 — 임의 쌍 오라클이 아니다. 세 팔 모두 정확한 불리언 단언(is not false / is not true)이라 NULL이 모든 팔에서 실패한다: plpgsql은 NULL을 거짓처럼 취급하므로 예전의 평범한 IF는 「전부 NULL을 내는 헬퍼」를 그대로 통과시켰다');
  else v_msg := v_bad; call _fail('srp','S10 호출자 전용 보장', v_msg); end if;

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
--     `incident_review` (from picked_up/active, 0058:164) or `completed` — which
--     `_club_compute_axes` maps to `service_state = 'ended'` on BOTH branches (0048:726-731
--     completed, 0048:732-741 incident_review).
--     Measured on the fixture, not read off the source: S9 ⓐ asserts the ended-ness it found.
--     S9 therefore carries a source arm as well as a behavioural one, and says why.

-- ── MUTATION BATTERY for arm ⓓ's propositions — RE-MEASURED IN FULL 2026-08-27 (round 5). ──
-- ⚠ THIS TABLE REPLACES THE ROUND-4 R0-R7 TABLE RATHER THAN AMENDING IT, and the reason is this
-- file's own law: a battery record goes stale the moment a pin CHANGES, not only when code does.
-- Round 5 gave S9 a fourth arm (ⓓ), so every row that touched S9 had to be re-run, and re-running
-- some rows while inheriting others produces a table nobody can trust. ⚠ It is also NOT a
-- reproduction of round 4's numbers: N5/N6 below are MY mutation, written out in full, and round
-- 4's M5 rode arm ⓓ's own liveness conjunct while mine carries its own. Different mutations give
-- different red sets legitimately; what is not legitimate is presenting one as the other.
-- Each plant is applied ALONE as an edit to a COPY of `supabase/` OUTSIDE the worktree — never by
-- editing 0131 in place, which another session owns. Every plant asserts `count(anchor) == 1` AND
-- reads the ARTIFACT back; `sed` exits 0 on no-match, and the read-back refused two runs here.
-- ⚠ THE CONTROL WAS OBSERVED CLEAN FIRST: the untouched lab is 1061/0, md5-identical to the
-- worktree. A delta measured against an unobserved control measures the lab, not the code.
--
--   N0  control, no plant                              1061/0   RED = []
--   N1  the LIVENESS conjunct deleted                  1059/2   RED = [S8, S9]. S8 names the
--       damage rather than swapping a token (「an ended dog's pointer reads session_people=2,
--       assignments=2, participant_activities=3」); S9 reddens on its PROFILE-BACKED external
--       custodian — a second, independent subject for the same conjunct. ⓓ does NOT move, and
--       correctly: ⓓ's dog is alive either way.
--   N2  the whole NOT-owner pointer disjunct deleted   1058/3   RED = [S6, S7, S8 ⓐ] — all three
--       report 「cannot read = 0」, i.e. the arm is gone, not that a denial changed shape.
--   N3  only `custodian_profile_id` deleted            1061/0   RED = []  ⚠ THE DOCUMENTED
--       LIMITATION, RE-MEASURED RATHER THAN INHERITED. Reachability fact 2 above: the three
--       pointers move in one UPDATE, so a live non-owner holds all three and dropping one changes
--       nothing any fixture can see. Written down as a gap instead of papered over with an INSERT
--       the product cannot make.
--   N4  `p_uid is distinct from owner` deleted         1060/1   RED = [S5b] — the round-3 critical
--       still has exactly one owner, and it is not one of these pins.
--   N5  a `custodian_external` name-matching disjunct  1060/1   RED = [S9], via **ⓒ AND ⓓ**.
--       ADDED to the helper, carrying its own liveness             Round 4 measured ⓒ only; ⓓ is
--       conjunct (the property S9 holds is an ABSENCE,             the arm that shows a LIVE row
--       so its mutation is an addition)                            really does admit the twin.
--       ⓑ stays green — it is over-determined by liveness and says so.
--   N6  N5 + N1 together                               1059/2   RED = [S8, S9 via the ended
--       external custodian AND ⓒ AND ⓓ].
--   N7  [round 5, finding 2 — THE ONE THAT MATTERS] the helper's own source stays CLEAN and a
--       CALLEE reads the column: `or public._lab_ext_member(p_session, p_uid)` is added to the
--       helper, and that function does the `profiles.name = custodian_external` match.
--       · against the PRE-round-5 suite:  **1061/0, RED = [] — codex's finding 2 reproduced
--         exactly.** ⓒ is green by construction (it scans one function's own text); ⓑ is green
--         because it is over-determined by liveness; nothing else looks. A transitive read of the
--         column was completely invisible.
--       · against THIS suite:  **1060/1, S9 alone, entirely via ⓓ** — ⓒ never speaks. ⓓ is an
--         OBSERVATION on a constructed live row, so it does not care what the predicate reads or
--         how many functions deep it reads it.
--
-- 🔴 N0-N7 ARE ROUND-5 MEASUREMENTS AGAINST A 1061-PIN CORPUS AND ROUND 6 STALED THEIR NUMBERS.
-- Round 6 added `0131-G5` and rewrote S9 ⓒ and ⓓ, so: every absolute count above is off by at
-- least one, and any plant that moves a POLICY PREDICATE now reddens `0131-G5` as well. The rows
-- are kept because each still records what a pin is SENSITIVE to; the numbers are not to be cited.
-- ⚠ They were not re-run because round 5's plants exist only as this prose, and a reconstruction
-- presented as a re-run is worse than an inherited row that says it is one. What round 6 measured
-- itself, on its own plants, is below.
--
-- ── ROUND 6's OWN PLANTS for these two arms (full table in 0131's header) ────────────────────
--   Q5  the helper's EXECUTABLE source references `custodian_external`, with a legal string
--       literal containing `--` earlier ON THE SAME LINE; behaviourally inert (`false and …`).
--       · pre-round-6 suite:  **1062/0, RED = [ ]** — round 5's `regexp_replace(prosrc,'--[^\n]*')`
--         deleted the reference, so ⓒ stayed green with its sentence false. Codex round 6's
--         finding 3, reproduced.
--       · this suite:  **1062/1, RED = [S9] alone, via ⓒ** (값=true). A raw scan cannot be
--         shortened by a `--` anywhere.
--   Q6  the 「name twin」 renamed, so it is no longer a twin.
--       · pre-round-6 suite:  **1062/0, RED = [ ]** — ⓓ read 0 rows and claimed a property about a
--         profile whose name it had never re-read.
--       · this suite:  **1062/1, RED = [S9] alone, via ⓓ's precondition**, printing both names.
--   Q3d the P-H class re-cut (a dead `or true` arm on `session_people`, D's predicate arms
--       removed):  **1056/7, RED = [S1, S5, S5b, S7, S8, S9, `0131-G5`]** — round 5 measured six
--       for this class; `0131-G5` is the seventh and the only one that names the CAUSE.
--   Q4  post-apply predicate drift (`or auth.uid() = '<uuid no fixture is>'`):  pre-round-6
--       **1062/0, RED = [ ]** · this suite **1062/1, RED = [`0131-G5`] alone**.

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
  -- (0066:37) still validates confirmed → picked_up — so this UPDATE from the harness's postgres
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
  v_ext2 text;                                   -- S9 ⓓ read-back of the planted live row (round 5, finding 2)
  v_twinname text;                               -- S9 ⓓ re-read of profiles.name at read time (round 6, finding 3)
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
  -- can. `session_dogs` is deliberately NOT the evidence table — the policy 「dogs scoped read」 has
  -- its own `current_runner_profile_id = auth.uid()` arm and would admit this person without the
  -- helper ever being consulted, which is the exact mistake codex rejected S3's first draft for.
  -- ⚠ Cited by POLICY NAME, not by line. This read a line-number citation into 0131 (line 207), and by round 5 that line was blank —
  -- the dog policy's direct arms had moved (codex round 5, finding 6). A policy name is stable
  -- against every edit that does not change what is being cited.
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
    -- ⓒ and the honest half: the dog ROW itself stays visible, through the policy 「dogs scoped
    --   read」's own direct pointer arms, which are not the helper and are not what S8 is about.
    --   Written down so a later reader does not take S8's green as 「the ex-custodian sees nothing」.
    --   (Cited by policy name: the old line-number citation into 0131 had gone stale — round 5, finding 6.)
    select count(*) into v_n from session_dogs where id = (f_end->>'session_dog')::uuid;
    if v_n <> 1 then v_bad := v_bad || ' ⓒ자기 담당이었던 개 행마저 사라졌다=' || v_n; end if;
    reset role;
    if v_bad = '' then call _pass('srp','S8 THE LIVENESS CONJUNCT, with attribution — the same emergency transferee, holding the same three pointers, reads the session while the dog is in service and reads NOTHING once a real settlement (t_settle completed) ends it. The pin asserts the three pointer values are byte-identical across the transition and that the subject is still not the owner, so `service_state is distinct from ended` is the only conjunct that can explain the change: deleting it alone must redden this pin, which is precisely what round 4 measured as impossible before. ⓒ the dog row itself is still visible to that person through the policy 「dogs scoped read」s own current_runner_profile_id = auth.uid() arm, not through the helper — what closes is the SESSION-WIDE read');
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
  -- the helper did consult the name.
  -- ⓒ reads SOURCE, and 🔴 [codex round 5, finding 2] ITS CLAIM USED TO OUTRUN ITS MEASUREMENT.
  -- It said the absence of one token from one function's text meant the string 「cannot admit anyone
  -- in ANY state」. It cannot mean that: `_club_session_member` could call something else that reads
  -- the column, and this scan would be green either way. What ⓒ licenses is exactly one sentence,
  -- and 🔴 [codex round 6, finding 3] ROUND 5's VERSION OF THAT SENTENCE WAS STILL WRONG. It read
  -- 「the helper's own EXECUTABLE source does not name `custodian_external`」 and established that by
  -- deleting `--`-to-end-of-line with a regex — which is not a SQL comment parser, and which a legal
  -- string literal containing `--` turns into a deleter of REAL source. The sentence is now the one
  -- the measurement actually supports: **the token appears nowhere in the helper's SOURCE TEXT,
  -- comments included, nothing stripped.** Stronger, unforgeable by a `--`, and red (not green) if
  -- someone ever writes the column name into a comment there.
  -- ⓓ is the arm that actually carries the 「any state」 half, and it carries it as an OBSERVATION
  -- rather than a source read: it CONSTRUCTS the state ⓐ has just shown the product cannot reach — a
  -- LIVE dog holding a non-null `custodian_external` that is the exact name of a real profile — and
  -- measures whether that profile is admitted. Whatever the predicate consults, directly or through
  -- any callee, the answer is measured rather than inferred. It is also the arm that is NOT
  -- over-determined: liveness holds, so a denial here can only come from the predicate.
  -- ⚠ [codex round 6, finding 3] ⓓ's own SUBJECT is now re-established at read time — the twin's
  -- `profiles.name` re-read and compared against the string actually planted, and its
  -- non-relationship to that session asserted across all four helper arms. Without those, ⓓ
  -- licensed 「one planted identity/session pair」 while its message claimed a property of the
  -- predicate: a name changed 200 lines earlier, or a relationship acquired in between, would have
  -- explained the result completely.
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
    -- ⓒ the SOURCE arm. 🔴 [codex round 6, finding 3] IT STRIPPED COMMENTS WITH
    --   `regexp_replace(prosrc, '--[^\n]*', '', 'g')` AND CALLED WHAT WAS LEFT 「executable source」.
    --   That regex is not a SQL comment parser: a perfectly legal string literal containing `--`
    --   makes it erase REAL source to the end of that line — so ⓒ could stay green while the
    --   sentence it prints was false. On an ABSENCE claim that is the fatal direction, and the
    --   repair is not a smarter regex: identifying executable SQL by regex is the thing that cannot
    --   be done here. ⓒ now scans the RAW `prosrc`, COMMENTS INCLUDED, and claims exactly that —
    --   **the token appears NOWHERE in the helper's source text.** Strictly stronger than the old
    --   sentence, and no `--` anywhere can shorten what is scanned.
    --   Its cost, stated so nobody later "fixes" it back: mentioning the column in a COMMENT in that
    --   body turns this pin red. That is fail-closed, and the answer is to rewrite the pin, never to
    --   reintroduce stripping. Word-anchored, because a bare `custodian` substring also hits
    --   `custodian_profile_id`, which the helper does and must consult (control measured on this
    --   server, both directions: raw `\mcustodian_profile_id\M` → true, `\mcustodian_external\M`
    --   → false). `is not false` and not a bare IF — a scan that came back NULL measured nothing.
    select (p.prosrc ~ '\mcustodian_external\M') into v_src
    from pg_proc p where p.oid = 'public._club_session_member(uuid,uuid)'::regprocedure;
    if v_src is not false then
      v_bad := v_bad || ' 헬퍼 원문(주석 포함)이 custodian_external을 참조한다 (값='
                     || coalesce(v_src::text, 'NULL') || ')'; end if;
    -- ⓓ THE CONSTRUCTED LIVE STATE — an observation, not a source read.
    --   ⚠ This row is HAND-WRITTEN, deliberately, and for the only reason a hand-written fixture is
    --   ever right in this file: the proposition is about a state NO RPC CAN PRODUCE (ⓐ measures
    --   that every reachable external-custody row is already `ended`), so a lifecycle-real fixture
    --   cannot exist by definition. Everything about the row that IS checkable is checked — the
    --   write landed, and the dog is still LIVE afterwards despite `club_v1_axes_sync`
    --   (BEFORE INSERT OR UPDATE, `tgenabled='O'` measured 2026-08-27) recomputing the axes on this
    --   very statement. `_club_compute_axes` was measured not to reference `custodian_external`, so
    --   the column survives the trigger; the assertion below is what proves it did, on this run.
    --   The subject is f_live's session — a different pairing from ⓐ/ⓑ/ⓒ, still in service — and
    --   v_twin holds no relationship to it whatsoever, so admission could only come from the name.
    update session_dogs set custodian_external = '반포구청 안전과'
     where id = (f_live->>'session_dog')::uuid;
    select custodian_external, service_state into v_ext2, v_state2
      from session_dogs where id = (f_live->>'session_dog')::uuid;
    if v_ext2 is distinct from '반포구청 안전과' then
      v_bad := v_bad || ' ⓓ 심기 실패: custodian_external=' || coalesce(v_ext2, 'NULL')
                     || ' — 이 팔은 아무것도 측정하지 못했다'; end if;
    if v_state2 is distinct from 'in_service' then
      v_bad := v_bad || ' ⓓ 심기 실패: 살아있어야 할 개가 service_state=' || coalesce(v_state2, 'NULL')
                     || ' — 과결정이 되살아나 이 팔이 ⓑ와 같은 것을 재는 팔이 된다'; end if;
    -- 🔴 [codex round 6, finding 3] THE SUBJECT IS RE-ESTABLISHED IMMEDIATELY BEFORE THE READ.
    --   ⓓ asserted the planted string and the liveness and then said 「a profile whose NAME is
    --   exactly that string, holding no relationship to this session」 — while checking NEITHER of
    --   those two facts at read time. A `t_user` call 200 lines earlier is not evidence about the
    --   row now (`profiles.name` is writable), and an admission would be fully explained by any
    --   relationship the twin had picked up in between. Both are read from the catalog here, and the
    --   name is compared against the value ACTUALLY planted rather than against a repeated literal.
    select name into v_twinname from profiles where id = v_twin;
    if v_twinname is distinct from v_ext2 then
      v_bad := v_bad || ' ⓓ 전제: 동명이인의 profiles.name=' || coalesce(v_twinname, 'NULL')
                     || ' 이 심은 custodian_external=' || coalesce(v_ext2, 'NULL')
                     || ' 과 다르다 — 동명이 아니면 이 팔은 아무것도 재지 않는다'; end if;
    --   no relationship of ANY kind to f_live's session — the helper's four arms, enumerated
    if exists (select 1 from club_sessions s where s.id = (f_live->>'session')::uuid
                 and (s.host_profile_id = v_twin or s.backup_host_profile_id = v_twin)) then
      v_bad := v_bad || ' ⓓ 전제: 동명이인이 호스트/백업 호스트다'; end if;
    select count(*) into v_n from session_people
      where session_id = (f_live->>'session')::uuid and profile_id = v_twin;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 전제: 동명이인에게 session_people 행이 있다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments
      where session_id = (f_live->>'session')::uuid and runner_profile_id = v_twin;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 전제: 동명이인에게 배정 행이 있다=' || v_n; end if;
    select count(*) into v_n from session_dogs
      where session_id = (f_live->>'session')::uuid
        and v_twin in (owner_profile_id, custodian_profile_id, responsible_profile_id, current_runner_profile_id);
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 전제: 동명이인이 session_dogs 포인터를 쥐고 있다=' || v_n; end if;
    perform set_config('request.jwt.claim.sub', v_twin::text, true);
    set local role authenticated;
    select count(*) into v_n from session_dogs where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 살아있는 개의 외부 이름과 동명인 사람이 session_dogs를 읽는다=' || v_n; end if;
    select count(*) into v_n from session_people where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 동명이인이 session_people을 읽는다=' || v_n; end if;
    select count(*) into v_n from session_runner_assignments where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 동명이인이 assignments를 읽는다=' || v_n; end if;
    select count(*) into v_n from participant_activities where session_id = (f_live->>'session')::uuid;
    if v_n <> 0 then v_bad := v_bad || ' ⓓ 동명이인이 participant_activities를 읽는다=' || v_n; end if;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    if v_bad = '' then call _pass('srp','S9 an external custodian is a STRING, not an identity — a real authorized_person transfer lands custodian_external as free text beside a profile-backed custodian_profile_id, and a profile whose NAME is exactly that string reads 0 from all four tables. Each arm licenses exactly one sentence and no more. ⓐ: the only state the product can REACH is already ENDED (every route into the external branch leaves the booking incident_review or completed). ⓑ: the name twin reads nothing there — over-determined by liveness, and it says so rather than taking credit. ⓒ: the token custodian_external appears NOWHERE in the helper''s own source TEXT — comments included, nothing stripped, word-anchored so custodian_profile_id is not miscounted. That is deliberately a weaker and TRUER sentence than round 5''s 「no executable line names it」, which was established by a regex that a string literal containing -- can turn into a deleter of real source; it still does NOT exclude a callee reading the column, which is why it is not the arm that carries the claim. ⓓ: it does — a LIVE dog is given that exact external name by hand, a state no RPC can produce, and the profile of that name still reads 0 from all four tables with liveness, the twin''s profiles.name (compared to the string actually planted) and its total non-relationship to that session — host, backup host, session_people, assignment, all four dog pointers — asserted at the moment of the read, so the denial cannot be liveness, cannot be a stale fixture identity, and cannot be explained away by the source scan either');
    else v_msg := v_bad; call _fail('srp','S9 외부 커스터디언 문자열', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('srp','S9 외부 커스터디언 문자열', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ═══ standing guards — schema-wide, outside the fixture block ═══
do $$
declare v_n int; v_list text; v_msg text; v_pub boolean; v_bad text; v_bodyhash text;  -- v_bad: 0131-G4
        v_owner oid; v_ownername text; v_super boolean; v_bypass boolean; v_owns int;  -- 0131-G4 bypass (round 5, finding 4)
        v_reads text[]; v_calls text[]; v_call text; v_tblname text; v_missing text;   -- 0131-G4 read set + ordinary privileges (round 6, finding 1)
        v_tbl text; v_pol text; v_qual text; v_got text; v_textok boolean; v_depok boolean;  -- 0131-G5 (round 6, finding 4)
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

  -- ---------- [0131-G4] THE HELPER'S OWN SHAPE — the PRECONDITION, not the predicate ----------
  -- 🔴 Added 2026-08-27 by applying ui6's finding to my own battery: 「I mutated what the guard
  -- DOES and never mutated the guard's PRECONDITION.」 Every other pin in this file attacks the
  -- helper's ARMS. Nothing standing attacked the facts that make those arms mean anything —
  -- `prosecdef`, the in-body `search_path`, and the ACL were checked ONLY by the migration's
  -- VERIFY block, which runs once at apply and never again. A property checked at apply and
  -- never pinned is protected exactly until someone recreates the function.
  -- ⚠ Honest scope, because this pin's green licenses one sentence: losing DEFINER here fails
  -- CLOSED, not open — an INVOKER helper reads the very tables it gates, so RLS would deny
  -- everyone rather than admit anyone. That makes it an availability defect, not a disclosure.
  -- It is pinned anyway: a standing guard should not depend on which direction the breakage
  -- happens to fall, and the next recreation may not be so lucky.
  -- 🔴 [codex round 5, finding 4] AND `prosecdef` ALONE WAS THE WRONG PRECONDITION — the same
  -- mistake one level down. SECURITY DEFINER is not RLS bypass: a definer runs as its OWNER, and a
  -- non-bypassing owner is RLS-FILTERED on the very tables this helper gates. `create or replace`
  -- PRESERVES the owner, so a helper first created by the wrong role keeps that owner through every
  -- later apply, silently, with `prosecdef` true the whole time. The owner is now checked against
  -- PostgreSQL's own three routes (check_enable_rls / has_bypassrls_privilege): ① superuser,
  -- ② `rolbypassrls`, ③ owns the table and the table is not FORCE ROW LEVEL SECURITY — ③ across the
  -- whole READ SET, because one filtered table breaks every policy that consults the helper.
  v_bad := '';
  if not (select prosecdef from pg_proc
           where oid = 'public._club_session_member(uuid,uuid)'::regprocedure) then
    v_bad := v_bad || ' 헬퍼가 SECURITY DEFINER가 아니다';
  end if;
  if not exists (select 1 from pg_proc
                  where oid = 'public._club_session_member(uuid,uuid)'::regprocedure
                    and 'search_path=public, pg_temp' = any (proconfig)) then
    v_bad := v_bad || ' 헬퍼 본문에 search_path가 없다 (ALTER는 create or replace가 지운다)';
  end if;
  if has_function_privilege('anon', 'public._club_session_member(uuid,uuid)', 'execute') then
    v_bad := v_bad || ' anon이 헬퍼를 실행할 수 있다';
  end if;
  if not has_function_privilege('authenticated', 'public._club_session_member(uuid,uuid)', 'execute') then
    v_bad := v_bad || ' authenticated가 헬퍼를 실행할 수 없다 (정책이 통째로 죽는다)';
  end if;
  -- 🔴 [ui6 cold read + codex round 6, finding 1] THE TABLE SET WAS THE POLICY SET, COPIED FROM
  -- pre-check A. The helper READS ('club_sessions','session_dogs','session_people',
  -- 'session_runner_assignments'); `club_sessions` was read and never checked, `participant_
  -- activities` checked and never read. 0131's VERIFY D was fixed on trunk and THIS PIN WAS NOT —
  -- the standing half kept certifying the wrong four. So the set is DERIVED from the shipped body
  -- and FENCED against the expected exact set, exactly as D does it; a derivation that comes back
  -- NULL/empty is reported as inert rather than passed.
  select coalesce(array_agg(distinct m[2] order by m[2]), '{}') into v_reads
    from (select regexp_replace(prosrc, '--[^\n]*', '', 'g') as b
            from pg_proc where oid = 'public._club_session_member(uuid,uuid)'::regprocedure) src,
         regexp_matches(src.b, '(from|join)\s+([a-z_]+)', 'g') m
   where m[2] not in ('auth', 'sd');
  if v_reads is null or cardinality(v_reads) = 0 then
    v_bad := v_bad || ' 헬퍼가 읽는 테이블 집합을 도출하지 못했다 (NULL/빈 배열) — 이 팔은 통과가 아니라 무력이다';
  elsif not (v_reads <@ array['club_sessions','session_dogs','session_people','session_runner_assignments']
             and v_reads @> array['club_sessions','session_dogs','session_people','session_runner_assignments']) then
    v_bad := v_bad || ' 헬퍼가 읽는 테이블이 ' || array_to_string(v_reads, ',')
                   || ' 이다 — 이 핀이 검사하는 네 테이블과 다르다 (둘 다 고치지 않으면 엉뚱한 집합을 검사한다)';
  else
    select p.proowner, pg_get_userbyid(p.proowner) into v_owner, v_ownername
      from pg_proc p where p.oid = 'public._club_session_member(uuid,uuid)'::regprocedure;
    select r.rolsuper, r.rolbypassrls into v_super, v_bypass from pg_roles r where r.oid = v_owner;
    select count(*) into v_owns
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = any (v_reads)
       and c.relowner = v_owner and not c.relforcerowsecurity;
    if not (coalesce(v_super, false) or coalesce(v_bypass, false) or v_owns = cardinality(v_reads)) then
      v_bad := v_bad || ' 헬퍼 소유자 ' || coalesce(v_ownername, 'NULL') || '가 RLS를 우회하지 못한다'
                     || ' (①rolsuper=' || coalesce(v_super::text, 'NULL')
                     || ' ②rolbypassrls=' || coalesce(v_bypass::text, 'NULL')
                     || ' ③소유·비강제 ' || v_owns || '/' || cardinality(v_reads)
                     || ' — 읽기 집합 ' || array_to_string(v_reads, ',') || ') — DEFINER는 RLS 우회가 아니다;'
                     || ' 헬퍼가 자기가 지키는 테이블에서 필터링되어 정책이 재귀하거나 아무도 통과시키지 못한다';
    end if;
    -- 🔴 [codex round 6, finding 1] AND BYPASS IS NOT EXECUTABILITY. A preserved owner can carry
    -- `rolbypassrls` and still lack USAGE on `auth`, EXECUTE on `auth.uid()`, USAGE on `public` or
    -- SELECT on what the body reads — every one of which raises 42501 on the first client read from
    -- inside a helper the arm above has just certified. The qualified-call set is derived and fenced
    -- for the same reason the read set is: hardcoding `auth.uid` is the staleness this ladder keeps
    -- being rejected for. (Measured on this shim: `service_role` holds EXECUTE on `auth.uid()` and
    -- still cannot reach it, because it has no USAGE on schema `auth` — two separate privileges.)
    -- ⚠ HONEST SCOPE, MEASURED NOT ASSUMED (round 6 battery, Q1c): in THIS harness this arm can
    -- never be the thing that reports. Any state that trips it makes all four policies raise 42501,
    -- so the behavioural block above dies under ON_ERROR_STOP and the harness exits before the pin
    -- table is ever printed. It is pinned for the environment that has no suite to die — a
    -- production drift, where a standing sweep is the only thing that would name the cause.
    select coalesce(array_agg(distinct m[1] || '.' || m[2] order by m[1] || '.' || m[2]), '{}') into v_calls
      from (select regexp_replace(prosrc, '--[^\n]*', '', 'g') as b
              from pg_proc where oid = 'public._club_session_member(uuid,uuid)'::regprocedure) src,
           regexp_matches(src.b, '([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(', 'g') m;
    if v_calls is null or cardinality(v_calls) = 0 then
      v_bad := v_bad || ' 헬퍼의 정규화 호출 집합을 도출하지 못했다 — 권한 팔이 무력이다';
    elsif not (v_calls <@ array['auth.uid'] and v_calls @> array['auth.uid']) then
      v_bad := v_bad || ' 헬퍼가 호출하는 함수가 ' || array_to_string(v_calls, ',')
                     || ' 이다 — 이 권한 검사가 아는 집합과 다르다';
    else
      v_missing := '';
      if not has_schema_privilege(v_owner, 'public', 'usage') then
        v_missing := v_missing || ' public 스키마 USAGE;'; end if;
      foreach v_call in array v_calls loop
        if not has_schema_privilege(v_owner, split_part(v_call, '.', 1), 'usage') then
          v_missing := v_missing || ' ' || split_part(v_call, '.', 1) || ' 스키마 USAGE;'; end if;
        if not has_function_privilege(v_owner, v_call || '()', 'execute') then
          v_missing := v_missing || ' ' || v_call || '() EXECUTE;'; end if;
      end loop;
      foreach v_tblname in array v_reads loop
        if not has_table_privilege(v_owner, format('public.%I', v_tblname), 'select') then
          v_missing := v_missing || ' public.' || v_tblname || ' SELECT;'; end if;
      end loop;
      if v_missing <> '' then
        v_bad := v_bad || ' 헬퍼 소유자 ' || coalesce(v_ownername, 'NULL')
                       || '가 RLS는 우회해도 본문을 실행할 권한이 없다 — 없는 권한:' || v_missing
                       || ' (DEFINER는 소유자의 일반 권한으로도 실행된다; 첫 클라이언트 읽기에서 42501)';
      end if;
    end if;
  end if;
  if v_bad = '' then
    call _pass('srp','0131-G4 헬퍼 자체의 형상 — DEFINER · 본문 search_path · anon 불가 · authenticated 가능 · 소유자가 실제로 RLS를 우회한다(superuser · rolbypassrls · 읽기 집합 소유+비강제 중 하나) · 그리고 소유자가 본문을 실행할 일반 권한(스키마 USAGE · 호출 EXECUTE · 읽는 테이블 SELECT)까지 실제로 가진다. 검사 대상 테이블 집합은 배포된 본문에서 도출하고 예상 집합에 대해 울타리를 친다 — 정책 테이블 목록을 베껴 쓰면 club_sessions를 읽으면서 검사하지 않는 상태가 조용히 통과한다. 전제조건이지 술어가 아니다');
  else v_msg := v_bad; call _fail('srp','0131-G4 헬퍼 전제조건', v_msg); end if;

  -- ---------- [0131-G5] THE FOUR PREDICATES THEMSELVES, STANDING ----------
  -- 🔴 [codex round 6, finding 4] THE ADMITTED GAP WAS REAL AND THE HEADER BOUNDED IT DISHONESTLY.
  -- Adding one arm to a shipped policy after apply — `or auth.uid() = '<any authenticated uuid this
  -- suite does not use>'::uuid` — hands that user every row of all four tables, and NOTHING here saw
  -- it: S1-S10 are behavioural and none of them IS that user; G1 only sweeps the exact OLD open
  -- predicate; G2/G3/G4 are about the helper and RLS being on; 0131's VERIFY D ran once at apply and
  -- never again. Measured as Q4a against the pre-round-6 suite: **the drift was 0 reds.**
  -- So the four predicates are pinned STANDING, in exactly the two kinds D uses at apply time and
  -- for the same reason they are two kinds — (i) the deparsed text is EQUAL to what section C wrote
  -- (a new arm changes it; so does a removed one), (ii) the policy records a pg_depend row on
  -- `public._club_session_member(uuid,uuid)` (text a shadow schema can forge; a catalog row it
  -- cannot). Both arms are computed before either is reported, so a red names both answers.
  -- ⚠ WHAT THIS STILL DOES NOT COVER, so the header can stop over-claiming: a WIDER predicate on a
  -- table this file never named. G1 catches only the exact `(auth.uid() IS NOT NULL)` string, so a
  -- differently-spelled open policy on a fifth table is invisible to this suite — that is a
  -- schema-wide question and it belongs to a schema-wide sweep, not to 0131's four.
  -- ⚠ `pg_get_expr` deparses against the SESSION's search_path (round 5's shadow plant taught this);
  -- these strings are the ones an ordinary `"$user", public` session renders, which is what the
  -- harness and psql both use. A drift here fails CLOSED and prints got= and want=.
  v_bad := '';
  for v_tbl, v_pol, v_qual in
    select * from (values
      ('session_dogs','dogs scoped read',
       '((auth.uid() IS NOT NULL) AND ((owner_profile_id = auth.uid()) OR (custodian_profile_id = auth.uid()) OR (responsible_profile_id = auth.uid()) OR (current_runner_profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('session_people','people scoped read',
       '((auth.uid() IS NOT NULL) AND ((profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('session_runner_assignments','assignments scoped read',
       '((auth.uid() IS NOT NULL) AND ((runner_profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('participant_activities','activities scoped read',
       '((auth.uid() IS NOT NULL) AND _club_session_member(session_id, auth.uid()))')) t(a,b,c)
  loop
    select count(*) into v_n
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tbl;
    if v_n <> 1 then
      v_bad := v_bad || ' ' || v_tbl || '이 정책 ' || v_n || '개를 갖는다 (정확히 1개여야 한다 — 두 번째 정책은 OR로 더해진다)';
      continue;
    end if;
    select count(*) into v_n
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol
       and p.polcmd = 'r' and p.polpermissive
       and pg_get_expr(p.polqual, p.polrelid) = v_qual
       and (select array_agg(rolname order by rolname) from pg_roles where oid = any (p.polroles))
           = array['authenticated']::name[];
    v_textok := (v_n = 1);
    v_depok := exists (select 1
                 from pg_policy p join pg_class c on c.oid = p.polrelid
                 join pg_namespace n on n.oid = c.relnamespace
                 join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = p.oid
                where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol
                  and d.refclassid = 'pg_proc'::regclass
                  and d.refobjid = 'public._club_session_member(uuid,uuid)'::regprocedure);
    if not (v_textok and v_depok) then
      select pg_get_expr(p.polqual, p.polrelid) into v_got
        from pg_policy p join pg_class c on c.oid = p.polrelid
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol;
      v_bad := v_bad || ' ' || v_tbl || '.' || v_pol
                     || ' — 정확일치 ' || case when v_textok then 'PASS' else 'FAIL' end
                     || ' · 카탈로그 의존 ' || case when v_depok then 'PASS' else 'FAIL' end
                     || ' got=[' || coalesce(v_got, '(정책 없음)') || '] want=[' || v_qual || ']';
    end if;
  end loop;
  if v_bad = '' then
    call _pass('srp','0131-G5 네 정책의 술어 자체가 서 있다 — 적용 시점의 VERIFY D와 같은 문장을, 같은 두 종류의 증거로(배포된 문자열과의 정확일치 + pg_depend가 기록한 실제 함수 의존), 매 실행 상시로 검사한다. 적용 후에 팔 하나를 더한 표류(예: or auth.uid() = <어떤 uuid>)는 행동 핀 S1~S10에는 보이지 않는다 — 그 uuid를 쓰는 픽스처가 없기 때문이고, 그것이 이 핀이 존재하는 이유다');
  else v_msg := v_bad; call _fail('srp','0131-G5 술어 상시 고정', v_msg); end if;

  -- ---------- [0131-G6] THE HELPER'S OWN BODY, STANDING — codex round 7, finding 1 ----------
  -- 🔴 G5 pins the four POLICY predicates standing. Nothing pinned the HELPER's authorization
  --   expression itself. So `_club_session_member` could be recreated post-apply with an extra
  --   `or p_uid = '<some uuid>'` and EVERY guard stays green: D and G4 inspect structural
  --   preconditions (owner, privileges, search_path, the derived name sets — all unchanged), G5
  --   sees unchanged policies, and no fixture uses that UUID so no behavioural pin notices.
  --   The mirror of the gap round 6 closed, pointed at the other half of the pair.
  -- ⚠ Pinned by NORMALISED BODY HASH, not by an expected string: the body is 40+ lines of prose
  --   and predicate, and a string comparison in this file would be a second copy that must move
  --   with the first (the limit G5 already carries and states). A hash moves in one place, and
  --   the failure message prints both so a legitimate change is one paste to re-pin.
  -- ⚠ Comments STRIPPED before hashing — otherwise every prose edit in the helper reddens this,
  --   which is how a guard earns a `--no-verify`. Whitespace collapsed for the same reason.
  --   The cost is stated rather than hidden: a body CRAFTED to hide a read inside a string
  --   literal defeats the strip, exactly as the fences in 0131 say of themselves. This pin is a
  --   guard against DRIFT and recreation, not against a hostile author with DDL rights.
  select md5(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', ' ', 'g'))
    into v_bodyhash
    from pg_proc where oid = 'public._club_session_member(uuid,uuid)'::regprocedure;
  if v_bodyhash is null then
    call _fail('srp','0131-G6 헬퍼 본문 상시 고정', '헬퍼가 없어 해시를 낼 수 없다 — 이 핀은 통과가 아니라 무력하다');
  elsif v_bodyhash <> 'fef0a8635882a3df9aa867444dd54f3c' then
    v_msg := '헬퍼 본문이 바뀌었다. got=' || v_bodyhash
          || ' want=fef0a8635882a3df9aa867444dd54f3c — 의도한 변경이면 이 핀의 기대값을 같은 슬라이스에서 갱신하라';
    call _fail('srp','0131-G6 헬퍼 본문 상시 고정', v_msg);
  else
    call _pass('srp','0131-G6 헬퍼의 권한 판정식 자체가 서 있다 — 적용 후 몰래 넓혀도 여기서 걸린다');
  end if;

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

  -- ---------- [G2] the membership helper is not PUBLIC-executable ----------
  -- ⚠ [codex round 5, finding 6] THE RATIONALE THIS PIN CARRIED IS STALE and is corrected rather
  -- than trimmed. It read 「it answers 'is this uid in this session' for ARBITRARY uid/session, so
  -- PUBLIC execute would be a membership probe for anyone holding two UUIDs」. Round 3's caller bind
  -- ended that: the helper's first conjunct is `p_uid is not distinct from auth.uid()`, so a caller
  -- with a NULL `auth.uid()` — which is what PUBLIC/anon reaches this function as — gets false for
  -- every pair. S10 is the pin that establishes the bind; this one does not.
  -- What G2 licenses is one narrow ACL fact: **PUBLIC has no effective EXECUTE on the helper.** It
  -- is kept because it is a SECOND, INDEPENDENT control over the same property as the bind, and the
  -- two fail differently — the bind lives in a function body that `create or replace` can drop, an
  -- ACL does not. Neither is evidence for the other, which is the entire reason to hold both.
  -- (0049 `_club_shell_access` is the precedent for the ACL habit, not for the oracle claim.)
  select has_function_privilege('public', 'public._club_session_member(uuid,uuid)', 'execute')
    into v_pub;
  if v_pub is not true then call _pass('srp','G2 _club_session_member는 PUBLIC 실행 불가');
  else v_msg := '_club_session_member가 PUBLIC 실행 가능 — 임의 uid 멤버십 오라클';
       call _fail('srp','G2 헬퍼 ACL', v_msg); end if;
end $$;
