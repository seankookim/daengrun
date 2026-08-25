// ═══════════ 지각 체크인 — 답을 받는 표면 ═══════════
// 정본: docs/plans/2026-08-21-late-booking-protocol.md §8-bis (③ + ③-A, ③-C 사유 하나) ·
// docs/labs/stop-reason-lab.html · 콘솔 룰링 #18 (Sean 2026-08-25, "approve on everything").
// 서버 계약: supabase/migrations/0117 §6 answer_checkin · §7 fetch_checkin (2026-08-25 배포).
//
// ⚠ 이건 late-notice.tsx 의 수정본이 **아니다**. 그 파일 9번째 줄이 자기 계약을 적어뒀다:
// 「이 컴포넌트는 답을 받지 않는다」. 답을 받는 것은 이 컴포넌트이고, 둘은 나란히 산다 —
// 위에서 사실을 말하고(LateNotice), 여기서 답을 받는다.
//
// ⚠ 이 표면이 지키는 네 가지, 전부 이 파일 바깥에서 배운 것:
//  1. **로딩은 0이 아니다.** 못 불러온 상태에서는 아무것도 그리지 않는다. 이 블록은 「지금 답해야
//     한다」는 **긍정 주장**이라 모르는 채로 띄울 수 없고, 블록의 부재는 아무것도 주장하지 않는다
//     (runner/run.tsx:970 의 bookingWatch 배너가 같은 이유로 같은 선택을 한다).
//     실패해도 마찬가지다 — 위의 LateNotice 는 그대로 서 있고, 새로 생기는 것이 없을 뿐이다.
//  2. **시계는 서버 것이다.** 카운트다운의 원점은 server_now 이고 Date.now() 는 '그 읽기 이후
//     얼마나 지났나'를 재는 스톱워치로만 쓴다 (checkin.ts remainMs 의 주석).
//  3. **천장을 넘기면 진행 문이 사라진다** — 서버가 거부하기 **전에**. 그래도 경합으로 거부가
//     오면 그 거부는 정직하게 그려진다 (checkin-copy 의 일곱 상태).
//  4. **긴급은 게이트 뒤에 있지 않다.** ③ 의 뼈대: 사용자와 도움 사이에 아무것도 두지 않는다.
//     119 는 tel: 링크이고 SOS 는 상대방 알림 하나다 — 그 이상을 말하면 그게 거짓말이다.
import { useCallback, useEffect, useState } from 'react';
import { KeyboardAvoidingView, Linking, Platform, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import {
  answerCheckin, fetchCheckin, sendSOS,
  type CheckinAnswerValue, type CheckinSide, type CheckinState,
} from '../lib/api';
import { checkinPossible, remainMs } from '../lib/checkin';
import {
  checkinCopy, checkinRefusalFrom, noteStepFor, recordedCopy, REASON_STEP,
  stopReasonsFor, reasonTextFor, TRIAGE,
  type CheckinRefusal, type StopReasonKey,
} from '../lib/checkin-copy';
import { paper } from '../theme';

type Step = 'ask' | 'triage' | 'reason' | 'note';
type SosState = 'idle' | 'sending' | 'sent' | 'failed';

export function CheckinAnswer({ bookingId, side, rawStatus, onAnswered }: {
  bookingId: string;
  side: CheckinSide;
  /** bookings.status 원문. 표시 어휘를 넘기면 게이트가 조용히 틀린다 (CLAUDE.md 법 3). */
  rawStatus: string | null | undefined;
  /** 답이 예약 상태를 바꿨을 수 있으니 호출부가 자기 목록을 다시 읽는다. 없으면 아무 일도 없다. */
  onAnswered?: () => void;
}) {
  const [state, setState] = useState<CheckinState | null>(null);
  /** 서버 읽기 시점의 **로컬** 시각. 경과 측정용 기준점일 뿐, 달력이 아니다.
   *  ref 가 아니라 state 인 이유: 렌더 중에 읽는 값이고, 렌더 중 ref 접근은 react-hooks/refs 가
   *  잡는다 — 그리고 그 규칙이 맞다. 이 값이 바뀌면 카운트다운이 다시 그려져야 한다. */
  const [fetchedAt, setFetchedAt] = useState<number | null>(null);
  const [step, setStep] = useState<Step>('ask');
  const [picked, setPicked] = useState<StopReasonKey | null>(null);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [refusal, setRefusal] = useState<CheckinRefusal | null>(null);
  const [failed, setFailed] = useState(false);
  const [sos, setSos] = useState<SosState>('idle');
  const [justAnswered, setJustAnswered] = useState(false);
  /** 카운트다운 리렌더 틱. 폴링이 아니다 — 네트워크를 건드리지 않는다. */
  const [, setTick] = useState(0);

  const possible = checkinPossible(rawStatus);

  useEffect(() => {
    // `!possible` 에서 state 를 비우지 않는 이유: 아래 렌더 가드가 이미 `!possible` 이면 null 을
    // 돌려준다. effect 안의 동기 setState 는 캐스케이드 렌더를 만들고, 여기서는 그걸 살 이유가 없다.
    // ⚠ **예약이 바뀌는 경우는 이 effect 가 아니라 마운트 지점의 `key` 가 처리한다** —
    // key={bookingId} 로 컴포넌트가 통째로 다시 마운트되므로, 이전 예약의 체크인이 새 예약의
    // 자리에 잠깐이라도 그려지는 일이 없다. state 초기화를 effect 로 흉내 내면 그 한 프레임이 남는다.
    if (!possible) return;
    let alive = true;
    fetchCheckin(bookingId)
      .then((s) => { if (alive) { setFetchedAt(Date.now()); setState(s); } })
      // 실패는 **아무것도 그리지 않는다** (위 법 1). 조용한 catch 가 아니라, 이 표면이 할 수 있는
      // 유일하게 정직한 일이다: 열린 확인이 있다고 주장할 근거가 없다.
      .catch(() => { if (alive) setState(null); });
    return () => { alive = false; };
  }, [bookingId, possible]);

  // 30초 틱 — 열려 있고 아직 답하지 않았을 때만. 마감이 분 단위라 초 단위 시계는 필요 없다.
  const ticking = state?.row != null && state.open && !justAnswered;
  useEffect(() => {
    if (!ticking) return;
    const id = setInterval(() => setTick((n) => n + 1), 30_000);
    return () => clearInterval(id);
  }, [ticking]);

  const send = useCallback(async (answer: CheckinAnswerValue, reason?: string | null) => {
    if (busy) return;
    setBusy(true); setRefusal(null); setFailed(false);
    try {
      const next = await answerCheckin(bookingId, side, answer, reason);
      setFetchedAt(Date.now());
      setState(next);
      setJustAnswered(true);
      setStep('ask');
      onAnswered?.();
    } catch (e) {
      // 일곱 토큰은 전부 문장이 있다. 없는 실패는 **실패로** 그린다 — 조용히 삼키고 성공한 척하지 않는다.
      const r = checkinRefusalFrom(e);
      if (r) setRefusal(r); else setFailed(true);
      // 거부는 대개 '내가 아는 상태가 낡았다'는 뜻이다. 새로 읽어 화면을 진실에 맞춘다.
      fetchCheckin(bookingId)
        .then((s) => { setFetchedAt(Date.now()); setState(s); })
        .catch(() => { /* 새로고침 실패는 거부 문장을 지우지 않는다 — 그건 방금 일어난 사실이다 */ });
    } finally {
      setBusy(false);
    }
  }, [bookingId, busy, onAnswered, side]);

  const fireSos = useCallback(async () => {
    if (sos === 'sending') return;
    setSos('sending');
    try {
      // ⚠ 이 예약을 명시적으로 넘긴다. 인자가 없으면 sendSOS 는 '지금의 예약'을 스스로 고르는데,
      // 이 표면은 **탭해서 연 특정 예약** 안에 산다 (owner/schedule 시트).
      const bid = await sendSOS(side, bookingId);
      setSos(bid ? 'sent' : 'failed');   // null = 보낼 상대가 없었다. 그것도 '못 보냄'이다.
    } catch {
      setSos('failed');
    }
  }, [bookingId, side, sos]);

  if (!possible || state == null) return null;   // 로딩·실패·해당 없음 — 새로 그리는 것 없음

  // ── 방금 답했다: 확인 블록. (`cannot_proceed` 는 같은 트랜잭션에서 체크인을 닫으므로 아래
  //    checkinCopy 는 null 이 된다 — 여기서 잡지 않으면 성공이 '표면이 사라짐'으로 보인다.)
  if (justAnswered) {
    const rec = recordedCopy(state, side);
    if (rec == null) return null;
    return (
      <View style={s.wrap}>
        <Text style={s.recHead}>{rec.head}</Text>
        <Text style={s.recLine}>{rec.line}</Text>
        {rec.reason ? <Text style={s.recReason}>{rec.reason}</Text> : null}
        {rec.note ? <Text style={s.body}>{rec.note}</Text> : null}
      </View>
    );
  }

  // 시계는 remainMs 안에 있다 (checkin.ts 의 주석) — 이 줄은 순수하다.
  const remaining = state.row != null && fetchedAt != null
    ? remainMs(state.row, state.serverNow, fetchedAt)
    : null;
  const copy = checkinCopy(state, side, rawStatus, remaining);
  if (copy == null) {
    // ⚠ 거부 문장은 표면이 접힐 때 같이 사라지면 안 된다. 거부의 흔한 원인이 「내가 아는 상태가
    // 낡았다」이고, 그때 위 재조회가 '이미 해소됨'을 들고 오면 checkinCopy 는 null 이 된다 —
    // 그대로 return 하면 사용자는 **탭했는데 화면이 그냥 비는 것**만 본다. 방금 일어난 일은
    // 방금 일어난 일이므로 남는다.
    if (refusal) return <View style={s.wrap}><RefusalBlock r={refusal} /></View>;
    if (failed) return <View style={s.wrap}><FailBlock /></View>;
    return null;   // 행이 없거나 이미 해소됐다 — 이 표면은 답을 받는 표면이다
  }

  const reasons = stopReasonsFor(side);
  const noteCopy = picked ? noteStepFor(picked) : null;
  const canSubmitNote = note.trim().length > 0;

  // ── 3단계: 노트 (③-A 의 needsNote — 서버가 증거를 요구하는 사유에만 있는 단계) ──────────
  if (step === 'note' && picked && noteCopy) {
    return (
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={s.wrap}>
          <Text style={s.stepHead}>{noteCopy.head}</Text>
          <Text style={s.noteLabel}>{noteCopy.label}</Text>
          <TextInput
            style={s.noteInput}
            value={note}
            onChangeText={setNote}
            multiline
            textAlignVertical="top"
            editable={!busy}
            placeholder={noteCopy.placeholder}
            placeholderTextColor={paper.faint}
            accessibilityLabel={noteCopy.label}
          />
          <Pressable
            style={[s.inkBtn, !canSubmitNote ? { backgroundColor: paper.disabledFill, borderColor: paper.disabledFill } : null]}
            disabled={!canSubmitNote || busy}
            onPress={() => { void send('cannot_proceed', reasonTextFor(side, picked, note)); }}
            accessibilityRole="button"
            accessibilityState={{ disabled: !canSubmitNote || busy }}
          >
            <Text style={[s.inkBtnTxt, !canSubmitNote ? { color: paper.faint } : null]}>
              {busy ? REASON_STEP.submitting : REASON_STEP.submit}
            </Text>
          </Pressable>
          <Pressable style={s.link} disabled={busy} onPress={() => { setStep('reason'); setNote(''); setPicked(null); }}>
            <Text style={s.linkTxt}>{REASON_STEP.back}</Text>
          </Pressable>
          {refusal ? <RefusalBlock r={refusal} /> : null}
          {failed ? <FailBlock /> : null}
        </View>
      </KeyboardAvoidingView>
    );
  }

  // ── 2단계: 사유 행 (③-A — 런엔드가 이미 쓰는 문법 그대로) ────────────────────────────────
  if (step === 'reason') {
    return (
      <View style={s.wrap}>
        <Text style={s.kicker}>{REASON_STEP.kicker}</Text>
        {reasons.map((r) => (
          <Pressable
            key={r.key}
            style={s.reasonRow}
            disabled={busy}
            onPress={() => {
              setPicked(r.key);
              if (r.needsNote) { setNote(''); setStep('note'); }
              else void send('cannot_proceed', reasonTextFor(side, r.key));
            }}
            accessibilityRole="button"
          >
            <Text style={s.reasonTxt}>{r.label}</Text>
            {r.needsNote ? <Text style={s.reasonMark}>{REASON_STEP.noteMark}</Text> : null}
          </Pressable>
        ))}
        {/* 건너뛰기는 숨기지 않는다. 의무는 묻는 것이지 답하게 만드는 게 아니다 (§8-bis 불변식). */}
        <Pressable style={s.link} disabled={busy} onPress={() => { void send('cannot_proceed', null); }}>
          <Text style={s.linkTxt}>{busy ? REASON_STEP.submitting : REASON_STEP.skip}</Text>
        </Pressable>
        {refusal ? <RefusalBlock r={refusal} /> : null}
        {failed ? <FailBlock /> : null}
      </View>
    );
  }

  // ── 1단계: 위급 먼저 (③) ────────────────────────────────────────────────────────────────
  if (step === 'triage') {
    return (
      <View style={s.wrap}>
        <Text style={s.stepHead}>{TRIAGE.head}</Text>
        <Text style={s.body}>{TRIAGE.sub}</Text>
        <View style={s.sosBox}>
          <Pressable
            style={s.sosBtn}
            onPress={() => { Linking.openURL('tel:119').catch(() => { /* 다이얼러가 없으면 열 것이 없다 */ }); }}
            accessibilityRole="button"
          >
            <Text style={s.sosBtnTxt}>{TRIAGE.callLabel}</Text>
          </Pressable>
          <Text style={s.sosSub}>{TRIAGE.callSub}</Text>
          <Pressable
            style={[s.sosBtn, { marginTop: 10 }]}
            disabled={sos === 'sending'}
            onPress={() => { void fireSos(); }}
            accessibilityRole="button"
            accessibilityState={{ disabled: sos === 'sending' }}
          >
            <Text style={s.sosBtnTxt}>{sos === 'sending' ? TRIAGE.sosSending : TRIAGE.sosLabel}</Text>
          </Pressable>
          <Text style={s.sosSub}>
            {sos === 'sent' ? TRIAGE.sosSent : sos === 'failed' ? TRIAGE.sosFailed : TRIAGE.sosSub}
          </Text>
        </View>
        <Pressable style={s.inkBtn} disabled={busy} onPress={() => setStep('reason')} accessibilityRole="button">
          {/* SOS 를 이미 보냈다면 「아니요」는 거짓이 된다 — 라벨이 상태를 따라간다. */}
          <Text style={s.inkBtnTxt}>{sos === 'sent' ? TRIAGE.nextAfterSos : TRIAGE.next}</Text>
        </Pressable>
        <Pressable style={s.link} disabled={busy} onPress={() => { void send('cannot_proceed', null); }}>
          <Text style={s.linkTxt}>{busy ? REASON_STEP.submitting : TRIAGE.skip}</Text>
        </Pressable>
        {refusal ? <RefusalBlock r={refusal} /> : null}
        {failed ? <FailBlock /> : null}
      </View>
    );
  }

  // ── 0단계: 질문과 세 답 ─────────────────────────────────────────────────────────────────
  return (
    <View style={s.wrap} accessibilityRole="summary">
      <Text style={s.kicker}>{copy.kick}</Text>
      <Text style={s.head}>{copy.head}</Text>
      {copy.sub ? <Text style={s.body}>{copy.sub}</Text> : null}

      {/* 내 답이 이미 있으면 버튼이 아니라 기록을 보여준다 — 답은 한 번뿐이다 (per-side immutable). */}
      {copy.mine ? (
        <View style={s.mineBox}>
          <Text style={s.recLine}>{copy.mine.line}</Text>
          {copy.mine.reason ? <Text style={s.recReason}>{copy.mine.reason}</Text> : null}
          <Text style={s.fine}>{copy.mine.immutable}</Text>
        </View>
      ) : null}

      {/* v4 랩 R5a 의 법을 그대로: 세 답은 **동급**이다. 하나에만 색을 주면 답을 유도하게 되고,
          유도된 답은 이 프로토콜이 받으려는 그 진술이 아니다. 코랄은 어느 쪽에도 없다 —
          화면당 코랄 하나는 이 표면을 마운트한 화면이 이미 쓰고 있다. */}
      {copy.options.map((o) => (
        <Pressable
          key={o.key}
          // disabled 는 명시 fill 로 그린다 — 불투명도 트릭 금지 법 (theme.ts §버튼 매트릭스).
          style={[s.optBtn, busy ? { borderColor: paper.disabledFill, backgroundColor: paper.disabledFill } : null]}
          disabled={busy}
          onPress={() => {
            // 「진행할 수 없어요」만 두 단계다 — ③ 의 위급 분기가 그 앞에 선다.
            if (o.key === 'cannot_proceed') { setSos('idle'); setStep('triage'); }
            else void send(o.key, null);
          }}
          accessibilityRole="button"
          accessibilityState={{ disabled: busy }}
        >
          <Text style={[s.optTxt, busy ? { color: paper.faint } : null]}>{o.label}</Text>
        </Pressable>
      ))}

      {copy.cancelNote ? <Text style={s.body}>{copy.cancelNote}</Text> : null}
      <Text style={s.body}>{copy.theirs}</Text>
      {/* ⚠ 4B — 남겼다는 사실만. 내용은 이 화면에 **도착하지도 않는다**. */}
      {copy.theirsReason ? <Text style={s.fine}>{copy.theirsReason}</Text> : null}
      <View style={s.strip}><Text style={s.stripTxt}>{copy.strip}</Text></View>
      {copy.terminalNote ? <Text style={s.fine}>{copy.terminalNote}</Text> : null}
      {refusal ? <RefusalBlock r={refusal} /> : null}
      {failed ? <FailBlock /> : null}
    </View>
  );
}

function RefusalBlock({ r }: { r: CheckinRefusal }) {
  return (
    <View style={s.refusal}>
      <Text style={s.refusalTitle}>{r.title}</Text>
      <Text style={s.refusalBody}>{r.body}</Text>
    </View>
  );
}

/** 아는 토큰이 아닌 실패. 서버 문자열을 인쇄하지 않고, 성공한 척도 하지 않는다. */
function FailBlock() {
  return (
    <View style={s.refusal}>
      <Text style={s.refusalTitle}>답을 보내지 못했어요</Text>
      <Text style={s.refusalBody}>잠시 후 다시 시도해 주세요. 아직 아무것도 기록되지 않았어요.</Text>
    </View>
  );
}

// 디테일 텍스트 바닥선 14pt. 예외는 레터스페이스 키커 하나뿐 (DESIGN.md).
const s = StyleSheet.create({
  wrap: { paddingVertical: 14, gap: 8 },
  kicker: { fontSize: 12, fontWeight: '800', letterSpacing: 0.9, color: paper.dim },
  head: { fontSize: 22, fontWeight: '900', letterSpacing: -0.4, lineHeight: 29, color: paper.ink },
  stepHead: { fontSize: 20, fontWeight: '900', letterSpacing: -0.3, lineHeight: 27, color: paper.ink },
  body: { fontSize: 14, lineHeight: 20, color: paper.text },
  fine: { fontSize: 14, lineHeight: 20, color: paper.dim },
  strip: { borderWidth: 1, borderColor: '#E6E6E6', backgroundColor: '#FAFAFA', padding: 10 },
  stripTxt: { fontSize: 14, lineHeight: 20, color: paper.text, fontWeight: '600' },
  // 답 버튼 — 잉크 아웃라인, 셋 다 같은 무게. 면(fill)은 쓰지 않는다 (코랄 예산은 호스트 화면 것).
  optBtn: { borderWidth: 1.5, borderColor: paper.ink, backgroundColor: paper.canvas, paddingVertical: 13, paddingHorizontal: 14 },
  optTxt: { fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' },
  inkBtn: { borderWidth: 1.5, borderColor: paper.ink, backgroundColor: paper.canvas, paddingVertical: 13, paddingHorizontal: 14, marginTop: 4 },
  inkBtnTxt: { fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' },
  // 사유 행 — ③-A 프레임 그대로: 헤어라인으로만 갈린 행 목록.
  reasonRow: { borderTopWidth: 1, borderTopColor: '#EFEEEA', paddingVertical: 14, flexDirection: 'row', alignItems: 'baseline', gap: 6 },
  reasonTxt: { fontSize: 16, fontWeight: '700', color: paper.ink },
  reasonMark: { fontSize: 14, color: paper.dim },
  link: { paddingVertical: 12, alignItems: 'center' },
  linkTxt: { fontSize: 14, fontWeight: '700', color: paper.dim, textDecorationLine: 'underline' },
  // 긴급 — critical 은 강조 예산 면제 토큰이다 (theme.ts:181). 코랄과 절대 섞지 않는다.
  sosBox: { borderWidth: 2, borderColor: paper.critical, backgroundColor: paper.criticalWash, padding: 12, gap: 4 },
  sosBtn: { borderWidth: 1.5, borderColor: paper.critical, backgroundColor: paper.canvas, paddingVertical: 12 },
  sosBtnTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textAlign: 'center' },
  sosSub: { fontSize: 14, lineHeight: 19, color: '#8C3722' },
  mineBox: { borderWidth: 1, borderColor: '#E6E6E6', padding: 11, gap: 4 },
  recHead: { fontSize: 18, fontWeight: '900', color: paper.ink },
  recLine: { fontSize: 16, fontWeight: '800', color: paper.ink, lineHeight: 22 },
  recReason: { fontSize: 14, lineHeight: 20, color: paper.text },
  noteLabel: { fontSize: 14, fontWeight: '800', color: paper.ink, marginTop: 4 },
  noteInput: {
    borderWidth: 1.5, borderColor: '#C9C7C0', backgroundColor: paper.canvas,
    minHeight: 96, padding: 11, fontSize: 15, lineHeight: 21, color: paper.ink,
  },
  refusal: { borderWidth: 1.5, borderColor: paper.critical, backgroundColor: paper.criticalWash, padding: 11, gap: 3 },
  refusalTitle: { fontSize: 15, fontWeight: '800', color: paper.critical },
  refusalBody: { fontSize: 14, lineHeight: 20, color: '#8C3722' },
});
