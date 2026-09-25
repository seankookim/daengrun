// Which phase the runner's receipt (`runner/done.tsx`) is drawn for — as pure data.
//
// ═══ WHY THIS EXISTS (runner-journey-3, 2026-09-25 sweep) ═══
// The receipt had ONE face for four different moments. It said 「{dog}를 보호자에게 안전하게
// 인계해 주세요」 whenever no ops resolution existed — including on a run the server had SETTLED,
// with the dog long home; it drew the loud-fail 「러닝 화면에서 다시 정산하면 실제 금액으로
// 확정돼요」 strip on every unsettled receipt — including the return ceremony, where the run screen
// is not the door (`settle_run_tx` answers `return_not_sealed`) and the seal screen is; and it kept
// the coral 「다음 요청 보기」 while the work gate (0092) was holding the runner off new requests.
//
// The four phases, and the order is the contract:
//   estimate — no booking param: run.tsx's freeze-FAILED route, where the in-memory estimate is
//              the honest thing to show and the run screen really is the retry door.
//   settled  — the server settled this booking (`rawStatus === 'completed'`, computed by the caller;
//              never `sealedAt`, which is the stranded state). Checked BEFORE custody: a settled
//              receipt must never ask for a handoff, whatever else the row says.
//   custody  — `picked_up`/`active` and not settled: the dog is still with the runner, the return
//              ceremony is the next step and `/runner/return-seal` is its door.
//   pending  — anything else (`incident_review`, `refund_pending`, …): a person has to look, and
//              there is no door the runner can press that would change it.
import { inCustodyPhase } from './custody-ping-policy';

export type ReceiptPhase = 'estimate' | 'settled' | 'custody' | 'pending';

export function receiptPhase(i: {
  paramBid: string | null | undefined;
  settled: boolean;
  rawStatus: string | null | undefined;
}): ReceiptPhase {
  if (!i.paramBid) return 'estimate';
  if (i.settled) return 'settled';
  if (inCustodyPhase(i.rawStatus)) return 'custody';
  return 'pending';
}
