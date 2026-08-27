-- ═══ 174: revocation lease + race (0141) — L1~L6 ═══
-- Every pin here exists because 0138's own battery was GREEN over the defect it names. That is
-- the useful fact about this file: a green battery measured what it could reach, and codex
-- reached further. Each pin below is the reach it was missing.
--
-- ⚠ L2 IS THE ONE I OWE MOST. 0138's suite computed `second_claim` and never asserted it — a
--   variable named after a property, holding the answer, never compared to anything. It read as
--   coverage in the file and was worth nothing. It is asserted here.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid; v_n int; v_txt text; v_msg text; v_bad text := '';
  v_id uuid; v_key text; v_tok uuid; v_ok boolean; v_sw boolean;
begin
  u1 := t_user('rl_one', 'owner');
  u2 := t_user('rl_two', 'owner');

  ------------------------------------------------------------------------------------------
  -- L1: 🔴 codex #3 — the DELETION RACE no longer loses the key. Toss has issued a real
  -- credential and the account is gone; 0138 logged it and threw, leaving a live key nobody
  -- tracked. The refusal must now RECORD it, in the same transaction as the refusal itself.
  update profiles set deleted_at = now() where id = u2;
  select swapped into v_sw from billing_key_swap(u2, 'bill_orphan', '{"brand":"신한"}'::jsonb);
  select count(*) into v_n from billing_key_revocations
   where billing_key = 'bill_orphan' and reason = 'orphaned_by_deletion' and state = 'pending';
  declare v_stored int; begin
    select count(*) into v_stored from billing_keys where profile_id = u2;
    v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' queued=' || v_n || ' stored=' || v_stored;
    -- refused AND recorded AND not stored: all three, because any two without the third is a
    -- different bug (stored = the tombstone hole; unrecorded = the orphan; accepted = both).
    if v_sw is distinct from false or v_n <> 1 or v_stored <> 0
      then call _fail('rvl','L1 무덤 레이스가 키를 잃지 않는다', v_msg);
      else call _pass('rvl','L1 무덤 레이스가 키를 잃지 않는다'); end if;
  end;
  update profiles set deleted_at = null where id = u2;

  ------------------------------------------------------------------------------------------
  -- L2: 🔴 EXCLUSIVITY, ASSERTED THIS TIME. A claimed row is invisible to a second claim while
  -- its lease holds. 0138 computed exactly this number and never compared it.
  perform billing_key_swap(u1, 'bill_A', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_B', '{"brand":"국민"}'::jsonb);   -- queues bill_A
  select id, billing_key, claim_token into v_id, v_key, v_tok
    from claim_billing_key_revocations(10) limit 1;
  select count(*) into v_n from claim_billing_key_revocations(10);      -- same tick, second worker
  v_msg := 'first=' || coalesce(v_key,'∅') || ' second_claim_count=' || v_n;
  if v_id is null or v_tok is null or v_n <> 0
    then call _fail('rvl','L2 리스 중인 행은 두 번 잡히지 않는다', v_msg);
    else call _pass('rvl','L2 리스 중인 행은 두 번 잡히지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- L3: a STALE report cannot overwrite a newer result. The first worker's lease expires, a
  -- second worker takes the row and reports success; the first then reports failure with its
  -- dead token and must be REFUSED — not applied late over a `done`.
  update billing_key_revocations set lease_until = now() - interval '1 minute' where id = v_id;
  declare v_tok2 uuid; begin
    select claim_token into v_tok2 from claim_billing_key_revocations(10) limit 1;
    v_ok := report_billing_key_revocation(v_id, true, null, v_tok2);     -- the new holder wins
    if v_ok is distinct from true then v_bad := v_bad || ' new-holder-refused'; end if;
    v_ok := report_billing_key_revocation(v_id, false, 'stale', v_tok);  -- the old one is late
    if v_ok is distinct from false then v_bad := v_bad || ' STALE-APPLIED'; end if;
  end;
  select state into v_txt from billing_key_revocations where id = v_id;
  if v_txt is distinct from 'done' then v_bad := v_bad || ' final-state(' || coalesce(v_txt,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('rvl','L3 만료된 클레임은 최신 결과를 덮지 못한다', v_bad);
                 else call _pass('rvl','L3 만료된 클레임은 최신 결과를 덮지 못한다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- L4: a CRASHED worker's row comes back on its own. 0138 stranded it forever: state stayed
  -- `pending` with attempts at the cap, so it was excluded from claiming AND from the
  -- dispatcher's count — invisible to both, needing an operator who would never be told.
  insert into billing_key_revocations (profile_id, billing_key, reason)
  values (u1, 'bill_crashed', 'replaced') returning id into v_id;
  select claim_token into v_tok from claim_billing_key_revocations(10) limit 1;   -- claimed…
  update billing_key_revocations set lease_until = now() - interval '1 second' where id = v_id;
  select count(*) into v_n from claim_billing_key_revocations(10)
   where billing_key = 'bill_crashed';                                            -- …and reclaimed
  if v_n <> 1 then call _fail('rvl','L4 죽은 워커의 행은 스스로 돌아온다', 'reclaimed=' || v_n);
              else call _pass('rvl','L4 죽은 워커의 행은 스스로 돌아온다'); end if;

  ------------------------------------------------------------------------------------------
  -- L5: 🔴 codex #5 — a queued key that becomes CURRENT again is abandoned, not revoked. The
  -- worker never re-reads `billing_keys`, so without this the sweep destroys a live card.
  perform billing_key_swap(u1, 'bill_A', '{"brand":"국민"}'::jsonb);   -- A is current again
  select state into v_txt from billing_key_revocations
   where billing_key = 'bill_A' and reason = 'replaced' order by created_at desc limit 1;
  select billing_key into v_key from billing_keys where profile_id = u1;
  v_msg := 'queued_state=' || coalesce(v_txt,'∅') || ' current=' || coalesce(v_key,'∅');
  if v_txt = 'pending' or v_key is distinct from 'bill_A'
    then call _fail('rvl','L5 되살아난 키는 폐기되지 않는다', v_msg);
    else call _pass('rvl','L5 되살아난 키는 폐기되지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- L6: 🔴 codex #2 — the dispatcher reads the REAL vault contract. 0138 looked for `key` and
  -- sent a Bearer header; the authoritative secret (0116:349) is `{url, cron_key}` with
  -- `X-Cron-Key`, and the url is a BASE that the caller appends a path to. So 0138 found no key,
  -- returned 0, and scheduled revocation never started — indistinguishable from 「nothing due」,
  -- which is why no green could ever have caught it. Asserted as SOURCE: a single-session suite
  -- cannot make an outbound HTTP call, and pretending otherwise would be a green standing for a
  -- property it never tested.
  v_bad := '';
  select prosrc into v_txt from pg_proc where proname = 'dispatch_billing_key_revocations';
  if v_txt !~ 'cron_key'          then v_bad := v_bad || ' NO-cron_key'; end if;
  if v_txt !~ 'X-Cron-Key'        then v_bad := v_bad || ' NO-X-Cron-Key'; end if;
  if v_txt ~  'Authorization'     then v_bad := v_bad || ' STILL-Bearer'; end if;
  if v_txt !~ '/revoke-billing-keys' then v_bad := v_bad || ' NO-path-append'; end if;
  -- and the count must see a reclaimable expired lease, or a crashed batch stalls the cron
  if v_txt !~ 'lease_until'       then v_bad := v_bad || ' count-blind-to-expired-lease'; end if;
  if v_bad <> '' then call _fail('rvl','L6 디스패처는 실제 볼트 계약을 읽는다', v_bad);
                 else call _pass('rvl','L6 디스패처는 실제 볼트 계약을 읽는다'); end if;
end $$;
