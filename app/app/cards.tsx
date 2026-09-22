import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Dimensions, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { PatchBadge, worldOf } from '../src/components/patch';
import { STAMP_GAP, STAMP_INK, StampCell } from '../src/components/stamp';
import { Row } from '../src/components/ui';
import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { CoursePatch, deriveStamps, fetchCoursePatches, fetchStampStats, StampStats } from '../src/lib/api';
import { collectionFace } from '../src/lib/collection-face';
import { lilac, lilacRadius, lilacShadow } from '../src/theme';

// 컬렉션 — 여권의 부속서(ANNEX). 리워드 ② 랩 Ⓑ① 채택.
// [정직 수리 2026-08-05] 목업 카드 6장(myCards) 퇴역 → 실파생 패치 월만 남았고,
// [라일락 리페인트 2026-08-05] 이 화면의 크림/볼트 잔재(테마 컨텍스트 팔레트 · 볼트딥 카운트)를 은퇴시키고
//   여권 문법으로 다시 칠했다: §도장(잉크 페이지) + §코스 패치(나이트 라일락 웰).
// 두 재질은 억지로 하나로 합치지 않는다 — 종이에 찍은 잉크와 자수 배지는 다른 물건이다.

const GRADE_LABEL: Record<string, string> = { basic: '획득', silver: '실버', gold: '골드', master: '마스터' };
const nextGrade = (n: number) => (n < 5 ? `실버까지 ${5 - n}회` : n < 10 ? `골드까지 ${10 - n}회` : n < 25 ? `마스터까지 ${25 - n}회` : '코스 마스터');

// 도장 프리미티브·잉크 법·폭 예산 → src/components/stamp.tsx (2026-08-05 추출 — 정본 한 곳).
const NIGHT = '#1C1837';                  // 패치 웰 바닥 (기록면과 같은 나이트 라일락)
const NIGHT_INK = '#B9AEF5';              // 나이트 위 바이올렛 — 8.45:1
const NIGHT_DIM = '#A9A3C8';              // 나이트 위 보조 — 7.09:1

const W = Dimensions.get('window').width;

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

export default function Cards() {
  const insets = useSafeAreaInsets();
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
  // [honesty 2026-09-22 · loading-state-audit #8 follow-up] The three failure faces on this screen
  // said 「다시 열면 다시 시도해요」 / 「화면을 다시 열어주세요」 — honest about the failure and then
  // handing the person a chore the screen could do itself. The read lived inline in a `[]` effect,
  // so there was nothing a button could call; that absence is what wrote the copy. One loader per
  // READ, so 도장's 다시 시도 re-runs `fetchStampStats` alone and 패치's re-runs `fetchCoursePatches`
  // alone — a retry that re-fires the healthy sibling would spend a call to prove nothing.
  // ⚠ Setters run on success only, so a failed retry keeps whatever had already arrived: the strip
  // says the READ failed, never that the collection is empty.
  const loadStamps = useCallback(() => {
    setStampErr(false);
    fetchStampStats().then(setStampStats).catch((e) => { setStampErr(true); console.warn('[cards] stamps:', e?.message ?? e); });
  }, []);
  const loadPatches = useCallback(() => {
    setPatchErr(false);
    fetchCoursePatches().then(setPatches).catch((e) => { setPatchErr(true); console.warn('[cards] patches:', e?.message ?? e); });
  }, []);
  useEffect(() => { loadPatches(); loadStamps(); }, [loadPatches, loadStamps]);

  const patchTotal = patches ? patches.earned.length + patches.locked.length : 0;
  const bothFailed = stampErr && patchErr && !stamps && !patches;

  // [honesty 2026-09-22] 섹션마다 얼굴은 하나 — 그리고 **아무 얼굴도 아닌 상태는 없다.**
  // 측정: 로그아웃 상태의 /cards에 § 코스 패치가 통째로 없었다(헤더도 실패도 빈 상태도 아닌 無).
  // 원인은 RLS도 에러도 아니다 — `fetchCoursePatches`는 세션이 없으면 `{ earned: [], locked: [] }`를
  // 던지지 않고 **성공적으로** 돌려준다(api.ts). 그래서 patches는 non-null, patchErr는 false,
  // patchTotal은 0이 되고, 예전 게이트 `patches && patchTotal > 0`에서 모든 가지가 동시에 거짓이 됐다.
  // (형제인 `fetchStampStats`는 같은 상황에서 throw하므로 § 도장만 실패 얼굴을 썼다 — 한 화면에서
  //  두 읽기가 로그아웃을 다르게 취급하는 것이 증상의 비대칭을 만들었다.)
  // 🔴 빈 컬렉션은 신규 사용자의 기본 상태다. 화면이 가장 말해야 할 상태에서 침묵하고 있었고,
  // 아무것도 안 그리는 섹션은 존재하지 않는 섹션과 구별되지 않는다. 다섯 얼굴을 이름으로 열거해
  // 「어느 가지도 안 맞음」이 값이 되게 한다 — 순수 함수라 test/collection-face.test.cjs가 전 입력을 돈다.
  const stampFace = collectionFace({ loaded: !!stamps, count: stamps ? stamps.length : 0, failed: stampErr, bothFailed });
  const patchFace = collectionFace({ loaded: !!patches, count: patchTotal, failed: patchErr, bothFailed });

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: insets.top, paddingBottom: 30 }}>

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
        {(stampFace === 'list' || patchFace === 'list') && (
          <Row style={s.sum}>
            {stampFace === 'list' && stamps && (
              <View style={s.sumC}>
                <Text style={[s.sumK, nf]}>STAMPS</Text>
                <Text style={[s.sumV, nf]}>{stampsEarned}<Text style={s.sumVU}> / {stamps.length}</Text></Text>
                <Text style={s.sumL}>받은 도장</Text>
              </View>
            )}
            {patchFace === 'list' && patches && (
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
            <Text style={s.errD}>네트워크를 확인하고 다시 시도해주세요</Text>
            {/* Both reads died, so this one button re-runs both — the only place on this screen
                where a retry may fire two calls, because here both of them are the failed ones. */}
            <Pressable
              onPress={() => { loadStamps(); loadPatches(); }}
              style={s.retryBtn}
              accessibilityRole="button"
              accessibilityLabel="수집함 다시 불러오기"
            >
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ————— § 도장 — 잉크 페이지 (my.tsx §③과 같은 칸, 조금 더 넉넉한 행간) —————
            [honesty 2026-09-17] 로딩 문장 추가. 두 읽기가 다 도착 전이면 이 화면은 마스트헤드
            아래가 통째로 백지였다 — 아무 섹션 조건도 참이 아니라서. 빈 수집함과 구별되지 않는
            얼굴이다. 실패 노트와 같은 문법·같은 자리에 두어, 섹션마다 로딩·실패·실값이 갈린다. */}
        {stampFace === 'loading' && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>STAMPS</Text>
              <Text style={s.secKo}>도장</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}><Text style={s.loadTxt}>도장을 불러오는 중...</Text></View>
          </>
        )}
        {stampFace === 'failed' && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>STAMPS</Text>
              <Text style={s.secKo}>도장</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}>
              <Text style={s.failTxt}>도장을 불러오지 못했어요</Text>
              <Pressable onPress={loadStamps} style={s.retryBtn} accessibilityRole="button" accessibilityLabel="도장 다시 불러오기">
                <Text style={s.retryTxt}>다시 시도</Text>
              </Pressable>
            </View>
          </>
        )}
        {/* 도장은 `deriveStamps`가 항상 12칸을 돌려주므로 'empty' 얼굴에 도달하지 않는다 — 빈 도장면은
            섹션의 부재가 아니라 칸 안의 '아직 비어 있어요' 문장으로 말한다(아래 stampsEarned === 0). */}
        {stampFace === 'list' && stamps && (
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
        {patchFace === 'loading' && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>PATCHES</Text>
              <Text style={s.secKo}>코스 패치</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}><Text style={s.loadTxt}>코스 패치를 불러오는 중...</Text></View>
          </>
        )}
        {patchFace === 'failed' && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>PATCHES</Text>
              <Text style={s.secKo}>코스 패치</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.failNote}>
              <Text style={s.failTxt}>코스 패치를 불러오지 못했어요</Text>
              <Pressable onPress={loadPatches} style={s.retryBtn} accessibilityRole="button" accessibilityLabel="코스 패치 다시 불러오기">
                <Text style={s.retryTxt}>다시 시도</Text>
              </Pressable>
            </View>
          </>
        )}
        {/* 🔴 읽기는 성공했는데 아무것도 없는 상태 — 이 화면에서 통째로 빠져 있던 얼굴.
            로그아웃(`fetchCoursePatches`가 빈 배열을 **성공으로** 돌려준다) 또는 활성 코스가 하나도
            없을 때 여기로 온다. 웰(나이트 바닥)이 아니라 페이지 바닥의 inset 박스인 이유: 잠긴 패치가
            0개면 웰 안에 그릴 자수가 없고, 빈 웰은 '로딩 중'과 구별되지 않는다. §도장의 빈 상태와 같은
            문법·같은 재질이다. 영속성('영구')은 약속하지 않는다 — 코스 비활성화가 실제 감소 벡터다. */}
        {patchFace === 'empty' && (
          <>
            <Row style={s.sec}>
              <Text style={[s.secNo, nf]}>§</Text>
              <Text style={[s.secT, nf]}>PATCHES</Text>
              <Text style={s.secKo}>코스 패치</Text>
              <View style={s.rule} />
            </Row>
            <View style={s.empt}>
              <Text style={s.emptT}>아직 모은 코스 패치가 없어요</Text>
              <Text style={s.emptD}>코스를 완주하면 그 코스의 패치가 여기에 남아요.</Text>
            </View>
          </>
        )}
        {patchFace === 'list' && patches && (
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
  cbarLabel: { fontSize: 15, fontWeight: '700', color: lilac.head },
  kicker: { alignItems: 'center', gap: 8, marginTop: 4, marginBottom: 8 },
  kickerTxt: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  // [§3c 화면 타이틀 2026-08-11] 40 → 30. 탭은 아니지만 마이에서 한 탭 거리라, 여기만 40으로
  // 남기면 통일 직후에 같은 불일치가 다시 보인다. 색은 이 화면의 월드(라일락) 유지.
  h1: { fontSize: 30, fontWeight: '900', color: lilac.head, lineHeight: 37 },
  official: {
    marginTop: 6, borderWidth: 1, borderColor: lilac.head, borderRadius: 2,
    paddingVertical: 5, paddingHorizontal: 8, backgroundColor: lilac.card,
  },
  officialTxt: { fontSize: 11.5, letterSpacing: 1.8, color: lilac.head, fontWeight: '600' },
  subNote: { fontSize: 15, lineHeight: 21, color: lilac.text, marginTop: 9 },

  // 요약 스트립
  sum: {
    alignItems: 'stretch', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 12, ...lilacShadow,
  },
  sumC: { flex: 1, paddingVertical: 11, paddingHorizontal: 12 },
  sumDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2 },
  sumK: { fontSize: 12, letterSpacing: 1.4, color: lilac.dim, textTransform: 'uppercase' },
  sumV: { fontSize: 22, lineHeight: 28, fontWeight: '800', color: lilac.head, marginTop: 3 }, // Oswald — 1.27× (BUG A)
  sumVU: { fontSize: 15, fontWeight: '600', color: lilac.dim },
  sumL: { fontSize: 15, color: lilac.text, marginTop: 2 },

  // 로드 실패 — 빈 화면 대신 실패를 말한다 (둘 다 실패 = 박스 · 한쪽만 실패 = 그 섹션 자리의 한 줄)
  errBox: { marginTop: 14, backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, padding: 13 },
  errT: { fontSize: 16, lineHeight: 20, fontWeight: '700', color: lilac.head },
  errD: { fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 2 },
  failNote: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.inner, paddingVertical: 11, paddingHorizontal: 12 },
  failTxt: { fontSize: 15, lineHeight: 20, color: lilac.text },
  // Retry — alerts.tsx:317's lilac-world grammar (bordered white box, head ink, 다시 시도) rather
  // than the paper world's underlined text, because this screen is the passport ANNEX and its
  // chrome is lilac. ⚠ 44 and not that neighbour's 40: HIG G1 is a 44pt minimum hit region, and a
  // bordered box has no hitSlop to make up the difference.
  retryBtn: {
    alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center',
    paddingHorizontal: 14, borderWidth: 1, borderColor: lilac.head,
    borderRadius: lilacRadius.btn, backgroundColor: '#fff',
  },
  retryTxt: { fontSize: 16, fontWeight: '800', color: lilac.head },
  // 로딩 문장 — 실패 노트와 같은 상자, 더 조용한 잉크 (실패가 아니라 아직인 것)
  loadTxt: { fontSize: 15, lineHeight: 20, color: lilac.dim },

  // 섹션 라벨 (마이와 같은 문법 — § · LATIN · 한글 · 룰)
  sec: { alignItems: 'center', gap: 8, marginTop: 18, marginBottom: 9, marginHorizontal: 2 },
  secNo: { fontSize: 12, color: lilac.accent, fontWeight: '600' }, // 글리프 전용(§) — 15pt 플로어 면제
  secT: { fontSize: 12, letterSpacing: 2, color: lilac.dim, textTransform: 'uppercase' },
  secKo: { fontSize: 15, fontWeight: '700', color: lilac.text },
  microK: { fontSize: 15, letterSpacing: 1.6, color: lilac.dim, textTransform: 'uppercase' }, // [FLOOR15] 'MILESTONE / 마일스톤' — 라틴 스트랩이 아니라 한글을 싣는다. 12 → 15 (§3: 한글은 키커 예외를 타지 못한다).

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
  visaCntTxt: { fontSize: 15, lineHeight: 18, letterSpacing: 0.8, color: STAMP_INK, fontWeight: '600' },
  empt: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.inner, padding: 11, marginBottom: 11 },
  emptT: { fontSize: 16, lineHeight: 20, fontWeight: '700', color: lilac.head },
  emptD: { fontSize: 15, lineHeight: 20, color: lilac.text, marginTop: 3 },

  // 도장 디스크 — my.tsx §③과 동일 기하, 행간만 한 단계 넉넉하게 (부속서는 수집함이다)
  sgrid: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', columnGap: STAMP_GAP, rowGap: 14 },

  // § 코스 패치 — 나이트 라일락 웰
  well: {
    backgroundColor: NIGHT, borderRadius: lilacRadius.card, paddingVertical: 13, paddingHorizontal: 11,
    shadowColor: '#120E2C', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  wellK: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  wellT: { fontSize: 16, fontWeight: '800', color: '#fff' },
  wellC: { fontSize: 15, lineHeight: 18, letterSpacing: 0.6, fontWeight: '600', color: NIGHT_INK }, // 볼트 은퇴 → 나이트 잉크
  wellNote: { fontSize: 15, lineHeight: 19, color: NIGHT_DIM, marginBottom: 12 },
  pgrid: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', columnGap: PATCH_GAP, rowGap: 13 },
  pcell: { width: PATCH_CELL_W, minHeight: BADGE + 62, alignItems: 'center' },
  pName: { fontSize: 15, lineHeight: 18, fontWeight: '700', color: '#fff', marginTop: 7, textAlign: 'center', maxWidth: PATCH_CELL_W },
  pNameOff: { color: 'rgba(255,255,255,0.72)' }, // 9.2:1
  pSub: { fontSize: 15, lineHeight: 18, color: NIGHT_DIM, marginTop: 1, textAlign: 'center' },
  pNext: { fontSize: 15, lineHeight: 18, fontWeight: '700', color: NIGHT_INK, marginTop: 1, textAlign: 'center' },
  pLock: {
    width: BADGE, height: BADGE, borderRadius: BADGE / 2, borderWidth: 2, borderStyle: 'dashed',
    alignItems: 'center', justifyContent: 'center',
  },
  pLockKm: { fontSize: Math.round(BADGE * 0.26), lineHeight: Math.round(BADGE * 0.3), fontWeight: '900' }, // PatchBadge의 km 비율(0.26)과 동일 — 잠긴 칸과 받은 칸의 숫자가 같은 크기로 읽힌다
  pLockWorld: { fontSize: 7.5, lineHeight: 10, fontWeight: '800', letterSpacing: 1.2, marginTop: 1 }, // 레터스페이스 라틴 키커 — 플로어 면제 (PatchBadge 월드 라벨과 같은 급)
});
