import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { fetchAvailableRunnersFor, fetchGearFor, fetchRunnerProfile, GEAR_META, GearItem, LiveRunner, requestRunner } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { draft } from '../../src/store';
import { lilac } from '../../src/theme';

// 러너 선택 — "비교 시트" (2026-08-04 리스타일).
// 위는 한 줄 = 한 명인 출전자 명단(로스터), 아래는 화면을 떠나지 않는 결정 시트 하나.
// 행을 누르면 바이올렛 링이 옮겨붙고 시트 내용만 갈아끼워진다 — 결정 표면은 끝까지 한 개다.
// [은퇴] 스택 덱 캐러셀·스냅 물리·오버레이 이중 렌더·포레스트/볼트 서피스 전면 제거.
// 스크롤은 평범하고 정직한 세로 ScrollView, 시트는 Modal이 아니라 형제 View.

// 코랄 종단 스톱 — 흰 라벨은 여기(≥#C6472C)에서만 (코랄 텍스트 법: 코랄은 면·엣지·도트)
const CORAL_DEEP = '#C6472C';
const HOLO = ['#CFC5F6', '#FFDCD1', '#F3E9C6', '#EAF6C8', '#CDEAF3']; // 홀로 3px 엣지 근사 (시트 상단 트림)
// 로스터 격자 — 레일 헤더와 행이 정확히 같은 트랙을 쓴다
const COL = { rk: 16, av: 40, m: 46, pace: 46, resp: 40, gap: 8 } as const;

// 티어 잉크 — 골드는 마스터에만 (희소 예산)
const tierColor = (tier: string) => (tier === '마스터' ? lilac.gold : tier === '베테랑' ? lilac.accent : lilac.dim);
const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);

// 매칭 목표 페이스 — 예약의 실제 페이스에 묶는다 (구: 420 하드코딩된 가상 목표).
// 라벨("6'10\"")의 첫 숫자 = 분. 미지정·파싱 실패면 420(7'00") 폴백.
const paceSecOf = (label?: string | null) => { const m = /(\d+)/.exec(label ?? ''); return m ? Number(m[1]) * 60 : 420; };

// 실러너 추천 점수 — 응답률·경험·페이스 적합의 가중합.
// 데이터가 쌓이면 매칭 엔진(견종 경험·후기·거리)으로 교체. 병원 레지던트식 하이브리드 매칭의 v1.
interface Match { total: number; reasons: { label: string; pct: number }[] }
// gearVerified: 인증 장비 부스트 — 슬롯당 +1, 최대 +2 (가드레일: 핵심 점수 불변, 장비는 승부축이 아니다)
function matchFor(r: LiveRunner, gearVerified = 0, targetPaceSec = 420): Match {
  const respond = r.respondRate ?? 88;
  const exp = Math.min(97, 62 + r.totalRuns * 5);
  const paceFit = Math.max(58, 100 - Math.round(Math.abs(r.paceSec - targetPaceSec) / 4));
  return {
    total: Math.min(99, Math.round(respond * 0.35 + exp * 0.3 + paceFit * 0.35) + Math.min(2, gearVerified)),
    reasons: [
      { label: '응답 신뢰도', pct: respond },
      { label: '러닝 경험', pct: exp },
      { label: '페이스 적합', pct: paceFit },
    ],
  };
}

// ── 로스터 행 — 한 명 = 한 줄. 탭 = 선택(바이올렛 링), 이동 없음 ──
// Sean 정제 1: 행은 60-64pt로 숨을 쉰다(48 압축 금지). 정제 2: 아바타 40pt · 라운드 11.
function RosterRow({ r, m, rank, selected, isTop, isCurrent, onPress, nf }: {
  r: LiveRunner; m: Match; rank: number; selected: boolean; isTop: boolean;
  isCurrent: boolean; onPress: () => void; nf: any;
}) {
  const weak = m.total < 80;
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      accessibilityLabel={`${r.name} 러너 · ${r.tier} · 적합도 ${m.total}%`}
      style={[s.row, selected && s.rowSel]}
    >
      {/* 순위 → 선택되면 바이올렛 체크로 바뀐다 */}
      <View style={{ width: COL.rk, alignItems: 'center' }}>
        {selected ? (
          <View style={s.rkCheck}><Text style={{ fontSize: 12, fontWeight: '900', color: '#fff', lineHeight: 14 }}>✓</Text></View>
        ) : (
          <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: isTop ? lilac.accent : lilac.dim }, nf]}>
            {rank < 10 ? `0${rank}` : `${rank}`}
          </Text>
        )}
      </View>

      {/* 따뜻한 아바타 — 사진이 없으면 소프트 바이올렛 위 이니셜 */}
      <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={COL.av} />

      <View style={{ flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 6 }}>
        <Text numberOfLines={1} style={{ fontSize: 15, fontWeight: '800', color: lilac.head, letterSpacing: -0.2 }}>{r.name}</Text>
        <Text numberOfLines={1} style={{ flexShrink: 1, fontSize: 14, fontWeight: '700', color: tierColor(r.tier) }}>{r.tier}</Text>
        {/* 러너 변경 모드에서 '지금 지명된 러너'를 표시 — 누구를 바꾸는 중인지 모르면 선택이 도박이 된다 */}
        {isCurrent && (
          <View style={s.curTag}><Text style={{ fontSize: 14, fontWeight: '700', color: lilac.accent }}>현재 지명</Text></View>
        )}
      </View>

      {/* 매치 — 표의 셀이 아니라 따뜻한 숫자 하나 */}
      <Text style={[{ width: COL.m, textAlign: 'right', fontSize: 18.5, fontWeight: '700', color: selected ? lilac.accent : weak ? lilac.dim : lilac.head }, nf]}>
        {m.total}<Text style={{ fontSize: 12 }}>%</Text>
      </Text>
      <Text style={[{ width: COL.pace, textAlign: 'right', fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.text }, nf]}>{r.paceLabel}</Text>
      {r.respondRate != null ? (
        <Text style={[{ width: COL.resp, textAlign: 'right', fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.text }, nf]}>{r.respondRate}%</Text>
      ) : (
        <Text style={{ width: COL.resp, textAlign: 'right', fontSize: 14, fontWeight: '600', color: lilac.dim }}>신규</Text>
      )}
    </Pressable>
  );
}

// ── 시트 매치 축 바 — 80 미만은 앰버(약점 축 신호) ──
function Bar({ label, pct, nf }: { label: string; pct: number; nf: any }) {
  const weak = pct < 80;
  const w = Math.max(0, Math.min(100, pct));
  return (
    <Row style={{ gap: 10 }}>
      {/* [FLOOR14] 76 → 84: 최장 라벨 '응답 신뢰도'(한글 5 + 공백)가 14pt 에서 ≈74px — 76은 여유 2px 뿐이라 랩됐다 */}
      <Text style={{ width: 84, fontSize: 14, color: lilac.text }}>{label}</Text>
      <View style={s.track}>
        <View style={{ height: '100%', borderRadius: 5, backgroundColor: weak ? lilac.amber : lilac.accent, width: `${w}%` }} />
      </View>
      <Text style={[{ width: 34, textAlign: 'right', fontSize: 14, lineHeight: 18, fontWeight: '700', color: weak ? lilac.amber : lilac.head }, nf]}>{pct}</Text>
    </Row>
  );
}

export default function Matching() {
  const df = useDisplayFont(); // Black Han Sans — 화면에서 딱 한 번(시트의 러너 이름)
  const nf = useNumFont();     // Oswald — 매치·페이스·응답률 등 모든 숫자
  // 목업 러너 참조 은퇴 — 이 화면은 실러너 전용 (2026-07-23)
  const live = !!draft.bookingId;
  // 러너 변경 모드 — 일정 화면의 '러너 변경'이 이 예약 id를 들고 넘어온다.
  // 새 예약을 만들지 않는다: 같은 예약에 request_runner를 다시 쏘면 서버가 지명을 갈아끼운다.
  // [리뷰 F4] 현재 지명자는 호출부(일정 탭)가 이미 들고 있다 — 라운드트립·직접 supabase 임포트 대신 파라미터로
  // pace: 이 예약의 목표 페이스 라벨 (선택 — 없으면 draft.pace, 그것도 없으면 420 폴백)
  const { mode, current, pace } = useLocalSearchParams<{ mode?: string; current?: string; pace?: string }>();
  const rebook = mode === 'rebook';
  const currentRunnerId = (typeof current === 'string' && current.length > 0) ? current : null;
  // 리북은 이 예약의 페이스를 파라미터로 받는다 (draft는 지난 플로우 잔여물일 수 있다)
  const paceParam = (typeof pace === 'string' && pace.length > 0) ? pace : null;
  const targetPaceLabel = rebook ? paceParam : (draft.pace ?? null);
  const targetPaceSec = paceSecOf(targetPaceLabel);
  const [liveRunners, setLiveRunners] = useState<LiveRunner[]>([]);
  const [nominating, setNominating] = useState<string | null>(null);
  // 러너별 장비 로드아웃 (0019) — 배치 조회, 실패해도 카드는 뜬다
  const [gearMap, setGearMap] = useState<Record<string, GearItem[]>>({});
  // 선택된 러너 — null이면 AI 1순위로 폴백한다 (시트는 절대 비지 않는다)
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    const ids = liveRunners.map((r) => r.profileId);
    if (ids.length === 0) return;
    fetchGearFor(ids).then(setGearMap).catch((e) => console.warn('[matching] gear:', e?.message ?? e));
  }, [liveRunners]);

  // 0054: 이 예약 시간에 실제로 갈 수 있는 러너만 (수락 게이트의 표시측 거울 RPC).
  // 바쁜 러너를 보여주고 지명하게 한 뒤 수락 409로 튕기던 흐름의 뿌리를 표시에서 끊는다.
  // 로딩·오류를 상태로 분리 — 실패나 로딩 중을 '가용 러너 없음'으로 위장하지 않는다 (정직 원칙)
  const [rosterLoading, setRosterLoading] = useState(!!draft.bookingId); // 첫 페인트에 '없어요' 오표시 방지
  const [rosterError, setRosterError] = useState<string | null>(null);
  const loadRoster = () => {
    if (!live || !draft.bookingId) return;
    setRosterLoading(true);
    setRosterError(null); // 재시도 중엔 '찾는 중'이 보여야 한다 — 오류 박스가 낡은 채 남지 않게
    fetchAvailableRunnersFor(draft.bookingId)
      .then((rs) => { setLiveRunners(rs); setRosterError(null); })
      .catch((e) => {
        console.warn('[matching] runners:', e?.message ?? e);
        setRosterError(e?.message ?? '러너 목록을 불러오지 못했어요');
      })
      .finally(() => setRosterLoading(false));
  };
  useEffect(loadRoster, [live]);

  // 현재 지명된 러너 — 이 화면이 이미 가진 데이터엔 없어서 예약 1행만 얇게 조회한다.
  // (보호자는 예약 당사자라 RLS 통과. 실패해도 목록은 그대로 뜨고 태그만 안 붙는다)
  // 선호 러너가 오프라인이라 목록에 없어도 반드시 보이게 주입 (지명은 오프라인이어도 가능)
  // 러너 변경 모드에선 '현재 지명된 러너'가 같은 이유로 빠질 수 있다 — 목록은 online=true·10명 컷.
  // 지금 누구인지 안 보이면 '변경'이 아니라 그냥 재선택이 된다. 같은 주입 경로를 재사용.
  useEffect(() => {
    // [리뷰 F3] 리북 모드는 신선한 선택 컨텍스트 — 묵은 preferredRunnerId로 폴스루하면 엉뚱한 러너가 주입된다
    const pref = rebook ? currentRunnerId : draft.preferredRunnerId;
    if (!live || !pref || liveRunners.some((r) => r.profileId === pref)) return;
    fetchRunnerProfile(pref)
      .then((p) => {
        setLiveRunners((cur) => (cur.some((r) => r.profileId === pref) ? cur : [{
          profileId: p.profileId, name: p.name, district: p.district, tier: p.tier,
          totalRuns: p.totalRuns, paceLabel: p.paceLabel, paceSec: p.paceSec, // 실측 원값 — 420 박제는 matchFor 점수를 지어냈다
          respondRate: p.respondRate, avatarUrl: p.avatarUrl, bio: p.bio,
        }, ...cur]));
      })
      .catch((e) => console.warn('[matching] pref inject:', e?.message ?? e));
  }, [live, liveRunners, rebook, currentRunnerId]);

  // 프로필→슬롯→결제로 온 경우: 이미 러너를 골랐으므로 지명을 자동 전송 (CTA 약속 이행)
  // 단, 러너 변경 모드에선 자동 전송 금지 — 남아 있던 preferredRunnerId가
  // '다른 러너를 고르러 온' 보호자 대신 멋대로 지명을 보내버린다.
  const autoRef = useRef(false);
  useEffect(() => {
    const pref = draft.preferredRunnerId;
    if (!live || rebook || !pref || !draft.bookingId || autoRef.current) return;
    autoRef.current = true;
    requestRunner(draft.bookingId, pref)
      .then(() => {
        const name = draft.preferredRunnerName ?? '선택한';
        draft.preferredRunnerId = null;
        draft.preferredRunnerName = null;
        Alert.alert('지명 요청 전송', `${name} 러너에게 우선 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
        router.replace('/owner/schedule');
      })
      .catch((e) => {
        autoRef.current = false; // 실패 → 수동 지명 리스트로 폴백
        console.warn('[matching] auto-nominate:', e?.message ?? e);
        // 침묵 금지 — '이 러너와 예약하기' 약속이 왜 안 지켜졌는지 말한다 (서버 409는 이제 행동 가능한 문장)
        Alert.alert('지명하지 못했어요', e?.message ?? '아래 목록에서 다른 러너를 골라주세요');
      });
  }, [live, rebook]);

  // 점수순 정렬 — 1위가 AI 추천 1순위(=시트 기본 선택), 나머지는 같은 격자의 로스터 행.
  // 프로필에서 '이 러너와 예약하기'로 왔으면 그 러너가 최상단.
  const scored = useMemo(() => {
    const arr = liveRunners
      .map((r) => ({ r, m: matchFor(r, (gearMap[r.profileId] ?? []).filter((g) => g.verified).length, targetPaceSec) }))
      .sort((a, b) => b.m.total - a.m.total);
    if (!rebook && draft.preferredRunnerId) { // [리뷰 F3] 리북에선 지난 플로우의 픽이 1순위를 훔치지 못하게
      const i = arr.findIndex((x) => x.r.profileId === draft.preferredRunnerId);
      if (i > 0) arr.unshift(arr.splice(i, 1)[0]);
    }
    return arr;
  }, [liveRunners, gearMap, targetPaceSec]);
  const top = scored[0];
  const topIsPreferred = !rebook && !!top && top.r.profileId === draft.preferredRunnerId;
  // 시트는 절대 비지 않는다 — 선택이 없거나 사라졌으면 AI 1순위로 폴백
  const sel = scored.find((x) => x.r.profileId === selectedId) ?? top;
  // 러너 변경 모드의 기준점 — 현재 지명 러너 (목록에 있으면 델타 계산 가능)
  const curEntry = currentRunnerId ? scored.find((x) => x.r.profileId === currentRunnerId) : undefined;
  const selIsCurrent = !!sel && !!currentRunnerId && sel.r.profileId === currentRunnerId;
  const lockCta = rebook && selIsCurrent; // 현재 지명자를 다시 지명하는 건 액션이 성립하지 않는다
  const selGear = sel ? (gearMap[sel.r.profileId] ?? []).filter((g) => g.verified) : [];

  const nominate = async (r: LiveRunner) => {
    if (!draft.bookingId) return;
    setNominating(r.profileId);
    try {
      await requestRunner(draft.bookingId, r.profileId);
      draft.preferredRunnerId = null; // 지명 완료 — 선호 러너 상태 소거
      Alert.alert(rebook ? '러너 변경 요청 전송' : '지명 요청 전송', `${r.name} 러너에게 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
      router.replace('/owner/schedule');
    } catch (e) {
      Alert.alert('요청 실패', (e as Error).message);
    } finally {
      setNominating(null);
    }
  };

  const select = (id: string) => {
    if (id === (sel?.r.profileId ?? null)) return;
    setSelectedId(id);
    try { require('expo-haptics').selectionAsync(); } catch {}
  };

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      {/* ── ① 헤더 — 로스터/시트와 분리된 고정 크롬 ── */}
      <View style={s.head}>
        <Row style={{ gap: 9 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: -2 }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 17.5, fontWeight: '900', color: lilac.head, letterSpacing: -0.3 }}>
            {rebook ? '러너 변경' : '러너 선택'}
          </Text>
          {rebook && (
            <View style={s.headTag}><Text style={{ fontSize: 14, fontWeight: '700', color: lilac.accent }}>재요청</Text></View>
          )}
        </Row>
        <Text style={{ fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 9 }}>
          {rebook
            ? '이 예약 그대로 다른 러너에게 다시 요청해요\n새 러너를 지명하면 기존 지명은 자동으로 취소돼요'
            : live ? '러너를 지명하거나, 오픈 매칭으로 기다릴 수 있어요\n보통 몇 분 안에 응답이 와요' : '보호자님과 러너의 선호도를 종합 분석했어요'}
        </Text>
        {/* '지금 누구를 바꾸는 중인지'는 별도 밴드 대신 로스터 행의 [현재 지명] 태그와
            시트의 델타 밴드가 답한다 — 같은 사실을 세 번 말하면 명단 볼 자리가 없다. */}
      </View>

      {/* ── ② 로스터 — 평범하고 정직한 세로 스크롤 (덱·스냅 없음) ── */}
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 10, paddingTop: 6, paddingBottom: 20 }}
        showsVerticalScrollIndicator={false}
      >
        {live && top && (
          <>
            {/* 컬럼 레일 = 범례 + 명단 규모. 행과 같은 트랙을 쓴다 */}
            <Row style={s.rail}>
              <Text style={[s.kick, { flex: 1 }]}>러너 {scored.length}명 · AI 추천 순</Text>
              <Text style={[s.kick, { width: COL.m, textAlign: 'right' }]}>매치</Text>
              <Text style={[s.kick, { width: COL.pace, textAlign: 'right' }]}>페이스</Text>
              <Text style={[s.kick, { width: COL.resp, textAlign: 'right' }]}>응답</Text>
            </Row>

            {scored.map(({ r, m }, i) => (
              <View key={r.profileId}>
                {i > 0 && <View style={s.sep} />}
                <RosterRow
                  r={r} m={m} rank={i + 1} nf={nf}
                  selected={!!sel && sel.r.profileId === r.profileId}
                  isTop={i === 0}
                  isCurrent={r.profileId === currentRunnerId}
                  onPress={() => select(r.profileId)}
                />
              </View>
            ))}

            {/* 이 순서의 근거 — 새 데이터 없이 시트와 같은 세 축으로만 설명 */}
            <View style={s.why}>
              <Row style={{ gap: 8, marginBottom: 9 }}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: lilac.head }}>이 순서는 어떻게 나왔나요</Text>
                <View style={{ flex: 1, height: 1, backgroundColor: lilac.hair }} />
              </Row>
              <View style={{ gap: 7 }}>
                <Row style={{ gap: 8, alignItems: 'flex-start' }}>
                  <View style={s.whyDot} />
                  <Text style={{ flex: 1, fontSize: 14, lineHeight: 18, color: lilac.text }}>
                    <Text style={{ fontWeight: '700', color: lilac.head }}>응답률</Text> — 지명 요청을 받고 실제로 수락한 비율이에요.
                  </Text>
                </Row>
                <Row style={{ gap: 8, alignItems: 'flex-start' }}>
                  <View style={s.whyDot} />
                  <Text style={{ flex: 1, fontSize: 14, lineHeight: 18, color: lilac.text }}>
                    <Text style={{ fontWeight: '700', color: lilac.head }}>경험</Text> — 지금까지 완료한 러닝 횟수를 봐요.
                  </Text>
                </Row>
                <Row style={{ gap: 8, alignItems: 'flex-start' }}>
                  <View style={s.whyDot} />
                  <Text style={{ flex: 1, fontSize: 14, lineHeight: 18, color: lilac.text }}>
                    <Text style={{ fontWeight: '700', color: lilac.head }}>페이스 적합</Text> — 이 예약의 페이스
                    {targetPaceLabel ? <Text style={[{ fontWeight: '700', color: lilac.head }, nf]}>{` ${targetPaceLabel} `}</Text> : ' '}
                    기준으로 러너 페이스가 얼마나 맞는지예요.
                  </Text>
                </Row>
              </View>
              <Text style={{ marginTop: 11, paddingTop: 10, borderTopWidth: 1, borderTopColor: lilac.hair2, fontSize: 14, lineHeight: 18, color: lilac.dim }}>
                세 축을 합쳐 매치 점수가 되고, 그 순서가 AI 추천 1순위예요. 인증 장비는 슬롯당 +1(최대 +2)만 더해요.
              </Text>
            </View>

            <Text style={{ marginTop: 16, textAlign: 'center', fontSize: 14, lineHeight: 18, color: lilac.dim }}>
              지명 없이 두면 오픈 매칭으로 모든 러너에게 보여요
            </Text>
          </>
        )}

        {/* 데모 매칭 섹션 은퇴 (2026-07-23) — 목업 김민준 화면이 결제 실패를 숨기는 함정이었음.
            이 화면은 이제 실예약 전용. */}
        {!live && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14, color: lilac.text, textAlign: 'center', lineHeight: 21 }}>
              진행 중인 예약이 없어요{'\n'}예약 화면에서 결제하면 러너 선택이 열려요
            </Text>
          </View>
        )}

        {live && rosterError && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14, color: lilac.text, textAlign: 'center', lineHeight: 21 }}>
              러너 목록을 불러오지 못했어요{'\n'}{rosterError}
            </Text>
            <Pressable onPress={loadRoster} disabled={rosterLoading} style={{ marginTop: 12, paddingVertical: 12, paddingHorizontal: 26, borderRadius: 10, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, alignSelf: 'center', opacity: rosterLoading ? 0.5 : 1 }}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: lilac.head }}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {live && !rosterError && rosterLoading && liveRunners.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14, color: lilac.text, textAlign: 'center', lineHeight: 21 }}>
              이 시간에 갈 수 있는 러너를 찾는 중…
            </Text>
          </View>
        )}

        {live && !rosterError && !rosterLoading && liveRunners.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14, color: lilac.text, textAlign: 'center', lineHeight: 21 }}>
              이 시간에 갈 수 있는 러너가 지금 없어요{'\n'}오픈 매칭으로 등록돼 있어요 — 일정이 빈 러너가 응답할 수 있어요
            </Text>
          </View>
        )}
      </ScrollView>

      {/* ── ③ 결정 시트 — 화면에 단 하나. Modal이 아니라 형제 View, 절대 비지 않는다 ── */}
      {live && sel && (
        <View style={s.sheet}>
          <View pointerEvents="none" style={s.holo}>
            {HOLO.map((c, i) => <View key={i} style={{ flex: 1, backgroundColor: c }} />)}
          </View>

          <Row style={{ gap: 9, marginBottom: 12 }}>
            <Text style={s.kick}>선택한 러너</Text>
            <View style={{ flex: 1, height: 1, backgroundColor: lilac.hair }} />
            <Pressable
              onPress={() => router.push(`/runner-profile/${sel.r.profileId}`)}
              style={s.profBtn}
              accessibilityRole="button"
              accessibilityLabel={`${sel.r.name} 러너 프로필 보기`}
            >
              <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }}>프로필 ›</Text>
            </Pressable>
          </Row>

          {/* 신원 — 큰 따뜻한 아바타 · Black Han Sans 이름(화면에서 한 번) · 사람 문장 · 매치 숫자 */}
          <Row style={{ gap: 12, alignItems: 'flex-start' }}>
            <Avatar url={sel.r.avatarUrl} char={sel.r.name[0]} bg={lilac.accent} size={52} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <Row style={{ gap: 7 }}>
                <Text numberOfLines={1} style={[{ fontSize: 20, color: lilac.head, letterSpacing: 0.2 }, df]}>{sel.r.name}</Text>
                <Text style={{ fontSize: 14, fontWeight: '700', color: tierColor(sel.r.tier) }}>{sel.r.tier}</Text>
                {top && sel.r.profileId === top.r.profileId && (
                  <View style={s.aiTag}>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.accent }}>
                      {topIsPreferred ? '내가 고른 러너' : 'AI 1순위'}
                    </Text>
                  </View>
                )}
              </Row>
              {/* 사람 문장 — 실필드(동네·누적 러닝)만으로 */}
              <Text style={{ fontSize: 14, lineHeight: 19, color: lilac.text, marginTop: 5 }}>
                {sel.r.totalRuns > 0 ? (
                  <>
                    {sel.r.district || '이 동네'}에서 <Text style={[{ fontSize: 14, fontWeight: '700', color: lilac.head }, nf]}>{sel.r.totalRuns}</Text>번 달렸어요
                  </>
                ) : (
                  `${sel.r.district || '이 동네'}에서 첫 러닝을 기다리고 있어요`
                )}
              </Text>
              {/* 평균 페이스·응답률은 아래 CTA 플레이트가 원값으로 들고 있다 — 시트에서 두 번 말하지 않는다 */}
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={[{ fontSize: 27, fontWeight: '700', color: lilac.head, lineHeight: 29 }, nf]}>
                {sel.m.total}<Text style={{ fontSize: 14, color: lilac.text }}>%</Text>
              </Text>
              <Text style={[s.kick, { marginTop: 1 }]}>매치</Text>
            </View>
          </Row>

          {/* 매치 3축 */}
          <View style={{ marginTop: 12, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair2, gap: 7 }}>
            {sel.m.reasons.map((reason) => (
              <Bar key={reason.label} label={reason.label} pct={reason.pct} nf={nf} />
            ))}
          </View>

          {/* 러너 변경 델타 — 현재 지명 러너 대비 (실필드로 계산 가능한 축만) */}
          {rebook && curEntry && (
            <View style={s.delta}>
              {selIsCurrent ? (
                <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.text }}>지금 이 예약에 지명돼 있는 러너예요.</Text>
              ) : (() => {
                const dm = sel.m.total - curEntry.m.total;
                const dr = (sel.r.respondRate == null || curEntry.r.respondRate == null) ? null : sel.r.respondRate - curEntry.r.respondRate;
                return (
                  <Row style={{ gap: 9, flexWrap: 'wrap' }}>
                    <Text style={{ fontSize: 14, color: lilac.text }}>
                      현재 <Text style={{ fontWeight: '700', color: lilac.head }}>{curEntry.r.name}</Text> 대비
                    </Text>
                    <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: dm >= 0 ? lilac.accent : lilac.amber }, nf]}>매치 {signed(dm)}</Text>
                    {dr == null
                      ? <Text style={{ fontSize: 14, color: lilac.dim }}>응답률 비교 불가 · 신규</Text>
                      : <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: dr >= 0 ? lilac.accent : lilac.amber }, nf]}>응답 {signed(dr)}</Text>}
                  </Row>
                );
              })()}
            </View>
          )}

          {/* 인증 장비 칩 (0019) — 사진으로 인증된 슬롯만. 없으면 그리지 않는다 */}
          {/* [정직 배치 2.5 · 감사 #35] 바디캠 칩은 '보유'까지만 참이다 — 영상 전달 경로가 아직 없다.
              바디캠이 없는 러너에게까지 부정문을 들이밀지 않도록 게이트 (없는 기능을 먼저 광고 금지) */}
          {selGear.length > 0 && (
            <>
              <Text style={{ fontSize: 14, lineHeight: 18, color: lilac.dim, marginTop: 11 }}>
                {selGear.some((g) => g.kind === 'bodycam')
                  ? '러너가 보유한 장비예요 — 영상 제공은 아직 지원하지 않아요'
                  : '러너가 보유한 장비예요'}
              </Text>
              <Row style={{ gap: 7, marginTop: 7, flexWrap: 'wrap' }}>
                {selGear.map((g) => (
                  <View key={g.id} style={s.gearChip}>
                    <Text style={{ fontSize: 14, fontWeight: '600', color: lilac.text }}>
                      {GEAR_META[g.kind].name} <Text style={{ color: lilac.accent, fontWeight: '700' }}>✓</Text>
                    </Text>
                  </View>
                ))}
              </Row>
            </>
          )}

          {/* 유일한 큰 버튼 — 시트 안에 산다 */}
          {lockCta ? (
            <View style={[s.cta, s.ctaLock]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: lilac.head }}>이미 지명된 러너예요</Text>
              <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 3 }}>다른 러너를 선택하면 재요청할 수 있어요</Text>
            </View>
          ) : (
            <Pressable
              onPress={() => nominate(sel.r)}
              disabled={nominating !== null} /* 전송 중 잠금 = 이중 지명 방지 (디렉터 판정: 안전 우선) */
              accessibilityRole="button"
              accessibilityLabel={`${sel.r.name} 러너 지명 요청`}
              style={[s.cta, { backgroundColor: CORAL_DEEP }, nominating !== null && { opacity: 0.55 }]}
            >
              <Row style={{ gap: 10 }}>
                <Text style={{ fontSize: 17.5, fontWeight: '800', color: '#fff', letterSpacing: -0.2 }}>
                  {nominating === sel.r.profileId ? '전송 중...' : '지명 요청'}
                </Text>
                <View style={{ flex: 1 }} />
                {/* 플레이트 = 원값 두 개(점수 아님) — 매치는 바로 위 큰 숫자가 이미 말한다 */}
                <View style={s.ctaPlate}>
                  <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '600', color: '#fff' }, nf]}>{sel.r.paceLabel}</Text>
                  <View style={{ width: 1, height: 11, backgroundColor: 'rgba(255,255,255,0.42)' }} />
                  <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '600', color: '#fff' }, nf]}>
                    {sel.r.respondRate != null ? `응답 ${sel.r.respondRate}%` : '신규'}
                  </Text>
                </View>
                <Text style={{ fontSize: 18, fontWeight: '800', color: '#fff' }}>›</Text>
              </Row>
            </Pressable>
          )}
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  // ── 헤더 크롬 ──
  head: {
    paddingTop: 58, paddingHorizontal: 14, paddingBottom: 12,
    backgroundColor: lilac.card, borderBottomWidth: 1, borderBottomColor: lilac.hair, zIndex: 10,
  },
  backBtn: {
    width: 34, height: 34, borderRadius: 10, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  headTag: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset,
    borderRadius: 7, paddingVertical: 3, paddingHorizontal: 8,
  },
  // ── 로스터 ──
  kick: { fontSize: 12, fontWeight: '600', letterSpacing: 1.4, color: lilac.dim },
  rail: { gap: COL.gap, paddingHorizontal: 9.5, paddingTop: 4, paddingBottom: 7 },
  // Sean 정제 1: 60-64pt 행 — 압축 금지. 정제 2: 라운드 11, 넉넉한 좌우 여백
  row: {
    flexDirection: 'row', alignItems: 'center', gap: COL.gap, minHeight: 62,
    paddingVertical: 11, paddingHorizontal: 8, borderRadius: 11,
    borderWidth: 1.5, borderColor: 'transparent',
  },
  rowSel: {
    backgroundColor: lilac.card, borderColor: lilac.accent,
    shadowColor: lilac.accent, shadowOpacity: 0.18, shadowRadius: 12,
    shadowOffset: { width: 0, height: 5 }, elevation: 4,
  },
  sep: { height: 1, backgroundColor: lilac.hair2, marginHorizontal: 10 },
  rkCheck: { width: 17, height: 17, borderRadius: 6, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  curTag: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.card,
    borderRadius: 6, paddingVertical: 2, paddingHorizontal: 6,
  },
  // ── 순서 근거 카드 ──
  why: {
    marginTop: 16, backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2,
    borderRadius: 12, padding: 14,
    shadowColor: '#1C1837', shadowOpacity: 0.06, shadowRadius: 12, shadowOffset: { width: 0, height: 5 }, elevation: 2,
  },
  whyDot: { width: 5, height: 5, borderRadius: 2.5, backgroundColor: lilac.accent, marginTop: 7 },
  emptyBox: {
    marginTop: 16, backgroundColor: lilac.card, borderRadius: 12, padding: 18,
    alignItems: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  // ── 결정 시트 ── (Sean 정제 1: 패딩 ≥18)
  sheet: {
    backgroundColor: lilac.card, borderTopWidth: 1, borderTopColor: lilac.hair,
    paddingTop: 18, paddingHorizontal: 18, paddingBottom: 22,
    shadowColor: '#1C1837', shadowOpacity: 0.16, shadowRadius: 20, shadowOffset: { width: 0, height: -8 }, elevation: 24,
  },
  holo: { position: 'absolute', top: 0, left: 0, right: 0, height: 3, flexDirection: 'row', zIndex: 2 },
  profBtn: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.card,
    borderRadius: 8, paddingVertical: 6, paddingHorizontal: 10,
  },
  aiTag: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset,
    borderRadius: 6, paddingVertical: 2, paddingHorizontal: 7,
  },
  track: {
    flex: 1, height: 9, borderRadius: 5, backgroundColor: lilac.inset,
    borderWidth: 1, borderColor: lilac.hair, overflow: 'hidden',
  },
  delta: {
    marginTop: 11, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: 9, paddingVertical: 8, paddingHorizontal: 11,
  },
  gearChip: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.card,
    borderRadius: 8, paddingVertical: 5, paddingHorizontal: 9,
  },
  // 코랄 종단 스톱(#C6472C) 위 흰 라벨 — 이 화면에서 흰 글씨가 코랄에 올라가는 유일한 자리
  cta: { marginTop: 14, borderRadius: 12, paddingVertical: 15, paddingHorizontal: 15 },
  ctaLock: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, alignItems: 'flex-start' },
  ctaPlate: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: 'rgba(28,24,55,0.55)', borderRadius: 7, paddingVertical: 5, paddingHorizontal: 9,
  },
});
