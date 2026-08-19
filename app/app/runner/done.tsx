import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Dimensions, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { HeatTrace } from '../../src/components/runcard';
import { Icon, Row } from '../../src/components/ui';
import { DropRow, fetchDrops, fetchMeetupInfo, fetchRunTrace, uploadRunPhoto } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { MediaImage } from '../../src/lib/media';
import { GeoRoutePoint, traceToBox } from '../../src/lib/trace';
import { runResult } from '../../src/store';
import { colors, layout, paper } from '../../src/theme';

// 러닝 완료 — the completion Peak (§7b Peak-End: exempt from minimization).
//
// [journey v4 · R7a 2026-08-19] The dark 50.5pt volt '오늘의 수익' receipt is RETIRED. It made the
// money the biggest object on the screen that exists to record a RUN, and it printed a client
// estimate at hero size whenever settle had failed. The lab's law: the amount is a plain row, never
// large; what goes large is **km**. So the hierarchy is now trace → display headline ("초코,
// 5.12km 완주") → the run's three numbers (Oswald) → one money row → the honesty sentence.
// The settled/unsettled split survives intact and is the whole point of the row's label: the spec
// word 적립 예정 is spoken only when the server confirmed the number; an unsettled run keeps the
// code's own '예상 수익 (정산 미완료)' verbatim and its explanation is drawn as a loud-fail strip
// (criticalWash + critical ink), because an unsettled run is a real failure with a real next step.
//
// The trace thumbnail is REAL: `runs.trace`, which run.tsx writes with saveRunTrace *before*
// settle (settle_run_tx closes the write window), read back here through fetchRunTrace under the
// "runs party read" policy. Three states — loading / failed / drawn — and nothing at all when
// there is no booking to read. Event counts (응가·물·스냅) the lab also asks for are NOT available
// on this screen: they live in run.tsx's local state and `runResult` (src/store.ts) does not carry
// them. Omitted rather than invented.
//
// Behavior frozen: fetchDrops/addPhoto/uploadRunPhoto, photo cap 6, the dogName re-read, all routes.

const W = Dimensions.get('window').width;
const TRACE_W = W - layout.gutter * 2;
const TRACE_H = 96;

// M:SS — same grammar as the report card's run numbers (owner/report.tsx fmtDur). The old
// '28분 40초' form was for a caption; inside an Oswald numeral row Korean units break the baseline.
const fmtDur = (sec: number) =>
  `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
// Average pace from the two measured values, using run.tsx's paceStr formula verbatim so the
// last number the runner saw live and the one printed here cannot disagree.
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

// Real dog name — settle put it on runResult from the booking context; if that never loaded, the
// screen re-reads the settled booking once. If the name is genuinely unknown (or the server's own
// generic '반려견' placeholder), the copy names no dog — never a fake one.
// Pure, so it lives at module scope (react-doctor prefer-module-scope-pure-function).
const realName = (n: string | null | undefined) => (n && n !== '반려견' ? n : null);

export default function RunDone() {
  const df = useDisplayFont(); // display font — the run headline (1/screen budget)
  const nf = useNumFont();     // Oswald — the three run numbers + the payout
  const [dogName, setDogName] = useState<string | null>(() => realName(runResult.dogName));
  useEffect(() => {
    if (!realName(runResult.dogName) && runResult.bookingId) {
      fetchMeetupInfo(runResult.bookingId)
        .then((i) => setDogName(realName(i.dogName)))
        .catch((e) => console.warn('[done] dogName:', (e as Error)?.message)); // unknown → generic wording stays
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 실측 경로 — runs.trace. Three states, and none of them is a drawn placeholder: a failed read
  // says it failed, an in-flight read says so, and a run with no stored points draws no plate.
  const [trace, setTrace] = useState<GeoRoutePoint[] | null>(null);
  const [traceErr, setTraceErr] = useState(false);
  const [traceLoading, setTraceLoading] = useState(!!runResult.bookingId);
  useEffect(() => {
    const bid = runResult.bookingId;
    if (!bid) return;
    fetchRunTrace(bid)
      .then(setTrace)
      .catch((e) => { setTraceErr(true); console.warn('[done] trace:', (e as Error)?.message); })
      .finally(() => setTraceLoading(false));
  }, []);
  const traceBox = trace ? traceToBox(trace) : [];

  // 실드랍 — settle-run이 굴린 결과를 DB에서 읽는다 (목업 215회 은퇴, fake-inventory)
  const [pendingDrop, setPendingDrop] = useState<DropRow | null>(null);
  useEffect(() => {
    fetchDrops().then((ds) => setPendingDrop(ds.find((d) => !d.openedAt) ?? null)).catch(() => {});
  }, []);
  const [photos, setPhotos] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);

  // 오늘의 순간 — 러닝 사진이 보호자 리포트(공유 페이지)에 실린다
  const addPhoto = async () => {
    if (!runResult.bookingId) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      const next = await uploadRunPhoto(runResult.bookingId, res.assets[0].base64);
      setPhotos(next);
    } catch (e) {
      Alert.alert('업로드 실패', (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  const km = runResult.km;
  // '완주' is a claim — spoken only when the server-recorded end was a completed run, exactly as
  // owner/report.tsx gates the same word on run.endReason.
  const headline = dogName
    ? `${dogName}, ${km.toFixed(2)}km${runResult.completed ? ' 완주' : ''}`
    : `${km.toFixed(2)}km${runResult.completed ? ' 완주' : ''}`;

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 70, paddingBottom: 40 }}
    >
      {/* ══════ ① 실측 경로 — dark plate (HeatTrace is built for a dark face) ══════ */}
      {traceLoading && (
        <View style={s.tracePlate}>
          <Text style={s.traceNote}>경로 불러오는 중...</Text>
        </View>
      )}
      {!traceLoading && traceErr && (
        <View style={s.tracePlate}>
          <Text style={s.traceNote}>경로를 불러오지 못했어요 — 기록 자체는 저장돼 있어요</Text>
        </View>
      )}
      {!traceLoading && !traceErr && traceBox.length > 1 && (
        <View style={s.tracePlate}>
          <HeatTrace points={traceBox} width={TRACE_W} height={TRACE_H} tint={colors.volt} />
          <Text style={s.traceCap}>내 실측 경로</Text>
        </View>
      )}

      {/* ══════ ② 헤드라인 + ③ 숫자 셋 (14a 문법) ══════ */}
      <Text style={[s.headline, df]}>{headline}</Text>
      {/* R6 (반환 봉인) does not exist on the client — this sentence is the only place the app
          tells the runner to hand the dog back. It stays until that server slice ships. */}
      <Text style={s.sub}>
        {dogName ? `${dogName}를 보호자에게 안전하게 인계해 주세요` : '반려견을 보호자에게 안전하게 인계해 주세요'}
      </Text>
      <Row style={{ gap: 22, marginTop: 14, alignItems: 'flex-start' }}>
        <DoneStat nf={nf} value={km.toFixed(2)} unit="km" label="거리" />
        <DoneStat nf={nf} value={fmtDur(runResult.sec)} label="러닝 시간" />
        <DoneStat nf={nf} value={paceStr(runResult.sec, km)} label="평균 페이스 /km" />
      </Row>

      {/* ══════ ④ 돈 — 한 줄. 절대 히어로가 아니다 ══════
          [2026-08-11, kept] 정산 성공 여부가 이 낱말을 정한다. 서버가 확정한 금액만 '적립'이고,
          정산이 실패해 러너가 '나중에 (추정치 표시)'를 고른 경우는 클라이언트 추정치다 —
          그걸 확정된 돈이라 부르는 순간 앱이 못 지킬 돈을 약속한 것이 된다. */}
      <View style={s.rule} />
      <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
        <Text style={s.moneyLabel}>{runResult.settled ? '적립 예정' : '예상 수익 (정산 미완료)'}</Text>
        <Row style={{ alignItems: 'baseline' }}>
          {/* Oswald — [BUG A] lineHeight 24 = 1.26× */}
          <Text style={[s.moneyNum, nf]}>{runResult.payout.toLocaleString()}</Text>
          <Text style={s.moneyUnit}>원</Text>
        </Row>
      </Row>
      {/* [2026-08-11, kept] '수익은 매주 수요일 정산됩니다'는 존재하지 않는 지급 운영이었다.
          기록은 진짜다(ledger_items). 지급 일정은 진짜가 아니었다. 아는 것만 말한다. */}
      <Text style={s.moneyNote}>
        {runResult.settled
          ? '정산 기록이 저장됐어요 — 수익 화면에서 누적을 볼 수 있어요 · 지급 일정은 결제 연동 후 안내드려요'
          : '정산이 확정되면 수익 화면에 반영돼요'}
      </Text>

      {/* 정산 미완료 = 진짜 실패. 라우드-페일 스트립 문법(criticalWash + critical) — 이 화면의
          앰버 장식이 아니라 earnings.tsx가 이미 쓰는 실패의 얼굴이다. 재시도 문은 러닝
          화면에 있고(여기엔 없다), 문장이 그 경로를 가리킨다 — 죽은 버튼을 만들지 않는다. */}
      {!runResult.settled && (
        <View style={s.failStrip}>
          <Text style={s.failText}>
            정산이 아직 서버에 반영되지 않았어요 — 이 숫자는 앱이 계산한 추정치예요.{'\n'}
            예약은 진행 중으로 남아 있어요. 러닝 화면에서 다시 정산하면 실제 금액으로 확정돼요.
          </Text>
        </View>
      )}

      {/* 조기 종료 사유 — 사실이지 경고가 아니다. 문장은 그대로, 색만 읽는 잉크로. */}
      {!runResult.completed && (
        <Text style={s.reasonLine}>
          {runResult.reason === 'dog' && '컨디션 종료 — 실제 거리 정산 · 완주율 무영향\n상태 사진과 메모가 보호자에게 전달돼요'}
          {runResult.reason === 'owner' && '보호자 요청 종료 — 실제 거리 + 잔여 거리 50% 보장 포함'}
          {runResult.reason === 'runner' && '개인 사유 종료 — 실제 거리 정산 · 완주율에 반영돼요'}
          {!runResult.reason && '조기 종료 — 실제 뛴 거리만큼 정산됩니다'}
        </Text>
      )}

      {/* ══════ ⑤ 오늘의 순간 — 사진이 보호자의 러닝 리포트에 실려요 (실예약만) ══════ */}
      {runResult.bookingId && (
        <>
          <View style={s.rule} />
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={s.secTitle}>오늘의 순간</Text>
            {photos.length < 6 ? (
              <Pressable
                onPress={addPhoto}
                disabled={uploading}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="사진 추가"
                accessibilityState={{ disabled: uploading, busy: uploading }}
              >
                <Text style={[s.secAction, uploading && { color: paper.dim }]}>
                  {uploading ? '올리는 중…' : '사진 추가 ›'}
                </Text>
              </Pressable>
            ) : (
              /* 상한에 닿으면 문을 남기지 않는다 — 눌러도 아무 일 없는 버튼 대신 사실 한 줄 */
              <Text style={s.secQuiet}>6장까지</Text>
            )}
          </Row>
          <Text style={s.secQuiet}>보호자 리포트에 실려요</Text>
          {photos.length > 0 && (
            <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
              {photos.map((url) => (
                /* [0064] uploadRunPhoto가 media 경로를 돌려준다 — 서명 URL로 렌더 */
                <MediaImage key={url} source={url} style={{ width: 64, height: 64, borderRadius: 0, backgroundColor: '#EEEEEE' }} />
              ))}
            </Row>
          )}
        </>
      )}

      {/* ══════ ⑥ 실드랍 — 미오픈 드랍이 있을 때만, 오픈은 리워드 센터에서 ══════
          Ink+volt ceremony face stays (drop = milestone artifact; dark is the artifact). */}
      {pendingDrop && (
        <Pressable
          onPress={() => router.push('/runner/rewards')}
          style={({ pressed }) => [s.dropBanner, pressed && { transform: [{ scale: 0.96 }] }]}
          accessibilityRole="button"
          accessibilityLabel={`${pendingDrop.runCountAt}회 달성 드랍 — 리워드 센터에서 열기`}
        >
          <Icon name={pendingDrop.kind === 'pick' ? 'Gift' : 'Package'} glyph="●" size={24} color={colors.volt} />
          <Text style={{ fontSize: 16, fontWeight: '800', color: colors.volt, marginTop: 5 }}>
            {pendingDrop.runCountAt}회 달성 — {pendingDrop.kind === 'pick' ? '픽 드랍' : '보급 상자'} 도착!
          </Text>
          <Text style={{ fontSize: 14, color: '#BBBBBB', marginTop: 3 }}>리워드 센터에서 열기 ›</Text>
        </Pressable>
      )}

      {/* ══════ ⑦ 출구 — 코랄은 '다음 요청 보기' 하나 (프레임당 채도 1) ══════
          리뷰는 runResult.bookingId를 읽어 쓰므로, 예약이 없으면 그 화면은 제출할 수 없다 —
          문 자체를 그리지 않는다 (죽은 버튼 금지). 홈은 조용한 출구로 남는다. */}
      {runResult.bookingId && (
        <PaperBtn
          label={dogName ? `${dogName} 리뷰 남기기 ›` : '반려견 리뷰 남기기 ›'}
          variant="secondary"
          style={{ marginTop: 22 }}
          onPress={() => router.push('/runner/review')}
        />
      )}
      <PaperBtn
        label="다음 요청 보기 ›"
        style={{ marginTop: runResult.bookingId ? 8 : 22 }}
        onPress={() => router.replace('/runner/requests')}
      />
      <PaperBtn label="홈으로" variant="quiet" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
    </ScrollView>
  );
}

// 숫자 셋 (14a) — Oswald via nf. [BUG A] lineHeight must be explicit or the ascenders clip.
// The unit rides inside the value line so '5.12' and 'km' share one baseline; the label under it
// holds the 14pt detail floor (it is not a letterspaced kicker, so it gets no exemption).
function DoneStat({ nf, value, unit, label }: { nf: TextStyle | null; value: string; unit?: string; label: string }) {
  return (
    <View>
      <Text style={[s.statValue, nf]}>
        {value}{unit ? <Text style={s.statUnit}>{unit}</Text> : null}
      </Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  // ---------- ① 트레이스 플레이트 ----------
  tracePlate: { backgroundColor: paper.ink, height: TRACE_H, marginBottom: 12, justifyContent: 'center' },
  traceNote: { fontSize: 14, lineHeight: 19, color: '#BBBBBB', paddingHorizontal: 12 },
  traceCap: { position: 'absolute', right: 10, bottom: 8, fontSize: 14, lineHeight: 18, color: '#999999' },
  // ---------- ② 헤드라인 ----------
  headline: { fontSize: 27.5, fontWeight: '900', color: paper.ink },
  sub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // ---------- ③ 숫자 셋 — owner/report.tsx와 같은 문법 ----------
  statValue: { fontSize: 27, lineHeight: 33, fontWeight: '900', color: paper.ink }, // [BUG A] 27 × 1.22
  statUnit: { fontSize: 15, lineHeight: 33, fontWeight: '800', color: paper.dim },
  statLabel: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 1 },
  // 섹션 분할 = 풀블리드 솔리드 코랄 1px — 이 선이 곧 브랜드 (§2 종이 법)
  rule: { marginHorizontal: -layout.gutter, height: 1, backgroundColor: paper.line, marginTop: 18, marginBottom: 14 },
  // ---------- ④ 돈 한 줄 ----------
  moneyLabel: { fontSize: 16, lineHeight: 21, fontWeight: '700', color: paper.text },
  moneyNum: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, // [BUG A] 19 × 1.26
  moneyUnit: { fontSize: 15, lineHeight: 24, fontWeight: '800', color: paper.ink },
  moneyNote: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // 라우드-페일 스트립 — earnings.tsx/community.tsx와 같은 문법 (criticalWash + critical ink)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 12 },
  failText: { fontSize: 14, lineHeight: 19.5, fontWeight: '700', color: paper.critical },
  reasonLine: { fontSize: 14.5, lineHeight: 20, color: paper.text, marginTop: 12 },
  // ---------- ⑤ 섹션 헤더 ----------
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
  secAction: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.actionInk },
  secQuiet: { fontSize: 14, lineHeight: 19, color: paper.dim },
  // ---------- ⑥ 드랍 ----------
  dropBanner: {
    marginTop: 18, padding: 18, alignItems: 'center',
    backgroundColor: paper.ink, borderWidth: 1.5, borderColor: colors.volt,
  },
});
