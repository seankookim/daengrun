import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { ClubCta, ClubMast, ClubTag, DawnCanvas, Flap, LilacCard, LoadGate } from '../../../src/components/club-ui';
import {
  fetchIncidentDetail, incidentEvidenceAdd, incidentResolve, incidentSettle, incidentSettleQuote,
  IncidentDetail, SettleOutcome, SettleQuote,
} from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { goBackOrHome } from '../../../src/lib/nav';
import { lilac, lilacRadius, paper } from '../../../src/theme';

// 케이스 상세 — 정본: master-lab '케이스 #24' (코랄 좌괘 + OUTSIDE 플랩이 무게를 진다, 어둠 없이)
// 열람은 서버 초크포인트(club_incident_detail — 케이스 당사자만). 타임라인 = 증거 seq.
// 커스터디 이벤트 병합(인계→러닝→이양 행)은 후속 — sdId 매핑이 보드에 없다.

const L = lilac;

const KIND_LABEL: Record<string, string> = {
  text: '기록', location: '위치 증거', photo: '사진 증거', document: '문서 증거',
};

export default function CaseDetail() {
  const { cid } = useLocalSearchParams<{ cid: string }>();
  const [inc, setInc] = useState<IncidentDetail | null>(null);
  const [denied, setDenied] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  // [0072] 정산 시트 — 금액은 서버 견적만 그린다. 클라가 숫자를 만들면 그건 이미 거짓말이다.
  const [quotes, setQuotes] = useState<Record<SettleOutcome, SettleQuote> | null>(null);
  const [quoteErr, setQuoteErr] = useState(false);
  const [settleFor, setSettleFor] = useState<string | null>(null);

  const load = useCallback(() => {
    if (!cid) return;
    fetchIncidentDetail(cid).then((d) => { setInc(d); setDenied(false); setLoadErr(false); })
      .catch((e) => {
        // [감사 P2] not_case_party 외 오류가 영구 '불러오는 중'으로 굳던 것 — SOS 직후 진입 화면이다
        if ((e as Error).message.includes('not_case_party')) setDenied(true);
        else setLoadErr(true);
      });
  }, [cid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  // 정산 대상 = 이 케이스의 booking 주체 (서버가 준 것만 — 클라가 부킹을 추측하지 않는다)
  const settleBooking = inc?.subjects.find((x) => x.type === 'booking')?.id ?? null;

  const openSettle = (bid: string) => {
    setSettleFor(bid); setQuotes(null); setQuoteErr(false);
    Promise.all([
      incidentSettleQuote(bid, 'refund_full'),
      incidentSettleQuote(bid, 'settle_measured'),
      incidentSettleQuote(bid, 'pay_full'),
    ])
      .then(([a, b2, c]) => setQuotes({ refund_full: a, settle_measured: b2, pay_full: c }))
      // 견적을 못 받으면 금액 없이 버튼만 그리지 않는다 — 근거 없는 결정은 이 화면의 반대말이다
      .catch(() => setQuoteErr(true));
  };
  const doSettle = (outcome: SettleOutcome) => {
    if (!settleFor || !cid || busy) return;
    const q = quotes?.[outcome];
    if (!q) return;
    Alert.alert('정산 확정',
      // [0121 §H] this alert is the SETTLING side's (authority) — both numbers are theirs; the
      // '—' arms fire only if a projection ever mis-answers, and then honesty beats a fake 0.
      `보호자 환불 ${q.refund == null ? '—' : q.refund.toLocaleString() + '원'} · 러너 정산 ${q.runnerNet == null ? '—' : q.runnerNet.toLocaleString() + '원'}(수수료 차감 후).\n한 번만 결정할 수 있고, 케이스에 근거가 남아요.`,
      [
        { text: '아직', style: 'cancel' },
        {
          text: '확정', style: 'destructive',
          onPress: () => {
            setBusy(true);
            incidentSettle(cid, settleFor, outcome, note.trim() || null)
              .then(() => { haptic('success'); setSettleFor(null); setNote(''); load(); })
              .catch((e) => {
                const m = (e as Error).message;
                Alert.alert('정산 실패',
                  m.includes('already_settled') ? '이미 정산된 예약이에요'
                  : m.includes('not_case_owner') ? '케이스 오너나 호스트만 정산할 수 있어요'
                  : m.includes('not_in_review') ? '이 예약은 정산 대상 상태가 아니에요'
                  : m.includes('case_closed') ? '이미 해소된 케이스예요' : m);
              })
              .finally(() => setBusy(false));
          },
        },
      ]);
  };

  // [2026-08-11] this screen's error/denied/retry trio was promoted to the shared
  // LoadGate (club-ui.tsx) — it now consumes its own pattern.
  if (denied) {
    return <LoadGate mode="denied" deniedLabel="케이스 당사자만 볼 수 있어요" onBack={goBackOrHome} />;
  }
  if (!inc) {
    return (
      <LoadGate
        mode={loadErr ? 'error' : 'loading'}
        errorLabel="케이스를 불러오지 못했어요"
        onRetry={() => { setLoadErr(false); load(); }}
        onBack={goBackOrHome}
      />
    );
  }

  const open = inc.state !== 'resolved';
  const iOwn = inc.myId != null && (inc.myId === inc.caseOwner);
  const sev = inc.severity.toUpperCase();

  const addNote = () => {
    const t = note.trim();
    if (!t || busy) return;
    setBusy(true);
    incidentEvidenceAdd(inc.id, 'text', { note: t })
      .then(() => { setNote(''); haptic('light'); load(); })
      .catch((e) => Alert.alert('기록 실패', (e as Error).message))
      .finally(() => setBusy(false));
  };
  const doResolve = () => {
    Alert.alert('케이스 해소', '해소하면 이 케이스가 걸었던 정산 보류가 풀려요.\n같은 아이의 다른 오픈 케이스가 있으면 보류는 유지돼요.', [
      { text: '아직', style: 'cancel' },
      {
        text: '해소', onPress: () => incidentResolve(inc.id).then(() => { haptic('success'); load(); })
          .catch((e) => Alert.alert('해소 실패', (e as Error).message.includes('not_case_owner') ? '케이스 오너나 호스트만 해소할 수 있어요' : (e as Error).message)),
      },
    ]);
  };

  return (
    <DawnCanvas>
      <ScrollView
        contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        keyboardShouldPersistTaps="handled"
      >
        <ClubMast title={`케이스 ${sev}`} sub={open ? '진행 중' : '해소됨'} onBack={goBackOrHome} />

        <LilacCard crit={open} hero={!open}>
          <Row style={{ gap: 8, alignItems: 'center' }}>
            <ClubTag label={sev} tone={sev === 'S1' ? 'coral' : sev === 'S2' ? 'amber' : 'dim'} />
            <ClubTag label={open ? '진행 중' : '해소'} tone={open ? 'amber' : 'volt'} />
          </Row>
          <Text style={{ fontSize: 14.5, fontWeight: '800', color: open ? L.tang : L.head, marginTop: 9 }}>{inc.summary}</Text>
          <Text style={{ fontSize: 14, color: L.text, marginTop: 7 }}>
            개설 {inc.openedByName} · 케이스 오너 <Text style={{ fontWeight: '800', color: L.head }}>{inc.caseOwnerName ?? '미지정'}</Text>
          </Text>
          {!open && <View style={{ marginTop: 8, alignSelf: 'flex-start' }}><Flap word="RESOLVED" /></View>}
        </LilacCard>

        {/* ---------- 타임라인 (증거 seq — 서버 순서만 신뢰) ---------- */}
        <View style={s.sechead}><Text style={s.secheadTitle}>기록</Text></View>
        <View style={s.tl}>
          {inc.evidence.length === 0 && <Text style={{ fontSize: 14, color: L.dim, paddingVertical: 6 }}>아직 기록이 없어요</Text>}
          {inc.evidence.map((e, i) => (
            <View key={i} style={s.ev}>
              <View style={[s.evDot, e.kind === 'location' && { backgroundColor: L.tang }]} />
              <Text style={{ fontSize: 14, color: L.text, flex: 1, lineHeight: 18 }}>
                <Text style={{ fontSize: 14, color: L.dim }}>{e.when} </Text>
                <Text style={{ fontWeight: '800', color: L.head }}>{KIND_LABEL[e.kind] ?? e.kind}</Text>
                {e.kind === 'text' && e.payload?.note ? ` — ${e.payload.note}` : ''}
                {e.kind === 'location' ? ' — 좌표 기록됨' : ''}
                <Text style={{ color: L.dim }}> · {e.byName}</Text>
              </Text>
            </View>
          ))}
        </View>

        {/* ---------- 기록 추가 (케이스 당사자) ---------- */}
        {open && (
          <Row style={s.inputbar}>
            <TextInput value={note} onChangeText={setNote} placeholder="상황 기록 추가..." placeholderTextColor={L.dim}
              style={s.inputField} multiline />
            <Pressable onPress={addNote} style={s.sendBtn}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>{busy ? '...' : '기록'}</Text>
            </Pressable>
          </Row>
        )}

        {/* ---------- [0072] 정산 — 돈이 멈춰 있는 케이스의 유일한 출구 ---------- */}
        {open && (iOwn || inc.isHost === true) && settleBooking && (
          settleFor !== settleBooking ? (
            <ClubCta label="예약 정산 결정하기" tone="secondary"
              onPress={() => openSettle(settleBooking)} style={{ marginTop: 14 }} />
          ) : (
            <LilacCard style={{ marginTop: 14 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: L.head }}>예약 정산</Text>
              <Text style={{ fontSize: 14, lineHeight: 19, color: L.text, marginTop: 5 }}>
                이 예약은 사건으로 멈춰 있어요. 셋 중 하나를 고르면 환불과 러너 정산이 실제로 움직이고,
                근거가 이 케이스에 남아요. 한 번만 결정할 수 있어요.
              </Text>
              {/* 로딩 ≠ 실패 ≠ 값 — 견적을 못 받으면 버튼을 그리지 않는다 (금액 없는 결정 금지) */}
              {quoteErr ? (
                <>
                  <Text style={{ fontSize: 14, lineHeight: 19, color: L.tang, marginTop: 10 }}>
                    견적을 불러오지 못했어요 — 금액 없이 결정할 수는 없어요.
                  </Text>
                  <ClubCta label="다시 시도" tone="secondary" onPress={() => openSettle(settleBooking)} />
                </>
              ) : !quotes ? (
                <Text style={{ fontSize: 14, color: L.dim, marginTop: 10 }}>견적을 계산하는 중...</Text>
              ) : (
                <>
                  {([
                    ['settle_measured', '실측대로 정산', '달린 만큼 러너에게, 나머지는 환불'],
                    ['refund_full', '전액 환불', '제공된 게 없어요 — 러너 정산 없음'],
                    ['pay_full', '전액 지급', '서비스는 이행됐어요 — 환불 없음'],
                  ] as [SettleOutcome, string, string][]).map(([k, label, why]) => (
                    <View key={k} style={s.settleRow}>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={{ fontSize: 14, fontWeight: '800', color: L.head }}>{label}</Text>
                        <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 1 }}>{why}</Text>
                        <Text style={{ fontSize: 14, lineHeight: 18, color: L.text, marginTop: 3 }}>
                          환불 {quotes[k].refund == null ? '—' : `${quotes[k].refund!.toLocaleString()}원`} · 러너 {quotes[k].runnerNet == null ? '—' : `${quotes[k].runnerNet!.toLocaleString()}원`}
                        </Text>
                      </View>
                      <Pressable onPress={() => doSettle(k)} disabled={busy} style={s.settleBtn}>
                        <Text style={{ fontSize: 14, fontWeight: '800', color: '#fff' }}>{busy ? '...' : '선택'}</Text>
                      </Pressable>
                    </View>
                  ))}
                  <Text style={{ fontSize: 14, lineHeight: 18, color: L.dim, marginTop: 8 }}>
                    실측 {quotes.settle_measured.measuredKm}km
                    {quotes.settle_measured.tookCustody ? ' · 인계 완료' : ' · 인계 전'}
                  </Text>
                </>
              )}
              <ClubCta label="닫기" tone="quiet" onPress={() => setSettleFor(null)} />
            </LilacCard>
          )
        )}

        {/* [0052 §7] 해소는 케이스 오너 또는 호스트/백업 호스트 — isHost는 서버 판정이라 클라가 추측하지 않는다.
            (db push 전 원격에선 undefined → 예전대로 케이스 오너에게만 보인다) */}
        {open && (iOwn || inc.isHost === true) && <ClubCta label="케이스 해소" onPress={doResolve} busy={busy} style={{ marginTop: 14 }} />}
        <Text style={{ fontSize: 14, color: L.dim, marginTop: 12, textAlign: 'center' }}>
          케이스는 세션이 끝나도 계속돼요 — 해소되면 알려드려요
        </Text>
      </ScrollView>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  // [0072] 정산 선택 행 — 금액이 라벨과 같은 행에 산다 (§3b: 상태는 자기 데이텀 옆에)
  settleRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 10,
    borderTopWidth: 1, borderTopColor: L.hair, paddingTop: 10,
  },
  settleBtn: {
    backgroundColor: paper.action, borderRadius: 0, paddingVertical: 11, paddingHorizontal: 14,
    minHeight: 44, alignItems: 'center', justifyContent: 'center', flexShrink: 0,
  },
  sechead: { marginTop: 14, paddingBottom: 6, borderBottomWidth: 1, borderBottomColor: L.hair2 },
  secheadTitle: { fontSize: 14, fontWeight: '800', color: L.head },
  tl: { borderLeftWidth: 2, borderLeftColor: L.hair, paddingLeft: 12, marginTop: 10, marginLeft: 3 },
  ev: { flexDirection: 'row', gap: 0, paddingVertical: 5 },
  evDot: { position: 'absolute', left: -16.5, top: 10, width: 7, height: 7, borderRadius: 4, backgroundColor: '#CFC8EC' },
  inputbar: {
    gap: 8, marginTop: 12, alignItems: 'flex-end',
    backgroundColor: L.glass, borderWidth: 1, borderColor: L.glassEdge, borderRadius: 10, padding: 7,
  },
  inputField: {
    flex: 1, backgroundColor: '#fff', borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    paddingVertical: 8, paddingHorizontal: 12, fontSize: 14, color: L.head, maxHeight: 90,
  },
  sendBtn: { backgroundColor: L.accent, borderRadius: lilacRadius.btn, paddingVertical: 10, paddingHorizontal: 13 },
});
