-- ═══ 0187: per-category push preferences — the PUSH is gated, the RECORD never is ═══
--
-- `settings.tsx` carried 「알림 설정 · 푸시 도입 후」 under 준비 중. Push has shipped since 0024
-- (`push_tokens` + the `notifications_push` AFTER INSERT trigger → Expo), so the label was stale in
-- the direction that matters: the product sends pushes and offered no way to turn any of them off.
-- This slice builds the surface and, more importantly, makes it MEAN something on the send path.
--
-- ═══ §0 THE CATEGORIES ARE DERIVED FROM THE WRITERS, NOT INVENTED ═══
--   `noti_kind` (0001:23) is `('booking','community','shop','safety','reward','system')`. Every
--   `insert into notifications` in the repo was enumerated (positional extraction of the `kind`
--   value, 2026-09-21):
--     booking    118 sites — requests · accept/decline · 인계 asks · run start/end · money ·
--                            cancels …, AND the chat nudge (0090:87 writes kind='booking')
--     community   52 sites — club feed · session · delegation · S3 incidents
--     safety      12 sites — SOS · S1/S2 incidents · 외부 커스터디 이양 · 반환 지연 경보
--     system       6 sites — ops escalations (0155 · 0166 · 0118 · 0182/0183 인계 확인 멈춤)
--     reward       3 sites — 0034's dog-record milestones (최고 페이스 · 누적 km · n번째 완주)
--     shop         0 sites — the enum value nothing writes
--   So the user-disableable set is **booking · chat · community · reward**, and `safety` is the
--   always-on category, which is `kind in ('safety','system')` — ops escalations belong with SOS.
--   ⚠ **`marketing` IS DELIBERATELY ABSENT.** The brief offered it; there is NO writer anywhere in
--   this repo that sends a campaign notification, and a toggle for a push nobody sends is a dead
--   control wearing a switch's costume (the no-dead-buttons law). It arrives with its first writer.
--   ⚠ `shop` likewise gets no column — but it is NOT silently muted, see §C's fallback.
--
-- ═══ §0b CHAT IS A CATEGORY THAT `kind` CANNOT SEE ═══
--   0090's nudge writes `kind = 'booking'` with `title = '새 메시지'`, so chat is separable only by
--   the title. That is not a new fragility invented here: 0090's OWN dedupe predicate (0090:78)
--   already keys on that exact literal, and the client's `CHAT_TITLE` (notification-route.ts:48) is
--   the third copy. §C puts the mapping in ONE named function instead of a fourth inline copy, and
--   `0187-N6` pins it **behaviourally** — it drives a real `chat_messages` INSERT through 0090's
--   trigger and asserts the row it produces maps to 'chat'. A title change on EITHER side reddens
--   it; a source pin matching the literal could not tell a changed title from a changed comment.
--
-- ═══ §A `notification_prefs` ═══
--   One row per profile, four booleans, all default true (opt-out, never opt-in — a person who has
--   never opened this screen must keep getting everything). RLS: own row only, read and write.
--   ⚠ **THE ROW SURVIVES AN ACCOUNT TOMBSTONE, and that is stated rather than hidden.**
--   `delete_my_account_tx` (0115 §D) TOMBSTONES `profiles` instead of deleting it, so the
--   `on delete cascade` below never fires for a deletion; 0115's ④ list is where a row would have
--   to be added. It is not added here: that would mean a `create or replace` of 0115's central
--   definer inside a preferences slice, and the residual is four booleans holding no personal data,
--   gating a push that cannot be sent anyway because ④ DOES delete `push_tokens` (0115:520). The
--   obligation rides the next slice that opens ④ — `comment on table` below names it so that slice
--   finds it.
--   ⚠ Not in 150 N6's retention set and not `%access_log`, so the CASCADE edge is invisible to that
--   watchdog by construction — checked, not assumed (the list is 23 names, verbatim at 0115:809).
--
-- ═══ §B `get_notification_prefs()` · `set_notification_prefs(…)` ═══
--   Flat whitelisted returns, definer with the in-body `search_path`, ACL restated (revoke
--   public/anon, grant authenticated). `auth.uid()` is the ONLY caller identity — there is no uid
--   argument, so there is nothing to spoof — and a NULL uid raises `not_signed_in`.
--   ⚠ **NO `safety` COLUMN IS RETURNED.** The always-on row the client draws is a client constant
--   with a reason line; returning a hard-coded `safety := true` from the server would be a
--   fabricated field (the honesty law: bind a real field or omit the element).
--   ⚠ A NULL argument to the setter means 「leave this one alone」, which is what lets the client
--   send one switch's worth of change. On a first-ever save an absent argument takes the column
--   DEFAULT, which is the same value — so the two readings never disagree.
--
-- ═══ §C ENFORCEMENT — where a `notifications` row becomes a device push ═══
--   It is a DB trigger, not an edge function: `notifications_push` AFTER INSERT → `notify_push()`
--   → `net.http_post` to Expo (0024). No edge function reads `push_tokens` at all (measured: the
--   only readers in `supabase/` are 0024, 0063, 0115 and the suites). So the gate belongs in SQL
--   and its pin belongs in the harness — `net._stub_calls` (00_shim.sql) records what would have
--   been sent, which is what makes `0187-N5` a behavioural pin rather than a source one.
--   THE ORDER IS LOAD-BEARING: the category is computed first, and a `safety` category **returns
--   before `notification_prefs` is touched at all**. A safety push therefore cannot be lost to a
--   preference, and cannot be lost to a fault in reading preferences either — 0024's function body
--   ends in `exception when others then return new`, which SWALLOWS an error into a skipped push,
--   so any read placed ahead of the safety decision would be a new way to silence SOS.
--   ⚠ ONE RULE DECIDES SUPPRESSION AND IT IS AN EXACT BOOLEAN: **only an explicit `false`
--   suppresses a push.** Everything that could be NULL therefore SENDS — no saved row (the `select
--   into` leaves NULL), a category with no column (the `case` has no ELSE), a NULL category. This
--   is deliberate and it is the direction that matters: a NULL collapsing into silence is how a
--   guard written to protect people ends up muting the one message they needed, and plpgsql is
--   generous with NULL. `0187-N5`'s CONTROL arm is what holds it, and the mutation that widens
--   `is false` to `is not true` reddens exactly that arm.
--   ⚠ An unknown/uncategorised kind (`shop` today) falls to 'safety' — i.e. it is SENT. A new kind
--   arriving without a category must be noisy, never silently muted; `0187-N5` inserts a real
--   `shop` row against all-false prefs to hold that.
--   ⚠ THE `system` ARM IN THE MAPPER IS DEFENCE IN DEPTH, NOT LOAD-BEARING — said out loud because
--   the battery measured it: removing `'system'` from the first `when` changes NO behaviour, since
--   the `else` already answers 'safety'. It is written explicitly so that a later session changing
--   the fallback (a plausible 「make the default `booking`」 edit) does not silently take ops
--   escalations with it. `0187-S1` is the only pin that can see it, and that is the honest scope.
--   ⚠ **THE INBOX IS UNTOUCHED.** The `notifications` row is written either way; `alerts.tsx` shows
--   everything. Preferences gate the DEVICE PUSH and nothing else, and the UI copy says so.
--
-- ⚠ `create or replace` of `notify_push()`, FIRST DEFINED IN 0024 — ACL restated below (the
--   grant-preservation class, CLAUDE.md §Migrations). 0024's body also carried
--   `set search_path = public` with no `pg_temp`; it passes 98 H1 only because 0055's ALTER
--   retro-sealed it, and a `create or replace` WIPES that ALTER — so the in-body list here is
--   `public, pg_temp` and H1 stays green for the right reason rather than by inheritance.
-- ⚠ DEPLOY: `db push` only. No edge function changes in this slice, so there is no ordering
--   hazard — a build without the new screen simply never calls the two RPCs.

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  the table
-- ═══════════════════════════════════════════════════════════════════════════════════════════
create table if not exists notification_prefs (
  profile_id uuid primary key references profiles(id) on delete cascade,
  booking    boolean     not null default true,
  chat       boolean     not null default true,
  community  boolean     not null default true,
  reward     boolean     not null default true,
  updated_at timestamptz not null default now()
);

alter table notification_prefs enable row level security;

-- Own row only, read and write — the `push_tokens` idiom (0024), for the same reason: this row is
-- nobody else's business and there is no product surface that reads another person's preferences.
drop policy if exists "prefs self all" on notification_prefs;
create policy "prefs self all" on notification_prefs for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

comment on table notification_prefs is
  '0187: per-category PUSH preferences (booking · chat · community · reward). The safety category
(kind safety/system) has no column and is not disableable. These gate `notify_push()` only — the
`notifications` row is always written and the in-app inbox always shows it.
⚠ 0115 ④ (`delete_my_account_tx`) does NOT delete this row, and `profiles` is tombstoned rather
than deleted, so the ON DELETE CASCADE never fires on an account deletion. Add `notification_prefs`
to ④ in the next slice that opens that list.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C-1  the category mapper — ONE copy of the chat discriminator
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Pure, no table access, so no definer and no search_path: `noti_kind` is a parameter type
-- resolved at CREATE, and nothing here can be shadowed by a temp object.
create or replace function _noti_push_category(p_kind noti_kind, p_title text) returns text
language sql immutable as $$
  select case
    -- SOS · S1/S2 incidents · 외부 커스터디 이양 · 반환 지연 · ops escalations — not disableable
    when p_kind in ('safety', 'system')                then 'safety'
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
  '0187 §C: notifications row → push category. Called only by notify_push(). Returns safety for an
unknown kind, so an uncategorised push is sent rather than muted.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C-2  the send path
-- ═══════════════════════════════════════════════════════════════════════════════════════════
create or replace function notify_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text; v_cat text; v_allowed boolean;
begin
  v_cat := _noti_push_category(new.kind, new.title);
  -- SAFETY RETURNS BEFORE THE PREFERENCE TABLE IS READ. Not tidiness: the `exception when others`
  -- arm below turns ANY error into a skipped push, so a read placed ahead of this decision would
  -- be a second way to silence SOS. See §C.
  -- ONE RULE, and it is stated as an exact boolean so no NULL can collapse it into silence:
  -- **only an explicit `false` suppresses a push.** `v_cat is not null` is written out rather than
  -- left to `<>`'s NULL behaviour; a `select into` that matches no row leaves v_allowed NULL, which
  -- is 「this person has never saved anything」 and therefore SENDS; and the `case` has no ELSE, so
  -- a category with no column also lands on NULL and also SENDS. Never silently mute.
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

  select token into v_token from push_tokens where profile_id = new.profile_id;
  if v_token is not null and v_token like 'ExponentPushToken%' then
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
  end if;
  return new;
exception when others then
  return new;
end $$;

-- 0024 relied on grant preservation and 0055's ALTER; both are restated here, in this file.
revoke execute on function notify_push() from public, anon, authenticated;

comment on function notify_push is
  '0024 notifications → Expo push bridge, with 0187''s per-category preference gate. safety/system
never even read notification_prefs. A preference suppresses the DEVICE PUSH only — the notifications
row and the in-app inbox are untouched.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  the two RPCs
-- ═══════════════════════════════════════════════════════════════════════════════════════════
create or replace function get_notification_prefs()
returns table (booking boolean, chat boolean, community boolean, reward boolean,
               updated_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- Exactly one row, always: the LEFT JOIN makes the absent-row case return the DEFAULTS rather
  -- than an empty set, so a client that has never saved renders switches instead of a blank list.
  -- `updated_at` NULL is the honest 「no row yet」 signal; the client does not draw it.
  return query
    select coalesce(p.booking,   true),
           coalesce(p.chat,      true),
           coalesce(p.community, true),
           coalesce(p.reward,    true),
           p.updated_at
      from (values (1)) as z(x)
      left join notification_prefs p on p.profile_id = v_uid;
end $$;

revoke execute on function get_notification_prefs() from public, anon;
grant  execute on function get_notification_prefs() to authenticated;

comment on function get_notification_prefs is
  '0187 §B: the caller''s own push preferences, or the defaults (all true) when no row exists.
auth.uid() is the only identity — there is no uid argument to spoof.';

create or replace function set_notification_prefs(
  p_booking   boolean default null,
  p_chat      boolean default null,
  p_community boolean default null,
  p_reward    boolean default null)
returns table (booking boolean, chat boolean, community boolean, reward boolean,
               updated_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- NULL argument = leave that category alone (so one switch can be saved on its own). On a
  -- first-ever save the column DEFAULT is that same value, so the insert and the update arms agree.
  return query
    insert into notification_prefs as np (profile_id, booking, chat, community, reward, updated_at)
    values (v_uid,
            coalesce(p_booking,   true),
            coalesce(p_chat,      true),
            coalesce(p_community, true),
            coalesce(p_reward,    true),
            now())
    on conflict (profile_id) do update
       set booking    = coalesce(p_booking,   np.booking),
           chat       = coalesce(p_chat,      np.chat),
           community  = coalesce(p_community, np.community),
           reward     = coalesce(p_reward,    np.reward),
           updated_at = now()
    returning np.booking, np.chat, np.community, np.reward, np.updated_at;
end $$;

revoke execute on function set_notification_prefs(boolean, boolean, boolean, boolean) from public, anon;
grant  execute on function set_notification_prefs(boolean, boolean, boolean, boolean) to authenticated;

comment on function set_notification_prefs is
  '0187 §B: upsert of the caller''s own row. A NULL argument leaves that category alone, so a single
switch can be saved on its own. Returns the stored row as written.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — fail the APPLY, not a pin. (The suite owns the same shape as `0187-S1`: a property
-- checked only at apply is protected exactly until someone recreates the function.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare v_src text; v_bad text := '';
begin
  -- ① the three definers: prosecdef + the in-body search_path + no PUBLIC/anon execute
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('notify_push', 'get_notification_prefs', 'set_notification_prefs')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) <> 3
  then v_bad := v_bad || ' DEFINER-OR-SEARCH-PATH'; end if;

  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('notify_push', 'get_notification_prefs', 'set_notification_prefs',
                                  '_noti_push_category')
                and (has_function_privilege('public', p.oid, 'execute')
                  or has_function_privilege('anon',   p.oid, 'execute')))
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;

  if not has_function_privilege('authenticated', 'get_notification_prefs()', 'execute')
     or not has_function_privilege('authenticated',
              'set_notification_prefs(boolean, boolean, boolean, boolean)', 'execute')
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;

  -- ② the send path actually consults the prefs, and safety decides BEFORE it. Comments stripped:
  --    a comment explaining the gate would otherwise satisfy a check for the gate (the standing law).
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)'; end if;
  if position('notification_prefs' in coalesce(v_src, '')) = 0
  then v_bad := v_bad || ' NO-PREFS-READ'; end if;
  if position('_noti_push_category' in coalesce(v_src, '')) = 0
  then v_bad := v_bad || ' NO-CATEGORY-MAPPER'; end if;
  -- the conjunct itself, not merely a `'safety'` literal somewhere ahead of the table name: a
  -- `case` arm named 'safety' would satisfy the position check on a function where safety had
  -- become disableable (measured — suite 218 S1 carries the same pair and the reason)
  if coalesce(v_src, '') !~ 'v_cat\s*<>\s*''safety'''
  then v_bad := v_bad || ' NO-SAFETY-CONJUNCT'; end if;
  if not (position('''safety''' in coalesce(v_src, '')) > 0
          and position('''safety''' in coalesce(v_src, ''))
              < position('notification_prefs' in coalesce(v_src, '')))
  then v_bad := v_bad || ' SAFETY-NOT-BEFORE-THE-PREFS-READ'; end if;

  -- ③ RLS on, exactly one policy, and it is not a blanket TRUE
  if not (select relrowsecurity from pg_class where oid = 'notification_prefs'::regclass)
  then v_bad := v_bad || ' RLS-OFF'; end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'notification_prefs') <> 1
  then v_bad := v_bad || ' POLICY-COUNT'; end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'notification_prefs'
                and (coalesce(qual, '') !~ 'auth\.uid\(\)'
                  or coalesce(with_check, '') !~ 'auth\.uid\(\)'))
  then v_bad := v_bad || ' POLICY-NOT-SELF'; end if;

  if v_bad <> '' then
    raise exception '❌ 0187 VERIFY:%', v_bad;
  end if;
end $verify$;
