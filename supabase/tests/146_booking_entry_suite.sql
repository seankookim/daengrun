-- ═══ 146 booking-entry rebuild — 0111 pins (D-1 … D-22) ═══
-- What this suite pins: **a client cannot make a booking row exist, nor the series row a definer
-- cron copies into one.** The row is what `is_booking_party()` reads (`0002:15-22`, no status
-- filter), so a forged booking was a key — chat thread to the victim, a review naming them, an
-- `incidents` row, and an attacker-authored push on their phone. A row carrying someone else's
-- `dog_id` at `matching` publishes that dog through `marketplace_open_requests`. A row with
-- attacker-chosen fares is money: `min_fare` is the runner's gross FLOOR (`0101:136`).
--
-- Supersedes suite 140 (deleted with `0105_booking_insert_party_guard.sql` in the same commit).
-- 140's B5 was a POSITIVE CONTROL asserting a client INSERT on `bookings` SUCCEEDS — after 0111
-- that must fail, and B1-B4/B7 expected `P0001` where they would now see `42501`. Per CLAUDE.md a
-- suite whose pinned behaviour legitimately changes must move in the same slice; since the
-- migration it pinned never applied to any environment, deleting both is the honest form.
--
-- Style: sibling of 144/124/131 — `_pass('bep',…)`/`_fail('bep',…)`, one begin…exception per arm,
--   `_fail` args pre-computed into `v_msg` (the 110 header law).
--
-- ⚠⚠ **EVERY negative arm runs under `set local role authenticated` (or `anon`) with
--   `request.jwt.claim.sub` set, and resets the role in BOTH arms — success and exception.**
--   A pin that runs as `postgres` measures NOTHING: the superuser bypasses RLS and holds every
--   grant, so a revoke-based fix and no fix at all produce identical output and the pin is green
--   either way. That is reviewer F5 of the rejected 0105 — the single defect that made its seven
--   green pins worthless.
-- ⚠ **ONLY the expected sqlstate counts.** These are grant refusals, so `42501`
--   (insufficient_privilege) is the pass — caught by NAME, not `when others`, which would swallow
--   a typo'd column as a security pass. The one exception is D-9, whose subject is the
--   `_guard_booking_cols` TRIGGER: there `P0001` is the pass and a `42501` would be a false green
--   from the wrong layer. A refusal from the wrong layer is not this slice's refusal.
-- ⚠ Every client arm asserts `current_user = <role>` after the `set local role` (custom sqlstate
--   `ZZ001`, 144's idiom): a SET ROLE that silently failed would run the attack as `postgres`, and
--   a SET ROLE that ERRORED would land in the same handler and be recorded for the wrong reason.
-- ⚠⚠ **ONE pin is green when the attack SUCCEEDS: D-1c, and that is deliberate.** It is a
--   BOUNDARY-DOCUMENTING pin — it breaks §2's fence inside its own arm and records that §3's belt
--   re-validates OWNERSHIP ONLY and lets the fare-mint through. Do not "fix" it to expect a
--   refusal; that would delete the only record of §3's limit. It restores the acl state it found
--   (snapshot, not hardcoded) so nothing downstream — D-21 especially — is masked by it.
--
-- ─── SCOPE: what is deliberately NOT here ───────────────────────────────────────────────────
--   · **D-10 (HTTP over the wire)** — `POST /rest/v1/bookings`, `POST /rest/v1/recurring_series`,
--     `PATCH /rest/v1/recurring_series` with a real JWT. Needs a DEPLOYED environment; the harness
--     has no PostgREST. It is a §E.8 live-verification item to be run against production after the
--     deploy, on a throwaway account, rolled back — NOT a harness pin, and it is not claimed as one.
--   · **D-18 / D-19 (`create-booking-hold`)** — TypeScript. The SQL harness cannot see a branch in
--     a Deno handler, which is exactly how C.4 shipped unpinned in the contract's first draft.
--     They live in `supabase/functions/_test/booking_runner_body_test.ts` and run under
--     `deno test --allow-all supabase/functions/_test/`.
--   · **TRUNCATE** — closed on these three tables by 0109 (deployed 2026-08-19 evening) and owned
--     by suite 144. Local privilege state is a model of production, and the authority on a
--     production privilege bit is production's own `relacl`, re-read after the deploy.
--   · **B-6 (club `session_pay_delegation`) and B-8 (`create_recurring_series`)** are already
--     pinned by suites 50/117 and 114 R3. D-13 and D-16 are REGRESSION checks that those stay
--     green — deliberately not re-pins (contract F10: a second copy of a pin is a second thing to
--     keep true, and the first copy is the one that gets updated).
--
-- ─── MUTATION map — EXECUTED, and two contract predictions came back FALSE ──────────────────
--   Every figure below is a full-harness run on worktree `p0-booking-entry`, 2026-08-19.
--   Clean green = **657 / 0** (baseline before the slice 641/0: suite 140's 7 pins leave, 23
--   arrive — round 2 added D-1c and D-22).
--   ⚠ **M1…M6 are ROUND-1 figures, measured against the then-baseline of 655/0, and were NOT
--   re-run in round 2.** The load-bearing claim in each is the **red SET**, which is unchanged;
--   the pass counts are stale by up to 2 and are left as measured rather than adjusted by
--   arithmetic nobody executed. **M7 is round 2's own and WAS executed on this tree.**
--
--   M1   §1's `revoke insert on bookings` deleted, verify block KEPT
--        → the MIGRATION refuses, fail closed, before any pin runs:
--          `ERROR: 0111: client roles still hold INSERT on 2 table-role pair(s): bookings:anon,
--           bookings:authenticated` (harness prints `❌ 0111_booking_entry_rebuild.sql`).
--   M1b  §1's revoke AND both verify blocks deleted → **654 / 1, red = [D-20] ALONE.**
--        ⚠⚠ **The contract predicted D-4/D-5/D-6 here. They stayed GREEN, and the reason is
--        worth more than the prediction was.** §1 is deliberately TWO layers — the revoke and the
--        policy drop — and Postgres reports an RLS refusal with the SAME sqlstate as a privilege
--        refusal (**42501**). With the grant back but `bookings owner insert` still dropped, the
--        INSERT is refused by RLS and every effects pin is satisfied for the WRONG REASON.
--        **This is precisely the failure D-20 exists to catch — a fix that worked for the wrong
--        reason — and it caught it, alone, on the first try.** No effects pin can distinguish the
--        two layers; only the catalog can. Recorded here so nobody later "simplifies" D-20 away
--        as redundant with D-4/D-5/D-6.
--   M1c  §1's revoke, its policy drop, AND the verify blocks all deleted — i.e. the genuine
--        pre-0111 world for `bookings` → **649 / 6, red = [D-4, D-5, D-6, D-1, D-3, D-20]**, and
--        the exploit reproduces verbatim:
--          D-4  `피해자를 러너로 지정한 INSERT가 42501이 아니었다 [SUCCEEDED]`
--          D-5  `dog_id=SUCCEEDED address_id=SUCCEEDED club_session_id=23503 series_id=23503`
--               (the last two are FK violations — the forged row was accepted by every gate this
--               slice is about and died only on a fabricated foreign key)
--          D-3  `공격자 소유 + 피해자 개인 예약이 1건 존재한다`
--        **D-9b stayed GREEN under M1c**, which falsifies its own stated rationale — see D-9b.
--   M2   `service_role` appended to §1's revoke list → the MIGRATION refuses:
--          `ERROR: 0111 OVER-REVOKE: service_role lost INSERT on bookings`.
--   M2b  same, verify blocks removed → **651 / 4, red = [D-20, D-11, 119 ren R2, 125 frc F5]**.
--        ⚠ The contract predicted "D-20 and nothing else, and if D-11 reddens it is doing D-20's
--        job by accident". D-11 reddens — but not by accident and not redundantly: D-11 EXECUTES
--        the service_role insert (`42501 permission denied for table bookings`), which is the
--        outage itself, while D-20 names the privilege that caused it. Both are wanted; the
--        contract's "nothing else" was simply wrong about a pin it had itself specified.
--        (119/125 redden because this slice moved their anti-vacuity controls onto `service_role`
--        — see the ⚠ notes in those files.)
--   M3u  §2's revoke narrowed to `revoke insert, delete …` (the UPDATE verb dropped)
--        → **652 / 3, red = [D-2, D-9c, D-21]**:
--          D-2   `정당한 시리즈를 피해자 개로 갈아끼우는 UPDATE가 42501이 아니었다 [SUCCEEDED]
--                 시리즈 행이 실제로 바뀌었다` — §0③ reproduced from a LEGITIMATE series.
--          D-21  `authenticated가 min_fare·dog_id·total_price·owner_id를 갱신할 수 있다`.
--        ⚠ D-2's CRON half stayed green under this mutation, and that is §3's belt firing for
--        real: the series was successfully repointed at the victim's dog, and the ownership
--        re-check refused to copy it. **But name the arm precisely — round 1 did not, and the
--        round-2 reviewer executed the difference.** D-2 moves the DOG and the money together, and
--        the belt refuses it *because of the dog*. The belt re-validates **OWNERSHIP ONLY and is
--        FARE-BLIND by design** (0111 §3: the fares are a consented snapshot; re-deriving them
--        changes what a recurring owner is charged and is Sean's call). A series that keeps its
--        OWN dog and moves only `total_price`/`min_fare` walks straight past it — **D-1c executes
--        exactly that under the same broken fence and pins the mint at `min_fare` 500,000.**
--        So under a broken fence the belt stops the dog-forgery half of §0②/③ and NOT the
--        fare-mint half; the fare columns are held by `grant update (paused)` and §2's revoke
--        alone. Do not read "the belt is load-bearing" as coverage of the money.
--   M4   §3's ⓔ ownership re-check deleted → **654 / 1, red = [D-1b] ALONE**:
--          `위조 시리즈에서 크론이 1건을 발행했다 (벨트가 발화하지 않았다)` + the missing
--          `raise warning …skipped` in the catalog arm.
--   M6   `grant update (min_fare) on recurring_series to authenticated` added
--        → **653 / 2, red = [D-21, D-9c]**:
--          D-21 `클라 컬럼 그랜트가 정확히 1개가 아니다 — 2개: recurring_series.paused:…,
--                recurring_series.min_fare:authenticated:UPDATE`
--          D-9c `min_fare가 바뀌었다 (9900→500000)` — the widened grant is immediately money.
--        ⚠ D-1c stays GREEN here and does not launder the mutation: it snapshots the column ACLs
--        before breaking the fence and re-grants exactly what it found, so the extra `min_fare`
--        grant survives its cleanup and D-21 — which runs later in the file — still reddens.
--        (Measured separately: `revoke update on <table> from <role>` clears that role's COLUMN
--        UPDATE aclitems too, which is why the restore cannot be a hardcoded `grant update
--        (paused)`.)
--   M7   [ROUND 2, executed] `grant update on recurring_series to authenticated` added to §2 —
--        the TABLE-level re-grant → **the MIGRATION refuses**, before any pin runs:
--          `ERROR: 0111: client roles hold EFFECTIVE INSERT/UPDATE on 16 column(s) they must not:
--           authenticated UPDATE recurring_series.addon_fare, …dog_id, …min_fare, …owner_id,
--           …total_price, …(16 in all)`
--        ⚠⚠ **0111's first verify block AND its attacl sweep both PASSED under this mutation** —
--        `pg_attribute.attacl` holds column-level grants ONLY, so a table-level grant leaves it
--        byte-identical and the "exactly one column grant" claim stays true while every fare
--        column becomes writable. D-21 would have caught it in the HARNESS; the point of the
--        `has_column_privilege` arm added to 0111's second verify block is that it now fails the
--        **DEPLOY**. Restore → 657/0.
--
--   D-9 is NOT mutation-proven against 0111 (it pins 0058's `_guard_booking_cols` deny-all, which
--   this slice does not touch); its mutation is 0058's own — revert the deny-all to 0057's column
--   list and the `status`-column arm reddens. It is here because it is the one load-bearing claim
--   in the rejected 0105's header that was TRUE and unpinned (reviewer F7).
--
--   D-11·D-12·D-14·D-15·D-17 = POSITIVE CONTROLS. A suite that only proves refusals is satisfied
--   by a fix that refuses everything — measured elsewhere in this repo at 11/14 green with the
--   feature dead. M2b is the run where they earn their place.
--
-- ⚠ Harness precondition: `00_shim.sql` reproduces production's default privileges
--   (`alter default privileges … grant all on tables to anon, authenticated`). Without that line
--   the client roles would never hold INSERT locally and every negative arm here would be green
--   with 0111 deleted — the exact vacuity that made 0109's first-round pins meaningless.

do $$
declare
  v_att       uuid; v_victim uuid; v_other uuid;
  v_mydog     uuid; v_mydog2 uuid; v_theirdog uuid;
  v_myaddr    uuid; v_theiraddr uuid;
  v_ser_legit uuid; v_ser_d2 uuid; v_ser_forged uuid; v_ser_d1c uuid;
  v_bk_upd    uuid; v_bk_cas uuid; v_bk_pay uuid;
  v_target    timestamptz; v_target2 timestamptz; v_targetf timestamptz; v_targetc timestamptz;
  v_hold_s    timestamptz; v_hold_e timestamptz;
  v_msg text; v_bad text; v_st text; v_n int; v_n2 int; v_id uuid;
  v_acl_snap  text[]; v_fence_broken boolean; v_txt text;
  v_bool boolean; v_int int; v_int2 int;
  v_p1 int; v_p2 int; v_p3 int; v_p4 int; v_p5 int; v_p6 int;
  r record;
begin
  -- ─────────────────────────── fixtures (as postgres, before any role switch) ───────────────
  v_att := gen_random_uuid(); v_victim := gen_random_uuid(); v_other := gen_random_uuid();
  insert into auth.users(id,email) values (v_att,'bep-att@t'),(v_victim,'bep-vic@t'),(v_other,'bep-oth@t');
  insert into profiles(id,role,name) values (v_att,'owner','BEP-att'),(v_victim,'runner','BEP-vic'),(v_other,'owner','BEP-oth');
  insert into runners(profile_id) values (v_victim);
  -- [0119] 이 스위트는 t_dog를 안 쓰고 직접 심는다 — 0119 §D 이후 미신고 강아지는 위탁이
  -- 거절되므로 신고값이 명시적으로 필요하다. 이 스위트가 핀하는 성질은 바뀌지 않는다.
  insert into dogs (owner_id,name) values (v_att,'mine')   returning id into v_mydog;
  insert into dogs (owner_id,name) values (v_att,'mine2')  returning id into v_mydog2;
  insert into dogs (owner_id,name) values (v_other,'theirs') returning id into v_theirdog;
  insert into addresses(owner_id,label,addr) values (v_att,'home','A')   returning id into v_myaddr;
  insert into addresses(owner_id,label,addr) values (v_other,'home','B') returning id into v_theiraddr;

  -- the slot D-7 defends: tomorrow 10:00 KST for 49 minutes (km 3 → 3*8+25). A whole-day
  -- availability rule on that weekday, so the ONLY thing that could make the slot unavailable is
  -- a hold — which is what D-7 measures. Fixed clock time on purpose: `is_slot_available` compares
  -- minutes-from-midnight, so a window that crossed KST midnight would fail for a reason that has
  -- nothing to do with this slice.
  v_hold_s := (((now() at time zone 'Asia/Seoul')::date + 1)::text || ' 10:00')::timestamp at time zone 'Asia/Seoul';
  v_hold_e := v_hold_s + interval '49 minutes';
  insert into runner_availability_rules(runner_id, weekday, start_min, end_min)
  values (v_victim, extract(dow from v_hold_s at time zone 'Asia/Seoul')::int, 0, 1439);

  perform set_config('request.jwt.claim.sub', v_att::text, true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-4] the original CSO #2 exploit: a client INSERT naming a victim as the runner
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_victim,'draft',now() + interval '3 days',3,7900,9000,16900);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 피해자를 러너로 지정한 INSERT가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('bep','D-4 클라 INSERT로 피해자를 러너로 지정 — 42501 (그랜트가 없다; is_booking_party를 여는 행 자체가 안 만들어진다)');
  else v_msg := v_bad; call _fail('bep','D-4 booking insert runner forgery', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-5] the same INSERT with each of the four cross-user pointers, one arm each.
  --       `series_id` is the one 0105's column blacklist missed entirely (reviewer F4) — and a
  --       draft carrying someone else's series_id on the right KST date silently SUPPRESSES their
  --       recurring booking, because the cron's dedup has no owner filter (`0080:757-761`).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  for r in
    select 'dog_id'::text as arm union all select 'address_id' union all
    select 'club_session_id' union all select 'series_id'
  loop
    v_st := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'dog_id' then
          insert into bookings(owner_id,dog_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_theirdog,'draft',now() + interval '3 days',3,7900,9000,16900);
        when 'address_id' then
          insert into bookings(owner_id,dog_id,address_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_mydog,v_theiraddr,'draft',now() + interval '3 days',3,7900,9000,16900);
        when 'club_session_id' then
          insert into bookings(owner_id,dog_id,club_session_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_mydog,gen_random_uuid(),'draft',now() + interval '3 days',3,7900,9000,16900);
        else
          insert into bookings(owner_id,dog_id,series_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_mydog,gen_random_uuid(),'draft',now() + interval '3 days',3,7900,9000,16900);
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('bep','D-5 남의 개·남의 주소·임의 클럽세션·임의 series_id 4종 전부 42501 (컬럼 블랙리스트가 아니라 그랜트라서 미래 컬럼도 자동 포섭)');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('bep','D-5 cross-user pointers', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-6] `runner_id = self` — the vector 0105 §0 named as its own and never pinned (F6).
  --       `_guard_booking_insert_cols` (0083 본문, 이 파일이 건드리지 않는다) does NOT cover
  --       runner_id, so §1's revoke is the only thing refusing this.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
      values (v_att,v_mydog,v_att,'draft',now() + interval '3 days',3,7900,9000,16900);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' runner_id=self INSERT가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  if v_bad = '' then call _pass('bep','D-6 runner_id=self INSERT도 42501 — `dogs runner read via booking`으로 임의 강아지를 여는 경로가 닫힌다');
  else v_msg := v_bad; call _fail('bep','D-6 runner_id self', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-9b] the `anon` GRANTEE. §A.1 measured `anon` holding the identical SIUD set on both tables
  --        and every 0002 policy as `{public}`, so anon is a SEPARATE grantee that every revoke
  --        must NAME — writing `… from authenticated` alone would leave the grant in place.
  --        ⚠⚠ **The contract's stated rationale for this pin is FALSIFIED, and saying so is the
  --        point of keeping the pin.** The contract claimed an authenticated-only revoke "leaves
  --        the whole exploit reachable with no login at all", and predicted that dropping `anon`
  --        from the revoke list would redden D-9b while D-4/D-5/D-6 stayed green. **Measured: it
  --        does not.** Under M1c — the FULL pre-0111 world for `bookings`, grant and policy both
  --        restored — D-4/D-5/D-6 redden and **D-9b stays green**, because `bookings owner
  --        insert`'s `with check (owner_id = auth.uid() …)` and `series owner all`'s
  --        `using (owner_id = auth.uid())` both evaluate `auth.uid()` to NULL for `anon`. Anon
  --        could never land the row; only a logged-in user could.
  --        So what this pin actually is: the anon arm of the revoke is **defence in depth** — it
  --        removes the grant so that a future policy which forgets the uid term (0088 and 0093
  --        were both exactly that mistake) cannot be exploited with no login — and D-9b pins the
  --        resulting STATE. It is NOT mutation-distinguishable from the authenticated arm, and it
  --        must not be advertised as if it were. D-20's catalog arm is what actually watches the
  --        anon grant.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  for r in
    select 'bookings/runner'::text as arm union all select 'bookings/dog' union all
    select 'bookings/self' union all select 'recurring_series'
  loop
    v_st := null;
    begin
      set local role anon;
      if current_user <> 'anon' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      perform set_config('request.jwt.claim.sub', '', true);
      case r.arm
        when 'bookings/runner' then
          insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_mydog,v_victim,'draft',now() + interval '3 days',3,7900,9000,16900);
        when 'bookings/dog' then
          insert into bookings(owner_id,dog_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_theirdog,'draft',now() + interval '3 days',3,7900,9000,16900);
        when 'bookings/self' then
          insert into bookings(owner_id,dog_id,runner_id,status,scheduled_at,km,base_fare,distance_fare,total_price)
            values (v_att,v_mydog,v_att,'draft',now() + interval '3 days',3,7900,9000,16900);
        else
          insert into recurring_series(owner_id,dog_id,rule,km,base_fare,distance_fare,addon_fare,total_price,min_fare)
            values (v_att,v_theirdog,'{"weekdays":[1],"time":"10:00","tz":"Asia/Seoul"}'::jsonb,3,0,0,0,0,500000);
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', v_att::text, true);
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  if v_bad = '' then call _pass('bep','D-9b anon(로그인 없음)으로도 bookings 3종·recurring_series 전부 42501 — anon은 별도 grantee이고 revoke가 이름을 불러야 한다 (⚠ 상태 핀이다: M1c 실측상 0111 이전에도 anon은 auth.uid()=NULL 때문에 정책에서 막혔다 — 이 arm은 심층 방어이지 뮤테이션으로 구별되는 벡터가 아니다)');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('bep','D-9b anon grantee', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-1] reviewer F1 VERBATIM: the client-writable mirror + the definer cron.
  --       INSERT a series naming the VICTIM's dog with zero fares and a ₩500,000 payout floor,
  --       then run the hourly sweep. Both halves are asserted — the refusal AND that the cron
  --       minted nothing, because the whole point of F1 is that the second half is what hurts.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into recurring_series(owner_id,dog_id,rule,km,base_fare,distance_fare,addon_fare,total_price,min_fare)
      values (v_att,v_theirdog,'{"weekdays":[1],"time":"10:00","tz":"Asia/Seoul"}'::jsonb,3,0,0,0,0,500000);
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 시리즈 INSERT가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  perform generate_recurring_bookings();
  -- `series_id is not null` on purpose: this arm's subject is what the CRON minted, and a bare
  -- `owner=attacker and dog=victim` count would also catch a row some OTHER arm's INSERT left
  -- behind in a broken world — attributing a direct-INSERT hole to the cron. D-3 owns the broad
  -- "no forged row anywhere" sweep.
  select count(*) into v_n from bookings b
   where b.owner_id = v_att and b.dog_id = v_theirdog and b.series_id is not null;
  if v_n <> 0 then v_bad := v_bad || ' 크론이 위조 시리즈에서 ' || v_n || '건을 발행했다'; end if;
  if v_bad = '' then call _pass('bep','D-1 F1 재현 — 피해자 개 + 요금 0 + min_fare 500,000 시리즈 INSERT가 42501, 크론 발행 0건 (돈-민트 경로 폐쇄)');
  else v_msg := v_bad; call _fail('bep','D-1 series insert money mint', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-7] §0④ — the sibling defect on the same 0002 line. A client hold naming any runner is
  --       counted by `is_slot_available`: a calendar DoS against any runner, no booking required.
  --       Both halves again — the refusal, and that the victim's slot is STILL AVAILABLE.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    insert into slot_holds(runner_id, owner_id, starts_at, ends_at, expires_at)
      values (v_victim, v_att, v_hold_s, v_hold_e, now() + interval '1 hour');
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 홀드 INSERT가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  select is_slot_available(v_victim, v_hold_s, v_hold_e) into v_bool;
  if v_bool is not true then v_bad := v_bad || ' 피해자 슬롯이 여전히 막혀 있다 (is_slot_available=' || coalesce(v_bool::text,'NULL') || ')'; end if;
  if v_bad = '' then call _pass('bep','D-7 클라가 남의 러너 이름으로 슬롯 홀드를 잡을 수 없다 — 42501, 피해자 슬롯은 그대로 가용 (예약 없이도 가능하던 캘린더 DoS)');
  else v_msg := v_bad; call _fail('bep','D-7 slot_holds sibling', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-11] POSITIVE CONTROL — the `create-booking-hold` shape as `service_role`.
  --        This is the failure mode that turns a security fix into an OUTAGE: the money path
  --        writes both `bookings` and `slot_holds` as service_role, and if the revoke caught it
  --        every booking in production dies. `runner_id` is null in BOTH rows — that is C.4's
  --        new shape, asserted here on the SQL side as well as in the Deno pin.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  begin
    set local role service_role;
    insert into bookings(owner_id,dog_id,runner_id,address_id,status,scheduled_at,km,
                         base_fare,distance_fare,addon_fare,total_price,min_fare)
      values (v_att,v_mydog,null,v_myaddr,'draft',now() + interval '10 days',3,7900,9000,0,16900,9900)
      returning id into v_bk_pay;
    update bookings set status = 'quoted'       where id = v_bk_pay;
    update bookings set status = 'payment_hold' where id = v_bk_pay;
    insert into slot_holds(runner_id, owner_id, starts_at, ends_at, expires_at, booking_id)
      values (null, v_att, now() + interval '10 days', now() + interval '10 days 49 minutes',
              now() + interval '5 minutes', v_bk_pay);
  exception when others then v_bad := ' 서버 경로가 막혔다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then
    select count(*) into v_n from bookings b where b.id = v_bk_pay and b.status = 'payment_hold' and b.runner_id is null and b.total_price = 16900;
    select count(*) into v_n2 from slot_holds h where h.booking_id = v_bk_pay and h.runner_id is null;
    if v_n <> 1 then v_bad := ' 부킹 행이 기대한 모습이 아니다 (payment_hold·runner_id null·서버 산정가)'; end if;
    if v_n2 <> 1 then v_bad := v_bad || ' 홀드 행이 runner_id null로 만들어지지 않았다'; end if;
  end if;
  if v_bad = '' then call _pass('bep','D-11 양성 대조 — service_role의 create-booking-hold 경로는 그대로 (bookings + slot_holds 둘 다, runner_id는 양쪽 다 null = C.4의 새 형상)');
  else v_msg := v_bad; call _fail('bep','D-11 service_role hold path', v_msg); end if;

  -- ─────────────── series fixtures for D-2 / D-8 / D-9c / D-12 / D-14 ───────────────
  -- Both series are created through the SANCTIONED path (`create_recurring_series`, definer,
  -- party-gated) called as `authenticated` — the point of D-2 is that even a wholly legitimate
  -- series was a money-mint through its UPDATE arm, so the fixture must be legitimate.
  -- The rule is derived from the seed booking's KST weekday+time, so the seed sits exactly 7 days
  -- BEFORE the intended generation slot: same weekday and clock time (KST has no DST), different
  -- KST date, so the cron's dedup does not suppress the very row D-12 is waiting for.
  v_target  := now() + interval '24 hours';   -- v_ser_legit generates here (2h < 24h < 72h)
  v_target2 := now() + interval '26 hours';   -- v_ser_d2 generates here — 2h clear of v_target,
                                              -- so the same dog's 49-minute windows never overlap
  insert into bookings(owner_id,dog_id,address_id,status,scheduled_at,km,pace_label,addons,
                       base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att,v_mydog,v_myaddr,'draft',v_target - interval '7 days',3,'easy','[]'::jsonb,
            7900,9000,0,16900,9900) returning id into v_id;
  set local role authenticated;
  select create_recurring_series(v_id) into v_ser_legit;
  reset role;
  insert into bookings(owner_id,dog_id,address_id,status,scheduled_at,km,pace_label,addons,
                       base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att,v_mydog,v_myaddr,'draft',v_target2 - interval '7 days',3,'easy','[]'::jsonb,
            7900,9000,0,16900,9900) returning id into v_id;
  set local role authenticated;
  select create_recurring_series(v_id) into v_ser_d2;
  reset role;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-2] §0③ — THE ONE NOTHING ELSE SAW. The owner of a LEGITIMATE series repoints it at a
  --       victim's dog with a ₩500,000 payout floor, and the cron mints F1's row from it.
  --       `recurring_series` has no trigger, so before 0111 the only gate was a `for all using`
  --       policy that permits exactly this. Revoking INSERT alone does not close it.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    update recurring_series set dog_id = v_theirdog, min_fare = 500000, total_price = 0
     where id = v_ser_d2;
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 정당한 시리즈를 피해자 개로 갈아끼우는 UPDATE가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  select count(*) into v_n from recurring_series s
   where s.id = v_ser_d2 and (s.dog_id = v_theirdog or s.min_fare = 500000);
  if v_n <> 0 then v_bad := v_bad || ' 시리즈 행이 실제로 바뀌었다'; end if;
  perform generate_recurring_bookings();
  select count(*) into v_n from bookings b where b.series_id = v_ser_d2 and b.dog_id = v_theirdog;
  if v_n <> 0 then v_bad := v_bad || ' 크론이 위조 예약 ' || v_n || '건을 발행했다'; end if;
  if v_bad = '' then call _pass('bep','D-2 §0③ 정당한 시리즈의 UPDATE 경로 — dog_id·min_fare 갈아끼우기 42501, 행 불변, 크론 위조 발행 0건 (컬럼 그랜트가 이 슬라이스의 하중 부재)');
  else v_msg := v_bad; call _fail('bep','D-2 series update money mint', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-9c] the shape an attacker actually sends: ONE statement touching a GRANTED column and a
  --        REVOKED one. This is what tells you whether `grant update (paused)` is a column filter
  --        or a statement gate — Postgres checks privileges per REFERENCED column, so a permitted
  --        column must not launder the forbidden one. The row is re-read afterwards, not just the
  --        sqlstate: a partial application would be the worst possible outcome.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  select min_fare into v_int from recurring_series where id = v_ser_d2;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    update recurring_series set paused = true, min_fare = 500000 where id = v_ser_d2;
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  if v_st <> '42501' then v_bad := ' 혼합 컬럼 UPDATE가 42501이 아니었다 [' || coalesce(v_st,'NULL') || ']'; end if;
  select min_fare into v_int2 from recurring_series where id = v_ser_d2;
  if v_int2 is distinct from v_int then v_bad := v_bad || ' min_fare가 바뀌었다 (' || coalesce(v_int::text,'NULL') || '→' || coalesce(v_int2::text,'NULL') || ')'; end if;
  if v_bad = '' then call _pass('bep','D-9c `set paused=true, min_fare=500000` 한 문장 — 문장 전체가 42501이고 min_fare 불변 (허용 컬럼이 금지 컬럼을 세탁하지 못한다)');
  else v_msg := v_bad; call _fail('bep','D-9c mixed-column update', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-8] the other two verbs on one's OWN series: hand it to someone else, or delete it.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  for r in select 'update owner_id'::text as arm union all select 'delete' loop
    v_st := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      if r.arm = 'delete' then
        delete from recurring_series where id = v_ser_d2;
      else
        update recurring_series set owner_id = v_other where id = v_ser_d2;
      end if;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL'); end if;
  end loop;
  select count(*) into v_n from recurring_series where id = v_ser_d2 and owner_id = v_att;
  if v_n <> 1 then v_bad := v_bad || ' 시리즈 행이 사라졌거나 소유자가 바뀌었다'; end if;
  if v_bad = '' then call _pass('bep','D-8 자기 시리즈의 owner_id 이전·삭제 둘 다 42501, 행은 그대로');
  else v_msg := '42501이 아닌 결과:' || v_bad; call _fail('bep','D-8 series update/delete', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-12] POSITIVE CONTROL — the cron still generates for a LEGITIMATE series: the owner's own
  --        dog, own address, the snapshot fares (which are a real consented quote and are NOT
  --        re-derived), the notification, and the KST-day dedup on a second sweep in the same day.
  --        Without this, §2's revokes and §3's belt are satisfied by a cron that generates nothing.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*) into v_n from bookings b
   where b.series_id = v_ser_legit
     and (b.scheduled_at at time zone 'Asia/Seoul')::date = (v_target at time zone 'Asia/Seoul')::date
     and b.owner_id = v_att and b.dog_id = v_mydog and b.address_id = v_myaddr
     and b.runner_id is null and b.status = 'matching'
     and b.base_fare = 7900 and b.distance_fare = 9000 and b.addon_fare = 0
     and b.total_price = 16900 and b.min_fare = 9900;
  if v_n < 1 then v_bad := ' 정당한 시리즈에서 크론이 스냅샷 그대로의 예약을 발행하지 않았다 (' || v_n || '건)'; end if;
  select count(*) into v_n2 from notifications nt
   join bookings b on b.id = nt.ref_id
   where b.series_id = v_ser_legit and nt.profile_id = v_att and nt.kind = 'booking';
  if v_n2 < 1 then v_bad := v_bad || ' 보호자 알림이 기록되지 않았다'; end if;
  select count(*) into v_n from bookings where series_id = v_ser_legit;
  perform generate_recurring_bookings();
  select count(*) into v_n2 from bookings where series_id = v_ser_legit;
  if v_n2 <> v_n then v_bad := v_bad || ' 같은 KST 날짜 재실행이 중복 발행됐다 (' || v_n || '→' || v_n2 || ')'; end if;
  if v_bad = '' then call _pass('bep','D-12 양성 대조 — 정당한 시리즈는 그대로 발행된다: 본인 개·본인 주소·스냅샷 요금 동일·runner_id null·matching·알림 기록·같은 KST 날짜 재실행은 중복 없음');
  else v_msg := v_bad; call _fail('bep','D-12 legitimate cron generation', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-3] F1's assertions on the minted row, asked of the whole table rather than of one row:
  --       nowhere in `bookings` is there a row owned by the attacker carrying the victim's dog,
  --       and no row anywhere satisfies the `marketplace_open_requests` PREDICATE for that dog.
  --       ⚠ The view itself is gated by `is_active_runner()`, which is false for `postgres` and
  --         would return 0 rows in ANY world — querying it here would be a vacuous pin. So the
  --         predicate is asserted directly against the base table (`0056:64-67`), which is the
  --         part that is actually about this slice.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*) into v_n from bookings b where b.owner_id = v_att and b.dog_id = v_theirdog;
  if v_n <> 0 then v_bad := ' 공격자 소유 + 피해자 개인 예약이 ' || v_n || '건 존재한다'; end if;
  select count(*) into v_n2 from bookings b
   where b.dog_id = v_theirdog and b.status = 'matching' and b.runner_id is null
     and b.club_session_id is null and b.owner_id <> v_other;
  if v_n2 <> 0 then v_bad := v_bad || ' 피해자 개가 마켓플레이스 술어를 만족하는 행이 ' || v_n2 || '건 있다 (전 러너에게 신상 공개)'; end if;
  select count(*) into v_n from bookings b where b.owner_id = v_att and b.total_price <= 0;
  if v_n <> 0 then v_bad := v_bad || ' 요금 0원 예약이 ' || v_n || '건 존재한다'; end if;
  if v_bad = '' then call _pass('bep','D-3 위조의 흔적 없음 — 공격자×피해자 개 예약 0건, 피해자 개가 마켓플레이스 술어를 만족하는 행 0건, 요금 0원 예약 0건');
  else v_msg := v_bad; call _fail('bep','D-3 no forged row anywhere', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-1b] §3's SECOND BELT, on its own. A forged series is PLANTED as `postgres` — i.e. exactly
  --        what a future re-grant, a support script or a new definer would produce, which is the
  --        only threat model §3 legitimately has (the stale-dog premise is unreachable: the FK is
  --        NO ACTION, `dogs owner all` reuses USING as its update check, and no dog-transfer RPC
  --        exists). The series is otherwise perfectly generatable — not paused, dog set, rule
  --        valid, inside the 72h window, no dedup, no clash, owner debt-free — so the ownership
  --        re-check is the ONLY thing that can stop it.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v_targetf := now() + interval '20 hours';
  insert into recurring_series(owner_id,dog_id,address_id,rule,km,pace_label,addons,
                               base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att, v_theirdog, v_myaddr,
            jsonb_build_object(
              'weekdays', jsonb_build_array(extract(dow from v_targetf at time zone 'Asia/Seoul')::int),
              'time', to_char(v_targetf at time zone 'Asia/Seoul','HH24:MI'),
              'tz','Asia/Seoul'),
            3,'easy','[]'::jsonb, 0,0,0,0,500000)
    returning id into v_ser_forged;
  perform generate_recurring_bookings();
  select count(*) into v_n from bookings where series_id = v_ser_forged;
  if v_n <> 0 then v_bad := ' 위조 시리즈에서 크론이 ' || v_n || '건을 발행했다 (벨트가 발화하지 않았다)'; end if;
  -- and the belt must stay OBSERVABLE: a silent `continue` makes a skipped series
  -- indistinguishable from a series with nothing due, which is the only signal ops ever gets.
  if not exists (select 1 from pg_proc p where p.proname = 'generate_recurring_bookings'
                   and p.prosrc like '%raise warning%skipped%') then
    v_bad := v_bad || ' 정본에 raise warning …skipped 가 없다 (조용한 continue = 벨트가 발화해도 아무도 모른다)';
  end if;
  if v_bad = '' then call _pass('bep','D-1b §3 두 번째 벨트 — 재그랜트를 가정해 심은 위조 시리즈에서 크론 발행 0건, 그리고 skip은 raise warning으로 보인다 (raise가 아니라 continue: 한 행이 전 보호자의 스윕을 영구 중단시킨다)');
  else v_msg := v_bad; call _fail('bep','D-1b C.3 belt', v_msg); end if;
  update recurring_series set paused = true where id = v_ser_forged;   -- 이후 스윕 소음 제거

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-1c] **BOUNDARY-DOCUMENTING PIN — this one is green when the ATTACK SUCCEEDS.**
  --        D-1b proves §3's belt refuses a series pointed at someone ELSE's dog. It is very easy
  --        to read that as "the belt covers the re-grant case", and round 1's own mutation note
  --        very nearly said so. It does not. **The belt re-validates OWNERSHIP ONLY and is
  --        FARE-BLIND** — deliberately, because the fares are a consented snapshot and re-deriving
  --        them changes what a recurring owner is charged (0111 §3; money canon → Sean). So the
  --        MONEY half of §0② walks straight past it.
  --        This pin breaks §2's fence on purpose INSIDE its own arm (`grant update on
  --        recurring_series to authenticated` — the re-grant the belt is supposedly the answer
  --        to), keeps the attacker's OWN dog so the belt has nothing to object to, moves only
  --        `total_price → 0` and `min_fare → 500000`, and asserts the cron **MINTS** the booking
  --        at a ₩500,000 runner payout floor. The fence is restored and every row this pin created
  --        is deleted before the next pin runs, so nothing downstream sees it.
  --        ⚠ Green = the mint happened. That is not a regression and must not be "fixed": it is
  --          the recorded LIMIT of §3, so that nobody later cites D-1b as fare coverage, and
  --          nobody deletes §2's `revoke update` believing the belt is behind it. `grant update
  --          (paused)` + §2's revoke are the ONLY things between a client and the fare columns.
  --        ⚠ The dog is `v_mydog2`, which has no live booking yet at this point in the file
  --          (D-15/D-17 create theirs later), and the slot is +18h — clear of v_ser_legit (+24h)
  --          and v_ser_d2 (+26h) — so the cron's clash guard cannot be the reason for a mint of 0.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := ''; v_st := null;
  v_targetc := now() + interval '18 hours';
  insert into recurring_series(owner_id,dog_id,address_id,rule,km,pace_label,addons,
                               base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att, v_mydog2, v_myaddr,
            jsonb_build_object(
              'weekdays', jsonb_build_array(extract(dow from v_targetc at time zone 'Asia/Seoul')::int),
              'time', to_char(v_targetc at time zone 'Asia/Seoul','HH24:MI'),
              'tz','Asia/Seoul'),
            3,'easy','[]'::jsonb, 7900,9000,0,16900,9900)
    returning id into v_ser_d1c;
  -- ⚠ Snapshot the EXACT prior write surface first, because the restore must reproduce what was
  --   FOUND and not what 0111 is supposed to leave. Measured: `revoke update on <table> from
  --   <role>` clears that role's COLUMN-level UPDATE aclitems as well as the table-level one. So a
  --   hardcoded `grant update (paused)` restore would silently REPAIR mutation M6 (which adds
  --   `grant update (min_fare)`) before D-21 — which runs later in this same file — ever looks,
  --   and M6 would show D-21 green on a broken migration. A pin must never launder the state it
  --   borrowed. If the table-level grant is ALREADY present when this pin starts (the M3u world,
  --   where §2's `revoke update` is gone and the shim's default privileges still hold it), the
  --   revoke is skipped entirely and the state is handed on exactly as found.
  select coalesce(array_agg(pg_get_userbyid(x.grantee) || '|' || a.attname order by a.attname), '{}')
    into v_acl_snap
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace ns on ns.oid = c.relnamespace,
         lateral aclexplode(a.attacl) x
   where ns.nspname = 'public' and c.relname = 'recurring_series'
     and x.privilege_type = 'UPDATE'
     and pg_get_userbyid(x.grantee) in ('anon','authenticated');
  select exists (
    select 1 from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace,
         lateral aclexplode(c.relacl) x
     where ns.nspname = 'public' and c.relname = 'recurring_series'
       and x.privilege_type = 'UPDATE'
       and pg_get_userbyid(x.grantee) = 'authenticated'
  ) into v_fence_broken;
  -- the fence, deliberately broken — this is the future re-grant §3 is advertised as surviving
  grant update on recurring_series to authenticated;
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    update recurring_series set total_price = 0, min_fare = 500000 where id = v_ser_d1c;
    v_st := 'SUCCEEDED';
  exception when others then v_st := sqlstate;
  end;
  reset role;
  -- …and restored IMMEDIATELY, before anything else can observe it, to the snapshot taken above.
  -- D-21 (later in this file) is the independent check that the restore was exact.
  if not v_fence_broken then
    revoke update on recurring_series from authenticated;
    foreach v_txt in array v_acl_snap loop
      execute format('grant update (%I) on recurring_series to %I',
                     split_part(v_txt, '|', 2), split_part(v_txt, '|', 1));
    end loop;
  end if;
  if v_st <> 'SUCCEEDED' then
    v_bad := ' 펜스를 깬 상태에서도 요금 UPDATE가 통과하지 않았다 [' || coalesce(v_st,'NULL')
          || '] — 이 핀의 전제(§2 revoke가 유일한 방어)가 성립하지 않는다';
  end if;
  perform generate_recurring_bookings();
  select count(*) into v_n from bookings b
   where b.series_id = v_ser_d1c and b.min_fare = 500000 and b.total_price = 0;
  if v_n <> 1 then
    v_bad := v_bad || ' 크론이 min_fare 500,000짜리 예약을 ' || v_n || '건 발행했다 (기대 1건)'
          || ' — 벨트가 요금까지 본다면 이 핀의 설명과 0111 §3 헤더를 함께 고쳐야 한다';
  end if;
  if v_bad = '' then call _pass('bep','D-1c 경계 핀 (성공이 초록이다) — 펜스를 깬 재그랜트 아래, 본인 개를 그대로 두고 돈만 옮기면 §3 벨트는 침묵하고 크론이 min_fare 500,000으로 1건을 발행한다: 벨트는 소유권만 재검증하고 요금은 보지 않는다 (D-1b를 요금 커버리지로 읽지 말 것 — 요금 컬럼을 쥐고 있는 것은 §2의 revoke와 grant update (paused)뿐이다)');
  else v_msg := v_bad; call _fail('bep','D-1c belt is fare-blind', v_msg); end if;
  -- full rollback of this pin's footprint: the minted booking is a ₩0 total_price row and D-3's
  -- sweep (already run) plus any later count would otherwise see it.
  delete from notifications where ref_id in (select id from bookings where series_id = v_ser_d1c);
  delete from bookings where series_id = v_ser_d1c;
  delete from recurring_series where id = v_ser_d1c;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-14] POSITIVE CONTROL — `pauseRecurringSeries` (`app/src/lib/api.ts:395`), the app's ONLY
  --        write to this table, in BOTH shapes: hand-written SQL, and the `json_to_record` form
  --        PostgREST actually emits for a PATCH (which additionally reads the row — the `0091 §E`
  --        lesson, where reasoning about PostgREST's generated statement was wrong).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  begin
    set local role authenticated;
    if current_user <> 'authenticated' then
      raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
    end if;
    update recurring_series set paused = true where id = v_ser_legit;
    get diagnostics v_n = row_count;
    update recurring_series set paused = x.paused
      from (select * from json_to_record('{"paused":false}') as (paused bool)) x
     where recurring_series.id = v_ser_legit;
    get diagnostics v_n2 = row_count;
  exception when others then
    v_bad := ' 정상 일시정지가 거부됐다 [' || sqlstate || ' ' || sqlerrm || ']'; v_n := -1; v_n2 := -1;
  end;
  reset role;
  if v_n <> 1 or v_n2 <> 1 then v_bad := v_bad || ' 갱신 행 수가 1/1이 아니다 (직접 SQL=' || v_n || ', PostgREST 형상=' || v_n2 || ')'; end if;
  select paused into v_bool from recurring_series where id = v_ser_legit;
  if v_bool is not false then v_bad := v_bad || ' 마지막 값이 반영되지 않았다'; end if;
  if v_bad = '' then call _pass('bep','D-14 양성 대조 — pauseRecurringSeries가 직접 SQL·PostgREST(json_to_record) 두 형상 모두 1행 갱신 (테이블 SELECT가 남아 WHERE의 권한이 선다)');
  else v_msg := v_bad; call _fail('bep','D-14 pause both shapes', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-9] reviewer F7 — pin the load-bearing "the UPDATE door is already shut" claim that 0105's
  --       header asserted and its suite never checked. Subject: `_guard_booking_cols`
  --       (`0058:263-278`), NOT anything 0111 changes.
  --       ⚠⚠ Each arm MUST write a value the row does NOT already hold. The guard raises only
  --       `if new is distinct from old`, and a no-op UPDATE passing is a DELIBERATE design (it is
  --       what lets a server path re-write identical values idempotently). So `set runner_id =
  --       <already null>` returns SUCCESS with the guard doing nothing — a false green on the one
  --       true claim in 0105's header. The fixture is built with known-different values and the
  --       DIFFERENCE is asserted first.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  insert into bookings(owner_id,dog_id,runner_id,series_id,status,scheduled_at,km,
                       base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att,v_mydog,null,null,'draft',now() + interval '15 days',3,7900,9000,0,16900,0)
    returning id into v_bk_upd;
  select count(*) into v_n from bookings
   where id = v_bk_upd and runner_id is null and series_id is null and min_fare = 0 and dog_id = v_mydog;
  if v_n <> 1 then v_bad := ' 픽스처가 기대한 출발값이 아니다 — 각 arm이 no-op이 되어 거짓 초록이 된다'; end if;
  for r in
    select 'runner_id'::text as arm union all select 'dog_id' union all
    select 'series_id' union all select 'min_fare'
  loop
    v_st := null;
    begin
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      case r.arm
        when 'runner_id' then update bookings set runner_id  = v_victim    where id = v_bk_upd;
        when 'dog_id'    then update bookings set dog_id     = v_mydog2    where id = v_bk_upd;
        when 'series_id' then update bookings set series_id  = v_ser_legit where id = v_bk_upd;
        else                  update bookings set min_fare   = 500000      where id = v_bk_upd;
      end case;
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate || ':' || coalesce(sqlerrm,'');
    end;
    reset role;
    -- P0001 alone is not enough: the guard's own message must be the reason, or a different
    -- P0001 from some other trigger would read as this one.
    if v_st is null or v_st not like 'P0001:booking_protected_columns%' then
      v_bad := v_bad || ' ' || r.arm || '=' || coalesce(v_st,'NULL');
    end if;
  end loop;
  select count(*) into v_n from bookings
   where id = v_bk_upd and runner_id is null and series_id is null and min_fare = 0 and dog_id = v_mydog;
  if v_n <> 1 then v_bad := v_bad || ' 행이 실제로 바뀌었다'; end if;
  if v_bad = '' then call _pass('bep','D-9 F7 — 기존 부킹의 runner_id·dog_id·series_id·min_fare 재지정 4종이 전부 P0001 booking_protected_columns (각 arm은 현재값과 다른 값을 쓴다: no-op은 설계상 통과하므로 거짓 초록이 된다)');
  else v_msg := 'P0001 booking_protected_columns가 아닌 결과:' || v_bad; call _fail('bep','D-9 booking update deny-all', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-15] POSITIVE CONTROL — the `request_runner` CAS (`transition-booking/index.ts:191-196`),
  --        the SANCTIONED nomination path and the reason C.4 can drop `create-booking-hold`'s
  --        body arm. One statement, CAS on the pre-state, run as `service_role`.
  --        ⚠ This pin proving GREEN is also the honest statement of what this slice does NOT
  --          close: any owner may still point `runner_id` at any real runner here (B-11).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  insert into bookings(owner_id,dog_id,status,scheduled_at,km,base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att,v_mydog2,'matching',now() + interval '5 days',3,7900,9000,0,16900,9900)
    returning id into v_bk_cas;
  begin
    set local role service_role;
    update bookings set runner_id = v_victim, status = 'runner_pending'
     where id = v_bk_cas and status in ('matching','runner_pending');
    get diagnostics v_n = row_count;
  exception when others then v_bad := ' CAS가 거부됐다 [' || sqlstate || ' ' || sqlerrm || ']'; v_n := -1;
  end;
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' CAS 갱신 행 수가 1이 아니다 (' || v_n || ')'; end if;
  select count(*) into v_n2 from bookings where id = v_bk_cas and runner_id = v_victim and status = 'runner_pending';
  if v_n2 <> 1 then v_bad := v_bad || ' 지명 결과가 반영되지 않았다'; end if;
  if v_bad = '' then call _pass('bep','D-15 양성 대조 — request_runner의 한 문장 CAS(service_role)는 그대로 1행: 지명은 이 경로에서만 일어난다 (⚠ B-11: 이 경로 자체는 이 슬라이스가 닫지 않는다)');
  else v_msg := v_bad; call _fail('bep','D-15 request_runner CAS', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-13] REGRESSION, not a re-pin — `create_recurring_series` (B-8) is owned by suite 114 R3
  --        (owner success · idempotence · the `bookings.series_id` stamp). This slice changed the
  --        table it writes into, so 114 must still be green; a second copy of the pin here would
  --        be a second thing to keep true and the first copy is the one that gets updated.
  --        (The fixture block above ALSO exercises it live, twice, as `authenticated`.)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  select count(*) filter (where not ok), count(*) filter (where ok and name like 'R3%')
    into v_n, v_n2 from _t where suite = 'rgd';
  v_bad := '';
  if v_n <> 0 then v_bad := ' 114(rgd) 실패 핀 ' || v_n || '건'; end if;
  if v_n2 < 1 then v_bad := v_bad || ' 114 R3 초록 핀을 찾지 못했다 (스위트가 실행되지 않았거나 이름이 바뀌었다)'; end if;
  if v_bad = '' then call _pass('bep','D-13 회귀 — 114 recurring_guard(R1~R4) 전부 초록, R3(소유자 성공·멱등·series_id 스탬프) 확인: create_recurring_series는 이 슬라이스 뒤에도 유일한 시리즈 생성 경로다');
  else v_msg := v_bad; call _fail('bep','D-13 114 regression', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-16] REGRESSION — the club money path (B-6, `session_pay_delegation`) is a THIRD writer of
  --        `bookings`, running as a definer. Suites 50 and 117 own its `not_owner` gate, its
  --        hard-coded null runner and its derived fare. Green here proves the revokes did not
  --        catch the definer paths.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  select count(*) filter (where not ok), count(*) into v_n, v_n2 from _t where suite in ('del','cmg');
  v_bad := '';
  if v_n <> 0 then v_bad := ' 50/117(del·cmg) 실패 핀 ' || v_n || '건'; end if;
  if v_n2 < 10 then v_bad := v_bad || ' del·cmg 핀 수가 ' || v_n2 || '건뿐이다 (스위트가 돌지 않았다 = 공허한 회귀 확인)'; end if;
  if v_bad = '' then call _pass('bep','D-16 회귀 — 50 delegation + 117 club money 전부 초록 (' || v_n2 || '핀): definer 세 번째 부킹 경로는 revoke의 영향을 받지 않는다');
  else v_msg := v_bad; call _fail('bep','D-16 club definer regression', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-17] the fare path did not move — asserted twice, because a regression check on someone
  --        else's suite is only as good as that suite still running. `compute_runner_payout` is
  --        called directly on a completed booking with known inputs: base 9,900 (the RUNNER's
  --        basis, not the owner's 7,900) + round(2.8 × 3,000) = 8,400 + addon 0, floor 0 → gross
  --        18,300, fee round(18,300 × 0.2) = 3,660.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  insert into bookings(owner_id,dog_id,status,scheduled_at,km,addons,
                       base_fare,distance_fare,addon_fare,total_price,min_fare)
    values (v_att,v_mydog2,'completed',now() - interval '3 days',3,'[]'::jsonb,7900,9000,0,16900,0)
    returning id into v_id;
  begin
    select p.base, p.distance, p.addon, p.guarantee, p.gross, p.fee
      into v_p1, v_p2, v_p3, v_p4, v_p5, v_p6
      from compute_runner_payout(v_id, 'completed', 2.8, 0.2) p;
  exception when others then v_bad := ' 지급액 계산이 실패했다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  if v_bad = '' and (v_p1 <> 9900 or v_p2 <> 8400 or v_p3 <> 0 or v_p4 <> 0 or v_p5 <> 18300 or v_p6 <> 3660) then
    v_bad := ' 지급액이 캡처값과 다르다 (base=' || v_p1 || ' distance=' || v_p2 || ' addon=' || v_p3
          || ' guarantee=' || v_p4 || ' gross=' || v_p5 || ' fee=' || v_p6 || '; 기대 9900/8400/0/0/18300/3660)';
  end if;
  select count(*) filter (where not ok), count(*) into v_n, v_n2 from _t where suite = 'rpay';
  if v_n <> 0 then v_bad := v_bad || ' 137(rpay) 실패 핀 ' || v_n || '건'; end if;
  if v_n2 < 5 then v_bad := v_bad || ' rpay 핀 수가 ' || v_n2 || '건뿐이다 (스위트가 돌지 않았다)'; end if;
  if v_bad = '' then call _pass('bep','D-17 요금 경로 불변 — compute_runner_payout이 완료 부킹에서 9,900+8,400+0 → gross 18,300 / fee 3,660 (러너 base는 보호자의 7,900이 아니다), 그리고 137(rpay) ' || v_n2 || '핀 전부 초록');
  else v_msg := v_bad; call _fail('bep','D-17 fare path unchanged', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-20] CATALOG, POSITIVE — assert the privilege state itself, not only its effects. An
  --        effects pin proves a statement was refused; a catalog pin proves WHY, and is the only
  --        thing that catches a fix that worked for the wrong reason (a missing policy rather
  --        than a missing grant). The `service_role` arm is the half that catches the failure
  --        mode which turns a security fix into an OUTAGE.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*), string_agg(g.table_name || ':' || g.grantee, ', ' order by g.table_name, g.grantee)
    into v_n, v_msg
    from information_schema.role_table_grants g
   where g.table_schema = 'public'
     and g.table_name in ('bookings','recurring_series','slot_holds')
     and g.grantee in ('anon','authenticated')
     and g.privilege_type = 'INSERT';
  if v_n <> 0 then v_bad := ' 클라 역할이 아직 INSERT를 쥐고 있다 (' || v_n || '): ' || coalesce(v_msg,''); end if;
  select count(*) into v_n2
    from information_schema.role_table_grants g
   where g.table_schema = 'public'
     and g.table_name in ('bookings','recurring_series','slot_holds')
     and g.grantee = 'service_role'
     and g.privilege_type = 'INSERT';
  if v_n2 <> 3 then v_bad := v_bad || ' service_role의 INSERT가 3/3이 아니다 (' || v_n2 || ') — 과다 회수'; end if;
  if v_bad = '' then call _pass('bep','D-20 카탈로그 — bookings·recurring_series·slot_holds에서 anon/authenticated의 INSERT 0/6, service_role의 INSERT 3/3 (돈 경로가 같이 잘렸는지를 직접 보는 유일한 핀)');
  else v_msg := v_bad; call _fail('bep','D-20 grant catalog', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-21] CATALOG, NEGATIVE — the COLUMN grants, counted. Not "contains that row": EXACTLY one.
  --        Any future migration that grants a second column to a client role on these tables
  --        reddens here immediately, with the column NAMED, instead of surfacing as a re-opened
  --        §0③ months later. That is what makes `grant update (paused)` a fence and not a hope.
  --        ⚠ `information_schema.column_privileges` is the WRONG instrument and was measured so:
  --          it expands TABLE-level grants across every column, returning **396** rows for these
  --          three tables after 0111 — it cannot distinguish a column grant from the table-wide
  --          SELECT that §2 deliberately keeps. `pg_attribute.attacl` holds column-level grants and
  --          nothing else, so it is what the "exactly one" claim is asked of. The EFFECTIVE
  --          privilege is asserted alongside with `has_column_privilege` (the house instrument,
  --          113 K14 / 124 G1 / 127 / 142), so the pin covers both the catalog and the answer a
  --          statement actually gets.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*), string_agg(c.relname || '.' || a.attname || ':' || pg_get_userbyid(x.grantee) || ':' || x.privilege_type, ', ')
    into v_n, v_msg
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace ns on ns.oid = c.relnamespace,
         lateral aclexplode(a.attacl) x
   where ns.nspname = 'public'
     and c.relname in ('bookings','recurring_series','slot_holds')
     and (x.grantee = 0 or pg_get_userbyid(x.grantee) in ('anon','authenticated'));
  if v_n <> 1 or v_msg is distinct from 'recurring_series.paused:authenticated:UPDATE' then
    v_bad := ' 클라 컬럼 그랜트가 정확히 1개(recurring_series.paused:authenticated:UPDATE)가 아니다 — ' || v_n || '개: ' || coalesce(v_msg,'(없음)');
  end if;
  if not has_column_privilege('authenticated','recurring_series','paused','UPDATE') then
    v_bad := v_bad || ' authenticated가 paused를 갱신할 수 없다 (앱의 유일한 쓰기가 죽었다)';
  end if;
  for r in select unnest(array['min_fare','dog_id','total_price','owner_id']) as col loop
    if has_column_privilege('authenticated','recurring_series',r.col,'UPDATE') then
      v_bad := v_bad || ' authenticated가 ' || r.col || '를 갱신할 수 있다';
    end if;
  end loop;
  if v_bad = '' then call _pass('bep','D-21 카탈로그 — 세 테이블의 클라 컬럼 그랜트는 정확히 1개(recurring_series.paused UPDATE authenticated), min_fare·dog_id·total_price·owner_id는 실효 권한도 없음 (information_schema.column_privileges는 테이블 그랜트를 컬럼으로 펼쳐 396행 — 이 주장에는 못 쓴다)');
  else v_msg := v_bad; call _fail('bep','D-21 column grant fence', v_msg); end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [D-22] CATALOG — the writable-VIEW bypass, pinned because 0111 is NOT what closes it.
  --        A write through a view runs with the VIEW OWNER's privileges, so an INSERTABLE view
  --        over `bookings` would route around §1's revoke completely. The grants for that are
  --        already in place: `marketplace_open_requests` (`0056:43-75`) and `available_runners`
  --        (`0015:14-36`) are both owned by `postgres` and carry INSERT/UPDATE/DELETE to `anon`
  --        AND `authenticated`. What actually stops it is that **both view bodies are JOINs**, so
  --        Postgres refuses to auto-update them (`is_insertable_into = NO`; an executed insert
  --        returns 55000). That is a property of the view DEFINITIONS, not of this slice — which
  --        is exactly why it needs a pin here: a future "simplify the view" that flattens either
  --        one to a single-table projection re-opens the booking entry point with nothing in §1
  --        going red. Named in 0111 §0c's residual list.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  for r in select unnest(array['marketplace_open_requests','available_runners']) as vw loop
    select v.is_insertable_into::text into v_st from information_schema.views v
     where v.table_schema = 'public' and v.table_name = r.vw;
    if v_st is null then
      v_bad := v_bad || ' ' || r.vw || ' 뷰를 찾을 수 없다';
    elsif v_st <> 'NO' then
      v_bad := v_bad || ' ' || r.vw || ' 가 자동 갱신 가능해졌다 (is_insertable_into=' || v_st
            || ') — 뷰 소유자(postgres) 권한으로 bookings에 INSERT가 뚫린다';
    end if;
  end loop;
  if v_bad = '' then call _pass('bep','D-22 카탈로그 — marketplace_open_requests·available_runners 둘 다 is_insertable_into=NO (둘 다 postgres 소유 + anon/authenticated에 I/U/D를 쥐고 있다: 조인이라서 막힌 것이지 0111이 막은 것이 아니다 — 뷰를 단일 테이블로 "단순화"하면 §1의 revoke를 우회한다)');
  else v_msg := v_bad; call _fail('bep','D-22 writable view bypass', v_msg); end if;

exception when others then
  reset role;
  v_msg := sqlstate || ' ' || sqlerrm;
  call _fail('bep', 'suite 146 aborted', v_msg);
end $$;
