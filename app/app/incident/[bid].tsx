import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import {
  fetchIncidentRunContext, fetchOpenIncident, openBookingIncident, verifyBookingIncident,
  IncidentKind, IncidentRunContext, IncidentSeverity, OpenIncident, NOT_FOUND,
} from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { paper } from '../../src/theme';

// 사고 신고 — 마켓플레이스 인시던트의 클라이언트 절반 (서버는 0094 ⑪ + 0114 §3 로 완성돼 있었고
// 화면만 없었다). 계약과 그 계약을 읽은 자리는 api.ts 의 「사고 신고」 블록 헤더에.
//
// 🔴 한 화면이 두 상태를 산다. 서버 모델이 「한 예약에 열린 인시던트는 하나」이므로 (0114 §3 ⑤),
//    이 화면도 예약 id 하나로 열리고 그 예약에 열린 건이 있느냐로 갈린다:
//      · 없다 + 접수 가능  → 접수 폼
//      · 없다 + 접수 불가  → 서버가 쓰는 그 문장 (수락 전이거나 종료된 예약)
//      · 있다             → 사건 상태 + 내 확인 도장
//    해소된 건은 '열린 건' 이 아니다 — 그래서 해소 뒤에는 다시 폼이 된다. 서버가 그렇게 판단한다.
//
// 🔴 두 집합이 다르고, 그 차이가 이 화면의 버튼을 정한다 (0114):
//      접수 가능(§3) = accepted + cancelled_owner + refund_pending
//      알림·채팅(§1) = accepted                                  ← 두 개 좁다
//    그래서 「채팅으로 알리기」 는 `ctx.contactable` 로만 그린다. 두 집합을 하나로 보면
//    cancelled_owner 에서 눌러봐야 42501 을 받는 버튼이 태어난다.
//
// ⚠ 전화번호는 없다. `incident_contact`(0088 §E) 는 name 과 **phone** 을 함께 돌려주는 문이고
//   이 제품은 상대방 연락을 채팅으로만 라우팅한다. 게다가 `profiles.phone` 은 지금 전원 NULL 이다
//   (0133 이 수집 경로를 자문 문안 대기 상태로 두고 서버만 랜딩했다) — 부르면 빈 칸 두 줄이 온다.
//
// ⚠ 폴링은 없다. 상대의 도장은 포커스 복귀와 당겨서 새로고침에서만 갱신된다 — 서버가 밀어주는
//   채널이 이 사건에는 없고, 없는 실시간을 도는 척하는 것보다 당길 수 있는 편이 정직하다.

const KIND_LABEL: Record<string, string> = {
  dog_injury: '강아지가 다쳤어요',
  lost_dog: '강아지를 잃어버렸어요',
  third_party: '다른 사람·개와 사고',
  equipment: '목줄·장비 문제',
  other: '그 밖의 일',
};
// 서버가 받는 다섯 값 그대로 (0094 §9 ④). 순서는 화면 순서일 뿐 서버에 의미가 없다.
const KINDS: IncidentKind[] = ['dog_injury', 'lost_dog', 'third_party', 'equipment', 'other'];

const SEVERITY_LABEL: Record<string, string> = { normal: '보통', urgent: '급해요', sos: '위급' };
const SEVERITIES: IncidentSeverity[] = ['normal', 'urgent', 'sos'];

/** 접수 RPC 의 raise 를 사람 문장으로. ⚠ `booking_not_reportable` 의 문장은 서버가 detail 에
 *  달아둔 것과 **같은 문장**이다 (0114 §3 ⑥) — 두 벌을 쓰면 언젠가 서로 다른 주장을 하게 된다. */
const openFailMessage = (m: string): string =>
  m.includes('booking_not_reportable') ? '수락 전이거나 종료된 예약에는 사고를 접수할 수 없어요'
  : m.includes('not_party') ? '이 러닝의 당사자만 접수할 수 있어요'
  : m.includes('not_found') ? '이 러닝을 찾을 수 없어요'
  : m;

/** 확인 RPC 의 raise. `incident_resolved` 와 `not_party` 는 서로 다른 사실이므로 문장도 다르다
 *  (0094 §10 이 서버 쪽에서 같은 규율을 지킨다). */
const verifyFailMessage = (m: string): string =>
  m.includes('incident_resolved') ? '이미 해소된 사고예요'
  : m.includes('not_party') ? '이 러닝의 당사자만 확인할 수 있어요'
  : m.includes('not_found') ? '사고 기록을 찾을 수 없어요'
  : m;

export default function IncidentScreen() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [ctx, setCtx] = useState<IncidentRunContext | null>(null);
  const [inc, setInc] = useState<OpenIncident | null>(null);
  // 네 가지 사실을 네 가지로 둔다. 'gone' 은 재시도가 의미 없는 사실(없는 예약 · 내 예약이 아님 —
  // RLS 가 둘을 구분하지 않는다), 'error' 는 다시 눌러볼 값이 있는 실패다.
  const [state, setState] = useState<'loading' | 'ready' | 'gone' | 'error'>('loading');
  const [refreshing, setRefreshing] = useState(false);
  const [kind, setKind] = useState<IncidentKind | null>(null);
  const [severity, setSeverity] = useState<IncidentSeverity>('normal'); // 서버 기본값과 같은 값
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    if (!bid) { setState('gone'); return; }
    try {
      const c = await fetchIncidentRunContext(bid);
      const i = await fetchOpenIncident(bid);
      setCtx(c); setInc(i); setState('ready');
    } catch (e) {
      const m = (e as Error).message ?? '';
      console.warn('[incident] load:', m);
      setState(m.includes(NOT_FOUND) ? 'gone' : 'error');
    }
  }, [bid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  const onRefresh = () => {
    setRefreshing(true);
    load().finally(() => setRefreshing(false));
  };

  const submit = async () => {
    if (!ctx || !kind || busy) return;
    setBusy(true);
    try {
      const r = await openBookingIncident(ctx, kind, severity, note.trim() || null);
      haptic('success');
      await load();
      // 접수와 알림은 두 개의 사실이다 — 알림이 실패했거나 애초에 닫혀 있었으면 그렇게 말한다.
      // 접수 자체는 성공했으므로 어느 쪽도 '접수 실패' 가 아니다.
      if (r.notify === 'failed') {
        Alert.alert('접수됐어요', '상대방에게 알림을 보내지 못했어요 — 채팅으로 알려주세요');
      } else if (r.notify === 'unavailable') {
        Alert.alert('접수됐어요', '이 예약은 알림이 닫혀 있어요 — 상대방에게 따로 알려주세요');
      }
    } catch (e) {
      Alert.alert('접수 실패', openFailMessage((e as Error).message ?? ''));
    } finally {
      setBusy(false);
    }
  };

  const verify = async () => {
    if (!ctx || !inc || busy) return;
    setBusy(true);
    try {
      const r = await verifyBookingIncident(inc.id, ctx.mySide);
      haptic(r.verified ? 'success' : 'light'); // 양측 확정은 다른 사건이라 다른 감촉
      await load();
    } catch (e) {
      Alert.alert('확인 실패', verifyFailMessage((e as Error).message ?? ''));
    } finally {
      setBusy(false);
    }
  };

  const body = () => {
    if (state === 'loading') return <Text style={s.plain}>불러오는 중...</Text>;
    if (state === 'gone') return <Text style={s.plain}>이 러닝을 찾을 수 없어요</Text>;
    if (state === 'error') {
      return (
        <View style={s.failStrip}>
          <Text style={s.failTxt}>사고 정보를 불러오지 못했어요</Text>
          <Pressable onPress={() => { setState('loading'); load(); }} style={s.retryBtn} accessibilityRole="button">
            <Text style={s.retryTxt}>다시 시도</Text>
          </Pressable>
        </View>
      );
    }
    if (!ctx) return null;

    const counterLabel = ctx.mySide === 'owner' ? (ctx.counterpartName ?? '러너') : '보호자';

    // ── 이미 열린 사건 ──────────────────────────────────────────────────────────────────
    if (inc) {
      const myStamp = ctx.mySide === 'owner' ? inc.ownerVerifiedAtIso : inc.runnerVerifiedAtIso;
      const theirStamp = ctx.mySide === 'owner' ? inc.runnerVerifiedAtIso : inc.ownerVerifiedAtIso;
      return (
        <>
          <Text style={s.secTitle}>접수 내용</Text>
          <Text style={s.kind}>{KIND_LABEL[inc.kind] ?? inc.kind}</Text>
          <Text style={s.meta}>
            {SEVERITY_LABEL[inc.severity] ?? inc.severity} · {inc.reportedByMe ? '내가 접수' : `${counterLabel}이(가) 접수`}
          </Text>
          {inc.note ? <Text style={s.note}>{inc.note}</Text> : null}

          <Text style={s.secTitle}>확인</Text>
          <StampRow label="내 확인" done={myStamp != null} />
          {/* 러너 미배정 예약에서는 찍을 사람이 없다. '대기 중' 이라고 쓰면 오지 않을 사람을
              기다리게 만든다 — 있는 사실(runner_id 가 없다)을 그대로 말한다. */}
          {ctx.counterpartId
            ? <StampRow label={`${counterLabel} 확인`} done={theirStamp != null} />
            : <Row style={s.stampRow}><Text style={s.stampLabel}>러너 확인</Text><Text style={s.stampWait}>러너 미배정</Text></Row>}

          {/* 0094 §11: ops 확정은 verified_at 만 채우고 양측 도장은 NULL 로 남긴다. 두 사실을 한
              문장으로 접으면 위의 두 줄이 모순처럼 읽힌다 — 그래서 이름이 다르다. */}
          {inc.verifiedAtIso ? (
            <Text style={s.verified}>{inc.forcedBy === 'ops' ? '운영자가 확정했어요' : '양쪽 확인 완료'}</Text>
          ) : null}

          {myStamp == null && (
            <PaperBtn label="사고를 확인했어요" busyLabel="확인 중..." onPress={verify} busy={busy} style={s.cta} />
          )}
          {/* 0114 §1 — accepted 집합에서만 스레드·메시지 INSERT 가 열린다. 닫힌 상태에서는
              문을 그리지 않는다 (채팅 화면의 '수락 전' 문구는 cancelled_owner 에서 거짓이다). */}
          {ctx.contactable && (
            <PaperBtn
              label="채팅으로 알리기" variant="secondary" style={s.cta}
              onPress={() => router.push({ pathname: '/chat', params: { bid: ctx.bookingId } })}
            />
          )}
          {inc.verifiedAtIso ? null : <Text style={s.ctaNote}>양쪽이 확인하면 사고로 확정돼요</Text>}
        </>
      );
    }

    // ── 접수할 수 없는 상태 ────────────────────────────────────────────────────────────
    if (!ctx.reportable) {
      return <Text style={s.plain}>수락 전이거나 종료된 예약에는 사고를 접수할 수 없어요</Text>;
    }

    // ── 접수 폼 ────────────────────────────────────────────────────────────────────────
    return (
      <>
        <Text style={s.secTitle}>무슨 일인가요?</Text>
        <Row style={s.chips}>
          {KINDS.map((k) => (
            <Pressable
              key={k} onPress={() => { setKind(k); haptic('light'); }}
              style={[s.chip, kind === k && s.chipOn]}
              accessibilityRole="radio" accessibilityState={{ selected: kind === k }}
            >
              <Text style={[s.chipTxt, kind === k && s.chipTxtOn]}>{KIND_LABEL[k]}</Text>
            </Pressable>
          ))}
        </Row>

        <Text style={s.secTitle}>얼마나 급한가요?</Text>
        <Row style={s.chips}>
          {SEVERITIES.map((v) => (
            <Pressable
              key={v} onPress={() => { setSeverity(v); haptic('light'); }}
              style={[s.chip, severity === v && s.chipOn]}
              accessibilityRole="radio" accessibilityState={{ selected: severity === v }}
            >
              <Text style={[s.chipTxt, severity === v && s.chipTxtOn]}>{SEVERITY_LABEL[v]}</Text>
            </Pressable>
          ))}
        </Row>

        <TextInput
          value={note} onChangeText={setNote} multiline maxLength={300}
          placeholder="본 것을 적어주세요 (선택)" placeholderTextColor={paper.faint} style={s.input}
        />

        {/* 종류를 고르기 전에는 눌러도 서버가 bad_kind 로 거절할 뿐이다 — 죽은 키는 여행이 없다
            (§3b disabled = 평평한 명시 fill, 알파 트릭 금지). */}
        <PaperBtn
          label="사고 접수하기" busyLabel="접수 중..." onPress={submit}
          disabled={kind == null} busy={busy} style={s.cta}
        />
        {ctx.contactable && <Text style={s.ctaNote}>접수하면 {counterLabel}에게 바로 알려요</Text>}
      </>
    );
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingBottom: 40 }}
        keyboardShouldPersistTaps="handled"
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* §2 종이 크롬 — 헤더는 거터 밖에 서서 코랄 헤어라인이 화면 끝까지 간다 */}
        <Row style={s.topBar}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>사고 신고</Text>
          <View style={{ width: 40 }} />
        </Row>

        <View style={{ paddingHorizontal: 15 }}>
          {/* 어느 러닝인지 — 서버가 준 두 필드뿐이다. 강아지 이름이 없으면 자리도 없다. */}
          {ctx && (
            <Text style={s.run}>{ctx.dogName ? `${ctx.dogName} · ` : ''}{ctx.dateLabel}</Text>
          )}
          {body()}
        </View>
      </ScrollView>
    </View>
  );
}

function StampRow({ label, done }: { label: string; done: boolean }) {
  return (
    <Row style={s.stampRow}>
      <Text style={s.stampLabel}>{label}</Text>
      <Text style={done ? s.stampDone : s.stampWait}>{done ? '확인 완료' : '대기 중'}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  topBar: {
    justifyContent: 'space-between', paddingTop: 56, paddingBottom: 12, paddingHorizontal: 15,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  backBtn: {
    width: 40, height: 40, borderRadius: 0, backgroundColor: paper.canvas,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line,
  },
  run: { fontSize: 15, lineHeight: 19, color: paper.text, marginTop: 16 },
  // §3b 섹션 헤더 — 풀블리드 코랄 1px + 20/800 잉크 (라틴 키커·서브타이틀 없음)
  secTitle: {
    fontSize: 20, fontWeight: '800', color: paper.ink,
    marginTop: 22, paddingTop: 14, borderTopWidth: 1, borderTopColor: paper.line,
    marginHorizontal: -15, paddingHorizontal: 15,
  },
  kind: { fontSize: 17, fontWeight: '800', color: paper.ink, marginTop: 12 },
  meta: { fontSize: 15, lineHeight: 19, color: paper.text, marginTop: 4 },
  note: { fontSize: 15, lineHeight: 20, color: paper.ink, marginTop: 10 },
  plain: { fontSize: 15, lineHeight: 20, color: paper.text, marginTop: 18 },
  stampRow: { justifyContent: 'space-between', alignItems: 'center', paddingVertical: 11, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  stampLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  stampDone: { fontSize: 16, fontWeight: '800', color: paper.readyDeep },
  stampWait: { fontSize: 16, fontWeight: '700', color: paper.text },
  verified: { fontSize: 17, fontWeight: '800', color: paper.readyDeep, marginTop: 14 },
  // §3b 선택칩 — 샤프 코너 · 선택은 코랄 워시 면 + 코랄 보더 + actionInk (review/dog 와 같은 문법)
  chips: { gap: 8, flexWrap: 'wrap', marginTop: 12 },
  chip: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 11, paddingHorizontal: 13, minHeight: 44, justifyContent: 'center',
  },
  chipOn: { backgroundColor: paper.wash, borderColor: paper.line },
  chipTxt: { fontSize: 15, fontWeight: '800', color: paper.text },
  chipTxtOn: { color: paper.actionInk },
  input: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    padding: 13, marginTop: 20, height: 96, textAlignVertical: 'top', fontSize: 16, color: paper.ink,
  },
  // 레이아웃만 — 면·라벨·눌림은 PaperBtn 이 가진다
  cta: { marginTop: 18 },
  ctaNote: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 10, textAlign: 'center' },
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 18 },
  failTxt: { fontSize: 15, fontWeight: '700', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.actionInk },
});
