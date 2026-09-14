-- ═══ 0169 — the SQL belt: `settle_run_tx` refuses a booking that is still `stopping` ════════
--
-- Closes the NAMED GAP 0168 wrote into its own header (`0168:72-80`) and repeated at the site
-- (`settle-run/handler.ts:100-103`): the edge handler refuses a `stopping` booking with a typed
-- 409 (`handler.ts:94-99`), and `settle_run_tx` itself has no such gate — so a caller holding
-- `service_role` (another edge function, a cron, a hand-run repair, a future handler that forgets)
-- can still settle a run whose numbers have not been frozen, **at the CLIENT's numbers**, which is
-- the defect 0168 exists to remove wearing a different door.
--
-- 🔴 LIVE MONEY, UN-FLAG-GATED, for 0168's reason: the runner's `ledger_items` row is written
--    with `ops_flags.payments_live_since` NULL (`0083:754`). The owner's COLLECTION is flagged;
--    the payout is not.
--
-- ── WHAT THIS FILE IS ──────────────────────────────────────────────────────────────────────
-- A forward redefinition of `settle_run_tx` whose base is the LAST definition in the tree —
-- `0083:628-836`, the §6/ⓑ/ⓒ/ⓓ/ⓔ body — **extracted programmatically rather than retyped**, and
-- byte-identical to it except for exactly three additions, two of which are mechanical:
--   ① one `declare` line: `v_run_stopping timestamptz;`
--   ② `run_stopping_at` added to the row read that is ALREADY taken `for update` (`0083:668-670`),
--      so the belt reads the same locked snapshot as ⓑ and ⓔ rather than re-selecting the row.
--   ③ one refusal, placed immediately after the existence gate (`not_found`, `0083:671-673`) and
--      therefore BEFORE the seal gate ⓑ, BEFORE the freeze gate ⓔ, and before the first state
--      mutation (`update bookings set status = 'completed'`, `0083:720`).
-- Nothing else moves. 0168's own apply-time VERIFY reads this function's source for ⓔ's
-- `frozen_measurement_mismatch` and for its freeze preservation (`0168:1016-1027`); both survive
-- here, and §VERIFY below re-asserts them so this file cannot quietly drop what 0168 depends on.
--
-- ── THE PREDICATE IS 0168'S OWN, NOT A NEW ONE ────────────────────────────────────────────
--   `run_stopping_at is not null and run_ended_at is null`
-- verbatim the phase as 0168 defines it everywhere it is read: `handler.ts:94`, the board's new
-- `runStopping` key (`0168:814`), and the state machine in 0168's header (`0168:24-29`). It is a
-- DERIVED predicate over two columns and there is no helper to call — inventing one here would be
-- a second definition of the phase, and 0168 §G's escalation ③ is the record of what happens when
-- one name is widened to mean two states.
-- ⚠ The `run_ended_at is null` half is load-bearing and is the thing a lazy version gets wrong:
--   the freeze does NOT clear `run_stopping_at` (`0168:589-600` writes `run_ended_at` and leaves
--   the stamp), so a gate keyed on `run_stopping_at` alone would refuse **every club settle for
--   ever**. 0168's Deno suite already carries that control for the handler; `0169-B2` is it here.
--
-- ── THE CODE, AND A DIVERGENCE FROM THE CONTRACT SAID OUT LOUD ─────────────────────────────
-- Raised as `run_stopping`, in the shape this function already uses for its other refusals —
-- `raise exception '<code>' using detail = '<Korean>'` (ⓑ `return_not_sealed` `0083:686-687`,
-- ⓔ `frozen_measurement_mismatch` `0083:714-715`) — with §5's SETTLE-time sentence
-- 「기록을 확정하고 있어요 — 잠시 뒤 정산할 수 있어요」, which is byte-for-byte the copy the handler's
-- 409 already returns (`handler.ts:98`). Never ⓑ's `run_not_ended`: that renders 「앱을 최신 버전으로
-- 업데이트해주세요」 (`handler.ts:242`) and sends a runner chasing a version that changes nothing —
-- contract §4.6's whole reason for asking for a distinct code.
--
-- ⚠ **DIVERGENCE, and it is Sean's to rule on.** Contract §5 names this code `run_stop_pending`;
--    this file raises `run_stopping`, which is the token the slice was specified against and the
--    one the shipped handler already writes in its own refusal log (`handler.ts:96`). The cost of
--    the choice, stated rather than discovered later: `club_save_run_trace` raises the SAME token
--    for a DIFFERENT event (a late upload after the drain closed) whose copy is
--    「업로드가 늦었어요 — 마지막 구간은 반영되지 않아요」 (contract §5, `0168:419`). The two never meet
--    today — different function, different endpoint, and `settle-run` maps RPC failures by
--    `msg.includes(...)` (`handler.ts:225-252`) with **no arm for either token**, so an unmapped
--    `run_stopping` from here falls to the retryable 500 at `:252` — and for the shipping caller
--    this belt is a tautology anyway, exactly as ⓔ is for the frozen path, because `handler.ts:94`
--    fires before the RPC is ever called. **But a future session wiring the client MUST key the new
--    arm on the SETTLE path and not on the token alone**, or it will hand a runner the ingest copy
--    at settle time. If Sean prefers two tokens, the change is this one string plus `0169-B1`.
--
-- ── WHY A BELT ON A DOOR NO CLIENT CAN REACH IS NOT CHURN ─────────────────────────────────
-- `settle_run_tx` is revoked from `public, anon, authenticated` (`0083:838`) and `settle-run` is
-- the only caller in the tree — so this is not a live breach, and calling it one would be the
-- 「a grant is not a door」 error in reverse. It is the belt: the handler's gate is one `if` in one
-- TypeScript file that any second caller bypasses by existing, and the invariant 0168 states —
-- 「no ledger row exists for a run whose trace is still changing」 (`0168:19-21`) — is a property of
-- the DATABASE, so it is owed a guard the database enforces.
--
-- ── ON THE SWEEP, WHICH IS THE REASON THIS REFUSAL CANNOT STRAND ANYBODY ───────────────────
-- The refused state is not terminal and nobody has to act to leave it: `club_finalize_stopped_runs()`
-- runs every minute (`0168:655-682`) and freezes the numbers 90-150 s after the tap, after which
-- the very same call settles (`0169-B2`). That is what separates this from the deadlock class
-- 0083 ⓔ argues against at length — a refusal that waits on a clock nobody winds is an unpayable
-- runner, and this one waits on a cron row that 0168-P4 re-reads from `cron.job`.

create or replace function settle_run_tx(
  p_booking uuid,
  p_actual_km numeric,
  p_duration_sec int,
  p_end_reason text,
  p_condition_note text,
  p_base int,
  p_distance_pay int,
  p_addon_pay int,
  p_guarantee int,
  p_fee int
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_owner uuid;
  v_runner uuid;
  v_route uuid;
  v_claimed int;
  v_is_full boolean := (p_end_reason = 'completed');
  v_has_poop boolean := false;
  v_total_runs int;
  v_drop jsonb := null;
  v_roll float;
  v_miles int;
  v_profile uuid;
  v_course_runs int;
  v_club uuid;                 -- [0083]
  v_run_ended timestamptz;     -- [0083]
  v_ready timestamptz;         -- [0083]
  v_seal_since timestamptz;    -- [0083]
  v_started timestamptz;       -- [0083]
  v_fz_km numeric;             -- [0083 ⓔ]
  v_fz_reason text;            -- [0083 ⓔ]
  v_run_stopping timestamptz;  -- [0169] addition ① — the tap, phase 1 of 0168's two-phase stop
begin
  -- [0028 ④] 입력 새니티 — 돈 계산 입력은 서버 경계에서 한 번 더
  if p_actual_km is null or p_actual_km < 0 or p_actual_km > 100 then
    raise exception 'invalid_km';
  end if;
  if p_duration_sec is not null and p_duration_sec < 0 then
    raise exception 'invalid_duration';
  end if;

  -- [0169] addition ② — `run_stopping_at` joins the row read that is ALREADY under `for update`,
  -- rather than a second select afterwards: every gate below then reads one snapshot of one locked
  -- row, and the belt cannot be reasoned about separately from the freeze gate it sits in front of.
  select owner_id, runner_id, route_id, club_session_id, run_ended_at, settlement_ready_at, run_stopping_at
    into v_owner, v_runner, v_route, v_club, v_run_ended, v_ready, v_run_stopping
  from bookings where id = p_booking for update;
  if v_owner is null then
    raise exception 'not_found';
  end if;

  -- ── [0169] addition ③ — THE BELT: a run whose numbers are not frozen is not settleable ───
  -- 0168's phase-1 state, read exactly as 0168 defines it (`handler.ts:94`, board key `0168:814`,
  -- state machine `0168:24-29`): the host has tapped 러닝 종료 and the sweep has not yet derived and
  -- frozen the distance. `settle_run_tx` would otherwise write the ledger from the CLIENT's
  -- numbers — which is the whole defect 0168 exists to remove, reached through the service_role
  -- door instead of the client's. The edge handler refuses this state with a 409 already
  -- (`handler.ts:94-99`); that gate is one `if` in one TypeScript file and any second caller
  -- bypasses it by existing, while the invariant is a property of the database.
  -- ⚠ BOTH halves. The freeze does not clear `run_stopping_at` (`0168:589-600` writes
  --   `run_ended_at` and leaves the stamp), so `v_run_stopping is not null` alone would refuse
  --   every club settle for ever — 0169-B2 is that control.
  -- ⚠ Placed HERE, after the existence gate and before the seal gate ⓑ, the freeze gate ⓔ and the
  --   atomic claim: a refusal that runs after `update bookings set status = 'completed'` would
  --   roll back in this transaction but would already have been a state mutation in the reading.
  -- ⚠ Nobody is stranded by it: `club_finalize_stopped_runs()` runs every minute and the same call
  --   succeeds 90-150 s later (0169-B2). A refusal waiting on a clock nobody winds is the deadlock
  --   class ⓔ argues against; this one waits on a cron row 0168-P4 reads back from `cron.job`.
  if v_run_stopping is not null and v_run_ended is null then
    raise exception 'run_stopping'
      using detail = '기록을 확정하고 있어요 — 잠시 뒤 정산할 수 있어요';
  end if;

  -- ── [0083 §6] THE RETURN SEAL (plan §2) ────────────────────────────────────────────────
  -- Clubs keep their own custody machinery (`session_custody_transfer`, 0045) and are out of this
  -- flow's scope by contract, so the gate is marketplace-only — stated as a predicate here rather
  -- than as a sentence in a plan (plan §7).
  if v_club is null then
    if v_run_ended is not null then
      if v_ready is null then
        -- The run stopped and the dog is not home. This is the bypass codex found: today this
        -- function pays the runner out mid-귀가.
        raise exception 'return_not_sealed'
          using detail = '아직 인계가 확인되지 않았어요 — 강아지가 집에 도착한 뒤 정산돼요';
      end if;
    else
      select f.return_seal_since into v_seal_since from ops_flags f where f.id;
      if v_seal_since is not null then
        select r.started_at into v_started from runs r where r.booking_id = p_booking;
        if coalesce(v_started, now()) >= v_seal_since then
          -- An old client settling a run it never ended. Distinct code on purpose (§9 D-r4①):
          -- the client renders "앱 업데이트가 필요해요", never a generic failure, never a no-op.
          raise exception 'run_not_ended'
            using detail = '러닝 종료 기록이 없어요 — 앱을 최신 버전으로 업데이트해주세요';
        end if;
      end if;
    end if;
  end if;

  -- ── [0083 §6-ⓔ] THE FREEZE, ENFORCED (plan §1/§2, codex minimum bar #3) ────────────────
  -- Once the stop is stamped, the client's numbers cannot change what is paid or charged. The
  -- shipping caller (`settle-run/handler.ts`) hands us its own `actual_km`/`end_reason`; if they
  -- are not the frozen ones, the price it computed from them is not this run's price either, so
  -- the only honest answer is a refusal. See ⓔ in the header for why this raises rather than
  -- substitutes, and why the comparison is made at the stored scale.
  if v_run_ended is not null then
    select rn.actual_km, rn.end_reason::text into v_fz_km, v_fz_reason
      from runs rn where rn.booking_id = p_booking;
    if round(p_actual_km, 2) is distinct from v_fz_km
       or p_end_reason is distinct from v_fz_reason then
      raise exception 'frozen_measurement_mismatch'
        using detail = '러닝 종료 때 기록된 거리·사유로만 정산할 수 있어요';
    end if;
  end if;

  -- 원자 클레임 — active에서만 completed로 (중복 정산 락, 기존 로직 그대로)
  update bookings set status = 'completed' where id = p_booking and status = 'active';
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    raise exception 'not_active';
  end if;

  -- run 기록 마감 ([0028 ①] 이넘 캐스트 · [0028 ③] upsert — start 이벤트 유실 시에도 기록 보존)
  -- [0083 ⓒⓓ] ended_at은 **서비스 정지 시각**이므로 이미 있으면 덮어쓰지 않는다. 돈이 움직인
  -- 시각은 settled_at이 따로 기록한다 (plan §3).
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note, settled_at)
  values (
    p_booking,
    case when p_duration_sec is not null then now() - make_interval(secs => p_duration_sec) else null end,
    now(), p_actual_km, p_duration_sec,
    case when p_duration_sec is not null and p_actual_km > 0 then round(p_duration_sec / p_actual_km)::int end,
    p_end_reason::end_reason, p_condition_note, now()
  )
  on conflict (booking_id) do update set
    ended_at = coalesce(runs.ended_at, excluded.ended_at),   -- [0083] 정지 시각 보존
    settled_at = now(),                                       -- [0083] 돈이 움직인 시각
    -- [0083 ⓔ] 동결된 러닝(정지 스탬프 있음)은 정산이 측정값을 **다시 쓰지 않는다**. 위 게이트가
    -- 거리·사유 불일치를 이미 거부하므로 그 둘은 어차피 같은 값이고, 돈을 움직이지 않는
    -- duration_sec·condition_note는 거부(=영구 미정산 위험) 대신 여기서 조용히 보존된다.
    -- 정지 스탬프가 없는 행(레거시·클럽 경로)은 0028 그대로 excluded가 이긴다.
    actual_km = case when v_run_ended is null then excluded.actual_km else runs.actual_km end,
    duration_sec = case when v_run_ended is null then excluded.duration_sec else runs.duration_sec end,
    avg_pace_sec_per_km = case when v_run_ended is null then excluded.avg_pace_sec_per_km
                               else runs.avg_pace_sec_per_km end,
    end_reason = case when v_run_ended is null then excluded.end_reason else runs.end_reason end,
    condition_note = case when v_run_ended is null then excluded.condition_note
                          else runs.condition_note end,
    started_at = coalesce(runs.started_at, excluded.started_at);

  -- 원장 (돈은 서버만 쓴다)
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee)
  values (v_runner, p_booking, p_base, p_distance_pay, p_addon_pay, 0, p_guarantee, p_fee);

  -- 응가 도장 여부 (러닝 이벤트)
  select exists (
    select 1 from runs, jsonb_array_elements(coalesce(events, '[]'::jsonb)) e
    where booking_id = p_booking and e->>'kind' = 'poop'
  ) into v_has_poop;

  -- 인센티브 게이트 — '완주'만 마일·러닝 카운트·드랍 (기존 독트린 그대로)
  if v_is_full then
    insert into miles_ledger (profile_id, delta, reason, ref_id) values
      (v_runner, 50, 'run_complete', p_booking),
      (v_owner, 50, 'run_complete', p_booking);
    if v_has_poop then
      insert into miles_ledger (profile_id, delta, reason, ref_id) values
        (v_runner, 30, 'poop_bonus', p_booking),
        (v_owner, 30, 'poop_bonus', p_booking);
    end if;

    -- 패치 승급 보너스 (0025) — 코스 누적이 정확히 10/25가 된 당사자에게
    -- [0028 ②] '완주'만 카운트: status='completed'는 조기 종료 정산도 포함하므로
    -- runs.end_reason='completed' 조인이 진짜 완주 기준 (인센티브는 완주만)
    if v_route is not null then
      for v_profile in select distinct unnest(array[v_runner, v_owner]) loop
        select count(*) into v_course_runs from bookings b
        join runs r on r.booking_id = b.id and r.end_reason = 'completed'
        where b.route_id = v_route and b.status = 'completed'
          and (b.owner_id = v_profile or b.runner_id = v_profile);
        if v_course_runs = 10 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 200, 'patch_gold', p_booking);
        elsif v_course_runs = 25 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 500, 'patch_master', p_booking);
        end if;
      end loop;
    end if;
  end if;

  -- 러너 스탯 — total_km은 실주행이니 항상, total_runs는 완주만
  update runners set
    total_runs = total_runs + (case when v_is_full then 1 else 0 end),
    total_km = coalesce(total_km, 0) + p_actual_km
  where profile_id = v_runner
  returning total_runs into v_total_runs;

  -- [0028 ⑤] completion_rate 실화 — 0001 정책 주석 그대로: 러너 개인 사유 종료만 반영
  -- (dog_condition/owner_* 무영향). 완주 / (완주 + runner_personal). 모수 0이면 null 유지.
  update runners set completion_rate = sub.rate
  from (
    select case when count(*) = 0 then null
      else round(count(*) filter (where r.end_reason = 'completed')::numeric / count(*), 3) end as rate
    from runs r join bookings b on b.id = r.booking_id
    where b.runner_id = v_runner and r.end_reason in ('completed', 'runner_personal')
  ) sub
  where profile_id = v_runner;

  -- 드랍 판정 + 롤 — 10회 픽 우선, 5회 미니 (settle-run JS 롤과 동일 확률)
  if v_is_full and v_total_runs % 10 = 0 then
    v_drop := jsonb_build_object('kind', 'pick',
      'contents', jsonb_build_object('options', jsonb_build_array('boost', 'miles', 'gear')));
  elsif v_is_full and v_total_runs % 5 = 0 then
    v_miles := 500 + floor(random() * 700)::int;
    v_roll := random();
    v_drop := jsonb_build_object('kind', 'mini', 'contents',
      jsonb_build_object('miles', v_miles)
      || case when v_roll < 0.10 then jsonb_build_object('card', '드랍 카드')
              when v_roll < 0.15 then jsonb_build_object('gear', '기어 교환권')
              else '{}'::jsonb end);
  end if;
  if v_drop is not null then
    -- [0028] jsonb ->> 는 text — drop_type 이넘 명시 캐스트
    insert into drops (runner_id, run_count_at, kind, contents)
    values (v_runner, v_total_runs, (v_drop->>'kind')::drop_type, v_drop->'contents');
  end if;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_owner, 'booking', '러닝 완료',
          round(p_actual_km, 2)::text || 'km 러닝이 끝났어요 — 리포트를 확인하세요', p_booking);

  return jsonb_build_object('total_runs', v_total_runs, 'drop', v_drop->>'kind');
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- THE ACL — restated verbatim from the file that last set it (`0083:838`), never inherited
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A `create or replace` preserves owner and ACL ONLY where the function already exists; on an
-- apply path where it does not (a partial prior apply, a cherry-pick, a rebuilt environment) the
-- statement above is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable (`0116:636`).
-- The line below is the one from `0083:838`, character for character, so this file decides the ACL
-- on EVERY apply path rather than on the lucky one. No grant accompanies it: `service_role` holds
-- EXECUTE through Supabase's default privileges, which a revoke naming only public/anon/
-- authenticated does not touch (`0057:59-62`), and that is the shipped shape this function has had
-- since 0020 — widening it here would be a security change wearing a restatement's costume.
revoke execute on function settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int) from public, anon, authenticated;

comment on function settle_run_tx is
  '0169 (was 0083 §6): 정산 원자 트랜잭션 — 0083 본문 그대로에 거절 하나만 앞에 붙었다.
[0169] 두 단계 정지의 SQL 벨트: run_stopping_at 이 찍혔고 run_ended_at 이 아직 NULL 인 예약(=0168 의
stopping 국면, handler.ts:94 와 같은 술어)은 run_stopping 으로 거절한다 — 숫자가 아직 얼지 않았으므로
호출자가 들고 온 클라이언트 숫자로 정산하면 0168 이 없애려던 결함이 문만 바꿔 되살아난다. 거절은
당사자 게이트(not_found) 다음, 씰 게이트ⓑ·동결 게이트ⓔ·모든 상태 변경보다 앞에 있다. 90~150초 뒤
club_finalize_stopped_runs() 가 얼리면 같은 호출이 그대로 성공한다(막다른 길이 아니다).
[0083] ⓑ 귀가 씰 게이트 · ⓒ ended_at 은 서비스 정지 시각 · ⓓ 돈이 움직인 시각은 settled_at ·
ⓔ 동결 강제(frozen_measurement_mismatch) 는 전부 0083 그대로이며 0168 의 VERIFY 가 이 본문에서
ⓔ 를 읽는다(0168:1016-1027).';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — at apply time, positive AND negative, with the source read COMMENT-STRIPPED
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ Comments are stripped before every match, for this repo's most-repeated structural reason:
--   `prosrc` is source PLUS our own prose, and this file argues about `run_stopping` at length in
--   the comments INSIDE the function's own neighbourhood. An un-stripped check for RAISING it
--   would be satisfied by a comment EXPLAINING it — the more carefully documented, the more
--   certainly green.
-- ⚠ Every arm asserts an exact boolean (`is not true` / `is distinct from`), never a bare `IF`:
--   plpgsql does not take an `IF` on a NULL predicate, so a bare `if <expr>` is SILENT precisely
--   when the source is missing — which is the case every arm here exists to notice. Hence the
--   loud NO-SOURCE arm first.
do $$
declare
  v_src text; v_bad text := ''; v_gate int; v_mut int;
begin
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'settle_run_tx';
  if v_src is null then
    raise exception '0169 VERIFY: NO-SOURCE(settle_run_tx) — 함수가 없거나 이름이 바뀌었다';
  end if;

  -- ① the belt is IN the deployed body, raised by name
  if (v_src ~ 'raise exception ''run_stopping''') is not true
    then v_bad := v_bad || ' 🔴 settle_run_tx-has-NO-run_stopping-refusal'; end if;
  -- ② and it reads 0168's phase, both halves. `run_ended_at is null` alone would refuse every
  --    club settle for ever, because the freeze never clears the stamp (0168:589-600).
  if (v_src ~ 'v_run_stopping is not null and v_run_ended is null') is not true
    then v_bad := v_bad || ' 🔴 belt-does-not-read-0168s-phase (both halves)'; end if;

  -- ③ POSITION — before the first state mutation. `for update;` cannot match: the pattern needs
  --    `update <ident> set`, and `do update set` inside the on-conflict is later regardless.
  v_gate := coalesce(regexp_instr(v_src, 'raise exception ''run_stopping'''), 0);
  v_mut  := coalesce(regexp_instr(v_src, '(update[[:space:]]+[a-z_]+[[:space:]]+set|insert[[:space:]]+into)'), 0);
  if v_gate <= 0 then v_bad := v_bad || ' belt-position-unmeasurable(no-gate)'; end if;
  if v_mut  <= 0 then v_bad := v_bad || ' belt-position-unmeasurable(no-mutation-found)'; end if;
  if (v_gate > 0 and v_mut > 0 and v_gate < v_mut) is not true
    then v_bad := v_bad || ' 🔴 belt-AFTER-the-first-mutation gate=' || v_gate || ' mut=' || v_mut; end if;

  -- ④ the base was not silently trimmed — 0168's VERIFY reads both of these out of THIS body
  --    (0168:1016-1027), so losing one here would redden 0168 on the next apply and, worse, would
  --    mean this file replaced the freeze enforcement with a stopping gate rather than adding one.
  if (v_src ~ 'frozen_measurement_mismatch') is not true
    then v_bad := v_bad || ' 🔴 settle_run_tx-LOST-the-freeze-gate (0083 ⓔ)'; end if;
  if (v_src ~ 'when v_run_ended is null then excluded\.actual_km') is not true
    then v_bad := v_bad || ' 🔴 settle_run_tx-LOST-freeze-preservation (R-2 reopened)'; end if;
  if (v_src ~ 'return_not_sealed') is not true
    then v_bad := v_bad || ' 🔴 settle_run_tx-LOST-the-seal-gate (0083 ⓑ)'; end if;

  -- ⑤ the envelope: definer, in-body search_path (ALTER-applied config is reset by every
  --    `create or replace` — 98 H1's standing invariant), and the ACL on EVERY apply path
  if (select p.prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'settle_run_tx') is distinct from true
    then v_bad := v_bad || ' 🔴 not-SECURITY-DEFINER'; end if;
  -- ⚠ read from `proconfig`, NOT from `prosrc`: `prosrc` is the body BETWEEN the dollar quotes and
  --   the `set search_path` rides on the CREATE header, so a `prosrc ~ 'search_path'` check is
  --   false on a perfectly correct function — measured here on the first apply of this file, and
  --   it is 98 H1's own instrument (`98_hardening_suite.sql:56`).
  if (select coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'
        and coalesce(array_to_string(p.proconfig, ','), '') like '%pg_temp%'
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'settle_run_tx') is not true
    then v_bad := v_bad || ' 🔴 in-body-search_path-missing (public, pg_temp)'; end if;
  if has_function_privilege('public',
       'public.settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int)', 'EXECUTE')
     is distinct from false then v_bad := v_bad || ' 🔴 settle_run_tx-PUBLIC-executable'; end if;
  if has_function_privilege('anon',
       'public.settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int)', 'EXECUTE')
     is distinct from false then v_bad := v_bad || ' 🔴 settle_run_tx-anon-executable'; end if;
  if has_function_privilege('authenticated',
       'public.settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int)', 'EXECUTE')
     is distinct from false then v_bad := v_bad || ' 🔴 settle_run_tx-authenticated-executable'; end if;
  if has_function_privilege('service_role',
       'public.settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int)', 'EXECUTE')
     is distinct from true then v_bad := v_bad || ' settle_run_tx-service_role-LOST-execute (over-reach)'; end if;

  if v_bad <> '' then raise exception '0169 VERIFY:%', v_bad; end if;
  raise notice '0169: settle_run_tx now refuses a stopping booking by name (run_stopping), after the party gate and before every state mutation; 0083 ⓑ/ⓔ and the freeze preservation are intact and the ACL is restated rather than inherited';
end $$;
