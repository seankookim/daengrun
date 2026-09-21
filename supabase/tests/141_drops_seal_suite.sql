-- ═══ 141 drops seal — 0106 pins (D1-D20) ═══
-- What this suite pins: a reward drop is a SERVER fact. `drops self open` (0002:131) was a bare
-- `for update using (runner_id = auth.uid())` — no WITH CHECK, no trigger — and `open-drop`
-- (service_role) reads `contents` off the row and pays it. Measured on the harness DB at 0105:
--   as authenticated: update drops set contents='{"miles":9999999}', opened_at=null → UPDATE 1.
-- After 0106 that statement is 42501 at the grant, would be an RLS deny without the grant, and
-- would be `drop_client_write` from the trigger without either (D17 proves the last one by
-- undoing §1 in-transaction).
-- ⚠ D8, D11, D14c, D15, D16e are POSITIVE CONTROLS: `open-drop`'s exact statements as service_role
--   must survive, or the seal has closed the reward system rather than the hole. Suite 10 D1/D2
--   separately keep the minter (`settle_run_tx`) honest.
-- ⚠ Refusal pins name the sqlstate they expect (42501 for the grant, P0001 for the trigger,
--   23514 for a CHECK). A 42703 or a bad fixture must NOT read as "the seal worked".
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
do $$
declare
  v_a uuid; v_b uuid;
  v_open uuid; v_unopened uuid; v_pick uuid; v_pick2 uuid; v_theirs uuid; v_gear uuid;
  v_msg text; v_bad text; v_n int; v_c jsonb; v_t timestamptz; v_txt text; v_id uuid;
begin
  v_a := gen_random_uuid(); v_b := gen_random_uuid();
  insert into auth.users(id,email) values (v_a,'d-a@t'),(v_b,'d-b@t');
  insert into profiles(id,role,name) values (v_a,'runner','D-a'),(v_b,'runner','D-b');
  insert into runners(profile_id) values (v_a),(v_b);
  -- minted as the owner, exactly the shapes settle_run_tx writes
  insert into drops(runner_id,kind,run_count_at,contents,opened_at)
    values (v_a,'mini',5,'{"miles":700}', now() - interval '1 day') returning id into v_open;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'mini',15,'{"miles":600,"card":"드랍 카드"}') returning id into v_unopened;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',10,'{"options":["boost","miles","gear"]}') returning id into v_pick;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_a,'pick',20,'{"options":["boost","miles","gear"]}') returning id into v_pick2;
  insert into drops(runner_id,kind,run_count_at,contents)
    values (v_b,'mini',5,'{"miles":800}') returning id into v_theirs;
  insert into gear_claims(profile_id,side,item,milestone,status)
    values (v_a,'runner','기어 교환권',5,'claimable') returning id into v_gear;

  perform set_config('request.jwt.claim.sub', v_a::text, true);

  -- ---------- [D1] THE EXPLOIT: rewrite contents on my own opened drop ----------
  v_bad := '';
  begin
    set local role authenticated;
    update drops set contents = '{"miles":9999999}' where id = v_open;
    v_bad := ' contents 덮어쓰기가 통과했다 (익스플로잇 그대로)';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  select contents into v_c from drops where id = v_open;
  if v_c <> '{"miles":700}'::jsonb then v_bad := v_bad || ' 행이 바뀌었다 ' || v_c::text; end if;
  if v_bad = '' then call _pass('dseal','D1 러너가 자기 드랍의 contents를 고칠 수 없다 — 42501, 행 그대로 (9,999,999 마일 익스플로잇 봉인)');
  else v_msg := v_bad; call _fail('dseal','D1 contents 덮어쓰기', v_msg); end if;

  -- ---------- [D2] re-arm: opened_at back to null ----------
  v_bad := '';
  begin
    set local role authenticated;
    update drops set opened_at = null where id = v_open;
    v_bad := ' opened_at 리셋이 통과했다';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ']'; end if;
  end;
  reset role;
  select opened_at into v_t from drops where id = v_open;
  if v_t is null then v_bad := v_bad || ' opened_at이 null이 됐다'; end if;
  if v_bad = '' then call _pass('dseal','D2 열린 드랍을 다시 잠글 수 없다 (opened_at → null 거부)');
  else v_msg := v_bad; call _fail('dseal','D2 opened_at 리셋', v_msg); end if;

  -- ---------- [D3] INSERT a drop for myself ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',20,'{"miles":5000}');
    v_bad := ' 러너가 드랍을 만들었다';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D3 러너가 드랍을 만들 수 없다 (INSERT 42501)');
  else v_msg := v_bad; call _fail('dseal','D3 INSERT', v_msg); end if;

  -- ---------- [D4] DELETE ----------
  v_bad := '';
  begin
    set local role authenticated;
    delete from drops where id = v_open;
    v_bad := ' 러너가 드랍을 지웠다';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ']'; end if;
  end;
  reset role;
  select count(*) into v_n from drops where id = v_open;
  if v_n <> 1 then v_bad := v_bad || ' 행이 사라졌다'; end if;
  if v_bad = '' then call _pass('dseal','D4 러너가 드랍을 지울 수 없다 (DELETE 42501)');
  else v_msg := v_bad; call _fail('dseal','D4 DELETE', v_msg); end if;

  -- ---------- [D5] upsert on id (the PostgREST `upsert` shape) ----------
  v_bad := '';
  begin
    set local role authenticated;
    insert into drops(id,runner_id,kind,run_count_at,contents)
      values (v_open,v_a,'mini',5,'{"miles":5000}')
      on conflict (id) do update set contents = excluded.contents, opened_at = null;
    v_bad := ' upsert가 통과했다';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ']'; end if;
  end;
  reset role;
  select contents into v_c from drops where id = v_open;
  if v_c <> '{"miles":700}'::jsonb then v_bad := v_bad || ' 행이 바뀌었다'; end if;
  if v_bad = '' then call _pass('dseal','D5 upsert(on conflict id)로도 못 바꾼다');
  else v_msg := v_bad; call _fail('dseal','D5 upsert', v_msg); end if;

  -- ---------- [D6] the grant law, read from the catalog ----------
  v_bad := '';
  if has_table_privilege('authenticated','public.drops','INSERT') then v_bad := v_bad || ' auth INSERT drops'; end if;
  if has_table_privilege('authenticated','public.drops','UPDATE') then v_bad := v_bad || ' auth UPDATE drops'; end if;
  if has_table_privilege('authenticated','public.drops','DELETE') then v_bad := v_bad || ' auth DELETE drops'; end if;
  if has_table_privilege('authenticated','public.drops','TRUNCATE') then v_bad := v_bad || ' auth TRUNCATE drops'; end if;
  if has_table_privilege('anon','public.drops','INSERT') or has_table_privilege('anon','public.drops','UPDATE')
     or has_table_privilege('anon','public.drops','DELETE') or has_table_privilege('anon','public.drops','TRUNCATE')
     then v_bad := v_bad || ' anon write drops'; end if;
  if has_table_privilege('authenticated','public.gear_claims','INSERT') or has_table_privilege('authenticated','public.gear_claims','UPDATE')
     or has_table_privilege('authenticated','public.gear_claims','DELETE') or has_table_privilege('authenticated','public.gear_claims','TRUNCATE')
     then v_bad := v_bad || ' auth write gear_claims'; end if;
  if has_table_privilege('anon','public.gear_claims','INSERT') or has_table_privilege('anon','public.gear_claims','UPDATE')
     or has_table_privilege('anon','public.gear_claims','DELETE') then v_bad := v_bad || ' anon write gear_claims'; end if;
  if not has_table_privilege('authenticated','public.drops','SELECT') then v_bad := v_bad || ' auth lost SELECT drops'; end if;
  if not has_table_privilege('authenticated','public.gear_claims','SELECT') then v_bad := v_bad || ' auth lost SELECT gear_claims'; end if;
  if exists (select 1 from pg_policy where polname in ('drops self open','gear self claim')) then v_bad := v_bad || ' 0002 write policy still present'; end if;
  -- (review F3) service_role: the four DML verbs and nothing structural
  if has_table_privilege('service_role','public.drops','TRIGGER') or has_table_privilege('service_role','public.gear_claims','TRIGGER')
     then v_bad := v_bad || ' service_role TRIGGER'; end if;
  if has_table_privilege('service_role','public.drops','TRUNCATE') or has_table_privilege('service_role','public.gear_claims','TRUNCATE')
     then v_bad := v_bad || ' service_role TRUNCATE'; end if;
  if has_table_privilege('service_role','public.drops','REFERENCES') or has_table_privilege('service_role','public.gear_claims','REFERENCES')
     then v_bad := v_bad || ' service_role REFERENCES'; end if;
  if not (has_table_privilege('service_role','public.drops','SELECT') and has_table_privilege('service_role','public.drops','INSERT')
          and has_table_privilege('service_role','public.drops','UPDATE') and has_table_privilege('service_role','public.gear_claims','INSERT'))
     then v_bad := v_bad || ' service_role lost a DML verb open-drop needs'; end if;
  if v_bad = '' then call _pass('dseal','D6 그랜트 법 — anon/authenticated는 drops·gear_claims에 SELECT뿐, 0002 쓰기 정책 없음; service_role은 DML 4종뿐(TRIGGER/TRUNCATE/REFERENCES 없음)');
  else v_msg := v_bad; call _fail('dseal','D6 그랜트', v_msg); end if;

  -- ---------- [D7] someone else's drop: write refused, read still own-only, own read alive ----------
  v_bad := '';
  begin
    set local role authenticated;
    update drops set contents = '{"miles":1}' where id = v_theirs;
    v_bad := ' 남의 드랍 UPDATE가 통과했다';
  exception when others then
    if sqlstate <> '42501' then v_bad := ' 그랜트가 아닌 이유로 실패했다 [' || sqlstate || ']'; end if;
  end;
  reset role;
  begin
    set local role authenticated;
    select count(*) into v_n from drops where id = v_theirs;
    if v_n <> 0 then v_bad := v_bad || ' 남의 드랍이 읽힌다'; end if;
    select count(*) into v_n from drops where runner_id = v_a;
    if v_n <> 4 then v_bad := v_bad || ' 내 드랍 read가 죽었다 (fetchDrops) n=' || v_n; end if;
    select count(*) into v_n from gear_claims where profile_id = v_a;
    if v_n <> 1 then v_bad := v_bad || ' 내 교환권 read가 죽었다 (fetchGearClaims)'; end if;
  exception when others then v_bad := v_bad || ' read가 예외 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D7 남의 드랍은 쓰기 42501·읽기 0행, 내 드랍/교환권 read(fetchDrops·fetchGearClaims)는 산다');
  else v_msg := v_bad; call _fail('dseal','D7 타인/읽기', v_msg); end if;

  -- ---------- [D8] POSITIVE CONTROL — open-drop's exact CAS UPDATE as service_role, once ----------
  v_bad := '';
  begin
    set local role service_role;
    with u as (update drops set opened_at = now(), pick_choice = null
                where id = v_unopened and opened_at is null returning id)
    select count(*) into v_n from u;
    if v_n <> 1 then v_bad := ' 첫 오픈이 ' || v_n || '행'; end if;
  exception when others then v_bad := ' open-drop의 CAS UPDATE가 막혔다 (보상 시스템이 죽었다) [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D8 양성 대조 — open-drop의 CAS UPDATE(opened_at null→now, pick_choice)는 service_role로 1행 통과');
  else v_msg := v_bad; call _fail('dseal','D8 open-drop CAS', v_msg); end if;

  -- ---------- [D9] service_role cannot rewrite contents after mint ----------
  v_bad := '';
  begin
    set local role service_role;
    update drops set contents = '{"miles":5000}' where id = v_unopened;
    v_bad := ' service_role의 contents 변경이 통과했다';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%drop_immutable_columns%' then v_bad := ' 트리거가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  select contents into v_c from drops where id = v_unopened;
  if v_c <> '{"miles":600,"card":"드랍 카드"}'::jsonb then v_bad := v_bad || ' 행이 바뀌었다'; end if;
  if v_bad = '' then call _pass('dseal','D9 service_role도 contents를 못 바꾼다 (트리거 drop_immutable_columns) — kind/runner_id/run_count_at 동급');
  else v_msg := v_bad; call _fail('dseal','D9 service_role contents', v_msg); end if;
  -- the sibling columns, one statement each, same arm
  v_bad := '';
  begin
    set local role service_role;
    update drops set runner_id = v_b where id = v_unopened;
    v_bad := ' runner_id 변경 통과';
  exception when others then if sqlstate <> 'P0001' then v_bad := ' [' || sqlstate || ']'; end if; end;
  reset role;
  begin
    set local role service_role;
    update drops set run_count_at = 999 where id = v_unopened;
    v_bad := v_bad || ' run_count_at 변경 통과';
  exception when others then if sqlstate <> 'P0001' then v_bad := v_bad || ' [' || sqlstate || ']'; end if; end;
  reset role;
  begin
    set local role service_role;
    update drops set kind = 'pick' where id = v_unopened;
    v_bad := v_bad || ' kind 변경 통과';
  exception when others then if sqlstate not in ('P0001','23514') then v_bad := v_bad || ' [' || sqlstate || ']'; end if; end;
  reset role;
  if v_bad = '' then call _pass('dseal','D9b runner_id·run_count_at·kind도 mint 뒤 불변');
  else v_msg := v_bad; call _fail('dseal','D9b 형제 컬럼', v_msg); end if;

  -- ---------- [D10] service_role cannot re-arm: opened_at → null ----------
  v_bad := '';
  begin
    set local role service_role;
    update drops set opened_at = null where id = v_unopened;
    v_bad := ' service_role의 opened_at 리셋이 통과했다';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%drop_already_opened%' then v_bad := ' 트리거가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  select opened_at into v_t from drops where id = v_unopened;
  if v_t is null then v_bad := v_bad || ' opened_at이 null이 됐다'; end if;
  if v_bad = '' then call _pass('dseal','D10 service_role도 열린 드랍을 다시 잠글 수 없다 (opened_at → null: drop_already_opened) — 소유자(postgres)만 예외');
  else v_msg := v_bad; call _fail('dseal','D10 service_role 리셋', v_msg); end if;

  -- ---------- [D11] the CAS two-step: second identical statement is 0 rows ----------
  v_bad := '';
  begin
    set local role service_role;
    with u as (update drops set opened_at = now(), pick_choice = null
                where id = v_unopened and opened_at is null returning id)
    select count(*) into v_n from u;
    if v_n <> 0 then v_bad := ' 두 번째 CAS가 ' || v_n || '행 (이중 오픈)'; end if;
  exception when others then v_bad := ' 두 번째 CAS가 예외 — 0행이어야 한다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D11 CAS 두 단계 — 같은 UPDATE … where opened_at is null을 두 번: 1행 뒤 0행 (open-drop의 이중 적립 방지 패턴)');
  else v_msg := v_bad; call _fail('dseal','D11 CAS', v_msg); end if;

  -- ---------- [D12] WITHOUT the CAS predicate: a re-stamp on an opened row RAISES ----------
  -- This is the property the trigger adds over the edge function: lose the `.is('opened_at',
  -- null)` and the second open is still refused, by the table.
  v_bad := '';
  begin
    set local role service_role;
    update drops set opened_at = now() + interval '1 second' where id = v_unopened;
    v_bad := ' 열린 드랍의 재도장이 통과했다 (CAS 없이 두 번 열린다)';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%drop_already_opened%' then v_bad := ' 트리거가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role service_role;
    update drops set pick_choice = 'miles' where id = v_unopened;
    v_bad := v_bad || ' 열린 드랍의 pick_choice 변경이 통과했다';
  exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' [' || sqlstate || ']'; end if;
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D12 CAS 술어 없이도 열린 드랍은 재도장·pick_choice 변경 불가 (drop_already_opened) — 씰이 엣지 습관이 아니라 테이블 성질');
  else v_msg := v_bad; call _fail('dseal','D12 재도장', v_msg); end if;

  -- ---------- [D13] CHECK: contents shape (as the owner — a CHECK binds every role) ----------
  v_bad := '';
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":-1}');
        v_bad := v_bad || ' 음수 miles 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 음수[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":5001}');
        v_bad := v_bad || ' 상한 초과 miles 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 상한[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":9999999}');
        v_bad := v_bad || ' 9,999,999 miles 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 9999999[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":12.5}');
        v_bad := v_bad || ' 소수 miles 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 소수[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":"abc"}');
        v_bad := v_bad || ' 문자열 miles 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 문자열miles[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'5');
        v_bad := v_bad || ' 비객체 contents 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 비객체[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'[1,2]');
        v_bad := v_bad || ' 배열 contents 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 배열[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":5,"bonus":99999}');
        v_bad := v_bad || ' 미허용 키 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 미허용키[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"miles":5,"gear":123}');
        v_bad := v_bad || ' 비문자열 gear 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' gear타입[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,jsonb_build_object('miles',5,'card',repeat('x',41)));
        v_bad := v_bad || ' 긴 card 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' card길이[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'pick',30,'{"miles":5000}');
        v_bad := v_bad || ' miles 든 pick 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' pick+miles[' || sqlstate || ']'; end if; end;
  begin insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',25,'{"options":["boost"]}');
        v_bad := v_bad || ' options 든 mini 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' mini+options[' || sqlstate || ']'; end if; end;
  if v_bad = '' then call _pass('dseal','D13 CHECK contents — 음수·>5000·9,999,999·소수·문자열 miles·비객체·배열·미허용 키·비문자열 gear·41자 card·kind 교차 전부 23514');
  else v_msg := v_bad; call _fail('dseal','D13 CHECK', v_msg); end if;

  -- D13b POSITIVE CONTROL — the minter's shapes still insert (mini+card, mini+gear, mini bare at
  -- the top of its range, pick)
  v_bad := '';
  begin
    insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',35,'{"miles":1199,"gear":"기어 교환권"}');
    insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',40,'{"miles":500,"card":"드랍 카드"}');
    insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'mini',45,'{"miles":0}');
    insert into drops(runner_id,kind,run_count_at,contents) values (v_a,'pick',50,'{"options":["boost","miles","gear"]}');
  exception when others then v_bad := ' 민트 형상이 거부됐다 (settle_run_tx가 죽는다) [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  if v_bad = '' then call _pass('dseal','D13b 양성 대조 — settle_run_tx의 네 민트 형상은 통과');
  else v_msg := v_bad; call _fail('dseal','D13b 민트 형상', v_msg); end if;

  -- ---------- [D14] CHECK: pick_choice ----------
  v_bad := '';
  begin update drops set pick_choice = 'nonsense' where id = v_unopened;   -- owner: trigger exempt, CHECK not
        v_bad := v_bad || ' 임의 pick_choice 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 임의[' || sqlstate || ']'; end if; end;
  begin update drops set pick_choice = 'boost' where id = v_pick;          -- unopened + choice
        v_bad := v_bad || ' 안 연 드랍에 pick_choice 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 미오픈[' || sqlstate || ']'; end if; end;
  -- D14c positive: open-drop's pick arm — stamp + choice in one statement, as service_role
  begin
    set local role service_role;
    with u as (update drops set opened_at = now(), pick_choice = 'boost'
                where id = v_pick and opened_at is null returning id)
    select count(*) into v_n from u;
    if v_n <> 1 then v_bad := v_bad || ' pick 오픈이 ' || v_n || '행'; end if;
  exception when others then v_bad := v_bad || ' pick 오픈이 막혔다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D14 pick_choice CHECK — 세 값 밖 23514·안 연 드랍엔 불가; open-drop의 pick 오픈(도장+선택 한 문장)은 통과');
  else v_msg := v_bad; call _fail('dseal','D14 pick_choice', v_msg); end if;

  -- ---------- [D15] POSITIVE CONTROL — open-drop's gear_claims INSERT as service_role ----------
  v_bad := '';
  begin
    set local role service_role;
    insert into gear_claims(profile_id,side,item,milestone,status) values (v_a,'runner','기어 교환권',15,'claimable');
  exception when others then v_bad := ' open-drop의 gear_claims INSERT가 막혔다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('dseal','D15 양성 대조 — open-drop의 gear_claims INSERT(service_role)는 통과');
  else v_msg := v_bad; call _fail('dseal','D15 gear INSERT', v_msg); end if;

  -- ---------- [D16] gear_claims: client sealed, service_role identity frozen, fulfilment open ----------
  v_bad := '';
  begin
    set local role authenticated;
    update gear_claims set status = 'shipped', item = '맥북' where id = v_gear;
    v_bad := ' 러너가 교환권을 고쳤다';
  exception when others then if sqlstate <> '42501' then v_bad := ' [' || sqlstate || ']'; end if; end;
  reset role;
  begin
    set local role authenticated;
    insert into gear_claims(profile_id,side,item,milestone,status) values (v_a,'runner','맥북',1,'claimable');
    v_bad := v_bad || ' 러너가 교환권을 만들었다';
  exception when others then if sqlstate <> '42501' then v_bad := v_bad || ' ins[' || sqlstate || ']'; end if; end;
  reset role;
  begin
    set local role authenticated;
    delete from gear_claims where id = v_gear;
    v_bad := v_bad || ' 러너가 교환권을 지웠다';
  exception when others then if sqlstate <> '42501' then v_bad := v_bad || ' del[' || sqlstate || ']'; end if; end;
  reset role;
  select item into v_txt from gear_claims where id = v_gear;
  if v_txt <> '기어 교환권' then v_bad := v_bad || ' item이 바뀌었다'; end if;
  -- service_role: item frozen (trigger), status writable (fulfilment)
  begin
    set local role service_role;
    update gear_claims set item = '맥북' where id = v_gear;
    v_bad := v_bad || ' service_role이 item을 바꿨다';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%gear_claim_immutable_columns%' then v_bad := v_bad || ' item[' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  begin
    set local role service_role;
    update gear_claims set status = 'shipped', claimed_at = now() where id = v_gear;
  exception when others then v_bad := v_bad || ' service_role의 status 처리(이행 경로)가 막혔다 [' || sqlstate || ']'; end;
  reset role;
  -- (review F2) item length CHECK, both ends, as the writer that actually inserts (service_role)
  begin
    set local role service_role;
    insert into gear_claims(profile_id,side,item,milestone,status) values (v_a,'runner',repeat('x',81),16,'claimable');
    v_bad := v_bad || ' 81자 item 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 81자[' || sqlstate || ']'; end if; end;
  reset role;
  begin
    set local role service_role;
    insert into gear_claims(profile_id,side,item,milestone,status) values (v_a,'runner','',17,'claimable');
    v_bad := v_bad || ' 빈 item 통과';
  exception when others then if sqlstate <> '23514' then v_bad := v_bad || ' 빈item[' || sqlstate || ']'; end if; end;
  reset role;
  if v_bad = '' then call _pass('dseal','D16 gear_claims — 러너는 I/U/D 전부 42501; service_role은 item/milestone/profile_id 불변, status/shipped_to/claimed_at은 처리 가능; item 81자·빈 문자열 23514');
  else v_msg := v_bad; call _fail('dseal','D16 gear_claims', v_msg); end if;

  -- ---------- [D17] THE BELT: undo §1 in-transaction, the trigger alone still refuses ----------
  -- 123 S-probe shape: re-grant + a permissive policy, attempt the exploit, expect the trigger's
  -- own raise (P0001 drop_client_write), then take both away again.
  v_bad := '';
  grant update on drops to authenticated;
  create policy "drops _tmp_141" on drops for update using (runner_id = auth.uid());
  begin
    set local role authenticated;
    update drops set contents = '{"miles":9999999}', opened_at = null where id = v_open;
    v_bad := ' 그랜트+정책을 되돌리자 익스플로잇이 통과했다 — 트리거 벨트가 없다';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%drop_client_write%' then v_bad := ' 트리거가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  drop policy "drops _tmp_141" on drops;
  revoke update on drops from authenticated;
  select contents into v_c from drops where id = v_open;
  if v_c <> '{"miles":700}'::jsonb then v_bad := v_bad || ' 행이 바뀌었다'; end if;
  if v_bad = '' then call _pass('dseal','D17 벨트 — §1을 되돌려도(재그랜트+허용 정책) 트리거가 drop_client_write로 거부');
  else v_msg := v_bad; call _fail('dseal','D17 벨트', v_msg); end if;

  -- ---------- [D18] the owner exemption exists and is the ONLY repair path ----------
  -- Documented decision (0106 §3): a wrongly-stamped drop is repaired by the table owner in the
  -- SQL editor, never by service_role. Pin that the door is where the header says it is.
  v_bad := '';
  begin
    update drops set opened_at = null, pick_choice = null where id = v_unopened;   -- as postgres (owner)
    select opened_at into v_t from drops where id = v_unopened;
    if v_t is not null then v_bad := ' 소유자 리셋이 반영되지 않았다'; end if;
    update drops set opened_at = now() where id = v_unopened;   -- restore
  exception when others then v_bad := ' 소유자(postgres)의 수리 경로가 막혔다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  if v_bad = '' then call _pass('dseal','D18 소유자(postgres)만 opened_at을 되돌릴 수 있다 — 운영 수리 경로는 SQL 에디터, API가 아니다');
  else v_msg := v_bad; call _fail('dseal','D18 소유자 예외', v_msg); end if;

  -- ---------- [D19] (review F1) catalog sweep — no client-callable function touches drops/gear_claims ----------
  -- 98 H1 idiom. A SECURITY DEFINER granted to authenticated runs as the owner, and D18 is the
  -- owner's door. So the door is only safe while no such function exists; this pin watches the
  -- whole schema for one. Comments are stripped first: 'drops' is an English verb in two
  -- unrelated definers' comments (incident_contact, _club_incident_can_open — measured), and a
  -- sweep that reads prose is a sweep nobody trusts. The regex is proven non-vacuous on
  -- settle_run_tx (owner-only, the minter) in the same pin.
  -- ⚠ [0176] THE FIRST ALLOWLISTED ENTRY, and it is the door F1 designed the service tier FOR,
  -- not an exception to it: `open_drop_tx(uuid, text)` (0176, backend audit H2) is a definer
  -- granted to authenticated whose body reads and CAS-stamps `drops` and inserts `gear_claims`.
  -- Called through PostgREST it is judged at the service tier (D19b): it can stamp opened_at
  -- ONCE, write pick_choice in that same statement, and nothing else — which is what the trigger
  -- exists to allow. What the function may DO is pinned by suite 207 (0176-O1…O6).
  --
  -- ⚠ [0195] THREE MORE ENTRIES, and this is a pinned behaviour that LEGITIMATELY CHANGED — not
  -- a drive-by widening. 0106 §4's own comment says `status`/`shipped_to`/`claimed_at` stay
  -- writable "because a future ops flow will need them"; 0195 is that flow, so the fulfilment
  -- door finally exists and this sweep must name it rather than go red for a true reason:
  --   · `claim_gear_tx(...)`          — the runner redeems their OWN claim (party gate on the
  --                                     locked row, before any state is read)
  --   · `ops_gear_claims_pending()`   — the ops read of claimed-not-shipped rows
  --   · `ops_mark_gear_shipped(...)`  — the ops write, claimed → shipped
  -- All three are `authenticated`-granted because the gate is INSIDE (the runner's own-row gate,
  -- and 0084 §E's ops roster) — the same shape 0186 §F uses. **What each may DO is pinned by
  -- suite 226 (0195-C1…C5 · P1…P3 · S1); this sweep's own property is unchanged** — it still
  -- asserts that NOTHING OUTSIDE this list of four has that shape.
  --
  -- ⚠ Every entry carries a LIVENESS arm below (exists · authenticated-executable · anon-refused ·
  -- actually touches the tables), because a dead allowlist entry is a false green: it silently
  -- absorbs the day someone drops the function and recreates it with a different ACL (98 H9's
  -- two-sided rule). Adding a fifth name here is a finding, not a fix.
  v_bad := '';
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and not exists (select 1 from (values
            ('open_drop_tx',            'p_drop_id uuid, p_pick_choice text'),
            ('claim_gear_tx',           'p_claim_id uuid, p_recipient text, p_phone text, p_address1 text, p_address2 text, p_postal text'),
            ('ops_gear_claims_pending', ''),
            ('ops_mark_gear_shipped',   'p_claim_id uuid, p_carrier text, p_tracking text')
          ) as a(nm, args)
          where a.nm = p.proname and a.args = pg_get_function_identity_arguments(p.oid))
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') ~* ('\m(public\.)?(drops|gear_claims)\M')
     and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  if v_n <> 0 then v_bad := ' 클라가 실행할 수 있는 함수 ' || v_n || '개가 drops/gear_claims를 만진다 (D18의 문이 API가 된다; 허용 항목은 open_drop_tx(0176) + 0195의 세 문뿐)'; end if;
  -- liveness: EVERY allowlist entry must be alive, and the count must be the WHOLE list — an
  -- entry that stopped existing, lost its authenticated grant, gained an anon grant, or stopped
  -- touching these tables is a dead entry, and a dead entry is a false green.
  select count(*) into v_n
    from (values
           ('open_drop_tx',            'p_drop_id uuid, p_pick_choice text'),
           ('claim_gear_tx',           'p_claim_id uuid, p_recipient text, p_phone text, p_address1 text, p_address2 text, p_postal text'),
           ('ops_gear_claims_pending', ''),
           ('ops_mark_gear_shipped',   'p_claim_id uuid, p_carrier text, p_tracking text')
         ) as a(nm, args)
    join pg_proc p on p.proname = a.nm
                  and pg_get_function_identity_arguments(p.oid) = a.args
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') ~* ('\m(public\.)?(drops|gear_claims)\M');
  if v_n <> 4 then v_bad := v_bad || ' 허용 항목 4개 중 살아 있는 것이 ' || v_n || '개 (없거나·authenticated 실행 불가·anon 실행 가능·drops/gear_claims를 안 만짐) — 죽은 허용 항목은 거짓 초록이다'; end if;
  select count(*) into v_n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'settle_run_tx'
     and regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') ~* ('\m(public\.)?(drops|gear_claims)\M');
  if v_n <> 1 then v_bad := v_bad || ' 스윕 정규식이 settle_run_tx(민터)를 못 본다 — 스윕이 공허하다'; end if;
  if v_bad = '' then call _pass('dseal','D19 카탈로그 스윕 — anon/authenticated가 실행 가능한 public 함수 중 drops/gear_claims를 참조하는 것은 허용 항목 네 개(open_drop_tx 0176 · claim_gear_tx · ops_gear_claims_pending · ops_mark_gear_shipped 0195)뿐이고 넷 다 살아 있다 (민터 settle_run_tx는 보이되 owner-only)');
  else v_msg := v_bad; call _fail('dseal','D19 카탈로그 스윕', v_msg); end if;

  -- ---------- [D19b] (review F1) owner + client JWT = service_role tier ----------
  -- What a definer called through PostgREST looks like from inside the trigger: current_user is
  -- the owner, request.jwt.claim.role is 'authenticated'. The exemption must not fire.
  v_bad := '';
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    update drops set contents = '{"miles":5000}' where id = v_open;   -- as postgres, JWT role = authenticated
    v_bad := ' 소유자+클라 JWT로 contents가 바뀌었다 (definer RPC 경로가 열려 있다)';
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm not like '%drop_immutable_columns%' then v_bad := ' 트리거가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  begin
    update drops set opened_at = null where id = v_open;
    v_bad := v_bad || ' 소유자+클라 JWT로 opened_at이 리셋됐다';
  exception when others then
    if sqlstate <> 'P0001' then v_bad := v_bad || ' [' || sqlstate || ']'; end if;
  end;
  perform set_config('request.jwt.claim.role', '', true);
  select contents into v_c from drops where id = v_open;
  if v_c <> '{"miles":700}'::jsonb then v_bad := v_bad || ' 행이 바뀌었다'; end if;
  if v_bad = '' then call _pass('dseal','D19b 소유자라도 요청에 클라 JWT(authenticated)가 실리면 service_role 등급 — contents 불변·opened_at 리셋 불가 (미래의 definer RPC 봉인)');
  else v_msg := v_bad; call _fail('dseal','D19b 소유자+JWT', v_msg); end if;

  -- ---------- [D20] (review F5) a pick drop cannot be stamped without a choice ----------
  v_bad := '';
  begin
    set local role service_role;
    update drops set opened_at = now(), pick_choice = null where id = v_pick2 and opened_at is null;
    v_bad := ' 선택 없는 pick 오픈이 통과했다 (수리 불가한 태운 드랍)';
  exception when others then
    if sqlstate <> '23514' or sqlerrm not like '%drops_pick_opened_has_choice%' then v_bad := ' CHECK가 아닌 이유로 실패했다 [' || sqlstate || ' ' || sqlerrm || ']'; end if;
  end;
  reset role;
  select opened_at into v_t from drops where id = v_pick2;
  if v_t is not null then v_bad := v_bad || ' 행이 열렸다'; end if;
  if v_bad = '' then call _pass('dseal','D20 pick 드랍은 pick_choice 없이 도장 불가 (23514, 행은 안 열린 채) — open-drop의 실제 pick 경로(D14c)와 mini 경로(D8)는 그대로');
  else v_msg := v_bad; call _fail('dseal','D20 pick 무선택 오픈', v_msg); end if;
end $$;
