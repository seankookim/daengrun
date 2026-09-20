-- ═══ 0189: an urgent BOOKING notification is not disableable · a tombstone gets no push ═══
--
-- Codex's adversarial review of 0187 (REJECT / 2, both HIGH, both real on reading). Fixed forward;
-- 0187 is NOT edited. **0187 must not be deployed without this file** — on its own it can silence
-- an SOS, which is strictly worse than the 준비 중 label it replaced.
--
-- ═══ §0 FINDING ①: THE CLIENT CANNOT WRITE `kind = 'safety'`, SO IT WRITES SOS AS `booking` ═══
--   0114's INSERT policy (`0114_party_membership_active.sql:273-281`, `noti party insert`) admits
--   ONLY `kind = 'booking'` from a booking party. Every client-side notification therefore arrives
--   as `booking`, urgent or not — and 0187's mapper files every non-chat `booking` row as the
--   disableable `booking` category. So `booking = false`, a setting a person turns on to stop
--   hearing about 응가 도장, ALSO silences the SOS button.
--
--   ⚠ I ENUMERATED EVERY CLIENT WRITER RATHER THAN TAKING THE REVIEWER'S THREE ON FAITH — the
--   standing law that a finding's SENTENCE is the property and the cited site is only one place it
--   is observable. `grep -n "from('notifications')" app/src app/app` gives exactly five INSERTs:
--     · `api.ts:2563`  addRunEvent        — 응가 완료 · 간식 타임 · 수분 보충 · 새 사진 도착
--     · `api.ts:2574`  notifyKmMilestone  — `${km}km 돌파`
--     · `api.ts:3548`  sendSOS            — **SOS**
--     · `api.ts:3741`  openBookingIncident— **사고 신고 접수** (`INCIDENT_NOTI_TITLE`)
--     · `api.ts:3811`  notifyRunStop      — **러닝 중단 요청** (`RUN_STOP_TITLE`)
--   The first two are genuinely disableable and stay that way; the reviewer's three are the whole
--   urgent set. Checked, not assumed.
--
--   THE FIX IS A TITLE FAMILY, decided ABOVE every disableable arm and therefore before the prefs
--   read. It is the same discriminator shape 0187 already uses for chat, for the same reason: the
--   kind column cannot carry the distinction and the deployed clients cannot be changed.
--   ⚠ **The writers' `kind` is deliberately NOT changed.** Binaries already on phones keep writing
--   `booking`, and 0114's policy would refuse anything else anyway; a server-side rule is the only
--   one that covers a client we cannot redeploy.
--   ⚠ The family is KIND-AGNOSTIC on purpose. A row titled `SOS` under any kind is always-on —
--   fail-open is the only acceptable direction for this class, and gating the family on
--   `kind = 'booking'` would make a future writer's choice of kind able to mute it.
--   ⚠ MATCHING IS EXACT EQUALITY, never a prefix or a substring. `notification-route.ts:45`'s own
--   comment records why: partial matching is what caused the 「도착」 routing incident. `0189-U2`
--   pins it with a trailing-space arm.
--   ⚠ DRIFT: the three strings live in `_noti_urgent_noti_titles()` here and in
--   `api.ts` (`SOS_TITLE` · `INCIDENT_NOTI_TITLE` · `RUN_STOP_TITLE`). A rename on the client that
--   did not reach this array would put the notification back in the disableable pile SILENTLY —
--   the push simply stops arriving, and nobody files a bug about a push they never saw. So
--   `app/test/notification-prefs.test.cjs` reads BOTH artifacts as text, comments stripped, and
--   asserts the three values agree in both directions. `sendSOS` wrote a bare `'SOS'` literal
--   before this slice; it now uses `SOS_TITLE`, so all three are named constants the pin can find.
--
-- ═══ §0b FINDING ②: A TOMBSTONE CAN RE-REGISTER A TOKEN AND KEEP RECEIVING PUSHES ═══
--   The chain, read end to end rather than assumed:
--     · `delete_my_account_tx` ④ deletes `push_tokens` and sets `profiles.deleted_at` (0115 §B/§D).
--     · If `auth.admin.deleteUser` then FAILS, the edge function throws `202 auth_delete_pending`
--       (`delete-account/handler.ts:168-182`) and — deliberately — leaves the row tombstoned and
--       the user SIGNED IN, because the JWT is what the retry needs. That is a real, reachable,
--       durable state; the handler says so in those words.
--     · On the next launch `registerPushToken()` upserts a fresh row (`push.ts:194-201`). The RLS
--       on `push_tokens` is ownership-only (`0024`), so it passes.
--     · A retry then hits the idempotent short-circuit at `0115:227-234`, which skips the whole SQL
--       half — so the newly re-registered token is never deleted. It survives every later retry.
--   0187 sent whenever a token existed. Result: an account that asked to be deleted keeps getting
--   notifications on a device, which is a disclosure rather than a nuisance.
--
--   THE FIX IS AT THE SEND BOUNDARY: the token lookup now joins `profiles` and requires
--   `deleted_at is null`, and it is taken **FIRST — ahead of the category decision** — so a
--   tombstone is refused for `safety` too.
--   🔴 WHY THAT ORDER IS SAFE, as a ladder rather than a verdict, because it is the one place this
--      slice can do harm:
--      · **READ** (0115 §D ②, twelve state-gate tokens): a deletion is REFUSED while a run is
--        live, a dog is in custody, a charge is unsettled or a club session is open. A tombstone
--        therefore cannot be a party to a run in flight at the moment it is created.
--      · **READ** (0115 §B comment, verbatim): a tombstone has 「no credential, no identity, no
--        login path」; the row survives only because bookings/reviews/custody evidence point at it.
--        There is no person behind it to rescue.
--      · **REASONED, and stated as such**: in the `auth_delete_pending` window the auth row still
--        exists, so that one person CAN still sign in. What an SOS would reach there is a redacted
--        account the user has already abandoned — and if the handset changed hands, a stranger.
--        Withholding the push is the safer half of that trade.
--      · **UNCHANGED AND LOAD-BEARING**: the `notifications` ROW is still written either way. The
--        record, the inbox, every ops query and every sweep see exactly what they saw before. This
--        slice withholds a device push; it destroys no evidence.
--      ⚠ RESIDUAL, named rather than hidden: nothing here stops a tombstoned-but-auth-pending
--        account from becoming a party to a NEW booking. That is 0115's surface, not this one, and
--        it is the only path by which a live counterparty's SOS could target a tombstone.
--
--   ⚠ AND A BELT THE REVIEWER OFFERED, TAKEN: `push_tokens` gains a BEFORE INSERT OR UPDATE guard
--   that refuses a tombstoned owner outright (`account_deleted`). The send-boundary conjunct is the
--   LOAD-BEARING half — it covers a token that predates this migration — and the guard is what
--   converts 「we filter it on the way out」 into 「it cannot be written」. Both are mutated
--   separately in the battery so neither can borrow the other's green. The guard deliberately
--   leaves DELETE and SELECT alone: a tombstone must still be able to remove its own token.
--
-- ⚠ `create or replace` of `notify_push()` and `_noti_push_category()` — FIRST DEFINED IN 0024 and
--   0187 respectively. ACLs restated in this file (the grant-preservation class).
-- ⚠ DEPLOY: `db push` only; no edge function changes. **0187 and 0189 must land together.**

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  the urgent title family — ONE array, and the client's copy is drift-pinned against it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Pure, no table access, so no definer and no search_path is needed.
create or replace function _noti_urgent_noti_titles() returns text[]
language sql immutable as $$
  -- api.ts:3548 sendSOS (SOS_TITLE) · api.ts:3741 openBookingIncident (INCIDENT_NOTI_TITLE) ·
  -- api.ts:3811 notifyRunStop (RUN_STOP_TITLE). Exact equality only — see §0's 「도착」 note.
  select array['SOS', '사고 신고 접수', '러닝 중단 요청']::text[]
$$;

revoke execute on function _noti_urgent_noti_titles() from public, anon, authenticated;

comment on function _noti_urgent_noti_titles is
  '0189 §A: the titles a CLIENT writes for an urgent event. 0114''s INSERT policy admits only
kind=''booking'' from a party, so these arrive as booking and would otherwise be disableable.
Mirrored by SOS_TITLE / INCIDENT_NOTI_TITLE / RUN_STOP_TITLE in app/src/lib/api.ts, drift-pinned
in both directions by app/test/notification-prefs.test.cjs.';

create or replace function _noti_push_category(p_kind noti_kind, p_title text) returns text
language sql immutable as $$
  select case
    -- SOS · S1/S2 incidents · 외부 커스터디 이양 · 반환 지연 · ops escalations — not disableable
    when p_kind in ('safety', 'system')                then 'safety'
    -- [0189 §A] the three CLIENT writers of an urgent event. They arrive as kind='booking' because
    -- 0114:273-281 admits nothing else from a party, so without this arm `booking = false` silences
    -- an SOS. Deliberately ABOVE every disableable arm and deliberately NOT gated on the kind.
    when p_title = any (_noti_urgent_noti_titles())    then 'safety'
    -- 0090:87 writes the chat nudge as kind='booking' with this exact title (0090:78 dedupes on it,
    -- notification-route.ts:48 routes on it). `0187-N6` drives the real trigger, so the
    -- three-way agreement is held behaviourally rather than by matching the literal.
    when p_kind = 'booking' and p_title = '새 메시지'  then 'chat'
    when p_kind = 'booking'                            then 'booking'
    when p_kind = 'community'                          then 'community'
    when p_kind = 'reward'                             then 'reward'
    -- `shop` today, and any kind a future slice adds before it adds a column here. FAIL LOUD:
    -- an uncategorised push is SENT, never silently dropped by a preference nobody set for it.
    else 'safety'
  end
$$;

revoke execute on function _noti_push_category(noti_kind, text) from public, anon, authenticated;

comment on function _noti_push_category is
  '0187 §C + 0189 §A: notifications row → push category. Returns safety for an unknown kind AND for
the client-written urgent titles, so nothing uncategorised is ever muted. Called only by
notify_push().';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  the send path — a live recipient first, then the category, then the preference
-- ═══════════════════════════════════════════════════════════════════════════════════════════
create or replace function notify_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text; v_cat text; v_allowed boolean;
begin
  -- ① [0189 §B] THE RECIPIENT MUST BE A LIVE ACCOUNT, AND THIS IS TAKEN FIRST — ahead of the
  -- category decision — so a tombstone is refused for `safety` as well. See §0b for the ladder
  -- that makes that order safe; the short version is that a tombstone has no identity to rescue
  -- and the `notifications` ROW is still written either way.
  select pt.token into v_token
    from push_tokens pt
    join profiles pr on pr.id = pt.profile_id
   where pt.profile_id = new.profile_id
     and pr.deleted_at is null;
  if v_token is null or v_token not like 'ExponentPushToken%' then
    return new;
  end if;

  -- ② the category. SAFETY IS DECIDED BEFORE THE PREFERENCE TABLE IS READ. Not tidiness: the
  -- `exception when others` arm below turns ANY error into a skipped push, so a read placed ahead
  -- of this decision would be a second way to silence SOS.
  v_cat := _noti_push_category(new.kind, new.title);

  -- ③ ONE RULE, stated as an exact boolean so no NULL can collapse it into silence: **only an
  -- explicit `false` suppresses a push.** `v_cat is not null` is written out rather than left to
  -- `<>`'s NULL behaviour; a `select into` that matches no row leaves v_allowed NULL, which is
  -- 「this person has never saved anything」 and therefore SENDS; and the `case` has no ELSE, so a
  -- category with no column also lands on NULL and also SENDS. Never silently mute.
  if v_cat is not null and v_cat <> 'safety' then
    select case v_cat
             when 'booking'   then p.booking
             when 'chat'      then p.chat
             when 'community' then p.community
             when 'reward'    then p.reward
           end
      into v_allowed
      from notification_prefs p
     where p.profile_id = new.profile_id;
    if v_allowed is false then
      return new;   -- the notifications row is already written; only the device push is skipped
    end if;
  end if;

  perform net.http_post(
    url := 'https://exp.host/--/api/v2/push/send',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object(
      'to', v_token,
      'title', new.title,
      'body', coalesce(new.body, ''),
      'sound', 'default',
      'data', jsonb_build_object('kind', new.kind, 'ref_id', new.ref_id)
    )
  );
  return new;
exception when others then
  return new;
end $$;

revoke execute on function notify_push() from public, anon, authenticated;

comment on function notify_push is
  '0024 notifications → Expo push bridge · 0187 per-category preferences · 0189 the urgent-title
family and the live-recipient conjunct. Order: a live (non-tombstoned) recipient, then the
category, then the preference. safety/system and the client-written urgent titles never read
notification_prefs. A refusal suppresses the DEVICE PUSH only — the notifications row and the
in-app inbox are untouched.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  the belt: a tombstone cannot WRITE a token at all
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A definer, because `profiles` carries its own RLS and a policy subquery would answer 「can I SEE
-- that row」 rather than 「is that account alive」 — two different questions, and the first one is
-- the wrong gate. `p_uid` is not a parameter: the trigger reads NEW, so this cannot be used as an
-- existence oracle for anybody else.
create or replace function _push_token_live_owner() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from profiles p where p.id = new.profile_id and p.deleted_at is not null) then
    raise exception 'account_deleted'
      using detail = '탈퇴한 계정에는 푸시 토큰을 등록할 수 없어요';
  end if;
  return new;
end $$;

revoke execute on function _push_token_live_owner() from public, anon, authenticated;

-- INSERT and UPDATE only. A tombstone must still be able to DELETE its own token and to read it —
-- taking those away would remove the one cleanup path a stranded account has.
drop trigger if exists push_tokens_live_owner on push_tokens;
create trigger push_tokens_live_owner before insert or update on push_tokens
  for each row execute function _push_token_live_owner();

comment on function _push_token_live_owner is
  '0189 §C: refuses a push_tokens INSERT/UPDATE whose owner is tombstoned (0115 §B). The belt; the
load-bearing half is the live-recipient conjunct in notify_push, which also covers a token written
before this migration. DELETE and SELECT are deliberately untouched.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — fail the APPLY, not a pin. Suite 220 `0189-S1` carries the same properties as a
-- STANDING pin, because a property checked only at apply is protected exactly until someone
-- recreates the function in a later migration.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare v_src text; v_bad text := ''; v_cat text;
begin
  -- ① the three urgent titles really do classify as safety, asked of the function itself
  foreach v_cat in array _noti_urgent_noti_titles() loop
    if _noti_push_category('booking'::noti_kind, v_cat) is distinct from 'safety' then
      v_bad := v_bad || ' URGENT-TITLE-DISABLEABLE(' || v_cat || ')';
    end if;
  end loop;
  -- …and the control, so this block cannot pass by classifying everything as safety
  if _noti_push_category('booking'::noti_kind, '응가 완료') is distinct from 'booking'
     or _noti_push_category('booking'::noti_kind, '새 메시지') is distinct from 'chat' then
    v_bad := v_bad || ' MAPPER-CLASSIFIES-EVERYTHING-SAFETY';
  end if;
  if array_length(_noti_urgent_noti_titles(), 1) is distinct from 3 then
    v_bad := v_bad || ' URGENT-TITLE-COUNT'; end if;

  -- ② the definers: prosecdef + the in-body search_path + no PUBLIC/anon execute
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('notify_push', '_push_token_live_owner')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) <> 2
  then v_bad := v_bad || ' DEFINER-OR-SEARCH-PATH'; end if;
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('notify_push', '_push_token_live_owner',
                                  '_noti_push_category', '_noti_urgent_noti_titles')
                and (has_function_privilege('public', p.oid, 'execute')
                  or has_function_privilege('anon',   p.oid, 'execute')))
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;

  -- ③ the send path's source, COMMENTS STRIPPED (a comment explaining a guard would otherwise
  --    satisfy a check for the guard — the standing law), with NO-SOURCE arms so an absent
  --    function fails LOUDLY rather than silently: position(x in NULL) is NULL and a bare IF on
  --    NULL never fires.
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
  else
    if position('deleted_at is null' in v_src) = 0
    then v_bad := v_bad || ' NO-LIVE-RECIPIENT-CONJUNCT'; end if;
    -- the conjunct must be taken BEFORE the category decision, or a tombstone gets safety pushes
    if not (position('deleted_at is null' in v_src) > 0
            and position('deleted_at is null' in v_src) < position('_noti_push_category' in v_src))
    then v_bad := v_bad || ' LIVE-RECIPIENT-NOT-BEFORE-THE-CATEGORY'; end if;
    -- 0187's own two properties, restated because this file recreates the function
    if v_src !~ 'v_cat\s*<>\s*''safety'''
    then v_bad := v_bad || ' NO-SAFETY-CONJUNCT'; end if;
    if not (position('''safety''' in v_src) > 0
            and position('''safety''' in v_src) < position('notification_prefs' in v_src))
    then v_bad := v_bad || ' SAFETY-NOT-BEFORE-THE-PREFS-READ'; end if;
  end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_noti_push_category';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(_noti_push_category)';
  else
    if position('_noti_urgent_noti_titles' in v_src) = 0
    then v_bad := v_bad || ' MAPPER-DOES-NOT-CONSULT-THE-URGENT-FAMILY'; end if;
    -- above every disableable arm: the family must be read before the chat/booking arms
    if not (position('_noti_urgent_noti_titles' in v_src) > 0
            and position('_noti_urgent_noti_titles' in v_src) < position('''chat''' in v_src))
    then v_bad := v_bad || ' URGENT-FAMILY-BELOW-A-DISABLEABLE-ARM'; end if;
  end if;

  -- ④ the belt's trigger — STATE, not shape (pg_get_triggerdef renders a disabled trigger
  --    identically; the standing law)
  if (select count(*) from pg_trigger
       where tgrelid = 'push_tokens'::regclass and tgname = 'push_tokens_live_owner'
         and not tgisinternal and tgenabled = 'O') <> 1
  then v_bad := v_bad || ' NO-LIVE-OWNER-TRIGGER'; end if;

  if v_bad <> '' then
    raise exception '❌ 0189 VERIFY:%', v_bad;
  end if;
end $verify$;
