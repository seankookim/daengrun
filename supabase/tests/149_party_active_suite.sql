-- ═══ 149 party-active suite — 0114 pins (P-1 … P-34) ═══
-- What this suite pins: **a nominated-but-not-accepted stranger is not a party for any WRITE
-- surface.** `is_booking_party` (`0002:15-22`) asks only "is auth.uid() owner or runner", never
-- "did they say yes" — so `request_runner` setting `runner_id = <victim>` (legitimate, owner-gated,
-- the product) handed an attacker a chat thread, arbitrary free text delivered as a push, a review
-- naming the victim, an attacker-titled notification pushed VERBATIM to a lock screen, and an
-- incident whose open state unlocks `incident_contact`'s phone door. That is B-11, executed by
-- 0111's reviewer; 0111's own header names it as what it did NOT close.
--
-- Style: sibling of 143/146/148. `_pass('pact',…)`/`_fail('pact',…)`, one begin…exception per arm,
--   `_fail` args pre-computed into `v_msg` (the 110 header law).
--
-- ⚠⚠ **EVERY attack arm runs under `set local role authenticated` with `request.jwt.claim.sub`
--   set, and resets the role in BOTH arms.** A pin that runs as `postgres` measures NOTHING —
--   the superuser bypasses RLS, so a fix and no fix produce identical output (146's F5 of the
--   rejected 0105). Every arm asserts `current_user = 'authenticated'` after the SET ROLE
--   (sqlstate `ZZ001`, 144's idiom): a SET ROLE that silently failed would run the attack as
--   `postgres`, and one that ERRORED would land in the same handler and be recorded as a pass.
-- ⚠⚠ **THE SQLSTATE LAW — every INSERT arm asserts `42501` BY NAME.** These are RLS refusals, so
--   `42501` (insufficient_privilege) is the only pass; the sqlstate is captured and COMPARED, never
--   swallowed by a bare `when others` handler that would read a typo'd column as a security win
--   (`146:24-27`). The `open_incident_tx` arms are the deliberate exception: those are plpgsql
--   raises (`P0001`) and are asserted on the MESSAGE — `booking_not_reportable`, never `not_party`,
--   never `42501`. **A refusal from the wrong layer is not this slice's refusal.**
--
-- ⚠⚠⚠ **THE FIXTURE IS LOAD-BEARING — `chat_threads.booking_id` is UNIQUE** (`chat_threads_booking_id_key`,
--   `0001_init.sql:362`). The contract's first draft aimed P-1 and P-2 at a booking whose thread the
--   fixture itself had pre-seeded, so both raised `23505` — **and did so with the migration ABSENT.**
--   Two of the three headline denial pins asserted nothing. **The general rule, which every arm
--   added later must be read against:** *a thread-INSERT arm must target a booking with NO thread;
--   a message-INSERT arm must target one WITH a thread. Never the same booking for both.*
--
--   | handle    | status                     | runner | thread seeded | used by                          |
--   |-----------|----------------------------|--------|---------------|----------------------------------|
--   | b_pend    | runner_pending             | vic    | YES           | P-3, P-7, P-11, P-13, P-25, P-26, P-33 |
--   | b_pend2   | runner_pending             | vic    | no            | P-1, P-2, then P-20/P-21 after accept |
--   | b_conf    | confirmed                  | vic    | YES           | P-10(msg), P-15, P-22, P-24, P-27, P-28 |
--   | b_conf2   | confirmed                  | vic    | no            | P-10's thread arm                |
--   | b_cxo     | cancelled_owner            | vic    | no            | P-9 thread/review/noti           |
--   | b_cxo2    | cancelled_owner            | vic    | YES           | P-9 message arm                  |
--   | b_done    | completed                  | vic    | no            | P-23                             |
--   | b_open    | matching (runner NULL)     | —      | no            | P-8, P-12, P-33                  |
--   | b_other   | confirmed (two other users)| oth_r  | no            | P-14 thread/review/noti          |
--   | b_other2  | confirmed (two other users)| oth_r  | YES           | P-14 message arm                 |
--   | b_saf     | driven to cancelled_owner  | vic    | no            | P-31 🔵                          |
--   | b_ref     | driven to refund_pending   | vic    | no            | P-32 🔵                          |
--   | b_idem    | confirmed → … → refund_pending | vic | no          | P-34 arm A                       |
--   | b_idem2   | confirmed → matching → expired | vic | no          | P-34 arm B (the diagnostic one)  |
--
-- ─── DELIBERATE DEVIATIONS FROM THE CONTRACT'S §D, and why each is not an improvisation ──────
--   ① **P-20/P-21 run on `b_pend2`, not `b_pend`.** §D names `b_pend`, but §D also gives `b_pend`
--      a pre-seeded thread for P-3 — so "as atk: create thread" there is a `23505`, i.e. F1's own
--      defect committed a second time in the positive direction. `b_pend2` is thread-free, and
--      using it is strictly stronger: it is **the same booking P-1 was refused on**, so the pair
--      reads "refused at runner_pending, allowed the moment the runner accepts". It also leaves
--      `b_pend` at `runner_pending` for P-7/P-11/P-13/P-25/P-26/P-33, which §D's own P-33 needs.
--   ② **P-10's thread arm uses `b_conf2`** (confirmed, thread-free) rather than sharing `b_pend2`.
--      §D says only "a thread-free booking"; picking one INSIDE the accepted set makes the arm
--      diagnostic of the PARTY gate alone — on a `runner_pending` booking a stranger would be
--      refused by the status gate and the party gate together, and the pin could not tell which.
--   ③ **P-34 gets a SECOND arm, and the second one is the real pin.** §D specifies
--      `b_conf → incident_review → refund_pending`. **That route cannot fail**, because `refund_pending`
--      is INSIDE §3's reportable set (the 🔵 decision) — so the mutation the pin exists to catch
--      ("move the state gate before the idempotent return") leaves it green. That is exactly the
--      F1 class of false green, arriving in the pin written to prove F1's fix. §C.3(5)'s own prose
--      names the fix — *"it would still refuse the id at `expired`"* — so **arm B drives
--      `confirmed → matching → expired`**, a legal path (`0066:51`, `0017:9`'s cron sink) and the
--      only one where a misplaced gate is visible. Arm A is kept as written, as the in-set control.
--   ④ **§D's P-6/P-33 error name is used verbatim: `booking_not_reportable`.** The build brief said
--      `booking_not_active`; that name would be false — the reportable set is deliberately WIDER
--      than active (it contains `cancelled_owner` and `refund_pending`) — and it would invite the
--      next reader to "fix" §3 to match §1, which is the one thing the 🔵 decision forbids.
--      0094 §10: DISTINCT FACTS GET DISTINCT NAMES.
--
-- ─── SCOPE: what is deliberately NOT here ───────────────────────────────────────────────────
--   · **The nomination push over the wire.** P-25 reproduces `request_runner`'s notification INSERT
--     under `service_role`, which is the authority that actually writes it (`transition-booking/index.ts:198`
--     → `notify` → `admin()`). The edge function itself is TypeScript and the harness has no Deno;
--     the end-to-end 「지명 러닝 요청」 arriving on a phone is a §E.8 manual smoke item, not a pin,
--     and is not claimed as one.
--   · **Rate-limiting the nomination push** (contract F11) — a real residual, `service_role`,
--     unreachable from any policy 0114 writes. Adjacent slice; no pin here owns it.
--   · **`dogs.memo` on the pre-accept request card** (contract F6) — client-side, ui2's.
--   · **The realtime rooms.** P-11/P-12/P-28 pin that they did NOT change; 143 owns them.
--
-- ─── MUTATION map — EXECUTED on tree `p0-party-active`, 2026-08-20 ──────────────────────────
--   Baseline before this slice **666 / 0** (measured on this tree, not copied — the contract's own
--   660/0 is two migrations stale). Clean green after: **694 / 0**, i.e. 28 pins arrive.
--   ⚠ Three mutations are caught by 0114 §5's verify block BEFORE any pin runs, so each is
--   reported in two stages: what the DEPLOY does, then what the PINS say once the verify is
--   relaxed. Both halves matter — the first is the fail-closed behaviour, the second is proof the
--   pins are not resting on it.
--
--   M1a revert policy (4) `noti party insert` to `is_booking_party`
--       → the MIGRATION refuses, fail closed: `0114: write policy did not switch to
--         is_booking_party_active: notifications.noti party insert`
--   M1b …with §5 ① relaxed → **691 / 3, red = [P-5, P-8, P-9]** — NOT "P-5 alone". Policy (4) is
--         the one predicate behind every attacker-authored `notifications` row, and P-8
--         (`matching`) and P-9 (`cancelled_owner`) each exercise it on their own booking. A
--         reviewer expecting one red would have hunted a second defect that does not exist.
--   M2  drop the §3 state gate from `open_incident_tx`
--       → **690 / 4, red = [P-6, P-7, P-8, P-33]**. P-7 is TRANSITIVE and that is the finding:
--         with the open restored, `incident_contact` immediately returns **2 rows** — both parties'
--         name and phone. B-11.g needs no code of its own; it rides on whatever can open a case.
--   M3  add `'runner_pending'` to `is_booking_party_active`'s set
--       → **686 / 8, red = [P-1, P-2, P-3, P-4, P-5, P-13, and by cascade P-20, P-21]**.
--         🔴 **P-1 and P-2 flipping is the check that the fixture fix landed** — under the
--         contract's original single-booking fixture they were green either way (23505 from
--         `chat_threads_booking_id_key`, never 42501). They flip now.
--         ⚠ Two honest caveats, recorded rather than smoothed: **P-2 reddens as `23505`, not as a
--         success** — P-1 now succeeds and takes the unique slot, which is exactly the collision
--         P-2's own comment warns about ("if P-1 ever legitimately succeeds, P-2 must move"). And
--         **P-20/P-21 are CASCADE reds, not independent ones**: P-1's success leaves a thread on
--         b_pend2, so P-20's legitimate thread INSERT hits the same index. Neither weakens the
--         mutation; both would mislead a reader who counted reds instead of reading them.
--         ⚠ **P-6 and P-7 do NOT redden here, and the contract predicted they would.** They are
--         correct as measured: `open_incident_tx` consults its OWN set (§3) and never calls this
--         predicate, so widening §1 cannot reach the incident path. That is the 🔵 decision
--         working — the two gates really are independent, and this is the executable proof.
--   M4  remove `sender_id = auth.uid()` from policy (2)
--       → **693 / 1, red = [P-15] alone**, both directions (`atk_as_vic` and `vic_as_atk` both
--         SUCCEEDED). Before this suite the identical mutation reddened **nothing** (the contract's
--         reviewer measured 660/0 with the clause deleted). The property was true in production and
--         owned by no pin; P-15 is its owner now.
--   M5a drop `set search_path = public, pg_temp` from `is_booking_party_active`'s body
--       → the MIGRATION refuses: `0114: definer written without pg_temp in its body:
--         is_booking_party_active(uuid)`
--   M5b …with §5 ③ narrowed → **693 / 1, red = [98 H1]** — the whole-schema definer sweep,
--         reporting `미봉인 1개 … is_booking_party_active(uuid)`. Two independent layers see it.
--   M6  replace §3's inline reportable set with `is_booking_party_active(p_booking)` — i.e. undo
--       the 🔵 decision → **692 / 2, red = [P-31, P-32]**, both refusing with
--       `booking_not_reportable` on bookings that reached their state THROUGH an accept. Every
--       negative stays green, which is precisely why the decision needed positives of its own.
--   M7  move the §3 state gate ABOVE the idempotent existing-incident return
--       → **693 / 1, red = [P-34] alone — and it is ARM B that fails** (`B재호출
--         P0001/booking_not_reportable`). **Arm A, the route the contract specified, stays GREEN
--         under this mutation.** That is deviation ③ measured rather than argued: written as
--         specified, this pin could not have failed.
--   M8a revert policy (2) `messages party send` to `is_booking_party`, keeping (1) narrowed
--       → the MIGRATION refuses: `0114: write policy did not switch to is_booking_party_active:
--         chat_messages.messages party send`
--   M8b …with §5 ① relaxed → **692 / 2, red = [P-3, P-9's message arm]** — ⚠ **not "P-3 alone"**,
--         as the contract predicted. Policy (2) is the single predicate behind every message a
--         leftover thread can carry, and P-9 exercises it on its own `cancelled_owner` booking.
--   M9  add `'cancelled_owner'` to `is_booking_party_active`'s set
--       → **693 / 1, red = [P-9] alone**, all four arms SUCCEEDED — the "nominate, then cancel
--         your own booking, be a full party again" bypass, in one line. It is why the exclusion
--         list is the interesting half of §1.
--
--   ⚠ **All green is not evidence. All green plus every mutation reddening its named set is.**
--     Two pins here (P-1/P-2's split fixture, P-34's arm B) exist ONLY because the version written
--     from the specification could not have failed — the same defect 0112 recorded (REGISTRY row
--     154) and 148 hit twice in one night. **Mutation-test the fixture, not only the migration.**

do $$
declare
  v_atk uuid; v_vic uuid; v_str uuid; v_oth_o uuid; v_oth_r uuid;
  v_dog uuid; v_addr uuid; v_odog uuid; v_oaddr uuid;
  b_pend uuid; b_pend2 uuid; b_conf uuid; b_conf2 uuid; b_cxo uuid; b_cxo2 uuid;
  b_done uuid; b_open uuid; b_other uuid; b_other2 uuid;
  b_saf uuid; b_ref uuid; b_idem uuid; b_idem2 uuid;
  th_pend uuid; th_conf uuid; th_cxo2 uuid; th_other2 uuid;
  v_bad text; v_msg text; v_st text; v_n int; v_n2 int;
  v_id uuid; v_id2 uuid; v_id1 uuid;
  v_when timestamptz := now() + interval '3 days';
  r record;
begin
  -- ─────────────────────────── fixtures (as postgres, before any role switch) ───────────────
  v_atk := gen_random_uuid(); v_vic := gen_random_uuid(); v_str := gen_random_uuid();
  v_oth_o := gen_random_uuid(); v_oth_r := gen_random_uuid();
  insert into auth.users(id,email) values
    (v_atk,'pact-atk@t'),(v_vic,'pact-vic@t'),(v_str,'pact-str@t'),
    (v_oth_o,'pact-otho@t'),(v_oth_r,'pact-othr@t');
  insert into profiles(id,role,name) values
    (v_atk,'owner','PACT-atk'),(v_vic,'runner','PACT-vic'),(v_str,'owner','PACT-str'),
    (v_oth_o,'owner','PACT-otho'),(v_oth_r,'runner','PACT-othr');
  insert into runners(profile_id) values (v_vic),(v_oth_r);
  -- [0119] 이 스위트는 t_dog를 안 쓰고 직접 심는다 — 0119 §D 이후 미신고 강아지는 위탁이
  -- 거절되므로 신고값이 명시적으로 필요하다. 이 스위트가 핀하는 성질은 바뀌지 않는다.
  insert into dogs (owner_id,name,dangerous_status) values (v_atk,'pact-mine','declared_none')  returning id into v_dog;
  insert into dogs (owner_id,name,dangerous_status) values (v_oth_o,'pact-theirs','declared_none') returning id into v_odog;
  insert into addresses(owner_id,label,addr) values (v_atk,'home','PA') returning id into v_addr;
  insert into addresses(owner_id,label,addr) values (v_oth_o,'home','PB') returning id into v_oaddr;

  -- Bookings are INSERTed directly at their target status: `booking_transition` is
  -- `before update of status`, so a direct insert is not a transition and no map arm is needed.
  -- The three that must PROVE their state was reached legitimately (b_saf, b_ref, b_idem*) are
  -- driven through real edges below, because "reachable from the accepted set" is their property.
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'runner_pending', v_when,3,7900,9000,16900) returning id into b_pend;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'runner_pending', v_when,3,7900,9000,16900) returning id into b_pend2;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'confirmed',      v_when,3,7900,9000,16900) returning id into b_conf;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'confirmed',      v_when,3,7900,9000,16900) returning id into b_conf2;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'cancelled_owner',v_when,3,7900,9000,16900) returning id into b_cxo;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'cancelled_owner',v_when,3,7900,9000,16900) returning id into b_cxo2;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,   'completed',      v_when,3,7900,9000,16900) returning id into b_done;
  insert into bookings(owner_id,dog_id,address_id,           status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,         'matching',       v_when,3,7900,9000,16900) returning id into b_open;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_oth_o,v_odog,v_oaddr,v_oth_r,'confirmed',   v_when,3,7900,9000,16900) returning id into b_other;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_oth_o,v_odog,v_oaddr,v_oth_r,'confirmed',   v_when,3,7900,9000,16900) returning id into b_other2;

  -- 🔵 b_saf — driven through a REAL accept path so its `cancelled_owner` is provably post-accept:
  -- runner_pending → confirmed → runner_enroute → cancelled_owner. Every edge legal (`0066:47,52`).
  -- This is 0066's en-route owner cancel: the runner may be standing at the door.
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,'runner_pending',v_when,3,7900,9000,16900) returning id into b_saf;
  update bookings set status='confirmed'       where id=b_saf;
  update bookings set status='runner_enroute'  where id=b_saf;
  update bookings set status='cancelled_owner' where id=b_saf;

  -- 🔵 b_ref — `confirmed → cancelled_runner → refund_pending`, the two-step `0038:219-221` uses
  -- precisely because the direct edge is illegal. Post-accept refund_pending, the F3 correction.
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,'confirmed',v_when,3,7900,9000,16900) returning id into b_ref;
  update bookings set status='cancelled_runner' where id=b_ref;
  update bookings set status='refund_pending'   where id=b_ref;

  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,'confirmed',v_when,3,7900,9000,16900) returning id into b_idem;
  insert into bookings(owner_id,dog_id,address_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price) values
    (v_atk,v_dog,v_addr,v_vic,'confirmed',v_when,3,7900,9000,16900) returning id into b_idem2;

  -- Threads seeded AS POSTGRES (RLS does not police the superuser) — these simulate leftovers from
  -- a reassignment, which is the honest shape: a thread can predate a nomination.
  insert into chat_threads(booking_id) values (b_pend)   returning id into th_pend;
  insert into chat_threads(booking_id) values (b_conf)   returning id into th_conf;
  insert into chat_threads(booking_id) values (b_cxo2)   returning id into th_cxo2;
  insert into chat_threads(booking_id) values (b_other2) returning id into th_other2;

  -- b_conf's thread also gets HISTORY, because P-27's subject is that history survives the cancel
  -- and an empty thread would let it pass on a vacuous count. Seeded as postgres: the pin is about
  -- the READ direction, and the write direction on a `confirmed` booking is P-20/P-22's job.
  insert into chat_messages(thread_id, sender_id, body) values
    (th_conf, v_atk, '취소 전 오너 메시지'), (th_conf, v_vic, '취소 전 러너 메시지');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- NEGATIVE ARMS — pre-acceptance is refused
  -- ══════════════════════════════════════════════════════════════════════════════════════════

  -- ---------- [P-1] the attacker cannot open the channel at runner_pending ----------
  -- ⚠ b_pend2, NOT b_pend: b_pend carries a seeded thread and the UNIQUE index would answer 23505
  --   before RLS was ever consulted (contract F1). This arm must be able to fail.
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into chat_threads(booking_id) values (b_pend2);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 지명 상태 예약에 공격자가 스레드를 만든 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-1 runner_pending 예약에 공격자(오너)의 chat_threads INSERT — 42501 (B-11.a: 지명만으로는 채널이 열리지 않는다)');
  else v_msg := v_bad; call _fail('pact','P-1 thread insert at runner_pending', v_msg); end if;

  -- ---------- [P-2] the narrow is SYMMETRIC — the nominated runner cannot open it either ----------
  -- ⚠ Sharing b_pend2 with P-1 is safe ONLY because P-1 must be refused: no row was created, so
  --   this cannot collide on the unique index. If P-1 ever legitimately succeeds, P-2 must move to
  --   its own booking or it silently becomes a 23505 pin.
  perform set_config('request.jwt.claim.sub', v_vic::text, true);
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into chat_threads(booking_id) values (b_pend2);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 지명된 러너의 스레드 생성 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-2 같은 예약에 지명된 러너 본인의 스레드 생성도 42501 — 좁힘은 대칭이다 (수락이 문을 여는 것이지 지명이 아니다)');
  else v_msg := v_bad; call _fail('pact','P-2 thread insert by nominee', v_msg); end if;

  -- ---------- [P-3] the arm that catches "gated thread creation only" ----------
  -- b_pend HAS a thread (a reassignment leftover). If policy (2) were left on the wide predicate,
  -- the attacker walks through the leftover and B-11.b/B-11.c reopen with no thread INSERT at all.
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into chat_messages(thread_id, sender_id, body) values (th_pend, v_atk, '공격자 자유 텍스트');
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 남아있던 스레드로 메시지를 보낸 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-3 이미 존재하는 스레드(재배정 잔재)에도 메시지 INSERT 42501 — 스레드 생성만 막는 구현을 잡는 핀 (B-11.b/c)');
  else v_msg := v_bad; call _fail('pact','P-3 message insert through leftover thread', v_msg); end if;

  -- ---------- [P-4] a review naming the victim ----------
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
      values (b_pend, v_atk, 'runner', v_vic, 1, 'public');
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 지명 상태에서 피해자를 지목한 리뷰 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-4 수락 전 예약에 피해자를 target으로 한 리뷰 INSERT 42501 (B-11.e)');
  else v_msg := v_bad; call _fail('pact','P-4 review insert at runner_pending', v_msg); end if;

  -- ---------- [P-5] THE LOCK-SCREEN ARM — the most direct form of the harm ----------
  -- `0024` pushes `title` and `body` VERBATIM to a phone (`0090:33-37` says so), and this needs no
  -- chat thread at all. Of every step in B-11 this is the one that reaches the victim fastest.
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into notifications(profile_id, kind, title, body, ref_id)
      values (v_vic, 'booking', '공격자가 고른 제목', '공격자가 고른 본문', b_pend);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 공격자 작성 알림 행 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-5 공격자가 제목·본문을 직접 쓴 notifications 행 42501 — 0024가 그대로 잠금화면에 밀어주는 경로 (B-11.d)');
  else v_msg := v_bad; call _fail('pact','P-5 attacker-authored notification row', v_msg); end if;

  -- ---------- [P-6] the incident opener refuses at runner_pending ----------
  -- ⚠ P0001 on the MESSAGE, not 42501: this is a plpgsql raise, and the name must be the one §3
  --   owns. A `not_party` here would mean the party gate refused (wrong layer — the attacker IS a
  --   party) and a 42501 would mean a grant refused. Both would be false greens.
  v_bad := ''; v_st := null; v_msg := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    perform open_incident_tx(b_pend, 'dog_injury');
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate; v_msg := sqlerrm;
  end;
  reset role;
  if v_st <> 'P0001' or coalesce(v_msg,'') <> 'booking_not_reportable' then
    v_bad := ' open_incident_tx 결과 [' || coalesce(v_st,'NULL') || '/' || coalesce(v_msg,'-') || ']';
  end if;
  if v_bad = '' then call _pass('pact','P-6 runner_pending에서 open_incident_tx가 booking_not_reportable로 거절 — not_party도 42501도 아니다 (0094 §10: 사실이 다르면 이름도 다르다)');
  else v_msg := v_bad; call _fail('pact','P-6 open_incident_tx at runner_pending', v_msg); end if;

  -- ---------- [P-7] the phone door stays shut, transitively ----------
  -- `incident_contact` is NOT edited (0094 §4 forbids narrowing it). Gating the OPENER is what
  -- shuts it: with no open incident, its state gate never passes. This is B-11.g — both parties'
  -- name AND phone, inert today only because `profiles.phone` is universally NULL (PASS not
  -- integrated), and armed with no further code change the day PASS lands.
  v_bad := ''; v_n := -1;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select count(*) from incident_contact($1)' into v_n using b_pend;
  exception when others then v_bad := ' incident_contact 예외 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and v_n <> 0 then v_bad := ' incident_contact가 ' || v_n || '행을 돌려줬다 (전화번호 문이 열려 있다)'; end if;
  if v_bad = '' then call _pass('pact','P-7 incident_contact 0행 — 열 수 있는 인시던트가 없으니 전화번호 문(B-11.g)이 이행적으로 닫힌다 (0088을 건드리지 않고)');
  else v_msg := v_bad; call _fail('pact','P-7 incident_contact transitive closure', v_msg); end if;

  -- ---------- [P-8] the same four refusals at `matching`, runner_id NULL ----------
  -- ⚠ NO message arm here: b_open has no thread, so a message INSERT would die on the FK — another
  --   false green wearing a different shape.
  v_bad := '';
  for r in select 'thread'::text as arm union all select 'review' union all
                  select 'noti'          union all select 'incident'
  loop
    v_st := null; v_msg := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'thread' then insert into chat_threads(booking_id) values (b_open);
        when 'review' then insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
                             values (b_open, v_atk, 'owner', v_atk, 1, 'public');
        when 'noti'   then insert into notifications(profile_id, kind, title, body, ref_id)
                             values (v_atk, 'booking', 'x', 'y', b_open);
        else perform open_incident_tx(b_open, 'other');
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate; v_msg := sqlerrm;
    end;
    reset role;
    if r.arm = 'incident' then
      if v_st <> 'P0001' or coalesce(v_msg,'') <> 'booking_not_reportable' then
        v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL') || '/' || coalesce(v_msg,'-');
      end if;
    elsif v_st <> '42501' then
      v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL');
    end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-8 matching(러너 미배정)에서도 스레드·리뷰·알림 42501, open_incident_tx booking_not_reportable — 좁힘은 지명 상태 하나만 겨냥한 게 아니다');
  else v_msg := '기대와 다른 결과:' || v_bad; call _fail('pact','P-8 matching refusals', v_msg); end if;

  -- ---------- [P-9] the "nominate, then cancel your own booking" bypass ----------
  -- If `cancelled_owner` were inside the set, the whole slice would fall to ONE extra call: the
  -- attacker nominates, cancels, and is a full party again. ⚠ Split across two bookings per F1 —
  -- thread arm on the thread-free b_cxo, message arm on the thread-seeded b_cxo2.
  -- ⚠ NO open_incident_tx arm: `cancelled_owner` is deliberately INSIDE §3's reportable set
  --   (the 🔵 decision). Its coverage is P-31/P-33, not here.
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  v_bad := '';
  for r in select 'thread'::text as arm union all select 'message' union all
                  select 'review'       union all select 'noti'
  loop
    v_st := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'thread'  then insert into chat_threads(booking_id) values (b_cxo);
        when 'message' then insert into chat_messages(thread_id, sender_id, body) values (th_cxo2, v_atk, '취소 후 자유 텍스트');
        when 'review'  then insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
                              values (b_cxo, v_atk, 'runner', v_vic, 1, 'public');
        else insert into notifications(profile_id, kind, title, body, ref_id)
               values (v_vic, 'booking', '취소 후 제목', '취소 후 본문', b_cxo);
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-9 cancelled_owner에서 스레드·메시지·리뷰·알림 전부 42501 — "지명하고 내 예약을 취소하면 다시 당사자" 우회가 닫혀 있다 (제외 목록이 핵심인 이유)');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('pact','P-9 nominate-then-cancel bypass', v_msg); end if;

  -- ---------- [P-10] the PARTY gate is unweakened — a stranger is still a stranger ----------
  -- ⚠ The thread arm targets b_conf2 (confirmed, thread-free): a booking INSIDE the accepted set,
  --   so the only thing that can refuse is party membership. On a pre-accept booking both gates
  --   would refuse and the arm could not tell which one did.
  perform set_config('request.jwt.claim.sub', v_str::text, true);
  v_bad := '';
  for r in select 'thread'::text as arm union all select 'message' union all
                  select 'review'       union all select 'noti' union all select 'incident'
  loop
    v_st := null; v_msg := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'thread'  then insert into chat_threads(booking_id) values (b_conf2);
        when 'message' then insert into chat_messages(thread_id, sender_id, body) values (th_conf, v_str, '무관한 사용자');
        when 'review'  then insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
                              values (b_conf, v_str, 'runner', v_vic, 1, 'public');
        when 'noti'    then insert into notifications(profile_id, kind, title, body, ref_id)
                              values (v_vic, 'booking', 'x', 'y', b_conf);
        else perform open_incident_tx(b_conf, 'other');
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate; v_msg := sqlerrm;
    end;
    reset role;
    if r.arm = 'incident' then
      if v_st <> 'P0001' or coalesce(v_msg,'') <> 'not_party' then
        v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL') || '/' || coalesce(v_msg,'-');
      end if;
    elsif v_st <> '42501' then
      v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL');
    end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-10 수락된 예약(confirmed)에도 제3자는 스레드·메시지·리뷰·알림 42501, open_incident_tx not_party — 상태 필터가 당사자 게이트를 약화시키지 않았다');
  else v_msg := '기대와 다른 결과:' || v_bad; call _fail('pact','P-10 stranger still refused', v_msg); end if;

  -- ---------- [P-11] the realtime chat room is UNCHANGED — recorded as a decision ----------
  -- This pin exists so §0f's deviation from the scoping brief reads as a decision rather than being
  -- discovered later as a bug. `chat-<thread>` must still admit both parties of a runner_pending
  -- booking, because `threads party` (SELECT) still admits them on the table and 0108's law is
  -- "mirror the table, do not invent". It closes nothing to narrow it: after 0114 §2 no thread and
  -- no message can be CREATED pre-accept, and the rooms are receive-only at the wire.
  v_bad := '';
  if channel_allowed('chat-' || th_pend::text, v_atk, 'read') is not true then v_bad := v_bad || ' 공격자(오너)가 자기 예약의 채팅방에서 밀려났다'; end if;
  if channel_allowed('chat-' || th_pend::text, v_vic, 'read') is not true then v_bad := v_bad || ' 지명된 러너가 채팅방에서 밀려났다'; end if;
  if channel_allowed('chat-' || th_pend::text, v_str, 'read') is not false then v_bad := v_bad || ' 무관한 사용자가 채팅방에 들어간다'; end if;
  if v_bad = '' then call _pass('pact','P-11 chat-<thread> 룸은 그대로 — 0114는 realtime 정책을 건드리지 않는다 (143 C3와 같은 성질, 여기선 결정으로 기록)');
  else v_msg := v_bad; call _fail('pact','P-11 realtime chat room unchanged', v_msg); end if;

  -- ---------- [P-12] the radar screen survives — 143 B1's property, re-pinned ----------
  -- Narrowing `bk-<booking>` would make `app/owner/radar.tsx` deaf for EVERY user: the owner
  -- watches this room at `matching`, before any runner exists.
  v_bad := '';
  if channel_allowed('bk-' || b_open::text, v_atk, 'read') is not true then v_bad := v_bad || ' 매칭 중 오너가 레이더 채널에 못 들어간다'; end if;
  if channel_allowed('bk-' || b_open::text, v_str, 'read') is not false then v_bad := v_bad || ' 매칭 중 무관한 사용자가 레이더 채널에 들어간다'; end if;
  if v_bad = '' then call _pass('pact','P-12 bk-<booking> 레이더 채널도 그대로 — matching(러너 없음)에서 오너가 들어간다 (143 B1)');
  else v_msg := v_bad; call _fail('pact','P-12 radar room unchanged', v_msg); end if;

  -- ---------- [P-13] the predicate itself, both sides ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  if is_booking_party_active(b_pend) is not false then v_bad := v_bad || ' 오너에게 true/NULL'; end if;
  if is_booking_party(b_pend) is not true then v_bad := v_bad || ' 넓은 술어가 오너에게 true가 아니다(대조군 실패 — 좁힘이 아니라 다른 이유로 거절되고 있다)'; end if;
  perform set_config('request.jwt.claim.sub', v_vic::text, true);
  if is_booking_party_active(b_pend) is not false then v_bad := v_bad || ' 지명된 러너에게 true/NULL'; end if;
  if is_booking_party(b_pend) is not true then v_bad := v_bad || ' 넓은 술어가 러너에게 true가 아니다(대조군 실패)'; end if;
  if v_bad = '' then call _pass('pact','P-13 is_booking_party_active(runner_pending)는 양쪽 다 false이고, is_booking_party는 양쪽 다 true — 두 술어가 나란히 있고 정확히 상태 하나에서 갈린다');
  else v_msg := v_bad; call _fail('pact','P-13 predicate at runner_pending', v_msg); end if;

  -- ---------- [P-14] another user's CONFIRMED booking ----------
  -- ⚠ Split per F1: b_other is `confirmed`, i.e. INSIDE the new set, so a thread arm colliding on
  --   23505 here would be the same false green wearing a different status.
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  v_bad := '';
  for r in select 'thread'::text as arm union all select 'message' union all
                  select 'review'       union all select 'noti'
  loop
    v_st := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'thread'  then insert into chat_threads(booking_id) values (b_other);
        when 'message' then insert into chat_messages(thread_id, sender_id, body) values (th_other2, v_atk, '남의 예약');
        when 'review'  then insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
                              values (b_other, v_atk, 'runner', v_oth_r, 1, 'public');
        else insert into notifications(profile_id, kind, title, body, ref_id)
               values (v_oth_r, 'booking', 'x', 'y', b_other);
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-14 완전한 남의 confirmed 예약(양쪽 다 타인)에도 4종 전부 42501 — 상태가 집합 안이어도 당사자가 아니면 아무것도 못 쓴다');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('pact','P-14 another user booking', v_msg); end if;

  -- ---------- [P-15] SENDER FORGERY — the clause that had no owner ----------
  -- The contract's reviewer DELETED `sender_id = auth.uid()` from `messages party send` and the
  -- harness stayed 660/0: nothing pinned it. It is true in production today, and 0114 §2 rewrites
  -- the policy AROUND it — so without this pin the slice would silently inherit an unpinned
  -- invariant it is editing. b_conf is inside the accepted set and atk/vic are both legitimate
  -- parties, so the `is_booking_party_active` arm PASSES and the sender clause is the only thing
  -- that can refuse. Both directions, so neither is assumed from the other.
  v_bad := '';
  for r in select 'atk_as_vic'::text as arm union all select 'vic_as_atk'
  loop
    v_st := null;
    perform set_config('request.jwt.claim.sub',
                       case when r.arm = 'atk_as_vic' then v_atk::text else v_vic::text end, true);
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      if r.arm = 'atk_as_vic' then
        insert into chat_messages(thread_id, sender_id, body) values (th_conf, v_vic, '러너인 척');
      else
        insert into chat_messages(thread_id, sender_id, body) values (th_conf, v_atk, '오너인 척');
      end if;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-15 적법한 confirmed 스레드 안에서도 sender_id 위조는 42501 — 0114가 정책을 다시 쓰면서 이 절을 조용히 물려받지 않았다는 증거 (직전까지 주인 없는 불변식)');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('pact','P-15 sender forgery', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- POSITIVE ARMS — the product still works. A policy that admits nobody is green on every denial.
  -- ══════════════════════════════════════════════════════════════════════════════════════════

  -- ---------- [P-20] the accept opens everything, on the very booking P-1 was refused on ----------
  update bookings set status = 'confirmed' where id = b_pend2;   -- runner_accept, simulated
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into chat_threads(booking_id) values (b_pend2) returning id into v_id;
    insert into chat_messages(thread_id, sender_id, body) values (v_id, v_atk, '오너 → 러너');
  exception when others then v_bad := v_bad || ' 오너 경로 실패 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', v_vic::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into chat_messages(thread_id, sender_id, body) values (v_id, v_vic, '러너 → 오너');
  exception when others then v_bad := v_bad || ' 러너 경로 실패 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' then call _pass('pact','P-20 수락 직후 같은 예약에서 스레드 생성·양방향 메시지 전부 성공 — P-1이 거절당한 바로 그 예약이다 (아무도 못 쓰는 정책은 모든 부정 핀에 초록이다)');
  else v_msg := v_bad; call _fail('pact','P-20 post-accept chat works', v_msg); end if;

  -- ---------- [P-21] the chat nudge still fires — ONE PER RECIPIENT ----------
  -- ⚠ Not "exactly one row": `notify_chat_message`'s throttle is scoped to the RECIPIENT
  --   (`0090:71-80` — `where n.profile_id = v_to and …`), so it suppresses a second nudge to the
  --   same person, not a first nudge to the other one. P-20 sent in BOTH directions, so the
  --   correct expectation is 2 rows total, 1 per profile_id. A bare total would have been red on a
  --   correct implementation (contract F8).
  v_bad := '';
  select count(*) into v_n  from notifications where ref_id = b_pend2 and title = '새 메시지' and profile_id = v_vic;
  select count(*) into v_n2 from notifications where ref_id = b_pend2 and title = '새 메시지' and profile_id = v_atk;
  if v_n <> 1 then v_bad := v_bad || ' 러너 수신 ' || v_n || '행'; end if;
  if v_n2 <> 1 then v_bad := v_bad || ' 오너 수신 ' || v_n2 || '행'; end if;
  if v_bad = '' then call _pass('pact','P-21 notify_chat_message가 수신자별로 정확히 1행 (총 2행) — 스로틀은 수신자 단위라 반대 방향 첫 알림을 삼키지 않는다');
  else v_msg := '기대: 각 1행 —' || v_bad; call _fail('pact','P-21 chat nudge per recipient', v_msg); end if;

  -- ---------- [P-22] SOS · 러닝 중단 요청 · km 마일스톤 keep working ----------
  -- These are real client notification INSERTs on a live booking (`api.ts:1889`, `:1900`, `:2565`,
  -- `:2589`). If policy (4) narrowed too far they would die silently mid-run.
  v_bad := '';
  for r in select 'atk'::text as arm union all select 'vic'
  loop
    v_st := null;
    perform set_config('request.jwt.claim.sub',
                       case when r.arm = 'atk' then v_atk::text else v_vic::text end, true);
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      if r.arm = 'atk' then
        insert into notifications(profile_id, kind, title, body, ref_id) values (v_vic, 'booking', '러닝 중단 요청', '보호자가 중단을 요청했어요', b_conf);
      else
        insert into notifications(profile_id, kind, title, body, ref_id) values (v_atk, 'booking', '3km 달성', '', b_conf);
      end if;
      v_st := 'OK';
    exception when others then v_st := sqlstate || '/' || sqlerrm;
    end;
    reset role;
    if v_st <> 'OK' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-22 confirmed 예약에서 양 당사자의 상호 알림 INSERT 성공 — SOS·중단 요청·km 마일스톤 경로가 살아 있다');
  else v_msg := v_bad; call _fail('pact','P-22 in-run notifications survive', v_msg); end if;

  -- ---------- [P-23] the review screens fire post-run ----------
  v_bad := '';
  for r in select 'atk'::text as arm union all select 'vic'
  loop
    v_st := null;
    perform set_config('request.jwt.claim.sub',
                       case when r.arm = 'atk' then v_atk::text else v_vic::text end, true);
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      if r.arm = 'atk' then
        insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
          values (b_done, v_atk, 'runner', v_vic, 5, 'public');
      else
        insert into reviews(booking_id, author_id, target_kind, target_id, rating, visibility)
          values (b_done, v_vic, 'owner', v_atk, 5, 'public');
      end if;
      v_st := 'OK';
    exception when others then v_st := sqlstate || '/' || sqlerrm;
    end;
    reset role;
    if v_st <> 'OK' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-23 completed 예약에서 양측 리뷰 INSERT 성공 — 리뷰 화면은 러닝이 끝난 뒤에 뜨고, completed는 provably-accepted라 집합 안에 있다');
  else v_msg := v_bad; call _fail('pact','P-23 post-run reviews', v_msg); end if;

  -- ---------- [P-24] the safety path works for a real party, phone door included ----------
  v_bad := ''; v_id := null; v_n := -1;
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id using b_conf, 'dog_injury';
    execute 'select count(*) from incident_contact($1)' into v_n using b_conf;
  exception when others then v_bad := ' 예외 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and v_id is null then v_bad := ' open_incident_tx가 id를 안 돌려줬다'; end if;
  if v_bad = '' and v_n <> 2 then v_bad := ' incident_contact가 ' || v_n || '행 (기대 2 — 양 당사자)'; end if;
  if v_bad = '' then call _pass('pact','P-24 confirmed 예약에서 당사자가 인시던트를 열고 incident_contact가 양측 2행 — 안전 경로는 그대로다 (0088의 문은 손대지 않았다)');
  else v_msg := v_bad; call _fail('pact','P-24 incident path for a real party', v_msg); end if;

  -- ---------- [P-25] 🔴 THE NOMINATION PUSH STILL LANDS — O-4's protected half ----------
  -- `request_runner`'s notification is written by `notify` through `admin()`, the SERVICE_ROLE
  -- client (`transition-booking/index.ts:198`, `_shared/ctx.ts`), and `service_role` never consults
  -- a policy. That separation of authority is the whole reason O-4 is buildable: the product half
  -- and the harm half were already on two different roles. **Mutation check: this must stay green
  -- while P-5 — the same table, the same booking, the authenticated arm — is red.**
  v_bad := ''; v_st := null;
  begin
    set local role service_role;
    if current_user <> 'service_role' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into notifications(profile_id, kind, title, body, ref_id)
      values (v_vic, 'booking', '지명 러닝 요청', '보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', b_pend);
    v_st := 'OK';
  exception when others then v_st := sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_st <> 'OK' then v_bad := ' service_role 지명 알림 결과 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('pact','P-25 지명 알림(service_role)은 runner_pending에서 그대로 성공 — O-4가 지키기로 한 절반. authenticated 팔(P-5)이 빨간 동안 이 핀은 초록이어야 한다');
  else v_msg := v_bad; call _fail('pact','P-25 nomination push survives', v_msg); end if;

  -- ---------- [P-26] the nominated runner can still SEE the request ----------
  -- `bookings party read` stays WIDE (0114 §4). Narrowing it would break the 요청 탭 — the exact
  -- flow O-4 exists to preserve.
  v_bad := ''; v_n := -1;
  perform set_config('request.jwt.claim.sub', v_vic::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select count(*) from bookings where id = $1' into v_n using b_pend;
  exception when others then v_bad := ' 예외 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and v_n <> 1 then v_bad := ' 지명된 러너가 자기 요청을 ' || v_n || '행으로 본다 (기대 1)'; end if;
  if v_bad = '' then call _pass('pact','P-26 지명된 러너는 여전히 예약 행을 읽는다 — 요청 탭에서 수락/거절하는 그 경로 (bookings party read는 좁히지 않는다)');
  else v_msg := v_bad; call _fail('pact','P-26 nominee reads the request', v_msg); end if;

  -- ---------- [P-27] history survives the cancel — §0e's cost is WRITE-only ----------
  update bookings set status = 'cancelled_owner' where id = b_conf;
  v_bad := '';
  for r in select 'atk'::text as arm union all select 'vic'
  loop
    perform set_config('request.jwt.claim.sub',
                       case when r.arm = 'atk' then v_atk::text else v_vic::text end, true);
    v_n := -1; v_n2 := -1;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      execute 'select count(*) from chat_threads where id = $1' into v_n using th_conf;
      execute 'select count(*) from chat_messages where thread_id = $1' into v_n2 using th_conf;
    exception when others then v_bad := v_bad || ' ' || r.arm || ' 예외 ' || sqlstate;
    end;
    reset role;
    if v_n <> 1 then v_bad := v_bad || ' ' || r.arm || ' 스레드 ' || v_n || '행'; end if;
    if v_n2 < 1 then v_bad := v_bad || ' ' || r.arm || ' 메시지 ' || v_n2 || '행'; end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-27 취소된 예약의 스레드와 메시지를 양 당사자가 그대로 읽는다 — 좁힘은 쓰기 방향에만 있고 읽기는 전부 넓은 술어 그대로다 (0114 §4)');
  else v_msg := v_bad; call _fail('pact','P-27 history survives cancel', v_msg); end if;

  -- ---------- [P-28] and the room stays open with it — 143 C3's property ----------
  v_bad := '';
  if channel_allowed('chat-' || th_conf::text, v_atk, 'read') is not true then v_bad := v_bad || ' 취소 후 오너가 채팅방에서 밀려났다'; end if;
  if channel_allowed('chat-' || th_conf::text, v_vic, 'read') is not true then v_bad := v_bad || ' 취소 후 러너가 채팅방에서 밀려났다'; end if;
  if v_bad = '' then call _pass('pact','P-28 취소 뒤에도 chat-<thread> 룸이 열려 있다 — 룸은 테이블을 거울처럼 따라야 하고(0108 §2), 테이블의 읽기는 안 좁혔다');
  else v_msg := v_bad; call _fail('pact','P-28 room mirrors the table after cancel', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- 🔵 THE INCIDENT-OPENER DECISION GETS ITS OWN PINS (contract F4)
  --    §3's set is WIDER than §1's. A decision with no pin is a comment — and P-6 alone would stay
  --    green under a naive `is_booking_party_active` gate, which is precisely the implementation
  --    the decision rejects. So the widening needs positives of its own.
  -- ══════════════════════════════════════════════════════════════════════════════════════════

  -- ---------- [P-31] 🔵 the safety door stays open at cancelled_owner ----------
  -- b_saf was driven runner_pending → confirmed → runner_enroute → cancelled_owner, i.e. its state
  -- is PROVABLY post-accept. This is 0066's en-route cancel: the owner cancelled while the runner
  -- was already moving, possibly at the door. If something goes wrong in that minute, this is the
  -- status the booking is standing in. 🔴 This is the pin that fails if §3 reuses §1's predicate.
  v_bad := ''; v_id := null; v_id2 := null;
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id using b_saf, 'dog_injury';
  exception when others then v_bad := v_bad || ' 오너 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', v_vic::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id2 using b_saf, 'dog_injury';
  exception when others then v_bad := v_bad || ' 러너 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and (v_id is null or v_id2 is null) then v_bad := ' id가 안 나왔다'; end if;
  if v_bad = '' and v_id2 is distinct from v_id then v_bad := ' 두 번째 호출이 같은 사건이 아니라 새 id를 만들었다'; end if;
  if v_bad = '' then call _pass('pact','P-31 🔵 cancelled_owner(en-route 취소, 실제 수락 경로로 도달)에서 양측 다 인시던트를 연다 — 좁힘이 안전 문까지 닫으면 안 된다는 결정의 실행형');
  else v_msg := v_bad; call _fail('pact','P-31 safety door at cancelled_owner', v_msg); end if;

  -- ---------- [P-32] 🔵 post-incident refund_pending is reportable ----------
  -- b_ref went confirmed → cancelled_runner → refund_pending, the two-step `0038:219-221` uses
  -- because the direct edge is illegal. Parties who DID accept and ran, whose first incident
  -- settled, must be able to report a second fact about the same run (contract F3).
  v_bad := ''; v_id := null;
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id using b_ref, 'other';
  exception when others then v_bad := ' ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and v_id is null then v_bad := ' id가 안 나왔다'; end if;
  if v_bad = '' then call _pass('pact','P-32 🔵 수락 집합에서 도달한 refund_pending도 접수 가능 — 첫 인시던트가 정산됐다고 두 번째 사실을 못 말하게 되면 안 된다');
  else v_msg := v_bad; call _fail('pact','P-32 reportable at post-incident refund_pending', v_msg); end if;

  -- ---------- [P-33] 🔵 the widening did NOT become "everyone" ----------
  -- P-6/P-8 already execute this; P-33 exists so the DECISION has a negative of its own recorded
  -- next to its positives, and so a future widening of the reportable set reddens something.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_atk::text, true);
  for r in select b_pend as bk, 'runner_pending'::text as lbl union all select b_open, 'matching'
  loop
    v_st := null; v_msg := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      perform open_incident_tx(r.bk, 'lost_dog');
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate; v_msg := sqlerrm;
    end;
    reset role;
    if v_st <> 'P0001' or coalesce(v_msg,'') <> 'booking_not_reportable' then
      v_bad := v_bad || ' ' || r.lbl || '=' || coalesce(v_st,'NULL') || '/' || coalesce(v_msg,'-');
    end if;
  end loop;
  if v_bad = '' then call _pass('pact','P-33 🔵 넓힌 집합도 여전히 집합이다 — runner_pending·matching에서 open_incident_tx는 booking_not_reportable (B-11.f는 닫힌 채다)');
  else v_msg := '기대와 다른 결과:' || v_bad; call _fail('pact','P-33 the wider set is still a set', v_msg); end if;

  -- ---------- [P-34] idempotence survives the state move — §3's placement, executable ----------
  -- The existing-open-incident return sits ABOVE the state gate, so an already-open case still
  -- hands back its id no matter where the booking has travelled since.
  -- ⚠⚠ TWO ARMS, and **arm B is the one that can fail.** Arm A is the contract's specified route
  --   (→ refund_pending), which is INSIDE §3's set — so a gate moved above the return would still
  --   pass it, and the pin would be a false green in the shape of the very defect it was written
  --   to rule out. Arm B lands on `expired`, which is OUTSIDE the set (§C.3(5)'s own prose names
  --   it), reached by the legal `confirmed → matching → expired` path (`0066:51`; `0017:9`'s cron
  --   sink). Arm A is kept as the in-set control so both halves of the property are recorded.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_atk::text, true);

  -- arm A: confirmed → runner_enroute → incident_review → refund_pending (still in the set)
  v_id1 := null; v_id2 := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id1 using b_idem, 'equipment';
  exception when others then v_bad := v_bad || ' A개설 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  update bookings set status='runner_enroute' where id=b_idem;
  update bookings set status='incident_review' where id=b_idem;
  update bookings set status='refund_pending'  where id=b_idem;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id2 using b_idem, 'equipment';
  exception when others then v_bad := v_bad || ' A재호출 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and (v_id1 is null or v_id2 is distinct from v_id1) then
    v_bad := v_bad || ' A: 같은 id가 안 돌아왔다 (' || coalesce(v_id1::text,'NULL') || ' vs ' || coalesce(v_id2::text,'NULL') || ')';
  end if;

  -- arm B: confirmed → matching → expired (OUTSIDE the set — the diagnostic arm)
  v_id1 := null; v_id2 := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id1 using b_idem2, 'third_party';
  exception when others then v_bad := v_bad || ' B개설 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  update bookings set status='matching' where id=b_idem2;
  update bookings set status='expired'  where id=b_idem2;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    execute 'select open_incident_tx($1, $2)' into v_id2 using b_idem2, 'third_party';
  exception when others then v_bad := v_bad || ' B재호출 ' || sqlstate || '/' || sqlerrm;
  end;
  reset role;
  if v_bad = '' and (v_id1 is null or v_id2 is distinct from v_id1) then
    v_bad := v_bad || ' B: expired로 간 뒤 열린 사건의 id가 안 돌아왔다 (' || coalesce(v_id1::text,'NULL') || ' vs ' || coalesce(v_id2::text,'NULL') || ')';
  end if;

  if v_bad = '' then call _pass('pact','P-34 이미 열린 사건은 예약이 refund_pending(집합 안)로 가도, expired(집합 밖)로 가도 같은 id를 돌려준다 — 상태 게이트가 멱등 반환보다 아래에 있다는 것의 실행형. 응급 상황의 더블탭이 거절로 바뀌지 않는다');
  else v_msg := v_bad; call _fail('pact','P-34 idempotence survives the state move', v_msg); end if;
end $$;
