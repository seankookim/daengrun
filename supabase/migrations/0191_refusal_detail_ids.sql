-- ═══ 0191: a refusal carries an ID, not just a token — the account-deletion state gate    ═══
-- ═══        stops describing the blocker and starts naming it                              ═══
--
-- ═══ §0 WHAT THIS FILE IS ════════════════════════════════════════════════════════════════════
-- `docs/decisions/awaiting-sean.md` §0-unvicies, queued by ui2 while wiring the deletion refusals
-- and unowned since that session ended. A 409 that says `club_custody_owner` tells an owner their
-- dog is out with a runner and **not which club session**, so the client can only describe the
-- destination in prose. `0115:388-392` records the measurement that stopped it being fixed then:
-- the id could not ride the message (the client matches on the bare token) and could not ride a
-- new top-level key, because `_shared/ctx.ts`'s error arm built the body with exactly one key and
-- that file is the error contract of 24 edge functions. Both halves move in this slice —
-- `HttpError` gains an optional `detail`, `handle()` spreads it conditionally, and this migration
-- is the half that produces the id.
--
-- The carrier is Postgres's own **errdetail**, reached with `raise exception '<token>' using
-- detail = …`. PostgREST surfaces it as `error.details`, which `open-drop/handler.ts:63` already
-- threads for a different purpose, so this is an existing road rather than a new one.
--
-- ═══ §0a WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - **The MESSAGE is untouched.** Every token stays bare: `raise exception 'active_booking'
--   using detail = …` leaves SQLERRM exactly `active_booking`. The client's `REFUSALS` lookup and
--   the deno pin 「the token must survive to the client unwrapped」 are keyed on that string, and a
--   token that grew an id inside it would break both silently. Suite 222 pins the bareness of the
--   message separately from the presence of the detail, because those are two propositions.
-- - **No gate is added, removed, widened or narrowed.** Not one predicate changes. Every `exists`
--   is the same `exists`, in the same order, with the same party-before-state shape. What is
--   added is a `select … limit 1` INSIDE the branch that was already going to raise — so it runs
--   only on a refusal, only after that refusal was already decided, and can change nothing about
--   whether the refusal happens.
-- - **No ordering or locking change.** 0190 §B's catalog-copy is inherited whole; the tombstone,
--   the redaction, the ④ delete list and 0138 §F's revocation enqueue are all untouched and two
--   of them are asserted present before the copy is taken.
-- - **Three of the twelve tokens get NO detail, on purpose.** `km_balance` is a SUM over `km_lots`
--   — there is no single blocking row to name, and picking a lot would be inventing a subject.
--   `unpaid_payout` is knowingly inert (0115:284-289: nothing writes `payouts` on the deletion
--   path). `active_recurring` has a row and no route that takes its id, and this file emits an id
--   only where one honestly identifies the blocker; the client half decides separately whether a
--   route exists. Adding a detail nobody produces a subject for would be a field that reads as
--   information and is not.
--
-- ═══ §0b THE CATALOG COPY, AND WHY IT IS THE ONLY HONEST SOURCE ══════════════════════════════
-- `delete_my_account_tx` has been rewritten IN PLACE twice — 0138 §F inserted the billing-key
-- revocation enqueue, 0190 §B narrowed the bank retention predicate — each by reading `prosrc`
-- back from the catalog and patching it. So the FILE (0115) and the DEPLOYED FUNCTION disagree,
-- and transcribing 0115's text here would silently delete both landings with nothing failing.
-- This file takes the same shape and inherits its guards:
--   · the body must exist, or the apply aborts rather than guessing;
--   · 0138 §F's enqueue must be present in the body being copied;
--   · 0190 §B's `paid_payout_id is null` retention predicate must be present;
--   · **every one of the nine anchors must occur EXACTLY ONCE.** A blind `replace()` on a body
--     that had moved would no-op, the migration would apply green, and the refusals would still
--     be bare — the failure 0138 §F wrote its own guard against. The count is computed by literal
--     string arithmetic (`length(src) - length(replace(src, anchor, ''))`), not by a regex, so
--     nothing here depends on escaping parentheses and quotes correctly.
--
-- ═══ §0c `coalesce(v_block_id::text, '')` IS NOT DEFENSIVE PADDING ═══════════════════════════
-- plpgsql REFUSES a null RAISE option (`RAISE statement option cannot be null`), and the id is
-- read by a SECOND statement after the `exists` that decided the refusal. Under READ COMMITTED
-- those two statements take different snapshots, so a row committed away in between leaves
-- `v_block_id` NULL — and a bare `using detail = v_block_id::text` would then turn a correct
-- 409 refusal into a 500. The empty string is the honest value for 「there is a blocker and I
-- could not name it」: `handle()`'s spread is truthiness-gated, so an empty detail emits NO
-- `detail` key at all and the client renders no deep link. The refusal itself is unaffected.
--
-- ═══ §0d WHICH ID EACH TOKEN CARRIES ═════════════════════════════════════════════════════════
--   active_booking     bookings.id                   the blocking booking
--   active_run         runs.id                       the run that has not ended
--   unsettled_run      runs.id                       the run whose money has not moved
--   unsettled_payment  payments.id                   the payment that is not terminal
--   open_incident      incidents.id | club_incidents.id   ⚠ ONE TOKEN, TWO FAMILIES — see below
--   club_host_duty     clubs.id                      the club whose session is still open
--   club_custody       club_sessions.id              the session holding the dog
--   club_custody_owner club_sessions.id              ★ the queue item's own example
--   club_assignment    club_sessions.id              the session the assignment is on
--
-- ⚠ **`open_incident` IS A NAMED GAP, NOT A DEEP LINK.** The arm is `exists(incidents …) or
-- exists(club_incidents …)`, two different entities behind one token, and a bare uuid carries no
-- discriminator. The two client destinations are `/incident/[bid]` (keyed on the BOOKING id, not
-- the incident id) and `/club/case/[cid]` (keyed on the club incident id), so a client that
-- guessed would be right half the time — a dead button under the honesty laws. The id is emitted
-- anyway because it is the one durable handle a support thread has on 「which incident」; the
-- client deliberately renders no button for it. Closing this properly means either a typed detail
-- or two tokens, and that is a decision with copy consequences, not a patch.
--
-- ⚠ **`club_host_duty` emits a club id and the client has nowhere to spend it TODAY.**
-- `app/app/club/[id].tsx` is a dynamic route that never reads its own param (measured: zero
-- `useLocalSearchParams` in the file) — the Banpo pilot has one club and the screen loads it
-- unconditionally. So the id is correct, and linking with it would be indistinguishable from the
-- static `/community` button already there. Emitted for the support handle; no button.
--
-- ═══ §0e THE ORDER IS `order by <pk> limit 1`, DELIBERATELY ══════════════════════════════════
-- Not 「the most recent」 and not 「the worst」: any blocking row is a true answer to 「what is
-- blocking me」, and a STABLE one is what a pin can assert and what a user sees twice in a row
-- when they retry. A `created_at desc` would make the id a moving target across two identical
-- refusals seconds apart, which reads to the user as the app changing its mind.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A delete_my_account_tx — nine refusals learn to say WHICH row
-- ═══════════════════════════════════════════════════════════════════════════════════════
do $mig$
declare
  v_src     text;
  v_new     text;
  v_anchors text[];
  v_repls   text[];
  v_a       text;
  v_n       int;
  v_i       int;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then
    raise exception '0191 §A: delete_my_account_tx not found — refusing to guess';
  end if;

  -- Inherited landings that this copy must carry forward. Both are in the body we are about to
  -- rewrite; if either is absent, something re-created the function from 0115's file and the
  -- loss is already there. Stop loudly rather than carry it forward under our name.
  if position($e$perform enqueue_billing_key_revocation(p_uid, 'account_deleted');$e$ in v_src) = 0 then
    raise exception '0191 §A: 0138 §F''s revocation enqueue is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$where runner_id = p_uid and paid_payout_id is null$e$ in v_src) = 0 then
    raise exception '0191 §A: 0190 §B''s paid-marker retention predicate is not in the live body — do not copy this, find out what removed it';
  end if;

  -- ── the local that holds the blocking row's id ───────────────────────────────────────────
  -- Appended to the DECLARE block, anchored on its last line plus `begin` so the anchor cannot
  -- match the ASSIGNMENT to v_bank_kept further down the body.
  v_anchors := array[$a$  v_bank_kept boolean := false;
begin$a$];
  v_repls := array[$a$  v_bank_kept boolean := false;
  -- [0191 §A] the id of the row that BLOCKS this deletion. Read inside the refusing branch and
  -- nowhere else, so it exists only on the refusal path and cannot influence any gate. Rides the
  -- exception's DETAIL; the MESSAGE stays the bare token the client matches on.
  v_block_id uuid;
begin$a$];

  -- ── 1. active_booking → the booking id ───────────────────────────────────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'active_booking'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select b.id into v_block_id from bookings b
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and b.status in ('draft','quoted','payment_hold','matching','runner_pending','confirmed',
                        'runner_enroute','picked_up','active','incident_review','refund_pending')
     order by b.id limit 1;
    raise exception 'active_booking' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 2. active_run → the run id ───────────────────────────────────────────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'active_run'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select r.id into v_block_id from runs r join bookings b on b.id = r.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid) and r.ended_at is null
     order by r.id limit 1;
    raise exception 'active_run' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 3. unsettled_run → the run id ────────────────────────────────────────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'unsettled_run'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select r.id into v_block_id from runs r join bookings b on b.id = r.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and r.ended_at is not null and r.settled_at is null
     order by r.id limit 1;
    raise exception 'unsettled_run' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 4. unsettled_payment → the payment id ────────────────────────────────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'unsettled_payment'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select pm.id into v_block_id from payments pm join bookings b on b.id = pm.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and pm.status not in ('confirmed','canceled','partial_canceled','failed','waived')
     order by pm.id limit 1;
    raise exception 'unsettled_payment' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 5. open_incident → the incident id, from whichever family raised it (see §0d) ────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'open_incident'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select coalesce(
      (select i.id from incidents i left join bookings b on b.id = i.booking_id
        where i.resolved_at is null
          and (i.reporter_id = p_uid or b.owner_id = p_uid or b.runner_id = p_uid)
        order by i.id limit 1),
      (select ci.id from club_incidents ci
        where ci.resolved_at is null and (ci.opened_by = p_uid or ci.case_owner = p_uid)
        order by ci.id limit 1))
      into v_block_id;
    raise exception 'open_incident' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 6. club_host_duty → the club id (all three sub-arms resolve to a club) ───────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'club_host_duty'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select coalesce(
      (select cs.club_id from club_sessions cs
        where cs.status in ('open','full')
          and (cs.host_profile_id = p_uid
               or cs.backup_host_profile_id = p_uid
               or cs.original_host_profile_id = p_uid)
        order by cs.id limit 1),
      (select c.id from clubs c
        where c.host_profile_id = p_uid
          and exists (select 1 from club_sessions cs
                       where cs.club_id = c.id and cs.status in ('open','full'))
        order by c.id limit 1),
      (select cs.club_id from club_sessions cs join club_series s on s.id = cs.series_id
        where s.host_profile_id = p_uid and cs.status in ('open','full')
        order by cs.id limit 1))
      into v_block_id;
    raise exception 'club_host_duty' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 7. club_custody → the club session id (you are holding a dog) ───────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'club_custody'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select sd.session_id into v_block_id from session_dogs sd
     where sd.checked_out_at is null
       and (sd.responsible_profile_id = p_uid
            or sd.custodian_profile_id = p_uid
            or sd.current_runner_profile_id = p_uid)
     order by sd.id limit 1;
    raise exception 'club_custody' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 8. club_custody_owner → the club session id ★ the queue item's own example ──────────
  -- 0115:388-392 wrote 「the refusal is a BARE TOKEN — it does not carry the club session id.
  -- Attaching one was ordered and then withdrawn after measurement」, and named `ctx.ts` as the
  -- reason. That sentence is what this slice retires.
  v_anchors := v_anchors || array[$a$  ) then raise exception 'club_custody_owner'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select sd.session_id into v_block_id from session_dogs sd
     where sd.checked_out_at is null
       and sd.owner_profile_id = p_uid
     order by sd.id limit 1;
    raise exception 'club_custody_owner' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── 9. club_assignment → the club session id ────────────────────────────────────────────
  v_anchors := v_anchors || array[$a$  ) then raise exception 'club_assignment'; end if;$a$];
  v_repls := v_repls || array[$a$  ) then
    select sra.session_id into v_block_id from session_runner_assignments sra
     join club_sessions cs on cs.id = sra.session_id
     where sra.runner_profile_id = p_uid and sra.status = 'committed'
       and cs.scheduled_at > now() and cs.status in ('open','full')
     order by cs.id limit 1;
    raise exception 'club_assignment' using detail = coalesce(v_block_id::text, '');
  end if;$a$];

  -- ── apply, each anchor asserted UNIQUE before it is used ─────────────────────────────────
  -- Literal string arithmetic rather than a regex: the anchors carry parentheses and quotes, and
  -- a mis-escaped pattern that silently matched nothing would put this guard on the wrong side
  -- of the thing it guards.
  v_new := v_src;
  for v_i in 1 .. array_length(v_anchors, 1) loop
    v_a := v_anchors[v_i];
    v_n := (length(v_new) - length(replace(v_new, v_a, ''))) / length(v_a);
    if v_n is distinct from 1 then
      raise exception '0191 §A: anchor % occurs % time(s) in delete_my_account_tx, expected exactly 1 — patch by hand', v_i, v_n;
    end if;
    v_new := replace(v_new, v_a, v_repls[v_i]);
  end loop;
  if v_new = v_src then raise exception '0191 §A: patch did not apply'; end if;

  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);
end $mig$;

-- 0115:645-648 / 0138 §F / 0190 §B's ACL restated — a `create or replace` on an absent-function
-- path is a plain CREATE, and a SECURITY DEFINER born PUBLIC-executable is the worst shape this
-- repo makes.
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant  execute on function delete_my_account_tx(uuid) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B VERIFY — the apply refuses to leave a half-done refusal contract behind
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Comments are STRIPPED before matching. `prosrc` is source PLUS our own prose, and the blocks
-- above quote the very strings these arms look for — an un-stripped match would be satisfied by
-- the explanation rather than by the code, and the better the explanation the more certainly.
do $mig$
declare
  v_txt   text;
  v_bad   text := '';
  v_tok   text;
  v_toks  text[] := array[
    'active_booking','active_run','unsettled_run','unsettled_payment','open_incident',
    'club_host_duty','club_custody','club_custody_owner','club_assignment'];
begin
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_txt
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';

  -- Fail LOUDLY on absence: a NULL body makes every `position(... in NULL)` below NULL, and a
  -- bare IF on NULL fires no arm at all — the whole battery would go silent in exactly the case
  -- it exists for.
  if v_txt is null then
    raise exception '0191 §B: NO-SOURCE(delete_my_account_tx)';
  end if;

  -- ⚠ Every needle below is DOLLAR-QUOTED. These strings are dense with single quotes, and a
  -- mis-escaped `''''` that silently matched nothing would put this guard on the wrong side of
  -- the thing it guards — a green produced by a typo in the checker.
  foreach v_tok in array v_toks loop
    -- the DETAIL is attached …
    if (position($q$raise exception '$q$ || v_tok || $q$' using detail = coalesce(v_block_id::text, '')$q$ in v_txt) > 0) is not true then
      v_bad := v_bad || ' DETAIL-MISSING(' || v_tok || ')';
    end if;
    -- … and the bare `raise exception '<token>';` form is GONE, so no arm was left behind.
    if (position($q$raise exception '$q$ || v_tok || $q$';$q$ in v_txt) > 0) is not false then
      v_bad := v_bad || ' STILL-BARE(' || v_tok || ')';
    end if;
  end loop;

  -- the local exists, and the two inherited landings survived the copy
  if (position($q$v_block_id uuid;$q$ in v_txt) > 0) is not true then
    v_bad := v_bad || ' NO-BLOCK-ID-LOCAL';
  end if;
  if (position($q$enqueue_billing_key_revocation(p_uid, 'account_deleted')$q$ in v_txt) > 0) is not true then
    v_bad := v_bad || ' 0138-ENQUEUE-LOST-IN-THE-COPY';
  end if;
  if (position($q$where runner_id = p_uid and paid_payout_id is null$q$ in v_txt) > 0) is not true then
    v_bad := v_bad || ' 0190-RETENTION-LOST-IN-THE-COPY';
  end if;

  -- the shape the ACL restatement above is protecting
  if (select p.prosecdef from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       and ns.nspname = 'public' where p.proname = 'delete_my_account_tx') is not true then
    v_bad := v_bad || ' NOT-SECURITY-DEFINER';
  end if;
  if (select 'search_path=public, pg_temp' = any(p.proconfig) from pg_proc p
       join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
      where p.proname = 'delete_my_account_tx') is not true then
    v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH';
  end if;

  if v_bad <> '' then
    raise exception '0191 §B VERIFY:%', v_bad;
  end if;
  raise notice '0191 §B VERIFY ok — nine refusals carry a detail, the messages stay bare';
end $mig$;

comment on function delete_my_account_tx(uuid) is
  '0115 §D + [0138 §F] + [0190 §B] + [0191 §A]: 탈퇴 트랜잭션. [0191 §A] 열두 개 상태 게이트 중
아홉 개가 막는 행의 id를 Postgres errdetail로 함께 보낸다 — 메시지는 여전히 맨 토큰이다(클라이언트가
그 문자열로 매칭한다). 거절 분기 안에서만 select 하므로 어떤 게이트도 바뀌지 않는다. km_balance는
합계라 지목할 행이 없고, unpaid_payout은 기록자가 없어 발화하지 않으며, active_recurring은 id를 쓸
경로가 없어 세 개는 맨 토큰으로 남는다. open_incident는 incidents와 club_incidents 두 계열이 한
토큰을 공유해 id만으로는 어느 화면인지 구분할 수 없다 — id는 보내되 클라이언트는 버튼을 그리지
않는다(222 D3에 기록된 명시적 공백). NULL은 plpgsql이 RAISE 옵션으로 받지 않으므로 coalesce로
빈 문자열을 보내고, ctx.ts의 조건부 스프레드가 빈 값을 키 자체 없음으로 만든다.';
