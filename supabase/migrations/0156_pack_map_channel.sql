-- ═══ 0156 — 팩 지도: `pack-<sessionId>`, 읽기는 공개, 쓰기는 체크인한 참가자 ════════════════
--
-- Sean, 2026-08-28, verbatim (`docs/decisions/2026-08-28-sean-rulings.md`):
--   「everyone should see everyone else on the map during a club run session with a little runner
--    icon. total public; everything that's not their password is public to anyone.」
-- and, round two, when asked whether to ship before or after counsel answers:
--   「Build it now anyway」 · 「forget about all legal concerns please.」
-- and, on the scope of 「total public」:
--   「You read it right — phones stay host-only」 — so 「public」 was scoped to the MAP. This file
--   discloses NO phone number and touches nothing in the phone family.
--
-- ⚠ The privacy question was put to him in plain language and he overruled it. It is not re-opened
--   here, not gated on counsel, and not shipped behind an 「off until legal approves」 flag. The
--   only thing this file argues about is the WINDOW, which is an engineering question he did not
--   answer and which §1 answers with a measurement rather than an opinion.
--
-- ═══ §0 WHAT EXISTED BEFORE THIS FILE, MEASURED ════════════════════════════════════════════
-- There is no map of the group anywhere in the product. `run2-<bookingId>` (0103/0104) carries ONE
-- runner's position to ONE owner while that ONE booking is live. A 동반 owner walking their own dog
-- publishes nothing (`club/companion/[sid].tsx` imports `startTracking` and has no publisher), a
-- dogless guest has no booking to be the subject of one, and the HOST sees nobody at all.
-- So this is not a wire that was missing from a built feature; the feature did not exist.
--
-- The plumbing, however, is close. `0108` already owns every `realtime.messages` policy in the
-- database, already has a family switch (`channel_allowed`), already has the uid-fixed indirection
-- (`my_channel_allowed`) that stops the predicate being an arbitrary-uid party probe, and already
-- proved at the boundary that `anon` gets 0 rows on every family (143 E1-E3). This file adds ONE
-- family to that switch and TWO policies. It does not build a channel layer.
--
-- ═══ §1 THE LIVE WINDOW — the one thing Sean did not rule, and why it is this shape ═════════
--
-- 🔴 **A CLUB SESSION HAS NO RUNNING STATE.** Measured at source, not assumed: `club_sessions.status`
--    is `check (status in ('open','full','done','cancelled'))` — `0030_hi_club.sql:62` — and no
--    later migration alters that constraint (grepped every `alter table club_sessions`: 0047:14,
--    0048:76, 0050:241, none of them touch `status`). A booking's channel closes itself because
--    `run_channel_allowed` reads `bookings.status in ('runner_enroute','picked_up','active')`
--    (`0104:46`). **A session has no equivalent.** `status = 'open'` is true from the moment the
--    session row is created, which is at least an hour before it happens (`0030:184`) and in
--    practice days. A `pack-` channel keyed on `status in ('open','full')` alone is a PUBLIC
--    location feed that opens when somebody schedules a walk. That is the exact failure
--    CLAUDE.md §Migrations names — the one that arrives when nobody does anything — and it is
--    why this file does not ship that predicate.
--
-- **The window is four conjuncts, and three of them are facts that have ALREADY OCCURRED.**
--
--   ① `status in ('open','full')` — the host's 세션 종료 (`club_finish_session`, `0030:270`, sets
--      `done`) and a cancellation both close the map. An affirmative end signal, host-controlled.
--
--   ② **Somebody has actually checked in** — `exists (session_people.checked_in_at is not null)`.
--      This is the conjunct that makes the difference between 「a walk is happening」 and 「a walk is
--      scheduled」, and it is a fact that has already occurred rather than a clock. Nothing opens
--      at session-creation time, which is the property §1's first paragraph demands.
--      ⚠ It is the same conjunct `0146` chose for the same reason (`0146:141`, argued at `:110-123`),
--      and the same one `docs/decisions/guest-gps-options.md` §c reached independently. Copied,
--      not reinvented.
--
--   ③ **The host's 러닝 종료 closes it** — `not exists (a delegated pairing of this session whose
--      booking carries `run_ended_at`)`. ⚠ This works because of a uniqueness that `0144` states
--      and that was re-verified at source here: `bookings.run_ended_at` has exactly TWO writers in
--      the whole repo (`grep -n 'run_ended_at\s*='` → `0083:441`, `0144:456`), and `end_run_tx`
--      **raises `club_out_of_scope` on any booking with a `club_session_id`** (`0083:383`, read).
--      So on a CLUB booking, `run_ended_at is not null` means 「the host tapped 러닝 종료」 and
--      nothing else. It is the end signal the brief said already exists, and it is exact.
--
--   ④ **A clock backstop, and it is not a fourth opinion — it is `session_checkin`'s own band.**
--      `now() between scheduled_at - interval '2 hours' and scheduled_at + interval '6 hours'`,
--      copied verbatim from `0030:251-253`, which is where this product already decided what
--      「at the meetup」 means. ⚠ **This conjunct exists ONLY to answer inaction**, and it must:
--      ① is a host tap that may never happen, ③ is a host tap that may never happen, and ② is
--      monotonic (nothing ever un-checks-in). Without ④, one forgotten 세션 종료 leaves a PUBLIC
--      live-location channel open forever. With it, the outer bound on that mistake is
--      `scheduled_at + 6h`. ⚠ Reusing the check-in band rather than inventing a number is the
--      point: ② cannot become true outside it anyway (`session_checkin` raises `checkin_window`),
--      so the lower bound is implied by ② and the upper bound is the only load-bearing half.
--
-- ⚠ **NAMED CONSEQUENCE, because it is a real narrowing and a client will meet it.** A session
--    where NOBODY taps 체크인 never opens a map, however many people are walking. That is
--    deliberate — check-in is the only affirmative 「I am here」 this product has — but it means the
--    map's availability now depends on a screen the client must actually offer. Stated here so it
--    is a known property rather than a bug report.
--
-- ⚠ **AND ONE THE OTHER WAY.** Conjunct ③ closes the map for the WHOLE session the instant the
--    first delegated pairing is ended by the host's tap, including for 동반 owners and dogless
--    guests who may still be walking. That is the narrow direction and it is chosen deliberately
--    for a public channel: 러닝 종료 is one host tap over the whole pack (`0144 §B` — one call, N
--    pairings, one clock `v_at`), so 「some pairings ended」 and 「the pack run ended」 are the same
--    event. A session with NO delegated pairing at all (every dog owner-handled, or a
--    people-only walk) is unaffected by ③ and closes on ① or ④.
--
-- ═══ §2 THE CONTRACT THIS FILE IMPLEMENTS ══════════════════════════════════════════════════
--   topic    `pack-<sessionId>`, a realtime BROADCAST topic, one per club session
--   payload  `{ profileId, name, lat, lng, at }` — the client's business; the server never sees a
--            broadcast payload (realtime does not route it through postgres). ⚠ Consequence worth
--            naming: **every field of that payload is client-asserted, `profileId` included.** The
--            channel authorizes WHO MAY PUBLISH AT ALL; it cannot authorize what they claim to be.
--            `club_pack_map_roster` (§C) is the authoritative name/role list a client must render
--            from — a broadcast whose `profileId` is not in the roster is a forgery and the client
--            drops it. This is the same property `run2-` has and the same remedy.
--   read     EVERYONE, `anon` included. Sean's ruling, implemented literally.
--   write    a CHECKED-IN participant of that session, while the window is open. Nobody else.
--
-- ⚠ **WHY WRITE IS CHECKED-IN AND NOT MERELY 「a member」.** Session membership is SELF-SERVE:
--    `session_rsvp` gates on session open / seats left / your own dog and on nothing else
--    (`0134:53-61`), `club_sessions` is `select using (true)` (`0030:133`). 「A member of this
--    session」 means 「anyone who found an open session and tapped 참가」 — which in code reads
--    exactly like a membership check. Check-in is the only conjunct that requires the publisher to
--    have physically shown up, and it is what stops a stranger injecting a fake dot into a live
--    map from anywhere in the world. Read is public by ruling; WRITE is not, and it is the half
--    where the mutations in suite 187 have something to catch.
--
-- ═══ §3 WHAT THIS FILE DELIBERATELY DOES NOT DO ════════════════════════════════════════════
-- - **No phone.** Not a column, not a join, not a grant. Sean's round-two answer scoped 「public」
--   to the map and left `phone-host-scope = wide` standing. `_club_phone_visible` is untouched.
-- - **No avatar, no dog name, no money, no booking id, no incident id** in the public roster. The
--   ruling is 「a little runner icon」; the narrowest thing that draws one is a name and a role.
--   Widening it is a product decision with its own review, not a convenience taken here.
-- - **No feature flag.** In particular `_club_require_v2()` is NOT called: `club_flags
--   .club_delegation_v2` is `enabled: false` on production, so gating the map on it would ship a
--   capability that is dead on arrival for everyone outside `club_test_accounts`, which is the
--   「dead button」 the honesty law forbids. The map is not part of the v2 delegation surface.
-- - **No write to any existing table, no new column, no cron.**
-- - **No change to `run2-`, `chat-`, `bk-` or `club-chat-`.** §A reorders two guards inside
--   `channel_allowed` that BOTH return false; §4 states why that is behaviour-preserving for all
--   four existing families and pins it.

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  the window predicate — ONE home for the rule (0108's own discipline)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Server-only. It is not granted to any client role: a client learns the window from
-- `club_pack_map_roster.windowOpen` (§C), which is the same answer with a name on it.
create or replace function public._club_pack_window(p_session uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from club_sessions s
    where s.id = p_session
      -- ① 세션 종료 / 취소가 닫는다 (club_finish_session → 'done', 0030:270)
      and s.status in ('open', 'full')
      -- ④ 체크인 창과 글자 그대로 같은 밴드 (0030:251-253) — 무행동에 대한 유일한 방어
      and now() >= s.scheduled_at - interval '2 hours'
      and now() <= s.scheduled_at + interval '6 hours'
      -- ② 실제로 시작됐다 — 이미 일어난 사실이지 시계가 아니다
      and exists (select 1 from session_people sp
                   where sp.session_id = s.id and sp.checked_in_at is not null)
      -- ③ 호스트의 러닝 종료가 닫는다. 클럽 부킹의 run_ended_at 은 club_end_pack_runs 만 쓴다
      --    (end_run_tx 는 club_session_id 가 있으면 club_out_of_scope, 0083:383)
      and not exists (select 1 from session_dogs sd
                      join bookings b on b.id = sd.booking_id
                       where sd.session_id = s.id
                         and sd.custody = 'runner_delegated'
                         and b.run_ended_at is not null)
  );
$$;

comment on function public._club_pack_window(uuid) is
  '0156 §A — 팩 지도 채널이 열려 있는가. ① 세션이 open/full ② 누군가 실제로 체크인했다 ③ 호스트가 아직 러닝 종료를 누르지 않았다 ④ 체크인 창(예정 -2h ~ +6h) 안이다. ④는 오직 무행동(아무도 세션 종료를 안 누름)에 대한 상한이고, 나머지 셋은 이미 일어난 사실이다. 서버 전용 — 클라이언트는 club_pack_map_roster.windowOpen 으로 같은 답을 받는다.';

revoke execute on function public._club_pack_window(uuid) from public, anon, authenticated;
grant  execute on function public._club_pack_window(uuid) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  the family switch — one new arm in 0108's `channel_allowed`
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **THE ONE STRUCTURAL CHANGE, AND WHY IT IS BEHAVIOUR-PRESERVING FOR THE FOUR OLD FAMILIES.**
-- 0108's body opened with `if p_uid is null or p_topic is null or p_op is null then return false`.
-- The `pack` READ arm is the first arm in this function that has NO uid to consult — it is public
-- by ruling — so it has to be answered before that guard. The guard is therefore SPLIT: the
-- topic/op halves stay exactly where they were, and the **uid half moves down**, to sit
-- immediately above the first arm that reads an identity.
--
-- For `run2-` / `chat-` / `bk-` / `club-chat-` this changes nothing that is observable:
--   · a NULL uid still returns false, one guard later, having touched no table (the regex and the
--     uuid cast are pure);
--   · a NULL topic, a NULL op, an unknown op and a malformed topic still return false, from the
--     identical statements, in the identical order;
--   · the two guards that swapped order BOTH return false, so no input can distinguish them.
-- Suite 143 C2/B2/K2 assert `channel_allowed(<family topic>, null, 'read') is not false` for all
-- three 0108 families and stay green; 187 `0156-N1` re-asserts the same thing for run2 and pins
-- the split explicitly, so 「the uid guard was deleted rather than moved」 is caught.
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
  -- Fail closed on every shape of bad input, before touching a table. (0108, verbatim, minus the
  -- uid half — see §B's header.)
  if p_topic is null or p_op is null then return false; end if;
  if p_op not in ('read', 'write') then return false; end if;

  -- One anchored regex names every family this function answers for. `club-chat` is listed
  -- before nothing that could swallow it: `^chat-` cannot match `club-chat-…` because of the
  -- anchor, and `run-` (0104's retired public namespace) is deliberately absent → false.
  -- `pack` (0156) cannot be confused with any of them for the same anchoring reason.
  v_m := regexp_match(p_topic,
           '^(run2|chat|bk|club-chat|pack)-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$');
  if v_m is null then return false; end if;
  v_family := v_m[1];
  begin
    v_id := v_m[2]::uuid;
  exception when others then
    return false;                       -- a cast that raises must deny, never propagate
  end;

  -- ═══ pack-<session> READ IS PUBLIC — Sean 2026-08-28. The ONLY arm in this function that does
  -- not consult p_uid, so it is answered ABOVE the identity guard. `anon` reaches here with
  -- auth.uid() = NULL through my_channel_allowed and is admitted iff the walk is actually
  -- happening (§A). Nothing else about a session is disclosed by this answer.
  if v_family = 'pack' and p_op = 'read' then
    return coalesce(_club_pack_window(v_id), false);
  end if;

  -- Every remaining arm reads an identity. No identity ⇒ deny, before any table is touched.
  if p_uid is null then return false; end if;

  -- run2-* is 0103/0104's rule, delegated verbatim (owner receives, assigned runner publishes,
  -- live statuses only). Not re-derived here.
  if v_family = 'run2' then
    return coalesce(run_channel_allowed(p_topic, p_uid, p_op), false);
  end if;

  -- ═══ pack-<session> WRITE: a CHECKED-IN participant, while the window is open (§2). Membership
  -- alone is not enough — `session_rsvp` has no approval gate (0134:53-61), so 「member」 means
  -- 「whoever tapped 참가」. Check-in is the only conjunct that requires having shown up.
  if v_family = 'pack' then                                   -- p_op = 'write' by elimination
    select coalesce(_club_pack_window(v_id), false)
           and exists (select 1 from session_people sp
                        where sp.session_id = v_id
                          and sp.profile_id = p_uid
                          and sp.attendance = 'checked_in')
      into v_ok;
    return coalesce(v_ok, false);
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
  '0156 (was 0108): may this uid read/write the realtime topic? Family switch: run2-* → run_channel_allowed (0103/0104); chat-<thread>/bk-<booking>/club-chat-<session> → read iff the table''s own party predicate, write never (postgres_changes rooms); pack-<session> → READ IS PUBLIC (anon included, Sean 2026-08-28) while _club_pack_window says the walk is happening, WRITE iff a checked-in participant of that session inside the same window. Fails closed on malformed topics and unknown families. Revoked from authenticated (arbitrary-uid = party probe); policies call my_channel_allowed.';

-- ⚠ WRITTEN OUT EVERY TIME. `create or replace` preserves an ACL only where the function already
-- exists; on an apply where it does not (a partial prior apply, a branch that never ran 0108, a
-- rebuilt environment) this statement is a plain CREATE and a SECURITY DEFINER is born
-- PUBLIC-executable (`0116:636`). The arbitrary-uid form is a party probe and must never be open.
revoke execute on function channel_allowed(text, uuid, text) from public, anon, authenticated;
grant  execute on function channel_allowed(text, uuid, text) to service_role;

-- The uid-fixed wrapper the policies call (0049 pattern). Definer so it may call channel_allowed.
-- 🔴 **GRANTED TO `anon` BY THIS FILE, and that is a real widening that needs stating.** Under
-- 0108 `anon` could not execute it at all, because every family needed an identity and an
-- anonymous caller has none — the grant would have bought nothing. `pack` read is public, so the
-- anon path has to reach the predicate. What an anonymous caller can now learn from it is exactly
-- one boolean per session id: 「is this session's map live right now」 — and for every other family
-- it still returns false, because `auth.uid()` is NULL and §B's identity guard denies.
-- 187 `0156-W3` pins both halves (anon gets true on a live pack, false on all four old families).
create or replace function my_channel_allowed(p_topic text, p_op text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$ select public.channel_allowed(p_topic, auth.uid(), p_op) $$;

comment on function my_channel_allowed(text, text) is
  '0156 (was 0108): channel_allowed(topic, auth.uid(), op) — the only form a client role may execute, so a caller can ask about nobody but themselves. Granted to anon as of 0156 because pack-<session> READ is public and an anonymous subscriber has to reach the predicate; for every other family an anon caller has a NULL uid and is denied.';

revoke execute on function my_channel_allowed(text, text) from public;
grant  execute on function my_channel_allowed(text, text) to anon, authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  club_pack_map_roster — who is on the map, publicly
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- The channel carries dots; this carries the names and the role that decides which icon a dot
-- gets. It is the AUTHORITATIVE half: a broadcast payload is client-asserted (§2), so a client
-- that renders a name out of a payload is rendering whatever the publisher typed. Render from
-- here, key by `profileId`, and drop a broadcast whose id is not in this list.
--
-- ⚠ **`people` IS EMPTY WHILE THE WINDOW IS CLOSED, deliberately.** Names are disclosed while the
--   walk is happening and not before or after it. `windowOpen` is returned either way so a client
--   can say 「아직 시작 전이에요」 honestly instead of rendering an empty map that looks broken.
--   This is also what gives suite 187 a mutation with something to catch on the READ side, which
--   a purely-public function would not have.
--
-- ⚠ **THE ROW SET IS CHECKED-IN PARTICIPANTS ONLY** — exactly the set §B admits to WRITE. A person
--   who RSVP'd and did not come is not on the map and is not named by this function. That keeps
--   「who is disclosed」 and 「who may publish」 the same sentence, so they cannot drift apart.
--
-- ⚠ **NOT RETURNED, and each omission is a decision:** phone (Sean's round-two answer keeps it
--   host-only), avatar, dog name/collar, booking id, custody, money, incident id, and anyone's
--   location — the positions live on the channel and never transit postgres.
create or replace function public.club_pack_map_roster(p_session uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  s      record;
  v_open boolean;
  v_ppl  jsonb;
begin
  -- ⚠ No `auth.uid() is null` gate. That is the ruling, stated as an absence so a later session
  --   does not add one back as 「hardening」. `club_sessions` is already `select using (true)`
  --   (0030:133), so this function's EXISTENCE answer discloses nothing the table did not.
  select cs.id, cs.host_profile_id, cs.backup_host_profile_id, cs.scheduled_at,
         cs.status, cs.meetup_point
    into s
  from club_sessions cs where cs.id = p_session;
  if s.id is null then raise exception 'not_found'; end if;

  v_open := coalesce(_club_pack_window(p_session), false);

  if v_open then
    select jsonb_agg(x.j order by x.is_host desc, x.nm)
      into v_ppl
    from (
      select
        (p.id = s.host_profile_id or p.id = s.backup_host_profile_id) as is_host,
        p.name as nm,
        jsonb_build_object(
          'profileId', p.id,
          'name',      p.name,
          -- the raw four-value role from session_people (0030:71), not a re-derivation
          'role',      sp.role,
          'isHost',    (p.id = s.host_profile_id or p.id = s.backup_host_profile_id),
          -- 🔴 the icon bit. A person draws a RUNNER icon if they are working: their
          --    session_people role is one of the three runner roles, OR they are actually
          --    responsible for at least one delegated dog in this session. The disjunction is
          --    deliberate — `session_dogs.responsible_profile_id` moves on handover (0038:84)
          --    and is the fact on the ground, while the role is what they signed up as.
          'isRunner',  (sp.role in ('host_runner','handling_runner','runner_attending')
                        or exists (select 1 from session_dogs sd
                                    where sd.session_id = p_session
                                      and sd.custody = 'runner_delegated'
                                      and sd.responsible_profile_id = p.id))
        ) as j
      from session_people sp
      join profiles p on p.id = sp.profile_id
      where sp.session_id = p_session
        and sp.checked_in_at is not null
        and sp.attendance = 'checked_in'
    ) x;
  end if;

  return jsonb_build_object(
    'sessionId',   s.id,
    'status',      s.status,
    'scheduledAt', s.scheduled_at,
    'meetupPoint', s.meetup_point,        -- already anon-readable on club_sessions (0030:133)
    'windowOpen',  v_open,
    'topic',       'pack-' || s.id::text, -- one place owns the namespace string, as geo.ts does
    'people',      coalesce(v_ppl, '[]'::jsonb));
end $$;

comment on function public.club_pack_map_roster(uuid) is
  '0156 §C — 팩 지도의 사람 목록. Sean 2026-08-28 「everyone should see everyone else on the map … total public」. 공개(anon 포함). 창이 닫혀 있으면 people=[] 이고 windowOpen=false 만 답한다. 반환하지 않는 것: 전화·아바타·개 이름·부킹·돈·인시던트·위치(위치는 realtime 채널에만 있고 postgres 를 지나지 않는다). 브로드캐스트 페이로드의 name/profileId 는 클라이언트 주장이므로, 화면은 이 목록을 진실로 삼고 여기에 없는 profileId 의 브로드캐스트는 버려야 한다.';

revoke execute on function public.club_pack_map_roster(uuid) from public;
grant  execute on function public.club_pack_map_roster(uuid) to anon, authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  the wiring — two new policies on realtime.messages
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Five policies after this file:
--   · `party channel read` (SELECT/authenticated)      — 0108's, UNTOUCHED
--   · `run channel read`   (SELECT/authenticated)      — 0108's, UNTOUCHED
--   · `run channel write`  (INSERT/authenticated)      — 0108's, UNTOUCHED
--   · `pack channel read`  (SELECT/anon+authenticated) — NEW
--   · `pack channel write` (INSERT/authenticated)      — NEW
--
-- ⚠ **`pack channel read` IS NOT REDUNDANT WITH `party channel read`, and the difference is the
--   entire feature.** `party channel read` has no topic guard, so an AUTHENTICATED user reaches a
--   `pack-` topic through it too, with the identical answer. What it cannot do is admit `anon` —
--   it is `to authenticated`. So dropping `pack channel read` leaves every logged-in user working
--   and silently kills the public half of Sean's ruling. 187 `0156-E2` is an anon boundary
--   execution for exactly that reason: the authenticated arm alone cannot see this policy at all.
--
-- ⚠ **`run channel write` cannot admit a pack publish** — it is fenced to `run2-%` (0108 §5) — so
--   `pack channel write` is the only INSERT door for this family, and dropping it is visible.
do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice '0156: realtime.messages absent — policies skipped (harness without the shim)';
    return;
  end if;

  drop policy if exists "pack channel read"  on realtime.messages;
  drop policy if exists "pack channel write" on realtime.messages;

  -- READ: everyone, anon included. `realtime.messages.extension = 'broadcast'` matches 0103/0108's
  -- shape — realtime admits a private join on broadcast-read OR presence-read, and opening the
  -- presence probe as well would widen a room nobody tracks presence in.
  execute $p$
    create policy "pack channel read" on realtime.messages
      for select to anon, authenticated
      using (realtime.messages.extension = 'broadcast'
             and realtime.topic() like 'pack-%'
             and public.my_channel_allowed(realtime.topic(), 'read'))
  $p$;

  -- WRITE: authenticated only, and then only a checked-in participant inside the window (§B).
  -- `anon` is deliberately absent from the role list: a publisher must be a person the session
  -- knows, and an anonymous caller has no identity for `session_people` to match.
  execute $p$
    create policy "pack channel write" on realtime.messages
      for insert to authenticated
      with check (realtime.messages.extension = 'broadcast'
                  and realtime.topic() like 'pack-%'
                  and public.my_channel_allowed(realtime.topic(), 'write'))
  $p$;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  VERIFY — the properties that are true at APPLY time, asserted at apply time
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ CLAUDE.md's law: a property checked at apply and never pinned is protected exactly until
--   someone recreates the function — so every assertion here ALSO has an owner in suite 187
--   (`0156-W1`/`0156-W2`), and neither is evidence for the other. This block exists so a bad
--   apply aborts rather than shipping a half-wired public channel.
do $$
declare v_n int; v_bad text := '';
begin
  -- the three definers this file creates or replaces must be definer + in-body search_path
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('_club_pack_window','club_pack_map_roster','channel_allowed','my_channel_allowed')
     and p.prosecdef
     and coalesce(array_to_string(p.proconfig, ','), '') like '%pg_temp%';
  if v_n <> 4 then v_bad := v_bad || ' definer+search_path 4개가 아니다=' || v_n; end if;

  -- the arbitrary-uid probe stays shut to both client roles (0108 §3 F1, re-asserted after a
  -- create-or-replace that would have preserved nothing on a fresh apply)
  if has_function_privilege('anon','channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' anon이 channel_allowed(임의 uid)를 실행할 수 있다'; end if;
  if has_function_privilege('authenticated','channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' authenticated가 channel_allowed(임의 uid)를 실행할 수 있다'; end if;
  -- the window predicate is server-only; a client asks club_pack_map_roster instead
  if has_function_privilege('anon','_club_pack_window(uuid)','execute')
    then v_bad := v_bad || ' anon이 _club_pack_window를 직접 실행할 수 있다'; end if;
  if has_function_privilege('authenticated','_club_pack_window(uuid)','execute')
    then v_bad := v_bad || ' authenticated가 _club_pack_window를 직접 실행할 수 있다'; end if;
  -- the two grants the feature depends on
  if not has_function_privilege('anon','my_channel_allowed(text,text)','execute')
    then v_bad := v_bad || ' anon이 my_channel_allowed를 실행 못 한다(공개 읽기가 죽는다)'; end if;
  if not has_function_privilege('anon','club_pack_map_roster(uuid)','execute')
    then v_bad := v_bad || ' anon이 club_pack_map_roster를 실행 못 한다(공개 로스터가 죽는다)'; end if;

  if to_regclass('realtime.messages') is not null then
    select count(*) into v_n from pg_policies
      where schemaname='realtime' and tablename='messages'
        and policyname='pack channel read' and cmd='SELECT'
        and 'anon' = any(roles) and 'authenticated' = any(roles);
    if v_n <> 1 then v_bad := v_bad || ' pack channel read(SELECT, anon+authenticated)가 없다=' || v_n; end if;
    select count(*) into v_n from pg_policies
      where schemaname='realtime' and tablename='messages'
        and policyname='pack channel write' and cmd='INSERT'
        and roles = '{authenticated}'::name[];
    if v_n <> 1 then v_bad := v_bad || ' pack channel write(INSERT, authenticated 전용)가 없다=' || v_n; end if;
    select count(*) into v_n from pg_policies where schemaname='realtime' and tablename='messages';
    if v_n <> 5 then v_bad := v_bad || ' realtime.messages 정책 수가 5가 아니다=' || v_n; end if;
  end if;

  if v_bad <> '' then
    raise exception '0156 VERIFY 실패:%', v_bad;
  end if;
end $$;
