-- 0027: 서버 집계 RPC — fetchMiles/fetchLedgerTotal의 '2000행 클라 합산' 파일럿 상한 은퇴.
-- 이전: 클라가 최대 2000행을 내려받아 reduce — 2000행 초과 시 잔액이 조용히 축소되는 거짓 숫자.
-- 이제: DB가 전체 합을 낸다. security invoker — RLS(self read)가 그대로 적용되므로
-- where 절과 이중 안전장치. (miles_ledger·ledger_items 모두 (uid, created_at) 인덱스 기존.)

create or replace function my_miles_balance() returns bigint
language sql stable security invoker set search_path = public as $$
  select coalesce(sum(delta), 0) from miles_ledger where profile_id = auth.uid();
$$;

create or replace function my_ledger_total() returns bigint
language sql stable security invoker set search_path = public as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip + coalesce(remaining_guarantee, 0) - platform_fee), 0)
  from ledger_items where runner_id = auth.uid();
$$;

grant execute on function my_miles_balance() to authenticated;
grant execute on function my_ledger_total() to authenticated;

comment on function my_miles_balance is '하이 포인트 잔액 — 원장 전체 합 (invoker, RLS self read)';
comment on function my_ledger_total is '러너 정산 예정 누적 net — 원장 전체 합 (invoker, RLS self read)';
