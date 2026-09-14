-- ═══ 199 — 0169 the SQL belt: `settle_run_tx` refuses a `stopping` booking ══════════════════
--                                                            — 0169-B1 ~ 0169-B4 (tag `ssb`)
--
-- What this file has to establish, in one sentence: **a run whose numbers are not yet frozen
-- cannot be settled through the SQL door either, the refusal lifts by itself the moment the sweep
-- freezes it, and it does not touch a run that was never stopped.**
--
-- 🔴 LIVE MONEY, UN-FLAG-GATED. `settle_run_tx` writes the runner's `ledger_items` row with
--    `ops_flags.payments_live_since` NULL (`0083:754`), so 0169-B1's proposition is 「no money row
--    exists」 and it is measured as a COUNT BEFORE and a COUNT AFTER, never as a state the fixture
--    happened to be in.
--
-- ── WHY A SUITE FOR ONE `if` ──────────────────────────────────────────────────────────────
-- 0168 closed this state at the edge (`settle-run/handler.ts:94-99`, four Deno tests) and wrote
-- the SQL side into its own header as a NAMED GAP: `settle_run_tx` is revoked from
-- `public, anon, authenticated` (`0083:838`), so the handler is the only door a CLIENT can reach —
-- but `service_role` holds EXECUTE through Supabase's defaults, and any second caller (another
-- edge function, a cron, a hand-run repair) settles at the CLIENT's numbers with nothing in its
-- way. That is 0168's own defect reached through a different door.
--
-- ── THE CONTROL PAIR, AND IT IS THE REASON THIS FILE IS NOT ONE PIN ───────────────────────
-- **0169-B1** (a stopping booking is refused) and **0169-B2 / 0169-B3** (a frozen one settles, an
-- un-stopped one settles). Name the failure each is blind to and the lists are different: B1
-- cannot see over-refusal, and over-refusal here is not hypothetical — it is the CHEAPEST wrong
-- version of this belt. `run_stopping_at` is **not cleared by the freeze** (`0168:589-600` writes
-- `run_ended_at` and leaves the stamp), so a gate written as `v_run_stopping is not null` alone
-- passes B1 perfectly and **refuses every club settle for ever**: every runner in every pack, never
-- paid, with a green pin over it. B2 is the arm that reddens on exactly that.
-- B3 is the other direction — a refusal that widened to every active booking would take the
-- marketplace with it, and B3 is the fixture where the two candidate predicates diverge.
--
-- ── THE FIXTURE ───────────────────────────────────────────────────────────────────────────
-- Driven through the shipped chain exactly as 176 and 198 do it, with 198's three manufactured
-- writes and 198's reasons for them (there is no SQL RPC for the door handoff; `now()` is
-- transaction-start time so `started_at` must be back-dated; and the harness cannot make 90 real
-- seconds pass, so `run_stopping_at` is back-dated by 330 s before the SHIPPED sweep is called
-- with no arguments, exactly as `cron.job` calls it). Two sessions, because `club_end_pack_runs`
-- taps a whole session: sA is tapped, sB never is, and B3's booking lives on sB.
-- ⚠ `club_finalize_stopped_runs()` is GLOBAL and 176/198 leave bookings `stopping` behind it, so
--   every assertion here is made on THIS file's own bookings or on a delta this file caused —
--   never on the sweep's counters.
--
-- ── MUTATION BATTERY — PREDICTED FIRST, THEN MEASURED 2026-09-15 ─────────────────────────
--   Applied against a COPY of `supabase/` outside the worktree (never by editing the live file),
--   each planter `&&`-chained to its harness run so a plant that fails to land yields NO row
--   rather than a green one, and each planter asserting its own `count(old) == 1` first.
--   `tests/.pgtest` is excluded from the copy: a copied data dir is a broken cluster and every run
--   dies at the shim, which reads in a summary table as 「the mutation reddened everything」.
--
--   #     mutation                                    PREDICTED          MEASURED
--   M0    none — the control                          1201+4 = 1205/0    **1205 / 0**
--   M1    the whole belt deleted from 0169            apply ABORTS       **APPLY ABORTED**:
--                                                                        `0169 VERIFY: 🔴 settle_run_tx-has-NO-run_stopping-refusal
--                                                                        🔴 belt-does-not-read-0168s-phase … gate=0 mut=2258`
--   M1b   the SAME deletion **plus** 0169's VERIFY     [B1] red, [B3]    **1202 / 3 = [0169-B1,
--         arms ①②③ removed, so the apply succeeds      green             0169-B4, 0169-B2]**
--         and the SUITE is what is measured
--         0169-B1: 「🔴 stopping 예약이 클라 숫자로 정산됐다 · 거절 토큰=<no raise> · 원장이 움직였다 +1 ·
--         거절 뒤 A=completed/stopping✓/frozen∅/**9.90**」 — the NAMED GAP reproduced verbatim: the
--         client's 9.90 km became a ledger row on a run the server had derived nothing for.
--   ⚠ **0169-B2's red under M1b is a CASCADE, not a second detector, and saying so is the point.**
--     Its booking had already been settled by the unguarded call, so the sweep found nothing to
--     freeze and every arm failed downstream of B1. B2 is blind to the belt being ABSENT by
--     design — it is the over-refusal control — and reading its red as independent evidence would
--     be 「one measurement printed twice」.
--   ⚠ **0169-B3 stayed GREEN under M1b**, which is what a control that owns a different failure
--     mode looks like: deleting the belt cannot change a booking the belt never applied to.
--   (M1 and M1b measure DIFFERENT propositions — 「the migration refuses to install it」 and 「the
--    suite sees it」 — and counting either as the other is the 「a green is evidence for exactly
--    one sentence」 error.)
--
-- ⚠ Every arm asserts an EXACT boolean (`is distinct from` / an explicit compare), never a bare
--   `IF`: plpgsql does not take an `IF` on a NULL predicate, so a bare `if <expr>` is SILENT
--   exactly when the thing under test returned NULL — and these pins exist to notice absence.
-- ⚠ 0169-B4 strips comments from `prosrc` before matching and carries a loud NO-SOURCE arm. 0169
--   argues about `run_stopping` at length in the comments INSIDE the function body; an un-stripped
--   check for RAISING it is satisfied by a comment EXPLAINING it, and the better the comment the
--   more certainly green.

set client_min_messages = warning;

-- ── a synthetic trace in the SHIPPED shape, 198's helper under this file's own name ─────────
create or replace function t199_trace(p_from timestamptz, p_i0 int, p_n int, p_step int, p_metres numeric)
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'lat', 37.5096 + (i * p_metres / 111000.0),
           'lng', 126.9954,
           't',   floor(extract(epoch from p_from))::bigint + 1 + (i * p_step)
         ) order by i), '[]'::jsonb)
  from generate_series(p_i0, p_i0 + p_n - 1) i
$$;

-- ── one pairing, through the shipped chain, up to (not including) the run start ─────────────
create or replace function t199_pair(p_sess uuid, p_tag text, p_runner uuid, p_host uuid)
returns uuid language plpgsql as $$
declare v_owner uuid; v_dog uuid; v_sd uuid;
begin
  v_owner := t_user('t199o_' || p_tag, 'owner');
  v_dog   := t_dog(v_owner, p_tag);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_sd := session_delegate_dog(p_sess, v_dog, t_consent());
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  perform session_pay_delegation(v_sd, 't199-idem-' || p_tag, true);
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_assign_dog(v_sd, p_runner);
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform session_proposal_respond(v_sd, true);
  -- the door handoff — the service_role transition path (198's note ①)
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
   where id = (select booking_id from session_dogs where id = v_sd);
  update bookings set status = 'picked_up'
   where id = (select booking_id from session_dogs where id = v_sd);
  perform set_config('request.jwt.claim.sub', '', false);
  return v_sd;
end $$;

create or replace function t199_bk(p_sd uuid) returns uuid
language sql stable as $$ select booking_id from session_dogs where id = p_sd $$;

-- ── advance past the drain window, then run phase 2 (198's note ③) ──────────────────────────
create or replace function t199_drain(p_session uuid) returns jsonb
language plpgsql as $$
declare v_res jsonb;
begin
  update bookings set run_stopping_at = run_stopping_at - interval '330 seconds'
   where club_session_id = p_session
     and run_stopping_at is not null
     and run_ended_at is null;
  v_res := club_finalize_stopped_runs();
  return v_res;
end $$;

-- the state of one pairing as ONE string, so a failure names every axis at once
create or replace function t199_state(p_sd uuid) returns text
language sql stable as $$
  select (select b.status::text from bookings b where b.id = t199_bk(p_sd))
      || '/' || case when (select b.run_stopping_at from bookings b where b.id = t199_bk(p_sd)) is null
                     then 'stopping∅' else 'stopping✓' end
      || '/' || case when (select b.run_ended_at from bookings b where b.id = t199_bk(p_sd)) is null
                     then 'frozen∅' else 'frozen✓' end
      || '/' || coalesce((select r.actual_km::text from runs r where r.booking_id = t199_bk(p_sd)), 'km∅')
$$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 1 — the tap, the belt, the sweep, and the two bookings the belt must not touch
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_host uuid; r1 uuid; r2 uuid; v_club uuid; v_sa uuid; v_sb uuid; v_route uuid;
  sdA uuid; sdB uuid; bkA uuid; bkB uuid;
  v_t0 timestamptz; v_tap timestamptz; v_stop timestamptz; v_res jsonb; v_sweep jsonb;
  v_bad text; v_n int; v_led0 int; v_led1 int; v_err text; v_km numeric;
begin
  update club_flags set enabled = true where name = 'club_delegation_v2';

  v_host := t_user('t199_host', 'runner');
  r1 := t_user('t199_r1', 'runner');
  r2 := t_user('t199_r2', 'runner');
  update runners set tier = 'veteran' where profile_id in (v_host, r1, r2);
  v_route := t_route('t199 반포 코스');

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_club := club_request_district('t199동');
  perform club_claim_host(v_club);
  -- sA is tapped; sB never is. `club_end_pack_runs` taps a whole SESSION, so B3's un-stopped
  -- booking cannot live on sA — a pin whose fixture sits where both candidate predicates agree is
  -- testing the fixture.
  v_sa := club_create_session(v_club, now() + interval '90 minutes', 't199 집결지 A', v_route, 20, 'mixed');
  v_sb := club_create_session(v_club, now() + interval '90 minutes', 't199 집결지 B', v_route, 20, 'mixed');
  perform session_runner_commit(v_sa); perform session_checkin(v_sa);
  perform session_runner_commit(v_sb); perform session_checkin(v_sb);
  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform session_runner_commit(v_sa); perform session_checkin(v_sa);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(v_sb); perform session_checkin(v_sb);
  perform set_config('request.jwt.claim.sub', '', false);

  sdA := t199_pair(v_sa, 'a1', r1, v_host);
  sdB := t199_pair(v_sb, 'b1', r2, v_host);
  bkA := t199_bk(sdA);
  bkB := t199_bk(sdB);

  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform club_start_delegated_runs(v_sa);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform club_start_delegated_runs(v_sb);
  perform set_config('request.jwt.claim.sub', '', false);

  -- back-date the starts (198's note ②) and upload the base trace through the shipped RPC:
  -- 21 points, 60 s apart, 100 m per step → 20 segments → 2.00 km, every point far inside the
  -- window under either rule.
  v_t0 := now() - interval '32 minutes';
  update runs set started_at = v_t0 where booking_id in (bkA, bkB);
  perform set_config('request.jwt.claim.sub', r1::text, false);
  perform club_save_run_trace(v_sa, t199_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform club_save_run_trace(v_sb, t199_trace(v_t0, 0, 21, 60, 100));
  perform set_config('request.jwt.claim.sub', '', false);

  -- ═══ THE TAP — phase 1 on sA only ════════════════════════════════════════════════════════
  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_res := club_end_pack_runs(v_sa);
  perform set_config('request.jwt.claim.sub', '', false);
  v_tap  := (v_res->>'at')::timestamptz;
  v_stop := v_tap - interval '330 seconds';   -- what t199_drain's back-date will make it

  -- ═══ [0169-B1] 💰 THE BELT — a stopping booking is refused, and no money row appears ══════
  -- The attack is the NAMED GAP verbatim: a `service_role` caller hands `settle_run_tx` its own
  -- 9.90 km while the server has derived nothing, which is 0168's defect reached through the door
  -- 0168 did not close. Measured as a ledger count BEFORE and AFTER — 「no row exists」 read off a
  -- fixture would be true whether or not this function ever ran.
  begin
    v_bad := ''; v_err := '<no raise>';
    if t199_state(sdA) is distinct from 'active/stopping✓/frozen∅/km∅'
      then v_bad := v_bad || ' 픽스처: 탭 직후 A=' || t199_state(sdA); end if;
    select count(*) into v_led0 from ledger_items;

    begin
      perform settle_run_tx(bkA, 9.90, 1590, 'completed', null, 9900, 29700, 0, 0, 8000);
      v_bad := v_bad || ' 🔴 stopping 예약이 클라 숫자로 정산됐다';
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'run_stopping'
      then v_bad := v_bad || ' 거절 토큰=' || v_err; end if;

    select count(*) into v_led1 from ledger_items;
    if v_led1 is distinct from v_led0
      then v_bad := v_bad || ' 🔴 거절됐는데 원장이 움직였다 +' || (v_led1 - v_led0); end if;
    select count(*) into v_n from ledger_items where booking_id = bkA;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 A의 원장 행=' || v_n; end if;
    -- and nothing else moved either: the refusal sits in front of the atomic claim, not behind it
    if t199_state(sdA) is distinct from 'active/stopping✓/frozen∅/km∅'
      then v_bad := v_bad || ' 거절 뒤 A=' || t199_state(sdA); end if;

    if v_bad = ''
      then call _pass('ssb','0169-B1 💰 SQL 벨트 — 호스트가 탭했고 스윕은 아직 얼리지 않은 예약(run_stopping_at✓ · run_ended_at∅, 0168 이 handler.ts:94 에서 읽는 바로 그 술어)을 service_role 이 직접 부르면 run_stopping 으로 거절된다. 공격은 0168 이 자기 헤더에 적어 둔 NAMED GAP 그대로다 — 서버가 아무것도 도출하지 않은 상태에서 호출자가 들고 온 9.90km 로 정산하는 것, 즉 0168 이 없애려던 결함을 닫히지 않은 문으로 되살리는 것. 원장은 **전후 카운트**로 잰다(픽스처에서 읽은 「행이 없다」는 이 함수가 돌았든 안 돌았든 참이다). 상태도 그대로다: 거절은 원자 클레임 **앞**에 있다');
      else call _fail('ssb','0169-B1 the belt refuses', v_bad); end if;
  exception when others then call _fail('ssb','0169-B1 the belt refuses', sqlerrm);
  end;

  -- ═══ [0169-B3] THE REFUSAL DID NOT WIDEN — a run that was never stopped still settles ═════
  -- Measured at the same moment B1's booking is refused, on a session nobody tapped. This is the
  -- fixture where the two candidate predicates diverge: a belt keyed on 「active」, on 「no ledger
  -- row」, or on anything other than the stamp would take this booking — and with it the whole
  -- marketplace, where `run_stopping_at` is never written at all.
  begin
    v_bad := '';
    if t199_state(sdB) is distinct from 'active/stopping∅/frozen∅/km∅'
      then v_bad := v_bad || ' 픽스처: B=' || t199_state(sdB); end if;
    select count(*) into v_led0 from ledger_items;
    begin
      perform settle_run_tx(bkB, 2.00, 1800, 'completed', null, 9900, 15000, 0, 0, 4980);
    exception when others then v_bad := v_bad || ' 🔴 정지된 적 없는 러닝이 정산 불가=' || sqlerrm;
    end;
    select count(*) into v_n from ledger_items where booking_id = bkB;
    if v_n is distinct from 1 then v_bad := v_bad || ' B의 원장 행=' || v_n; end if;
    select count(*) into v_led1 from ledger_items;
    if v_led1 is distinct from v_led0 + 1
      then v_bad := v_bad || ' 원장 델타=' || (v_led1 - v_led0); end if;
    if (select b.status::text from bookings b where b.id = bkB) is distinct from 'completed'
      then v_bad := v_bad || ' B 상태=' || coalesce((select b.status::text from bookings b where b.id = bkB),'NULL'); end if;

    if v_bad = ''
      then call _pass('ssb','0169-B3 거절은 넓어지지 않았다 — 한 번도 정지된 적 없는 active 예약(run_stopping_at∅)은 B1 이 거절당하는 바로 그 순간에 정상 정산되고 원장은 **이 핀이 일으킨 +1** 이다. 두 후보 술어가 갈리는 지점이 여기다: 스탬프가 아니라 「active」나 「원장이 없다」 같은 것을 보는 벨트는 이 예약을 가져가고, run_stopping_at 을 아예 쓰지 않는 마켓플레이스 전체를 함께 가져간다');
      else call _fail('ssb','0169-B3 the refusal did not widen', v_bad); end if;
  exception when others then call _fail('ssb','0169-B3 the refusal did not widen', sqlerrm);
  end;

  -- ═══ [0169-B2] THE CONTROL — the sweep freezes it and the SAME call settles ═══════════════
  -- The pin that makes B1 worth having. `run_stopping_at` is NOT cleared by the freeze, so a belt
  -- written as `v_run_stopping is not null` alone passes B1 perfectly and refuses every club
  -- settle for ever. The sweep is the shipped function, called with no arguments exactly as
  -- `cron.job` calls it; only the back-date is manufactured, because 90 real seconds cannot pass
  -- inside one transaction.
  begin
    v_bad := ''; v_err := '<no raise>';
    v_sweep := t199_drain(v_sa);
    if t199_state(sdA) is distinct from 'active/stopping✓/frozen✓/2.00'
      then v_bad := v_bad || ' 스윕 후 A=' || t199_state(sdA); end if;
    if (select b.run_ended_at from bookings b where b.id = bkA) is distinct from v_stop
      then v_bad := v_bad || ' 동결 시각이 탭이 아니다'; end if;
    if (select b.run_stopping_at from bookings b where b.id = bkA) is null
      then v_bad := v_bad || ' 픽스처가 스탬프를 지웠다 (이 핀의 대상이 사라졌다)'; end if;

    -- ⓐ the belt has lifted, and 0083 ⓔ is what stands behind it: the client's numbers are still
    --    refused, now for the RIGHT reason and by a DIFFERENT name. Without this arm 「it settles」
    --    would not distinguish 「the belt lifted」 from 「every guard on this path is gone」.
    begin
      perform settle_run_tx(bkA, 9.90, 1590, 'completed', null, 9900, 29700, 0, 0, 8000);
      v_bad := v_bad || ' 🔴 동결 후에도 클라 숫자가 통과했다';
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'frozen_measurement_mismatch'
      then v_bad := v_bad || ' 동결 후 불일치 토큰=' || v_err; end if;
    select count(*) into v_n from ledger_items where booking_id = bkA;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 불일치 거절인데 원장=' || v_n; end if;

    -- ⓑ and the SERVER's numbers settle — the same call that was refused in B1
    select count(*) into v_led0 from ledger_items;
    select r.actual_km into v_km from runs r where r.booking_id = bkA;
    if v_km is distinct from 2.00 then v_bad := v_bad || ' 동결 km=' || coalesce(v_km::text,'NULL'); end if;
    begin
      perform settle_run_tx(bkA, 2.00, 1590, 'completed', null, 9900, 15000, 0, 0, 4980);
    exception when others then v_bad := v_bad || ' 🔴 동결된 러닝이 정산 불가=' || sqlerrm;
    end;
    select count(*) into v_n from ledger_items where booking_id = bkA;
    if v_n is distinct from 1 then v_bad := v_bad || ' 동결 후 A의 원장 행=' || v_n; end if;
    select count(*) into v_led1 from ledger_items;
    if v_led1 is distinct from v_led0 + 1
      then v_bad := v_bad || ' 원장 델타=' || (v_led1 - v_led0); end if;
    if (select b.status::text from bookings b where b.id = bkA) is distinct from 'completed'
      then v_bad := v_bad || ' 동결 후 A 상태=' || coalesce((select b.status::text from bookings b where b.id = bkA),'NULL'); end if;

    if v_bad = ''
      then call _pass('ssb','0169-B2 💰 통제 — 벨트는 스스로 풀린다. 스윕(club_finalize_stopped_runs(), cron 이 부르는 그대로 인자 없이)이 **탭 시각**으로 2.00km 를 얼린 뒤, B1 에서 거절당한 바로 그 호출이 서버 숫자로 성공하고 원장은 이 핀이 일으킨 +1 이다. **이 핀이 없으면 B1 은 최악의 벨트를 완벽히 통과시킨다**: 동결은 run_stopping_at 을 지우지 않으므로(0168:589-600) `run_stopping_at is not null` 만 보는 게이트는 모든 클럽 정산을 영원히 거절하면서 B1 위에 초록을 띄운다. ⓐ 팔은 벨트가 풀린 자리에 0083 ⓔ 가 서 있음을 잰다 — 클라 숫자는 여전히 frozen_measurement_mismatch 로 거절된다(「정산된다」만으로는 「벨트가 풀렸다」와 「이 경로의 가드가 전부 사라졌다」가 구별되지 않는다)');
      else call _fail('ssb','0169-B2 the sweep lifts the belt', v_bad); end if;
  exception when others then call _fail('ssb','0169-B2 the sweep lifts the belt', sqlerrm);
  end;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- BLOCK 2 — [0169-B4] the SOURCE pin: the belt is in the deployed body, and it is in FRONT
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Behaviour cannot see ORDER. B1 proves a stopping booking ends with no ledger row; it cannot
-- distinguish 「the refusal ran before the atomic claim」 from 「the refusal ran after three writes
-- and the transaction rolled them back」 — and the second is a money function that mutates state
-- before deciding whether it is allowed to, which is one refactor away from a partially applied
-- settlement. The deployed body is the only instrument for that, and it must be read
-- COMMENT-STRIPPED: 0169 argues about `run_stopping` in the comments inside this very function.
do $$
declare v_src text; v_bad text := ''; v_gate int; v_mut int;
begin
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'settle_run_tx';

  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE(settle_run_tx)';
  else
    if (v_src ~ 'raise exception ''run_stopping''') is not true
      then v_bad := v_bad || ' 🔴 본문에 run_stopping 거절이 없다'; end if;
    if (v_src ~ 'v_run_stopping is not null and v_run_ended is null') is not true
      then v_bad := v_bad || ' 🔴 0168 의 국면 술어 두 반쪽이 아니다'; end if;
    -- `for update;` cannot match the mutation pattern: it needs `update <ident> set`. The
    -- on-conflict's `do update set` is later than the first UPDATE regardless.
    v_gate := coalesce(regexp_instr(v_src, 'raise exception ''run_stopping'''), 0);
    v_mut  := coalesce(regexp_instr(v_src, '(update[[:space:]]+[a-z_]+[[:space:]]+set|insert[[:space:]]+into)'), 0);
    if v_gate <= 0 then v_bad := v_bad || ' 위치 측정 불가(게이트 없음)'; end if;
    if v_mut  <= 0 then v_bad := v_bad || ' 위치 측정 불가(UPDATE/INSERT 를 못 찾았다)'; end if;
    if (v_gate > 0 and v_mut > 0 and v_gate < v_mut) is not true
      then v_bad := v_bad || ' 🔴 거절이 첫 상태 변경보다 뒤에 있다 gate=' || v_gate || ' mut=' || v_mut; end if;
    -- the belt was ADDED, not swapped in for 0083's own guards
    if (v_src ~ 'frozen_measurement_mismatch') is not true
      then v_bad := v_bad || ' 🔴 0083 ⓔ 동결 게이트가 사라졌다'; end if;
    if (v_src ~ 'return_not_sealed') is not true
      then v_bad := v_bad || ' 🔴 0083 ⓑ 씰 게이트가 사라졌다'; end if;
  end if;

  if v_bad = ''
    then call _pass('ssb','0169-B4 소스 — 배포된 본문(주석 제거)에 run_stopping 거절이 있고, 그 위치가 **첫 UPDATE/INSERT 보다 앞**이다. 행동으로는 순서를 볼 수 없다: B1 은 「원장 행이 없다」만 말할 수 있고, 「원자 클레임 앞에서 거절했다」와 「세 번 쓰고 롤백했다」를 구별하지 못한다 — 후자는 허가 여부를 정하기 전에 상태를 바꾸는 돈 함수이고 부분 적용 정산까지 리팩터 한 번 거리다. 주석을 반드시 벗긴다: 0169 는 바로 이 함수 안의 주석에서 run_stopping 을 길게 설명하므로, 벗기지 않은 검사는 **설명이 잘 될수록 더 확실히 초록**이 된다. 0083 ⓑ/ⓔ 존재 팔은 벨트가 기존 가드를 대체한 게 아니라 **더해졌음**을 잰다');
    else call _fail('ssb','0169-B4 source: the belt is in front', v_bad); end if;
exception when others then call _fail('ssb','0169-B4 source: the belt is in front', sqlerrm);
end $$;
