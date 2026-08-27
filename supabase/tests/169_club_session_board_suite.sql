-- ═══ 169: club_session_board (0136) — P1~P22 ═══
-- Contract: docs/contracts/club-board-s2-contract.md §8.
--
-- THE DONE TEST this suite mechanises (§12): a reviewer holding an authenticated JWT for an
-- account that joined the club one minute ago, calling club_session_board against a live
-- session, CANNOT NAME any address, any money value, any phone or emergency contact, any
-- incident, any breed or health attribute, or the identity of any runner who has not yet
-- accepted — and gets the SAME answer for a session id that does not exist as for one they
-- cannot see.
--
-- ⚠ P14 AND P15 ARE DIFFERENT PROPOSITIONS AND BOTH ARE NEEDED. P14 reads the OUT-column list
--   off pg_proc: a column that does not exist cannot leak (shape). P15 asserts no returned TEXT
--   contains a value the fixture planted for EACH forbidden class — address, money, phone,
--   emergency contact, incident, dog attribute: a value smuggled through the `state` label
--   would pass P14 and fail P15. The battery's 「interpolate the fare into the state label」
--   mutation reddens P15 and NOT P14 — that is why both exist.
-- ⚠ P15 WAS NARROWER THAN ITS NAME UNTIL 2026-08-27 (found by codex, confirmed by mutation): it
--   seeded ONLY a phone and then checked for money-shaped digits, so 「값 밀반출 없음」 was a claim
--   about two classes wearing the name of six. An address interpolated into the `state` label
--   passed it. The fix is not a longer assertion list — it is a FIXTURE that actually contains
--   one unmistakable value per class, plus a seed control so a seed that stops landing fails the
--   pin instead of making it vacuously green.
-- ⚠ P4 ≡ P5 is the anti-enumeration property. Compared to EACH OTHER, not to a literal.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  hh uuid; mem uuid; strg uuid; own uuid; run uuid; run2 uuid; guest uuid; bkp uuid; pure uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; rt uuid; club uuid; ses uuid; sd1 uuid; sd3 uuid; sd4 uuid;
  v_n int; v_n2 int; v_txt text; v_txt2 text; v_msg text; v_bad text := ''; v_ts timestamptz;
  rec record;
  -- P15's sentinel machinery (2026-08-27) and P16's expected-value pair.
  v_addr uuid; v_who uuid; v_money text[]; v_forbidden text[]; v_hits text;
  v_name_exp text; v_photo_exp text;
begin
  hh    := t_user('bd_host',   'runner');
  bkp   := t_user('bd_backup', 'runner');
  mem   := t_user('bd_member', 'owner');
  strg  := t_user('bd_stranger','owner');
  own   := t_user('bd_owner',  'owner');
  run   := t_user('bd_runner', 'runner'); update runners set tier = 'veteran' where profile_id = run;
  -- ⚠ A SECOND runner for the R3 pairing. `run` is reserved for P8's crew→commit transition, and
  --   `session_assign_dog` requires its runner to be COMMITTED to the session (capacity is read
  --   through `_club_runner_load` against the assignment). Committing `run` early would delete
  --   P8's fixture — the crew row it needs to observe disappearing.
  run2  := t_user('bd_runner2','runner'); update runners set tier = 'veteran' where profile_id = run2;
  -- ⚠ P16 NEEDS AN AVATAR TO EXIST, or its three visible arms cannot tell 「the gate is shut」 from
  --   「this runner never had a photo」 — a NULL-vs-NULL comparison that passes for the wrong reason.
  --   `t_user` leaves avatar_url NULL, so the fixture states it. Digit-free on purpose: P15
  --   concatenates every returned text column and greps it for money shapes.
  update profiles set avatar_url = 'https://cdn.test.local/avatar-run-two.png' where id = run2;
  guest := t_user('bd_guest',  'owner');
  d1 := t_dog(own, '보드견1');
  d2 := t_dog(mem, '동반견2');
  d3 := t_dog(own, '페어링견3');
  d4 := t_dog(own, '철회견4');
  -- ⚠ R7 SENTINELS ARE PLANTED **HERE**, BEFORE ANY DELEGATION EXISTS, AND THE PLACEMENT IS
  --   LOAD-BEARING — not tidiness. `club_dog_materiality` is an AFTER `update of weight_kg`
  --   trigger (0119 family) that, for an APPROVED live delegation, sets review_needed, writes an
  --   `assignment_events` revocation and pushes the booking back to `matching` with runner_id
  --   NULL. Planting the weight after 승인 would therefore DELETE P16/P17's fixture — the proposed
  --   pairing they exist to read — while looking like an innocuous fixture line. At this point in
  --   the file no session_dogs row references these dogs, so the trigger's loop is empty.
  --   breed/memo/vaccinations are R7's 「name+photo 이상의 속성」 — 견종, 러너에게 전달되는 성향
  --   메모, 접종 기록(건강 속성). weight is numeric, so its sentinel is a value (88.8), not a
  --   string. P15 checks all four.
  -- ⚠ `dogs.collar` CANNOT CARRY A SENTINEL AND IS NOT FAKED: 0033:7 constrains it to eight
  --   palette keys ('tangerine'|'sky'|…), so any unnatural value is rejected by the CHECK
  --   (measured — the first draft of this line died on `dogs_collar_check`). Planting a REAL
  --   palette key instead would give an ambiguous hit, which is worse than an honest gap, so the
  --   column is left to P14's shape arm and named here rather than silently omitted.
  update dogs set breed = 'ZZBREEDSENTINEL', memo = 'ZZMEMOSENTINEL', weight_kg = 88.8,
                  vaccinations = '[{"type": "ZZVACCINESENTINEL", "at": "2026-01-01"}]'::jsonb
   where id in (d1, d2, d3, d4);
  -- ⚠ A PURE CLUB MEMBER — joined the club, never touched the session. P1 needs a caller whose
  --   ONLY route in is `club_members`; `mem` also holds a session_people row (shell 'full'), so a
  --   P1 written on `mem` passes through the shell arm and cannot see the membership arm being
  --   deleted. Measured: mutation M1 reddened NOTHING until this fixture existed.
  pure  := t_user('bd_pure',   'owner');
  rt := t_route('보드 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  -- ⚠ DISTRICT NAMES ARE A SHARED NAMESPACE ACROSS THE WHOLE HARNESS. `club_request_district`
  --   RETURNS AN EXISTING club for a district instead of creating one, so a name another suite
  --   already used hands back that suite's club — already `active`, so `club_claim_host` raises
  --   `not_collecting` and the failure surfaces at the DO block's end, far from its cause.
  --   Measured: '보드동' is 60_custody_suite.sql:305's. Grep before choosing a district.
  club := club_request_district('멤버보드동');
  perform club_claim_host(club);
  -- The precondition the raise above was really about, asserted so a future collision names
  -- itself instead of appearing as an unrelated error 250 lines later.
  select count(*) into v_n from clubs where id = club and host_profile_id = hh;
  if v_n <> 1 then raise exception 'fixture: club not claimed by this suite (district collision?)'; end if;
  -- ⚠ 90 minutes: `session_assign_dog`/`session_propose_dog` refuse outside
  --   [scheduled − 2h, scheduled + 6h] (`assign_window`), and `session_rsvp` refuses a past
  --   session — the fixture has to sit inside BOTH windows at once.
  ses  := club_create_session(club, now() + interval '90 minutes', '보드 집결지', rt, 8, 'mixed');
  -- ⚠ Two delegated pairings live in this fixture (one for P6's withdraw, one for R3), and
  --   `session_approve_dog` refuses past `delegated_dog_capacity` with `no_capacity`. Raised
  --   explicitly rather than hoping the default fits: `club_sessions` carries no trigger, so this
  --   is a plain fixture write and not something a normalizer will rewrite.
  update club_sessions set backup_host_profile_id = bkp, delegated_dog_capacity = 6 where id = ses;

  -- a delegated pairing (P0 pending — see the S2.5 note below), and a 동반견
  perform set_config('request.jwt.claim.sub', own::text, false);
  sd1 := session_delegate_dog(ses, d1, t_consent());
  -- a SECOND delegated pairing, kept alive for R3 (P16/P17). It must be a DELEGATED dog: a
  -- 동반견 has no runner by construction, so proposing one on it is nonsense the axes normalizer
  -- would erase anyway.
  sd3 := session_delegate_dog(ses, d3, t_consent());
  -- ⚠ A proposal requires an APPROVED and PAID pairing (`session_propose_dog`: approval must be
  --   'approved' and booking_id non-null). Driven through the real chain in 163's order rather
  --   than hand-set, because the axes normalizer rewrites anything hand-set.
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sd3, true);
  perform set_config('request.jwt.claim.sub', own::text, false);
  perform session_pay_delegation(sd3, 't168-idem-sd3', true);
  -- ⚠ A PAID pairing that is then WITHDRAWN. `session_cancel_delegation` only writes
  --   approval='withdrawn' on a booking-less row; a paid one keeps its booking_id, which is what
  --   makes the liveness clause (`service_state <> 'ended' OR booking_id is not null`) still
  --   admit it. That is the ONLY fixture where the approval filter is load-bearing — with a
  --   booking-less row, liveness excludes it anyway and P6 passes for the wrong reason.
  --   Measured: mutation M3 (re-adding 0053:333's self-arm) reddened NOTHING until this existed.
  sd4 := session_delegate_dog(ses, d4, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sd4, true);
  perform set_config('request.jwt.claim.sub', own::text, false);
  perform session_pay_delegation(sd4, 't168-idem-sd4', true);
  update session_dogs set approval = 'withdrawn' where id = sd4;
  perform set_config('request.jwt.claim.sub', mem::text, false);
  perform session_rsvp(ses, d2);                      -- owner_handled + a people row
  -- a dogless GUEST (owner_attending — NOT a runner: ruling #6's whole point)
  perform set_config('request.jwt.claim.sub', guest::text, false);
  perform session_rsvp(ses, null);
  perform set_config('request.jwt.claim.sub', pure::text, false);
  perform club_join(club);

  ------------------------------------------------------------------------------------------
  -- P1: a club_members row for the session's club → rows returned.
  -- ⚠ SCOPE: proves the MEMBERSHIP arm fires. Says nothing about shell grades (P2/P3 own those).
  -- asserted, not assumed: `pure` must have NO session_people row and NO delegation, or this
  -- pin is measuring the shell arm while claiming to measure membership.
  select count(*) into v_n2 from session_people where session_id = ses and profile_id = pure;
  if v_n2 <> 0 then v_bad := v_bad || ' pure-has-people-row'; end if;
  perform set_config('request.jwt.claim.sub', pure::text, false);
  discard plans;
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'role did not take'; end if;
  select count(*) into v_n from club_session_board(ses);
  set local role postgres;
  v_msg := v_bad || ' rows=' || v_n;
  if v_bad <> '' or v_n < 1 then call _fail('bds','P1 멤버십 팔 (순수 멤버)', v_msg);
                            else call _pass('bds','P1 멤버십 팔 (순수 멤버)'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- P2: shell `full` with NO club_members row → rows returned. Proves the shell arm is a real
  -- OR, not decoration. The guest RSVP'd (session_people row ⇒ shell 'full') and never joined
  -- the club — asserted here rather than assumed.
  select count(*) into v_n from club_members where club_id = club and profile_id = guest;
  if v_n <> 0 then v_bad := v_bad || ' guest-IS-member(' || v_n || ')'; end if;
  perform set_config('request.jwt.claim.sub', guest::text, false);
  set local role authenticated;
  select count(*) into v_n2 from club_session_board(ses);
  set local role postgres;
  v_msg := v_bad || ' rows=' || v_n2;
  if v_bad <> '' or v_n2 < 1 then call _fail('bds','P2 셸 팔은 진짜 OR다', v_msg);
                             else call _pass('bds','P2 셸 팔은 진짜 OR다'); end if;

  ------------------------------------------------------------------------------------------
  -- P4 / P5: 🔴 THE ANTI-ENUMERATION PAIR. Neither a member nor a party → zero rows; a
  -- NONEXISTENT session id → zero rows. Compared to EACH OTHER: a session that does not exist
  -- and a session you cannot see must be indistinguishable, or this is an oracle over session
  -- ids. Zero rows, never an exception (§10 T3 — today's operational board does NOT have this
  -- property, and the contract records that divergence rather than harmonising to it).
  v_bad := '';
  perform set_config('request.jwt.claim.sub', strg::text, false);
  set local role authenticated;
  begin
    select count(*) into v_n  from club_session_board(ses);
    select count(*) into v_n2 from club_session_board('00000000-0000-4000-8000-000000000000'::uuid);
  exception when others then v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  set local role postgres;
  v_msg := v_bad || ' denied=' || coalesce(v_n::text,'∅') || ' missing=' || coalesce(v_n2::text,'∅');
  if v_bad <> '' or v_n <> 0 or v_n2 <> 0
    then call _fail('bds','P4≡P5 거부와 부재가 구별불가', v_msg);
    else call _pass('bds','P4≡P5 거부와 부재가 구별불가'); end if;

  ------------------------------------------------------------------------------------------
  -- P6: a P0 `approval='pending'` row IS returned; `rejected`/`withdrawn` are NOT — INCLUDING
  -- to their own owner (0053:333's self-arm must not leak into a public projection).
  -- ⚠ S2.5 SEQUENCING, MEASURED NOT ASSUMED: the contract's §13a rewrites this pin 「after
  --   S2.5」, because that slice makes session_delegate_dog insert 'approved' and removes the
  --   `pending` producer. S2.5 HAS NOT LANDED — production still inserts 'pending', verified at
  --   authoring — so this pin is correct AS WRITTEN today. Whoever lands S2.5 restates it.
  perform set_config('request.jwt.claim.sub', own::text, false);
  set local role authenticated;
  select count(*) into v_n from club_session_board(ses) b where b.dog_name = '보드견1';
  set local role postgres;
  if v_n <> 1 then v_bad := ' pending-missing(' || v_n || ')'; else v_bad := ''; end if;
  -- now withdraw it: session_cancel_delegation writes 'withdrawn' (0124:74) through the real RPC
  perform set_config('request.jwt.claim.sub', own::text, false);
  perform session_cancel_delegation(sd1);
  set local role authenticated;
  -- 철회견4 is PAID, so liveness admits it and ONLY the approval filter can hide it — the arm
  -- this pin actually owns. 보드견1 (booking-less) is excluded by liveness either way.
  select count(*) into v_n2 from club_session_board(ses) b where b.dog_name = '철회견4';
  set local role postgres;
  v_msg := v_bad || ' paid_withdrawn_to_OWNER=' || v_n2;
  if v_bad <> '' or v_n2 <> 0
    then call _fail('bds','P6 pending 노출 · withdrawn은 본인에게도 비노출', v_msg);
    else call _pass('bds','P6 pending 노출 · withdrawn은 본인에게도 비노출'); end if;

  ------------------------------------------------------------------------------------------
  -- P7: a dogless NON-RUNNER guest appears as row_kind='crew'. Ruling #6's corrected predicate,
  -- not the spec's `role='runner_attending'` (which would have dropped every guest).
  -- ⚠ RESOLVE THE EXPECTED NAME AS postgres, BEFORE the role switch. Read inside the
  --   `authenticated` block, `(select name from profiles where id = guest)` is subject to
  --   profiles' RLS and returns NULL, so the comparison is NULL and the pin counts 0 while the
  --   board is perfectly correct — a fixture artefact that reads exactly like a product defect.
  --   The board dump in the failure message is what separated the two.
  select name into v_txt from profiles where id = guest;
  perform set_config('request.jwt.claim.sub', mem::text, false);
  set local role authenticated;
  select count(*) into v_n from club_session_board(ses) b
   where b.row_kind = 'crew' and b.owner_name = v_txt;
  set local role postgres;
  select role into v_txt2 from session_people where session_id = ses and profile_id = guest;
  declare v_dump text; begin
  select coalesce(string_agg(b2.row_kind || '/' || coalesce(b2.owner_name,'∅'), ' | '), 'none')
    into v_dump from club_session_board(ses) b2;
  v_msg := 'crew_rows=' || v_n || ' guest_role=' || coalesce(v_txt2,'∅') || ' board=[' || v_dump || ']';
  -- the role assertion is what proves the pin tests ruling #6 rather than passing by luck
  if v_n <> 1 or v_txt2 is distinct from 'owner_attending'
    then call _fail('bds','P7 게스트도 크루 (룰링 #6)', v_msg);
    else call _pass('bds','P7 게스트도 크루 (룰링 #6)'); end if;
  end;

  ------------------------------------------------------------------------------------------
  -- P8: the same person after session_runner_commit (role → handling_runner, 0043:238-240) is
  -- NO LONGER a crew row. The promotion transition, handled rather than assumed.
  perform set_config('request.jwt.claim.sub', run::text, false);
  perform session_rsvp(ses, null);                    -- runner_attending (tier <> applicant)
  set local role authenticated;
  select count(*) into v_n from club_session_board(ses) b
   where b.row_kind = 'crew' and b.owner_name = (select name from profiles where id = run);
  set local role postgres;
  perform set_config('request.jwt.claim.sub', run::text, false);
  perform session_runner_commit(ses);
  set local role authenticated;
  select count(*) into v_n2 from club_session_board(ses) b
   where b.row_kind = 'crew' and b.owner_name = (select name from profiles where id = run);
  set local role postgres;
  v_msg := 'before=' || v_n || ' after_commit=' || v_n2;
  if v_n <> 1 or v_n2 <> 0 then call _fail('bds','P8 커밋하면 크루에서 빠진다', v_msg);
                           else call _pass('bds','P8 커밋하면 크루에서 빠진다'); end if;

  ------------------------------------------------------------------------------------------
  -- P9: an owner_handled dog appears with state='보호자 동반'. Ruling #2's visibility (today
  -- those dogs are on NO board — 0053:330) and F2's no-money in one row.
  perform set_config('request.jwt.claim.sub', mem::text, false);
  set local role authenticated;
  select b.row_kind, b.state, b.runner_name into rec
    from club_session_board(ses) b where b.dog_name = '동반견2';
  set local role postgres;
  v_msg := 'kind=' || coalesce(rec.row_kind,'∅') || ' state=' || coalesce(rec.state,'∅')
           || ' runner=' || coalesce(rec.runner_name,'∅');
  if rec.row_kind is distinct from 'owner_handled' or rec.state is distinct from '보호자 동반'
     or rec.runner_name is not null
    then call _fail('bds','P9 동반견 가시 · 러너 없음', v_msg);
    else call _pass('bds','P9 동반견 가시 · 러너 없음'); end if;

  ------------------------------------------------------------------------------------------
  -- P14: 🔴 THE SHAPE PIN. The function's OUT-column list carries no name matching the forbidden
  -- vocabulary. R1/R2/R4/R5/R7/R8 as a property of the SIGNATURE — a column that does not exist
  -- cannot leak, no matter what a future body does.
  -- ⚠ AMENDED 2026-08-27, and the amendment is the point rather than a nuisance. `profile_id` was
  --   in this forbidden list because contract R8 refused ids outright. **Sean reversed R8**
  --   (「for the tap for profile, yes make it like instagram」) so board rows can route to a
  --   profile, and 0139 adds `owner_profile_id`/`runner_profile_id`. This pin therefore asserts a
  --   proposition that is no longer true, and leaving it red would make the harness red for a
  --   CORRECT change — so it is amended here, in the slice that moved it, per the law on pins
  --   whose pinned behaviour legitimately changes.
  --   ⚠ ONLY those two names are excused, and by NAME, not by dropping `profile_id` from the
  --     pattern — a bare `booking_id`, a `session_dog_id`, or any other id must still fail. And
  --     the property Sean did NOT reverse (an id must not be disclosed where the name is hidden)
  --     is owned by **suite 172 I2**, which measures the two as a conjunction. This pin is about
  --     SHAPE; that one is about the gate. Neither is evidence for the other.
  select coalesce(string_agg(a, ' '), '') into v_txt
    from (select unnest(p.proargnames) a from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
          where p.proname = 'club_session_board') q
   where a ~* '(addr|fare|price|fee|gross|rate|phone|emergency|incident|breed|weight|memo|booking_id|profile_id)'
     and a not in ('owner_profile_id', 'runner_profile_id');
  if v_txt <> '' then call _fail('bds','P14 금지 컬럼 부재 (형태)', v_txt);
                 else call _pass('bds','P14 금지 컬럼 부재 (형태)'); end if;

  ------------------------------------------------------------------------------------------
  -- P15: 🔴 THE VALUE PIN, and it is NOT the same proposition as P14. A fare/address/phone
  -- smuggled through the `state` label would pass P14 and must fail here.
  --
  -- 🔴 THE PROPOSITION, in words: for each class the contract §4 REFUSES, this fixture contains a
  -- value that cannot occur naturally, that value is REACHABLE from the board's own row (one join
  -- away from `session_dogs`), and no text column club_session_board returns — read by three
  -- different callers, including the most privileged ones — contains it.
  --   R1 주소     → addresses.addr/detail/label ← bookings.address_id ← session_dogs.booking_id
  --   R2 금액     → this session's REAL fares, read at runtime (never a literal — a literal would
  --                 pin the pin to today's price list and go quietly false when 요금 changes)
  --   R4 연락처   → profiles.phone (보호자) · delegation_consents.emergency_contact/pickup_contact
  --   R5 인시던트 → incidents.note ← incidents.booking_id = session_dogs.booking_id
  --   R7 개 속성  → dogs.breed/memo/vaccinations/weight_kg (planted at fixture creation — see
  --                 there; `collar` is CHECK-constrained to a palette and takes no sentinel)
  --
  -- ⚠ WHAT THIS GREEN DOES **NOT** PROVE, stated because the old version of this pin was read as
  --   proving all six while seeding one:
  --   ⓐ It says nothing about classes with no reachable column in THIS fixture. Measured while
  --     writing it: `addresses.gate_code_enc` is ciphertext and no join in the board's query
  --     reaches it; 러너 정산/수수료 rows (ledger_items, payments) hang off the booking too but a
  --     `state` label could only carry them by a join this pin does not force to exist. Those stay
  --     P14's problem (a column that does not exist cannot leak) — SHAPE, not value.
  --   ⓑ It is a statement about this projection for this caller set, never about whether the
  --     values are protected anywhere else. Their own tables' RLS owns that.
  --   ⓒ A leak that ENCODES rather than copies (a hash, a truncation, an id that resolves to the
  --     address elsewhere) passes this pin by construction. Substring search is the floor.
  update profiles set phone = '01088887777' where id = own;
  -- R1 — the refused address is the PICKUP address, and the board's only path to one is the
  -- booking, so it is planted exactly there rather than on a table the projection cannot see.
  insert into addresses (owner_id, label, addr, detail)
  values (own, 'ZZLABELSENTINEL', 'ZZADDRSENTINEL', 'ZZADDRDETAILSENTINEL')
  returning id into v_addr;
  update bookings set address_id = v_addr
   where id = (select sd.booking_id from session_dogs sd where sd.id = sd3);
  -- R4 — the emergency contact rides the consent record, one join off the session_dog.
  update delegation_consents
     set emergency_contact = 'ZZEMERGSENTINEL', pickup_contact = 'ZZPICKUPCONTACTSENTINEL'
   where session_dog_id = sd3;
  -- R5 — a real incident row on the same booking. `incidents` carries no trigger, and no function
  -- in the club chain reads it (measured against pg_proc), so this plants a value without moving
  -- any state P16/P17 depend on.
  insert into incidents (booking_id, reporter_id, kind, severity, note)
  select sd.booking_id, own, 'dog_injury', 'urgent', 'ZZINCIDENTSENTINEL'
    from session_dogs sd where sd.id = sd3;

  -- 🔴 THE SEED CONTROL. A pin that greps for a value nobody planted passes for free, and it
  -- passes LOUDER the more classes you list. Each arm below asserts the sentinel is present AND
  -- reachable from this session — so a schema change that quietly drops a column reddens the pin
  -- instead of widening its green.
  v_bad := '';
  if not exists (select 1 from session_dogs sd join bookings bk on bk.id = sd.booking_id
                   join addresses a on a.id = bk.address_id
                  where sd.session_id = ses and a.addr = 'ZZADDRSENTINEL')
    then v_bad := v_bad || ' SEED-addr'; end if;
  if not exists (select 1 from session_dogs sd
                   join delegation_consents dc on dc.session_dog_id = sd.id
                  where sd.session_id = ses and dc.emergency_contact = 'ZZEMERGSENTINEL')
    then v_bad := v_bad || ' SEED-emergency'; end if;
  if not exists (select 1 from session_dogs sd join profiles p on p.id = sd.owner_profile_id
                  where sd.session_id = ses and p.phone = '01088887777')
    then v_bad := v_bad || ' SEED-phone'; end if;
  if not exists (select 1 from session_dogs sd join dogs d on d.id = sd.dog_id
                  where sd.session_id = ses and d.breed = 'ZZBREEDSENTINEL'
                    and d.memo = 'ZZMEMOSENTINEL' and d.weight_kg = 88.8
                    and d.vaccinations::text like '%ZZVACCINESENTINEL%')
    then v_bad := v_bad || ' SEED-dogattr'; end if;
  if not exists (select 1 from session_dogs sd join incidents i on i.booking_id = sd.booking_id
                  where sd.session_id = ses and i.note = 'ZZINCIDENTSENTINEL')
    then v_bad := v_bad || ' SEED-incident'; end if;
  -- R2's sentinels are the fixture's ACTUAL fares, in both the raw and the 천 단위 콤마 form — a
  -- value rendered as 「24,900원」 is the same leak as one rendered as 24900 and the old regex saw
  -- neither reliably. Anything under 1,000 is excluded: a one- or two-digit literal matches
  -- Korean state labels and dog names by accident, which would make this arm noise.
  select coalesce(array_agg(distinct f), array[]::text[]) into v_money
    from (select unnest(array[bk.total_price, bk.base_fare, bk.distance_fare, bk.min_fare]) amt
            from session_dogs sd join bookings bk on bk.id = sd.booking_id
           where sd.session_id = ses) q
    cross join lateral (values (q.amt::text), (to_char(q.amt, 'FM999,999,999'))) t(f)
   where q.amt >= 1000;
  if coalesce(array_length(v_money, 1), 0) = 0 then v_bad := v_bad || ' SEED-money'; end if;

  -- Read with THREE pairs of eyes, because the R3 gate opens for some of them: a third party
  -- (mem), the delegated dog's own 보호자 (own), and the host (hh). A value that only leaks down
  -- the privileged branch is still a leak, and a single third-party read cannot see that branch.
  v_txt := '';
  foreach v_who in array array[mem, own, hh] loop
    perform set_config('request.jwt.claim.sub', v_who::text, false);
    set local role authenticated;
    select v_txt || ' ' || coalesce(string_agg(
             coalesce(b.row_kind,'') || ' ' || coalesce(b.dog_name,'') || ' ' || coalesce(b.owner_name,'')
             || ' ' || coalesce(b.state,'') || ' ' || coalesce(b.runner_name,'')
             || ' ' || coalesce(b.dog_photo_url,'') || ' ' || coalesce(b.runner_photo_url,''), ' '), '')
      into v_txt from club_session_board(ses) b;
    set local role postgres;
  end loop;

  v_forbidden := array['ZZADDRSENTINEL','ZZADDRDETAILSENTINEL','ZZLABELSENTINEL',
                       'ZZEMERGSENTINEL','ZZPICKUPCONTACTSENTINEL','01088887777',
                       'ZZBREEDSENTINEL','ZZMEMOSENTINEL','ZZVACCINESENTINEL','88.8',
                       'ZZINCIDENTSENTINEL'] || v_money;
  -- Pre-computed into a variable, never a subquery inside `_fail` (the 110 header law).
  select coalesce(string_agg(s, ' '), '') into v_hits
    from unnest(v_forbidden) s where v_txt like '%' || s || '%';
  -- The shape arm survives from the original pin: it catches a money value this fixture never
  -- produced (a fee computed inside the projection, say), which no sentinel list can enumerate.
  if v_txt ~ '[0-9]{4,}원' or v_txt ~ '\m[0-9]{5,}\M' then v_hits := v_hits || ' MONEYISH'; end if;
  v_msg := v_bad || ' HIT:' || v_hits || ' :: ' || left(v_txt, 160);
  if v_bad <> '' or v_hits <> '' then call _fail('bds','P15 값 밀반출 없음', v_msg);
                                 else call _pass('bds','P15 값 밀반출 없음'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- P16 / P17: 🔴 R3 — pairs are public, courtships are not.
  -- Put the pairing at P3 (proposed) and read runner_name as four different callers, then move
  -- to P4 (accepted) and read it as an unrelated member.
  -- ⚠ DRIVEN BY THE REAL RPC, NEVER A DIRECT UPDATE. `session_dogs` carries `club_v1_axes_sync`,
  --   a BEFORE trigger that RECOMPUTES assignment_state on every write (measured: _club_compute_axes
  --   references it), so a hand-set 'proposed' is normalised straight back and the fixture silently
  --   does not exist while the pin looks correct. Suite 167's B2 hit the identical trap.
  -- ⚠ `session_assign_dog` requires the runner to be COMMITTED **and CHECKED IN**
  --   (0047:94 `runner_not_checked_in`). 163's chain does both before assigning; hand-setting
  --   attendance would be rewritten by nothing here, but driving the real RPC is what keeps the
  --   fixture honest about the state the product actually produces.
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_runner_commit(ses);
  perform session_checkin(ses);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sd3, run2);
  -- 🔴 NAME **AND** PHOTO, AS A CONJUNCTION — widened 2026-08-27 (codex). The pin used to assert
  --    runner_name alone, so a body that hid the name and returned `pp.avatar_url` unconditionally
  --    was GREEN: an avatar URL is a stable per-person handle, it renders as a face, and 0139's
  --    own comment says the id 「rides the name's gate, exactly」 for precisely this reason. The
  --    two columns are computed by the IDENTICAL predicate in the function, so asserting one and
  --    not the other measures half of a single decision. Every arm below now states both.
  -- ⚠ EXPECTED VALUES RESOLVED AS postgres, BEFORE any role switch. Read under `authenticated`,
  --   `profiles` is subject to RLS and hands back NULL, and a NULL expectation would make every
  --   visible arm compare NULL to NULL — a pin that passes hardest when it is measuring nothing.
  select p.name, p.avatar_url into v_name_exp, v_photo_exp from profiles p where p.id = run2;
  select assignment_state into v_txt from session_dogs where id = sd3;
  if v_txt is distinct from 'proposed' or v_name_exp is null or v_photo_exp is null then
    call _fail('bds','P16 R3 네 방향 (이름·사진 동시)', 'PRECONDITION assignment_state=' || coalesce(v_txt,'∅')
      || ' exp_name=' || coalesce(v_name_exp,'∅') || ' exp_photo=' || coalesce(v_photo_exp,'∅'));
  else
  v_bad := '';
  -- ⓐ unrelated member → NEITHER. This is the arm the whole R3 refusal is for.
  perform set_config('request.jwt.claim.sub', guest::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_photo_url into v_txt, v_txt2
    from club_session_board(ses) b where b.dog_name = '페어링견3';
  set local role postgres;
  if v_txt  is not null then v_bad := v_bad || ' third-party-SEES-NAME(' || v_txt || ')'; end if;
  if v_txt2 is not null then v_bad := v_bad || ' third-party-SEES-PHOTO(' || v_txt2 || ')'; end if;
  -- ⓑ the dog's owner → both, and they must be THIS runner's, not merely non-NULL. `own` owns
  --   페어링견3; `mem` owns the 동반견 and would be a third party here — reading as the wrong
  --   person made this arm look like a product defect.
  perform set_config('request.jwt.claim.sub', own::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_photo_url into v_txt, v_txt2
    from club_session_board(ses) b where b.dog_name = '페어링견3';
  set local role postgres;
  if v_txt  is distinct from v_name_exp  then v_bad := v_bad || ' owner-NAME(' || coalesce(v_txt,'∅') || ')'; end if;
  if v_txt2 is distinct from v_photo_exp then v_bad := v_bad || ' owner-PHOTO(' || coalesce(v_txt2,'∅') || ')'; end if;
  -- ⓒ the proposed runner → both
  perform set_config('request.jwt.claim.sub', run2::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_photo_url into v_txt, v_txt2
    from club_session_board(ses) b where b.dog_name = '페어링견3';
  set local role postgres;
  if v_txt  is distinct from v_name_exp  then v_bad := v_bad || ' proposed-runner-NAME(' || coalesce(v_txt,'∅') || ')'; end if;
  if v_txt2 is distinct from v_photo_exp then v_bad := v_bad || ' proposed-runner-PHOTO(' || coalesce(v_txt2,'∅') || ')'; end if;
  -- ⓓ THE BACKUP HOST — the nullable-column fail-open arm (§10 T2 / 0116:425)
  perform set_config('request.jwt.claim.sub', bkp::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_photo_url into v_txt, v_txt2
    from club_session_board(ses) b where b.dog_name = '페어링견3';
  set local role postgres;
  if v_txt  is distinct from v_name_exp  then v_bad := v_bad || ' backup-host-NAME(' || coalesce(v_txt,'∅') || ')'; end if;
  if v_txt2 is distinct from v_photo_exp then v_bad := v_bad || ' backup-host-PHOTO(' || coalesce(v_txt2,'∅') || ')'; end if;
  -- ⚠ GREEN DOES NOT PROVE: that runner_profile_id agrees with these two. It is gated by the same
  --   predicate and is the same leak one hop later, but this pin never reads it — suite 172's I2
  --   owns that conjunction. Neither pin is evidence for the other.
  if v_bad <> '' then call _fail('bds','P16 R3 네 방향 (이름·사진 동시)', v_bad);
                 else call _pass('bds','P16 R3 네 방향 (이름·사진 동시)'); end if;
  end if;

  -- P17: at accepted, the pairing is public to an unrelated member.
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_proposal_respond(sd3, true);
  select assignment_state into v_txt from session_dogs where id = sd3;
  if v_txt is distinct from 'accepted' then
    call _fail('bds','P17 수락되면 페어링은 공개', 'PRECONDITION state=' || coalesce(v_txt,'∅'));
  end if;
  perform set_config('request.jwt.claim.sub', guest::text, false);
  set local role authenticated;
  select b.runner_name into v_txt from club_session_board(ses) b where b.dog_name = '페어링견3';
  set local role postgres;
  if v_txt is null then call _fail('bds','P17 수락되면 페어링은 공개', 'still null');
                   else call _pass('bds','P17 수락되면 페어링은 공개'); end if;

  ------------------------------------------------------------------------------------------
  -- P18: a null-uid caller (ops/harness) gets rows without a gate error. 0116 §D's shared
  -- exemption, pinned rather than assumed.
  -- ⚠ SCOPE: this does NOT prove a client can ever be null-uid — it cannot, because the only
  --   EXECUTE holders are `authenticated` (always carries a JWT sub) and server roles.
  perform set_config('request.jwt.claim.sub', '', false);
  select count(*) into v_n from club_session_board(ses);
  if v_n < 1 then call _fail('bds','P18 null-uid 면제', 'rows=' || v_n);
              else call _pass('bds','P18 null-uid 면제'); end if;

  ------------------------------------------------------------------------------------------
  -- P19 / P20 / P21: the ACL both directions, the in-body search_path, and the caller selector.
  v_bad := '';
  if has_function_privilege('anon', 'club_session_board(uuid)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-CAN'; end if;
  if not has_function_privilege('authenticated', 'club_session_board(uuid)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING'; end if;
  select coalesce(array_to_string(p.proconfig, ','), '') into v_txt
    from pg_proc p where p.proname = 'club_session_board';
  if v_txt not like '%search_path=public, pg_temp%' then v_bad := v_bad || ' searchpath(' || v_txt || ')'; end if;
  select prosrc into v_txt from pg_proc where proname = 'club_session_board';
  -- ⚠ `not like` on a NULL is NULL, so an ABSENT function passes every arm below. Measured on
  --   180 W1/W6 (2026-08-27): pointed at a nonexistent proname, the pins went 1061/0 green.
  if v_txt is null then v_bad := v_bad || ' NO-SOURCE(club_session_board)'; end if;
  if v_txt like '%current_user%' then v_bad := v_bad || ' USES-current_user'; end if;
  if v_txt not like '%auth.uid()%' then v_bad := v_bad || ' NO-auth.uid'; end if;
  if v_bad <> '' then call _fail('bds','P19·P20·P21 ACL·search_path·선택자', v_bad);
                 else call _pass('bds','P19·P20·P21 ACL·search_path·선택자'); end if;

  ------------------------------------------------------------------------------------------
  -- P-R6: state_since is the custody-event time, and NULL before custody begins. The contract
  -- specifies a column the schema can only partly produce (session_dogs has no created_at/
  -- updated_at), and NULL is the honest answer for pre-custody states — not bookings.updated_at,
  -- which is 「last write of any kind」 and would look like an answer without being one.
  perform set_config('request.jwt.claim.sub', mem::text, false);
  set local role authenticated;
  select b.state_since into v_ts from club_session_board(ses) b where b.dog_name = '동반견2';
  set local role postgres;
  select count(*) into v_n from dog_custody_events e
    join session_dogs sd on sd.id = e.session_dog_id
   where sd.session_id = ses and sd.dog_id = d2;
  v_msg := 'events=' || v_n || ' since=' || coalesce(v_ts::text,'NULL');
  if (v_n = 0 and v_ts is not null) or (v_n > 0 and v_ts is null)
    then call _fail('bds','R6 state_since는 실제 커스터디 이벤트뿐', v_msg);
    else call _pass('bds','R6 state_since는 실제 커스터디 이벤트뿐'); end if;
end $$;
