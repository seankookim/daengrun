-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0116 — the four defects that are INERT while charging is off and REAL the day it flips
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Queue: docs/decisions/awaiting-sean.md §0-tricies items 1-4. Sean approved bundling them.
-- Every one of these is harmless today — `ops_flags.payments_live_since` is null, there are 0
-- payments, 0 billing keys, `TOSS_SECRET_KEY` is unset and the Vault secret is absent — which is
-- exactly why they are worth fixing NOW rather than on flip day with money moving.
--
-- ═══ WHOSE OBJECTS THIS FILE RE-CREATES (REGISTRY.md silent-collision law) ═══════════════════
-- This file EXTENDS six existing objects. Each one names the version it builds on:
--   §A `sweep_settled_without_payments`   ← 0080 §G   (0083 §0f handed this predicate to 0080's
--                                                      owner explicitly; this is that handoff
--                                                      being collected, not a drive-by edit)
--   §B `_club_record_cancel_fee`          ← 0048 §B
--   §C `dispatch_due_charges`             ← 0080 §K ⓑ
--   §D `club_incident_settle_quote`       ← 0072 §A
--       `runner_work_gate`                ← 0092 §7
--       `club_dog_ui_state`               ← 0052 §6   (v5 — the newest of six definitions)
--       `club_host_stats`                 ← 0031
-- NEW objects: `charge_max_attempts`, `charge_row_due`, `_charge_ts`, `_charge_int`,
-- `_charge_bool`. Nothing else in the repo creates or replaces any of these.
--
-- ⚠ `search_path`: four of the extended functions carried `set search_path = public` in their
-- own file and pass 98 H1 today only because a later ALTER retro-sealed them. `create or replace`
-- RESETS an ALTER-applied config (REGISTRY, measured), so every function below writes
-- `public, pg_temp` in its OWN body. Dropping that line turns 98 H1 red, which is the point.
--
-- Suite: 151_flip_blockers_suite.sql. It pins each fix BOTH ways (the thing that must now be
-- refused, and the legitimate caller that must still work), and every pin was mutation-verified
-- by deleting its fix and reading the red set — see the suite header for the exact sets.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  F1 — a charge could mint for a dog still on the leash
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0083 §6 changed what `runs.ended_at` MEANS: it used to mean settlement, it now means the STOP.
-- 0080 §G's sweep was written against the old meaning, so from 0083 onward it can see a run that
-- stopped and has not been returned yet, and mint the owner's charge while the dog is still with
-- the runner. 0083 §0f named the hole, refused to fix it inside 0080's territory, wrote out the
-- one-line predicate, and blocked the cutover on it. This is that line landing.
--
--       and rn.settled_at is not null        -- (0083 §1: did money actually happen)
--
-- Verified live by the announcer before this slice opened (`prosrc like '%settled_at is not
-- null%'` → false, while the body does reference `ended_at`).
--
-- ⚠ The two substitutes a reader will reach for are BOTH wrong and 0083 §0f says why:
--   · `bookings.status` — §0-ter #11 / 116 C8: a settled booking legitimately moves on to
--     incident_review or refund_pending, and anchoring there hides the very crash the sweep exists
--     to catch.
--   · `ledger_items` presence — 0080 §K writes a ledger row for a CANCELLED booking, which is not
--     a run at all (REGISTRY records this under 0081 for the same reason).
-- `runs.settled_at` is written by settlement and by nothing else; 119 R11 is the pin that keeps
-- that true, and this predicate is why that pin matters.
--
-- Everything else below is 0080 §G byte-faithful. The scope guard, the aligned "has a payments
-- row" predicate, the two per-row refusals (missing end_reason / missing actual_km) and the
-- per-row exception guard are all preserved exactly — this migration adds one line to a WHERE
-- clause and changes nothing else about how the sweep prices or refuses a run.
create or replace function sweep_settled_without_payments() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  n int := 0;
  v_minted boolean;
  v_since timestamptz;
begin
  select f.payments_live_since into v_since from ops_flags f where f.id;
  if v_since is null then return 0; end if;

  for r in
    select b.id as booking_id, rn.end_reason::text as end_reason, rn.actual_km
    from bookings b
    join runs rn on rn.booking_id = b.id
    where rn.ended_at is not null
      and rn.ended_at >= v_since
      -- [0116 §A / 0083 §0f] DID MONEY ACTUALLY HAPPEN. After 0083 the RETURN handoff is what
      -- says the dog is home; `ended_at` alone only says the run stopped. Without this line the
      -- sweep bills an owner while the runner still has their dog.
      and rn.settled_at is not null
      -- "Has a payments row" must mean the SAME thing here as it does in the mint's exists-check
      -- (round-2 R3 P3-9). The old bare `not exists` let any payments row at all blind the sweep,
      -- including the widget flow's kind-less failed/canceled/pending debris — which captures
      -- nothing, blocks nothing in the mint, and would therefore leave a genuinely settled booking
      -- with no charge intent and no sweep willing to look at it. Aligned predicate: a row counts
      -- only if this machine minted it (kind) or if it settles the question (confirmed/waived).
      and not exists (
        select 1 from payments p
        where p.booking_id = b.id
          and ((p.raw->>'kind') is not null or p.status in ('confirmed', 'waived'))
      )
  loop
    -- A finished run with no end_reason cannot be priced honestly, and guessing 'completed'
    -- would charge the owner the full quote on a guess. Leave it for a human (§I is where it
    -- shows up as a settled booking that still has no row).
    if r.end_reason is null then
      raise notice 'sweep_settled_without_payments: booking % has ended_at but no end_reason — skipped', r.booking_id;
      continue;
    end if;
    -- Symmetric refusal for a missing actual_km (round-2 R1 P3). The mint would coalesce NULL to
    -- 0 km and charge the base + addons on an unmeasured run — or, on an owner-caused end, the
    -- whole planned quote — from a number nobody recorded. `actual_km` is not nullable in
    -- practice (settle_run_tx writes it), so a NULL here means something is already wrong, and
    -- the honest output of a money sweep facing a broken row is a NOTICE, not an invoice.
    if r.actual_km is null then
      raise notice 'sweep_settled_without_payments: booking % has ended_at but no actual_km — skipped', r.booking_id;
      continue;
    end if;
    begin
      select m.minted into v_minted
      from mint_settle_charge_intent(r.booking_id, r.end_reason, r.actual_km) m;
      if coalesce(v_minted, false) then n := n + 1; end if;
    exception when others then
      raise notice 'sweep_settled_without_payments: booking % — %', r.booking_id, sqlerrm;
    end;
  end loop;
  return n;
end $$;
revoke execute on function sweep_settled_without_payments() from public, anon, authenticated;
grant execute on function sweep_settled_without_payments() to service_role;

comment on function sweep_settled_without_payments is
  '0080 §G + [0116 §A]: invariant #1 (§0-ter #1) — a booking whose run is SETTLED
(`runs.settled_at`, 0083 §0f) and has no payments row gets one, minted from the runs row''s own
end_reason/actual_km (a run missing either is SKIPPED with a notice — a money sweep does not
guess). ⚠ `settled_at`, never `ended_at` alone: after 0083 `ended_at` means the run STOPPED, and
minting on it bills an owner whose dog is still on the leash. Never `bookings.status` (§0-ter #11
/ 116 C8) and never `ledger_items` presence (0080 §K writes one for a cancelled booking). "Has a
row" is the mint''s definition, not any row: kind-bearing or confirmed/waived, so widget debris
cannot blind it. Scoped to runs that ended at or after ops_flags.payments_live_since (0 while
null) — the flip must never bill a pilot-era run retroactively';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  F2 — the club cancel fee never reaches the money, and the runner's share never lands
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- `_club_record_cancel_fee` (0048 §B) computes the fee, splits it, and writes BOTH halves to
-- `club_fee_items` — a ledger of intent that nothing downstream reads. It never writes
-- `bookings.cancel_fee`. Verified live by the announcer (writes_booking_fee → false,
-- writes_club_items → true). Two consequences, both dormant only because charging is off:
--   · `mint_cancel_fee_intent` (0080 §E) reads `coalesce(b.cancel_fee, 0)` and mints NOTHING at
--     0, so a club cancellation is structurally uncollectable.
--   · `owner_has_unsettled_charge` (0080 §F) scopes on `coalesce(b.cancel_fee, 0) > 0`, so the
--     debt gate cannot see it either.
--   · and `my_ledger_total` (0027) sums `ledger_items`, which this function never writes — so the
--     runner's supply-compensation share exists as a club_fee_items row and as nothing the runner
--     can ever be paid from.
--
-- ⚠ WHAT THIS SECTION DELIBERATELY DOES **NOT** DO — read before "finishing" it.
-- TWO FEE LADDERS EXIST and which one governs a club cancellation is Sean's open ruling
-- (§0-tricies item 2):
--   · the club ladder — `club_cfg('cancel_post_accept_pct')` 20 / `cancel_late_pct` 10 / free,
--     split 50/50 platform:runner by `club_cfg('fee_platform_split_pct')` (0048/0057)
--   · the marketplace ladder — 0066's 0 / 50% en-route / 0 / 10%, with 0085 paying the runner
--     50% of the fee
-- This file CHOOSES NEITHER. It takes the amounts the existing code ALREADY computed — `v_fee`
-- and the supply-compensation share `v_fee - v_plat` — and connects them to the two places that
-- were never wired. If Sean later rules that the marketplace ladder governs, the ladder changes
-- in `session_cancel_delegation`'s percentage arms and this plumbing keeps working unchanged.
-- Writing the ruling into this file would have made a decision that is not this slice's to make.
--
-- ── Two idioms borrowed verbatim, and why each ────────────────────────────────────────────
-- ① FIRST WRITER WINS on `bookings.cancel_fee` (`and coalesce(cancel_fee, 0) = 0`). Post-cutover
--    a payments row is minted FROM this number, so silently re-pricing it under a live charge
--    intent is the one thing a second call must not do. Same direction as 0080 §E and 0085: an
--    already-recorded amount is REPORTED, never overwritten.
-- ② The ledger write takes 0080 §K's `comp:` advisory key and 0085's existence check, because it
--    is a THIRD writer into the same one-row-per-booking space. `ledger_items` has no unique key
--    on booking_id (0001:264, 0080:1112 explains why), so the shared lock IS the serialization —
--    read-then-insert under a per-booking lock. Sharing the key means the club comp writer and
--    the two marketplace comp writers cannot interleave past each other's existence check even
--    if a caller bug got two of them running for one booking.
-- ③ The share sits in `remaining_guarantee` with `platform_fee` = 0. MEASURED TRAP, transcribed
--    from 0085: `my_ledger_total` subtracts `platform_fee`, so recording the platform's half
--    there — which reads as the honest double-entry thing to do — nets the runner to ZERO at a
--    50/50 split. The ledger is the RUNNER's book of what they are owed, not a double-entry one.
--    The platform's half stays in `club_fee_items`, where 0048 already puts it.
-- ④ `p_runner` is passed in, not read back from `bookings.runner_id`, because
--    `session_cancel_delegation` NULLs `runner_id` before calling this (it revokes the assignment
--    first). The caller's captured runner is the only correct one.
create or replace function _club_record_cancel_fee(
  p_session uuid, p_sd uuid, p_booking uuid, p_kind text,
  p_base int, p_pct numeric, p_runner uuid, p_rule text
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_fee int; v_plat int; v_share int;
begin
  v_fee := round(p_base * p_pct / 100.0)::int;
  if v_fee <= 0 then return; end if;
  v_plat := round(v_fee * coalesce(club_cfg('fee_platform_split_pct'), 50) / 100.0)::int;
  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
    recipient_type, recipient_profile_id, basis)
  values
    (p_session, p_sd, p_booking, p_kind, v_plat, 'platform', null,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule, 'share', 'platform')),
    (p_session, p_sd, p_booking, p_kind, v_fee - v_plat,
     case when p_runner is not null then 'runner' else 'platform' end, p_runner,
     jsonb_build_object('pct', p_pct, 'base', p_base, 'rule', p_rule, 'share', 'supply_compensation'));

  if p_booking is null then return; end if;   -- session-level fee with no booking: nothing to bill

  -- [0116 §B ①] the owner's side — the number the charge mint and the debt gate both read
  update bookings set cancel_fee = v_fee
  where id = p_booking and coalesce(cancel_fee, 0) = 0;

  -- [0116 §B ②③④] the runner's side — supply compensation reaching `my_ledger_total`
  if p_runner is null then return; end if;
  v_share := v_fee - v_plat;
  if v_share <= 0 then return; end if;        -- a share that rounds to nothing pays nothing
  perform pg_advisory_xact_lock(hashtextextended('comp:' || p_booking::text, 0));
  if exists (select 1 from ledger_items li where li.booking_id = p_booking) then return; end if;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                            tip, remaining_guarantee, platform_fee)
  values (p_runner, p_booking, 0, 0, 0, 0, v_share, 0);
end $$;
revoke execute on function _club_record_cancel_fee(uuid, uuid, uuid, text, int, numeric, uuid, text)
  from public, anon, authenticated;

comment on function _club_record_cancel_fee is
  '0048 §B + [0116 §B]: 클럽 취소·노쇼 수수료 분배. club_fee_items 두 행(플랫폼 몫 + 공급 보상)에
더해 이제 **bookings.cancel_fee**(보호자가 실제로 청구받는 금액 — 0080 §E 민팅과 §F 부채 게이트가
읽는 유일한 숫자)와 **ledger_items.remaining_guarantee**(러너의 공급 보상 — my_ledger_total이
읽는 유일한 곳)까지 쓴다. cancel_fee는 먼저 쓴 값이 이긴다(살아있는 청구 인텐트의 금액을 조용히
바꾸지 않는다). 원장 쓰기는 0080 §K의 comp: 자문 락 + 부킹당 1행 검사 — 세 comp 작성자가 같은
키 공간을 공유한다. platform_fee는 0 (my_ledger_total이 그것을 빼기 때문). ⚠ 어느 사다리가
지배하는지는 결정되지 않았다 — 이 파일은 배관만 잇고 기존 계산식을 그대로 쓴다';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  F3 — one unparseable timestamp stopped charge dispatch for EVERYBODY
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0080 §K ⓑ's own comment says it out loud: "THIS PREDICATE AND `isDue()` IN
-- collect-charges/handler.ts ARE ONE RULE WRITTEN TWICE … They must change together." Two copies
-- of a rule kept in agreement by discipline is a promise, not a mechanism, and they had already
-- drifted in two ways:
--   ① SQL hardcoded `< 3` where TS reads `MAX_ATTEMPTS` from `_shared/charge.ts`. Equal today;
--      the next person to move the cap moves one of them.
--   ② SQL cast `(p.raw->>'next_retry_at')::timestamptz` **inside the count**, so ONE row with an
--      unparseable timestamp raises → the function's outer handler catches it → it returns 0 and
--      posts nothing. The batch then never wakes FOR ANYBODY, for as long as that row exists.
--      Meanwhile TS reads the same row as DUE (`!Number.isFinite(at)` → true). So the two sides
--      disagreed about the poisoned row AND the poisoned row silenced the whole ladder.
--      ⚠ The same shape sits on three other jsonb reads in that predicate — `attempts`,
--      `needs_card_relink`, `dispatched_at` — and every one of them is the same one-row outage.
--
-- THE FIX: the rule becomes ONE NAMED SQL OBJECT, `charge_row_due`, and the cap becomes one
-- named SQL object, `charge_max_attempts()`. `dispatch_due_charges` calls the rule per row rather
-- than open-coding it, so a row that cannot be parsed fails THAT ROW (it is simply not due) and
-- never the batch. The TS side keeps its own evaluation — moving row selection into an RPC would
-- put a third copy of the rule in the Deno fake DB — but it no longer keeps its own COPY of the
-- number: `collect-charges` now reads `charge_max_attempts()` at the top of each batch and
-- reports a mismatch loudly instead of the two sides silently disagreeing. Discipline replaced
-- by a detector, which is the most this repo can honestly claim across a SQL/TS boundary.
--
-- ── The three parse helpers, and why each returns instead of raising ─────────────────────
-- Each one models what the TS side does with the same jsonb value, so "they agree" is a property
-- of the helpers rather than of two hand-written predicates:
--   `_charge_ts`   — unparseable OR absent → NULL. `charge_row_due` then coalesces `next_retry_at`
--                    to -infinity, i.e. DUE. That is TS's direction and TS's stated reason: "A
--                    MISSING next_retry_at is DUE, not exempt … An unparseable timestamp goes the
--                    same way." The failure direction to prefer is one extra attempt, which the
--                    attempt cap already bounds.
--   `_charge_int`  — models `Number(x ?? 0)`: a JSON number OR a numeric string parses; anything
--                    else is NULL, which `charge_row_due` coalesces to 0 (= not spent = due),
--                    matching `NaN >= MAX_ATTEMPTS` → false.
--   `_charge_bool` — models JS truthiness exactly (`false`/`0`/`""`/absent/null are falsy, every
--                    other value truthy) with no cast that can raise. The safe direction for a
--                    garbage `needs_card_relink` is "the flag is set": we do not hammer a card
--                    the row says is dead.
create or replace function _charge_ts(p_raw jsonb, p_key text) returns timestamptz
language plpgsql stable set search_path = public, pg_temp as $$
begin
  return (p_raw->>p_key)::timestamptz;      -- absent key → NULL::text → NULL, no exception
exception when others then
  return null;                              -- garbage in a money row must not raise
end $$;

create or replace function _charge_int(p_raw jsonb, p_key text) returns int
language plpgsql stable set search_path = public, pg_temp as $$
begin
  return floor((p_raw->>p_key)::numeric)::int;
exception when others then
  return null;
end $$;

create or replace function _charge_bool(p_raw jsonb, p_key text) returns boolean
language sql stable set search_path = public, pg_temp as $$
  select case jsonb_typeof(p_raw->p_key)
           when 'boolean' then (p_raw->p_key)::boolean
           when 'null'    then false
           when 'number'  then (p_raw->>p_key)::numeric <> 0
           when 'string'  then (p_raw->>p_key) <> ''
           else (p_raw->p_key) is not null      -- object/array = truthy; absent key = false
         end
$$;

-- The ladder cap, named once on this side of the wire. `_shared/charge.ts` exports the same
-- number as MAX_ATTEMPTS; `collect-charges` compares them every batch.
create or replace function charge_max_attempts() returns int
language sql immutable set search_path = public, pg_temp as $$ select 3 $$;

-- THE due rule. One object, three arms, no cast that can raise.
--   ⓐ a failed row with rungs left, whose next rung has arrived, and whose card is not known-dead.
--      `needs_card_relink` is the 카드 재연결 class: retrying a dead billing key on a timer
--      produces three identical declines and three identical notifications, so that row waits for
--      the owner to relink, not for the clock.
--   ⓑ a server intent minted but never dispatched (settle-run's immediate attempt did not happen
--      or died before writing dispatched_at).
--   ⓒ a DISPATCHED pending older than 15 minutes — the row 0080 §I deliberately refuses to
--      auto-fail. Waking for it is not a re-charge: it wakes collect-charges' verification arm,
--      which asks Toss for the orderId's real outcome.
-- `kind` and `amount > 0` sit above the status split because that is where isDue() has them: a
-- kind-less row is widget-era debris nobody may charge, and a zero-amount kind row is a waive that
-- never became one.
create or replace function charge_row_due(p_status text, p_amount int, p_raw jsonb, p_at timestamptz)
returns boolean
language sql stable set search_path = public, pg_temp as $$
  -- ⚠ the outer coalesce is not decoration. Arm ⓒ's comparison is NULL when `dispatched_at` is
  -- unparseable, and `false or false or NULL` is NULL — which a WHERE clause silently treats as
  -- "no", but which any caller reading the boolean directly (a pin, a future ops query) would
  -- have to know to coalesce itself. A rule about money answers yes or no.
  select coalesce(
       (p_raw->>'kind') is not null
   and coalesce(p_amount, 0) > 0
   and (
        (p_status = 'failed'
          and coalesce(_charge_int(p_raw, 'attempts'), 0) < charge_max_attempts()
          and coalesce(_charge_bool(p_raw, 'needs_card_relink'), false) = false
          and coalesce(_charge_ts(p_raw, 'next_retry_at'), '-infinity'::timestamptz) <= p_at)
     or (p_status = 'pending' and (p_raw->>'dispatched_at') is null)
     or (p_status = 'pending'
          and _charge_ts(p_raw, 'dispatched_at') <= p_at - interval '15 minutes')
   ), false)
$$;

revoke execute on function _charge_ts(jsonb, text) from public, anon, authenticated;
revoke execute on function _charge_int(jsonb, text) from public, anon, authenticated;
revoke execute on function _charge_bool(jsonb, text) from public, anon, authenticated;
revoke execute on function charge_row_due(text, int, jsonb, timestamptz) from public, anon, authenticated;
revoke execute on function charge_max_attempts() from public, anon;
grant execute on function _charge_ts(jsonb, text) to service_role;
grant execute on function _charge_int(jsonb, text) to service_role;
grant execute on function _charge_bool(jsonb, text) to service_role;
grant execute on function charge_row_due(text, int, jsonb, timestamptz) to service_role;
-- `charge_max_attempts` stays readable by `authenticated` as well: it is a published policy
-- number (the debt screen's copy says how many attempts the ladder makes), it reads no row, and
-- collect-charges' drift check must work from the cron path too.
grant execute on function charge_max_attempts() to authenticated, service_role;

comment on function charge_row_due is
  '0116 §C: THE due rule for a payments row — the single SQL definition that dispatch_due_charges
calls per row. Never raises: every jsonb read goes through _charge_ts/_charge_int/_charge_bool,
which model what collect-charges'' isDue() does with the same value (unparseable next_retry_at =
DUE, unparseable attempts = 0, garbage needs_card_relink = set). Before this existed the predicate
was open-coded with bare ::timestamptz casts, so ONE poisoned row raised inside the count and the
whole batch never woke — for everybody';

comment on function charge_max_attempts is
  '0116 §C: the retry ladder''s attempt cap, named once in SQL. `_shared/charge.ts` exports the
same number as MAX_ATTEMPTS and collect-charges compares the two at the top of every batch, so a
drift is reported instead of silently splitting the two sides'' idea of "spent"';

-- ---------- dispatch_due_charges — 0080 §K ⓑ, now calling the rule instead of copying it -----
-- The vault → pg_net bridge below is 0080's, byte-faithful. The ONLY change is that the due
-- predicate is now `charge_row_due(...)` per row. Everything stays exception-guarded, for the two
-- reasons 0080 gives: the local harness has no vault (and stubs pg_net), and in production a
-- dispatcher that raises leaves a cron job flapping instead of retrying next tick.
create or replace function dispatch_due_charges() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_due int;
  v_secret text;
  v_cfg jsonb;
  v_url text;
  v_key text;
begin
  -- [0116 §C] The rule lives in `charge_row_due` and is applied PER ROW. A row this function
  -- cannot parse is simply not due — it does not raise, and it does not take the batch down with
  -- it. `status in (...)` stays in the query so the index/scan is bounded before the rule runs.
  select count(*)::int into v_due
  from payments p
  where p.status in ('pending', 'failed')
    and charge_row_due(p.status, p.amount, p.raw, now());
  if v_due = 0 then return 0; end if;

  begin
    select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'charge_dispatch';
  exception when others then
    raise notice 'dispatch_due_charges: vault unavailable (%) — % due row(s) left for the next tick', sqlerrm, v_due;
    return 0;
  end;
  if v_secret is null then
    raise notice 'dispatch_due_charges: vault secret charge_dispatch absent — % due row(s) left for the next tick', v_due;
    return 0;
  end if;

  v_cfg := v_secret::jsonb;
  v_url := v_cfg->>'url';
  v_key := v_cfg->>'cron_key';
  if v_url is null or v_key is null then
    raise notice 'dispatch_due_charges: charge_dispatch secret needs {"url":…,"cron_key":…}';
    return 0;
  end if;

  perform net.http_post(
    url := v_url || '/collect-charges',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Key', v_key),
    body := jsonb_build_object('mode', 'batch')
  );
  return v_due;
exception when others then
  -- A dispatcher must never be the reason a cron job dies. The rows stay due.
  raise notice 'dispatch_due_charges: %', sqlerrm;
  return 0;
end $$;
revoke execute on function dispatch_due_charges() from public, anon, authenticated;
grant execute on function dispatch_due_charges() to service_role;

comment on function dispatch_due_charges is
  '0080 §K + [0116 §C]: wakes collect-charges for due rows. 술어는 이제 `charge_row_due` 하나 —
행마다 적용되므로 파싱 불가능한 행 하나가 배치 전체를 잠재우지 못한다 (그 전에는 next_retry_at
하나가 ::timestamptz에서 raise → 함수가 0을 반환 → 모든 사용자에 대해 배치가 영영 깨어나지
않았다). 사다리 상한은 charge_max_attempts() 하나이고 collect-charges가 매 배치마다 TS의
MAX_ATTEMPTS와 대조한다. Reads the vault secret charge_dispatch {"url","cron_key"}; absent
vault/secret = a NOTICE and 0, which is the correct pre-cutover state. Fully exception-guarded —
the ladder retries next tick, the cron job never dies';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  F4 — four definers that answer questions about strangers
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- The server sweep measured four functions holding `authenticated` EXECUTE that take a
-- caller-supplied id and contain no `auth.uid()` anywhere. A `security definer` bypasses RLS, so
-- for each of them the row-level protection on the underlying tables is simply not in the path.
-- House law: the party gate goes BEFORE the state gate, and "no such thing" and "not yours" get
-- the SAME answer so the function is not an enumeration oracle (0054:73 / 0067 §C).
--
-- ⚠ ONE SHAPE IS SHARED BY ALL FOUR AND IS DELIBERATE: the gate fires only when
-- `auth.uid() is not null`. Reaching these functions requires EXECUTE, and after the revokes
-- below the only holders are `authenticated` — which by construction carries a JWT `sub` — and
-- server roles, which carry none. So a null uid is a server/ops caller (and the harness), never a
-- client, and refusing it would break `transition-booking`, the delegation board's server path
-- and every suite that measures these functions directly without buying any security.
-- The suite pins this explicitly rather than leaving it as an assumption.

-- ---------- ⓐ club_incident_settle_quote (HIGH) — 0072 §A -----------------------------------
-- What it hands out for ANY booking id: total_price, base_fare, distance_fare, addon_fare, the
-- measured km, BOTH handoff timestamps (as `took_custody`), and the runner's commission-derived
-- fee. That is the full money and handoff-timing readout of a stranger's booking.
--
-- The gate mirrors the AUTHORITY of the mutation it quotes for (`club_incident_settle`, 0072 §B)
-- and adds the booking's own parties, who can already read the booking row through RLS:
--   · the owner or the runner of the booking
--   · the host or backup host of the booking's club session
--   · the case owner, or the host/backup host, of an incident that NAMES this booking as a subject
-- The last arm is what keeps the shipped client path working: `app/app/club/case/[cid].tsx` quotes
-- all three outcomes from the case screen, and its caller is exactly that set.
-- ⚠ `exists`, never `auth.uid() in (host, backup_host)` — 0058 F1 / 110 S2: a NULL backup host
-- collapses `uid in (host, null)` to NULL for an unrelated caller and `not (NULL)` never fires,
-- which is fail-OPEN. `exists` treats NULL as "no row".
create or replace function club_incident_settle_quote(p_booking uuid, p_outcome text)
returns table (refund int, runner_gross int, runner_fee int, runner_net int,
               measured_km numeric, took_custody boolean, basis text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare b record; v_km numeric; v_ratio numeric; v_gross int; v_rate numeric; v_custody boolean;
begin
  select id, km, base_fare, distance_fare, addon_fare, total_price, runner_id, owner_id,
         club_session_id, owner_confirmed_handoff_at, runner_confirmed_handoff_at
    into b from bookings where id = p_booking;
  -- [0116 §D ⓐ] PARTY GATE BEFORE STATE GATE. `not_found` and "not yours" are the SAME sentence
  -- on purpose: two answers make this an enumeration oracle over other people's booking ids.
  if b.id is null then raise exception 'not_found'; end if;
  -- ⚠ THE `coalesce(…, false)` IS LOAD-BEARING AND WAS EARNED, NOT COPIED. The first version of
  -- this gate was `not ( owner = uid or runner = uid or exists(…) or exists(…) )` and 151 B5
  -- caught it FAIL-OPEN on the first run: `bookings.runner_id` is NULL for a cancelled club
  -- booking (`session_cancel_delegation` revokes the assignment before recording the fee), so
  -- `NULL = <stranger>` is NULL, the whole disjunction collapses to NULL, `not NULL` is NULL, and
  -- the IF never fires. A stranger read the booking's full fare breakdown and both handoff
  -- timestamps. That is 0058 F1 and 110 S2's trap — which this very file's §D header quotes —
  -- reproduced one arm over by the person quoting it. The `exists` arms below were already
  -- NULL-safe; the two column comparisons were not, and one comparison is enough.
  if auth.uid() is not null and not coalesce(
       b.owner_id = auth.uid()
    or b.runner_id = auth.uid()
    or exists (select 1 from club_sessions cs where cs.id = b.club_session_id
                 and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
    or exists (select 1 from club_incidents i
                 join club_incident_subjects sub on sub.incident_id = i.id
                where sub.subject_type = 'booking' and sub.subject_id = p_booking
                  and ((i.case_owner is not null and i.case_owner = auth.uid())
                       or exists (select 1 from club_sessions cs2 where cs2.id = i.session_id
                                    and auth.uid() in (cs2.host_profile_id, cs2.backup_host_profile_id))))
  , false) then
    raise exception 'not_found';
  end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  -- 인계가 실제로 일어났는가 = 기본요금(픽업·보호 책임)을 벌었는가. 부킹은 지금 incident_review라
  -- 예전 상태를 읽을 수 없지만, 양측 인계 스탬프는 남아 있다 (picked_up의 전제 그 자체).
  v_custody := b.owner_confirmed_handoff_at is not null and b.runner_confirmed_handoff_at is not null;
  v_km := coalesce((select r.actual_km from runs r where r.booking_id = p_booking), 0);
  v_ratio := case when coalesce(b.km, 0) > 0 then least(1.0, v_km / b.km) else 0 end;
  select coalesce(rn.commission_rate, 0.33) into v_rate
  from runners rn where rn.profile_id = b.runner_id;
  v_rate := coalesce(v_rate, 0.33);   -- 러너 행 부재 시에도 0059 정책과 일치 (저과금 방지)

  v_gross := case p_outcome
    when 'refund_full' then 0
    when 'pay_full'    then b.total_price
    else least(b.total_price,
           (case when v_custody then coalesce(b.base_fare, 0) else 0 end)
           + round((coalesce(b.distance_fare, 0) + coalesce(b.addon_fare, 0)) * v_ratio)::int)
  end;

  refund := b.total_price - v_gross;
  runner_gross := v_gross;
  runner_fee := round(v_gross * v_rate)::int;
  runner_net := v_gross - runner_fee;
  measured_km := v_km;
  took_custody := v_custody;
  basis := case p_outcome
    when 'refund_full' then 'incident_refund_full'
    when 'pay_full'    then 'incident_pay_full'
    else 'incident_measured:' || (case when v_custody then 'custody+' else 'no_custody+' end)
         || round(v_ratio * 100)::text || '%' end;
  return next;
end $$;
revoke execute on function club_incident_settle_quote(uuid, text) from public, anon;
grant execute on function club_incident_settle_quote(uuid, text) to authenticated;

comment on function club_incident_settle_quote is
  '0072 §A + [0116 §D ⓐ]: 인시던트 정산 견적 — 새 상수 없음. 부킹이 기록한 요금 구성 + 인계 스탬프 +
runs.actual_km + runners.commission_rate에서만 파생된다. **당사자 게이트 선행**: 부킹의 보호자·러너,
그 클럽 세션의 호스트·백업 호스트, 또는 이 부킹을 주체로 가진 케이스의 케이스오너·호스트만 답을
받는다. 없는 부킹과 남의 부킹은 같은 답(not_found) — 다르게 답하면 부킹 id 열거 오라클이 된다';

-- ---------- ⓑ runner_work_gate (HIGH) — 0092 §7 ---------------------------------------------
-- 0092's own comment claims the function is "party-safe by construction: it takes a runner id and
-- returns only that runner's own blocking booking". That is true about the ROWS and false about
-- the CALLER: any authenticated user could pass any runner's id and learn whether that runner is
-- currently holding a dog, which booking, when the run stopped, and which side has stamped. It is
-- a live liveness oracle over the whole supply side, and 128's own header (W5) had already
-- written down that this grant was the thing to watch.
-- The gate is the ruling's own sentence: "a runner may ask about THEIR OWN standing." Enforcement
-- still lives on the accept path (`transition-booking`), which calls this as a server role.
create or replace function runner_work_gate(p_runner uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare g record;
begin
  if p_runner is null then raise exception 'runner_required'; end if;
  -- [0116 §D ⓑ] PARTY GATE FIRST — a client may ask about themselves and nobody else.
  if auth.uid() is not null and auth.uid() <> p_runner then raise exception 'not_party'; end if;
  select * into g from _runner_work_gate_blocking(p_runner);
  if g.booking_id is null then
    return jsonb_build_object('gated', false);
  end if;
  return jsonb_build_object(
    'gated', true,
    'booking_id', g.booking_id,
    'status', g.status,
    'run_ended_at', g.run_ended_at,
    'runner_confirmed', g.runner_confirmed,
    'owner_confirmed', g.owner_confirmed,
    'waiting_on', g.waiting_on,
    -- The exit, named in the payload rather than left to each caller to reinvent — the same
    -- reason 0083 raises distinct exception names: a caller that has to compose the remedy
    -- itself will eventually compose a different one.
    'exit', case g.waiting_on
              when 'runner' then 'runner_confirm_return'
              when 'owner'  then 'owner_confirm_return'
              else 'both_confirm_return'
            end);
end $$;
revoke execute on function runner_work_gate(uuid) from public, anon;
grant  execute on function runner_work_gate(uuid) to authenticated, service_role;

comment on function runner_work_gate is
  '0092 ⑫ + [0116 §D ⓑ] — may this runner take new work? Sean 2026-08-13: "pay the runner but dont
let them make new runs until the dog is confirmed by both sides". DERIVED from 0083''s two return
stamps, never cached on `runners`. **당사자 게이트 선행**: a signed-in caller may ask only about
THEMSELVES (`not_party` otherwise) — 0092''s "party-safe by construction" was true of the rows and
false of the caller, which made it a liveness oracle over every runner. Server roles (no JWT) are
unaffected: enforcement lives on the accept path, not here and never in the client.';

-- ---------- ⓒ club_dog_ui_state — 0052 §6 (v5, the newest of six definitions) ----------------
-- The projection for ONE delegated dog: custody phase, payment/refund state, payout hold, whether
-- the booking is at picked_up, and whether an unresolved incident names that dog. It is granted
-- directly to `authenticated`, so a client can call it for any session_dog id, not only through
-- the board.
-- The gate is the board's OWN audience predicate, reused rather than reinvented:
-- `_club_shell_access(session, uid)` — host/backup host = 'host', a checked-in participant or a
-- committed runner or an approved delegating owner = 'full', an owner with a delegated dog in the
-- session = 'limited', everyone else = 'none'. `_club_delegation_board_impl` filters its dogs on
-- exactly this grading ('limited' sees only their own dog), so mirroring it here keeps every
-- legitimate board render identical while closing the direct call.
-- ⚠ The board calls this function from inside its own definer. `auth.uid()` reads a GUC and is
-- therefore PRESERVED across a definer boundary, so this gate applies to the board's inner calls
-- too — which is why it has to be the board's grading and not something stricter.
create or replace function club_dog_ui_state(p_session_dog uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare sd session_dogs; v_stage text; v_badges jsonb := '[]'; v_actors jsonb := '[]';
        v_sev text := 'info'; v_block jsonb := '[]'; v_access text;
begin
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then return null; end if;
  -- [0116 §D ⓒ] PARTY GATE BEFORE ANY PROJECTION. Same grading the board uses; 'none' is refused
  -- and 'limited' may see only their own dog. A missing row already returned NULL above, so an
  -- unrelated caller gets the same shape for "no such dog" and "not your session".
  if auth.uid() is not null then
    v_access := _club_shell_access(sd.session_id, auth.uid());
    if v_access = 'none'
       or (v_access = 'limited' and sd.owner_profile_id is distinct from auth.uid()) then
      return null;
    end if;
  end if;
  if sd.custody = 'owner_handled' then
    v_stage := '보호자 동반';
  else
    -- 커스터디 우선 단계 (반환·이양·외부 보호는 서비스 축이 뭐라 하든 화면의 1번 사실)
    if sd.custodian_type in ('clinic','authority') then
      v_stage := '외부 보호 중';
      v_badges := v_badges || to_jsonb(coalesce(sd.custodian_external, '외부 기관'));
      v_sev := 'critical'; v_actors := '["host","ops"]'; v_block := '["케이스 확인"]';
    elsif sd.custody_phase = 'transfer_pending' then
      v_stage := '이양 수락 대기'; v_sev := 'warn';
      v_actors := '["runner"]'; v_block := '["이양 수락"]';
    elsif sd.custody_phase = 'return_pending' then
      v_stage := '반환 대기'; v_sev := 'warn';
      v_actors := case
        when sd.owner_confirmed_return_at is null and sd.runner_confirmed_return_at is null
          then '["owner","runner"]'
        when sd.owner_confirmed_return_at is null then '["owner"]'
        else '["runner"]' end;
      v_block := '["반환 확인"]';
    else
      v_stage := case
        when sd.service_state = 'requested' then '신청 대기'
        when sd.service_state = 'approved' and sd.hold_status = 'active' then '승인 — 결제 대기'
        when sd.service_state = 'approved' then '승인 — 결제 필요'
        when sd.service_state = 'confirmed' and sd.assignment_state in ('unassigned','declined','replacement_needed') then '결제 완료 — 배정 대기'
        when sd.service_state = 'confirmed' and sd.assignment_state = 'proposed' then '러너 수락 대기'
        when sd.service_state = 'confirmed' then '담당 확정 — 인계 대기'
        when sd.service_state = 'in_service' and (select status from bookings where id = sd.booking_id)::text = 'picked_up'
          then '러너가 보호 중'
        when sd.service_state = 'in_service' then '러닝 중'
        when sd.service_state = 'ended' and sd.completion_outcome in ('completed','partial')
          and sd.custody_phase = 'resolved' then '완료'
        when sd.service_state = 'ended' then '종료'
        else '확인 중' end;
      if sd.service_state = 'approved' and sd.charge_state <> 'paid' then
        v_actors := '["owner"]'; v_block := '["결제"]';
      elsif sd.assignment_state = 'proposed' then v_actors := '["runner"]'; v_block := '["러너 수락"]';
      elsif sd.service_state = 'confirmed' and sd.assignment_state = 'accepted' then
        v_actors := '["owner","runner"]'; v_block := '["인계 확인"]';
      end if;
    end if;
    if sd.refund_state = 'pending' then v_badges := v_badges || '"환불 처리 중"'::jsonb; end if;
    if sd.refund_state = 'failed' then v_badges := v_badges || '"환불 실패"'::jsonb; v_sev := 'critical'; end if;
    if sd.hold_status = 'expired' then v_badges := v_badges || '"결제 기한 만료"'::jsonb; end if;
    if sd.payout_hold = 'held' then v_badges := v_badges || '"정산 보류"'::jsonb; end if;
    if sd.assignment_state = 'replacement_needed' then v_badges := v_badges || '"자리 재확인 중"'::jsonb; v_sev := 'warn'; end if;
    if sd.review_needed then v_badges := v_badges || '"재검토 필요"'::jsonb; v_sev := 'warn'; end if;
    -- [0052 §6] 조기 반환(부분 완료)은 '완료'와 같은 낱말로 덮이면 안 된다 — 배지로만 정직하게
    if sd.service_state = 'ended' and sd.completion_outcome = 'partial' then
      v_badges := v_badges || '"조기 반환"'::jsonb;
    end if;
    -- [rev2 P2] 세션 필터 — 타 세션 미해소 인시던트가 오늘 보드에서 크리티컬 배지(+openIncidentId
    -- 세션 한정과 비대칭: null id 죽은 딥링크)·교차 세션 존재 누수를 일으켰다. session_id로 좁힌다.
    if exists (select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
               where s.subject_type = 'dog' and s.subject_id = sd.dog_id and i.state <> 'resolved'
                 and i.session_id = sd.session_id) then
      v_badges := v_badges || '"인시던트 확인 중"'::jsonb; v_sev := 'critical';
    end if;
  end if;
  return jsonb_build_object(
    'primaryStage', v_stage, 'secondaryBadges', v_badges,
    'blockingIssues', v_block, 'primaryIssue', v_block->0,
    'requiredActors', v_actors, 'severity', v_sev,
    'allowedActions', '[]'::jsonb
  );
end $$;

grant execute on function club_dog_ui_state(uuid) to authenticated;

comment on function club_dog_ui_state is
  'UI 프로젝션 v5 (0052) + [0116 §D ⓒ] — ended·partial이면 secondaryBadges에 조기 반환
(낱말=primaryStage는 불변). **당사자 게이트 선행**: 보드와 같은 등급(_club_shell_access)으로,
none은 거절되고 limited는 자기 개만 본다. 없는 행과 남의 세션은 똑같이 NULL — 다르게 답하면
session_dog id 열거 오라클이 된다';

-- ---------- ⓓ club_host_stats — 0031 ---------------------------------------------------------
-- ⚠ MEASURED, AND THE HONEST ANSWER IS SMALLER THAN THE FINDING SUGGESTS. This one is a definer
-- over `club_sessions` (policy "sessions public read" = `using (true)`) and `session_people`
-- (policy "people authed read" = `using (auth.uid() is not null)`). Every number it returns is an
-- aggregate any signed-in user can already compute with three ordinary queries, so restricting it
-- to club MEMBERS would not close a leak — it would break the club storefront's host-trust card
-- for exactly the prospective member it exists to convince (`app/app/club/[id].tsx:112`), which is
-- a product decision and not this slice's to make.
-- What IS missing is the caller term its own inputs have: `session_people` refuses a caller with
-- no session, and a definer bypasses that. So the gate is that term, restored — and the honest
-- claim in the report is "definer hygiene", not "closed an exposure".
create or replace function club_host_stats(p_club uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- [0116 §D ⓓ] the caller term `session_people`'s own policy carries and the definer bypassed.
  -- ⚠ NOT `current_user in ('authenticated','anon')` — the idiom `_guard_booking_cols` uses. That
  -- works in a plain trigger function; inside a SECURITY DEFINER `current_user` is the function
  -- OWNER, so the arm would never fire and this would be a dead gate wearing a gate's clothes.
  -- `auth.uid()` reads the request GUC and is the only thing here that sees the caller.
  -- This one function has no server caller (its only site is the client storefront card), so it
  -- can require a session outright instead of taking §D's shared null-uid exemption.
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  return jsonb_build_object(
    'sessions', (select count(*) from club_sessions s where s.club_id = p_club and s.status = 'done'),
    'totalTeams', (select count(*) from club_sessions s join session_people sp on sp.session_id = s.id
                   where s.club_id = p_club and s.status = 'done' and sp.attendance = 'checked_in'),
    'returning', (select count(*) from (
        select sp.profile_id from club_sessions s join session_people sp on sp.session_id = s.id
        where s.club_id = p_club and s.status = 'done' and sp.attendance = 'checked_in'
        group by sp.profile_id having count(*) >= 2) t)
  );
end $$;
revoke execute on function club_host_stats(uuid) from public, anon;
grant execute on function club_host_stats(uuid) to authenticated, service_role;

comment on function club_host_stats is
  '0031 + [0116 §D ⓓ]: 호스트 신뢰 카드 (검증된 로컬 신뢰 — 팔로워 수가 아니라). 세션 수·누적 팀
수·재방문 수. ⚠ 일부러 클럽 **회원 전용이 아니다**: 이것은 가입을 설득하는 스토어프론트 카드이고,
세 숫자 모두 club_sessions(public read) + session_people(authed read)에서 로그인한 누구나 이미
계산할 수 있다. 게이트는 session_people 정책이 이미 요구하는 항 — 세션 없는 호출자 거절 — 하나이며,
definer가 우회하던 것을 되돌린 것이다 (노출 차단이 아니라 definer 위생)';
