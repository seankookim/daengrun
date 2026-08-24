-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0119 — 맹견: the word existed nowhere in this product, and the product hands a dog to a stranger
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Measured before this file was written (`git grep 맹견 origin/redesign-v4`): 22 hits, ALL of them
-- in `docs/`. **Zero in `app/`, zero in `supabase/migrations/`, zero in `supabase/functions/`.**
-- The repo's own legal readiness review says the same thing in its own words and calls it the one
-- genuine build gap in its §8:
--
--   docs/legal/readiness-review-nonlocation-2026-08-19.md:173-178
--     「🟡 Dangerous dogs: no exclusion exists … There is no gate, no field, and no question in the
--      booking flow. Nothing stops such a booking today. This is the one genuine build gap in §8,
--      and it is small: a dog-profile field plus a booking-time refusal.」
--   docs/handoff-codex/legal-ops-domain.md:42        「맹견 exclusion | DOES NOT EXIST … [measured]」
--   docs/handoff-codex/legal-ops-domain.md:355-357   「the source review asks for [statutorily-
--      defined breeds and individually-designated dangerous dogs] to be excluded from the MVP
--      outright.」
--
-- This file is that field and that refusal. It is a SAFETY hole first and a statutory exposure
-- second: the whole product is a stranger taking someone's dog out alone, and 동물보호법 puts the
-- muzzle/leash duty on 소유자등 — which is the RUNNER for the length of a run, a person we have
-- never asked whether they are about to take custody of a 맹견.
--
-- ═══ WHOSE OBJECTS THIS FILE RE-CREATES (REGISTRY.md silent-collision law) ═══════════════════
-- ONE existing object is re-created, and only because leaving it alone would ship a NEW bug:
--   §E `generate_recurring_bookings`  ← 0111 §3   (custody belt + token-only row isolation)
-- Everything else is NEW and nothing in the repo creates or replaces any of it:
--   type   `dog_dangerous_status`
--   cols   `dogs.dangerous_status` · `dogs.dangerous_basis` · `dogs.dangerous_declared_at`
--   funcs  `_breed_reads_as_dangerous` · `dog_custody_gate` · `dog_custody_refusal_detail`
--          `_guard_dangerous_dog_custody` · `_guard_dog_dangerous_declaration`
--          `_guard_dangerous_dog_delete`
--   trigs  `bookings_dangerous_dog` · `bookings_dangerous_dog_move`
--          `session_dogs_dangerous_dog` · `session_dogs_dangerous_dog_move`
--          `dogs_dangerous_declaration` · `dogs_dangerous_delete`
-- Checked against every remote branch on 2026-08-21: the only unlanded migration above 0116 is
-- `0117_late_booking_protocol` on `origin/claude/late-booking-server-stage2`, which touches
-- check-ins, faults and cancel money — no overlap with `dogs`, `session_dogs` or the recurring
-- generator.
--
-- ⚠ `search_path`: every function below writes `set search_path = public, pg_temp` in its OWN
-- body. 0055's retro-sealing ALTER is wiped by `create or replace` (REGISTRY, measured), and
-- 98 H1 sweeps every `security definer` function in `public` for it.
--
-- ═══ 🔴 WHAT THIS FILE DOES **NOT** DECIDE — Sean's, not mine ════════════════════════════════
-- The mechanism below refuses a 맹견 delegation OUTRIGHT. That is the conservative direction and
-- it is what the readiness review asks for ("excluded from the MVP outright"), but a review
-- recommendation is not a product ruling, and the *interesting* question is untouched:
--
--   🔴 **Are 맹견 bookings refused forever, or allowed under conditions?** The obvious conditions
--      are 입마개 confirmation, the owner's 맹견사육허가, a 책임보험 certificate, and an
--      experienced-runner-only pool. **Every one of those needs a verifier this product does not
--      have** — no document upload, no ops reviewer, no runner tier that means "has handled a
--      맹견". Build the verifier and the condition in the same slice or you have built a form.
--   🔴 **Should the same refusal cover 동반 (owner-accompanied) club attendance?** This file says
--      NO, deliberately: `session_rsvp` with `custody = 'owner_handled'` leaves the dog with its
--      own 소유자, which is the exact situation the statute contemplates, and refusing it would
--      throw away the one remedy §C can honestly name. If Sean wants 맹견 out of club sessions
--      entirely, that is one more `when` clause — and a different product.
--   🟡 **Whether an owner may un-declare.** §F latches `declared_dangerous` as final because the
--      platform cannot verify a de-designation. Reversal is therefore an ops errand that has no
--      ops surface yet. Named, not solved.
--
-- ═══ 🔴 DEPLOY ORDER — THE CLIENT FIELD SHOULD LAND FIRST (COMPANION, NOT A MIGRATION) ═══════
-- After this file, a dog whose 맹견 question has never been answered CANNOT be delegated (§C's
-- `dog_dangerous_undeclared`). The refusal names a remedy the owner can perform — "answer it on
-- the dog profile" — but **today there is no UI that asks**, so until the client ships the field
-- the remedy is nameable and not reachable. The client half is three edits and is NOT in this
-- slice:
--   · `app/src/lib/api.ts:325` `DOG_SELECT` — add `dangerous_status, dangerous_basis`
--   · `app/src/lib/api.ts:357` the `updateDog` patch type — accept both
--   · the dog-profile edit screen — a required two-part question, and the 맹견 answer should say
--     what happens next rather than silently disabling a button
--   · `supabase/functions/create-booking-hold/handler.ts:310` currently maps ANY booking-insert
--     error to `HttpError(500, bErr.message)`. The token reaches the client either way (it IS the
--     message), but a refusal is a 409, not a 500. One `if` — deliberately not taken here so this
--     slice stays SQL-only and its harness prediction stays clean.
-- **Blast radius of shipping the SQL first, measured-by-citation not by me:** REGISTRY's 0104 row
-- records "0 accounts active in 7 days" and the location brief's Q6 window records 9 runs across
-- 25 days on a single self-testing account. I did NOT re-measure production (this session does not
-- touch the linked project). If that citation is still true, the population that would be stranded
-- by an undeclared refusal is Sean's own test account, and pre-launch is the cheapest possible
-- moment for this gate. If it is NOT still true, ship the client field first.
--
-- ⚠ **NO BACKFILL, and that is the decision, not an omission.** It would take one line to set
-- every existing dog to `declared_none`. That line is the platform asserting, in a legal record,
-- a fact about someone else's dog that nobody ever asked them — which is precisely the assertion
-- this gate exists to stop being made silently. Existing dogs stay `undeclared` and their owners
-- answer once.
--
-- Suite: `154_dangerous_breed_suite.sql`. It pins the refusal AND the ordinary booking that must
-- still work AND the undeclared/NULL case, on both custody paths.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE FIELD — and why it is a declared PAIR, not a boolean and not a breed enum
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Three shapes were on the table. The law and this product's own data kill two of them.
--
-- ── ✗ a boolean `is_dangerous` ──────────────────────────────────────────────────────────────
-- There are THREE facts here, not two: "the owner says yes", "the owner says no", and "nobody has
-- ever been asked". A boolean can only hold the third as NULL — and a NULL in a gate column is
-- this repo's single most repeated bug (0058 F1, 110 S2, 0116 §D's own first draft, which shipped
-- `not (owner = uid or runner = uid or …)` and was caught FAIL-OPEN by its own suite because
-- `runner_id` was NULL). Putting the undeclared state into the value domain, as a NAME, is how the
-- gate below can be written without a single three-valued comparison in its hot path.
--
-- ── ✗ a breed enum ─────────────────────────────────────────────────────────────────────────
-- The legal set is NOT a function of a breed string, in two independent ways:
--   ① the statutory list is five breeds **and their crosses (그 잡종의 개)** — a cross has no
--      canonical name, and the owner of a 핏불 믹스 will type "믹스".
--   ② the 2024 동물보호법 amendment lets a 시·도지사 designate an individual dog a 맹견 after
--      기질평가 **whatever its breed is**. The readiness review names both doors explicitly
--      ("statutorily-defined breeds AND individually-designated dangerous dogs").
-- And `dogs.breed` is free text with no vocabulary and no validating writer (`app/src/lib/api.ts:357`,
-- `breed?: string`). A breed enum would be a gate answering a question the law does not ask.
--
-- ── ✓ owner-declared, with the DOOR recorded, plus a derived second belt ────────────────────
-- `dangerous_status` is the owner's answer. `dangerous_basis` records WHICH statutory door the
-- answer came through, because the two doors have different evidence behind them (a listed breed
-- has none; a 기질평가 designation has a document) and the future "allowed under conditions"
-- ruling will differ by door. The pair is constrained to move together — see the CHECK below.
--
-- ⚠ **WHAT IS DELIBERATELY NOT HERE: a 허가번호 / 보험증권 column.** Adding one would be the
-- repo's own recorded anti-pattern — `gate_code_access_log` sat for 60 migrations as, in
-- `0060_wave3_server_honesty.sql:52`'s words, 「한 번도 쓰인 적 없는 빈 껍데기」, next to
-- `club_phone_access_log`, which has real writers. A verification column with no verifier reads to
-- the next person as "we check permits". We do not. The day the conditions ruling lands, that
-- slice adds the column AND the human who reads it, in one breath.
create type dog_dangerous_status as enum ('undeclared', 'declared_none', 'declared_dangerous');

alter table dogs
  add column dangerous_status      dog_dangerous_status not null default 'undeclared',
  add column dangerous_basis       text,
  add column dangerous_declared_at timestamptz;

-- The pair moves together, in both directions, and the expression is NEVER three-valued:
-- `dangerous_status` is NOT NULL so the left side is always true/false, and the right side is an
-- `is not null` test. A 맹견 declaration without a stated door is refused; a door on a dog nobody
-- called a 맹견 is refused. (`declared_none` and `undeclared` both carry a null basis.)
alter table dogs add constraint dogs_dangerous_basis_pairs_with_status check (
  (dangerous_status = 'declared_dangerous') = (dangerous_basis is not null)
  and (dangerous_basis is null or dangerous_basis in ('listed_breed', 'designated'))
);

comment on column dogs.dangerous_status is
  '0119 §A — 맹견 여부에 대한 보호자의 신고. 세 값이고 NULL이 없는 이유: 「아직 아무도 묻지 않았다」는
BOOLEAN의 NULL이 아니라 이름 있는 상태여야 게이트를 3값 비교 없이 쓸 수 있다 (0058 F1 / 110 S2 /
0116 §D 초안이 전부 그 NULL에서 fail-open했다). 견종 이넘이 아닌 이유: 법정 목록은 「그 잡종의 개」를
포함하고, 기질평가로 지정된 개는 견종과 무관하며, dogs.breed는 어휘도 검증자도 없는 자유 텍스트다.
플랫폼이 대신 신고해 주지 않는다 — 기존 행은 백필하지 않고 undeclared로 남으며, 그 상태로는 위탁이
거절된다 (§C `dog_dangerous_undeclared`)';
comment on column dogs.dangerous_basis is
  '0119 §A — 어느 문으로 맹견이 되었는가. `listed_breed`(동물보호법 시행규칙의 법정 견종 및 그 잡종)
또는 `designated`(기질평가를 거친 시·도지사 지정). 두 문은 뒤에 붙는 증거가 다르고(전자는 없고 후자는
평가서가 있다), 「조건부 허용」 룰링이 내려오면 조건도 문마다 달라진다. dangerous_status와 짝으로만
움직인다 (dogs_dangerous_basis_pairs_with_status). ⚠ 게이트는 이 컬럼을 읽지 않는다 — 읽으면 미검증
값이 문을 여는 통로가 된다';
comment on column dogs.dangerous_declared_at is
  '0119 §A/§F — 신고 시각. 서버만 찍는다: `dogs_dangerous_declaration` 트리거가 status가 실제로 바뀔
때만 now()를 쓰고, 안 바뀌면 old 값을 되돌려 놓는다. 클라이언트가 보낸 값은 항상 버려진다 (0083 §2가
인계·귀가 도장에 쓴 것과 같은 이유 — 미리 담아 온 도장은 도장이 아니다)';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §B  THE SECOND BELT — a breed SCREEN, which can only ever ADD a refusal
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- A self-service declaration alone has one obvious defeat: type "로트와일러" into `breed`, answer
-- "not a 맹견", and the platform hands a Rottweiler to a stranger with every gate green. So the
-- declaration is checked against the data the owner ALREADY gave us.
--
-- The five statutory breeds, and their 잡종, are: 도사견 · 아메리칸 핏불테리어 · 아메리칸
-- 스태퍼드셔 테리어 · 스태퍼드셔 불 테리어 · 로트와일러.
-- ⚠ **Article numbers are deliberately not cited here.** The five breeds are the load-bearing and
-- stable fact; the 2023 전부개정 renumbered the provisions around them, and a wrong 조문 in a file
-- a lawyer may one day read is worse than none. `docs/biz/` counsel-brief errand owns the citation.
--
-- ⚠ **THIS IS A SCREEN, NOT A LEGAL DETERMINATION, AND THE ASYMMETRY IS THE WHOLE DESIGN.**
--   · It can only ever turn "allowed" into "refused with a remedy the owner can perform" (fix the
--     breed text, or fix the answer). It can never turn a refusal into an allow — `dog_custody_gate`
--     never consults it on a dog that is already refused.
--   · It deliberately does NOT chase relabels (아메리칸 불리, "믹스", "테리어 믹스"). Whether a
--     particular cross is 그 잡종 is exactly what 기질평가 exists to decide, and a platform regex
--     that pretends to decide it would be both wrong and the more dangerous kind of wrong: it
--     would look like coverage.
--   · False positives are cheap and self-clearing. A dog genuinely named "산토사" hits `tosa` and
--     its owner is told, in one sentence, which two fields disagree.
create or replace function _breed_reads_as_dangerous(p_breed text) returns boolean
language sql immutable set search_path = public, pg_temp as $$
  -- 공백·하이픈·숫자를 걷어내고 소문자화한 뒤 어간 매칭 — '아메리칸 핏 불 테리어', 'Pit-Bull',
  -- 'PITBULL' 이 같은 문자열이 되게 한다. `coalesce(..., false)`: breed는 nullable이고, NULL을
  -- 그대로 돌려주면 호출부의 `if not ...`가 안 터진다 (이 파일이 §A에서 지목한 바로 그 실패).
  -- ⚠ [measurement 2026-08-21] The concatenation MUST be parenthesised. `~` and `||` are both
  -- "any other operator" in postgres, i.e. EQUAL precedence, LEFT associative — so the unbracketed
  -- form parsed as `((haystack ~ '(도사|tosa') || '|핏불…') || …`, a TEXT expression, and
  -- `coalesce(text, false)` raised `COALESCE types text and boolean cannot be matched` at CREATE
  -- (a `language sql` body is parsed at CREATE — the harness comment at 0119's own top says so).
  -- 0119 did not apply at all until this was bracketed. Proof: `select pg_typeof('x' ~ 'a' || 'b')`
  -- → `text`. Had it somehow reached runtime it would have been worse than a raise: the regex
  -- would have been the unterminated `'(도사|tosa'` alone — four of the five statutory breeds
  -- silently unscreened.
  select coalesce(
    regexp_replace(lower(p_breed), '[^a-z가-힣]', '', 'g') ~
      ('(도사|tosa'
      || '|핏불|피트불|피불|pitbull|pitbul|apbt'
      || '|스태퍼드|스태포드|스탠퍼드|스탯퍼드|staffordshire|amstaff|staffybull'
      || '|로트와일|로트바일|롯트와일|롯와일|rottweil|rottie)'),
    false)
$$;
revoke execute on function _breed_reads_as_dangerous(text) from public, anon, authenticated;
grant  execute on function _breed_reads_as_dangerous(text) to service_role;

comment on function _breed_reads_as_dangerous is
  '0119 §B — 신고를 보호자가 이미 준 데이터와 대조하는 두 번째 벨트. 법정 5종(도사견·아메리칸
핏불테리어·아메리칸 스태퍼드셔 테리어·스태퍼드셔 불 테리어·로트와일러)의 어간과 흔한 표기 변형만
본다. ⚠ 판정이 아니라 스크린이다: 「허용」을 「수행 가능한 구제책이 붙은 거절」로 바꿀 수만 있고,
거절을 허용으로 바꾸지 못한다. 잡종 상표(아메리칸 불리 등)는 일부러 안 쫓는다 — 그건 기질평가의
일이고, 흉내 내면 커버리지처럼 보이는 오답이 된다';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §C  THE RULE — one object, and it fails CLOSED in every direction
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Returns NULL when custody may pass to a runner, and otherwise the refusal TOKEN. One definition,
-- called by every custody trigger in §D and by the cron belt in §E — 0116 §C's lesson, one file back:
-- 「Two copies of a rule kept in agreement by discipline is a promise, not a mechanism.」
--
-- ── The NULL discipline, stated once ────────────────────────────────────────────────────────
-- Every comparison below is wrapped so the answer is a real boolean, never NULL:
--   · a dog id that names no row leaves every field NULL. `d.dangerous_status = 'declared_none'`
--     is then NULL, `not NULL` is NULL, and an `if` on NULL DOES NOT FIRE. That is fail-OPEN, it
--     is the exact shape of 0058 F1 / 110 S2 / 0116's own first draft, and it is why the
--     permission is expressed as a POSITIVE match wrapped in `coalesce(…, false)` rather than as
--     `<> 'declared_dangerous'`.
--   · `p_dog is null` short-circuits to the same refusal rather than falling through.
--
-- ── Why a missing dog gets the SAME token as an undeclared one ──────────────────────────────
-- House law (0054:73 / 0067 §C): 「no such thing」 and 「not yours」 get the SAME answer. Handing a
-- distinct token to a caller who guessed a dog uuid would make this an enumeration oracle over
-- other people's dogs — and the thing it would enumerate is a legal record about a dangerous
-- animal. Both answers are `dog_dangerous_undeclared`.
create or replace function dog_custody_gate(p_dog uuid) returns text
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare d record;
begin
  -- ⓐ no dog named at all — refuse before anything can be read as permission
  if p_dog is null then return 'dog_dangerous_undeclared'; end if;

  select dangerous_status, breed into d from dogs where id = p_dog;

  -- ⓑ THE ONLY WAY OUT IS A POSITIVE MATCH. Written as `= 'declared_none'` and not as
  --   `<> 'declared_dangerous'` on purpose: the second form admits `undeclared`, admits a NULL
  --   from a missing row, and would admit any enum value added by a future migration — three
  --   fail-open directions from one operator choice.
  if not coalesce(d.dangerous_status = 'declared_none', false) then
    if coalesce(d.dangerous_status = 'declared_dangerous', false) then
      return 'dog_dangerous_custody_refused';
    end if;
    -- undeclared, or no such dog — same answer, see the header
    return 'dog_dangerous_undeclared';
  end if;

  -- ⓒ declared not-맹견, but the breed the owner typed says otherwise (§B). Reached ONLY on an
  --   otherwise-allowed dog, so this arm can add a refusal and can never remove one.
  if _breed_reads_as_dangerous(d.breed) then
    return 'dog_dangerous_breed_conflict';
  end if;

  return null;
end $$;
revoke execute on function dog_custody_gate(uuid) from public, anon, authenticated;
grant  execute on function dog_custody_gate(uuid) to service_role;

comment on function dog_custody_gate is
  '0119 §C — 낯선 사람에게 커스터디가 넘어가도 되는가. 넘어가도 되면 NULL, 아니면 거절 토큰
(dog_dangerous_undeclared · dog_dangerous_custody_refused · dog_dangerous_breed_conflict). 규칙은
여기 한 번만 정의되고 §D의 두 트리거와 §E의 크론이 같은 것을 부른다 (0116 §C: 규율로 맞춰 두는 두
벌의 사본은 메커니즘이 아니라 약속이다). ⚠ 유일한 통과 조건은 `= declared_none` **양성 일치**다 —
`<> declared_dangerous`로 쓰면 미신고·없는 개·미래에 추가될 이넘 값이 전부 통과한다.
⚠ 클라이언트에 EXECUTE를 주지 않았다: 남의 강아지 uuid로 「그 집 개가 맹견인가」를 물을 수 있는
definer가 되기 때문. 사전 조회 API가 필요해지면 당사자 게이트가 먼저다 (0116 §D)';

-- ── The remedy, defined once, next to the token it belongs to ────────────────────────────────
-- ⚠ **A refusal token must name something its reader can actually DO.** Two of the three below do:
-- answer the question, or fix whichever of the two fields is wrong. The third — an actual 맹견 —
-- has no on-platform remedy that would make the delegation happen, so it does not invent one. What
-- it names instead is TRUE and PERFORMABLE and is the whole reason §D refuses at custody transfer
-- rather than at the dog: **동반 참여 is still open.** `session_rsvp` writes
-- `session_dogs.custody = 'owner_handled'`, creates no booking, and is untouched by this file —
-- the dog goes running, with its own 소유자 holding the leash, which is the arrangement the statute
-- is written around.
create or replace function dog_custody_refusal_detail(p_token text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select case p_token
    when 'dog_dangerous_undeclared' then
      '강아지 프로필에서 맹견 여부를 먼저 알려주세요 — 러너에게 아이를 맡기려면 필요한 답변이에요'
    when 'dog_dangerous_breed_conflict' then
      '견종과 맹견 여부 답변이 서로 달라요 — 강아지 프로필에서 둘 중 맞는 쪽으로 고쳐주세요'
    when 'dog_dangerous_custody_refused' then
      '맹견은 아직 러너 위탁을 받지 못해요 (입마개·보험·전담 러너 확인 절차가 준비되지 않았어요). '
      || '보호자가 함께 뛰는 클럽 세션 동반 참여는 그대로 이용하실 수 있어요'
    else '강아지 정보를 확인해주세요'
  end
$$;
revoke execute on function dog_custody_refusal_detail(text) from public, anon, authenticated;
grant  execute on function dog_custody_refusal_detail(text) to service_role;

comment on function dog_custody_refusal_detail is
  '0119 §C — 토큰마다의 구제책. 앞의 둘은 보호자가 지금 할 수 있는 행동을 지목한다(답하거나, 어긋난
두 필드 중 하나를 고치거나). 세 번째는 이 제품에 없는 구제책을 지어내지 않는 대신 **사실이면서 수행
가능한 것**을 말한다 — 동반 참여(session_rsvp, custody=owner_handled)는 이 파일이 건드리지 않았고
부킹을 만들지도 않는다. 거절이 「개」가 아니라 「커스터디 이전」에 걸려 있는 이유가 그것이다';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §D  THE REFUSAL — at the server boundary, on BOTH paths a stranger can take the dog
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 「The UI no longer offers it」 is not a closure. These are triggers, so the refusal is the
-- database refusing the write, and it does not care which of the four writers issued it:
--   ① marketplace — `create-booking-hold/handler.ts:291` inserts `bookings` as **service_role**
--   ② club        — `session_pay_delegation` (0081 §A) inserts `bookings` as a definer
--   ③ recurring   — `generate_recurring_bookings` (0111 §3) inserts `bookings` from cron
--   ④ club, EARLIER — `session_delegate_dog` (0048) inserts `session_dogs` at
--                     `custody = 'runner_delegated'`, long before any booking exists
--
-- ⚠ **NO `current_user` BRANCH — deliberately, and this is the difference from `_guard_booking_
-- insert_cols` (0083 §2) sitting on the same table.** That guard asks whether the caller is
-- `authenticated`/`anon` because it is protecting SERVER-WRITTEN COLUMNS from a client. This one
-- is protecting a DOG from the product, and the product writes as service_role and as definers.
-- A `current_user` branch here would exempt every single real writer. (Inside a SECURITY DEFINER,
-- `current_user` is the function OWNER anyway — it can never identify a caller.)
--
-- ⚠ ④ is a SEPARATE trigger and not folded into ①-③ on purpose. Without it, a 맹견 owner applies,
-- a host spends a real decision approving a delegation they may not lawfully accept, and the
-- refusal only lands at payment. The host's decision is the thing being protected.
create or replace function _guard_dangerous_dog_custody() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_token text;
begin
  -- `new.dog_id` resolves per row type — both `bookings` and `session_dogs` carry that column, so
  -- ONE function serves both triggers (the `touch_updated_at` pattern, 0002:10-12).
  v_token := dog_custody_gate(new.dog_id);
  if v_token is not null then
    raise exception using
      errcode = 'P0001',
      message = v_token,
      detail  = dog_custody_refusal_detail(v_token),
      hint    = '0119 §D — 맹견 게이트. dogs.dangerous_status / dogs.dangerous_basis';
  end if;
  return new;
end $$;

drop trigger if exists bookings_dangerous_dog on bookings;
create trigger bookings_dangerous_dog before insert on bookings
  for each row execute function _guard_dangerous_dog_custody();

-- A declaration can land AFTER this INSERT. The edge accepts a runner with a service_role UPDATE,
-- then advances through enroute, arrival and the two handoff stamps; an INSERT-only gate leaves
-- every one of those doors open. Re-use the same function and token, but only while the row moves
-- TOWARD stranger custody:
--   · a non-null runner is assigned or changed;
--   · the state advances through request/accept/enroute/pickup/start;
--   · arrival or either outbound handoff stamp is newly recorded.
-- The outer old-status exemption is the outage direction. Once a row is picked_up/active the dog
-- is already out, so this trigger must never stand between that dog and home — including run-stop,
-- both return confirmations, settlement and incident/ops exits. Every nullable comparison below is
-- `is distinct from` plus an explicit non-null direction; a NULL can neither hide a move nor turn a
-- clearing/homeward write into an outward one.
drop trigger if exists bookings_dangerous_dog_move on bookings;
create trigger bookings_dangerous_dog_move before update on bookings
  for each row when (
    old.status is distinct from 'picked_up'
    and old.status is distinct from 'active'
    and (
      -- (re-verdict F1b, 2026-08-24) the runner-change arm is scoped to OUTWARD statuses. Unscoped,
      -- it trapped the one legitimate post-completion runner change: an emergency transfer bringing
      -- a return_pending dog HOME (session_transfer_accept reassigns runner_id on a completed
      -- booking, 0058:133). A dog declared dangerous while out must still come home — the header's
      -- own law, and this arm was the one place the fix round broke it.
      (new.runner_id is not null and new.runner_id is distinct from old.runner_id
       and coalesce(old.status in
         ('matching', 'runner_pending', 'confirmed', 'runner_enroute'), false))
      or (new.dog_id is distinct from old.dog_id
          and coalesce(new.status in
            ('runner_pending', 'confirmed', 'runner_enroute', 'picked_up', 'active'), false))
      or (new.status is distinct from old.status
          and coalesce(new.status in
            ('runner_pending', 'confirmed', 'runner_enroute', 'picked_up', 'active'), false))
      or (new.arrived_at is not null and new.arrived_at is distinct from old.arrived_at)
      or (new.owner_confirmed_handoff_at is not null
          and new.owner_confirmed_handoff_at is distinct from old.owner_confirmed_handoff_at)
      or (new.runner_confirmed_handoff_at is not null
          and new.runner_confirmed_handoff_at is distinct from old.runner_confirmed_handoff_at)
    )
  )
  execute function _guard_dangerous_dog_custody();

-- ⚠ THE `when` CLAUSE IS `is distinct from 'owner_handled'`, NOT `= 'runner_delegated'`.
-- Same reasoning as §C ⓑ, one layer out: a trigger `when` that evaluates to NULL does not fire,
-- and `= 'runner_delegated'` would also silently exempt any custody value a later migration adds.
-- Only the ONE value that means "the owner is holding their own leash" is exempt; everything else,
-- including anything not yet invented, goes through the gate.
drop trigger if exists session_dogs_dangerous_dog on session_dogs;
create trigger session_dogs_dangerous_dog before insert on session_dogs
  for each row when (new.custody is distinct from 'owner_handled')
  execute function _guard_dangerous_dog_custody();

-- ⚠ 🔴 THE UPDATE ARM IS A SEPARATE TRIGGER AND ITS EXTRA CONDITION IS LOAD-BEARING — WITHOUT IT
-- THIS GATE BECOMES A TRAP THAT LOCKS A DOG WITH ITS RUNNER. A `before insert or update` trigger
-- with only the custody test re-evaluates the gate on EVERY write to a delegated row —
-- `booking_id`, `hold_status`, `custody_phase`, `checked_in_at`, `service_state`, the return
-- transitions. So an owner who declares 맹견 WHILE their dog is out (or a support agent correcting
-- a wrong answer mid-session) would make every subsequent custody write raise, including the ones
-- that bring the dog home. The gate must refuse a dog going INTO a stranger's custody, and must
-- never refuse the row that is already there — least of all the write that ends it.
-- Split rather than merged because a `when` clause on an INSERT trigger cannot reference OLD.
-- `is distinct from` throughout: a NULL on either side must still count as a change.
drop trigger if exists session_dogs_dangerous_dog_move on session_dogs;
create trigger session_dogs_dangerous_dog_move before update on session_dogs
  for each row when (new.custody is distinct from 'owner_handled'
                     and (old.custody is distinct from new.custody
                          or old.dog_id  is distinct from new.dog_id))
  execute function _guard_dangerous_dog_custody();

revoke execute on function _guard_dangerous_dog_custody() from public, anon, authenticated;
grant  execute on function _guard_dangerous_dog_custody() to service_role;

comment on function _guard_dangerous_dog_custody is
  '0119 §D — 커스터디가 낯선 사람에게 넘어가는 지점(bookings INSERT/외향 UPDATE · session_dogs의 위탁 행)에서
서버가 거절한다. ⚠ `current_user` 분기 없음: 0083 §2의 가드는 클라이언트로부터 서버 컬럼을 지키므로
역할을 묻지만, 이 가드는 제품 자신으로부터 개를 지키고 제품은 service_role과 definer로 쓴다 — 역할
분기를 넣으면 실제 writer 전부가 면제된다 (게다가 definer 안에서 current_user는 함수 소유자다).
동반(owner_handled)은 통과한다 — 그게 §C 세 번째 토큰이 이름 붙일 수 있는 구제책이다';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §E  THE CRON BELT — because a raise inside an hourly loop is an outage for EVERYBODY
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ← builds on 0111 §3. The custody additions are confined to the ⓕ belt, its per-row INSERT
-- handler, and one aggregate warning after the loop; the pre-existing scheduling/money logic is
-- untouched.
--
-- 🔴 WITHOUT THIS SECTION §D SHIPS A NEW BUG, AND IT IS THE ONE THE PREVIOUS MIGRATION FIXED.
-- `generate_recurring_bookings` (cron `recurring-gen`, `7 * * * *`) originally inserted inside a
-- `for` loop with **no per-row exception handler**. The moment §D's trigger raised for one 맹견 series, the
-- whole sweep aborts — and every OTHER owner's recurring booking silently stops being generated,
-- for as long as that series exists. That is `0116 §C` verbatim ("one unparseable timestamp
-- stopped charge dispatch for EVERYBODY"), reproduced one migration later by the file that quotes
-- it. So the generator asks the gate itself and `continue`s, exactly as 0111's own ⓔ ownership
-- belt does, with the same `raise warning` first — 0111's reason applies unchanged: a silent
-- `continue` makes a skipped series indistinguishable from a series with nothing due.
--
-- ⚠ The belt is NOT the fix and must not be mistaken for one: the TRIGGER is the closure. If this
-- check drifts out of agreement with §C the trigger still refuses — the belt only decides whether
-- the sweep dies with it. (Which is why the belt calls `dog_custody_gate`, not a copy of it.)
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
  v_gate text;                 -- [0119 ⓕ] null | a dog_custody_gate refusal token
  v_gate_skips int := 0;       -- [0119 F7] refused series this sweep
  v_gate_dogs uuid[] := '{}';  -- [0119 F7] distinct refused dogs this sweep
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  for s in select * from recurring_series where not paused and dog_id is not null loop
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
      if not (s.owner_id = any(v_notified)) then          -- ⓓ once per owner per sweep
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (s.owner_id, 'booking', '반복 예약 일시 중지',
                '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null);
        v_notified := v_notified || s.owner_id;
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

    -- ⓕ [0119 §E] custody gate — `continue`, never `raise`, for 0111 ⓔ's reason AND 0116 §C's.
    -- The token-only handler immediately below is the backstop for a declaration racing this check;
    -- without it ONE refused INSERT would abort the sweep for every owner.
    -- The trigger in §D is still what refuses; this only keeps the refusal from becoming an
    -- outage. The owner is not notified here — §D's token reaches them the moment they touch a
    -- booking themselves, and a silent hourly push about a dog they cannot currently delegate is
    -- a notification with no action attached to it.
    v_gate := dog_custody_gate(s.dog_id);
    if v_gate is not null then
      v_gate_skips := v_gate_skips + 1;
      if array_position(v_gate_dogs, s.dog_id) is null then
        v_gate_dogs := v_gate_dogs || s.dog_id;
      end if;
      continue;
    end if;

    -- The pre-check is an operations belt, not a lock. A declaration can commit after it and before
    -- the INSERT trigger reads the dog. Isolate that one row in its own subtransaction: only the
    -- three custody-refusal tokens are skippable; any other P0001 (and every other SQLSTATE) remains
    -- a real sweep failure and is re-raised.
    begin
      insert into bookings
        (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
         km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
      values
        (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
         (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
         v_sched, s.km, s.pace_label, s.addons,
         s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
      returning id into v_bid;
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_gate = message_text;
      if v_gate in ('dog_dangerous_undeclared',
                    'dog_dangerous_custody_refused',
                    'dog_dangerous_breed_conflict') then
        v_gate_skips := v_gate_skips + 1;
        if array_position(v_gate_dogs, s.dog_id) is null then
          v_gate_dogs := v_gate_dogs || s.dog_id;
        end if;
        continue;
      end if;
      raise;
    end;

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
  end loop;

  -- One ops signal per sweep, not one per refused series (~70/week/series). Count series, name each
  -- dog once, and keep WARNING severity: a skipped series must remain visible without flooding.
  if v_gate_skips > 0 then
    raise warning 'recurring custody gate skipped % series; distinct dogs: %',
      v_gate_skips, array_to_string(v_gate_dogs, ',');
  end if;
  return n;
end $$;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘: 미수금 보호자는 생성 중단(항상), payments_live_since가 설정된
뒤엔 카드 없는 보호자도 중단. 보호자당 스윕 1회만 통지. 그 둘이 없으면 ≤1건 노출 한도가 거짓이 된다
+ [0111] 복사 시점 소유권 재확인 (두 번째 벨트): 시리즈의 dog/address가 시리즈 소유자의 것이 아니면
warning 후 continue — raise면 한 행이 매시간 스윕 전체를 죽인다
+ [0119 §E] the custody gate also continues. If a declaration races the check, the per-row INSERT
handler swallows only the three known refusal tokens and re-raises everything else. One WARNING per
sweep reports the refused-series count and distinct dog ids (0116 §C outage shape)';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- §F  THE LATCH — UPDATE and DELETE cannot erase a dangerous declaration
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- `dogs owner all` (0002:63) is `for all using (owner_id = auth.uid())` and `authenticated` holds
-- table-wide UPDATE, so the owner writes this field directly through the ordinary dog-profile
-- path — which is right (the declaration is theirs to make; 동물보호법 puts the duty on 소유자등,
-- and a false declaration is their exposure, not a platform opinion). But it means the refusal in
-- §D is one UPDATE away from being undone, and 「a gate that EXISTS is not a gate that GUARDS」.
--
-- So: **`declared_dangerous` is one-way.** The platform has no way to verify a de-designation —
-- a 기질평가 result or a 시·도지사 decision is a document nobody here can read — so it cannot
-- honor one, and the honest behaviour is to refuse the write rather than to accept it and hope.
-- 🟡 That leaves reversal as an ops errand with no ops surface. Named in this file's header; the
-- alternative (accept the flip) is a self-service switch that turns the whole gate off.
--
-- The other direction, `declared_none → undeclared`, is deliberately ALLOWED: it only moves the
-- owner into a state that is itself refused, so it cannot buy anything, and refusing it would mean
-- a mis-tap on a form is permanent.
--
-- ⓑ The timestamp is server-stamped on the same pass — 0083 §2's rule ("a draft born with a stamp
-- already set is a forged stamp") applied to a legal record: whatever the client sends in
-- `dangerous_declared_at` is discarded, always.
create or replace function _guard_dog_dangerous_declaration() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    new.dangerous_declared_at :=
      case when new.dangerous_status = 'undeclared' then null else now() end;
    return new;
  end if;

  -- ⓐ the latch. `is distinct from` rather than `<>` — a NULL on either side must still count as
  -- a change, and this column is NOT NULL only because §A made it so.
  if old.dangerous_status = 'declared_dangerous'
     and new.dangerous_status is distinct from 'declared_dangerous' then
    raise exception using
      errcode = 'P0001',
      message = 'dog_dangerous_declaration_final',
      detail  = '맹견 신고는 앱에서 되돌릴 수 없어요 — 기질평가 결과나 지정 해제 서류가 있다면 '
                || '문의로 보내주시면 저희가 확인하고 바꿔 드릴게요',
      hint    = '0119 §F — 지정 해제는 플랫폼이 검증할 수 없는 문서다';
  end if;

  -- ⓑ server-stamped, in both directions
  if new.dangerous_status is distinct from old.dangerous_status then
    new.dangerous_declared_at :=
      case when new.dangerous_status = 'undeclared' then null else now() end;
  else
    new.dangerous_declared_at := old.dangerous_declared_at;
  end if;
  return new;
end $$;

drop trigger if exists dogs_dangerous_declaration on dogs;
create trigger dogs_dangerous_declaration before insert or update on dogs
  for each row execute function _guard_dog_dangerous_declaration();

revoke execute on function _guard_dog_dangerous_declaration() from public, anon, authenticated;
grant  execute on function _guard_dog_dangerous_declaration() to service_role;

comment on function _guard_dog_dangerous_declaration is
  '0119 §F — ⓐ declared_dangerous는 편도다. 보호자가 자기 강아지 행을 직접 UPDATE할 수 있으므로
(0002:63 dogs owner all), 되돌릴 수 있는 신고는 §D의 거절을 UPDATE 한 번 거리로 만든다. 지정 해제는
플랫폼이 읽을 수 없는 문서라서 반영할 수 없고, 정직한 동작은 거절이다. declared_none→undeclared는
일부러 허용 — 그 상태 자체가 거절되므로 아무것도 사지 못하고, 막으면 폼 오탭이 영구가 된다.
ⓑ dangerous_declared_at은 서버만 찍는다 (0083 §2: 미리 담아 온 도장은 도장이 아니다)';

-- DELETE+recreate is an UPDATE latch with one extra statement. `dogs owner all` authorizes DELETE,
-- so an owner could otherwise remove a declared-dangerous row (when no FK blocks it) and recreate
-- an evasive declared-none dog. This guard is deliberately INVOKER and caller-role scoped, exactly
-- like 0057/0058: inside it current_user remains authenticated/anon for an app write, while postgres
-- and service_role remain the ops escape hatch for a verified de-designation or data correction.
create or replace function _guard_dangerous_dog_delete() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon')
     and old.dangerous_status = 'declared_dangerous' then
    raise exception using
      errcode = 'P0001',
      message = 'dog_dangerous_declaration_delete_final',
      detail  = '맹견 신고가 있는 강아지는 앱에서 삭제할 수 없어요 — 지정 해제 서류가 있다면 '
                || '문의로 보내주시면 운영자가 확인하고 처리해 드릴게요',
      hint    = '0119 §F — DELETE 후 재생성으로 편도 신고를 지울 수 없다';
  end if;
  return old;
end $$;

drop trigger if exists dogs_dangerous_delete on dogs;
create trigger dogs_dangerous_delete before delete on dogs
  for each row execute function _guard_dangerous_dog_delete();

revoke execute on function _guard_dangerous_dog_delete() from public, anon, authenticated;
grant  execute on function _guard_dangerous_dog_delete() to service_role;

comment on function _guard_dangerous_dog_delete is
  '0119 §F — closes DELETE+recreate around the declared_dangerous latch. INVOKER current_user
refuses app-role deletes while leaving postgres/service_role available for verified ops changes';


-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY, DO NOT ASSUME — fail closed, in BOTH directions (0111's shape)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Checking only that the triggers exist would let the failure that turns a safety gate into an
-- OUTAGE ship silently: a `session_dogs` trigger with no `when` clause refuses 동반 attendance
-- too, and that is the one path this whole design keeps open on purpose.
do $$
declare r record; v_def text;
begin
  -- tgtype is checked as an exact bit-set: ROW=1, BEFORE=2, INSERT=4, DELETE=8, UPDATE=16.
  -- Each trigger is fetched independently. That makes its table/event/timing/enabled/function/WHEN
  -- facts belong to that trigger alone; a healthy sibling cannot donate a substring through an
  -- aggregate and hide a mutated definition.
  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'bookings'
     and t.tgname = 'bookings_dangerous_dog';
  if not found then
    raise exception '0119: bookings_dangerous_dog is missing from public.bookings';
  end if;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 7
     or r.tgfoid is distinct from '_guard_dangerous_dog_custody()'::regprocedure::oid
     or r.tgqual is not null then
    raise exception '0119: bookings_dangerous_dog has the wrong event/timing/enabled/function/WHEN shape';
  end if;

  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'bookings'
     and t.tgname = 'bookings_dangerous_dog_move';
  if not found then
    raise exception '0119: bookings_dangerous_dog_move is missing from public.bookings';
  end if;
  v_def := r.def;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 19
     or r.tgfoid is distinct from '_guard_dangerous_dog_custody()'::regprocedure::oid
     or r.tgqual is null
     or v_def is null
     or v_def not ilike '%old.status IS DISTINCT FROM ''picked_up''%'
     or v_def not ilike '%old.status IS DISTINCT FROM ''active''%'
     or v_def not ilike '%new.runner_id IS NOT NULL%'
     or v_def not ilike '%new.runner_id IS DISTINCT FROM old.runner_id%'
     or v_def not ilike '%new.dog_id IS DISTINCT FROM old.dog_id%'
     or v_def not ilike '%new.status IS DISTINCT FROM old.status%'
     or v_def not ilike '%new.arrived_at IS NOT NULL%'
     or v_def not ilike '%new.arrived_at IS DISTINCT FROM old.arrived_at%'
     or v_def not ilike '%new.owner_confirmed_handoff_at IS NOT NULL%'
     or v_def not ilike '%new.owner_confirmed_handoff_at IS DISTINCT FROM old.owner_confirmed_handoff_at%'
     or v_def not ilike '%new.runner_confirmed_handoff_at IS NOT NULL%'
     or v_def not ilike '%new.runner_confirmed_handoff_at IS DISTINCT FROM old.runner_confirmed_handoff_at%'
     or position('runner_pending' in lower(v_def)) = 0
     or position('confirmed' in lower(v_def)) = 0
     or position('runner_enroute' in lower(v_def)) = 0
     or position('picked_up' in lower(v_def)) = 0
     or position('active' in lower(v_def)) = 0
     -- (F1b) 'matching' appears ONLY in the runner-arm's outward-status scope — its absence means
     -- the arm went unscoped again and a completed-booking emergency transfer home is trapped.
     or position('matching' in lower(v_def)) = 0 then
    raise exception '0119: bookings_dangerous_dog_move lost its outward-only or already-in-custody exemption'
      using hint = 'assignment/acceptance/enroute/handoff/pickup are gated; picked_up/active rows and every homeward write are exempt';
  end if;

  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'session_dogs'
     and t.tgname = 'session_dogs_dangerous_dog';
  if not found then
    raise exception '0119: session_dogs_dangerous_dog is missing from public.session_dogs';
  end if;
  v_def := r.def;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 7
     or r.tgfoid is distinct from '_guard_dangerous_dog_custody()'::regprocedure::oid
     or r.tgqual is null or v_def is null
     or v_def not ilike '%new.custody IS DISTINCT FROM ''owner_handled''%' then
    raise exception '0119 OVER-REACH: session_dogs_dangerous_dog lost its own owner_handled WHEN exemption'
      using hint = '동반(owner_handled)은 부킹을 만들지 않고 소유자가 리드를 쥔다 — 거절 대상이 아니다';
  end if;

  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'session_dogs'
     and t.tgname = 'session_dogs_dangerous_dog_move';
  if not found then
    raise exception '0119: session_dogs_dangerous_dog_move is missing from public.session_dogs';
  end if;
  v_def := r.def;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 19
     or r.tgfoid is distinct from '_guard_dangerous_dog_custody()'::regprocedure::oid
     or r.tgqual is null or v_def is null
     or v_def not ilike '%new.custody IS DISTINCT FROM ''owner_handled''%'
     or v_def not ilike '%old.custody IS DISTINCT FROM new.custody%'
     or v_def not ilike '%old.dog_id IS DISTINCT FROM new.dog_id%' then
    raise exception '0119 OVER-REACH: session_dogs_dangerous_dog_move lost its own exemption or movement condition'
      using hint = '이미 위탁 중인 행의 쓰기(반환 포함)까지 거절하게 된다 — 게이트가 덫이 된다';
  end if;

  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'dogs'
     and t.tgname = 'dogs_dangerous_declaration';
  if not found then
    raise exception '0119: dogs_dangerous_declaration is missing from public.dogs';
  end if;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 23
     or r.tgfoid is distinct from '_guard_dog_dangerous_declaration()'::regprocedure::oid
     or r.tgqual is not null then
    raise exception '0119: dogs_dangerous_declaration has the wrong event/timing/enabled/function/WHEN shape';
  end if;

  select t.tgenabled, t.tgtype::int as tgtype, t.tgqual, t.tgfoid,
         pg_get_triggerdef(t.oid) as def
    into r
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and c.relnamespace = 'public'::regnamespace
     and c.relname = 'dogs'
     and t.tgname = 'dogs_dangerous_delete';
  if not found then
    raise exception '0119: dogs_dangerous_delete is missing from public.dogs';
  end if;
  if r.tgenabled is distinct from 'O' or r.tgtype is distinct from 11
     or r.tgfoid is distinct from '_guard_dangerous_dog_delete()'::regprocedure::oid
     or r.tgqual is not null then
    raise exception '0119: dogs_dangerous_delete has the wrong event/timing/enabled/function/WHEN shape';
  end if;

  -- The rule must actually refuse an undeclared dog. A gate that exists is not a gate that guards.
  if dog_custody_gate(null) is null then
    raise exception '0119: dog_custody_gate(null) returned NULL — the gate fails OPEN';
  end if;

  raise notice '0119: 6 gate triggers verified independently; outward and homeward WHEN clauses hold; the gate refuses a null dog';
end $$;
