-- 0108 — realtime.messages policies for the three postgres_changes channels the app already
-- opens: `chat-<thread_id>`, `bk-<booking_id>`, `club-chat-<session_id>`. Prerequisite for the
-- `private_only` flip. Also SUPERSEDES 0103's two policy definitions (same names, same rule,
-- routed through the uid-fixed wrapper) and closes the party/liveness oracle 0103 left open — §3.
--
-- ═══ §0 WHY ═════════════════════════════════════════════════════════════════════════════
-- 0103/0104 closed the live-location hole by making `run2-*` a PRIVATE, policy-bound channel.
-- The project's next move is to flip realtime `private_only=true` ("Allow public access" off),
-- so no client can open an unpoliced public channel at all. Under that flag every join must be
-- `private:true`, and a private join is admitted ONLY if a `realtime.messages` SELECT policy
-- returns the probe row for that topic (realtime inserts one `broadcast` and one `presence` row
-- for the topic and reads them back as the caller; broadcast-read OR presence-read admits the
-- join, both false rejects it — read from realtime's `authorization.ex` / `realtime_channel.ex`,
-- 2026-08-19). Today the only policies on `realtime.messages` are 0103's `run2-*` pair. So the
-- flip, alone, kills chat live updates (`api.ts:2434`), booking-status live updates
-- (`api.ts:2476`, radar/meetup/live for both parties) and club chat live updates
-- (`api.ts:3192`) for EVERY user. This migration is the server half; the client half is the same
-- three lines geo.ts already carries (`REALTIME_PRIVATE` + `supabase.realtime.setAuth()`) applied
-- to those three `channel()` calls. Migration first, client second, never the reverse (0103 §0).
--
-- ═══ §1 WHAT EACH CHANNEL IS, MEASURED IN THE CLIENT ═══════════════════════════════════
-- All three are `postgres_changes` subscriptions and NOTHING else — grepped `app/`:
-- `.send({type:'broadcast'})` and `.on('broadcast')` exist only in geo.ts on `RUN_TOPIC`; there
-- is no `.track()` (presence) anywhere. So:
--   · `chat-<thread_id>`      INSERT on chat_messages      filter thread_id=eq.<thread_id>
--   · `bk-<booking_id>`       UPDATE on bookings           filter id=eq.<booking_id>
--   · `club-chat-<session_id>` INSERT on club_chat_messages filter session_id=eq.<session_id>
-- The channel join is what these policies gate. The EVENTS on a postgres_changes channel are
-- still filtered per subscriber by the SOURCE table's RLS (0008: "RLS는 구독에도 그대로 적용됨"),
-- which is why the admission predicate for each family only has to answer "may this uid be in
-- the room at all" — and answers it with the same predicate the room's table already uses.
--
-- ═══ §2 THE RULE PER FAMILY — mirror the table, do not invent ═══════════════════════════
--   · `chat-<thread>`: `chat_threads` "threads party" = `is_booking_party(booking_id)` (0002:141),
--     no status gate. So the thread's owner and CURRENT runner may join in any booking status —
--     chat persists after cancel/complete, exactly as the table lets it. A former runner loses
--     the room the instant `bookings.runner_id` moves, because the predicate reads it live.
--   · `bk-<booking>`: `bookings` "bookings party read" = `owner_id = uid or runner_id = uid`
--     (0002:92), no status gate — the radar screen watches this channel while `runner_id` is
--     still null, so it must admit the owner alone during matching. Losing bidders never held
--     `runner_id` and are refused (they hold the UUID from the open pool; the UUID is not a key).
--   · `club-chat-<session>`: `club_chat_messages` "club chat read" (0052:250) is per-ROW —
--     group rows for host/full, host-channel rows for host or the recipient (which is how a
--     `limited` applicant reads their own thread). The per-session projection of that union is
--     `_club_shell_access(session, uid) <> 'none'`, and that is exactly the app's own gate
--     (`club/session/[sid].tsx:150` subscribes only when `access !== 'none'`). Which rows a
--     member then receives is still the table's per-row policy, delivered by realtime's RLS
--     filter — this predicate admits the room, not the row.
--     ⚠ Accepted delta (adversarial review F2, 2026-08-19): the table's host-channel arm admits
--     `recipient_profile_id = auth.uid()` with NO shell-access check, so a `no_show` attendee
--     (`_club_shell_access` = 'none') can still READ a host DM addressed to them on the table —
--     and this room predicate refuses them. The room set is therefore a strict SUBSET of the
--     table read set for exactly that case. Not a regression: the app never subscribes when
--     `access === 'none'` ([sid].tsx:150), so those users get no live updates today either.
--     Widening the room to "or is the recipient of a host DM in this session" is a product
--     call, not a mirror-fidelity fix; it is NOT done here.
--   · `run2-<booking>`: delegated verbatim to `run_channel_allowed` (0103/0104). Not re-derived,
--     so a change to the live set has one home.
--   · WRITE (broadcast publish / presence track) on the three new families: NOBODY. They are
--     postgres_changes rooms; a broadcast on them would be a client-forged "event". There is no
--     write policy for them — 0103's `run channel write` is the only INSERT policy on the table
--     and its predicate returns false for every non-`run2-` topic, so the deny is measured at the
--     boundary (suite 143 E-pins), not implied by absence. `channel_allowed(...,'write')` returns
--     false for them so the rule is stated once, in one place, and pinned.
--
-- ═══ §3 SHAPE — and one deliberate deviation from 0103 ═════════════════════════════════
-- Same factoring as 0103 §2: a pure `channel_allowed(topic, uid, op)` that the suite pins as
-- ordinary SQL, plus a thin policy. Family switch on a single anchored regex; malformed topic,
-- unknown family, null uid/op, unknown op → false before any table is touched.
-- ⚠ Deviation: 0103 grants `run_channel_allowed(text, uuid, text)` to `authenticated`. That
-- signature with an ARBITRARY uid is a party-probe — `select run_channel_allowed('run2-'||X, V,
-- 'read')` answers "is V the runner of live booking X" for any V a caller names. 0049 closed
-- exactly this class for club (`_club_shell_access` revoked; only the `auth.uid()`-fixed
-- `club_my_shell_access` is granted). This file follows 0049: `channel_allowed(text,uuid,text)`
-- is revoked from `authenticated`; the policy calls `my_channel_allowed(topic, op)`, which fixes
-- uid = auth.uid(). Nothing an RLS policy needs is lost — the policy runs as the caller and can
-- only ever ask about the caller.
-- ⚠ And 0103's own grant is the same oracle, so this file closes it too (adversarial review F1,
-- 2026-08-19): any logged-in user could call `run_channel_allowed('run2-'||X, V, 'read'|'write')`
-- and learn "is V the runner of X" / "is X live right now" — and losing bidders hold X from the
-- open pool. `app/src` has no caller (grepped). So `run channel read` / `run channel write` are
-- DROPPED AND RECREATED under the same names, calling `my_channel_allowed(realtime.topic(), op)`
-- — whose run2- arm is `run_channel_allowed` verbatim, so the boundary behaviour is unchanged
-- (139 L1–L9 pin the predicate and L7 the boundary; both still hold) — and then
-- `run_channel_allowed(text,uuid,text)` is REVOKED from `authenticated`. It stays callable by
-- `service_role`, by `postgres`, and by definer bodies (this file's), which is every legitimate
-- caller. 0103's file is not edited; 0108 is the definition of record for those two policies.

-- ---------- §4 the predicate ----------
create or replace function channel_allowed(p_topic text, p_uid uuid, p_op text)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_m      text[];
  v_family text;
  v_id     uuid;
  v_ok     boolean;
begin
  -- Fail closed on every shape of bad input, before touching a table.
  if p_uid is null or p_topic is null or p_op is null then return false; end if;
  if p_op not in ('read', 'write') then return false; end if;

  -- One anchored regex names every family this function answers for. `club-chat` is listed
  -- before nothing that could swallow it: `^chat-` cannot match `club-chat-…` because of the
  -- anchor, and `run-` (0104's retired public namespace) is deliberately absent → false.
  v_m := regexp_match(p_topic,
           '^(run2|chat|bk|club-chat)-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$');
  if v_m is null then return false; end if;
  v_family := v_m[1];
  begin
    v_id := v_m[2]::uuid;
  exception when others then
    return false;                       -- a cast that raises must deny, never propagate
  end;

  -- run2-* is 0103/0104's rule, delegated verbatim (owner receives, assigned runner publishes,
  -- live statuses only). Not re-derived here.
  if v_family = 'run2' then
    return coalesce(run_channel_allowed(p_topic, p_uid, p_op), false);
  end if;

  -- The three postgres_changes rooms: read is the table's own party predicate; write is nobody's.
  if p_op = 'write' then return false; end if;

  case v_family
    when 'chat' then
      -- chat_threads "threads party" = is_booking_party(booking_id), no status gate (0002:141).
      select (p_uid = b.owner_id or p_uid = b.runner_id) into v_ok
        from chat_threads t join bookings b on b.id = t.booking_id
       where t.id = v_id;
    when 'bk' then
      -- bookings "bookings party read" (0002:92), no status gate — the owner watches during matching.
      select (p_uid = b.owner_id or p_uid = b.runner_id) into v_ok
        from bookings b where b.id = v_id;
    when 'club-chat' then
      -- the per-session projection of club_chat_messages "club chat read" (0052:250): every grade
      -- but 'none' can read at least its own rows; the app subscribes on the same gate.
      v_ok := _club_shell_access(v_id, p_uid) <> 'none';
    else
      v_ok := false;
  end case;

  -- No row (unknown id) or a null comparison (runner_id still null and uid is not the owner) → deny.
  return coalesce(v_ok, false);
end $$;

comment on function channel_allowed(text, uuid, text) is
  '0108: may this uid read/write the realtime topic? Family switch: run2-* → run_channel_allowed (0103/0104); chat-<thread>/bk-<booking>/club-chat-<session> → read iff the table''s own party predicate, write never (postgres_changes rooms). Fails closed on malformed topics and unknown families. Revoked from authenticated (arbitrary-uid = party probe); policies call my_channel_allowed.';

revoke execute on function channel_allowed(text, uuid, text) from public, anon, authenticated;
grant  execute on function channel_allowed(text, uuid, text) to service_role;

-- The uid-fixed wrapper the policy calls (0049 pattern). Definer so it may call channel_allowed.
create or replace function my_channel_allowed(p_topic text, p_op text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$ select public.channel_allowed(p_topic, auth.uid(), p_op) $$;

comment on function my_channel_allowed(text, text) is
  '0108: channel_allowed(topic, auth.uid(), op) — the only form authenticated may execute, so a caller can ask about nobody but themselves.';

revoke execute on function my_channel_allowed(text, text) from public, anon;
grant  execute on function my_channel_allowed(text, text) to authenticated, service_role;

-- ---------- §5 the wiring ----------
-- Three policies after this file, all routed through `my_channel_allowed`:
--   · `party channel read`  (SELECT) — the three new families. NEW.
--   · `run channel read`    (SELECT) — 0103's, recreated under the same name via the wrapper.
--   · `run channel write`   (INSERT) — 0103's, recreated under the same name via the wrapper.
-- Policies are permissive-OR: run2-* SELECT is admitted by either SELECT policy (same answer —
-- the same delegate); the three new families are admitted ONLY by `party channel read` (the
-- 0103-named pair is guarded to `run2-%`); INSERT anywhere is admitted only by `run channel
-- write`, whose predicate is false for every non-run2 topic. `extension = 'broadcast'` matches 0103's shape and is sufficient: realtime admits the
-- join on broadcast-read OR presence-read, and granting the presence probe as well would only
-- widen a room nobody tracks presence in.
do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice '0108: realtime.messages absent — policies skipped (harness without the shim)';
    return;
  end if;

  drop policy if exists "party channel read" on realtime.messages;
  drop policy if exists "run channel read"   on realtime.messages;
  drop policy if exists "run channel write"  on realtime.messages;

  execute $p$
    create policy "party channel read" on realtime.messages
      for select to authenticated
      using (realtime.messages.extension = 'broadcast'
             and public.my_channel_allowed(realtime.topic(), 'read'))
  $p$;

  -- 0103 §3's pair, verbatim in effect, now through the uid-fixed wrapper (§3 F1). The
  -- `like 'run2-%'` guard is what 0103's predicate already implied (false for every other
  -- namespace); stating it in the policy keeps this pair the run family's door and `party channel
  -- read` the ONLY door for the three new families — so the two SELECT policies are not
  -- interchangeable, and dropping either is visible at the boundary (suite 143 M1).
  execute $p$
    create policy "run channel read" on realtime.messages
      for select to authenticated
      using (realtime.messages.extension = 'broadcast'
             and realtime.topic() like 'run2-%'
             and public.my_channel_allowed(realtime.topic(), 'read'))
  $p$;

  execute $p$
    create policy "run channel write" on realtime.messages
      for insert to authenticated
      with check (realtime.messages.extension = 'broadcast'
                  and realtime.topic() like 'run2-%'
                  and public.my_channel_allowed(realtime.topic(), 'write'))
  $p$;
end $$;

-- ---------- §6 close 0103's oracle (F1) ----------
-- Nothing an RLS policy needs is lost: both `run channel *` policies now reach this function only
-- through the definer wrapper. Direct callers left: service_role, postgres, definer bodies.
revoke execute on function run_channel_allowed(text, uuid, text) from public, anon, authenticated;
grant  execute on function run_channel_allowed(text, uuid, text) to service_role;
