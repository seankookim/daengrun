-- ═══ 208 — the four money/ops crons are SCHEDULED, and the LA stale sweep holds a job lock ═══
--            (0177 · audit H3 + M10) — 0177-S1 … 0177-S7, tag `crb`
--
-- ═══ THE PROPOSITION S1…S5 OWN ═══════════════════════════════════════════════════════════════
-- 「the sweep EXISTS」 and 「the sweep RUNS」 are two claims, and for these four only the first was
-- ever checked. All four were registered inside `exception when others then raise notice`
-- (`0045:443`, `0083:1512`, `0117:1652`, `0118:1338`) — the form `0157 §A` condemned and `0172`
-- swept two names out of — so a failed `cron.schedule` COMMITTED as a successful migration and
-- nothing afterwards said the job was missing. 0177 re-registers all four strictly and reads them
-- back at apply; these pins are the STANDING half of that.
--
-- ⚠ TWO DIFFERENT ARTIFACTS, AND NEITHER IS EVIDENCE FOR THE OTHER (the `check-definer-acl`
--   division, restated from 202's header because it applies unchanged):
--     · **0177's VERIFY block** runs on the PRODUCTION apply and aborts it if any of the four is
--       not scheduled as written — the load-bearing half. The harness can SIMULATE the absence
--       (battery plant A deletes a registration and the apply aborts) but CANNOT reproduce the
--       real-world CAUSE: the shim's `cron.schedule` (`00_shim.sql:102`) cannot fail, so 「pg_cron
--       absent / the role lacks rights in `cron`」 is structurally unreachable here. Plant A
--       measures that the VERIFY fires on a missing row, never that it fires on the failure that
--       would produce one in production.
--     · **These pins** are the standing guard: they redden if a later file unschedules a job,
--       renames one, re-registers it running something else, or re-staggers it without updating
--       its pin — states the harness CAN produce and a production VERIFY that already ran cannot
--       see.
--
-- ⚠ WHY FOUR PINS AND NOT ONE WITH FOUR ARMS. One pin whose message lists four counts is one
--   measurement printed four times: a plant that removes a single registration reddens it exactly
--   as a plant that removes all four does, and the battery table below could not tell those apart.
--   Four rows means the count of reddened pins IS the count of broken jobs.
--
-- ⚠ AND WHY `0177-S5` EXISTS AT ALL. S1…S4 read a registry that 0177 itself populates on every
--   apply, so on their own they cannot distinguish 「the detector works」 from 「the detector always
--   says yes」. S5 manufactures the absence BY VALUE for each of the four — whole-row snapshot →
--   delete → re-read → park inactive → wrong command → wrong schedule → restore — and asserts the
--   detector reports 0 in every one of those states and 1 again afterwards, with the row byte-
--   identical to what it took.
-- 🔴 NAMED GAP, inherited from 202's and stated in the same terms: S5 proves the detector SHAPE
--   rejects an inactive / mis-commanded / mis-scheduled row, using **its own copy** of the query.
--   It does NOT prove that S1…S4's four copies each carry those three conjuncts. Nothing in the
--   migration chain ever sets `cron.job.active = false`, so a plant that drops `and active` from
--   S1's own query reddens nothing — that is a fact about what the harness can reach, not a blind
--   pin, and it is written here rather than repaired by reshaping a pin around a mutation.
--
-- ═══ THE PROPOSITION S6/S7 OWN (M10) ═════════════════════════════════════════════════════════
-- `owner-la-stale` fires every minute and both arms of `owner_la_sweep_stale` dedupe by READING
-- `owner_la_tokens.last_state` and comparing the line they are about to push. Two overlapping ticks
-- both read the old state and both push. 0177 adds `pg_try_advisory_lock` at the top and releases
-- on both exits; the body is otherwise `0083:1297-1376` verbatim.
--
-- ⚠ S6 IS A SOURCE PIN AND THE HARNESS CANNOT MAKE IT A BEHAVIOURAL ONE — said plainly rather
--   than left for a reader to assume the green is broader. Reproducing the duplicate push needs
--   two BACKENDS ticking the same minute concurrently; `harness.sh` runs one psql connection per
--   suite and `90_race_check.sh` is the only two-connection fixture in the repo, built for a
--   different subject. A single-session pin cannot see a session-scoped lock work, because a
--   session-scoped lock is RE-ENTRANT: the same connection acquires it twice happily. So what is
--   pinned is the SHAPE — the call, its position ahead of the first loop, both releases, and the
--   re-raise — which is exactly the division `check-device-clock` and 98 H1 record, and neither
--   half is evidence for the other.
-- ⚠ COMMENTS ARE STRIPPED BEFORE EVERY MATCH, and 0177's body NAMES the call in a comment ON
--   PURPOSE so the strip is demonstrably load-bearing rather than merely present: arm ⑥ asserts
--   the stripped source carries exactly ONE `pg_try_advisory_lock` while the raw source carries
--   MORE. A check that skipped the strip would be satisfied by the comment explaining the fix —
--   the class this repo has now met four times.
-- ⚠ S7 IS THE PRECONDITION PIN, not a duplicate of 98 H1's sweep. `prosecdef`, the in-body
--   `search_path` and the ACL are what make S6's arms mean anything: a definer recreated
--   PUBLIC-executable turns this sweep into an arbitrary-push surface, and 0083's own recreation
--   is line 82 of `check-definer-acl-baseline.txt` precisely because it relies on preservation.
--   0177 re-states the ACL; this pin is what keeps that true after the next recreation.
--
-- ═══ BATTERY — MEASURED 2026-09-17, every plant `&&`-CHAINED to its run ══════════════════════
-- Against a COPY of the tree (`scratchpad/lab`, migrations + tests rsynced, `.pgtest` excluded so
-- no broken data dir can make a run come back blank), never the live files. Each plant asserts its
-- own occurrence count BEFORE editing and the harness invocation is `&&`-chained to it, so a plant
-- that did not land yields NO ROW rather than a green one.
-- 🔴 CONTROL OBSERVED CLEAN FIRST: the unmutated lab copy ran **1236 pass / 0 fail, exit 0**, with
--    all 7 `crb` pins present by label — identical to the worktree. A delta means nothing until
--    that number has been looked at.
-- ⚠ EVERY ROW BELOW WAS RE-MEASURED AFTER THE 0175→0177 / 205→208 RENUMBER, under the labels it
--   quotes. The first pass ran under 0175/205 and produced the same six results; a table that
--   quoted `0175-S2` after the rename would be a write-up that outlived the thing measured, which
--   is why the whole battery was run again rather than sed'd.
-- ⚠ AND ONE RUN WAS DISCARDED AS AN ENVIRONMENT FAULT rather than read as a row: the lab's
--   `reset_lab.sh` used `rsync -a --delete --exclude='.pgtest'`, which removed the lab cluster's
--   data directory mid-sequence — the A2 run died at `connection refused` after applying every
--   migration. That is 202's 「a battery that reddens nothing and a battery that never ran are
--   indistinguishable in a summary table」 arriving as a LOUD failure instead of a quiet one, and
--   it was still worth naming: the fix is `--filter='P .pgtest'`, the control was re-observed clean
--   (1236/0) on the repaired lab, and A2 was re-run from there.
--
--   | plant                                                            | result | what it measures |
--   |------------------------------------------------------------------|--------|------------------|
--   | **A0** 0177 §B's `run-end-recovery` registration removed, 0083's left | **1236 / 0, exit 0, NO abort** | 🔴 NOTHING REDDENS — and this is 202's measured lesson reproduced, not a blind pin. 0083:1512's swallowed registration still SUCCEEDS in the harness (the shim's `cron.schedule` cannot fail), so the row is there either way. A VERIFY that read back a row only its own file wrote would be testing its own setup (the `175 V2` law); the plant has to remove BOTH. |
--   | **A1** A0 **+** 0083:1512's registration removed                 | **APPLY ABORTS** | `0177 VERIFY FAILED: … found club-payout-release=1 run-end-recovery=0 cancel-money-gaps=1 sweep-club-cancel-fees=1`. That measures the VERIFY block, not this suite (0131-G4's distinction). |
--   | **A2** A1 **+** the VERIFY's `run-end-recovery` arm demoted so the suite can speak | **1234 / 2** | `0177-S2` (`run-end-recovery 활성 작업 수=0 (이름만 일치하는 행=0)` — the defect by name, with the diagnostic that separates 「gone」 from 「renamed」) and `0177-S5` (`NO-SUBJECT … 3/4`). ⚠ The S5 cascade is CORRECT and is why it is written that way: its subject IS the set S1…S4 assert, so with one row gone the control REFUSES rather than passing over a partial world (0151's absence-pin lesson). **S1, S3, S4, S6, S7 stayed GREEN** — so the four job pins are four measurements, not one printed four times. |
--   | **B** the executable `pg_try_advisory_lock` line deleted from 0177 §E — **the comment naming the call left in place** | **1235 / 1** | `0177-S6` alone: `🔴 작업 단위 락이 없다 … 개수=0 … 🔴 락이 첫 루프보다 뒤에 있다`. This is simultaneously the COMMENT-STRIP CONTROL: the body still says `pg_try_advisory_lock(hashtextextended('owner_la_sweep_stale', 0))` in prose and the pin is red anyway. A check reading `prosrc` raw would have been green here. |
--   | **B3** the EXCEPTION-arm `pg_advisory_unlock` deleted (happy-path one kept) | **1235 / 1** | `0177-S6` alone: `실행되는 pg_advisory_unlock 개수=1 (…=2여야 한다)` + `예외 출구가 「해제 후 재-raise」 형태가 아니다`. The precondition, not the branch: a session-scoped lock leaked on the failing exit silences every later tick on that backend. |
--   | **C** S6's own query pointed at a function name that does not exist | **1235 / 1** | `0177-S6` opens with `NO-SOURCE(owner_la_sweep_stale — 함수가 없다)` and then EVERY arm fires loudly (`개수=0`, `raw=0 stripped=0`, `RAW-SOURCE 자체가 비어 있다`). This is the NULL-collapse guard doing its job: with `prosrc` NULL a bare `IF` would have made the whole pin silent and green — the class that cost ui6 four pins on 2026-08-27. |
--
-- ⚠ NOT MEASURED, and named rather than implied: no plant here reddens `0177-S1`, `S3`, `S4` or
--   `S7` individually. A0/A1/A2 chose `run-end-recovery` because it is the HARDER case (its
--   original registration does fire in the harness); `club-payout-release` is the easy one —
--   measured incidentally, `0045:443`'s block runs `create extension if not exists pg_cron` FIRST,
--   which raises locally, so its own `cron.schedule` never executes and **0177 §A is the only
--   thing that puts that row in the harness's `cron.job` at all**. The four pins are textually
--   identical in shape, but 「identical in shape」 is a reading, not a measurement.
set client_min_messages = warning;

-- ───────────────────────────────────────────────────────────────────────────────────────────
-- [0177-S1 … 0177-S4] the four jobs are on `cron.job`, each exactly once, active, with the
-- schedule AND command 0177 registered. Every arm is `is distinct from`, never a bare `IF`: a
-- NULL predicate makes a plpgsql `IF` silent, and these four pins exist to notice absence.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad text := ''; v_msg text; v_n int; v_has_cron boolean;
begin
  -- Shared precondition, asserted as a VALUE and not assumed: `to_regclass` returns NULL for an
  -- absent relation rather than raising, so absence is a value here.
  select to_regclass('cron.job') is not null into v_has_cron;

  ------------------------------------------------------------------------------------------
  -- [0177-S1] club-payout-release — nothing else flips a club payout to released.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent — 00_shim.sql:90 is the fixture)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'club-payout-release'
       and active
       and schedule = '0 18 * * *'
       and command  = 'select club_release_payouts()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' club-payout-release 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      -- Which of the failure shapes it is: 「사라졌다」 and 「이름은 같은데 다른 걸 돌린다」 need
      -- different repairs and a bare count cannot tell them apart.
      select count(*)::int into v_n from cron.job where jobname = 'club-payout-release';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S1 클럽 정산 크론이 실제로 예약돼 있다 — cron.job 에 active 한 club-payout-release 가 정확히 1개, 스케줄 0 18 * * *, command 가 club_release_payouts() (0045:443 은 등록 실패를 notice 로 삼켰다)');
  else v_msg := v_bad; call _fail('crb','0177-S1 클럽 정산 크론이 실제로 예약돼 있다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0177-S2] run-end-recovery — 0083 §9's janitor: sealed-but-unsettled and stranded-active are
  -- both permanent without it.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'run-end-recovery'
       and active
       and schedule = '8-58/10 * * * *'
       and command  = 'select sweep_run_end_recovery()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' run-end-recovery 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      select count(*)::int into v_n from cron.job where jobname = 'run-end-recovery';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S2 런 종료 복구 크론이 실제로 예약돼 있다 — active 한 run-end-recovery 가 정확히 1개, 스케줄 8-58/10 * * * *, command 가 sweep_run_end_recovery() (봉인됐지만 정산 안 된 예약과 확인 없이 멈춘 예약은 이 스윕이 없으면 영구히 남는다)');
  else v_msg := v_bad; call _fail('crb','0177-S2 런 종료 복구 크론이 실제로 예약돼 있다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0177-S3] cancel-money-gaps — 0117 §9e: a cancellation commits in one statement and its money
  -- is written by later requests; a worker dying in between leaves a fee with no compensation.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'cancel-money-gaps'
       and active
       and schedule = '6-56/10 * * * *'
       and command  = 'select sweep_cancel_money_gaps()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' cancel-money-gaps 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      select count(*)::int into v_n from cron.job where jobname = 'cancel-money-gaps';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S3 취소 돈 구멍 스윕이 실제로 예약돼 있다 — active 한 cancel-money-gaps 가 정확히 1개, 스케줄 6-56/10 * * * *, command 가 sweep_cancel_money_gaps() (수수료만 적히고 러너 보상도 청구 인텐트도 없는 부분 커밋을 되메우는 유일한 기계)');
  else v_msg := v_bad; call _fail('crb','0177-S3 취소 돈 구멍 스윕이 실제로 예약돼 있다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0177-S4] sweep-club-cancel-fees — 0118 §F's durable retry for club-fee mints that failed
  -- where SQL cannot reach `_shared/ops.ts`.
  v_bad := '';
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent)';
  else
    select count(*)::int into v_n
      from cron.job
     where jobname = 'sweep-club-cancel-fees'
       and active
       and schedule = '2-52/10 * * * *'
       and command  = 'select sweep_club_cancel_fee_intents()';
    if v_n is distinct from 1 then
      v_bad := v_bad || ' sweep-club-cancel-fees 활성 작업 수=' || coalesce(v_n::text, 'NULL');
      select count(*)::int into v_n from cron.job where jobname = 'sweep-club-cancel-fees';
      v_bad := v_bad || ' (이름만 일치하는 행=' || coalesce(v_n::text, 'NULL') || ')';
    end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S4 클럽 취소 수수료 민팅 재시도 크론이 실제로 예약돼 있다 — active 한 sweep-club-cancel-fees 가 정확히 1개, 스케줄 2-52/10 * * * *, command 가 sweep_club_cancel_fee_intents()');
  else v_msg := v_bad; call _fail('crb','0177-S4 클럽 취소 수수료 민팅 재시도 크론이 실제로 예약돼 있다', v_msg); end if;

exception when others then
  v_msg := sqlerrm; call _fail('crb','0177-S1..S4 크론 판독 핀이 예외로 중단됐다', v_msg);
end $$;


-- ───────────────────────────────────────────────────────────────────────────────────────────
-- [0177-S5] 🔴 THE CONTROL — S1…S4 CAN REPORT ABSENT.
-- Four count-equals-1 pins over a registry 0177 populates on every apply cannot, alone, tell
-- 「the detector works」 from 「the detector always says yes」. This arm manufactures four kinds of
-- absence per job and reads the detector each time, then restores BY VALUE and proves the row went
-- back byte-identical. Whole-row jsonb rather than a column list (185 G4 / 202 0172-S3's idiom) so
-- a column added to `cron.job` later is carried without this file being edited.
-- ⚠ The restore is asserted, not assumed: a failed restore leaves four money/ops jobs unscheduled
--   for every suite that runs after this one, and surfaces as somebody else's inexplicable red.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_bad text := ''; v_msg text; v_n int; v_has_cron boolean;
  v_snap jsonb; v_row jsonb; v_cur jsonb; r record; e jsonb;
begin
  select to_regclass('cron.job') is not null into v_has_cron;
  if v_has_cron is not true then
    v_bad := v_bad || ' NO-CRON-REGISTRY(cron.job absent — 통제 자체가 불가능)';
  else
    select coalesce(jsonb_agg(to_jsonb(j)), '[]'::jsonb) into v_snap
      from cron.job j
     where j.jobname in ('club-payout-release','run-end-recovery',
                         'cancel-money-gaps','sweep-club-cancel-fees');
    if jsonb_array_length(v_snap) is distinct from 4 then
      -- S1..S4 already reported whichever is missing; a control cannot run without its subject,
      -- and saying so beats a green produced by having nothing to delete (0151's empty-world law).
      v_bad := v_bad || ' NO-SUBJECT(네 작업 행이 모두 있지는 않다: '
                     || coalesce(jsonb_array_length(v_snap)::text,'NULL') || '/4)';
    else
      for r in
        select * from (values
          ('club-payout-release',    '0 18 * * *',      'select club_release_payouts()'),
          ('run-end-recovery',       '8-58/10 * * * *', 'select sweep_run_end_recovery()'),
          ('cancel-money-gaps',      '6-56/10 * * * *', 'select sweep_cancel_money_gaps()'),
          ('sweep-club-cancel-fees', '2-52/10 * * * *', 'select sweep_club_cancel_fee_intents()')
        ) v(jn, sc, cmd)
      loop
        select to_jsonb(j) into v_row from cron.job j where j.jobname = r.jn;

        -- ⓐ gone ⇒ 0
        delete from cron.job where jobname = r.jn;
        select count(*)::int into v_n from cron.job
         where jobname = r.jn and active and schedule = r.sc and command = r.cmd;
        if v_n is distinct from 0 then
          v_bad := v_bad || ' [' || r.jn || '] 행을 지웠는데 탐지기가 ' || coalesce(v_n::text,'NULL') || ' 을 보고한다'; end if;

        -- ⓑ present but PARKED ⇒ 0. `active = false` is how pg_cron parks a job, and a name-only
        --    detector would call that scheduled.
        insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, v_row);
        update cron.job set active = false where jobname = r.jn;
        select count(*)::int into v_n from cron.job
         where jobname = r.jn and active and schedule = r.sc and command = r.cmd;
        if v_n is distinct from 0 then
          v_bad := v_bad || ' [' || r.jn || '] 비활성 작업을 예약됨으로 셌다=' || coalesce(v_n::text,'NULL'); end if;

        -- ⓒ same name, RUNNING SOMETHING ELSE ⇒ 0. This is the state a later re-registration
        --    produces, and the one a name-only readback is blind to.
        update cron.job set active = true, command = 'select 1' where jobname = r.jn;
        select count(*)::int into v_n from cron.job
         where jobname = r.jn and active and schedule = r.sc and command = r.cmd;
        if v_n is distinct from 0 then
          v_bad := v_bad || ' [' || r.jn || '] command 가 다른데 예약됨으로 셌다=' || coalesce(v_n::text,'NULL'); end if;

        -- ⓓ same name and command, RE-STAGGERED ⇒ 0. This is the conjunct 0172 chose not to carry;
        --    0177 carries it because its own §A…§D write the schedule in the same file.
        update cron.job set command = r.cmd, schedule = '59 23 31 12 *' where jobname = r.jn;
        select count(*)::int into v_n from cron.job
         where jobname = r.jn and active and schedule = r.sc and command = r.cmd;
        if v_n is distinct from 0 then
          v_bad := v_bad || ' [' || r.jn || '] 스케줄이 다른데 예약됨으로 셌다=' || coalesce(v_n::text,'NULL'); end if;

        -- ⓔ restore, by value, and prove it
        delete from cron.job where jobname = r.jn;
        insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, v_row);
        select to_jsonb(j) into v_cur from cron.job j where j.jobname = r.jn;
        if v_cur is distinct from v_row then
          v_bad := v_bad || ' [' || r.jn || '] 복구된 행이 원본과 다르다(' || coalesce(v_cur::text,'∅') || ')'; end if;
        select count(*)::int into v_n from cron.job
         where jobname = r.jn and active and schedule = r.sc and command = r.cmd;
        if v_n is distinct from 1 then
          v_bad := v_bad || ' [' || r.jn || '] 복구 뒤 탐지기=' || coalesce(v_n::text,'NULL'); end if;
      end loop;
    end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S5 통제 — 네 작업 각각에 대해 탐지기가 「없음」을 보고할 수 있다: 행을 지우면 0, 비활성이면 0, command 가 다르면 0, 스케줄이 다르면 0, 값으로 되돌리면 다시 1이고 행은 원본과 바이트 동일');
  else v_msg := v_bad; call _fail('crb','0177-S5 통제 — 탐지기가 「없음」을 보고할 수 있다', v_msg); end if;

exception when others then
  -- This control DELETES live registry rows. If anything above raises between a delete and its
  -- restore, four money/ops jobs would be left unscheduled for everything that runs after this
  -- file — so the restore is repeated here rather than trusted to the happy path.
  if v_snap is not null and jsonb_array_length(v_snap) = 4 then
    for e in select * from jsonb_array_elements(v_snap) loop
      delete from cron.job where jobname = e->>'jobname';
      insert into cron.job overriding system value select * from jsonb_populate_record(null::cron.job, e);
    end loop;
  end if;
  v_msg := sqlerrm; call _fail('crb','0177-S5 통제가 예외로 중단됐다', v_msg);
end $$;


-- ───────────────────────────────────────────────────────────────────────────────────────────
-- [0177-S6] the job lock is IN `owner_la_sweep_stale`, at the top, and released on BOTH exits.
-- [0177-S7] and the envelope that makes S6 mean anything: definer, in-body search_path, ACL.
-- ───────────────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_src text; v_raw text; v_bad text := ''; v_msg text;
  v_lock_src int; v_lock_raw int; v_unlock_src int;
begin
  ------------------------------------------------------------------------------------------
  -- [0177-S6]
  select regexp_replace(prosrc, '--[^\n]*', '', 'g'), prosrc into v_src, v_raw
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'owner_la_sweep_stale';

  v_bad := '';
  -- ⑤ the NULL-collapse arm, first: with `prosrc` NULL every `~` below is NULL and every
  --    `is not true` fires correctly, but the message would not say WHY.
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(owner_la_sweep_stale — 함수가 없다)'; end if;

  select count(*)::int into v_lock_src   from regexp_matches(coalesce(v_src,''), 'pg_try_advisory_lock', 'g');
  select count(*)::int into v_lock_raw   from regexp_matches(coalesce(v_raw,''), 'pg_try_advisory_lock', 'g');
  select count(*)::int into v_unlock_src from regexp_matches(coalesce(v_src,''), 'perform pg_advisory_unlock\(hashtextextended\(''owner_la_sweep_stale'', 0\)\);', 'g');

  -- ① THE LOCK ITSELF, keyed on this function's own name.
  if (v_src ~ 'if not pg_try_advisory_lock\(hashtextextended\(''owner_la_sweep_stale'', 0\)\) then return 0; end if;') is not true
    then v_bad := v_bad || ' 🔴 작업 단위 락이 없다 (겹친 틱 둘이 같은 스테일 줄을 두 번 밀어낸다)'; end if;
  if v_lock_src is distinct from 1
    then v_bad := v_bad || ' 실행되는 pg_try_advisory_lock 개수=' || coalesce(v_lock_src::text,'NULL') || ' (1이어야 한다)'; end if;

  -- ② POSITION, not merely presence — the precondition, not the branch. A lock taken after the
  --    first loop is a lock that guards nothing, and it would satisfy arm ① exactly as well.
  if (position('pg_try_advisory_lock' in coalesce(v_src,'')) > 0
      and position('pg_try_advisory_lock' in coalesce(v_src,'')) < position('for r in' in coalesce(v_src,''))) is not true
    then v_bad := v_bad || ' 🔴 락이 첫 루프보다 뒤에 있다 (아무것도 직렬화하지 않는다)'; end if;

  -- ③ BOTH EXITS release. Session-scoped: a tick that left it held silences every later tick on
  --    that backend, which is worse than the duplicate push M10 is about.
  if v_unlock_src is distinct from 2
    then v_bad := v_bad || ' 실행되는 pg_advisory_unlock 개수=' || coalesce(v_unlock_src::text,'NULL') || ' (정상/예외 두 출구 = 2여야 한다)'; end if;

  -- ④ and the failing exit RE-RAISES, so 0083's handler-free behaviour is preserved exactly.
  if (v_src ~ 'exception when others then[[:space:]]+perform pg_advisory_unlock\(hashtextextended\(''owner_la_sweep_stale'', 0\)\);[[:space:]]+raise;') is not true
    then v_bad := v_bad || ' 예외 출구가 「해제 후 재-raise」 형태가 아니다'; end if;

  -- ⑥ THE CONTROL ON THE INSTRUMENT: 0177's body names the call in a COMMENT on purpose, so the
  --    raw source must carry MORE mentions than the stripped one. If this arm is green while the
  --    strip is doing nothing, arms ①/② would be satisfied by prose describing the fix — the
  --    class that has cost this repo four findings.
  if (v_lock_raw > v_lock_src) is not true
    then v_bad := v_bad || ' 주석 제거가 아무 것도 지우지 않았다 (raw=' || coalesce(v_lock_raw::text,'NULL')
                        || ' stripped=' || coalesce(v_lock_src::text,'NULL')
                        || ') — 스트립이 무력해지면 ①②는 주석만으로 초록이 된다'; end if;
  if (v_raw ~ 'owner_la_tokens') is not true
    then v_bad := v_bad || ' RAW-SOURCE 자체가 비어 있다'; end if;

  if v_bad = '' then call _pass('crb','0177-S6 owner_la_sweep_stale 이 작업 단위 락을 잡는다 — 첫 루프보다 앞에서 pg_try_advisory_lock(hashtextextended(''owner_la_sweep_stale'',0)), 정상/예외 두 출구 모두에서 해제, 예외 출구는 해제 후 재-raise. 주석 제거 후 매칭이고, 그 스트립이 실제로 일하고 있음을 raw>stripped 로 함께 측정한다');
  else v_msg := v_bad; call _fail('crb','0177-S6 owner_la_sweep_stale 이 작업 단위 락을 잡는다', v_msg); end if;

  ------------------------------------------------------------------------------------------
  -- [0177-S7] the envelope. A definer recreated PUBLIC-executable turns a sweep that PUSHES to
  -- owners' lock screens into an arbitrary-push surface; `0083`'s own recreation relies on grant
  -- preservation (line 82 of check-definer-acl-baseline.txt) and 0177 re-states the ACL. This pin
  -- is what keeps that true after the NEXT recreation — a property checked only at apply is
  -- protected exactly until someone recreates the function.
  v_bad := '';
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'owner_la_sweep_stale')
    then v_bad := v_bad || ' NO-FUNCTION(owner_la_sweep_stale)';
  else
    if (select prosecdef from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'owner_la_sweep_stale') is not true
      then v_bad := v_bad || ' definer가 아니다'; end if;
    if (select 'search_path=public, pg_temp' = any(proconfig) from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'owner_la_sweep_stale') is not true
      then v_bad := v_bad || ' search_path가 본문에 없다 (98 H1 의 주제)'; end if;
    if has_function_privilege('public',        'public.owner_la_sweep_stale()', 'execute') is distinct from false
      then v_bad := v_bad || ' 🔴 public이 실행 가능'; end if;
    if has_function_privilege('anon',          'public.owner_la_sweep_stale()', 'execute') is distinct from false
      then v_bad := v_bad || ' 🔴 anon이 실행 가능'; end if;
    if has_function_privilege('authenticated', 'public.owner_la_sweep_stale()', 'execute') is distinct from false
      then v_bad := v_bad || ' 🔴 authenticated가 실행 가능 (누구나 남의 잠금화면에 푸시를 돌릴 수 있다)'; end if;
    -- the over-reach arm: revoke too far and the every-minute cron installs and never fires
    if has_function_privilege('service_role',  'public.owner_la_sweep_stale()', 'execute') is distinct from true
      then v_bad := v_bad || ' service_role가 실행 불가 (크론이 영원히 아무것도 안 한다)'; end if;
  end if;
  if v_bad = '' then call _pass('crb','0177-S7 락을 의미 있게 만드는 봉투 — owner_la_sweep_stale 은 definer 이고 본문에 search_path 를 들고 있으며 public/anon/authenticated 실행 불가·service_role 실행 가능. 0177 가 ACL 을 명시하고 이 핀이 다음 재생성 이후에도 그걸 지킨다');
  else v_msg := v_bad; call _fail('crb','0177-S7 락을 의미 있게 만드는 봉투', v_msg); end if;

exception when others then
  v_msg := sqlerrm; call _fail('crb','0177-S6/S7 소스·봉투 핀이 예외로 중단됐다', v_msg);
end $$;
