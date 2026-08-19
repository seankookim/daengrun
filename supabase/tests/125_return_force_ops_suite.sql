-- ═══ 125 return-force OPS-ONLY suite — 0089 pins (F1~F5) ═══
-- ═══ §0 WHAT THIS FILE EXISTS FOR ═══════════════════════════════════════════════════════════
-- Sean, 2026-08-13, verbatim:
--   "no, the confirmation must happen with both parties and never just the runner. also handoff."
-- Said in refusal of a design that would have let a one-sided force release money as long as the
-- RECORD stayed honest about it ("runner asserted handover; owner never confirmed"). The ruling
-- is that honest labelling is not the point: the confirmation IS the safety artifact, and a
-- one-sided one is not a confirmation at all. 0089 implements it — `force_return_tx` becomes an
-- OPS adjudication, refuses `runner`/`owner` by name, and writes NO party confirmation stamp.
--
-- 119 R5/R6/R13/R17 already pin the FUNCTION's behaviour under that ruling. This file pins the
-- properties 119 does not, and each was chosen because it survives a rewrite of the function:
--   F1  the CHECK on the COLUMN rejects a party actor independently of any function. If the
--       function is ever replaced (or bypassed by a definer/ops script), the row still cannot
--       claim a runner forced it — the database itself refuses to record that sentence.
--   F2  the money consequence of a one-sided party action, measured as money: no seal, no ledger,
--       no payment, no status move. 119 R5 measures the ERROR CODE; this measures the AFTERMATH,
--       which is the thing Sean actually ruled about.
--   F3  🔴 the ruling's whole point, stated as a READER's question: after an ops force, can a
--       later reader tell "ops resolved this" apart from "both parties confirmed"? Only if the
--       force leaves both stamps NULL. A design that stamps the forcing side cannot express the
--       difference at all — which is exactly the 0083 shape the ruling rejected.
--   F4  the two-party path is UNTOUCHED. A ruling that removes a valve must not quietly damage
--       the normal door; a green F2/F3 with a broken F4 would be a worse product, not a safer one.
--   F5  the PICKUP handoff stays two-sided. 0089 §4 verified that `confirm_handoff` already
--       satisfies the ruling (one stamp, RE-READ, `picked_up` only when both exist) and touched
--       nothing — so the risk here is not a bug, it is a future slice "simplifying" it. Pinned
--       structurally: the promotion lives in the edge function, and NO database routine may write
--       a non-null handoff stamp. The day one does, one side can be stamped without the other.
--
-- Style: sibling of 119 — `_pass('frc',…)`/`_fail('frc',…)`, one begin…exception per case,
--   `_fail` arguments pre-computed into v_msg (the 110 header law).
-- ⚠ No pin here asserts a G1 amount. Every money assertion is a PRESENCE/ABSENCE claim (a ledger
--   row, a payment row) or is read out of the quote fixture — never a hardcoded fare.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   F1 ← 0089 §5: widen `bookings_return_forced_by_check` back to
--        `in ('runner','owner','ops')` — the column stops refusing the sentence the ruling
--        forbids, and every later belt becomes a function that could be rewritten       → RED
--   F2 ← 0089 §6: collapse the door back to one line —
--          `if p_side not in ('runner','owner','ops') then raise exception 'bad_side'; end if;`
--        (i.e. the `force_party_forbidden` block deleted and the ops-only gate widened). A party
--        force then falls through and seals/settles while the row still records `ops`, so the
--        record is not merely permissive, it is FALSE. Measured as money: settlement_ready_at,
--        ledger, payments, status                                                       → RED
--   F3 ← 0089 §6: restore 0083's
--        `runner_confirmed_return_at = case when p_side = 'runner' then coalesce(…, now())`
--        (or its owner twin, or ANY unconditional stamp write) — "ops resolved" and "both
--        confirmed" collapse into the same row shape and the classifier can no longer tell
--        them apart                                                                     → RED
--   F4 ← 0083 §6-ⓓ: settle on the FIRST stamp in confirm_return_tx instead of on both, or drop
--        the second stamp's `settlement_ready_at` write — the ruling's positive half        → RED
--   F5 ← add ANY database routine that writes a non-null `owner_confirmed_handoff_at` /
--        `runner_confirmed_handoff_at` (the "one RPC to finish pickup" shortcut), or drop the
--        0057/0083 client seal on either stamp in either direction                       → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13 (method: the revert applied to a COPY of
--     0089 at a short path — the harness cannot run from a worktree, macOS's 103-byte Unix socket
--     limit — `rm -rf .pgtest` for a clean cluster, the WHOLE harness run, then the tree restored
--     from the pristine source and re-verified by md5 + a green run).
--     Pristine 0089 md5 `d2be2fc506d18d816de64be37df188ab`. GREEN with this suite: **511/0**
--     (baseline with 0089 present and the 119 pins updated, this suite absent: 506/0).
--       F2 → **508/3**, red = [F2, 119 R5, 119 R6]. F2's detail is the attack end to end:
--           `러너 강제 거부 사유=not_party … 서버 대리 강제:통과 한쪽 행동이 씰을 찍었다
--            한쪽 행동이 강제를 기록했다=ops 한쪽 행동이 상태를 옮겼다=completed
--            원장 행수=1 (러너가 스스로 지급받았다) settled_at이 찍혔다` — the runner paid by
--           their own tap, on a row that says ops did it. ⚠ The two cascades are CORRECT and are
--           named rather than engineered away: 119 R5 measures the same removed law from the
--           ERROR-CODE side and R6's last arm re-probes it on a settled row. That F2 and R5 are
--           two views of one law is the reason both exist — F2 is the only one of them that
--           would notice a revert which refused the party by a DIFFERENT code but still paid.
--       F3 → **507/4**, red = [F3, 119 R6, 119 R17, F4]. The mutation is 0089 §6's stamp comment
--           replaced by 0083's inference in its most complete form (`runner_confirmed_return_at =
--           coalesce(b.runner_confirmed_return_at, v_now)` + the owner twin). F3's detail is the
--           collapse itself: `🔴 ops 강제가 러너 확인을 찍었다 🔴 ops 강제가 보호자 확인을 찍었다
--           씰 직후 판독=both_confirmed … 정산 뒤 판독=both_confirmed` — an ops adjudication that
--           a later reader cannot tell from a genuine two-sided return, which is exactly what
--           Sean's ruling forbids. F4's cascade (`판정 행과 확인 행이 같은 모양으로 읽힌다`) is
--           the same fact seen from the other row and is why that cross-check is in F4 at all.
--     F1/F4/F5 are not machine-proven as primaries; each is named above with the single revert
--     that would redden it, F1's probe is a direct constraint exercise (no indirection left to
--     get wrong), F4 was observed red as F3's cascade above, and F5's probe shapes are clones of
--     already-proven siblings (119 R2 for the client seal, 116 C21 for the catalogue scan idiom).
set client_min_messages = warning;

-- ---------- suite-local helpers (self-contained: this file must not depend on 119's fixtures) --
-- An `active` marketplace booking with a live runs row — the state the moment before the stop.
create or replace function t_frc_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '40 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '40 minutes', '[]'::jsonb);
  return v;
end $$;

-- The payout the edge function computes AT SETTLE and hands to the RPC. A fixture, not a rule —
-- this suite is not the place that owns pricing (119's header law, restated).
create or replace function t_frc_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- 🔴 THE READER'S QUESTION, as a function. This is the classifier a dispute, an ops console or a
-- receipt would use, and the ruling is a claim about ITS output: an ops adjudication and a genuine
-- two-sided confirmation must never produce the same answer. `sealed_by_unknown_means` is the
-- shape that must be unreachable — a seal with neither both stamps nor a recorded ops force.
create or replace function t_frc_how_returned(p_booking uuid) returns text
language sql stable as $$
  select case
           when b.runner_confirmed_return_at is not null
            and b.owner_confirmed_return_at  is not null then 'both_confirmed'
           when b.return_forced_by = 'ops'                then 'ops_resolved'
           when b.settlement_ready_at is not null         then 'sealed_by_unknown_means'
           else 'open'
         end
  from bookings b where b.id = p_booking
$$;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  b_1 uuid; b_2 uuid; b_3 uuid; b_4 uuid;
  v_bad text := ''; v_msg text; v_n int; v_txt text; v_js jsonb;
begin
  oo := t_user('frc_oo', 'owner'); rr := t_user('frc_rr', 'runner');
  dg := t_dog(oo, '판정견'); rt := t_route('판정 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [F1] the COLUMN refuses a party actor — with no function in the way
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Every other belt in 0089 is inside `force_return_tx`, which is one `create or replace` away
  -- from being different. This one is not: the CHECK is the database refusing to STORE the
  -- sentence "the runner forced this return", whatever wrote it — an RPC, an ops script, a
  -- definer helper, a hand-typed UPDATE at 3am. It is run here as `postgres`, deliberately, so
  -- no RLS policy and no client-facing trigger can be mistaken for the thing that refused.
  begin
    v_bad := '';
    b_1 := t_frc_live(oo, dg, rt, rr);
    foreach v_txt in array array['runner', 'owner', 'both', 'system'] loop
      begin
        update bookings set return_forced_by = v_txt where id = b_1;
        v_bad := v_bad || ' ' || v_txt || ':컬럼이 받아들였다';
      exception when check_violation then null;
        when others then v_bad := v_bad || ' ' || v_txt || ' 거부가 CHECK가 아니다=' || sqlerrm;
      end;
    end loop;
    if (select b.return_forced_by from bookings b where b.id = b_1) is not null
      then v_bad := v_bad || ' 거부된 값이 남았다=' || (select b.return_forced_by from bookings b where b.id = b_1); end if;
    -- positive control: the two legal values ARE accepted (else the CHECK is just "refuse all")
    begin
      update bookings set return_forced_by = 'ops' where id = b_1;
    exception when others then v_bad := v_bad || ' ops도 거부됐다=' || sqlerrm;
    end;
    if (select b.return_forced_by from bookings b where b.id = b_1) is distinct from 'ops'
      then v_bad := v_bad || ' ops가 기록되지 않았다'; end if;
    begin
      update bookings set return_forced_by = null where id = b_1;
    exception when others then v_bad := v_bad || ' null도 거부됐다=' || sqlerrm;
    end;
    -- …and the constraint is the one 0089 wrote, by name and by definition (a same-named
    -- constraint with the old three-value list would pass every probe above only if the probes
    -- were weaker — they are not, but the definition is cheap to read and expensive to guess)
    select pg_get_constraintdef(c.oid) into v_txt from pg_constraint c
     where c.conrelid = 'bookings'::regclass and c.conname = 'bookings_return_forced_by_check';
    if v_txt is null then v_bad := v_bad || ' bookings_return_forced_by_check가 없다'; end if;
    if v_txt is not null and (v_txt like '%''runner''%' or v_txt like '%''owner''%')
      then v_bad := v_bad || ' 제약에 당사자가 남아 있다=' || v_txt; end if;

    if v_bad = ''
      then call _pass('frc','F1 컬럼 제약 — bookings.return_forced_by는 함수를 거치지 않은 직접 UPDATE에서도 runner·owner를 CHECK로 거부한다(제약 정의에 당사자 문자열이 없다), ops와 null만 받는다: "러너가 강제했다"는 문장 자체를 DB가 저장하지 않는다');
    else v_msg := v_bad; call _fail('frc','F1 컬럼 제약', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('frc','F1 컬럼 제약', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [F2] a one-sided party action moves NO MONEY — measured as money, not as an error code
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 119 R5 pins that the call raises `force_party_forbidden`. That is the mechanism. THIS pin is
  -- the consequence Sean ruled about: after a runner has tried everything a runner can try, the
  -- booking must be exactly where it was — nobody sealed, nobody paid, nobody charged, and the
  -- dog is still officially in the runner's hands. A revert that let the party path through would
  -- show up here as a ledger row, which is the unit the ruling is denominated in.
  begin
    v_bad := '';
    b_2 := t_frc_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_2, 4.4, 2000, 'completed', null, null);

    -- ⓐ the runner forces from their own phone, for their own booking, with real evidence and a
    --    real reason — the MOST privileged and most sympathetic version of the removed path.
    begin
      perform force_return_tx(b_2, 'runner', '보호자가 문 앞에 없어요',
                              jsonb_build_object('kind','pickup_radius','m',8));
      v_bad := v_bad || ' 러너 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 러너 강제 거부 사유=' || sqlerrm;
      else
        -- the refusal speaks Korean to the person holding the phone, and says WHY rather than
        -- "invalid input" — the honest answer names the rule (0089 §6)
        get stacked diagnostics v_txt = pg_exception_detail;
        if coalesce(v_txt,'') not like '%양측이 함께%'
          then v_bad := v_bad || ' 거부 문구=' || coalesce(v_txt,'∅'); end if;
      end if;
    end;
    -- ⓑ …and the same call carrying a PRICE is refused for the party reason FIRST, not for the
    --    quote reason — the side is judged before anything else, so no ordering accident can let
    --    a party through on a technicality.
    begin
      perform force_return_tx(b_2, 'runner', '가격까지 들고 왔다',
                              jsonb_build_object('kind','pickup_radius'), t_frc_quote(4.4));
      v_bad := v_bad || ' 가격 든 러너 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 가격 든 러너 강제 거부 사유=' || sqlerrm; end if;
    end;
    -- ⓒ the owner's version, and the server-class version (an edge function dialling on the
    --    runner's behalf — the removed path's most likely return route)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform force_return_tx(b_2, 'owner', '내가 이미 받았어요', jsonb_build_object('kind','owner_tap'));
      v_bad := v_bad || ' 보호자 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 보호자 강제 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform force_return_tx(b_2, 'runner', '엣지가 러너 대신 부른다',
                              jsonb_build_object('kind','ops'), t_frc_quote(4.4));
      v_bad := v_bad || ' 서버 대리 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 서버 대리 강제 거부 사유=' || sqlerrm; end if;
    end;

    -- 🔴 THE AFTERMATH — this is the assertion, the codes above are only how we got here
    if (select b.settlement_ready_at from bookings b where b.id = b_2) is not null
      then v_bad := v_bad || ' 한쪽 행동이 씰을 찍었다'; end if;
    if (select b.return_forced_by from bookings b where b.id = b_2) is not null
      then v_bad := v_bad || ' 한쪽 행동이 강제를 기록했다=' || (select b.return_forced_by from bookings b where b.id = b_2); end if;
    if (select b.status::text from bookings b where b.id = b_2) <> 'active'
      then v_bad := v_bad || ' 한쪽 행동이 상태를 옮겼다=' || (select b.status::text from bookings b where b.id = b_2); end if;
    select count(*) into v_n from ledger_items where booking_id = b_2;
    if v_n <> 0 then v_bad := v_bad || ' 원장 행수=' || v_n || ' (러너가 스스로 지급받았다)'; end if;
    select count(*) into v_n from payments where booking_id = b_2;
    if v_n <> 0 then v_bad := v_bad || ' 청구 행수=' || v_n; end if;
    if (select r.settled_at from runs r where r.booking_id = b_2) is not null
      then v_bad := v_bad || ' settled_at이 찍혔다'; end if;
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_2) is not null
       or (select b.owner_confirmed_return_at from bookings b where b.id = b_2) is not null
      then v_bad := v_bad || ' 거부된 시도가 확인 스탬프를 남겼다'; end if;
    if t_frc_how_returned(b_2) <> 'open'
      then v_bad := v_bad || ' 판독=' || t_frc_how_returned(b_2) || ' (아직 아무 일도 일어나지 않았어야 한다)'; end if;

    if v_bad = ''
      then call _pass('frc','F2 한쪽 행동은 돈을 움직이지 않는다 — 러너가 자기 예약을 증거·사유·가격까지 갖춰 강제해도(보호자도, 엣지의 대리 호출도) force_party_forbidden(한국어로 "양측이 함께"라고 이유를 말한다)이고, 그 뒤 씰·강제 기록·원장·청구·settled_at이 전부 없고 상태는 active 그대로다');
    else v_msg := v_bad; call _fail('frc','F2 한쪽 행동은 돈을 안 움직인다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frc','F2 한쪽 행동은 돈을 안 움직인다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [F3] 🔴 an ops force RESOLVES a return; it does not CONFIRM one
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The ruling's whole point, asked as the question a reader will actually ask months later:
  -- "how did this return end?" There are two true answers and they must not be the same row.
  -- 0083 wrote the forcing side's own stamp and called it "implied by the act"; under that design
  -- an ops-resolved return and a genuinely confirmed one are indistinguishable after the fact,
  -- which is what makes the confirmation stop being a safety artifact. So: settlement_ready_at
  -- YES (an adjudication does release the money — that is what it is for), both stamps NO.
  begin
    v_bad := '';
    b_3 := t_frc_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_3, 3.6, 1900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓐ ops seals WITHOUT a price: the seal exists, both stamps do not
    v_js := force_return_tx(b_3, 'ops', '보호자 연락 두절 — 운영이 판정',
                            jsonb_build_object('kind','ops_review','ticket','OPS-1'));
    if not coalesce((v_js->>'forced')::boolean, false) then v_bad := v_bad || ' ops 강제가 기록되지 않았다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b_3) is null
      then v_bad := v_bad || ' ops 강제가 씰을 찍지 않았다'; end if;
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_3) is not null
      then v_bad := v_bad || ' 🔴 ops 강제가 러너 확인을 찍었다'; end if;
    if (select b.owner_confirmed_return_at from bookings b where b.id = b_3) is not null
      then v_bad := v_bad || ' 🔴 ops 강제가 보호자 확인을 찍었다'; end if;
    if t_frc_how_returned(b_3) <> 'ops_resolved'
      then v_bad := v_bad || ' 씰 직후 판독=' || t_frc_how_returned(b_3); end if;

    -- ⓑ …and settlement does not change the answer. The money moving is not a confirmation
    --    either — this is where 0083's inference would have snuck back in on the second call.
    v_js := force_return_tx(b_3, 'ops', '가격 재시도', jsonb_build_object('kind','retry'),
                            t_frc_quote(3.6));
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 가격 재진입이 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b_3) <> 'completed'
      then v_bad := v_bad || ' 정산 뒤에도 completed 아님'; end if;
    select count(*) into v_n from ledger_items where booking_id = b_3;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_3) is not null
       or (select b.owner_confirmed_return_at from bookings b where b.id = b_3) is not null
      then v_bad := v_bad || ' 🔴 정산이 확인 스탬프를 찍었다'; end if;
    if t_frc_how_returned(b_3) <> 'ops_resolved'
      then v_bad := v_bad || ' 정산 뒤 판독=' || t_frc_how_returned(b_3); end if;

    if v_bad = ''
      then call _pass('frc','F3 판정과 확인은 다른 사실이다 — ops 강제는 settlement_ready_at을 찍어 돈을 풀지만 어느 쪽의 확인 스탬프도 찍지 않고(정산이 일어난 뒤에도), 그래서 나중에 이 행을 읽는 사람은 "운영이 판정함"과 "양측이 확인함"을 구분할 수 있다 — 0083의 "행위에 내포됨"이 정확히 이 구분을 없앴다');
    else v_msg := v_bad; call _fail('frc','F3 판정 ≠ 확인', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frc','F3 판정 ≠ 확인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [F4] the two-party door is UNTOUCHED — the ruling closed a valve, not the flow
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- A slice that removes a path is a slice that can break the path it kept. This pin is the
  -- positive half of the ruling: both parties confirm → sealed → settled, exactly as before, and
  -- the classifier says `both_confirmed` — the answer that F3's row must never produce.
  begin
    v_bad := '';
    b_4 := t_frc_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_4, 5.0, 2400, 'completed', null, null);

    -- ⓐ one stamp seals nothing (119 R3's law, re-measured because 0089 touched this family)
    v_js := confirm_return_tx(b_4, 'runner');
    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 러너 스탬프 미기록'; end if;
    if coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 한쪽 스탬프로 정산됨'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b_4) is not null
      then v_bad := v_bad || ' 한쪽 스탬프에 씰이 찍혔다'; end if;
    if t_frc_how_returned(b_4) <> 'open' then v_bad := v_bad || ' 한쪽 스탬프 판독=' || t_frc_how_returned(b_4); end if;

    -- ⓑ the second stamp seals AND settles (the server call carries the price)
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := confirm_return_tx(b_4, 'owner', t_frc_quote(5.0));
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 봉인하지 않았다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b_4) <> 'completed'
      then v_bad := v_bad || ' 양측 확인 뒤에도 completed 아님'; end if;
    select count(*) into v_n from ledger_items where booking_id = b_4;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    if (select r.settled_at from runs r where r.booking_id = b_4) is null
      then v_bad := v_bad || ' settled_at 미기록'; end if;
    -- the record of a genuine return carries NO force at all
    if (select b.return_forced_by from bookings b where b.id = b_4) is not null
      then v_bad := v_bad || ' 정상 인계에 강제가 기록됐다=' || (select b.return_forced_by from bookings b where b.id = b_4); end if;
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_4) is null
       or (select b.owner_confirmed_return_at from bookings b where b.id = b_4) is null
      then v_bad := v_bad || ' 양측 확인인데 스탬프가 비어 있다'; end if;
    if t_frc_how_returned(b_4) <> 'both_confirmed'
      then v_bad := v_bad || ' 양측 확인 판독=' || t_frc_how_returned(b_4); end if;

    -- ⓒ …and the two rows are genuinely distinguishable, which is the sentence the ruling makes
    if b_3 is not null and t_frc_how_returned(b_3) = t_frc_how_returned(b_4)
      then v_bad := v_bad || ' 판정 행과 확인 행이 같은 모양으로 읽힌다'; end if;
    -- nothing anywhere in this database ever reached a seal by an unnamed route
    select count(*) into v_n from bookings b
     where b.settlement_ready_at is not null
       and b.return_forced_by is null
       and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null);
    if v_n <> 0 then v_bad := v_bad || ' 출처 불명의 씰 ' || v_n || '행'; end if;

    if v_bad = ''
      then call _pass('frc','F4 양측 경로는 그대로다 — 한쪽 스탬프는 여전히 씰도 정산도 아니고, 두 번째 스탬프가 봉인·정산(원장 1행·settled_at)하며 강제 기록은 비어 있다, 그리고 이 행은 판정 행과 다른 값으로 읽힌다 (전 DB에 출처 불명의 씰 0행)');
    else v_msg := v_bad; call _fail('frc','F4 양측 경로 무손상', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frc','F4 양측 경로 무손상', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [F5] "also handoff" — the PICKUP handoff stays two-sided (0089 §4)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Sean's ruling ends "also handoff". 0089 §4 verified that `confirm_handoff`
  -- (transition-booking/index.ts:280-296) already satisfies it — it stamps ONE side, RE-READS the
  -- row, and moves to `picked_up` only when both stamps exist — and deliberately changed nothing.
  -- So the exposure is not a bug today; it is a future slice "simplifying" pickup into a single
  -- RPC. This pin makes that regression loud from SQL, where the simplification would live:
  --   ⓐ the two stamps still exist as separate facts;
  --   ⓑ neither party can write EITHER stamp — their own side or the other's, on UPDATE or
  --      smuggled through an INSERT — so a one-sided pickup cannot be produced by hand;
  --   ⓒ 🔴 and NO database routine writes a non-null value to either stamp. The only writer is
  --      the edge function that re-reads and requires both; the day a definer RPC stamps a side,
  --      the two-sidedness stops being enforced by anything.
  begin
    v_bad := '';
    -- ⓐ two columns, two facts
    select count(*) into v_n from information_schema.columns
     where table_schema = 'public' and table_name = 'bookings'
       and column_name in ('owner_confirmed_handoff_at', 'runner_confirmed_handoff_at');
    if v_n <> 2 then v_bad := v_bad || ' 인계 스탬프 컬럼 수=' || v_n || ' (한 쪽으로 합쳐졌다면 양면성이 사라진 것)'; end if;

    -- ⓑ neither party may write either stamp (0057 §R1 / 0083 §2 — restated because a pickup
    --    "simplification" would arrive as an RLS/grant change first)
    b_1 := t_frc_live(oo, dg, rt, rr);
    foreach v_txt in array array['owner', 'runner'] loop
      perform set_config('request.jwt.claim.sub',
                         case when v_txt = 'owner' then oo::text else rr::text end, false);
      begin
        set local role authenticated;
        update bookings set owner_confirmed_handoff_at = now() where id = b_1;
        reset role;
        v_bad := v_bad || ' ' || v_txt || '이 보호자 인계 스탬프를 썼다';
      exception when others then reset role;
      end;
      reset role;
      begin
        set local role authenticated;
        update bookings set runner_confirmed_handoff_at = now() where id = b_1;
        reset role;
        v_bad := v_bad || ' ' || v_txt || '이 러너 인계 스탬프를 썼다';
      exception when others then reset role;
      end;
      reset role;
    end loop;
    if (select b.owner_confirmed_handoff_at from bookings b where b.id = b_1) is not null
       or (select b.runner_confirmed_handoff_at from bookings b where b.id = b_1) is not null
      then v_bad := v_bad || ' 클라 쓰기가 실제로 들어갔다'; end if;
    -- …nor smuggle one in on a draft insert.
    -- ⚠ UPDATED 2026-08-19 by `0111_booking_entry_rebuild.sql`. The parenthetical was "(0083 §2's
    --   blacklist covers both handoff stamps)". It still does, but the blacklist is no longer what
    --   refuses HERE: 0111 revokes client INSERT on `bookings` outright, so this arm now sees a
    --   **42501** grant refusal instead of the blacklist's **P0001**, and
    --   `_guard_booking_insert_cols`'s client branch is unreachable by construction. The
    --   behavioural assertion — a client cannot land a draft carrying a handoff stamp — is
    --   unchanged. The new property is owned by suite 146 D-4·D-5·D-6 and D-20.
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      set local role authenticated;
      insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare,
                            addon_fare, total_price, min_fare, runner_confirmed_handoff_at)
      values (oo, dg, 'draft', now() + interval '1 day', 5.0, 9900, 15000, 0, 24900, 9900, now());
      reset role;
      v_bad := v_bad || ' 초안에 인계 스탬프 심기:통과';
    exception when others then reset role;
    end;
    reset role;
    -- positive control: the SAME draft without the stamp is still written (else ⓑ proves nothing)
    -- ⚠ UPDATED 2026-08-19 by 0111 — same reason as 119's twin control. It ran as `authenticated`
    --   and asserted an owner could insert a clean draft; after 0111 no client can insert a
    --   booking at all, so the control moves to `service_role`, the role that legitimately writes
    --   this row (`create-booking-hold`). Purpose unchanged: ⓑ must not be green merely because
    --   booking creation is dead. Suite 146 D-11 / D-20 own that property directly.
    begin
      set local role service_role;
      insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare,
                            addon_fare, total_price, min_fare)
      values (oo, dg, 'draft', now() + interval '1 day', 5.0, 9900, 15000, 0, 24900, 9900);
      reset role;
    exception when others then reset role;
      v_bad := v_bad || ' 서버(service_role) 초안 insert도 거부됨 (인계 스탬프 핀이 우연히 통과 — 예약 생성이 죽었다)';
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓒ 🔴 no database routine writes a non-null handoff stamp. Every SQL assignment in the repo
    --    is a RESET to null (the runner-swap / delegation-revoke paths, which UNDO a handoff and
    --    are therefore safe by construction). A new routine writing `now()` into either column is
    --    the exact shape of the "one RPC to finish pickup" simplification, and it lands here.
    --    ⚠ harness fixtures are excluded by name: `race_setup_*` builds a two-sided pickup state
    --    directly because it is simulating the edge function, and `t_*` are this repo's suite
    --    helpers. Product code has no such licence.
    select coalesce(string_agg(distinct s.proname || '←' || s.rhs, ', '), '') into v_txt
      from (
        select p.proname::text as proname,
               (regexp_matches(p.prosrc,
                  '(?:owner|runner)_confirmed_handoff_at\s*=\s*([^\s,;)]+)', 'g'))[1] as rhs
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prokind = 'f'
           and p.proname !~ '^(t_|race_setup|_t)'
      ) s
     where lower(s.rhs) <> 'null';
    if v_txt <> '' then v_bad := v_bad || ' SQL 루틴이 인계 스탬프를 찍는다: ' || v_txt; end if;
    -- positive control for the scan itself: the reset paths ARE found (else the regex is dead
    -- and ⓒ would stay green through any change at all)
    select count(*) into v_n
      from (
        select p.proname::text as proname,
               (regexp_matches(p.prosrc,
                  '(?:owner|runner)_confirmed_handoff_at\s*=\s*([^\s,;)]+)', 'g'))[1] as rhs
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prokind = 'f'
           and p.proname !~ '^(t_|race_setup|_t)'
      ) s
     where lower(s.rhs) = 'null';
    if v_n = 0 then v_bad := v_bad || ' 스캔이 아무것도 못 찾았다 (리셋 경로조차 — 정규식이 죽었다)'; end if;

    if v_bad = ''
      then call _pass('frc','F5 인계도 양측이다 — 픽업 인계 스탬프는 두 컬럼으로 남아 있고(합쳐지지 않았다), 보호자도 러너도 자기 쪽·상대 쪽 어느 스탬프도 UPDATE로든 초안 INSERT로든 못 쓰며(정상 초안은 통과), 어떤 DB 루틴도 인계 스탬프에 non-null을 쓰지 않는다 — 승격은 양쪽을 재조회하는 엣지 함수에만 있다 (Sean: "also handoff")');
    else v_msg := v_bad; call _fail('frc','F5 인계도 양측이다', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frc','F5 인계도 양측이다', v_msg);
  end;
end $$;
