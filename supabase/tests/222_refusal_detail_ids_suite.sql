-- ═══ 222 — 0191: a refusal carries an ID, not just a token ═══════════════════════════════════
-- ═══        0191-D1 · D2 · D3 · D4 · D5 · S1, tag `rdi`                                    ═══
--
-- THE PROPOSITIONS THIS FILE OWNS, and they are deliberately FIVE rather than one:
--   · D1 a refusal that names a BOOKING carries that booking's id in the exception's DETAIL,
--     and the id is the one that actually blocks — not merely a uuid of the right shape.
--   · D2 `open_incident` carries an incident id from EITHER family (`incidents` and
--     `club_incidents` are two entities behind one token). ⚠ This pin also records the GAP: the
--     detail alone cannot say WHICH family, so the client renders no button for this token. The
--     pin asserts what is true — an id arrives, and it is the blocking row's — and says in its
--     own sentence what that does NOT buy.
--   · D3 `club_custody_owner` — the queue item's own example — carries the CLUB SESSION id.
--     ⚠ Its second arm is the one that matters: the detail must be `club_sessions.id` and must
--     NOT be `session_dogs.id`. Both are uuids on the blocking row's own line, both would look
--     correct in a log, and only one of them is a route (`app/app/club/session/[sid].tsx`).
--     A pin that only asked 「is it a uuid」 could not tell a working deep link from a dead one.
--   · D4 CONTROL — an account with nothing blocking it still deletes, raising nothing. Without
--     it, a `delete_my_account_tx` that raised on EVERYTHING would pass D1/D2/D3 perfectly.
--   · D5 the MESSAGE stays BARE, and two more tokens are measured. ⚠ HONEST ABOUT ITS OWN
--     OVERLAP: D1 and D3 already compare the message to the token, so for THOSE two tokens the
--     bareness claim is implied and D5 restates it rather than adding it. What D5 genuinely adds
--     is (a) the `active_run` / `unsettled_run` pair, which nothing else in this file reaches —
--     two tokens, one blocking row, so the SAME run id must come back through both — and (b) the
--     two arms an equality cannot express: no uuid anywhere in the message, and the detail is not
--     a substring of the message. Without (a) this pin would be a second printing of D1.
--   · S1 deployed shape: nine `using detail` arms present, ZERO bare `raise exception '<token>';`
--     left behind, the `v_block_id` local, 0138 §F's enqueue and 0190 §B's retention predicate
--     both still in the body, definer · in-body search_path · ACL by value, NO-SOURCE arm.
--
-- ─── WHY THE SOURCE ARM IS READ WITH COMMENTS STRIPPED ───
-- `prosrc` is source PLUS our own prose, and 0191's replacement blocks are commented. An
-- un-stripped match would be satisfied by a comment EXPLAINING the detail rather than by the
-- code attaching it — and the better the explanation, the more certainly it passes. Stripped
-- with `regexp_replace(prosrc, '--[^\n]*', '', 'g')`, and a NULL body fails LOUDLY
-- (`NO-SOURCE(delete_my_account_tx)`) rather than collapsing every `if` into silence.
--
-- ─── WHY 150 STAYS GREEN AND IS NOT STALE ───
-- 150's N2-* arms compare `sqlerrm` to a token and are blind to the detail by construction —
-- `t_acd_try` returns `sqlerrm` and nothing else. They are still exactly right about what they
-- assert (the token, the gate, the order), so not one of them is touched here. 150 N2-set, which
-- pins 「exactly twelve tokens」 by sweeping `prosrc` for `raise exception '…'`, is the one arm
-- that could have gone stale: it is a regex over the raise statements, and the raises just grew
-- a `using detail` clause. Measured in this slice: it stays green, because its pattern captures
-- the quoted token and stops at the closing quote. Recorded here so the next reader does not
-- have to re-derive it.
--
-- ─── MUTATION MAP — measured 2026-09-22 against THESE EXACT FILES (md5-verified), not predicted ─
--   Lab: an rsync of `supabase/` OUTSIDE the worktree, suite and migration md5-identical to the
--   committed ones; the plant restores from pristine, reads the file BACK from disk, and is
--   &&-CHAIN-GATED to its harness run so a failed plant yields NO row rather than a green one.
--   Control observed clean FIRST, in the lab: **1348 / 0**.
--   「demoted」 = 0191 §B's VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where VERIFY aborts the apply before any suite runs.
--
--   (i-a) `using detail` deleted from the `club_custody_owner` arm, demoted → **1346 / 2: D3 + S1.**
--         D1, D2, D4 and D5 stay green, and that is the correct result rather than a gap: each of
--         them measures a DIFFERENT token's arm, and this mutation removes exactly one arm. A
--         battery row where everything reddens would mean the pins were not separable.
--   (i-b) the same plant, un-demoted → the apply ABORTS:
--         `0191 §B VERIFY: DETAIL-MISSING(club_custody_owner) STILL-BARE(club_custody_owner)`,
--         and no suite runs at all. The two halves are different propositions — (i-a) says 「the
--         suite notices」, (i-b) says 「the migration refuses to land in that state」 — and only
--         running both tells them apart.
--
--   ⚠ NOT MEASURED, and named rather than implied: the empty-detail race (§0c) — the `exists`
--   matching and the row being committed away before the `select` — needs two transactions, and
--   every pin here is one session. It is covered by construction (`coalesce(…, '')` plus
--   `handle()`'s truthiness-gated spread) and by the deno arm
--   「a refusal with NO errdetail carries no detail」, not by anything in this file.
set client_min_messages = warning;

-- ═══ fixtures ══════════════════════════════════════════════════════════════════════════════
-- The refusal probe. `t_acd_try` (150) returns `sqlerrm` only, which is exactly the instrument
-- that cannot see this slice — so 222 needs its own, and `get stacked diagnostics` is the only
-- way to read an errdetail from plpgsql.
create or replace function t_rdi_try(p_uid uuid, out o_msg text, out o_detail text)
language plpgsql as $$
begin
  perform delete_my_account_tx(p_uid);
  o_msg := '';                       -- '' means the deletion SUCCEEDED, which D4 needs to see
  o_detail := '';
exception when others then
  o_msg := sqlerrm;
  get stacked diagnostics o_detail = pg_exception_detail;
end $$;

-- A booking parked at a status the gate refuses. INSERTed at that status, never UPDATEd into it:
-- `enforce_booking_transition` (0002) refuses most jumps.
create or replace function t_rdi_booking(p_owner uuid, p_runner uuid, p_dog uuid,
                                         p_status booking_status default 'confirmed') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_status, now() - interval '1 day', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  return v;
end $$;

do $$
declare
  v_bad text := ''; v_msg text; v_txt text; v_oid oid;
  v_m text; v_d text;
  o uuid; r uuid; d uuid; u uuid; u2 uuid;
  bk uuid; cl uuid; cs uuid; sd uuid; inc uuid; cinc uuid;
  v_tok text;
  v_toks text[] := array[
    'active_booking','active_run','unsettled_run','unsettled_payment','open_incident',
    'club_host_duty','club_custody','club_custody_owner','club_assignment'];
begin
  perform set_config('request.jwt.claim.sub', '', true);

  -- ---------- [0191-D1] active_booking carries the BLOCKING booking's id ----------
  begin
    v_bad := '';
    o := t_user('rdi_bk_o', 'owner'); r := t_user('rdi_bk_r', 'runner'); d := t_dog(o, '보리');
    bk := t_rdi_booking(o, r, d, 'confirmed');
    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from 'active_booking' then
      v_bad := v_bad || ' 토큰=' || coalesce(nullif(v_m, ''), '삭제됨') || ' (기대 active_booking)';
    end if;
    -- the id is the ROW THAT BLOCKS, not any uuid: compared against the booking we just made.
    if v_d is distinct from bk::text then
      v_bad := v_bad || ' / detail=' || coalesce(nullif(v_d, ''), '(없음)') || ' 인데 막는 예약은 ' || bk::text;
    end if;
    -- the runner side of the same booking gets the same refusal and the same id — the gate is
    -- two-sided and so is the answer.
    select o_msg, o_detail into v_m, v_d from t_rdi_try(r);
    if v_m is distinct from 'active_booking' then
      v_bad := v_bad || ' / 러너 쪽 토큰=' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if v_d is distinct from bk::text then
      v_bad := v_bad || ' / 러너 쪽 detail이 같은 예약을 가리키지 않는다: ' || coalesce(nullif(v_d, ''), '(없음)'); end if;
    if v_bad = '' then
      call _pass('rdi','0191-D1 active_booking은 막는 예약의 id를 errdetail로 들고 온다 — 아무 uuid가 아니라 방금 만든 그 예약이고, 양측(보호자·러너)이 같은 행을 받는다. 예전에는 토큰만 와서 클라이언트가 화면을 말로 설명할 수밖에 없었다');
    else call _fail('rdi','0191-D1 active_booking detail', v_bad); end if;
  exception when others then call _fail('rdi','0191-D1 active_booking detail', sqlerrm);
  end;

  -- ---------- [0191-D2] open_incident — both families carry an id, and the GAP is named ----------
  -- ⚠ This pin proves 「an id arrives and it is the blocking row's」 and NOTHING MORE. One token
  -- covers `incidents` (whose client screen is keyed on the BOOKING id) and `club_incidents`
  -- (keyed on the incident id), so a bare uuid cannot choose a destination. The client
  -- deliberately draws no button here; that refusal to guess is the honesty law, not an
  -- unfinished half. Closing it needs a typed detail or a second token — a copy decision.
  begin
    v_bad := '';
    u := t_user('rdi_inc_r', 'owner');
    insert into incidents (booking_id, reporter_id, kind) values (null, u, 'other') returning id into inc;
    select o_msg, o_detail into v_m, v_d from t_rdi_try(u);
    if v_m is distinct from 'open_incident' then
      v_bad := v_bad || ' incidents 토큰=' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if v_d is distinct from inc::text then
      v_bad := v_bad || ' / incidents detail=' || coalesce(nullif(v_d, ''), '(없음)') || ' 기대 ' || inc::text; end if;

    -- club family: a different user, a different table, the same token
    u2 := t_user('rdi_inc_h', 'runner');
    insert into clubs (name, district, host_profile_id) values ('rdi 사고 클럽', '반포동', u2) returning id into cl;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status)
    values (cl, u2, now() - interval '2 days', '집결지', 'done') returning id into cs;
    u := t_user('rdi_inc_op', 'owner');
    insert into club_incidents (session_id, severity, opened_by, case_owner, summary)
    values (cs, 'S2', u, u, '요약') returning id into cinc;
    select o_msg, o_detail into v_m, v_d from t_rdi_try(u);
    if v_m is distinct from 'open_incident' then
      v_bad := v_bad || ' / club_incidents 토큰=' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if v_d is distinct from cinc::text then
      v_bad := v_bad || ' / club_incidents detail=' || coalesce(nullif(v_d, ''), '(없음)') || ' 기대 ' || cinc::text; end if;
    if v_bad = '' then
      call _pass('rdi','0191-D2 open_incident은 두 계열(incidents · club_incidents) 각각에서 막는 행의 id를 들고 온다. ⚠ 명시적 공백: 한 토큰이 두 엔티티를 덮으므로 id만으로는 어느 화면인지 정할 수 없고(/incident/[bid]는 예약 id로, /club/case/[cid]는 사고 id로 열린다) 클라이언트는 이 토큰에 버튼을 그리지 않는다 — 이 핀은 id가 온다는 것만 증명하며 딥링크가 가능하다고 말하지 않는다');
    else call _fail('rdi','0191-D2 open_incident detail', v_bad); end if;
  exception when others then call _fail('rdi','0191-D2 open_incident detail', sqlerrm);
  end;

  -- ---------- [0191-D3] club_custody_owner carries the CLUB SESSION id ----------
  -- The queue item's own example: 「a 409 that says club_custody_owner tells the owner their dog
  -- is out and not WHICH session」. The fixture is 150 N2-b2's, built so only the owner arm can
  -- catch it (custody='runner_delegated' with responsible = the runner, so the owner appears in
  -- exactly one column). What is NEW here is the second arm.
  begin
    v_bad := '';
    o  := t_user('rdi_custo_o', 'owner');
    r  := t_user('rdi_custo_r', 'runner');
    u2 := t_user('rdi_custo_h', 'runner');
    d  := t_dog(o, '단추');
    insert into clubs (name, district, host_profile_id) values ('rdi 보호자 인계 클럽', '반포동', u2) returning id into cl;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status, format,
                               delegated_dog_capacity)
    values (cl, u2, now() - interval '1 hour', '집결지', 'open', 'delegated_only', 3) returning id into cs;
    insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                              custody, checked_in_at, checked_out_at)
    values (cs, d, o, r, 'runner_delegated', now() - interval '30 minutes', null) returning id into sd;

    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from 'club_custody_owner' then
      v_bad := v_bad || ' 토큰=' || coalesce(nullif(v_m, ''), '삭제됨') || ' (기대 club_custody_owner)'; end if;
    -- ① it is the SESSION
    if v_d is distinct from cs::text then
      v_bad := v_bad || ' / detail=' || coalesce(nullif(v_d, ''), '(없음)') || ' 인데 세션은 ' || cs::text; end if;
    -- ② 🔴 and it is NOT the session_dogs row. Both are uuids on the same blocking line and both
    --    read as correct in a log; only `club_sessions.id` is a route. A pin that asked only
    --    「is it a uuid」 could not tell a working deep link from a dead one.
    if (v_d = sd::text) is not false then
      v_bad := v_bad || ' / 🔴 detail이 session_dogs 행 id다 — 그것을 여는 화면은 없다 (/club/session/[sid]는 세션 id로 열린다)'; end if;
    -- ③ the holder's side keeps its own token, and carries the same session
    select o_msg, o_detail into v_m, v_d from t_rdi_try(r);
    if v_m is distinct from 'club_custody' then
      v_bad := v_bad || ' / 러너 쪽 토큰=' || coalesce(nullif(v_m, ''), '삭제됨') || ' (기대 club_custody)'; end if;
    if v_d is distinct from cs::text then
      v_bad := v_bad || ' / 러너 쪽 detail이 세션을 가리키지 않는다: ' || coalesce(nullif(v_d, ''), '(없음)'); end if;
    if v_bad = '' then
      call _pass('rdi','0191-D3 club_custody_owner는 클럽 세션 id를 들고 온다 — 0115:388-392가 「ctx.ts 때문에 붙일 수 없다」고 적어 둔 바로 그 필드다. 🔴 두 번째 팔이 요점: detail은 club_sessions.id이고 session_dogs.id가 아니다 — 둘 다 같은 줄의 uuid라 로그에서는 구분이 안 되지만 화면이 되는 것은 하나뿐이다(/club/session/[sid]). 홀더 쪽도 자기 토큰(club_custody)에 같은 세션을 받는다');
    else call _fail('rdi','0191-D3 club_custody_owner detail', v_bad); end if;
  exception when others then call _fail('rdi','0191-D3 club_custody_owner detail', sqlerrm);
  end;

  -- ---------- [0191-D4] CONTROL — nothing blocking ⇒ the account still deletes ----------
  -- Without this arm a function that raised on EVERYTHING would pass D1, D2 and D3 perfectly.
  begin
    v_bad := '';
    o := t_user('rdi_clean_o', 'owner');
    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from '' then
      v_bad := v_bad || ' 막을 것이 없는 계정이 거절당했다: ' || v_m || ' (detail=' || coalesce(v_d, '(null)') || ')'; end if;
    if (select deleted_at is not null from profiles where id = o) is not true then
      v_bad := v_bad || ' / 툼스톤이 찍히지 않았다'; end if;
    if (select name from profiles where id = o) is distinct from '탈퇴한 사용자' then
      v_bad := v_bad || ' / 이름이 대체되지 않았다'; end if;
    if v_bad = '' then
      call _pass('rdi','0191-D4 대조: 막는 것이 없는 계정은 그대로 삭제된다(아무것도 raise하지 않고 툼스톤·이름 대체까지 간다). 이 팔이 없으면 「전부 거절」하는 함수도 D1·D2·D3를 완벽히 통과한다');
    else call _fail('rdi','0191-D4 unblocked control', v_bad); end if;
  exception when others then call _fail('rdi','0191-D4 unblocked control', sqlerrm);
  end;

  -- ---------- [0191-D5] the MESSAGE stays BARE, and two more tokens are measured ----------
  -- The client's `REFUSALS` lookup is an exact-string match on the token, so an id that leaked
  -- into the message breaks all twelve Korean refusal lines at once.
  -- ⚠ WHAT THIS PIN ADDS OVER D1/D3, stated rather than implied: for `active_booking` and
  -- `club_custody_owner` those pins already compare the message to the token, so the bareness
  -- claim is IMPLIED there and repeating it buys nothing. The new coverage is the
  -- `active_run` → `unsettled_run` pair — two tokens nothing else in this file reaches, raised by
  -- ONE row, so the same `runs.id` must come back through both — plus the two arms an equality
  -- cannot express: no uuid anywhere in the message, and the detail is not a substring of it.
  begin
    v_bad := '';
    o := t_user('rdi_bare_o', 'owner'); r := t_user('rdi_bare_r', 'runner'); d := t_dog(o, '가루');
    bk := t_rdi_booking(o, r, d, 'confirmed');
    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from 'active_booking' then
      v_bad := v_bad || ' 메시지가 맨 토큰이 아니다: ' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if (v_m ~ '[0-9a-f]{8}-[0-9a-f]{4}') is not false then
      v_bad := v_bad || ' / 메시지 안에 uuid가 있다: ' || v_m; end if;
    if v_d = '' or v_d is null then
      v_bad := v_bad || ' / detail이 비어 있어 이 핀이 증명할 것이 없다 (D1이 먼저 빨개져야 한다)';
    elsif (position(v_d in v_m) > 0) is not false then
      v_bad := v_bad || ' / detail이 메시지의 부분문자열이다 — id가 메시지로 새고 있다'; end if;

    -- 🔴 THE ARM THAT MAKES THIS PIN MORE THAN A SECOND PRINTING OF D1. active_run and
    -- unsettled_run are raised by ONE row on a PARKED booking (an `active` booking would trip
    -- active_booking first and the gate is ordered), so the same `runs.id` has to come back
    -- through both tokens. A per-arm select that reached for the wrong table would look fine on
    -- either token alone and fails here.
    o := t_user('rdi_run_o', 'owner'); r := t_user('rdi_run_r', 'runner'); d := t_dog(o, '노을');
    bk := t_rdi_booking(o, r, d, 'completed');
    insert into runs (booking_id, started_at) values (bk, now() - interval '1 hour') returning id into inc;
    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from 'active_run' then
      v_bad := v_bad || ' / active_run 대신 ' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if v_d is distinct from inc::text then
      v_bad := v_bad || ' / active_run detail=' || coalesce(nullif(v_d, ''), '(없음)') || ' 기대 ' || inc::text; end if;
    update runs set ended_at = now() where id = inc;
    select o_msg, o_detail into v_m, v_d from t_rdi_try(o);
    if v_m is distinct from 'unsettled_run' then
      v_bad := v_bad || ' / unsettled_run 대신 ' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if v_d is distinct from inc::text then
      v_bad := v_bad || ' / unsettled_run이 같은 러닝을 가리키지 않는다: ' || coalesce(nullif(v_d, ''), '(없음)'); end if;

    -- the same, one token further in: a club session id is a different shape of leak
    u2 := t_user('rdi_bare_h', 'runner');
    insert into clubs (name, district, host_profile_id) values ('rdi 맨토큰 클럽', '반포동', u2) returning id into cl;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status, format,
                               delegated_dog_capacity)
    values (cl, u2, now() - interval '1 hour', '집결지', 'open', 'delegated_only', 3) returning id into cs;
    u := t_user('rdi_bare_o2', 'owner');
    insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                              custody, checked_in_at, checked_out_at)
    values (cs, t_dog(u, '깨'), u, u2, 'runner_delegated', now() - interval '20 minutes', null);
    select o_msg, o_detail into v_m, v_d from t_rdi_try(u);
    if v_m is distinct from 'club_custody_owner' then
      v_bad := v_bad || ' / 클럽 쪽 메시지=' || coalesce(nullif(v_m, ''), '삭제됨'); end if;
    if (v_m ~ '[0-9a-f]{8}-[0-9a-f]{4}') is not false then
      v_bad := v_bad || ' / 클럽 쪽 메시지 안에 uuid가 있다: ' || v_m; end if;
    if v_bad = '' then
      call _pass('rdi','0191-D5 메시지는 맨 토큰 그대로다(메시지 == 토큰 · 메시지 안에 uuid 없음 · detail이 메시지의 부분문자열이 아님) — 클라이언트의 REFUSALS 조회가 정확 일치 매칭이라 id가 메시지로 새면 열두 줄의 한국어 거절 문구가 한꺼번에 깨진다. ⚠ 겹침을 숨기지 않는다: active_booking·club_custody_owner의 맨 토큰 성질은 D1·D3의 동등 비교가 이미 함의한다. 이 핀이 실제로 더하는 것은 (a) 이 파일의 다른 어떤 핀도 닿지 않는 active_run → unsettled_run 쌍 — 한 행이 두 토큰을 일으키므로 같은 runs.id가 양쪽으로 돌아와야 한다 — 와 (b) 동등 비교로는 쓸 수 없는 두 팔이다');
    else call _fail('rdi','0191-D5 bare message', v_bad); end if;
  exception when others then call _fail('rdi','0191-D5 bare message', sqlerrm);
  end;

  -- ---------- [0191-S1] the deployed shape ----------
  begin
    v_bad := '';
    select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.proname = 'delete_my_account_tx';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(delete_my_account_tx)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then
        v_bad := v_bad || ' definer 아님'; end if;
      if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
            from pg_proc where oid = v_oid) is distinct from true then
        v_bad := v_bad || ' 본문 search_path 없음'; end if;
      if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then
        v_bad := v_bad || ' 클라 실행 가능'; end if;
      if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then
        v_bad := v_bad || ' service_role 실행 불가'; end if;

      -- comments STRIPPED before matching: 0191's blocks quote these very strings, and an
      -- un-stripped read would be satisfied by the prose explaining the fix.
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_txt
        from pg_proc where oid = v_oid;
      if v_txt is null then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
      else
        foreach v_tok in array v_toks loop
          if (position($q$raise exception '$q$ || v_tok || $q$' using detail = coalesce(v_block_id::text, '')$q$ in v_txt) > 0) is not true then
            v_bad := v_bad || ' DETAIL-MISSING(' || v_tok || ')'; end if;
          if (position($q$raise exception '$q$ || v_tok || $q$';$q$ in v_txt) > 0) is not false then
            v_bad := v_bad || ' STILL-BARE(' || v_tok || ')'; end if;
        end loop;
        if (position($q$v_block_id uuid;$q$ in v_txt) > 0) is not true then
          v_bad := v_bad || ' NO-BLOCK-ID-LOCAL'; end if;
        -- the two inherited landings the catalog copy had to carry forward
        if (position($q$enqueue_billing_key_revocation(p_uid, 'account_deleted')$q$ in v_txt) > 0) is not true then
          v_bad := v_bad || ' 0138-ENQUEUE-LOST-IN-THE-COPY'; end if;
        if (position($q$where runner_id = p_uid and paid_payout_id is null$q$ in v_txt) > 0) is not true then
          v_bad := v_bad || ' 0190-RETENTION-LOST-IN-THE-COPY'; end if;
        -- the three tokens that deliberately stay bare (§0a). Their presence in the BARE form is
        -- the correct state; asserting it stops a later sweep from "finishing the job" without an
        -- argument for why km_lots' sum or an unwritten payout has a single subject.
        foreach v_tok in array array['km_balance','unpaid_payout','active_recurring'] loop
          if (position($q$raise exception '$q$ || v_tok || $q$';$q$ in v_txt) > 0) is not true then
            v_bad := v_bad || ' EXPECTED-BARE-BUT-CHANGED(' || v_tok || ')'; end if;
        end loop;
      end if;
    end if;
    if v_bad = '' then
      call _pass('rdi','0191-S1 배포 형상 — 아홉 개 팔 전부가 using detail = coalesce(v_block_id::text, '''')을 달고 있고 맨 raise 형태는 하나도 남지 않았으며, v_block_id 지역변수가 있고, 카탈로그 복사가 0138 §F의 revocation enqueue와 0190 §B의 미지급 보관 술어를 그대로 살려 뒀다. definer · 본문 search_path · ACL(anon·authenticated 불가 / service_role 가능)을 값으로 확인하고, 주석을 떼고 읽으며(0191의 설명문이 바로 이 문자열들을 인용한다), 본문이 없으면 NO-SOURCE로 소리 내어 실패한다. km_balance·unpaid_payout·active_recurring 세 개는 일부러 맨 토큰이고 그 상태까지 핀으로 잡는다');
    else call _fail('rdi','0191-S1 deployed shape', v_bad); end if;
  exception when others then call _fail('rdi','0191-S1 deployed shape', sqlerrm);
  end;
end $$;
