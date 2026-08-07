-- ═══ 0062 runner application + certification funnel ═══
-- What this suite pins: the applicant → certified path is the ONLY way `runners.tier` rises, the
-- application table is unreachable from any client role, the applicant projection cannot leak ops
-- notes or contact details, and approval changes exactly the columns it is allowed to change.
--
-- Style follows the 97/98/99/100/101 siblings: `_pass('rf',…)`/`_fail('rf',…)`, each case in its own
-- begin…exception when others, definer/view paths stay `postgres` and switch identity with
-- set_config('request.jwt.claim.sub', …), real RLS/role paths use `set local role` with an
-- unconditional `reset role` in every handler. Runs LAST in the harness, so every earlier helper
-- exists; the now()-independent fixture window is 2026-11-24 (disjoint from 95-100's 09/10 windows).
--
-- ─── DELIBERATE OMISSION: plan pin F1 ───
-- Plan §8.1 F1 pins the `runners` INSERT seal. That seal shipped as 0061_runner_insert_seal.sql and
-- is already pinned six ways by 101_runner_insert_seal_suite.sql (S1 the published attack, S2
-- commission, S3 identity, S4 the positive control, S5 the service path, S6 the UPDATE guard).
-- Re-pinning it here would be a verbatim duplicate — and the plan's F1 wording is stale besides:
-- shipped 0061 COERCES privileged columns to defaults rather than raising `runner_protected_columns`.
-- F2-F14 below are the 0062 surface. F2/F3 carry the "0062 did not open a second promotion path"
-- half of F1's job.
--
-- ─── MUTATION VERIFICATION (2026-08-08) ───
-- Baseline before this slice: 252/0. With 0062 + this suite: 265/0.
-- ✔ = ACTUALLY EXECUTED in this build: the single revert was applied to an undamaged 0062 (the perl
--     substitution asserts it matched exactly one hunk and the file md5 changed — a sed that
--     silently matches nothing is a fake proof), the WHOLE harness was re-run, the named pin went
--     RED and nothing else moved, then 0062 was byte-restored and 265/0 returned.
--     Unmarked lines are the IDENTIFIED revert, not an executed proof. Do not add ✔ without running.
--   F2  ← `create policy "rf self all" on runner_applications for all using (profile_id = auth.uid());`
--         ✔ executed → 264/1, F2 alone: `보인행=2 insert거부=true update행=-1 delete행=1 state=∅`
--         (the client read BOTH of uz's rows and deleted one — the whole point of zero policies)
--   F3  ← delete the final `insert into runner_applications … returning id` from runner_apply_submit
--   F4  ← `drop index runner_app_one_active;`  (RPC check alone leaves the direct-insert half red)
--   F5  ← delete the three-consent check from runner_apply_submit
--         ✔ executed → 264/1, F5 alone: `terms=false privacy=false idcheck=false null=false rows=0`
--         (the column-level check constraints still refuse the row, but with the WRONG token — which
--          is exactly why this pin asserts `consent_required` and not merely "no row appeared")
--   F6  ← swap the party gate and the state gate in runner_apply_withdraw
--         ✔ executed → 264/1, F6 alone:
--           `없는id=not_found 남의활성=not_found 남의종단=not_withdrawable 본인취소=withdrawn`
--         ⚠ This proof is why the seed carries app_z2. The FIRST version of F6 probed only a live
--           foreign row, and against this very revert it stayed GREEN — a live foreign row passes
--           the state gate and dies at the party gate, answering `not_found` either way. Only a
--           TERMINAL foreign row exposes the oracle. A pin that cannot fail is not a pin.
--   F7  ← add `decided_note text` to runner_my_application's returns table + select
--   F8  ← `grant execute on function runner_app_approve(uuid,text,text) to authenticated;`
--         (F8 half (c) already earned its keep during the build — see the note on the case itself)
--   F9  ← add `online = true` to the runner_app_approve UPDATE
--         ✔ executed → 264/1, F9 alone: `online(false였음)=true`, every other field unchanged
--   F10 ← remove the `if v_app.state = 'approved' then return …` early-return branch
--         ✔ executed → 264/1, F10 alone: `not_approvable`
--   F11 ← change is_active_runner() to read runner_applications instead of runners.tier
--   F12 ← delete the `application_barred` check from runner_apply_submit
--   F13 ← drop `set search_path = public, pg_temp` from runner_app_approve's body (98 H1 also reds)
--   F14 ← `alter table runner_applications drop constraint runner_app_decided_shape;`
set client_min_messages = warning;

-- Submit helper — the RPC takes 14 arguments and every case would otherwise be unreadable.
-- Invoker (not definer) on purpose: it is a test fixture, not a surface, so 98 H1 / 99 S1 ignore it.
create or replace function t_rf_submit(
  p_uid uuid,
  p_district text default '반포동',
  p_kakao text default 'rf_kakao',
  p_phone text default null
) returns uuid language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  return runner_apply_submit(
    p_district, 333, 27.5, 5.0, array['대형견','새벽러닝'],
    '반포 한강공원에서 매일 아침 달립니다 — 대형견 동반 러닝이 제일 자신 있어요',
    '10km 50분, 주 4회 5년째. 마라톤 완주 2회.',
    '보더콜리 두 마리를 7년 키웠고 이웃 대형견 산책을 3년 대신했어요',
    p_kakao, p_phone, '평일 저녁 8시 이후', true, true, true);
end $$;

do $$
declare
  uo uuid; uz uuid; ua uuid; uc uuid; ud uuid; ue uuid; ug uuid;
  uh uuid; ui uuid; uj uuid; um uuid; uk uuid;
  dg uuid; rt uuid; bk uuid;
  app_z uuid; app_z2 uuid; app_k uuid; app_a uuid; app_c uuid; app_d uuid; app_e uuid;
  app_h uuid; app_i uuid; app_j uuid;
  fake  uuid := '00000000-0000-4000-8000-0000000f0f0f';
  v_n int; v_n2 int; v_n3 int; v_pre int; v_post int;
  v_a boolean; v_b boolean; v_c boolean; v_d boolean; v_e boolean; v_f boolean; v_g boolean;
  v_tier text; v_state text; v_txt text; v_txt2 text; v_txt2b text; v_txt3 text; v_uid uuid;
  v_comm numeric; v_comm0 numeric; v_km numeric; v_pace int; v_rad numeric; v_wt numeric;
  v_idv boolean; v_online boolean; v_runs int; v_bar boolean; v_reapply boolean;
  v_dec timestamptz; v_dec2 timestamptz;
  v_cols text[]; v_keys text[];
  v_ids uuid[]; v_ids2 uuid[];
  v_exp_cols text[] := array['id','state','attempt_no','submitted_at','reviewed_at','decided_at',
                             'reject_reason','is_hard_bar','can_reapply'];
  w_start timestamptz := timestamptz '2026-11-24 10:00:00+09';   -- now()-independent fixture window
  w_end   timestamptz := timestamptz '2026-11-24 11:00:00+09';
begin
  -- ---------- seed ----------
  -- t_user(…, 'runner') would mint a tier='certified' runners row; every applicant here is created
  -- as an 'owner' profile and then given an explicit applicant-tier runners row where one is needed.
  uo := t_user('rf_oo', 'owner');
  uz := t_user('rf_uz', 'owner'); uc := t_user('rf_uc', 'owner');
  ua := t_user('rf_ua', 'owner'); ud := t_user('rf_ud', 'owner'); ue := t_user('rf_ue', 'owner');
  ug := t_user('rf_ug', 'owner'); uh := t_user('rf_uh', 'owner'); ui := t_user('rf_ui', 'owner');
  uj := t_user('rf_uj', 'owner'); um := t_user('rf_um', 'owner'); uk := t_user('rf_uk', 'owner');
  update profiles set role = 'runner'
    where id in (uz, ua, uc, ud, ue, ug, uh, ui, uj, um, uk);

  insert into runners (profile_id, online, bio) values (ua, false, 'rf 지원 전 소개');
  insert into runners (profile_id, online, bio) values (ud, true,  'rf 지원 전 소개');
  insert into runners (profile_id, online, bio) values (ue, false, 'rf 지원 전 소개');
  insert into runners (profile_id, online)      values (ug, true);
  insert into runners (profile_id, online)      values (uh, false);
  insert into runners (profile_id, online)      values (uk, false);

  -- A raw row for the seal/constraint pins, created as `postgres` so F2 and F14 do not depend on
  -- the RPC working (they must stay meaningful even if runner_apply_submit is broken).
  insert into runner_applications (profile_id, district, avg_pace_sec_per_km, max_dog_weight_kg,
    bio, running_experience, dog_experience, contact_kakao,
    consent_terms, consent_privacy, consent_id_check)
  values (uz, '반포동', 400, 20.0, '봉인 테스트용 소개 문구입니다',
    '러닝 경력 문구입니다 열자 이상', '반려견 경험 문구입니다 열자 이상', 'rf_uz_kakao',
    true, true, true)
  returning id into app_z;

  -- A TERMINAL application belonging to someone else. F6 needs one: with the party gate and the
  -- state gate in the wrong order, a live foreign row still answers `not_found` (it passes the
  -- state gate and dies at the party gate) — only a terminal foreign row exposes the oracle by
  -- answering `not_withdrawable`. Without this fixture F6 would be green against its own revert.
  insert into runner_applications (profile_id, attempt_no, state, district, avg_pace_sec_per_km,
    max_dog_weight_kg, bio, running_experience, dog_experience, contact_kakao,
    consent_terms, consent_privacy, consent_id_check, decided_at, decided_by, reject_reason)
  values (uz, 2, 'rejected', '반포동', 400, 20.0, '봉인 테스트용 소개 문구입니다',
    '러닝 경력 문구입니다 열자 이상', '반려견 경험 문구입니다 열자 이상', 'rf_uz_kakao',
    true, true, true, now(), 'sean', '종단 상태 픽스처')
  returning id into app_z2;

  -- F14 mutates a row to destruction-adjacent states; it gets its OWN row so that a revert which
  -- lets F2's client DELETE succeed cannot take F14's fixture down with it (observed: it did).
  insert into runner_applications (profile_id, district, avg_pace_sec_per_km, max_dog_weight_kg,
    bio, running_experience, dog_experience, contact_kakao,
    consent_terms, consent_privacy, consent_id_check)
  values (uk, '반포동', 400, 20.0, '형상 제약 테스트용 소개 문구입니다',
    '러닝 경력 문구입니다 열자 이상', '반려견 경험 문구입니다 열자 이상', 'rf_uk_kakao',
    true, true, true)
  returning id into app_k;

  -- ---------- [F2] the table is sealed — RLS on, zero policies ----------
  -- Supabase default privileges DO grant authenticated select/insert/update/delete on new public
  -- tables (00_shim.sql:58 models this), so the seal has to be RLS, not a missing grant. All four
  -- verbs are exercised against a row that really exists — a false-green where "nothing leaked
  -- because nothing was there" is exactly what this pin must not be.
  begin
    v_a := false; v_b := false; v_c := false; v_d := false;
    perform set_config('request.jwt.claim.sub', uz::text, false);
    set local role authenticated;
    select count(*) into v_n from runner_applications;
    v_a := (v_n = 0);                                        -- own row invisible too
    begin
      insert into runner_applications (profile_id, district, avg_pace_sec_per_km, max_dog_weight_kg,
        bio, running_experience, dog_experience, contact_kakao, state,
        consent_terms, consent_privacy, consent_id_check)
      values (uz, '반포동', 400, 20.0, '자가 승인 시도 소개 문구', '러닝 경력 문구입니다 열자',
        '반려견 경험 문구입니다 열자', 'x', 'approved', true, true, true);
      v_b := false;                                          -- insert succeeded = hole
    exception when others then v_b := true;
    end;
    -- update/delete get their own handlers too: with a policy in place the UPDATE reaches the
    -- decided_shape constraint and raises, and an unhandled raise here would report a constraint
    -- name instead of "a client could reach these rows" — a true RED, but an unreadable one.
    begin
      update runner_applications set state = 'approved' where id = app_z;
      get diagnostics v_n2 = row_count;
      v_c := (v_n2 = 0);
    exception when others then v_c := false; v_n2 := -1;
    end;
    begin
      delete from runner_applications where id = app_z;
      get diagnostics v_n3 = row_count;
      v_d := (v_n3 = 0);
    exception when others then v_d := false; v_n3 := -1;
    end;
    reset role;
    select a.state into v_state from runner_applications a where a.id = app_z;
    if v_a and v_b and v_c and v_d and v_state = 'submitted'
      then call _pass('rf','F2 테이블 봉인 — authenticated: select 0행·insert 거부·update 0행·delete 0행 (정책 0개)');
    else call _fail('rf','F2 테이블 봉인',
           '보인행=' || coalesce(v_n::text,'∅') || ' insert거부=' || coalesce(v_b::text,'∅')
           || ' update행=' || coalesce(v_n2::text,'∅') || ' delete행=' || coalesce(v_n3::text,'∅')
           || ' state=' || coalesce(v_state,'∅'));
    end if;
  exception when others then reset role; call _fail('rf','F2 테이블 봉인', sqlerrm);
  end;

  -- ---------- [F3] submit happy — 1행·submitted·attempt 1, 그리고 tier는 그대로 applicant ----------
  -- The tier half is the point: submitting an application must not itself be a promotion path.
  begin
    app_a := t_rf_submit(ua);
    select count(*) into v_n from runner_applications a where a.profile_id = ua;
    select a.state, a.attempt_no into v_state, v_n2 from runner_applications a where a.id = app_a;
    select r.tier::text into v_tier from runners r where r.profile_id = ua;
    if v_n = 1 and v_state = 'submitted' and v_n2 = 1 and v_tier = 'applicant'
      then call _pass('rf','F3 지원 제출 — 1행·state=submitted·attempt_no=1, 제출만으로는 tier가 오르지 않는다');
    else call _fail('rf','F3 지원 제출',
           'rows=' || coalesce(v_n::text,'∅') || ' state=' || coalesce(v_state,'∅')
           || ' attempt=' || coalesce(v_n2::text,'∅') || ' tier=' || coalesce(v_tier,'∅'));
    end if;
  exception when others then call _fail('rf','F3 지원 제출', sqlerrm);
  end;

  -- ---------- [F4] one live application — RPC 토큰 + 부분 유니크 인덱스 두 반쪽 ----------
  -- The direct-insert half proves the INDEX, not just the RPC guard: two connections racing
  -- runner_apply_submit both pass the `exists` check, and the index is what makes exactly one win.
  begin
    v_a := false; v_b := false;
    begin
      perform t_rf_submit(ua);
    exception when others then v_a := (sqlerrm = 'already_applied');
    end;
    begin
      insert into runner_applications (profile_id, attempt_no, state, district,
        avg_pace_sec_per_km, max_dog_weight_kg, bio, running_experience, dog_experience,
        contact_kakao, consent_terms, consent_privacy, consent_id_check)
      values (ua, 2, 'under_review', '반포동', 400, 20.0, '두 번째 활성 지원 소개 문구',
        '러닝 경력 문구입니다 열자', '반려견 경험 문구입니다 열자', 'x', true, true, true);
    exception when others then v_b := (sqlerrm like '%runner_app_one_active%');
    end;
    select count(*) into v_n from runner_applications a where a.profile_id = ua;
    if v_a and v_b and v_n = 1
      then call _pass('rf','F4 활성 지원 1건 — 재제출은 already_applied, postgres 직접 2행 삽입은 runner_app_one_active 위반');
    else call _fail('rf','F4 활성 지원 1건',
           'rpc=' || coalesce(v_a::text,'∅') || ' index=' || coalesce(v_b::text,'∅')
           || ' rows=' || coalesce(v_n::text,'∅'));
    end if;
  exception when others then call _fail('rf','F4 활성 지원 1건', sqlerrm);
  end;

  -- ---------- [F5] consent gate — 세 동의 중 하나라도 빠지면 행이 생기지 않는다 ----------
  -- NULL is tested separately from false: `is distinct from true` is the reason a client-sent NULL
  -- cannot slip past, and an `= false` comparison would let it through.
  begin
    v_a := false; v_b := false; v_c := false; v_d := false;
    perform set_config('request.jwt.claim.sub', um::text, false);
    begin
      perform runner_apply_submit('반포동', 333, 27.5, 5.0, '{}', '소개 문구입니다 열자 이상',
        '러닝 경력 문구입니다 열자', '반려견 경험 문구입니다 열자', 'k', null, null, false, true, true);
    exception when others then v_a := (sqlerrm = 'consent_required'); end;
    begin
      perform runner_apply_submit('반포동', 333, 27.5, 5.0, '{}', '소개 문구입니다 열자 이상',
        '러닝 경력 문구입니다 열자', '반려견 경험 문구입니다 열자', 'k', null, null, true, false, true);
    exception when others then v_b := (sqlerrm = 'consent_required'); end;
    begin
      perform runner_apply_submit('반포동', 333, 27.5, 5.0, '{}', '소개 문구입니다 열자 이상',
        '러닝 경력 문구입니다 열자', '반려견 경험 문구입니다 열자', 'k', null, null, true, true, false);
    exception when others then v_c := (sqlerrm = 'consent_required'); end;
    begin
      perform runner_apply_submit('반포동', 333, 27.5, 5.0, '{}', '소개 문구입니다 열자 이상',
        '러닝 경력 문구입니다 열자', '반려견 경험 문구입니다 열자', 'k', null, null, true, true, null);
    exception when others then v_d := (sqlerrm = 'consent_required'); end;
    select count(*) into v_n from runner_applications a where a.profile_id = um;
    if v_a and v_b and v_c and v_d and v_n = 0
      then call _pass('rf','F5 동의 게이트 — 약관·개인정보·신분확인 중 하나라도 false/NULL이면 consent_required, 행 0');
    else call _fail('rf','F5 동의 게이트',
           'terms=' || coalesce(v_a::text,'∅') || ' privacy=' || coalesce(v_b::text,'∅')
           || ' idcheck=' || coalesce(v_c::text,'∅') || ' null=' || coalesce(v_d::text,'∅')
           || ' rows=' || coalesce(v_n::text,'∅'));
    end if;
  exception when others then call _fail('rf','F5 동의 게이트', sqlerrm);
  end;

  -- ---------- [F6] enumeration oracle — 없는 id와 남의 id의 에러가 바이트 동일 ----------
  -- Party gate BEFORE state gate. If the order flips, another user's live application answers
  -- `not_withdrawable` while a nonexistent id answers `not_found` — and the difference is a free
  -- existence oracle over every application id in the table.
  begin
    app_c := t_rf_submit(uc);
    perform set_config('request.jwt.claim.sub', uc::text, false);
    v_txt := null; v_txt2 := null; v_txt3 := null;
    begin perform runner_apply_withdraw(fake);        -- (a) no such application anywhere
    exception when others then v_txt := sqlerrm; end;
    begin perform runner_apply_withdraw(app_a);       -- (b) ua's real, LIVE application
    exception when others then v_txt2 := sqlerrm; end;
    begin perform runner_apply_withdraw(app_z2);      -- (c) uz's real, TERMINAL application
    exception when others then v_txt3 := sqlerrm; end;
    perform runner_apply_withdraw(app_c);             -- positive control: own row withdraws
    select a.state into v_state from runner_applications a where a.id = app_c;
    select a.state into v_txt2b from runner_applications a where a.id = app_a;
    v_a := (v_txt2b = 'submitted');                   -- the other user's row is untouched
    if v_txt is not distinct from v_txt2 and v_txt is not distinct from v_txt3
       and v_txt = 'not_found' and v_state = 'withdrawn' and v_a
      then call _pass('rf','F6 열거 오라클 차단 — 없는 id·남의 활성 지원서·남의 종단 지원서가 모두 바이트 동일한 not_found (양성 대조: 본인 지원서는 취소됨)');
    else call _fail('rf','F6 열거 오라클 차단',
           '없는id=' || coalesce(v_txt,'∅') || ' 남의활성=' || coalesce(v_txt2,'∅')
           || ' 남의종단=' || coalesce(v_txt3,'∅')
           || ' 본인취소=' || coalesce(v_state,'∅') || ' 타인무변=' || coalesce(v_a::text,'∅'));
    end if;
  exception when others then call _fail('rf','F6 열거 오라클 차단', sqlerrm);
  end;

  -- ---------- [F7] projection shape — 선언 9컬럼 = 런타임 9키, ops 노트·연락처는 자리가 없다 ----------
  -- 100 W6 / 97 V10 clone, both halves: (1) the contract surface (proargnames mode 't'), which a
  -- future `create or replace` would widen, and (2) the runtime key set of a REAL row. uj's row is
  -- approved with a non-empty decided_note and a real phone number on purpose — this pin must read
  -- "structurally absent", not "happened to be null".
  begin
    app_j := t_rf_submit(uj, '반포동', 'rf_uj_kakao', '01012345678');
    perform runner_app_approve(app_j, 'sean', 'ops 내부 메모 — 화상 통화 확인');
    perform set_config('request.jwt.claim.sub', uj::text, false);
    select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'runner_my_application' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(k order by k) into v_keys from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from runner_my_application() x limit 1) s) t;
    select count(*) into v_n
    from unnest(coalesce(v_cols, '{}'::text[]) || coalesce(v_keys, '{}'::text[])) c
    where c ~* 'note|_by$|contact|kakao|phone|bio|district|consent|experience|special|radius|weight|pace';
    if coalesce(array_length(v_cols,1),0) = 9 and v_cols @> v_exp_cols and v_exp_cols @> v_cols
       and coalesce(array_length(v_keys,1),0) = 9 and v_keys @> v_exp_cols and v_exp_cols @> v_keys
       and v_n = 0
      then call _pass('rf','F7 투영 형상·누수 — 선언 9컬럼 = 런타임 9키, decided_note/decided_by/contact_*/페이로드 0');
    else call _fail('rf','F7 투영 형상·누수','proargnames=' || coalesce(v_cols::text,'∅')
           || ' 런타임키=' || coalesce(v_keys::text,'∅') || ' 누수=' || coalesce(v_n::text,'∅'));
    end if;
  exception when others then call _fail('rf','F7 투영 형상·누수', sqlerrm);
  end;

  -- ---------- [F8] ops RPC 봉인 — ACL · 실제 거부 · 그리고 그랜트가 잘못 걸려도 본문이 막는다 ----------
  -- Three layers, because the plan asks for belt AND braces:
  --   (a) has_function_privilege for all three ops RPCs (positive control: runner_apply_submit).
  --   (b) an actual call as `authenticated` → permission denied.
  --   (c) grant EXECUTE to authenticated on purpose, call again → must still raise `ops_only`.
  --       The grant is revoked in both the happy path and the handler.
  -- (c) is the half that caught a real defect in the plan: the specified in-body check was
  -- `current_user in ('authenticated','anon')`, and inside a SECURITY DEFINER body current_user is
  -- ALWAYS the owner (postgres) — so the "belt and braces" was dead code, and the first run of this
  -- pin approved app_a from a client role. 0062 §4 checks the `role` GUC instead. This is why (c)
  -- grants for real rather than reasoning about the grant.
  begin
    v_a := has_function_privilege('authenticated','runner_app_review(uuid,text)','execute');
    v_b := has_function_privilege('authenticated','runner_app_approve(uuid,text,text)','execute');
    v_c := has_function_privilege('authenticated','runner_app_reject(uuid,text,text,boolean)','execute');
    v_d := has_function_privilege('authenticated',
      'runner_apply_submit(text,int,numeric,numeric,text[],text,text,text,text,text,text,boolean,boolean,boolean)','execute');
    v_e := false; v_f := false; v_g := false;
    perform set_config('request.jwt.claim.sub', ua::text, false);
    begin
      set local role authenticated;
      perform runner_app_approve(app_a, 'attacker', 'x');
      reset role;
    exception when others then reset role; v_e := (sqlerrm like '%permission denied%'); end;
    begin
      set local role anon;
      perform runner_app_review(app_a, 'attacker');
      reset role;
    exception when others then reset role; v_f := (sqlerrm like '%permission denied%'); end;
    grant execute on function runner_app_approve(uuid,text,text) to authenticated;
    begin
      set local role authenticated;
      perform runner_app_approve(app_a, 'attacker', 'x');
      reset role;
    exception when others then reset role; v_g := (sqlerrm = 'ops_only'); end;
    revoke execute on function runner_app_approve(uuid,text,text) from authenticated;
    select a.state into v_state from runner_applications a where a.id = app_a;
    if not v_a and not v_b and not v_c and v_d and v_e and v_f and v_g and v_state = 'submitted'
      then call _pass('rf','F8 ops RPC 봉인 — authenticated/anon 실행 불가(양성 대조: runner_apply_submit 가능), 그랜트를 강제로 걸어도 본문이 ops_only');
    else call _fail('rf','F8 ops RPC 봉인',
           'review=' || coalesce(v_a::text,'∅') || ' approve=' || coalesce(v_b::text,'∅')
           || ' reject=' || coalesce(v_c::text,'∅') || ' 대조군(submit)=' || coalesce(v_d::text,'∅')
           || ' 거부(auth)=' || coalesce(v_e::text,'∅') || ' 거부(anon)=' || coalesce(v_f::text,'∅')
           || ' 본문게이트=' || coalesce(v_g::text,'∅') || ' state=' || coalesce(v_state,'∅'));
    end if;
  exception when others then
    reset role;
    revoke execute on function runner_app_approve(uuid,text,text) from authenticated;
    call _fail('rf','F8 ops RPC 봉인', sqlerrm);
  end;

  -- ---------- [F9] approve가 바꾸는 것과 바꾸지 않는 것 ----------
  -- Changes: tier, identity_verified, and the storefront payload (bio/specialties/pace/radius/weight).
  -- Does NOT change: `online` (the runner owns that switch — tested with it BOTH true and false),
  -- `commission_rate` (take rate is flat; tier and commission are linked only in a stale 0001:75
  -- comment), `total_runs`/`total_km` (settle_run_tx owns those; a newly certified runner must not
  -- get a second visibility boost on top of the 8+2 rookie slots).
  begin
    app_d := t_rf_submit(ud);
    app_e := t_rf_submit(ue);
    select r.commission_rate into v_comm0 from runners r where r.profile_id = ud;
    perform runner_app_approve(app_d, 'sean', '화상 통화 2026-11-24, 신분증 확인');
    perform runner_app_approve(app_e, 'sean', '화상 통화 2026-11-24, 신분증 확인');
    select r.tier::text, r.identity_verified, r.online, r.commission_rate, r.total_runs, r.total_km,
           r.bio, r.avg_pace_sec_per_km, r.service_radius_km, r.max_dog_weight_kg
      into v_tier, v_idv, v_online, v_comm, v_runs, v_km, v_txt, v_pace, v_rad, v_wt
      from runners r where r.profile_id = ud;
    select r.online into v_a from runners r where r.profile_id = ue;
    select p.district into v_txt2 from profiles p where p.id = ud;
    if v_tier = 'certified' and v_idv and v_online = true and v_a = false
       and v_comm = v_comm0 and v_runs = 0 and v_km = 0
       and v_pace = 333 and v_rad = 5.0 and v_wt = 27.5 and v_txt <> 'rf 지원 전 소개'
       and v_txt2 = '반포동'
      then call _pass('rf','F9 승인 효과 — tier=certified·identity_verified·스토어프런트 페이로드 복사, online(양쪽)·commission_rate·total_runs/km는 무변');
    else call _fail('rf','F9 승인 효과',
           'tier=' || coalesce(v_tier,'∅') || ' idv=' || coalesce(v_idv::text,'∅')
           || ' online(true였음)=' || coalesce(v_online::text,'∅')
           || ' online(false였음)=' || coalesce(v_a::text,'∅')
           || ' comm=' || coalesce(v_comm::text,'∅') || '/' || coalesce(v_comm0::text,'∅')
           || ' runs=' || coalesce(v_runs::text,'∅') || ' km=' || coalesce(v_km::text,'∅')
           || ' pace=' || coalesce(v_pace::text,'∅') || ' radius=' || coalesce(v_rad::text,'∅')
           || ' weight=' || coalesce(v_wt::text,'∅') || ' 동네=' || coalesce(v_txt2,'∅'));
    end if;
  exception when others then call _fail('rf','F9 승인 효과', sqlerrm);
  end;

  -- ---------- [F10] approve 멱등 — ops가 두 번 눌러도 승인은 한 번 ----------
  begin
    select a.decided_at into v_dec from runner_applications a where a.id = app_d;
    v_uid := runner_app_approve(app_d, 'someone_else', '두 번째 클릭');
    select a.decided_at, a.state, a.decided_by into v_dec2, v_state, v_txt
      from runner_applications a where a.id = app_d;
    select count(*) into v_n from runner_applications a where a.profile_id = ud;
    if v_uid = ud and v_dec2 = v_dec and v_state = 'approved' and v_txt = 'sean' and v_n = 1
      then call _pass('rf','F10 승인 멱등 — 재승인은 같은 uuid 반환·decided_at/decided_by 무변·행 증가 없음');
    else call _fail('rf','F10 승인 멱등',
           'uuid=' || coalesce(v_uid::text,'∅') || ' decided_at동일=' || coalesce((v_dec2 = v_dec)::text,'∅')
           || ' state=' || coalesce(v_state,'∅') || ' by=' || coalesce(v_txt,'∅')
           || ' rows=' || coalesce(v_n::text,'∅'));
    end if;
  exception when others then call _fail('rf','F10 승인 멱등', sqlerrm);
  end;

  -- ---------- [F11] 게이트 거울 — 네 소비자 전부가 runners.tier를 읽는다 ----------
  -- This pin exists to stop a future refactor from deriving the capability gate from
  -- runner_applications and putting a join inside is_active_runner() / the RLS policies that call
  -- it. ud is approved and online; ug is an applicant, online, with an IDENTICAL availability rule —
  -- so the only difference between them is the tier.
  -- count_available_runners is asserted as a DELTA, not an absolute: earlier suites leave their own
  -- runners in the cluster and an absolute count would be a hostage to their fixtures.
  begin
    dg := t_dog(uo, 'rf견'); rt := t_route('rf 코스');
    v_pre := count_available_runners(w_start, w_end);
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (ug, extract(dow from w_start at time zone 'Asia/Seoul')::int, 0, 1440);
    v_post := count_available_runners(w_start, w_end);
    v_a := (v_post = v_pre);                                  -- applicant is not supply
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (ud, extract(dow from w_start at time zone 'Asia/Seoul')::int, 0, 1440);
    v_post := count_available_runners(w_start, w_end);
    v_b := (v_post = v_pre + 1);                              -- certified is

    select count(*) into v_n  from available_runners av where av.profile_id = ud;
    select count(*) into v_n2 from available_runners av where av.profile_id = ug;
    v_c := (v_n = 1 and v_n2 = 0);

    perform set_config('request.jwt.claim.sub', ud::text, false);
    v_d := is_active_runner();
    perform set_config('request.jwt.claim.sub', ug::text, false);
    v_e := not is_active_runner();

    insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (uo, dg, rt, 'matching', w_start, 5.0, 9900, 15000, 0, 24900, 9900)
    returning id into bk;
    -- runners_available_for hands back at most 10 rows (8 veteran + 2 rookie slots, 0055 §1-2), and
    -- earlier suites leave more than 10 online certified runners in the cluster — ud, with 0 runs
    -- and a random uuid, loses the rookie tiebreak roughly at chance. That would make this pin
    -- FLAKY, not wrong, so the other online runners are parked offline for exactly this call and
    -- restored immediately. Safe because 102 runs last, and the restore is asserted below.
    select array_agg(r.profile_id) into v_ids from runners r
      where r.online and r.profile_id not in (ud, ug);
    update runners set online = false where profile_id = any(coalesce(v_ids, '{}'::uuid[]));
    perform set_config('request.jwt.claim.sub', uo::text, false);
    select array_agg(x.profile_id) into v_ids2 from runners_available_for(bk) x;
    update runners set online = true where profile_id = any(coalesce(v_ids, '{}'::uuid[]));
    select count(*) into v_n3 from runners r
      where r.profile_id = any(coalesce(v_ids, '{}'::uuid[])) and not r.online;
    v_f := (coalesce(v_ids2, '{}'::uuid[]) @> array[ud]
            and not (coalesce(v_ids2, '{}'::uuid[]) @> array[ug])
            and v_n3 = 0);                                   -- and the park/restore left no debris
    update bookings set status = 'expired' where id = bk;   -- do not pollute the open pool

    if v_a and v_b and v_c and v_d and v_e and v_f
      then call _pass('rf','F11 게이트 거울 — 승인 러너는 available_runners·count_available_runners·is_active_runner·runners_available_for 전부에, 신청자는 어디에도 없다');
    else call _fail('rf','F11 게이트 거울',
           'count(신청자무영향)=' || coalesce(v_a::text,'∅') || ' count(+1)=' || coalesce(v_b::text,'∅')
           || ' view=' || coalesce(v_c::text,'∅') || ' is_active(승인)=' || coalesce(v_d::text,'∅')
           || ' is_active(신청)=' || coalesce(v_e::text,'∅') || ' 지명목록=' || coalesce(v_f::text,'∅')
           || ' 목록크기=' || coalesce(array_length(v_ids2,1)::text,'0')
           || ' 복구잔여=' || coalesce(v_n3::text,'∅'));
    end if;
  exception when others then call _fail('rf','F11 게이트 거울', sqlerrm);
  end;

  -- ---------- [F12] 거절 — 빈 사유 불가 · 사유 축자 노출 · 재지원 · 하드바 · 시도 상한 ----------
  -- The empty-reason half is enforced by the check constraint, not by a duplicate RPC check: one
  -- enforcement point, and it also covers a direct service-role update.
  begin
    v_a := false; v_b := false; v_c := false; v_d := false; v_e := false; v_f := false;
    app_h := t_rf_submit(uh);
    begin perform runner_app_reject(app_h, 'sean', '   ');
    exception when others then v_a := (sqlerrm like '%runner_app_reject_reason%'); end;

    perform runner_app_reject(app_h, 'sean', '반포 활동 지역이 아니에요 — 서비스 지역이 열리면 알려드릴게요');
    perform set_config('request.jwt.claim.sub', uh::text, false);
    select m.reject_reason, m.is_hard_bar, m.can_reapply, m.attempt_no
      into v_txt, v_bar, v_reapply, v_n from runner_my_application() m;
    v_b := (v_txt = '반포 활동 지역이 아니에요 — 서비스 지역이 열리면 알려드릴게요'
            and not v_bar and v_reapply and v_n = 1);

    perform runner_app_reject(t_rf_submit(uh), 'sean', '두 번째 거절 사유');
    select a.attempt_no into v_n2 from runner_applications a
      where a.profile_id = uh order by a.attempt_no desc limit 1;
    v_c := (v_n2 = 2);                                        -- soft reject → re-application allowed
    perform runner_app_reject(t_rf_submit(uh), 'sean', '세 번째 거절 사유');
    begin perform t_rf_submit(uh);
    exception when others then v_d := (sqlerrm = 'attempt_cap_reached'); end;

    app_i := t_rf_submit(ui);
    perform runner_app_reject(app_i, 'sean', '안전 사유로 영구 제외합니다', true);
    begin perform t_rf_submit(ui);
    exception when others then v_e := (sqlerrm = 'application_barred'); end;
    perform set_config('request.jwt.claim.sub', ui::text, false);
    select m.is_hard_bar, m.can_reapply into v_bar, v_reapply from runner_my_application() m;
    v_f := (v_bar and not v_reapply);

    select count(*) into v_n3 from runners r
      where r.profile_id in (uh, ui) and r.tier is distinct from 'applicant';
    if v_a and v_b and v_c and v_d and v_e and v_f and v_n3 = 0
      then call _pass('rf','F12 거절 — 빈 사유는 runner_app_reject_reason 위반·사유 축자 노출·소프트 거절 후 2차 지원·4차는 attempt_cap_reached·하드바는 영구 application_barred, tier는 내내 applicant');
    else call _fail('rf','F12 거절',
           '빈사유=' || coalesce(v_a::text,'∅') || ' 축자=' || coalesce(v_b::text,'∅')
           || ' 재지원=' || coalesce(v_c::text,'∅') || ' 상한=' || coalesce(v_d::text,'∅')
           || ' 하드바=' || coalesce(v_e::text,'∅') || ' 투영=' || coalesce(v_f::text,'∅')
           || ' 승급된행=' || coalesce(v_n3::text,'∅'));
    end if;
  exception when others then call _fail('rf','F12 거절', sqlerrm);
  end;

  -- ---------- [F13] definer 위생 — 6개 함수 pg_temp 봉인 + 실제 섀도잉 공격 ----------
  -- Half one is a named-six restatement of 98 H1 (which sweeps the whole schema); half two is the
  -- 0055 §3 lesson: prove the sweep MEANS something by actually shadowing `runner_applications`
  -- with a temp table containing a decoy row and confirming the definer still reads `public`.
  -- The decoy row would approve uk if it were read — so uk.tier is the real assertion.
  begin
    select count(*) into v_n from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef
      and p.proname in ('runner_apply_submit','runner_apply_withdraw','runner_my_application',
                        'runner_app_review','runner_app_approve','runner_app_reject')
      and coalesce(array_to_string(p.proconfig, ','), '') like '%pg_temp%';
    create temp table runner_applications (like public.runner_applications including defaults);
    insert into pg_temp.runner_applications (id, profile_id, district, avg_pace_sec_per_km,
      max_dog_weight_kg, bio, running_experience, dog_experience, contact_kakao,
      consent_terms, consent_privacy, consent_id_check)
    values (fake, uk, '섀도우동', 400, 20.0, '섀도잉 미끼 소개 문구', '러닝 경력 문구 열자',
      '반려견 경험 문구 열자', 'shadow', true, true, true);
    v_a := false;
    begin
      perform runner_app_approve(fake, 'attacker', 'shadow');
    exception when others then v_a := (sqlerrm = 'not_found'); end;
    drop table pg_temp.runner_applications;
    select r.tier::text into v_tier from runners r where r.profile_id = uk;
    if v_n = 6 and v_a and v_tier = 'applicant'
      then call _pass('rf','F13 definer 위생 — 신규 6함수 전부 본문에 search_path=public,pg_temp, temp 테이블 섀도잉 승인 시도는 not_found로 튕김');
    else call _fail('rf','F13 definer 위생',
           '봉인된함수=' || coalesce(v_n::text,'∅') || '/6 섀도잉차단=' || coalesce(v_a::text,'∅')
           || ' uk.tier=' || coalesce(v_tier,'∅'));
    end if;
  exception when others then
    begin drop table if exists pg_temp.runner_applications; exception when others then null; end;
    call _fail('rf','F13 definer 위생', sqlerrm);
  end;

  -- ---------- [F14] 형상 제약 — 서비스롤 직접 UPDATE도 상태 머신 밖으로 못 나간다 ----------
  -- These run as `postgres`, i.e. the service path. The RPCs are the intended door, but the ops
  -- script holds the service key and the SQL-editor runbook exists — the constraints are what make
  -- a typo there impossible rather than merely unlikely.
  begin
    v_a := false; v_b := false; v_c := false;
    begin update runner_applications set state = 'approved_lol' where id = app_k;
    exception when others then v_a := (sqlerrm like '%state_check%'); end;
    begin update runner_applications set state = 'approved', decided_at = now(), is_hard_bar = true
             where id = app_k;
    exception when others then v_b := (sqlerrm like '%runner_app_hard_bar_terminal%'); end;
    begin update runner_applications set decided_at = now() where id = app_k;
    exception when others then v_c := (sqlerrm like '%runner_app_decided_shape%'); end;
    select a.state into v_state from runner_applications a where a.id = app_k;
    if v_a and v_b and v_c and v_state = 'submitted'
      then call _pass('rf','F14 형상 제약 — 미지의 state·approved+hard_bar·submitted에 decided_at 전부 제약 위반');
    else call _fail('rf','F14 형상 제약',
           'state=' || coalesce(v_a::text,'∅') || ' hardbar=' || coalesce(v_b::text,'∅')
           || ' decided=' || coalesce(v_c::text,'∅') || ' 행상태=' || coalesce(v_state,'∅'));
    end if;
  exception when others then call _fail('rf','F14 형상 제약', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
