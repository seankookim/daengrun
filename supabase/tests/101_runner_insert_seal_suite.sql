-- ═══ 0061 P0 — runners INSERT seal ═══
-- What this pins: a client (role `authenticated`) can create their OWN runner row, but never with
-- privileged values. Before 0061, `runners self insert` (0002:71) checked only ownership and
-- `_guard_runner_cols` (0057) was `before update` only, so one free signup bought
-- tier=master + commission_rate=0 + identity_verified=true.
--
-- Style follows the 97/98/99/100 siblings: `_pass('seal',…)`/`_fail('seal',…)`, each case in its
-- own begin…exception when others, `set local role` for real RLS paths and always `reset role`.
-- Runs last in the harness, so 97's helpers exist; fixtures use a window disjoint from 95-100.
--
-- ─── MUTATION VERIFICATION (2026-08-08) ───
-- ✔ = actually executed this build (full harness re-run against a reverted 0061, then restored).
--   ✔ M1: trigger `before insert` → `before update` (restores the exact 0057 oversight)
--         → S1, S2, S3 RED. S1 reported `tier=master comm=0.000 idv=true funnel=certified
--         runs=999 km=9999.00` — the published attack reproduced verbatim under test.
--   ✔ M2: delete ONLY the `new.commission_rate := 0.20;` line
--         → S1, S2 RED with `tier=applicant comm=0.000` (everything else still coerced), which
--         is what proves S2 is independently load-bearing rather than riding on S1.
--   S4 is a positive control, so it has no revert: reverting 0061 leaves it GREEN by design —
--     the seal must never break legitimate signup.
--   S5, S6 are not mutation-verified in this build. S6 is covered by the existing
--     99_security_suite S4 pin for the UPDATE guard it re-asserts.

do $$
declare
  atk uuid; leg uuid;
  v_tier text; v_comm numeric; v_idv boolean; v_fs text; v_runs int; v_km numeric;
  v_n int;
begin
  atk := t_user('seal_atk', 'runner');
  leg := t_user('seal_leg', 'runner');

  -- ── S1: the exact published attack — self-INSERT with privileged values ──
  begin
    delete from runners where profile_id = atk;
    perform set_config('request.jwt.claim.sub', atk::text, false);
    set local role authenticated;
    insert into runners (profile_id, tier, funnel_step, identity_verified,
                         insurance_active, trainer_certified, commission_rate,
                         total_runs, total_km, respond_rate_pct)
    values (atk, 'master', 'certified', true, true, true, 0, 999, 9999, 100);
    reset role;
    select tier::text, commission_rate, identity_verified, funnel_step::text, total_runs, total_km
      into v_tier, v_comm, v_idv, v_fs, v_runs, v_km
      from runners where profile_id = atk;
    if v_tier = 'applicant' and v_comm = 0.20 and v_idv = false and v_fs = 'info'
       and v_runs = 0 and v_km = 0
      then call _pass('seal','S1 자가 등급 상승 봉인 — tier=master·commission=0·identity=true INSERT가 전부 기본값으로 강등');
    else call _fail('seal','S1 자가 등급 상승 봉인',
           'tier=' || coalesce(v_tier,'∅') || ' comm=' || coalesce(v_comm::text,'∅')
           || ' idv=' || coalesce(v_idv::text,'∅') || ' funnel=' || coalesce(v_fs,'∅')
           || ' runs=' || coalesce(v_runs::text,'∅') || ' km=' || coalesce(v_km::text,'∅'));
    end if;
  exception when others then reset role; call _fail('seal','S1 자가 등급 상승 봉인', sqlerrm);
  end;

  -- ── S2: payout theft specifically (commission_rate is what settle-run reads) ──
  begin
    delete from runners where profile_id = atk;
    perform set_config('request.jwt.claim.sub', atk::text, false);
    set local role authenticated;
    insert into runners (profile_id, commission_rate) values (atk, 0.000);
    reset role;
    select commission_rate into v_comm from runners where profile_id = atk;
    if v_comm = 0.20
      then call _pass('seal','S2 수수료율 봉인 — commission_rate=0 INSERT가 0.20으로 강등 (정산 절도 차단)');
    else call _fail('seal','S2 수수료율 봉인','commission_rate=' || coalesce(v_comm::text,'∅'));
    end if;
  exception when others then reset role; call _fail('seal','S2 수수료율 봉인', sqlerrm);
  end;

  -- ── S3: safety-claim forgery (identity_verified backs the owner-facing trust copy) ──
  begin
    delete from runners where profile_id = atk;
    perform set_config('request.jwt.claim.sub', atk::text, false);
    set local role authenticated;
    insert into runners (profile_id, identity_verified, trainer_certified, insurance_active)
    values (atk, true, true, true);
    reset role;
    select identity_verified into v_idv from runners where profile_id = atk;
    if v_idv = false
      then call _pass('seal','S3 신원·자격 위조 봉인 — identity_verified/trainer/insurance INSERT가 false로 강등');
    else call _fail('seal','S3 신원·자격 위조 봉인','identity_verified=' || coalesce(v_idv::text,'∅'));
    end if;
  exception when others then reset role; call _fail('seal','S3 신원·자격 위조 봉인', sqlerrm);
  end;

  -- ── S4: the seal must not have broken legitimate signup (api.ts ensureRunner payload verbatim) ──
  begin
    delete from runners where profile_id = leg;
    perform set_config('request.jwt.claim.sub', leg::text, false);
    set local role authenticated;
    insert into runners (profile_id, tier, funnel_step, avg_pace_sec_per_km, identity_verified, online)
    values (leg, 'applicant', 'info', 420, false, true);
    reset role;
    select count(*) into v_n from runners
      where profile_id = leg and tier = 'applicant' and online = true and avg_pace_sec_per_km = 420;
    if v_n = 1
      then call _pass('seal','S4 정상 가입 보존 — ensureRunner 페이로드 그대로 성공, online/페이스 등 비권한 열은 보존');
    else call _fail('seal','S4 정상 가입 보존','rows=' || coalesce(v_n::text,'∅'));
    end if;
  exception when others then reset role; call _fail('seal','S4 정상 가입 보존', sqlerrm);
  end;

  -- ── S5: service role is untouched (seed scripts / edge functions must still set real values) ──
  begin
    delete from runners where profile_id = atk;
    insert into runners (profile_id, tier, identity_verified, commission_rate)
    values (atk, 'certified', true, 0.15);   -- postgres 세션 = 서버 경로
    select tier::text, identity_verified, commission_rate into v_tier, v_idv, v_comm
      from runners where profile_id = atk;
    if v_tier = 'certified' and v_idv = true and v_comm = 0.15
      then call _pass('seal','S5 서버 경로 비간섭 — 서비스롤 INSERT는 실값 그대로 (승급 RPC·시드 스크립트 보존)');
    else call _fail('seal','S5 서버 경로 비간섭',
           'tier=' || coalesce(v_tier,'∅') || ' idv=' || coalesce(v_idv::text,'∅')
           || ' comm=' || coalesce(v_comm::text,'∅'));
    end if;
  exception when others then call _fail('seal','S5 서버 경로 비간섭', sqlerrm);
  end;

  -- ── S6: UPDATE guard still holds (0057 S4 sibling — the seal must not have displaced it) ──
  begin
    perform set_config('request.jwt.claim.sub', leg::text, false);
    set local role authenticated;
    begin
      update runners set tier = 'master' where profile_id = leg;
      reset role;
      call _fail('seal','S6 UPDATE 가드 잔존','authenticated가 tier UPDATE에 성공했다');
    exception when others then
      reset role;
      if sqlerrm like '%runner_protected_columns%'
        then call _pass('seal','S6 UPDATE 가드 잔존 — 0057 _guard_runner_cols는 그대로 (INSERT 봉인이 대체하지 않는다)');
      else call _fail('seal','S6 UPDATE 가드 잔존', sqlerrm);
      end if;
    end;
  exception when others then reset role; call _fail('seal','S6 UPDATE 가드 잔존', sqlerrm);
  end;

  delete from runners where profile_id in (atk, leg);
end $$;
