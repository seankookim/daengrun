-- 오픈 풀 수락: matching 상태에서 러너가 바로 수락하면 confirmed로 직행할 수 있다.
-- (지정 러너 경로는 기존대로 matching → runner_pending → confirmed)

create or replace function enforce_booking_transition() returns trigger
language plpgsql as $$
declare ok boolean := false;
begin
  if old.status = new.status then return new; end if;
  ok := case old.status
    when 'draft'          then new.status in ('quoted','expired')
    when 'quoted'         then new.status in ('payment_hold','expired')
    when 'payment_hold'   then new.status in ('matching','expired','refund_pending')
    when 'matching'       then new.status in ('runner_pending','confirmed','expired','refund_pending','cancelled_owner')
    when 'runner_pending' then new.status in ('confirmed','matching','expired','cancelled_owner')
    when 'confirmed'      then new.status in ('runner_enroute','picked_up','cancelled_owner','cancelled_runner','no_show')
    when 'runner_enroute' then new.status in ('picked_up','no_show','cancelled_runner','incident_review')
    when 'picked_up'      then new.status in ('active','incident_review')
    when 'active'         then new.status in ('completed','incident_review')
    when 'completed'      then new.status in ('incident_review')
    else new.status in ('refund_pending')
  end;
  if not ok then
    raise exception 'invalid booking transition: % -> %', old.status, new.status;
  end if;
  return new;
end $$;
