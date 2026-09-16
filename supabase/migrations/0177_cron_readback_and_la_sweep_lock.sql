-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0177 — the four unswept money/ops crons are READ BACK from `cron.job` (H3), and the
--        every-minute Live-Activity stale sweep gets a JOB-LEVEL LOCK (M10)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 208_cron_readback_suite.sql (tag `crb`).
-- Source: docs/reviews/2026-09-17-backend-honesty-audit.md — H3 (HIGH) and M10 (MED).
--
-- ═══ §H3 — WHAT THIS HALF ASSERTS, AND WHAT IT DOES NOT ═════════════════════════════════════
--
-- 17 of this repo's 22 cron jobs are registered inside `do $$ … exception when others then raise
-- notice … end $$`. `0157 §A` named the class and `0172` swept two names out of it, in 0157's own
-- words: *「`cron.schedule` returning (or, worse, being swallowed) is a claim; a row in `cron.job`
-- is the fact」*. A failed `cron.schedule` under that form COMMITS as a successful migration, and
-- nothing anywhere afterwards says the job is missing.
--
-- These four are the money/ops residue of that class — every one of them is the thing that repairs
-- a partial commit or pays somebody, and every one of them was registered swallowed:
--
--   | jobname                | schedule          | command                                  | registered |
--   |------------------------|-------------------|------------------------------------------|------------|
--   | club-payout-release    | `0 18 * * *`      | `select club_release_payouts()`          | `0045:443` |
--   | run-end-recovery       | `8-58/10 * * * *` | `select sweep_run_end_recovery()`        | `0083:1512`|
--   | cancel-money-gaps      | `6-56/10 * * * *` | `select sweep_cancel_money_gaps()`       | `0117:1652`|
--   | sweep-club-cancel-fees | `2-52/10 * * * *` | `select sweep_club_cancel_fee_intents()` | `0118:1338`|
--
--   ⚠ EACH OF THE FOUR IS REGISTERED EXACTLY ONCE IN THE WHOLE MIGRATION HISTORY — verified by
--     `grep -rn "'<jobname>'" supabase/migrations/` per name, not assumed from the audit table. So
--     there is no 「first registration vs later re-registration」 question to answer here: the
--     FIRST registration is also the LATEST one, and the tuples above are those lines. (`0126:142`
--     is the only `cron.unschedule` in the repo and it names `late-booking-sweep`, none of these.)
--
-- ⚠ THIS IS A READBACK, NOT A POLICY CHANGE. Every tuple below is byte-identical to its shipped
--   registration — same jobname, same schedule string, same command text. `cron.schedule` UPSERTS
--   on (jobname, username) in pg_cron >= 1.4 (and the harness stub models exactly that,
--   `00_shim.sql:102-112`), so this overwrites rather than duplicating. No cadence is chosen here,
--   so nothing in this file is PROVISIONAL.
-- ⚠ NO `exception` HANDLER, DELIBERATELY — `0157 §A`'s reason verbatim: an environment with no
--   scheduler must not be allowed to believe it has one. The harness ships a pg_cron registry stub,
--   so the strict form is EXERCISED here rather than merely asserted.
-- ⚠ NO `create extension if not exists pg_cron` — `0045:442` carries one inside its own swallowing
--   block, where a failure was invisible. Repeating it here would ABORT the local harness (no
--   pg_cron binary), which is the one environment that exercises the strict form. Production has
--   the extension because 0045 installed it; if it did not, `cron.schedule` below fails loudly,
--   which is the whole point.
-- ⚠ NO `cron.unschedule` BEFORE `cron.schedule` — 0172 does not use one and neither does this
--   file. It would buy nothing (the upsert already replaces the row) and it would COST: `L4` of the
--   same audit records that `cron.unschedule` raises `P0001` on an absent job, so on a fresh
--   database — the exact apply path this file exists to make honest — an unguarded unschedule
--   aborts before the schedule it was supposed to help.
-- ⚠ ONE ABORT DIRECTION IS KNOWN AND ACCEPTED, inherited from 0157 §A and 0172: if production's
--   existing job is owned by a DIFFERENT `username` than the role applying this file, the upsert
--   key differs, a second row appears, and VERIFY aborts on `found 2`. Loud, before anything moves,
--   and the message names the count.
--
-- 🔴 AND THE SENTENCE THIS HALF DOES **NOT** LICENSE, because the audit itself flags it (§(e) #1):
--   nobody has read production's `cron.job`. H3 is a claim about a MISSING GUARANTEE, not an
--   observed gap. After this file applies, 「these four are scheduled」 becomes a fact checked at
--   every apply; before it, it was never checked at all. That is the entire delta. If the
--   production apply of this file ABORTS, that abort is the first evidence anyone has ever had
--   about those rows — in either direction.
--
-- ⚠ OUT OF SCOPE, NAMED RATHER THAN SILENTLY OMITTED. Thirteen further jobs carry the same
--   swallowing form (`expire-unmatched` 0017, `expire-reschedules` 0021, `recurring-gen` 0026,
--   `club-series-gen` 0035, `club-min-attendance` 0037, `club-hold-expiry` 0043,
--   `club-assignment-recovery` 0047, `purge-holds` 0060, `owner-la-stale` 0063,
--   `club-stale-delegation-sweep` 0070, `sweep-payment-intents` 0076, plus `weekly-rewards` and
--   `purge-chat` 0014). H3 names four and this file registers four. Widening it to every swallowed
--   cron in the repo is a different slice with a different blast radius — and asserting a job I
--   have not read the registration of is how a byte-identical claim stops being byte-identical.
--   ⚠ `owner-la-stale` is on that list and IS touched below — by its FUNCTION (M10), never by its
--     registration. The two halves of this file do not meet.


-- ═══ §A — `club-payout-release`: the club payout window ════════════════════════════════════
-- Re-registration of `0045:443`, unswallowed. Identical jobname / schedule / command.
-- `club_release_payouts()` is the only thing that flips club payouts to released; if it was never
-- scheduled, nobody is paid and nothing says so.
do $$
begin
  perform cron.schedule('club-payout-release', '0 18 * * *',
                        'select club_release_payouts()');
end $$;


-- ═══ §B — `run-end-recovery`: the janitor behind every run that stopped ════════════════════
-- Re-registration of `0083:1512`, unswallowed. Identical jobname / schedule / command.
-- `0083 §9`'s own header: a booking that sealed and never settled, and a booking that stopped and
-- was never confirmed, are both permanent without this sweep.
do $$
begin
  perform cron.schedule('run-end-recovery', '8-58/10 * * * *',
                        'select sweep_run_end_recovery()');
end $$;


-- ═══ §C — `cancel-money-gaps`: the repair for a half-written cancellation ══════════════════
-- Re-registration of `0117:1652`, unswallowed. Identical jobname / schedule / command.
-- `0117 §9e` (blind review BLOCKER-5): a cancellation commits in one statement and the money that
-- follows it is written by later requests — a worker dying in between leaves a fee charged with no
-- runner compensation and no charge intent, and the retry path exits early on already-cancelled.
do $$
begin
  perform cron.schedule('cancel-money-gaps', '6-56/10 * * * *',
                        'select sweep_cancel_money_gaps()');
end $$;


-- ═══ §D — `sweep-club-cancel-fees`: the durable club-fee mint retry ════════════════════════
-- Re-registration of `0118:1338`, unswallowed. Identical jobname / schedule / command.
-- `0118 §F`: the ops-visible safety net for club cancel-fee mints that failed where SQL cannot
-- reach `_shared/ops.ts`.
do $$
begin
  perform cron.schedule('sweep-club-cancel-fees', '2-52/10 * * * *',
                        'select sweep_club_cancel_fee_intents()');
end $$;


-- ═══ VERIFY — the ARTIFACT, read back from `cron.job` ══════════════════════════════════════
-- `is distinct from`, never a bare `IF`: an aggregate cannot be NULL here, but every pin this repo
-- has lost to that collapse was a pin whose job was to notice that something is MISSING, which is
-- exactly this block's job.
--
-- ⚠ THE SCHEDULE **IS** ASSERTED HERE AND 0172 DELIBERATELY DID NOT ASSERT IT. That divergence is
--   a choice, with a reason: 0172's stated worry was 「a later slice may legitimately re-stagger a
--   cadence, and a VERIFY that aborts over a minute offset gets `--no-verify`'d」. A later slice
--   re-staggers in a LATER file, which applies after this VERIFY has already run — it cannot
--   redden this block. The only way the schedule assertion can abort is the one that should abort:
--   the literal in §A…§D drifting from the literal here. Which is the second reason —
-- ⚠ THE LITERALS ARE WRITTEN TWICE ON PURPOSE. A VERIFY that read the same variable the
--   registration wrote would be the first measurement printed twice, and a mistyped command in
--   §A would then satisfy it by construction. Two independent spellings of the same four tuples
--   means a typo in either place aborts the apply.
do $$
declare
  v_payout int; v_runend int; v_gaps int; v_clubfee int;
begin
  select count(*)::int into v_payout
    from cron.job
   where jobname = 'club-payout-release'
     and active
     and schedule = '0 18 * * *'
     and command  = 'select club_release_payouts()';

  select count(*)::int into v_runend
    from cron.job
   where jobname = 'run-end-recovery'
     and active
     and schedule = '8-58/10 * * * *'
     and command  = 'select sweep_run_end_recovery()';

  select count(*)::int into v_gaps
    from cron.job
   where jobname = 'cancel-money-gaps'
     and active
     and schedule = '6-56/10 * * * *'
     and command  = 'select sweep_cancel_money_gaps()';

  select count(*)::int into v_clubfee
    from cron.job
   where jobname = 'sweep-club-cancel-fees'
     and active
     and schedule = '2-52/10 * * * *'
     and command  = 'select sweep_club_cancel_fee_intents()';

  if v_payout  is distinct from 1 or v_runend  is distinct from 1
  or v_gaps    is distinct from 1 or v_clubfee is distinct from 1 then
    raise exception '0177 VERIFY FAILED: the four money/ops crons are not scheduled as written — expected exactly 1 active row each on (jobname, schedule, command); found club-payout-release=% run-end-recovery=% cancel-money-gaps=% sweep-club-cancel-fees=%',
      coalesce(v_payout::text,  'NULL'), coalesce(v_runend::text,  'NULL'),
      coalesce(v_gaps::text,    'NULL'), coalesce(v_clubfee::text, 'NULL');
  end if;
end $$;


-- ═══ §E (M10) — `owner_la_sweep_stale` takes a JOB-LEVEL LOCK ══════════════════════════════
-- `owner-la-stale` runs EVERY MINUTE (`0063:431`) and its dedupe is a read-then-write: each arm
-- reads `owner_la_tokens.last_state`, compares the line it is about to push, and `continue`s if it
-- matches. Two overlapping ticks both read the OLD `last_state` and both push — the owner's lock
-- screen gets 「N분째 위치가 갱신되지 않았어요」 twice for the same minute. Nothing in the function
-- serialises the ticks, and a per-row lock would not help: the duplicate is produced by the gap
-- between the read and the push, not by a row conflict.
--
-- The fix is `0117:1206`'s idiom, whose comment is the argument: *「ONE sweep at a time. try, not
-- wait: a slow predecessor must not queue ticks behind it」*. A session-scoped advisory lock keyed
-- on the function's own name; a duplicate tick returns 0 immediately instead of pushing.
--
-- ⚠ THE BODY BELOW IS `0083:1297-1376` VERBATIM — its latest definition (0063 → 0079 → **0083**),
--   extracted from that file rather than retyped. THREE lines are added and NOTHING else changes:
--   the acquire at the top, the release before `return v_n`, and the `exception when others` arm
--   that releases and RE-RAISES. The re-raise preserves today's behaviour exactly: 0083's body has
--   no handler, so an error propagates to the caller, and it still does.
-- ⚠ THE UNLOCK ON THE EXCEPTION PATH IS NOT OPTIONAL AND THE REASON IS THE LOCK'S SCOPE.
--   `pg_try_advisory_lock` is SESSION-scoped, not transaction-scoped: a tick that raises without
--   releasing leaves the lock held for the life of that backend, and every later tick on the same
--   connection returns 0 — the sweep would go permanently silent, which is the failure mode this
--   file is supposed to be removing. `0117:1275-1279` is the shape.
-- ⚠ `continue` IS NOT AN EXIT PATH. Both `continue`s below leave a loop ITERATION, not the
--   function; `return v_n` and the exception arm are the only two ways out, and both release.
-- ⚠ THE ACL IS RE-STATED IN THIS FILE, which `0083` did not do (it is line 82 of
--   `check-definer-acl-baseline.txt` for exactly that reason). On an apply where the function is
--   ABSENT this `create or replace` is a plain CREATE and the definer is born PUBLIC-executable
--   (`0116:636`). The pair below is the measured production ACL, re-stated rather than inherited:
--   `proacl = {postgres=X/postgres, service_role=X/postgres}` — service_role's EXECUTE arrives
--   through Supabase's default privileges on functions, so the explicit grant changes nothing and
--   makes the file true on every apply path instead of only the ordered one.

create or replace function owner_la_sweep_stale() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_last_t numeric; v_age int; v_min int; v_km numeric; v_line text; v_props jsonb;
  v_n int := 0;
begin
  -- [0177 · audit M10] ONE tick at a time. The dedupe in both arms below is a READ-then-WRITE on
  -- `owner_la_tokens.last_state` — each arm reads the stored line, compares the line it is about to
  -- push, and `continue`s when they match — so two overlapping minute ticks both read the OLD
  -- state and both push. `pg_try_advisory_lock(hashtextextended('owner_la_sweep_stale', 0))`, and
  -- TRY rather than wait (0117:1206's idiom and its argument): a slow predecessor must not queue
  -- ticks behind it, and this job fires every 60 seconds.
  -- ⚠ This comment NAMES the call on purpose. 208's source pin strips comments before matching, so
  --   if that strip were ever dropped, this line alone would satisfy a check for the lock — which
  --   is precisely the class the strip exists for (a comment explaining a fix is indistinguishable
  --   from the fix to any grep that reads prosrc raw).
  if not pg_try_advisory_lock(hashtextextended('owner_la_sweep_stale', 0)) then return 0; end if;
  for r in
    select t.booking_id, t.last_state, run.trace, b.km as target_km,
           d.name as dog_name, coalesce(p.name, '러너') as runner_name
      from owner_la_tokens t
      join bookings b on b.id = t.booking_id and b.status = 'active'
                     and b.run_ended_at is null            -- [0083] 러닝 구간 전용
      join runs run on run.booking_id = b.id
      join dogs d on d.id = b.dog_id
      left join profiles p on p.id = b.runner_id
  loop
    -- No fix ever received → the LA is still on the handoff card; there is no number to grey out.
    if coalesce(jsonb_array_length(r.trace), 0) < 2 then continue; end if;
    v_last_t := (r.trace->-1->>'t')::numeric;
    v_age := floor(extract(epoch from now()) - v_last_t)::int;
    if v_age < 90 then continue; end if;

    v_min := greatest(1, v_age / 60);
    v_line := v_min || '분째 위치가 갱신되지 않았어요';
    if coalesce(r.last_state->>'phase', '') = 'stale'
       and coalesce(r.last_state->>'statusLine', '') = v_line then
      continue;  -- same minute already pushed
    end if;

    v_km := _owner_la_trace_km(r.trace);
    v_props := jsonb_build_object(
      'phase', 'stale',
      'dogName', r.dog_name,
      'runnerName', r.runner_name,
      'km', case when v_km < 0.01 then '' else to_char(v_km, 'FM999990.00') end,
      'targetKm', rtrim(rtrim(to_char(r.target_km, 'FM999990.0'), '0'), '.'),
      'pace', '',
      'elapsed', '',
      'statusLine', v_line,
      'paceState', '');                                      -- [0079] stale never carries a claim
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;

  -- [0083 §8-ⓑ] 귀가 arm — freshness from the heartbeat, never from the trace (plan §5)
  for r in
    select t.booking_id, t.last_state,
           coalesce(b.custody_last_seen_at, b.run_ended_at) as seen_at,
           run.actual_km, run.duration_sec,
           d.name as dog_name, coalesce(p.name, '러너') as runner_name
      from owner_la_tokens t
      join bookings b on b.id = t.booking_id and b.status = 'active'
                     and b.run_ended_at is not null
      left join runs run on run.booking_id = b.id
      join dogs d on d.id = b.dog_id
      left join profiles p on p.id = b.runner_id
  loop
    v_age := floor(extract(epoch from (now() - r.seen_at)))::int;
    if v_age < 90 then continue; end if;              -- a beating heart says nothing new

    v_min := greatest(1, v_age / 60);
    v_line := v_min || '분째 위치 신호가 없어요';
    if coalesce(r.last_state->>'statusLine', '') = v_line
       and coalesce(r.last_state->>'phase', '') = 'homeward' then
      continue;                                       -- same minute already pushed (arm ① idiom)
    end if;

    v_props := jsonb_build_object(
      'phase', 'homeward',
      'dogName', r.dog_name,
      'runnerName', r.runner_name,
      'km', case when r.actual_km is null then '' else to_char(r.actual_km, 'FM999990.00') end,
      'targetKm', '',
      'pace', '',
      'elapsed', case when r.duration_sec is null then '' else _owner_la_fmt_elapsed(r.duration_sec) end,
      'statusLine', v_line,
      'paceState', '');
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;
  -- [0177 · audit M10] the happy exit releases the job lock.
  perform pg_advisory_unlock(hashtextextended('owner_la_sweep_stale', 0));
  return v_n;
exception when others then
  -- [0177 · audit M10] AND SO DOES THE FAILING EXIT — the lock is SESSION-scoped, not
  -- transaction-scoped, so a tick that raised without `pg_advisory_unlock(...)` would leave it
  -- held for the life of the backend and every later tick on that connection would return 0. The
  -- sweep would go permanently silent, which is worse than the duplicate push M10 is about.
  -- `raise` re-raises unchanged: 0083's body carried no handler, so an error reached the caller,
  -- and it still does. 0117:1275-1279 is the shape.
  perform pg_advisory_unlock(hashtextextended('owner_la_sweep_stale', 0));
  raise;
end $$;

revoke execute on function owner_la_sweep_stale() from public, anon, authenticated;
grant  execute on function owner_la_sweep_stale() to service_role;

comment on function owner_la_sweep_stale is
  '0083 §8 (was 0079/0063) + [0177 M10]: 스테일 스윕 두 팔. ① 러닝 구간(run_ended_at is null)만
트레이스 기준 90초 무갱신을 stale로 — 귀가에는 트레이스가 의도적으로 멈추므로 그 팔이 들어가면
매 귀가마다 거짓 경고가 나간다. ② 귀가 구간은 custody_last_seen_at(하트비트) 기준 — 러너 폰이
죽어도 "집으로 가는 중"이 영원히 살아있지 않게 (plan §5, codex #9). [0177] 작업 단위 락:
owner-la-stale 은 매 분 돌고 두 팔의 중복 제거는 last_state 를 읽고-쓰는 형태여서 겹친 틱 둘이
같은 줄을 두 번 밀어낸다. pg_try_advisory_lock(hashtextextended(''owner_la_sweep_stale'', 0)) 로
한 번에 한 틱만 — 대기가 아니라 try, 그리고 세션 스코프이므로 정상/예외 두 출구 모두에서 해제한다
(0117:1206/1275-1279 관용구). 본문은 0083 의 것 그대로이고 바뀐 것은 그 세 줄뿐이다. 핀: 208
0177-S6/S7'
;
