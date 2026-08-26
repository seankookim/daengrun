-- ═══ 164 scoped read policies — 0131 pins (S1-S4 · R1 · G1-G2) ═══
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
  v_host uuid; v_member uuid; v_owner uuid; v_runner uuid; v_stranger uuid;
  v_club uuid; v_ses uuid; v_ses2 uuid; v_rt2 uuid; v_dog uuid; v_sp_id uuid;
  v_n int; v_pre int; v_bad text; v_msg text; v_finish_err text;
begin
  -- ---------- fixtures: one session, four people who belong, one who does not ----------
  v_host     := t_user('sr_host', 'runner');
  v_member   := t_user('sr_member', 'owner');
  v_owner    := t_user('sr_owner', 'owner');
  v_runner   := t_user('sr_runner', 'runner');
  v_stranger := t_user('sr_stranger', 'owner');

  insert into clubs (name, district, status, host_profile_id)
    values ('SR클럽', '반포동', 'active', v_host) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host, now() + interval '2 hours', 'SR 집결지') returning id into v_ses;

  insert into session_people (session_id, profile_id, role, attendance)
    values (v_ses, v_member, 'owner_attending', 'rsvp') returning id into v_sp_id;
  insert into session_runner_assignments (session_id, runner_profile_id, delegated_capacity, status)
    values (v_ses, v_runner, 2, 'committed');
  v_dog := t_dog(v_owner, 'SR-dog');
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody, approval)
    values (v_ses, v_dog, v_owner, v_runner, 'runner_delegated', 'approved');
  insert into participant_activities (session_id, person_id, source, km)
    values (v_ses, v_sp_id, 'self_reported', 3.2);

  -- ---------- R1's population, built through the REAL lifecycle ----------
  -- ⚠ R1 was VACUOUSLY GREEN at pre=0/post=0 until this existed: the caller's predicate needs
  -- `attendance='checked_in'` AND `club_sessions.status='done'`, and the S1-S4 fixture produces
  -- neither. A pin that compares 0 to 0 asserts nothing — 「empty is not a control」. This drives
  -- club_create_session → session_runner_commit → session_checkin → club_finish_session so the
  -- population is one the product can actually produce.
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  -- ⚠ 1시간 미만은 `too_soon` (0037:372). 첫 시도가 30분이었고 create에서 죽었다 — 예외 블록은
  -- finish를 감싸고 있었으므로 이 실패는 잡히지 않았다.
  v_rt2 := t_route('SR 종료 코스');
  v_ses2 := club_create_session(v_club, now() + interval '2 hours', 'SR 종료 집결지', v_rt2, 8, 'mixed');
  perform set_config('request.jwt.claim.sub', v_member::text, false);
  insert into session_people (session_id, profile_id, role, attendance)
    values (v_ses2, v_member, 'owner_attending', 'checked_in')
    on conflict do nothing;
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  begin
    perform club_finish_session(v_ses2);
  exception when others then
    -- finishing can refuse for reasons unrelated to this pin (a future session, viability,
    -- blockers). Fall back to the terminal status directly and RECORD that it happened — a silent
    -- fallback would let R1's pass message claim a lifecycle-real fixture it did not build.
    v_finish_err := sqlerrm;
    update club_sessions set status = 'done' where id = v_ses2;
  end;
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
  if v_n <> 1 then v_bad := v_bad || ' session_dogs=' || v_n; end if;
  select count(*) into v_n from session_people             where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' session_people=' || v_n; end if;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' session_runner_assignments=' || v_n; end if;
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
  if v_n <> 1 then v_bad := v_bad || ' ⓐ호스트(session_people)=' || v_n; end if;
  reset role;
  -- ⓒ committed runner reading session_people: his own profile_id is NOT in session_people for
  --   this session, so admission can only come from the helper's assignment branch
  perform set_config('request.jwt.claim.sub', v_runner::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' ⓒ배정러너(session_people)=' || v_n; end if;
  reset role;
  -- ⓓ delegating owner reading session_people: likewise no row of his own there, so only the
  --   helper's live-dog branch can admit him
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;
  select count(*) into v_n from session_people where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' ⓓ위탁보호자(session_people)=' || v_n; end if;
  reset role;
  -- ⓑ the attending member reading session_runner_assignments: no direct arm there either
  perform set_config('request.jwt.claim.sub', v_member::text, true);
  set local role authenticated;
  select count(*) into v_n from session_runner_assignments where session_id = v_ses;
  if v_n <> 1 then v_bad := v_bad || ' ⓑ참가자(assignments)=' || v_n; end if;
  reset role;
  if v_bad = '' then call _pass('srp','S3 헬퍼 네 갈래를 각각 고립 검증 — 직접 arm이 없는 테이블에서 읽어 헬퍼만이 통과시킬 수 있게 했다 (ⓐ호스트 ⓑ참가자 ⓒ배정러너 ⓓ위탁보호자)');
  else v_msg := '헬퍼 갈래가 막혔다:' || v_bad; call _fail('srp','S3 헬퍼 갈래 고립', v_msg); end if;

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
  -- app/src/lib/api.ts:1629 (fetchStampStats) counts session_people filtered by profile_id.
  -- Its own comment says the filter is a correctness requirement BECAUSE the RLS was open.
  -- 0131 must not turn that count into 0 — that would silently zero the 도장 벽.
  -- 🔴 [codex REJECT] 이 핀은 `where profile_id = v_member`만 셌다. 진짜 호출자
  -- (api.ts:1629 fetchStampStats)는 `attendance='checked_in'` 이고 club_sessions에 조인해
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
             || coalesce(' · 종료 경로: 직접 update (' || v_finish_err || ')', ' · 종료 경로: club_finish_session');
       call _pass('srp','R1 fetchStampStats의 실제 술어가 정책 전후로 같은 수를 센다 — ' || v_msg);
  else v_msg := 'pre=' || v_pre || ' post=' || v_n || ' — 정책이 도장 벽을 깎았다';
       call _fail('srp','R1 실제 호출자 보존', v_msg); end if;
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

  -- ---------- [G2] the membership helper is not a public oracle ----------
  -- It answers "is this uid in this session" for ARBITRARY uid/session. PUBLIC execute on it
  -- would be a membership probe for anyone holding two UUIDs — the 0049 _club_shell_access rule.
  select has_function_privilege('public', 'public._club_session_member(uuid,uuid)', 'execute')
    into v_pub;
  if v_pub is not true then call _pass('srp','G2 _club_session_member는 PUBLIC 실행 불가');
  else v_msg := '_club_session_member가 PUBLIC 실행 가능 — 임의 uid 멤버십 오라클';
       call _fail('srp','G2 헬퍼 ACL', v_msg); end if;
end $$;
