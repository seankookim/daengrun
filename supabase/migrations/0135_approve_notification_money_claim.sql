-- 0135 — the approval notification told the OWNER a payment was pending. No payment exists.
--
-- Found 2026-08-26 by a peer who was verifying a DIFFERENT claim of mine about the client, and
-- walked one layer down. Nobody was looking here.
--
-- 🔴 THE FUNCTION CONTRADICTS ITSELF, TWO LINES APART, and the comment is the half that is right:
--
--     -- ⓑ [0084 §F, ruling ④] 요금 없음, '결제' 없음 … 이 단계에서 움직이는 돈은 없다
--     insert into notifications (…) values (sd.owner_profile_id, 'booking',
--            '위탁 승인 — 결제 대기',            ← the money claim
--            '20분 안에 자리를 확정하면 돼요',    ← correct, seat-shaped
--
-- Measured on the deployed function before this file was written: `prosrc ~ '요금 없음'` → true,
-- `prosrc ~ '움직이는 돈은 없다'` → true, and the notification title contains 결제 대기. The RPC
-- documents that no money moves at approval and then tells a real person their payment is pending.
--
-- ⚠ WHY THIS ONE MATTERS MORE THAN THE CLIENT STRINGS IT MATCHES. The same false claim lived at
-- `console/[sid].tsx:154`/`:374` and was fixed there today — but those are read by a HOST on an
-- admin console. This one is a push notification to the OWNER: it lands on a real person's lock
-- screen, is not dismissible by re-reading the screen, and is the only sentence most owners will
-- ever see about this step. Under 「no fake numbers, no fabricated data」 a fabricated *event* is
-- the same defect as a fabricated number.
--
-- ⚠ NOT a money-model change. Nothing about charging moves here — `payments_live_since` is
-- untouched and charging remains off. This changes ONE string to describe what the function
-- already does.
--
-- THE ONLY EDIT: the title. Everything else is a byte-faithful recreation of the deployed body
-- (read from `pg_proc.prosrc`, not from 0084's source — the deployed function is the artifact).
-- The new title keeps the URGENCY the old one carried: the owner has 20 minutes and the title is
-- what they see first, so 「위탁이 승인됐어요」 alone would lose the deadline. It states the event
-- and the deadline, and claims no money.

begin;

-- ── A. PRE-CHECK — fail closed if the deployed body is not what this file was written against ──
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'session_approve_dog';
  if v_src is null then raise exception '0135 A: session_approve_dog absent'; end if;
  if v_src not like '%위탁 승인 — 결제 대기%' then
    raise exception '0135 A: the money-claim title is not present — someone changed this already; re-scout before applying.';
  end if;
end $$;

-- ── B. The recreation. `set search_path` IN THE BODY (ALTER-applied config is reset by
--    `create or replace`; 98 H1 watches the whole schema for this).
create or replace function public.session_approve_dog(p_session_dog uuid, p_approve boolean)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sd record; s record; v_reserved int;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'pending' then raise exception 'not_pending'; end if;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  if not p_approve then
    update session_dogs set approval = 'rejected' where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'community', '위탁 신청 거절',
            '이번 세션에는 함께하지 못하게 됐어요', sd.session_id);
    return null;
  end if;

  v_reserved := _club_delegated_reserved(sd.session_id);
  if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;

  update session_dogs set approval = 'approved',
    hold_status = 'active', hold_expires_at = now() + interval '20 minutes'
  where id = p_session_dog;

  -- ⓑ [0084 §F, ruling ④] 요금 없음, '결제' 없음. 가격 고지는 승낙서 한 곳뿐이고, 이 단계에서
  -- 움직이는 돈은 없다 (컷오버 뒤에도 청구는 러닝이 끝난 뒤다 — 0081 §B와 같은 문장 규율).
  -- [0135] 제목이 이 주석과 정면으로 모순됐다 — '결제 대기'는 일어나지 않는 사건이었다.
  -- 자리와 마감만 말한다. 20분이라는 시한은 제목이 계속 들고 있어야 한다: 알림 제목은 보호자가
  -- 가장 먼저 보는 문장이고, 대부분에게는 이 단계에 대해 보는 유일한 문장이다.
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.owner_profile_id, 'booking', '위탁 승인 — 20분 안에 자리 확정',
          '20분 안에 자리를 확정하면 돼요', sd.session_id);
  return p_session_dog;
end
$$;

-- ── C. ACL written EXPLICITLY, never relying on grant preservation.
--    `create or replace` preserves owner and ACL only where the function ALREADY exists; on a
--    partial prior apply it is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable
--    (0116:636). The pre-check above guarantees existence on the normal path — this covers the
--    path where it does not.
revoke all on function public.session_approve_dog(uuid, boolean) from public, anon;
grant execute on function public.session_approve_dog(uuid, boolean) to authenticated, service_role;

-- ── D. VERIFY — the negative AND the positive. An absence sweep alone is green on a wasteland.
do $$
declare v_src text; v_exec text; v_pub boolean; v_cfg text;
begin
  select prosrc, array_to_string(proconfig, ',') into v_src, v_cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'session_approve_dog';

  -- 🔴 STRIP COMMENT LINES BEFORE THE NEGATIVE CHECK, and this is not fastidiousness — the first
  -- draft of this VERIFY FAILED ON ITS OWN COMMENT. The ⓑ note above explains the fix by quoting
  -- the string it removed, so `prosrc like '%결제 대기%'` matched the explanation and reported the
  -- defect as surviving. That is CLAUDE.md's own law — 「a comment that quotes the code it replaced
  -- matches every grep that hunts for that code」 — walked into inside the guard written to enforce
  -- it. Fixing the CHECK rather than deleting the comment is the durable direction: the comment is
  -- worth keeping, and the next person to document a removal here would otherwise re-break this.
  select coalesce(string_agg(l, chr(10)), '') into v_exec
    from unnest(string_to_array(v_src, chr(10))) l
   where btrim(l) not like '--%';

  -- negative: no money word survives in an EXECUTABLE line of this function
  if v_exec like '%결제 대기%' or v_exec like '%결제 요청%' then
    raise exception '0135 D: the money claim survives in session_approve_dog';
  end if;

  -- positive: the replacement is present, and the REJECTION notification is untouched
  if v_exec not like '%위탁 승인 — 20분 안에 자리 확정%' then
    raise exception '0135 D: the replacement title is absent';
  end if;
  if v_exec not like '%위탁 신청 거절%' then
    raise exception '0135 D: the rejection notification was lost in the recreation';
  end if;
  -- positive: the gates the recreation had to carry forward verbatim
  if v_exec not like '%not_host%' or v_exec not like '%not_pending%'
     or v_exec not like '%session_closed%' or v_exec not like '%no_capacity%'
     or v_exec not like '%_club_delegated_reserved%' or v_exec not like '%interval ''20 minutes''%' then
    raise exception '0135 D: a gate or the hold window was lost in the recreation';
  end if;

  if v_cfg is null or v_cfg not like '%search_path=public, pg_temp%' then
    raise exception '0135 D: search_path is %, expected public, pg_temp', coalesce(v_cfg, 'NULL');
  end if;
  select has_function_privilege('public', 'public.session_approve_dog(uuid,boolean)', 'execute') into v_pub;
  if v_pub then raise exception '0135 D: session_approve_dog is PUBLIC-executable'; end if;
end $$;

commit;
