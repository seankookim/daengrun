-- ═══ 141 drops seal — 0106 pins (D1-D18) ═══
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
  v_open uuid; v_unopened uuid; v_pick uuid; v_theirs uuid; v_gear uuid;
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
  if v_bad = '' then call _pass('dseal','D6 그랜트 법 — anon/authenticated는 drops·gear_claims에 SELECT뿐, 0002 쓰기 정책 없음');
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
    if v_n <> 3 then v_bad := v_bad || ' 내 드랍 read가 죽었다 (fetchDrops) n=' || v_n; end if;
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
  if v_bad = '' then call _pass('dseal','D16 gear_claims — 러너는 I/U/D 전부 42501; service_role은 item/milestone/profile_id 불변, status/shipped_to/claimed_at은 처리 가능');
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
end $$;
