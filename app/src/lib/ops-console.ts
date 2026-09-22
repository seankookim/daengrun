// The PURE half of the 0206 ops screens — every sentence the strand list, the strand detail and
// the stalled-handoff list compose, with no router, no supabase and no store. `app/test/
// ops-console.test.cjs` bundles this real source (the late-copy idiom) and pins the table, which
// is the only way these sentences get tested at all: `app/test/*.cjs` cannot import a `.tsx`
// route module.
//
// 🔴 **EVERY FUNCTION HERE GATES ON THE RAW SERVER WORD AND RETURNS DISPLAY COPY** — the standing
//    STATUS_MAP law. `rawStatus` is `active` | `incident_review` out of `ops_stranded_returns()`
//    (0206 §A carries it unmapped on purpose) and is never rendered; what a screen prints is one
//    of the sentences below.
//
// ⚠ **NULL IS AN ANSWER AND NEVER A ZERO.** `minutesStranded`, `strandMinutes`, `notifiedAt` and
//   `opsAlertedAt` are each genuinely absent in a state the product reaches, and each absence
//   means something DIFFERENT from any number. Every function here takes the null and says the
//   absent thing in words rather than printing a 0 or an em-dash.

/** 「3시간 20분째」 — how long this return has been stranded. `null` ⇒ the server did not give us a
 *  number, which is not 「0분째」. Minutes below an hour keep the minute form so a fresh strand does
 *  not read as 「0시간」. */
export function strandAgeLabel(minutesStranded: number | null): string | null {
  if (minutesStranded === null || !Number.isFinite(minutesStranded)) return null;
  const m = Math.max(0, Math.floor(minutesStranded));
  if (m < 60) return `${m}분째`;
  const h = Math.floor(m / 60);
  const rem = m % 60;
  return rem === 0 ? `${h}시간째` : `${h}시간 ${rem}분째`;
}

/** What state this stranded return is actually in, as a sentence an operator can act on.
 *  ⚠ The `incident_review` arm is the one that matters and it is NOT a cosmetic difference:
 *    0096 lets late stamps land on such a row and refuses to seal it, so it cannot settle at all
 *    until an operator acts — which is why 0201's codex #2 widened the sweep to carry it whatever
 *    its stamps say. The copy says so instead of showing two ticks and implying all is well. */
export function strandStateLabel(
  rawStatus: string, runnerStamped: boolean, ownerStamped: boolean,
): string {
  if (rawStatus === 'incident_review') {
    return runnerStamped && ownerStamped
      ? '담당자 확인 대기 — 양측이 늦게 확인했지만 봉인되지 않았어요'
      : '담당자 확인 대기 — 아무도 반환을 확인하지 않아 넘어왔어요';
  }
  if (runnerStamped && !ownerStamped) return '러너만 확인했어요 — 보호자 확인이 없어요';
  if (!runnerStamped && ownerStamped) return '보호자만 확인했어요 — 러너 확인이 없어요';
  if (!runnerStamped && !ownerStamped) return '양쪽 다 확인하지 않았어요';
  // Both stamped on an `active` row: 0206 §A's predicate excludes it, so reaching this line means
  // the row changed under the screen. Said plainly rather than left as a blank.
  return '양쪽 확인이 모두 들어왔어요 — 목록을 새로고침해주세요';
}

/** The deadline the SWEEP is currently using, from `ops_flags.return_strand_minutes`.
 *  🔴 NULL is the SHIPPED value and means the strand arm does nothing at all (0193 §A · 0201:714),
 *    so new strands stop being announced. An operator looking at this list has to know that, or
 *    they will read an empty list as 「nothing is stranded」. */
export function strandDeadlineNote(strandMinutes: number | null): string {
  if (strandMinutes === null || !Number.isFinite(strandMinutes)) {
    return '좌초 알림이 꺼져 있어요 — 새로 좌초되는 예약은 알림이 오지 않아요 (이미 알림이 간 건만 보여요)';
  }
  return `러닝 종료 후 ${Math.max(0, Math.floor(strandMinutes))}분이 지나면 좌초로 봅니다`;
}

/** Has the roster actually been paged about this row yet? `null` ⇒ not yet — it is in the list
 *  because it is past the deadline, and the next sweep tick will ring it. */
export function strandNotifiedNote(notifiedAt: string | null): string {
  return notifiedAt === null
    ? '아직 알림이 가지 않았어요 — 다음 점검에서 발송돼요'
    : '담당자 알림이 발송된 건이에요';
}

/** Who stamped the pickup handoff, and who we are waiting on. Names may be absent (a profile with
 *  no name); the fallback is a ROLE word, never a blank and never an invented name. */
export function handoffWaitingLabel(
  ownerStamped: boolean, runnerStamped: boolean,
  ownerName: string | null, runnerName: string | null,
): string {
  const owner = ownerName ?? '보호자';
  const runner = runnerName ?? '러너';
  if (ownerStamped && !runnerStamped) return `${owner} 확인 완료 — ${runner} 확인을 기다리는 중`;
  if (!ownerStamped && runnerStamped) return `${runner} 확인 완료 — ${owner} 확인을 기다리는 중`;
  // 0206 §B's predicate is an XOR, so neither of these is reachable through the list; both are
  // said in words rather than drawn as a blank if the row moves under the screen.
  if (ownerStamped && runnerStamped) return '양쪽 확인이 끝났어요 — 목록을 새로고침해주세요';
  return '아직 아무도 확인하지 않았어요 — 목록을 새로고침해주세요';
}

/** 🔴 0183's PENDING state, said out loud. `escalatedAt` set with `opsAlertedAt` NULL does NOT
 *  mean 「we do not know」 — it means the two parties were told while the ops roster was EMPTY, and
 *  arm ⓔ retries every tick. An operator reading a blank there would conclude the escalation
 *  failed; it is waiting for a roster row to exist. */
export function handoffAlertNote(escalatedAt: string | null, opsAlertedAt: string | null): string {
  if (escalatedAt === null) return '아직 승격되지 않았어요';
  if (opsAlertedAt === null) {
    return '양측에는 알렸지만 담당자 알림은 대기 중이에요 — 담당자 명부가 비어 있어 점검 때마다 다시 시도해요';
  }
  return '양측과 담당자 모두에게 알렸어요';
}

/** The local restatement of `ops_resolve_return_tx`'s `memo_required`, so the operator learns the
 *  reason from the button instead of from a round trip. The SERVER enforces it regardless — this
 *  is a courtesy, never the rule (`resolve_return.ts` says the same thing about its own copy). */
export const MEMO_REQUIRED_KO = '무엇을 확인했는지 적어주세요 — 판정에는 기록이 필요해요';

/** `null` when the memo is acceptable, the Korean refusal otherwise. */
export function memoRefusal(memo: string): string | null {
  return memo.trim() === '' ? MEMO_REQUIRED_KO : null;
}

/** What `opsResolveReturn` actually did, for the success strip. Three genuinely different
 *  outcomes and the copy separates them: a fresh resolution that settled, a fresh resolution that
 *  did NOT settle (the RPC requires a quote, so this is rare and worth saying), and a re-call on a
 *  booking somebody already resolved. */
export function resolveOutcomeLabel(
  r: { resolved: boolean; settled: boolean; unchanged: boolean },
): string {
  if (r.unchanged) return '이미 정리된 예약이에요 — 아무것도 바뀌지 않았어요';
  if (r.resolved && r.settled) return '반환을 정리하고 정산까지 마쳤어요';
  if (r.resolved) return '반환을 정리했어요 — 정산은 아직이에요, 담당자에게 확인해주세요';
  return '서버가 아무것도 바꾸지 않았어요 — 목록을 새로고침해주세요';
}
