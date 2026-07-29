-- ═══ 0032: 클럽 수요 보드 (P-B, Sean 확정 — R1-A 티켓 · R1-C 스트립 · D-A 진행 링 + 동네 리그) ═══
-- 듀얼 수요 보드의 단일 데이터 소스. 원칙 유지: 유령 클럽 금지 — collecting은 '대기 팀 수'로만
-- 표현하고, 실적(sessionsMonth/teamsMonth)은 done 세션의 실데이터만 집계한다.
-- 랭킹: active(이달 done 세션 수 → 체크인 팀 수) 우선, collecting은 관심 수 순.

create or replace function club_demand_board() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_district text;
  v_mine jsonb;
  v_league jsonb;
begin
  -- 내 동네 (profiles.district, 미설정이면 파일럿 동네 폴백)
  select nullif(trim(coalesce(district, '')), '') into v_district
  from profiles where id = auth.uid();
  v_district := coalesce(v_district, '반포동');

  -- 내 동네 클럽 1개 (공식 우선) — threshold 10팀 = 호스트 모집 시작 기준 (프로덕트 상수)
  select jsonb_build_object(
    'clubId', c.id, 'name', c.name, 'district', c.district, 'status', c.status,
    'interestCount', (select count(*) from club_interest where club_id = c.id),
    'threshold', 10,
    'myInterest', exists (select 1 from club_interest where club_id = c.id and profile_id = auth.uid()),
    'isHost', exists (select 1 from club_members m
                      where m.club_id = c.id and m.profile_id = auth.uid() and m.role = 'host')
  ) into v_mine
  from clubs c
  where c.district = v_district
  order by (c.kind = 'official') desc, c.created_at
  limit 1;

  -- 동네 리그 (최대 8) — 이달 실적 랭킹. 노이즈 컷: active도 아니고 관심도 0이고 내 동네도 아니면 제외
  select coalesce(jsonb_agg(jsonb_build_object(
    'clubId', y.id, 'name', y.name, 'district', y.district, 'status', y.status,
    'sessionsMonth', y.sessions, 'teamsMonth', y.teams, 'interestCount', y.cnt,
    'mine', y.district = v_district
  ) order by y.rn), '[]'::jsonb) into v_league
  from (
    select c.id, c.name, c.district, c.status, st.sessions, st.teams, ic.cnt,
      row_number() over (
        order by (c.status = 'active') desc, st.sessions desc, st.teams desc, ic.cnt desc, c.created_at
      ) as rn
    from clubs c
    cross join lateral (
      select count(*)::int as sessions,
             coalesce(sum((select count(*) from session_people sp
                           where sp.session_id = s.id and sp.attendance = 'checked_in')), 0)::int as teams
      from club_sessions s
      where s.club_id = c.id and s.status = 'done'
        and s.scheduled_at >= date_trunc('month', now())
    ) st
    cross join lateral (
      select count(*)::int as cnt from club_interest where club_id = c.id
    ) ic
    where c.status = 'active' or ic.cnt > 0 or c.district = v_district
    order by rn
    limit 8
  ) y;

  return jsonb_build_object('district', v_district, 'mine', v_mine, 'league', v_league);
end $$;

grant execute on function club_demand_board() to authenticated;
comment on function club_demand_board is
  '듀얼 수요 보드 (0032) — 내 동네 대기 현황(mine) + 동네 리그(이달 done 세션 실데이터 랭킹). 유령 클럽 금지 원칙 유지';
