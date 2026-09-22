-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0208 — the ops ROSTER gets a door: read it, change it, and find a person to put on it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 239_ops_roster_suite.sql (tag `orx`) — 0208-G1 · R1 · L1 · C1 · P1 · S1
--
-- DEPLOY: `supabase db push` + a client build. NO edge function change, no cron, no secret, no
-- enum. Three new functions, one new sealed table. `ops_recipients` (0084 §E) is NOT altered —
-- no column, no constraint, no policy, no grant. This file only adds doors onto it.
--
-- ─── §0 WHAT IS MISSING, MEASURED BEFORE A LINE WAS WRITTEN ─────────────────────────────────────
-- `ops_recipients` (0084 §E) decides who receives every operational alert this product emits —
-- `payout_due`, `return_strand`, `handoff_unanswered`, `billing_key_revocation_abandoned`,
-- `club_fee_mint_failed` in SQL, and eight more through `_shared/ops.ts` — and since 0198 it also
-- decides **who can open the ops console at all** (`ops_me()` computes `is_ops` through
-- `ops_recipients_for('payout_due')`).
--
-- It is sealed: RLS on, ZERO policies, and 0084 §E gave it exactly ONE read door
-- (`ops_recipients_for`, `service_role` only) and **no write door of any kind**. Measured on trunk
-- `debe82e`: zero `insert into ops_recipients` / `update ops_recipients` outside test fixtures,
-- zero references under `app/`. So the only way an operator comes into existence is a human typing
-- SQL at production — which is what Sean did for himself on 2026-09-22, and which is the same
-- shape 0198 §0 named as the thing that produces a wrong `p_amount_won`.
--
-- ⚠ **0084 §E's seal is NOT being reversed, and the distinction is the whole design.** §E's
--   sentence is 「nothing CLIENT-SIDE reads or writes it」 — i.e. no RLS policy, no table grant, no
--   PostgREST surface. That stands: this file adds no policy, no grant, and no column. What it
--   adds is three `security definer` functions whose FIRST act is the same
--   `ops_recipients_for('payout_due')` gate every other ops door takes, so the roster is readable
--   and writable by an operator and by nobody else. A staff roster behind the staff gate is not
--   the thing §E refused; an open table is.
--
-- ⚠ **AND THE BOOTSTRAP IS STILL SEAN'S AND STILL psql.** Every door here requires an existing
--   active `payout_due` operator, so the FIRST operator cannot be created through this file — by
--   construction, not by omission. A migration that could seat the first operator would be a
--   migration that decides who can read bank account numbers (0198's sentence, unchanged). The
--   bootstrap row stays:
--       insert into ops_recipients (profile_id, event_class, active)
--       values ('<uuid>', 'payout_due', true);
--
-- ─── §0b WHY `payout_due` IS THE GATE ON ALL THREE, AND NOT 「any active ops row」 ───────────────
-- 0198 §0d settled this for the console and the reason transfers verbatim: `is_ops` means 「can you
-- use the console」, computed THROUGH `ops_recipients_for` with the class constant the doors use,
-- because a second implementation of the membership rule is correct today and free to drift
-- tomorrow. The roster screen lives inside `app/ops/*`, behind `ops_me()`. If these three
-- functions gated on a different class, the console would draw a screen whose every call answers
-- `not_ops` — the dead button 0198 §0d exists to prevent. One class constant, one window.
--
-- ─── §0c THE CLASS LIST IS A **UI ALLOWLIST**, AND 0084 §E'S REFUSAL TO CONSTRAIN THE COLUMN
--          STANDS UNCHANGED ─────────────────────────────────────────────────────────────────────
-- 0084 §E deliberately put NO check constraint on `ops_recipients.event_class`, and its reasoning
-- is worth restating because this file must not quietly overturn it: a constrained vocabulary
-- makes ADDING AN EMITTER A MIGRATION, while the failure mode of a wrong string is already safe —
-- `ops_recipients_for()` returns zero rows and `_shared/ops.ts` falls back to `OPS_PROFILE_ID`. A
-- typo degrades to yesterday's behaviour, never to silence.
--
-- So `c_classes` below is **NOT a schema constraint**. It is the list of strings this SCREEN will
-- offer and accept, and its job is narrower and different: a human tapping a chip must not be able
-- to invent a class, because a subscription to `payout_dues` (sic) is a person who believes they
-- are on call and receives nothing — the one failure §E's safety argument does not cover, because
-- §E is about an EMITTER's typo and this is about a SUBSCRIBER's. A row written by psql with any
-- string at all is still accepted by the table, still read by `ops_recipients_for`, and still
-- LISTED by `ops_roster()` below (§A returns every row, not only allowlisted ones — a roster that
-- hid rows it did not recognise would be a roster that lies about who is on call).
--
-- ⚠ THE LIST WAS ENUMERATED FROM THE EMITTERS, NOT INVENTED. Measured on trunk `debe82e`:
--   · SQL, literal `ops_recipients_for('…')` in `supabase/migrations/` (5):
--       payout_due · return_strand · handoff_unanswered · billing_key_revocation_abandoned ·
--       club_fee_mint_failed
--   · Edge, the `OpsEventClass` union in `supabase/functions/_shared/ops.ts`, every member of
--     which `notifyOps` routes through `ops_recipients_for(eventClass)` at `ops.ts:185` (8):
--       payment_manual_cancel · charge_ladder_exhausted · charge_dispatch_stale ·
--       settled_without_payment · enroute_comp_failed · late_comp_failed ·
--       incident_waive_pending · payment_marker_lost
--   Union = 13. `charge_dispatch_stale` has no emitter TODAY (it is a declared arm of the union
--   with no call site yet) and is kept: the union is the contract `_shared/ops.ts`'s own header
--   calls 「the routing vocabulary, shared with 0084's ops_recipients.event_class」, and a class an
--   operator cannot subscribe to is a class whose first emission goes nowhere.
--   ⚠ The strings that appear in `supabase/tests/` only (`no_such_event_class_at_all`, and the
--   fixture uses of the eight edge classes) are NOT evidence of an emitter and are excluded.
--
-- ⚠ **WHEN AN EMITTER IS ADDED, THIS LIST IS PART OF ITS SLICE.** Adding a class to
--   `_shared/ops.ts`'s union and not here produces an alert nobody can subscribe to through the
--   product. `0208-C1` pins the list as a SET (every name accepted, two invented names refused),
--   so the omission reddens rather than shipping quietly.
--
-- ─── §0d WHY `last_operator` IS A REFUSAL AND NOT A WARNING ─────────────────────────────────────
-- The console's entry is `ops_me().is_ops`, which is `payout_due` membership. Deactivating the
-- last active `payout_due` row therefore locks EVERY human out of the console — including the
-- person doing it, one tap after they do it — and the only way back in is psql. That is a door
-- that removes its own handle, so §B refuses it by name and the screen renders the refusal.
--   ⚠ Scoped to `payout_due` ON PURPOSE. Emptying `return_strand` does NOT lock anyone out; it
--     makes a sweep find zero recipients, which 0084 §E documents as an honest answer with a
--     fallback behind it. A guard that refused the last row of EVERY class would be forbidding a
--     state the system already handles, which is a different and worse kind of wrong.
--   ⚠ 「and refuses to deactivate yourself while you are the only one」 is the SAME rule and not a
--     second one — self is simply the case where the last operator is the caller. One conjunct,
--     one token. A second guard would be a second implementation of one sentence (§0b's law).
--
-- ⚠ **NAMED GAP, written as prose because no pin can reach it (the house law):** deleting an
--   ACCOUNT still empties the roster without passing this guard — `delete_my_account_tx`
--   (0115:590) deletes that profile's `ops_recipients` rows directly, and `ops_recipients` is in
--   0115 §F's ④ delete list by name. That path is correct (a deleted person must not stay on
--   call) and it is outside this file: the guard here is about an OPERATOR'S TAP, not about an
--   invariant of the table. Stating it so nobody reads `0208-L1`'s green as 「the roster can never
--   be emptied」.
--
-- ─── §0e WHAT `ops_profile_lookup` MAY NOT CARRY ───────────────────────────────────────────────
-- Three columns: `id`, `name`, `role`. NOT phone, NOT email, NOT `handle`, NOT `district`, NOT
-- `avatar_url`. The operator's task is 「turn a name into a uuid so I can seat this person」, and
-- three columns answer it. `profiles` is column-granted (0088 · 0091) for `authenticated`, but
-- this is a DEFINER and the grant does not bind it — so the narrowing has to be written here and
-- pinned here, which `0208-P1` does BY COLUMN SET (`pg_proc.proargnames`) rather than by looking
-- at one row's values: a widening that added `phone` would pass any value-shaped pin the day no
-- fixture happened to have a phone.
-- ⚠ Tombstoned profiles (`deleted_at is not null`, 0115) are excluded from the lookup AND from
--   the roster's join is NOT the same decision — see §A. The lookup must not offer a deleted
--   person as a candidate; the roster must still name a row that exists.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A ops_roster_changes — the journal, sealed
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Who changed whose subscription, when. `ops_recipients.active` already keeps 「who used to be on
-- call」 (0084's column comment: false = unsubscribed without losing the row), and that answers
-- WHAT but never WHO DID IT — and the roster is the surface that decides who can read a runner's
-- decrypted bank account, so 「who added this person」 is the question an incident actually asks.
--
-- ⚠ **NO FOREIGN KEY, on either uuid.** The same decision 0186 §A took for `payouts.recorded_by`
--   and 0194 §D took for `bank_account_access_log`, for the same two reasons: `on delete restrict`
--   would block account deletion with a nameless constraint error, and `on delete cascade` would
--   DELETE THE AUDIT FACT — the row exists precisely to outlive the profile.
create table if not exists ops_roster_changes (
  id      uuid primary key default gen_random_uuid(),
  actor   uuid not null,
  profile uuid not null,
  class   text not null,
  active  boolean not null,
  at      timestamptz not null default now()
);
create index if not exists ops_roster_changes_profile_idx on ops_roster_changes (profile, at desc);
create index if not exists ops_roster_changes_at_idx      on ops_roster_changes (at desc);

alter table ops_roster_changes enable row level security;
revoke all on ops_roster_changes from public, anon, authenticated;

comment on table ops_roster_changes is
  '0208 §A: ops 명부 변경 장부 — 누가(actor) 누구를(profile) 어느 클래스에(class) 켜고 껐는지(active).
SEALED: RLS on, 정책 0개, 테이블 그랜트 0개. ops_roster_set()만 쓴다.
FK 없음 — 0186 §A·0194 §D와 같은 이유(restrict는 탈퇴를 이름 없는 제약 오류로 막고, cascade는
감사 사실 자체를 지운다; 이 행은 프로필보다 오래 살아남으려고 존재한다).
⚠ **변경만 적는다**: 이미 active=true인 행에 다시 true를 쓰면 행은 남지 않는다(ops_roster_set이
changed=false를 돌려준다). 장부 이름이 changes인 이유이고, 239 0208-R1이 그 델타를 핀한다.';
comment on column ops_roster_changes.actor is
  '0208: 변경을 실행한 운영자(auth.uid()). FK 없음 — 감사 사실은 프로필 삭제보다 오래 산다.';
comment on column ops_roster_changes.active is
  '0208: 이 변경이 남긴 **결과** 상태(켠 것이면 true, 끈 것이면 false). 이전 값이 아니다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B ops_roster — the whole roster, flat, behind the console gate
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ **IT TAKES NO ARGUMENT, and that is the same structural defence `ops_me()` (0198 §A) makes.**
--   There is no parameter to point at a third party, so the ORACLE question 「is <uuid> an
--   operator?」 cannot be asked of it at all. A caller who passes the gate sees the whole roster,
--   which is what a roster is; a caller who does not sees `not_ops` and learns nothing else.
--
-- ⚠ **INACTIVE ROWS ARE RETURNED.** `ops_recipients_for` filters on `active` because it is a
--   ROUTING window; this is the roster, and 0084's column comment says the row is kept precisely
--   so that 「who used to be on call」 survives. A screen that showed only active rows would make
--   re-activating a former operator require typing their uuid again.
--
-- ⚠ **EVERY ROW IS RETURNED, INCLUDING A CLASS OUTSIDE §0c's ALLOWLIST.** §0c argues this: a
--   roster that hid rows it did not recognise would be a roster that lies about who is on call,
--   and the strings in this table are not constrained (0084 §E). The screen renders an unknown
--   class as itself rather than pretending it is absent.
--
-- ⚠ A TOMBSTONED profile's row is returned too, with its name, because `delete_my_account_tx`
--   removes the `ops_recipients` row outright (0115:590) — so a tombstone with a live roster row
--   is a state the product does not make, and a roster that silently dropped it would hide a
--   shape that means something went wrong. `left join` for the same reason: a row whose profile
--   vanished by some path nobody has thought of is shown with a NULL name, never omitted.
create or replace function ops_roster()
returns table (
  profile_id  uuid,
  name        text,
  role        text,
  event_class text,
  active      boolean,
  created_at  timestamptz
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- the SAME constant every shipped ops door uses (0186 §B/§C · 0194 §F④ · 0195 §C/§D · 0198 §A).
  -- §0b is why it is this one and why it is taken through `ops_recipients_for`.
  c_ops_class constant text := 'payout_due';
  v_uid uuid := auth.uid();
begin
  -- ① GATE FIRST — before any read of anything. There is no argument to validate after it, which
  --    is the point: this function cannot leak a distinction it does not have.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
  select r.profile_id, p.name, p.role::text, r.event_class, r.active, r.created_at
    from ops_recipients r
    left join profiles p on p.id = r.profile_id
   order by p.name nulls last, r.profile_id, r.event_class;
end $$;
revoke execute on function ops_roster() from public, anon;
grant  execute on function ops_roster() to authenticated;

comment on function ops_roster is
  '0208 §B: ops 명부 전체(운영자별 클래스 구독), 평평한 행으로. **인자가 없다** — 0198 §A와 같은
구조적 방어다: 제3자를 가리킬 파라미터가 없으므로 「저 사람이 운영자인가」를 물을 수 없다.
게이트는 ops_recipients_for(''payout_due'')를 **어떤 읽기보다 먼저** 통과해야 한다(§0b: 콘솔의
다른 다섯 문과 같은 창구여야 입구와 문이 갈라지지 않는다).
비활성 행도 돌려준다(0084의 active 주석 — 누가 당번이었는지는 감사 사실이다) — 라우팅 창구인
ops_recipients_for와 다른 문장이고, 둘 다 참이다. §0c의 허용목록 밖 클래스도 숨기지 않는다:
숨기는 명부는 당번에 대해 거짓말하는 명부다. 239 0208-G1/R1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C ops_roster_set — seat someone, or take them off, and write down that you did
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE ORDER OF THE REFUSALS IS LOAD-BEARING and is 0194 §F④'s, restated: the GATE comes before
--   the arguments are even looked at, so a stranger naming a profile that exists and a stranger
--   naming a uuid that does not get the IDENTICAL word. The difference between `not_ops` and
--   `no_profile` is itself information about who is in this product; `0208-G1` measures exactly
--   that pair.
create or replace function ops_roster_set(p_profile uuid, p_event_class text, p_active boolean)
returns table (profile_id uuid, event_class text, active boolean, changed boolean)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  -- §0c: a UI allowlist, NOT a schema constraint. 0084 §E's refusal to CHECK the column stands,
  -- and a row written by psql with any string at all is still accepted by the table and still
  -- listed by §B. Enumerated from the emitters — the five SQL literals and the eight members of
  -- `_shared/ops.ts`'s `OpsEventClass` union. Adding an emitter means adding it here too, and
  -- 239 `0208-C1` pins the set so the omission reddens.
  c_classes constant text[] := array[
    -- ── SQL emitters, literal `ops_recipients_for('…')` in supabase/migrations/ ──
    'payout_due',                        -- 0186 §B/§C · 0194 §F④ · 0195 §C/§D · 0198 §A — the console
    'return_strand',                     -- 0193 §A · 0201 §A
    'handoff_unanswered',                -- 0182 · 0183 · 0188 · 0193 · 0201
    'billing_key_revocation_abandoned',  -- 0155
    'club_fee_mint_failed',              -- club fee mint
    -- ── edge emitters, the OpsEventClass union in supabase/functions/_shared/ops.ts ──
    'payment_manual_cancel',
    'charge_ladder_exhausted',
    'charge_dispatch_stale',             -- declared in the union, no emitter yet (§0c)
    'settled_without_payment',
    'enroute_comp_failed',
    'late_comp_failed',
    'incident_waive_pending',
    'payment_marker_lost'
  ];
  v_uid     uuid := auth.uid();
  v_was     boolean;
  v_others  int;
  v_changed boolean;
begin
  -- ① GATE FIRST, argument-blind (see the header).
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  -- ② the arguments, each refused BY NAME. `p_active is null` is its own word rather than being
  --    coalesced to a default: a three-valued boolean arriving from a client is a bug on the
  --    client, and picking a value for it would write a subscription nobody chose.
  if p_profile is null then raise exception 'no_profile'; end if;
  if p_active  is null then raise exception 'bad_active'; end if;
  if p_event_class is null or (p_event_class = any(c_classes)) is not true
  then raise exception 'unknown_class'; end if;

  -- ③ the person must exist and must not be a tombstone. A subscription for a deleted account is
  --    a recipient `notify_push` refuses by design (0189) — i.e. an operator who believes they
  --    seated someone and did not.
  if (select exists (select 1 from profiles p
                     where p.id = p_profile and p.deleted_at is null)) is not true
  then raise exception 'no_profile'; end if;

  -- ④ LOCK the roster row (if any) before the last-operator count is taken, so two terminals
  --    deactivating the two last operators cannot both observe 「there is another one」 and both
  --    succeed. `for update` on the target row plus a count over the others is enough here
  --    BECAUSE the only transition the guard forbids is a DEACTIVATION, and the count's members
  --    are rows the other transaction must itself lock to change.
  select r.active into v_was
    from ops_recipients r
   where r.profile_id = p_profile and r.event_class = p_event_class
     for update;

  -- ⑤ THE LAST-OPERATOR GUARD (§0d). Scoped to the console class, and to a real deactivation:
  --    turning OFF a row that is already off changes nothing and must not be refused.
  if p_active is false and p_event_class = c_ops_class and v_was is true then
    select count(*)::int into v_others
      from ops_recipients r
     where r.event_class = c_ops_class
       and r.active
       and r.profile_id <> p_profile;
    if v_others = 0 then raise exception 'last_operator'; end if;
  end if;

  -- ⑥ the upsert. `created_at` is NOT touched on conflict — 0084's `ops_recipients_for` orders by
  --    it, so re-activating a former operator must not move them to the front of the notification
  --    order, and 「when did this person first go on call」 is an audit fact.
  --
  -- ⚠ **`on conflict ON CONSTRAINT`, NOT an inference spec, and it is not a style choice.**
  --    `on conflict (profile_id, event_class)` is an EXPRESSION context, so plpgsql resolves those
  --    two names against this function's `returns table` OUT parameters as well as against the
  --    table's columns and raises `column reference "profile_id" is ambiguous` — measured here on
  --    the first harness run, where it reddened R1, C1 and L1 together while G1 and P1 stayed
  --    green (their writes are refused before they reach this line, which is exactly the shape
  --    that would have let this ship if the suite had only had a gate pin). Naming the constraint
  --    removes the expression context entirely, and it is the stronger statement anyway: an
  --    inference spec silently picks whatever unique index matches, and this upsert means 「the
  --    (person, class) primary key」 and nothing else. The VERIFY block asserts the constraint
  --    exists and covers exactly those two columns, so a rename cannot make this a runtime death.
  insert into ops_recipients (profile_id, event_class, active)
  values (p_profile, p_event_class, p_active)
  on conflict on constraint ops_recipients_pkey do update set active = excluded.active;

  -- ⑦ the journal — CHANGES only (§A's table comment). `v_was is null` = the row did not exist,
  --    so seating someone is always a change; otherwise it is a change iff the boolean moved.
  --    `is distinct from` and not `<>`: a NULL `v_was` must read as 「new」, not as 「unknown」.
  v_changed := (v_was is distinct from p_active);
  if v_changed then
    insert into ops_roster_changes (actor, profile, class, active)
    values (v_uid, p_profile, p_event_class, p_active);
  end if;

  return query select p_profile, p_event_class, p_active, v_changed;
end $$;
revoke execute on function ops_roster_set(uuid, text, boolean) from public, anon;
grant  execute on function ops_roster_set(uuid, text, boolean) to authenticated;

comment on function ops_roster_set is
  '0208 §C: ops 명부 upsert(켜기/끄기). 게이트가 **인자보다 먼저** — 남이 존재하는 프로필을 대도,
존재하지 않는 uuid를 대도 똑같이 not_ops다(0194 §F④의 순서; 그 차이 자체가 정보다).
거절: not_signed_in · not_ops · no_profile(널이거나 없거나 탈퇴) · bad_active(널) ·
unknown_class(§0c의 UI 허용목록 밖) · last_operator.
**last_operator**(§0d): 활성 payout_due 행이 그 하나뿐일 때 그것을 끄면 거절한다 — 콘솔 입구가
ops_me().is_ops = payout_due 멤버십이라, 마지막 하나를 끄는 것은 모든 사람을(누른 본인 포함)
psql 말고는 못 들어오게 잠그는 문이다. **자기 자신을 끄는 경우도 같은 규칙, 같은 토큰**이다
(자기는 마지막 운영자가 호출자인 경우일 뿐 — 두 번째 구현을 만들지 않는다). payout_due에만
건다: return_strand를 비우는 것은 잠금이 아니라 0084 §E가 정직한 답이라고 적어 둔 상태다.
행은 지우지 않고 active=false로 둔다(0084). created_at은 on conflict에서 건드리지 않는다 —
ops_recipients_for의 통지 순서가 그 값으로 정렬되고, 언제 처음 당번이 됐는지는 감사 사실이다.
changed=false면 장부에 행을 남기지 않는다(§A: 변경 장부). 239 0208-G1/R1/L1/C1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D ops_profile_lookup — a name prefix to a uuid, three columns, at most ten
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Without this the 「운영자 추가」 sheet is a uuid text field, and a uuid typed by a human is the
-- shape that seats the wrong person — silently, because every uuid looks like every other uuid.
--
-- ⚠ THREE COLUMNS AND THE NARROWING IS THE FEATURE (§0e). No phone, no email, no handle, no
--   district, no avatar. `0208-P1` pins it by COLUMN SET rather than by values, because a pin over
--   values is green whenever no fixture happens to carry the field.
-- ⚠ `like` WITH AN EXPLICIT ESCAPE, never `ilike '<raw>%'`: `%` typed into the search box would
--   otherwise be a full dump of every profile in the product, ten rows at a time, through a
--   function whose entire justification is that it is narrow.
-- ⚠ `limit 10` is a REFUSAL TO ANSWER, not a page. An operator who cannot find the person in ten
--   types more letters; a paging API here would be a people-directory with a cursor.
create or replace function ops_profile_lookup(p_query text)
returns table (id uuid, name text, role text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';
  c_limit     constant int  := 10;
  v_uid uuid := auth.uid();
  v_q   text;
begin
  -- ① GATE FIRST, argument-blind. A stranger searching a name that exists and a stranger
  --    searching gibberish get the identical word (`0208-G1`).
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  -- ② two characters minimum, refused by name. One character is not a lookup, it is a directory
  --    walk with a smaller page — and the answer to 「I only know one letter」 is not a worse list.
  v_q := btrim(coalesce(p_query, ''));
  if length(v_q) < 2 then raise exception 'short_query'; end if;

  -- ③ the wildcards the CALLER typed are literal. `\` first, or it would re-escape the escapes.
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');

  return query
  select p.id, p.name, p.role::text
    from profiles p
   where p.deleted_at is null
     and p.name ilike v_q || '%' escape '\'
   order by p.name, p.id
   limit c_limit;
end $$;
revoke execute on function ops_profile_lookup(text) from public, anon;
grant  execute on function ops_profile_lookup(text) to authenticated;

comment on function ops_profile_lookup is
  '0208 §D: 이름 접두사로 사람을 찾아 uuid를 얻는 창구 — 운영자 추가 시트가 uuid 입력칸이 되지
않게 하는 것이 전부다. 게이트가 인자보다 먼저(남에게는 이름이 맞든 아니든 not_ops).
**세 칸만: id · name · role.** 전화번호·이메일·handle·district·avatar는 돌려주지 않는다 —
definer라 0088/0091의 열 그랜트가 여기를 묶지 않으므로 좁히는 일은 이 본문의 책임이고,
239 0208-P1이 **열 집합으로** 핀한다(값으로 핀하면 마침 전화번호 없는 픽스처에서 늘 초록이다).
탈퇴 프로필(deleted_at)은 후보가 아니다. 두 글자 미만은 short_query — 한 글자는 조회가 아니라
디렉터리 열람이다. `%`·`_`·`\`는 escape로 리터럴화한다(검색창의 %가 전체 덤프가 되지 않도록).
최대 10행은 페이지가 아니라 **답하기를 거절하는 지점**이다 — 커서를 달면 인명부가 된다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the shape, at apply time
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ This block and `239 0208-S1` check overlapping things ON PURPOSE and neither is evidence for
--   the other: a property checked only at apply is protected exactly until someone recreates the
--   function (0131-G4's lesson), and a suite pin cannot abort a bad apply.
do $verify$
declare
  v_bad   text := '';
  v_fn    text;
  v_src   text;
  v_oid   oid;
  v_names text[];
begin
  foreach v_fn in array array['ops_roster', 'ops_roster_set', 'ops_profile_lookup'] loop
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || v_fn || ');'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || v_fn || ': definer 아님;'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || v_fn || ': 본문 search_path 없음;'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || v_fn || ': anon에 열려 있음;'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not true
      then v_bad := v_bad || ' ' || v_fn || ': authenticated가 실행할 수 없음;'; end if;
    -- the gate must be PRESENT and must precede the first table read. Comments stripped — this
    -- file explains the gate at length inside these very bodies, and an un-stripped match is
    -- satisfied by the prose (the `prosrc`-is-source-plus-our-own-prose law).
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where oid = v_oid;
    if v_src is null or btrim(v_src) = ''
      then v_bad := v_bad || ' NO-SOURCE(' || v_fn || ');'; continue; end if;
    if (position('ops_recipients_for(c_ops_class)' in v_src) > 0) is not true
      then v_bad := v_bad || ' ' || v_fn || ': 게이트 없음;'; end if;
  end loop;

  -- the journal is sealed. ⚠ Here the grant arms MEAN something, because §A revokes explicitly —
  -- unlike `ops_recipients` below, where the seal is RLS and never grant absence.
  if (select relrowsecurity from pg_class where oid = 'ops_roster_changes'::regclass) is not true
    then v_bad := v_bad || ' 장부에 RLS 없음;'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_roster_changes')
    then v_bad := v_bad || ' 장부에 정책 있음;'; end if;
  if has_table_privilege('authenticated', 'public.ops_roster_changes', 'select') is not false
    then v_bad := v_bad || ' 장부가 authenticated에 열려 있음;'; end if;
  if has_table_privilege('anon', 'public.ops_roster_changes', 'select') is not false
    then v_bad := v_bad || ' 장부가 anon에 열려 있음;'; end if;

  -- `ops_recipients` itself must still be sealed — this file adds DOORS, never a surface.
  -- ⚠ THE SEAL IS 「RLS on, ZERO policies」 AND NOT 「no grant」, and reading it the other way
  --   would be a false arm: supabase's own default privileges grant `all on tables` to
  --   `anon, authenticated` for every table postgres creates (the harness shim mirrors that,
  --   `00_shim.sql:128`), so 0084 §E's table has carried a SELECT privilege since the day it was
  --   created and is invisible anyway. 120 G1 and 229 read it the same way.
  if (select relrowsecurity from pg_class where oid = 'ops_recipients'::regclass) is not true
    then v_bad := v_bad || ' 🔴 ops_recipients의 RLS가 꺼졌다 (0084 §E의 봉인);'; end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ops_recipients')
    then v_bad := v_bad || ' 🔴 ops_recipients에 정책이 생겼다 (0084 §E의 봉인);'; end if;

  -- §C's upsert names this constraint, so its absence or a change of shape is a RUNTIME death in
  -- the one function that writes the roster. Checked here, where it aborts the apply instead.
  if (select array(select unnest(c.conkey) order by 1) from pg_constraint c
       where c.conrelid = 'ops_recipients'::regclass and c.conname = 'ops_recipients_pkey'
         and c.contype = 'p') is distinct from
     (select array(select a.attnum from pg_attribute a
                    where a.attrelid = 'ops_recipients'::regclass
                      and a.attname in ('profile_id', 'event_class') order by 1))
    then v_bad := v_bad || ' 🔴 ops_recipients_pkey가 (profile_id, event_class)가 아니다 — §C의 upsert가 터진다;'; end if;

  -- the lookup's column set, by NAME, at apply time (§0e)
  select p.proargnames into v_names from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ops_profile_lookup';
  if v_names is distinct from array['p_query', 'id', 'name', 'role']
    then v_bad := v_bad || ' 🔴 조회 창구의 열 집합이 다르다=' || coalesce(v_names::text, '(null)') || ';'; end if;

  if v_bad <> '' then raise exception '0208 VERIFY failed:%', v_bad; end if;
end $verify$;
