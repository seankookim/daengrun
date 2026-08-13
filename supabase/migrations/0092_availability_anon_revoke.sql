-- ═══ 0092: runner_availability_rules — a stranger should not know when a runner is out alone ═══
--
-- ═══ §0 WHAT WAS MEASURED, IN PRODUCTION, WITH NO ACCOUNT ═══
-- Found by the post-deploy canary on 2026-08-13, minutes after 0076–0091 landed. This is not a
-- new hole and 0091 did not open it: `0002:77` has shipped since 2026-07. It had been RECORDED
-- (0088's follow-up 2, and 124 G1 whitelists the table with a 🔴) but never MEASURED, so nobody
-- knew what it actually returned. It returns this:
--
--     GET /rest/v1/runner_availability_rules?select=*        (anon key only, no account)
--       → 200, 63 rows, 9 distinct runners
--          {runner_id, weekday, start_min, end_min}  — every runner's whole week
--     GET /rest/v1/available_runners?select=profile_id,name,district     (also anon)
--       → 200, name + 동네
--
-- Join them on the runner's profile id and **6 of those 9 runners are nameable right now**, by
-- someone with no account: 이름, 동네, and the hours they are outside on foot. Membership in
-- `available_runners` is availability-dependent, so a stranger polling over a week very likely
-- reaches all 9. Most are 반포동 — one pilot neighbourhood, a handful of people.
--
-- This is not a data-classification argument. Our runners walk alone, outdoors, on a schedule
-- they published to get work, and the schedule is the product. Publishing WHO and WHERE together
-- with WHEN is a different fact from any of the three alone, and it is the one a stranger wants.
--
-- ═══ §A WHY IT SURVIVED, WHICH IS THE SAME SENTENCE AS 0088'S ═══
--     0002:77  create policy "avail rules public read" on runner_availability_rules
--                for select using (true);
--
-- `using (true)`. No `to` clause, no `auth.uid()` term. **An RLS policy with no caller term is
-- not an access rule, it is a row filter** — 0088 §0 wrote that sentence about `profiles` while
-- this table sat two lines below it in the same file. The lesson generalised and the sweep did
-- not: 124 G1 pins the anon-readable table LIST, so this table is inside a whitelist that was
-- built to catch new exposures, marked 🔴, and shipped green. A whitelist entry with a warning
-- emoji is documentation, not a gate.
--
-- ═══ §B WHY THE ANON REVOKE IS FREE (verified, not assumed) ═══
-- Every reader of this table is behind the login redirect. `app/app/index.tsx:20` is
-- `if (!loading && !auth) router.replace('/login')`, and there is no logged-out data screen:
--   · `fetchRunnerAvailability` (api.ts:1466) — 러너 본인 편집기, own rows
--   · `saveMyAvailability` (api.ts:1483) — writes, `auth.getUser()` first
--   · `fetchRunnerProfile` (api.ts:1898) — the storefront, called from `owner/matching.tsx:194`
--     and `runner-profile/[id].tsx:72/92`. Both are authenticated screens.
-- So `anon` has no legitimate read, and removing it costs the app nothing. This is the check
-- 0088 §B taught: the union of every reader across all history, not "which build is live".
--
-- ═══ §C WHAT THIS DOES **NOT** CLOSE — say it here or it will read as closed ═══
-- ⚠ **Any AUTHENTICATED user can still read every runner's full schedule in bulk.** `using (true)`
-- still matches them; only the `anon` GRANT is gone. Signing up is free, so this raises the cost
-- of the attack from "nothing" to "one email address" — real, but not a wall.
--
-- The honest fix for the bulk half is that the storefront should ask for ONE runner's schedule
-- through a definer function instead of the client reading the table, the same shape as 0088 §E's
-- `incident_contact`. That is a bigger change on a surface this session does not own (the
-- availability definitions are three deliberately distinct predicates — CLAUDE.md DO-NOT-REFACTOR),
-- and it needs a product call about what a 보호자 may see before booking. **It is written up for
-- Sean rather than done quietly here.** What is done here is the half that is free, verified, and
-- removes the no-account case entirely.
--
-- Also deliberately NOT touched, to keep this reversible and small:
--   · `runners` (profile_id, tier, bio) — anon-readable, pseudonymous, no name. Lower harm, and
--     it is the runner directory another team owns.
--   · `available_runners` (0015) — the definer view that supplies the name half of the join.
--     Sealing it would break the storefront, and 124 G6 already pins its column list. Without the
--     schedule, name + 동네 is the storefront working as intended.
-- Removing the schedule is what breaks the join, and it is the cheapest of the three to remove.
--
-- ═══ §D THE CHANGE ═══
-- A grant, not a policy edit. Dropping `avail rules public read` would also cut off the
-- storefront's authenticated read, which is a real feature — 128 A3 pins that it survives, so
-- nobody "finishes the job" by deleting the policy and silently breaking 러너 프로필.
revoke select on runner_availability_rules from anon;

-- Explicit rather than implied: `authenticated` keeps its read (0002:77's policy still governs
-- WHICH rows), and service_role is untouched. Stating both means a future blanket revoke reddens
-- a pin instead of turning the storefront off in production.
grant select on runner_availability_rules to authenticated;

comment on table runner_availability_rules is
  '0092: 러너 주간 가용시간. anon SELECT 취소됨 — 계정 없는 사람이 특정 러너의 이름·동네·야외
활동 시간대를 함께 알 수 있었다 (2026-08-13 프로덕션 측정: 9명 중 6명 실명 조인 가능).
⚠ 로그인한 사용자는 여전히 전체 러너의 스케줄을 대량으로 읽을 수 있다 — 0002:77의
`using (true)`가 그대로다. 그 절반은 스토어프런트를 definer 함수로 옮겨야 닫히고, 그건
보호자가 예약 전에 무엇을 볼 수 있어야 하는가라는 제품 결정이다 (Sean 대기 중).';
