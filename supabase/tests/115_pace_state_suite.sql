-- ═══ 0079 pace-state — 런 시작 스냅샷 · 롤링 윈도우 · 래치 · 페이로드 ═══
-- What this suite pins: the pace claim reaches the push job as a FIRST-CLASS prop (never folded
-- into phase), the honesty gate refuses to claim below 0.30km/180s, the stale sweep drops the
-- claim entirely ("무신호"와 "느림"은 절대 같아 보이면 안 된다), the run-start snapshot clamps a
-- client-written jsonb into the 420..540 band, a pace flip does NOT buy a push through the 20s
-- throttle (ambient signal stays ambient), the hysteresis LATCH holds both directions inside the
-- band, a mid-run preference edit cannot move the goalpost, and the snapshot column is sealed
-- against the one client role that can UPDATE runs — the runner it measures.
--
-- Style follows 103 (the sibling this extends): `_pass('pace',…)`/`_fail('pace',…)`, each case in
-- its own begin…exception handler, pg_net is the 00_shim stub so every push lands in
-- net._stub_calls. now() is transaction-constant inside the do-block, so every elapsed and window
-- number below is exact, not approximate — and the 20s throttle NEVER expires on its own, which is
-- why the latch pins rewind last_push_at by hand (that rewind is wall-clock passage, not a
-- weakening of the rule: P6 pins the rule itself with the clock untouched).
-- Every count is filtered by props' booking_id: sibling suites leave live tokens behind and
-- owner_la_sweep_stale() sweeps the whole table.
--
-- Trace arithmetic used below (equirectangular, the 0063/0079 shared rule: 111000 m/° lat):
--   Δlat 0.0009   = 99.900m — 30s apart ⇒ window pace 300"/km (양호), 60s apart ⇒ 600"/km (느림)
--   Δlat 0.000554 = 61.494m — 30s apart ⇒ window pace 488"/km (밴드 안: 480 < 488 ≤ 495)
--   Δlat 0.00049  = 54.390m — 30s apart ⇒ window pace 552"/km (스냅샷 480이면 느림, 540이면 양호)
--
-- ─── MUTATION VERIFICATION (2026-08-13) ───
-- Baseline before this slice: 388/0. With 0079 + this suite: 397/0.
-- ✔ = ACTUALLY EXECUTED in this build: the revert was applied to an undamaged 0079 (file md5
--     checked before and after — an edit that matches nothing is a fake proof), the WHOLE harness
--     was re-run, the named pin went RED and nothing else moved, then 0079 was byte-restored
--     (md5 back to pristine) and 397/0 returned. Unmarked = identified revert, not executed.
--   P1  ← delete `'paceState', v_state` from _owner_la_trace_tg's props object. NOT single-pin:
--         it kills the payload field itself, so P2/P7/P8 (same field) go red with it.
--   P2  ← in _owner_la_pace_state, replace the final edge with a constant 'good' (also reddens P8 —
--         both ride the prev-''/good edge; the slow-latch branch keeps P7's second half green)
--   P3  ← delete the km/elapsed gate lines (the first two `when`s) from _owner_la_pace_state
--   P4  ← delete `'paceState', ''` from owner_la_sweep_stale's props object
--         ✔ executed → 396/1, P4 alone: `직전=good calls=1 phase=stale state=∅` — the running push
--           had really claimed 'good', and the stale push then carried no field at all. That is the
--           failure this pin exists for: a lock screen where the last colour outlives the signal.
--   P5  ← drop the clamp: `new.pace_suggest_sec := coalesce(v_sec, 480)` in _runs_pace_snapshot_tg
--   P6  ← add paceState to _owner_la_push's throttle condition (make a pace flip bypass the gap)
--   P7  ← two directions, two reverts, either one reddens the pin (each is single-pin):
--         good-latch: `> coalesce(p_suggest,480) + 15` → `> coalesce(p_suggest,480)` (slack gone)
--         slow-latch: delete the `when coalesce(p_prev,'') = 'slow'` branch (memory gone)
--         ✔ executed (slow-latch) → 396/1, P7 alone: `직전good→good 직전slow→good` — the latch is
--           what makes 488"/km mean two different things; without memory the chip flickers at the
--           boundary and a runner who was told 느림 is silently told 양호 without changing pace.
--   P8  ← read the live pref instead of the snapshot in _owner_la_trace_tg:
--         `v_suggest := coalesce((select (d.preferences->>'paceSuggestSec')::int from bookings b
--          join dogs d on d.id = b.dog_id where b.id = new.booking_id), 480)`
--   P9  ← delete `or new.pace_suggest_sec is distinct from old.pace_suggest_sec` from _guard_run_cols
set client_min_messages = warning;

do $$
declare
  o1 uuid; r1 uuid; rt uuid;
  d_std uuid; d_lo uuid; d_hi uuid; d_bad uuid; d_imm uuid;
  bk_good uuid; bk_slow uuid; bk_short uuid; bk_young uuid; bk_stale uuid;
  bk_lo uuid; bk_hi uuid; bk_bad uuid; bk_imm uuid; bk_seal uuid;
  e0 numeric;                       -- transaction-constant epoch anchor
  v_base bigint; v_n int; v_cnt int; v_body jsonb; v_txt text; v_txt2 text;
  v_lo int; v_hi int; v_bad int; v_snap int; v_raise boolean; v_upd int;
  tok text := repeat('ef', 40);
begin
  o1 := t_user('pace_owner', 'owner');
  r1 := t_user('pace_runner', 'runner');
  rt := t_route('서울숲 페이스 코스');
  e0 := floor(extract(epoch from now()));

  -- The relay must exist or every push is an honest no-op (0063 §4) — idempotent: 103 may have
  -- inserted the same single row already.
  insert into owner_la_push_config (id, relay_url, relay_secret)
  values (true, 'https://relay.test/owner-la', 't-secret') on conflict (id) do nothing;

  d_std := t_dog(o1, '초코');
  update dogs set preferences = jsonb_build_object('paceSuggestSec', 480) where id = d_std;

  -- ── P1: 양호 상태가 푸시 잡까지 도달한다 (phase에 접히지 않고 자기 필드로) ──
  begin
    bk_good := t_active_booking(o1, r1, d_std, rt);
    update runs set started_at = now() - interval '20 minutes' where booking_id = bk_good;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_good, 'act-good', tok, 'production');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    -- 8점 · 30초 간격 · 99.9m ⇒ 총 0.6993km(게이트 통과), 최근 180초 창 = 300"/km
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 210),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 150),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5476, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.5485, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.5494, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.5503, 'lng', 127.0557, 't', e0))
    where booking_id = bk_good;
    select count(*) into v_n from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_good::text;
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_good::text order by id desc limit 1;
    if v_n = 1
       and v_body->'props'->>'phase' = 'running'
       and v_body->'props'->>'paceState' = 'good'
      then call _pass('pace','P1 양호 페이로드 — 권장 이내 창 페이스가 props.paceState=good으로 잠금화면까지 간다');
    else call _fail('pace','P1 양호 페이로드','calls=' || v_n
           || ' state=' || coalesce(v_body->'props'->>'paceState','∅')
           || ' km=' || coalesce(v_body->'props'->>'km','∅'));
    end if;
  exception when others then call _fail('pace','P1 양호 페이로드', sqlerrm);
  end;

  -- ── P2: 느림 상태 (권장 + 15초 슬랙을 넘겨야 노랗게 된다) ──
  begin
    bk_slow := t_active_booking(o1, r1, d_std, rt);
    update runs set started_at = now() - interval '20 minutes' where booking_id = bk_slow;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_slow, 'act-slow', tok, 'production');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    -- 7점 · 60초 간격 · 99.9m ⇒ 총 0.5994km, 최근 180초 창 = 601"/km (> 480+15)
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 360),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 300),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 240),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.5476, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5485, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.5494, 'lng', 127.0557, 't', e0))
    where booking_id = bk_slow;
    select count(*) into v_n from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_slow::text;
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_slow::text order by id desc limit 1;
    if v_n = 1 and v_body->'props'->>'paceState' = 'slow'
      then call _pass('pace','P2 느림 페이로드 — 권장+15초를 넘긴 창 페이스는 props.paceState=slow');
    else call _fail('pace','P2 느림 페이로드','calls=' || v_n
           || ' state=' || coalesce(v_body->'props'->>'paceState','∅'));
    end if;
  exception when others then call _fail('pace','P2 느림 페이로드', sqlerrm);
  end;

  -- ── P3: 정직 게이트 — 0.30km 미만도, 180초 미만도 주장하지 않는다 (측정처럼 보이는 비측정 금지) ──
  -- 두 게이트를 각각 건다: 거리는 짧고 시간은 충분한 런, 거리는 충분하고 시간이 짧은 런.
  -- 둘 다 푸시 자체는 나간다 (km ≥ 0.01) — 빠지는 건 오직 '주장'이다.
  begin
    bk_short := t_active_booking(o1, r1, d_std, rt);
    bk_young := t_active_booking(o1, r1, d_std, rt);
    update runs set started_at = now() - interval '20 minutes' where booking_id = bk_short;
    update runs set started_at = now() - interval '60 seconds' where booking_id = bk_young;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_short, 'act-short', tok, 'production');
    perform owner_la_register(bk_young, 'act-young', tok, 'production');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(                       -- 0.1998km — 거리 게이트 미달
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0))
    where booking_id = bk_short;
    update runs set trace = jsonb_build_array(                       -- 0.5994km인데 경과 60초
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 150),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.5476, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.5485, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.5494, 'lng', 127.0557, 't', e0))
    where booking_id = bk_young;
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_short::text order by id desc limit 1;
    v_txt := v_body->'props'->>'paceState';
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_young::text order by id desc limit 1;
    v_txt2 := v_body->'props'->>'paceState';
    if v_txt = '' and v_txt2 = ''
      then call _pass('pace','P3 정직 게이트 — 0.30km 미만·180초 미만에서는 색을 주장하지 않는다 (부재, 회색 아님)');
    else call _fail('pace','P3 정직 게이트','짧은거리=' || coalesce(v_txt,'∅') || ' 짧은시간=' || coalesce(v_txt2,'∅'));
    end if;
  exception when others then call _fail('pace','P3 정직 게이트', sqlerrm);
  end;

  -- ── P4: 스테일 스윕은 주장을 통째로 내려놓는다 — "무신호"와 "느림"은 같아 보이면 안 된다 ──
  begin
    bk_stale := t_active_booking(o1, r1, d_std, rt);
    update runs set started_at = now() - interval '20 minutes' where booking_id = bk_stale;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_stale, 'act-stale', tok, 'production');
    -- 200초 전에 끊긴 양호한 러닝: 직전 running 푸시는 실제로 'good'을 실어 보냈다.
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 410),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 380),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 350),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 320),
      jsonb_build_object('lat', 37.5476, 'lng', 127.0557, 't', e0 - 290),
      jsonb_build_object('lat', 37.5485, 'lng', 127.0557, 't', e0 - 260),
      jsonb_build_object('lat', 37.5494, 'lng', 127.0557, 't', e0 - 230),
      jsonb_build_object('lat', 37.5503, 'lng', 127.0557, 't', e0 - 200))
    where booking_id = bk_stale;
    select body into v_body from net._stub_calls
     where body->>'booking_id' = bk_stale::text order by id desc limit 1;
    v_txt := v_body->'props'->>'paceState';                    -- 살아있던 주장 (대조군)
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_stale::text;
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_stale::text order by id desc limit 1;
    if v_txt = 'good' and v_n = 1
       and v_body->'props'->>'phase' = 'stale'
       and v_body->'props'->>'paceState' = ''
      then call _pass('pace','P4 스테일 = 주장 철회 — 신호가 끊기면 색이 죽는다 (마지막 색이 살아남지 않는다)');
    else call _fail('pace','P4 스테일 = 주장 철회','직전=' || coalesce(v_txt,'∅') || ' calls=' || v_n
           || ' phase=' || coalesce(v_body->'props'->>'phase','∅')
           || ' state=' || coalesce(v_body->'props'->>'paceState','∅'));
    end if;
  exception when others then call _fail('pace','P4 스테일 = 주장 철회', sqlerrm);
  end;

  -- ── P5: 밴드 밖 선호값은 런 생성 시점에 서버가 잘라 넣는다 (클라가 쓴 jsonb는 신뢰하지 않는다) ──
  begin
    d_lo  := t_dog(o1, '밴드아래');
    d_hi  := t_dog(o1, '밴드위');
    d_bad := t_dog(o1, '깨진값');
    update dogs set preferences = jsonb_build_object('paceSuggestSec', 60)   where id = d_lo;
    update dogs set preferences = jsonb_build_object('paceSuggestSec', 1200) where id = d_hi;
    update dogs set preferences = jsonb_build_object('paceSuggestSec', 'fast') where id = d_bad;
    bk_lo  := t_active_booking(o1, r1, d_lo,  rt);
    bk_hi  := t_active_booking(o1, r1, d_hi,  rt);
    bk_bad := t_active_booking(o1, r1, d_bad, rt);
    select pace_suggest_sec into v_lo  from runs where booking_id = bk_lo;
    select pace_suggest_sec into v_hi  from runs where booking_id = bk_hi;
    select pace_suggest_sec into v_bad from runs where booking_id = bk_bad;
    if v_lo = 420 and v_hi = 540 and v_bad = 480
      then call _pass('pace','P5 스냅샷 클램프 — 60→420, 1200→540, 숫자가 아닌 값→480 (에러가 아니라 기본값)');
    else call _fail('pace','P5 스냅샷 클램프','lo=' || coalesce(v_lo::text,'∅')
           || ' hi=' || coalesce(v_hi::text,'∅') || ' bad=' || coalesce(v_bad::text,'∅'));
    end if;
  exception when others then call _fail('pace','P5 스냅샷 클램프', sqlerrm);
  end;

  -- ── P6: 색 변화는 스로틀을 사지 못한다 — 앰비언트 신호는 앰비언트로 남는다 ──
  -- P1의 양호 러닝을 20초 안에 '느림'으로 뒤집는다. 위상은 그대로 running이므로 푸시는 0이어야 한다
  -- (위상 전환만이 갭을 통과한다 — 103 L13이 그 반대편을 핀한다).
  begin
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 360),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 300),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 240),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.5476, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5485, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.5494, 'lng', 127.0557, 't', e0))
    where booking_id = bk_good;
    select count(*) into v_n from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_good::text;
    select t.last_state->>'paceState' into v_txt from owner_la_tokens t where t.booking_id = bk_good;
    if v_n = 0 and v_txt = 'good'
      then call _pass('pace','P6 스로틀 보존 — 페이스만 뒤집힌 재저장은 20초 갭을 뚫지 않는다 (60초 채널이 수다스러워지지 않는다)');
    else call _fail('pace','P6 스로틀 보존','calls=' || v_n || ' last_state=' || coalesce(v_txt,'∅'));
    end if;
  exception when others then call _fail('pace','P6 스로틀 보존', sqlerrm);
  end;

  -- ── P7: 히스테리시스 래치 — 밴드 안(480 < 488 ≤ 495) 값은 양방향 모두 직전 상태를 유지한다 ──
  -- 래치는 '기억'이다: 같은 488"/km가 직전 양호면 양호로, 직전 느림이면 느림으로 남는다. 이 한 문장이
  -- 경계에서의 칩 깜빡임을 없앤다. last_push_at 되감기는 벽시계 경과의 대역(트랜잭션 now()는 고정)
  -- — 스로틀 법 자체는 P6이 시계를 건드리지 않은 채로 핀한다.
  begin
    update owner_la_tokens set last_push_at = now() - interval '60 seconds'
     where booking_id in (bk_good, bk_slow);
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    -- 8점 · 30초 간격 · 61.494m ⇒ 총 0.4305km, 최근 180초 창 = 488"/km
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.544000, 'lng', 127.0557, 't', e0 - 210),
      jsonb_build_object('lat', 37.544554, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.545108, 'lng', 127.0557, 't', e0 - 150),
      jsonb_build_object('lat', 37.545662, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.546216, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.546770, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.547324, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.547878, 'lng', 127.0557, 't', e0))
    where booking_id = bk_good;                                 -- 직전 good
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.544000, 'lng', 127.0557, 't', e0 - 210),
      jsonb_build_object('lat', 37.544554, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.545108, 'lng', 127.0557, 't', e0 - 150),
      jsonb_build_object('lat', 37.545662, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.546216, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.546770, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.547324, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.547878, 'lng', 127.0557, 't', e0))
    where booking_id = bk_slow;                                 -- 직전 slow
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_good::text order by id desc limit 1;
    v_txt := v_body->'props'->>'paceState';
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_slow::text order by id desc limit 1;
    v_txt2 := v_body->'props'->>'paceState';
    if v_txt = 'good' and v_txt2 = 'slow'
      then call _pass('pace','P7 래치 — 같은 488"/km가 직전 양호면 양호로, 직전 느림이면 느림으로 남는다 (양방향)');
    else call _fail('pace','P7 래치','직전good→' || coalesce(v_txt,'∅') || ' 직전slow→' || coalesce(v_txt2,'∅'));
    end if;
  exception when others then call _fail('pace','P7 래치', sqlerrm);
  end;

  -- ── P8: 스냅샷 면역 — 러닝 중 선호값을 바꿔도 골대는 움직이지 않는다 (공정성) ──
  -- 창 페이스 552"/km: 스냅샷 480 기준이면 느림(552 > 495), 러닝 중에 바꾼 540을 읽었다면
  -- 양호(552 ≤ 555)가 된다. 즉 이 핀은 "어느 숫자를 읽었는가"를 직접 구별한다.
  begin
    d_imm := t_dog(o1, '골대고정');
    update dogs set preferences = jsonb_build_object('paceSuggestSec', 480) where id = d_imm;
    bk_imm := t_active_booking(o1, r1, d_imm, rt);
    update runs set started_at = now() - interval '20 minutes' where booking_id = bk_imm;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_imm, 'act-imm', tok, 'production');
    update dogs set preferences = jsonb_build_object('paceSuggestSec', 540) where id = d_imm;  -- 러닝 중 편집
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    -- 8점 · 30초 간격 · 54.39m ⇒ 총 0.3807km, 최근 180초 창 = 552"/km
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.544000, 'lng', 127.0557, 't', e0 - 210),
      jsonb_build_object('lat', 37.544490, 'lng', 127.0557, 't', e0 - 180),
      jsonb_build_object('lat', 37.544980, 'lng', 127.0557, 't', e0 - 150),
      jsonb_build_object('lat', 37.545470, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.545960, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.546450, 'lng', 127.0557, 't', e0 - 60),
      jsonb_build_object('lat', 37.546940, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.547430, 'lng', 127.0557, 't', e0))
    where booking_id = bk_imm;
    select body into v_body from net._stub_calls
     where id > v_base and body->>'booking_id' = bk_imm::text order by id desc limit 1;
    select pace_suggest_sec into v_snap from runs where booking_id = bk_imm;
    if v_snap = 480 and v_body->'props'->>'paceState' = 'slow'
      then call _pass('pace','P8 스냅샷 면역 — 러닝 중 선호값 편집은 이 런의 기준을 못 바꾼다 (다음 런부터)');
    else call _fail('pace','P8 스냅샷 면역','snapshot=' || coalesce(v_snap::text,'∅')
           || ' state=' || coalesce(v_body->'props'->>'paceState','∅'));
    end if;
  exception when others then call _fail('pace','P8 스냅샷 면역', sqlerrm);
  end;

  -- ── P9: 스냅샷 컬럼 봉인 — 측정당하는 당사자(러너)가 자기 기준을 못 만진다 ──
  -- runs는 러너가 직접 UPDATE할 수 있는 테이블이다 (라이브 트레이스 저장 경로). 양성 대조를 같이
  -- 건다: trace 저장이 실제로 성공해야 이 핀이 공허하게 초록이 아니다 (113 K14의 교훈).
  begin
    bk_seal := t_active_booking(o1, r1, d_std, rt);
    perform set_config('request.jwt.claim.sub', r1::text, false);
    set local role authenticated;
    v_raise := false;
    begin
      update runs set pace_suggest_sec = 540 where booking_id = bk_seal;
    exception when others then v_raise := (sqlerrm = 'run_protected_columns');
    end;
    update runs set trace = jsonb_build_array(                   -- 양성 대조: 이 경로는 살아있다
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 30),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0))
    where booking_id = bk_seal;
    get diagnostics v_upd = row_count;
    reset role;
    select pace_suggest_sec into v_snap from runs where booking_id = bk_seal;
    if v_raise and v_upd = 1 and v_snap = 480
      then call _pass('pace','P9 스냅샷 봉인 — 러너는 트레이스는 쓰고 자기 기준선은 못 쓴다 (run_protected_columns)');
    else call _fail('pace','P9 스냅샷 봉인','raise=' || v_raise || ' trace행=' || v_upd
           || ' snapshot=' || coalesce(v_snap::text,'∅'));
    end if;
  exception when others then reset role; call _fail('pace','P9 스냅샷 봉인', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
