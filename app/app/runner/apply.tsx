import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { fetchMyRunnerCert, MyRunnerCert } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { lilac, lilacRadius, lilacShadow } from '../../src/theme';

// 러너 인증 센터 — [정직 수리 2026-08-05] 목업 퍼널 철거 + 테일러드 라일락 리페인트.
// 이전: store.ts의 applyStatus(하드코딩 '인증 러너'·'베테랑까지 36회'·done/active 체크마크 5단계)를
//   '내 인증 진행 상황'으로 그렸다. 서버엔 그 진행을 담는 것이 없다 — 전부 지어낸 개인 이력이었다.
// 지금: 이 화면이 말하는 사실은 셋뿐이다.
//   ① 서버 러너 레코드(등급·누적 완주·누적 거리·정산 수수료율) — runners 실컬럼 그대로.
//   ② 인증 절차의 '구성' — 개인 체크마크가 아니라 절차가 무엇인지에 대한 설명.
//   ③ 개인 단계 추적은 준비 중 — 앱이 아직 기록하지 않는다는 사실을 그대로 말한다.
// funnel_step·identity_verified·education_modules_done은 컬럼이 있어도 그리지 않는다:
//   현재 값의 출처가 ensureRunner()의 루프 테스트 부트스트랩이라, 통과한 적 없는 심사를 통과로 보이게 한다.
// 실 퍼널 설계는 docs/specs/runner-cert-funnel-spec.md — 다음 세션의 마이그레이션 사이클이 세운다.

const TIER_LABEL: Record<string, string> = {
  applicant: '지원자', certified: '인증 러너', veteran: '베테랑', master: '마스터',
};

// 절차의 '구성' — 개인 진행이 아니다. 각 단계가 무엇을 하는지의 설명만 담는다.
const STEPS: { no: string; label: string; desc: string }[] = [
  { no: '01', label: '기본 정보', desc: '활동 지역 · 평균 페이스 · 감당 가능한 견종 크기를 등록하는 단계예요' },
  { no: '02', label: '신원 확인', desc: '본인인증과 신분 서류로 러너가 누구인지 확인하는 단계예요' },
  { no: '03', label: '안전 교육', desc: '리드 통제 · 더위와 추위 대응 · 응급 상황 대처를 익히는 단계예요' },
  { no: '04', label: '시범 러닝', desc: '실제 러닝 한 번을 함께 뛰며 현장에서 확인하는 단계예요' },
  { no: '05', label: '인증 완료', desc: '등급이 인증 러너가 되고 요청을 받기 시작하는 단계예요' },
];

export default function Apply() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀 1회
  const nf = useNumFont();     // Oswald — 숫자·대문자 키커 (lineHeight 명시 필수, BUG A)
  // null = 러너 레코드 없음. loaded 플래그가 따로 있는 이유: 미도착과 '없음'은 다른 사실이고,
  // 둘 중 어느 쪽도 0으로 그리지 않는다.
  const [cert, setCert] = useState<MyRunnerCert | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    fetchMyRunnerCert()
      .then((c) => { setCert(c); setLoaded(true); })
      .catch((e) => { setErr(e?.message ?? '러너 정보를 불러오지 못했어요'); setLoaded(true); });
  }, []);

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 14, paddingTop: 58, paddingBottom: 40 }}>

        {/* ————— 마스트헤드 ————— */}
        <Row style={{ gap: 10 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: -2 }}>‹</Text>
          </Pressable>
          <View style={s.rule} />
          <Text style={[s.kick, nf]}>RUNNER · CERTIFICATION</Text>
        </Row>
        <Text style={[s.h1, df]}>인증 센터</Text>
        <Text style={s.lede}>
          검증된 러너만 아이들을 만나요{'\n'}지금 이 화면이 말할 수 있는 건 서버에 남은 기록과 절차의 구성이에요
        </Text>

        {/* ————— ① 내 러너 레코드 — 서버 진실 ————— */}
        <SecRule no="§" en="RECORD" ko="내 러너 레코드" />
        {!loaded && (
          <View style={s.plain}><Text style={s.plainTxt}>러너 레코드를 불러오는 중이에요…</Text></View>
        )}
        {loaded && err !== null && (
          <View style={s.errBox}>
            <View style={s.errTick} />
            <View style={{ flex: 1 }}>
              <Text style={s.errT}>러너 레코드를 불러오지 못했어요</Text>
              <Text style={s.errD}>{err}</Text>
            </View>
          </View>
        )}
        {loaded && err === null && cert === null && (
          <View style={s.plain}>
            <Text style={s.plainT}>아직 러너로 등록되어 있지 않아요</Text>
            <Text style={s.plainTxt}>
              러너 레코드가 만들어져야 등급과 누적 기록이 생겨요{'\n'}러너 모드로 한 번 들어오면 레코드가 만들어져요
            </Text>
          </View>
        )}
        {loaded && err === null && cert !== null && (
          <View style={s.rec}>
            <View style={s.recInner}>
              <Row style={s.recStrap}>
                <Text style={[s.micro, nf]}>SERVER RECORD</Text>
                <View style={s.srcTag}><Text style={[s.srcTagTxt, nf]}>RUNNERS</Text></View>
              </Row>

              <Text style={s.recK}>현재 등급</Text>
              <Text style={s.recTier}>{TIER_LABEL[cert.tier] ?? cert.tier}</Text>
              <Text style={s.recNote}>
                {cert.tier === 'applicant'
                  ? '지원자 등급은 아직 요청을 받을 수 없어요 — 인증이 끝나야 매칭에 올라가요'
                  : '요청을 받을 수 있는 등급이에요 — 지명 목록과 오픈 요청에 올라가요'}
              </Text>

              <Row style={s.grid}>
                {/* 단위는 숫자 Text 밖의 형제로 둔다 — Oswald(라틴 전용) 안에 한글을 넣지 않는다 */}
                <View style={s.cell}>
                  <Text style={s.cellK}>완주</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{cert.totalRuns.toLocaleString()}</Text>
                    <Text style={s.cellU}>회</Text>
                  </Row>
                </View>
                <View style={[s.cell, s.cellDiv]}>
                  <Text style={s.cellK}>누적 거리</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{cert.totalKm.toFixed(1)}</Text>
                    <Text style={s.cellU}>km</Text>
                  </Row>
                </View>
                <View style={[s.cell, s.cellDiv]}>
                  <Text style={s.cellK}>정산 수수료</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{Math.round(cert.commissionRate * 100)}</Text>
                    <Text style={s.cellU}>%</Text>
                  </Row>
                </View>
              </Row>
            </View>
            <Text style={s.recFoot}>
              네 값 모두 서버 러너 레코드에서 그대로 읽어요 — 완주와 거리는 정산이 올리고, 수수료율은 정산에 그대로 쓰여요
            </Text>
          </View>
        )}

        {/* ————— ② 인증 절차의 구성 — 개인 체크마크 아님 ————— */}
        <SecRule no="§" en="PROCESS" ko="인증 절차는 이렇게 구성돼요" />
        <View style={s.stepCard}>
          <Text style={s.stepLede}>아래는 절차가 무엇인지에 대한 설명이에요 — 내가 어디까지 왔는지를 표시하는 목록이 아니에요</Text>
          {STEPS.map((st, i) => (
            <View key={st.no} style={[s.step, i > 0 && s.stepDiv]}>
              <Text style={[s.stepNo, nf]}>{st.no}</Text>
              <View style={{ flex: 1 }}>
                <Text style={s.stepT}>{st.label}</Text>
                <Text style={s.stepD}>{st.desc}</Text>
              </View>
            </View>
          ))}
        </View>

        {/* ————— ③ 개인 진행 추적 — 준비 중 (없는 것을 없다고 말한다) ————— */}
        <SecRule no="§" en="PROGRESS" ko="내 진행 상황" />
        <View style={s.soon}>
          <Row style={{ gap: 8, alignItems: 'center' }}>
            <View style={s.soonDot} />
            <Text style={s.soonT}>단계별 진행 표시는 준비 중이에요</Text>
          </Row>
          <Text style={s.soonD}>
            앱은 아직 러너 한 명 한 명이 어느 단계에 있는지를 기록하지 않아요.{'\n'}
            그래서 이 화면은 완료 표시나 남은 단계를 그리지 않아요 — 없는 기록을 그리는 대신 준비 중이라고 말해요.{'\n'}
            파일럿 기간에는 인증 절차를 운영팀과 직접 진행해요.
          </Text>
          <Pressable
            onPress={() => router.push('/settings')}
            style={s.cta}
            accessibilityRole="button"
            accessibilityLabel="설정 화면의 문의하기로 이동"
          >
            <View style={{ flex: 1 }}>
              <Text style={s.ctaT}>인증 절차 문의하기</Text>
              <Text style={s.ctaD}>설정 › 문의하기로 이동해요</Text>
            </View>
            <Text style={s.ctaGo}>›</Text>
          </Pressable>
        </View>

        <View style={s.colophon}>
          <Text style={[s.colophonTxt, nf]}>DOGS HIGH · RUNNER CERTIFICATION</Text>
        </View>
      </ScrollView>
    </View>
  );
}

// 섹션 룰 — § 글리프(12pt 면제) + 대문자 키커 + 헤어라인 + 한글 라벨
function SecRule({ no, en, ko }: { no: string; en: string; ko: string }) {
  const nf = useNumFont();
  return (
    <Row style={s.sec}>
      <Text style={s.secNo}>{no}</Text>
      <Text style={[s.secT, nf]}>{en}</Text>
      <View style={s.rule} />
      <Text style={s.secKo}>{ko}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  // ── 마스트헤드 ──
  backBtn: {
    width: 34, height: 34, borderRadius: 10, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  kick: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33× (BUG A)
  h1: { fontSize: 36, lineHeight: 44, fontWeight: '900', color: lilac.head, marginTop: 10 },
  lede: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 8 },

  // ── 섹션 룰 ──
  sec: { alignItems: 'center', gap: 8, marginTop: 20, marginBottom: 9 },
  secNo: { fontSize: 12, fontWeight: '600', color: lilac.accent }, // 글리프 전용(§) — 14pt 플로어 면제
  secT: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33×
  secKo: { fontSize: 14, fontWeight: '700', color: lilac.text },

  // ── ① 러너 레코드 ──
  rec: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow,
  },
  recInner: { margin: 9, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, padding: 13 },
  recStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 },
  micro: { fontSize: 12, lineHeight: 16, letterSpacing: 1.6, color: lilac.dim }, // Oswald 1.33×
  srcTag: {
    borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE',
    borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 8,
  },
  srcTagTxt: { fontSize: 12, lineHeight: 16, letterSpacing: 1, color: lilac.accent }, // Oswald 1.33×
  recK: { fontSize: 14, color: lilac.dim },
  recTier: { fontSize: 28, lineHeight: 34, fontWeight: '900', color: lilac.head, marginTop: 3 },
  recNote: { fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 6 },
  grid: { alignItems: 'stretch', marginTop: 13, marginHorizontal: -13, borderTopWidth: 1, borderTopColor: lilac.hair2 },
  cell: { flex: 1, paddingTop: 10, paddingBottom: 2, paddingLeft: 13 },
  cellDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2 },
  cellK: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginBottom: 2 }, // 한글 라벨 — 14pt 플로어 준수
  cellVal: { alignItems: 'baseline', gap: 3 },
  cellV: { fontSize: 22, lineHeight: 28, color: lilac.head }, // Oswald 1.27× (BUG A)
  cellU: { fontSize: 14, lineHeight: 18, color: lilac.dim },
  recFoot: { fontSize: 14, lineHeight: 20, color: lilac.dim, paddingHorizontal: 13, paddingBottom: 12, paddingTop: 2 },

  // ── 로딩 · 빈 상태 ──
  plain: {
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 14,
  },
  plainT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head, marginBottom: 3 },
  plainTxt: { fontSize: 14, lineHeight: 20, color: lilac.text },

  // ── 실패는 실패로 ──
  errBox: {
    flexDirection: 'row', alignItems: 'flex-start', gap: 10,
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 13,
  },
  errTick: { width: 3, alignSelf: 'stretch', borderRadius: 2, backgroundColor: lilac.coralDeep },
  errT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head },
  errD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 2 },

  // ── ② 절차 ──
  stepCard: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, paddingHorizontal: 13, paddingBottom: 4, ...lilacShadow,
  },
  stepLede: { fontSize: 14, lineHeight: 20, color: lilac.dim, paddingTop: 13, paddingBottom: 3 },
  step: { flexDirection: 'row', alignItems: 'flex-start', gap: 11, paddingVertical: 12 },
  stepDiv: { borderTopWidth: 1, borderTopColor: lilac.hair2 },
  stepNo: { fontSize: 14, lineHeight: 20, letterSpacing: 0.8, color: lilac.accent, width: 22 }, // Oswald 1.43×
  stepT: { fontSize: 15, fontWeight: '800', color: lilac.head },
  stepD: { fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 2 },

  // ── ③ 준비 중 ──
  soon: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 14, ...lilacShadow,
  },
  soonDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.amber },
  soonT: { fontSize: 15, fontWeight: '800', color: lilac.head },
  soonD: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 8 },
  cta: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 13,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.btn, paddingVertical: 12, paddingHorizontal: 12,
  },
  ctaT: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: lilac.head },
  ctaD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 1 },
  ctaGo: { fontSize: 17, color: lilac.accent },

  // ── 콜로폰 ──
  colophon: { marginTop: 20, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair, alignItems: 'center' },
  colophonTxt: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33×
});
