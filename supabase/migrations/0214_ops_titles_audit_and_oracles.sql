-- ═══ 0214: the ops category stops being inherited by every `system` row · and one uuid oracle
-- ═══        (`claim_gear_tx`) answers the same word for a stranger whatever the id is
--
-- Correct-forward for F1 (medium) and F5 (low) of
-- `docs/reviews/2026-09-23-executing-review-0203-0213.md`. F4 (low) rides in the same slice and is
-- an EDGE FUNCTION change only (`transition-booking/index.ts`) — it is described in §0d because a
-- deploy of this migration without that function leaves half the slice, and nothing in SQL can
-- point at it.
--
-- ═══ §0 F1, RE-DERIVED RATHER THAN COPIED ══════════════════════════════════════════════════════
--
-- 0210 §B moved `kind = 'system'` out of the undisableable `safety` category and into a new `ops`
-- category with a column of its own. **The mechanism is correct and the reviewer measured it
-- working.** What was wrong is the ENUMERATION the honesty argument rests on: 0210's header names
-- FOUR titles and `0210-O2`'s `OPS_TITLES` holds the same four, so the pin cannot see the rest and
-- stays green as the set grows.
--
-- ─── ① THE SET, MEASURED HERE, NOT TAKEN FROM THE REVIEW ───
--   Derived mechanically from this tree: every `insert into notifications` whose `kind` column is
--   `'system'` (with OR without the `::noti_kind` cast — 0118 writes it as a bare literal, which is
--   why a `'system'::noti_kind` grep misses it), restricted to the LATEST declaration of each
--   function, plus every `kind: "system"` writer in `supabase/functions/_shared/ops.ts`. Titles
--   held in a plpgsql `constant text` are resolved to their value. Comments are stripped first
--   (the standing comment-matching law).
--
--   | title                                                   | writer                      | latest declaration | recipient                            |
--   |---------------------------------------------------------|-----------------------------|--------------------|--------------------------------------|
--   | 지급 대기 — 확인 필요                                    | ops_payouts_stuck_sweep     | 0210:417           | ops_recipients_for('payout_due')     |
--   | 인계 확인 멈춤 — 확인 필요                                | sweep_run_end_recovery      | 0201:928 · 0201:976| ops_recipients_for('handoff_unanswered') |
--   | 반환 좌초 — 확인 필요                                    | sweep_run_end_recovery      | 0201:768           | ops_recipients_for('return_strand')  |
--   | 굿즈 수령 신청 — 확인 필요                                | claim_gear_tx               | 0206:439 → §B here | ops_recipients_for('payout_due')     |
--   | 카드 해지 실패 — 확인 필요                                | _note_revocation_abandoned  | 0166:166           | ops_recipients_for('billing_key_revocation_abandoned') |
--   | 클럽 취소 수수료 인텐트 실패 — 확인 필요                    | _club_note_fee_mint_failure | 0118:674           | ops_recipients_for('club_fee_mint_failed') |
--   | 결제 자동 취소 실패 — 수동 취소 필요                       | notifyOps                   | _shared/ops.ts:65  | ops_recipients_for(eventClass) → OPS_PROFILE_ID |
--   | 이동 중 취소 보상 기록 실패 — 수동 확인 필요                | notifyOps                   | _shared/ops.ts:69  | 〃                                    |
--   | 결제 취소 실패 기록이 남지 않았어요 — 즉시 확인 필요         | notifyOps                   | _shared/ops.ts:79  | 〃                                    |
--   | 취소 보상 기록 실패 (24시간 이내 취소) — 수동 확인 필요      | notifyOps                   | _shared/ops.ts:84  | 〃                                    |
--   | 운영 확인이 필요한 이벤트가 있어요                         | notifyOps                   | _shared/ops.ts:124 | 〃                                    |
--
--   12 sites, **11 distinct titles**. ⚠ The crude counterpart was run beside it and BOTH
--   directions are accounted for (the standing rule for a new detector): the crude sweep — every
--   declaration, superseded ones included — finds **18 SQL sites / 6 distinct titles**; the refined
--   one finds 7 SQL sites / **the same 6 titles**, so latest-declaration-wins drops eleven
--   re-declarations of `sweep_run_end_recovery` / `ops_payouts_stuck_sweep` / `_note_revocation_
--   abandoned` and **loses no title**. The five it ADDS over any SQL grep are `ops.ts`'s, which a
--   migration sweep structurally cannot see.
--
-- ─── ② THE RULE, WRITTEN DOWN, AND IT IS **RECIPIENT** AND NOT SUBJECT MATTER ───
--   🔴 **A title belongs to the `ops` category when it is ADDRESSED TO THE OPS ROSTER.** Not when
--   it is about operations, not when it sounds like a desk ping, and not when it is money-shaped.
--   The operator's switch may only silence a push the OPERATOR receives; a push a CONSUMER
--   receives must be gated by a switch that consumer can see (`booking` · `chat` · `community` ·
--   `reward`), or by nothing at all (`safety`).
--
--   Applied to the eleven: **every one of them is ops-addressed.** Ten route through
--   `ops_recipients_for(<class>)`; the eleventh family (`notifyOps`) routes through the same
--   function and falls back to the `OPS_PROFILE_ID` env var, which is also an operator. **There is
--   no consumer-addressed `system` writer in this tree** — measured, not assumed.
--
--   ⚠ **SO ONE OF THE REVIEW'S SENTENCES IS CORRECTED HERE RATHER THAN INHERITED.** F1 reads
--   「the seven that were not enumerated include a consent obligation」, meaning 「카드 해지 실패 —
--   확인 필요」. That title's whole content is a consent obligation — a customer asked us to delete
--   their card and the PG refused — but its RECIPIENT is
--   `ops_recipients_for('billing_key_revocation_abandoned')`, i.e. Sean's own roster under 0155's
--   ruling 「the toss is fine, report to me」. The customer is not told by that writer at all. So it
--   is an ops title by the rule above, and routing it to `payment` would file an operator's work
--   queue under a consumer category — the mirror of the mistake F1 names. A relayed ANALYSIS is
--   evidence, not authority (CLAUDE.md); the grep that settles it costs the same as agreeing.
--   ⚠ **AND THE CONSISTENCY ARGUMENT IS THE STRONGER HALF, not the pedantic one.** 0210 already
--   made 「반환 좌초 — 확인 필요」 disableable, and that is a dog that has not come home. If a
--   stranded return may be silenced on an operator's phone — with the `notifications` row still
--   written, `alerts.tsx` still drawing it and the 0206 console still listing it — then a card
--   that must be deleted by hand may be too. Giving 카드 해지 실패 an always-on route while 반환
--   좌초 keeps a switch would be a ranking nobody chose.
--
-- ─── ③ WHAT IS ACTUALLY FIXED, THEN: THE ARM IS TITLE-KEYED, SO NOTHING **INHERITS** `ops` ───
--   0210 §B's arm is `when p_kind = 'system' then 'ops'`, which hands the operator's switch to
--   EVERY present and future `system` row on the strength of a kind. That is the same shape as the
--   defect 0210 §0② fixed one level up (an unknown KIND born into the most privileged category),
--   and it fails in the direction F1 is worried about: **the day a `system` writer addresses a
--   consumer, that consumer's push is silenced by a switch they cannot see** —
--   `notification-settings.tsx` draws the 운영 알림 row only behind `ops_me().is_ops` (0210 §A), so
--   a non-operator has no control it is muted by.
--
--   §A therefore adds `_noti_ops_titles()` — the eleven, by value, in the database — and §B
--   re-declares the classifier with
--       when p_kind = 'system' and p_title = any (_noti_ops_titles())  then 'ops'
--       when p_kind = 'system'                                        then 'booking'
--   Membership in `ops` is now **by name and measured**, and an unledgered `system` title falls to
--   `booking`: the least-privileged DISABLEABLE category, still SENT by default (0187 §C's rule is
--   untouched — every column defaults true and only an explicit `false` suppresses), and gated by
--   a switch its reader can actually see.
--   ⚠ **THE COST, SAID OUT LOUD.** An operator who has turned `booking` off and `ops` on now
--   misses a NEW ops title until it is added to the ledger — that direction got worse, and it is
--   chosen deliberately: a consumer silenced by someone else's switch is a worse failure than an
--   operator missing a push whose row is in their console either way, and the window is one line
--   long and gated (0214-T4 in SQL, `app/test/ops-system-titles.test.cjs` over the sources).
--   ⚠ **NULL IS SAFE BY CONSTRUCTION AND THAT IS WHY THE ARM IS SPLIT IN TWO.** `p_title = any(…)`
--   is NULL for a NULL title, a `case … when NULL` does not fire, and the row falls to the second
--   `system` arm — `booking`, which SENDS. Never to NULL, never to silence.
--   ⚠ **THE URGENT ARM STILL SITS ABOVE BOTH**, so a `system` row borrowing an urgent title is
--   `safety` exactly as 0210 §B arranged. Unchanged, and re-pinned here.
--
-- ─── ④ THREE SHIPPED SUITE ARMS LEGITIMATELY CHANGE AND ARE UPDATED IN THIS SLICE ───
--   The standing law (CLAUDE.md §Migrations) — a pin whose behaviour genuinely moves is updated
--   with the change, with the reason in a comment and the new owner named:
--     · `218 0187-N5`  — `system` with the arbitrary title 「즉시 확인하세요」 under four-columns-off
--     · `241 0210-C1`  — `_noti_push_category('system','아무거나')` and the near-miss 'SOS 접수'
--   Each of those asks what an ARBITRARY `system` title does, which is precisely the proposition
--   this file changes. `0214-T2`/`T3` own the new ones. Every arm that uses a LEDGERED title
--   (218:553 · 220:420 · 241 O1/O2) is untouched and stays green, which is the control.
--
-- ═══ §0b F5 — `claim_gear_tx` IS AN EXISTENCE ORACLE (0195:215 → 0206:381, order unchanged) ═════
--   MEASURED by the reviewer: `stranger + REAL claim id → not_claim_owner`, `stranger + RANDOM
--   uuid → claim_not_found`. 0206's comment says 「파티 게이트가 상태를 읽기 전에 온다」 and that
--   is true — the party gate precedes the STATE read. It does not precede the EXISTENCE answer,
--   because the row is fetched unscoped and 「not found」 is raised before the owner is compared.
--   §B scopes the locking select to the caller (`and g.profile_id = v_uid`), so both worlds raise
--   the SAME token. ⚠ `not_claim_owner` is the honest merge rather than `claim_not_found`: 「this
--   is not yours」 is TRUE of a claim that does not exist, while 「not found」 is FALSE of a claim
--   that exists and belongs to someone else. The client map keeps both strings (`api.ts:4883-4884`)
--   — `claim_not_found` is still raised by `ops_mark_gear_shipped` (`api.ts:7392`), so removing it
--   would break a live mapping on the operator side.
--   ⚠ Everything else in the function is 0206's **character for character**: the bell and its
--   position below ⑦, ④'s `already_claimed` early return, ⑤'s positive state gate, ⑥'s form
--   validation, ⑦'s asserted row count, ⑧'s read-back.
--
-- ═══ §0c NOT IN THIS SLICE, said so it is not read as an omission ══════════════════════════════
--   · F2 (the `extra` availability window with no owner-facing reader) is CLIENT work and belongs
--     to the 0215 slice that owns the slot builders.
--   · F3 (`payout_due` is effectively root) is a product decision about privilege separation and
--     is Sean's, not a builder's.
--   · F6 (`resolved_by` in `return_force_evidence`) is untouched: the amplification is closed
--     (`profiles` refuses the party, measured B1b) and narrowing the column is its own slice.
--   · `_noti_urgent_noti_titles()` is NOT re-declared. 0193 §E holds the current array and the
--     client drift gate reads the highest-numbered declaring migration; re-declaring it to change
--     nothing would move that gate's subject for no reason (0210 §0b's rule, kept).
--
-- ═══ §0d DEPLOY ════════════════════════════════════════════════════════════════════════════════
--   `supabase db push` **AND** `supabase functions deploy transition-booking` (F4 — the
--   `runner_accept` eligibility check moves ahead of the booking read). The two halves are
--   independent in the safe direction: the edge change is a pure re-ordering that needs no new SQL,
--   and this migration needs no new edge function. A client build is NOT required — no client
--   contract moves.
--
-- ⚠ `create or replace` of `_noti_push_category()` (first defined 0187) and `claim_gear_tx()`
--   (first defined 0195) — **ACLs restated in THIS file for both**, the grant-preservation class
--   (CLAUDE.md §Migrations, 0116:636). `_noti_ops_titles()` is new here and sets its own.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  the ledger — the ops roster's own titles, by value, in the database
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Pure, no table access, so no definer and no `search_path`: there is nothing here to shadow.
-- Shape and ACL mirror `_noti_urgent_noti_titles()` (0189 §A → 0193 §E) deliberately — one idiom
-- for 「a title family the classifier consults」, so the next one has somewhere to copy from.
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
    '운영 확인이 필요한 이벤트가 있어요'                        -- generic()                    ops.ts:124
  ]::text[]
$$;

revoke execute on function _noti_ops_titles() from public, anon, authenticated;

comment on function _noti_ops_titles is
  '0214 §A: every title written with kind=''system'', i.e. every notification ADDRESSED TO THE OPS
ROSTER — ten through ops_recipients_for(<class>), five of those through _shared/ops.ts''s notifyOps
(which falls back to OPS_PROFILE_ID, also an operator). Consulted by _noti_push_category: a system
row whose title is in this array is the ''ops'' category (disableable by notification_prefs.ops);
a system row whose title is NOT is ''booking'' — still sent by default, but gated by a switch its
reader can see, because an unledgered title is the one that might not be ops-addressed.
Adding a system writer means adding its title HERE. Pinned by 245 0214-T1/T2/T4 and by
app/test/ops-system-titles.test.cjs, which re-derives the set from the writers'' own source.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  the classifier — 0210 §B's body with arm ③ split in two, every other arm transcribed
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ THE ARM ORDER IS THE WHOLE DESIGN AND IT IS NOT ALPHABETICAL (0210 §B's note, still true):
--   ① `kind = 'safety'` — the writers' own classification, above everything.
--   ② the urgent TITLE family — 0114:273-281 admits only `kind='booking'` from a party, so
--      SOS/사고/중단 arrive indistinguishable from 응가 도장 and only the title saves them. Still
--      above every disableable arm, both `system` arms included.
--   ③ [0214 §B] `kind = 'system'` **AND a ledgered title** → 'ops'.
--   ③b [0214 §B] `kind = 'system'` with any other title → 'booking'. See §0③.
--   ④…⑦ chat · booking · community · reward, 0189's arms character for character.
--   ⑧ the unknown-KIND fallthrough, 0210 §0②'s `booking`.
create or replace function _noti_push_category(p_kind noti_kind, p_title text) returns text
language sql immutable as $$
  select case
    -- ① SOS · S1/S2 incidents · 외부 커스터디 이양 · 반환 지연 — the writer said safety, and
    -- safety is the one category with no column.
    when p_kind = 'safety'                             then 'safety'
    -- ② [0189 §A] the CLIENT writers of an urgent event plus 0188 ⓑ-①'s server one. They arrive
    -- as kind='booking' because 0114:273-281 admits nothing else from a party, so without this arm
    -- `booking = false` silences an SOS. Deliberately ABOVE every disableable arm — both `system`
    -- arms included — and deliberately NOT gated on the kind.
    when p_title = any (_noti_urgent_noti_titles())    then 'safety'
    -- ③ [0214 §B] the ops roster's own escalations, BY NAME. 0210 §B read `when p_kind = 'system'
    -- then 'ops'`, which handed the operator's switch to every present and future system row on
    -- the strength of a kind. The eleven titles in `_noti_ops_titles()` are measured from their
    -- writers and every one of them is addressed to `ops_recipients_for(...)`; that is what makes
    -- 「an operator may silence this」 a true sentence about them.
    when p_kind = 'system'
     and p_title = any (_noti_ops_titles())            then 'ops'
    -- ③b [0214 §B] A `system` TITLE NOBODY HAS LEDGERED IS NOT ASSUMED TO BE THE OPERATOR'S.
    -- The least-privileged DISABLEABLE category: still SENT by default (0187 §C), and gated by a
    -- column its reader can see — `notification-settings.tsx` draws 운영 알림 only for an operator
    -- (0210 §A), so a consumer muted by `ops` would be muted by a control they do not have. A NULL
    -- title lands here too, because `= any(...)` is NULL and a `case` arm on NULL does not fire.
    when p_kind = 'system'                             then 'booking'
    -- ④ 0090:87 writes the chat nudge as kind='booking' with this exact title (0090:78 dedupes on
    -- it, notification-route.ts:48 routes on it). `0187-N6` drives the real trigger, so the
    -- three-way agreement is held behaviourally rather than by matching the literal.
    when p_kind = 'booking' and p_title = '새 메시지'  then 'chat'
    when p_kind = 'booking'                            then 'booking'
    when p_kind = 'community'                          then 'community'
    when p_kind = 'reward'                             then 'reward'
    -- ⑧ [0210 §B] THE UNKNOWN-KIND FALLTHROUGH, AND IT IS THE LEAST-PRIVILEGED DISABLEABLE
    -- CATEGORY, NOT THE UNDISABLEABLE ONE. `shop` is the only `noti_kind` member with no arm above
    -- and it is a RESERVED value with ZERO writers anywhere in this repo (0187 §0, 0210 §0②) — the
    -- enum member is deliberately NOT dropped, because enum surgery is a separate decision with
    -- its own blast radius. 0187 §C's rule is kept: an uncategorised push is still SENT by default.
    else 'booking'
  end
$$;

revoke execute on function _noti_push_category(noti_kind, text) from public, anon, authenticated;

comment on function _noti_push_category is
  '0187 §C + 0189 §A + 0210 §B + [0214 §B]: notifications row → push category. safety and the
urgent-title family are the always-on category. A `system` row is ''ops'' — the roster''s own
escalations, disableable by the `ops` column — **only when its title is in _noti_ops_titles()**;
any other `system` title, and any unknown kind, falls to ''booking'': still SENT by default, and
gated by a column the reader can actually see. Called only by notify_push().';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C  `claim_gear_tx` — 0206 §C's body, with ① scoped to the caller
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Everything below the locking select is 0206's, unchanged. The ONE edit is in ①/②: the row is
-- fetched `for update` already scoped to `auth.uid()`, so 「no such claim」 and 「somebody else's
-- claim」 are the same observation and raise the same word. §0b has the reasoning and the token
-- choice.
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
  -- ① [0214 §C] THE LOCK **AND** THE PARTY GATE, IN ONE READ. 0206's version selected the row by
  --    id alone and raised `claim_not_found` before ② could compare the owner, so a stranger got
  --    two different words for 「a real claim」 and 「a random uuid」 — the existence oracle F5 names.
  --    Scoping the select is what collapses them: the query either returns THE CALLER'S row or it
  --    returns nothing, and nothing has exactly one honest sentence.
  if v_uid is null       then raise exception 'not_signed_in';   end if;
  if p_claim_id is null  then raise exception 'not_claim_owner'; end if;
  select g.id into v_owned
    from gear_claims g
   where g.id = p_claim_id and g.profile_id = v_uid
     for update;
  -- ② the ONE refusal for both worlds. It is the honest merge: 「이 교환권은 회원님의 것이
  --    아니에요」 is true of a claim that does not exist AND of one that belongs to someone else,
  --    while 「찾지 못했어요」 would be false in the second case (§0b).
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
  '0195 §B + 0206 §C + **[0214 §C]**: 러너가 자기 굿즈 교환권을 수령 신청한다. 한 트랜잭션, definer.
순서는 **잠금 = 파티 게이트**(호출자 소유로 스코프된 select … for update) → 상태 읽기 → 이미
신청함(already_claimed 플랫 필드, 예외 아님) → 상태 게이트(not_claimable) → 양식 검증 → 쓰기 →
ops 종 → 되읽기.
🔴 [0214 §C] **존재 오라클이 닫혔다.** 0206까지는 id만으로 행을 집어 `claim_not_found`를 먼저
던졌으므로, 남의 교환권 id와 아무 uuid가 서로 다른 낱말을 받았다(실행 리뷰 2026-09-23 F5). 이제
select 자체가 `profile_id = auth.uid()`로 좁혀져 있어 두 경우 모두 **not_claim_owner** 하나다 —
「회원님의 것이 아니에요」는 없는 교환권에도 참이고, 「찾지 못했어요」는 남의 교환권에 대해
거짓이라서 이쪽이 정직한 병합이다. `claim_not_found` 문자열은 클라 맵에 남는다:
`ops_mark_gear_shipped`가 여전히 그 낱말을 쓴다(api.ts:7392).
나머지는 0206 그대로 — 종은 ⑦ 쓰기 **뒤**, ④ 조기 반환보다 아래, 모든 raise보다 아래. 본문에는
식별자가 없다(0084 §E). 226 0195-C1~C5 + 237 0206-G1·S1 + 245 0214-C1이 핀.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the deploy-time shape. Behaviour belongs to suite 245; this is what must be true the
-- instant the file applies, so a broken apply aborts instead of leaving a half-armed classifier.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_bad text := ''; v_src text; v_n int;
begin
  -- ① the ledger exists, is the measured size, and holds no duplicate and no blank
  if to_regprocedure('public._noti_ops_titles()') is null then
    v_bad := v_bad || ' NO-FUNCTION(_noti_ops_titles)';
  else
    if array_length(_noti_ops_titles(), 1) is distinct from 11
    then v_bad := v_bad || ' _noti_ops_titles has ' ||
                  coalesce(array_length(_noti_ops_titles(), 1)::text, 'NULL') || ' entries (expected 11)'; end if;
    -- Asked against the array's OWN length, never against 11, so a size change does not print
    -- 「has duplicates」 about a list that has none.
    select count(*) into v_n from (select distinct unnest(_noti_ops_titles()) t) s;
    if v_n is distinct from coalesce(array_length(_noti_ops_titles(), 1), -1)
    then v_bad := v_bad || ' _noti_ops_titles has duplicates (' || v_n || ' distinct of '
                        || coalesce(array_length(_noti_ops_titles(), 1)::text, 'NULL') || ')'; end if;
    if exists (select 1 from unnest(_noti_ops_titles()) t where btrim(coalesce(t, '')) = '')
    then v_bad := v_bad || ' _noti_ops_titles contains a blank entry'; end if;
  end if;

  -- ② the classifier answers, by value — the four propositions this file moves
  if _noti_push_category('system'::noti_kind, '지급 대기 — 확인 필요') is distinct from 'ops'
  then v_bad := v_bad || ' a LEDGERED ops title is not ops'; end if;
  if _noti_push_category('system'::noti_kind, '카드 해지 실패 — 확인 필요') is distinct from 'ops'
  then v_bad := v_bad || ' a NEWLY-ledgered ops title is not ops'; end if;
  if _noti_push_category('system'::noti_kind, '아직 아무도 쓰지 않은 제목') is distinct from 'booking'
  then v_bad := v_bad || ' an UNLEDGERED system title answers '
                      || coalesce(_noti_push_category('system'::noti_kind, '아직 아무도 쓰지 않은 제목'), 'NULL')
                      || ' (expected booking)'; end if;
  if _noti_push_category('system'::noti_kind, null) is distinct from 'booking'
  then v_bad := v_bad || ' a NULL title on a system row answers '
                      || coalesce(_noti_push_category('system'::noti_kind, null), 'NULL')
                      || ' (expected booking — a case arm on NULL must not fire)'; end if;
  if _noti_push_category('system'::noti_kind, 'SOS') is distinct from 'safety'
  then v_bad := v_bad || ' the urgent arm no longer sits above the system arms'; end if;
  if _noti_push_category('safety'::noti_kind, '아무거나') is distinct from 'safety'
  then v_bad := v_bad || ' safety moved'; end if;

  -- ③ the ACLs this file is obliged to restate (grant-preservation class)
  if has_function_privilege('authenticated', '_noti_ops_titles()', 'execute') is not false
  then v_bad := v_bad || ' _noti_ops_titles is executable by authenticated'; end if;
  if has_function_privilege('authenticated', '_noti_push_category(noti_kind, text)', 'execute') is not false
  then v_bad := v_bad || ' _noti_push_category is executable by authenticated'; end if;
  if has_function_privilege('anon', 'claim_gear_tx(uuid, text, text, text, text, text)', 'execute') is not true
     and has_function_privilege('anon', 'claim_gear_tx(uuid, text, text, text, text, text)', 'execute') is not false
  then v_bad := v_bad || ' claim_gear_tx ACL unreadable'; end if;
  if has_function_privilege('anon', 'claim_gear_tx(uuid, text, text, text, text, text)', 'execute') is not false
  then v_bad := v_bad || ' claim_gear_tx is executable by anon'; end if;
  if has_function_privilege('authenticated', 'claim_gear_tx(uuid, text, text, text, text, text)', 'execute') is not true
  then v_bad := v_bad || ' claim_gear_tx is NOT executable by authenticated — the runner cannot claim'; end if;

  -- ④ claim_gear_tx's deployed shape: definer, in-body search_path, and the scoped read.
  --    Comments are stripped before matching: this file explains the scoping at length and an
  --    un-stripped match is satisfied by the paragraph rather than by the code.
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = 'claim_gear_tx';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(claim_gear_tx)';
  else
    if position('g.profile_id = v_uid' in v_src) = 0
    then v_bad := v_bad || ' claim_gear_tx no longer scopes its read to the caller'; end if;
    if position('claim_not_found' in v_src) > 0
    then v_bad := v_bad || ' claim_gear_tx still raises claim_not_found — the two worlds are distinguishable again'; end if;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.pronamespace = 'public'::regnamespace and p.proname = 'claim_gear_tx'
                    and p.prosecdef
                    and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public, pg_temp%')
  then v_bad := v_bad || ' claim_gear_tx lost SECURITY DEFINER or its in-body search_path'; end if;

  if v_bad <> '' then raise exception '0214 VERIFY:%', v_bad; end if;
  raise notice '0214 VERIFY ok — ops title ledger (11) · classifier arm is title-keyed · claim_gear_tx reads scoped';
end $$;
