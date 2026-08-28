import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Avatar, Row } from '../../src/components/ui';
import { fetchAvailableRunnersFor, fetchGearFor, fetchRunnerProfile, GEAR_META, GearItem, LiveRunner, requestRunner } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { goBackOrHome } from '../../src/lib/nav';
import { draft } from '../../src/store';
import { paper } from '../../src/theme';

// 러너 선택 — "비교 시트" (2026-08-04 리스타일).
// 위는 한 줄 = 한 명인 출전자 명단(로스터), 아래는 화면을 떠나지 않는 결정 시트 하나.
// 행을 누르면 선택이 옮겨붙고 시트 내용만 갈아끼워진다 — 결정 표면은 끝까지 한 개다.
// [은퇴] 스택 덱 캐러셀·스냅 물리·오버레이 이중 렌더·포레스트/볼트 서피스 전면 제거.
// 스크롤은 평범하고 정직한 세로 ScrollView, 시트는 Modal이 아니라 형제 View.
//
// [2026-08-24 · Sean picks M② + M④, enh-owner-booking-lab] Two changes, both drawn on the
// paper world the lab's frames use (the booking flow is paper end to end and this screen was
// the last lilac island — DESIGN.md §2 puts service/transaction screens in paper):
//   M② 원값이 크고, 매치는 순위가 된다 — the composite 매치 % leaves the roster and the sheet.
//     It is COMPUTED, not measured, and it renormalises silently for runners with no respond
//     rate (matchFor below). It still ORDERS the list — a rank is a claim we can defend — and
//     the two raw fields the owner is really choosing between (응답률 · 누적 러닝) take the
//     display weight. The three axis bars stay: they are the disclosure of how the rank formed.
//   M④ 0명일 때 문이 있는 화면 — the empty arm used to be one centred sentence with NO action.
//     Same sentence, plus the two doors that already exist: retry, and 내 일정 (whose cancel
//     sheet quotes this booking's own fee tier). ⚠ The empty state must never quote a fee — the
//     ladder is quoted per booking by quote_cancel_fee (server, 0117 §9b), and a second copy is how ladders drift.
// Coral horizontals are capped at TWO full-bleed rules (header + sheet top) — Sean 2026-08-24:
// "the screen shows too many horizontal red lines". Row separators are the neutral #EEEEEE rule
// (theme.ts:206 · request.tsx:1465 — a coral full-bleed rule means SECTION, not list row).

// 로스터 격자 — 레일 헤더와 행이 정확히 같은 트랙을 쓴다
const COL = { rk: 16, av: 40, resp: 56, runs: 52, pace: 46, gap: 8 } as const;

const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);

// 매칭 목표 페이스 — 예약의 실제 페이스에 묶는다 (구: 420 하드코딩된 가상 목표).
// 라벨("6'10\"")의 첫 숫자 = 분. 미지정·파싱 실패면 420(7'00") 폴백.
const paceSecOf = (label?: string | null) => { const m = /(\d+)/.exec(label ?? ''); return m ? Number(m[1]) * 60 : 420; };

// 실러너 추천 점수 — 응답률·경험·페이스 적합의 가중합.
// 데이터가 쌓이면 매칭 엔진(견종 경험·후기·거리)으로 교체. 병원 레지던트식 하이브리드 매칭의 v1.
// [M② 2026-08-24] The score is no longer PRINTED anywhere; it is the ordering key and the three
// axes are still disclosed one by one. Nothing about the computation changed.
// pct: null = no data (a new runner's respond rate) — the bar says 신규 instead of inventing a value.
interface Match { total: number; partial: boolean; reasons: { label: string; pct: number | null }[] }
// gearVerified: 인증 장비 부스트 — 슬롯당 +1, 최대 +2 (가드레일: 핵심 점수 불변, 장비는 승부축이 아니다)
// [honesty audit 2026-08-11 · P1 #3] The old `?? 88` fabricated an 88% respond rate for exactly
// the runners with no data and fed it into the score at 35% weight. Now an unknown respond rate
// excludes that axis and renormalizes the two known axes over their own weight sum
// (0.30 + 0.35 = 0.65) — relative weights between the remaining axes are unchanged, and no
// value is invented. `partial` marks the score so the UI can disclose the two-axis computation.
function matchFor(r: LiveRunner, gearVerified = 0, targetPaceSec = 420): Match {
  const respond = r.respondRate; // number | null — null flows through untouched
  const exp = Math.min(97, 62 + r.totalRuns * 5);
  // paceSec null = 기록 없는 신규 러너 (api.ts 가 더는 7'00" 를 지어내지 않는다). respondRate 가
  // 이미 밟은 길을 그대로: 없는 축은 0 으로 깔지 않고 **빼고**, 남은 축을 재정규화한다.
  const paceFit = r.paceSec != null
    ? Math.max(58, 100 - Math.round(Math.abs(r.paceSec - targetPaceSec) / 4))
    : null;
  const axes: Array<[number | null, number]> = [[respond, 0.35], [exp, 0.3], [paceFit, 0.35]];
  const wsum = axes.reduce((t, [v, w]) => (v != null ? t + w : t), 0);
  const weighted = axes.reduce((t, [v, w]) => (v != null ? t + v * w : t), 0) / (wsum || 1);
  return {
    total: Math.min(99, Math.round(weighted) + Math.min(2, gearVerified)),
    partial: respond == null,
    reasons: [
      { label: '응답 신뢰도', pct: respond },
      { label: '러닝 경험', pct: exp },
      { label: '페이스 적합', pct: paceFit },
    ],
  };
}

// ── 로스터 행 — 한 명 = 한 줄. 탭 = 선택, 이동 없음 ──
// Sean 정제 1: 행은 60-64pt로 숨을 쉰다(48 압축 금지). 정제 2: 아바타 40pt.
// [M②] 오른쪽 세 칸은 이제 전부 **원값**이다 — 응답률·누적 러닝·페이스. 순위는 이름 아래 한 줄.
function RosterRow({ r, rank, selected, isCurrent, onPress, nf }: {
  r: LiveRunner; rank: number; selected: boolean;
  isCurrent: boolean; onPress: () => void; nf: any;
}) {
  const sub = `${rank}순위 · ${r.tier}${isCurrent ? ' · 현재 지명' : ''}`;
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      accessibilityLabel={`${r.name} 러너 · ${sub}${r.respondRate != null ? ` · 응답률 ${r.respondRate}%` : ' · 응답률 신규'}`}
      style={[s.row, selected && s.rowSel]}
    >
      {/* 순위 → 선택되면 잉크 체크로 바뀐다 (선택은 링이 아니라 면 + 표식이다) */}
      <View style={{ width: COL.rk, alignItems: 'center' }}>
        {selected ? (
          <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: paper.ink }}>✓</Text>
        ) : (
          <Text style={[{ fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim }, nf]}>
            {rank < 10 ? `0${rank}` : `${rank}`}
          </Text>
        )}
      </View>

      {/* 아바타 — 사진이 없으면 모노그램. Monogram의 잉크는 흰색 고정이라 면은 항상 어둡게 */}
      <Avatar url={r.avatarUrl} char={r.name[0]} bg={selected ? paper.ink : paper.dim} size={COL.av} />

      <View style={{ flex: 1, minWidth: 0 }}>
        <Text numberOfLines={1} style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>{r.name}</Text>
        <Text numberOfLines={1} style={{ fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim }}>{sub}</Text>
      </View>

      {/* 응답률 — 이 화면에서 가장 큰 숫자. 데이터가 없으면 숫자 대신 '신규' (0을 지어내지 않는다) */}
      {r.respondRate != null ? (
        <Text style={[{ width: COL.resp, textAlign: 'right', fontSize: 18.5, lineHeight: 23, fontWeight: '700', color: paper.ink }, nf]}>
          {r.respondRate}<Text style={{ fontSize: 15 }}>%</Text>
        </Text>
      ) : (
        <Text style={{ width: COL.resp, textAlign: 'right', fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim }}>신규</Text>
      )}
      <Text style={[{ width: COL.runs, textAlign: 'right', fontSize: 16, lineHeight: 20, fontWeight: '600', color: paper.text }, nf]}>{r.totalRuns}회</Text>
      {/* null = 기록 전 신규 러너. 컬럼은 자리가 고정이라 빈 칸이 '빠름'처럼 읽힌다 — 사실을 적는다 */}
      <Text style={[{ width: COL.pace, textAlign: 'right', fontSize: 15, lineHeight: 18, fontWeight: '600', color: r.paceLabel != null ? paper.text : paper.faint }, nf]}>{r.paceLabel ?? '기록 전'}</Text>
    </Pressable>
  );
}

// ── 시트 매치 축 바 — 80 미만은 앰버(약점 축 신호) ──
// pct null = no data: empty track + "신규 · 데이터 없음" — neither a bar length nor a number is invented
function Bar({ label, pct, nf }: { label: string; pct: number | null; nf: any }) {
  if (pct == null) {
    return (
      <Row style={{ gap: 10 }}>
        <Text style={{ width: 84, fontSize: 15, lineHeight: 18, color: paper.text }}>{label}</Text>
        <View style={s.track} />
        <Text style={{ textAlign: 'right', fontSize: 15, lineHeight: 18, fontWeight: '600', color: paper.dim }}>신규 · 데이터 없음</Text>
      </Row>
    );
  }
  const weak = pct < 80;
  const w = Math.max(0, Math.min(100, pct));
  return (
    <Row style={{ gap: 10 }}>
      {/* [FLOOR15] 76 → 84: 최장 라벨 '응답 신뢰도'(한글 5 + 공백)가 14pt 에서 ≈74px — 76은 여유 2px 뿐이라 랩됐다 */}
      <Text style={{ width: 84, fontSize: 15, lineHeight: 18, color: paper.text }}>{label}</Text>
      <View style={s.track}>
        <View style={{ height: '100%', backgroundColor: weak ? paper.pending : paper.ink, width: `${w}%` }} />
      </View>
      <Text style={[{ width: 34, textAlign: 'right', fontSize: 15, lineHeight: 18, fontWeight: '700', color: weak ? paper.pending : paper.ink }, nf]}>{pct}</Text>
    </Row>
  );
}

export default function Matching() {
  const df = useDisplayFont(); // Black Han Sans — 화면에서 딱 한 번(시트의 러너 이름)
  const nf = useNumFont();     // Oswald — 응답률·러닝·페이스 등 모든 숫자
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
  }, [liveRunners, gearMap, targetPaceSec, rebook]);
  const top = scored[0];
  const topIsPreferred = !rebook && !!top && top.r.profileId === draft.preferredRunnerId;
  // 시트는 절대 비지 않는다 — 선택이 없거나 사라졌으면 AI 1순위로 폴백
  const selIdx = scored.findIndex((x) => x.r.profileId === selectedId);
  const sel = selIdx >= 0 ? scored[selIdx] : top;
  const selRank = (selIdx >= 0 ? selIdx : 0) + 1;
  // 러너 변경 모드의 기준점 — 현재 지명 러너 (목록에 있으면 순위·응답률 델타 계산 가능)
  const curIdx = currentRunnerId ? scored.findIndex((x) => x.r.profileId === currentRunnerId) : -1;
  const curEntry = curIdx >= 0 ? scored[curIdx] : undefined;
  const selIsCurrent = !!sel && !!currentRunnerId && sel.r.profileId === currentRunnerId;
  const lockCta = rebook && selIsCurrent; // 현재 지명자를 다시 지명하는 건 액션이 성립하지 않는다
  const selGear = sel ? (gearMap[sel.r.profileId] ?? []).filter((g) => g.verified) : [];
  // M④: 세 개의 비-정상 상태는 서로 다른 사실이다 — 실패·로딩·빈 명단을 한 문장으로 뭉치지 않는다
  const rosterEmpty = live && !rosterError && !rosterLoading && liveRunners.length === 0;

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
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* ── ① 헤더 — 로스터/시트와 분리된 고정 크롬 ── */}
      <View style={s.head}>
        <Row style={{ gap: 10 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 20, fontWeight: '800', color: paper.ink }}>
            {rebook ? '러너 변경' : '러너 선택'}
          </Text>
          {rebook && (
            <View style={s.headTag}><Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '800', color: paper.actionInk }}>재요청</Text></View>
          )}
        </Row>
        <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 8 }}>
          {rebook
            ? '이 예약 그대로 다른 러너에게 다시 요청해요\n새 러너를 지명하면 기존 지명은 자동으로 취소돼요'
            : live ? '러너를 지명하거나, 오픈 매칭으로 기다릴 수 있어요\n보통 몇 분 안에 응답이 와요'
              /* 🔴 [정직 2026-08-27] 이 자리는 「보호자님과 러너의 선호도를 종합 분석했어요」였다.
                 그런데 이건 **예약이 없는 분기**다 (`!live`) — 화면 본문이 바로 아래에서
                 「진행 중인 예약이 없어요」라고 말한다. 분석할 대상이 없는 상태에서 분석을
                 마쳤다고 주장했고, 그런 분석기는 앱에도 서버에도 없다 (fit 필드는 2026-08-06에
                 같은 이유로 은퇴했다 — store.ts RouteInfo 주석). 없는 예약에 대해 한 적 없는
                 계산을 말하는 대신, 이 화면이 무엇을 하는 곳인지만 말한다. */
              : '예약을 만들면 여기서 러너를 고를 수 있어요'}
        </Text>
        {/* '지금 누구를 바꾸는 중인지'는 별도 밴드 대신 로스터 행의 [현재 지명] 줄과
            시트의 델타 밴드가 답한다 — 같은 사실을 세 번 말하면 명단 볼 자리가 없다. */}
      </View>
      {/* 코랄 풀블리드 룰 ① — 섹션 구분(헤더/본문). 이 화면의 코랄 가로선은 여기와 시트 상단 둘뿐 */}
      <View style={s.rule} />

      {/* ── ② 로스터 — 평범하고 정직한 세로 스크롤 (덱·스냅 없음) ── */}
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 15, paddingTop: 4, paddingBottom: 24 }}
        showsVerticalScrollIndicator={false}
      >
        {live && top && (
          <>
            {/* 컬럼 레일 = 범례 + 명단 규모. 행과 같은 트랙을 쓴다 */}
            <Row style={s.rail}>
              <Text style={{ flex: 1, fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim }}>러너 {scored.length}명 · AI 추천 순</Text>
              <Text style={[s.railCol, { width: COL.resp }]}>응답률</Text>
              <Text style={[s.railCol, { width: COL.runs }]}>러닝</Text>
              <Text style={[s.railCol, { width: COL.pace }]}>페이스</Text>
            </Row>

            {scored.map(({ r }, i) => (
              <RosterRow
                key={r.profileId}
                r={r} rank={i + 1} nf={nf}
                selected={!!sel && sel.r.profileId === r.profileId}
                isCurrent={r.profileId === currentRunnerId}
                onPress={() => select(r.profileId)}
              />
            ))}

            {/* 이 순서의 근거 — 새 데이터 없이 시트와 같은 세 축으로만 설명.
                [M②] 매치 %는 화면에서 사라졌지만 근거는 남는다 — 순위가 어떻게 나왔는지는 여전히 말해야 한다 */}
            <View style={s.why}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: paper.ink }}>이 순서는 어떻게 나왔나요</Text>
              <View style={{ gap: 7, marginTop: 9 }}>
                <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text }}>
                  <Text style={{ fontWeight: '800', color: paper.ink }}>응답률</Text> — 지명 요청을 받고 실제로 수락한 비율이에요.
                </Text>
                <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text }}>
                  <Text style={{ fontWeight: '800', color: paper.ink }}>러닝</Text> — 지금까지 완료한 러닝 횟수를 봐요.
                </Text>
                <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text }}>
                  <Text style={{ fontWeight: '800', color: paper.ink }}>페이스 적합</Text> — 이 예약의 페이스
                  {/* Oswald는 명시 lineHeight ≥1.2× 없이는 어센더가 잘린다 (BUG A) — 중첩 Text도 예외 아님 */}
                  {targetPaceLabel ? <Text style={[{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink }, nf]}>{` ${targetPaceLabel} `}</Text> : ' '}
                  기준으로 러너 페이스가 얼마나 맞는지예요.
                </Text>
              </View>
              <Text style={{ marginTop: 11, paddingTop: 10, borderTopWidth: 1, borderTopColor: '#EEEEEE', fontSize: 15, lineHeight: 19, color: paper.dim }}>
                세 축을 합쳐 순위를 정해요 — 1순위가 AI 추천이에요. 응답률 데이터가 없는 신규 러너는 나머지 두 축으로만 계산해요. 인증 장비는 슬롯당 +1(최대 +2)만 더해요.
              </Text>
            </View>

            <Text style={{ marginTop: 16, textAlign: 'center', fontSize: 15, lineHeight: 19, color: paper.dim }}>
              지명 없이 두면 오픈 매칭으로 모든 러너에게 보여요
            </Text>
          </>
        )}

        {/* 데모 매칭 섹션 은퇴 (2026-07-23) — 목업 김민준 화면이 결제 실패를 숨기는 함정이었음.
            이 화면은 이제 실예약 전용. */}
        {!live && (
          // [§E.5] 요청 화면에 결제 단계는 없다 — 홀드가 잡히면 그 자리에서 matching으로 넘어가고
          // 바로 러너 찾기로 간다. "결제하면 러너 선택이 열려요"는 없는 단계를 가리키고 있었다.
          <View style={{ paddingTop: 22 }}>
            <Text style={{ fontSize: 19, lineHeight: 26, fontWeight: '800', color: paper.ink }}>
              진행 중인 예약이 없어요
            </Text>
            <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text, marginTop: 8 }}>
              예약하면 러너 선택이 열려요
            </Text>
          </View>
        )}

        {/* [M④ · LOAD FAILED] 실패는 실패로 — 라우드-페일 스트립 + 재시도 (라벨 스왑, 불투명도 트릭 금지) */}
        {live && rosterError && (
          <View style={s.failStrip}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.critical }}>러너 목록을 불러오지 못했어요</Text>
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.critical }}>{rosterError}</Text>
            </View>
            <Pressable
              onPress={loadRoster}
              disabled={rosterLoading}
              accessibilityRole="button"
              accessibilityLabel="다시 시도"
              accessibilityState={{ disabled: rosterLoading }}
              style={{ minHeight: 44, justifyContent: 'center' }}
            >
              <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
                {rosterLoading ? '확인 중…' : '다시 시도'}
              </Text>
            </Pressable>
          </View>
        )}

        {/* [M④ · LOADING] 로딩은 빈 명단이 아니다 */}
        {live && !rosterError && rosterLoading && liveRunners.length === 0 && (
          <Text style={{ paddingTop: 22, fontSize: 15, lineHeight: 19, color: paper.text }}>
            이 시간에 갈 수 있는 러너를 찾는 중…
          </Text>
        )}

        {/* [M④ · NO AVAILABLE RUNNERS] 같은 문장, 이제 문이 있다.
            ⚠ 여기서 취소 수수료를 인용하지 않는다 — 일정 화면이 예약별로 계산해 말한다 */}
        {rosterEmpty && (
          <View style={{ paddingTop: 22 }}>
            <Text style={{ fontSize: 19, lineHeight: 26, fontWeight: '800', color: paper.ink }}>
              이 시간에 갈 수 있는{'\n'}러너가 지금 없어요
            </Text>
            <Text style={{ fontSize: 15, lineHeight: 20, color: paper.text, marginTop: 9 }}>
              오픈 매칭으로 등록돼 있어요 — 일정이 빈 러너가 응답할 수 있어요.{'\n'}기다리는 동안 이 예약은 그대로 살아 있어요.
            </Text>
            <View style={{ marginTop: 18, gap: 10 }}>
              {/* 이 버튼을 누르면 즉시 로딩 상태로 넘어가므로(위 arm) busy 라벨 스왑은 여기서 필요 없다 */}
              <PaperBtn label="러너 다시 찾기" variant="secondary" onPress={loadRoster} />
              <PaperBtn label="내 일정에서 이 예약 보기 ›" variant="secondary" onPress={() => router.push('/owner/schedule')} />
            </View>
            <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 12 }}>
              일정 화면에서 시간 변경·취소를 할 수 있어요 — 취소 조건은 그 화면이 예약별로 알려드려요
            </Text>
          </View>
        )}
      </ScrollView>

      {/* ── ③ 결정 시트 — 화면에 단 하나. Modal이 아니라 형제 View, 절대 비지 않는다 ── */}
      {live && sel && (
        <View style={s.sheet}>
          <Row style={{ gap: 9, marginBottom: 12 }}>
            <Text style={s.kick}>선택한 러너</Text>
            <View style={{ flex: 1, height: 1, backgroundColor: '#EEEEEE' }} />
            <Pressable
              onPress={() => router.push(`/runner-profile/${sel.r.profileId}`)}
              style={s.profBtn}
              accessibilityRole="button"
              accessibilityLabel={`${sel.r.name} 러너 프로필 보기`}
            >
              <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '800', color: paper.ink }}>프로필 ›</Text>
            </Pressable>
          </Row>

          {/* 신원 — 아바타 · Black Han Sans 이름(화면에서 한 번) · 사람 문장 · [M②] 원값 응답률 */}
          <Row style={{ gap: 12, alignItems: 'flex-start' }}>
            <Avatar url={sel.r.avatarUrl} char={sel.r.name[0]} bg={paper.ink} size={52} />
            <View style={{ flex: 1, minWidth: 0 }}>
              <Row style={{ gap: 7 }}>
                <Text numberOfLines={1} style={[{ fontSize: 20, color: paper.ink }, df]}>{sel.r.name}</Text>
                {top && sel.r.profileId === top.r.profileId && (
                  <View style={s.aiTag}>
                    <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '800', color: paper.actionInk }}>
                      {topIsPreferred ? '내가 고른 러너' : 'AI 1순위'}
                    </Text>
                  </View>
                )}
              </Row>
              {/* 사람 문장 — 실필드(동네·누적 러닝·순위)만으로 */}
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text, marginTop: 5 }}>
                {sel.r.totalRuns > 0 ? (
                  <>
                    {sel.r.district || '이 동네'}에서 <Text style={[{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink }, nf]}>{sel.r.totalRuns}</Text>번 달렸어요
                  </>
                ) : (
                  `${sel.r.district || '이 동네'}에서 첫 러닝을 기다리고 있어요`
                )}
              </Text>
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 2 }}>{selRank}순위 · {sel.r.tier}</Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              {sel.r.respondRate != null ? (
                <Text style={[{ fontSize: 27, lineHeight: 33, fontWeight: '700', color: paper.ink }, nf]}>
                  {sel.r.respondRate}<Text style={{ fontSize: 15, color: paper.dim }}>%</Text>
                </Text>
              ) : (
                <Text style={{ fontSize: 19, lineHeight: 25, fontWeight: '800', color: paper.dim }}>신규</Text>
              )}
              <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim }}>응답률</Text>
            </View>
          </Row>

          {/* Match axes — an unknown respond rate renders as 신규 and the score discloses it's partial */}
          <View style={{ marginTop: 12, paddingTop: 12, borderTopWidth: 1, borderTopColor: '#EEEEEE', gap: 7 }}>
            {sel.m.reasons.map((reason) => (
              <Bar key={reason.label} label={reason.label} pct={reason.pct} nf={nf} />
            ))}
            {sel.m.partial && (
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim }}>
                아직 응답률 데이터가 없어 경험·페이스 두 축으로만 계산한 순위예요
              </Text>
            )}
          </View>

          {/* 러너 변경 델타 — 현재 지명 러너 대비. [M②] 합성 점수가 아니라 순위와 원값으로 말한다 */}
          {rebook && curEntry && (
            <View style={s.delta}>
              {selIsCurrent ? (
                <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text }}>지금 이 예약에 지명돼 있는 러너예요.</Text>
              ) : (() => {
                const dr = (sel.r.respondRate == null || curEntry.r.respondRate == null) ? null : sel.r.respondRate - curEntry.r.respondRate;
                return (
                  <Row style={{ gap: 9, flexWrap: 'wrap' }}>
                    <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text }}>
                      현재 <Text style={{ fontWeight: '800', color: paper.ink }}>{curEntry.r.name}</Text> 대비
                    </Text>
                    <Text style={[{ fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.ink }, nf]}>{curIdx + 1}순위 → {selRank}순위</Text>
                    {dr == null
                      ? <Text style={{ fontSize: 15, lineHeight: 18, color: paper.dim }}>응답률 비교 불가 · 신규</Text>
                      : <Text style={[{ fontSize: 15, lineHeight: 18, fontWeight: '700', color: dr >= 0 ? paper.ink : paper.pending }, nf]}>응답 {signed(dr)}</Text>}
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
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 11 }}>
                {selGear.some((g) => g.kind === 'bodycam')
                  ? '러너가 보유한 장비예요 — 영상 제공은 아직 지원하지 않아요'
                  : '러너가 보유한 장비예요'}
              </Text>
              <Row style={{ gap: 7, marginTop: 7, flexWrap: 'wrap' }}>
                {selGear.map((g) => (
                  <View key={g.id} style={s.gearChip}>
                    <Text style={{ fontSize: 15, lineHeight: 18, fontWeight: '600', color: paper.text }}>
                      {GEAR_META[g.kind].name} <Text style={{ color: paper.actionInk, fontWeight: '800' }}>✓</Text>
                    </Text>
                  </View>
                ))}
              </Row>
            </>
          )}

          {/* 유일한 큰 버튼 — 시트 안에 산다. 화면의 유일한 코랄 면이기도 하다 */}
          {lockCta ? (
            <View style={s.ctaLock}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: paper.ink }}>이미 지명된 러너예요</Text>
              <Text style={{ fontSize: 15, lineHeight: 18, color: paper.dim, marginTop: 3 }}>다른 러너를 선택하면 재요청할 수 있어요</Text>
            </View>
          ) : (
            <Pressable
              onPress={() => nominate(sel.r)}
              disabled={nominating !== null} /* 전송 중 잠금 = 이중 지명 방지 (디렉터 판정: 안전 우선) */
              accessibilityRole="button"
              accessibilityLabel={`${sel.r.name} 러너 지명 요청`}
              /* The lock was visible (opacity) and enforced (disabled) but never announced —
                 VoiceOver read a live 지명 요청 button mid-send. Same predicate, three outputs.
                 [2026-08-24] 불투명도 트릭 은퇴 — 잠금은 라벨 스왑 + pressed 면으로만 말한다 (F2.1). */
              accessibilityState={{ disabled: nominating !== null }}
              /* [Sean 2026-08-26 press behaviour] filled primary = a physical key. Rest carries a
                 4px lip in the pressed fill; press gives 3px of that edge back and takes it as
                 translateY(3), so the bottom edge stays put and the key descends into it. The
                 send lock keeps the rest lip and loses only the travel — same predicate as
                 PaperBtn's busy arm, because the face stays action here rather than going to
                 disabledFill. No scale on a filled button (§3b). */
              style={({ pressed }) => {
                const live = pressed && nominating === null;
                return [
                  s.cta,
                  { backgroundColor: live ? paper.actionPressed : paper.action },
                  live
                    ? { transform: [{ translateY: 3 }], borderBottomWidth: 1, borderBottomColor: paper.actionPressed }
                    : { borderBottomWidth: 4, borderBottomColor: paper.actionPressed },
                ];
              }}
            >
              <Row style={{ gap: 10 }}>
                <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>
                  {nominating === sel.r.profileId ? '전송 중...' : '지명 요청'}
                </Text>
                <View style={{ flex: 1 }} />
                {/* 플레이트 = 원값 두 개(점수 아님). 작은 흰 글씨는 코랄 위에 직접 앉지 않는다 —
                    actionPressed(#A83315) 잉크 플레이트 위에서 6.67:1 (알파 금지, 명시 색) */}
                <View style={s.ctaPlate}>
                  <Text style={[{ fontSize: 15, lineHeight: 18, fontWeight: '600', color: '#FFFFFF' }, nf]}>{sel.r.paceLabel ?? '기록 전'}</Text>
                  <View style={{ width: 1, height: 11, backgroundColor: '#FFFFFF' }} />
                  <Text style={[{ fontSize: 15, lineHeight: 18, fontWeight: '600', color: '#FFFFFF' }, nf]}>
                    {sel.r.respondRate != null ? `응답 ${sel.r.respondRate}%` : '신규'}
                  </Text>
                </View>
                <Text style={{ fontSize: 18, fontWeight: '800', color: '#FFFFFF' }}>›</Text>
              </Row>
            </Pressable>
          )}
        </View>
      )}

      {/* 시트가 열리지 않는 상태에도 아래는 비지 않는다 — 왜 비었는지 한 줄로 말한다 (M④) */}
      {live && !sel && (
        <View style={s.sheetQuiet}>
          <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, textAlign: 'center' }}>
            선택한 러너가 없어 지명 시트는 열리지 않아요
          </Text>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  // ── 헤더 크롬 (페이퍼 리페인트) ──
  head: { paddingTop: 56, paddingHorizontal: 15, paddingBottom: 11, backgroundColor: paper.canvas },
  // 40×40 스퀘어 백 버튼 — request.tsx circleBtn 문법
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  headTag: { backgroundColor: paper.wash, paddingVertical: 4, paddingHorizontal: 9 },
  // 코랄 풀블리드 헤어라인 — 사이드 마진 금지 (§순백/코랄 법)
  rule: { height: 1, backgroundColor: paper.line },
  // ── 로스터 ──
  rail: { gap: COL.gap, paddingTop: 9, paddingBottom: 7 },
  railCol: { textAlign: 'right', fontSize: 15, lineHeight: 18, fontWeight: '600', color: paper.dim },
  // Sean 정제 1: 60-64pt 행 — 압축 금지. 행 구분선은 뉴트럴(#EEE): 코랄 풀블리드는 섹션의 문법이다
  row: {
    flexDirection: 'row', alignItems: 'center', gap: COL.gap, minHeight: 62,
    paddingVertical: 11, borderTopWidth: 1, borderTopColor: '#EEEEEE',
  },
  // 선택 = 면(코랄 95% 워시) + 체크. 링·그림자 은퇴. 풀블리드로 빼서 행 전체가 선택으로 읽히게
  rowSel: { backgroundColor: paper.wash, marginHorizontal: -15, paddingHorizontal: 15 },
  // ── 순서 근거 ──
  why: { marginTop: 18, paddingTop: 14, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  // ── 라우드-페일 스트립 (F1.2) — criticalWash 면 + critical 잉크 + 밑줄 재시도 ──
  failStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    marginHorizontal: -15, paddingHorizontal: 15, paddingVertical: 11, marginTop: 18,
  },
  // ── 결정 시트 ── 코랄 풀블리드 룰 ② (이 화면의 마지막 코랄 가로선)
  sheet: {
    backgroundColor: paper.canvas, borderTopWidth: 1, borderTopColor: paper.line,
    paddingTop: 14, paddingHorizontal: 15, paddingBottom: 22,
  },
  sheetQuiet: {
    backgroundColor: paper.canvas, borderTopWidth: 1, borderTopColor: paper.line,
    paddingHorizontal: 15, paddingVertical: 14,
  },
  kick: { fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim },
  profBtn: {
    borderWidth: 1, borderColor: '#EEEEEE', backgroundColor: paper.canvas,
    paddingVertical: 7, paddingHorizontal: 10, minHeight: 34, justifyContent: 'center',
  },
  aiTag: { backgroundColor: paper.wash, paddingVertical: 2, paddingHorizontal: 7 },
  track: {
    flex: 1, height: 9, backgroundColor: paper.disabledFill,
    borderWidth: 1, borderColor: '#EEEEEE', overflow: 'hidden',
  },
  delta: { marginTop: 11, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 8, paddingHorizontal: 11 },
  gearChip: { borderWidth: 1, borderColor: '#EEEEEE', backgroundColor: paper.canvas, paddingVertical: 5, paddingHorizontal: 9 },
  // 코랄 종단 스톱(paper.action #C6472C) 위 흰 라벨 — 이 화면에서 흰 글씨가 코랄에 올라가는 유일한 자리
  cta: { marginTop: 14, paddingVertical: 15, paddingHorizontal: 15 },
  ctaLock: {
    marginTop: 14, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 13, paddingHorizontal: 15, alignItems: 'flex-start',
  },
  ctaPlate: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: paper.actionPressed, paddingVertical: 5, paddingHorizontal: 9,
  },
});
