import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import Svg, { Defs, LinearGradient, Rect, Stop } from 'react-native-svg';
import { useAuth } from '../src/auth-context';
import { BottomNav } from '../src/components/bottomnav';
import { StatusBarCover } from '../src/components/status-bar-cover';
import { TabSwipe } from '../src/components/tabswipe';
import { STAMP_GAP, STAMP_INK, StampCell } from '../src/components/stamp';
import { Avatar, Row } from '../src/components/ui';
import { deriveStamps, fetchFitness, fetchMyRunnerApplication, fetchMyRunnerStatus, fetchStampStats, RunnerApplication, StampStats } from '../src/lib/api';
import { fetchMyProfile, fetchMyRunnerBio, MyProfile, setMyHandle, updateMyProfile, updateRunnerBio, uploadAvatar } from '../src/lib/api';
import { session } from '../src/store';
import { colors, layout, lilac, lilacRadius, paper } from '../src/theme';

// 마이 — 여권(PASSPORT) 리페인트. 신분면(이중 프레임·MRZ)·기록면(나이트 라일락)·서류행.
// 로직 동결: 실프로필(사진·이름·동네)·MENU 라우팅·편집 시트·아바타 업로드는 원본 그대로.
// [paper chrome 2026-08-10] 라일락 크롬 은퇴 → 페이퍼: 순백 캔버스 · 샤프 · 신분면 = 이 화면의
// 강조 카드(1px 코랄, 예산 1회) · 내부 선은 #EEE. 다크 아티팩트는 그대로: 기록면(나이트 라일락),
// 도장면 그리드+소인, MRZ 스트립, 홀로 엣지 (artifact law — 주변 크롬만 페이퍼).
// 코랄은 텍스트로 쓰지 않는다 — 라인/엣지/틱으로만.

// 홀로 엣지 (여권 각인 · 티켓 엣지 문법) — 코랄이 텍스트가 아닌 엣지로만 등장
const HOLO = ['#CFC5F6', '#FFDCD1', '#F3E9C6', '#EAF6C8', '#CDEAF3', '#CFC5F6'];
function HoloEdge({ height = 3, opacity = 1 }: { height?: number; opacity?: number }) {
  return (
    <Svg width="100%" height={height} style={{ position: 'absolute', top: 0, left: 0, right: 0, opacity }} pointerEvents="none">
      <Defs>
        <LinearGradient id="holo" x1="0" y1="0" x2="1" y2="0">
          {HOLO.map((c, i) => (
            <Stop key={i} offset={`${i / (HOLO.length - 1)}`} stopColor={c} />
          ))}
        </LinearGradient>
      </Defs>
      <Rect x="0" y="0" width="100%" height={height} fill="url(#holo)" />
    </Svg>
  );
}

// ③ 도장면 프리미티브 — src/components/stamp.tsx로 추출 (2026-08-05, 3중복 사고 재발 방지).
// 잉크 법·폭 예산·기울기 정본은 전부 그 파일에 산다. 여기는 소비만.

export default function My() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀 (화면당 1회)
  const nf = useNumFont();     // [V4] Oswald — 숫자·마이크로캡 라벨
  const isRunner = session.role === 'runner';
  // 나의 러닝 기록 — 실데이터 (러너: 서버 누적 스탯 / 보호자: 이번 주 집계)
  // [정직 수리 2026-08-05] Fitness에는 totalKm/totalRuns가 존재한 적 없다 — f:any가 가리던 채로
  // 주간 수치가 '총 거리/총 횟수'로 표기되던 P1. 보호자는 주간 수치를 주간 라벨로 말한다.
  // 실누적은 리워드 ② 구현에서 실카운트 쿼리와 함께 온다.
  const [rec, setRec] = useState<{ km: number; runs: number; pace: string; dogName?: string | null } | null>(null);
  // [정직 배치 2026-08-06 · item 5] 로딩 ≠ 실패 ≠ 진짜 0. '—'만으론 영원한 로딩과 실패를 구별할 수
  // 없어 기록면 아래에 라우드 페일 스트립 + 재시도를 단다 (fetchFitness는 이제 실패 시 throw한다).
  const [recErr, setRecErr] = useState(false);
  const loadRec = useCallback(() => {
    setRecErr(false);
    // [E7 2026-08-12] 러너 분기 삭제 — 기록면이 러너 홈으로 갔으므로 이 화면에서 러너는 rec를
    // 쓰지 않는다. 그 분기에는 버그도 있었다: `(r: any)`로 캐스팅해 `r.paceLabel`을 읽었는데
    // MyRunnerStatus에 그런 필드가 없어(`{totalRuns, totalKm, online, tier}`) 페이스는 항상 '—'였다.
    // any 캐스트가 타입 검사기의 눈을 가린 자리다 — 옮기면서 필드째 은퇴시켰다.
    if (isRunner) return;
    fetchFitness()
      .then((f) => setRec({
        km: f.weekKm ?? 0, runs: f.weekRuns ?? 0,
        pace: f.avgPaceSec ? `${Math.floor(f.avgPaceSec / 60)}'${String(f.avgPaceSec % 60).padStart(2, '0')}"` : '—',
        dogName: f.dogName ?? null, // [리뷰 F4] 신분면·메뉴 라벨의 목업 초코 은퇴용 실이름
      }))
      .catch((e) => { console.warn('[my] fitness:', e?.message ?? e); setRecErr(true); }); // 직전 실값 유지
  }, [isRunner]);
  useEffect(() => { loadRec(); }, [loadRec]);
  // ③ 도장면 — 파생 실데이터. null = 아직 안 왔거나 실패 = 섹션 통째로 침묵 (로딩은 0이 아니다).
  const [stampStats, setStampStats] = useState<StampStats | null>(null);
  const [stampErr, setStampErr] = useState(false);
  const loadStamps = () => {
    setStampErr(false);
    fetchStampStats().then(setStampStats).catch((e) => { console.warn('[my] stamps:', e?.message ?? e); setStampErr(true); });
  };
  const stamps = useMemo(() => (stampStats ? deriveStamps(stampStats) : null), [stampStats]);
  const stampsEarned = stamps ? stamps.filter((x) => x.earned).length : 0;
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState('');
  const [district, setDistrict] = useState('');
  // [0074 · Sean 2026-08-12] 인스타식 계정 아이디. 서버가 유일한 검증자라 클라는 형식을 흉내내지 않는다.
  const [handle, setHandle] = useState('');
  const [bio, setBio] = useState('');
  const [savedBio, setSavedBio] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  const [saving, setSaving] = useState(false);

  // [plan §6.4] 러너 인증 센터 행의 부제는 이제 상태를 말한다 — /runner/apply가 실퍼널이 됐기 때문에
  // '인증 절차 안내'는 더 이상 그 화면이 하는 일의 전부가 아니다. loaded 플래그가 따로 있는 이유는
  // 여기서도 같다: 미도착과 '지원한 적 없음'은 다른 사실이고, 미도착일 땐 상태를 주장하지 않는다.
  const [runnerApp, setRunnerApp] = useState<RunnerApplication | null>(null);
  const [runnerAppLoaded, setRunnerAppLoaded] = useState(false);

  useFocusEffect(useCallback(() => {
    fetchMyProfile().then(setProfile).catch((e) => console.warn('[my] profile:', e?.message ?? e));
    if (isRunner) fetchMyRunnerBio().then(setSavedBio).catch(() => {});
    if (isRunner) {
      fetchMyRunnerApplication()
        .then((a) => { setRunnerApp(a); setRunnerAppLoaded(true); })
        .catch((e) => console.warn('[my] runner application:', e?.message ?? e)); // 실패 = 미도착 유지
    }
    // 도장은 다른 화면(리포트·클럽·피드)에서 찍히고 돌아온다 → 포커스마다 다시 센다.
    // 실패는 실패로: 이전 실값이 있으면 그대로 두고, 없으면 실패 스트립이 말한다
    // (0/12를 그리지 않는다 — [honesty 2026-08-11] 조용한 섹션 증발도 그만: recErr 모델 복제).
    loadStamps();
  }, [isRunner]));

  const openEdit = () => {
    setName(profile?.name ?? '');
    setDistrict(profile?.district ?? '');
    setHandle(profile?.handle ?? '');
    setBio(savedBio ?? '');
    setEditing(true);
  };

  const pickPhoto = async () => {
    // 지연 로드 — 네이티브 모듈이 없는 빌드(구 dev build/Expo Go)에서 앱 전체가 죽지 않게.
    // 상단 import는 라우터의 라우트 스캔 단계에서 앱을 통째로 크래시시킨다 (2026-07-23).
    let ImagePicker: any;
    try {
      ImagePicker = require('expo-image-picker');
    } catch {
      Alert.alert('개발 빌드 업데이트 필요', '프로필 사진 기능은 새 빌드에 포함돼요\n터미널에서: npx expo run:ios');
      return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({
        mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.6, base64: true,
      });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      const url = await uploadAvatar(res.assets[0].base64);
      setProfile((p) => (p ? { ...p, avatarUrl: url } : p));
    } catch (e) {
      Alert.alert('업로드 실패', (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  const save = async () => {
    setSaving(true);
    try {
      await updateMyProfile({ name: name.trim() || undefined, district: district.trim() || undefined });
      // 아이디는 별도 RPC — profiles 직접 UPDATE로는 못 쓴다 (0074: 컬럼 화이트리스트가 없는 테이블).
      // 바뀐 경우에만 부른다. 서버가 멱등이라 안 불러도 되지만, 실패 메시지를 아이디 탓으로만 돌리려면
      // 호출 자체가 아이디를 바꿀 때만 일어나는 편이 명확하다.
      const h = handle.trim();
      if (h && h.toLowerCase() !== (profile?.handle ?? '')) await setMyHandle(h);
      if (isRunner) {
        await updateRunnerBio(bio.trim());
        setSavedBio(bio.trim());
      }
      setProfile((p) => (p ? { ...p, name: name.trim() || p.name, district: district.trim() || p.district } : p));
      setEditing(false);
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  // 인증 센터 행 부제 — 지원 상태에 따라. 미도착이면 아무 상태도 주장하지 않고 화면 이름만 말한다.
  const certDesc = !runnerAppLoaded ? '내 러너 레코드 · 인증 절차'
    : runnerApp === null ? '내 러너 레코드 · 지원하기'
      : runnerApp.state === 'submitted' || runnerApp.state === 'under_review' ? '내 러너 레코드 · 심사 중'
        : runnerApp.state === 'approved' ? '내 러너 레코드 · 인증 완료'
          : runnerApp.canReapply ? '내 러너 레코드 · 다시 지원하기'
            : '내 러너 레코드 · 지원 결과 확인';

  // [2026-08-11] 명시 타입 앵커. 러너/보호자 분기가 조건부 스프레드 3개로 늘면서 TS가 배열의
  // 원소 타입을 `never`로 접었다 (`m.label` does not exist on type 'never'). 리터럴 라우트 유니온을
  // 타입으로 못박으면 router.push의 타입 안전성은 그대로 두고 추론만 안정된다.
  type MenuRow = {
    glyph: string; label: string; ink: string; tint: string;
    // [D14 2026-08-12] desc 옵셔널 — 부제가 라벨을 되풀이하기만 하는 행에서는 아예 없앤다.
    // 빈 줄을 그리거나 자리를 예약하지 않는다 (없는 부제는 없는 높이다).
    desc?: string;
    path: '/safety' | '/runner/apply' | '/owner/addresses' | '/owner/dog'
        | '/owner/schedule' | '/cards' | '/alerts' | '/settings';
  };
  const MENU: MenuRow[] = [
    { glyph: '✚', label: '안심 센터', desc: 'SOS · 긴급 연락처 · 보험', path: '/safety', ink: colors.tang, tint: '#FCE7E1' },
    isRunner
      // [정직 수리 2026-08-05] 부제 교정 — 인증 센터에는 '등급 사다리'가 없다(목업 퍼널과 함께 퇴역).
      // [2026-08-08 / plan §6.4] 그 화면이 실퍼널이 되면서 부제가 상태를 말한다 (certDesc 참조).
      ? { glyph: '✓', label: '러너 인증 센터', desc: certDesc, path: '/runner/apply', ink: colors.voltDeep, tint: '#EDF5D8' }
      : { glyph: '⌂', label: '주소 관리', desc: '픽업 장소 · 공동현관 정보', path: '/owner/addresses', ink: colors.voltDeep, tint: '#EDF5D8' },
    ...(!isRunner ? ([{ glyph: '◉', label: '반려견 프로필', desc: '사진 · 성향 · 러너에게 전달되는 정보', path: '/owner/dog', ink: colors.terra, tint: colors.terraTint }] as MenuRow[]) : []),
    // [죽은 버튼 2026-08-11] 러너에게 이 행은 path: null이라 '준비 중이에요' 얼럿만 띄웠다 — 그런데
    // 러너의 '다가오는 일정과 지난 예약'은 **준비 중이 아니다**. 캘린더 탭이 바로 그 화면이고 탭 바에서
    // 한 번에 간다. 없는 기능이라 거짓말한 게 아니라, 있는 기능을 없다고 말하던 행이다.
    // 보호자에게만 남긴다 (보호자는 일정 탭이 있지만 이 허브에서도 들어오는 기존 경로를 유지).
    // [D14] desc '다가오는 일정과 지난 예약' 삭제 — 라벨을 더 긴 말로 다시 쓴 것뿐이다.
    ...(isRunner ? [] : ([{ glyph: '▦', label: '예약 관리', path: '/owner/schedule', ink: '#4A6E93', tint: '#E3EEF8' }] as MenuRow[])),
    // [Sean 2026-08-11] 러너의 '내 러닝 기록' 행은 러너 홈의 '내 기록' 섹션으로 옮겼다 —
    // 같은 목적지(/cards)로 가는 문이 마이와 홈에 둘 있었고, 홈 쪽만 실수치(누적 거리)를 말한다.
    // 보호자 행은 남는다 (보호자 홈에는 대응 섹션이 없다). ⚠ 두 행 모두 목적지 이름이 틀렸었다:
    // /cards는 **컬렉션(ANNEX — 도장 + 코스 패치)**이지 '러닝 히스토리'가 아니다 (cards.tsx:89 '컬렉션').
    ...(isRunner ? [] : ([{ glyph: '⌗', label: rec?.dogName ? `${rec.dogName}의 기록` : '러닝 기록', desc: '도장 · 코스 패치 컬렉션', path: '/cards', ink: colors.goldDeep, tint: colors.goldTint }] as MenuRow[])),
    // [D14] desc '알림 확인 및 설정' 삭제 — 최악의 되풀이였다 ('알림'을 열면 알림을 확인한다).
    { glyph: '◔', label: '알림', path: '/alerts', ink: colors.clubInk, tint: colors.clubTint },
    { glyph: '⚙', label: '설정', desc: '계정 · 로그아웃 · 문의', path: '/settings', ink: '#586055', tint: '#EFF1EC' },
  ];

  // 신분면 필드 값 (원본 subtitle과 동일 바인딩 — 활동 동네 · 반려견)
  // [정직 배치 2026-08-06 · item 7] 러너 줄의 '신원인증 · 펫보험 가입' 은퇴 — 서명된 보험 증권도,
  // 신원인증 상태를 읽는 코드도 없다(P1-6). 실등급이 붙기 전까진 활동 동네만 말한다.
  // [리뷰 F4] 오너 줄의 목업 초코·품종 은퇴 — 실이름 있으면 이름만, 없으면 동네만 (품종 실소스 없음 → 생략)
  const districtLine = isRunner
    ? (profile?.district ? profile.district : '—')
    : [profile?.district, rec?.dogName].filter(Boolean).join(' · ') || '—';
  const passportType = isRunner ? 'RUNNER' : 'OWNER';
  const docNo = profile?.id ? profile.id.replace(/-/g, '').slice(0, 8).toUpperCase() : null;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: layout.gutter, paddingTop: 64, paddingBottom: 24 }}>

        {/* ————— 마스트헤드 (에디토리얼 키커 + Black Han Sans 타이틀) ————— */}
        <Row style={s.kicker}>
          <Text style={[s.kickerTxt, nf]}>DOGS HIGH · MEMBER</Text>
          <View style={s.rule} />
          <Text style={[s.kickerTxt, nf]}>KOR</Text>
        </Row>
        <Row style={{ alignItems: 'flex-start', gap: 10 }}>
          <Text style={[s.h1, df]}>마이</Text>
          <View style={s.official}><Text style={[s.officialTxt, nf]}>PASSPORT</Text></View>
        </Row>
        {/* [2026-08-10 density audit] TOC sentence cut — the sections announce themselves; a passport needs no table of contents */}

        {/* ————— ① 신분면 — 이중 프레임 + MRZ ————— */}
        <View style={s.idcard}>
          <HoloEdge height={3} />
          <View style={s.idInner}>
            <Row style={s.idStrap}>
              <Text style={[s.microK, nf]}>IDENTITY / 신분면</Text>
              <View style={s.roleTag}><Text style={[s.roleTagTxt, nf]}>{isRunner ? '러너' : '보호자'}</Text></View>
            </Row>

            <Row style={{ alignItems: 'flex-start', gap: 12 }}>
              {/* 사진 창 — 탭하면 프로필 사진 변경 (uploadAvatar) */}
              <Pressable onPress={pickPhoto} disabled={uploading} style={s.photoWin}>
                <Avatar url={profile?.avatarUrl} char={(profile?.name ?? '나')[0]} bg={lilac.accent} size={56} />
                <View style={s.cam}><Text style={{ fontSize: 14, color: '#fff' }}>{uploading ? '…' : '✎'}</Text></View>
              </Pressable>

              <View style={{ flex: 1, minWidth: 0 }}>
                <View style={s.fld}>
                  <Text style={[s.fldK, nf]}>NAME / 이름</Text>
                  <Text style={s.fldV}>
                    {profile?.name ?? '...'} <Text style={s.fldVSmall}>{isRunner ? '러너' : '보호자님'}</Text>
                  </Text>
                </View>
                <View style={s.fld}>
                  <Text style={[s.fldK, nf]}>DISTRICT / 활동 동네</Text>
                  <Text style={s.fldV2}>{districtLine}</Text>
                </View>
                <Pressable
                  style={s.idEdit}
                  onPress={() => {
                    // 프로필 편집 단일화 — 러너는 스토어프런트에서, 보호자는 여기 시트에서 (혼선 제거)
                    if (isRunner) {
                      if (profile) router.push(`/runner-profile/${profile.id}`);
                    } else {
                      openEdit();
                    }
                  }}
                >
                  <Text style={s.idEditTxt}>{isRunner ? '프로필 편집' : '프로필 설정'}</Text>
                  <Text style={[s.idEditEm, nf]}>EDIT ›</Text>
                </Pressable>
              </View>
            </Row>

            {/* 신분면 그리드 — Type(역할 실데이터) · No.(프로필 id 파생) */}
            <Row style={s.idGrid}>
              <View style={s.idCell}>
                <Text style={[s.gridK, nf]}>TYPE</Text>
                <Text style={[s.gridV, nf]}>P · {passportType}</Text>
              </View>
              {docNo && (
                <View style={[s.idCell, s.idCellDiv]}>
                  <Text style={[s.gridK, nf]}>NO.</Text>
                  <Text style={[s.gridV, nf]}>DH-{docNo}</Text>
                </View>
              )}
            </Row>
          </View>

          {/* MRZ 스트립 — 순수 장식 (aria-safe, 실데이터 없음) */}
          <View
            style={s.mrz}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
            pointerEvents="none"
          >
            <Text style={[s.mrzTxt, nf]} numberOfLines={1}>P&lt;KOR&lt;DOGSHIGH&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;</Text>
            <Text style={[s.mrzTxt, nf]} numberOfLines={1}>{passportType}&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;&lt;</Text>
          </View>
        </View>
        {/* [2026-08-10 density audit] photo-change hint row cut — the ✎ badge on the photo and the
            edit-sheet hint already cover it (this was the 3rd copy of the same instruction) */}

        {/* ————— ② 기록면 — 나이트 라일락 앵커 (실데이터) —————
             [E7 승인 2026-08-12 · Sean] **러너에게는 여기 없다** — 러너 홈의 '내 기록' 섹션으로
             옮겼다 ("러너 페이지의 내 기록 같은 건 마이가 아니라 홈에 있어야 한다").
             보호자는 남는다: 보호자 홈에 대응 섹션이 없고, 보호자의 세 칸(주간 거리·횟수·페이스)은
             fetchFitness가 전부 실값으로 채운다. 러너 쪽 '평균 페이스'는 그렇지 않았다 —
             MyRunnerStatus에 paceLabel이 없어 영원히 '—'였고, 그 칸은 이사하면서 버렸다. */}
        {!isRunner && (
        <Pressable
          onPress={() => router.push('/owner/fitness')}
          style={s.record}
        >
          <HoloEdge height={2} opacity={0.85} />
          <View style={s.recordInner}>
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: '#fff' }}>나의 러닝 기록</Text>
              <Row style={{ alignItems: 'center', gap: 5 }}>
                <View style={s.coralDot} />
                <Text style={[s.recordKick, nf]}>RECORD / 기록면</Text>
              </Row>
            </Row>
            <Row>
              {[
                // 로딩은 0이 아니다 — rec가 오기 전엔 세 칸 모두 '—' (단위도 함께 접어 대시에 매달리지 않게)
                { v: rec ? rec.km.toFixed(1) : '—', u: rec ? ' km' : '', l: isRunner ? '총 거리' : '이번 주 거리', div: false },
                { v: rec ? `${rec.runs}` : '—', u: rec ? ' 회' : '', l: isRunner ? '총 횟수' : '이번 주 횟수', div: true },
                { v: rec?.pace ?? '—', u: '', l: isRunner ? '평균 페이스' : '주간 페이스', div: true },
              ].map((c) => (
                <View key={c.l} style={[{ flex: 1 }, c.div && s.recDiv]}>
                  <Text style={[s.recN, nf]}>
                    {c.v}<Text style={s.recU}>{c.u}</Text>
                  </Text>
                  <Text style={s.recL}>{c.l}</Text>
                </View>
              ))}
            </Row>
            <View style={s.recGoWrap}>
              <Text style={s.recGo}>상세 기록 보기 ›</Text>
            </View>
          </View>
        </Pressable>
        )}
        {/* 기록 로드 실패 — 세 칸의 '—'가 로딩인지 실패인지 여기서 갈린다 (라우드 페일 + 재시도) */}
        {!isRunner && recErr && (
          <View style={s.recFail}>
            <Text style={s.recFailTxt}>러닝 기록을 불러오지 못했어요</Text>
            <Pressable onPress={loadRec} hitSlop={8} accessibilityRole="button" accessibilityLabel="러닝 기록 다시 불러오기">
              <Text style={s.recFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ————— ③ 도장면 — 비자 페이지 (리워드 ② · 랩 Ⓐ①) —————
            정적면이다: 애니메이션 0. 세리머니는 리포트(런엔드)가 진다 — 벽은 조용한 문서다.
            파생이 도착하기 전에는 섹션 자체가 없다 (로딩은 0이 아니다 → '0 / 12'를 그리지 않는다). */}
        {/* 도장 로드 실패 — 섹션이 말없이 증발하는 대신 라우드 페일 + 재시도 (recErr 모델) */}
        {!stamps && stampErr && (
          <View style={s.recFail}>
            <Text style={s.recFailTxt}>도장 현황을 불러오지 못했어요</Text>
            <Pressable onPress={loadStamps} hitSlop={8} accessibilityRole="button" accessibilityLabel="도장 현황 다시 불러오기">
              <Text style={s.recFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
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
                  <Text style={[s.microK, nf]}>STAMPS / 도장면</Text>
                  <View style={s.visaCnt}>
                    <Text style={[s.visaCntTxt, nf]}>{stampsEarned} / {stamps.length}</Text>
                  </View>
                </Row>
                {/* 0개 상태 — 정직하되 나무라지 않는다: 재촉 카피도, 경고색 카운트도 없다 */}
                {stampsEarned === 0 && (
                  <View style={s.empt}>
                    <Text style={s.emptT}>도장면은 비어 있는 채로 시작해요</Text>
                    {/* 영속성 카피 주의 — '영구' 류 약속은 거짓이 될 수 있다: 자랑 글 삭제·코스 비활성이 실제 감소 벡터 (api.ts 계약 주석) */}
                    <Text style={s.emptD}>첫 러닝을 완주하면 왼쪽 위 칸부터 찍혀요. 기록이 남아 있는 한 도장은 그대로예요.</Text>
                  </View>
                )}
                {/* 인쇄 순서는 고정 — 하나 받았다고 칸이 재배열되는 종이는 없다 (deriveStamps가 순서를 진다) */}
                <View style={s.sgrid}>
                  {stamps.map((st) => <StampCell key={st.key} info={st} nf={nf} />)}
                </View>
              </View>
              <View style={s.perf} />
              {/* [2026-08-10 density audit] "코스 패치도..." lead-in cut — the link alone says where it goes */}
              <Pressable style={s.visaFoot} onPress={() => router.push('/cards')}>
                <Text style={s.visaFootG}>전체 보기 ›</Text>
              </Pressable>
            </View>
          </>
        )}

        {/* ————— ④ 서류행 — 헤어라인 문서 목록 (MENU 동결) ————— */}
        <Row style={s.sec}>
          <Text style={[s.secNo, nf]}>§</Text>
          <Text style={[s.secT, nf]}>DOCUMENTS</Text>
          <Text style={s.secKo}>서류</Text>
          <View style={s.rule} />
        </Row>
        <View style={s.doc}>
          {MENU.map((m, i) => (
            <Pressable
              key={m.label}
              style={({ pressed }) => [s.drow, i > 0 && s.drowDiv, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
              onPress={() => {
                if (m.path) router.push(m.path);
                else Alert.alert(m.label, '준비 중이에요');
              }}
            >
              {/* 도메인 잉크 — 좌측 액센트 틱 + 틴트 아이콘 칩 */}
              <View style={[s.drowTick, { backgroundColor: (m as any).ink }]} />
              <View style={[s.drowIcon, { backgroundColor: (m as any).tint }]}>
                <Text style={{ fontSize: 14, color: (m as any).ink }}>{m.glyph}</Text>
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                <Text style={s.drowTitle}>{m.label}</Text>
                {m.desc ? <Text style={s.drowDesc}>{m.desc}</Text> : null}
              </View>
              <Text style={{ fontSize: 16, color: paper.dim }}>›</Text>
            </Pressable>
          ))}
        </View>

        {/* ————— ⑤ 큰 버튼 (여백엔 큰 버튼 — Sean 룰) ————— */}
        <Pressable style={({ pressed }) => [s.btnRole, { transform: [{ scale: pressed ? 0.96 : 1 }] }]} onPress={() => router.dismissTo('/')}>
          <View>
            <Text style={s.btnRoleTitle}>역할 전환</Text>
            {/* [이모지 법 2026-08-11] ↔(U+2194)는 소스상 변이 셀렉터 없는 **타이포그래픽 글리프**라
                산증 클래스다 — 그런데 Oswald(nf)에 그 글리프가 없어 iOS가 Apple Color Emoji로
                폴백했고, 화면엔 파란 상자 이모지가 떴다 (시뮬레이터 실측). 저자가 아니라
                폰트 폴백이 만든 컬러 이모지 — 금지는 결과에 걸린다 (§7b). 산증 글리프
                ›로 바꾸고 양방향은 제목('역할 전환')과 스위치 칩이 말한다. */}
            <Text style={[s.btnRoleSub, nf]}>OWNER › RUNNER</Text>
          </View>
          <View style={s.btnRoleSw}><Text style={[s.btnRoleSwTxt, nf]}>보호자 › 러너</Text></View>
        </Pressable>

        <Pressable
          style={({ pressed }) => [s.signout, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
        >
          <View style={s.signoutTick} />
          <View style={{ flex: 1 }}>
            <Text style={s.signoutTitle}>로그아웃</Text>
            {auth?.user.email ? <Text style={s.signoutSub}>{auth.user.email}</Text> : null}
          </View>
          <Text style={{ fontSize: 15, color: paper.dim }}>›</Text>
        </Pressable>

        {/* ————— ⑥ 콜로폰 (브랜드 워드마크 — 정적 브랜딩) ————— */}
        <View style={s.colophon}>
          <Text style={[s.colophonTxt, nf]}>도그스하이 · DOGS HIGH</Text>
        </View>
      </ScrollView>
      {/* 시스템 바 스트립 — 마스트헤드가 시계 뒤로 지나가던 것 */}
      <StatusBarCover />
      </TabSwipe>
      <BottomNav />

      {/* ---------- 프로필 편집 시트 ---------- */}
      <Modal visible={editing} transparent animationType="slide" onRequestClose={() => setEditing(false)}>
        <Pressable style={s.backdrop} onPress={() => setEditing(false)} />
        <View style={s.sheet}>
          <View style={s.handle} />
          <Text style={{ fontSize: 22, fontWeight: '900', color: paper.ink }}>프로필 설정</Text>

          {/* [0074 · Sean 2026-08-12] 아이디가 이름보다 위에 온다 — 인스타에서 사람을 부르는 단위는
              표시 이름이 아니라 @아이디다. 서버 규칙(3~20자·소문자·[a-z0-9_.])을 라벨이 미리 말해주되
              **검증은 하지 않는다**: 두 곳에서 자르면 두 규칙이 갈라진다 (0073의 교훈). */}
          <Text style={s.fieldLabel}>아이디</Text>
          <Row style={{ alignItems: 'center', gap: 6 }}>
            <Text style={{ fontSize: 17, fontWeight: '800', color: paper.dim }}>@</Text>
            <TextInput
              value={handle}
              onChangeText={(t) => setHandle(t.toLowerCase().replace(/\s/g, ''))}
              placeholder="choco.runner"
              placeholderTextColor={paper.faint}
              style={[s.input, { flex: 1 }]}
              maxLength={20}
              autoCapitalize="none"
              autoCorrect={false}
            />
          </Row>
          <Text style={{ fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 5 }}>
            영문 소문자·숫자·밑줄(_)·점(.) · 3~20자 · 피드에서 이 이름으로 보여요
          </Text>

          <Text style={s.fieldLabel}>이름</Text>
          <TextInput
            value={name}
            onChangeText={setName}
            placeholder="이름 또는 닉네임"
            placeholderTextColor={paper.faint}
            style={s.input}
            maxLength={20}
          />
          <Text style={s.fieldLabel}>활동 동네</Text>
          <TextInput
            value={district}
            onChangeText={setDistrict}
            placeholder="예: 반포동"
            placeholderTextColor={paper.faint}
            style={s.input}
            maxLength={20}
          />
          {isRunner && (
            <>
              <Text style={s.fieldLabel}>자기소개 (스토어프런트)</Text>
              <TextInput
                value={bio}
                onChangeText={setBio}
                placeholder="보호자에게 보여줄 소개를 적어보세요 — 러닝 경력, 반려견 경험, 나의 강점"
                placeholderTextColor={paper.faint}
                style={[s.input, { height: 96, textAlignVertical: 'top', paddingTop: 12 }]}
                multiline
                maxLength={300}
              />
            </>
          )}
          <Text style={{ fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 17 }}>
            이름과 동네는 매칭 화면에서 상대방에게 보여요{'\n'}프로필 사진은 마이 화면에서 사진을 탭해 변경해요
          </Text>

          {/* busy = 라벨 스왑 (버튼 매트릭스 법 — 불투명도 트릭 금지) */}
          <Pressable onPress={save} disabled={saving} style={s.saveBtn}>
            <Text style={{ fontSize: 16, fontWeight: '800', color: '#fff' }}>{saving ? '저장 중...' : '저장'}</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  // 마스트헤드 — 키커 = faint 장식 클래스 (라틴 캡스 12 면제), 인라인 룰은 중립 #EEE
  kicker: { alignItems: 'center', gap: 8, marginTop: 6, marginBottom: 8 },
  kickerTxt: { fontSize: 12, letterSpacing: 2, color: paper.faint, textTransform: 'uppercase' },
  rule: { flex: 1, height: 1, backgroundColor: '#EEE' },
  // [§3c 화면 타이틀 2026-08-11] 40 → 30 (탭 타이틀 통일 — 위 community.tsx 주석 참조)
  h1: { fontSize: 30, fontWeight: '900', color: paper.ink, lineHeight: 37 },
  // PASSPORT 태그 — 1px 잉크 보더 샤프로 정규화
  official: {
    marginTop: 6, borderWidth: 1, borderColor: paper.ink,
    paddingVertical: 5, paddingHorizontal: 8, backgroundColor: paper.canvas,
  },
  officialTxt: { fontSize: 11.5, letterSpacing: 1.8, color: paper.ink, fontWeight: '600' },
  // subNote (TOC line) retired — 2026-08-10 density audit

  // ① 신분면 — 이 화면의 강조 카드: 1px 코랄 (예산 1회), 내부 선은 전부 #EEE. 샤프·섀도 은퇴.
  idcard: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    overflow: 'hidden', marginTop: 14,
  },
  idInner: { margin: 9, borderWidth: 1, borderColor: '#EEE', padding: 12, paddingBottom: 0 },
  idStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  // Korean-data-in-kicker (신분면/도장면 halves) — 14pt floor applies; letterSpacing tightened
  // so the passport look survives the raise. Latin-only kickers elsewhere stay 12.
  microK: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: paper.dim, textTransform: 'uppercase' },
  roleTag: { borderWidth: 1, borderColor: '#EEE', backgroundColor: paper.canvas, paddingVertical: 4, paddingHorizontal: 9 },
  roleTagTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: paper.ink, fontWeight: '600' }, // '러너'/'보호자' is data, not decoration — 14pt floor
  photoWin: {
    width: 62, height: 74, borderWidth: 1, borderColor: '#EEE',
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
  },
  cam: {
    position: 'absolute', right: -6, bottom: 2, width: 22, height: 22, borderRadius: 11,
    backgroundColor: '#C6472C', borderWidth: 1.5, borderColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
  },
  fld: { marginBottom: 8 },
  fldK: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: paper.dim, textTransform: 'uppercase', marginBottom: 4 }, // 'NAME / 이름' carries Korean — 14pt floor
  fldV: { fontSize: 17, fontWeight: '800', color: paper.ink }, // user name = the page's lead datum (15 -> 17)
  fldVSmall: { fontSize: 14, fontWeight: '600', color: paper.text },
  fldV2: { fontSize: 14, fontWeight: '600', color: paper.text, lineHeight: 18 },
  idEdit: {
    marginTop: 2, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderWidth: 1, borderColor: '#EEE', backgroundColor: paper.canvas,
    paddingVertical: 10, paddingHorizontal: 11,
  },
  idEditTxt: { fontSize: 14, fontWeight: '700', color: paper.ink },
  idEditEm: { fontSize: 14, lineHeight: 18, letterSpacing: 1.4, color: paper.ink, textTransform: 'uppercase' }, // pressable emphasis, not decoration — 14pt floor
  idGrid: { marginTop: 10, marginHorizontal: -12, borderTopWidth: 1, borderTopColor: '#EEE' },
  idCell: { flex: 1, paddingTop: 9, paddingBottom: 10, paddingLeft: 12 },
  idCellDiv: { borderLeftWidth: 1, borderLeftColor: '#EEE' },
  gridK: { fontSize: 11.5, letterSpacing: 1.2, color: paper.dim, textTransform: 'uppercase', marginBottom: 3 },
  gridV: { fontSize: 13, letterSpacing: 0.6, color: paper.ink, fontWeight: '600' },
  // MRZ 스트립 — 아티팩트, 그대로 (artifact law)
  mrz: { backgroundColor: lilac.inset, borderTopWidth: 1, borderTopColor: lilac.hair2, paddingVertical: 7, paddingHorizontal: 10, gap: 2 },
  mrzTxt: { fontSize: 9, letterSpacing: 0.8, color: '#6E67A0' },
  // photoHint / photoHintDot retired — 2026-08-10 density audit (✎ badge + edit sheet keep coverage)

  // ② 기록면
  record: {
    backgroundColor: '#1C1837', borderRadius: lilacRadius.card, overflow: 'hidden', marginTop: 14,
    shadowColor: '#120E2C', shadowOpacity: 0.34, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  recordInner: { margin: 9, borderWidth: 1, borderColor: 'rgba(255,255,255,0.13)', borderRadius: lilacRadius.inner, padding: 13 },
  coralDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: lilac.coral },
  recordKick: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: 'rgba(255,255,255,0.5)', textTransform: 'uppercase' }, // 'RECORD / 기록면' carries Korean — 14pt floor
  recDiv: { borderLeftWidth: 1, borderLeftColor: 'rgba(255,255,255,0.13)', paddingLeft: 11 },
  recN: { fontSize: 23, lineHeight: 28, fontWeight: '800', color: '#fff' },
  recU: { fontSize: 14, fontWeight: '500', color: 'rgba(255,255,255,0.55)' },
  recL: { fontSize: 14, color: 'rgba(255,255,255,0.62)', marginTop: 4 },
  recGoWrap: { marginTop: 12, paddingTop: 10, borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.13)', alignItems: 'flex-end' },
  recGo: { fontSize: 14, fontWeight: '700', color: '#fff' },
  // 기록 로드 실패 스트립 (item 5) — 라우드 페일 토큰 전용. 다크 기록면 '밖'에 붙여 대비를 지킨다.
  recFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    // full-bleed: cancels the scroll padding, which is layout.gutter now (was hardcoded 16)
    marginHorizontal: -layout.gutter, marginTop: 8, paddingVertical: 11, paddingHorizontal: layout.gutter,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
  },
  recFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  recFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },

  // 섹션 라벨 — 섹션 헤드 위 코랄 1px 풀블리드 룰 (페이퍼 섹션 분리 법)
  sec: {
    alignItems: 'center', gap: 8, marginTop: 18, marginBottom: 9,
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter + 2,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 12,
  },
  secNo: { fontSize: 12, color: paper.line, fontWeight: '600' }, // 글리프 전용(§) — 코랄 룰과 한 시스템, 12pt 플로어 면제
  secT: { fontSize: 12, letterSpacing: 2, color: paper.faint, textTransform: 'uppercase' },
  secKo: { fontSize: 14, fontWeight: '700', color: paper.text },

  // ③ 도장면 — 도장 그리드·소인은 아티팩트 그대로, 카드 크롬만 페이퍼 (백지 샤프 + #EEE)
  visa: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEE',
    overflow: 'hidden',
  },
  visaInner: { margin: 9, borderWidth: 1, borderColor: '#EEE', padding: 11 },
  visaStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 11 },
  visaCnt: {
    borderWidth: 1, borderColor: '#EEE', backgroundColor: paper.canvas,
    paddingVertical: 3, paddingHorizontal: 9,
  },
  visaCntTxt: { fontSize: 16, lineHeight: 21, letterSpacing: 0.8, color: STAMP_INK, fontWeight: '600' }, // Oswald — lineHeight 1.31x (BUG A) · STAMP_INK = 아티팩트 어휘
  perf: { marginHorizontal: 9, borderTopWidth: 1, borderStyle: 'dashed', borderTopColor: '#EEE' }, // 절취선
  // visaFootL retired with its lead-in copy — the foot is now just the right-aligned link
  visaFoot: { flexDirection: 'row', alignItems: 'center', justifyContent: 'flex-end', paddingVertical: 10, paddingHorizontal: 11 },
  visaFootG: { fontSize: 14, fontWeight: '800', color: STAMP_INK },
  empt: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEE', padding: 11, marginBottom: 11 },
  emptT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: paper.ink },
  emptD: { fontSize: 14, lineHeight: 20, color: paper.text, marginTop: 3 },

  // 도장 그리드 — 칸/디스크/링은 stamp.tsx가 전담, 여기는 배열만
  sgrid: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-start', columnGap: STAMP_GAP, rowGap: 12 },

  // ④ 서류행 — 백지 샤프 카드 1px #EEE (도메인 잉크 틱·틴트 칩은 시맨틱 — 생존)
  doc: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEE', overflow: 'hidden' },
  drow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 13, paddingRight: 12, backgroundColor: paper.canvas },
  drowDiv: { borderTopWidth: 1, borderTopColor: '#EEE' },
  drowTick: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3 },
  drowIcon: { width: 27, height: 27, alignItems: 'center', justifyContent: 'center', marginLeft: 11, marginRight: 10 },
  drowTitle: { fontSize: 14, fontWeight: '700', color: paper.ink },
  drowDesc: { fontSize: 14, color: paper.dim, marginTop: 2, lineHeight: 18 },

  // ⑤ 큰 버튼 — 역할 전환 = 잉크 면 프라이머리 (15/14 라벨 유지, 섀도 은퇴)
  btnRole: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    // [액션] 역할 전환은 내비게이션이지 커밋이 아니다 -> 세컨더리 (허브 화면에 코랄 바 2개 금지)
    backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 16, paddingHorizontal: 15, marginTop: 20,
  },
  // 🔴 [2026-08-11 — 시뮬레이터에서 발견한 실배포 버그] 이 버튼은 같은 날 액션 스윕에서 잉크 면 →
  // **세컨더리**(캔버스/워시 + 코랄 보더)로 바뀌었는데(위 btnRole 주석), **라벨 색이 따라오지 않았다.**
  // 흰 글자가 그대로 남아 paper.wash(#FFF6F4) 위에 앉았다 = 대비 약 **1.06:1**. 사실상 안 보인다.
  // 화면에서 확인: '역할 전환 / OWNER › RUNNER / 보호자 › 러너'가 전부 유령처럼 떠 있었다.
  // 하필 보호자↔러너를 오가는 **유일한 문**이다. 면을 바꿀 때 라벨을 함께 옮기지 않으면 이렇게 된다 —
  // 불투명도 트릭 금지법이 막으려던 바로 그 결과를, 색 하나 안 바꿔서 만들었다.
  // §3b 세컨더리 규격으로 정정: 캔버스 + 코랄 1px + **잉크 16/800** 라벨.
  btnRoleTitle: { fontSize: 16, fontWeight: '800', color: paper.ink },
  // 라틴 레터스페이스 캡스 = 산증 키커 클래스(§3 예외)라 12pt 유지 가능하나, 색은 읽는 값으로.
  btnRoleSub: { fontSize: 12, letterSpacing: 1.8, color: paper.dim, textTransform: 'uppercase', marginTop: 3 },
  btnRoleSw: { borderWidth: 1, borderColor: paper.line, paddingVertical: 6, paddingHorizontal: 10 },
  btnRoleSwTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: paper.actionInk, fontWeight: '600' }, // '보호자 › 러너' is the button label — 14pt floor · wash 위 5.99:1

  signout: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: paper.canvas,
    borderWidth: 1, borderColor: '#EEE', paddingVertical: 13, paddingHorizontal: 12, marginTop: 12,
  },
  signoutTick: { width: 3, height: 30, backgroundColor: paper.line }, // 코랄 틱 — critical 아님 (로그아웃은 실패가 아니다)
  signoutTitle: { fontSize: 14, fontWeight: '700', color: paper.ink },
  signoutSub: { fontSize: 14, color: paper.dim, marginTop: 2 },

  // ⑥ 콜로폰
  colophon: { marginTop: 18, paddingTop: 12, borderTopWidth: 1, borderTopColor: '#EEE', alignItems: 'center' },
  colophonTxt: { fontSize: 12, letterSpacing: 1.8, color: paper.faint, textTransform: 'uppercase' },

  // 편집 시트 — 순백·샤프 (인풋 = addresses 문법: 캔버스 면 + 1px 코랄)
  backdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: paper.canvas, padding: 16, paddingBottom: 40 },
  handle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#EEE', marginBottom: 14 },
  fieldLabel: { fontSize: 14, fontWeight: '700', color: paper.ink, marginTop: 14, marginBottom: 6 },
  input: {
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 12, paddingHorizontal: 14, fontSize: 16, color: paper.ink,
  },
  // [액션] 시트의 유일한 커밋 = 프라이머리 코랄.
  saveBtn: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 16, marginTop: 18 },
});
