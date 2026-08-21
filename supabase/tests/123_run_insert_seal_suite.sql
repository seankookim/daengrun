-- ═══ 123 runs INSERT seal — 0087 pins (S1-S9) ═══
-- What this suite pins: that a `runs` row is a SERVER fact from birth. `_guard_run_cols` has been
--   `before update` only since 0057:465, and `runs runner write` (0002:107) asked only WHO was
--   inserting, never WHAT — so an authenticated assigned runner could create the run row for
--   their own booking with every column pre-filled. Three separate money outcomes followed, and
--   S1/S2/S3 are those three, measured end to end rather than described.
-- Sibling of 101 (`runners` INSERT seal, 0061) — the same oversight on a different table, and the
--   same suite shape: `_pass('risl',…)`/`_fail('risl',…)`, one begin…exception per case,
--   `set local role authenticated` for real RLS paths and always `reset role`.
-- ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
-- ⚠ Money is read through `mint_settle_charge_intent` / the payments row, never recomputed here
--   (105's law). NO PIN ASSERTS A G1 AMOUNT — S3 counts payments ROWS, so whichever way the
--   fault-based basis lands, not one pin here moves.
-- ⚠ Global side effects, deliberately (this suite runs last, after 119/120): S1 sets
--   `ops_flags.return_seal_since` and S3 sets `ops_flags.payments_live_since`; each is restored
--   to the shipped NULL by its own last act AND by its exception handler, and S9 re-asserts both
--   restorations at the end so a mid-suite raise cannot leave a cutover switch on for the next
--   reader. (119 R14 does the same for its own flags; this suite runs after it, so it must not
--   hand back a dirtier ops_flags than it found.)
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   S1  ← §2: change start_run_tx's on-conflict from `started_at = excluded.started_at` back to
--         `coalesce(runs.started_at, excluded.started_at)` — a planted `'2000-01-01'` then
--         survives a legitimate start, stays `< return_seal_since` forever, and the run settles
--         with NO return seal (0087 §0 ①, the residual path §4(a) names)                → RED
--   S2  ← §1: re-create the `"runs runner write"` insert policy (restores 0002:107 verbatim) —
--         an authenticated assigned runner inserts a fully client-controlled runs row  → RED
--   S3  ← §1: the same revert — the plant lands on a booking that was never started, and
--         `sweep_settled_without_payments` (0080 §G) mints a real charge intent against the
--         owner's card from `end_reason`/`actual_km` the beneficiary typed (0087 §0 ③) → RED
--   S4  ← §1 or §3: either belt removed lets `runs.settled_at` — the anchor 0083 §0f's sweep fix
--         is about to be built on, and the property 119 R11 pins — take a client value  → RED
--   S5  ← §3: drop the `_guard_run_insert` trigger. S5 is the DEFENCE-IN-DEPTH pin and the only
--         one that survives §1: it re-creates a permissive insert policy inside the case,
--         proves the trigger still refuses, and drops it again. Without that probe the second
--         belt would be untestable, i.e. unpinned, i.e. free to rot                     → RED
--         · its positive-control arm (an insert carrying ONLY `booking_id` must SUCCEED) goes
--           RED if the guard is widened into a deny-all — a guard that refuses everything is
--           not a stricter guard, it is one that cannot tell an attack from a caller
--   S6  ← §2: delete start_run_tx's `picked_up` state gate, or its atomic
--         `where status = 'picked_up'` claim, or make a second start raise instead of returning
--         {unchanged:true} (the runner's screen re-fires on every re-entry — run.tsx:623), or
--         let the idempotent branch overwrite a real `started_at`                        → RED
--   S7  ← §1/§3 over-reach: the live append surface (saveTrace's direct UPDATE, append_run_event,
--         append_run_photo) must be untouched. POSITIVE CONTROL — it goes red if the seal is
--         built by dropping `"runs runner update"` or by widening the guard to UPDATE  → RED
--   S8  ← §3: make `_guard_run_insert_cols` SECURITY DEFINER (0083's recorded trap — `current_user`
--         inside a definer is always `postgres`, so the guard would judge nobody and pass
--         everybody), or widen it so `settle_run_tx`'s no-runs-row upsert backstop (0028 ③)
--         can no longer create a row carrying measurements                              → RED
--   S9  ← §1: any INSERT policy on `runs`, or a grant of start_run_tx to authenticated/anon → RED
--   ⚠ S9's INSERT arm was `cmd = 'INSERT'` until 2026-08-14 and a `FOR ALL` policy reports
--      `cmd = 'ALL'`, so the shape S9 exists to catch slipped past it. Mutation-verified both
--      directions with `create policy "convenience all" on runs for all to authenticated`:
--        · fixed arm  (`cmd in ('INSERT','ALL')`) → 553/3, red = [M7, S2, S9]
--        · old arm    (`cmd = 'INSERT'`)          → 554/2, red = [M7, S2] — **S9 GREEN**
--      HONEST SCOPE, because the tempting claim is bigger than the fact: the hole was NOT silent.
--      **S2 already caught it behaviourally** — it plants a forged row and the row appears — so
--      the harness went red either way. What the literal match defeated was S9's OWN stated
--      purpose one line above: "assert the SHAPE, so that the next person who adds a convenience
--      policy trips a pin instead of reopening §0." The fix restores that, and buys a failure
--      message naming the policy rather than only reporting that a row got created.
--
--   ─── what is NOT pinned here, said out loud ───
--   · The two-connection race on `start_run_tx`'s claim (two starts landing at once must produce
--     ONE runs row). One connection cannot race itself; S6 pins the SEQUENTIAL idempotence, and
--     the genuine concurrent claim belongs in `90_race_check.sh` beside RD/RE. Named as the gap
--     it is rather than pretended away (110's S1 lesson, 119's own closing note).
--   · The TypeScript half — that `start_run` calls the RPC, sends no clock, and no longer
--     swallows the error — is pinned by `supabase/functions/_test/start_run_test.ts`, not here.
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13. Method: the revert was applied to a COPY
--     of the migration at a short, SESSION-NAMED path (`/tmp/dr-riseal` — the harness cannot run
--     from a worktree, macOS's 103-byte Unix socket limit; and a path derived from the MIGRATION
--     number is how two sessions deleted each other's postmaster mid-run on 2026-08-13), the md5
--     of the mutated file was recorded, `rm -rf .pgtest` gave a clean cluster, the WHOLE harness
--     ran, and the tree was then restored from the pristine source and re-verified by md5 + a
--     green run. Green with this suite is **487/0** (baseline on this branch, this suite absent:
--     478/0). Pristine `0087` md5 `110561f19b0d154311c2a91ca8e6ed2b`.
--       M1 §2's on-conflict `started_at = excluded.started_at` reverted to
--          `coalesce(runs.started_at, excluded.started_at)` (md5 `3e9897028b8c59bfb6dc883bfd362257`)
--          → 486/1, red = [S1] alone, detail `시작 시각이 여전히 클라 값이다=2000-01-01 00:00:00+09
--          씰 없이 정산이 통과했다 (컷오버 무력화) 거부됐는데 상태가 움직였다=completed 거부됐는데
--          원장이 생겼다=1` — exploit ① end to end, from the planted birthday through the
--          grandfathering to a booking that reached `completed` with a ledger row and no seal.
--       M2 `"runs runner write"` re-created verbatim, §3's belt LEFT IN PLACE
--          (md5 `aebc6efa08b495b72dba2d4657be1805`) → 485/2, red = [S2, S9].
--          ⚠ THE INTERESTING RESULT: S3 and S4 stayed GREEN. With the policy back, the trigger
--          alone still refused every money column — so the defence in depth is not decorative,
--          it is measurably the thing standing between a restored policy and a real charge.
--          This is why M3 exists: one belt off is not the pre-0087 world.
--       M3 the TRUE pre-0087 state — policy re-created AND `_guard_run_insert` dropped
--          (md5 `859e5438ab4b2853b357958088de6314`) → 482/5, red = [S2, S3, S4, S5, S9].
--          S3's detail: `유령 러닝 심기 통과 하지도 않은 러닝에 청구가 생겼다=1행 유령 run 행이
--          남았다=1` — exploit ③ complete: a booking that was never started, a planted row, and a
--          server-minted charge intent against the owner's card. S4: `INSERT로 settled_at 심기
--          통과` — exploit ②, the settlement anchor taking a client value.
--          (S1 stayed GREEN under M3, correctly: its plant is corrected by §2's overwrite, which
--          M3 does not touch. Clean attribution — S1 answers to M1 and to nothing else.)
--       M4 `_guard_run_insert` dropped alone, §1's policy drop standing
--          (md5 `2a7355f218119d8ed7a455e910c1306b`) → 485/2, red = [S5, S9] and nothing else —
--          which is the proof that S5 is independently load-bearing rather than riding on S2.
--     S6, S7, S8 are positive controls and have no revert: reverting 0087 leaves S7/S8 GREEN by
--       design (the seal must never break the runner's live appends or the server's own writers),
--       and S6's arms are named above with the single change that would redden each.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A marketplace booking parked at `picked_up` — the exact state the plant was made in: the runner
-- is assigned, the handoff is done, the run has not started, and no `runs` row exists yet.
-- ⚠ the status is a CONSTRUCTOR argument, never something a case patches afterwards:
-- `enforce_booking_transition` (0066 §1) has no `picked_up → confirmed` edge, so building a
-- pre-handoff fixture by downgrading a picked_up one raises. Born in the state it needs to be in.
create or replace function t_risl_picked(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                         p_status booking_status default 'picked_up')
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, p_status, now() - interval '10 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  return v;
end $$;

-- "did this insert get in?" — the attempt runs as `authenticated` with the runner's JWT, and the
-- answer is a row count rather than an error string, because the two belts fail with DIFFERENT
-- messages (RLS: `new row violates row-level security policy`; the trigger:
-- `run_insert_protected_columns`) and the pin is about the ROW, not the wording.
create or replace function t_risl_plant(p_booking uuid, p_runner uuid, p_cols text, p_vals text)
returns text language plpgsql as $$
declare v_err text := '';
begin
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  execute 'set local role authenticated';
  begin
    execute format('insert into runs (booking_id, %s) values (%L, %s)', p_cols, p_booking, p_vals);
  exception when others then
    v_err := sqlstate || ':' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
  return v_err;
end $$;

do $$
declare
  oo uuid; oz uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  bk uuid; b_a uuid; b_b uuid; b_c uuid;
  v_bad text := ''; v_msg text; v_err text; v_n int; v_txt text;
  v_js jsonb; v_ts timestamptz; v_ts2 timestamptz; v_status text;
  v_col text;
begin
  oo := t_user('risl_oo', 'owner'); oz := t_user('risl_oz', 'owner');
  rr := t_user('risl_rr', 'runner'); rz := t_user('risl_rz', 'runner');
  dg := t_dog(oo, '봉인견'); rt := t_route('봉인 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S1] EXPLOIT ① — a forged `started_at` can no longer defeat the return seal
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The attack: plant `runs(booking_id, started_at = '2000-01-01')` while the booking is still
  -- `picked_up`. 0083 §6's old-client arm grandfathers a settlement whose run STARTED before
  -- `ops_flags.return_seal_since`, and it reads that moment off `runs.started_at` — so a run born
  -- in the year 2000 is grandfathered forever and settles with no return seal at all, no matter
  -- when Sean flips the flag. That is the codex bypass 0083 exists to close, reopened from
  -- underneath by the one input it assumed was a server fact.
  -- ⚠ The plant here is made AS POSTGRES, deliberately: S2 pins that a client can no longer make
  -- it, and S1 pins the SECOND question — what happens to a row that got in anyway (a plant from
  -- before this migration applied, which is residual (a) in §4). The answer must be that starting
  -- the run corrects it, because `start_run_tx` overwrites the timestamp rather than coalescing.
  begin
    v_bad := '';
    bk := t_risl_picked(oo, dg, rt, rr);
    insert into runs (booking_id, started_at) values (bk, timestamptz '2000-01-01 00:00:00+09');

    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := start_run_tx(bk);
    perform set_config('request.jwt.claim.sub', '', false);

    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if v_ts < now() - interval '1 minute' then
      v_bad := v_bad || ' 시작 시각이 여전히 클라 값이다=' || v_ts::text;
    end if;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 상태가 active가 아니다'; end if;

    -- now arm the seal and try to settle without any return stamp — the whole point of the attack
    update ops_flags set return_seal_since = now() - interval '1 hour', updated_at = now();
    begin
      perform t_settle(bk, 'completed');
      v_bad := v_bad || ' 씰 없이 정산이 통과했다 (컷오버 무력화)';
    exception when others then
      if sqlerrm not like '%run_not_ended%' then
        v_bad := v_bad || ' 거부 사유가 다르다=' || sqlerrm;
      end if;
    end;
    -- and the refusal actually held: no state move, no money
    select b.status::text into v_status from bookings b where b.id = bk;
    if v_status <> 'active' then v_bad := v_bad || ' 거부됐는데 상태가 움직였다=' || v_status; end if;
    select count(*) into v_n from ledger_items where booking_id = bk;
    if v_n <> 0 then v_bad := v_bad || ' 거부됐는데 원장이 생겼다=' || v_n; end if;

    update ops_flags set return_seal_since = null, updated_at = now();
    if v_bad = ''
      then call _pass('risl','S1 ① 컷오버 무력화 봉인 — 심어진 started_at(2000년)은 러닝 시작이 서버 시각으로 덮고, 씰 이후 시작된 러닝은 종료 기록 없이는 run_not_ended로 거부된다 (상태·원장 무변)');
    else v_msg := v_bad; call _fail('risl','S1 ① 컷오버 무력화 봉인', v_msg); end if;
  exception when others then
    update ops_flags set return_seal_since = null;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S1 ① 컷오버 무력화 봉인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S2] THE REVOCATION — an authenticated assigned runner cannot INSERT into `runs` at all
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `runs runner write` (0002:107) checked `b.runner_id = auth.uid()` and nothing else. The
  -- runner IS the assigned runner here — that is the point: this is not a stolen booking, it is
  -- the legitimate party writing a row nobody validates. Every probe below is a column money or a
  -- derived surface reads, plus the bare insert, because after §1 there is no legitimate client
  -- insert AT ALL and the seal has to be total rather than column-shaped.
  begin
    v_bad := '';
    b_a := t_risl_picked(oo, dg, rt, rr);

    if t_risl_plant(b_a, rr, 'started_at', quote_literal('2000-01-01')) = ''
      then v_bad := v_bad || ' started_at 심기 통과'; end if;
    if t_risl_plant(b_a, rr, 'settled_at', 'now()') = ''
      then v_bad := v_bad || ' settled_at 심기 통과'; end if;
    if t_risl_plant(b_a, rr, 'ended_at, actual_km, end_reason',
                    'now(), 9.9, ' || quote_literal('completed') || '::end_reason') = ''
      then v_bad := v_bad || ' ended_at/거리/사유 심기 통과'; end if;
    if t_risl_plant(b_a, rr, 'duration_sec, avg_pace_sec_per_km', '99999, 1') = ''
      then v_bad := v_bad || ' 시간·페이스 심기 통과'; end if;
    if t_risl_plant(b_a, rr, 'events', quote_literal('[{"kind":"poop"}]') || '::jsonb') = ''
      then v_bad := v_bad || ' events 심기 통과'; end if;
    -- the bare insert too: `booking_id` alone is refused because there is no policy, not because
    -- of the column list. This is the probe that tells §1 apart from §3.
    if t_risl_plant(b_a, rr, 'trace', quote_literal('[]') || '::jsonb') = ''
      then v_bad := v_bad || ' 빈 행 심기 통과 (정책이 아직 살아 있다)'; end if;

    -- and neither can the other party, nor a stranger
    if t_risl_plant(b_a, oo, 'started_at', 'now()') = ''
      then v_bad := v_bad || ' 보호자 심기 통과'; end if;
    if t_risl_plant(b_a, rz, 'started_at', 'now()') = ''
      then v_bad := v_bad || ' 제3자 심기 통과'; end if;

    select count(*) into v_n from runs where booking_id = b_a;
    if v_n <> 0 then v_bad := v_bad || ' 실제로 행이 생겼다=' || v_n; end if;

    if v_bad = ''
      then call _pass('risl','S2 클라 INSERT 봉인 — 배정된 러너 본인도(보호자·제3자도) runs 행을 만들 수 없다: started_at·settled_at·ended_at/거리/사유·시간·events는 물론 빈 행조차 거부 (0002:107 정책 철거)');
    else v_msg := v_bad; call _fail('risl','S2 클라 INSERT 봉인', v_msg); end if;
  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S2 클라 INSERT 봉인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S3] EXPLOIT ③ — no charge can be minted for a run that never happened
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `sweep_settled_without_payments` (0080 §G) selects every booking whose run has an `ended_at`
  -- and no payments row, then mints through `mint_settle_charge_intent` using `end_reason` and
  -- `actual_km` READ OFF THAT SAME ROW. It checks no booking status — `settle_run_tx`'s atomic
  -- `where status = 'active'` claim protects the normal path, and the sweep inherits none of it.
  -- So a planted row on a booking that was never started is a real charge intent against the
  -- owner's card, priced by numbers the beneficiary typed.
  -- ⚠ The positive control is load-bearing: it plants the identical row AS THE SERVER and proves
  -- the sweep DOES mint from it. Without that, S3 would pass just as happily against a dead sweep.
  begin
    v_bad := '';
    b_b := t_risl_picked(oz, dg, rt, rz);   -- never started: status stays `picked_up`
    update ops_flags set payments_live_since = now() - interval '1 hour', updated_at = now();

    -- the attack
    if t_risl_plant(b_b, rz, 'ended_at, actual_km, duration_sec, end_reason',
                    'now(), 9.9, 3600, ' || quote_literal('completed') || '::end_reason') = ''
      then v_bad := v_bad || ' 유령 러닝 심기 통과'; end if;
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments where booking_id = b_b;
    if v_n <> 0 then v_bad := v_bad || ' 하지도 않은 러닝에 청구가 생겼다=' || v_n || '행'; end if;
    select count(*) into v_n from runs where booking_id = b_b;
    if v_n <> 0 then v_bad := v_bad || ' 유령 run 행이 남았다=' || v_n; end if;

    -- POSITIVE CONTROL — the same row, written by the server, IS swept and minted. This is what
    -- proves S3 measures the plant's absence rather than a sweep that stopped working.
    -- ⚠ On its OWN booking, deliberately: reusing the attack's booking would make a successful
    -- plant collide with `runs_booking_id_key` and this case would report a duplicate-key error
    -- instead of the charge it lost. A pin whose red message does not name the money is a worse
    -- pin, and that is exactly how the M3 mutation run first read.
    -- ⚠ [0116 §A] `settled_at` ADDED to the positive control, and this is the pin's asserted
    -- property legitimately MOVING rather than a fixture being tuned until it passes. This block's
    -- own header (S4, below) already names `and rn.settled_at is not null` as the predicate 0083
    -- §0f hands the payments session; 0116 §A is that predicate landing. "The server writes this
    -- row and the sweep mints from it" now means a SETTLED row — an `ended_at` alone means the run
    -- STOPPED, and billing on it is a charge for a dog still on the leash.
    -- ⚠ The ATTACK arm above is deliberately NOT given a `settled_at`, and must not be: S4 pins
    -- that no client can write that column on either verb, so after 0116 §A a successful ghost
    -- plant cannot reach a charge at all. The attack arm's own two assertions (the plant is
    -- REFUSED, and no `runs` row survives) are what carry it, and they still redden under 0087's
    -- mutation. 151 B1 owns the new property in both directions.
    b_c := t_risl_picked(oz, dg, rt, rz);
    insert into runs (booking_id, ended_at, settled_at, actual_km, duration_sec, end_reason)
      values (b_c, now(), now(), 9.9, 3600, 'completed');
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments where booking_id = b_c and (raw->>'kind') is not null;
    if v_n <> 1 then v_bad := v_bad || ' 양성 대조 실패: 서버가 쓴 같은 행을 스윕이 민팅하지 않았다=' || v_n; end if;

    -- leave nothing behind: these bookings are fixtures, not settlements
    delete from payments where booking_id in (b_b, b_c);
    delete from runs where booking_id in (b_b, b_c);
    update ops_flags set payments_live_since = null, updated_at = now();

    if v_bad = ''
      then call _pass('risl','S3 ③ 유령 청구 봉인 — 시작조차 안 한 예약에 ended_at·거리·사유를 심을 수 없고 스윕도 청구를 만들지 않는다 (서버가 **정산된** 같은 행을 쓰면 민팅된다 = 양성 대조. [0116 §A] 양성 대조가 settled_at을 찍는다 — 스윕의 앵커가 정지가 아니라 정산이 됐고, 그래서 심기가 뚫려도 청구까지는 못 간다)');
    else v_msg := v_bad; call _fail('risl','S3 ③ 유령 청구 봉인', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = null;
    begin execute 'reset role'; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S3 ③ 유령 청구 봉인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S4] EXPLOIT ② — `runs.settled_at` has no client writer, on either verb
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `settled_at` is the anchor 0083 §0f hands the payments session (`and rn.settled_at is not
  -- null`) and the property 119 R11 pins: *written by settlement and by nothing else*. R11 could
  -- not see this hole — it watches the RPCs, and a raw INSERT calls none of them.
  -- (⚠ 0087 §0 ② corrects the brief that found this: a forged `settled_at` does not HIDE a
  -- booking from that sweep, since the predicate is `is not null`. It makes it visible — i.e. it
  -- is the entry ticket to S3 once §0f lands, not an evasion. Same defect, same fix.)
  begin
    v_bad := '';
    b_c := t_risl_picked(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform start_run_tx(b_c);
    perform set_config('request.jwt.claim.sub', '', false);

    -- INSERT side (a second row for the same booking would also hit the unique index, so the
    -- probe is a DIFFERENT booking with no row at all — the shape the attack actually uses)
    if t_risl_plant(t_risl_picked(oo, dg, rt, rr), rr, 'settled_at, ended_at', 'now(), now()') = ''
      then v_bad := v_bad || ' INSERT로 settled_at 심기 통과'; end if;

    -- UPDATE side (0083 §2's `_guard_run_cols`, re-asserted here because the two belts are only
    -- worth anything together — sealing one verb and leaving the other is how this hole was born)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    set local role authenticated;
    begin
      update runs set settled_at = now() where booking_id = b_c;
      v_bad := v_bad || ' UPDATE로 settled_at 쓰기 통과';
    exception when others then
      if sqlerrm not like '%run_protected_columns%' then
        v_bad := v_bad || ' UPDATE 거부 사유가 다르다=' || sqlerrm;
      end if;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);

    select r.settled_at into v_ts from runs r where r.booking_id = b_c;
    if v_ts is not null then v_bad := v_bad || ' 정산도 안 했는데 settled_at이 찍혔다'; end if;

    if v_bad = ''
      then call _pass('risl','S4 ② 정산 앵커 봉인 — settled_at은 INSERT로도 UPDATE로도 클라가 쓸 수 없다 (119 R11의 "정산만이 쓴다"가 INSERT 쪽에서도 참이 된다)');
    else v_msg := v_bad; call _fail('risl','S4 ② 정산 앵커 봉인', v_msg); end if;
  exception when others then
    begin reset role; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S4 ② 정산 앵커 봉인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S5] DEFENCE IN DEPTH — the BEFORE INSERT guard holds when the policy comes back
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- §1 is the fix and §3 is the belt, and a belt nobody can test is a belt nobody maintains. So
  -- this case RE-CREATES the exact 0002:107 policy inside itself, proves `_guard_run_insert_cols`
  -- refuses every protected column anyway, proves a bare `booking_id` insert still SUCCEEDS (the
  -- guard is a list, not a deny-all — 0083 §2's shape), and drops the policy again.
  -- That last positive control is not decoration: a guard that refuses everything cannot tell an
  -- attack from a caller, and would silently break the next legitimate insert path anyone adds.
  begin
    v_bad := '';
    create policy "risl probe insert" on runs for insert with check (
      exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid())
    );

    for v_col, v_txt in
      select * from (values
        ('started_at',          'now()'),
        ('ended_at',            'now()'),
        ('settled_at',          'now()'),
        ('actual_km',           '9.9'),
        ('duration_sec',        '3600'),
        ('avg_pace_sec_per_km', '300'),
        ('end_reason',          quote_literal('completed') || '::end_reason'),
        ('condition_note',      quote_literal('가짜')),
        ('events',              quote_literal('[{"kind":"poop"}]') || '::jsonb'),
        ('trace',               quote_literal('[{"lat":1,"lng":2}]') || '::jsonb'),
        ('photos',              quote_literal('{"https://x/y.jpg"}') || '::text[]')
      ) t(c, v)
    loop
      b_c := t_risl_picked(oo, dg, rt, rr);
      v_err := t_risl_plant(b_c, rr, v_col, v_txt);
      if v_err = '' then
        v_bad := v_bad || ' 정책 복구 시 ' || v_col || ' 통과';
      elsif v_err not like '%run_insert_protected_columns%' then
        v_bad := v_bad || ' ' || v_col || ' 거부 사유가 트리거가 아니다=' || left(v_err, 60);
      end if;
    end loop;

    -- POSITIVE CONTROL — booking_id alone is a legitimate shape and must get through.
    b_c := t_risl_picked(oz, dg, rt, rz);
    v_err := t_risl_plant(b_c, rz, 'trace', quote_literal('[]') || '::jsonb');
    if v_err <> '' then
      v_bad := v_bad || ' 최소 삽입(booking_id + 기본값)이 거부됐다 = 전면 거부 가드=' || left(v_err, 60);
    end if;
    -- and 0079's snapshot still owns pace_suggest_sec regardless of what the caller sent
    select r.pace_suggest_sec into v_n from runs r where r.booking_id = b_c;
    if v_n is null then v_bad := v_bad || ' 0079 페이스 스냅샷이 안 찍혔다 (트리거 순서 회귀)'; end if;
    delete from runs where booking_id = b_c;

    drop policy if exists "risl probe insert" on runs;
    if v_bad = ''
      then call _pass('risl','S5 이중 벨트 — 정책이 되살아나도 _guard_run_insert가 11개 보호 컬럼을 전부 거부하고, booking_id만 담은 정당한 삽입은 통과시킨다(전면 거부 아님) · 0079 페이스 스냅샷 순서 유지');
    else v_msg := v_bad; call _fail('risl','S5 이중 벨트', v_msg); end if;
  exception when others then
    begin drop policy if exists "risl probe insert" on runs; exception when others then null; end;
    begin execute 'reset role'; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S5 이중 벨트', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S6] start_run_tx — atomic, gated, idempotent, and the clock is the SERVER's
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The two-step it replaces (`set status='active'` then a separate insert whose error was
  -- discarded) is the reason a plant survived. What replaces it has to be all four things at
  -- once, so all four are measured in one case.
  begin
    v_bad := '';
    bk := t_risl_picked(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);

    v_js := start_run_tx(bk);
    if coalesce((v_js->>'unchanged')::boolean, true) then v_bad := v_bad || ' 첫 시작이 unchanged=true'; end if;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 상태가 active로 가지 않았다'; end if;
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if v_ts is null or v_ts < now() - interval '1 minute'
      then v_bad := v_bad || ' 서버 started_at이 아니다=' || coalesce(v_ts::text,'∅'); end if;

    -- idempotence: a second start is the SAME start, and must not move the clock
    v_js := start_run_tx(bk);
    if not coalesce((v_js->>'unchanged')::boolean, false) then v_bad := v_bad || ' 재시작이 unchanged=false'; end if;
    select r.started_at into v_ts2 from runs r where r.booking_id = bk;
    if v_ts2 is distinct from v_ts then v_bad := v_bad || ' 재시작이 시작 시각을 옮겼다'; end if;
    select count(*) into v_n from runs where booking_id = bk;
    if v_n <> 1 then v_bad := v_bad || ' runs 행이 1행이 아니다=' || v_n; end if;

    -- the repair arm: `active` with a NULL started_at (the two-step's crash window) is fixed,
    -- not left showing both parties a blank elapsed clock
    update runs set started_at = null where booking_id = bk;
    perform start_run_tx(bk);
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if v_ts is null then v_bad := v_bad || ' started_at 결손이 복구되지 않았다'; end if;

    -- state gate: a booking that has not been handed over cannot start
    b_c := t_risl_picked(oo, dg, rt, rr, 'confirmed');
    begin
      perform start_run_tx(b_c);
      v_bad := v_bad || ' confirmed에서 시작이 통과했다';
    exception when others then
      if sqlerrm not like '%not_picked_up%' then v_bad := v_bad || ' 상태 거부 사유가 다르다=' || sqlerrm; end if;
    end;
    if (select count(*) from runs where booking_id = b_c) <> 0
      then v_bad := v_bad || ' 거부됐는데 run 행이 생겼다'; end if;
    if (select b.status::text from bookings b where b.id = b_c) <> 'confirmed'
      then v_bad := v_bad || ' 거부됐는데 상태가 움직였다'; end if;

    -- party gate BEFORE state gate (repo law): another runner cannot start my run
    b_c := t_risl_picked(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    begin
      perform start_run_tx(b_c);
      v_bad := v_bad || ' 남의 러너가 시작시켰다';
    exception when others then
      if sqlerrm not like '%not_run_runner%' then v_bad := v_bad || ' 당사자 거부 사유가 다르다=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('risl','S6 start_run_tx — picked_up에서만·원자 클레임·서버 시각·재시작은 unchanged(시각 불변)·started_at 결손 복구·당사자 게이트가 상태 게이트보다 먼저');
    else v_msg := v_bad; call _fail('risl','S6 start_run_tx', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S6 start_run_tx', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S7] POSITIVE CONTROL — the runner's live append surface is untouched
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The cheap way to close an INSERT hole is to revoke the runner's writes wholesale, and it
  -- would take live GPS persistence down with it: `saveTrace` (api.ts:1807) is a DIRECT
  -- `update runs set trace = …` through `"runs runner update"` (0057 §5), and the events/photos
  -- appends ride definer RPCs. This case is what stops that shortcut being taken later.
  begin
    v_bad := '';
    bk := t_risl_picked(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform start_run_tx(bk);

    -- ① the direct trace UPDATE, as the runner, through RLS
    set local role authenticated;
    begin
      update runs set trace = jsonb_build_array(jsonb_build_object('lat',37.5,'lng',127.0,'t',1))
        where booking_id = bk;
    exception when others then
      v_bad := v_bad || ' 라이브 트레이스 저장이 막혔다=' || sqlerrm;
    end;
    reset role;
    if (select jsonb_array_length(r.trace) from runs r where r.booking_id = bk) <> 1
      then v_bad := v_bad || ' 트레이스가 실제로 안 들어갔다'; end if;

    -- ② the two definer appends
    begin
      perform append_run_event(bk, jsonb_build_object('kind','poop','at', now()));
    exception when others then v_bad := v_bad || ' append_run_event 실패=' || sqlerrm; end;
    begin
      perform append_run_photo(bk, 'https://x/y.jpg');
    exception when others then v_bad := v_bad || ' append_run_photo 실패=' || sqlerrm; end;
    select jsonb_array_length(r.events), array_length(r.photos, 1) into v_n, v_status
      from runs r where r.booking_id = bk;
    if coalesce(v_n,0) <> 1 then v_bad := v_bad || ' events가 안 들어갔다'; end if;
    if coalesce(v_status,'0') <> '1' then v_bad := v_bad || ' photos가 안 들어갔다'; end if;

    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('risl','S7 양성 대조 — 봉인 뒤에도 러너의 라이브 append 3종(직접 trace UPDATE·append_run_event·append_run_photo)은 그대로 동작한다 (INSERT를 막느라 UPDATE를 끄지 않았다)');
    else v_msg := v_bad; call _fail('risl','S7 양성 대조', v_msg); end if;
  exception when others then
    begin reset role; exception when others then null; end;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S7 양성 대조', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S8] POSITIVE CONTROL — every SERVER writer of `runs` still gets through the new trigger
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The trigger judges `current_user`, and the failure mode of that idiom is well documented in
  -- this repo (0083's header: inside a SECURITY DEFINER `current_user` is always `postgres`, so a
  -- DEFINER guard judges NOBODY). The mirror-image failure is a guard so broad it refuses the
  -- server: `settle_run_tx`'s upsert backstop (0028 ③) creates a runs row FROM SCRATCH carrying
  -- ended_at + actual_km + end_reason + settled_at when the start event was lost — the single
  -- most protected-column-dense insert in the repo, and it must pass.
  begin
    v_bad := '';
    -- ① end_run_tx (definer, service_role) writes measurements into an existing row
    bk := t_risl_picked(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform start_run_tx(bk);
    perform end_run_tx(bk, 3.2, 2100, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    select r.actual_km, r.ended_at into v_txt, v_ts from runs r where r.booking_id = bk;
    if v_txt::numeric is distinct from 3.2 or v_ts is null
      then v_bad := v_bad || ' end_run_tx 동결이 막혔다'; end if;

    -- ② settle_run_tx's no-runs-row backstop — the densest server INSERT there is
    b_c := t_risl_picked(oz, dg, rt, rz);
    update bookings set status = 'active' where id = b_c;
    if (select count(*) from runs where booking_id = b_c) <> 0
      then v_bad := v_bad || ' 사전 조건 실패: run 행이 이미 있다'; end if;
    begin
      perform t_settle(b_c, 'completed');
    exception when others then
      v_bad := v_bad || ' settle_run_tx 백스톱 INSERT가 막혔다=' || sqlerrm;
    end;
    select count(*) into v_n from runs where booking_id = b_c;
    if v_n <> 1 then v_bad := v_bad || ' 백스톱이 run 행을 만들지 못했다=' || v_n; end if;
    select r.settled_at into v_ts from runs r where r.booking_id = b_c;
    if v_ts is null then v_bad := v_bad || ' 백스톱이 settled_at을 못 썼다 (가드가 서버를 막았다)'; end if;

    if v_bad = ''
      then call _pass('risl','S8 양성 대조 — 서버 작성자는 전부 통과한다: end_run_tx의 동결과 settle_run_tx의 run 행 없는 백스톱 upsert(ended_at·거리·사유·settled_at을 한 번에 담는 가장 조밀한 INSERT)가 새 INSERT 가드를 지난다');
    else v_msg := v_bad; call _fail('risl','S8 양성 대조', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('risl','S8 양성 대조', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [S9] the structural inventory — and the flags are handed back clean
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 116 C21 / 119 R13's idiom: assert the SHAPE, so that the next person who adds a convenience
  -- policy or a broad grant trips a pin instead of reopening §0. Plus the housekeeping half —
  -- S1 and S3 both flip a cutover switch, and this suite runs last, so leaving one on would
  -- change what the NEXT reader's harness run means.
  begin
    v_bad := '';
    if not (select c.relrowsecurity from pg_class c where c.oid = 'runs'::regclass)
      then v_bad := v_bad || ' runs에 RLS가 꺼졌다'; end if;
    -- ⚠ `cmd in ('INSERT','ALL')`, NOT `cmd = 'INSERT'` — corrected 2026-08-14 (trust).
    -- A policy created `FOR ALL` reports `cmd = 'ALL'` in pg_policies and PERMITS INSERT, so the
    -- old literal match counted 0 and this pin stayed GREEN while 0087's forgery hole was open.
    -- Measured before fixing: `create policy … for all to authenticated` → pg_policies.cmd = 'ALL'.
    -- The convenience policy this pin exists to catch is the exact shape most likely to be written
    -- `FOR ALL` — one policy instead of three is what makes it convenient. Same defect class as the
    -- REGISTRY detector corrected the same day: enumerating a literal instead of asking what the
    -- engine actually permits. 'ALL' is the complete additional case ('r'/'a'/'w'/'d'/'*' is the
    -- whole polcmd domain, and only 'a' and '*' permit INSERT).
    select count(*) into v_n from pg_policies
      where schemaname = 'public' and tablename = 'runs' and cmd in ('INSERT','ALL');
    if v_n <> 0 then v_bad := v_bad || ' runs에 INSERT를 허용하는 정책이 있다(INSERT 또는 ALL)=' || v_n; end if;
    select count(*) into v_n from pg_policies
      where schemaname = 'public' and tablename = 'runs' and cmd in ('SELECT','UPDATE');
    if v_n <> 2 then v_bad := v_bad || ' 읽기·수정 정책이 2개가 아니다=' || v_n; end if;
    if not exists (select 1 from pg_trigger where tgrelid = 'runs'::regclass
                     and tgname = '_guard_run_insert' and not tgisinternal)
      then v_bad := v_bad || ' _guard_run_insert 트리거가 없다'; end if;
    -- INVOKER, not DEFINER — the whole guard is worthless the other way (0083's recorded trap)
    if (select p.prosecdef from pg_proc p where p.proname = '_guard_run_insert_cols')
      then v_bad := v_bad || ' 가드가 SECURITY DEFINER다 (current_user가 항상 postgres → 아무도 못 잡는다)'; end if;
    -- start_run_tx is service_role only, exactly like end_run_tx
    if has_function_privilege('authenticated', 'start_run_tx(uuid)', 'execute')
      then v_bad := v_bad || ' start_run_tx가 authenticated에 열려 있다'; end if;
    if has_function_privilege('anon', 'start_run_tx(uuid)', 'execute')
      then v_bad := v_bad || ' start_run_tx가 anon에 열려 있다'; end if;
    if not has_function_privilege('service_role', 'start_run_tx(uuid)', 'execute')
      then v_bad := v_bad || ' start_run_tx가 service_role에 닫혀 있다'; end if;

    -- the cutover switches this suite touched are back to the shipped NULL
    if (select f.return_seal_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' return_seal_since가 켜진 채 남았다'; end if;
    if (select f.payments_live_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' payments_live_since가 켜진 채 남았다'; end if;

    if v_bad = ''
      then call _pass('risl','S9 구조 인벤토리 — runs는 RLS on·INSERT 허용 정책 0개(ALL 포함)·읽기/수정 2개, _guard_run_insert는 존재하고 INVOKER, start_run_tx는 service_role 전용, 그리고 이 스위트가 만진 컷오버 스위치 둘은 NULL로 반납됐다');
    else v_msg := v_bad; call _fail('risl','S9 구조 인벤토리', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('risl','S9 구조 인벤토리', v_msg);
  end;
end $$;
