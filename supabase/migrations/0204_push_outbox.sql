-- ═══ 0204 — the push leaves through an OUTBOX, and the recipient is checked again at dispatch ═══
--
-- Codex finding **B8** (`docs/reviews/2026-09-22-0188-0189-0190-codex-verdict.md:17`), recorded as
-- a gap on 2026-09-22 and carried unreviewed-forward twice:
--   「tombstone does not invalidate a push already queued in the same window · pg_net has no
--    dispatch-time recheck; the window is one transaction; an outbox is a separate slice (queue)」
-- This is that slice.
--
-- ═══ §0 THE DEFECT, READ END TO END RATHER THAN QUOTED ═══════════════════════════════════════
-- `notify_push()` (0024 → 0187 → **0189 §B**, which is its latest declaration — `grep -ln
-- 'function notify_push' supabase/migrations/*.sql` gives exactly those three files) does two
-- things in ONE statement, inside the `notifications` INSERT's transaction:
--   ① it SELECTs the recipient's token joined to `profiles`, requiring `deleted_at is null`
--      (0189 §B ①, the live-recipient conjunct), and
--   ② it `perform net.http_post(...)`.
-- `net.http_post` is **asynchronous**: it returns a request id and pg_net's background worker
-- performs the HTTP call afterwards, outside this transaction (`00_shim.sql:58-66` records the
-- same asynchrony, and it is why the shim has a separate `net._http_response`). So ① is a check
-- taken at time T and ② is an act performed at some time T+δ that nothing re-examines.
--
-- 🔴 THE WINDOW, stated as the property rather than as one site: **between the liveness check and
--    the send, the recipient can stop being a live account, and nothing looks again.** Two
--    reachable shapes, and they are different failures:
--    · **the concurrent commit.** Transaction A writes a notification; its snapshot shows the
--      profile live. Transaction B — `delete_my_account_tx` — commits the tombstone. A commits
--      afterwards with a send already handed to pg_net. Neither transaction did anything wrong;
--      MVCC means A could not have seen B and B could not have seen A's row.
--    · **pg_net's own queue latency.** A request sitting in `net.http_request_queue` is sent when
--      the worker reaches it. Under a backed-up queue that is not instantaneous, and the queue is
--      exactly where 0151/182 found that a row 「holds rows only while a request is in flight」 —
--      a duration nobody has bounded.
--    Neither is closable by another conjunct inside `notify_push`. There is no place to put it:
--    the act being guarded happens after the function returns.
--
-- ⚠ WHAT 0189 ALREADY CLOSES, so this file does not claim it: a recipient ALREADY tombstoned at
--   enqueue time gets nothing (0189 §B ①), and a tombstoned account cannot WRITE a token at all
--   (0189 §C's belt). Those are the two halves of 「is this account alive **now**」. B8 is the
--   third question — 「is it still alive when the push actually leaves」 — and it needs a second
--   place to stand.
--
-- ═══ §0a THE SHAPE: A QUEUE WE OWN, BETWEEN THE DECISION AND THE SEND ═════════════════════════
--   · `notify_push` keeps EVERY classification rule 0187 and 0189 added — the live-recipient
--     conjunct first, the category second, the preference third — and ends by INSERTing a
--     `push_outbox` row instead of calling `net.http_post`. **Nothing about WHAT is sent changes.**
--     The payload is assembled from the same four expressions, byte for byte.
--   · `push_outbox_dispatch()` runs every minute, takes a TRY transaction-scoped job lock, and for
--     each pending row RE-CHECKS that the recipient is a live profile AND that the queued token is
--     still that profile's token, then posts exactly what `notify_push` used to post.
--   · `delete_my_account_tx` cancels the caller's undispatched rows in the deletion's OWN
--     transaction, so the invalidation is atomic with the tombstone rather than dependent on a
--     cron tick.
--
-- 🔴 §0b THE LADDER — which of those three actually closes B8, written as rungs because a verdict
--    would let the weak ones borrow the strong one's standing:
--    · **THE DISPATCH-TIME RECHECK IS THE LOAD-BEARING HALF.** It is the only thing that sees a
--      state which came into being AFTER the enqueue, which is the entire finding. Mutation-
--      verified: delete it and 235 `0204-R2` reddens with a push delivered to a tombstone.
--    · **THE CANCEL-ON-DELETE IS NOT THE SAME GUARD WEARING A SECOND COAT, AND IT IS ALSO NOT
--      THE LOAD-BEARING ONE.** With the recheck present, a pending row for a deleted account
--      produces no push either way — so the cancel's OBSERVABLE contribution is not 「no push」, it
--      is 「the queue stops containing a live-looking push for a deleted account, at commit, with
--      the reason recorded」. That matters for one reason that is not defence-in-depth theatre:
--      **it is the only layer that does not depend on the dispatcher running.** A tick that is
--      unscheduled, wedged behind the job lock, or dying at the HTTP call leaves rows pending; the
--      cancel has already happened. 235 `0204-D1` therefore asserts the MARKER (`cancelled_at`
--      set, reason `account_deleted`) and NOT the absence of a push — a pin asserting the absence
--      would pass with the cancel deleted, which is the 「fix that changes nothing」 shape this
--      repo has paid for twice.
--    · **THE ENQUEUE-TIME CHECK IS KEPT AS A FAST PATH AND PROVES NOTHING NEW.** It is 0189's,
--      unchanged, and 220 still owns it.
--
-- 🔴 §0c THE RESIDUAL, NAMED RATHER THAN HIDDEN — THIS SLICE NARROWS THE WINDOW, IT DOES NOT
--    DELETE IT. `push_outbox_dispatch` re-checks inside its own transaction and then calls
--    `net.http_post`, which is still asynchronous. A deletion committing between the dispatcher's
--    recheck and pg_net's worker firing is still unobserved. What changes is the SIZE and the
--    NUMBER of checks: from 「checked once, at write time, with an unbounded tail」 to 「checked
--    again at most one tick before the send, plus a cancel that fires at the deletion's commit」.
--    Closing the residual entirely needs the recheck to live inside pg_net, which is not ours.
--    **Anyone quoting this file must quote that sentence with it.**
--
-- 🔴 §0d THE PRICE, AND IT IS A PRODUCT DECISION SEAN HAS NOT MADE — **EVERY PUSH IS NOW UP TO
--    ONE TICK LATE.** The job is registered at `* * * * *`, so a notification written at 10:00:01
--    is pushed at 10:01:00: **worst case ~59s, mean ~30s, where today it is ~0.** That is the
--    whole cost of this slice and it falls hardest exactly where it is least welcome — the three
--    urgent titles 0189 exists to protect (`SOS` · `사고 신고 접수` · `러닝 중단 요청`), plus
--    0193's `귀가 확인이 필요해요`. An SOS a minute late is a worse product than an SOS that can
--    reach a tombstone.
--    ⚠ THE FILE DOES NOT RESOLVE THAT TRADE AND MUST NOT PRETEND TO. Two options exist and both
--      are a separate decision:
--        (a) a second, sub-minute job — pg_cron ≥ 1.5 accepts `'15 seconds'`; **this session
--            cannot run the CLI and has not read production's pg_cron version**, so that is an
--            unmeasured premise and is written here as one;
--        (b) a two-speed outbox — `safety` dispatched in the enqueuing transaction and everything
--            else queued — which would keep SOS instant and leave B8 open for exactly the class
--            where a stale delivery is least harmful and a late delivery is most.
--      Neither is built. `dispatch_after` exists in the table so (b) or a backoff can be added
--      without a schema change.
--
-- ⚠ §0d-bis WHAT IS DELIBERATELY NOT BUILT, so nobody reads its absence as an oversight:
--   · **NO RETENTION.** `push_outbox` grows forever — dispatched and cancelled rows are never
--     purged. That is a real operational cost and it is left open because the retention window is
--     a DECISION (how long must 「we tried to push this」 be answerable?) rather than a default, and
--     0115's retention doctrine says such a window belongs to whoever can name the obligation it
--     serves. Bounding it is one `delete … where dispatched_at < now() - <window>` in a later
--     slice; guessing the window here and calling it done is how a retention rule gets made by
--     accident. ⚠ It is NOT free to postpone: at the pilot's volume it is negligible, at scale it
--     is not, and the table is on the write path of every notification.
--   · **NO BACKOFF.** `dispatch_after` is always `now()`, so a failing row is retried on the very
--     next tick until the ceiling. The column exists so a backoff needs no schema change.
--   · **NO OPS READ.** Nothing surfaces the queue to an operator; it is sealed from every client
--     role. A stuck or given-up row is visible only to someone with database access.
--
-- ═══ §0e WHOSE OBJECTS THIS RE-DECLARES, AND WHAT IT DOES NOT EDIT ═══════════════════════════
--   · `notify_push()` — first defined 0024, latest 0189 §B. Re-declared here; **0189 is NOT
--     edited** (it is landed). Its ACL is restated in THIS file (the grant-preservation class,
--     0116:636).
--   · `delete_my_account_tx(uuid)` — patched from the CATALOG, never from a file (§0f). ACL
--     restated here.
--   · NEW and first defined here: `push_outbox`, `push_outbox_dispatch()`.
--   · NOT TOUCHED: `_noti_push_category`, `_noti_urgent_noti_titles`, `_push_token_live_owner`,
--     the `notifications_push` and `push_tokens_live_owner` triggers, `push_tokens`, and every
--     other function. `force_return_tx` and the availability functions belong to sibling slices
--     and are not read or written here.
--
-- ═══ §0f THE CATALOG COPY FOR `delete_my_account_tx` (0191 §0b's rule, inherited whole) ═══════
-- That function has now been rewritten IN PLACE four times — 0138 §F, 0190 §B, 0191 §A, 0202 §B②
-- — each by reading `prosrc` back and patching it. **The file (0115) and the deployed function
-- disagree**, so transcribing any file's text here would silently delete four landings with
-- nothing failing. This file takes the same shape and inherits every guard, plus one:
--   · the body must exist, or the apply aborts rather than guessing;
--   · 0138 §F's revocation enqueue must be present;
--   · 0190 §B's `paid_payout_id is null` retention predicate must be present;
--   · 0191 §A's nine `using detail` arms must be present, COUNTED — exactly 9;
--   · **0202 §B②'s `gear_claims.delivery` redaction must be present** — the newest landing, and
--     the one a copy taken from a stale body would drop;
--   · the insertion anchor must occur EXACTLY ONCE, computed by literal string arithmetic
--     (`length(src) - length(replace(src, anchor, ''))`) rather than by a regex.
--
-- ⚠ §0g THE ANCHOR IS THE `push_tokens` DELETE IN ④, AND THE ORDER IS DELIBERATE. `delete from
--   notifications` runs two statements EARLIER in ④. `push_outbox` therefore holds **no FK to
--   `notifications`** — a `references notifications on delete cascade` would have the queue rows
--   vanish before the cancel could mark them, turning the cancel into a provable no-op that still
--   reads as a fix. `noti_id` is kept as a plain column so the queue stays auditable against the
--   record while surviving the record's deletion.
--
-- ⚠ §0h SUITES WHOSE PINNED BEHAVIOUR THIS SLICE LEGITIMATELY MOVES — 218, 220, 224. Their push
--   probes count `net._stub_calls` deltas around a `notifications` INSERT, i.e. 「the row → HTTP
--   step was taken」 (218's and 220's own headers say so in those words). That step is now
--   row → outbox → HTTP, and the half those suites own — classification, preferences, liveness at
--   enqueue — is the FIRST arrow. Per the standing law (a suite whose pinned behaviour legitimately
--   changes must be updated in the same slice), the three probe helpers now count `push_outbox`
--   rows, scoped to the row they just wrote, and each carries a `[0204]` comment saying why.
--   **Not one pin's proposition changes and not one assertion's expected value changes.** The new
--   property — outbox → HTTP, exactly once, only for a still-live recipient — is owned by 235
--   `0204-R1`…`R4`, named here so no later reader has to find it.
--
-- ⚠ DEPLOY: **`supabase db push` only.** No edge function changes, no secrets, no env. The cron
--   job `push-outbox-dispatch` is created BY THIS MIGRATION and read back at apply (§E); if the
--   registration fails the apply ABORTS, deliberately and per 0157 §A's rule — an environment
--   with no scheduler must not be allowed to believe it has one. **Applying this file without a
--   working pg_cron stops every push**, which is why the readback is an abort and not a notice.
-- ⚠ Pins: `supabase/tests/235_push_outbox_suite.sql` (`0204-Q1`·`Q2`·`R1`…`R4`·`A1`·`A2`·`D1`·
--   `L1`·`C1`·`S1`, tag `pox`) + `90_race_check.sh` arm `RQ` (two processes; the job lock's skip
--   is invisible to a single connection by construction — an advisory lock is re-entrant within
--   a session).


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  the queue — sealed, RLS on, no client grant, and no client ever reads it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ RLS WITH ZERO POLICIES IS THE SEAL, not the absence of grants: `00_shim.sql:213-215` mirrors
--   production's `alter default privileges … grant all on tables to anon, authenticated`, so a new
--   table is born client-writable and only RLS closes it. The explicit `revoke` below is the belt.
create table if not exists push_outbox (
  id             bigint generated always as identity primary key,
  profile_id     uuid        not null references profiles(id) on delete cascade,
  -- the record this push came from. NO FK, and §0g is the reason.
  noti_id        uuid,
  -- the token as it stood AT ENQUEUE. The dispatcher compares it against the token as it stands
  -- AT DISPATCH — a token that moved is a token this row must not be sent to.
  token          text        not null,
  title          text        not null,
  body           text        not null default '',
  data           jsonb       not null default '{}'::jsonb,
  kind           noti_kind   not null,
  created_at     timestamptz not null default now(),
  -- not before this instant. Today always `now()`; the column exists so §0d (b) or a backoff can
  -- be added without a schema change.
  dispatch_after timestamptz not null default now(),
  dispatched_at  timestamptz,
  attempts       int         not null default 0,
  -- why the last attempt did not deliver: an HTTP error, or the NAMED reason it will never be
  -- attempted again (`recipient_not_dispatchable` · `account_deleted` · `gave_up`).
  last_error     text,
  cancelled_at   timestamptz
);
alter table push_outbox enable row level security;
revoke all on table push_outbox from anon, authenticated;

-- The dispatcher's candidate query, and nothing else reads this table in a hot path.
create index if not exists push_outbox_pending_idx
  on push_outbox (dispatch_after, id)
  where dispatched_at is null and cancelled_at is null;
-- `delete_my_account_tx`'s cancel (§D) and any ops question about one person's queue.
create index if not exists push_outbox_profile_pending_idx
  on push_outbox (profile_id)
  where dispatched_at is null;

comment on table push_outbox is
  '0204 §A: notify_push 가 만든 푸시를 실제 발송 전까지 담아 두는 큐. 0189 까지는 notifications
INSERT 트랜잭션 안에서 수신자 생존을 한 번 확인하고 곧바로 net.http_post 를 불렀는데, pg_net 은
비동기라서 확인과 발송 사이에 탈퇴가 커밋될 수 있었고 다시 보는 곳이 없었다(Codex B8).
이 테이블이 그 사이에 선다 — push_outbox_dispatch() 가 매 분 돌며 발송 직전에 수신자와 토큰을
다시 확인하고, delete_my_account_tx 는 탈퇴 트랜잭션 안에서 아직 안 나간 행을 취소한다.
봉인: 정책 0개 + RLS(클라이언트는 default privileges 로 권한을 받으므로 RLS 가 유일한 잠금이다).
핀: 235 (tag pox) + 90_race_check.sh RQ.';

comment on column push_outbox.cancelled_at is
  '0204: 이 행은 절대 발송되지 않는다. 탈퇴(§D, last_error=account_deleted) · 발송 직전 재확인
실패(§C, recipient_not_dispatchable) · 재시도 한도 소진(§C, gave_up) 셋 중 하나. dispatched_at
과 배타적이다 — 둘 다 채워지는 경로는 없다.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  notify_push — 0189 §B's body, with the send replaced by an enqueue
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 EVERYTHING ABOVE THE LAST STATEMENT IS 0189 §B VERBATIM, and that is load-bearing rather
--    than tidy: 220 `0189-S1` reads this function's source with comments stripped and asserts
--    (a) the live-recipient conjunct exists, (b) it is taken BEFORE `_noti_push_category`,
--    (c) the `v_cat <> 'safety'` conjunct exists, (d) `'safety'` is decided BEFORE
--    `notification_prefs` is read. All four still hold here by construction, because the only
--    line that moved is the one after them.
-- ⚠ The `exception when others then return new` arm stays. Its meaning is unchanged: a push that
--   cannot be arranged must never block the `notifications` row, which is the record.
create or replace function notify_push() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text; v_cat text; v_allowed boolean;
begin
  -- ① [0189 §B] THE RECIPIENT MUST BE A LIVE ACCOUNT, AND THIS IS TAKEN FIRST — ahead of the
  -- category decision — so a tombstone is refused for `safety` as well. 0189 §0b carries the
  -- ladder that makes that order safe. [0204] It is now a FAST PATH rather than the only check:
  -- §C re-asks the same question at dispatch, which is where B8 lives.
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

  -- ④ [0204 §B] THE ENQUEUE, where 0024/0187/0189 had `perform net.http_post(...)`. The four
  -- payload expressions are unchanged — `to`, `title`, `body`, `data` are assembled from exactly
  -- the same sources — so nothing about WHAT is sent moves; only WHEN, and WHO decides it is
  -- still allowed to go. §C posts it.
  insert into push_outbox (profile_id, noti_id, token, title, body, data, kind)
  values (new.profile_id, new.id, v_token, new.title, coalesce(new.body, ''),
          jsonb_build_object('kind', new.kind, 'ref_id', new.ref_id), new.kind);
  return new;
exception when others then
  return new;
end $$;

revoke execute on function notify_push() from public, anon, authenticated;

comment on function notify_push is
  '0024 notifications → Expo push bridge · 0187 per-category preferences · 0189 the urgent-title
family and the live-recipient conjunct · [0204 §B] the send is an OUTBOX INSERT, not an HTTP call.
Order is unchanged: a live (non-tombstoned) recipient, then the category, then the preference.
safety/system and the client-written urgent titles never read notification_prefs. A refusal
suppresses the DEVICE PUSH only — the notifications row and the in-app inbox are untouched.
[0204] The HTTP call moved to push_outbox_dispatch(), which re-asks the liveness question at
dispatch time; pg_net is asynchronous, so the check this function takes cannot cover the send
(Codex B8). Cost: a push now waits for the next tick — see 0204 §0d.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  the dispatcher — a TRY xact job lock, a recheck per row, then the same HTTP call
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0190 §A's lock shape, for 0190 §A's reasons:
--   · **TRY, never `pg_advisory_xact_lock`.** A queueing lock makes the second tick WAIT and then
--     run, which for an every-minute job means an unbounded pile of waiting cron backends behind
--     one slow tick. A skipped tick costs at most 60 seconds here, and the rows are still pending.
--   · **xact-scoped, so there is no unlock to forget.** Every exit path — the early return, a
--     raise, the backend dying — releases at commit or rollback. A `pg_advisory_unlock` in this
--     body would be an EARLY release re-opening exactly the window the lock closes, so 235
--     `0204-L1` asserts its ABSENCE as well as the lock's presence.
--   · **Before the first candidate is read.** The race is read-then-post across the whole scan:
--     two ticks reading the same pending row and both posting it is the duplicate, and there is
--     no unique key that could catch it (`dispatched_at` is written AFTER the post, which is the
--     only order that can be honest — writing it first would mark a push that never left).
-- ⚠ THE KEY IS THIS FUNCTION'S OWN NAME and must stay distinct from every other job's.
--
-- 🔴 THE RECHECK IS THE POINT OF THE WHOLE FILE, and it asks TWO questions, not one:
--    · is the recipient still a live profile (0115's `deleted_at` marker)? — B8 exactly;
--    · does the queued token still belong to that profile? — a token that was replaced or removed
--      between enqueue and dispatch points at a device this row was never authorised for. 0189 §C
--      stops a TOMBSTONE writing a token; it does not stop an ordinary re-registration, and a
--      queued row must not outlive the token it was addressed to.
--    Both are ONE `exists` over the same join `notify_push` takes, so the two boundaries cannot
--    drift apart by someone fixing one of them.
-- ⚠ `is not true`, never a bare `IF`: a NULL from the `exists` cannot happen, but every pin and
--   guard this repo has lost to that collapse was one whose job was to notice something MISSING,
--   which is this branch's job exactly.
--
-- ⚠ ATTEMPTS IS INCREMENTED BEFORE THE POST, NOT ON FAILURE, and that is the difference between
--   a counter and a bound. A row whose post raises every time must eventually stop being a
--   candidate; counting only failures leaves a row that raises BEFORE the counter runs (an error
--   in the recheck, an OOM, a backend killed mid-loop) retrying forever. Counting attempts also
--   makes the give-up pinnable without a failing HTTP stub, since a seeded `attempts` is enough.
-- ⚠ THE PER-ROW `begin … exception` IS A SUBTRANSACTION AND THE `update attempts` SITS OUTSIDE IT
--   ON PURPOSE. Inside, a failing post would roll the increment back with it and the bound would
--   never be reached — the retry-forever bug, re-introduced by the block that was supposed to
--   contain the failure.
create or replace function push_outbox_dispatch() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  MAX_ATTEMPTS constant int := 5;
  BATCH        constant int := 200;
  r      record;
  n      int := 0;
  v_live boolean;
begin
  -- [0204 §C] the job lock, before a single candidate is read. TRY, so a slow predecessor is
  -- SKIPPED and never queued; transaction-scoped, so every exit path releases it. `90_race_check.sh`
  -- RQ measures the skip with two processes — a single connection cannot see it at all, because an
  -- advisory lock is re-entrant within a session.
  if not pg_try_advisory_xact_lock(hashtextextended('push_outbox_dispatch', 0)) then
    raise notice 'push_outbox_dispatch: another tick holds the job lock — skipped';
    return 0;
  end if;

  for r in
    select o.id, o.profile_id, o.token, o.title, o.body, o.data, o.attempts
      from push_outbox o
     where o.dispatched_at is null
       and o.cancelled_at is null
       and o.dispatch_after <= now()
       and o.attempts < MAX_ATTEMPTS
     order by o.dispatch_after, o.id
     limit BATCH
  loop
    update push_outbox set attempts = attempts + 1 where id = r.id;

    -- 🔴 THE DISPATCH-TIME RECHECK (Codex B8). Same join notify_push takes, plus the token
    -- identity, asked again HERE because the enqueue's answer is now old.
    select exists (
      select 1
        from push_tokens pt
        join profiles pr on pr.id = pt.profile_id
       where pt.profile_id = r.profile_id
         and pr.deleted_at is null
         and pt.token = r.token)
      into v_live;

    if v_live is not true then
      update push_outbox
         set cancelled_at = now(),
             last_error   = 'recipient_not_dispatchable'
       where id = r.id;
      continue;
    end if;

    begin
      perform net.http_post(
        url := 'https://exp.host/--/api/v2/push/send',
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body := jsonb_build_object(
          'to', r.token,
          'title', r.title,
          'body', coalesce(r.body, ''),
          'sound', 'default',
          'data', r.data
        )
      );
      update push_outbox
         set dispatched_at = now(), last_error = null
       where id = r.id;
      n := n + 1;
    exception when others then
      -- The give-up. `r.attempts` is the value the candidate query READ, i.e. before this tick's
      -- increment, so `+ 1` is the number of attempts made including this one. One statement, two
      -- cases, so the row can never be left saying `gave_up` while still being a candidate.
      update push_outbox
         set last_error   = case when r.attempts + 1 >= MAX_ATTEMPTS
                                 then left('gave_up: ' || sqlerrm, 500)
                                 else left(sqlerrm, 500) end,
             cancelled_at = case when r.attempts + 1 >= MAX_ATTEMPTS then now() else null end
       where id = r.id;
    end;
  end loop;
  return n;
end $$;

revoke execute on function push_outbox_dispatch() from public, anon, authenticated;
grant  execute on function push_outbox_dispatch() to service_role;

comment on function push_outbox_dispatch is
  '0204 §C: push_outbox 의 대기 행을 실제로 발송한다. 매 분 cron(push-outbox-dispatch).
후보를 읽기 전에 pg_try_advisory_xact_lock(hashtextextended(''push_outbox_dispatch'', 0)) —
TRY 라서 겹친 틱은 0 을 돌려주고 건너뛴다(밀리지 않는다), xact 스코프라서 풀 것을 잊을 수 없다.
행마다 발송 직전에 (ⓐ 수신자가 아직 살아 있는 프로필인가, ⓑ 큐에 적힌 토큰이 아직 그 프로필의
토큰인가) 를 다시 묻는다 — 이게 Codex B8 이다: pg_net 은 비동기라 notify_push 가 잡은 시점의
답이 발송 시점에도 참이라는 보장이 없다. 실패하면 cancelled_at + recipient_not_dispatchable.
attempts 는 발송 시도 전에 올린다(실패 시가 아니라) — 그래야 재확인 자체가 터지는 행도 한도에
걸린다. 5회에서 포기하고 cancelled_at + gave_up. 핀: 235 0204-R1..R4·A1·A2·L1, 90_race_check.sh RQ.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  delete_my_account_tx — the tombstone cancels its own pending queue
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Patched from the CATALOG, never from a file (§0f). The inserted statement sits immediately after
-- 0115 ④'s `push_tokens` delete because it is the same act on the other half of the push surface:
-- ④ removes the ADDRESS a push would go to, and this removes the pushes already ADDRESSED.
-- ⚠ §0g: `notifications` is deleted two statements earlier, which is why `push_outbox` holds no FK
--   to it. With one, these rows would already be gone and this UPDATE would be a measured no-op
--   wearing a fix's clothes.
do $mig$
declare
  v_src  text;
  v_new  text;
  v_a    text;
  v_repl text;
  v_n    int;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then
    raise exception '0204 §D: delete_my_account_tx not found — refusing to guess';
  end if;

  -- Inherited landings this copy must carry forward. If any is absent, something re-created the
  -- function from a FILE and the loss is already there — stop loudly rather than carry it forward
  -- under our name.
  if position($e$perform enqueue_billing_key_revocation(p_uid, 'account_deleted');$e$ in v_src) = 0 then
    raise exception '0204 §D: 0138 §F''s revocation enqueue is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$where runner_id = p_uid and paid_payout_id is null$e$ in v_src) = 0 then
    raise exception '0204 §D: 0190 §B''s paid-marker retention predicate is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$update gear_claims set delivery = '{"redacted": true}'::jsonb$e$ in v_src) = 0 then
    raise exception '0204 §D: 0202 §B②''s gear_claims delivery redaction is not in the live body — do not copy this, find out what removed it';
  end if;
  -- 0191 §A put a detail on NINE refusals. Counted, not merely detected: a body that had lost
  -- three of them would satisfy a presence check and the copy would ship the loss.
  v_a := $e$using detail = coalesce(v_block_id::text, '')$e$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 9 then
    raise exception '0204 §D: 0191 §A''s detail arms occur % time(s) in the live body, expected exactly 9 — patch by hand', v_n;
  end if;

  -- ── the anchor: ④'s push_tokens delete, both of its lines ───────────────────────────────────
  v_a := $a$  with d as (delete from push_tokens   where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('push_tokens', v_n);$a$;

  v_repl := $a$  with d as (delete from push_tokens   where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('push_tokens', v_n);

  -- 🔴 [0204 §D] THE QUEUED PUSHES THAT HAVE NOT LEFT YET. The line above removes the ADDRESS;
  -- this removes the pushes already ADDRESSED to it. Until 0204 the send was handed to pg_net
  -- inside the writing transaction, so a deletion had nothing to recall — that is Codex B8's
  -- other half. It is NOT the load-bearing half (push_outbox_dispatch re-checks the recipient
  -- before every send, and a pending row for a tombstone would be refused there anyway); it is
  -- the only half that does not depend on a cron tick running, and it is what makes the
  -- invalidation ATOMIC with the tombstone. Dispatched rows are left alone: they are a record of
  -- something that already happened.
  update push_outbox
     set cancelled_at = now(), last_error = 'account_deleted'
   where profile_id = p_uid and dispatched_at is null and cancelled_at is null;
  get diagnostics v_n = row_count; v_counts := v_counts || jsonb_build_object('push_outbox_cancelled', v_n);$a$;

  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0204 §D: the push_tokens anchor occurs % time(s) in delete_my_account_tx, expected exactly 1 — patch by hand', v_n;
  end if;

  v_new := replace(v_src, v_a, v_repl);
  if v_new = v_src then raise exception '0204 §D: patch did not apply'; end if;

  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);
end $mig$;

-- 0115:645-648 / 0138 §F / 0190 §B / 0191 §A / 0202 §B②'s ACL restated — a `create or replace` on
-- an absent-function path is a plain CREATE, and a SECURITY DEFINER born PUBLIC-executable is the
-- worst shape this repo makes.
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant  execute on function delete_my_account_tx(uuid) to service_role;

comment on function delete_my_account_tx(uuid) is
  '0115 §D + [0138 §F] + [0190 §B] + [0191 §A] + [0202 §B②] + [0204 §D]: 탈퇴 트랜잭션.
[0204 §D] ④ 가 push_tokens 를 지운 직후, 아직 발송되지 않은 push_outbox 행을 취소한다
(cancelled_at, last_error=''account_deleted''). 0204 이전에는 발송이 쓰기 트랜잭션 안에서 pg_net
으로 넘어간 뒤였기 때문에 탈퇴가 되돌릴 대상 자체가 없었다(Codex B8). 이미 나간 행(dispatched_at)
은 건드리지 않는다 — 일어난 일의 기록이다. 반환 jsonb 에 push_outbox_cancelled 칸이 는다.';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  the cron registration — UNSWALLOWED, then READ BACK from cron.job
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0177's shape and 0157 §A's rule, verbatim in intent: **no `exception` handler**. An environment
-- with no scheduler must not be allowed to believe it has one, and here that matters more than
-- anywhere else in the repo — a failed registration means EVERY push stops, silently, with the
-- rows piling up in a table nobody is watching.
-- ⚠ NO `create extension if not exists pg_cron` — 0045:442 installed it in production, and
--   repeating it here would ABORT the local harness (no pg_cron binary), which is the one
--   environment that exercises the strict form. `00_shim.sql:79-113` ships a pg_cron REGISTRY stub
--   whose `cron.schedule` upserts on (jobname, username) exactly as pg_cron ≥ 1.4 does.
-- ⚠ NO `cron.unschedule` first — 0177's reason: `cron.unschedule` raises P0001 on an absent job,
--   so on a fresh database (the exact apply path this VERIFY exists to make honest) an unguarded
--   unschedule aborts before the schedule it was meant to help. The upsert already replaces.
-- ⚠ ONE ABORT DIRECTION IS KNOWN AND ACCEPTED, inherited from 0177: if an existing job is owned by
--   a DIFFERENT `username` than the role applying this file, the upsert key differs, a second row
--   appears, and the readback aborts on `found 2`. Loud, before anything moves.
do $$
begin
  perform cron.schedule('push-outbox-dispatch', '* * * * *',
                        'select push_outbox_dispatch()');
end $$;


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the ARTIFACT, not the tool's report. Suite 235 `0204-S1` carries the same properties
-- as a STANDING pin, because a property checked only at apply is protected exactly until someone
-- recreates the object in a later migration.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE CRON LITERALS ARE WRITTEN TWICE ON PURPOSE (0177's argument). A VERIFY that read the same
--   variable the registration wrote would be the first measurement printed twice, and a mistyped
--   command in §E would satisfy it by construction.
do $verify$
declare v_src text; v_bad text := ''; v_job int;
begin
  -- ① the cron job, read back from cron.job by all three literals
  select count(*)::int into v_job
    from cron.job
   where jobname  = 'push-outbox-dispatch'
     and active
     and schedule = '* * * * *'
     and command  = 'select push_outbox_dispatch()';
  if v_job is distinct from 1 then
    v_bad := v_bad || ' CRON-NOT-REGISTERED(found=' || coalesce(v_job::text, 'NULL') || ')';
  end if;

  -- ② the queue is sealed: RLS on, zero policies, no anon/authenticated privilege of any kind
  if (select c.relrowsecurity from pg_class c where c.oid = 'push_outbox'::regclass) is not true
  then v_bad := v_bad || ' OUTBOX-RLS-OFF'; end if;
  if (select count(*) from pg_policy where polrelid = 'push_outbox'::regclass) <> 0
  then v_bad := v_bad || ' OUTBOX-HAS-POLICIES'; end if;
  if exists (select 1 from unnest(array['anon','authenticated']) g
              where has_table_privilege(g, 'push_outbox', 'select')
                 or has_table_privilege(g, 'push_outbox', 'insert')
                 or has_table_privilege(g, 'push_outbox', 'update')
                 or has_table_privilege(g, 'push_outbox', 'delete'))
  then v_bad := v_bad || ' OUTBOX-CLIENT-GRANT'; end if;

  -- ③ the definers: prosecdef + the in-body search_path + no PUBLIC/anon execute
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('notify_push', 'push_outbox_dispatch', 'delete_my_account_tx')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) <> 3
  then v_bad := v_bad || ' DEFINER-OR-SEARCH-PATH'; end if;
  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('notify_push', 'push_outbox_dispatch', 'delete_my_account_tx')
                and (has_function_privilege('public', p.oid, 'execute')
                  or has_function_privilege('anon',   p.oid, 'execute')
                  or has_function_privilege('authenticated', p.oid, 'execute')))
  then v_bad := v_bad || ' PUBLIC-ANON-OR-AUTHENTICATED-EXECUTE'; end if;

  -- ④ notify_push's source, COMMENTS STRIPPED (a comment explaining a guard would otherwise
  --    satisfy a check for the guard — the standing law), with a NO-SOURCE arm so an absent
  --    function fails LOUDLY: position(x in NULL) is NULL and a bare IF on NULL never fires.
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'notify_push';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_push)';
  else
    if position('insert into push_outbox' in v_src) = 0
    then v_bad := v_bad || ' NOTIFY-PUSH-DOES-NOT-ENQUEUE'; end if;
    if position('net.http_post' in v_src) <> 0
    then v_bad := v_bad || ' NOTIFY-PUSH-STILL-POSTS-DIRECTLY(the B8 window is back)'; end if;
    -- 0189's and 0187's four properties, restated because this file recreates the function
    if position('deleted_at is null' in v_src) = 0
    then v_bad := v_bad || ' NO-LIVE-RECIPIENT-CONJUNCT'; end if;
    if not (position('deleted_at is null' in v_src) > 0
            and position('deleted_at is null' in v_src) < position('_noti_push_category' in v_src))
    then v_bad := v_bad || ' LIVE-RECIPIENT-NOT-BEFORE-THE-CATEGORY'; end if;
    if v_src !~ 'v_cat\s*<>\s*''safety'''
    then v_bad := v_bad || ' NO-SAFETY-CONJUNCT'; end if;
    if not (position('''safety''' in v_src) > 0
            and position('''safety''' in v_src) < position('notification_prefs' in v_src))
    then v_bad := v_bad || ' SAFETY-NOT-BEFORE-THE-PREFS-READ'; end if;
  end if;

  -- ⑤ the dispatcher's source: the TRY xact lock, taken BEFORE the candidate read; no session
  --    unlock; the recheck present and taken BEFORE the post
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'push_outbox_dispatch';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(push_outbox_dispatch)';
  else
    if position('pg_try_advisory_xact_lock(hashtextextended(''push_outbox_dispatch'', 0))' in v_src) = 0
    then v_bad := v_bad || ' NO-JOB-LOCK'; end if;
    if not (position('pg_try_advisory_xact_lock' in v_src) > 0
            and position('pg_try_advisory_xact_lock' in v_src) < position('from push_outbox o' in v_src))
    then v_bad := v_bad || ' JOB-LOCK-NOT-BEFORE-THE-CANDIDATE-READ'; end if;
    if (v_src ~ 'pg_advisory_unlock') is distinct from false
    then v_bad := v_bad || ' SESSION-UNLOCK-PRESENT(early release reopens the race)'; end if;
    if position('pr.deleted_at is null' in v_src) = 0
    then v_bad := v_bad || ' NO-DISPATCH-TIME-LIVENESS-RECHECK'; end if;
    if position('pt.token = r.token' in v_src) = 0
    then v_bad := v_bad || ' NO-DISPATCH-TIME-TOKEN-RECHECK'; end if;
    if not (position('pr.deleted_at is null' in v_src) > 0
            and position('pr.deleted_at is null' in v_src) < position('net.http_post' in v_src))
    then v_bad := v_bad || ' RECHECK-NOT-BEFORE-THE-POST'; end if;
  end if;

  -- ⑥ the deletion's cancel, in the DEPLOYED body (the catalog, never the file)
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'delete_my_account_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
  else
    if position('update push_outbox' in v_src) = 0
    then v_bad := v_bad || ' DELETION-DOES-NOT-CANCEL-THE-QUEUE'; end if;
    if position('''account_deleted''' in v_src) = 0
    then v_bad := v_bad || ' CANCEL-REASON-NOT-NAMED'; end if;
    -- the four inherited landings, re-asserted on the body that actually came out of §D
    if position('enqueue_billing_key_revocation' in v_src) = 0
    then v_bad := v_bad || ' LOST-0138-REVOCATION-ENQUEUE'; end if;
    if position('paid_payout_id is null' in v_src) = 0
    then v_bad := v_bad || ' LOST-0190-RETENTION-PREDICATE'; end if;
    if position('redacted' in v_src) = 0
    then v_bad := v_bad || ' LOST-0202-DELIVERY-REDACTION'; end if;
    if (length(v_src) - length(replace(v_src, 'using detail = coalesce(v_block_id::text', '')))
       / length('using detail = coalesce(v_block_id::text') is distinct from 9
    then v_bad := v_bad || ' LOST-0191-DETAIL-ARMS'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0204 VERIFY:%', v_bad;
  end if;
end $verify$;
