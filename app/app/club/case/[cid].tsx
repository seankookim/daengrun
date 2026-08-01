import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { ClubCta, ClubMast, ClubTag, DawnCanvas, Flap, LilacCard } from '../../../src/components/club-ui';
import { fetchIncidentDetail, incidentEvidenceAdd, incidentResolve, IncidentDetail } from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { lilac, lilacRadius } from '../../../src/theme';

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
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(() => {
    if (!cid) return;
    fetchIncidentDetail(cid).then((d) => { setInc(d); setDenied(false); })
      .catch((e) => { if ((e as Error).message.includes('not_case_party')) setDenied(true); });
  }, [cid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));
  const onRefresh = () => { setRefreshing(true); Promise.resolve(load()).finally(() => setTimeout(() => setRefreshing(false), 400)); };

  if (denied) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 13, color: L.dim }}>케이스 당사자만 볼 수 있어요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={() => router.back()} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }
  if (!inc) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 13, color: L.dim }}>불러오는 중...</Text>
        </View>
      </DawnCanvas>
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
        <ClubMast title={`케이스 ${sev}`} sub={open ? '진행 중' : '해소됨'} onBack={() => router.back()} />

        <LilacCard crit={open} hero={!open}>
          <Row style={{ gap: 8, alignItems: 'center' }}>
            <ClubTag label={sev} tone={sev === 'S1' ? 'coral' : sev === 'S2' ? 'amber' : 'dim'} />
            <ClubTag label={open ? '진행 중' : '해소'} tone={open ? 'amber' : 'volt'} />
          </Row>
          <Text style={{ fontSize: 14.5, fontWeight: '800', color: open ? L.tang : L.head, marginTop: 9 }}>{inc.summary}</Text>
          <Text style={{ fontSize: 10.5, color: L.text, marginTop: 7 }}>
            개설 {inc.openedByName} · 케이스 오너 <Text style={{ fontWeight: '800', color: L.head }}>{inc.caseOwnerName ?? '미지정'}</Text>
          </Text>
          {!open && <View style={{ marginTop: 8, alignSelf: 'flex-start' }}><Flap word="RESOLVED" /></View>}
        </LilacCard>

        {/* ---------- 타임라인 (증거 seq — 서버 순서만 신뢰) ---------- */}
        <View style={s.sechead}><Text style={s.secheadTitle}>기록</Text></View>
        <View style={s.tl}>
          {inc.evidence.length === 0 && <Text style={{ fontSize: 10.5, color: L.dim, paddingVertical: 6 }}>아직 기록이 없어요</Text>}
          {inc.evidence.map((e, i) => (
            <View key={i} style={s.ev}>
              <View style={[s.evDot, e.kind === 'location' && { backgroundColor: L.tang }]} />
              <Text style={{ fontSize: 10.5, color: L.text, flex: 1, lineHeight: 16 }}>
                <Text style={{ fontSize: 8.5, color: L.dim }}>{e.when} </Text>
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
              <Text style={{ fontSize: 11, fontWeight: '900', color: '#fff' }}>{busy ? '...' : '기록'}</Text>
            </Pressable>
          </Row>
        )}

        {open && iOwn && <ClubCta label="케이스 해소" onPress={doResolve} busy={busy} style={{ marginTop: 14 }} />}
        <Text style={{ fontSize: 10, color: L.dim, marginTop: 12, textAlign: 'center' }}>
          케이스는 세션이 끝나도 계속돼요 — 해소되면 알려드려요
        </Text>
      </ScrollView>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  sechead: { marginTop: 14, paddingBottom: 6, borderBottomWidth: 1, borderBottomColor: L.hair2 },
  secheadTitle: { fontSize: 12.5, fontWeight: '800', color: L.head },
  tl: { borderLeftWidth: 2, borderLeftColor: L.hair, paddingLeft: 12, marginTop: 10, marginLeft: 3 },
  ev: { flexDirection: 'row', gap: 0, paddingVertical: 5 },
  evDot: { position: 'absolute', left: -16.5, top: 10, width: 7, height: 7, borderRadius: 4, backgroundColor: '#CFC8EC' },
  inputbar: {
    gap: 8, marginTop: 12, alignItems: 'flex-end',
    backgroundColor: L.glass, borderWidth: 1, borderColor: L.glassEdge, borderRadius: 10, padding: 7,
  },
  inputField: {
    flex: 1, backgroundColor: '#fff', borderWidth: 1, borderColor: L.hair, borderRadius: lilacRadius.btn,
    paddingVertical: 8, paddingHorizontal: 12, fontSize: 12, color: L.head, maxHeight: 90,
  },
  sendBtn: { backgroundColor: L.accent, borderRadius: lilacRadius.btn, paddingVertical: 10, paddingHorizontal: 13 },
});
