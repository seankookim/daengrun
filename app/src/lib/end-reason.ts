// Why a run ended, in the runner's words — ONE table for every screen that prints it.
//
// ═══ WHY THIS IS ITS OWN MODULE (copy-hierarchy-3, 2026-09-25 second gap sweep) ═══
// The same `runs.end_reason` value had four different names across screens, and one screen printed
// the raw English token. `runner/return-seal.tsx` kept a private 4-member copy of this table and
// fell back to `?? s.endReason`, so an `incident` run (0045:259, 0058:165, 0069:211, 0070:212 all
// write it, and runner-job-route.ts routes `incident_review` + a stamped run end to that screen)
// drew 「종료 사유 incident」 in a Korean UI. The table below is api.ts's, moved here unchanged so the
// ledger (`fetchLedger`) and the seal screen read the same words; the pins in
// `test/end-reason.test.cjs` read the enum out of 0001_init.sql and fail if a member is unmapped.
//
// [0132] The `end_reason` enum's SIX members (0001:18), every one mapped.
// ⚠ An unmapped value must resolve to null, NEVER to the raw token — `CHARGE_LABEL`'s
//   `?? d.chargeLabel` fallback printed the English words 'none' and 'hold' as chips in a
//   Korean UI, and that is the bug this comment exists to not repeat. If a seventh member is
//   ever added, a caller goes quiet instead of speaking English (`END_REASON_LABEL[x] ?? null`).
// `owner_forced` and `owner_request` share one phrase deliberately: they are the same event to
// a runner (owner-caused end) and 0101 §A prices them IDENTICALLY, guarantee included. The
// distinction is who may declare it — server-only vs runner-declarable (0083's whitelist) —
// which is an ops fact, not something a runner can act on. Inventing two words for one
// outcome would imply a difference in the money that does not exist.
export const END_REASON_LABEL: Record<string, string> = {
  completed: '완주',
  dog_condition: '강아지 상태로 중단',
  owner_request: '보호자 요청으로 중단',
  owner_forced: '보호자 요청으로 중단',
  runner_personal: '러너 사정으로 중단',
  incident: '사고로 중단',
};
