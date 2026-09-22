-- ═══ 0210: ops alerts get their OWN switch · the unknown kind stops failing into always-on ·
-- ═══        and the runner whose money is stuck is finally one of the people who is told
--
-- Three findings, all measured on trunk `6d02769`, and they share one function — 0189's
-- `_noti_push_category`. The first two are what that function ANSWERS; the third is a writer that
-- told everybody except the person whose money it is.
--
-- ═══ §0 WHAT WAS WRONG, MEASURED ═══════════════════════════════════════════════════════════════
--
-- ─── ① OPS ALERTS ARE FILED AS 안전·긴급, AND THEREFORE CANNOT BE TURNED OFF ───
--   0189's mapper opens `when p_kind in ('safety','system') then 'safety'`, and `notify_push`
--   RETURNS BEFORE THE PREFERENCE TABLE IS READ for that category (0187 §C — deliberate, and it
--   stays). So every `system` row is undisableable. The four titles that ride it are ops
--   escalations, enumerated from their writers:
--       「지급 대기 — 확인 필요」        0186:428 → 0190:98   ref = a RUNNER profile
--       「인계 확인 멈춤 — 확인 필요」    0183:429/477 → 0201:929/977
--       「반환 좌초 — 확인 필요」        0193:656 → 0201:503
--       「굿즈 수령 신청 — 확인 필요」    0206:363             ref = a gear_claims row
--   And `notification-settings.tsx` explains that undisableable row to the person holding the
--   phone with 「안전 알림은 끌 수 없어요 — 개와 사람이 걸린 일이라서예요」. For an SOS that is
--   true. For 「굿즈 수령 신청」 — a goods-shipping desk ping — it is not: we are telling an
--   operator that a shipping request is a matter of a dog's safety in order to keep a switch away
--   from them. That is the honesty law in its plainest form, and the fix is a fifth column, not
--   better copy.
--   ⚠ **`safety` IS UNCHANGED AND STAYS ALWAYS-ON.** SOS · S1/S2 incidents · 외부 커스터디 이양 ·
--     반환 지연 · 귀가 확인 — every one of those is `kind = 'safety'` or a member of
--     `_noti_urgent_noti_titles()` (0189 §A, re-checked against its CURRENT declaration in 0193
--     §E: `SOS · 사고 신고 접수 · 러닝 중단 요청 · 귀가 확인이 필요해요`). **NOT ONE of the four
--     ops titles is in that array** — checked, not assumed, which is what makes it safe to move
--     `system` out from under the always-on umbrella. `0210-O2` holds it by value.
--   ⚠ **AN OPERATOR WHO TURNS THIS OFF STILL SEES THE OPS INBOX.** A preference has only ever
--     gated the DEVICE PUSH; the `notifications` row is written on every path and `alerts.tsx`
--     draws it, 0206's console reads are untouched, and `PREFS_NOTE` says so on the screen. The
--     switch buys a quiet phone, never a missing escalation.
--   ⚠ **THE ROW IS OPERATOR-ONLY ON THE CLIENT.** `PREF_ROWS` gains 운영 알림 behind
--     `ops_me().is_ops` (0198 §A — the wrapper already exists), because a switch for a push you
--     can never receive is a dead control wearing a switch's costume. Server-side the column is
--     simply there for everyone, which costs nothing and keeps the setter's shape uniform.
--
-- ─── ② THE UNKNOWN-KIND ARM FAILS OPEN INTO THE UNDISABLEABLE CATEGORY ───
--   0189's mapper ends `else 'safety'`, and 0187 §C argued for it: 「an uncategorised push is SENT,
--   never silently dropped by a preference nobody set for it」. The SENDING half of that sentence
--   is right and is kept. The CATEGORY it chose is not: `'safety'` is the one category a person
--   cannot switch off, so a kind nobody has thought about yet is born with the highest privilege
--   in the system. `noti_kind` (0001:23) has `shop`, with **zero writers** (0187 §0, re-measured
--   here: `grep -c "'shop'" supabase/migrations` outside the enum declaration = 0) — the day
--   someone adds the first one, it arrives as an un-silenceable alert.
--   The fallthrough moves to `booking`, the LEAST-PRIVILEGED disableable category: still sent by
--   default (all columns default true, and only an explicit `false` suppresses — 0187 §C's rule is
--   untouched), and now stoppable by a person who does not want it. `0210-F1` measures both
--   halves: a `shop` row pushes with no prefs row and is silenced by `booking = false`.
--   ⚠ **THE ENUM VALUE IS NOT DROPPED.** Removing a member of `noti_kind` is enum surgery with its
--     own blast radius (every `::noti_kind` cast, every stored row, every dependent view) and it is
--     a separate decision. It is documented as reserved-with-no-writer, in the mapper, where the
--     next person to read the fallthrough will be standing.
--
-- ─── ③ THE RUNNER IS NEVER TOLD THAT THEIR OWN MONEY IS STUCK ───
--   `ops_payouts_stuck_sweep` (0186 §D → 0190 §A) finds every runner whose oldest unpaid ledger
--   row is past seven days with a positive net, and tells `ops_recipients_for('payout_due')`.
--   Measured on 0190:126-135: the ONLY recipients are the ops roster. The runner — whose money it
--   is, who may be the reason it is stuck (no `bank_accounts` row means there is nowhere to send
--   it), and who has a 수익 screen that would show them the rows — learns nothing at all. They are
--   the one party who can act, and they are the one party who is not told.
--   **§D adds a second insert in the same loop**, addressed to the runner.
--   ⚠ **KIND, AND WHY IT IS `booking`.** `noti_kind` has no `payment` member — checked, it is
--     `('booking','community','shop','safety','reward','system')` (0001:23). `system` is now `ops`
--     and is the OPERATOR's category, so it is exactly wrong here. The category a runner reads as
--     money is `booking`: `PREF_ROWS`' 예약·러닝 row says 「… 러닝 시작과 종료, **결제 안내**」,
--     and the runner's other money receipt — 「시간을 비워둔 보상이 기록됐어요」 (0117 ·
--     `cancel_owner.ts`) — is `kind = 'booking'` routed to `/runner/earnings`. One category, one
--     screen, already true before this slice.
--   ⚠ **`ref_id` IS NULL, DELIBERATELY.** `/runner/earnings` takes no booking (it is the whole
--     ledger), so a ref would be a param nothing reads — the defect 0193 codex A4 found in the
--     other direction. `REFLESS_BOOKING_DESTINATIONS` is the shape 0180's 「반복 예약 일시 중지」
--     already uses for exactly this, and `hasNotificationRoute` consults it, so the inbox row is a
--     real tap rather than a dead button or a line of text.
--   ⚠ **THE BODY NAMES THE AMOUNT, AND THE OPS BODY STILL DOES NOT.** 0084 §E keeps ids and money
--     out of an ops body because that body describes a THIRD PARTY. This one describes the reader's
--     own earnings, so the number is theirs to be told.
--   ⚠ **THE BANK ARM IS BOUND TO A REAL READ**, never to a guess: `bank_accounts` (0001:277, PK
--     `runner_id` → `runners.profile_id`, so the key is the profile id) either has their row or it
--     does not, and only the second case says 「정산 계좌를 확인해주세요」. Telling a runner who
--     has already registered an account to go register one would be a fabricated instruction.
--   ⚠ **ONE MESSAGE A WEEK, NOT TWO A DAY.** The ops bell dedupes on a 20-hour lookback because
--     the cron ticks twice daily and an operator's desk is a work queue. A runner is not a desk:
--     the same sentence twice a day is noise that trains them to ignore it, and the condition it
--     reports is a WEEK old by construction. `RUNNER_NOTICE_WINDOW` is 7 days, so a stuck payout
--     says it once and then once a week while it stays stuck. `0210-P2` pins that the second tick
--     adds nothing.
--   ⚠ **THE RUNNER INSERT IS IN ITS OWN SUBTRANSACTION, INSIDE 0190's.** plpgsql's
--     `begin … exception` is a subtransaction: a raise anywhere in 0190's per-runner block rolls
--     back EVERYTHING in it, so putting the new insert beside the ops insert would let a failure in
--     the new code silently destroy the escalation that already works. The nested block makes that
--     impossible rather than unlikely. This is prose and not a pin: the harness has no way to make
--     the runner insert fail without also breaking the fixture, and a pin that cannot be reddened
--     is an unfalsifiable guard doing prose's job (CLAUDE.md).
--   ⚠ **`n` STILL COUNTS WHAT IT COUNTED** — runners for whom at least one OPS recipient was
--     newly told. 217/221 read that number; widening it to mean 「rows written」 would move a
--     value other suites already pin, for no gain. The runner leg reports through `raise notice`.
--
-- ═══ §0b WHAT THIS SLICE DOES NOT CHANGE, said out loud ════════════════════════════════════════
--   · The ORDER inside `notify_push` — live recipient (0189 §B), then category, then preference —
--     is byte-identical. `safety` still returns before `notification_prefs` is touched.
--   · `_noti_urgent_noti_titles()` is NOT re-declared. 0193 §E holds the current array and the
--     client drift gate reads the highest-numbered declaring migration; re-declaring it here to
--     change nothing would move that gate's subject for no reason.
--   · The 20-hour ops dedupe, `STUCK_AFTER`, the candidate query, the job lock and its key are all
--     0190's, unchanged and re-transcribed (this file is the third declaration of that function, so
--     the body is copied from 0190 — the LATEST one — and not from 0186).
--   · `notification_prefs` still survives an account tombstone (0187 §A's note, and 0115 ④ is
--     still where that obligation lives). A fifth boolean does not change that ledger.
--
-- ⚠ `create or replace` of `notify_push()` (first defined 0024), `_noti_push_category()` (0187) and
--   `ops_payouts_stuck_sweep()` (0186) — ACLs restated in THIS file for all three, the
--   grant-preservation class (CLAUDE.md §Migrations, 0116:636). `get_notification_prefs` and
--   `set_notification_prefs` are DROP + CREATE because both return types / signatures change, and a
--   plain CREATE is born PUBLIC-EXECUTABLE — so their revoke/grant pairs are load-bearing, not
--   tidiness.
-- ⚠ DEPLOY: `db push` only, plus a client build. No edge function changes. The two halves are
--   independent in the safe direction: a build without the new screen simply never sends `p_ops`
--   (the argument defaults to NULL = 「leave it alone」), and a server without this migration is
--   what today already is.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  the fifth column
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Default TRUE and NOT NULL, exactly like the other four: opt-out, never opt-in. Every operator
-- who already has a row keeps getting ops pushes until they say otherwise, and an operator with no
-- row at all is unaffected (a `select into` that matches nothing leaves NULL, and NULL SENDS).
alter table notification_prefs add column if not exists ops boolean not null default true;

comment on table notification_prefs is
  '0187 §A + [0210 §A]: per-category PUSH preferences (booking · chat · community · reward · ops).
`ops` gates the `system` kind — the ops roster''s own escalations (지급 대기 · 인계 확인 멈춤 ·
반환 좌초 · 굿즈 수령 신청). Only `safety` has no column and is not disableable: SOS, S1/S2
인시던트, 외부 커스터디 이양, 반환 지연, 귀가 확인 — kind=safety plus _noti_urgent_noti_titles().
These gate `notify_push()` only — the `notifications` row is always written, the in-app inbox
always shows it, and 0206''s ops console reads are untouched.
⚠ 0115 ④ (`delete_my_account_tx`) does NOT delete this row, and `profiles` is tombstoned rather
than deleted, so the ON DELETE CASCADE never fires on an account deletion. Add `notification_prefs`
to ④ in the next slice that opens that list.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  the classifier — 0189 §A's body, with two arms changed and every other one transcribed
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Pure, no table access, so no definer and no search_path: `noti_kind` is a parameter type resolved
-- at CREATE and nothing here can be shadowed by a temp object.
--
-- ⚠ THE ARM ORDER IS THE WHOLE DESIGN AND IT IS NOT ALPHABETICAL:
--   ① `kind = 'safety'` — the writers' own classification, above everything.
--   ② the urgent TITLE family — 0189 §A's finding: 0114:273-281 admits only `kind='booking'` from
--      a party, so SOS/사고/중단 arrive indistinguishable from 응가 도장 and only the title saves
--      them. Still above every disableable arm, `system` included.
--   ③ `kind = 'system'` → **'ops'**, and it sits BELOW ② on purpose. Not one of today's four ops
--      titles is in the urgent family (0210-O2 measures that), so the position changes nothing
--      today — and if an ops writer ever borrows an urgent title, ② wins and that row stays
--      always-on. The safe direction, chosen where it is free.
--   ④…⑦ chat · booking · community · reward, 0189's arms character for character.
--   ⑧ the fallthrough, now `booking` instead of `safety` — see §0 ②.
create or replace function _noti_push_category(p_kind noti_kind, p_title text) returns text
language sql immutable as $$
  select case
    -- ① SOS · S1/S2 incidents · 외부 커스터디 이양 · 반환 지연 — the writer said safety, and
    -- safety is the one category with no column. [0210 §B] `system` no longer rides this arm.
    when p_kind = 'safety'                             then 'safety'
    -- ② [0189 §A] the CLIENT writers of an urgent event plus 0188 ⓑ-①'s server one. They arrive
    -- as kind='booking' because 0114:273-281 admits nothing else from a party, so without this arm
    -- `booking = false` silences an SOS. Deliberately ABOVE every disableable arm — `system`
    -- included, since 0210 made that one disableable — and deliberately NOT gated on the kind.
    when p_title = any (_noti_urgent_noti_titles())    then 'safety'
    -- ③ [0210 §B] the ops roster's own escalations: 지급 대기 · 인계 확인 멈춤 · 반환 좌초 ·
    -- 굿즈 수령 신청 (0186/0190 · 0183/0201 · 0193/0201 · 0206 §C). Disableable by the `ops`
    -- column and by nothing else. An operator who switches it off still gets the `notifications`
    -- row and still has the console — only the phone goes quiet.
    when p_kind = 'system'                             then 'ops'
    -- ④ 0090:87 writes the chat nudge as kind='booking' with this exact title (0090:78 dedupes on
    -- it, notification-route.ts:48 routes on it). `0187-N6` drives the real trigger, so the
    -- three-way agreement is held behaviourally rather than by matching the literal.
    when p_kind = 'booking' and p_title = '새 메시지'  then 'chat'
    when p_kind = 'booking'                            then 'booking'
    when p_kind = 'community'                          then 'community'
    when p_kind = 'reward'                             then 'reward'
    -- ⑧ [0210 §B] THE FALLTHROUGH, AND IT IS THE LEAST-PRIVILEGED DISABLEABLE CATEGORY, NOT THE
    -- UNDISABLEABLE ONE. `shop` is the only `noti_kind` member with no arm above and it is a
    -- RESERVED value with ZERO writers anywhere in this repo (0187 §0, re-measured 2026-09-23) —
    -- the enum member is deliberately NOT dropped here, because enum surgery is a separate
    -- decision with its own blast radius. 0187 §C's rule is kept: an uncategorised push is still
    -- SENT by default, because every column defaults true and only an explicit `false` suppresses.
    -- What changes is that a kind nobody has thought about is no longer born un-silenceable.
    else 'booking'
  end
$$;

revoke execute on function _noti_push_category(noti_kind, text) from public, anon, authenticated;

comment on function _noti_push_category is
  '0187 §C + 0189 §A + [0210 §B]: notifications row → push category. safety and the urgent-title
family are the always-on category; `system` is ''ops'' (the roster''s own escalations, disableable
by the `ops` column); an unknown kind falls to ''booking'' — still SENT by default, no longer born
undisableable. Called only by notify_push().';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C  the send path — 0189 §B's body with one `case` arm added
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function notify_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text; v_cat text; v_allowed boolean;
begin
  -- ① [0189 §B] THE RECIPIENT MUST BE A LIVE ACCOUNT, AND THIS IS TAKEN FIRST — ahead of the
  -- category decision — so a tombstone is refused for `safety` as well. The `notifications` ROW is
  -- still written either way.
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
  -- [0210 §C] `ops` joins the four. `safety` still has no column and is still excluded by the
  -- conjunct below, which is the only category that never reaches this read.
  if v_cat is not null and v_cat <> 'safety' then
    select case v_cat
             when 'booking'   then p.booking
             when 'chat'      then p.chat
             when 'community' then p.community
             when 'reward'    then p.reward
             when 'ops'       then p.ops
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
family and the live-recipient conjunct · [0210 §C] the `ops` column. Order: a live (non-tombstoned)
recipient, then the category, then the preference. Only `safety` never reads notification_prefs. A
refusal suppresses the DEVICE PUSH only — the notifications row and the in-app inbox are untouched.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D  the two RPCs gain `ops` — DROP + CREATE, because both shapes change
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ postgres REFUSES a return-type change on `create or replace`, and a 5th parameter with a
--   default would make the 4-argument call AMBIGUOUS against the surviving 4-parameter function
--   rather than replacing it. Both are therefore dropped first — and a plain CREATE is born
--   PUBLIC-EXECUTABLE (0116:636), so the revoke/grant pairs below are the only thing standing
--   between a SECURITY DEFINER and every anonymous caller.
-- ⚠ Existing 4-argument POSITIONAL callers still resolve: suites 220/224 call
--   `set_notification_prefs(false, false, false, false)` and there is exactly one candidate once
--   the old arity is gone, so `p_ops` takes its default of NULL = 「leave it alone」.
drop function if exists get_notification_prefs();
create function get_notification_prefs()
returns table (booking boolean, chat boolean, community boolean, reward boolean, ops boolean,
               updated_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- Exactly one row, always: the LEFT JOIN makes the absent-row case return the DEFAULTS rather
  -- than an empty set, so a client that has never saved renders switches instead of a blank list.
  -- `updated_at` NULL is the honest 「no row yet」 signal; the client does not draw it.
  -- [0210 §D] `ops` is APPENDED, before `updated_at`, and every existing consumer names its
  -- columns (the client maps by key; 218's helpers use `select * into r`), so nothing reads by
  -- position. It is returned to EVERY caller, operator or not — the screen decides who sees a
  -- switch (`ops_me()`), and a server that answered differently per role would be returning a
  -- field whose meaning depends on the reader.
  return query
    select coalesce(p.booking,   true),
           coalesce(p.chat,      true),
           coalesce(p.community, true),
           coalesce(p.reward,    true),
           coalesce(p.ops,       true),
           p.updated_at
      from (values (1)) as z(x)
      left join notification_prefs p on p.profile_id = v_uid;
end $$;

revoke execute on function get_notification_prefs() from public, anon;
grant  execute on function get_notification_prefs() to authenticated;

comment on function get_notification_prefs is
  '0187 §B + [0210 §D]: the caller''s own push preferences (booking · chat · community · reward ·
ops), or the defaults (all true) when no row exists. auth.uid() is the only identity — there is no
uid argument to spoof. No `safety` column, because there is no `safety` column to return: a
hard-coded true would be a fabricated field.';

drop function if exists set_notification_prefs(boolean, boolean, boolean, boolean);
create function set_notification_prefs(
  p_booking   boolean default null,
  p_chat      boolean default null,
  p_community boolean default null,
  p_reward    boolean default null,
  p_ops       boolean default null)
returns table (booking boolean, chat boolean, community boolean, reward boolean, ops boolean,
               updated_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- NULL argument = leave that category alone (so one switch can be saved on its own). On a
  -- first-ever save the column DEFAULT is that same value, so the insert and the update arms agree.
  return query
    insert into notification_prefs as np (profile_id, booking, chat, community, reward, ops, updated_at)
    values (v_uid,
            coalesce(p_booking,   true),
            coalesce(p_chat,      true),
            coalesce(p_community, true),
            coalesce(p_reward,    true),
            coalesce(p_ops,       true),
            now())
    on conflict (profile_id) do update
       set booking    = coalesce(p_booking,   np.booking),
           chat       = coalesce(p_chat,      np.chat),
           community  = coalesce(p_community, np.community),
           reward     = coalesce(p_reward,    np.reward),
           ops        = coalesce(p_ops,       np.ops),
           updated_at = now()
    returning np.booking, np.chat, np.community, np.reward, np.ops, np.updated_at;
end $$;

revoke execute on function set_notification_prefs(boolean, boolean, boolean, boolean, boolean) from public, anon;
grant  execute on function set_notification_prefs(boolean, boolean, boolean, boolean, boolean) to authenticated;

comment on function set_notification_prefs is
  '0187 §B + [0210 §D]: upsert of the caller''s own row. A NULL argument leaves that category
alone, so a single switch can be saved on its own — which is also what lets a pre-0210 client that
sends four arguments leave `ops` untouched. Returns the stored row as written.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E  ops_payouts_stuck_sweep — the runner is told too
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Body below is 0190 §A's — the LATEST declaration, checked (`create or replace function
-- ops_payouts_stuck_sweep` appears in 0186 and 0190 and nowhere after; 0206 did not touch it) —
-- unchanged except the block marked [0210 §E].
create or replace function ops_payouts_stuck_sweep() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  STUCK_AFTER         constant interval := interval '7 days';
  DEDUPE_WINDOW       constant interval := interval '20 hours';
  -- [0210 §E] a runner is not a work queue: one message, then one a week while it stays stuck.
  RUNNER_NOTICE_WINDOW constant interval := interval '7 days';
  c_ops_class   constant text := 'payout_due';
  c_title       constant text := '지급 대기 — 확인 필요';
  c_body        constant text := '일주일 넘게 지급되지 않은 러너 정산이 있어요. 지급 장부를 확인해 주세요.';
  -- [0210 §E] the runner's own sentence. `notification-route.ts` carries this exact string and
  -- `app/test/notification-route.test.cjs` reads it back out of this file, so the two cannot part.
  c_runner_title constant text := '정산 지급이 늦어지고 있어요';
  r       record;
  n       int := 0;
  v_ops   int;
  v_runner int;
  v_bank  boolean;
  v_body  text;
begin
  -- [0190 §A] the job lock, before a single candidate is read. TRY, so a slow predecessor is
  -- SKIPPED and never queued; transaction-scoped, so every exit path releases it and there is no
  -- unlock to forget. `90_race_check.sh` RP measures the skip with two processes — a single
  -- connection cannot see this property at all, which is why 217 P6 was green without it.
  if not pg_try_advisory_xact_lock(hashtextextended('ops_payouts_stuck_sweep', 0)) then
    raise notice 'ops_payouts_stuck_sweep: another tick holds the job lock — skipped';
    return 0;
  end if;

  for r in
    -- [0210 §E] `net` is ADDED to the select list. It is the SAME expression the `having` already
    -- computes to decide the row is a candidate at all, so it is a projection of a number this
    -- query was producing anyway — not a second definition of what a runner is owed.
    select l.runner_id as runner, min(l.created_at) as oldest,
           sum(l.base + l.distance_pay + l.addon_pay + l.tip
                 + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::bigint as net
      from ledger_items l
     where l.paid_payout_id is null
       and not exists (select 1 from runs rn
                        where rn.booking_id = l.booking_id and rn.ended_at is null)
     group by l.runner_id
    having sum(l.base + l.distance_pay + l.addon_pay + l.tip
                 + coalesce(l.remaining_guarantee, 0) - l.platform_fee) > 0
       and min(l.created_at) < now() - STUCK_AFTER
     order by min(l.created_at), l.runner_id
  loop
    begin
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_title, c_body, r.runner
        from ops_recipients_for(c_ops_class) as rc(profile_id)
       where not exists (
             select 1 from notifications n2
              where n2.profile_id = rc.profile_id
                and n2.kind    = 'system'
                and n2.title   = c_title
                and n2.ref_id  = r.runner
                and n2.created_at > now() - DEDUPE_WINDOW);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then n := n + 1; end if;
      raise notice 'ops_payouts_stuck_sweep: runner % unpaid since %, past %: % ops recipient(s) told for %',
        r.runner, r.oldest, STUCK_AFTER, v_ops, c_ops_class;

      -- ─── [0210 §E] AND THE RUNNER, whose money it is ────────────────────────────────────────
      -- ITS OWN SUBTRANSACTION, INSIDE the per-runner one. `begin … exception` is a
      -- subtransaction: a raise here would otherwise roll back the ops insert above, so a fault in
      -- the new leg could destroy the escalation that already works. Nested, it cannot.
      begin
        -- Bound to a real read, never to a guess: only a runner with NO bank row is told to go
        -- register one. `bank_accounts.runner_id` is `runners.profile_id` (0001:277), so this is
        -- the same id the loop is already holding.
        v_bank := exists (select 1 from bank_accounts ba where ba.runner_id = r.runner);
        v_body := to_char(r.net, 'FM999,999,999,999') || '원이 일주일 넘게 지급되지 않았어요 · '
               || case when v_bank then '수익 화면에서 내역을 확인할 수 있어요'
                                   else '정산 계좌를 확인해주세요' end;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select r.runner, 'booking'::noti_kind, c_runner_title, v_body, null
         where not exists (
               select 1 from notifications n3
                where n3.profile_id = r.runner
                  and n3.kind    = 'booking'
                  and n3.title   = c_runner_title
                  and n3.ref_id is null
                  and n3.created_at > now() - RUNNER_NOTICE_WINDOW);
        get diagnostics v_runner = row_count;
        raise notice 'ops_payouts_stuck_sweep: runner % told about their own stuck payout: % row(s), bank_on_file=%',
          r.runner, v_runner, v_bank;
      exception when others then
        raise notice 'ops_payouts_stuck_sweep: runner % — the runner leg failed (%), the ops bell stands',
          r.runner, sqlerrm;
      end;
    exception when others then
      raise notice 'ops_payouts_stuck_sweep: runner % — %', r.runner, sqlerrm;
    end;
  end loop;
  return n;
end $$;
-- 0186 §F's ACL restated (this repo never relies on grant preservation — 0116:636).
revoke execute on function ops_payouts_stuck_sweep() from public, anon, authenticated;
grant  execute on function ops_payouts_stuck_sweep() to service_role;

comment on function ops_payouts_stuck_sweep is
  '0186 §D + 0190 §A + [0210 §E]: 하루 두 번 도는 「막힌 지급」 보고. 미지급(paid_payout_id IS NULL)
정산 중 가장 오래된 행이 7일을 넘고 순액이 0보다 큰 러너마다 ops_recipients_for(''payout_due'')
수신자에게 1회 알린다(20시간 룩백; 본문에 id도 금액도 없다 — 0084 §E).
[0190 §A] 후보를 읽기 전에 pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'',
0))을 잡는다(TRY라서 밀리지 않고 건너뛴다; xact 스코프라서 풀 것을 잊을 수 없다).
[0210 §E] **러너 본인에게도 알린다** — 0190까지는 돈의 주인만 빼고 모두가 알았다. kind=booking
(noti_kind에 payment 멤버가 없고, 러너가 돈으로 읽는 칸이 예약·러닝이다), 제목
「정산 지급이 늦어지고 있어요」, ref_id는 NULL(/runner/earnings는 예약을 받지 않는다 —
REFLESS_BOOKING_DESTINATIONS가 목적지를 준다), 본문은 **본인 금액**을 말하고 bank_accounts 행이
없을 때만 「정산 계좌를 확인해주세요」라고 한다(실제 읽기에 묶인 문장이지 추측이 아니다).
룩백은 7일 — 운영자 데스크는 큐지만 러너는 아니다. 러너 삽입은 **중첩 서브트랜잭션**이라
새 다리가 실패해도 이미 동작하는 ops 종은 살아남는다. 반환값 n의 뜻은 바뀌지 않았다(새로 알린
OPS 수신자가 있던 러너 수). 241 0210-P1/P2/P3가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — fail the APPLY, not a pin. (A property checked only in a suite is not checked on the
-- environment the file actually lands on; a property checked only at apply is protected exactly
-- until someone recreates the function. The overlap with 241 is deliberate.)
-- ⚠ Comments are STRIPPED before every source match: `prosrc` is source PLUS our own prose, and
--   every sentence explaining a guard is a string that satisfies a check for the guard.
-- ⚠ Every arm is an EXACT boolean (`is distinct from` / `is not true`), never a bare IF on a
--   possibly-NULL predicate — `position(x in NULL)` is NULL and a bare IF on NULL never fires,
--   which is precisely how a check written to notice something missing goes silent.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare v_src text; v_bad text := '';
begin
  -- ① the column exists, is NOT NULL and defaults true
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'notification_prefs' and column_name = 'ops'
         and is_nullable = 'NO' and column_default = 'true') is distinct from 1
  then v_bad := v_bad || ' OPS-COLUMN-SHAPE'; end if;

  -- ② the classifier ANSWERS, by value — not by source, because what matters is the mapping
  if _noti_push_category('system'::noti_kind, '지급 대기 — 확인 필요') is distinct from 'ops'
  then v_bad := v_bad || ' SYSTEM-NOT-OPS'; end if;
  if _noti_push_category('safety'::noti_kind, '아무거나') is distinct from 'safety'
  then v_bad := v_bad || ' SAFETY-MOVED'; end if;
  if _noti_push_category('booking'::noti_kind, 'SOS') is distinct from 'safety'
  then v_bad := v_bad || ' URGENT-TITLE-DISABLEABLE'; end if;
  if _noti_push_category('shop'::noti_kind, '아무거나') is distinct from 'booking'
  then v_bad := v_bad || ' FALLTHROUGH-NOT-BOOKING'; end if;
  if _noti_push_category('booking'::noti_kind, '새 메시지') is distinct from 'chat'
     or _noti_push_category('booking'::noti_kind, '응가 완료') is distinct from 'booking'
     or _noti_push_category('community'::noti_kind, 'x') is distinct from 'community'
     or _noti_push_category('reward'::noti_kind, 'x') is distinct from 'reward'
  then v_bad := v_bad || ' EXISTING-ARMS-MOVED'; end if;
  -- …and NONE of the four ops titles may be in the urgent family, or moving `system` off the
  -- always-on arm would have been a no-op hiding behind a green.
  if (select count(*) from unnest(array['지급 대기 — 확인 필요', '인계 확인 멈춤 — 확인 필요',
                                        '반환 좌초 — 확인 필요', '굿즈 수령 신청 — 확인 필요']) as t(x)
       where x = any (_noti_urgent_noti_titles())) is distinct from 0
  then v_bad := v_bad || ' AN-OPS-TITLE-IS-IN-THE-URGENT-FAMILY'; end if;

  -- ③ the send path reads the new column and still excludes safety BEFORE the read
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
  else
    if (position('when ''ops''' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-OPS-ARM-IN-THE-SEND-PATH'; end if;
    if (v_src ~ 'v_cat\s*<>\s*''safety''') is not true
    then v_bad := v_bad || ' NO-SAFETY-CONJUNCT'; end if;
    if (position('''safety''' in v_src) > 0
        and position('''safety''' in v_src) < position('notification_prefs' in v_src)) is not true
    then v_bad := v_bad || ' SAFETY-NOT-BEFORE-THE-PREFS-READ'; end if;
    if (position('deleted_at is null' in v_src) > 0
        and position('deleted_at is null' in v_src) < position('_noti_push_category' in v_src)) is not true
    then v_bad := v_bad || ' LIVE-RECIPIENT-NOT-FIRST'; end if;
  end if;

  -- ④ the two RPCs exist at their NEW shapes, with the ACL restated
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('notify_push', 'get_notification_prefs', 'set_notification_prefs')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 3
  then v_bad := v_bad || ' DEFINER-OR-SEARCH-PATH'; end if;
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('notify_push', 'get_notification_prefs', 'set_notification_prefs',
                                  '_noti_push_category', 'ops_payouts_stuck_sweep')
                and (has_function_privilege('public', p.oid, 'execute')
                  or has_function_privilege('anon',   p.oid, 'execute')))
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;
  if has_function_privilege('authenticated', 'get_notification_prefs()', 'execute') is not true
     or has_function_privilege('authenticated',
          'set_notification_prefs(boolean, boolean, boolean, boolean, boolean)', 'execute') is not true
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;
  -- the OLD 4-argument arity must be GONE, or a positional call is ambiguous
  if to_regprocedure('set_notification_prefs(boolean, boolean, boolean, boolean)') is not null
  then v_bad := v_bad || ' THE-4-ARG-SETTER-SURVIVED'; end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'notification_prefs') is distinct from 7
  then v_bad := v_bad || ' PREFS-COLUMN-COUNT'; end if;

  -- ⑤ the sweep tells the runner, and the ops leg is untouched
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ops_payouts_stuck_sweep';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_payouts_stuck_sweep)';
  else
    -- 🔴 THE ARM BELOW IS THE ROW THAT IS INSERTED, NOT THE STRING THAT IS DECLARED, and the
    -- difference was MEASURED rather than reasoned (battery M4, 2026-09-23). Deleting the entire
    -- runner insert while leaving `c_runner_title constant text := …` in the declare block left
    -- both this block and 241 `0210-S1` GREEN — the title literal is present in the source of a
    -- function that no longer writes it, which is the comment-quoting law wearing a constant's
    -- costume: a pattern present in BOTH the fixed and unfixed states is uninformative. The
    -- property stated without reference to that mutation: **the sweep must INSERT a `booking` row
    -- addressed to the runner**, and the recipient expression is the only thing that says so.
    -- ⚠ Deliberately NOT anchored on `c_runner_title`: inlining the literal would be a legitimate
    --   refactor, and a gate that reddens on correct code is `--no-verify`'d within a day. The
    --   TITLE and the BODY are held behaviourally instead (241 `0210-P1`/`P3`).
    if (v_src ~ 'select\s+r\.runner,\s*''booking''::noti_kind,') is not true
    then v_bad := v_bad || ' NO-RUNNER-ROW-INSERTED'; end if;
    if (position('정산 지급이 늦어지고 있어요' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-RUNNER-TITLE-CONSTANT'; end if;
    -- the bank sentence must be DRIVEN by the read, not merely accompanied by it
    if (v_src ~ 'v_bank\s*:=\s*exists\s*\(') is not true
    then v_bad := v_bad || ' THE-BANK-ARM-IS-NOT-BOUND-TO-A-READ'; end if;
    if (position('bank_accounts' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-BANK-TABLE-READ'; end if;
    if (v_src ~ 'case\s+when\s+v_bank\s+then') is not true
    then v_bad := v_bad || ' THE-BODY-DOES-NOT-BRANCH-ON-THE-BANK-READ'; end if;
    if (position('정산 계좌를 확인해주세요' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-BANK-INSTRUCTION'; end if;
    if (position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src) > 0
        and position('pg_try_advisory_xact_lock(hashtextextended(''ops_payouts_stuck_sweep'', 0))' in v_src)
            < position('from ledger_items' in v_src)) is not true
    then v_bad := v_bad || ' JOB-LOCK-GONE-OR-AFTER-THE-CANDIDATES'; end if;
    if (position('pg_advisory_unlock' in v_src) > 0) is not false
    then v_bad := v_bad || ' AN-EARLY-UNLOCK-REOPENED-THE-WINDOW'; end if;
    if (position('ops_recipients_for' in v_src) > 0) is not true
    then v_bad := v_bad || ' THE-OPS-BELL-IS-GONE'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0210 VERIFY:%', v_bad;
  end if;
end $verify$;
