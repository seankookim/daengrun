-- ═══ 130 incident-verification suite — 0094 pins (⑪: both sides, and the door that was dead) ═══
-- Sean, 2026-08-13, verbatim: "incident verified by both runner and owner."
--
-- ⚠ READ V1 AND V3 TOGETHER BEFORE CHANGING EITHER. The subtlety this suite exists to protect is
--   that ⑪ has TWO different one-sided/two-sided rules pointing opposite ways, and swapping them
--   is a safety bug in the literal sense:
--     · OPENING an incident is ONE-SIDED on purpose — a dog may be bleeding and the other party
--       may be unreachable. It costs nothing and decides nothing.
--     · VERIFYING is TWO-SIDED — that is the ruling, and it is what establishes the incident.
--     · **The phone door opens on the OPEN, not the verification** (Sean: "phone numbers should
--       be present during those emergency situations"). Requiring the other side to confirm
--       before you may telephone them is a deadlock exactly when it costs most.
--   A future reader "hardening" ⑪ by gating `incident_contact` on `verified_at` would pass a
--   naive reading of the ruling and break the emergency. V3 pins it in the safe direction.
--
-- What was actually broken before 0094, and is measured here rather than asserted:
--   `incidents` had NO WRITER anywhere in the repo, so `incident_contact()` (0088 §E) could
--   never return a row for a marketplace booking — the door Sean's phone ruling depends on was
--   built, correct, and connected to nothing. V3's first arm is that door working for the first
--   time; V3's control arm is that it still refuses a stranger.
--
-- Style: sibling of 119/125/128 — `_pass('ivf',…)`/`_fail('ivf',…)`, one begin…exception per
--   case, `_fail` arguments pre-computed into v_msg (the 110 header law). `set local role` +
--   `request.jwt.claim.sub` for every client path, and ALWAYS `reset role`.
-- ⚠ No pin here asserts a money amount, or any money at all — ⑪ decides whether an incident is
--   real; ⑫ (`0092`) decides what money does once it is. V5 pins that separation as a property.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   V1 ← 0094 §9: drop `open_incident_tx`'s booking-party check (the `0002:154` shape — checking
--        only `reporter_id = auth.uid()` and not WHICH booking). A stranger can then open an
--        incident on your booking, which under V3 hands YOUR two parties each other's phone
--        numbers on a third party's action                                              → RED
--        · or re-create the dropped `"incidents report"` INSERT policy, which is the same
--          hole one layer down                                                          → RED
--   V2 ← 0094 §10: 🔴 write `verified_at` on the FIRST stamp instead of on both — the ruling
--        inverted. Or drop the `p_side` identity check so a caller may stamp the other
--        party's side, which is the same thing wearing a party gate                     → RED
--   V3 ← 0094 §4: gate `incident_contact` on `verified_at` instead of `resolved_at is null`
--        (the plausible-sounding "hardening" that deadlocks an emergency)               → RED
--        · or widen it past the party gate — 0088 §E's scope is Sean's, and ⑪'s memo warns
--          specifically against a future reader widening this door                      → RED
--   V4 ← 0094 §11: let `runner`/`owner` force (0089's law, inherited), or make an ops force
--        write either party stamp — "ops established" and "both confirmed" then read the same
--        and the custody record is forged                                               → RED
--   V5 ← 0094 §11/§6: grant `force_verify_incident_tx` to authenticated, or make any function
--        in this file write `ledger_items`/`payments`/`bookings.status`                 → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13, from the worktree. Method: revert applied
--     to `0094` in place, WHOLE harness run (it drops and recreates the database each run, so a
--     migration edit fully re-applies), then restored from a pristine copy and re-verified by md5
--     + a green run. Pristine `0094` md5 `47912cc6d4d06d61d3b98b52c693fb53`; green is **539/0**.
--       P1 `if v_r is not null and v_o is not null` → `or` (verified_at on the FIRST stamp — the
--          ruling exactly inverted) → 538/1, red = [V2] alone. Detail carries all four arms:
--          `러너 혼자로 확립됐다 (판결의 정반대) … 같은 쪽 재도장이 확립시켰다 … 보호자 혼자로
--          확립됐다` — both orders and the idempotence arm, which is why V2 exercises both.
--       P2 `open_incident_tx`'s booking-party check deleted (i.e. `0002:154`'s own shape, only
--          WHO reports and never WHICH booking) → 538/1, red = [V1] alone, detail
--          `제3자가 남의 예약에 인시던트를 열었다 (원격 프라이버시 트리거)` — the hole reproducing
--          as what it actually costs: a stranger making YOUR two parties exchange phone numbers.
--       P3 🔴 `incident_contact` re-created with `and i.verified_at is not null` — the
--          plausible-sounding "hardening" a future reader would write from a naive reading of
--          Sean's ruling → 537/2, red = [V3, **0088's own G7**]. V3's detail is the cost:
--          `열린(미확인) 인시던트에서 번호 행=0 (긴급에 전화를 못 건다)`. The G7 cascade is not
--          noise and is the most reassuring result here — 0088 owns that door and notices when
--          another slice re-creates it, which is exactly the silent-revert class the REGISTRY's
--          shared-object table exists to catch, firing on its own.
--       P4 the ops force made to write both party stamps ("we established it, so call it
--          confirmed") → 538/1, red = [V4] alone, detail `판정이 러너 도장을 찍었다 (아무도 하지
--          않은 확인) … 분쟁 조회에 양측 확인으로 보인다` — 0089's law failing in a new room, and
--          the dispute-review oracle catching it.
--     V5 is NOT machine-proven as a primary: its grant matrix is the 116 C21 idiom (proven under
--     that suite) and its ⑪/⑫ separation arm is a presence/absence check with a positive control.
--     Named above with the single revert that would redden it; recorded as inherited, not fresh.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
create or replace function t_ivf_booking(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '1 hour', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  bk uuid; b2 uuid; inc uuid; inc2 uuid;
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_txt text; v_id uuid;
  v_denied boolean;
begin
  oo := t_user('ivf_oo', 'owner');
  rr := t_user('ivf_rr', 'runner'); rz := t_user('ivf_rz', 'runner');
  dg := t_dog(oo, '사고견'); rt := t_route('사고 코스');
  -- real numbers so V3 can prove the door hands over something, not just a row shape
  update profiles set phone = '010-1111-2222' where id = oo;
  update profiles set phone = '010-3333-4444' where id = rr;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [V1] opening is one-sided BUT party-scoped — 0002:154's hole, closed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The dropped policy checked WHO reported and never WHICH booking. Harmless while nothing read
  -- `incidents`; a remote privacy trigger the moment V3's door starts working. Both halves are
  -- pinned: the RPC refuses a stranger, and the raw table INSERT is gone as a second door.
  begin
    v_bad := '';
    bk := t_ivf_booking(oo, dg, rt, rr);

    -- ⓐ a party opens — one side is enough, deliberately (a dog may be bleeding)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    inc := open_incident_tx(bk, 'dog_injury', 'urgent', '앞발 절뚝임');
    if inc is null then v_bad := v_bad || ' 당사자가 인시던트를 못 열었다'; end if;
    if (select i.reporter_id from incidents i where i.id = inc) is distinct from rr
      then v_bad := v_bad || ' 신고자가 기록되지 않았다'; end if;
    if (select i.verified_at from incidents i where i.id = inc) is not null
      then v_bad := v_bad || ' 여는 것만으로 확립됐다 (한쪽 주장이 사실이 됐다)'; end if;

    -- ⓑ a double-tap in an emergency returns the SAME incident, not a second case
    inc2 := open_incident_tx(bk, 'dog_injury', 'sos', '다시 탭');
    if inc2 is distinct from inc then v_bad := v_bad || ' 두 번째 열기가 새 케이스를 만들었다'; end if;
    select count(*) into v_n from incidents where booking_id = bk and resolved_at is null;
    if v_n <> 1 then v_bad := v_bad || ' 열린 인시던트 수=' || v_n; end if;

    -- ⓒ 🔴 a STRANGER may not open one on someone else's booking
    perform set_config('request.jwt.claim.sub', rz::text, false);
    begin
      perform open_incident_tx(bk, 'other', 'normal', '남의 예약');
      v_bad := v_bad || ' 제3자가 남의 예약에 인시던트를 열었다 (원격 프라이버시 트리거)';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 제3자 거부 사유=' || sqlerrm; end if;
    end;
    -- ⓓ …and the raw table INSERT is not a second door (0002:154 dropped)
    perform set_config('request.jwt.claim.sub', rz::text, true);
    v_denied := false;
    begin
      set local role authenticated;
      begin
        execute 'insert into incidents (booking_id, reporter_id, kind) values ($1,$2,$3)'
          using bk, rz, 'other';
      exception when insufficient_privilege or check_violation then v_denied := true;
      end;
      reset role;
    exception when others then reset role; raise;
    end;
    if not v_denied then v_bad := v_bad || ' 정책을 지웠는데도 클라가 incidents에 직접 INSERT했다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓔ input validation — a free-text kind would make the enum a lie
    perform set_config('request.jwt.claim.sub', rr::text, false);
    b2 := t_ivf_booking(oo, dg, rt, rr);
    begin
      perform open_incident_tx(b2, '아무거나', 'normal', null);
      v_bad := v_bad || ' 알 수 없는 kind가 통과했다';
    exception when others then
      if sqlerrm <> 'bad_kind' then v_bad := v_bad || ' kind 거부=' || sqlerrm; end if;
    end;
    begin
      perform open_incident_tx(b2, 'other', '아주심각', null);
      v_bad := v_bad || ' 알 수 없는 severity가 통과했다';
    exception when others then
      if sqlerrm <> 'bad_severity' then v_bad := v_bad || ' severity 거부=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('ivf','V1 열기는 한쪽이지만 당사자여야 한다 — 당사자 한쪽이 열 수 있고(연 것만으로는 확립 아님)·재탭은 같은 케이스를 돌려주며·제3자는 not_party·0002:154의 원시 INSERT 정책은 사라져 두 번째 문이 없고·kind/severity는 화이트리스트다');
    else v_msg := v_bad; call _fail('ivf','V1 열기는 한쪽이지만 당사자여야 한다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ivf','V1 열기는 한쪽이지만 당사자여야 한다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [V2] 🔴 THE RULING — one stamp never establishes, two always do
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ the runner stamps. Recorded, and NOT established.
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := verify_incident_tx(inc, 'runner');
    if not coalesce((v_js->>'runner_verified')::boolean, false) then v_bad := v_bad || ' 러너 도장 미기록'; end if;
    if coalesce((v_js->>'verified')::boolean, true)
      then v_bad := v_bad || ' 러너 혼자로 확립됐다 (판결의 정반대)'; end if;
    if (select i.verified_at from incidents i where i.id = inc) is not null
      then v_bad := v_bad || ' 한쪽 도장인데 verified_at이 찍혔다'; end if;
    if (v_js->>'waiting_on') is distinct from 'owner' then v_bad := v_bad || ' waiting_on=' || coalesce(v_js->>'waiting_on','∅'); end if;

    -- ⓑ idempotent — the same side twice is success, not a raise
    v_js := verify_incident_tx(inc, 'runner');
    if coalesce((v_js->>'verified')::boolean, true) then v_bad := v_bad || ' 같은 쪽 재도장이 확립시켰다'; end if;

    -- ⓒ 🔴 a party may not stamp the OTHER side. "I am the owner" is a claim; auth.uid() is a fact.
    begin
      perform verify_incident_tx(inc, 'owner');   -- still the runner's jwt
      v_bad := v_bad || ' 러너가 보호자 쪽 도장을 찍었다 (한쪽이 양측을 만든다)';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 대리 도장 거부=' || sqlerrm; end if;
    end;
    -- and a total stranger gets nothing either
    perform set_config('request.jwt.claim.sub', rz::text, false);
    begin
      perform verify_incident_tx(inc, 'runner');
      v_bad := v_bad || ' 제3자가 확인했다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 제3자 거부=' || sqlerrm; end if;
    end;

    -- ⓓ the owner stamps → established, in the same breath
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := verify_incident_tx(inc, 'owner');
    if not coalesce((v_js->>'verified')::boolean, false) then v_bad := v_bad || ' 양측 도장인데 확립 안 됨'; end if;
    if (select i.verified_at from incidents i where i.id = inc) is null
      then v_bad := v_bad || ' verified_at 미기록'; end if;
    if (v_js->>'waiting_on') is not null then v_bad := v_bad || ' 확립 뒤에도 waiting_on이 남았다'; end if;
    -- both party stamps are real and distinct from the establishment
    if (select i.runner_verified_at from incidents i where i.id = inc) is null
      or (select i.owner_verified_at from incidents i where i.id = inc) is null
      then v_bad := v_bad || ' 확립됐는데 당사자 도장이 비었다'; end if;

    -- ⓔ the OTHER ORDER — owner first, then runner. A predicate can be wrong in one order only.
    perform set_config('request.jwt.claim.sub', rr::text, false);
    inc2 := open_incident_tx(b2, 'lost_dog', 'sos', '목줄 놓침');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := verify_incident_tx(inc2, 'owner');
    if coalesce((v_js->>'verified')::boolean, true) then v_bad := v_bad || ' 보호자 혼자로 확립됐다'; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := verify_incident_tx(inc2, 'runner');
    if not coalesce((v_js->>'verified')::boolean, false) then v_bad := v_bad || ' 반대 순서에서 확립 안 됨'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('ivf','V2 확립은 양측이다 — 한쪽 도장은 어느 순서에서도 verified_at을 찍지 않고, 같은 쪽 재도장은 멱등이며, 당사자가 상대 쪽 도장을 대신 찍을 수 없고(auth.uid가 사실이고 p_side는 주장일 뿐), 제3자는 not_party, 두 번째 도장에서 같은 호출로 확립된다');
    else v_msg := v_bad; call _fail('ivf','V2 확립은 양측이다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ivf','V2 확립은 양측이다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [V3] the phone door — alive for the first time, and OPEN-gated, not verified-gated
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Before 0094 this returned zero rows for every marketplace booking because nothing could
  -- write `incidents`. The first arm is therefore not a regression guard, it is the feature.
  -- The THIRD arm is the one that matters most: an UNVERIFIED open incident must already hand
  -- over the numbers, because that is when someone needs to make a phone call.
  begin
    v_bad := '';
    b2 := t_ivf_booking(oo, dg, rt, rr);

    -- ⓐ no incident → no numbers (and silence, not an error — 0088's oracle rule)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from incident_contact(b2);
    if v_n <> 0 then v_bad := v_bad || ' 인시던트 없는데 번호가 나왔다=' || v_n; end if;

    -- ⓑ 🔴 open it — UNVERIFIED — and the numbers are there NOW
    perform set_config('request.jwt.claim.sub', rr::text, false);
    inc2 := open_incident_tx(b2, 'dog_injury', 'sos', '긴급');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from incident_contact(b2);
    if v_n <> 2 then v_bad := v_bad || ' 열린(미확인) 인시던트에서 번호 행=' || v_n || ' (긴급에 전화를 못 건다)'; end if;
    if (select i.verified_at from incidents i where i.id = inc2) is not null
      then v_bad := v_bad || ' 픽스처가 이미 확립됐다 (ⓑ가 무의미해진다)'; end if;
    select string_agg(c.phone, ',' order by c.role) into v_txt from incident_contact(b2) c;
    if v_txt is distinct from '010-1111-2222,010-3333-4444'
      then v_bad := v_bad || ' 실제 번호가 아니라 형상만 돌아왔다=' || coalesce(v_txt,'∅'); end if;

    -- ⓒ a stranger still gets silence — the party gate is untouched by any of this
    perform set_config('request.jwt.claim.sub', rz::text, false);
    select count(*) into v_n from incident_contact(b2);
    if v_n <> 0 then v_bad := v_bad || ' 제3자에게 번호가 나갔다=' || v_n; end if;

    -- ⓓ resolving closes the door again
    perform set_config('request.jwt.claim.sub', '', false);
    update incidents set resolved_at = now() where id = inc2;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from incident_contact(b2);
    if v_n <> 0 then v_bad := v_bad || ' 해소된 뒤에도 번호가 나온다=' || v_n; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('ivf','V3 전화 문 — 0088의 문이 마침내 열린다: 인시던트가 없으면 0행, 열리면(확인 전이라도) 양측 실번호 2행, 제3자는 여전히 0행, 해소되면 다시 0행. 🔴 문은 "열림"에 열리지 "확립"에 열리지 않는다 — 긴급에 상대 확인을 기다리게 하는 것은 가장 비쌀 때의 교착이다');
    else v_msg := v_bad; call _fail('ivf','V3 전화 문', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ivf','V3 전화 문', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [V4] the ops force inherits 0089's law — no party may force, and a force stamps nobody
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b2 := t_ivf_booking(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    inc2 := open_incident_tx(b2, 'third_party', 'urgent', '제3자 개 접촉');
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓐ both parties refused BY NAME, from the phone and from the server class alike
    foreach v_txt in array array['runner','owner'] loop
      begin
        perform force_verify_incident_tx(inc2, v_txt, '판정', jsonb_build_object('kind','ops'));
        v_bad := v_bad || ' ' || v_txt || ' 강제 확립:통과';
      exception when others then
        if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' ' || v_txt || ' 거부=' || sqlerrm; end if;
      end;
    end loop;
    -- ⓑ ops owes evidence and a reason
    begin
      perform force_verify_incident_tx(inc2, 'ops', '이유만', null);
      v_bad := v_bad || ' 증거 없는 판정:통과';
    exception when others then
      if sqlerrm <> 'evidence_required' then v_bad := v_bad || ' 증거 거부=' || sqlerrm; end if;
    end;
    begin
      perform force_verify_incident_tx(inc2, 'ops', '', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' 사유 없는 판정:통과';
    exception when others then
      if sqlerrm <> 'reason_required' then v_bad := v_bad || ' 사유 거부=' || sqlerrm; end if;
    end;
    -- ⓒ a phone claiming ops
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform force_verify_incident_tx(inc2, 'ops', '내가 운영', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' 폰이 ops를 자칭:통과';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' ops 자칭 거부=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    -- ⓓ 🔴 a real ops force establishes and stamps NEITHER party
    v_js := force_verify_incident_tx(inc2, 'ops', '보호자 연락 두절 — 운영 판정',
                                     jsonb_build_object('kind','ops_adjudication','ticket','OPS-3120'));
    if not coalesce((v_js->>'forced')::boolean, false) then v_bad := v_bad || ' ops 판정이 거부됐다'; end if;
    if (select i.verified_at from incidents i where i.id = inc2) is null
      then v_bad := v_bad || ' 판정했는데 확립되지 않았다'; end if;
    if (select i.runner_verified_at from incidents i where i.id = inc2) is not null
      then v_bad := v_bad || ' 판정이 러너 도장을 찍었다 (아무도 하지 않은 확인)'; end if;
    if (select i.owner_verified_at from incidents i where i.id = inc2) is not null
      then v_bad := v_bad || ' 판정이 보호자 도장을 찍었다'; end if;
    if (select i.verify_forced_by from incidents i where i.id = inc2) is distinct from 'ops'
      then v_bad := v_bad || ' 행위자 미기록'; end if;
    -- THE ORACLE: "ops established" and "both confirmed" must be distinguishable from the row
    if (select i.runner_verified_at is not null and i.owner_verified_at is not null
          from incidents i where i.id = inc2)
      then v_bad := v_bad || ' 분쟁 조회에 양측 확인으로 보인다'; end if;
    -- ⓔ first-writer-wins
    v_js := force_verify_incident_tx(inc2, 'ops', '다시 쓴다', jsonb_build_object('kind','ops'));
    if coalesce((v_js->>'forced')::boolean, true) then v_bad := v_bad || ' 두 번째 판정이 다시 기록했다'; end if;
    if (select i.verify_force_reason from incidents i where i.id = inc2) <> '보호자 연락 두절 — 운영 판정'
      then v_bad := v_bad || ' 두 번째 판정이 첫 사유를 덮었다'; end if;
    -- ⓕ the column refuses a party actor even by direct UPDATE
    begin
      update incidents set verify_forced_by = 'runner' where id = inc2;
      v_bad := v_bad || ' 컬럼이 runner를 받았다';
    exception when check_violation then null;
      when others then v_bad := v_bad || ' 컬럼 거부가 체크 위반이 아니다=' || sqlerrm;
    end;

    if v_bad = ''
      then call _pass('ivf','V4 판정은 확인이 아니다 — runner/owner는 force_party_forbidden으로 이름을 불려 거부되고, ops도 증거·사유가 없으면 거부되며 폰의 ops 자칭은 not_party, 진짜 판정은 확립만 시키고 🔴 어느 쪽 도장도 찍지 않아 "ops 확립"과 "양측 확인"이 행 하나로 구분되며, 두 번째 판정은 첫 기록을 덮지 않고 컬럼 제약도 당사자를 거부한다');
    else v_msg := v_bad; call _fail('ivf','V4 판정은 확인이 아니다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ivf','V4 판정은 확인이 아니다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [V5] grants, and the ⑪/⑫ separation held as a property
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⑪ decides whether an incident is REAL. ⑫ (0092) decides what money does once it is. A slice
  -- that quietly moved money or the booking's status here would pass every pin above while
  -- re-coupling the two questions Sean deliberately separated.
  begin
    v_bad := '';
    if has_function_privilege('authenticated', 'force_verify_incident_tx(uuid,text,text,jsonb)', 'execute')
      then v_bad := v_bad || ' 강제가 authenticated에 열렸다'; end if;
    if has_function_privilege('anon', 'force_verify_incident_tx(uuid,text,text,jsonb)', 'execute')
      then v_bad := v_bad || ' 강제가 anon에 열렸다'; end if;
    if not has_function_privilege('service_role', 'force_verify_incident_tx(uuid,text,text,jsonb)', 'execute')
      then v_bad := v_bad || ' 강제가 service_role에서 막혔다'; end if;
    -- positive control: the two-sided path IS the client's — both parties may confirm
    foreach v_txt in array array['open_incident_tx(uuid,text,text,text,text[])','verify_incident_tx(uuid,text)'] loop
      if not has_function_privilege('authenticated', v_txt, 'execute')
        then v_bad := v_bad || ' ' || v_txt || ':authenticated 불가'; end if;
      if has_function_privilege('anon', v_txt, 'execute')
        then v_bad := v_bad || ' ' || v_txt || ':anon 가능'; end if;
    end loop;
    -- every function in this slice is a definer with a pinned search_path (98 H1's law, locally)
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('open_incident_tx','verify_incident_tx','force_verify_incident_tx')
           and p.prosecdef and 'search_path=public, pg_temp' = any(p.proconfig)) <> 3
      then v_bad := v_bad || ' definer/search_path가 셋 다 갖춰지지 않았다'; end if;

    -- 🔴 the separation: nothing in this slice moved money or the booking
    b2 := t_ivf_booking(oo, dg, rt, rr);
    v_txt := (select b.status::text from bookings b where b.id = b2);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    inc2 := open_incident_tx(b2, 'equipment', 'normal', '하네스 파손');
    perform verify_incident_tx(inc2, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform verify_incident_tx(inc2, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if (select i.verified_at from incidents i where i.id = inc2) is null
      then v_bad := v_bad || ' 양성 대조 실패: 확립되지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b2) is distinct from v_txt
      then v_bad := v_bad || ' ⑪이 예약 상태를 옮겼다 (incident_review 막다른 길로 밀어넣는다)'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b2)
      then v_bad := v_bad || ' ⑪이 원장을 썼다 (돈은 ⑫의 질문이다)'; end if;
    if exists (select 1 from payments p where p.booking_id = b2)
      then v_bad := v_bad || ' ⑪이 결제 행을 만들었다'; end if;

    if v_bad = ''
      then call _pass('ivf','V5 권한과 ⑪/⑫ 분리 — 강제는 service_role 전용이고 열기·확인은 authenticated(양성 대조 포함)·anon은 전부 거부, 셋 다 definer+search_path 고정, 그리고 양측 확립이 끝나도 예약 상태·원장·결제는 하나도 움직이지 않는다 (⑪은 사실 여부, ⑫는 돈)');
    else v_msg := v_bad; call _fail('ivf','V5 권한과 ⑪/⑫ 분리', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ivf','V5 권한과 ⑪/⑫ 분리', v_msg);
  end;
end $$;
