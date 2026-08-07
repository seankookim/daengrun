-- 0061 — P0: seal the runners INSERT path.
--
-- The hole: `runners self insert` (0002_rls.sql:71) checks only `profile_id = auth.uid()`, and
-- `_guard_runner_cols` (0057) is attached `before update` ONLY. So any authenticated user could
-- insert their own runners row with arbitrary privileged values. Verified by execution against a
-- harness cluster as role `authenticated`:
--
--   insert into runners (profile_id, tier, commission_rate, identity_verified)
--   values (auth.uid(), 'master', 0, true);
--   -- SUCCEEDED: tier=master  commission_rate=0.000  identity_verified=t
--
-- Three consequences, all live on production since 0057 shipped:
--   1. Certification bypass — transition-booking's `tier === 'applicant'` gate passes, so an
--      unvetted stranger can accept a booking and take physical custody of someone's dog.
--   2. Payout theft — settle-run reads commission_rate; 0 means the platform's cut is zero.
--   3. Safety-claim forgery — identity_verified=true is what the owner-facing trust copy rests on.
--
-- Cost to exploit: one free signup. No prior state needed.
--
-- That 0057 used `before insert or update` for _guard_runner_doc_verify (0057:539) but
-- `before update` for this one makes it an oversight, not a decision.
--
-- Fix shape: FORCE the privileged columns to their safe defaults on client INSERT rather than
-- raising. Rationale — the legitimate client payload (api.ts ensureRunner: tier 'applicant',
-- funnel_step 'info', identity_verified false) already equals these defaults, so no shipped app
-- build changes behavior; an old build in the wild cannot be broken by this migration; and an
-- attacker learns nothing (no error to distinguish "blocked" from "allowed" — no oracle).
-- Service-role paths (seed scripts, edge functions, ops) are untouched, exactly as with the
-- UPDATE guard.

create or replace function _guard_runner_insert_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    -- 서버가 정하는 값은 클라 INSERT에서 전부 기본값으로 되돌린다 (거절이 아니라 강등).
    -- 열 목록은 _guard_runner_cols(0057)의 UPDATE 보호 목록과 1:1로 같아야 한다.
    new.tier                   := 'applicant';
    new.funnel_step            := 'info';
    new.identity_verified      := false;
    new.insurance_active       := false;
    new.trainer_certified      := false;
    new.education_modules_done := 0;
    new.total_runs             := 0;
    new.total_km               := 0;
    new.completion_rate        := null;
    new.compliance_pct         := null;
    new.respond_rate_pct       := null;
    new.commission_rate        := 0.20;
  end if;
  return new;
end $$;

drop trigger if exists _guard_runner_insert_cols on runners;
create trigger _guard_runner_insert_cols before insert on runners
  for each row execute function _guard_runner_insert_cols();

comment on function _guard_runner_insert_cols is
  '0061 P0 — 러너 자가 등록 시 권한 열을 기본값으로 강등. 0002 self insert 정책은 소유자만 확인하고 '
  '0057 가드는 UPDATE 전용이라, 누구나 tier=master·commission_rate=0·identity_verified=true로 '
  '자기 러너 행을 만들 수 있었다. 열 목록은 _guard_runner_cols와 동기 유지.';
