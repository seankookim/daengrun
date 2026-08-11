-- ═══ 0067: P1 SECURITY — club incident subject gate + SOS unification (audit 2026-08-11) ═══
--
-- FINDING (verified, TODOS.md §"P1 SECURITY"). club_incident_open (0050:14-45) validated
-- severity, summary, session existence and `_club_shell_access <> 'none'`, but NEVER validated
-- p_dog or p_booking against the session or the caller. Three compounding facts made that a
-- remote payout-freeze primitive:
--   1. `_club_shell_access` returns 'limited' for ANY profile with a session_dogs row of
--      custody='runner_delegated' — no approval check, no service_state check. A rejected or
--      withdrawn applicant keeps 'limited' forever (0053 §5 decided that ON PURPOSE, so the
--      applicant can still see their own rejection card and their own host_channel thread;
--      pin 96 F5 holds it). So the fix is NOT to narrow shell access — it is to stop treating
--      "can see the door" as "may open a case".
--   2. p_dog was inserted as a subject unvalidated. The payout-hold loop IS session-scoped, so
--      the hold landed only inside the session — but it landed on ANOTHER OWNER's dog.
--   3. p_booking was the bad one: inserted with zero validation, and club_release_payouts
--      (0045:433-436) matched `subject_type='booking' and subject_id = sd.booking_id` with NO
--      session join. An arbitrary booking UUID therefore froze that booking's payout
--      cross-session AND cross-club. Either subject also blocked club_finish_session via
--      `incident_unassigned` (0048:398) until a host adopted the case.
--
-- FIX, in three layers (defense in depth — each is independently sufficient for its own class):
--   §A who may open       — `_club_incident_can_open`: host/full, plus the owner of an APPROVED
--                           delegation (they must keep the right after service_state='ended':
--                           a return/settlement dispute is exactly what a case is for, and
--                           0050 §A already holds payouts on ended rows for that reason), plus
--                           the runner who actually held a dog here. A pending/rejected/
--                           withdrawn applicant is 'limited' and is now refused.
--   §B what may be named  — `_club_incident_dog_party` / `_club_incident_booking_party`: the
--                           subject must belong to THIS session and the actor must be a party
--                           to that subject. Absent ≡ foreign ≡ not-yours (one error each).
--   §D 2nd defense line   — club_release_payouts scopes its incident probe to the session_dog's
--                           OWN session, so a subject row can never reach across clubs again.
--
-- Also fixed here, same function, same commit:
--   §C party gate BEFORE state gate (CLAUDE.md §Migrations): 0050 raised `not_found` on an
--     unknown session before checking party, leaking session existence to strangers. Now an
--     unknown session and a session you are not party to are indistinguishable ('not_party').
--   §E C3 (club audit) — the two SOS buttons made the same promise and each implemented the
--     half the other was missing, and NEITHER told the dog's owner. Owner SOS (club_sos) passed
--     p_dog => null so no payout hold landed; runner SOS (club_incident_open) held payout but
--     had no runner fan-out. PANEL VERDICT: unify on club_incident_open with an OPTIONAL dog —
--     NOT "always attach a dog", because an owner's SOS often has no dog subject (loose dog, a
--     fight, a collapsed person) and attaching one would drop a payout hold on an uninvolved
--     runner. So: dog attached ⇒ payout hold (already there) · always ⇒ runner fan-out (lifted
--     out of club_sos, gated to S1/S2) · always ⇒ notify the affected owner.
--
-- ⚠ club_sos becomes a THIN WRAPPER and is NOT dropped/repointed. check-rpc-contracts.mjs
--   (app/scripts, :37-38) only ever pushes signatures and never removes one, so
--   `drop function club_sos(...)` would leave the gate validating a ghost forever — green on
--   broken by construction. It also parses no return types, so club_sos MUST keep returning
--   `uuid`: the caller pushes straight to /club/case/{id} (session/[sid].tsx:488) and a jsonb
--   return would render /club/case/[object Object] past both gates.
--
-- Every `create or replace` below re-states `set search_path = public, pg_temp` in the BODY:
--   replace resets proconfig (measured, 0055), and pin 98 H1 fails the whole harness on any
--   public definer function without pg_temp.
--
-- Pins: supabase/tests/106_incident_subject_suite.sql (mutation map in its header).
-- Pin collision handled in the same commit: 95 G12 passed a foreign-session dog THROUGH this
--   RPC and was green precisely because the validation was absent — it now seeds its
--   cross-session incident by direct INSERT (the projection is what G12 actually asserts).

-- ---------- §A. Who may open a case ----------
-- Deliberately NOT `_club_shell_access <> 'none'`. 'limited' means "has an application record
-- here" — including rejected and withdrawn ones, forever (0053 §5, pinned by 96 F5). That is
-- the right answer for reading your own rejection card; it is the wrong answer for opening an
-- S1 that freezes money and blocks club_finish_session.
create or replace function _club_incident_can_open(p_session uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select p_profile is not null and (
    _club_shell_access(p_session, p_profile) in ('host', 'full')
    -- the owner of an approved delegation keeps the right after service ends — disputes about
    -- the return or the settlement arrive AFTER 'ended' drops them out of 'full' (90 RC pins
    -- exactly this actor: oc opens a case on a resolved/ended row)
    or exists (select 1 from session_dogs sd
               where sd.session_id = p_session and sd.owner_profile_id = p_profile
                 and sd.custody = 'runner_delegated' and sd.approval = 'approved')
    -- and so does the runner who actually held a dog here (covers an emergency-transfer
    -- recipient who never held a session_runner_assignments row of their own)
    or exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
               where sd.session_id = p_session and b.runner_id = p_profile));
$$;
revoke execute on function _club_incident_can_open(uuid, uuid) from public, anon, authenticated;

-- ---------- §B. What may be named as a subject ----------
-- Absent, foreign-session and not-yours all return false — one error, no probing oracle.
create or replace function _club_incident_dog_party(p_session uuid, p_dog uuid, p_actor uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from session_dogs sd
    left join bookings b on b.id = sd.booking_id
    where sd.session_id = p_session and sd.dog_id = p_dog
      and (sd.owner_profile_id = p_actor
        or b.runner_id = p_actor
        or exists (select 1 from club_sessions s
                   where s.id = p_session
                     and p_actor in (s.host_profile_id, s.backup_host_profile_id))));
$$;
revoke execute on function _club_incident_dog_party(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function _club_incident_booking_party(p_session uuid, p_booking uuid, p_actor uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from bookings b
    where b.id = p_booking and b.club_session_id = p_session
      and (b.owner_id = p_actor
        or b.runner_id = p_actor
        or exists (select 1 from club_sessions s
                   where s.id = p_session
                     and p_actor in (s.host_profile_id, s.backup_host_profile_id))));
$$;
revoke execute on function _club_incident_booking_party(uuid, uuid, uuid) from public, anon, authenticated;

-- ---------- §C+§E. 인시던트 개설 v2 — 주체 검증·당사자 우선 게이트·SOS 통합 ----------
create or replace function club_incident_open(
  p_session uuid, p_severity text, p_summary text,
  p_dog uuid default null, p_booking uuid default null, p_location jsonb default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record; v_inc uuid; v_sd record;
  v_owner uuid; v_dog_name text; v_role text;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_severity not in ('S1', 'S2', 'S3') then raise exception 'bad_severity'; end if;
  if coalesce(trim(p_summary), '') = '' then raise exception 'summary_required'; end if;

  -- [0067 §C] party gate BEFORE state gate. _club_incident_can_open is false for an unknown
  -- session too, so absent and not-yours are the same answer — no existence oracle.
  if not _club_incident_can_open(p_session, auth.uid()) then raise exception 'not_party'; end if;
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_party'; end if;      -- identical error, deliberately

  -- [0067 §B] subject gate. Unvalidated, these two arguments were a remote payout freeze.
  if p_dog is not null and not _club_incident_dog_party(p_session, p_dog, auth.uid()) then
    raise exception 'not_dog_party';
  end if;
  if p_booking is not null and not _club_incident_booking_party(p_session, p_booking, auth.uid()) then
    raise exception 'not_booking_party';
  end if;

  insert into club_incidents (session_id, severity, state, opened_by, summary)
  values (p_session, p_severity, 'open', auth.uid(), trim(p_summary))
  returning id into v_inc;
  insert into club_incident_subjects (incident_id, subject_type, subject_id)
  values (v_inc, 'session', p_session);
  if p_dog is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'dog', p_dog);
    -- 강아지에 열린 인시던트 ⇒ 지급 보류 (릴리스 크론의 직렬화 지점 — 세션 락 하에서 씀)
    -- ended 행도 보류한다: 서비스 종료 후 분쟁(반환·정산 시비)이 정확히 payable을 막아야 하는
    -- 경우다 — 레이스 검사(RC)가 잡은 결함: ended 필터가 지급 보류를 무력화했다
    for v_sd in select id from session_dogs
      where session_id = p_session and dog_id = p_dog and custody = 'runner_delegated'
        and payout_state <> 'released'
    loop
      update session_dogs set payout_hold = 'held', payout_hold_reason = 'incident',
        payout_hold_incident = v_inc where id = v_sd.id;
    end loop;
  end if;
  if p_booking is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'booking', p_booking);
  end if;
  if p_location is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (v_inc, 'location', p_location, auth.uid());
  end if;

  -- S1/S2 = 크리티컬 (제목 레지스트리 → ack 배너) · S3 = 커뮤니티 잉크
  insert into notifications (profile_id, kind, title, body, ref_id)
  select p.pid, (case when p_severity = 'S3' then 'community' else 'safety' end)::noti_kind,   -- CASE는 text로 굳는다 (0028 이넘 교훈)
         case when p_severity = 'S3' then '인시던트 접수' else '인시던트 발생' end,
         '[' || p_severity || '] ' || trim(p_summary) || ' — 케이스를 확인하세요', p_session
  from (select s.host_profile_id as pid
        union select s.backup_host_profile_id where s.backup_host_profile_id is not null) p
  where p.pid is not null and p.pid <> auth.uid();

  -- [0067 §E — C3 절반 ①] 커밋 러너 전원 팬아웃 (현장의 손이 가장 가깝다). 0050 club_sos에만
  -- 있던 절반을 여기로 올린다 — 이제 어느 문으로 들어와도 같은 약속이 지켜진다.
  -- 5분 dedup은 club_sos의 것을 그대로 (같은 사건에 알림 폭풍 금지).
  if p_severity in ('S1', 'S2') then
    insert into notifications (profile_id, kind, title, body, ref_id)
    select a.runner_profile_id, 'safety', '인시던트 발생',
           '[' || p_severity || '] ' || trim(p_summary) || ' — 주변을 확인하세요', p_session
    from session_runner_assignments a
    where a.session_id = p_session and a.status = 'committed'
      and a.runner_profile_id <> auth.uid()
      and a.runner_profile_id is distinct from s.host_profile_id            -- 위에서 이미 받았다
      and a.runner_profile_id is distinct from s.backup_host_profile_id
      and not exists (select 1 from notifications n where n.profile_id = a.runner_profile_id
                      and n.ref_id = p_session and n.title = '인시던트 발생'
                      and n.created_at > now() - interval '5 minutes');
  end if;

  -- [0067 §E — C3 절반 ②] 대상견 보호자에게 알린다. 두 SOS 버튼 모두 '호스트와 러너 전원에게
  -- 즉시 알림'을 약속하면서 정작 그 개의 보호자에게는 한 글자도 보내지 않았다.
  -- 카피는 아는 것만 말한다: 무슨 일인지 진단하지 않는다 — SOS를 누른 러너도 아직 모를 수 있다.
  -- 제목은 상수여야 한다 (club_critical_titles는 정확 일치 레지스트리) → 개 이름은 본문으로.
  if p_dog is not null then
    select sd.owner_profile_id, d.name into v_owner, v_dog_name
    from session_dogs sd join dogs d on d.id = sd.dog_id
    where sd.session_id = p_session and sd.dog_id = p_dog;
  elsif p_booking is not null then
    select b.owner_id, d.name into v_owner, v_dog_name
    from bookings b join dogs d on d.id = b.dog_id where b.id = p_booking;
  end if;
  if v_owner is not null and v_owner <> auth.uid() then
    v_role := case
      when auth.uid() in (s.host_profile_id, s.backup_host_profile_id) then '호스트'
      when exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
                   where sd.session_id = p_session and b.runner_id = auth.uid()
                     and (p_dog is null or sd.dog_id = p_dog)) then '담당 러너'
      else '참가자' end;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_owner,
      (case when p_severity = 'S3' then 'community' else 'safety' end)::noti_kind,
      case when p_severity = 'S3' then '담당견 케이스 접수' else '담당견 인시던트' end,
      coalesce(v_dog_name, '위탁견') || ' — [' || p_severity || '] ' || trim(p_summary)
        || ' · ' || v_role || '가 케이스를 열었어요 — 케이스를 열어 상황을 확인하세요',
      p_session);
  end if;
  return v_inc;
end $$;

-- [0067 §E] SOS = S1 슈가. **얇은 래퍼**로 남긴다 — drop 후 재지정이 아니다:
-- check-rpc는 삭제된 시그니처를 절대 지우지 않으므로(app/scripts/check-rpc-contracts.mjs:37-38)
-- drop 경로는 구조적으로 green-on-broken이고, 반환형 uuid도 게이트가 보지 못한다.
-- 팬아웃·보호자 알림·지급 보류는 이제 전부 club_incident_open 안에 있다.
create or replace function club_sos(p_session uuid, p_location jsonb default null) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return club_incident_open(p_session, 'S1', '긴급 SOS', null, null, p_location);
end $$;

grant execute on function club_incident_open(uuid, text, text, uuid, uuid, jsonb) to authenticated;
grant execute on function club_sos(uuid, jsonb) to authenticated;

-- 대상견 보호자 알림은 크리티컬 ack 배선을 탄다 (S1/S2만 — S3는 커뮤니티 잉크).
-- 레지스트리는 정확 일치이므로 제목에 개 이름을 넣지 않는다 (본문이 담는다).
insert into club_critical_titles (title) values ('담당견 인시던트') on conflict do nothing;

comment on function club_incident_open is
  'R6(0050)+0067: 참가자 인시던트 개설 — 주체(dog/booking) 세션·당사자 검증(not_dog_party/not_booking_party) ·
당사자 게이트 선행(not_party, 존재 누수 없음) · 대상견 payout_hold=held(세션 락 하) ·
S1/S2 커밋 러너 팬아웃 + 대상견 보호자 알림(C3 통합) · S1/S2=크리티컬 ack';
comment on function club_sos is
  'R6(0050)+0067: SOS = club_incident_open(S1) 얇은 래퍼 — 팬아웃/보호자 알림은 개설 함수가 담당.
uuid 반환 유지(클라가 /club/case/{id}로 직행) · drop 금지(check-rpc가 죽은 시그니처를 지우지 않음)';
comment on function _club_incident_can_open is
  '0067 §A: 케이스 개설 자격 — host/full · 승인된 위탁의 보호자(ended 이후 분쟁 포함) · 실제로 개를 잡았던 러너.
limited(신청만·거절·철회)는 제외 — 문을 볼 권리(0053 §5)와 돈을 묶을 권리는 다르다';

-- ---------- §D. 지급 릴리스 2차 방어선 — 같은 세션으로 한정 ----------
-- 0045의 not exists는 subject_id만 맞으면 세션을 묻지 않았다 → 임의 booking UUID 하나로
-- 다른 클럽의 지급을 얼렸다. 1차 방어선(payout_hold)은 원래부터 세션 스코프였으므로,
-- 2차 방어선을 같은 스코프로 맞추는 것이 정합이다. 같은 세션의 인시던트는 그대로 막는다 (60 E21).
create or replace function club_release_payouts() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  -- [직렬화 법] payout_hold가 릴리스 차단의 직렬화 지점이다: 지급을 막아야 하는 모든 인시던트
  -- 개설 RPC는 그 강아지의 세션 락 아래에서 payout_hold='held'를 함께 써야 한다 (clinic 이양이
  -- 그 예). 아래 인시던트 존재 검사는 2차 방어선(defense-in-depth)이지 락 대체가 아니다.
  -- 멱등: payable → released 단방향, 재실행 시 0행.
  update session_dogs sd set payout_state = 'released'
  where sd.payout_state = 'payable' and sd.payout_hold = 'none' and sd.custody_phase = 'resolved'
    and not exists (
      select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
      where i.state <> 'resolved'
        and i.session_id = sd.session_id                    -- [0067 §D] 교차 세션/교차 클럽 차단
        and ((s.subject_type = 'dog' and s.subject_id = sd.dog_id)
          or (s.subject_type = 'booking' and s.subject_id = sd.booking_id)));
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function club_release_payouts() from public, anon, authenticated;

comment on function club_release_payouts is
  '0045+0067: 지급 릴리스 배치 — 1차 방어선은 payout_hold, 2차 방어선(인시던트 존재)은 이제
session_dog 자신의 세션으로 한정한다 (임의 subject_id 주입으로 타 클럽 지급을 얼리던 경로 폐쇄)';
