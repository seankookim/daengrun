-- ═══ 193: chat client_key idempotency (0162) — 0162-K1 · K2 · K3 ═══════════════════════════
--
-- THE PROPERTY: a retried send with the same (thread_id, client_key) cannot create a second
-- row, and nothing that does not send a key is affected. Three arms with different blind spots:
--   K1  same thread + same key twice  → second INSERT raises 23505  (the property)
--   K2  same key, DIFFERENT thread    → admitted                    (a global unique on client_key
--                                                                    alone passes K1 and breaks K2)
--   K3  NULL key twice, same thread   → both admitted               (a non-partial index passes K1
--                                                                    and breaks every legacy writer)
-- Fixture: two threads on two bookings, inserted as postgres (the property is the index, not the
-- policy — 149 owns the party policy). The 23505 arm asserts the SQLSTATE, not merely 「it raised」.

do $suite$
declare
  th_a uuid; th_b uuid; b_a uuid; b_b uuid; k uuid := gen_random_uuid();
  v_state text; v_n int;
begin
  select id into b_a from bookings order by created_at limit 1;
  select id into b_b from bookings where id <> b_a order by created_at limit 1;
  if b_a is null or b_b is null then
    call _fail('cck', '0162-K0 fixture — need two bookings', 'found fewer than two bookings');
    return;
  end if;
  insert into chat_threads(booking_id) values (b_a) returning id into th_a;
  insert into chat_threads(booking_id) values (b_b) returning id into th_b;

  -- [0162-K1] same thread, same key, twice → 23505 on the second
  insert into chat_messages(thread_id, sender_id, body, client_key)
    select th_a, owner_id, 'k1', k from bookings where id = b_a;
  v_state := null;
  begin
    insert into chat_messages(thread_id, sender_id, body, client_key)
      select th_a, owner_id, 'k1 retry', k from bookings where id = b_a;
  exception when others then
    v_state := sqlstate;
  end;
  if v_state is distinct from '23505' then
    call _fail('cck', '0162-K1 duplicate (thread, client_key) refused with 23505', 'sqlstate=' || coalesce(v_state, 'NONE (second row was admitted)'));
  else
    select count(*) into v_n from chat_messages where thread_id = th_a and client_key = k;
    if v_n is distinct from 1 then
      call _fail('cck', '0162-K1 exactly one row survives', 'rows=' || v_n);
    else
      call _pass('cck', '0162-K1 duplicate (thread, client_key) refused with 23505 and one row survives');
    end if;
  end if;

  -- [0162-K2] same key in a DIFFERENT thread → admitted
  v_state := null;
  begin
    insert into chat_messages(thread_id, sender_id, body, client_key)
      select th_b, owner_id, 'k2', k from bookings where id = b_b;
  exception when others then
    v_state := sqlstate;
  end;
  if v_state is not null then
    call _fail('cck', '0162-K2 same key in another thread admitted', 'sqlstate=' || v_state || ' (index is not thread-scoped)');
  else
    call _pass('cck', '0162-K2 same key in another thread admitted — the index is (thread_id, client_key), not client_key alone');
  end if;

  -- [0162-K3] NULL key twice in one thread → both admitted (partial index; legacy writers untouched)
  v_state := null;
  begin
    insert into chat_messages(thread_id, sender_id, body)
      select th_a, owner_id, 'k3' from bookings where id = b_a;
    insert into chat_messages(thread_id, sender_id, body)
      select th_a, owner_id, 'k3 again' from bookings where id = b_a;
  exception when others then
    v_state := sqlstate;
  end;
  select count(*) into v_n from chat_messages where thread_id = th_a and client_key is null and body like 'k3%';
  if v_state is not null or v_n is distinct from 2 then
    call _fail('cck', '0162-K3 NULL keys never collide', 'sqlstate=' || coalesce(v_state,'none') || ' rows=' || v_n);
  else
    call _pass('cck', '0162-K3 NULL keys never collide — the index is partial, so writers that send no key are untouched');
  end if;

  delete from chat_messages where thread_id in (th_a, th_b);
  delete from chat_threads where id in (th_a, th_b);
end $suite$;
