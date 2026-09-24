-- ═══ 0217 — a gear claim cannot resume behind the tombstone                                ═══
-- ═══        claim_gear_tx locks the caller's profile in deletion's own lock order and         ═══
-- ═══        refuses a deleted profile; the ops queue and the ship gate join the tombstone     ═══
--
-- ═══ §0 WHICH FINDING ═══════════════════════════════════════════════════════════════════════
-- Correct-forward for Finding #2 (high) of `docs/reviews/2026-09-25-server-0201-0215-codex-verdict.md`
-- (Codex REJECT, 2026-09-25 02:30 KST, base `da47510`). Codex's SQL findings are READ, not measured
-- — its sandbox could not run the harness — so this file's suite REPRODUCES the hole on trunk's
-- body before pinning the fix (248's header, MEASURED).
--
--   **0214:344-353 `claim_gear_tx` never checks or locks the caller's deletion state.** 0202 §B②
--   redacts `gear_claims.delivery` only `where delivery is not null` and `_gear_redact_tombstoned_
--   deliveries()` repairs already-tombstoned owners — both correct for the rows that EXIST at
--   deletion time. But a `claimable` row carries no `delivery` yet, so deletion leaves it exactly as
--   it was: claimable, delivery NULL, owned by a tombstoned profile. A claim that RESUMES after
--   deletion (a still-valid JWT — access tokens are stateless and outlive `auth.admin.deleteUser`
--   until `exp`; or the deletion committing while the claim is in flight) passes every gate 0214
--   has — signed in, owns the row, row is claimable — and writes a fresh name, phone and street
--   address behind the tombstone. `ops_gear_claims_pending` and `ops_mark_gear_shipped` exclude
--   only the `{"redacted": true}` marker (0202:453, 521), so that address is readable and shippable.
--
-- ═══ §0a WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - **It edits NO landed migration.** 0195, 0202, 0206, 0214 are untouched; every function here is
--   a `create or replace` forward from this file and **restates its own ACL in this file** (on an
--   apply where the function is absent, `create or replace` is a plain CREATE and a SECURITY
--   DEFINER born PUBLIC-executable is the worst shape this repo makes — 0116:636).
-- - **`delete_my_account_tx` is NOT touched.** Its redaction (0202 §B②) is correct for every row
--   that holds an address; the hole is a row that acquires one AFTER the tombstone, and the fix
--   belongs to the writer of that address, not to deletion. See §0d for why deletion is also not
--   asked to mark the address-less rows.
-- - **No new enum value, no new column, no new table.** `claim_status` keeps 0001:21's four words.
-- - **No signature, column-order or return-shape change** on any of the three functions. The client
--   wrappers (`api.ts` `claimGear` / `fetchOpsGearPending` / `markGearShipped`) need no edit.
-- - **No change to the non-deleted path.** A live runner's claim, the idempotent re-claim, the
--   form gates, the asserted write, the ops bell and the read-back are 0214 §C's byte-for-byte
--   below the new gate (248 `0217-D1` measures the whole path, bell included).
--
-- ═══ §0b THE LOCK, AND WHY IT IS `for share` ON THE PROFILE, TAKEN FIRST ══════════════════════
-- `delete_my_account_tx` (0115 §D ③, deployed body per 0202 §0d) takes NO explicit lock. Its
-- tombstone is `update profiles set … deleted_at = now() where id = p_uid`, which acquires the
-- profile ROW lock (`FOR NO KEY UPDATE`, or `FOR UPDATE` — `handle` sits under a partial unique
-- index), and only AFTER that does 0202 §B②'s `update gear_claims … where profile_id = p_uid and
-- delivery is not null` lock claim rows. **Deletion's order is therefore profile row → claim rows.**
--
-- `claim_gear_tx` now takes the SAME order: the caller's profile row **first** (`select deleted_at
-- … from profiles where id = auth.uid() for share`), the claim row second (0214's scoped
-- `for update`, unchanged). Two transactions that acquire locks in the same order cannot deadlock:
-- whichever holds the profile row first, the other waits there holding nothing.
--   · deletion first: the claim blocks at the profile row; when deletion commits, READ COMMITTED
--     re-evaluates the locked row (EvalPlanQual) and the select returns the NEW version —
--     `deleted_at` set — so the claim refuses. Nothing was written.
--   · claim first: deletion blocks at its `update profiles`; the claim commits its address; the
--     redaction statement that follows in deletion runs on a FRESH statement snapshot (VOLATILE
--     plpgsql, one snapshot per statement — 0202 §0's own mechanism) and sees the just-committed
--     `delivery`, so it is redacted in the same act. Either interleaving ends with no live address
--     behind a tombstone.
-- **`for share`, not `for update`, for two reasons and both are load-bearing.** (1) It is the
-- weakest lock that CONFLICTS with deletion's UPDATE (`FOR KEY SHARE` would not — it is compatible
-- with `FOR NO KEY UPDATE` — and a lock that does not conflict serialises nothing). Two of the
-- caller's own claims may proceed together; nothing here writes `profiles`. (2) 226 `0195-S1` pins
-- 「the party scope precedes the FIRST `for update` in the body」 by string position; a `for update`
-- on the profile would sit above the scoped select and turn a correct function red for a false
-- reason. `for share` is the lock the property wants AND the word the pin allows.
-- ⚠ The single-session harness can measure the COMMITTED case (tombstone lands, then the claim is
--   refused) but cannot see a lock at all — a plain, lock-free read of `deleted_at` passes every
--   single-session pin. That is why `248_claim_deletion_race.sh` exists: one psql holds deletion
--   open across `pg_sleep(2)` while a second calls `claim_gear_tx`; with the lock the claim waits
--   and refuses, without it the claim lands its address before the tombstone commits. The race is
--   the only arm that reads the lock, and it is the arm M1b reddens (248's header).
--
-- ═══ §0c THE TOKEN, AND WHY ITS POSITION CREATES NO ORACLE ════════════════════════════════════
-- The refusal is ONE bare token, `profile_deleted`, raised **after `not_signed_in` and before any
-- read of `gear_claims`**. Order inside the body: signed-in → profile lock + tombstone gate →
-- NULL-id guard → scoped claim lock (0214 §C ①) → state → form → write → bell → read-back.
--
-- Why the tombstone gate goes BEFORE the claim read, and not after ownership is settled:
--   · **A deleted profile is not a party.** The party gate is 「signed in AND a live profile」;
--     checking the tombstone only after the claim row was found would read — and lock — a row on
--     behalf of a caller the gate has already excluded. Party before state, and party before any
--     read of the locked row, are this repo's standing laws; putting the tombstone after the
--     ownership answer would violate both for the one caller the gate exists for.
--   · **It cannot create an existence oracle, because the answer is a function of the CALLER
--     alone.** A tombstoned caller gets `profile_deleted` for their own id, a foreign id, a missing
--     uuid and NULL alike — the token carries zero bits about the claim id, so it can distinguish
--     nothing about any row. A live caller's answers are byte-for-byte 0214's (`not_claim_owner`
--     for foreign and missing, one word). 248 `0217-E1` measures both halves: within each caller
--     foreign == missing, and the live owner passes (so 「refuse everyone」 is excluded).
--   · What the token DOES disclose is the caller's own deletion, to the caller — not a secret.
--   · **No `using detail`.** 0191's convention attaches a blocking ROW's id where the client can
--     route to it. The blocker here is the caller's own profile; a detail would be a field that
--     reads as information and is not (0191 §0a's own rule).
--   · **A profile row that does not exist at all is NOT `profile_deleted`.** `auth.users` can carry
--     a user with no `profiles` row (0115 §D ① measured 11 vs 10 on production). Such a caller owns
--     no claim (`gear_claims.profile_id references profiles`), so the scoped select returns nothing
--     and they get `not_claim_owner` exactly as before — the select-into leaves `v_deleted` NULL,
--     and `v_deleted is not null` is an exact boolean, never a bare IF on NULL.
--
-- ═══ §0d THE SHIP GATE REUSES `claim_redacted`; THE ROW BELT IS DELIBERATELY NOT ADDED ═════════
-- `ops_mark_gear_shipped` refuses a tombstoned owner's claim with **`claim_redacted`**, 0202 §B④'s
-- existing token, in 0202's existing gate position (after `already_shipped`, after `not_claimed`).
-- The operator copy already mapped to that token says precisely this state — 「탈퇴한 회원의
-- 신청이에요 … 신청을 취소해주세요」 (api.ts, `OPS_ERROR_KO`) — and the operator's remedy is the
-- same whether the address is redacted or was written behind the tombstone: cancel the claim, never
-- post the box. A second token would be a second sentence for one instruction. The tombstone is
-- read in the SAME statement as the status and the marker (one locked row version, `for update of
-- g` — the join side is not locked, and a `for update` over a join would lock `profiles` too and
-- invert §0b's order for the operator).
--
-- **Should deletion also mark the profile's address-less claim rows, so a resumed claim is refused
-- by the ROW as well?** Considered and NOT done, with the reasons written so a later session does
-- not re-open it as an oversight:
--   ⓐ There is no honest value to write. `delivery = '{"redacted": true}'` on a row that never held
--      an address would say 「an address was here and was removed」 — the exact distinction 0202 §0b
--      exists to keep (「redacted」 vs 「never had one」, recognisable in the fulfilment queue). A new
--      `claim_status` value is enum surgery, a separate decision with its own blast radius (0214 §B
--      took the same stance on `shop`).
--   ⓑ It would require patching `delete_my_account_tx` from the catalog a FIFTH time (0138 → 0190
--      → 0191 → 0202), a large surface for a belt whose buckle — the profile lock — already holds
--      under both interleavings (§0b).
--   ⓒ The address-less row is INERT after deletion by construction of the existing surfaces:
--      `claim_gear_tx` refuses at the profile gate (this file); `ops_gear_claims_pending` lists only
--      `status = 'claimed'` (0195 §C, positive match); `_guard_gear_claim_cols` (0106 §4) refuses
--      every client write to the table; `open_drop_tx` (0176) only INSERTS `claimable`. No path
--      moves it. 248 `0217-A1` pins that the refusal leaves it byte-identical.
--   The row stays `claimable` with `delivery` NULL, which is TRUE of it.
--
-- ═══ §0e WHOSE OBJECTS THIS RE-DECLARES ══════════════════════════════════════════════════════
--   0195 §B → 0206 §C → 0214 §C  `claim_gear_tx(uuid,text,text,text,text,text)`  — §A
--   0195 §C → 0202 §B③            `ops_gear_claims_pending()`                     — §B
--   0195 §D → 0202 §B④            `ops_mark_gear_shipped(uuid,text,text)`         — §C
-- NEW: nothing. `_gear_redact_tombstoned_deliveries()` (0202 §B⑤) is untouched and is called once
-- more at the end of this file (§D) — idempotent, and the one honest repair for any row that a
-- resumed claim wrote behind a tombstone BEFORE this file applied.
--
-- ═══ §0f DEPLOY ══════════════════════════════════════════════════════════════════════════════
-- `supabase db push` ONLY. No edge function names `claim_gear_tx` (measured: `grep -rl` over
-- `supabase/functions` is empty), no cron, no secrets, no client change required — the client's
-- token map folds an unknown token to Korean (`rpc-error.ts` stage (c)), and on the device that
-- deleted the account the claim screen is unreachable (`delete-account-sheet.tsx` signs out on
-- success). Pins: `supabase/tests/248_claim_deletion_lock_suite.sql` (0217-A1 · B1 · C1 · D1 · E1 ·
-- S1) + `supabase/tests/248_claim_deletion_race.sh` (0217-R1, two connections).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  `claim_gear_tx` — 0214 §C's body, with the profile lock and tombstone gate ahead of the
--     claim read. Everything from the NULL-id guard down is 0214's, unchanged.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
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
  -- the class `ops_gear_claims_pending` / `ops_mark_gear_shipped` gate on (0195 §0f) — the people
  -- who can actually open the list this bell points at. 0206 §0b.
  c_ops_class constant text := 'payout_due';
  c_ops_title constant text := '굿즈 수령 신청 — 확인 필요';
  c_ops_body  constant text := '굿즈 수령 신청이 들어왔어요. 배송 대기 목록을 확인해 주세요.';
  v_uid       uuid := auth.uid();
  v_deleted   timestamptz;
  v_owned     uuid;
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
  v_ops       int;
begin
  -- ⓪ signed in — ahead of everything, unchanged.
  if v_uid is null       then raise exception 'not_signed_in';   end if;

  -- ⓪b [0217 §A] THE PROFILE ROW, LOCKED FIRST AND IN DELETION'S ORDER (§0b). `for share` is the
  --    weakest lock that conflicts with `delete_my_account_tx`'s `update profiles`, so a deletion
  --    in flight makes this statement WAIT, and the row version it then returns is the one deletion
  --    committed. A deleted profile is not a party (§0c): the refusal is one bare token, raised
  --    before any read of `gear_claims`, and it is a function of the caller alone — the same word
  --    for the caller's own id, a foreign id, a missing uuid and NULL — so it can be no oracle.
  --    A caller with NO profile row leaves `v_deleted` NULL and falls through to the scoped select,
  --    which finds nothing they own: `not_claim_owner`, exactly as before. Exact boolean, never a
  --    bare IF on NULL.
  select p.deleted_at into v_deleted
    from profiles p
   where p.id = v_uid
     for share;
  if v_deleted is not null then raise exception 'profile_deleted'; end if;

  -- ① [0214 §C] THE LOCK **AND** THE PARTY GATE, IN ONE READ. 0206's version selected the row by
  --    id alone and raised `claim_not_found` before ② could compare the owner, so a stranger got
  --    two different words for 「a real claim」 and 「a random uuid」 — the existence oracle F5 names.
  --    Scoping the select is what collapses them: the query either returns THE CALLER'S row or it
  --    returns nothing, and nothing has exactly one honest sentence.
  if p_claim_id is null  then raise exception 'not_claim_owner'; end if;
  select g.id into v_owned
    from gear_claims g
   where g.id = p_claim_id and g.profile_id = v_uid
     for update;
  -- ② the ONE refusal for both worlds. It is the honest merge: 「이 교환권은 회원님의 것이
  --    아니에요」 is true of a claim that does not exist AND of one that belongs to someone else,
  --    while 「찾지 못했어요」 would be false in the second case (0214 §0b).
  if not found or v_owned is null then raise exception 'not_claim_owner'; end if;

  -- ③ only now is the state readable. Same locked row, same transaction. Re-scoped to the caller
  --    as well, so this read can never widen what ① narrowed.
  select g.status::text, g.claimed_at, g.delivery_carrier, g.delivery_tracking
    into v_status, v_claimed, v_carrier, v_tracking
    from gear_claims g where g.id = p_claim_id and g.profile_id = v_uid;

  -- ④ IDEMPOTENCY, before the form is judged (0195 §0e). Writes nothing, raises nothing, and
  --    reports the row as it stands — including a carrier, if ops has already posted it.
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
  --    reports success while writing nothing is the exact failure 0195 exists to remove.
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

  -- ⑦b [0206 §C] THE BELL. Reached only from the one path that actually moved a row to `claimed`:
  --     after ⑦'s asserted write, below ④'s early return, below every raise. An EMPTY ROSTER
  --     writes nothing and is the honest answer — the claim still succeeded and
  --     `ops_gear_claims_pending()` still lists it, so the box is not lost, only unannounced. The
  --     count is put in a NOTICE rather than swallowed, exactly as 0183:442 and 0193:772 do it.
  insert into notifications (profile_id, kind, title, body, ref_id)
  select rc.profile_id, 'system'::noti_kind, c_ops_title, c_ops_body, p_claim_id
    from ops_recipients_for(c_ops_class) as rc(profile_id);
  get diagnostics v_ops = row_count;
  raise notice 'claim_gear_tx: claim % — 수령 신청 접수: ops 수신자 %명 (%)',
    p_claim_id, v_ops,
    c_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (신청 자체는 접수됨)' else '' end;

  -- ⑧ the answer is READ BACK from the written row, never composed from the inputs. The client
  --    re-renders from this, so anything it reports must be what the table actually holds.
  return query
    select g.id, g.status::text, g.claimed_at, false, g.delivery_carrier, g.delivery_tracking
      from gear_claims g where g.id = p_claim_id;
end $$;
revoke execute on function claim_gear_tx(uuid, text, text, text, text, text) from public, anon;
grant  execute on function claim_gear_tx(uuid, text, text, text, text, text) to authenticated;

comment on function claim_gear_tx is
  '0195 §B + 0206 §C + 0214 §C + **[0217 §A]**: 러너가 자기 굿즈 교환권을 수령 신청한다. 한 트랜잭션, definer.
순서는 로그인 → **[0217] 호출자 프로필 행 잠금(for share) + 탈퇴 게이트(profile_deleted)** → 잠금 = 파티
게이트(호출자 소유로 스코프된 select … for update) → 상태 읽기 → 이미 신청함(already_claimed 플랫 필드) →
상태 게이트(not_claimable) → 양식 검증 → 쓰기 → ops 종 → 되읽기.
🔴 [0217] **탈퇴 뒤에 재개된 신청이 툼스톤 뒤에 새 주소를 쓰던 구멍이 닫혔다** (Codex 2026-09-25 #2).
0202 §B②의 지움은 delivery가 이미 있는 행만 지우므로, 아직 주소가 없던 claimable 행은 탈퇴 뒤에도
신청 가능했고 유효한 세션이 이름·전화·주소를 새로 썼다. 이제 gear_claims를 읽기 **전에** 호출자의
profiles 행을 탈퇴 트랜잭션과 **같은 순서**(프로필 → 교환권 행)로 잠그고 deleted_at이 있으면
profile_deleted 한 낱말로 거절한다 — 본인 id·남의 id·없는 uuid·NULL 모두 같은 낱말이라 오라클이 아니다.
0214의 존재 오라클 닫힘은 그대로다(살아 있는 호출자의 답은 바이트 그대로). 226 0195-C1~C5·S1 +
237 0206-G1·S1 + 245 0214-C1 + 248 0217-A1·D1·E1·S1·R1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  `ops_gear_claims_pending` — a tombstoned owner's claim is not pending, whatever `delivery`
--     says. 0202 §B③'s body plus ONE join and ONE conjunct.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The redaction-marker exclusion (`? 'redacted'`, broad on the disclosure side — 0202 §0b) is KEPT;
-- the tombstone is a second, independent exclusion read from `profiles` rather than inferred from
-- the payload. They cover different failures: a redacted row of a live profile (the marker fires,
-- the join does not) and a live snapshot behind a tombstone (the join fires, the marker does not).
-- Neither implies the other, which is why both stay. An INNER join fails closed: a claim whose
-- profile row is somehow absent is not listed either.
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
  c_ops_class constant text := 'payout_due';   -- 0195 §0f
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
      join profiles p on p.id = g.profile_id
     where g.status = 'claimed'
       and coalesce(g.delivery ? 'redacted', false) is not true
       -- [0217 §B] the owner is not tombstoned. Read from the tombstone itself, never from the
       -- payload: an address written behind a tombstone looks exactly like a live one.
       and p.deleted_at is null
     order by g.claimed_at, g.id;
end $$;
revoke execute on function ops_gear_claims_pending() from public, anon;
grant  execute on function ops_gear_claims_pending() to authenticated;

comment on function ops_gear_claims_pending is
  '0195 §C + 0202 §B③ + **[0217 §B]**: 수령 신청은 됐는데 아직 안 보낸 교환권 — 운영자가 상자를 부치려고
읽는 목록. ops 전용(payout_due). 술어는 status = ''claimed'' 긍정 매칭 그대로.
[0202] 지워진 배송지(delivery ? ''redacted'')는 빠진다. **[0217] 주인의 profiles.deleted_at이 찍힌 신청도
빠진다 — 표식이 아니라 툼스톤을 조인해서 본다.** 툼스톤 뒤에 쓰인 주소는 살아 있는 주소와 페이로드만으로는
구별되지 않기 때문이다. 두 제외는 서로 다른 실패를 덮는다(살아 있는 프로필의 지워진 행 / 툼스톤 뒤의 살아
있는 스냅샷). 226 0195-P1·P3, 233 0202-B2, 248 0217-B1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C  `ops_mark_gear_shipped` — a tombstoned owner's claim refuses with 0202's own token
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0202 §B④ verbatim, with the tombstone read in the SAME locking statement as the status and the
-- marker (one row version, no second look) and folded into the existing `claim_redacted` gate.
-- `for update of g`: the claim row is locked, the profile row is NOT — locking the join side would
-- take `profiles` AFTER `gear_claims`, the inverse of deletion's order (§0b), and an operator's
-- click must never be the transaction that deadlocks a person's account deletion.
-- ⚠ The gate ORDER is 0202's and is not arbitrary: `already_shipped` first (the box left before the
--   account did — 0115's sentence), `not_claimed` second (a claimable row's fact comes first), and
--   the merged 「nowhere to send it」 gate last.
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
  c_ops_class constant text := 'payout_due';   -- 0195 §0f
  v_uid       uuid := auth.uid();
  v_status    text;
  v_redacted  boolean;
  v_tombstone boolean;
  v_carrier   text;
  v_tracking  text;
  v_n         int;
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

  -- ② the lock, then the state gates on what the lock held. Status, redaction marker AND the
  --    owner's tombstone are read in ONE statement — one locked row version, no second look.
  select g.status::text,
         coalesce(g.delivery ? 'redacted', false),
         (p.deleted_at is not null)
    into v_status, v_redacted, v_tombstone
    from gear_claims g
    join profiles p on p.id = g.profile_id
   where g.id = p_claim_id
     for update of g;
  if not found then raise exception 'claim_not_found'; end if;
  if v_status = 'shipped' then raise exception 'already_shipped'; end if;
  if v_status is distinct from 'claimed' then raise exception 'not_claimed'; end if;
  -- [0202 §B④] `is not false` rather than a bare `if`: a NULL predicate must REFUSE, never
  -- disappear (the NULL-collapse law). There is nowhere to send this box.
  -- [0217 §C] …and a tombstoned owner is the same instruction to the operator — cancel the claim,
  -- never post the box — so it is the same token. Exact booleans on both arms.
  if v_redacted is not false or v_tombstone is not false then raise exception 'claim_redacted'; end if;

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
revoke execute on function ops_mark_gear_shipped(uuid, text, text) from public, anon;
grant  execute on function ops_mark_gear_shipped(uuid, text, text) to authenticated;

comment on function ops_mark_gear_shipped is
  '0195 §D + 0202 §B④ + **[0217 §C]**: 운영자가 부친 상자의 택배사·송장번호를 적고 claimed → shipped 로
옮긴다. ops 전용. 두 번째 호출은 already_shipped.
[0202] claim_redacted — 배송지가 지워진 신청은 발송 처리할 수 없다. **[0217] 주인의 profiles.deleted_at이
찍힌 신청도 같은 낱말로 거절한다** — 운영자가 할 일이 같기 때문이다(신청을 취소하고 상자는 부치지
않는다). 상태·표식·툼스톤을 **한 문장**에서 잠근 행 버전으로 읽고(for update of g — 프로필 행은 잠그지
않는다, 탈퇴 트랜잭션의 잠금 순서를 뒤집지 않으려고), 게이트 순서는 0202 그대로다. 226 0195-P2·P3,
233 0202-B3, 248 0217-C1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D  the repair, run once more — a row a resumed claim wrote behind a tombstone BEFORE this file
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- `_gear_redact_tombstoned_deliveries()` (0202 §B⑤) is exactly the repair for the state this file
-- closes off going forward: a tombstoned profile with a live snapshot. Idempotent; 0 in production
-- (0195 has never been deployed — 0202 §0e); cheap; and the honest thing to do rather than assume
-- no staging database ever hit the hole.
do $$
declare v_n int;
begin
  v_n := _gear_redact_tombstoned_deliveries();
  raise notice '0217 §D: redacted % delivery snapshot(s) found behind a tombstone', v_n;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the deploy-time shape. Behaviour belongs to suite 248; this is what must be true the
-- instant the file applies, so a broken apply aborts instead of leaving a half-armed gate.
-- ⚠ Everything matched against `prosrc` is matched with COMMENTS STRIPPED — this file explains its
--   own guards at length and an un-stripped match is satisfied by the paragraph rather than the code.
-- ⚠ These arms and 248 `0217-S1` are DIFFERENT ARTIFACTS: this aborts an apply that lands wrong,
--   the suite reddens when a LATER file undoes something (0131-G4's lesson).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $verify$
declare
  v_bad text := '';
  v_src text;
  v_oid oid;
  fn    text;
  p_lock int; p_gate int; p_null int; p_claim int; p_share int;
begin
  -- ① claim_gear_tx: the profile lock precedes the claim-row lock, the gate precedes the claim read
  v_oid := to_regprocedure('claim_gear_tx(uuid,text,text,text,text,text)');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(claim_gear_tx)';
  else
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
    else
      p_lock  := position('from profiles p' in v_src);
      p_share := position('for share' in v_src);
      p_gate  := position('raise exception ''profile_deleted''' in v_src);
      p_null  := position('raise exception ''not_claim_owner''' in v_src);
      p_claim := position('from gear_claims g' in v_src);
      if p_lock = 0  then v_bad := v_bad || ' claim_gear_tx does not read profiles'; end if;
      if p_share = 0 then v_bad := v_bad || ' claim_gear_tx does not lock the profile row (for share)'; end if;
      if p_gate = 0  then v_bad := v_bad || ' claim_gear_tx never raises profile_deleted'; end if;
      if (p_lock > 0 and p_share > 0 and p_lock < p_share) is not true
      then v_bad := v_bad || ' the profile read and its lock are not one statement'; end if;
      if (p_share > 0 and p_claim > 0 and p_share < p_claim) is not true
      then v_bad := v_bad || ' the profile lock does not precede the claim read (lock order = deletion''s)'; end if;
      if (p_gate > 0 and p_null > 0 and p_gate < p_null) is not true
      then v_bad := v_bad || ' the tombstone gate sits after the NULL-id / ownership refusal'; end if;
      if (p_gate > 0 and p_claim > 0 and p_gate < p_claim) is not true
      then v_bad := v_bad || ' the tombstone gate sits after the claim read'; end if;
      -- 0214's two properties are inherited, not regressed
      if position('g.profile_id = v_uid' in v_src) = 0
      then v_bad := v_bad || ' claim_gear_tx no longer scopes its read to the caller'; end if;
      if position('claim_not_found' in v_src) > 0
      then v_bad := v_bad || ' claim_gear_tx raises claim_not_found again'; end if;
    end if;
  end if;

  -- ② the two ops readers join the tombstone
  foreach fn in array array['ops_gear_claims_pending()', 'ops_mark_gear_shipped(uuid,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || fn || ')'; continue; end if;
    if position('join profiles p on p.id = g.profile_id' in v_src) = 0
    then v_bad := v_bad || ' ' || fn || ' does not join profiles'; end if;
    if position('p.deleted_at' in v_src) = 0
    then v_bad := v_bad || ' ' || fn || ' does not read the tombstone'; end if;
    if position('''redacted''' in v_src) = 0
    then v_bad := v_bad || ' ' || fn || ' lost the redaction marker'; end if;
  end loop;
  -- pending excludes by `is null`; ship reads `is not null` into an exact boolean and locks only g
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_gear_claims_pending()');
  if v_src is not null and position('p.deleted_at is null' in v_src) = 0
  then v_bad := v_bad || ' ops_gear_claims_pending does not exclude tombstoned owners'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_mark_gear_shipped(uuid,text,text)');
  if v_src is not null then
    if position('(p.deleted_at is not null)' in v_src) = 0
    then v_bad := v_bad || ' ops_mark_gear_shipped does not read the tombstone as a boolean'; end if;
    if position('for update of g' in v_src) = 0
    then v_bad := v_bad || ' ops_mark_gear_shipped locks the join side (inverts deletion''s order)'; end if;
    if position('v_tombstone is not false' in v_src) = 0
    then v_bad := v_bad || ' ops_mark_gear_shipped does not refuse a tombstoned owner'; end if;
  end if;

  -- ③ definer + in-body search_path + ACL, for all three (grant-preservation class)
  foreach fn in array array['claim_gear_tx(uuid,text,text,text,text,text)',
                            'ops_gear_claims_pending()', 'ops_mark_gear_shipped(uuid,text,text)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' ' || fn || ':NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') like '%search_path=public, pg_temp%'
          from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' ' || fn || ':SEARCH-PATH'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is not false
    then v_bad := v_bad || ' ' || fn || ':ANON-EXECUTABLE'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
    then v_bad := v_bad || ' ' || fn || ':NO-AUTHENTICATED'; end if;
  end loop;

  if v_bad <> '' then raise exception '0217 VERIFY:%', v_bad; end if;
  raise notice '0217 VERIFY ok — profile lock (for share) precedes the claim lock · profile_deleted before any claim read · both ops readers join the tombstone · definer/search_path/ACL restated';
end $verify$;
