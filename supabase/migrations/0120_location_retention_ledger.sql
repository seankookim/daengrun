-- ═══ 0120: 위치정보법 — the one-year destruction floor and the 제16조 확인자료 ledger ═══
--
-- Suite 155. Numbers: 0120/155 taken because 0117 and 0118 are in flight and the announcer
-- allocated 0119/154 to the 맹견 (dangerous-dog) slice running in parallel tonight; this file is
-- the offset-by-one. If that allocation was wrong, the announcer arbitrates and this file renames.
--
-- ═══ §0 THE TWO OBLIGATIONS, AND WHY NEITHER IS A DRAFTING FIX ═══
-- Legal measured both on 2026-08-19 and ranked them ABOVE the 맹견 gate because they matter at the
-- first real runner (`docs/legal/readiness-review-2026-08-19.md:411-448`,
-- `docs/handoff-codex/legal-ops-domain.md:2.7 / 5.1 / 5.2`, queued at
-- `docs/decisions/awaiting-sean.md` §0-sexdecies with "nothing for Sean"):
--
--   ⓐ **Nothing purges `runs.trace`.** MEASURED on trunk: 17 `cron.schedule` calls exist; the only
--      two purges are `purge-chat` (0014) and `purge-holds` (0060). `runs.trace` (`0001:243`,
--      `[{lat,lng,t,v}]`) has three writers — `club_save_run_trace` (0038 → 0050 → 0053),
--      `saveRunTrace` (`api.ts:2118`) and `end_run_tx` (`0083:439`) — and **no deleter anywhere in
--      the repo**. `0115_account_deletion.sql:84` disclaims it in-file: *"this purge is owned
--      elsewhere, for EVERY run, not only deleted ones."* Owned elsewhere resolved to nobody.
--      위치정보법 시행령 제26조의2 caps 개인위치정보 at **one year even with separate retention
--      consent**; `privacy-policy.md:98` says "필요한 기간", which is not a period and cannot become
--      one by drafting.
--
--   ⓑ **No 이용·제공 사실 확인자료 ledger exists.** 위치정보법 제16조 requires the fact of every use
--      and provision of 개인위치정보 to be recorded **automatically**; the 안전조치 기준 require the
--      ledger to be kept **≥ 6 months**. `privacy-policy.md:95` already promises the 열람·고지 right.
--      Six log-shaped tables exist in `public`; none of them is this one.
--
-- Softening §3/§5 of the policy would delete the EVIDENCE of the gap, not the gap: both duties are
-- statutory, not contractual. So both halves are builds, and they are one file because they are one
-- statute and because the second is what makes the first honest — a purge with no record of what it
-- destroyed is indistinguishable from data loss.
--
-- ═══ §0a THE READ PATH THIS ACTUALLY CLOSES — measured, and it is not the one the client uses ═══
-- `runs` carries `"runs party read" … using (is_booking_party(booking_id))` (`0002:106`), and no
-- migration has ever issued a GRANT or REVOKE on `runs` — so `anon`/`authenticated` hold
-- **table-level** privileges from Supabase's default ACL. The shipped client reads `runs.trace` at
-- three sites, all as the runner (`api.ts:2125` ← `runner/run.tsx:265`, `runner/done.tsx:79`; plus a
-- raw select at `club/run/[sid].tsx:88`).
--
-- ⚠ **But the policy admits the OWNER too**, and an owner reading the runner's coordinate track is
-- 제공 of 개인위치정보 to a 열람자 — the exact event 제16조 exists to record. That path is open over
-- PostgREST today with the shipped key and an ordinary owner JWT, and it leaves no trace of itself.
-- The client not using it is not a control (REGISTRY: *"An empty result is not a control"*), and the
-- REGISTRY's own detector ① law applies: ask the engine what it permits, never the caller.
--
-- So §D closes the raw column and §E re-opens it as ONE window that records. That is 0113's shape
-- for `routes.trace` applied to the other trace — with the difference that this one must record,
-- because this one is a live person's whereabouts and not a de-identified public course.
--
-- ⚠⚠ **A COLUMN REVOKE AGAINST A TABLE-LEVEL GRANT IS A NO-OP.** PostgreSQL's `REVOKE SELECT (col)`
-- does not touch a table-wide SELECT, so `revoke select (trace) on runs` alone would be a gate that
-- exists and does not guard. 0113 could spell it that way only because 0107 had already revoked
-- table-wide on `routes` and re-granted a column whitelist. `runs` has had neither, so §D does both
-- in one breath: revoke the table, grant the thirteen survivors by name.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** CLOSE — said out loud (0073/0075/0114 §0d's law) ═══
-- ⓐ **The live broadcast channel is not ledgered.** `run2-<booking>` (0104) carries the runner's
--    position to the owner in realtime and is 제공 in the plainest sense. It never touches a table,
--    and a `realtime.messages` RLS policy cannot write a ledger row (a SELECT policy that mutates is
--    not a policy). Recording it needs a client/edge call, which is a different slice. **Named, not
--    silently skipped:** the ledger built here covers the STORED trace, which is what the counsel
--    brief §2 separates as 보유(제23조) from 제공(제19조).
-- ⓑ **`booking_pickup_address` (0060 §2) stays unlogged.** Two reasons, and the second is the
--    binding one: a fixed home address is 개인정보, not the 위치정보 of a moving person, so 제16조
--    does not reach it; and whether to log gate-code/address viewing is an OPEN SEAN DECISION
--    (`awaiting-sean.md` §0-septemvicies item 2, verbatim from `0060:52-53`). This file does not
--    pre-empt it. `gate_code_access_log` is likewise left exactly as it is — an empty shell
--    (`0060:52`), and deliberately NOT the pattern copied here.
-- ⓒ **No admin/ops access path is ledgered**, because there is none to hook: `0082:174` records
--    that this repo has no admin role in RLS; ops access is the service key and the SQL console
--    (`legal-ops-domain.md` §6-quinquies ⑦). service_role reads `runs.trace` directly and this file
--    deliberately does not break that (settlement, `_owner_la_*`, seeds all depend on it).
-- ⓓ **No consent record, no 위치기반서비스 이용약관, no KCC 신고.** Those are §5.3/§5.4/§5.5 and two
--    of the three are blocked on counsel. This file is only the two that legal marked
--    *"Blocked on: nothing."*
-- ⓔ **The privacy policy is not edited here.** `privacy-policy.md:98`'s "필요한 기간" can now become a
--    period, and `:95`'s 열람권 now has something behind it — but that document carries a
--    DECIDE-BEFORE-PUBLICATION header and its wording is Sean's and counsel's, not a migration's.
--
-- ═══ §0c THE TWO NUMBERS, AND WHY NEITHER NEEDED A LAWYER ═══
-- **The cap is one year** because that is the statutory ceiling (시행령 제26조의2) and the repo's own
-- legal review names it four times. A SHORTER period would be a product decision (the statute also
-- requires destruction once the purpose is achieved); a LONGER one is simply unlawful. Shipping the
-- ceiling is the choice that cannot be wrong, and §C makes it one named function so shortening it is
-- a one-line edit whose effect is recorded per row in `location_retention_log.cap`.
-- ⚠ **No dispute carve-out, deliberately.** "분쟁 대응에 필요한 기간" is the policy's phrase for the
-- run record; it cannot extend the LOCATION half, because 제26조의2 caps it at one year *even with
-- separate retention consent*. An open incident does not buy more time for coordinates. The rest of
-- the run row — km, pace, photos, money — is untouched by this purge and keeps its own retention.
-- **"Access" is defined here as: a call that actually hands 개인위치정보 to a caller.** Server-internal
-- processing of the same column (`_owner_la_trace_km`, settlement) is 이용 by the operator through
-- code that returns no coordinates to anyone, and is not ledgered; a call that returns zero points
-- provided nothing and records nothing (`0049:236`'s "실제 반환된 번호만" applied verbatim). If counsel
-- later rules that operator-internal 이용 must also be recorded, the hook is one insert in §G.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §A. 제16조 이용·제공 사실 확인자료 — the ledger
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Shape copied from `club_phone_access_log` (`0049:156-163`) — **live**, with real writers at
-- `0049:236` and `0053:435` — and explicitly NOT from `gate_code_access_log` (`0001:130`), which
-- `0060:52-53` records as *"한 번도 쓰인 적 없는 빈 껍데기"*. Legal named both and said which to copy.
--
-- 🔴 **THE FK SHAPES ARE LOAD-BEARING AND WERE CHOSEN AGAINST A WATCHDOG THAT IS ALREADY ARMED.**
-- `0115_account_deletion.sql:755-833` carries a `%access_log` WILDCARD in its §F deletion watchdog,
-- put there specifically for this unbuilt table, and suite 150 mutation-tested it both ways
-- (`150:118-148`): a `location_access_log(profile_id → profiles ON DELETE SET DEFAULT)` reddens
-- N6-2 alone. **Every FK here is NO ACTION** — the two referential actions that REFUSE a delete are
-- the only two that are safe for a retention record, and enumerating the dangerous ones rather than
-- the safe ones is 0115's own correction. A ledger that can be cascaded away is not a ledger.
--
-- ⚠ **NO COORDINATE MAY EVER LIVE IN THIS TABLE.** A ledger that stored the track it recorded the
-- reading of would defeat §G entirely — the purge would empty `runs.trace` and leave a perfect copy
-- behind under an audit label. Counts and times only. Suite 155 L6 pins the column set so the day
-- someone adds `lat`/`lng`/a jsonb payload, it goes red.
create table if not exists location_access_log (
  id                 bigint generated always as identity primary key,
  run_id             uuid not null references runs(id),              -- NO ACTION: evidence refuses to be cascaded
  subject_profile_id uuid not null references profiles(id),          -- 개인위치정보주체 — whose device recorded it
  viewer_profile_id  uuid not null references profiles(id),          -- 이용자 / 제공받은 자
  viewer_relation    text not null check (viewer_relation in ('subject', 'owner')),
  access_kind        text not null check (access_kind in ('run_trace_read')),
  point_count        int  not null check (point_count > 0),          -- 0 points = nothing provided = no row
  accessed_at        timestamptz not null default now()
);
alter table location_access_log enable row level security;   -- 정책 없음 — 0049 패턴 (ops 전용)
revoke all on location_access_log from anon, authenticated;
-- Belt AND braces on purpose. RLS-with-no-policies is the house seal, but 0109's own history is that
-- default privileges keep handing new tables to client roles, and 0095 is the table that sat open
-- because a listing could not tell "RLS off" from "RLS on, no policies". Both are stated here.

create index if not exists location_access_log_subject_idx
  on location_access_log (subject_profile_id, accessed_at desc);
create index if not exists location_access_log_dedup_idx
  on location_access_log (run_id, viewer_profile_id, accessed_at desc);

comment on table location_access_log is
  '위치정보법 제16조 이용·제공 사실 확인자료. 개인위치정보(runs.trace)가 실제로 호출자에게 건네진 사건만 기록한다 — 0행을 돌려준 호출은 제공이 아니므로 기록하지 않는다(0049:236 관용구). 보존 하한 6개월(안전조치 기준)이며 상한은 없다: 확인자료는 위치정보 그 자체가 아니므로 시행령 제26조의2의 1년 상한이 적용되지 않는다 — 0120 §G의 파기 대상이 아니다. ⚠ 좌표를 절대 담지 않는다(담으면 파기가 무의미해진다). 모든 FK는 NO ACTION — 0115 §F의 %access_log 와일드카드가 겨냥한 바로 그 테이블이다.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §B. 파기 기록 — what the purge destroyed, and under which cap
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- "Never a silent mass delete" made structural. Without this table the purge is an UPDATE that
-- leaves the world looking exactly as if the traces had never been written — indistinguishable from
-- a bug that wiped them, and unanswerable when a 주체 asks what happened to their record.
-- `cap` is stored per row rather than assumed, so shortening the constant later is legible in the
-- data instead of only in a diff.
create table if not exists location_retention_log (
  id                 bigint generated always as identity primary key,
  run_id             uuid not null references runs(id),              -- NO ACTION, same reason as §A
  subject_profile_id uuid references profiles(id),                   -- nullable: see the note below
  points_removed     int not null check (points_removed > 0),
  anchor_at          timestamptz not null,                           -- the instant the cap was measured against
  cap                interval not null,                              -- the cap ACTUALLY applied, recorded not inferred
  purged_at          timestamptz not null default now()
);
alter table location_retention_log enable row level security;   -- 정책 없음
revoke all on location_retention_log from anon, authenticated;

create index if not exists location_retention_log_run_idx on location_retention_log (run_id);

-- ⚠ `subject_profile_id` is NULLABLE and that is a decision, not an oversight. It comes from
-- `bookings.runner_id`, which is nullable (`0001:...`, matching 전 null). A NOT NULL here would make
-- one malformed row raise inside a set-based purge and abort the whole sweep — 0111's lesson
-- (*"continue + raise warning, never raise — one row would abort the whole hourly sweep forever"*)
-- in a place where the sweep's job is to DESTROY data on a legal deadline. A purge that stops is
-- worse than a log line with a null in it. This column is a record, not a gate; nothing branches on
-- it (the fleet's NULL-fail-open rule is about gates, and §G's gate is `anchor_at`, which cannot be
-- null — see there).
comment on table location_retention_log is
  '0120 §G 파기 기록. 어떤 런의 좌표 몇 점을, 어느 시점을 기준으로, 어떤 상한을 적용해 지웠는지 — 좌표는 담지 않는다. 위치정보 파기는 조용해선 안 된다: 기록 없는 대량 삭제는 버그와 구별되지 않는다.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §C. The cap, in exactly one place
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 시행령 제26조의2. Shortening it is a one-line edit here; lengthening it past a year is unlawful and
-- the comment says so where the next reader will be standing.
create or replace function location_retention_cap() returns interval
language sql immutable
set search_path = public, pg_temp
as $$ select interval '1 year' $$;
comment on function location_retention_cap is
  '개인위치정보 보유 상한 (위치정보법 시행령 제26조의2 — 별도 보유 동의가 있어도 1년). 짧게 줄이는 것은 제품 판단이고 여기 한 줄이다. 늘리는 것은 위법이다.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §D. Close the raw column (0113's step-3 shape, with the table-level correction from §0a)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE ORDER MATTERS AND THE CLIENT MOVES WITH THIS FILE. Revoking a column a shipped binary
-- selects does not hide a field — PostgREST fails the WHOLE request (0088: `revoke select (role)` on
-- `profiles` 403'd every signup until 0091 put it back). The three read sites move to §E's RPC in
-- the same commit. The precondition 0113 §0c measured — **zero EAS builds have ever been produced,
-- TestFlight never uploaded**, so no installed binary can hold old code — is the same precondition
-- here and it is still the reason this is free today. ⚠ It is a PRECONDITION TO RE-CHECK, not a
-- measurement this file took: if a build has been uploaded since 2026-08-19, §D must wait for an OTA.
--
-- The thirteen survivors are every column of `runs` except `trace`, enumerated by name because the
-- alternative — a table grant with a column revoke — does nothing at all (§0a).
-- ⚠ A column added to `runs` after today will NOT be client-readable until its migration grants it.
-- That is the standing cost of a whitelist and it is the same cost `routes` has carried since 0107.
-- Suite 155 L10c pins the column count so the omission surfaces as a red pin, not as a blank screen.
revoke select on runs from public, anon, authenticated;
grant select (
  id, booking_id, started_at, ended_at, actual_km, duration_sec, avg_pace_sec_per_km,
  end_reason, condition_note, photos, events, pace_suggest_sec, settled_at
) on runs to anon, authenticated;
-- INSERT/UPDATE/DELETE are untouched: `saveRunTrace` (`api.ts:2118`) writes `trace` through
-- `"runs runner update"` (0057 §5) and must keep working — the live append surface is not the
-- provision surface. `service_role` is untouched everywhere (settlement, `_owner_la_*`, seeds).

comment on column runs.trace is
  '러닝 중 러너 기기의 실좌표열 [{lat,lng,t,v}] — 식별되는 개인의 위치정보(위치정보법). 0120 이후 클라이언트 역할은 이 컬럼을 직접 읽지 못한다: 유일한 창구는 run_trace_read()이고, 그 호출은 제16조 확인자료를 남긴다. service_role은 그대로 읽는다(정산·LA·시드). 보유 상한 1년 — purge_expired_run_traces()가 상한을 넘긴 행의 이 컬럼을 비운다(행은 남는다).';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §E. The one window — reads the trace, records the reading
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- **VOLATILE, and that is the whole point.** `0060:52-53` declined to log `booking_pickup_address`
-- precisely because a log would make it volatile, and left the decision open. This function is born
-- on the other side of that trade: the record is not a side effect of the read, it is a
-- **precondition of it**. Both statements run in one transaction, insert first, so a ledger that
-- cannot be written means coordinates that are not handed out. Suite 155 L18 executes that.
--
-- Gate order, and it is not stylistic: party gate BEFORE any state or existence gate, and
-- **absent / not-yours return the SAME exception** — a booking that does not exist and a booking
-- that is not yours both answer `not_party`, or the difference between them is an enumeration
-- oracle (`0054:73`, `0067 §C`, `0060 §2`'s own reasoning).
--
-- 목적/관계 are SERVER-DERIVED. A client-supplied "purpose" string in a statutory ledger is
-- attacker-authored free text; the only honest 목적 is the operation, and the only honest 관계 is
-- what the booking says the caller is.
create or replace function run_trace_read(p_booking uuid) returns jsonb
language plpgsql volatile security definer
set search_path = public, pg_temp
as $$
declare
  v_uid      uuid := auth.uid();
  v_run_id   uuid;
  v_trace    jsonb;
  v_owner    uuid;
  v_runner   uuid;
  v_relation text;
  v_points   int;
begin
  -- ⚠ SECURITY DEFINER: `current_user` here is the function OWNER, never the caller. auth.uid() is
  -- the only thing that identifies a human, and a null one is refused explicitly — a definer that
  -- lets a JWT-less caller through is a definer with no gate at all.
  if v_uid is null then raise exception 'not_signed_in'; end if;

  -- ① 당사자 게이트 — 부재도 타인도 같은 답
  if not coalesce(is_booking_party(p_booking), false) then
    raise exception 'not_party';
  end if;

  select r.id, r.trace, b.owner_id, b.runner_id
    into v_run_id, v_trace, v_owner, v_runner
    from runs r join bookings b on b.id = r.booking_id
   where r.booking_id = p_booking;

  -- ② 빈 결과 ≠ 오류 (0060 §2의 자세). 아직 런이 없으면 클라는 '기록 없음'으로 그린다.
  if v_run_id is null then return '[]'::jsonb; end if;

  v_points := case when jsonb_typeof(v_trace) = 'array' then jsonb_array_length(v_trace) else 0 end;

  -- ③ 제공된 개인위치정보가 0점이면 제공 사실이 없다 → 확인자료도 없다 (0049:236 "실제 반환된 것만").
  --    파기된 런(§G가 비운 trace)이 여기로 떨어진다 — 파기 뒤의 열람이 유령 기록을 낳지 않는다.
  if v_points = 0 then return '[]'::jsonb; end if;

  -- ④ 주체 없는 좌표는 내주지 않는다. runner_id가 null이면 이 트레이스의 개인위치정보주체를
  --    적을 수 없고, 주체를 적을 수 없는 제공은 제16조를 만족시킬 수 없다 — 그래서 거절한다
  --    (기록 없이 내주는 쪽이 아니라). NULL은 여기서도 닫는 방향이다.
  if v_runner is null then raise exception 'not_party'; end if;

  v_relation := case when v_runner = v_uid then 'subject'
                     when v_owner  = v_uid then 'owner' end;
  if v_relation is null then raise exception 'not_party'; end if;   -- coalesce 대신 명시 — NULL은 거절

  -- ⑤ 제16조 기록. 반환보다 먼저, 같은 트랜잭션. 이 insert가 실패하면 좌표는 나가지 않는다.
  --    dedup 10분: 0053:435의 창(club_phone_access_log)과 같은 관용구 — 재진입·재마운트가 대장을
  --    도배하는 것을 막되, 창이 지나면 새 사건으로 다시 기록된다(억제가 아니라 창이다).
  insert into location_access_log
    (run_id, subject_profile_id, viewer_profile_id, viewer_relation, access_kind, point_count)
  select v_run_id, v_runner, v_uid, v_relation, 'run_trace_read', v_points
   where not exists (
     select 1 from location_access_log l
      where l.run_id = v_run_id
        and l.viewer_profile_id = v_uid
        and l.access_kind = 'run_trace_read'
        and l.accessed_at > now() - interval '10 minutes');

  return v_trace;
end $$;
revoke execute on function run_trace_read(uuid) from public, anon;
grant execute on function run_trace_read(uuid) to authenticated;
comment on function run_trace_read is
  '0120 §E — runs.trace 로 가는 유일한 클라이언트 창구. 당사자 게이트(부재·타인 동일 응답) → 제16조 확인자료 기록 → 좌표 반환. 기록이 반환보다 먼저이고 같은 트랜잭션이므로 "기록 없이 제공"이 구조적으로 불가능하다. 0점 반환은 제공이 아니므로 기록하지 않는다. VOLATILE인 이유가 바로 이 기록이다(0060:52의 트레이드를 반대편에서 받은 것).';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §F. 열람권 — the right `privacy-policy.md:95` already promises
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- The table stays sealed (RLS on, no policies, no client grant); the right is delivered through a
-- narrow definer window that returns the caller's OWN rows only. That is the 0060 §2 창구 shape and
-- it avoids opening a table read path that no UI exists to use yet.
-- ⚠ There is still no SCREEN for this (`legal-ops-domain` §6-quinquies ⑨ lists all four user-facing
-- controls as absent). What changes today is that the answer exists and can be produced — by a
-- client screen, or by ops answering a 고지 요구 with one call instead of with an apology.
create or replace function my_location_access_log(p_limit int default 200)
returns table (
  accessed_at    timestamptz,
  viewer_name    text,
  viewer_relation text,
  access_kind    text,
  point_count    int,
  booking_id     uuid,
  scheduled_at   timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  -- ⚠ EVERY column reference below is alias-qualified, and that is required rather than tidy:
  -- `returns table (…)` puts `accessed_at`, `booking_id`, `point_count` … into scope as plpgsql
  -- VARIABLES for the whole body, and each is also a column name in the query. plpgsql substitutes
  -- only UNqualified identifiers, so `l.accessed_at` is the column and a bare `accessed_at` would
  -- be the (empty) output variable. Do not "simplify" the aliases away.
  return query
    select l.accessed_at, p.name, l.viewer_relation, l.access_kind, l.point_count,
           r.booking_id, b.scheduled_at
      from location_access_log l
      join runs r     on r.id = l.run_id
      join bookings b on b.id = r.booking_id
      left join profiles p on p.id = l.viewer_profile_id
     where l.subject_profile_id = auth.uid()
     order by l.accessed_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;
revoke execute on function my_location_access_log(int) from public, anon;
grant execute on function my_location_access_log(int) to authenticated;
comment on function my_location_access_log is
  '위치정보법 제16조 열람·고지 요구권 (privacy-policy.md:95가 이미 약속한 권리). 호출자가 개인위치정보주체인 행만 돌려준다 — 대장 테이블 자체는 봉인된 채로 남는다.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §G. The purge — bounded, resumable, and it writes down what it destroyed
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **THE ANCHOR IS THE WHOLE CORRECTNESS ARGUMENT, AND THE OBVIOUS SPELLING IS THIS REPO'S
-- SIGNATURE BUG.** `where ended_at < now() - cap` looks right and fails open: `runs.ended_at` is
-- NULLABLE (`0001:236`), and a run that never ended — crashed client, abandoned session, an
-- `end_run_tx` that never ran — would then be kept **forever**, which is exactly the row whose
-- coordinates are most orphaned. NULL fail-open is this codebase's recurring defect (0058 F1,
-- 110 S2, 0116 §D) and it would land here in the one place where "keep it" is the violation.
--
-- So the anchor is `least(greatest(ended_at, started_at, bookings.created_at), now())`:
--   · `greatest` ignores NULL arguments and returns NULL only if ALL are null — and
--     `bookings.created_at` is NOT NULL (`0001:...`), while `runs.booking_id` is NOT NULL and
--     references it. **The anchor therefore cannot be null for any row that exists.** There is no
--     NULL branch to get wrong.
--   · It takes the LATEST real event, so the clock never starts before the data did.
--   · `least(…, now())` clamps a corrupt FUTURE timestamp. Without it, one bad `ended_at` in 2099
--     keeps a track forever — fail-open again, wearing a different hat. With it, such a row becomes
--     purgeable one year from today. The clamp can only ever DELAY a purge relative to a correct
--     timestamp, never advance it, so it cannot destroy anything early.
--
-- **The row is not deleted. The column is emptied.** `runs` is a retention table (money, settlement,
-- km ledger, route evidence all hang off it); destroying the row to destroy the coordinates would
-- take the ledger with it. 제26조의2 asks for the 개인위치정보 to be destroyed, not the transaction.
--
-- **Bounded and resumable** by `p_limit`, oldest first: a set-based UPDATE with no bound is one
-- statement that can lock every historical run at once, and `remaining` in the return makes a
-- backlog visible instead of silent. Re-running continues where it stopped — the predicate itself is
-- the cursor (`trace <> '[]'`), so there is no state to lose.
-- ⚠ `p_limit => 0` is a **DRY RUN**: it clears nothing and returns `remaining` = how many rows are
-- past the cap right now. Ops can ask "what would this destroy?" without destroying it, and suite
-- 155 uses it to take a baseline so its counts do not depend on what other suites left lying around.
--
-- ⚠ Emptying `trace` fires `owner_la_trace` (`after update of trace on runs`, latest body at
-- `0083:1204`). Verified by reading it: its first substantive guard is
-- `if coalesce(jsonb_array_length(new.trace),0) < 2 then return new`, and `'[]'` is length 0 — so a
-- purge cannot push a "running" Live Activity update at a year-old booking. That guard is now
-- load-bearing for a second reason; if it is ever removed, this is the other caller.
create index if not exists runs_trace_retention_idx
  on runs (ended_at) where trace <> '[]'::jsonb;

-- ⚠ The OUT parameters are `purged_runs`/`purged_points`/`remaining_runs`, not the obvious
-- `points_removed`. `returns table (…)` puts every output name into scope as a plpgsql VARIABLE for
-- the whole body, and `points_removed` is also a COLUMN of `location_retention_log` that this body
-- names in an INSERT — a shadowing question I would rather not have to be right about in a file
-- nobody can re-run by hand. Renaming the outputs removes the question instead of answering it.
create or replace function purge_expired_run_traces(p_limit int default 500)
returns table (purged_runs int, purged_points int, remaining_runs int)
language plpgsql volatile security definer
set search_path = public, pg_temp
as $$
declare v_cap interval := location_retention_cap();
begin
  -- ⚠ SECURITY DEFINER, owner = postgres. That is what lets this bypass `runs`' RLS, and it is also
  -- why `_guard_run_cols` (0057 §5, security INVOKER, gated on `current_user in ('authenticated',
  -- 'anon')`) does not fire against it: inside a definer, `current_user` is the OWNER, never the
  -- caller. Here that asymmetry is wanted. Anywhere it is used to identify a caller it is a bug.
  return query
  with due as (
    select r.id,
           least(greatest(r.ended_at, r.started_at, b.created_at), now()) as anchor_at,
           b.runner_id,
           case when jsonb_typeof(r.trace) = 'array' then jsonb_array_length(r.trace) else 1 end as points
      from runs r
      join bookings b on b.id = r.booking_id
     where r.trace <> '[]'::jsonb
  ),
  overdue as (
    select * from due where anchor_at < now() - v_cap
  ),
  picked as (
    select * from overdue order by anchor_at, id limit greatest(coalesce(p_limit, 500), 0)
  ),
  cleared as (
    update runs r set trace = '[]'::jsonb
      from picked p
     where r.id = p.id
    returning r.id
  ),
  logged as (
    insert into location_retention_log
      (run_id, subject_profile_id, points_removed, anchor_at, cap)
    select p.id, p.runner_id, p.points, p.anchor_at, v_cap
      from picked p
     where p.id in (select id from cleared)     -- 지운 것만 적는다 (그리고 지운 것은 전부 적는다)
    returning 1
  )
  select (select count(*) from cleared)::int,
         (select coalesce(sum(p.points), 0) from picked p where p.id in (select id from cleared))::int,
         ((select count(*) from overdue) - (select count(*) from cleared))::int;
end $$;
revoke execute on function purge_expired_run_traces(int) from public, anon, authenticated;
comment on function purge_expired_run_traces is
  '0120 §G — 위치정보법 시행령 제26조의2 파기. 상한을 넘긴 runs.trace 를 비운다(행은 남긴다). 앵커 = least(greatest(ended_at, started_at, bookings.created_at), now()) — ended_at이 NULL인 런을 영원히 보관하는 fail-open을 막고, 미래로 오염된 타임스탬프도 1년 안에 만료시킨다. p_limit로 경계, 오래된 것부터, 재실행이 곧 재개. 지운 모든 행은 location_retention_log에 남는다 — 조용한 대량 삭제는 버그와 구별되지 않는다. 크론: purge-run-traces.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §H. The schedule — and the pin belongs on `cron.job`, not on the function
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- `0060:129-147` is the reason this section has a paragraph: `purge_expired_holds` sat UNSCHEDULED
-- for months while a comment claimed it ran every minute, AND its predicate meant it had never
-- deleted a row. A function without a verified schedule row is the exact failure this repo already
-- made once. Suite 155 L7 asserts the `cron.job` ROW — jobname, schedule and command — and 00_shim
-- gained a pg_cron stub in this same commit so that assertion is a real gate locally instead of a
-- sentence (the `realtime` shim of 2026-08-15 was added for exactly this reason and says so).
--
-- Stagger (0060:145's doctrine). Daily at **17:43 UTC = 02:43 KST**, in a quiet hour:
--   · Hour: the only other daily jobs are `club-payout-release` (18:00 UTC) and `purge-chat`
--     (19:00 UTC); 17:00 is empty.
--   · Minute 43 avoids every hourly job (`recurring-gen` :07, `club-stale-delegation-sweep` :17,
--     `club-series-gen` :20, `club-min-attendance` :40).
--   · Minute 43 is ≡3 (mod 5) and ≡3 (mod 10). Four `*/5` families cover every residue mod 5, so
--     mod-5 avoidance is arithmetically impossible — what the doctrine actually asks is that two
--     batches not bite the same TABLE in the same minute. Residue 3 belongs to
--     `sweep-payment-intents` (payment_intents/bookings), and residue 3 mod 10 keeps it off
--     `run-end-recovery` (8-58/10), which is the only other job that writes `runs`.
--   · `owner-la-stale` runs every minute and READS `runs.trace`; it only ever touches bookings with
--     a live Live Activity token, which by construction are not a year old.
-- The guarded do-block form is 0017:22-26 / 0060:149-153 — no `create extension`, so the block
-- succeeds wherever `cron` exists and raises a notice where it does not.
do $$ begin
  perform cron.schedule('purge-run-traces', '43 17 * * *', 'select purge_expired_run_traces()');
exception when others then
  raise notice 'pg_cron unavailable — purge_expired_run_traces() 를 외부 스케줄러로 매일 호출하세요';
end $$;
