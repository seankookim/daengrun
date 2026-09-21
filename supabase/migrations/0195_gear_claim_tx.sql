-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0195 — 굿즈 수령: the claim chip becomes a door
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ═══ §0a WHY NOW ═══════════════════════════════════════════════════════════════════════════════
-- `gear_claims` rows have been reachable since 0176 (`open_drop_tx` inserts `status='claimable'`),
-- and the whole fulfilment half has been a label. `runner/rewards.tsx` renders a chip whose word
-- is `claimStatusLabel('claimable')` = 「수령 가능 · 배송 연동 준비 중」 — a Pressable-less `View`
-- with no route and no effect. That clause was the honest thing to say while there was no door:
-- `claim-status.ts`'s own header calls it 「the one line that changes when fulfilment ships」.
-- This is that file.
--
-- After this slice a runner can actually redeem: name, phone, address, postal → `status='claimed'`
-- with the shipping snapshot stored on the row, an ops read that lists what is owed, and an ops
-- write that stamps carrier/tracking and moves the row to `shipped`. The enum already had every
-- value this needs — `claim_status` is `('locked','claimable','claimed','shipped')` (0001:21) —
-- so **no enum value is added**, and the four words keep the meanings 0001 gave them.
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO ════════════════════════════════════════════════════════════
-- - **No carrier integration.** `delivery_carrier` / `delivery_tracking` are what an operator TYPES
--   after they hand the box over, exactly as `ops_record_manual_payout` (0186 §C) records a bank
--   transfer a person made. Nothing here calls a courier API, and `shipped` therefore means
--   「발송했다」 — dispatched — and never 「도착했다」. There is no `delivered` value and this file
--   does not invent one.
-- - **No journal, no notification, no cron.** The row's own `claimed_at` / `dispatched_at` are the
--   whole record, per the slice's instruction. `notifications` is untouched.
-- - **`_guard_gear_claim_cols` (0106 §4) is NOT recreated.** Its immutable list is
--   profile_id/side/item/milestone/created_at; the columns this file adds are fulfilment columns
--   and join `status`/`shipped_to`/`claimed_at` on the writable side, which is the posture 0106
--   chose deliberately ("future ops fulfilment"). ⚠ That trigger refuses `authenticated`/`anon`
--   OUTRIGHT, so the client still cannot write this table by any path; the definer below is the
--   only door, and inside it `current_user` is the owner while `request.jwt.claim.role` is
--   `authenticated`, which is the tier 0106 §3's comment names as admitted-but-frozen. Pinned S1.
-- - **No new read RPC for the client.** Checked before writing one: `authenticated` holds
--   table-level `SELECT` on `gear_claims` (0106:135) and RLS `gear self read`
--   (`profile_id = auth.uid()`, 0002:133) scopes it to the caller's own rows. A table-level grant
--   covers columns added later, so `fetchGearClaims` can select the new columns with no server
--   change. The existing read is preferred over a `my_gear_claim(…)` that would duplicate it.
--   ⚠ **The disclosure this decision accepts, stated rather than implied:** `delivery` holds the
--   runner's own phone and address, and `authenticated` can therefore select it — for THEIR OWN
--   row only, because the RLS policy is row-scoped and `gear self claim` (the UPDATE policy) was
--   dropped by 0106. A runner reading back what they themselves typed is not a disclosure; a
--   stranger reading it would be, and that is pinned (226 `0195-C5`). Converting 0106's
--   table-level grant into column grants would be a re-seal of a sealed table with its own blast
--   radius, and RLS already answers the tenancy question — so it is not done here, on purpose.
--
-- ═══ §0c WHOSE OBJECTS THIS BUILDS ON (REGISTRY.md's silent-collision rule) ═════════════════════
-- Re-creates NOTHING. `claim_gear_tx`, `ops_gear_claims_pending` and `ops_mark_gear_shipped` are
-- all new, all first defined here, all setting their own ACL in this file (§E). It ALTERS one
-- shipped table (§A) and READS `ops_recipients_for` (0084 §E) without redefining it.
--
-- ═══ §0d THE COLUMN PROBLEM, AND WHY A NEW ONE — read this before `git blame`s you ══════════════
-- The obvious place to put a shipping address is `gear_claims.shipped_to`. It cannot hold one.
-- Measured on the declaration (0001:333): `shipped_to uuid references addresses`. Two independent
-- reasons it is the wrong column, and the second is the one that settles it:
--
--   ⓐ It is a uuid FK, not a payload. Retyping it would mean dropping an FK on a shipped table
--      and rewriting it — and `0115_account_deletion.sql:442,457` reasons explicitly about that
--      FK ("`gear_claims.shipped_to` points at one of the rows just redacted"), so the edge is
--      load-bearing in a file this slice must not disturb.
--   ⓑ **`addresses` structurally cannot hold a gear shipment.** Its columns are
--      `label · addr · detail · gate_code_enc · lat · lng · is_default` (0001:117-128) — there is
--      **no recipient name, no phone and no postal code** anywhere in it. So even writing an
--      `addresses` row and pointing `shipped_to` at it would lose three of the five fields a
--      courier needs. It would also put a runner's shipping address into the OWNER pickup-address
--      list that `addresses owner all` (0002:82) exposes to the app.
--
-- So the payload gets its own column. `shipped_to` is left exactly as declared — nullable, unused,
-- and still the FK 0115 reasons about. ⚠ **The names are deliberately not neighbours.** The new
-- columns are `delivery` / `delivery_carrier` / `delivery_tracking` / `dispatched_at`, none of
-- which is a substring of `shipped_to` or of each other, because this house has lost a decision to
-- exactly that (`custody` matching `custody_phase`, CLAUDE.md §Migrations). A later grep for
-- `shipped_to` must not return this slice's columns and vice versa.
--
-- ═══ §0e THE ORDER INSIDE `claim_gear_tx`, written as the property each step owns ═══════════════
--   ① lock the row and read ONLY `profile_id` · ② party gate on the locked row · ③ read state
--   ④ already-claimed short-circuit · ⑤ state gate · ⑥ validate the form · ⑦ write · ⑧ return.
--
--   ⚠ **① and ② are two statements on purpose.** Selecting the whole row and then gating would be
--   correct at runtime — an outsider still learns nothing, because the raise precedes any use of
--   the state — but it is not CHECKABLE from source, and the party-before-state property is one
--   this repo pins by reading `prosrc` (0176-O1's shape). Splitting the read makes the property
--   observable: `not_claim_owner` is raised before the word `v_status` exists anywhere in the body.
--
--   ⚠ **④ BEFORE ⑥ — an already-claimed row answers `already_claimed`, whatever the form says.**
--   The disagreement zone is 「already claimed AND a malformed field」, and the two orders give
--   different answers. `already_claimed` is a fact about the world; `bad_postal` is a fact about a
--   request that will change nothing either way. The world wins: a client retrying after a dropped
--   response must never be told its form is broken when the claim already landed.
--
--   ⚠ **`already_claimed` is a FLAT FIELD, not an exception, and `not_claimable` IS one.** They are
--   different propositions and the difference is the whole idempotency contract. A second claim on
--   a row you already claimed is SUCCESS — nothing changed because nothing needed to, the runner
--   has their answer, and raising would roll back a transaction that wrote nothing and force the
--   client to special-case an error that is not one. A claim on a `locked` row is a genuine refusal
--   the runner can act on (「아직 달성 전이에요」), and it raises. `shipped` joins `claimed` on the
--   idempotent side: it is strictly further along the same path, so 「you already claimed this」
--   remains true and is the only honest answer.
--
-- ═══ §0f THE OPS GATE — which class, and why it is `payout_due` ═════════════════════════════════
-- The ops functions reuse 0186 §C's gate verbatim: `ops_recipients_for(c_ops_class)` with the
-- membership test written as `is not true` so a NULL refuses (§Migrations' NULL-collapse law).
-- The class STRING is `payout_due`, and that is a choice with a cost, so it is named:
--   · A new class (`gear_fulfilment`) would be the semantically right label and would refuse
--     EVERY caller on day one, because `ops_recipients` would have no row for it — a door that
--     cannot be opened until someone inserts a row this migration would have to invent. This house
--     does not ship dead doors.
--   · At Banpo-pilot scale the operator who moves payout money is the operator who posts the box.
--     `payout_due` is the roster that names them, and it is already provisioned.
--   · The narrowing, when the roster grows past one person, is ONE constant in this file plus the
--     `ops_recipients` rows — not a redesign. `0084:517-520` deliberately left `event_class`
--     unconstrained so that adding a class is not a migration.
--
-- ═══ §0g DEPLOY ════════════════════════════════════════════════════════════════════════════════
-- **`supabase db push` ONLY.** No edge function changes (`open-drop` still only ever inserts
-- `claimable` and is untouched), no cron, no secrets. The client build ships alongside but is not
-- required for the server to be correct: every new column is nullable and every new function is
-- additive, so an app that predates this push keeps working and simply has no 수령 button.
-- Pins: `supabase/tests/226_gear_claim_suite.sql` (0195-C1…C5 · P1…P3 · S1).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §A the columns — the shipping snapshot, and what the courier was told
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `delivery` is a SNAPSHOT, not a reference. An address the runner edits next month must not
-- retroactively change where a box already went, and 전자상거래법's 재화공급 record (the reason
-- 0115 §B.3 keeps `gear_claims` through account deletion) is a record of what was ACTUALLY sent.
-- A jsonb frozen at claim time says that; an FK to a mutable row does not.
alter table gear_claims
  add column if not exists delivery          jsonb,
  add column if not exists delivery_carrier  text,
  add column if not exists delivery_tracking text,
  add column if not exists dispatched_at     timestamptz;

comment on column gear_claims.delivery is
  '0195 §A: 수령 신청 시점에 굳은 배송지 스냅샷 {recipient, phone, address1, address2, postal}.
`shipped_to`(uuid → addresses)가 아니라 새 열인 이유는 0195 §0d — addresses에는 받는 사람 이름도
전화번호도 우편번호도 없다. 스냅샷인 이유는 나중에 주소를 고쳐도 이미 보낸 상자의 행선지는
바뀌면 안 되기 때문이다(0115 §B.3의 재화공급 기록). claim_gear_tx 하나만 쓴다.';
comment on column gear_claims.delivery_carrier is
  '0195 §A: 운영자가 상자를 넘기고 손으로 적는 택배사. 연동은 없다 — 0186 §C가 은행 이체를 적는
방식과 같다. ops_mark_gear_shipped 하나만 쓴다.';
comment on column gear_claims.delivery_tracking is
  '0195 §A: 운영자가 손으로 적는 송장번호. 클라이언트는 읽기만 한다(0002 gear self read).';
comment on column gear_claims.dispatched_at is
  '0195 §A: 발송 시각. `claimed_at`(수령 신청)과 다른 사실이다 — 하나는 러너가 눌렀고 하나는
운영자가 보냈다. delivered_at은 없다: claim_status에 delivered 값이 없고, 도착은 아무도 기록하지
않으므로 있다고 말하면 거짓이다.';

-- The shape belt. NULL-permissive by construction, so it cannot fail on any row that exists today
-- (production `gear_claims` reaches this file with `delivery` NULL on every row — the column is
-- born in the statement above) and cannot fail on the suites that hand-write `status='shipped'`
-- without a payload (141 D16 does exactly that, and it must keep passing: this file does NOT add a
-- 「claimed implies delivery」 cross-column rule, because that would convert an ops row repair into
-- a raw constraint error nobody named).
-- What it DOES guarantee: if a row claims to carry a destination, that destination is postable —
-- four non-empty fields and a real Korean 5-digit 우편번호. The RPC validates the same five facts
-- before it writes; this constraint is the belt for every other writer that could ever exist.
alter table gear_claims drop constraint if exists gear_claims_delivery_shape;
alter table gear_claims add constraint gear_claims_delivery_shape check (
  delivery is null or (
        jsonb_typeof(delivery) = 'object'
    and coalesce(btrim(delivery->>'recipient'), '') <> ''
    and coalesce(btrim(delivery->>'phone'),     '') <> ''
    and coalesce(btrim(delivery->>'address1'),  '') <> ''
    and coalesce(delivery->>'postal',           '') ~ '^[0-9]{5}$'
  )
);
comment on constraint gear_claims_delivery_shape on gear_claims is
  '0195 §A: delivery가 있다면 부칠 수 있는 주소여야 한다 — 받는사람·전화·주소1 비어있지 않고
우편번호는 숫자 5자리. NULL은 허용(오늘의 모든 행, 그리고 141 D16이 손으로 만드는 shipped 행).
「claimed면 delivery가 있어야 한다」는 규칙은 일부러 넣지 않았다: 운영자의 행 수리가 아무도
이름 붙이지 않은 제약 오류로 죽는다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §B claim_gear_tx — the door
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Flat whitelisted return (house law). `already_claimed` rides as a COLUMN, not as an exception —
-- §0e says why. Every column here is one the caller's own row already discloses to them under
-- `gear self read`, so the return widens nothing.
create or replace function claim_gear_tx(
  p_claim_id uuid,
  p_recipient text,
  p_phone text,
  p_address1 text,
  p_address2 text,
  p_postal text
) returns table (
  claim_id        uuid,
  status          text,
  claimed_at      timestamptz,
  already_claimed boolean,
  carrier         text,
  tracking        text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_owner     uuid;
  v_status    text;
  v_claimed   timestamptz;
  v_carrier   text;
  v_tracking  text;
  v_recipient text;
  v_phone     text;
  v_addr1     text;
  v_addr2     text;
  v_postal    text;
  v_n         int;
begin
  -- ① THE LOCK, and the owner is the ONLY thing read from it.
  if v_uid is null       then raise exception 'not_signed_in';   end if;
  if p_claim_id is null  then raise exception 'claim_not_found'; end if;
  select g.profile_id into v_owner from gear_claims g where g.id = p_claim_id for update;
  if not found then raise exception 'claim_not_found'; end if;

  -- ② PARTY GATE on the locked row, ahead of every state gate and ahead of the form.
  --    `is distinct from` rather than `<>`: a NULL owner must refuse, not disappear.
  if v_owner is distinct from v_uid then raise exception 'not_claim_owner'; end if;

  -- ③ only now is the state readable. Same locked row, same transaction.
  select g.status::text, g.claimed_at, g.delivery_carrier, g.delivery_tracking
    into v_status, v_claimed, v_carrier, v_tracking
    from gear_claims g where g.id = p_claim_id;

  -- ④ IDEMPOTENCY, before the form is judged (§0e). Writes nothing, raises nothing, and reports
  --    the row as it stands — including a carrier, if ops has already posted it.
  if v_status in ('claimed', 'shipped') then
    return query select p_claim_id, v_status, v_claimed, true, v_carrier, v_tracking;
    return;
  end if;

  -- ⑤ state gate. The only remaining values are `locked` and `claimable`; `locked` is the refusal
  --    a runner can act on. Written positively so an unexpected value refuses rather than passes.
  if v_status is distinct from 'claimable' then raise exception 'not_claimable'; end if;

  -- ⑥ the form. Phone is reduced to its digits because that is what a courier dials and what an
  --    operator must be able to compare — 010-1234-5678 and 01012345678 are the same number, and
  --    storing both spellings makes a duplicate look like two people.
  v_recipient := btrim(coalesce(p_recipient, ''));
  v_addr1     := btrim(coalesce(p_address1, ''));
  v_addr2     := nullif(btrim(coalesce(p_address2, '')), '');
  v_phone     := regexp_replace(coalesce(p_phone,  ''), '[^0-9]', '', 'g');
  v_postal    := regexp_replace(coalesce(p_postal, ''), '[^0-9]', '', 'g');
  if v_recipient = ''                 then raise exception 'bad_recipient'; end if;
  if length(v_phone) not between 10 and 11 then raise exception 'bad_phone'; end if;
  if v_addr1 = ''                     then raise exception 'bad_address';   end if;
  if v_postal !~ '^[0-9]{5}$'         then raise exception 'bad_postal';    end if;

  -- ⑦ the write. `status = 'claimable'` is restated in the WHERE although the row is locked, and
  --    the count is ASSERTED rather than assumed — 0186 §C's `mark_lost` idiom. A claim that
  --    reports success while writing nothing is the exact failure this slice exists to remove.
  update gear_claims g
     set status       = 'claimed',
         claimed_at   = now(),
         delivery     = jsonb_build_object(
                          'recipient', v_recipient,
                          'phone',     v_phone,
                          'address1',  v_addr1,
                          'address2',  v_addr2,
                          'postal',    v_postal)
   where g.id = p_claim_id and g.status = 'claimable';
  get diagnostics v_n = row_count;
  if v_n is distinct from 1 then raise exception 'claim_race'; end if;

  -- ⑧ the answer is READ BACK from the written row, never composed from the inputs. The client
  --    re-renders from this, so anything it reports must be what the table actually holds.
  return query
    select g.id, g.status::text, g.claimed_at, false, g.delivery_carrier, g.delivery_tracking
      from gear_claims g where g.id = p_claim_id;
end $$;

comment on function claim_gear_tx is
  '0195 §B: 러너가 자기 굿즈 교환권을 수령 신청한다. 한 트랜잭션, definer. 순서는 잠금 →
파티 게이트(not_claim_owner) → 상태 읽기 → 이미 신청함(already_claimed 플랫 필드, 예외 아님) →
상태 게이트(not_claimable) → 양식 검증(bad_recipient/bad_phone/bad_address/bad_postal) → 쓰기.
**파티 게이트가 상태를 읽기 전에 온다** — 남의 교환권 id를 넣은 사람은 그 교환권이 어떤 상태인지
배우지 못한다. 멱등성: 같은 주인이 같은 행을 두 번 신청하면 already_claimed=true로 현재 행을
그대로 돌려주고 아무것도 쓰지 않는다(예외가 아닌 이유는 0195 §0e — 두 번째 신청은 실패가 아니라
이미 성공한 것이다). shipped도 같은 쪽이다: 더 나아간 상태이지 다른 상태가 아니다. 배송지는
행에 굳은 스냅샷으로 저장된다(§0d). 226 0195-C1~C5가 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §C ops_gear_claims_pending — what is owed, and where to send it
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Shape copied from `ops_payouts_due` (0186 §B): flat whitelisted columns, ops-only definer.
-- ⚠ **It DOES carry name, phone and address, and that is the opposite of `ops_payouts_due`'s
--   rule — so the difference is stated rather than left to look like an oversight.** 0186 §B
--   refuses to join a payable amount to bank details because an operator pays by looking the
--   runner up deliberately, as a second act; the disclosure buys nothing there. Here the address
--   IS the act: an operator cannot post a box without it, and a function that returned claim ids
--   alone would force a second query that discloses exactly the same fields to exactly the same
--   person with none of the scoping. What keeps it narrow is the predicate, not the columns:
--   `status = 'claimed'` only — a `claimable` row has no address yet, and a `shipped` row's box
--   is gone. ⚠ It is a POSITIVE match on one value, not `<> 'shipped'`: an enum value added later
--   must not fall into this list by default.
create or replace function ops_gear_claims_pending()
returns table (
  claim_id    uuid,
  profile_id  uuid,
  item        text,
  milestone   int,
  claimed_at  timestamptz,
  recipient   text,
  phone       text,
  address1    text,
  address2    text,
  postal      text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';   -- §0f
  v_uid uuid := auth.uid();
begin
  -- ① PARTY GATE — ops membership, before a single row is read.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  return query
    select g.id, g.profile_id, g.item, g.milestone, g.claimed_at,
           g.delivery->>'recipient', g.delivery->>'phone',
           g.delivery->>'address1',  g.delivery->>'address2', g.delivery->>'postal'
      from gear_claims g
     where g.status = 'claimed'
     order by g.claimed_at, g.id;
end $$;

comment on function ops_gear_claims_pending is
  '0195 §C: 수령 신청은 됐는데 아직 안 보낸 교환권 — 운영자가 상자를 부치려고 읽는 목록.
ops 전용(0084 §E 로스터, 클래스는 payout_due — 이유는 0195 §0f). 술어는 status = ''claimed''
하나이고 **긍정 매칭**이다: claimable 행에는 아직 주소가 없고 shipped 행은 이미 떠났으며,
나중에 enum 값이 생겨도 기본값으로 이 목록에 들어오지 않는다. 이름·전화·주소를 싣는 것은
0186 §B의 규칙(돈과 계좌를 한 창구에서 잇지 않는다)의 예외이고 일부러 그렇다 — 여기서는 주소가
곧 그 행위 자체다. 226 0195-P1·P3이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D ops_mark_gear_shipped — the operator says they posted it
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The enum's last value already exists, so nothing is invented: `claimed` → `shipped`. An
-- `already_shipped` RAISE (not a flat field, unlike §B's `already_claimed`) because the two
-- situations are genuinely different — a runner re-tapping a button is a retry, while an operator
-- stamping a second tracking number over the first is a mistake that would silently destroy the
-- number the first box was actually sent under.
create or replace function ops_mark_gear_shipped(
  p_claim_id uuid, p_carrier text, p_tracking text
) returns table (
  claim_id      uuid,
  status        text,
  carrier       text,
  tracking      text,
  dispatched_at timestamptz
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c_ops_class constant text := 'payout_due';   -- §0f
  v_uid      uuid := auth.uid();
  v_status   text;
  v_carrier  text;
  v_tracking text;
  v_n        int;
begin
  -- ① PARTY GATE — ops membership, ahead of the lock and every state gate.
  if v_uid is null then raise exception 'not_signed_in'; end if;
  if (select exists (select 1 from ops_recipients_for(c_ops_class) as rc(profile_id)
                     where rc.profile_id = v_uid)) is not true
  then raise exception 'not_ops'; end if;

  if p_claim_id is null then raise exception 'claim_not_found'; end if;
  v_carrier  := btrim(coalesce(p_carrier,  ''));
  v_tracking := btrim(coalesce(p_tracking, ''));
  if v_carrier  = '' then raise exception 'bad_carrier';  end if;
  if v_tracking = '' then raise exception 'bad_tracking'; end if;

  -- ② the lock, then the state gate on what the lock held.
  select g.status::text into v_status from gear_claims g where g.id = p_claim_id for update;
  if not found then raise exception 'claim_not_found'; end if;
  if v_status = 'shipped' then raise exception 'already_shipped'; end if;
  if v_status is distinct from 'claimed' then raise exception 'not_claimed'; end if;

  update gear_claims g
     set status            = 'shipped',
         delivery_carrier  = v_carrier,
         delivery_tracking = v_tracking,
         dispatched_at     = now()
   where g.id = p_claim_id and g.status = 'claimed';
  get diagnostics v_n = row_count;
  if v_n is distinct from 1 then raise exception 'ship_race'; end if;

  return query
    select g.id, g.status::text, g.delivery_carrier, g.delivery_tracking, g.dispatched_at
      from gear_claims g where g.id = p_claim_id;
end $$;

comment on function ops_mark_gear_shipped is
  '0195 §D: 운영자가 부친 상자의 택배사·송장번호를 적고 claimed → shipped로 옮긴다. ops 전용.
enum에 이미 있던 값이라 새로 만든 값은 없다(0001:21). 두 번째 호출은 already_shipped로 거절한다 —
§B의 already_claimed가 플랫 필드인 것과 일부러 다르다: 러너의 재탭은 재시도이지만 운영자가 송장을
덮어쓰는 것은 실제로 보낸 번호를 지우는 실수다. shipped는 「발송」이고 「도착」이 아니다.
226 0195-P2·P3이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E ACL — restated in THIS file, for functions first defined in THIS file
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- `create or replace` preserves an ACL only where the function ALREADY EXISTS. On any apply where
-- it does not — a rebuilt environment, a partial prior apply, a branch that never ran this file —
-- the same statement is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable
-- (0116:636). Every grant these three functions rely on is therefore written here.
-- The two ops functions are granted to `authenticated` on purpose: the roster check inside is the
-- gate, exactly as 0186 §F does it, so an ops operator can call them with their ordinary session.
revoke execute on function claim_gear_tx(uuid, text, text, text, text, text) from public, anon;
grant  execute on function claim_gear_tx(uuid, text, text, text, text, text) to authenticated;

revoke execute on function ops_gear_claims_pending() from public, anon;
grant  execute on function ops_gear_claims_pending() to authenticated;

revoke execute on function ops_mark_gear_shipped(uuid, text, text) from public, anon;
grant  execute on function ops_mark_gear_shipped(uuid, text, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §F VERIFY — the apply refuses to finish on a shape it did not intend
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Written independently of §A-§E's statements so a typo in either place aborts the apply rather
-- than shipping. ⚠ Everything matched against `prosrc` here is matched with COMMENTS STRIPPED:
-- this file documents its own guards in prose, and a check that a guard is CALLED would otherwise
-- be satisfied by the paragraph EXPLAINING it — the more carefully documented, the more certainly
-- green (CLAUDE.md, the comment-matching law).
do $$
declare
  v_src  text;
  v_bad  text := '';
  v_oid  oid;
  fn     text;
begin
  -- the columns and the constraint
  foreach fn in array array['delivery', 'delivery_carrier', 'delivery_tracking', 'dispatched_at'] loop
    if (select exists (select 1 from information_schema.columns
                        where table_schema = 'public' and table_name = 'gear_claims'
                          and column_name = fn)) is not true
    then v_bad := v_bad || ' COLUMN-MISSING(' || fn || ')'; end if;
  end loop;
  if (select exists (select 1 from pg_constraint
                      where conrelid = 'gear_claims'::regclass
                        and conname = 'gear_claims_delivery_shape')) is not true
  then v_bad := v_bad || ' DELIVERY-SHAPE-CONSTRAINT-MISSING'; end if;
  -- `shipped_to` is NOT touched by this file (§0d) — if it ever stops being a uuid, the reasoning
  -- in 0115:442 and in this header has silently changed owner.
  if (select data_type from information_schema.columns
       where table_schema = 'public' and table_name = 'gear_claims' and column_name = 'shipped_to')
     is distinct from 'uuid'
  then v_bad := v_bad || ' SHIPPED-TO-NO-LONGER-UUID'; end if;

  -- the three functions: definer, in-body search_path, and no PUBLIC/anon execute.
  -- ACL is read through `has_function_privilege` — the EFFECTIVE answer, which is what 217 S1 and
  -- 221 S1 use. Parsing `proacl` text would answer 「what is written」 rather than 「who can call」.
  foreach fn in array array['claim_gear_tx', 'ops_gear_claims_pending', 'ops_mark_gear_shipped'] loop
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' NOT-DEFINER(' || fn || ')'; end if;
      if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
            from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' NO-INBODY-SEARCH-PATH(' || fn || ')'; end if;
      if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' PUBLIC-EXECUTE(' || fn || ')'; end if;
      if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ANON-EXECUTE(' || fn || ')'; end if;
      if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' AUTHENTICATED-MISSING(' || fn || ')'; end if;
    end if;
  end loop;

  -- claim_gear_tx: the ORDER is the property — lock → party gate → state read. NO-SOURCE fails
  -- loudly rather than letting a NULL `prosrc` make every arm below silently true (the
  -- NULL-collapse law: a bare `IF` on a NULL predicate does not fire).
  -- ⚠ The state anchor is `into v_status`, NOT the bare name `v_status`: `prosrc` includes the
  -- DECLARE block, where every variable is named BEFORE the body starts, so an ordering arm
  -- anchored on a bare variable name compares against its declaration and is false on correct
  -- code. Caught here before it shipped; the same trap waits in any prosrc ordering pin.
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'claim_gear_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
  else
    if (position('raise exception ''not_claim_owner''' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-PARTY-GATE'; end if;
    if (position('for update' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-ROW-LOCK'; end if;
    if (position('into v_status' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-STATE-READ'; end if;
    if (position('for update' in v_src)
        < position('raise exception ''not_claim_owner''' in v_src)) is not true
    then v_bad := v_bad || ' PARTY-GATE-BEFORE-THE-LOCK'; end if;
    if (position('raise exception ''not_claim_owner''' in v_src)
        < position('into v_status' in v_src)) is not true
    then v_bad := v_bad || ' STATE-READ-BEFORE-THE-PARTY-GATE'; end if;
    -- `already_claimed` must NEVER be a raise: it is a flat return field (§0e). If this string
    -- appears at all in the body, someone converted the idempotent path into an exception.
    if (position('already_claimed' in v_src) > 0)
    then v_bad := v_bad || ' ALREADY-CLAIMED-IS-A-RAISE'; end if;
    if (position('raise exception ''not_claimable''' in v_src) > 0) is not true
    then v_bad := v_bad || ' NO-STATE-GATE'; end if;
  end if;

  -- both ops functions read the roster through 0084's one window, and the gate precedes the work
  foreach fn in array array['ops_gear_claims_pending', 'ops_mark_gear_shipped'] loop
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = fn;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' NO-OPS-ROSTER(' || fn || ')'; end if;
      if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' NO-OPS-GATE(' || fn || ')'; end if;
      if (position('raise exception ''not_ops''' in v_src)
          < position('from gear_claims' in v_src)) is not true
      then v_bad := v_bad || ' OPS-GATE-AFTER-THE-ROW-READ(' || fn || ')'; end if;
    end if;
  end loop;

  if v_bad <> '' then raise exception '0195 VERIFY:%', v_bad; end if;
end $$;
