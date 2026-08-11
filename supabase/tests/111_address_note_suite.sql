-- ═══ 111 address-note suite — 0073 pins (owner_update_address_detail) ═══
-- Purpose: `addresses` is the one owner-owned table a client can now write through a definer.
--   What must hold is not "the note saves" but "**nothing else** saves". These pins are mostly
--   about the columns that must NOT move.
-- Style: sibling of 105-110 — `_pass('addr',…)` / `_fail('addr',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law:
--   `call _fail(…, (select …))` raises `cannot use subquery in CALL argument`, fires only on the
--   failure path so it sits green forever, and when it does fire it unwinds the pin's begin…end
--   and rolls back the fixture that pin already wrote).
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   N1 ← 0073: delete the `update addresses set detail …` statement (function becomes a no-op) → RED
--   N2 ← 0073: drop the `not exists (… owner_id = auth.uid())` party gate                      → RED
--   N3 ← 0073: make the absent-id path raise a different string than the foreign-id path
--        (e.g. `raise exception 'not_found'` when the row does not exist)                      → RED
--   N4 ← 0073: drop `nullif(btrim(...), '')` — empty text lands as '' instead of NULL          → RED
--   N5 ← 0073: drop the `char_length > 60` cap                                                 → RED
--   N6 ← 0073: widen the update to another column, e.g. `set detail = …, addr = …`             → RED
--   N7 ← 0073: `grant execute … to public` (or drop the revoke)                                → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-12 (restore → 343/0 every time). Measured,
--     not predicted — each line below is an observed run:
--       MUT N6 (update also writes addr)  → 342/1, red = [N6]  ← clean single
--       MUT N5 (drop the 60-char cap)     → 342/1, red = [N5]  ← clean single
--       MUT N2 (drop the party gate)      → 341/2, red = [N2, N3]
--       MUT N4 (drop nullif/btrim)        → 341/2, red = [N1, N4]
--       MUT N1 (delete the update stmt)   → 340/3, red = [N1, N4, N5]
--       MUT N7 (grant execute to public)  → 341/2, red = [N7, **99 S1**]
--     The cascades are correct, not sloppy: N3 compares the absent-id and foreign-id errors, so
--     deleting the gate (which removes BOTH errors) genuinely breaks it; N1 asserts the trim, so
--     removing nullif/btrim genuinely breaks it; and a no-op function fails every pin that
--     asserts a write landed. N7's revert also trips the standing 99 S1 anon-execute sweep —
--     defense in depth working, and worth knowing this suite is not the only thing watching.
--
--   🔎 Found while mutating, worth keeping: MUT N2 removed the party gate and N2 still reported
--     the victim's note UNCHANGED (`detail=남의 메모`). The `update … where id = p_address and
--     owner_id = auth.uid()` clause is a **second, independent** guard — the gate controls the
--     error, the WHERE controls the write. Do not delete the redundant-looking `owner_id` in that
--     UPDATE thinking the gate above already covers it; it is the one that actually stops the row.
--
--   N6 is the pin that carries this migration's whole argument. The threat here was never a
--   cross-tenant read — the RLS policy is row-scoped and correct. It is that a write path onto a
--   table referenced by `bookings.address_id` could move `addr` while leaving `lat/lng`, which
--   renders a **falsely pinned address on a handoff screen**. N6 is what makes "note only" a
--   fact instead of a comment.
--
-- 🔴 What these pins deliberately do NOT assert: that `addresses` is sealed. It is not. Broad
--   UPDATE is still granted to `authenticated` (no column grants for this table exist anywhere in
--   the repo) — a pre-existing hole, logged P1 in TODOS, with its own slice. A pin claiming the
--   table is sealed would be the most dangerous kind of green.

do $$
declare
  oo uuid; oz uuid;
  a_mine uuid; a_other uuid; a_ghost uuid := gen_random_uuid();
  v_detail text; v_addr text; v_label text; v_lat numeric; v_lng numeric; v_gate text; v_dflt boolean;
  v_err_foreign text; v_err_ghost text; v_msg text; v_n int;
begin
  -- ---------- seed ----------
  oo := t_user('addr_oo', 'owner');
  oz := t_user('addr_oz', 'owner');
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng, is_default)
    values (oo, '집', '서초구 신반포로 275', '1층 로비에서 인계', 'ENC_DO_NOT_TOUCH', 37.512203, 126.996087, true)
    returning id into a_mine;
  insert into addresses (owner_id, label, addr, detail)
    values (oz, '남의집', '성동구 뚝섬로 273', '남의 메모')
    returning id into a_other;

  perform set_config('request.jwt.claim.sub', oo::text, false);

  -- ---------- [N1] 주인은 자기 메모를 고칠 수 있다 ----------
  begin
    perform owner_update_address_detail(a_mine, '  공동현관 #1204 눌러주세요  ');
    select detail into v_detail from addresses where id = a_mine;
    if v_detail = '공동현관 #1204 눌러주세요'
      then call _pass('addr','N1 메모 수정 + 트림 — 주인이 자기 픽업 메모를 바꾼다');
      else v_msg := 'detail=' || coalesce(v_detail, '<null>'); call _fail('addr','N1 메모 수정', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N1', v_msg);
  end;

  -- ---------- [N6] **오직 detail만 움직인다** — 이 마이그레이션의 핵심 주장 ----------
  begin
    select addr, label, lat, lng, gate_code_enc, is_default
      into v_addr, v_label, v_lat, v_lng, v_gate, v_dflt
      from addresses where id = a_mine;
    if v_addr = '서초구 신반포로 275' and v_label = '집'
       and v_lat = 37.512203 and v_lng = 126.996087
       and v_gate = 'ENC_DO_NOT_TOUCH' and v_dflt
      then call _pass('addr','N6 컬럼 화이트리스트 — addr/label/lat/lng/gate/default 전부 불변');
      else
        v_msg := 'addr=' || v_addr || ' label=' || v_label
              || ' lat=' || coalesce(v_lat::text,'<null>') || ' lng=' || coalesce(v_lng::text,'<null>')
              || ' gate=' || coalesce(v_gate,'<null>') || ' default=' || v_dflt::text;
        call _fail('addr','N6 컬럼 누수', v_msg);
      end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N6', v_msg);
  end;

  -- ---------- [N2] 남의 주소는 못 고친다 + 원본이 그대로다 ----------
  begin
    begin
      perform owner_update_address_detail(a_other, '내가 남의 메모를 바꾼다');
      v_err_foreign := '<no error>';
    exception when others then v_err_foreign := sqlerrm;
    end;
    select detail into v_detail from addresses where id = a_other;
    if v_err_foreign like '%not_owner%' and v_detail = '남의 메모'
      then call _pass('addr','N2 타인 주소 거절 — not_owner, 원본 불변');
      else v_msg := 'err=' || v_err_foreign || ' detail=' || coalesce(v_detail,'<null>');
           call _fail('addr','N2 타인 주소', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N2', v_msg);
  end;

  -- ---------- [N3] 없는 id와 남의 id가 **같은 문장** (열거 오라클 차단) ----------
  begin
    begin
      perform owner_update_address_detail(a_ghost, '유령');
      v_err_ghost := '<no error>';
    exception when others then v_err_ghost := sqlerrm;
    end;
    if v_err_ghost = v_err_foreign and v_err_ghost like '%not_owner%'
      then call _pass('addr','N3 부재 = 타인 — 같은 예외 문자열 (열거 오라클 없음)');
      else v_msg := 'ghost=' || v_err_ghost || ' foreign=' || coalesce(v_err_foreign,'<null>');
           call _fail('addr','N3 오라클 누수', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N3', v_msg);
  end;

  -- ---------- [N4] 빈 문자열은 NULL로 접힌다 ('' 와 NULL이 두 가지 '메모 없음'이 되면 안 된다) ----------
  begin
    perform owner_update_address_detail(a_mine, '    ');
    select detail into v_detail from addresses where id = a_mine;
    if v_detail is null
      then call _pass('addr','N4 공백 메모 → NULL — 러너 화면이 빈 구분자를 그리지 않는다');
      else v_msg := 'detail=[' || v_detail || ']'; call _fail('addr','N4 빈 문자열 잔존', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N4', v_msg);
  end;

  -- ---------- [N5] 60자 초과 거절 + 기존 값 불변 ----------
  begin
    perform owner_update_address_detail(a_mine, '경비실에 맡겨주세요');
    begin
      perform owner_update_address_detail(a_mine, repeat('가', 61));
      v_msg := '<no error>';
    exception when others then v_msg := sqlerrm;
    end;
    select detail into v_detail from addresses where id = a_mine;
    if v_msg like '%detail_too_long%' and v_detail = '경비실에 맡겨주세요'
      then call _pass('addr','N5 60자 초과 거절 — 주소 줄이 화면 밖으로 밀리지 않는다');
      else v_msg := 'err=' || v_msg || ' detail=' || coalesce(v_detail,'<null>');
           call _fail('addr','N5 길이 상한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N5', v_msg);
  end;

  -- ---------- [N7] 익명에게 실행 권한이 없다 ----------
  begin
    select count(*) into v_n
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'owner_update_address_detail'
        and (has_function_privilege('anon',   p.oid, 'execute')
          or has_function_privilege('public', p.oid, 'execute'));
    if v_n = 0
      then call _pass('addr','N7 anon/public 실행 불가 — authenticated 전용');
      else v_msg := 'anon 또는 public이 실행 가능 (n=' || v_n || ')'; call _fail('addr','N7 권한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('addr','N7', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
