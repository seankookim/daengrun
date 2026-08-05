import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Dimensions, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { PatchBadge, worldOf } from '../src/components/patch';
import { Row } from '../src/components/ui';
import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { CoursePatch, deriveStamps, fetchCoursePatches, fetchStampStats, StampInfo, StampStats } from '../src/lib/api';
import { lilac, lilacRadius, lilacShadow } from '../src/theme';

// 컬렉션 — 여권의 부속서(ANNEX). 리워드 ② 랩 Ⓑ① 채택.
// [정직 수리 2026-08-05] 목업 카드 6장(myCards) 퇴역 → 실파생 패치 월만 남았고,
// [라일락 리페인트 2026-08-05] 이 화면의 크림/볼트 잔재(테마 컨텍스트 팔레트 · 볼트딥 카운트)를 은퇴시키고
//   여권 문법으로 다시 칠했다: §도장(잉크 페이지) + §코스 패치(나이트 라일락 웰).
// 두 재질은 억지로 하나로 합치지 않는다 — 종이에 찍은 잉크와 자수 배지는 다른 물건이다.

const GRADE_LABEL: Record<string, string> = { basic: '획득', silver: '실버', gold: '골드', master: '마스터' };
const nextGrade = (n: number) => (n < 5 ? `실버까지 ${5 - n}회` : n < 10 ? `골드까지 ${10 - n}회` : n < 25 ? `마스터까지 ${25 - n}회` : '코스 마스터 👑');

// ══════════ 잉크 법 (my.tsx §③과 동일 — 표현만 공유, 택소노미는 deriveStamps 단일 소스) ══════════
const INK = '#4A3DA8';                    // 읽는 바이올렛 — 흰 카드 위 8.32:1
const INK_FILL = 'rgba(108,92,231,0.05)';
const NIGHT = '#1C1837';                  // 패치 웰 바닥 (기록면과 같은 나이트 라일락)
const NIGHT_INK = '#B9AEF5';              // 나이트 위 바이올렛 — 8.45:1
const NIGHT_DIM = '#A9A3C8';              // 나이트 위 보조 — 7.09:1

const W = Dimensions.get('window').width;
// 도장 그리드 폭 예산 (my.tsx §③과 동일 산술 — 두 그리드가 같은 칸에서 읽히도록)
//   패딩 16*2 · 카드 보더 1*2 · 내부 마진 9*2 · 내부 보더 1*2 · 내부 패딩 11*2 = W-76
//   320dp: 244 → 칸 74 · 디스크 68 (3*74+2*10 = 242 ≤ 244 ✓) · 390dp: 314 → 칸 97 · 디스크 76
const STAMP_GRID_W = W - 76;
const STAMP_GAP = 10;
const STAMP_CELL_W = Math.floor((STAMP_GRID_W - STAMP_GAP * 2 - 1) / 3);
const DISC = Math.min(76, STAMP_CELL_W - 6);

// 패치 웰 폭 예산 — 웰은 보더 없이 패딩 11*2만 먹는다 (W-32-22 = W-54)
//   320dp: 266 → 2열, 칸 127 (코스 이름이 잘리지 않는 폭) · 360dp: 306 → 3열, 칸 95
//   390dp: 336 → 3열, 칸 105. 배지는 76 고정 — 60 미만이면 PatchBadge의 월드 라벨이 사라진다.
//   3열 문턱을 296으로 잡은 이유: 그 아래에서 칸이 92 미만이 되고, 76 배지가 칸을 꽉 채워 이름이 갈린다.
const PATCH_GRID_W = W - 54;
const PATCH_GAP = 10;
const PATCH_COLS = PATCH_GRID_W >= 296 ? 3 : 2;
const PATCH_CELL_W = Math.floor((PATCH_GRID_W - PATCH_GAP * (PATCH_COLS - 1) - 1) / PATCH_COLS);
const BADGE = Math.min(76, PATCH_CELL_W - 6);

// 월드색 알파 — 나이트 바닥에서 잠긴 패치 힌트의 대비를 올린다 (patch.tsx의 dim은 흰 카드 기준값이었다)
function withA(hex: string, a: number): string {
  const h = hex.replace('#', '');
  return `rgba(${parseInt(h.slice(0, 2), 16)},${parseInt(h.slice(2, 4), 16)},${parseInt(h.slice(4, 6), 16)},${a})`;
}

// 도장 한 칸 — 획득: 바이올렛 잉크 + rings만큼의 링 · 첫-가족: 코랄 엣지+도트 · 미획득: 대시 헤어라인.
// v1에서 도장은 눌리지 않는다 (상세 화면 없음 = 죽은 버튼 금지).
// 기울기는 deriveStamps의 고정 각도(info.angle) 그대로 — 마이와 부속서에서 같은 도장은 같게 기운다.
function StampCell({ info, nf }: { info: StampInfo; nf: TextStyle | null }) {
  const on = info.earned;
  return (
    <View style={s.scell}>
      <View
        style={[
          s.disc,
          on ? (info.coral ? s.discCoral : s.discOn) : s.discOff,
          on && { transform: [{ rotate: `${info.angle}deg` }] },
        ]}
      >
        {on && info.rings >= 2 && <View style={[s.ring2, info.rings >= 3 && s.ring2Top, info.coral && s.ring2Coral]} />}
        {on && info.rings >= 3 && <View style={s.ring3} />}
        {on && info.coral && <View style={s.dot1} />}
        <Text style={[s.discN, nf, !on && s.discInkOff]}>{info.num}</Text>
        <Text style={[s.discW, !on && s.discInkOff]}>{info.word}</Text>
      </View>
      {/* 받은 칸은 이름을, 빈 칸은 실진행(있으면)을, 진행이 뜻없는 1회짜리는 조건을 말한다 */}
      <Text style={[s.scellCond, on && s.scellCondOn]} numberOfLines={2}>
        {on ? info.label : (info.prog ?? info.cond)}
      </Text>
    </View>
  );
}

export default function Cards() {
  const df = useDisplayFont(); // 화면당 1회 — 타이틀 '컬렉션'
  const nf = useNumFont();     // Oswald — 숫자·라틴 키커

  // 코스 패치 월 (2026-07-28) — ×1 획득 → ×5 실버 → ×10 골드 → ×25 마스터
  const [patches, setPatches] = useState<{ earned: CoursePatch[]; locked: { routeId: string; name: string; km: number }[] } | null>(null);
  // 도장 (리워드 ②) — 파생 실데이터. null이면 §도장 섹션 자체가 없다 (로딩은 0이 아니다).
  const [stampStats, setStampStats] = useState<StampStats | null>(null);
  const stamps = useMemo(() => (stampStats ? deriveStamps(stampStats) : null), [stampStats]);
  const stampsEarned = stamps ? stamps.filter((x) => x.earned).length : 0;

  // 실패는 실패로, 그리고 실패한 쪽만 — 한쪽만 죽으면 그 섹션 자리에서 실패를 말한다.
  // (섹션이 조용히 사라지면 '아직 아무것도 없어요'로 읽힌다 = 조용한 catch → 행복한 UI)
  const [stampErr, setStampErr] = useState(false);
  const [patchErr, setPatchErr] = useState(false);
  useEffect(() => {
    fetchCoursePatches().then(setPatches).catch((e) => { setPatchErr(true); console.warn('[cards] patches:', e?.message ?? e); });
    fetchStampStats().then(setStampStats).catch((e) => { setStampErr(true); console.warn('[cards] stamps:', e?.message ?? e); });
  }, []);

  const patchTotal = patches ? patches.earned.length + patches.locked.length : 0;
  const bothFailed = stampErr && patchErr && !stamps && !patches;

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 30 }}>

        {/* ————— 마스트헤드 — 부속서 표지 ————— */}
        {/* 뒤로: 여기로 오는 길은 전부 push다(마이 · 오너 홈 비컨 · 러너 홈 · 리포트 오버레이) →
            back()이 항상 맞다. 스택이 없을 때만(딥링크·리스타트) 홈으로 떨어진다. */}
        <Pressable
          style={s.cbar}
          onPress={() => (router.canGoBack() ? router.back() : router.replace(homePath()))}
        >
          <Text style={s.cbarGlyph}>‹</Text>
          <Text style={s.cbarLabel}>뒤로</Text>
        </Pressable>

        <Row style={s.kicker}>
          <Text style={[s.kickerTxt, nf]}>DOGS HIGH · COLLECTION</Text>
          <View style={s.rule} />
          <Text style={[s.kickerTxt, nf]}>ANNEX</Text>
        </Row>
        <Row style={{ alignItems: 'flex-start', gap: 10 }}>
          <Text style={[s.h1, df]}>컬렉션</Text>
          <View style={s.official}><Text style={[s.officialTxt, nf]}>ANNEX</Text></View>
        </Row>
        <Text style={s.subNote}>여권의 부속서예요 — 도장과 코스 패치가 한 수집함에 있어요</Text>

        {/* ————— 요약 — 두 숫자 모두 실파생. 안 온 쪽은 칸 자체가 없다 ————— */}
        {(stamps || patchTotal > 0) && (
          <Row style={s.sum}>
            {stamps && (
              <View style={s.sumC}>
                <Text style={[s.sumK, nf]}>STAMPS</Text>
                <Text style={[s.sumV, nf]}>{stampsEarned}<Text style={s.sumVU}> / {stamps.length}</Text></Text>
                <Text style={s.sumL}>받은 도장</Text>
              </View>
            )}
            {patches && patchTotal > 0 && (
              <View style={[s.sumC, !!stamps && s.sumDiv]}>
                <Text style={[s.sumK, nf]}>COURSES</Text>
                <Text style={[s.sumV, nf]}>{patches.earned.length}<Text style={s.sumVU}> / {patchTotal}</Text></Text>
                <Text style={s.sumL}>개척한 코스</Text>
              </View>
            )}
          </Row>
        )}

        {bothFailed && (
          <View style={s.errBox}>
            <Text style={s.errT}>수집함을 불러오지 못했어요</Text>
            <Text style={s.errD}>네트워크를 확인하고 화면을 다시 열어주세요</Text>
          </View>
        )}

        {/* ————— § 도장 — 잉크 페이지 (my.tsx §③과 같은 칸, 조금 더 넉넉한 행간) ————— */}
        {!stamps && stampErr && !bothFailed && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>STAMPS</Text>
              <Text style={s.secKo}>도장</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}><Text style={s.failTxt}>도장을 불러오지 못했어요 — 다시 열면 다시 시도해요</Text></View>
          </>
        )}
        {stamps && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>STAMPS</Text>
              <Text style={s.secKo}>도장</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.visa}>
              <View style={s.visaInner}>
                <Row style={s.visaStrap}>
                  <Text style={[s.microK, nf]}>MILESTONE / 마일스톤</Text>
                  <View style={s.visaCnt}>
                    <Text style={[s.visaCntTxt, nf]}>{stampsEarned} / {stamps.length}</Text>
                  </View>
                </Row>
                {stampsEarned === 0 && (
                  <View style={s.empt}>
                    <Text style={s.emptT}>도장면은 비어 있는 채로 시작해요</Text>
                    {/* 영속성 카피 주의 — '영구' 류 약속은 거짓이 될 수 있다: 자랑 글 삭제·코스 비활성이 실제 감소 벡터 (api.ts 계약 주석) */}
                    <Text style={s.emptD}>첫 러닝을 완주하면 왼쪽 위 칸부터 찍혀요. 기록이 남아 있는 한 도장은 그대로예요.</Text>
                  </View>
                )}
                <View style={s.sgrid}>
                  {stamps.map((st) => <StampCell key={st.key} info={st} nf={nf} />)}
                </View>
              </View>
            </View>
          </>
        )}

        {/* ————— § 코스 패치 — 나이트 라일락 웰 (어두운 디스크에는 어두운 바닥이 필요하다) ————— */}
        {!patches && patchErr && !bothFailed && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>PATCHES</Text>
              <Text style={s.secKo}>코스 패치</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}><Text style={s.failTxt}>코스 패치를 불러오지 못했어요 — 다시 열면 다시 시도해요</Text></View>
          </>
        )}
        {patches && patchTotal > 0 && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>PATCHES</Text>
              <Text style={s.secKo}>코스 패치</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.well}>
              <Row style={s.wellK}>
                <Text style={s.wellT}>코스 패치</Text>
                <Text style={[s.wellC, nf]}>{patches.earned.length} / {patchTotal}</Text>
              </Row>
              <Text style={s.wellNote}>
                거리마다 색 세계 — TRAIL · FOREST · RIVER · NIGHT · HALF{'\n'}×5 실버 · ×10 골드 · ×25 마스터
              </Text>
              <View style={s.pgrid}>
                {patches.earned.map((pt) => (
                  <Pressable key={pt.routeId} onPress={() => router.push(`/course/${pt.routeId}`)} style={s.pcell}>
                    {/* name을 넘기지 않는다 — PatchBadge 안의 이름은 ~6.5px(플로어 미달)이고 아래 14pt 라벨과 중복이었다 */}
                    <PatchBadge km={pt.km} grade={pt.grade} size={BADGE} />
                    <Text numberOfLines={1} style={s.pName}>{pt.name}</Text>
                    <Text numberOfLines={1} style={s.pSub}>{GRADE_LABEL[pt.grade]} ×{pt.count}</Text>
                    <Text numberOfLines={1} style={s.pNext}>{nextGrade(pt.count)}</Text>
                  </Pressable>
                ))}
                {patches.locked.map((pt) => {
                  const w = worldOf(pt.km);
                  return (
                    <Pressable key={pt.routeId} onPress={() => router.push(`/course/${pt.routeId}`)} style={s.pcell}>
                      {/* 잠긴 패치도 월드색 힌트 — '저 색을 갖고 싶다' (P2).
                          나이트 바닥에서 dim(월드색 55%)은 2.7~4.9:1로 얕아 링은 70%, 숫자는 80%로 올렸다. */}
                      <View style={[s.pLock, { borderColor: withA(w.tone, 0.7) }]}>
                        <Text style={[s.pLockKm, { color: withA(w.tone, 0.8) }]}>{pt.km}K</Text>
                        <Text style={[s.pLockWorld, { color: withA(w.tone, 0.7) }]}>{w.label}</Text>
                      </View>
                      <Text numberOfLines={1} style={[s.pName, s.pNameOff]}>{pt.name}</Text>
                      <Text numberOfLines={1} style={s.pSub}>완주하면 획득 ›</Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </>
        )}

      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  // 마스트헤드
  cbar: { flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start', paddingVertical: 4, paddingRight: 10, marginBottom: 4 },
  cbarGlyph: { fontSize: 22, lineHeight: 26, color: lilac.head },
  cbarLabel: { fontSize: 14, fontWeight: '700', color: lilac.head },
  kicker: { alignItems: 'center', gap: 8, marginTop: 4, marginBottom: 8 },
  kickerTxt: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  h1: { fontSize: 40, fontWeight: '900', color: lilac.head, lineHeight: 48 },
  official: {
    marginTop: 6, borderWidth: 1, borderColor: lilac.head, borderRadius: 2,
    paddingVertical: 5, paddingHorizontal: 8, backgroundColor: lilac.card,
  },
  officialTxt: { fontSize: 11.5, letterSpacing: 1.8, color: lilac.head, fontWeight: '600' },
  subNote: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 9 },

  // 요약 스트립
  sum: {
    alignItems: 'stretch', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 12, ...lilacShadow,
  },
  sumC: { flex: 1, paddingVertical: 11, paddingHorizontal: 12 },
  sumDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2 },
  sumK: { fontSize: 12, letterSpacing: 1.4, color: lilac.dim, textTransform: 'uppercase' },
  sumV: { fontSize: 22, lineHeight: 28, fontWeight: '800', color: lilac.head, marginTop: 3 }, // Oswald — 1.27× (BUG A)
  sumVU: { fontSize: 14, fontWeight: '600', color: lilac.dim },
  sumL: { fontSize: 14, color: lilac.text, marginTop: 2 },

  // 로드 실패 — 빈 화면 대신 실패를 말한다 (둘 다 실패 = 박스 · 한쪽만 실패 = 그 섹션 자리의 한 줄)
  errBox: { marginTop: 14, backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, padding: 13 },
  errT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head },
  errD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 2 },
  failNote: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.inner, paddingVertical: 11, paddingHorizontal: 12 },
  failTxt: { fontSize: 14, lineHeight: 20, color: lilac.text },

  // 섹션 라벨 (마이와 같은 문법 — § · LATIN · 한글 · 룰)
  sec: { alignItems: 'center', gap: 8, marginTop: 18, marginBottom: 9, marginHorizontal: 2 },
  secNo: { fontSize: 12, color: lilac.accent, fontWeight: '600' }, // 글리프 전용(§) — 14pt 플로어 면제
  secT: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  secKo: { fontSize: 14, fontWeight: '700', color: lilac.text },
  microK: { fontSize: 12, letterSpacing: 1.6, color: lilac.dim, textTransform: 'uppercase' }, // 라틴 스트랩 — 신분면 microK 예외 상속

  // § 도장 — 잉크 페이지 (포일 0)
  visa: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow,
  },
  visaInner: { margin: 9, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, padding: 11 },
  visaStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  visaCnt: {
    borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE',
    borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 9,
  },
  visaCntTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 0.8, color: INK, fontWeight: '600' },
  empt: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.inner, padding: 11, marginBottom: 11 },
  emptT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head },
  emptD: { fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 3 },

  // 도장 디스크 — my.tsx §③과 동일 기하, 행간만 한 단계 넉넉하게 (부속서는 수집함이다)
  sgrid: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', columnGap: STAMP_GAP, rowGap: 14 },
  scell: { width: STAMP_CELL_W, minHeight: DISC + 48, alignItems: 'center' },
  disc: { width: DISC, height: DISC, borderRadius: DISC / 2, alignItems: 'center', justifyContent: 'center' },
  discOn: { borderWidth: 2, borderColor: INK, backgroundColor: INK_FILL },
  discCoral: { borderWidth: 2, borderColor: lilac.coralDeep, backgroundColor: INK_FILL },
  discOff: { borderWidth: 1.5, borderStyle: 'dashed', borderColor: lilac.hair },
  ring2: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderRadius: (DISC - 8) / 2, borderWidth: 1.5, borderColor: INK, opacity: 0.85 },
  ring2Top: { opacity: 0.9 },
  ring2Coral: { borderColor: lilac.coralDeep, opacity: 0.34 },
  ring3: { position: 'absolute', top: -5, left: -5, right: -5, bottom: -5, borderRadius: (DISC + 10) / 2, borderWidth: 1.5, borderColor: INK, opacity: 0.55 },
  dot1: { position: 'absolute', top: -3.5, left: (DISC - 7) / 2, width: 7, height: 7, borderRadius: 3.5, backgroundColor: lilac.coralDeep },
  discN: { fontSize: 22, lineHeight: 27, fontWeight: '800', color: INK }, // Oswald — 1.23× (BUG A)
  discW: { fontSize: 14, lineHeight: 17, fontWeight: '800', color: INK, marginTop: 1 },
  discInkOff: { color: lilac.dim },
  scellCond: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.dim, marginTop: 6, textAlign: 'center' },
  scellCondOn: { fontWeight: '700', color: lilac.head },

  // § 코스 패치 — 나이트 라일락 웰
  well: {
    backgroundColor: NIGHT, borderRadius: lilacRadius.card, paddingVertical: 13, paddingHorizontal: 11,
    shadowColor: '#120E2C', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  wellK: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  wellT: { fontSize: 14, fontWeight: '800', color: '#fff' },
  wellC: { fontSize: 14, lineHeight: 18, letterSpacing: 0.6, fontWeight: '600', color: NIGHT_INK }, // 볼트 은퇴 → 나이트 잉크
  wellNote: { fontSize: 14, lineHeight: 19, color: NIGHT_DIM, marginBottom: 12 },
  pgrid: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', columnGap: PATCH_GAP, rowGap: 13 },
  pcell: { width: PATCH_CELL_W, minHeight: BADGE + 62, alignItems: 'center' },
  pName: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: '#fff', marginTop: 7, textAlign: 'center', maxWidth: PATCH_CELL_W },
  pNameOff: { color: 'rgba(255,255,255,0.72)' }, // 9.2:1
  pSub: { fontSize: 14, lineHeight: 18, color: NIGHT_DIM, marginTop: 1, textAlign: 'center' },
  pNext: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: NIGHT_INK, marginTop: 1, textAlign: 'center' },
  pLock: {
    width: BADGE, height: BADGE, borderRadius: BADGE / 2, borderWidth: 2, borderStyle: 'dashed',
    alignItems: 'center', justifyContent: 'center',
  },
  pLockKm: { fontSize: Math.round(BADGE * 0.26), lineHeight: Math.round(BADGE * 0.3), fontWeight: '900' }, // PatchBadge의 km 비율(0.26)과 동일 — 잠긴 칸과 받은 칸의 숫자가 같은 크기로 읽힌다
  pLockWorld: { fontSize: 7.5, lineHeight: 10, fontWeight: '800', letterSpacing: 1.2, marginTop: 1 }, // 레터스페이스 라틴 키커 — 플로어 면제 (PatchBadge 월드 라벨과 같은 급)
});
