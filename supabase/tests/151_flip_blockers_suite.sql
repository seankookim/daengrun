-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 151 — 0116 flip-blockers: the four defects that are inert today and real on flip day
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Every pin here is written BOTH ways on purpose. A one-sided pin on a gate is the failure this
-- repo has now made three times in a week: a fixture that exercises only the side the fix already
-- allowed stays green when the fix is deleted (110 S1's own header records it, twice).
--
-- ─── MUTATION MAP (measured, not predicted — each fix deleted in turn, full harness re-run) ───
--   §A delete `and rn.settled_at is not null` from sweep_settled_without_payments
--                                                              → RED = [B1] (+116 C9)
--   §B delete the `update bookings set cancel_fee`             → RED = [B2]
--   §B delete the ledger_items insert                          → RED = [B2]
--   §C revert dispatch_due_charges to the open-coded predicate  → RED = [B3]
--   §C delete the `charge_max_attempts()` arm of charge_row_due → RED = [B4]
--   §D ⓐ delete the club_incident_settle_quote party gate      → RED = [B5]
--   §D ⓑ delete the runner_work_gate party gate                → RED = [B6]
--   §D ⓒ delete the club_dog_ui_state party gate               → RED = [B7]
--   §D ⓓ delete the club_host_stats session gate               → RED = [B8]
--   The exact sets are reproduced in the commit message; a pin that survived its own fix being
--   deleted was rewritten until it did not.
--
-- ─── Two fixture notes that are load-bearing ───────────────────────────────────────────────
--  ① [B3] BUILDS ITS OWN vault stub. Without one `dispatch_due_charges` returns 0 for lack of a
--     secret whether or not the poisoned row killed the count, so the fix and the bug are
--     indistinguishable and the pin would be theatre. With the stub the function reaches its
--     return and the number it returns IS the answer. `net.http_post` is already stubbed by the
--     harness (0024), so only `vault.decrypted_secrets` is invented here.
--  ② [B3] also proves its own poison. Before asserting that the NEW rule survives the row, it
--     executes the OLD open-coded predicate against the same table and requires it to RAISE. A
--     fixture whose "unparseable" timestamp happened to parse would make every other assertion in
--     that pin vacuous, and nothing would say so.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

do $$
declare
  oo uuid; oz uuid; rr uuid; hh uuid; zz uuid; ol uuid;
  dg uuid; dz uuid; dl uuid; rt uuid;
  v_club uuid; v_s uuid; v_s2 uuid; sda uuid; sdz uuid; sdl uuid; sd2 uuid;
  ba uuid; b2 uuid; b_free uuid; b_mkt uuid; b_pay uuid;
  v_inc uuid;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_js jsonb; v_js2 jsonb;
  v_since timestamptz;
  v_fee int; v_share int; v_plat int; v_total int; v_ledger bigint; v_pre bigint;
  q record; v_err boolean; v_txt text;
begin
  -- ---------- shared seed ----------
  -- ⚠ THE CLUB FIXTURE IS BUILT HERE, AT TOP LEVEL, AND NOT INSIDE [B2]. A plpgsql
  -- `begin … exception` block is a SUBTRANSACTION: when it catches, everything the block wrote is
  -- ROLLED BACK. A first draft of this suite built the club, the session and the paid delegation
  -- inside B2 — B2 then failed on an unrelated `checkin_window`, its rollback took the fixture
  -- with it, and B5 and B7 reported `not_found` about a session that had existed a moment earlier.
  -- Three pins, one root cause, and two of the three red messages named the wrong thing. This is
  -- 110's recorded house law (`_fail` arguments are pre-computed for the same reason) applied to
  -- the fixture itself: state that more than one pin depends on lives OUTSIDE every pin.
  hh := t_user('fbl_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr := t_user('fbl_rr', 'runner');
  oo := t_user('fbl_oo', 'owner');  dg := t_dog(oo, '차단견');
  oz := t_user('fbl_oz', 'owner');  dz := t_dog(oz, '남의견');
  ol := t_user('fbl_ol', 'owner');  dl := t_dog(ol, '미승인견');
  zz := t_user('fbl_zz', 'owner');                       -- 완전한 무관자
  rt := t_route('차단 코스');

  -- a paid, assigned, accepted club delegation — B2 cancels it, B5 quotes it, B7 projects it
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('차단동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '차단 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  sda := session_delegate_dog(v_s, dg, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sda, true);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  b_pay := session_pay_delegation(sda, 'idem-fbl-a', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sda, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_proposal_respond(sda, true);
  -- a 'limited' member for B7: a dog delegated into the same session but never approved
  perform set_config('request.jwt.claim.sub', ol::text, false);
  sdl := session_delegate_dog(v_s, dl, t_consent());
  -- the free-window session for B2's negative control. ⚠ NO `session_checkin` — check-in has a
  -- window and a session 48h out refuses it; the control needs the CLOCK, not attendance.
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_s2 := club_create_session(v_club, now() + interval '48 hours', '무료창 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s2);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s2);
  perform set_config('request.jwt.claim.sub', '', false);

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B1] §A the sweep bills a SETTLED run, and refuses one that merely STOPPED
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0083 §6 changed `runs.ended_at` from "settlement" to "the stop". The sweep kept billing on
  -- it, so it could mint the owner's charge while the dog was still with the runner (§0-tricies
  -- item 1, verified live). Both arms are here because the positive one alone would stay green
  -- under a predicate that refuses EVERYTHING, and the negative one alone would stay green under
  -- a sweep that was simply deleted.
  begin
    v_bad := '';
    select f.payments_live_since into v_since from ops_flags f where f.id;   -- restore at the end
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- ⓐ settled: run stopped AND money happened → a charge is owed and must be minted
    ba := t_av_booking(oo, dg, rt, rr, now() - interval '4 hours', 5.0, 'completed');
    insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
    values (ba, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
            5.0, 'completed'::end_reason);
    -- ⓑ stopped but NOT returned: same ended_at, same end_reason, same km — settled_at is the
    --    ONLY difference between the two rows, which is what makes this pin about the predicate
    --    rather than about anything else in the sweep.
    b2 := t_av_booking(oz, dz, rt, rr, now() - interval '4 hours', 5.0, 'active');
    insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
    values (b2, now() - interval '4 hours', now() - interval '3 hours', null,
            5.0, 'completed'::end_reason);

    perform sweep_settled_without_payments();

    select count(*) into v_n from payments where booking_id = ba;
    if v_n <> 1 then v_bad := v_bad || ' 정산된 런에 청구가 안 생겼다(=' || v_n || ') — 술어가 전부를 막는다'; end if;
    select count(*) into v_n2 from payments where booking_id = b2;
    if v_n2 <> 0 then v_bad := v_bad || ' 🔴 목줄에 매인 개에게 청구가 발행됐다(=' || v_n2 || ') — settled_at 가드 없음'; end if;

    -- and the sweep is still idempotent for the settled one
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments where booking_id = ba;
    if v_n <> 1 then v_bad := v_bad || ' 2회차 스윕이 행을 더 만들었다=' || v_n; end if;

    -- the moment the return seal lands, the same row becomes billable — the gate is settlement,
    -- not a permanent refusal (the arm that catches "just never mint anything")
    update runs set settled_at = now() where booking_id = b2;
    perform sweep_settled_without_payments();
    select count(*) into v_n2 from payments where booking_id = b2;
    if v_n2 <> 1 then v_bad := v_bad || ' 정산 도장이 찍힌 뒤에도 청구가 안 생겼다=' || v_n2; end if;

    update ops_flags set payments_live_since = v_since, updated_at = now();

    if v_bad = ''
      then call _pass('fbl','B1 §A 스윕의 앵커는 정산이지 정지가 아니다 — settled_at이 있는 런은 청구되고(멱등), ended_at만 있고 반환 봉인이 없는 런은 청구되지 않으며, 그 도장이 찍히는 순간 같은 행이 청구 가능해진다 (0083 §0f가 0080에게 넘긴 한 줄)');
    else v_msg := v_bad; call _fail('fbl','B1 §A 스윕 앵커', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = v_since, updated_at = now();
    v_msg := sqlerrm; call _fail('fbl','B1 §A 스윕 앵커', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B2] §B the club cancel fee reaches the money, and the runner's share reaches the ledger
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `_club_record_cancel_fee` wrote `club_fee_items` and nothing else, so `mint_cancel_fee_intent`
  -- (which reads `bookings.cancel_fee`) and `owner_has_unsettled_charge` (which scopes on it) both
  -- saw ZERO for a club cancellation, and the runner's supply-compensation share existed only as a
  -- row nothing pays from. 66 F5 already pins the LADDER; this pins the PLUMBING, and pins it as
  -- plumbing: every number asserted here is compared against what the existing club_fee_items rows
  -- already say, never against a rate this suite invents. Which ladder governs is Sean's open
  -- ruling (§0-tricies item 2) and no pin here has an opinion about it.
  begin
    v_bad := '';
    select total_price into v_total from bookings where id = b_pay;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_pre := my_ledger_total();

    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform session_cancel_delegation(sda);                    -- 수락 후 취소 = 사다리 상단

    -- what the EXISTING code computed, read back from its own ledger of intent
    select coalesce(sum(amount_krw), 0) into v_fee
      from club_fee_items where session_dog_id = sda and kind = 'cancel_fee';
    select coalesce(sum(amount_krw), 0) into v_share
      from club_fee_items where session_dog_id = sda and kind = 'cancel_fee'
        and basis->>'share' = 'supply_compensation';
    select coalesce(sum(amount_krw), 0) into v_plat
      from club_fee_items where session_dog_id = sda and kind = 'cancel_fee'
        and basis->>'share' = 'platform';
    if v_fee <= 0 then v_bad := v_bad || ' 픽스처가 수수료를 만들지 못했다 (핀이 공허해진다)'; end if;
    if v_share <= 0 then v_bad := v_bad || ' 픽스처가 러너 몫을 만들지 못했다'; end if;
    if v_fee <> v_plat + v_share then v_bad := v_bad || ' 픽스처 산술 불일치 ' || v_fee || '<>' || v_plat || '+' || v_share; end if;

    -- ⓐ the owner's side — the number the mint and the debt gate read
    if (select cancel_fee from bookings where id = b_pay) is distinct from v_fee
      then v_bad := v_bad || ' 🔴 bookings.cancel_fee=' || coalesce((select cancel_fee from bookings where id = b_pay)::text, '∅')
        || ' (기록된 수수료 ' || v_fee || '와 다르다 — 청구 민팅과 부채 게이트가 0을 본다)'; end if;

    -- ⓑ the runner's side — a ledger row carrying exactly the supply-compensation share
    select count(*) into v_n from ledger_items where booking_id = b_pay;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n || ' (부킹당 1행)'; end if;
    if not exists (select 1 from ledger_items li where li.booking_id = b_pay
                     and li.runner_id = rr and li.remaining_guarantee = v_share
                     and li.platform_fee = 0)
      then v_bad := v_bad || ' 🔴 러너 공급보상이 원장에 없다 (기대 remaining_guarantee=' || v_share || ', platform_fee=0)'; end if;

    -- ⓒ and it actually reaches what the runner is SHOWN. platform_fee is subtracted by
    --    my_ledger_total (0085's measured trap), so a "double-entry" write here would net to 0.
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_ledger := my_ledger_total();
    if v_ledger - v_pre <> v_share
      then v_bad := v_bad || ' my_ledger_total 증가분=' || (v_ledger - v_pre) || ' (기대 ' || v_share || ')'; end if;

    -- ⓓ idempotence: the shared `comp:` key space means one booking gets one ledger row even if a
    --    second comp writer runs. Calling the recorder again must add nothing.
    perform _club_record_cancel_fee(v_s, sda, b_pay, 'cancel_fee', v_total, 20, rr, 'post_acceptance');
    select count(*) into v_n from ledger_items where booking_id = b_pay;
    if v_n <> 1 then v_bad := v_bad || ' 재호출이 원장 행을 추가했다=' || v_n; end if;
    if (select cancel_fee from bookings where id = b_pay) is distinct from v_fee
      then v_bad := v_bad || ' 재호출이 이미 기록된 청구 금액을 바꿨다'; end if;

    -- ⓔ NEGATIVE CONTROL — the free tier writes nothing anywhere. Without this arm a plumbing
    --    that wrote a fee unconditionally would pass every assertion above.
    perform set_config('request.jwt.claim.sub', oz::text, false);
    sdz := session_delegate_dog(v_s2, dz, t_consent());
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_approve_dog(sdz, true);
    perform set_config('request.jwt.claim.sub', oz::text, false);
    b_free := session_pay_delegation(sdz, 'idem-fbl-free', true);
    perform session_cancel_delegation(sdz);                    -- 24h 밖 · 미배정 = 무료
    if exists (select 1 from club_fee_items where session_dog_id = sdz)
      then v_bad := v_bad || ' 무료창인데 수수료 행이 생겼다 (픽스처가 무료 티어가 아니다)'; end if;
    if coalesce((select cancel_fee from bookings where id = b_free), 0) <> 0
      then v_bad := v_bad || ' 🔴 무료 취소에 청구 금액이 기록됐다=' || (select cancel_fee from bookings where id = b_free); end if;
    if exists (select 1 from ledger_items where booking_id = b_free)
      then v_bad := v_bad || ' 🔴 무료 취소에 원장이 생겼다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('fbl','B2 §B 클럽 취소 수수료가 돈에 닿는다 — bookings.cancel_fee(민팅·부채 게이트가 읽는 유일한 숫자)와 러너 공급보상 원장 1행(remaining_guarantee, platform_fee=0 → my_ledger_total에 그대로 더해진다)이 club_fee_items가 이미 계산한 값과 정확히 같고, 재호출은 아무것도 더하지 않으며, 무료 티어는 세 곳 모두에 아무것도 쓰지 않는다 (사다리 선택 없음 — 배관만)');
    else v_msg := v_bad; call _fail('fbl','B2 §B 클럽 취소 수수료 배관', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fbl','B2 §B 클럽 취소 수수료 배관', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B3] §C one unparseable timestamp must fail its OWN ROW, never the batch
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The old predicate cast `(raw->>'next_retry_at')::timestamptz` inside the count, so one row
  -- raised, the function's outer handler swallowed it, and it returned 0 — the ladder never woke
  -- FOR ANYBODY while that row existed. See the header for why this pin builds a vault stub: with
  -- no secret the function returns 0 whether or not it was poisoned, and the pin would prove
  -- nothing.
  begin
    v_bad := '';
    create schema if not exists vault;
    create table if not exists vault.decrypted_secrets (name text, decrypted_secret text);
    delete from vault.decrypted_secrets where name = 'charge_dispatch';
    insert into vault.decrypted_secrets values
      ('charge_dispatch', '{"url":"http://harness.invalid","cron_key":"k"}');

    b_mkt := t_av_booking(oo, dg, rt, rr, now() - interval '2 hours', 5.0, 'completed');
    insert into payments (booking_id, order_id, amount, status, raw) values
      (b_mkt, 'dr_fbl_ok1', 24900, 'failed',
       jsonb_build_object('kind','settle_charge','attempts',1,'next_retry_at',(now() - interval '1 hour')::text)),
      (b_mkt, 'dr_fbl_ok2', 24900, 'pending',
       jsonb_build_object('kind','settle_charge','attempts',0)),
      -- ☠ the poisoned row
      (b_mkt, 'dr_fbl_poison', 24900, 'failed',
       jsonb_build_object('kind','settle_charge','attempts',1,'next_retry_at','not-a-timestamp'));

    -- ① the fixture really is poisonous — the OLD predicate raises on this very table
    v_err := false;
    begin
      select count(*) into v_n from payments p
       where (p.raw->>'kind') is not null and p.amount > 0 and p.status = 'failed'
         and coalesce((p.raw->>'next_retry_at')::timestamptz, '-infinity'::timestamptz) <= now();
    exception when others then v_err := true;
    end;
    if not v_err then v_bad := v_bad || ' 픽스처가 위험을 재현하지 못한다 — 옛 술어가 이 테이블에서 raise하지 않았다'; end if;

    -- ② the rule survives it, and calls the poisoned row DUE (TS isDue's direction: an
    --    unparseable rung is not an exemption — one extra attempt, bounded by the cap)
    select count(*) into v_n from payments p
     where p.booking_id = b_mkt and charge_row_due(p.status, p.amount, p.raw, now());
    if v_n <> 3 then v_bad := v_bad || ' 규칙이 센 due 행수=' || v_n || ' (기대 3: 정상2 + 오염1)'; end if;
    if not charge_row_due('failed', 24900,
         '{"kind":"settle_charge","attempts":1,"next_retry_at":"not-a-timestamp"}'::jsonb, now())
      then v_bad := v_bad || ' 파싱 불가 next_retry_at이 due가 아니다 (TS는 due로 본다)'; end if;

    -- ③ 🔴 THE PIN — the batch still wakes, and the number it reports includes every row
    v_n := dispatch_due_charges();
    if v_n < 3 then v_bad := v_bad || ' 🔴 오염된 행 하나가 배치를 재웠다 — dispatch_due_charges=' || v_n
      || ' (기대 ≥3: 이 예약의 due 행만 3개)'; end if;

    -- ④ the same table with the poison REMOVED must not change the other two rows' verdict —
    --    otherwise ③ could be passing for a reason unrelated to the poison
    delete from payments where order_id = 'dr_fbl_poison';
    v_n2 := dispatch_due_charges();
    if v_n2 <> v_n - 1 then v_bad := v_bad || ' 오염 제거 전후 차이=' || (v_n - v_n2) || ' (기대 1)'; end if;

    delete from vault.decrypted_secrets where name = 'charge_dispatch';

    if v_bad = ''
      then call _pass('fbl','B3 §C 오염된 타임스탬프는 그 행만 떨어뜨린다 — 옛 술어가 raise하는 바로 그 테이블에서 dispatch_due_charges가 여전히 깨어나 모든 due 행을 세고(오염 행 포함), 오염 행을 빼면 정확히 하나 줄어든다 (금고 스텁이 없으면 고친 것과 망가진 것이 둘 다 0을 돌려줘 핀이 연극이 된다)');
    else v_msg := v_bad; call _fail('fbl','B3 §C 오염 행 격리', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('fbl','B3 §C 오염 행 격리', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B4] §C the due rule agrees with isDue() arm for arm, and the cap has ONE definition
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `collect-charges/handler.ts` isDue() is the other half of this rule. Each line below is one of
  -- its branches, executed rather than read. The cap is pinned against a LITERAL — re-deriving it
  -- from charge_max_attempts() would assert nothing at all.
  begin
    v_bad := '';
    if charge_max_attempts() <> 3 then v_bad := v_bad || ' 사다리 상한=' || charge_max_attempts() || ' (TS MAX_ATTEMPTS=3과 갈라졌다)'; end if;
    -- failed arm
    if charge_row_due('failed', 100, '{"kind":"k","attempts":3}'::jsonb, now())
      then v_bad := v_bad || ' 소진된 사다리(attempts=3)가 due다'; end if;
    if not charge_row_due('failed', 100, '{"kind":"k","attempts":2}'::jsonb, now())
      then v_bad := v_bad || ' attempts=2가 due가 아니다'; end if;
    if not charge_row_due('failed', 100, '{"kind":"k","attempts":"2"}'::jsonb, now())
      then v_bad := v_bad || ' 문자열 "2"가 due가 아니다 (TS Number("2")=2)'; end if;
    if not charge_row_due('failed', 100, '{"kind":"k","attempts":"junk"}'::jsonb, now())
      then v_bad := v_bad || ' 파싱 불가 attempts가 due가 아니다 (TS NaN>=cap = false ⇒ due)'; end if;
    if not charge_row_due('failed', 100, '{"kind":"k","attempts":1}'::jsonb, now())
      then v_bad := v_bad || ' next_retry_at 부재가 due가 아니다 (스윕이 뒤집은 무카드 행이 영영 안 걷힌다)'; end if;
    if charge_row_due('failed', 100, '{"kind":"k","attempts":1,"next_retry_at":"2999-01-01T00:00:00Z"}'::jsonb, now())
      then v_bad := v_bad || ' 아직 안 온 rung이 due다'; end if;
    if charge_row_due('failed', 100, '{"kind":"k","attempts":1,"needs_card_relink":true}'::jsonb, now())
      then v_bad := v_bad || ' 죽은 카드가 타이머로 재시도된다'; end if;
    if charge_row_due('failed', 100, '{"kind":"k","attempts":1,"needs_card_relink":"junk"}'::jsonb, now())
      then v_bad := v_bad || ' 파싱 불가 relink 플래그가 안전한 쪽(설정됨)으로 안 읽혔다'; end if;
    if not charge_row_due('failed', 100, '{"kind":"k","attempts":1,"needs_card_relink":false}'::jsonb, now())
      then v_bad := v_bad || ' relink=false가 due가 아니다'; end if;
    -- pending arms
    if not charge_row_due('pending', 100, '{"kind":"k"}'::jsonb, now())
      then v_bad := v_bad || ' 미발송 인텐트가 due가 아니다'; end if;
    if charge_row_due('pending', 100, ('{"kind":"k","dispatched_at":"' || now()::text || '"}')::jsonb, now())
      then v_bad := v_bad || ' 방금 발송된 pending이 due다 (블라인드 재청구)'; end if;
    if not charge_row_due('pending', 100,
         ('{"kind":"k","dispatched_at":"' || (now() - interval '20 minutes')::text || '"}')::jsonb, now())
      then v_bad := v_bad || ' 15분 넘은 발송 pending이 검증 대상으로 안 잡힌다'; end if;
    if charge_row_due('pending', 100, '{"kind":"k","dispatched_at":"junk"}'::jsonb, now())
      then v_bad := v_bad || ' 파싱 불가 dispatched_at이 재청구 대상이 됐다 (TS isStaleDispatched는 false)'; end if;
    -- the two gates above the status split
    if charge_row_due('failed', 100, '{}'::jsonb, now())
      then v_bad := v_bad || ' 위젯 시대 행(kind 없음)이 due다'; end if;
    if charge_row_due('failed', 0, '{"kind":"k"}'::jsonb, now())
      then v_bad := v_bad || ' 0원 행이 due다 (waive가 되지 못한 행)'; end if;
    -- and the rule never answers NULL: a money rule says yes or no
    if (select charge_row_due('pending', 100, '{"kind":"k","dispatched_at":"junk"}'::jsonb, now())) is null
      then v_bad := v_bad || ' 규칙이 NULL을 돌려준다'; end if;

    if v_bad = ''
      then call _pass('fbl','B4 §C due 규칙이 isDue()와 가지별로 일치한다 — 사다리 상한 리터럴 3, 소진/미도래/죽은 카드는 거절, 부재·파싱불가 rung과 파싱불가 attempts는 due, 미발송 pending은 due이고 방금 발송된 것은 아니며 15분 넘은 것은 검증 대상, kind 없음·0원은 어느 쪽도 아니고, 답이 NULL인 경우가 없다');
    else v_msg := v_bad; call _fail('fbl','B4 §C due 규칙 일치', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('fbl','B4 §C due 규칙 일치', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B5] §D ⓐ club_incident_settle_quote — a stranger cannot price someone else's booking
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- It hands out total_price, every fare component, the measured km, BOTH handoff stamps and the
  -- runner's commission-derived fee. Four legitimate audiences are pinned alongside the refusal,
  -- because a gate that also refuses the case screen is not a fix.
  begin
    v_bad := '';
    -- ⓐ the host of the booking's own club session
    perform set_config('request.jwt.claim.sub', hh::text, false);
    begin
      select * into q from club_incident_settle_quote(b_pay, 'settle_measured');
      if q.refund is null then v_bad := v_bad || ' 호스트가 빈 답을 받았다'; end if;
    exception when others then v_bad := v_bad || ' 🔴 호스트가 거절당했다=' || sqlerrm;
    end;
    -- ⓑ the booking's own owner
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      select * into q from club_incident_settle_quote(b_pay, 'refund_full');
      if q.refund is null then v_bad := v_bad || ' 보호자가 빈 답을 받았다'; end if;
    exception when others then v_bad := v_bad || ' 🔴 보호자가 거절당했다=' || sqlerrm;
    end;
    -- ⓒ 🔴 THE REFUSAL — an unrelated signed-in user
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_err := false; v_txt := '';
    begin
      select * into q from club_incident_settle_quote(b_pay, 'settle_measured');
    exception when others then v_err := true; v_txt := sqlerrm;
    end;
    if not v_err then v_bad := v_bad || ' 🔴 무관자가 남의 부킹 금액·인계 시각을 읽었다'; end if;
    -- ⓓ and "no such booking" gets the SAME sentence — otherwise this is an id enumeration oracle
    v_msg := '';
    begin
      select * into q from club_incident_settle_quote(gen_random_uuid(), 'settle_measured');
    exception when others then v_msg := sqlerrm;
    end;
    if v_txt is distinct from v_msg
      then v_bad := v_bad || ' 없는 부킹(' || coalesce(v_msg,'∅') || ')과 남의 부킹(' || coalesce(v_txt,'∅') || ')의 답이 다르다 — 열거 오라클'; end if;

    -- ⓔ the CASE arm — the shipped client path (app/app/club/case/[cid].tsx quotes a booking from
    --    a case screen). A marketplace booking with no club session at all is reachable to the
    --    host of the session whose incident NAMES it, and to nobody else.
    b_mkt := t_av_booking(oz, dz, rt, rr, now() - interval '5 hours', 5.0, 'incident_review');
    insert into club_incidents (session_id, severity, state, opened_by, summary)
    values (v_s, 'S2', 'open', hh, '견적 게이트 픽스처 — 케이스 팔') returning id into v_inc;
    insert into club_incident_subjects (incident_id, subject_type, subject_id)
    values (v_inc, 'booking', b_mkt);
    perform set_config('request.jwt.claim.sub', hh::text, false);
    begin
      select * into q from club_incident_settle_quote(b_mkt, 'settle_measured');
      if q.refund is null then v_bad := v_bad || ' 케이스 호스트가 빈 답을 받았다'; end if;
    exception when others then v_bad := v_bad || ' 🔴 케이스 호스트가 거절당했다=' || sqlerrm || ' (케이스 화면이 죽는다)';
    end;
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_err := false;
    begin
      select * into q from club_incident_settle_quote(b_mkt, 'settle_measured');
    exception when others then v_err := true;
    end;
    if not v_err then v_bad := v_bad || ' 🔴 케이스 주체 부킹이 무관자에게 열려 있다'; end if;

    -- ⓕ a server caller (no JWT) is unaffected — the exemption §D relies on, pinned not assumed
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      select * into q from club_incident_settle_quote(b_pay, 'pay_full');
      if q.refund is null then v_bad := v_bad || ' 서버 호출자가 빈 답을 받았다'; end if;
    exception when others then v_bad := v_bad || ' 서버 호출자가 거절당했다=' || sqlerrm;
    end;

    if v_bad = ''
      then call _pass('fbl','B5 §D ⓐ 정산 견적에 당사자 게이트가 생겼다 — 부킹의 호스트·보호자·케이스 호스트는 답을 받고, 무관자는 거절되며, 없는 부킹과 남의 부킹은 같은 문장으로 답하고(열거 오라클 차단), JWT 없는 서버 호출자는 영향이 없다');
    else v_msg := v_bad; call _fail('fbl','B5 §D ⓐ 정산 견적 당사자 게이트', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fbl','B5 §D ⓐ 정산 견적 당사자 게이트', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B6] §D ⓑ runner_work_gate — a runner may ask about themselves and nobody else
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0092's comment called it "party-safe by construction". That was true of the ROWS and false of
  -- the CALLER: any signed-in user could ask whether any runner is currently holding a dog, which
  -- booking, when the run stopped, and which side has stamped. 128 pins the gate's LOGIC; this
  -- pins who may ask.
  begin
    v_bad := '';
    -- a booking that gates rr: stopped, unreturned, marketplace
    b2 := t_av_booking(oo, dg, rt, rr, now() - interval '3 hours', 5.0, 'active');
    update bookings set run_ended_at = now() - interval '30 minutes' where id = b2;

    -- ⓐ the runner themselves still gets the whole legible answer (the ruling's second half)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false) then v_bad := v_bad || ' 픽스처가 게이트를 안 걸었다'; end if;
    if (v_js->>'booking_id') is distinct from b2::text then v_bad := v_bad || ' 막는 예약을 지목하지 못했다'; end if;
    if (v_js->>'exit') is null then v_bad := v_bad || ' 출구 이름이 사라졌다 (읽히지 않는 정지)'; end if;

    -- ⓑ 🔴 THE REFUSAL — anyone else asking about that runner
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_err := false;
    begin v_js2 := runner_work_gate(rr);
    exception when others then v_err := true;
    end;
    if not v_err then v_bad := v_bad || ' 🔴 무관자가 남의 러너 상태를 읽었다=' || coalesce(v_js2::text,'∅'); end if;
    -- and another RUNNER is not privileged either — supply-side peers are strangers here
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_err := false;
    begin v_js2 := runner_work_gate(rr);
    exception when others then v_err := true;
    end;
    if not v_err then v_bad := v_bad || ' 🔴 다른 러너가 남의 러너 상태를 읽었다'; end if;

    -- ⓒ the accept path (transition-booking, service_role — no JWT) is unaffected. This is the
    --    exemption the whole §D shape rests on, so it is executed, not assumed.
    perform set_config('request.jwt.claim.sub', '', false);
    v_js2 := runner_work_gate(rr);
    if not coalesce((v_js2->>'gated')::boolean, false)
      then v_bad := v_bad || ' 🔴 서버 경로가 게이트를 못 읽는다 (수락 경로가 봉인된다)'; end if;

    -- ⓓ asking about a FREE runner is still answered for the party — the gate is about the
    --    caller, not about the answer being negative
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_js2 := runner_work_gate(hh);
    if coalesce((v_js2->>'gated')::boolean, true) then v_bad := v_bad || ' 깨끗한 러너가 자기 상태를 못 읽는다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now() where id = b2;

    if v_bad = ''
      then call _pass('fbl','B6 §D ⓑ 작업 게이트는 자기 것만 읽힌다 — 러너 본인은 막는 예약·출구까지 전부 받고, 무관자도 다른 러너도 거절되며, JWT 없는 수락 경로(transition-booking)는 그대로 동작한다');
    else v_msg := v_bad; call _fail('fbl','B6 §D ⓑ 작업 게이트 당사자', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fbl','B6 §D ⓑ 작업 게이트 당사자', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B7] §D ⓒ club_dog_ui_state — the board's own grading, applied to the direct call
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The gate has to be the BOARD's audience and not something stricter: `_club_delegation_board`
  -- calls this function from inside its own definer, and `auth.uid()` is preserved across that
  -- boundary — so a stricter gate would blank the host's board rather than protect anything. ⓓ is
  -- the composition arm that catches exactly that.
  begin
    v_bad := '';
    -- ⓐ the host reads any dog in their session
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_js := club_dog_ui_state(sda);
    if v_js is null or (v_js->>'primaryStage') is null then v_bad := v_bad || ' 🔴 호스트가 자기 세션 강아지를 못 읽는다'; end if;
    -- ⓑ the delegating owner reads their own dog
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js2 := club_dog_ui_state(sda);
    if v_js2 is distinct from v_js then v_bad := v_bad || ' 보호자와 호스트의 프로젝션이 다르다'; end if;
    -- ⓒ 🔴 THE REFUSALS
    perform set_config('request.jwt.claim.sub', zz::text, false);
    if club_dog_ui_state(sda) is not null then v_bad := v_bad || ' 🔴 무관자가 남의 위탁견 상태를 읽었다'; end if;
    perform set_config('request.jwt.claim.sub', ol::text, false);
    if club_dog_ui_state(sda) is not null
      then v_bad := v_bad || ' 🔴 limited 등급이 남의 강아지를 읽었다 (보드의 dogs 필터와 어긋난다)'; end if;
    if club_dog_ui_state(sdl) is null
      then v_bad := v_bad || ' limited 등급이 **자기** 강아지도 못 읽는다'; end if;
    -- "no such row" and "not your session" are the same shape — no enumeration oracle
    perform set_config('request.jwt.claim.sub', zz::text, false);
    if club_dog_ui_state(gen_random_uuid()) is not null then v_bad := v_bad || ' 없는 행이 값을 돌려줬다'; end if;

    -- ⓓ 🔴 THE COMPOSITION — the board still renders that dog's `ui`. This is the arm that goes
    --    red if the gate is tightened past the board's own grading.
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_js := club_delegation_board(v_s);
    if not exists (
      select 1 from jsonb_array_elements(v_js->'dogs') d
       where d->>'sdId' = sda::text and (d->'ui'->>'primaryStage') is not null)
      then v_bad := v_bad || ' 🔴 보드에서 강아지 ui가 비었다 (게이트가 보드보다 엄격하다)'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('fbl','B7 §D ⓒ 강아지 프로젝션에 보드와 같은 등급 게이트 — 호스트와 위탁 보호자는 읽고, 무관자와 limited 등급의 남의 강아지는 NULL(없는 행과 같은 모양)이며, 자기 강아지는 여전히 읽히고, 호스트의 위임 보드는 ui까지 그대로 렌더된다 (보드는 이 함수를 definer 안에서 부르고 auth.uid()는 그 경계를 넘어 보존된다)');
    else v_msg := v_bad; call _fail('fbl','B7 §D ⓒ 강아지 프로젝션 게이트', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fbl','B7 §D ⓒ 강아지 프로젝션 게이트', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [B8] §D ⓓ club_host_stats — the caller term its own inputs already carry
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ Said out loud in the pin, not only in the migration: this one is DELIBERATELY not
  -- members-only. `club_sessions` is `using (true)` and `session_people` is
  -- `using (auth.uid() is not null)`, so every number here is already computable by any signed-in
  -- user, and gating on membership would break the storefront card that exists to convince a
  -- prospective member (app/app/club/[id].tsx:112). The gate restored is `session_people`'s own
  -- term — a caller with no session — which the definer was bypassing.
  begin
    v_bad := '';
    -- ⓐ a signed-in NON-member still gets the storefront card (deliberate, and pinned so nobody
    --    "hardens" it into a members-only call without reading why)
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_js := club_host_stats(v_club);
    if v_js is null or (v_js->>'sessions') is null
      then v_bad := v_bad || ' 🔴 로그인한 비회원이 스토어프론트 카드를 못 받는다 (가입 설득 화면이 죽는다)'; end if;
    -- and the answer is the same one the raw tables give — the gate did not change the numbers
    select count(*) into v_n from club_sessions s where s.club_id = v_club and s.status = 'done';
    if (v_js->>'sessions')::int <> v_n then v_bad := v_bad || ' 세션 수가 원표와 다르다 ' || (v_js->>'sessions') || '<>' || v_n; end if;
    -- ⓑ 🔴 THE REFUSAL — no session at all
    perform set_config('request.jwt.claim.sub', '', false);
    v_err := false;
    begin v_js2 := club_host_stats(v_club);
    exception when others then v_err := true;
    end;
    if not v_err then v_bad := v_bad || ' 🔴 세션 없는 호출자가 답을 받았다 (session_people 정책이 요구하는 항을 definer가 우회한다)'; end if;

    if v_bad = ''
      then call _pass('fbl','B8 §D ⓓ 호스트 통계는 세션을 요구한다 — 세션 없는 호출자는 거절되고, 로그인한 비회원은 여전히 카드를 받으며(회원 전용이 아닌 것은 의도다: 세 숫자 모두 public read + authed read에서 이미 계산 가능하고 이건 가입을 설득하는 스토어프론트다), 숫자는 원표와 같다');
    else v_msg := v_bad; call _fail('fbl','B8 §D ⓓ 호스트 통계 게이트', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fbl','B8 §D ⓓ 호스트 통계 게이트', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
