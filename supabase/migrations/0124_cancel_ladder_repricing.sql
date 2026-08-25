-- ═══ 0124: the cancel ladder repriced — two console rulings, one function ═══
--
-- Sean, 2026-08-25 console (docs/decisions/2026-08-25-console-rulings.md, verbatim):
--   #11 「Free 24h+ always wins」 — the free window outranks post-acceptance.
--   #13 「should be no fee if the owner was not connected; it's our job to connect them.」
--       — a cancellation with NO accepted runner is FREE at any time. Supersedes the
--       10%-vs-5% question AND makes 0118 ruling B's halving moot for this arm (nothing to
--       halve; the halving stays in _club_record_fee as a belt for any other runnerless fee).
--
-- ONE slice for both by design (spec-v2 session's coordination call, 2026-08-25): both arms
-- edit the SAME ladder in `session_cancel_delegation`, and two sessions create-or-replacing
-- one function separately is the silent-collision class the ledger memory names.
--
-- The new ladder:
--   ≥ free_hours out                  → 0    'free_window'      (#11 — accepted or not)
--   < free_hours, runner ACCEPTED     → 20%  'post_acceptance'  (unchanged)
--   < free_hours, NO runner ever      → 0    'unconnected_free' (#13)
-- `cancel_late_pct` thereby loses its LAST club consumer. The config row and its 0118 §H
-- value pin stay (deleting ruled config is not this slice's call); the marketplace analog was
-- CHECKED per #13's disposition and already embodies the principle — 0117:1419 charges 0 when
-- `runner_id is null or status in ('matching','runner_pending')`. No 0117 change needed.
--
-- ⚠ REVIEW-NAMED EDGE (blind review №1, ruled DELIBERATE): accept → host-revoke
-- (session_assignment_revoke, 0057:133) → near cancel prices FREE, not 20%. Sean's words are
-- present-tense — 「no fee if the owner was not connected」 — and at cancel time this owner is
-- not; the 20%'s supply half would compensate a runner already revoked by the HOST's own act
-- (whose record lives in assignment_events for the strike policy). Pinned by 159 L5; queued as
-- a one-line console note in case the intent was history-based. Not a silent choice.
--
-- Shared-object discipline (0057 §2): `session_cancel_delegation` is reproduced byte-faithful
-- from 0118:989-1092 with FOUR named edits — ① the ladder above; ② the runner's release
-- notification branches on v_pct (「보상 기록이 남았어요」 was about to become a shipped lie:
-- under #11 a ≥24h cancel records NO compensation); ③ this header; ④ the catalog COMMENT ON
-- at the foot (review №7: an undeclared change is a change). Everything else — party
-- gate order, the incident gate, the pre-booking withdrawal arm, first-writer fee recording,
-- collectable copy — is unchanged and stays pinned by 153.

create or replace function session_cancel_delegation(p_session_dog uuid) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  sd record;
  s record;
  v_bst text;
  v_runner uuid;
  v_total int;
  v_pct numeric;
  v_rule text;
  v_collectable boolean;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- PARTY GATE FIRST. No row and another owner's row are the same answer.
  select * into sd from session_dogs
  where id = p_session_dog and owner_profile_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
  perform _club_require_v2();

  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if not found then raise exception 'not_found'; end if;

  if sd.service_state = 'ended' then raise exception 'already_ended'; end if;
  if exists (
    select 1 from club_incident_subjects sub
    join club_incidents i on i.id = sub.incident_id
    where sub.subject_type = 'dog' and sub.subject_id = sd.dog_id and i.state <> 'resolved'
  ) then
    raise exception 'incident_open';
  end if;

  if sd.booking_id is null then
    update session_dogs set approval = 'withdrawn',
      hold_status = case when hold_status = 'active' then 'released' else hold_status end
    where id = p_session_dog;
    update session_dogs set id = id where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '위탁 신청 취소',
            '보호자가 위탁 신청을 취소했어요', sd.session_id);
    return;
  end if;

  select status::text, runner_id, total_price into v_bst, v_runner, v_total
  from bookings where id = sd.booking_id for update;
  if v_bst not in ('matching', 'confirmed') then raise exception 'already_handed_off'; end if;
  -- [0124, review №2] the schema permits shapes no club flow writes (matching+runner,
  -- confirmed+NULL); pricing either would be a guess, and a guess about money fails LOUD.
  if (v_bst = 'confirmed') <> (v_runner is not null) then
    raise exception 'inconsistent_booking_shape';
  end if;

  -- [0124 edit ①] THE REPRICED LADDER. Free-window FIRST (#11: 「Free 24h+ always wins」 —
  -- an accepted runner does not defeat an early cancellation), then post-acceptance, and the
  -- runnerless remainder is FREE (#13: 「no fee if the owner was not connected」). The
  -- late_cancel rung (cancel_late_pct) has NO remaining arm here — deliberately, not by
  -- omission. R2A discipline unchanged: the charged rung reads club_cfg_required; the two
  -- zero arms are this ladder's own "no fee", never a config shadow copy.
  if s.scheduled_at - now()
       >= make_interval(hours => club_cfg_required('cancel_free_hours')::int) then
    v_pct := 0;
    v_rule := 'free_window';
  elsif v_bst = 'confirmed' and v_runner is not null then
    v_pct := club_cfg_required('cancel_post_accept_pct');
    v_rule := 'post_acceptance';
  else
    v_pct := 0;
    v_rule := 'unconnected_free';
  end if;

  if v_bst = 'confirmed' then
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_runner, 'revoked', 'owner_cancel', auth.uid());
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  end if;
  update bookings set status = 'refund_pending', cancel_reason = 'club_owner_cancel'
  where id = sd.booking_id;
  update session_dogs set id = id where id = p_session_dog;

  -- p_runner is the captured value. The booking is intentionally NULL by now.
  perform _club_record_cancel_fee(sd.session_id, sd.id, sd.booking_id, 'cancel_fee',
                                  v_total, v_pct, v_runner, v_rule);
  v_collectable := _club_fee_event_collectable(sd.booking_id);

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '위탁 취소 접수',
     case
       when v_pct > 0 and v_collectable then
         '위탁 취소가 접수됐어요 — 취소 수수료 ' || v_pct || '%가 결제 예정으로 기록됐어요'
       when v_pct > 0 then
         '위탁 취소가 접수됐어요 — 취소 수수료 ' || v_pct || '%가 기록됐어요'
       else
         '위탁 취소가 접수됐어요 — 취소 수수료는 없어요'
     end,
     sd.booking_id),
    (s.host_profile_id, 'community', '위탁 취소',
     '보호자가 결제된 위탁을 취소했어요', sd.session_id);
  if v_runner is not null then
    -- [0124 edit ②] the compensation clause fires ONLY when a fee (and so a supply share) was
    -- actually recorded — under #11 an early cancel of an accepted runner records nothing, and
    -- 「보상 기록이 남았어요」 would be a shipped lie about money.
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_runner, 'booking', '배정 취소',
            case when v_pct > 0
                 then '보호자 취소로 배정이 해제됐어요 — 보상 기록이 남았어요'
                 else '보호자 취소로 배정이 해제됐어요' end,
            sd.session_id);
  end if;
end $$;
revoke execute on function session_cancel_delegation(uuid) from public, anon;
grant execute on function session_cancel_delegation(uuid) to authenticated;

comment on function session_cancel_delegation is
  '0118 §D + [0124]: 취소 사다리 개정 — 자유 창(≥24h)이 수락을 이긴다 (#11) · 러너가 한 번도
수락하지 않은 취소는 언제든 무료 (#13, 「연결은 우리 일」). late_cancel 렁은 소비자가 없다
(의도된 사실). 파티/사건 게이트·선기록·회수 가능 문구는 0118 그대로.';
