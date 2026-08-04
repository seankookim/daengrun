# SESSION HANDOFF — 2026-08-04 (lilac repaint · precision-director · marketplace fixes)

Companion docs to read: `docs/audit-2026-08-02.md` (audit ledger), `precision-director-install/skills/precision-director/SKILL.md` + its `references/` (the operating protocol — READ AND FOLLOW IT), `/tmp` labs are GONE (ephemeral) — approved mockups transcribed below.
Opener for next session: **"read docs/session-handoff.md fully, then continue"**.

## 1. Goal & current state
daengrun (도그스하이) — RN/Expo + Supabase dog-running marketplace, 반포 pilot. This session:
- **App-wide "tailored lilac" repaint: DONE** [verified-now via commits] — owner home, runner home, community(동네 신문), my(여권), alerts(안내판), bottom nav, club widget (white elevated card, one 클럽 홈 door), club home = root hub (Variant D: photo strip + editorial masthead + boarding-pass ticket + role-aware doors), runner selection (V3 비교 시트 — deck carousel deleted). Swamp green (forest/volt) fully retired app-wide [verified-now: grep 0].
- **Marketplace flow fixes: DONE, partly awaiting deploy** — see §7/§8.
- **precision-director skill + 5 opus agents: BUILT** [verified-now], staged in `precision-director-install/` (device bridge blocks `.claude` writes); Sean must run installer (§7).
- Branch `redesign-v4`, ~15 commits ahead. Last commits: `be81c59` (runner UX), `7b58308` (V3 selection), `120f068` (ticket doors act), `c60cbc1` (precision-director round 1), `62daed6`, `43f52ad`, `03fb7ca`, `2bf70f9`, `afd4dcd` (repaint waves).

## 2. Standing doctrines (Sean's invariants — outlive any task)
- **Big UI decisions get an HTML mockup lab first → Sean picks by number → then implement.** Labs: 340px phone frames on #1C1837 backdrop.
- **precision-director protocol**: Fable session directs/arbitrates/accepts; opus subagents execute substantial work; **boss-verify every agent claim with your own greps/diffs before committing** (Sean exploded when agent reports were trusted unverified).
- **Server migrations**: harness-gated (`supabase/tests/harness.sh` in container) + 5-agent adversarial workflow (author → adversarial reviewers executing RLS paths → test author → revision). It caught P0/P1 every round.
- Commit gate: `tsc --noEmit` (app/) + `node scripts/check-rpc-contracts.mjs`. Never claim device-visual success — Sean smoke-tests.
- Lilac tokens only (src/theme.ts `lilac`); coral-text law (coral = fill/edge/dot; white text only on ≥#C6472C stop); no forest #0F1D13 / volt #C6F542; night = #1C1837; gold scarce; fonts only Black Han Sans (once/screen) + Oswald (numbers, lineHeight ≥1.2× or tops clip — "UU" bug) + IBM Plex Sans KR. Detail text ≥12pt; `lilac.dim` is now #7C76A0.
- Buttons big when space allows; no dead/mislabeled buttons (doors must DO the action); no fabricated data ever — bind real fields or omit.
- 홈 = 루트: club banner/card always lands `/club/[id]`; the home shows public session info; single CTA.

## 3. Working-relationship norms
- Sean tests on real device and reports with screenshots; his complaints are precise — trust them over agent claims (he caught 3 rounds of agent overshoot).
- Wants opus agents used "accurately" with fable as boss; got angry at 1.8× font overshoot and unverified "done"s. Give honest ship/no-ship, admit fakes (he asks "is X real?" — answer with evidence, e.g. matchFor pace target was hardcoded).
- Approvals are short ("go ahead", "sure", picks by number). He speaks Korean-product/English-mixed; UI copy in warm honest Korean.
- Session model: fable main loop; subagents `model: opus` (alias, resolves to Opus 5 tier).

## 4. Decision log (what & why)
- Scroll-collapse morph on owner home: kept (fixed to native-driver transforms, geometry-simulated 0px error) — the "vertical scroll" Sean scrapped was the **runner-selection deck**, not this. [verified-now]
- Runner selection = V3 비교 시트: roster rows + persistent bottom sheet, ONE 지명 CTA, AI-1순위 pre-selected; rejected deck (physics+invisible touch layer ate taps — 도윤 worked only by geometry luck).
- matchFor pace: formula symmetric-|distance| kept (Sean's 6-vs-9-for-8 example already correct); **target was fake (hardcoded 420)** → now bound to draft.pace / rebook `pace` param.
- 러너 변경 = rebook mode on SAME booking (`/owner/matching?mode=rebook&current=&pace=`), never new booking (dog_slot_clash was the symptom). Edge fn `request_runner` + `runner_accept` now CAS (`.update().eq/in(status)...select()` 0-rows→409) — reviewer F1 TOCTOU.
- Declined open-pool reappearance: session-local `declinedIds` Set filter in runner home (server decline-log = proper fix, deferred).
- fetchRunnerInbox/fetchOpenRequests read `marketplace_open_requests` VIEW (0042 choke point) — direct bookings reads return 0 rows under RLS; this was why runners never saw open requests. Inbox legs error-isolated.
- W4 filmstrip morph reserved for fitness-report hero (Sean likes its boldness). Club card: no photo banner, holo monogram identity.

## 5. Architecture & contracts (tricky, DO-NOT-REFACTOR)
- `enforce_booking_transition` trigger (0047 supersedes 0005): same-status updates pass (`old=new → return new`) — re-nomination legality depends on this. confirmed→runner_pending forbidden.
- 0042 view `marketplace_open_requests` = ONLY open-pool read path (flat columns, definer, is_active_runner()). Client mapper `mapOpenRequestView` in api.ts.
- Owner-home morph: 54 dots, two static layers, crossfade only via `ringOpacity/lineOpacity/lineSlide`; `useNativeDriver:true`; static heights + transform collapse with inverse-scale `s.heroInner` — do NOT reintroduce height animation.
- Club home `[id].tsx` fetches `club_delegation_board` for role-aware doors (dogs.isMine / me.committed / isHost).
- Oswald numbers need explicit lineHeight ≥1.2×fontSize (ascender clip); NEVER `adjustsFontSizeToFit` on custom-font values (mis-measures → crushed text).
- Git on device: locks can't unlink → `mv .git/*.lock _to_delete/git-locks/` before+after every git op; also `tmp_obj_*`.
- Device stage cache SERVES STALE FILES — **always md5sum staged vs device (`device_bash md5sum`) before basing edits**; prefer pulling via `device_bash` sed/base64 or patching on-device with `node -e` anchored replaces.
- Bridge blocks writes to `.claude/**` → installer pattern (`precision-director-install/install.sh` from repo ROOT).
- Cloud container: network allowlist blocks supabase.co (no remote DB probes); device_bash has NO network; supabase creds in `app/.env` (service key exists — useless from container).
- Harness runs in container `/tmp/daengrun/supabase` — GONE (ephemeral). Rebuild: tar from device → base64 → md5 verify (see docs/audit-2026-08-02.md rituals); PG must start in same Bash call.

## 6. File map (this session's surface)
- `app/app/owner/home.tsx` — lilac editorial home, brand row, native-driver morph, deep-coral CTA, dark radar, ranking ticker, conditional today-ticket. `matching.tsx` — V3 compare sheet + rebook + paceSecOf. `schedule.tsx` — 러너 변경 → matching(mode/current/pace). `request.tsx` — untouched booking creation.
- `app/app/runner/home.tsx` — bib + ledger(오늘 확보 line) + real accept/decline doors + declinedIds filter + club engine. `app/app/community.tsx` 동네 신문 · `my.tsx` 여권 · `alerts.tsx` 안내판.
- `app/app/club/[id].tsx` root hub (Variant D). `app/src/components/clubcard.tsx` white club card. `bottomnav.tsx` lilac glass. `ui.tsx` Row style widened.
- `app/src/lib/api.ts` — mapOpenRequestView + view reads, declineBooking, inbox resilience.
- `supabase/functions/transition-booking/index.ts` — CAS request_runner/runner_accept, runner validation, displaced notify. **NOT DEPLOYED** [verified-now].
- `precision-director-install/**` — skill+agents+install.sh. `app/scripts/check-rpc-contracts.mjs` gate.

## 7. Pending on Sean's side (ordered)
1. `cd /Users/sean/dev/daengrun && sh precision-director-install/install.sh` (he ran it from app/ — failed).
2. `supabase functions deploy transition-booking` — CAS race fix + 러너 변경 server half INERT until this.
3. `supabase db push` — 0051/0052/0053 (harness-green 181/196/202) still unpushed [from-history].
4. `git push` (redesign-v4). 5. Device smoke: V3 selection, 러너 변경 e2e, accept/decline doors, owner scroll, club card.

## 8. Known bugs / gotchas
- 5pm accept-409 mystery: busy formula correct; likely a third overlapping confirmed booking on s4kim2025 (test residue) [uncertain — verify in DB]. Improve error to name conflicting job when next editing edge fn.
- Reviewer flagged, NOT fixed: schedule.tsx offers 일정 변경 요청 on pending bookings but server requires confirmed → guaranteed 409 dead button; `cancelled` bookings share that else-branch; api.ts `runnerId: 'minjun'` mock in fetchMyBookings sheet lookup.
- matching.tsx roster: long name + 현재 지명 + 마스터 at max font scale may clip tier [uncertain — device check].
- my.tsx MRZ/✎ are the only <11pt exemptions. Community "제 128호" removed — never reintroduce fabricated serials.
- `.fuse_hidden*` file in app/src/components — ignore, don't commit.

## 9. Ideas discussed, not built
- **NEXT ENGAGEMENT (designed, approved direction): owner-side availability gating** — "customer shouldn't see a busy runner at all". Design: security-definer RPC (e.g. `runners_available_for(p_booking uuid)`) filtering by interval overlap (aEnd = start + km*8+25min formula — keep consistent with hold/accept) against LIVE statuses + availability rules; matching screen consumes it instead of/joined with fetchCertifiedRunners; RLS keeps runner schedules private. Requires migration → full harness + 5-agent adversarial workflow. Also add conflict-time to accept-409 message in same edge-fn pass.
- Server decline-log table (booking_declines) so declined requests never resurface across restarts; open-pool view excludes decliner.
- W4 filmstrip as fitness-report hero. §3b private photo bucket migration (deferred pre-session, still open). Choreography 4 motions (flap flip, seal stamp, stub tear, ring drain) — want device eyes. Runner monthly/cumulative earnings + owner D-day badge + unread badges = small RPC additions Sean was told about.

## 10. Next 1–3 steps
1. [read-only] Verify Sean ran installer + deploy + push (§7); re-verify md5 of any file before editing (stale-cache law).
2. [needs-harness, local-edit] Availability-gating migration 0054 + edge-fn error enrichment (§9 design) via precision-director: scout→implement→adversarial review→harness→commit. Rebuild container harness first.
3. [local-edit] Reviewer leftovers: 일정 변경 gate on confirmed-only; decline-log design.

## 11. Verification commands
Read-only: `git -C /Users/sean/dev/daengrun log --oneline -15`; `git status --short`; tsc gate `cd app && ./node_modules/.bin/tsc --noEmit`; `node scripts/check-rpc-contracts.mjs`; swamp scan `grep -rn "0F1D13\|C6F542" app/app app/src`; md5 ritual before edits.
Expensive/destructive (Sean only): functions deploy, db push, git push.
