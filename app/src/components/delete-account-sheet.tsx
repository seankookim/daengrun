// 계정 삭제 확인 시트 — App Store 5.1.1(v) · 개인정보보호법 제37조.
// Contract: docs/contracts/account-deletion-contract.md §C.2 (the order of the disclosure is fixed
// there, not a styling choice).
//
// ═══ WHY A SHEET AND NOT `Alert.alert` ════════════════════════════════════════════════════
// The confirmation has to CARRY COPY: four disclosure blocks in a fixed order, one of which
// (forfeiture) is the *only* protection the product has for 하이 포인트 and unopened drops —
// there is no server gate for them (contract F11), so the sentence IS the gate. `Alert.alert`
// truncates, cannot order its body, and cannot put a control between two paragraphs. A sheet can.
//
// ═══ THE OUTCOMES, ALL OF THEM REAL SCREENS ═══════════════════════════════════════════════
// Under the honesty laws none of these may be a toast, a silent catch, or a happy UI:
//   200 → sign out AFTER the call (the JWT is what authorised it), then dismissTo('/login').
//   409 → a REFUSAL, keyed on a stable server token. Each token gets a Korean line that names the
//         remedy, rendered from `REFUSALS` below.
//   202 `auth_delete_pending` → NOT an error and NOT success. The data is already redacted; the
//         credential outlived it. The user STAYS SIGNED IN (the JWT is needed for the retry) and
//         gets one button that re-invokes the same function — the server short-circuits the SQL
//         half and retries only the auth delete. There is no un-tombstone path, so no "undo".
//   401 → the session expired before the call. Its own state, keyed on the STATUS, not on a
//         message string. (The party gate arrives as HTTP 401 and is keyed on the status alone
//         because that arm is mid-move from 409 to 401 server-side; either shape must land here
//         rather than in the raw-token arm, where a user with a merely-expired session would be
//         shown a symbol instead of a sentence.)
//   400 `confirm_required` is NOT in this list on purpose — it can only mean this app failed to
//   send `{ confirm: 'DELETE' }`, which `deleteMyAccount()` asserts. It is a bug, not a state.
//
// ⚠ NO GRACE PERIOD (contract 🔵 decision). Nothing in this copy may imply a delay or a
// recoverable window — deletion is immediate and the copy is stronger for being unqualified.
import { router } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Linking, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../auth-context';
import { haptic } from '../lib/haptics';
import { DeleteAccountError, deleteMyAccount, fetchLedger } from '../lib/api';
import { session } from '../store';
import { paper } from '../theme';
import { PaperBtn } from './paper-btn';

const SUPPORT_MAIL = 'mailto:seankookim@uchicago.edu?subject=도그스하이 계정 삭제 문의';

interface Refusal {
  /** State-then-remedy, blaming nobody. Four of these are the contract's own words (§C.2 3) and
   *  are reproduced verbatim — do not paraphrase them. */
  body: string;
  /** Present ONLY where this app has somewhere real to land. A remedy the reader cannot perform,
   *  or one whose destination needs an id we do not hold, gets no button rather than a button
   *  that goes nowhere. `href` may be a thunk when the destination depends on the current role. */
  action?: { label: string; href: string | (() => string) };
}

// 🔴 THE SET IS OPEN AND IS RESOLVED AT RUNTIME BY LOOKUP, NOT BY ARITY.
// The server's token list is still moving. So: no union type, no count in a comment, no assertion
// on `Object.keys(...).length`. Adding a token is ONE entry here and nothing else, and a token
// that arrives before its entry does falls into the fallback arm below — which prints the raw
// token and offers 문의하기, never a generic "다시 시도" that would imply a transience nobody
// verified. That fallback is what makes an unfinished set safe to ship against.
const REFUSALS: Record<string, Refusal> = {
  // ── contract-verbatim copy ──
  active_booking: {
    body: '진행 중인 예약이 있어요. 예약을 마치거나 취소한 뒤 다시 시도해주세요.',
    action: { label: '예약 보기', href: '/owner/schedule' },
  },
  // ⚠ 일시정지, NOT 해지 — 0111:192 revoked the client's DELETE on recurring_series and :193
  // granted only `update (paused)`, so pausing is the only remedy that exists (contract F13).
  active_recurring: {
    body: '정기 러닝이 켜져 있어요. 정기 러닝을 일시정지한 뒤 다시 시도해주세요.',
    action: { label: '예약에서 정기 러닝 일시정지', href: '/owner/schedule' },
  },
  // You are holding someone else's dog right now.
  club_custody: {
    body: '지금 맡고 있는 강아지가 있어요. 인계를 마친 뒤 다시 시도해주세요.',
    action: { label: '클럽 보기', href: '/community' },
  },
  club_assignment: {
    body: '확정된 클럽 러닝 배정이 있어요. 배정을 철회한 뒤 다시 시도해주세요.',
    action: { label: '클럽 보기', href: '/community' },
  },
  // ── same shape, written here ──
  // 🔴 The mirror of club_custody: YOUR dog is out with a runner, and the return confirm is
  // TWO-SIDED — the owner's own half may be the outstanding one, so the copy names the screen
  // instead of commanding the runner.
  // ⚠ NO ACTION BUTTON, and this is deliberate rather than unfinished: the 409 body carries no
  // session id, so the client cannot deep-link to the right session and cannot know whether the
  // owner's half is the one still open. The control lives at
  // `app/club/session/[sid].tsx:344` (`confirmReturn(sdId, 'owner')`, rendered :827-843 as
  // 「인계받았어요 — 반환 확인 →」) — NOT on /owner/schedule, which touches no `session_dogs`
  // row. Naming the screen without linking is the honest maximum until the token carries an id.
  club_custody_owner: {
    body: '지금 러너가 우리 아이와 함께 있어요. 반환 확인이 끝나면 탈퇴할 수 있어요 — 클럽 세션 화면에서 내 확인이 남아 있는지 볼 수 있어요.',
  },
  active_run: {
    body: '지금 진행 중인 러닝이 있어요. 러닝이 끝난 뒤 다시 시도해주세요.',
    action: { label: '러닝 화면 보기', href: () => (session.role === 'runner' ? '/runner/run' : '/owner/live') },
  },
  unsettled_run: {
    body: '정산이 끝나지 않은 러닝이 있어요. 정산이 끝난 뒤 다시 시도해주세요.',
  },
  unsettled_payment: {
    body: '처리 중인 결제가 있어요. 결제가 완료되거나 취소된 뒤 다시 시도해주세요.',
    action: { label: '결제 관리', href: '/payments' },
  },
  unpaid_payout: {
    body: '아직 지급되지 않은 정산금이 있어요. 정산금이 입금된 뒤 다시 시도해주세요.',
    action: { label: '정산 내역 보기', href: '/runner/earnings' },
  },
  // km_lots.won_paid is 「고객이 이 로트에 실제로 낸 ₩」 (0075:113) — real money, so the gate
  // stays and the remedy has to name the cash-out route as well as spending it down.
  km_balance: {
    body: '남은 유상 거리가 있어요. 남은 거리를 모두 사용하거나 문의로 환불받은 뒤 다시 시도해주세요.',
    action: { label: '문의하기', href: SUPPORT_MAIL },
  },
  open_incident: {
    body: '해결되지 않은 사고 접수가 있어요. 사고가 해결된 뒤 다시 시도해주세요.',
  },
  club_host_duty: {
    body: '아직 끝나지 않은 클럽 러닝의 호스트예요. 호스트를 넘기거나 세션이 끝난 뒤 다시 시도해주세요.',
    action: { label: '클럽 보기', href: '/community' },
  },
};

// 꾹 눌러 확인 — held, not typed. A typed word is a locale trap on a Korean keyboard (the user
// must switch IME to type an English "DELETE", or we ask them to copy a Korean word they cannot
// see while the keyboard covers the disclosure). A hold needs no keyboard, cannot be autofilled,
// and is impossible to trigger by a stray tap. 1.5s is long enough to be deliberate.
const HOLD_MS = 1500;

function HoldToConfirm({ armed, onArm, disabled }: {
  armed: boolean; onArm: () => void; disabled: boolean;
}) {
  // `useState(() => new Animated.Value(0))` rather than the usual `useRef(...).current`: the value
  // is READ during render (`progress.interpolate(...)` builds the style), and react-hooks/refs
  // correctly refuses a ref read there. Lazy useState gives the same single instance per mount
  // without lying about when it is touched.
  const progress = useState(() => new Animated.Value(0))[0];

  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [trackW, setTrackW] = useState(0);

  const clear = useCallback(() => {
    if (timer.current) { clearTimeout(timer.current); timer.current = null; }
  }, []);
  useEffect(() => clear, [clear]);

  const start = () => {
    if (armed || disabled) return;
    Animated.timing(progress, { toValue: 1, duration: HOLD_MS, useNativeDriver: true }).start();
    timer.current = setTimeout(() => { timer.current = null; haptic('success'); onArm(); }, HOLD_MS);
  };
  const cancel = () => {
    if (armed) return;
    clear();
    progress.stopAnimation(() => {
      Animated.timing(progress, { toValue: 0, duration: 140, useNativeDriver: true }).start();
    });
  };

  return (
    <Pressable
      onPressIn={start}
      onPressOut={cancel}
      disabled={armed || disabled}
      // VoiceOver cannot express a press-and-hold, so the accessibility action arms it directly —
      // the gesture is the deliberateness device, not the only way in.
      accessibilityRole="button"
      accessibilityLabel={armed ? '삭제 확인됨' : '꾹 눌러 삭제 확인'}
      accessibilityHint={armed ? undefined : '1.5초간 길게 누르면 아래 삭제 버튼이 열려요'}
      accessibilityState={{ disabled, checked: armed }}
      onAccessibilityTap={armed || disabled ? undefined : () => { haptic('success'); onArm(); }}
      style={s.holdWrap}
    >
      <Text style={[s.holdLabel, armed && { color: paper.critical }]}>
        {armed ? '확인됨 — 아래에서 삭제할 수 있어요' : '꾹 눌러 확인 (1.5초)'}
      </Text>
      <View style={s.track} onLayout={(e) => setTrackW(e.nativeEvent.layout.width)}>
        {/* ⚠ Gated on a measured width. The fill is an absolutely-positioned full-width bar slid
            out of the track by -trackW; before onLayout that offset is 0, which would flash a
            FULL bar for one frame — an empty progress meter reading as complete. */}
        {trackW > 0 && (
          <Animated.View
            style={[
              s.fill,
              armed
                ? { transform: [{ translateX: 0 }] }
                // translateX (not width) so the fill runs on the native driver — a JS-driven
                // width animation stutters behind the very press it is reporting.
                : { transform: [{ translateX: progress.interpolate({ inputRange: [0, 1], outputRange: [-trackW, 0] }) }] },
            ]}
          />
        )}
      </View>
    </Pressable>
  );
}

type Phase =
  | { k: 'confirm' }
  | { k: 'refused'; token: string }
  | { k: 'pending' }
  | { k: 'expired' }
  | { k: 'unknown'; token: string };

/** ⚠ MOUNTED ONLY WHILE OPEN (`{deleteOpen && <DeleteAccountSheet/>}` in settings.tsx).
 *  That is the reset mechanism: a refusal from the last attempt must not greet the next open and
 *  an armed hold must not survive a dismiss, and unmounting says so structurally instead of via
 *  an effect that re-runs setState on every `visible` flip. */
export function DeleteAccountSheet({ onClose }: { onClose: () => void }) {
  const { signOut } = useAuth();
  const [phase, setPhase] = useState<Phase>({ k: 'confirm' });
  const [armed, setArmed] = useState(false);
  const [busy, setBusy] = useState(false);
  // The busy REF is what makes a double-invoke impossible. `busy` state alone cannot: two taps in
  // the same frame both read the pre-render value and both fire. Opacity is not a guard either.
  // O-7 KEEP disclosure — a retention statement, so its failure mode matters more than its cost.
  // ⚠ `bank_kept` arrives in the deletion RESULT, and on success we sign out immediately: there is no
  // post-call screen it could be rendered on. So the sheet asks the only question answerable BEFORE
  // the call — does this account have ledger rows? — because rows are what make the payout
  // destination worth keeping (O-7: kept intact, not blanked, while `ledger_items` exist).
  //
  // Two corrections from the 2026-08-20 device pass, both mine:
  //  ① EXISTENCE, not a positive sum. The server keeps the row when rows exist; a ledger netting
  //     exactly ₩0 would have been kept server-side and gone unmentioned here.
  //  ② A silent catch is not acceptable on this line. One transient failure in three renders a
  //     sheet with the disclosure missing, and the user cannot tell. So: one retry, and an explicit
  //     `unknown` that still says the true thing conditionally rather than saying nothing.
  //     For a legally relevant KEEP statement the asymmetry favours disclosure.
  // We never assert a bank account is on file: no client reader for `bank_accounts` exists and
  // registration ships with open banking (earnings.tsx:116).
  const [ledger, setLedger] = useState<'unknown' | 'none' | 'some'>('unknown');
  useEffect(() => {
    let alive = true;
    const read = (attempt: number): void => {
      fetchLedger()
        .then((rows) => { if (alive) setLedger(rows.length > 0 ? 'some' : 'none'); })
        .catch(() => {
          if (!alive) return;
          if (attempt === 0) setTimeout(() => { if (alive) read(1); }, 1200);
          // else: stay 'unknown' — the conditional sentence below is true either way
        });
    };
    read(0);
    return () => { alive = false; };
  }, []);

  const busyRef = useRef(false);
  // The success path unmounts this component (onClose) and then keeps awaiting signOut, so the
  // `finally` below would setState on a dead component. Guarded rather than ignored.
  const aliveRef = useRef(true);
  useEffect(() => () => { aliveRef.current = false; }, []);

  const close = useCallback(() => { if (!busyRef.current) onClose(); }, [onClose]);

  const go = useCallback((href: string | (() => string)) => {
    const to = typeof href === 'function' ? href() : href;
    close();
    if (to.startsWith('mailto:')) Linking.openURL(to);
    else router.push(to);
  }, [close]);

  const invoke = useCallback(async () => {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    try {
      // Success. `already === true` means this pass was the retry after a 202 and only the
      // credential was removed; either way the account is gone and the exit is identical, so we
      // do not branch on it — a second success screen would be copy nobody reads on the way out.
      await deleteMyAccount();
      haptic('success');
      onClose();
      // ⚠ AFTER, never before: the JWT is what authorised the call. Mirrors the 로그아웃 handler.
      await signOut();
      router.dismissTo('/login');
      return;
    } catch (e) {
      haptic('error');
      const status = e instanceof DeleteAccountError ? e.status : null;
      const token = e instanceof Error ? e.message : String(e);
      // 401 is the party gate (`not_authenticated`); every state token is a 409. Measured against
      // delete-account **v1 ACTIVE**, deployed from the tree carrying the 401 fix — the earlier
      // string match was scaffolding for the window before that deploy and is deleted, not disabled.
      if (status === 401) {
        setPhase({ k: 'expired' });
      } else if (token === 'auth_delete_pending') {
        setPhase({ k: 'pending' });
      } else if (Object.prototype.hasOwnProperty.call(REFUSALS, token)) {
        setPhase({ k: 'refused', token });
      } else {
        setPhase({ k: 'unknown', token });
      }
    } finally {
      busyRef.current = false;
      if (aliveRef.current) setBusy(false);
    }
  }, [onClose, signOut]);

  const relogin = useCallback(async () => {
    onClose();
    await signOut();
    router.dismissTo('/login');
  }, [onClose, signOut]);

  const refusal = phase.k === 'refused' ? REFUSALS[phase.token] : undefined;

  return (
    <Modal visible transparent animationType="slide" onRequestClose={close}>
      <Pressable style={s.backdrop} onPress={close} accessibilityLabel="닫기" />
      <View style={s.sheet}>
        <View style={s.handle} />
        <ScrollView showsVerticalScrollIndicator={false} style={{ maxHeight: 520 }}>
          {phase.k === 'confirm' && (
            <>
              <Text style={s.title}>계정 삭제</Text>

              {/* (a) irreversible, and you cannot sign back in */}
              <Text style={s.lead}>
                되돌릴 수 없어요. 삭제하면 이 계정으로 다시 로그인할 수 없어요.
              </Text>

              {/* (b) what is deleted */}
              <Text style={s.h}>지워지는 것</Text>
              <Text style={s.p}>프로필, 강아지 사진, 주소, 결제수단, 알림, 피드 글</Text>

              {/* (c) what is forfeited — ⚠ MUST sit ABOVE the confirmation control. There is no
                  server gate for 하이 포인트 or unopened drops (contract F11), so this sentence
                  is the entire protection. Moving it below the control removes the protection. */}
              <View style={s.forfeit}>
                <Text style={s.forfeitText}>하이 포인트와 미개봉 드롭은 소멸해요.</Text>
              </View>

              {/* (d) what is kept, and why */}
              <Text style={s.h}>남는 것</Text>
              <Text style={s.p}>
                예약·결제·정산 기록은 전자상거래법에 따라 보관돼요. 이름은 &apos;탈퇴한 사용자&apos;로
                바뀌고 연락처·사진은 지워져요.
              </Text>
              <Text style={[s.p, { marginTop: 6 }]}>
                채팅과 후기는 상대방의 기록이라 그대로 남아요.
              </Text>
              {/* O-7 (Sean): the payout destination is kept INTACT while the runner has earnings —
                  a redacted account number is a row nobody can pay into. A KEEP fact, so it lives
                  here with 남는 것 and never with 소멸. Rendered only when the server says so. */}
              {ledger !== 'none' && (
                <Text style={[s.p, { marginTop: 6 }]}>
                  {ledger === 'some'
                    ? '아직 정산되지 않은 금액이 있어요 — 지급에 필요한 정산 정보는 남겨둬요.'
                    : '정산 기록이 있다면 지급에 필요한 정산 정보는 남겨둬요.'}
                </Text>
              )}

              {/* (e) confirmation control, then the destructive button */}
              <HoldToConfirm armed={armed} onArm={() => setArmed(true)} disabled={busy} />
              <PaperBtn
                label="계정 삭제"
                busyLabel="삭제 중..."
                busy={busy}
                disabled={!armed}
                variant="destructive"
                onPress={invoke}
                style={{ marginTop: 10 }}
              />
              {!armed && !busy && (
                <Text style={s.hint}>위 막대를 꾹 눌러야 삭제 버튼이 열려요.</Text>
              )}
              <PaperBtn label="취소" variant="quiet" onPress={close} disabled={busy} style={{ marginTop: 8 }} />
            </>
          )}

          {phase.k === 'refused' && refusal && (
            <>
              <Text style={s.title}>아직 삭제할 수 없어요</Text>
              <View style={s.refuse}>
                <Text style={s.refuseText}>{refusal.body}</Text>
              </View>
              {refusal.action && (
                <PaperBtn
                  label={refusal.action.label}
                  variant="secondary"
                  onPress={() => go(refusal.action!.href)}
                  style={{ marginTop: 16 }}
                />
              )}
              <PaperBtn label="닫기" variant="quiet" onPress={close} style={{ marginTop: refusal.action ? 8 : 16 }} />
            </>
          )}

          {phase.k === 'pending' && (
            <>
              <Text style={s.title}>탈퇴 처리 중</Text>
              {/* NOT 실패 (the data IS redacted) and NOT success (the credential lives). The user
                  stays signed in because the retry needs their JWT. No undo is offered because
                  there is no un-tombstone path — offering one would be a lie. */}
              <Text style={s.lead}>탈퇴 처리 중 — 잠시 후 다시 시도해주세요.</Text>
              <Text style={s.p}>
                회원 정보는 이미 삭제됐어요. 로그인 정보만 남아 있어서, 아래 버튼으로 마무리하면 돼요.
              </Text>
              <PaperBtn
                label="다시 시도"
                busyLabel="처리 중..."
                busy={busy}
                variant="destructive"
                onPress={invoke}
                style={{ marginTop: 16 }}
              />
              <PaperBtn label="닫기" variant="quiet" onPress={close} disabled={busy} style={{ marginTop: 8 }} />
            </>
          )}

          {phase.k === 'expired' && (
            <>
              <Text style={s.title}>로그인이 만료됐어요</Text>
              <Text style={s.lead}>다시 로그인한 뒤 시도해주세요. 계정은 아직 그대로예요.</Text>
              <PaperBtn label="다시 로그인" variant="primary" onPress={relogin} style={{ marginTop: 16 }} />
            </>
          )}

          {/* Fallback arm — a token with no entry yet, or a shape nobody predicted. It prints
              itself so support can act on it in one message. No "다시 시도": nothing verified
              that this is transient, and a button saying so would be a claim we cannot make. */}
          {(phase.k === 'unknown' || (phase.k === 'refused' && !refusal)) && (
            <>
              <Text style={s.title}>계정을 삭제하지 못했어요</Text>
              <Text style={s.lead}>알 수 없는 응답을 받았어요. 아래 코드와 함께 문의해주세요.</Text>
              <View style={s.tokenBox}>
                <Text style={s.tokenText} selectable>{phase.token}</Text>
              </View>
              <PaperBtn
                label="문의하기"
                variant="secondary"
                onPress={() => go(SUPPORT_MAIL)}
                style={{ marginTop: 16 }}
              />
              <PaperBtn label="닫기" variant="quiet" onPress={close} style={{ marginTop: 8 }} />
            </>
          )}
        </ScrollView>
      </View>
    </Modal>
  );
}

const s = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: paper.canvas, paddingHorizontal: 16, paddingTop: 8, paddingBottom: 36 },
  handle: { alignSelf: 'center', width: 40, height: 4, borderRadius: 2, backgroundColor: '#E0E0E0', marginBottom: 12 },
  title: { fontSize: 23, fontWeight: '900', color: paper.ink, marginBottom: 8 },
  lead: { fontSize: 16, fontWeight: '700', color: paper.text, lineHeight: 23 },
  h: { fontSize: 14, fontWeight: '900', color: paper.dim, marginTop: 16, marginBottom: 4 },
  p: { fontSize: 14.5, color: paper.text, lineHeight: 21 },
  // (c) — the forfeiture disclosure. Given a plate of its own because it is doing a gate's job.
  forfeit: { marginTop: 16, backgroundColor: paper.criticalWash, paddingHorizontal: 12, paddingVertical: 11 },
  forfeitText: { fontSize: 15, fontWeight: '800', color: paper.critical, lineHeight: 22 },
  refuse: { marginTop: 4, backgroundColor: paper.criticalWash, paddingHorizontal: 12, paddingVertical: 12 },
  refuseText: { fontSize: 15.5, fontWeight: '700', color: paper.critical, lineHeight: 23 },
  holdWrap: { marginTop: 20, paddingVertical: 12, paddingHorizontal: 12, borderWidth: 1, borderColor: paper.line, backgroundColor: paper.wash },
  holdLabel: { fontSize: 15, fontWeight: '800', color: paper.actionInk, textAlign: 'center' },
  track: { marginTop: 10, height: 6, backgroundColor: '#EFE3DF', overflow: 'hidden' },
  fill: { position: 'absolute', left: 0, top: 0, bottom: 0, right: 0, backgroundColor: paper.critical },
  hint: { fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 8, lineHeight: 20 },
  tokenBox: { marginTop: 12, backgroundColor: paper.criticalWash, paddingHorizontal: 12, paddingVertical: 10 },
  tokenText: { fontSize: 14.5, fontWeight: '800', color: paper.critical },
});
