-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0237 — a recurring series that keeps failing finally reaches an operator: the
--        `recurring_generation_failed` class, one ring per failure EPISODE, recovery resets it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 268_recurring_failure_escalation_suite.sql (tag `rfe`) — 0237-C1 · E1 · E2 · E3 · E4 · E5 ·
--        E6 · E7 · E8 · E9 · B1 · S1
-- Deploy: `supabase db push` only. No edge function, no cron change, no client code change (one
--        roster chip label and the 운영 알림 sentence — display vocabulary, no new route), no flag.
-- ⚠ Numbers: 0229–0231 / suites 260–262 are held by unpushed worktrees on Sean's Mac (REGISTRY, the
--   0228 row); 0232–0236 / 263–267 by other cloud slices. 0237 / 268 were GIVEN by the coordinator
--   and re-read against every local and remote-tracking ref at claim time AND at commit time.
-- Stacks on `cloud/0233-incident-exits` @ 2aaef9b (= trunk + 0232 + 0233/0234). Every re-declared
--   object is copied from its LATEST body on THAT stack (see §0e).
--
-- ═══ §0a WHAT IS WRONG — Codex wave-4 s1 (high), still open ══════════════════════════════════════
-- docs/reviews/2026-09-25-wave4-codex-verdicts.md s1, verbatim in substance: 「0227:323-345 — a series
-- that fails every tick is recorded and warned, the tick succeeds, and nothing ever escalates: the owner
-- silently loses recurring bookings while cron reports success.」 Codex's recommendation: 「Add a
-- monitored, deduplicated escalation for repeated or aged failures, isolated from minting. Test that
-- persistent failure alerts an operator, healthy series continue, and recovery resets the escalation
-- episode.」
-- Read on this stack (0232 §D, the generator's latest body): the per-series handler raises a WARNING
-- and upserts `recurring_generation_failures` (0227 §A) — and nothing reads that table. 0227 §0d said
-- so out loud (「It pages nobody … a product decision — named in the REGISTRY row」) and 0232 §0d left
-- it for 「a slice that owns 245」. This is that slice. A series whose rule is malformed, or whose row
-- is held by a stuck session every hour, fails ~70 hourly ticks in a row (its 72 h → 2 h minting
-- window), the booking is never made, the owner is told nothing, and `cron.job_run_details` reads
-- `succeeded` every time. REPRODUCED on 0232's body: 268 `0237-E1` — six failing ticks, zero ops rows.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `recurring_generation_failures` gains the EPISODE: `episode_failures` (failed ticks since the
--      episode began), `episode_started_at`, `escalated_at` (the instant this episode rang; NULL = not
--      yet). The lifetime `attempts` / `first_failed_at` / `last_failed_at` are untouched.
--   §B `_noti_ops_titles()` — 0234 §A's ledger plus ONE title (19): 「반복 예약 생성 실패 — 확인 필요」.
--   §C `ops_roster_set` — patched FROM THE CATALOG (0234 §C's method; its live body is in no file): the
--      class `recurring_generation_failed` joins `c_classes`, so an operator can be seated from the
--      product. Every inherited landing asserted before the copy.
--   §D `_recurring_failure_escalate(uuid)` — NEW. Given a series that has just failed a tick: if its
--      current episode has reached `c_ring_at` failed ticks and has not rung, write ONE `system` row to
--      every `recurring_generation_failed` recipient (constant title, identifier-free body, `ref_id` =
--      the SERIES) and stamp `escalated_at` — ONLY when at least one recipient was written (an empty
--      roster rings nobody, stamps nothing, and the next failing tick tries again: 0233 arm ⓗ's rule).
--   §E `generate_recurring_bookings` — 0232 §D's body, built BY SCRIPT, four edits and nothing else:
--        ① the failure upsert also counts the episode (`episode_failures` + 1, `episode_started_at`
--          kept or started) — ④ says which failures count;
--        ② after the record's own block, the escalation in ITS OWN subtransaction (a raise inside it is
--          a WARNING; the record, the rest of the tick and every sibling stand — 268 `0237-E4`);
--        ③ after `n := n + 1` (a booking of this series was MINTED this tick), the RECOVERY reset in its
--          own subtransaction: `episode_failures = 0`, `episode_started_at` / `escalated_at` NULL — so
--          the next failure starts a NEW episode that rings again (`0237-E3`); a raise inside it is a
--          WARNING and the booking stands (`0237-E5`);
--        ④ [exec review 2026-09-26] only a failure that is COSTING A BOOKING advances the episode:
--          ④a `v_sched := null` at the top of the series' block (so a failure before the occurrence is
--          named cannot read the previous series' value), ④b inside the record's own block, `v_owed` =
--          「the occurrence was never named, or the series holds no booking on its KST date」, and the
--          upsert adds 1 only when owed (the lifetime `attempts` / `error_code` are written either way).
--          `0237-E9` (two real sessions).
--      Every other line is 0232's byte for byte — the build script undoes the four edits and asserts
--      equality with 0232's text. The money gates, the route gate, the episode rows of 0232, 0227's
--      per-series block and nested record write, the dog lock, `lock_timeout`, the loop order, the
--      ownership belt, every insert and every owner-facing string: UNCHANGED. ACL restated.
--
-- ═══ §0c THE RULE, NAMED — and why it is this one ═════════════════════════════════════════════
--   **A series rings when the SAME failure episode reaches `c_ring_at` = 3 failed ticks. An episode
--   begins at a series' first failure and ends when the generator MINTS a booking for that series.
--   One ring per episode (per recipient: one row each). Nothing else resets it.**
--   · Why a COUNT and not an age: the only thing that makes a failure "repeated" is that the generator
--     tried again and it failed again, and the table already counts that per tick. An age ("failing for
--     ≥ X h") needs a second clock and says nothing a count does not: the cron is hourly, so 3 failed
--     ticks is ≥ ~2 h of failing.
--   · Why 3: one failed tick can be noise — an overlapping manual call waiting on the cron's dog lock
--     records a 55P03 that means 「another tick had this dog」 (0227 §0d ②), and one stuck session can
--     outlast one 2 s lock wait. Two ticks can be the same stuck session. The third is past both, and it
--     arrives ~2 h into a ~70 h minting window (T-72 h → T-2 h), leaving an operator ~2½ days before the
--     booking is lost. Bigger thresholds spend that margin; smaller ones page for noise.
--   · **Only a failure that is costing a booking counts (§E ④).** After a mint, the occurrence stays
--     inside the 72 h window for ~70 hourly ticks, and each of them still takes the dog lock BEFORE the
--     dedup `continue` (0180's order, pinned by 211 `0180-A1`, deliberately not moved). So contention
--     noise could not be assumed to sit between mints: an executing review measured three 55P03 ticks
--     on a series already holding its booking → a page. A failed tick whose occurrence is named and
--     already booked is RECORDED (attempts, error_code) and does not advance the episode; a failure that
--     never named its occurrence (malformed rule, bad time) always counts — errs toward telling.
--   · Why "failed ticks in the episode" and not "CONSECUTIVE ticks": a tick in which the series is NOT
--     attempted (paused by its owner, outside its window, money-blocked, clash, route gate) is not a
--     success — only a mint proves the series works. Counting those as resets would let a series that
--     fails at every attempt and is blocked in between never ring. ⚠ Consequence, stated: a failure
--     episode can span WEEKS if the series never mints in between (e.g. it fails twice, the owner
--     pauses it, unpauses it a month later and it fails again → that third failure rings). That errs
--     toward telling, once.
--   · Why the reset is a write on the minting path when 0227 §0c refused one: 0227 refused it because a
--     new statement there could cost a booking. §E ③ is in its OWN subtransaction (`0237-E5` plants a
--     raise inside it: the booking and its notice stand), and it runs once per MINT — about once per
--     series per week — not once per series per tick. The alternative witnesses were measured and are
--     WORSE: `bookings.created_at` is party-writable (`bookings party update`, 0057:377, and
--     `_guard_booking_cols` (0058) does not guard `created_at`), so an owner or runner could post-date
--     one booking and make every later failure look like a recovery — a client-forged silence; and a
--     booking COUNT can move for reasons unrelated to minting. The generator observing its own mint is
--     the only witness a client cannot touch.
--
-- ═══ §0d THE ONE-SHOT KEY — why it is a server column, not a notifications read ═══════════════════
--   0233/0234's fix round keyed their bells on the notifications table: kind `system` AND a recipient
--   who is or was seated at the class, because `noti self update` (0002, USING-only) lets any signed-in
--   user rewrite one of their own rows to any kind/title/ref_id/created_at, and 0114's party insert
--   admits look-alike titles. They named a RESIDUE: a profile once seated at the class can still forge
--   the bell on their own row and silence it. 0233 had no server-owned episode state to key on; this
--   file does — `recurring_generation_failures` is server-only (RLS on, zero policies, every client
--   privilege revoked, 258 `0227-S1`). So the key is `escalated_at`, written only by §D and cleared only
--   by §E ③, and the ring reads NO notifications row at all. No client — stranger, series owner or
--   seated operator — can suppress it (268 `0237-E6`, which forges all three first and asserts each
--   forging UPDATE landed). This is 「never (ref_id, title) alone」 taken one step further, not a
--   departure from it: the brief's requirement is that the key be unforgeable, and this one has no
--   client door at all, residue included.
--
-- ═══ §0e WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
--   · **NO owner-facing copy.** The owner of a failing series is still told nothing — what they are
--     told (and whether) is Sean's letter (docs/reviews/2026-09-25-wave4-codex-verdicts.md s1 routing:
--     「owner-facing copy stays Sean's letter」). This file pages the ROSTER only.
--   · **No console desk and no notification route.** Nothing lists failing series in the product; the
--     ring is ledgered, so `ops/index.tsx` draws it as a card carrying its body (no chevron, no dead
--     button — `ops-system-titles.test.cjs` pins 「a ledgered title has a destination iff it is in
--     OPS_SYSTEM_TITLES」), and the body says where the facts are. A read (`ops_failing_series()`) and
--     a desk are a later slice's.
--   · The title is NOT urgent: it files as `ops`, which an operator can switch off on their phone (the
--     console still shows it) — every other ops title's category.
--   · `_shared/ops.ts`'s `OpsEventClass` is not touched: the emitter is SQL (like `return_strand`).
--   · A tick in which the ring's own write fails (`0237-E4`) does not stamp `escalated_at`, so the next
--     FAILING tick rings. If the series stops failing first, that episode is never rung — it ended.
--   · NAMED RESIDUE (prose — no pin: the harness cannot separate a shared cause from a planted one): the
--     ring is an INSERT into `notifications`, the same channel the generator's own notices use
--     (「반복 러닝 예약 생성」). A fault that breaks every notifications insert — the kind that could BE
--     why the series fails — breaks the ring the same way on every tick: `escalated_at` is never
--     stamped and the only trace per tick is a WARNING. Common mode, not isolation. The durable record
--     survives it: `recurring_generation_failures` (error_code, episode_failures ≥ 3, escalated_at IS
--     NULL) is exactly the 「due and unrung」 set a later read or desk should show.
--   · NAMED RESIDUE (prose — the harness has one session): two overlapping ticks (a manual call beside
--     the cron). The follower records a 55P03 for a dog the leader holds, and — if the leader then
--     mints that series — the leader's reset UPDATE may wait on the follower's row lock for the 2 s
--     `lock_timeout` and time out; the booking stands (E5's property) and the episode is NOT reset, so
--     the follower's noise failure and any later real ones share an episode. Errs toward telling; the
--     series' next mint resets it.
--   · NO backfill of pre-0237 failure rows (exec review 2026-09-26 removed a draft one): such a row reads
--     episode 0 / not rung and its series' next failing tick starts an episode — at most two ticks of
--     delay, never a page for a series that had recovered. Production is believed to hold no such rows
--     (0227 is not deployed there — the handoff's 「production is at 0202」, READ, not measured here).
--   · The ring BODY claims only what every ringing episode makes true — the generator failed for this
--     series several times — and points at `error_code` (55P03 = lock contention). It does not say the
--     owner is losing bookings (a malformed rule can ring while this week's booking exists), and it does
--     not say 「연속으로」: the rule counts failed ticks in the episode, not consecutive ones (§0c).
--
-- ═══ §0f SHIPPED PINS / FILES THAT MOVE, AND WHY ═════════════════════════════════════════════
--   · `161 P4` — the generator's prosrc/comment digests, re-read from the catalog after this file
--     applied, as P4's own note asks (re-read again after the exec-review round's edit ④).
--   · `245 0214-T1` (19 titles) and `0214-T4` (`_recurring_failure_escalate` joins SYSTEM_WRITERS).
--   · `239`'s copy of `c_classes` gains the class (its NAMED GAP ④: the two copies AGREE).
--   · `app/src/lib/ops-roster.ts` gains the chip label; `app/test/ops-roster.test.cjs`'s SERVER_CLASSES
--     the class. `app/src/lib/notification-prefs.ts`'s 운영 알림 sentence names the new family, and
--     `app/test/notification-prefs.test.cjs` ⑦ gains the family. `app/test/ops-system-titles.test.cjs`
--     re-derives the ledger from the writers and needs no edit (it reads the latest declarations).
--
-- ═══ §0g WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES `generate_recurring_bookings()` ←0232 §D (built by script, four edits, every other line
--   asserted identical) · `_noti_ops_titles()` ←0234 §A (copied by script, +1) · `ops_roster_set(uuid,text,
--   boolean)` ←the catalog (0208 §C + 0216 §A + 0234 §C; one array entry). ALTERS table
--   `recurring_generation_failures` (+3 columns). CREATES `_recurring_failure_escalate(uuid)`. Every
--   ACL restated in THIS file.
--   ⚠ A later slice re-declaring `generate_recurring_bookings` must keep 0227's per-series block and
--   nested record write, 0232's route gate and episode rows, AND this file's episode count (with its
--   `v_owed` condition and the `v_sched := null` reset), the escalation's own block and the recovery
--   reset's own block (268 `0237-E1…E5`, `E8`, `E9`).
--   ⚠ ⚠ `0231` (be/sweep-honesty-route-gate, held on Sean's Mac) was ROUTED this finding and is
--   described in the verdict doc as 「already re-declaring generate_recurring_bookings」. If it lands
--   after this file it will be a re-declaration from an OLDER body — whoever lands second must rebuild
--   from the latest (268 reddens if the escalation is lost).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A recurring_generation_failures — the episode
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
alter table recurring_generation_failures
  add column if not exists episode_failures   int not null default 0,
  add column if not exists episode_started_at timestamptz,
  add column if not exists escalated_at       timestamptz;
do $chk$ begin
  if not exists (select 1 from pg_constraint where conname = 'recurring_generation_failures_episode_failures_check') then
    alter table recurring_generation_failures
      add constraint recurring_generation_failures_episode_failures_check check (episode_failures >= 0);
  end if;
end $chk$;

-- NO BACKFILL (exec review 2026-09-26). A pre-0237 row starts at episode 0 / not rung, and its series'
-- next failing tick starts an episode (§0e). The earlier draft backfilled from `bookings.created_at` —
-- the very witness §0c rejects as party-writable — and no pin could reach it (the harness applies
-- every migration before any suite writes a failure row, so it always ran on an empty table).

-- 0227's seal, restated (a column add does not move it; said so the VERIFY below can hold it)
alter table recurring_generation_failures enable row level security;
revoke all on table recurring_generation_failures from public, anon, authenticated;
grant select, insert, update, delete on table recurring_generation_failures to service_role;

comment on table recurring_generation_failures is
  '0227 + 0237: one row per recurring series that has failed a generate_recurring_bookings tick — the last
SQLSTATE and message (SQLERRM, 500 chars, never DETAIL), a lifetime attempt count, first and last
failure time; and since 0237 the current failure EPISODE: episode_failures (failed ticks since it began),
episode_started_at, escalated_at (when this episode rang the recurring_generation_failed roster; NULL =
not yet). A failure advances the episode only when it is costing a booking (the occurrence was never
named, or the series holds no booking on its date). The generator''s failure handler writes the row; _recurring_failure_escalate stamps
escalated_at; a MINT of the series resets the episode (0237 §E ③). A 55P03 row can also mean an
overlapping tick held that dog (0227 §0d ②). Server-only: RLS on, no policies, no client privilege.
258 0227-V1/V2/S1 and 268 0237-E1…E9 pin it.';
comment on column recurring_generation_failures.episode_failures is
  '0237: failed ticks in the current episode that were costing a booking (a failure on a tick whose occurrence is already booked is recorded but not counted). Rings at 3 (_recurring_failure_escalate c_ring_at). Reset to 0 when the generator mints a booking for the series.';
comment on column recurring_generation_failures.escalated_at is
  '0237: the instant this episode rang the recurring_generation_failed roster (at least one row written). NULL = not rung. The ring''s one-shot key — server-only, so no client can forge it (268 0237-E6).';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B _noti_ops_titles — 0234 §A's ledger, plus the recurring-failure ring
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function _noti_ops_titles() returns text[]
language sql immutable as $$
  -- Derived from the writers, NEVER hand-listed (§0①). One entry per DISTINCT title; the two
  -- sites that share 「인계 확인 멈춤」 are one entry.
  select array[
    -- ── SQL writers, latest declaration of each function ──
    '지급 대기 — 확인 필요',                                 -- ops_payouts_stuck_sweep      0210:417
    '인계 확인 멈춤 — 확인 필요',                             -- sweep_run_end_recovery       0201:928/976
    '반환 좌초 — 확인 필요',                                 -- sweep_run_end_recovery       0201:768
    '굿즈 수령 신청 — 확인 필요',                             -- claim_gear_tx                §B below
    '카드 해지 실패 — 확인 필요',                             -- _note_revocation_abandoned   0166:166
    '클럽 취소 수수료 인텐트 실패 — 확인 필요',                 -- _club_note_fee_mint_failure  0118:674
    -- ── edge writers, all five through `notifyOps` (_shared/ops.ts:163 sets kind:"system") ──
    '결제 자동 취소 실패 — 수동 취소 필요',                     -- COPY.payment_manual_cancel   ops.ts:65
    '이동 중 취소 보상 기록 실패 — 수동 확인 필요',              -- COPY.enroute_comp_failed     ops.ts:69
    '결제 취소 실패 기록이 남지 않았어요 — 즉시 확인 필요',       -- COPY.payment_marker_lost     ops.ts:79
    '취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요',    -- COPY.late_comp_failed        ops.ts:84
    '운영 확인이 필요한 이벤트가 있어요',                        -- generic()                    ops.ts:124
    -- ── [0224] three more SQL writers ──
    '러닝 시작 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '러닝 종료 좌초 — 확인 필요',                             -- _sweep_custody_strands       0224 §C
    '정산 미완료 — 확인 필요',                                -- sweep_run_end_recovery ⓐ     0224 §D
    -- ── [0233] one more SQL writer ──
    '러닝 전 사고 검토 — 확인 필요',                          -- _sweep_prerun_incidents      0233 §C
    -- ── [0234] the incident_opened bell, one title per severity ──
    '사고 접수 — 확인 필요',                                 -- open_incident_tx (normal)    0234 §B
    '긴급 사고 접수 — 확인 필요',                             -- open_incident_tx (urgent)    0234 §B
    'SOS 사고 접수 — 즉시 확인 필요',                          -- open_incident_tx (sos)       0234 §B
    -- ── [0237] the recurring generator's failure-episode ring ──
    '반복 예약 생성 실패 — 확인 필요'                           -- _recurring_failure_escalate  0237 §D
  ]::text[]
$$;

revoke execute on function _noti_ops_titles() from public, anon, authenticated;

comment on function _noti_ops_titles is
  '0214 §A + 0224 §G + 0233 §E + 0234 §A + 0237 §B: every title written with kind=''system'' — nineteen at
0237 (the recurring generator''s failure-episode ring added). Consulted by _noti_push_category: a system
row whose title is here is the ''ops'' category (disableable by notification_prefs.ops). Adding a
system writer means adding its title HERE, in a new re-declaration. Pinned by 245 0214-T1/T2/T4,
264 0233-B2, 265 0234-B2, 268 0237-B1 and app/test/ops-system-titles.test.cjs.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C ops_roster_set — `recurring_generation_failed` joins the UI allowlist (catalog patch)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0234 §C's method, for 0216 §A's reason: this body was last written FROM THE CATALOG, so no migration
-- file holds its current text. Every inherited landing is asserted before the copy (0234's class
-- included); the one anchor is asserted to occur exactly once; the new class is asserted present after.
do $mig$
declare
  v_src  text;
  v_new  text;
  v_a    text;
  v_repl text;
  v_n    int;
begin
  select p.prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'ops_roster_set';
  if v_src is null then raise exception '0237 §C: ops_roster_set not found — refusing to guess'; end if;
  if position('''recurring_generation_failed''' in v_src) > 0 then
    raise exception '0237 §C: ops_roster_set already names recurring_generation_failed — applied twice, or something else landed it; find out which';
  end if;
  -- inherited landings
  if position('pg_advisory_xact_lock(hashtextextended(''ops_roster'', 0))' in v_src) = 0 then
    raise exception '0237 §C: 0216 §A''s roster key is not in the live body — do not copy this';
  end if;
  if position('on conflict on constraint ops_recipients_pkey' in v_src) = 0 then
    raise exception '0237 §C: 0208 §C''s upsert-by-constraint is not in the live body';
  end if;
  if position('insert into ops_roster_changes' in v_src) = 0 then
    raise exception '0237 §C: 0208 §A''s journal write is not in the live body';
  end if;
  if position('raise exception ''last_operator''' in v_src) = 0 then
    raise exception '0237 §C: 0208 §C''s last-operator guard is not in the live body';
  end if;
  if position('''incident_opened''' in v_src) = 0 then
    raise exception '0237 §C: 0234 §C''s incident_opened is not in the live body';
  end if;

  -- the one anchor: 0234's last entry and the closing bracket
  v_a := $a$    'incident_opened'
  ];$a$;
  v_repl := $a$    'incident_opened',
    -- ── [0237 §C] SQL emitter: the recurring generator failure ring (0237 §D) ──
    'recurring_generation_failed'
  ];$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0237 §C: the allowlist anchor occurs % time(s) in ops_roster_set, expected exactly 1 — patch by hand', v_n;
  end if;
  v_new := replace(v_src, v_a, v_repl);
  if v_new = v_src or position('''recurring_generation_failed''' in v_new) = 0 then
    raise exception '0237 §C: patch did not apply';
  end if;

  -- the declaration is 0208:231-234's (and 0216's, 0234's), verbatim
  execute format(
    'create or replace function ops_roster_set(p_profile uuid, p_event_class text, p_active boolean) returns table (profile_id uuid, event_class text, active boolean, changed boolean) language plpgsql security definer set search_path = public, pg_temp as %L',
    v_new);

  execute format('comment on function ops_roster_set(uuid, text, boolean) is %L',
    coalesce((select obj_description(p.oid, 'pg_proc') from pg_proc p
               join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
              where p.proname = 'ops_roster_set'), '')
    || chr(10) || '[0237 §C] recurring_generation_failed joins the class allowlist (the emitter is '
    || '_recurring_failure_escalate, called by generate_recurring_bookings). Signature, returns, gate '
    || 'order and tokens unchanged.');
end $mig$;

-- 0234:303-304 verbatim — never rely on grant preservation
revoke execute on function ops_roster_set(uuid, text, boolean) from public, anon;
grant  execute on function ops_roster_set(uuid, text, boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D _recurring_failure_escalate — one ring per failure episode
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Called ONLY from generate_recurring_bookings' failure handler, inside its own subtransaction (§E ②),
-- right after the failure row was upserted in the same transaction. Returns the number of recipients
-- rung (0 = nothing to do, or nobody seated).
-- ⚠ The ops row carries NO identifier and NO amount (0084 §E: a wrong recipient pushes the body to a
--   stranger's lock screen); the series rides in `ref_id`. Title and body are CONSTANTS, so
--   `app/test/ops-system-titles.test.cjs` resolves the title to a literal and the roster test's emitter
--   scan finds `c_ops_class`.
-- ⚠ THE KEY IS `escalated_at` (§0d) — no notifications row is read, so none can be forged into a
--   「it already rang」. The condition is asked as ONE boolean with `is not true`, so a NULL anywhere in
--   it (NOT NULL columns today) fails CLOSED to 「do not ring twice」 rather than silently past a bare IF.
-- ⚠ `escalated_at` is stamped ONLY when a row was written: an empty roster pages nobody and the next
--   failing tick of the same episode tries again (0233 arm ⓗ's rule).
create or replace function _recurring_failure_escalate(p_series uuid) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_ring_at   constant int  := 3;   -- §0c: the episode's THIRD failed tick rings
  c_ops_class constant text := 'recurring_generation_failed';
  c_ops_title constant text := '반복 예약 생성 실패 — 확인 필요';
  c_ops_body  constant text := '반복 예약 하나가 생성 중 여러 번 실패했어요 — 서버 기록(recurring_generation_failures)의 error_code로 원인을 확인해 주세요. 55P03은 다른 작업과의 잠금 경합이에요.';
  v_f   record;
  v_ops int;
begin
  select f.episode_failures, f.escalated_at into v_f
    from recurring_generation_failures f
   where f.series_id = p_series
   for update;
  if not found then return 0; end if;
  if (v_f.escalated_at is null and v_f.episode_failures >= c_ring_at) is not true then return 0; end if;

  insert into notifications (profile_id, kind, title, body, ref_id)
  select rc.profile_id, 'system'::noti_kind, c_ops_title, c_ops_body, p_series
    from ops_recipients_for(c_ops_class) as rc(profile_id);
  get diagnostics v_ops = row_count;

  if v_ops > 0 then
    update recurring_generation_failures set escalated_at = now() where series_id = p_series;
    raise warning '_recurring_failure_escalate: recurring_series % — failure episode rang % recipient(s) of %',
      p_series, v_ops, c_ops_class;
  else
    -- a WARNING, not a NOTICE: with the default log_min_messages a NOTICE in a pg_cron tick reaches no
    -- log (0227 §0c), and this line is the only trace of a page nobody got
    raise warning '_recurring_failure_escalate: recurring_series % — failure episode due to ring but the % roster is empty; nobody was paged, retried on its next failing tick',
      p_series, c_ops_class;
  end if;
  return v_ops;
end $$;

revoke execute on function _recurring_failure_escalate(uuid) from public, anon, authenticated;
grant  execute on function _recurring_failure_escalate(uuid) to service_role;

comment on function _recurring_failure_escalate is
  '0237 §D: rings the recurring_generation_failed roster ONCE per failure episode of a recurring series —
when recurring_generation_failures.episode_failures reaches 3 and escalated_at is NULL. One system row per
recipient (「반복 예약 생성 실패 — 확인 필요」, identifier-free body, ref_id = the series); escalated_at is
stamped only when a row was written (empty roster ⇒ retried on the next failing tick). The one-shot key
is escalated_at — server-only, never a notifications read, so no client can forge it. Called only from
generate_recurring_bookings'' failure handler in its own subtransaction. Server-only. 268 0237-E1…E9 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E generate_recurring_bookings — the episode counted, the ring isolated, a mint resets it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0232 §D's body, built BY SCRIPT: the four edits in §0b, every other line 0232's byte for byte.
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
  v_live boolean;              -- [0080] cutover switch, read once per sweep
  v_block text;                -- [0080] null | 'debt' | 'no_card'
  v_notified uuid[] := '{}';   -- [0080] owners already told this sweep (ⓓ)
  v_fail_state text;          -- [0227] the SQLSTATE a failed series raised …
  v_fail_msg text;            -- [0227] … and its message
  v_nid uuid;                 -- [0232] the notice just written (its episode row keys on it)
  v_debt uuid[];              -- [0232] the owner's debt charges NOW (a pause's episode)
  v_owed boolean;             -- [0237] a failure this tick counts toward the episode (§E ④)
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  -- [0180] the bounded wait (0117 MINOR-14's other half, late_booking_sweep's value): the dog
  -- locks below can WAIT, and a sweep stalled on one holds every lock it already took. Past 2 s
  -- the statement raises, this transaction and its locks release, and the next tick retries.
  perform set_config('lock_timeout', '2000', true);

  -- [0180] deterministic candidate order: two overlapping ticks take the dog locks below in the
  -- same sequence, so they queue instead of deadlocking (0117 MINOR-14's lesson, applied here).
  for s in select * from recurring_series where not paused and dog_id is not null
           order by dog_id, id loop
    -- [0227] EACH SERIES IN ITS OWN SUBTRANSACTION — the Codex s1 shape (0226 §0d ③ named it here).
    -- Until 0227 one series whose write raised — a row held past the 2 s lock_timeout above, or any
    -- other fault — raised out of the WHOLE function: every other owner's booking in the tick went
    -- unminted, every notice already written rolled back, and the next tick met the same series
    -- again, so nothing resolved it (258 `0227-R1`/`R2`, reproduced on 0226's body). Everything one
    -- series writes — its booking, 「반복 러닝 예약 생성」, 「지명 러닝 요청」, the pause notice —
    -- commits or rolls back TOGETHER, so a booking never outlives the notice that announces it
    -- (`0227-R3`). Inside this block the body is 0226's byte for byte, one indent deeper.
    begin
      -- [0237 §E ④a] this series' occurrence is unknown until computed below — a failure before that
      -- line must not read the PREVIOUS series' v_sched (plpgsql variables survive the rollback).
      v_sched := null;
      v_dow := (s.rule->'weekdays'->>0)::int;
      v_time := s.rule->>'time';
      if v_dow is null or v_time is null then continue; end if;

      -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
      v_kst_now := now() at time zone 'Asia/Seoul';
      v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
      v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
      if v_sched < now() + interval '2 hours' then
        v_sched := v_sched + interval '7 days';
      end if;
      if v_sched > now() + interval '72 hours' then continue; end if;

      -- [0180] THE DOG LOCK — the same key text `create_booking_hold_tx` (0179) takes, so this sweep
      -- and an edge hold for the same dog SERIALIZE: whichever runs second sees the first's committed
      -- row in the clash guard below. Transaction-scoped and held to COMMIT on purpose — releasing it
      -- early (a session lock unlocked in an exception arm, 0117's job-lock shape) would let an edge
      -- hold take the lock, read a snapshot with this sweep's row still uncommitted, and pass: the
      -- exact race this lock exists to close. Taken only for a series with something due (after the
      -- 72h gate), before any read of this dog's bookings. The edge takes key-lock then dog-lock; this
      -- sweep takes only dog locks, in `order by dog_id` sequence, so no lock cycle is possible.
      perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || s.dog_id::text, 0));

      -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
      if exists (
        select 1 from bookings
        where series_id = s.id
          and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
      ) then continue; end if;

      v_start := v_sched;
      v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

      -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
      select exists (
        select 1 from bookings c
        where c.dog_id = s.dog_id
          and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
          and c.scheduled_at < v_end
          and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
      ) into v_clash;
      if v_clash then continue; end if;

      -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
      v_runner := null;
      select b2.runner_id into v_runner from bookings b2
      where b2.series_id = s.id and b2.runner_id is not null
        and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
      order by b2.scheduled_at desc limit 1;
      if v_runner is not null then
        begin
          select is_slot_available(v_runner, v_start, v_end) into v_avail;
        exception when others then
          v_avail := false;
        end;
        if not coalesce(v_avail, false) then v_runner := null; end if;
      end if;

      -- ⓑ/ⓒ [0080 §0-ter #3] money gates — the last thing before the insert.
      v_block := null;
      if owner_has_unsettled_charge(s.owner_id) then
        v_block := 'debt';
      elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = s.owner_id) then
        v_block := 'no_card';
      end if;
      if v_block is not null then
        -- [0232 §C] the charges that make this owner a debtor NOW. Written onto the notice's
        -- episode row below, and compared against every earlier notice's row in the guard.
        v_debt := _unsettled_charge_ids(s.owner_id);
        -- ⓓ once per owner per sweep (v_notified) — [0224 §H] AND at most once per 24 h per owner
        -- per EPISODE: an earlier pause notice counts only while no booking of this owner's series
        -- has been created since it (the owner fixed it, it resumed, it broke again ⇒ tell them).
        -- [0226 §C] …AND, for a DEBT block, only while a charge that already existed when that notice
        -- was written is STILL unsettled. A generated booking proves an unblocked tick; it is not the
        -- only way an episode ends — paid and re-incurred between two hourly ticks leaves no booking
        -- (codex s3, measured by 257 `0226-C2`). A `failed` charge stays `failed` through every retry
        -- until it is paid, so an old charge still unpaid means the debt never ended. A card-less
        -- block has no debt to witness and keeps 0224's rule (`0226-C4`).
        if not (s.owner_id = any(v_notified))
           and not exists (
             select 1 from notifications nt
              where nt.profile_id = s.owner_id
                and nt.title = '반복 예약 일시 중지'
                and nt.created_at > now() - interval '24 hours'
                and not exists (select 1 from bookings gb
                                  join recurring_series gs on gs.id = gb.series_id
                                 where gs.owner_id = s.owner_id
                                   and gb.created_at > nt.created_at)
                -- [0232 §C] …for a DEBT block, only while a charge that WAS DEBT when that notice
                -- went out (its episode row, extended by every tick that saw the debt continue) is
                -- STILL debt. 0226 asked 「existed then, debt now」 — so a charge that was a fresh
                -- pending at the notice and became debt after the old debt was paid suppressed the
                -- new pause (codex s2). A notice with no episode row predates 0232 and keeps
                -- 0226's witness (it ages out of the 24 h window by itself).
                and (v_block is distinct from 'debt'
                     or case when exists (select 1 from recurring_pause_notices pn
                                           where pn.notice_id = nt.id)
                             then exists (select 1 from recurring_pause_notices pn
                                           where pn.notice_id = nt.id
                                             and pn.debt_payment_ids && v_debt)
                             else _unsettled_charge_through(s.owner_id, nt.created_at) end)) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (s.owner_id, 'booking', '반복 예약 일시 중지',
                  '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null)
          returning id into v_nid;
          -- [0232 §C] the episode this notice announced: which block, and — for debt — exactly
          -- which charges were debt when it went out.
          insert into recurring_pause_notices (notice_id, series_id, reason, debt_payment_ids)
          values (v_nid, s.id, v_block, coalesce(v_debt, '{}'));
          v_notified := v_notified || s.owner_id;
        end if;
        -- [0232 §C] CONTINUITY, observed. A tick that finds the owner still in debt adds today's
        -- debt charges to every live notice whose charges are still debt — the episode did not
        -- end, it gained a charge. Without this, paying the ORIGINAL charge while a later one is
        -- still unpaid would read as a new episode and re-tell a pause that never lifted.
        if v_block = 'debt' and cardinality(v_debt) > 0 then
          update recurring_pause_notices pn
             set debt_payment_ids = array(select distinct x from unnest(pn.debt_payment_ids || v_debt) x order by x)
           where pn.debt_payment_ids && v_debt
             and not (pn.debt_payment_ids @> v_debt)
             and pn.notice_id in (select nt.id from notifications nt
                                   where nt.profile_id = s.owner_id
                                     and nt.title = '반복 예약 일시 중지'
                                     and nt.created_at > now() - interval '24 hours');
        end if;
        continue;
      end if;

      -- ⓔ [0111] the series row is a snapshot, and a snapshot can go stale or (before this
      -- migration) be FORGED. Ownership is re-asked at copy time, not trusted from write time.
      -- A silent `continue` would make a skipped series indistinguishable from a series with
      -- nothing due, so say so in the log first — this warning is the ONLY signal that the second
      -- belt fired at all. `continue`, never `raise`: see this file's §3 header.
      if not exists (select 1 from dogs d where d.id = s.dog_id and d.owner_id = s.owner_id)
         or (s.address_id is not null
             and not exists (select 1 from addresses a where a.id = s.address_id and a.owner_id = s.owner_id))
      then
        raise warning 'recurring_series % skipped: dog/address not owned by series owner', s.id;
        continue;
      end if;

      -- [0232 §B] THE ROUTE GATE — create-booking-hold/handler.ts refuses a suspended or retired
      -- course (「이 코스는 지금 예약할 수 없어요」), and this generator copied `s.route_id` without
      -- ever reading it, so an operator's suspension stopped new holds and not the weekly copy.
      -- Nothing is minted; the owner is told once per series per 24 h per episode (0226's
      -- recurring-pause shape: an earlier notice stops counting once this series produced a
      -- booking after it — the course came back and went away again ⇒ tell them again).
      if s.route_id is not null
         and exists (select 1 from routes rt
                      where rt.id = s.route_id and rt.status in ('suspended', 'retired')) then
        if not exists (
             select 1 from recurring_pause_notices pn
               join notifications nt on nt.id = pn.notice_id
              where pn.series_id = s.id
                and pn.reason = 'route'
                and nt.created_at > now() - interval '24 hours'
                and not exists (select 1 from bookings gb
                                 where gb.series_id = s.id
                                   and gb.created_at > nt.created_at)) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (s.owner_id, 'booking', '반복 예약 코스 점검 중',
                  '반복 예약 코스가 점검 중이라 이번 주 러닝을 만들지 않았어요 — 다른 코스로 바꿔 예약해주세요', null)
          returning id into v_nid;
          insert into recurring_pause_notices (notice_id, series_id, reason)
          values (v_nid, s.id, 'route');
        end if;
        continue;
      end if;

      insert into bookings
        (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
         km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
      values
        (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
         (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
         v_sched, s.km, s.pace_label, s.addons,
         s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
      returning id into v_bid;

      insert into notifications (profile_id, kind, title, body, ref_id)
      values (s.owner_id, 'booking', '반복 러닝 예약 생성',
              to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
              || ' 러닝이 자동 예약됐어요'
              || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
              v_bid);
      if v_runner is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_runner, 'booking', '지명 러닝 요청',
                '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
      end if;

      n := n + 1;

      -- [0237 §E ③] RECOVERY — this series was MINTED, so any failure episode it was in is over: the
      -- next failure starts a new one, which rings again (268 `0237-E3`). The generator's own
      -- observation is the witness (0237 §0c: `bookings.created_at` is party-writable). ITS OWN
      -- subtransaction: a raise here is a WARNING and the booking and its notices stand (`0237-E5`).
      -- Runs once per MINT (≈ once per series per week), never on a tick that minted nothing.
      begin
        update recurring_generation_failures
           set episode_failures = 0, episode_started_at = null, escalated_at = null
         where series_id = s.id
           and (episode_failures > 0 or escalated_at is not null);
      exception when others then
        raise warning 'generate_recurring_bookings: recurring_series % — minted, but its failure episode could not be reset (% %); the booking stands',
          s.id, sqlstate, sqlerrm;
      end;
    exception when others then
      -- [0227] this series' writes are already rolled back; say so, record it, move to the next.
      -- Its dog lock, if it was taken inside this block, is released with the block — safe, because
      -- nothing it guarded was written (0180's race needs this sweep's row to EXIST). A lock an
      -- earlier series of the same dog took belongs to the enclosing transaction and stays to commit.
      v_fail_state := sqlstate;
      v_fail_msg := sqlerrm;
      raise warning 'generate_recurring_bookings: recurring_series % failed (% %) — nothing of it was written this tick; retried next tick',
        s.id, v_fail_state, v_fail_msg;
      -- The record is its OWN subtransaction: a raise inside a handler is not caught by that handler,
      -- so a failing record write would abort the very tick this block exists to save (`0227-V2`).
      begin
        -- [0237 §E ①] …and counts the failure EPISODE: a first failure (or the first after a mint
        -- reset it to 0) starts one; every further failed tick adds one. `_recurring_failure_escalate`
        -- reads the count below. 268 `0237-E1`/`E3`.
        -- [0237 §E ④b] …but ONLY a failure that is costing a booking counts: if this tick got as far
        -- as naming the occurrence (v_sched) and the series already HOLDS its booking for that KST
        -- date, nothing is being lost — the tick had nothing to mint. Such a failure is still recorded
        -- (lifetime `attempts`, `error_code`) and does not advance the episode. Without this, the ~70
        -- hourly ticks after every mint that still queue on the dog lock turned lock contention (an
        -- overlapping manual call, a long edge hold → 55P03) into a page (exec review 2026-09-26,
        -- measured with two sessions: three such ticks rang for a series holding its booking).
        -- An occurrence never named (a malformed rule — v_sched NULL, §E ④a) always counts: errs
        -- toward telling. 268 `0237-E9`.
        v_owed := v_sched is null
                  or not exists (select 1 from bookings b
                                  where b.series_id = s.id
                                    and (b.scheduled_at at time zone 'Asia/Seoul')::date
                                        = (v_sched at time zone 'Asia/Seoul')::date);
        insert into recurring_generation_failures as f
          (series_id, error_code, error_message, episode_failures, episode_started_at)
        values (s.id, v_fail_state, left(coalesce(v_fail_msg, ''), 500),
                case when v_owed then 1 else 0 end, case when v_owed then now() end)
        on conflict (series_id) do update
          set error_code         = excluded.error_code,
              error_message      = excluded.error_message,
              attempts           = f.attempts + 1,
              last_failed_at     = now(),
              episode_failures   = f.episode_failures + case when v_owed then 1 else 0 end,
              episode_started_at = case when v_owed then coalesce(f.episode_started_at, now())
                                        else f.episode_started_at end;
      exception when others then
        raise warning 'generate_recurring_bookings: recurring_series % — its failure record could not be written (% %); the warning above is the only trace',
          s.id, sqlstate, sqlerrm;
      end;
      -- [0237 §E ②] THE ESCALATION, in ITS OWN subtransaction — after the record's block, never inside
      -- it: a raise in the ring must cost neither the failure record nor the tick (a raise inside a
      -- handler is not caught by that handler — 0210 §E's reason, 0227-V2's shape). One ring per
      -- failure EPISODE, at its third failed tick, keyed on the server-only `escalated_at` (0237 §0c/§0d).
      -- A failed ring is a WARNING and stamps nothing, so the next failing tick rings (268 `0237-E4`).
      begin
        perform _recurring_failure_escalate(s.id);
      exception when others then
        raise warning 'generate_recurring_bookings: recurring_series % — its ops escalation could not be written (% %); the failure record stands and the next failing tick retries the ring',
          s.id, sqlstate, sqlerrm;
      end;
    end;
  end loop;
  return n;
end $$;

-- 0232's ACL, restated verbatim — never rely on grant preservation (0116:636; check-definer-acl).
revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘 + [0111] 복사 시점 소유권 재확인 + [0180] 강아지별 xact 락 —
+ [0224 §H] the pause notice (「반복 예약 일시 중지」) is sent at most once per 24 h per owner per episode
+ [0226 §C] and an episode ends when the series produces a booking again OR — for a debt block — when
every charge that existed at the last notice has been paid (the witness is _unsettled_charge_through).
Title, body and NULL ref unchanged. 255 0224-C1 and 257 0226-C2/C3/C4 pin it.
+ [0227] each series runs in its own subtransaction: a series whose write raises writes nothing that
tick, raises a WARNING naming it and is recorded in recurring_generation_failures, is retried next
tick, and touches no other series. 258 0227-R1/R2/R3/V1/V2/G1 pin it.
+ [0232] a debt pause''s episode is RECORDED (recurring_pause_notices: the charges that were debt when
the notice went out, extended while the debt continues) and a notice counts only while one of them
is still debt — 0226''s witness remains for notices older than 0232. And a series on a suspended or
retired course mints nothing and tells its owner 「반복 예약 코스 점검 중」 once per series per 24 h per
episode. 263 0232-B1…B4/D1…D3 pin it.
+ [0237] a failure that is costing a booking also counts the failure EPISODE of the series
(recurring_generation_failures.episode_failures — a failure on a tick whose occurrence is already booked
is recorded, not counted);
at its third failed tick _recurring_failure_escalate rings the recurring_generation_failed roster ONCE
(「반복 예약 생성 실패 — 확인 필요」, ref = the series), in its own subtransaction; a MINT of the series
resets the episode, in its own subtransaction. No owner-facing copy. 268 0237-E1…E9 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time SHAPE only (behaviour is suite 268's — 0131-G4's lesson). Source arms read
-- COMMENT-STRIPPED prosrc: this file explains every edit at length inside the bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  fn text;
  v_src text;
  v_role text;
  v_priv text;
  c text;
begin
  foreach fn in array array['generate_recurring_bookings()', '_recurring_failure_escalate(uuid)',
                            'ops_roster_set(uuid,text,boolean)'] loop
    if to_regprocedure('public.' || fn) is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || fn)
                    and p.prosecdef and 'search_path=public, pg_temp' = any(coalesce(p.proconfig, '{}')))
      then v_bad := v_bad || ' ' || fn || ': not a definer with the in-body search_path;'; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': anon can execute;'; end if;
  end loop;
  foreach fn in array array['generate_recurring_bookings()', '_recurring_failure_escalate(uuid)'] loop
    if to_regprocedure('public.' || fn) is not null
       and has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': authenticated can execute (server-only);'; end if;
  end loop;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.generate_recurring_bookings()');
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings);';
  else
    if (v_src like '%episode_failures   = f.episode_failures + case when v_owed then 1 else 0 end%') is not true
      then v_bad := v_bad || ' generator: the failure upsert does not count the episode;'; end if;
    if (v_src like '%perform _recurring_failure_escalate(s.id);%') is not true
      then v_bad := v_bad || ' generator: the escalation is not called;'; end if;
    if (position('perform _recurring_failure_escalate(s.id);' in v_src)
        > position('insert into recurring_generation_failures' in v_src)) is not true
      then v_bad := v_bad || ' generator: the escalation does not follow the failure record;'; end if;
    if (v_src like '%set episode_failures = 0, episode_started_at = null, escalated_at = null%') is not true
      then v_bad := v_bad || ' generator: no recovery reset;'; end if;
    if (position('set episode_failures = 0' in v_src) > position('n := n + 1;' in v_src)) is not true
      then v_bad := v_bad || ' generator: the recovery reset does not follow the mint;'; end if;
    -- the landings this file must not have lost (0227, 0232)
    if (v_src like '%rt.status in (''suspended'', ''retired'')%') is not true
      then v_bad := v_bad || ' generator: 0232''s route gate is gone;'; end if;
    if (v_src like '%and pn.debt_payment_ids && v_debt)%') is not true
      then v_bad := v_bad || ' generator: 0232''s debt episode dedupe is gone;'; end if;
  end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public._recurring_failure_escalate(uuid)');
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(_recurring_failure_escalate);'; end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.ops_roster_set(uuid,text,boolean)');
  if (position('''recurring_generation_failed''' in coalesce(v_src, '')) > 0) is not true
    then v_bad := v_bad || ' ops_roster_set: the class is not in the allowlist;'; end if;

  if ('반복 예약 생성 실패 — 확인 필요' = any (_noti_ops_titles())) is not true
    then v_bad := v_bad || ' the ring title is not ledgered;'; end if;
  if array_length(_noti_ops_titles(), 1) is distinct from 19
    then v_bad := v_bad || ' the ledger holds ' || coalesce(array_length(_noti_ops_titles(), 1)::text, 'NULL') || ' titles (19 expected);'; end if;

  foreach c in array array['episode_failures', 'episode_started_at', 'escalated_at'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'recurring_generation_failures' and column_name = c)
      then v_bad := v_bad || ' NO-COLUMN(' || c || ');'; end if;
  end loop;
  if (select c2.relrowsecurity from pg_class c2 where c2.oid = 'public.recurring_generation_failures'::regclass) is not true
    then v_bad := v_bad || ' recurring_generation_failures: RLS off;'; end if;
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege(v_role, 'public.recurring_generation_failures', v_priv)
        then v_bad := v_bad || ' recurring_generation_failures: ' || v_role || ' holds ' || v_priv || ';'; end if;
    end loop;
  end loop;

  if v_bad <> '' then raise exception '0237 VERIFY failed:%', v_bad; end if;
  raise notice '0237 VERIFY ok — the episode is counted, the ring is its own definer and subtransaction, a mint resets it, the class is seatable and the title ledgered; the record stays sealed';
end $$;
