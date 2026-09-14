-- ═══ 0168: the run-end TWO-PHASE STOP — the host's tap stops the clock, a sweep freezes the money ═══
--
-- Builds `docs/contracts/run-end-two-phase-stop-contract.md` (codex GPS finding 4, the one 0156's
-- own header says it does NOT close: 「the stale-trace race needs a two-phase stop … Do not read
-- this migration as closing 4」, `0156:21-24`).
--
-- 🔴 **LIVE MONEY, UN-FLAG-GATED, AND DELIBERATELY SO.** The owner's COLLECTION is behind
--    `ops_flags.payments_live_since` (`settle-run/handler.ts:320-322`), but the RUNNER's
--    `ledger_items` row is not (`0083:754`). A flag on this fix would leave the defect live in
--    exactly the state it is live in now (contract §7).
--
-- ── THE DEFECT, IN ONE SENTENCE ────────────────────────────────────────────────────────────
-- The host taps 러닝 종료 at 12:00:00 and the server prices whatever trace has ARRIVED, while the
-- runner's phone is holding up to a full 60 s upload interval of real GPS that has not been sent
-- yet (`club/run/[sid].tsx:285` is the only uploader and it is a 60 s `setInterval`). The booking
-- stays `active`, so that tail lands in `runs.trace` after the price is immutable and is paid for
-- by nobody. Bounded by the 8 m/s billable gate at ≤480 m, ~180 m at a dog's pace.
--
-- ── THE INVARIANT (contract §2) ────────────────────────────────────────────────────────────
--   A run's priced distance is derived from a trace that can no longer change, and no ledger row
--   exists for a run whose trace is still changing.
--
-- ── THE STATE MACHINE, SIX LINES ───────────────────────────────────────────────────────────
--   active                      run_stopping_at ∅ · run_ended_at ∅   trace accepted
--   → host taps 러닝 종료       run_stopping_at = tap · run_ended_at ∅   trace STILL accepted (drain)
--   → tap + 90 s               drain closed: trace refused by name (`run_stopping`)
--   → sweep (every minute)     km derived with cutoff = THE TAP · freeze written
--   frozen                     run_stopping_at set · run_ended_at = THE TAP   settle released
--   deferred                   derivation unusable ⇒ stays `stopping`, no freeze, NO ledger row
--
-- ── 🔴 THE THREE ESCALATIONS, EACH OF WHICH IS A WAY TO BUILD THIS AND MAKE IT WORSE ───────
--
-- **① `_club_derive_run_km` MUST TAKE THE CUTOFF AS A PARAMETER** (contract §4.3, and the
--    highest-risk item in the slice). 0156's money guard bounds the window at `now()` and argues
--    for it verbatim: the function 「is called only from `club_end_pack_runs` inside the freeze
--    transaction, so `now()` here IS the host's tap」 (`0156:16-20`, `:162-164`). **Two-phase
--    makes that sentence false** — phase 2 runs 90+ s later, so `now()` there is the SWEEP's
--    clock and 0156's guard would silently widen the paid window by the whole drain. A file that
--    never mentions 0156 would have reverted it. So the cutoff is threaded, the 2-arg form is
--    DROPPED rather than left as a dead `now()`-bounded door, and 0156's 60 s grace and 300 s
--    coverage gate are carried across byte-for-byte.
--
-- **② PHASE 1 MUST NOT STAMP `bookings.run_ended_at`** (contract §3). Two measured reasons:
--    · `settle-run/handler.ts:90` keys the entire frozen path on it and `readFrozenRun` (`:264-280`)
--      does `Number(data.actual_km)` — **`Number(null) === 0`** — with every band/floor check
--      skipped on that path. Stamping it before km exists turns an under-payment into a **0 km
--      settlement**. That is the 「loading is not 0」 law with money attached.
--    · `0159:148-154` closes the pack map channel for club bookings on `run_ended_at is not null`.
--      Stamping at phase 1 kills the owner's live map while the run is still being recorded.
--    `run_ended_at` therefore keeps its exact current meaning: **the numbers are frozen.**
--
-- **③ `club_delegation_board.runEnded` MUST NOT BE WIDENED** to cover `stopping` (contract §4.4).
--    Widening lets `club/run/[sid].tsx:300` permit a GPS-denied settle while no server numbers
--    exist, and makes `:594` hide the early-end reasons for a run that is not frozen. Both callers
--    are correct today and both break with no edit. A SEPARATE key `runStopping` is added instead.
--
-- ── WHY A CRON SWEEP AND NOT THE CLIENT'S ACK (contract §3) ────────────────────────────────
-- The run screen has NO poll — `load()` runs on `useFocusEffect` (`club/run/[sid].tsx:164`) and
-- after a settle (`:342`). A backgrounded phone never learns the run is stopping and can never
-- ack, so an ack-triggered phase 2 would strand every run whose runner's phone is in a pocket —
-- the ORDINARY case. **A sweep answers INACTION**, which is what this repo's doctrine requires.
--
-- ── WHERE THIS FILE DIVERGES FROM THE CONTRACT, SAID OUT LOUD ──────────────────────────────
-- Contract §4.2 and §5 disagree about which list a phase-1 pairing is reported in: §4.2 says
-- 「keep the three-list shape; add a `phase`; make km/durationSec explicitly null at phase 1」
-- (with the caller consequence spelled out — `api.ts:4323`'s non-null `km` must widen), while
-- §5's table calls `stop_pending` a new `blocked.reason`. **§4.2 wins here**, for a reason from
-- 0144's own header: `blocked` means 「this dog's run did not end and SOMEBODY MUST ACT」
-- (`0144:281-285`), and nobody must act on a run that is draining normally. §5's sentence
-- 「기록을 모으는 중이에요 — 곧 확정돼요」 is delivered at §5's render location (the host console
-- result list) off `ended[].phase = 'stopping'`, so the copy contract is met without lying about
-- the list's meaning. A second tap inside the drain lands in `already` as `already_stopping`.
--
-- `settle_run_tx` is NOT recreated here, and that is a scope decision rather than an omission.
-- Contract §4.6 asks for a `run_stop_pending` refusal inside it; the reachable door is the edge
-- function (`settle_run_tx` is revoked from `authenticated` at `0083:838`, so only `service_role`
-- can call it and `settle-run/handler.ts` is the only caller in the tree), and the refusal is
-- implemented there in the same slice. Re-creating a 210-line money function to add one gate on a
-- path no client can reach would be a far larger risk than the hole it closes. **NAMED GAP:** a
-- direct `service_role` caller can still settle a `stopping` booking at the CLIENT's numbers.
--
-- ── SEAN'S OPEN QUESTIONS — every constant below is PROVISIONAL and marked at its line ──────
--   §8.1 drain window   → 90 s   (recommended (ii): 60 s is the tick interval itself)
--   §8.2 a tail after the freeze → never credited, refused BY NAME and shown to the runner
--   §8.3 phone offline for the whole window → the run STAYS `stopping`; no ledger row, no
--        client-priced fallback. (i) would restore exactly the client-priced ledger this slice
--        exists to remove.
--   §8.4 sweep granularity → every minute, so the real window is 90–150 s. Only the LOWER bound
--        is pinned (never freeze before tap + 90 s).

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE COLUMN — a third state on the booking, and NOT a reuse of run_ended_at
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ `_guard_booking_cols` (`0058:263`) is deny-ALL for `authenticated`/`anon` — it refuses any
-- change to any column from a client role and therefore covers this new one automatically. Every
-- writer below is a SECURITY DEFINER owned by postgres, so `current_user` never enters that arm.
alter table bookings add column if not exists run_stopping_at timestamptz;

comment on column bookings.run_stopping_at is
  '0168 — 호스트가 러닝 종료를 누른 시각. 이것만으로는 아무것도 동결되지 않는다: 러너의 폰이 아직
보내지 못한 마지막 구간을 90초 동안 더 받아들이는 배수 창이 열리고(club_save_run_trace), 창이 닫힌
뒤 club_finalize_stopped_runs()가 그 탭 시각을 컷오프로 km을 도출해 run_ended_at과 함께 동결한다.
run_ended_at은 지금까지의 뜻을 그대로 지킨다 — 「숫자가 얼었다」. 여기서 run_ended_at을 미리 찍으면
settle-run이 Number(null)===0 으로 0km 정산을 만들고(handler.ts:90,264-280) 0159의 팩 지도 채널이
러닝 도중에 닫힌다(0159:148-154).';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  THE CUTOFF BECOMES A PARAMETER — escalation ①
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0156 §B's body verbatim, with ONE change: `v_t1` is derived from the caller's cutoff instead of
-- from `now()`. The 60 s grace and the 300 s coverage gate are 0156's and are unchanged in value
-- and in argument — read `0156:155-170` and `:204-208` for why each exists; nothing here revisits
-- them, and the 300 s threshold is still Sean's to rule on.
--
-- ⚠ THE 2-ARG FORM IS DROPPED, NOT LEFT AS AN OVERLOAD. Its sole caller was `0144:427` and this
-- file replaces that call site. Leaving it in place would leave a `now()`-bounded money door with
-- no caller and no pin — dead code that a later session would reach for precisely because it has
-- the shorter signature. `drop function` on a helper that is revoked from every role (`0156:213`)
-- costs nothing; the VIEW rule (never DROP) does not apply to functions.
-- ⚠ Suite 187's three call sites and its ACL arm are updated in this same slice, with the cutoff
-- passed explicitly as `now()` — which is what those fixtures already meant.
drop function if exists public._club_derive_run_km(jsonb, timestamptz);

create or replace function public._club_derive_run_km(
  p_trace   jsonb,
  p_started timestamptz,
  p_cutoff  timestamptz
)
returns numeric
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_t0   numeric;
  v_t1   numeric;
  v_pts  jsonb;
  v_n    int;
  i      int;
  v_prev jsonb;
  v_cur  jsonb;
  v_psec numeric;
  v_csec numeric;
  v_dt   numeric;
  v_d    numeric;
  v_km   numeric := 0;
  v_gap  numeric := 0;
  c_max_gap_sec constant numeric := 300;
  c_tap_grace_sec constant numeric := 60;
begin
  if p_trace is null or p_started is null or p_cutoff is null then return null; end if;
  if jsonb_typeof(p_trace) <> 'array' then return null; end if;
  v_t0 := extract(epoch from p_started);
  v_t1 := extract(epoch from p_cutoff) + c_tap_grace_sec;

  select jsonb_agg(e order by (e->>'t')::numeric)
    into v_pts
    from jsonb_array_elements(p_trace) e
   where jsonb_typeof(e) = 'object'
     and (e->>'t')   is not null
     and (e->>'lat') is not null
     and (e->>'lng') is not null
     and (e->>'t')::numeric >= v_t0
     and (e->>'t')::numeric <= v_t1;

  if v_pts is null then return null; end if;
  v_n := jsonb_array_length(v_pts);
  if v_n < 2 then return null; end if;

  v_prev := v_pts->0;
  v_psec := floor((v_prev->>'t')::numeric);
  for i in 1 .. v_n - 1 loop
    v_cur  := v_pts->i;
    v_csec := floor((v_cur->>'t')::numeric);
    if v_csec > v_psec then
      v_dt := v_csec - v_psec;
      if v_dt > v_gap then v_gap := v_dt; end if;
      v_d  := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
      if v_d > 2 and v_d < 120 and v_d / v_dt <= 8 then
        v_km := v_km + v_d / 1000;
      end if;
      v_prev := v_cur;
      v_psec := v_csec;
    end if;
  end loop;

  if v_gap > c_max_gap_sec then return null; end if;

  return round(v_km, 2);
end $$;

-- Server-only, exactly as 0156:213-214 left it: this function takes a caller-supplied trace and
-- has no party gate of its own. Written out rather than relied upon — a `create or replace` on an
-- apply where the function is absent is a plain CREATE and is born PUBLIC-executable (0116:636).
revoke execute on function _club_derive_run_km(jsonb, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;

comment on function public._club_derive_run_km(jsonb, timestamptz, timestamptz) is
  '0168 §B — 0156 §B 본문 + 컷오프를 파라미터로. 0156 은 「이 함수는 프리즈 트랜잭션 안에서만 불리므로
now() 가 곧 호스트의 탭」이라는 근거로 상한을 now() 로 두었는데, 두 단계 정지는 그 문장을 거짓으로 만든다
— 2단계는 90초 뒤 스윕의 시계에서 돌기 때문이다. 컷오프는 이제 호출자가 넘기는 **탭 시각**이고, 60 초
여유와 300 초 커버리지 게이트는 0156 의 것 그대로다 (300 초는 여전히 Sean 의 판단 사항).';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  PHASE 1 — `club_end_pack_runs` marks the pack `stopping`. It freezes nothing.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0144 §B's body, with the derivation-and-freeze branch replaced by one stamp. EVERYTHING ELSE IS
-- 0144's and is preserved deliberately: best-effort per-pairing subtransactions, the three named
-- lists, the host-OR-backup gate with its two `is distinct from` arms, the one clock `v_at`, the
-- session lock, the deterministic order, the 2 s `lock_timeout`, the `when others` warning.
-- Read `0144:269-289` and `:314-345` for why each is shaped that way; nothing here revisits it.
--
-- ⚠ THE TWO NOTIFICATIONS MOVED TO PHASE 2, and that is a correctness change rather than a tidy.
-- 0144 sent the runner 「기록이 준비됐어요, 마무리해주세요」 from the tap. Under two-phase the record
-- is NOT ready at the tap — it is ready when the sweep freezes it, and telling a runner to settle
-- a run that will refuse them is the dead-button law wearing a push notification.
--
-- ⚠ `no_trace` AND `km_out_of_band` ARE NO LONGER PHASE-1 VERDICTS, and they could not be. Both
-- require a derivation, and the whole point of the drain is that the trace is not final yet — the
-- dog whose trace is EMPTY at the tap is exactly the case the drain exists to rescue (a phone
-- whose uploads have been failing sends its whole buffer on the next tick). They become phase-2
-- outcomes; suite 176's P3 is updated in this slice to say so.
create or replace function public.club_end_pack_runs(p_session uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s        record;
  r        record;
  v_bk     record;
  v_at     timestamptz;
  v_ended  jsonb := '[]'::jsonb;
  v_block  jsonb := '[]'::jsonb;
  v_alrdy  jsonb := '[]'::jsonb;
  v_verd   text;
  v_reason text;
  v_inc    uuid;
  v_has    boolean;
  v_start  timestamptz;
  v_rend   timestamptz;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  select cs.id, cs.host_profile_id, cs.backup_host_profile_id, cs.status
    into s
  from club_sessions cs where cs.id = p_session for update;
  if s.id is null then raise exception 'not_host'; end if;

  if auth.uid() is distinct from s.host_profile_id
     and auth.uid() is distinct from s.backup_host_profile_id then
    raise exception 'not_host';
  end if;
  if s.status not in ('open', 'full') then raise exception 'session_closed'; end if;

  v_at := now();

  perform set_config('lock_timeout', '2000', true);

  for r in
    select sd.id as sd_id, sd.dog_id, sd.booking_id, d.name as dog_name
      from session_dogs sd
      join dogs d      on d.id = sd.dog_id
      join bookings b  on b.id = sd.booking_id
     where sd.session_id = p_session
       and sd.custody = 'runner_delegated'
       and sd.booking_id is not null
       and b.club_session_id = sd.session_id
     order by sd.id
  loop
    v_verd := 'ended'; v_reason := null; v_inc := null;

    begin
      select bk.id, bk.status::text as status, bk.run_ended_at, bk.run_stopping_at,
             bk.runner_id, bk.owner_id
        into v_bk
      from bookings bk where bk.id = r.booking_id for update;

      select true, rn.started_at, rn.ended_at
        into v_has, v_start, v_rend
      from runs rn where rn.booking_id = r.booking_id for update;

      if v_bk.id is null then
        v_verd := 'blocked'; v_reason := 'not_found';

      elsif v_bk.status = 'completed' then
        v_verd := 'already'; v_reason := 'already_settled';
      elsif v_bk.run_ended_at is not null or v_rend is not null then
        v_verd := 'already'; v_reason := 'already_ended';

      -- A second tap inside the drain window. Nothing to do and nobody to chase: the first tap's
      -- instant is the one the money will be measured to, and it is already recorded.
      elsif v_bk.run_stopping_at is not null then
        v_verd := 'already'; v_reason := 'already_stopping';

      elsif v_bk.status = 'picked_up' then
        v_verd := 'blocked'; v_reason := 'not_started';

      elsif v_bk.status <> 'active' then
        v_verd := 'blocked'; v_reason := 'not_active';

      else
        select i.id into v_inc
          from club_incident_subjects sub
          join club_incidents i on i.id = sub.incident_id
         where i.state <> 'resolved'
           and i.session_id = p_session
           and ((sub.subject_type = 'dog'     and sub.subject_id = r.dog_id)
             or (sub.subject_type = 'booking' and sub.subject_id = r.booking_id))
         order by i.id
         limit 1;

        if v_inc is not null then
          v_verd := 'blocked'; v_reason := 'incident_open';
        elsif not coalesce(v_has, false) or v_start is null then
          v_verd := 'blocked'; v_reason := 'not_started';
        else
          -- ═══ PHASE 1. ONE COLUMN, AND NOT THE OTHER ONE. ══════════════════════════════════
          -- The conjuncts are the idempotency key, read and written under the row lock taken
          -- above: a concurrent tap that won the race leaves this UPDATE matching zero rows and
          -- the pairing is reported by the branch above on the next call.
          update bookings set run_stopping_at = v_at
           where id = r.booking_id and run_stopping_at is null and run_ended_at is null;
        end if;
      end if;

    exception
      when lock_not_available then
        v_verd := 'blocked'; v_reason := 'locked';
      when others then
        v_verd := 'blocked'; v_reason := 'error';
        raise warning 'club_end_pack_runs: pairing % — % %', r.sd_id, sqlstate, sqlerrm;
    end;

    if v_verd = 'ended' then
      -- 🔴 `km` and `durationSec` are explicitly NULL, never 0. Phase 1 does not know them and a
      -- zero here would be read as a measurement by every consumer of this payload.
      v_ended := v_ended || jsonb_build_object(
        'sdId', r.sd_id, 'bookingId', r.booking_id, 'runnerId', v_bk.runner_id,
        'dogId', r.dog_id, 'dogName', r.dog_name,
        'phase', 'stopping', 'km', null::numeric, 'durationSec', null::int);
    elsif v_verd = 'already' then
      v_alrdy := v_alrdy || jsonb_build_object(
        'sdId', r.sd_id, 'dogId', r.dog_id, 'dogName', r.dog_name, 'reason', v_reason);
    else
      v_block := v_block || jsonb_build_object(
        'sdId', r.sd_id, 'dogId', r.dog_id, 'dogName', r.dog_name,
        'reason', v_reason, 'incidentId', v_inc);
    end if;
  end loop;

  return jsonb_build_object(
    'session', p_session,
    'at',      v_at,
    'phase',   'stopping',
    'ended',   v_ended,
    'blocked', v_block,
    'already', v_alrdy);
end $$;

revoke execute on function public.club_end_pack_runs(uuid) from public, anon, service_role;
grant  execute on function public.club_end_pack_runs(uuid) to authenticated;

comment on function public.club_end_pack_runs is
  '0168 §C — 러닝 종료 1단계. 호스트(또는 백업 호스트)의 한 번의 탭이 세션의 모든 위탁 페어를
bookings.run_stopping_at 으로 표시한다. **아무것도 동결하지 않는다**: 러너의 폰이 아직 보내지 못한
마지막 구간이 90초 배수 창 동안 더 올라오고, 그 뒤 club_finalize_stopped_runs() 가 이 탭 시각을
컷오프로 거리를 도출해 동결한다. run_ended_at 을 여기서 찍으면 settle-run 이 Number(null)===0 으로
0km 정산을 만들고 팩 지도 채널이 러닝 도중에 닫힌다. 반환은 0144 의 세 리스트 그대로이고 ended 의
km·durationSec 은 **명시적 null** 이다 — 0 이 아니다. 호스트+백업만. 돈은 여전히 이 함수 밖이다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  INGEST — the drain window, and its terminator
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0156 §A's body verbatim, plus ONE state gate. Contract §3 chose (b) bounded drain with (a) as
-- the window's terminator, and the argument is worth keeping here: **pure (a) throws away a full
-- upload interval of real, honest GPS on every run and under-pays every runner by design** — the
-- defect's own direction, made permanent. 90 s and not 60 s because the client re-sends the WHOLE
-- buffer each tick (`build(trace.current)`, `[sid].tsx:275`; the server appends by `t > last_t`),
-- so ONE tick inside the window suffices — and a tap landing 1 s after a tick needs 59 s plus a
-- round trip, which 60 s gives no margin for.
--
-- ⚠ THE REFUSAL IS BY NAME AND IT IS THE POINT. A late tail that is silently dropped is
-- indistinguishable, to the runner, from one that was counted. `run_stopping` gets its own banner
-- on the run screen in this same slice — the `saveLag` banner says 「자동 재시도해요」, and a
-- PERMANENT refusal shown as 「will retry automatically」 is a lie the client tells with no change
-- on our side (contract §4.1).
--
-- ⚠ THE GATE IS A STATE GATE AND IT SITS AFTER THE PARTY GATE, per the repo law. It reads only
-- bookings whose `runner_id` is the caller, so it is not an oracle about anybody else's run.
create or replace function club_save_run_trace(p_session uuid, p_trace jsonb) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  n int; v_prev jsonb; v_cur jsonb; v_dt numeric; v_dist numeric; i int;
  v_run runs%rowtype; v_existing jsonb; v_last_t numeric; v_add jsonb; v_merged jsonb;
  v_now numeric; v_max_t numeric;
  c_future_slack_sec constant numeric := 3600;
  -- PROVISIONAL (Sean §8.1). The same constant governs the sweep's eligibility below; the two
  -- must agree or a point is refused by one and awaited by the other.
  c_drain_sec constant numeric := 90;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if jsonb_typeof(coalesce(p_trace, 'null'::jsonb)) <> 'array' then raise exception 'bad_trace'; end if;

  -- 🔴 THE DRAIN WINDOW'S TERMINATOR. Asserted on an EXISTS over the caller's own rows, so the
  -- answer cannot be NULL and the guard cannot go silent.
  if exists (
    select 1 from bookings b
     where b.club_session_id = p_session
       and b.runner_id = auth.uid()
       and b.status = 'active'
       and (b.run_ended_at is not null
            or (b.run_stopping_at is not null
                and now() > b.run_stopping_at + interval '1 second' * c_drain_sec))
  ) then
    raise exception 'run_stopping';
  end if;

  v_now := extract(epoch from now());
  select max((e->>'t')::numeric) into v_max_t
    from jsonb_array_elements(p_trace) e
   where jsonb_typeof(e) = 'object' and (e->>'t') is not null;
  if v_max_t is not null and v_max_t > v_now + c_future_slack_sec then
    raise exception 'trace_future_fix';
  end if;

  for i in 1..coalesce(jsonb_array_length(p_trace), 0) - 1 loop
    v_prev := p_trace->(i - 1); v_cur := p_trace->i;
    v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
    if v_dt <= 0 then raise exception 'trace_out_of_order'; end if;
    v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                 + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
    if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
  end loop;

  n := 0;
  for v_run in
    select r.* from runs r join bookings b on b.id = r.booking_id
    where b.club_session_id = p_session and b.runner_id = auth.uid() and b.status = 'active'
      -- the OPEN half of the same rule the refusal above closes: a frozen run takes nothing more,
      -- and a stopping run keeps taking points until its window shuts.
      and b.run_ended_at is null
      and (b.run_stopping_at is null
           or now() <= b.run_stopping_at + interval '1 second' * c_drain_sec)
  loop
    v_existing := coalesce(v_run.trace, '[]'::jsonb);
    if jsonb_typeof(v_existing) <> 'array' then v_existing := '[]'::jsonb; end if;
    if jsonb_array_length(v_existing) = 0 then
      v_merged := p_trace;
    else
      v_last_t := (v_existing->(jsonb_array_length(v_existing) - 1)->>'t')::numeric;
      select jsonb_agg(e order by (e->>'t')::numeric)
        into v_add
        from jsonb_array_elements(p_trace) e
        where (e->>'t')::numeric > v_last_t;
      if v_add is null or jsonb_array_length(v_add) = 0 then
        v_merged := v_existing;
      else
        v_cur := v_add->0;
        v_prev := v_existing->(jsonb_array_length(v_existing) - 1);
        v_dt := (v_cur->>'t')::numeric - (v_prev->>'t')::numeric;
        v_dist := sqrt(power(((v_cur->>'lat')::numeric - (v_prev->>'lat')::numeric) * 111000, 2)
                     + power(((v_cur->>'lng')::numeric - (v_prev->>'lng')::numeric) * 88800, 2));
        if v_dist / v_dt > 8 then raise exception 'impossible_speed'; end if;
        v_merged := v_existing || v_add;
      end if;
    end if;
    update runs set trace = v_merged where id = v_run.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- 0038:291 granted this to `authenticated`; restated explicitly, never relied upon. Written
-- UNQUALIFIED to match `check-definer-acl.mjs:118`'s pattern (0156:122-125's note).
revoke execute on function club_save_run_trace(uuid, jsonb) from public, anon;
grant  execute on function club_save_run_trace(uuid, jsonb) to authenticated;

comment on function club_save_run_trace is
  '0168 §D — 0156 §A 본문 + 배수 창. 호스트가 러닝 종료를 누른 뒤에도 90초 동안은 러너의 마지막 구간을
계속 받는다 (클라는 매 틱 버퍼 전체를 다시 보내므로 창 안의 한 번이면 충분하다). 창이 닫히거나 숫자가
이미 동결된 뒤의 업로드는 조용히 버려지지 않고 run_stopping 으로 **이름을 붙여 거절**된다 — 러너의
화면이 그 거절에 전용 배너를 가진다. 미래 시각 거부(trace_future_fix)와 8 m/s·단조성 검사는 0156 그대로.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  PHASE 2 — the sweep. Idempotent, and it answers INACTION.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 **THE FREEZE CLOCK IS THE TAP, NOT THE SWEEP.** `runs.ended_at` is the service-stop instant
--    and is the CHARGING CUTOVER (`mint_settle_charge_intent` compares `coalesce(r.ended_at,
--    now())` against `ops_flags.payments_live_since`), and Sean's ruling ③ says duration is
--    measured to the host's tap. So every one of the four values this function writes —
--    `ended_at`, `run_ended_at`, `duration_sec`, and the cutoff handed to the derivation — is
--    `run_stopping_at`. The run stopped when the host tapped; the freeze merely records it late.
--
-- ⚠ **THE FREEZE IS STILL BOTH STATEMENTS OR NEITHER** (0144 §0a R-2, unchanged and still the
--   single most load-bearing sentence in this family). Half of it is worse than none in BOTH
--   directions: the stamp alone and the device wins again; the `runs` row alone, or a stamp over
--   a NULL km, and every club settle raises `frozen_measurement_mismatch` forever. A pairing whose
--   number cannot be derived is therefore left COMPLETELY unfrozen.
--
-- ⚠ **A PAIRING THE DERIVATION CANNOT ANSWER STAYS `stopping` — Sean §8.3 (ii), PROVISIONAL.**
--   It is not frozen, it mints nothing, and it is returned by name in `pending` so an ops surface
--   can show it. The rejected option (i) — let the runner settle on their own client numbers — is
--   exactly the client-priced ledger this slice exists to remove, restored at the one point where
--   we have the least evidence.
create or replace function public.club_finalize_stopped_runs()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r        record;
  v_bk     record;
  v_has    boolean;
  v_start  timestamptz;
  v_rend   timestamptz;
  v_trace  jsonb;
  v_km     numeric;
  v_dur    int;
  v_stop   timestamptz;
  v_fin    int := 0;
  v_def    int := 0;
  v_skip   int := 0;
  v_pend   jsonb := '[]'::jsonb;
  v_reason text;
  -- PROVISIONAL (Sean §8.1). Must equal §D's constant.
  c_drain_sec constant numeric := 90;
begin
  perform set_config('lock_timeout', '2000', true);

  for r in
    select b.id as booking_id, sd.id as sd_id, sd.dog_id, d.name as dog_name
      from bookings b
      -- LEFT joins on purpose: a row that lost its pairing must still be swept and reported,
      -- never silently dropped by a join that looks like a filter.
      left join session_dogs sd on sd.booking_id = b.id
      left join dogs d          on d.id = sd.dog_id
     where b.run_stopping_at is not null
       and b.run_ended_at is null
       and now() > b.run_stopping_at + interval '1 second' * c_drain_sec
     order by b.id
  loop
    v_reason := null;
    begin
      -- 🔴 THE PRECONDITION. The row LOCK is what makes every read below mean anything: without
      -- it two ticks can both pass the `run_ended_at is null` test and both write the freeze.
      select bk.id, bk.status::text as status, bk.run_ended_at, bk.run_stopping_at,
             bk.runner_id, bk.owner_id
        into v_bk
      from bookings bk where bk.id = r.booking_id for update;

      if v_bk.id is null then
        v_skip := v_skip + 1;
      -- Re-read UNDER the lock. These three are the idempotency key: a second tick, a
      -- concurrent tick, and a tick that raced the drain all land here and write nothing.
      elsif v_bk.run_ended_at is not null then
        v_skip := v_skip + 1;
      elsif v_bk.run_stopping_at is null then
        v_skip := v_skip + 1;
      elsif now() <= v_bk.run_stopping_at + interval '1 second' * c_drain_sec then
        v_skip := v_skip + 1;
      elsif v_bk.status is distinct from 'active' then
        -- cancelled, force-resolved into incident_review, or settled during the drain. There is
        -- nothing to freeze and this is not a failure.
        v_skip := v_skip + 1;
      else
        v_stop := v_bk.run_stopping_at;

        select true, rn.started_at, rn.ended_at, rn.trace
          into v_has, v_start, v_rend, v_trace
        from runs rn where rn.booking_id = r.booking_id for update;

        if not coalesce(v_has, false) or v_start is null then
          v_reason := 'not_started';
        elsif v_rend is not null then
          v_skip := v_skip + 1;
        else
          v_km := _club_derive_run_km(v_trace, v_start, v_stop);
          if v_km is null then
            v_reason := 'no_trace';
          elsif v_km < 0 or v_km > 100 then
            v_reason := 'km_out_of_band';
          else
            v_dur := greatest(1, extract(epoch from (v_stop - v_start))::int);

            update runs set
              ended_at            = v_stop,
              actual_km           = v_km,
              duration_sec        = v_dur,
              avg_pace_sec_per_km = case when v_km > 0 then round(v_dur / v_km)::int end,
              end_reason          = 'completed'::end_reason
            where booking_id = r.booking_id;

            update bookings set run_ended_at = v_stop
             where id = r.booking_id and run_ended_at is null;

            -- Moved here from the tap (§C's header): the record is ready NOW, not 90 s ago.
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_bk.owner_id, 'booking', '러닝 종료',
                    coalesce(r.dog_name, '아이') || '의 러닝이 끝났어요 — 기록을 정리하고 있어요',
                    r.booking_id);
            if v_bk.runner_id is not null then
              insert into notifications (profile_id, kind, title, body, ref_id)
              values (v_bk.runner_id, 'booking', '러닝 종료',
                      '호스트가 팩 러닝을 종료했어요 — ' || coalesce(r.dog_name, '아이') ||
                      '의 기록이 준비됐어요, 마무리해주세요', r.booking_id);
            end if;

            v_fin := v_fin + 1;
          end if;
        end if;

        if v_reason is not null then
          v_def := v_def + 1;
          v_pend := v_pend || jsonb_build_object(
            'bookingId', r.booking_id, 'sdId', r.sd_id, 'dogId', r.dog_id,
            'dogName', r.dog_name, 'reason', v_reason, 'stoppingAt', v_stop);
        end if;
      end if;

    exception
      when lock_not_available then
        v_skip := v_skip + 1;
      when others then
        v_skip := v_skip + 1;
        raise warning 'club_finalize_stopped_runs: booking % — % %', r.booking_id, sqlstate, sqlerrm;
    end;
  end loop;

  return jsonb_build_object(
    'at', now(), 'finalized', v_fin, 'deferred', v_def, 'skipped', v_skip, 'pending', v_pend);
end $$;

-- The cron runs this and nobody else does. `service_role` is named EXPLICITLY on both sides: it
-- holds EXECUTE through Supabase DEFAULT PRIVILEGES, which a revoke naming only
-- public/anon/authenticated does not touch (0057:59-62), so the grant below is what the
-- deployment actually depends on rather than an accident of defaults.
revoke execute on function public.club_finalize_stopped_runs() from public, anon, authenticated;
grant  execute on function public.club_finalize_stopped_runs() to service_role;

comment on function public.club_finalize_stopped_runs is
  '0168 §E — 러닝 종료 2단계. 배수 창(탭 + 90초)이 지난 stopping 예약을 훑어, **탭 시각**을 컷오프로
_club_derive_run_km 을 돌리고 runs.{ended_at,actual_km,duration_sec,end_reason} 와 bookings.run_ended_at
을 함께 동결한다 — 둘 다 아니면 아무것도. 시계는 스윕이 아니라 탭이다: runs.ended_at 은 과금 컷오버이고
시간은 호스트의 탭까지 재기 때문(Sean 2026-08-26 ③). 도출이 답을 못 내면 그 페어는 동결하지 않고
stopping 으로 남겨 pending 에 이름으로 돌려준다 (Sean §8.3 잠정 — 러너의 클라 숫자로 정산하게 두는 쪽은
이 슬라이스가 없애려는 바로 그 결함이다). 멱등: 행 락 아래에서 run_ended_at is null 을 다시 읽는다.
클라이언트 경로는 이 함수를 부르지 않는다 — 크론(service_role)만.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §F  THE CRON — registered, and READ BACK from `cron.job`
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0157 §A's shape, for 0157 §A's reason: `cron.schedule` returning is a CLAIM and a row in
-- `cron.job` is the FACT. No `exception` handler, deliberately — an environment with no scheduler
-- must not be allowed to believe it has one, and here that belief would mean every stopped run
-- stays `stopping` forever with no ledger row and nothing that fails.
-- ⚠ `cron.schedule` UPSERTS on (jobname, username) in pg_cron >= 1.4, so re-applying is idempotent.
-- ⚠ EVERY MINUTE, not every ten: the drain is 90 s and §8.4 accepts a real window of 90–150 s.
--   A ten-minute tick would make a runner wait up to eleven and a half minutes to settle.
do $$
begin
  perform cron.schedule('finalize-stopped-runs', '* * * * *',
                        'select club_finalize_stopped_runs()');
end $$;

do $$
declare v_n int;
begin
  select count(*)::int into v_n
    from cron.job
   where jobname = 'finalize-stopped-runs'
     and active
     and command = 'select club_finalize_stopped_runs()';
  if v_n is distinct from 1 then
    raise exception '0168 §F VERIFY: expected exactly 1 active `finalize-stopped-runs` job running `select club_finalize_stopped_runs()`, found %', coalesce(v_n::text, 'NULL');
  end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §G  THE BOARD LEARNS ABOUT THE THIRD STATE — a NEW key, never a widened one
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Escalation ③ (contract §4.4). `runEnded` means 「the numbers are frozen」 and three shipped
-- consumers read it that way — `club/run/[sid].tsx:300` (`!d.runEnded && trackMode === 'denied'`
-- gates the settle refusal), `:594` (`endTarget?.runEnded` gates the early-end reasons) and
-- `club/console/[sid].tsx:335-336` (`packRunning`/`packOther`). Widening it to cover `stopping`
-- would break all three with no edit to any of them, which is §④'s 「the defect IS the unchanged
-- line」 class. So a separate boolean is added and `runEnded` keeps its sentence exactly.
--
-- ⚠ **A BOOLEAN, AND `run_ended_at is null` IS PART OF IT.** `runStopping` answers 「this run is
--   ending and its numbers are not final」, which is FALSE once the sweep has frozen it. A bare
--   `run_stopping_at is not null` would stay true forever and every screen reading it would show
--   「정산 중」 on a run that settled an hour ago.
--
-- ⚠ **BYTE-FAITHFUL RECREATION.** The body below is 0147:60-186 with exactly one key inserted;
--   it was EXTRACTED from that file programmatically rather than retyped, because 0147's own §D
--   VERIFY only catches a key that was DROPPED, not a sub-select that was mangled in transit.
--   §H re-asserts the full key set anyway.
--
-- ⚠ **AND THE ACL IS 0153's, NOT 0147's.** 0147 granted this to `authenticated`, which was a live
--   disclosure proven by execution on production 2026-08-28 (`0153` header), and 0153 revoked it
--   WITHOUT recreating the function precisely so no grant could be re-established by accident.
--   This file DOES recreate it, so the revoke must be restated here or 0153 is silently reverted
--   by a file that never mentions it — the same shape as escalation ① one level down.

-- §G pre-check — fail closed if the deployed body is not what this file was written against
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_delegation_board_impl';
  if v_src is null then raise exception '0168 G: _club_delegation_board_impl is absent.'; end if;
  if v_src like '%''runStopping''%' then
    raise exception '0168 G: runStopping already present — this migration already applied, or someone else added it.';
  end if;
  if v_src not like '%''runEnded''%' then
    raise exception '0168 G: the runEnded anchor (0147) is not in the deployed body. Re-scout before recreating.';
  end if;
end $$;

create or replace function public._club_delegation_board_impl(p_session uuid, p_access text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
      'format', s.format, 'status', s.status,
      'routeName', (select name from routes where id = s.route_id),
      'routeKm', (select km from routes where id = s.route_id),
      'fare', (select club_fare(km) from routes where id = s.route_id),
      'delegatedCapacity', s.delegated_dog_capacity,
      'reservedCount', _club_delegated_reserved(s.id),
      'approvedCount', (select count(*) from session_dogs d
                        where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'approved'),
      'pendingCount', (select count(*) from session_dogs d
                       where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'pending'
                         and d.service_state is distinct from 'ended'),
      'isHost', s.host_profile_id = auth.uid(),
      'checkinOpen', now() between s.scheduled_at - interval '2 hours' and s.scheduled_at + interval '6 hours',
      'viability', club_session_viability(s.id),
      'openIncidents', (select count(*) from club_incidents i
                        where i.session_id = s.id and i.state <> 'resolved'),
      'unassignedIncidents', (select count(*) from club_incidents i
                              where i.session_id = s.id and i.state <> 'resolved' and i.case_owner is null)
    ),
    -- [rev2 P1] runners는 host/full에게만 (러너 실명·티어) — 그 외 등급은 []
    'runners', case when p_access in ('host', 'full') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'profileId', a.runner_profile_id,
        'name', (select name from profiles where id = a.runner_profile_id),
        'tier', (select tier::text from runners where profile_id = a.runner_profile_id),
        'cap', a.delegated_capacity,
        'assigned', (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
                     where x.session_id = s.id and x.custody = 'runner_delegated'
                       and b.runner_id = a.runner_profile_id
                       and b.status in ('confirmed', 'picked_up', 'active', 'completed')),
        'checkedIn', exists (select 1 from session_people sp
                             where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                               and sp.attendance = 'checked_in'),
        'isMe', a.runner_profile_id = auth.uid()
      ) order by a.delegated_capacity desc, a.runner_profile_id)
      from session_runner_assignments a
      where a.session_id = s.id and a.status = 'committed'), '[]'::jsonb) else '[]'::jsonb end,
    'me', jsonb_build_object(
      'committed', exists (select 1 from session_runner_assignments a
                           where a.session_id = s.id and a.runner_profile_id = auth.uid() and a.status = 'committed'),
      'runnerCap', coalesce(_club_runner_cap(auth.uid()), 0),
      'checkedIn', exists (select 1 from session_people sp
                           where sp.session_id = s.id and sp.profile_id = auth.uid() and sp.attendance = 'checked_in')
    ),
    'dogs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sdId', d.id, 'dogId', d.dog_id,
        'dogName', (select name from dogs where id = d.dog_id),
        'collar', (select collar from dogs where id = d.dog_id),
        'ownerName', (select name from profiles where id = d.owner_profile_id),
        'isMine', d.owner_profile_id = auth.uid(),
        'approval', d.approval,
        'serviceState', d.service_state,
        'completionOutcome', d.completion_outcome,
        'terminationType', d.termination_type,
        'chargeState', d.charge_state,
        'holdStatus', d.hold_status,
        'holdExpiresAt', d.hold_expires_at,
        'refundState', d.refund_state,
        'bookingId', d.booking_id,
        'bookingStatus', (select status::text from bookings b where b.id = d.booking_id),
        'runnerId', (select runner_id from bookings b where b.id = d.booking_id),
        'runnerName', (select p.name from bookings b join profiles p on p.id = b.runner_id where b.id = d.booking_id),
        'ownerConfirmed', (select owner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'runnerConfirmed', (select runner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'custodyWithRunner', d.responsible_profile_id <> d.owner_profile_id,
        'checkedOut', d.checked_out_at is not null,
        -- [0147] THE FREEZE, as a BOOLEAN not a timestamp. 0144 made the host's tap freeze a
        -- pair's money numbers server-side; the run screen could not see that, so it kept
        -- offering early-end reasons whose text settle-run DISCARDS (handler.ts:115-118 reads
        -- km/endReason/durationSec/conditionNote from the frozen row and logs 'body ignored').
        -- WARN: a boolean, deliberately. The neighbours here (ownerConfirmed, runnerConfirmed)
        -- already project "... is not null" rather than the instant, and the client's only
        -- question is whether the server has already decided. A timestamp would disclose WHEN
        -- the host tapped to every board reader and answer nothing extra.
        'runEnded', coalesce((select b.run_ended_at is not null from bookings b where b.id = d.booking_id), false),
        -- [0168] THE THIRD STATE, AS ITS OWN KEY. 러닝 종료를 눌렀지만 숫자는 아직 얼지 않았다.
        -- ⚠ `runEnded` 를 넓히지 않는다 (contract §4.4, escalation ③): 넓히면 run/[sid].tsx:300 이
        -- 서버 숫자가 없는 상태에서 GPS 거부 정산을 허용하고, :594 가 얼지도 않은 런의 조기 종료
        -- 사유를 숨긴다 — 두 호출자 모두 오늘 옳고, 한 줄도 고치지 않은 채 깨진다.
        'runStopping', coalesce((select b.run_stopping_at is not null and b.run_ended_at is null
                                   from bookings b where b.id = d.booking_id), false),
        -- [R2] 커스터디·payout 축 (디버그 스크린의 축 분리 표시 원천)
        'custodyPhase', d.custody_phase,
        'custodianType', d.custodian_type,
        'custodianProfileId', d.custodian_profile_id,
        'custodianExternal', d.custodian_external,
        'ownerReturnConfirmed', d.owner_confirmed_return_at is not null,
        'runnerReturnConfirmed', d.runner_confirmed_return_at is not null,
        'payoutState', d.payout_state,
        'payoutHold', d.payout_hold,
        'payoutHoldReason', d.payout_hold_reason,
        'pendingTransfer', d.pending_transfer,
        'returnOverrideKind', d.return_override->>'kind',
        -- [R3] 배정 축 — 제안 후보는 호스트·피제안 러너에게만 (보호자는 상태만: 러너 프라이버시)
        'assignmentState', d.assignment_state,
        'objectionUsed', d.objection_used,
        'reviewNeeded', d.review_needed,
        'proposedRunnerId', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                 then d.proposed_runner_profile_id end,
        'proposedRunnerName', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                   then (select name from profiles where id = d.proposed_runner_profile_id) end,
        'proposalExpiresAt', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                  then d.proposal_expires_at end,
        -- [0052 §1] 이 강아지를 대상으로 한 이 세션의 미해소 인시던트 (케이스 딥링크 원천)
        'openIncidentId', (select i.id from club_incidents i
                           join club_incident_subjects sub on sub.incident_id = i.id
                           where i.session_id = s.id and i.state <> 'resolved'
                             and sub.subject_type = 'dog' and sub.subject_id = d.dog_id
                           order by i.opened_at limit 1),
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        -- [0053 §4] 활성/부킹 있음 또는 **자기 것**의 rejected/withdrawn (정직한 마지막 말 도달)
        and (d.service_state is distinct from 'ended' or d.booking_id is not null
             or (d.owner_profile_id = auth.uid() and d.approval in ('rejected', 'withdrawn')))
        -- [rev2 P1] host/full=전체 · limited=자기 개만 · none=[] (both false → 제외)
        and (p_access in ('host', 'full')
             or (p_access = 'limited' and d.owner_profile_id = auth.uid()))), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$fn$;

-- 0153's ACL, restated. `service_role` is retained deliberately (the backend key); the outer
-- wrapper `club_delegation_board(uuid)` is what clients call and is untouched by this file.
revoke execute on function public._club_delegation_board_impl(uuid, text)
  from public, anon, authenticated;
grant  execute on function public._club_delegation_board_impl(uuid, text) to service_role;

comment on function public._club_delegation_board_impl(uuid, text) is
  '0168 §G (0153 의 문장 유지) — INTERNAL. 호출자가 준 p_access 를 그대로 믿으므로 클라이언트 롤이
부를 수 없어야 한다 — public.club_delegation_board(uuid) 를 부를 것. 0168 이 키 하나를 더한다:
runStopping = 호스트가 러닝 종료를 눌렀고 아직 숫자가 얼지 않았다. runEnded 는 넓히지 않았다 —
「얼었다」는 그 문장 그대로다. 핀: 스위트 184, 198.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §H  VERIFY — at apply time, positive AND negative, with the source read COMMENT-STRIPPED
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ Every `prosrc` read below strips `--` comments first. This file argues at length, inside and
--   outside the function bodies, about guards it adds — and a check for CALLING something is
--   otherwise satisfied by a comment EXPLAINING it. That is the repo's most-repeated instrument
--   failure and it is mechanical to avoid, so it is avoided mechanically rather than carefully.
-- ⚠ Every arm is an exact boolean (`is not true` / `is distinct from`). A bare `IF` on a NULL
--   predicate is SILENT, and the arms below are exactly the kind whose job is to notice that
--   something is MISSING.
-- ⚠ A VERIFY is a one-shot at apply. Suite 198 asserts the same shapes on EVERY run — the two
--   prove different things and neither is evidence for the other.
do $$
declare
  v_bad text := '';
  v_n int;
  v_secdef boolean;
  v_cfg text[];
  v_end text; v_ing text; v_der text; v_fin text; v_brd text; v_stx text;
begin
  -- ── ⓐ the column exists and is a timestamptz ─────────────────────────────────────────────
  select count(*)::int into v_n from information_schema.columns
   where table_schema = 'public' and table_name = 'bookings'
     and column_name = 'run_stopping_at' and data_type = 'timestamp with time zone';
  if v_n is distinct from 1 then v_bad := v_bad || ' NO-COLUMN(bookings.run_stopping_at)'; end if;

  -- ── ⓑ the derivation: the 3-arg form exists, the 2-arg form is GONE, and nobody can run it ─
  select count(*)::int into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_derive_run_km';
  if v_n is distinct from 1 then
    v_bad := v_bad || ' DERIVE-arity=' || coalesce(v_n::text, 'NULL')
                   || ' (the now()-bounded 2-arg door must not survive beside the threaded one)';
  end if;
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_der
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_derive_run_km';
  if v_der is null then v_bad := v_bad || ' NO-SOURCE(_club_derive_run_km)'; end if;
  if (v_der ~ 'p_cutoff') is not true then v_bad := v_bad || ' derive-cutoff-not-a-parameter'; end if;
  if (v_der ~ 'c_tap_grace_sec') is not true then v_bad := v_bad || ' derive-LOST-0156-tap-grace'; end if;
  if (v_der ~ 'c_max_gap_sec') is not true then v_bad := v_bad || ' derive-LOST-0156-coverage-gate'; end if;
  -- the guard this file exists not to revert: the window's upper bound must not read the clock
  if (v_der ~ 'extract\(epoch from now\(\)\)') is not false then
    v_bad := v_bad || ' 🔴 derive-STILL-BOUNDED-BY-now() — 0156 reverted';
  end if;
  if has_function_privilege('public',        'public._club_derive_run_km(jsonb, timestamptz, timestamptz)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' derive-public-executable'; end if;
  if has_function_privilege('anon',          'public._club_derive_run_km(jsonb, timestamptz, timestamptz)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' derive-anon-executable'; end if;
  if has_function_privilege('authenticated', 'public._club_derive_run_km(jsonb, timestamptz, timestamptz)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' derive-client-executable'; end if;
  if has_function_privilege('service_role',  'public._club_derive_run_km(jsonb, timestamptz, timestamptz)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' derive-service_role-executable'; end if;

  -- ── ⓒ phase 1 stamps `stopping` and FREEZES NOTHING (escalation ②) ───────────────────────
  select p.prosecdef, p.proconfig, regexp_replace(p.prosrc, '--[^\n]*', '', 'g')
    into v_secdef, v_cfg, v_end
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_end_pack_runs';
  if v_end is null then v_bad := v_bad || ' NO-SOURCE(club_end_pack_runs)'; end if;
  if v_secdef is not true then v_bad := v_bad || ' end-not-definer'; end if;
  if (v_cfg is not null and 'search_path=public, pg_temp' = any(v_cfg)) is not true
    then v_bad := v_bad || ' end-no-inbody-search_path'; end if;
  if (v_end ~ 'run_stopping_at = v_at') is not true then v_bad := v_bad || ' phase1-does-not-stamp-stopping'; end if;
  -- 🔴 the escalation, as a negative: an ASSIGNMENT to run_ended_at anywhere in phase 1.
  if (v_end ~ 'run_ended_at\s*=') is not false then
    v_bad := v_bad || ' 🔴 phase1-STAMPS-run_ended_at (Number(null)===0 settles 0 km; the pack map dies mid-run)';
  end if;
  if (v_end ~ '_club_derive_run_km') is not false then
    v_bad := v_bad || ' 🔴 phase1-DERIVES (the drain has not happened yet — this prices a truncated trace)';
  end if;
  if (v_end ~ 'actual_km') is not false then v_bad := v_bad || ' 🔴 phase1-writes-actual_km'; end if;
  if has_function_privilege('public',       'public.club_end_pack_runs(uuid)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' end-public-executable'; end if;
  if has_function_privilege('anon',         'public.club_end_pack_runs(uuid)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' end-anon-executable'; end if;
  if has_function_privilege('service_role', 'public.club_end_pack_runs(uuid)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' end-service_role-executable'; end if;
  if has_function_privilege('authenticated','public.club_end_pack_runs(uuid)', 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' end-LOST-authenticated (the host cannot tap)'; end if;

  -- ── ⓓ ingest: the drain window and its named terminator ──────────────────────────────────
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_ing
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_save_run_trace';
  if v_ing is null then v_bad := v_bad || ' NO-SOURCE(club_save_run_trace)'; end if;
  if (v_ing ~ 'run_stopping') is not true then v_bad := v_bad || ' ingest-no-drain-refusal'; end if;
  if (v_ing ~ 'c_drain_sec') is not true then v_bad := v_bad || ' ingest-no-drain-constant'; end if;
  if (v_ing ~ 'trace_future_fix') is not true then v_bad := v_bad || ' ingest-LOST-0156-future-bound'; end if;
  if has_function_privilege('authenticated','public.club_save_run_trace(uuid, jsonb)','EXECUTE') is distinct from true
    then v_bad := v_bad || ' ingest-LOST-authenticated'; end if;
  if has_function_privilege('anon','public.club_save_run_trace(uuid, jsonb)','EXECUTE') is distinct from false
    then v_bad := v_bad || ' ingest-anon-executable'; end if;

  -- ── ⓔ phase 2: the sweep's own shape, its LOCK, and the cutoff it hands the derivation ───
  select p.prosecdef, p.proconfig, regexp_replace(p.prosrc, '--[^\n]*', '', 'g')
    into v_secdef, v_cfg, v_fin
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_finalize_stopped_runs';
  if v_fin is null then v_bad := v_bad || ' NO-SOURCE(club_finalize_stopped_runs)'; end if;
  if v_secdef is not true then v_bad := v_bad || ' sweep-not-definer'; end if;
  if (v_cfg is not null and 'search_path=public, pg_temp' = any(v_cfg)) is not true
    then v_bad := v_bad || ' sweep-no-inbody-search_path'; end if;
  -- the PRECONDITION, not the branch: the row lock is what makes every read below it mean anything
  if (v_fin ~ 'from bookings bk where bk\.id = r\.booking_id for update') is not true
    then v_bad := v_bad || ' 🔴 sweep-does-not-LOCK-the-booking-row'; end if;
  -- 🔴 the cutoff is the TAP. `now()` here would widen the paid window by the whole drain.
  if (v_fin ~ '_club_derive_run_km\(v_trace, v_start, v_stop\)') is not true
    then v_bad := v_bad || ' 🔴 sweep-does-not-thread-the-tap-as-cutoff'; end if;
  if (v_fin ~ 'v_stop := v_bk\.run_stopping_at') is not true
    then v_bad := v_bad || ' sweep-freeze-clock-is-not-the-tap'; end if;
  if (v_fin ~ 'c_drain_sec') is not true then v_bad := v_bad || ' sweep-no-drain-constant'; end if;
  if has_function_privilege('public',        'public.club_finalize_stopped_runs()', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' sweep-public-executable'; end if;
  if has_function_privilege('anon',          'public.club_finalize_stopped_runs()', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' sweep-anon-executable'; end if;
  if has_function_privilege('authenticated', 'public.club_finalize_stopped_runs()', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' sweep-client-executable'; end if;
  if has_function_privilege('service_role',  'public.club_finalize_stopped_runs()', 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' sweep-service_role-CANNOT-execute (the cron installs and never fires)'; end if;

  -- ── ⓕ the board: the NEW key, the OLD key unchanged, every pre-existing key still there ──
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_brd
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_delegation_board_impl';
  if v_brd is null then v_bad := v_bad || ' NO-SOURCE(_club_delegation_board_impl)'; end if;
  if (v_brd ~ '''runStopping''') is not true then v_bad := v_bad || ' board-missing-runStopping'; end if;
  if (v_brd ~ '''runEnded''') is not true then v_bad := v_bad || ' board-LOST-runEnded'; end if;
  -- a recreation that DROPS a key is the silent half of this class and no behavioural pin sees it
  if (v_brd ~ '''ownerConfirmed''' and v_brd ~ '''runnerConfirmed''' and v_brd ~ '''custodyWithRunner'''
      and v_brd ~ '''holdExpiresAt''' and v_brd ~ '''bookingStatus''' and v_brd ~ '''refundState'''
      and v_brd ~ '''openIncidentId''' and v_brd ~ '''payoutState''') is not true then
    v_bad := v_bad || ' 🔴 board-recreation-LOST-a-pre-existing-key';
  end if;
  if has_function_privilege('anon',          'public._club_delegation_board_impl(uuid, text)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' board-anon-executable'; end if;
  if has_function_privilege('authenticated', 'public._club_delegation_board_impl(uuid, text)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' 🔴 board-authenticated-executable (0153 reverted by this recreation)'; end if;
  if has_function_privilege('public',        'public._club_delegation_board_impl(uuid, text)', 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' board-public-executable'; end if;
  if has_function_privilege('service_role',  'public._club_delegation_board_impl(uuid, text)', 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' board-service_role-LOST-execute (over-reach)'; end if;
  if has_function_privilege('authenticated', 'public.club_delegation_board(uuid)', 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' outer-board-LOST-authenticated-execute'; end if;

  -- ── ⓖ R-2: the two shipped mechanisms this whole family leans on are still present ───────
  -- 0144 §C ⓒ's shape, and its reason is unchanged: if `settle_run_tx`'s freeze arm were ever
  -- absent, everything above would be writing numbers nothing reads — a green harness on a
  -- feature that does nothing.
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_stx
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'settle_run_tx';
  if v_stx is null then v_bad := v_bad || ' NO-SOURCE(settle_run_tx)'; end if;
  if (v_stx ~ 'frozen_measurement_mismatch') is not true
    then v_bad := v_bad || ' settle_run_tx-LOST-the-freeze-gate'; end if;
  if (v_stx ~ 'when v_run_ended is null then excluded\.actual_km') is not true
    then v_bad := v_bad || ' settle_run_tx-LOST-freeze-preservation (R-2 reopened)'; end if;

  if v_bad <> '' then raise exception '0168 VERIFY:%', v_bad; end if;
  raise notice '0168: two-phase stop installed — phase 1 stamps run_stopping_at and freezes nothing, the 90 s drain is bounded at both ends, the sweep is registered and READ BACK from cron.job, and the derivation cutoff is the TAP rather than the clock';
end $$;
