-- ═══ 0068: C1 — the T-10 auto-refund is deleted (the cron contradicted the app's promise) ═══
--
-- FINDING (club audit 2026-08-11, C1). `club_assignment_recovery` block ① (0049:344-365, on a
-- `*/5` cron) refunded EVERY paid delegation still `matching` from `scheduled_at - 10 minutes`.
-- The product says the opposite, in two places the user actually reads:
--   · the delegation consent checkbox itself — "담당은 집결지에서 정해져요" (session/[sid].tsx:1283)
--   · the host console — the same sentence (console/[sid].tsx:359)
-- And the server agrees with the copy, not with the cron: `session_propose_dog` opens the
-- assign window at [T-2h, T+6h] (0048:454) and additionally requires the runner to be
-- `checked_in` (0048:465) — i.e. assignment is DESIGNED to happen at the meetup, minutes
-- before the run. A host arriving at 06:50 for a 07:00 session therefore found every
-- delegation already refunded, with the owners standing there holding their dogs.
--
-- FIX: delete block ① outright. This is a DELETE, not a new constant — moving the hard stop to
-- T+0 or T+6h would only relocate the same disagreement, and the honest terminal already
-- exists: `club_finish_session` refunds every still-`matching` club booking as
-- 'club_not_picked_up' / '위탁 미진행 — 전액 환불' (0048 §J), a registered critical-ack title.
-- Refunding when the host closes the session is true ("the delegation did not happen");
-- refunding ten minutes before it starts is false ("assignment failed" — it had not been
-- attempted yet).
--
-- ACCEPTED RESIDUAL, written down rather than papered over: a host who never presses
-- 종료 leaves paid delegations sitting in `matching`. That is a stuck refund an operator can
-- still resolve, and it is strictly better than an automatic refund fired at the exact moment
-- the service was about to be delivered. Tracked in TODOS.md.
--
-- Everything else in the function (② expired proposals · ③ T-30 alerts · ④ return-delay alarm ·
-- ⑤ ack escalation) is carried over byte-for-byte. `sess`/`v_ids` were block ①'s locals and go
-- with it. `set search_path = public, pg_temp` is re-stated in the body because replace resets
-- proconfig and pin 98 H1 fails the harness on any public definer function without it.
--
-- Pin: 65 A8 is REWRITTEN in the same commit — it pinned the auto-refund and would otherwise
-- read as a regression. It now pins the inverse (the cron must leave a paid, unassigned
-- delegation alone), and 107 R1 pins the positive half (assignment still works past T-10).

create or replace function club_assignment_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  -- ② 만료 제안 정리: 이벤트 기록 + 캐시 클리어 (진실은 이벤트 — 캐시 청소는 상태 변경이 아님)
  for r in
    select d.id, d.session_id, d.proposed_runner_profile_id, d.dog_id,
           (select host_profile_id from club_sessions where id = d.session_id) as host
    from session_dogs d join bookings b on b.id = d.booking_id
    where d.proposed_runner_profile_id is not null and d.proposal_expires_at <= now()
      and b.status = 'matching'
  loop
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason)
    values (r.id, r.proposed_runner_profile_id, 'expired', 'proposal_timeout');
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null where id = r.id;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (r.host, 'community', '배정 제안 만료',
      (select name from dogs where id = r.dog_id) || ' 제안이 응답 없이 만료됐어요 — 다시 제안하세요', r.session_id);
    n := n + 1;
  end loop;

  -- ③ T-30 경보 (dedup: 제목+ref+수신자 1회) — 러너 지각 = capacity-at-risk · 호스트 부재 = 백업 안내
  for r in
    select s.id, s.host_profile_id, s.backup_host_profile_id, a.runner_profile_id
    from club_sessions s
    join session_runner_assignments a on a.session_id = s.id and a.status = 'committed'
    where s.status in ('open', 'full')
      and s.scheduled_at between now() and now() + interval '30 minutes'
      and not exists (select 1 from session_people sp
                      where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                        and sp.attendance = 'checked_in')
      and exists (select 1 from session_dogs d join bookings b on b.id = d.booking_id
                  where d.session_id = s.id and b.runner_id = a.runner_profile_id
                    and b.status = 'confirmed')
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.host_profile_id, 'community', '러너 체크인 지연',
           '배정 수락 러너가 T-30까지 체크인하지 않았어요 — 교체 제안을 준비하세요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.host_profile_id and ref_id = r.id and title = '러너 체크인 지연');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.runner_profile_id, 'booking', '체크인 지연',
           '배정을 수락한 세션이 30분 안에 시작돼요 — 지금 체크인하세요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.runner_profile_id and ref_id = r.id and title = '체크인 지연');
  end loop;
  for r in
    select s.id, s.backup_host_profile_id from club_sessions s
    where s.status in ('open', 'full') and s.backup_host_profile_id is not null
      and s.scheduled_at between now() and now() + interval '30 minutes'
      and not exists (select 1 from session_people sp
                      where sp.session_id = s.id and sp.profile_id = s.host_profile_id
                        and sp.attendance = 'checked_in')
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.backup_host_profile_id, 'community', '호스트 부재 위험',
           '호스트가 T-30까지 체크인하지 않았어요 — 인수(assume host)가 가능해요', r.id
    where not exists (select 1 from notifications
                      where profile_id = r.backup_host_profile_id and ref_id = r.id and title = '호스트 부재 위험');
  end loop;
  -- ④ [R5] 반환 지연 경보: 예정 +6h 지나도 return_pending → 양측 크리티컬 (ack 트리거가 배너化)
  for r in
    select sd.id, sd.owner_profile_id, sd.session_id, b.runner_id,
           (select name from dogs where id = sd.dog_id) as dog_name
    from session_dogs sd
    join club_sessions s on s.id = sd.session_id
    left join bookings b on b.id = sd.booking_id
    where sd.custody = 'runner_delegated' and sd.custody_phase = 'return_pending'
      and s.scheduled_at < now() - interval '6 hours'
  loop
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.owner_profile_id, 'safety', '반환 지연 경보',
           r.dog_name || ' 반환이 아직 확인되지 않았어요 — 즉시 확인하세요', r.session_id
    where not exists (select 1 from notifications where profile_id = r.owner_profile_id
                      and ref_id = r.session_id and title = '반환 지연 경보');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select r.runner_id, 'safety', '반환 지연 경보',
           r.dog_name || ' 반환 확인이 지연되고 있어요 — 지금 반환을 완료하세요', r.session_id
    where r.runner_id is not null
      and not exists (select 1 from notifications where profile_id = r.runner_id
                      and ref_id = r.session_id and title = '반환 지연 경보');
  end loop;

  -- ⑤ [R5] ack 에스컬레이션: 30분 미확인 크리티컬 → 세션 호스트에게 1회 (§9 unacked → escalate)
  for r in
    select a.id as ack_id, a.profile_id, a.title,
           coalesce(cs.id, (select b.club_session_id from bookings b where b.id = a.ref_id)) as sess
    from club_acks a
    left join club_sessions cs on cs.id = a.ref_id
    where a.acked_at is null and a.escalated_at is null
      and a.created_at < now() - interval '30 minutes'
  loop
    update club_acks set escalated_at = now() where id = r.ack_id;
    if r.sess is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      select s.host_profile_id, 'safety', '미확인 크리티컬 알림',
             '참가자가 중요 알림(' || r.title || ')을 30분째 확인하지 않았어요 — 직접 연락이 필요할 수 있어요', r.sess
      from club_sessions s
      where s.id = r.sess and s.host_profile_id <> r.profile_id
        and not exists (select 1 from notifications where profile_id = s.host_profile_id
                        and ref_id = r.sess and title = '미확인 크리티컬 알림'
                        and created_at > now() - interval '30 minutes');
    end if;
  end loop;
  return n;
end $$;
revoke execute on function club_assignment_recovery() from public, anon, authenticated;

comment on function club_assignment_recovery is
  'R5(0049)+0068: 회복 크론 — ① T-10 자동 환불은 폐지됐다 (앱은 집결지 배정을 약속하고 서버 배정 창은
[T-2h, T+6h]이다 — 환불의 정직한 종단은 club_finish_session의 club_not_picked_up) ·
② 만료 제안 정리 · ③ T-30 경보 · ④ 반환 지연 경보 · ⑤ ack 에스컬레이션';
