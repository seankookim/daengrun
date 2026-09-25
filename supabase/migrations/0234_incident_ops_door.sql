-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0234 — a reported incident finally reaches an operator: the `incident_opened` class, its bell on
--        `open_incident_tx`, and the roster's read of every open incident
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 265_incident_ops_door_suite.sql (tag `iod`) — 0234-I1 · I2 · I3 · B2 · C1 · L1 · L2 · S1
-- Gap sweep 2 P5 · M2 (docs/reviews/2026-09-25-gap-sweep-2-final.md §P5). Stacks on 0233 (M1).
--
-- ═══ §0a WHAT IS WRONG, READ ON `cloud/0232-sweep-honesty-route-gate` @ 54dfae7 ═══════════════════
--   (3) A marketplace incident is opened through `open_incident_tx` (0114:311, its latest
--       declaration; the client's `openBookingIncident`, api.ts). It inserts the `incidents` row and
--       returns — the ONLY notification is the client's own row to the COUNTERPARTY
--       (「사고 신고 접수」, api.ts). No operator is told, no ops event class exists for it (0208's
--       `c_classes`, `_shared/ops.ts:36-51`), and no ops read lists open incidents. An SOS reported
--       at 2 a.m. is known to the two people already in it and to nobody whose job it is.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `_noti_ops_titles()` — 0233 §E's ledger plus three titles, one per SEVERITY (18). Severity is
--      IN THE TITLE because the title is what a lock screen shows: an operator must be able to tell
--      an SOS from a scraped knee without opening the app.
--   §B `open_incident_tx` — 0114 §3's text, copied BY SCRIPT, ONE insertion after the insert ⑦:
--      the `incident_opened` roster is told ONCE, by a constant title per severity, with an
--      identifier-free body and `ref_id` = the INCIDENT id (the new row — not the booking: a booking
--      can carry a second incident after the first resolves, and the desk's `notified_at` must
--      belong to the incident it describes). ⚠ The bell runs in its OWN subtransaction: a failing
--      bell is a NOTICE and the report STANDS — an emergency report must never be refused because a
--      notification could not be written. The idempotent-return path (⑤: an open incident already
--      exists) rings NOTHING — it is not a new incident, and a double-tap must not page twice.
--   §C `ops_roster_set` — patched FROM THE CATALOG (0216 §A's discipline: its live body exists in no
--      file), ONE edit: `incident_opened` joins `c_classes`, so an operator can be seated at the new
--      desk from the product. Every inherited landing (0216's key, 0208's upsert and journal) is
--      asserted before the copy is taken.
--   §D `ops_open_incidents()` — the `incident_opened` roster's read: every incident with
--      `resolved_at is null`, SOS first. Zero arguments, roster gate FIRST, flat whitelisted columns;
--      NO note, NO media (free text a reporter typed under stress is not an ops-list column — the
--      incident's own screens own it), no money, no contact field.
--
-- ═══ §0c WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
--   · **NO resolve/close door for incidents** (§P5 DO NOT BUILD, letters L2/L3). The desk is a READ.
--   · An EMPTY `incident_opened` roster at the instant of the report means nobody is paged, and
--     nothing retries: this is an EVENT bell, not a sweep. The incident is still on §D's list for
--     whoever is seated later, and the list's `notified_at` is NULL for it — said, not hidden.
--   · The client's counterparty row (「사고 신고 접수」, always-on by 0189's urgent family) is
--     unchanged; the ops titles are distinct strings and are NOT urgent — they file as `ops`, which
--     an operator can switch off on their phone (the console still shows them). That is the
--     category every other ops title has; making an ops title undisableable is Sean's call.
--   · `_shared/ops.ts`'s `OpsEventClass` union is not touched: the emitter is SQL, like
--     `return_strand` or `handoff_unanswered`, and `notifyOps` never sends this class.
--   · `my_booking_payment_state`, `confirm_return_tx`, `work-gate-strip.ts` — untouched.
--
-- ═══ §0d WHOSE OBJECTS THIS BUILDS ON ════════════════════════════════════════════════════════
--   RE-DECLARES `_noti_ops_titles()` ←0233 §E (copied by script, +3), `open_incident_tx(uuid,text,
--   text,text,text[])` ←0114 §3 (copied by script, one insertion), `ops_roster_set(uuid,text,boolean)`
--   ←the catalog (0208 §C + 0216 §A; one array entry). CREATES `ops_open_incidents()`. Every ACL
--   restated in THIS file.
--
-- ═══ §0e SHIPPED PINS / FILES THAT MOVE ══════════════════════════════════════════════════════
--   · `245 0214-T1/T4` (18 titles; `open_incident_tx` joins SYSTEM_WRITERS) — see 0233 §0e.
--   · `239`'s second copy of `c_classes` gains `incident_opened` (its own NAMED GAP ④ says the pin
--     is that the two copies AGREE); `app/src/lib/ops-roster.ts` gains the chip and
--     `app/test/ops-roster.test.cjs`'s SERVER_CLASSES the class (the key set is pinned both ways).
--
-- ═══ §0f DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   `supabase db push` (with 0233), then seat at least one operator at `incident_opened` from the
--   console's 운영자 명단 — until then the bell writes nothing (and says so in its notice).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A _noti_ops_titles — 0233 §E's ledger, plus the three incident titles
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
    'SOS 사고 접수 — 즉시 확인 필요'                           -- open_incident_tx (sos)       0234 §B
  ]::text[]
$$;

revoke execute on function _noti_ops_titles() from public, anon, authenticated;

comment on function _noti_ops_titles is
  '0214 §A + 0224 §G + 0233 §E + 0234 §A: every title written with kind=''system'' — eighteen at 0234
(the three incident_opened bells, one per severity, added). Consulted by _noti_push_category: a system
row whose title is here is the ''ops'' category (disableable by notification_prefs.ops). Adding a
system writer means adding its title HERE, in a new re-declaration. Pinned by 245 0214-T1/T2/T4,
264 0233-B2, 265 0234-B2 and app/test/ops-system-titles.test.cjs.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B open_incident_tx — the report now reaches the incident_opened roster, once
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0114 §3's text, copied BY SCRIPT; the only change is the marked block ⑧ after the insert and the
-- constants it reads. Gate order unchanged: signed-in → for-update fetch → PARTY → arguments →
-- idempotent return → STATE → insert → ⑧ bell. The bell is AFTER every gate, so a refused call
-- (not_party, bad_kind, booking_not_reportable) and the idempotent return ring nothing.
create or replace function open_incident_tx(
  p_booking  uuid,
  p_kind     text,
  p_severity text default 'normal',
  p_note     text default null,
  p_media    text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_uid uuid := auth.uid(); v_id uuid;
  -- [0234 §B] the incident_opened bell. One CONSTANT title per severity (the lock screen shows the
  -- title; `app/test/ops-system-titles.test.cjs` resolves each to a literal). NO id, NO amount, NO
  -- note in the body (0084 §E: a wrong recipient pushes the body verbatim to a stranger's lock
  -- screen). The incident rides in `ref_id`.
  c_ops_class        constant text := 'incident_opened';
  c_ops_title_normal constant text := '사고 접수 — 확인 필요';
  c_ops_title_urgent constant text := '긴급 사고 접수 — 확인 필요';
  c_ops_title_sos    constant text := 'SOS 사고 접수 — 즉시 확인 필요';
  c_ops_body         constant text := '예약에서 사고가 접수됐어요. 운영 콘솔에서 사고 내용을 확인해 주세요.';
  v_ops int;
begin
  -- ① signed in
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- ② `for update` fetch, so two simultaneous opens serialise on the booking
  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status
    into b from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  -- ③ party gate BEFORE state gate (house law), on THIS booking — 0094 §2's fix, unchanged
  if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
    raise exception 'not_party';
  end if;
  -- ④ argument validation
  if p_kind not in ('dog_injury','lost_dog','third_party','equipment','other')
    then raise exception 'bad_kind'; end if;
  if p_severity not in ('normal','urgent','sos') then raise exception 'bad_severity'; end if;

  -- ⑤ One OPEN incident per booking. A second open is not an error — it returns the existing one,
  -- so a double-tap in an emergency does not produce two cases for one event, and the caller
  -- still gets a usable id rather than a raise it has to interpret under stress.
  -- ⚠ THIS STAYS ABOVE ⑥. See the placement paragraph in the header.
  select i.id into v_id from incidents i
   where i.booking_id = p_booking and i.resolved_at is null
   order by i.created_at limit 1;
  if v_id is not null then return v_id; end if;

  -- ⑥ [0114 🔵] state gate — the REPORTABLE set. Deliberately wider than
  -- `is_booking_party_active`: the accepted set PLUS `cancelled_owner` (0066's en-route cancel —
  -- the runner may be standing at the door) and `refund_pending` (reached from the accepted set
  -- after an incident settles, `0072:179` / `0038:219-221`). Those are precisely the two states a
  -- genuinely-accepted party is most likely to be standing in when they need to report, and an
  -- incident report is not a convenience that can wait for an accept.
  -- Written inline against the already-fetched row rather than as a second function: the record is
  -- in hand from ② so it costs nothing, and the set stays legible at the call site.
  -- ⚠ Still a SET, not "everyone": at `runner_pending`, `matching`, `payment_hold`, `draft`,
  -- `quoted` and `expired` this refuses, which is what keeps B-11.f closed.
  if b.status not in (
       'confirmed', 'runner_enroute', 'picked_up', 'active',
       'completed', 'no_show', 'incident_review', 'cancelled_runner',
       'cancelled_owner',                                  -- 🔵 en-route cancel: report still open
       'refund_pending'                                    -- 🔵 post-incident: a second fact
     ) then
    raise exception 'booking_not_reportable'
      using detail = '수락 전이거나 종료된 예약에는 사고를 접수할 수 없어요',
            hint   = '0114 §3: the reportable set is the accepted set + cancelled_owner + refund_pending.';
  end if;

  -- ⑦ insert
  insert into incidents (booking_id, reporter_id, kind, severity, note, media)
  values (p_booking, v_uid, p_kind, p_severity, p_note, coalesce(p_media, '{}'))
  returning id into v_id;

  -- ⑧ [0234 §B] THE OPS BELL — the incident_opened roster, ONCE, for a NEW incident only (the
  --   idempotent return ⑤ left above; a refused call raised above). Its OWN subtransaction: a
  --   failing bell is a NOTICE and the report STANDS — an emergency report must never be refused
  --   because a notification could not be written. An EMPTY roster writes nothing and nothing
  --   retries (an event, not a sweep); `ops_open_incidents()` still lists the incident, with
  --   `notified_at` NULL. One insert per severity, through constants (see the declare block).
  begin
    if p_severity = 'sos' then
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_ops_title_sos, c_ops_body, v_id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
    elsif p_severity = 'urgent' then
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_ops_title_urgent, c_ops_body, v_id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
    else
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, c_ops_title_normal, c_ops_body, v_id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
    end if;
    get diagnostics v_ops = row_count;
    raise notice 'open_incident_tx: incident % (%) — % ops recipient(s) for %', v_id, p_severity, v_ops,
      c_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was paged' else '' end;
  exception when others then
    raise notice 'open_incident_tx: incident % — the incident_opened bell failed (% %); the report stands',
      v_id, sqlstate, sqlerrm;
  end;

  return v_id;
end $$;

revoke execute on function open_incident_tx(uuid, text, text, text, text[]) from public, anon;
grant  execute on function open_incident_tx(uuid, text, text, text, text[]) to authenticated, service_role;

comment on function open_incident_tx(uuid, text, text, text, text[]) is
  '0094 §9 + 0114 §3 + 0234 §B. Opens (or idempotently returns) the one OPEN incident on a booking. Gate
order: signed-in → for-update fetch → PARTY → argument validation → existing-open-incident RETURN →
STATE (the reportable set: accepted + cancelled_owner + refund_pending, 0114 🔵) → insert → [0234] the
incident_opened roster told ONCE, title by severity (「사고 접수 — 확인 필요」 · 「긴급 사고 접수 — 확인
필요」 · 「SOS 사고 접수 — 즉시 확인 필요」), identifier-free body, ref_id = the new incident. The bell runs
in its own subtransaction: a failing bell never refuses the report. The idempotent return rings
nothing. Accepted residual (0114): an attacker who nominates a stranger and then cancels their own
booking can open an incident on them — and since 0234 that also pages the incident roster once.
265 0234-I1..I3 pin the bell.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C ops_roster_set — `incident_opened` joins the UI allowlist (catalog patch)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0216 §A's method, restated for its reason: this body was last written by 0216 from the CATALOG, so
-- no migration file holds its current text and a copy from any file would ship the loss of 0216's
-- roster key. Every inherited landing is asserted before the copy; the one anchor is asserted to
-- occur exactly once; the new class is asserted present after.
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
  if v_src is null then raise exception '0234 §C: ops_roster_set not found — refusing to guess'; end if;
  if position('''incident_opened''' in v_src) > 0 then
    raise exception '0234 §C: ops_roster_set already names incident_opened — applied twice, or something else landed it; find out which';
  end if;
  -- inherited landings
  if position('pg_advisory_xact_lock(hashtextextended(''ops_roster'', 0))' in v_src) = 0 then
    raise exception '0234 §C: 0216 §A''s roster key is not in the live body — do not copy this';
  end if;
  if position('on conflict on constraint ops_recipients_pkey' in v_src) = 0 then
    raise exception '0234 §C: 0208 §C''s upsert-by-constraint is not in the live body';
  end if;
  if position('insert into ops_roster_changes' in v_src) = 0 then
    raise exception '0234 §C: 0208 §A''s journal write is not in the live body';
  end if;
  if position('raise exception ''last_operator''' in v_src) = 0 then
    raise exception '0234 §C: 0208 §C''s last-operator guard is not in the live body';
  end if;

  -- the one anchor: the allowlist's last entry and its closing bracket
  v_a := $a$    'payment_marker_lost'
  ];$a$;
  v_repl := $a$    'payment_marker_lost',
    -- ── [0234 §C] SQL emitter: open_incident_tx's ops bell (0234 §B) ──
    'incident_opened'
  ];$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0234 §C: the allowlist anchor occurs % time(s) in ops_roster_set, expected exactly 1 — patch by hand', v_n;
  end if;
  v_new := replace(v_src, v_a, v_repl);
  if v_new = v_src or position('''incident_opened''' in v_new) = 0 then
    raise exception '0234 §C: patch did not apply';
  end if;

  -- the declaration is 0208:231-234's (and 0216's), verbatim
  execute format(
    'create or replace function ops_roster_set(p_profile uuid, p_event_class text, p_active boolean) returns table (profile_id uuid, event_class text, active boolean, changed boolean) language plpgsql security definer set search_path = public, pg_temp as %L',
    v_new);

  execute format('comment on function ops_roster_set(uuid, text, boolean) is %L',
    coalesce((select obj_description(p.oid, 'pg_proc') from pg_proc p
               join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
              where p.proname = 'ops_roster_set'), '')
    || chr(10) || '[0234 §C] incident_opened joins the class allowlist (the emitter is open_incident_tx''s '
    || 'ops bell, 0234 §B). Signature, returns, gate order and tokens unchanged.');
end $mig$;

-- 0208:337-338's ACL restated — a `create or replace` on an absent-function path is a plain CREATE.
revoke execute on function ops_roster_set(uuid, text, boolean) from public, anon;
grant  execute on function ops_roster_set(uuid, text, boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D ops_open_incidents — the incident_opened roster's read
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §F / 0233 §F's shape. `reporter_role` is DERIVED against the booking's CURRENT parties
-- ('owner' | 'runner' | 'other' — the last when the reporter is no longer a party, e.g. a runner who
-- was replaced; never guessed). `notified_at` is the bell's instant on THIS incident (§B's ref_id),
-- NULL when the roster was empty at report time. SOS first, then urgent, then normal; oldest first.
create or replace function ops_open_incidents()
returns table (
  incident_id    uuid,
  booking_id     uuid,
  dog_name       text,
  owner_name     text,
  runner_name    text,
  booking_status text,
  kind           text,
  severity       text,
  reporter_role  text,
  opened_at      timestamptz,
  verified_at    timestamptz,
  notified_at    timestamptz
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  c_ops_class        constant text := 'incident_opened';
  -- §B's three titles, verbatim
  c_ops_title_normal constant text := '사고 접수 — 확인 필요';
  c_ops_title_urgent constant text := '긴급 사고 접수 — 확인 필요';
  c_ops_title_sos    constant text := 'SOS 사고 접수 — 즉시 확인 필요';
  v_uid uuid := auth.uid();
begin
  -- ① THE ROSTER GATE, before any read of any incident or booking
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select i.id,
         i.booking_id,
         d.name,
         po.name,
         pr.name,
         b.status::text,
         i.kind,
         i.severity,
         case when b.id is null                   then 'other'
              when i.reporter_id = b.owner_id     then 'owner'
              when i.reporter_id = b.runner_id    then 'runner'
              else 'other' end,
         i.created_at,
         i.verified_at,
         (select min(nt.created_at) from notifications nt
           where nt.ref_id = i.id
             and nt.title in (c_ops_title_normal, c_ops_title_urgent, c_ops_title_sos))
    from incidents i
    left join bookings b  on b.id = i.booking_id
    left join dogs d      on d.id = b.dog_id
    left join profiles po on po.id = b.owner_id
    left join profiles pr on pr.id = b.runner_id
   where i.resolved_at is null
   order by case i.severity when 'sos' then 0 when 'urgent' then 1 else 2 end, i.created_at, i.id;
end $$;

revoke execute on function ops_open_incidents() from public, anon;
grant  execute on function ops_open_incidents() to authenticated;

comment on function ops_open_incidents is
  '0234 §D: every OPEN incident (resolved_at is null) — the rows behind the three incident_opened bells.
Gate: the incident_opened roster, BEFORE any read (not_signed_in / not_ops). Carries incident and booking
ids, dog and both display names, the booking''s raw status (gate on it, never print it), kind, severity,
reporter_role (owner | runner | other, derived against the booking''s CURRENT parties), opened_at,
verified_at and the bell instant (NULL = the roster was empty at report time). NO note, NO media, no
money, no contact field. SOS first. Read-only: no door closes an incident here (L2/L3, Sean''s).
265 0234-L1/L2 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare v_src text; t text;
begin
  foreach t in array array['사고 접수 — 확인 필요', '긴급 사고 접수 — 확인 필요', 'SOS 사고 접수 — 즉시 확인 필요',
                           '러닝 전 사고 검토 — 확인 필요'] loop
    if (t = any (_noti_ops_titles())) is not true then
      raise exception '0234 VERIFY: 「%」 is not ledgered', t;
    end if;
  end loop;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'open_incident_tx';
  if position('ops_recipients_for(c_ops_class)' in coalesce(v_src, '')) = 0 then
    raise exception '0234 VERIFY: open_incident_tx does not ring the incident_opened roster';
  end if;
  if position('ops_recipients_for(c_ops_class)' in v_src) < position('insert into incidents' in v_src) then
    raise exception '0234 VERIFY: the bell precedes the insert (a refused or idempotent call would ring)';
  end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ops_roster_set';
  if position('''incident_opened''' in coalesce(v_src, '')) = 0 then
    raise exception '0234 VERIFY: ops_roster_set does not accept incident_opened';
  end if;
end $verify$;
