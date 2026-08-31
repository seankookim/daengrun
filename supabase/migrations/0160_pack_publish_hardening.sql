-- ═══ 0160 — 팩 지도 발행을 RPC 로 옮긴다 (0159 codex REJECT/11 의 서버 절반) ═════════════════
--
-- Contract: `docs/contracts/pack-publish-hardening-contract.md`.
-- Verdict being answered: `docs/decisions/2026-08-28-codex-verdicts.md` §0159 (REJECT, 11 findings).
-- 0159 is on trunk and NOT deployed; production is at 0156. This file lands with 0161 and the
-- client half in one landing, and the three deploy together.
--
-- ═══ §0 WHAT THIS FILE CHANGES, AND WHICH FINDING EACH CHANGE CLOSES ═══════════════════════
--
-- 0159 shipped a broadcast channel whose WRITE door was a realtime POLICY. Two measured facts
-- make that door unfixable in place, and both were confirmed on production 2026-08-31:
--
--   (a) 🔴 **REALTIME AUTHORIZATION IS CACHED PER SOCKET** (codex #2). The policy is evaluated at
--       JOIN, not per broadcast. A participant who joins while checked-in keeps publishing after
--       세션 종료 / 러닝 종료 / a revoked check-in, until the socket is refreshed. No amount of
--       care in the predicate fixes this: the predicate is not consulted again.
--   (b) 🔴 **THE PAYLOAD WAS CLIENT-AUTHORED** (codex #4). 0159 §2 says so in its own header —
--       「every field of that payload is client-asserted, `profileId` included」 — and left the
--       remedy to the client (「the roster is the truth, drop a broadcast whose id is not in it」).
--       A checked-in attacker could publish ANOTHER member's `profileId` and `name` with a newer
--       timestamp, and every honest client would render it, because it IS in the roster.
--
-- The fix is structural rather than careful: **the client stops writing to the socket at all.**
-- `club_pack_publish` re-checks membership and the window on EVERY call (so (a) has no cache to
-- live in), authors the payload entirely server-side from `auth.uid()` (so (b) has no argument to
-- carry a lie — the signature is the proof), and INSERTS the broadcast row into
-- `realtime.messages` itself so a failure is an exception it can convert into an honest refusal.
--
--   §A   new RPC `club_pack_publish` — the only publisher
--   §B   `channel_allowed`: the pack WRITE arm is REMOVED (0159:233-241). Falls through to false.
--   §C   policy `pack channel write` is DROPPED. realtime.messages goes 5 policies → 4.
--   §D-1 `pack_map_roster_reads` — the viewer counter's table (Sean's ruling, see §D-1).
--   §D   `club_pack_map_roster` gains `clubName` (codex #10 — the masthead binds a server fact
--        instead of a URL parameter a deep link can spoof) and `serverNow` (the viewer's clock
--        offset), and becomes VOLATILE because it now counts its own reads.
--   §E   `club_pack_publish_marks` — the throttle's one row per publisher.
--   §F   VERIFY.
--
-- ⚠ **THE READ SIDE IS UNCHANGED AND ITS RESIDUAL IS A DESIGN CALL, NOT AN OVERSIGHT.** A
--   subscriber's read authorization is cached per socket too, so a socket that joined during the
--   window keeps RECEIVING after it closes. Reads are PUBLIC by Sean's ruling (2026-08-28,
--   「total public」), and post-window there is nothing to receive: every publisher is refused
--   per-publish, server-side, by this file. The write side — the side that matters — has no cache
--   anywhere in its path.
--
-- ⚠ **WHAT THIS FILE DELIBERATELY DOES NOT DO.** It does not touch `_club_pack_window` (0159 §A),
--   `pack channel read`, or the four older channel families. It adds no column to any existing
--   table, no cron, and no flag.
--
-- ═══ §0.1 FOUR THINGS A LATER READER WILL WANT AND WOULD OTHERWISE HAVE TO GUESS ═══════════
-- (autoplan addendum item 6, 2026-08-31.)
--
-- 🔴 **(a) `PrivateOnly` IS A SETTING, NOT AN INVARIANT — say the honest sentence.** Measured on
--     production 2026-08-31: a public-channel join is refused by the project
--     (`PrivateOnly: This project only allows private channels`), which is why the trunk client's
--     two public `supabase.channel(topic)` calls could never have joined. That is a PROJECT
--     CONFIG. One dashboard toggle and it is gone, with no code change and nothing that fails —
--     the same shape as 0151's 「protected by PostgREST's schema allowlist」 (a config, not a
--     privilege). So the impossibility of a client socket WRITE does not rest on it. It rests on
--     two belts this file installs: (i) `pack channel write` no longer exists, so an INSERT
--     matches NO policy (§C) and `channel_allowed` has no pack-write arm to consult (§B); and
--     (ii) the map keys peers on the SERVER ROSTER, so a payload whose `profileId` is not on the
--     roster is dropped by the screen even if it somehow reached the plane. PrivateOnly is a
--     third belt and is named here as a belt, never as the reason.
--
-- ⚠ **(b) ANON-COARSENING IS PRESERVED AS A SERVER-ONLY CHANGE, and this note is the reason it
--     stays cheap.** If Sean later wants an anonymous viewer to see initials and coarse positions
--     rather than full names and exact ones, every piece of that decision is inside two function
--     BODIES — `club_pack_map_roster` (names) and `club_pack_publish` (the payload it authors).
--     No client change, no new RPC, no schema change: the roster already answers per-caller
--     (`auth.uid()` is in scope) and the payload is already authored here. Do NOT re-architect to
--     get it, and do not let a later slice move name selection to the client 「for flexibility」 —
--     that would move this decision out of reach and hand identity back to the caller, which is
--     the exact defect (codex #4) this file exists to close.
--
-- ⚠ **(c) ALTERNATIVES CONSIDERED, and why each lost** (from the /autoplan eng review):
--     · **per-member topics** (`pack-<session>-<member>`, one channel per publisher, the write
--       policy keyed to the topic's own uid): identity becomes structural — but the WINDOW does
--       not, because a policy is still evaluated once per join and cached. It fixes codex #4 and
--       leaves codex #2 exactly where it was, at the cost of N channels per session.
--     · **client broadcast + roster filter on the receiver**: cheapest, and it cannot stop
--       INTRA-roster spoofing — any checked-in member can still publish another checked-in
--       member's `profileId`, and the receiver's roster filter admits it because that id IS on the
--       roster. It converts a total forgery into a forgery among participants, which is not the
--       property anyone wanted.
--     · **an edge function that publishes**: identical security properties to this RPC, plus a
--       network hop and a second deployment artifact to keep in step with the schema. Same
--       answer, worse latency, more places to be wrong.
--
-- ⚠ **(d) PILOT ARCHITECTURE — THE EXIT NOTE, so the price is a decision rather than a surprise.**
--     One RPC call per publisher per 3 s is roughly **50x more database work per position than a
--     socket publish** (a round trip, a transaction, four gate reads, an INSERT — against a
--     websocket frame the realtime server relays). At Banpo pilot scale (one session, single-digit
--     publishers) that is nothing, and it buys server-authored identity, which nothing cheaper
--     buys. It is NOT the shape to scale on. When it stops being free the exits, in order:
--     **batch** several positions per call (the client already ticks on a timer, so a 2-3 position
--     batch is a client change and an argument-shape change here, nothing structural); and take
--     **per-message authorization** the moment the realtime platform offers it — the whole reason
--     this RPC exists is that authorization is cached per JOIN, and a platform that re-checks per
--     MESSAGE lets the socket write come back with all of this file's properties intact.

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  the throttle's table — declared FIRST because §A's body writes it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- One row per publisher, holding the last SUCCESSFUL publish instant. Nothing else reads it and
-- nothing else may: RLS on with ZERO policies is the same seal `billing_keys` (0080:110) and
-- `billing_key_revocations` (0138:44) carry, and the explicit revoke below is the other half of
-- it — Supabase's default privileges hand `anon`/`authenticated` full DML on every new table in
-- `public` (measured, mirrored at `00_shim.sql:82-95`), so 「we granted nothing」 is not the same
-- sentence as 「they hold nothing」. Only the definer in §A touches this table.
create table if not exists club_pack_publish_marks (
  profile_id uuid primary key references profiles on delete cascade,
  last_at    timestamptz not null
);
alter table club_pack_publish_marks enable row level security;
revoke all on table club_pack_publish_marks from anon, authenticated;

comment on table club_pack_publish_marks is
  '0160 §E — club_pack_publish 의 발행 간격 제한(2초) 표시. 성공한 발행만 기록한다(거절은 남기지 않는다 — 남기면 거절이 다음 시도까지 막는다). RLS on + 정책 0개 + 클라이언트 권한 회수: 오직 club_pack_publish 만 읽고 쓴다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  club_pack_publish — the only publisher on a pack topic
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Flat, whitelisted return: `{ok: boolean, refusal: text|null}`. The refusal vocabulary is
-- CLOSED — `not_signed_in` · `not_checked_in` · `window_closed` · `bad_position` · `too_fast` ·
-- `not_delivered` — because the client maps each one to a sentence a person reads.
--
-- **Party gate before state gate** (house law): who you are is decided before what the session is
-- doing, so a stranger and a missing session get the identical answer and this function is never
-- an existence oracle over session ids.
--
-- ⚠ **THE MEMBERSHIP CONJUNCTION IS DELIBERATELY THE ROSTER'S OWN ROW-SET PREDICATE**
--   (`attendance = 'checked_in'` AND `checked_in_at is not null` — 0159:367-368). 0159 §C claims
--   「the row set is exactly the set §B admits to WRITE」, and that claim is FALSE in 0159 as
--   written: its window conjunct ② tests `checked_in_at is not null` while its write arm tests
--   `attendance = 'checked_in'`, and `session_no_show` (95:52) moves ATTENDANCE by UPDATE while
--   the STAMP stands — so the two halves diverge on a real, reachable row. Taking BOTH halves here
--   makes 0159 §C's sentence true by construction rather than by coincidence, and suite 191's
--   divergence-zone fixture is the only fixture that can see the difference (a fixture where both
--   halves agree cannot distinguish the two rules — CLAUDE.md's fixture-agreement law).
--
-- 🔴 **THE BROADCAST IS A DIRECT INSERT, NOT `realtime.send`, AND THAT IS THE WHOLE DELIVERY
--   DESIGN** (autoplan addendum item 1, superseding the contract's §A.7-8). `realtime.send` on
--   production ends with `EXCEPTION WHEN OTHERS THEN RAISE WARNING` and returns void (measured
--   2026-08-31): a send that fails leaves NO caller-visible signal at all, so calling it would
--   force this function to prove delivery by READING the table back — and that read is the
--   expensive, fragile half:
--     · it scans every daily partition of `realtime.messages` on an UNINDEXED json key
--       (`payload->>'id'`), once per publisher per 3 s. At ten publishers that is a recurring tax
--       on the shared PostgREST pool — i.e. the pack map degrading chat and bookings;
--     · it has to be a LATER statement, because `select realtime.send(...), (select count(*) …)`
--       returns **0** on production (measured 2026-08-31 — the count reads the statement-start
--       snapshot and structurally cannot see the insert its own statement is making). A
--       same-statement verify is green-blind by construction, which is a trap in the hot path;
--     · it needs SELECT on `realtime.messages`, which this function otherwise does not.
--   Inserting the row OURSELVES removes all three: an INSERT that fails RAISES, and an exception
--   is a better detector than any read-back — free, immediate, and it names the cause.
--   `postgres` holds BYPASSRLS and INSERT on `realtime.messages` (measured, contract foundation
--   3) and the realtime service tails COMMITTED rows regardless of who wrote them, so the row
--   broadcasts exactly as a `realtime.send` row would.
--
-- ⚠ **THE `WHEN OTHERS` BELOW IS NOT A SILENT CATCH, and the difference is the whole honesty
--   law.** A silent catch swallows a failure and renders a happy UI. This one (i) `RAISE
--   WARNING`s the SQLSTATE so the failure is in the server log, and (ii) converts it into the
--   TYPED refusal `not_delivered`, which the client maps to a sentence a person reads. The
--   failure it exists for is real and reachable: `realtime.messages` is PARTITIONED BY DAY and
--   the partition janitor wakes on socket connect, so a publish into a cold project can fail with
--   `MissingPartition` (measured: idle production had partitions ending 2026-08-29, and holding
--   one anon socket ~75 s took it to 2026-09-03). Without this handler that failure would
--   propagate as a 500 the client cannot distinguish from a network fault.
--
-- ⚠ **DELIVERY IS PROVEN BY A PROBE AT DEPLOY, NOT BY THIS FUNCTION.** A verify-read only ever
--   proved 「a row is in the table」, never 「a subscriber received it」 — the deploy protocol's
--   end-to-end publish→receive probe (an anon private-channel socket observing a fixture member's
--   publish) is what actually closes that question, and it is also the observation that direct
--   INSERT rows broadcast.
--
-- ⚠ **`p_age_ms` IS A PAST-ONLY CLAMP** (addendum item 1b). The client sends `Date.now() - fix.t`
--   so a fix that was 8 s old is stamped 8 s old instead of being presented as fresh. The clamp is
--   `least(greatest(p_age_ms, 0), 120000)` — a liar can only make themselves look STALER, never
--   newer, so the forged-future-stamp attack that server-side stamping killed stays dead. Without
--   it every fix up to the client's 120 s staleness bound renders at full freshness, and the
--   comment claiming otherwise becomes a comment-vs-code lie.
create or replace function club_pack_publish(
  p_session uuid,
  p_lat     double precision,
  p_lng     double precision,
  p_age_ms  integer default 0)
returns jsonb
language plpgsql volatile security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid     uuid;
  v_topic   text;
  v_msg_id  uuid;
  v_name    text;
  v_at      timestamptz;
  v_payload jsonb;
begin
  -- ① 당사자 게이트 ㉠ — 로그인
  v_uid := auth.uid();
  if v_uid is null then
    return jsonb_build_object('ok', false, 'refusal', 'not_signed_in');
  end if;

  -- ② 당사자 게이트 ㉡ — 이 세션에 실제로 체크인한 사람인가.
  --    없는 세션과 남의 세션이 같은 답을 받는다(존재 오라클이 되지 않는다).
  if not exists (select 1 from session_people sp
                  where sp.session_id = p_session
                    and sp.profile_id = v_uid
                    and sp.attendance = 'checked_in'
                    and sp.checked_in_at is not null) then
    return jsonb_build_object('ok', false, 'refusal', 'not_checked_in');
  end if;

  -- ③ 상태 게이트 — 창(0159 §A). 매 호출 재평가된다: 소켓 캐시가 낄 자리가 없다.
  if _club_pack_window(p_session) is not true then
    return jsonb_build_object('ok', false, 'refusal', 'window_closed');
  end if;

  -- ④ 좌표. 정확히 (0,0) 은 거절 — 기니 만(Null Island)은 이 서비스의 좌표가 아니라
  --    「위치를 못 읽었다」의 가장 흔한 표현이고, 지도에 아프리카 앞바다 점을 찍는다.
  if p_lat is null or p_lng is null
     or p_lat < -90  or p_lat > 90
     or p_lng < -180 or p_lng > 180
     or (p_lat = 0 and p_lng = 0) then
    return jsonb_build_object('ok', false, 'refusal', 'bad_position');
  end if;

  -- ⑤ 간격 제한 — 읽고 나서 쓰는 게 아니라 **조건부 upsert 한 문장**이다.
  -- 🔴 읽고-판단하고-쓰는 원래 모양은 이 제한이 존재하는 단 하나의 적대자에게 통째로 뚫린다:
  --    동시에 도착한 N 개의 요청은 전부 같은 커밋된 표시를 읽고 전부 통과한다. 조건부 upsert 는
  --    같은 profile_id 의 행 잠금을 한 문장 안에서 잡으므로, 둘째 요청은 첫째의 커밋을 보고
  --    where 절에서 걸린다(갱신 0행 → NOT FOUND → too_fast). 표시를 **보내기 전에** 잡는 것도
  --    같은 이유다 — 잠금을 늦게 잡을수록 창이 넓어진다.
  -- ⚠ 그래서 not_delivered 로 끝난 호출도 2초 한 칸을 쓴다. 다음 틱이 3초 뒤라 실질 손실이
  --   없고(클라이언트의 발행 주기가 3초다), 반대쪽 — 실패한 발행이 표시를 안 남겨서 무제한
  --   재시도가 되는 쪽 — 이 훨씬 나쁘다. 의도된 교환이다.
  -- ⚠ ①~④ 의 거절은 여전히 표시를 남기지 않는다. 위치를 한 번 못 읽은 클라이언트가 스스로를
  --   지도에서 밀어내면 안 되기 때문이고, 0160-A6 이 그 팔을 재고 있다.
  insert into club_pack_publish_marks as m (profile_id, last_at)
       values (v_uid, now())
  on conflict (profile_id) do update set last_at = excluded.last_at
        where m.last_at <= now() - interval '2 seconds';
  if not found then
    return jsonb_build_object('ok', false, 'refusal', 'too_fast');
  end if;

  -- ⑥ 페이로드는 여기서, 그리고 오직 여기서 만들어진다. profileId 는 auth.uid() 이고 name 은
  --    profiles 의 값이다 — 호출자가 줄 수 있는 인자에 신원이 없다(codex #4 의 구조적 종결).
  -- ⚠ at 은 「지금」이 아니라 「이 좌표를 읽은 때」다. p_age_ms 는 과거로만 움직이는 clamp 라
  --   거짓말은 자기를 더 낡아 보이게 만들 뿐이다(위 §A 헤더). NULL 은 greatest 가 0 으로
  --   흡수한다(Postgres 의 greatest/least 는 NULL 인자를 무시한다).
  v_msg_id := gen_random_uuid();
  select p.name into v_name from profiles p where p.id = v_uid;
  v_topic  := 'pack-' || p_session::text;
  v_at     := now() - make_interval(secs => least(greatest(p_age_ms, 0), 120000) / 1000.0);
  v_payload := jsonb_build_object(
    'id',        v_msg_id,
    'profileId', v_uid,
    'name',      coalesce(v_name, '참가자'),
    'lat',       p_lat,
    'lng',       p_lng,
    'at',        to_char(v_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));

  -- ⑦ 브로드캐스트 — realtime.send 를 거치지 않고 행을 직접 넣는다(위 §A 헤더의 이유).
  --    실패는 예외로 올라오고, 예외 핸들러가 그것을 **타입이 있는 거절**로 바꾼다.
  --    ⚠ 이 when others 는 조용한 catch 가 아니다: SQLSTATE 를 WARNING 으로 남기고(서버 로그에
  --      원인이 남는다) not_delivered 를 돌려준다(화면이 정직하게 말한다). 조용한 catch 는
  --      실패를 삼키고 행복한 UI 를 그리는 것이고, 이건 그 반대다.
  begin
    insert into realtime.messages (id, payload, event, topic, private, extension)
         values (v_msg_id, v_payload, 'pos', v_topic, true, 'broadcast');
  exception when others then
    raise warning '0160 club_pack_publish: realtime.messages INSERT 실패 topic=% sqlstate=% %',
      v_topic, sqlstate, sqlerrm;
    return jsonb_build_object('ok', false, 'refusal', 'not_delivered');
  end;

  return jsonb_build_object('ok', true, 'refusal', null);
end $fn$;

comment on function public.club_pack_publish(uuid, double precision, double precision, integer) is
  '0160 §A — 팩 지도의 유일한 발행 경로. 매 호출마다 당사자(체크인한 참가자 = 단어 AND 스탬프)와 창(_club_pack_window)을 다시 확인하고, 페이로드를 서버가 직접 만든다(profileId = auth.uid(), name = profiles.name) — 인자에 신원이 없으므로 남의 신원으로 발행할 방법이 구조적으로 없다(codex #4). 간격 제한(2초)은 조건부 upsert 한 문장이라 동시 요청에도 뚫리지 않는다. 브로드캐스트는 realtime.send(모든 오류를 삼킨다 — 운영 prosrc 측정 2026-08-31)가 아니라 realtime.messages 에 직접 INSERT 하고, 실패는 예외 → WARNING + not_delivered 라는 타입 있는 거절로 바뀐다. p_age_ms 는 과거로만 움직이는 clamp(0~120000ms)라 at 이 실제 측위 시각을 말하되 미래로는 위조할 수 없다. 반환은 평평한 화이트리스트 {ok, refusal}; refusal 어휘는 닫혀 있다: not_signed_in · not_checked_in · window_closed · bad_position · too_fast · not_delivered.';

-- ⚠ WRITTEN OUT, not inherited. On an apply where this function does not yet exist the statement
--   above is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable (0116:636).
revoke execute on function public.club_pack_publish(uuid, double precision, double precision, integer) from public, anon;
grant  execute on function public.club_pack_publish(uuid, double precision, double precision, integer) to authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  channel_allowed — the pack WRITE arm is REMOVED
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0159:233-241 admitted a checked-in participant to a socket WRITE. That arm is gone: with no
-- `pack` write branch, `v_family = 'pack'` and `p_op = 'write'` falls through to the
-- postgres_changes guard (`if p_op = 'write' then return false`) and denies. Publishing now goes
-- through `club_pack_publish` (§A), and a socket write has no policy to admit it either (§C) —
-- deny-by-no-policy, which is the shape that cannot be re-opened by a cached join.
--
-- Everything else in this body is 0159's, byte-for-byte: the split input guard (topic/op above
-- the regex, uid below it, so the public pack READ arm can be answered without an identity), the
-- anchored family regex, the run2 delegation, the three postgres_changes rooms.
create or replace function channel_allowed(p_topic text, p_uid uuid, p_op text)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_m      text[];
  v_family text;
  v_id     uuid;
  v_ok     boolean;
begin
  -- Fail closed on every shape of bad input, before touching a table. (0108, verbatim, minus the
  -- uid half — see 0159 §B's header.)
  if p_topic is null or p_op is null then return false; end if;
  if p_op not in ('read', 'write') then return false; end if;

  -- One anchored regex names every family this function answers for. `club-chat` is listed
  -- before nothing that could swallow it: `^chat-` cannot match `club-chat-…` because of the
  -- anchor, and `run-` (0104's retired public namespace) is deliberately absent → false.
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
  -- not consult p_uid, so it is answered ABOVE the identity guard. Unchanged by 0160.
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

  -- ═══ 0160: 0159's `pack` WRITE arm stood here and is REMOVED. Nobody writes a pack topic
  -- through a socket any more — `club_pack_publish` is the door, and it re-gates per call rather
  -- than once per join. `pack` + `write` now falls into the guard below and returns false.
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
end $fn$;

comment on function channel_allowed(text, uuid, text) is
  '0160 (was 0159, was 0108): may this uid read/write the realtime topic? Family switch: run2-* → run_channel_allowed (0103/0104); chat-<thread>/bk-<booking>/club-chat-<session> → read iff the table''s own party predicate, write never (postgres_changes rooms); pack-<session> → READ IS PUBLIC (anon included, Sean 2026-08-28) while _club_pack_window says the walk is happening, WRITE **NEVER** — 0160 removed 0159 의 pack 쓰기 팔이다. 팩 발행은 club_pack_publish RPC 하나뿐이고(호출마다 재검사), 소켓 쓰기는 이를 받아줄 정책이 아예 없다. Fails closed on malformed topics and unknown families. Revoked from authenticated (arbitrary-uid = party probe); policies call my_channel_allowed.';

-- ⚠ WRITTEN OUT EVERY TIME (0159's own note, and check-definer-acl's rule). `create or replace`
--   preserves an ACL only where the function already exists; where it does not, this is a plain
--   CREATE and a SECURITY DEFINER is born PUBLIC-executable (0116:636). The arbitrary-uid form is
--   a party probe and must never be open.
revoke execute on function channel_allowed(text, uuid, text) from public, anon, authenticated;
grant  execute on function channel_allowed(text, uuid, text) to service_role;

-- The uid-fixed wrapper the policies call. Recreated here only so this file states its own ACL on
-- every apply path — the BODY is 0159's, unchanged.
create or replace function my_channel_allowed(p_topic text, p_op text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $fn$ select public.channel_allowed(p_topic, auth.uid(), p_op) $fn$;

comment on function my_channel_allowed(text, text) is
  '0160 (was 0159, was 0108): channel_allowed(topic, auth.uid(), op) — the only form a client role may execute, so a caller can ask about nobody but themselves. Granted to anon because pack-<session> READ is public and an anonymous subscriber has to reach the predicate; for every other family an anon caller has a NULL uid and is denied, and pack WRITE is now false for everyone (0160 §B).';

revoke execute on function my_channel_allowed(text, text) from public;
grant  execute on function my_channel_allowed(text, text) to anon, authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  the write policy is dropped — deny by NO POLICY
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- `pack channel write` (0159 §D) was the only INSERT door for this family — `run channel write`
-- is fenced to `run2-%` (0108 §5) and `party channel read` is a SELECT policy. Dropping it means
-- an authenticated socket write to a pack topic matches NO policy and is refused by RLS, whatever
-- a cached join decided minutes ago. `pack channel read` is untouched: the ruling is public read.
-- realtime.messages goes 5 policies → 4 (143 W1 and 190 `0159-W1` both count it, both updated).
do $mig$
begin
  if to_regclass('realtime.messages') is null then
    raise notice '0160: realtime.messages absent — policy drop skipped (harness without the shim)';
    return;
  end if;
  drop policy if exists "pack channel write" on realtime.messages;
end $mig$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D-1  pack_map_roster_reads — 팩 지도를 몇 번이나 열어 봤는가
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 **RULED, not proposed: Sean 2026-08-31 (announcer console) 「Yes, add counter」.** The pilot
--    question the pack map exists to answer is 「does anyone open this」, and without a counter the
--    only available answer after the walk is a guess.
--
-- ⚠ **COUNT ONLY. NO PII, and the shape is the privacy decision.** One row per
--   (session, anon-or-authed, KST day) holding an integer. It cannot answer 「who looked」 or
--   「when, within the day」 — those are questions this table is deliberately unable to be asked,
--   which is a stronger guarantee than a policy saying nobody will ask them. The anon/authed
--   split is the one distinction the pilot actually needs (does a shared link bring in people
--   without accounts) and it is a two-value bucket, not an identity.
-- ⚠ The day is **KST**, not UTC: the product's day boundary is Seoul's, and a walk that starts at
--   21:00 KST must not be split across two rows by a UTC midnight that falls inside it.
-- ⚠ Sealed exactly like `club_pack_publish_marks` (§E) and for the same reason — Supabase's
--   default privileges hand `anon`/`authenticated` full DML on every new table in `public`
--   (measured, mirrored at `00_shim.sql:82-95`), so RLS-on-with-zero-policies is only half the
--   seal and the explicit revoke is the other half. Only the definer in §D writes it, and nothing
--   reads it but a human with a psql prompt.
create table if not exists pack_map_roster_reads (
  session_id uuid   not null,
  viewer     text   not null check (viewer in ('anon','authed')),
  day        date   not null,
  n          bigint not null default 0,
  primary key (session_id, viewer, day)
);
alter table pack_map_roster_reads enable row level security;
revoke all on table pack_map_roster_reads from anon, authenticated;

comment on table pack_map_roster_reads is
  '0160 §D-1 — 팩 지도 로스터 조회 수(Sean 2026-08-31 「Yes, add counter」). (세션, anon|authed, KST 날짜)당 정수 하나. PII 없음: 누가 봤는지도, 하루 중 언제 봤는지도 이 테이블로는 물을 수 없다. club_pack_map_roster 가 반환을 만들기 전에 n=n+1 한다(예외로 삼키지 않는다 — 카운터가 죽으면 시끄럽게 죽는다). RLS on + 정책 0개 + 클라이언트 권한 회수.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  club_pack_map_roster — `clubName` · `serverNow` · and it now counts its own reads
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- codex #10: the map masthead rendered a club name taken from a URL PARAMETER, unbound to the
-- session — a deep link could title someone else's walk with any string. The name is a server
-- fact; this returns it. Present whether or not the window is open, because the masthead has to
-- say something before the walk starts (`people` stays window-gated, 0159 §C's decision).
--
-- 🔴 **`serverNow` EXISTS BECAUSE EVERY PAYLOAD IS NOW ON ONE CLOCK** (addendum item 1c). Under
--    0159 each publisher stamped its own `at` with its own device clock, so a viewer's skew was
--    spread across senders. 0160 §A stamps every `at` with the SERVER's clock — which is strictly
--    more honest and makes the viewer's own skew the single point of failure: a phone 15 s slow
--    computes every marker as 15 s in the FUTURE, the freshness rule refuses it, and the map is
--    silently empty with nothing on screen saying why. That is the silent-feature-loss class, not
--    a cosmetic one. Returning the server's clock at each roster fetch lets the screen compute
--    `offset = serverNowMs - Date.now()` and evaluate freshness against the adjusted clock, so
--    the comparison is server-clock-to-server-clock at both ends. Same ISO-8601 UTC spelling as
--    the payload's `at`, for exactly that reason.
--
-- 🔴 **AND THIS FUNCTION IS NOW `volatile`, WHICH IS A REAL CHANGE, NOT A KEYWORD.** It writes
--    (§D-1's counter), so `stable` would be a lie to the planner and PostgREST would run it in a
--    READ-ONLY transaction and fail. Nothing in the repo pins this function's `provolatile`
--    (checked 2026-08-31 — the four `provolatile` pins in 133/157/158/161 name other functions),
--    and 0160 §F pins it here instead so a later 「it only reads, make it stable」 tidy-up fails
--    the apply rather than the deploy.
-- ⚠ The counter write is deliberately NOT wrapped in an exception handler. A counter that fails
--   silently reports zero forever and reads as 「nobody opened the map」 — the worst possible
--   failure for the one question it exists to answer. It fails loudly instead.
-- ⚠ It sits AFTER the `not_found` raise on purpose: counting before the existence check would let
--   anyone (anon included) create an unbounded number of rows by calling with random uuids. The
--   existence check is what bounds this table to real sessions.
--
-- ⚠ `left join`, not `join`: `club_sessions.club_id` is `not null` (0030:52) so the row always
--   exists today, but an inner join would make this function's `not_found` answer depend on a
--   second table's row. The refusal must keep meaning exactly 「no such session」 — and api.ts's
--   `fetchPackRoster` maps that answer by MESSAGE STRING (`/not_found/`), so the raise token is
--   part of the contract and must not be reworded.
create or replace function club_pack_map_roster(p_session uuid)
returns jsonb
language plpgsql volatile security definer
set search_path = public, pg_temp
as $fn$
declare
  s      record;
  v_open boolean;
  v_ppl  jsonb;
begin
  -- ⚠ No `auth.uid() is null` gate. That is the ruling, stated as an absence so a later session
  --   does not add one back as 「hardening」. `club_sessions` is already `select using (true)`
  --   (0030:133), so this function's EXISTENCE answer discloses nothing the table did not.
  select cs.id, cs.host_profile_id, cs.backup_host_profile_id, cs.scheduled_at,
         cs.status, cs.meetup_point, c.name as club_name
    into s
  from club_sessions cs
  left join clubs c on c.id = cs.club_id
  where cs.id = p_session;
  if s.id is null then raise exception 'not_found'; end if;

  -- 🔴 §D-1 의 카운터. 반환을 만들기 전에, 존재 확인 뒤에. n 은 첫 조회에서 1 이다(컬럼 기본값
  --    0 은 「아직 아무도 안 봤다」의 철자이지 첫 조회의 값이 아니다).
  insert into pack_map_roster_reads as r (session_id, viewer, day, n)
       values (p_session,
               case when auth.uid() is null then 'anon' else 'authed' end,
               (now() at time zone 'Asia/Seoul')::date,
               1)
  on conflict (session_id, viewer, day) do update set n = r.n + 1;

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
          --    responsible for at least one delegated dog in this session.
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
    'clubName',    s.club_name,           -- 0160 (codex #10): the masthead's own fact
    -- 0160: the viewer's clock offset reference. Same ISO-8601 UTC spelling as the payload's `at`
    -- so the screen subtracts two values of the same kind.
    'serverNow',   to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'people',      coalesce(v_ppl, '[]'::jsonb));
end $fn$;

comment on function public.club_pack_map_roster(uuid) is
  '0160 (was 0159 §C) — 팩 지도의 사람 목록. Sean 2026-08-28 「everyone should see everyone else on the map … total public」. 공개(anon 포함). 창이 닫혀 있으면 people=[] 이고 windowOpen=false 만 답한다. 0160 이 더한 것: clubName(clubs.name) — 지도 머리글이 URL 파라미터가 아니라 서버 사실에 묶이도록(codex #10), 창과 무관하게 항상; serverNow(ISO-8601 UTC) — 이제 모든 페이로드의 at 이 서버 시계라서 보는 쪽 시계가 어긋나면 지도 전체가 조용히 비므로, 화면이 offset = serverNow - Date.now() 로 보정하도록. 그리고 이 함수는 이제 VOLATILE 이다: 반환을 만들기 전에 pack_map_roster_reads 에 조회 수를 센다(§D-1, Sean 2026-08-31 「Yes, add counter」). 반환하지 않는 것: 전화·아바타·개 이름·부킹·돈·인시던트·위치. 브로드캐스트 페이로드는 이제 서버가 만들지만(0160 §A) 화면은 여전히 이 목록을 진실로 삼고 여기에 없는 profileId 는 버린다.';

revoke execute on function public.club_pack_map_roster(uuid) from public;
grant  execute on function public.club_pack_map_roster(uuid) to anon, authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §F  VERIFY — house form only. Every arm is `is distinct from`, never a bare `IF has_*`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ `has_function_privilege` can answer NULL, and plpgsql does not take an `IF` on a NULL
--   predicate — a bare `if has_*` is SILENT in exactly the case an ACL check exists for. Same
--   collapse for `has_table_privilege`.
-- ⚠ Source matches strip `--` comments first: `prosrc` is our code AND our prose, so an
--   un-stripped match is satisfied by a comment EXPLAINING the property (CLAUDE.md's
--   comment-matching law). Here the header above literally contains the word `clubName`.
-- ⚠ A property checked at apply and never pinned is protected exactly until someone recreates the
--   function — every assertion below also has an owner in suite 191, and neither is evidence for
--   the other.
do $mig$
declare v_n int; v_bad text := '';
begin
  -- the five definers this family depends on: definer + in-body search_path
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('_club_pack_window','club_pack_map_roster','channel_allowed',
                       'my_channel_allowed','club_pack_publish')
     and p.prosecdef
     and coalesce(array_to_string(p.proconfig, ','), '') like '%pg_temp%';
  if v_n <> 5 then v_bad := v_bad || ' definer+search_path 5개가 아니다=' || v_n; end if;

  -- the new RPC: open to authenticated, shut to anon and PUBLIC
  if has_function_privilege('authenticated','club_pack_publish(uuid,double precision,double precision,integer)','execute')
       is distinct from true
    then v_bad := v_bad || ' authenticated가 club_pack_publish를 실행 못 한다(발행이 죽는다)'; end if;
  if has_function_privilege('anon','club_pack_publish(uuid,double precision,double precision,integer)','execute')
       is distinct from false
    then v_bad := v_bad || ' anon이 club_pack_publish를 실행할 수 있다'; end if;
  if has_function_privilege('public','club_pack_publish(uuid,double precision,double precision,integer)','execute')
       is distinct from false
    then v_bad := v_bad || ' PUBLIC이 club_pack_publish를 실행할 수 있다'; end if;
  -- ⚠ 시그니처가 정확히 네 인자인가. p_age_ms 를 빼면 위 세 팔은 has_function_privilege 가
  --   NULL 을 답하고 `is distinct from` 이 그것을 잡아 주지만, 인자가 하나 더 **늘어나는** 쪽은
  --   못 잡는다 — 신원을 실어 나를 인자가 생기는 방향이 바로 codex #4 의 재발이다.
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_publish'
     and coalesce(array_to_string(p.proargnames, ','), '') = 'p_session,p_lat,p_lng,p_age_ms';
  if v_n <> 1 then v_bad := v_bad || ' club_pack_publish 인자가 (p_session,p_lat,p_lng,p_age_ms) 가 아니다=' || v_n; end if;

  -- the two sealed helpers stay sealed after this file's create-or-replace
  if has_function_privilege('anon','channel_allowed(text,uuid,text)','execute') is distinct from false
    then v_bad := v_bad || ' anon이 channel_allowed(임의 uid)를 실행할 수 있다'; end if;
  if has_function_privilege('authenticated','channel_allowed(text,uuid,text)','execute') is distinct from false
    then v_bad := v_bad || ' authenticated가 channel_allowed(임의 uid)를 실행할 수 있다'; end if;
  if has_function_privilege('anon','_club_pack_window(uuid)','execute') is distinct from false
    then v_bad := v_bad || ' anon이 _club_pack_window를 직접 실행할 수 있다'; end if;
  if has_function_privilege('authenticated','_club_pack_window(uuid)','execute') is distinct from false
    then v_bad := v_bad || ' authenticated가 _club_pack_window를 직접 실행할 수 있다'; end if;
  -- the two grants the public half of the ruling depends on
  if has_function_privilege('anon','my_channel_allowed(text,text)','execute') is distinct from true
    then v_bad := v_bad || ' anon이 my_channel_allowed를 실행 못 한다(공개 읽기가 죽는다)'; end if;
  if has_function_privilege('anon','club_pack_map_roster(uuid)','execute') is distinct from true
    then v_bad := v_bad || ' anon이 club_pack_map_roster를 실행 못 한다(공개 로스터가 죽는다)'; end if;

  -- the roster really returns the new keys (comments stripped — the header above says both words)
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_map_roster'
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') like '%clubName%';
  if v_n <> 1 then v_bad := v_bad || ' club_pack_map_roster 본문에 clubName이 없다=' || v_n; end if;
  select count(*) into v_n from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_map_roster'
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') like '%serverNow%';
  if v_n <> 1 then v_bad := v_bad || ' club_pack_map_roster 본문에 serverNow가 없다=' || v_n; end if;
  -- and it must stay VOLATILE — it writes the counter, and `stable` would make PostgREST run it
  -- in a read-only transaction (a deploy-time failure for a keyword a later tidy-up would change)
  if (select p.provolatile::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'club_pack_map_roster') is distinct from 'v'
    then v_bad := v_bad || ' club_pack_map_roster 가 volatile 이 아니다(카운터를 쓰는데 stable 이면 읽기 전용 트랜잭션에서 죽는다)'; end if;

  -- the marks table is sealed: RLS on, zero policies, no client privilege
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'club_pack_publish_marks') is distinct from true
    then v_bad := v_bad || ' club_pack_publish_marks에 RLS가 없다'; end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'club_pack_publish_marks';
  if v_n <> 0 then v_bad := v_bad || ' club_pack_publish_marks에 정책이 있다=' || v_n; end if;
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.club_pack_publish_marks', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' club_pack_publish_marks에 클라이언트 권한이 남아 있다=' || v_n; end if;

  -- the counter table carries the identical seal, and the identical two halves
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'pack_map_roster_reads') is distinct from true
    then v_bad := v_bad || ' pack_map_roster_reads에 RLS가 없다'; end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'public' and tablename = 'pack_map_roster_reads';
  if v_n <> 0 then v_bad := v_bad || ' pack_map_roster_reads에 정책이 있다=' || v_n; end if;
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.pack_map_roster_reads', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' pack_map_roster_reads에 클라이언트 권한이 남아 있다=' || v_n; end if;

  if to_regclass('realtime.messages') is not null then
    select count(*) into v_n from pg_policies
      where schemaname='realtime' and tablename='messages' and policyname='pack channel write';
    if v_n <> 0 then v_bad := v_bad || ' pack channel write가 아직 있다=' || v_n; end if;
    select count(*) into v_n from pg_policies
      where schemaname='realtime' and tablename='messages'
        and policyname='pack channel read' and cmd='SELECT'
        and 'anon' = any(roles) and 'authenticated' = any(roles);
    if v_n <> 1 then v_bad := v_bad || ' pack channel read(SELECT, anon+authenticated)가 없다=' || v_n; end if;
    select count(*) into v_n from pg_policies where schemaname='realtime' and tablename='messages';
    if v_n <> 4 then v_bad := v_bad || ' realtime.messages 정책 수가 4가 아니다=' || v_n; end if;
  end if;

  if v_bad <> '' then
    raise exception '0160 VERIFY 실패:%', v_bad;
  end if;
end $mig$;
