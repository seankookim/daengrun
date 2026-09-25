import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, FlatList, Image, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Avatar, Icon, Row } from '../../src/components/ui';
import { alertFail } from '../../src/lib/alert-fail';
import { checkSlot, CoursePatch, deleteGear, NOT_FOUND, deleteRunnerPhoto, fetchGear, fetchOfferedSlots, fetchProfileIdentity, fetchProfilePosts, fetchRunnerCourseHistory, fetchRunnerProfile, fetchRunnerReviewCount, GEAR_KINDS, GEAR_META, GearItem, GearKind, OfferedSlotRow, ProfileIdentity, ProfilePost, RunnerPublicProfile, uploadRunnerPhoto, upsertGear } from '../../src/lib/api';
import { PaperBtn } from '../../src/components/paper-btn';
import { PatchBadge } from '../../src/components/patch';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { MediaImage } from '../../src/lib/media';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { useNumFont } from '../../src/lib/fonts';
import { supabase } from '../../src/lib/supabase';
import { draft, session } from '../../src/store';
import { colors, paper, secTitle } from '../../src/theme';
import { kstCal, kstDateLabel, kstInstant, kstKey } from '../../src/lib/kst';
import { expectedDurationMs } from '../../src/lib/lateness';
// [0215] 후보 슬롯 규칙은 순수 모듈 한 벌 — 이 화면과 owner/reschedule 이 같은 것을 읽는다.
// 예전에는 이 루프가 두 파일에 글자 그대로 복제돼 있었고(그래서 한 번 드리프트했다) .cjs 스위트가
// 닿을 수 없었다. `test/offered-slots.test.cjs` 가 세 시간대에서 고정한다.
import { EXTRA_CHIP_KO, kstDayKey, OfferedSource, slotStartsForDay, windowsFromRules } from '../../src/lib/offered-slots';

// 공개 프로필 — **인스타 모양**(Sean 2026-08-27: 「for the tap for profile, yes make it like
// instagram」, 스크린샷이 모델). 머리 = 아이디 바 · 아바타 · 카운트 행 · 소개 · 편집 버튼,
// 그 아래 그리드. 러너면 그 아래로 스토어프런트(장비·코스·가능 시간·후기·예약)가 이어진다.
//
// 두 개의 읽기가 겹쳐 있고 서로 대신하지 못한다:
//   · `fetchProfileIdentity` — `profiles` 한 줄 (이름·아이디·동네·사진). 누구에게나 있다.
//   · `fetchRunnerProfile`   — `runners` 한 줄. 러너에게만 있고, 없으면 NOT_FOUND다.
// 그래서 러너가 아닌 사람의 프로필도 머리와 그리드까지는 성립한다. ⚠ 다만 **남의** 비러너
// 프로필은 RLS상 행 자체가 안 보인다 (0002: 본인 · 승인 러너 · 툼스톤만) — 그 경우 화면은
// '비공개'라고 말하고 아무것도 지어내지 않는다.
//
// 편집기는 이 화면 안의 시트가 아니라 **별도 라우트** `/profile/edit`다 (인스타식 행 목록,
// 아바타 행 없음 — Sean의 명시 제외). 예전에 여기 있던 편집 모달은 그 화면으로 접혔다:
// 편집기가 둘이면 규칙도 둘이 된다.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const DAY = '일월화수목금토';
const W = Dimensions.get('window').width;
// 3열 그리드: 좌우 1px 패딩 + 2px 갭 2개 = 6px를 빼야 딱 맞는다 (3·TILE + 4 + 2 = W).
const TILE = (W - 6) / 3;

// [HIG A6] Module scope so the array identity is stable across the grid's re-renders.
const PHOTO_A11Y_ACTIONS = [{ name: 'longpress', label: '사진 삭제' }];
// Same idiom, same reason, for the day strip's two accessibilityState values — a FlatList cell
// that is handed a freshly built object every render has nothing to compare against.
const A11Y_SELECTED = { selected: true };
const A11Y_UNSELECTED = { selected: false };

type GearSlotRow = { kind: GearKind; item: GearItem | null };
type DayCell = { cal: ReturnType<typeof kstCal>; label: string | undefined; d: number; w: string };

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

// [E6] 슬롯 시각은 기기 로컬이 아니라 **KST 벽시계**로 짓는다 — 서버 가용 규칙과 홀드 검증이
// KST 고정이라, 로컬로 지으면 UTC 시뮬레이터·해외 기기에서 화면이 07:30을 보여주고 16:30 KST를
// 저장한다. 산술은 src/lib/kst.ts 한 곳에 있다 (세 입구가 복제하던 것을 모았다 — 그 복제가
// E6 를 처음 고칠 때 셋 중 둘만 고치게 만든 원인이다). 테스트: app/test/run-kst-tests.sh

function availabilitySummary(rules: RunnerPublicProfile['availability']): string[] {
  if (rules.length === 0) return [];
  const key = (r: { startMin: number; endMin: number }) => `${r.startMin}-${r.endMin}`;
  if (rules.length === 7 && new Set(rules.map(key)).size === 1) {
    return [`매일 ${fmtMin(rules[0].startMin)}–${fmtMin(rules[0].endMin)}`];
  }
  return [...rules]
    .sort((a, b) => a.weekday - b.weekday)
    .map((r) => `${DAY[r.weekday]} ${fmtMin(r.startMin)}–${fmtMin(r.endMin)}`);
}

export default function RunnerProfileScreen() {
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();
  const nf = useNumFont(); // Oswald — 카운트 숫자 (lineHeight는 스타일에서 명시, ≥1.2× BUG A)
  const [p, setP] = useState<RunnerPublicProfile | null>(null);
  // 신원 한 줄 (profiles). 러너 행과 수명이 다르다 — 러너가 아닌 사람도 여기까지는 있다.
  const [who, setWho] = useState<ProfileIdentity | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // 러너 행 조회 결과. 'none' = 러너가 아님(스토어프런트를 통째로 안 그린다) · 'error' = 못 읽음.
  // 'none'과 'error'를 같은 침묵으로 다루지 않는다: error는 예약 문을 닫는 이유가 되면 안 되므로
  // 화면이 그 사실을 말한다 (settings.tsx의 base 섹션이 같은 갈래를 쓴다).
  const [runnerState, setRunnerState] = useState<'loading' | 'ok' | 'none' | 'error'>('loading');
  const [isMe, setIsMe] = useState(false);
  const [dayIdx, setDayIdx] = useState(0);
  // null = 확인 중 · 'error' = check failed (availability UNKNOWN — never painted 가능)
  const [slotOk, setSlotOk] = useState<Record<string, boolean | null | 'error'>>({});
  // [0215] 후보 슬롯의 달력. 네 상태를 구별한다 — 확인 중 · 서버 달력 · 그리드 폴백(0215 미배포)
  //        · 실패. 실패를 '시간 없음'으로 접으면 화면은 멀쩡해 보이고 아무도 원인을 못 찾는다.
  const [offered, setOffered] = useState<OfferedSlotRow[]>([]);
  const [offeredState, setOfferedState] = useState<'loading' | 'ready' | 'fallback' | 'error'>('loading');
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  // 러너 장비 로드아웃 (0019) — kind당 1슬롯, 사진이 곧 인증
  const [gear, setGear] = useState<GearItem[]>([]);
  const [gearBusy, setGearBusy] = useState<GearKind | null>(null);
  // 달린 코스 (0023) — 공개 경험 증명 패치 스트립
  const [courseHist, setCourseHist] = useState<CoursePatch[]>([]);
  // 게시물 그리드 (하이 피드, 0013) — 로딩 ≠ 실패 ≠ 진짜 0을 세 상태로 나눠 든다.
  const [posts, setPosts] = useState<'loading' | 'error' | ProfilePost[]>('loading');
  const [postTotal, setPostTotal] = useState<number | null>(null); // null = 아직 모름 (0이 아니다)
  const [reviewTotal, setReviewTotal] = useState<number | null>(null);
  // 그리드 탭 — 게시물(피드) · 갤러리(runners.photos). 둘 다 실소스이고 서로 다른 것을 말한다.
  const [tab, setTab] = useState<'posts' | 'gallery'>('posts');
  // 선택 → 하단 확인 바 → 진행 (즉시 이동 없음 — 결제 바와 같은 확인 패턴)
  const [selected, setSelected] = useState<{ key: string; label: string; start: Date } | null>(null);
  // 확인 바 스프링 등장 — 선택이라는 상태 변화를 모션으로.
  // ⚠ [react-doctor · lazy ref init] `useRef(new Animated.Value(90))` 였다 — useRef 의 인자는
  // **매 렌더마다** 평가되므로 첫 렌더 이후 버려질 Animated.Value 를 렌더 횟수만큼 만들고
  // 있었다 (값 자체는 첫 개가 계속 쓰이니 화면은 멀쩡하다 — 그래서 아무도 못 본다).
  const barYRef = useRef<Animated.Value | null>(null);
  if (barYRef.current === null) barYRef.current = new Animated.Value(90);
  const barY = barYRef.current;
  useEffect(() => {
    if (!selected) return;
    barY.setValue(90);
    Animated.spring(barY, { toValue: 0, useNativeDriver: true, friction: 9, tension: 70 }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected?.key]);

  // 게시물만 따로 다시 부를 수 있어야 한다 — 실패 타일의 '다시 시도'가 그 한 줄을 쓴다.
  const loadPosts = useCallback(() => {
    if (!id) return;
    setPosts('loading');
    fetchProfilePosts(id)
      .then((page) => { setPosts(page.posts); setPostTotal(page.total); })
      .catch(() => { setPosts('error'); setPostTotal(null); }); // 실패는 실패로 — 빈 그리드로 위장하지 않는다
  }, [id]);

  // 편집기(/profile/edit)에서 돌아오면 이름·아이디·동네·소개가 낡는다 → 포커스마다 다시 읽는다
  // (my.tsx·settings.tsx가 같은 이유로 같은 훅을 쓴다). 슬롯 가용성 재확인은 순수 읽기라 무해하고,
  // 오히려 화면에 머무는 동안 마감된 슬롯을 갱신해 준다.
  useFocusEffect(useCallback(() => {
    if (!id) { setErr('러너 정보가 없어요'); return; }
    // Never render `e.message` — PostgREST's English reached this screen verbatim on a bad or
    // retired profile id. Not-found and failure get different sentences.
    setErr(null);
    fetchProfileIdentity(id).then((w) => { setWho(w); setErr(null); }).catch((e) => {
      if (e?.message === NOT_FOUND) {
        // 0행 = 이 사람의 프로필이 나에게 공개돼 있지 않다 (RLS: 본인·승인 러너·툼스톤만).
        // '없는 사람'이라고 말하지 않는다 — 우리가 아는 것은 '못 본다'까지다.
        // ⚠ 이때는 **직전 값을 지운다**: 포커스마다 다시 읽으므로, 보이던 프로필이 안 보이게 된
        // 순간(탈퇴·러너 강등) 낡은 이름·사진을 계속 그리면서 '공개되어 있지 않아요'라고 말하게 된다.
        setWho(null); setP(null); setRunnerState('none');
        setErr('이 프로필은 공개되어 있지 않아요');
      } else {
        // 일시적 실패는 직전 실값을 유지하고 실패를 **함께** 말한다 (my.tsx recErr 모델).
        setErr('프로필을 불러오지 못했어요');
      }
    });
    fetchRunnerProfile(id)
      .then((r) => { setP(r); setRunnerState('ok'); })
      .catch((e) => { setP(null); setRunnerState(e?.message === NOT_FOUND ? 'none' : 'error'); });
    fetchGear(id).then(setGear).catch(() => {}); // 장비는 실패해도 프로필은 뜬다
    fetchRunnerCourseHistory(id).then(setCourseHist).catch(() => {}); // 0023 미배포 시 조용히 숨김
    fetchRunnerReviewCount(id).then(setReviewTotal).catch(() => setReviewTotal(null)); // 모르면 '—'
    loadPosts();
    supabase.auth.getUser().then(({ data }) => setIsMe(data.user?.id === id)).catch(() => {});
  }, [id, loadPosts]));

  const avail = p ? availabilitySummary(p.availability) : [];

  // 역할 기반 모드 분리 — 갤러리·장비 편집은 러너 모드 + 본인, 예약은 보호자 모드에서만.
  // (솔로 계정에서 두 모드가 겹쳐 보이던 혼선 수정, 2026-07-23)
  const canEdit = isMe && session.role === 'runner';
  const canBook = session.role === 'owner';
  // ⚠ '프로필 편집'은 canEdit가 아니라 isMe로 뜬다: 이름·아이디·동네는 러너의 것이 아니라
  // **계정의 것**이고, 보호자 모드로 자기 프로필을 봐도 자기 이름은 고칠 수 있어야 한다.

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const cal = kstCal(Date.now() + i * 86400_000);
    return { cal, label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined, d: cal.d, w: DAY[cal.wd] };
  }), []);

  const durMin = expectedDurationMs(draft.km ?? 5) / 60_000; // 한 벌: src/lib/lateness.ts

  // [0215] 서버의 달력을 읽는다 — 주간 그리드 ∪ 추가 근무 − 휴가. 0215 이전에는 이 화면이
  // `p.availability`(주간 그리드)만 열거했고, 그래서 러너가 연 **추가 근무 창을 보호자에게 내줄
  // 방법이 아예 없었다** (판정은 이미 true를 주고 있었는데 아무도 묻지 않았다 — review F2 ④).
  const runnerId = p?.profileId;
  const loadOffered = useCallback(() => {
    if (!runnerId || !canBook) return;
    setOfferedState('loading');
    fetchOfferedSlots(runnerId, kstDayKey(days[0].cal), kstDayKey(days[days.length - 1].cal))
      .then((rows) => {
        // null = 이 빌드가 0215보다 앞서 나갔다. 그때만 주간 그리드로 접는다 (0215 이전 동작 그대로).
        if (rows === null) { setOffered([]); setOfferedState('fallback'); return; }
        setOffered(rows); setOfferedState('ready');
      })
      .catch(() => { setOffered([]); setOfferedState('error'); });
  }, [runnerId, canBook, days]);
  useEffect(loadOffered, [loadOffered]);

  const daySlots = useMemo(() => {
    if (!p) return [] as { key: string; label: string; start: Date; source: OfferedSource }[];
    const day = days[dayIdx];
    const dayKey = kstDayKey(day.cal);
    // 확인 중·실패에는 후보를 만들지 않는다 — 아래 렌더가 그 셋을 '시간 없음'과 구별해서 말한다.
    const windows = offeredState === 'ready' ? offered
      : offeredState === 'fallback' ? windowsFromRules(p.availability, day.cal)
      : [];
    const out: { key: string; label: string; start: Date; source: OfferedSource }[] = [];
    const minStart = Date.now() + 2 * 3600_000;
    // ⚠ [codex 2026-08-21] 여기만 60분 고정이었다 — reschedule 에서 고친 드리프트가 세 번째
    // 예약 입구에 그대로 남아 있었다. 서버 수락 검증은 km×8+25 를 본다. 이제 두 화면이 같은
    // 순수 모듈을 부르므로 그 드리프트가 다시 생길 자리가 없다.
    slotStartsForDay(windows, dayKey, durMin).forEach((sl) => {
      const start = kstInstant(day.cal, Math.floor(sl.startMin / 60), sl.startMin % 60);
      if (start.getTime() < minStart) return;
      out.push({ key: start.toISOString(), label: fmtMin(sl.startMin), start, source: sl.source });
    });
    return out;
  }, [p, dayIdx, days, durMin, offered, offeredState]);

  useEffect(() => {
    if (!p || daySlots.length === 0) return;
    let alive = true;
    setSlotOk((prev) => {
      const next = { ...prev };
      daySlots.forEach((sl) => { if (!(sl.key in next)) next[sl.key] = null; });
      return next;
    });
    daySlots.forEach((sl) => {
      const end = new Date(sl.start.getTime() + durMin * 60_000);
      checkSlot(p.profileId, sl.start.toISOString(), end.toISOString())
        .then((ok) => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: ok })); })
        // [honesty P1 2026-08-11] failure used to paint the slot 가능 — a booking
        // against fabricated availability is a real-world no-show. Unknown stays unknown.
        .catch(() => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: 'error' })); });
    });
    return () => { alive = false; };
  }, [p, daySlots, durMin]);

  // single-slot recheck — the retry path for a failed availability check
  const recheckSlot = (sl: { key: string; start: Date }) => {
    if (!p) return;
    setSlotOk((m) => ({ ...m, [sl.key]: null }));
    const end = new Date(sl.start.getTime() + durMin * 60_000);
    checkSlot(p.profileId, sl.start.toISOString(), end.toISOString())
      .then((ok) => setSlotOk((m) => ({ ...m, [sl.key]: ok })))
      .catch(() => setSlotOk((m) => ({ ...m, [sl.key]: 'error' })));
  };

  const confirmSlot = (sl: { label: string; start: Date }) => {
    if (!p) return;
    haptic('medium');
    draft.preferredRunnerId = p.profileId;
    draft.preferredRunnerName = p.name;
    draft.scheduledAtIso = sl.start.toISOString();
    // ⚠ [codex 2026-08-21] instant 는 KST 로 옳게 지었는데 **라벨을 기기 로컬 getter 로** 다시
    // 조판했다. UTC 기기에서 07:30 KST 슬롯이 전날 날짜로 표시되고 owner/request 가 그 라벨을
    // 그대로 보여준다 — E6 가 이 화면에서만 절반 남아 있었다.
    draft.timeLabel = `${kstDateLabel(kstCal(sl.start.getTime()))} ${sl.label}`;
    router.push('/owner/request');
  };

  const addPhoto = async () => {
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploadingPhoto(true);
      const photos = await uploadRunnerPhoto(res.assets[0].base64);
      setP((prev) => (prev ? { ...prev, photos } : prev));
    } catch (e) {
      alertFail('업로드 실패', e);
    } finally {
      setUploadingPhoto(false);
    }
  };

  // 장비 슬롯 등록/교체 — 사진 필수 (사진이 곧 인증, 0019 도그마)
  const registerGear = async (kind: GearKind) => {
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setGearBusy(kind);
      const item = await upsertGear(kind, res.assets[0].base64);
      setGear((cur) => [...cur.filter((g) => g.kind !== kind), item]);
    } catch (e) {
      alertFail('장비 등록 실패', e);
    } finally {
      setGearBusy(null);
    }
  };

  const onGearSlot = (kind: GearKind) => {
    const existing = gear.find((g) => g.kind === kind);
    if (!existing) { registerGear(kind); return; }
    Alert.alert(GEAR_META[kind].name, '이 장비 슬롯을 어떻게 할까요?', [
      { text: '사진 교체', onPress: () => registerGear(kind) },
      {
        text: '삭제', style: 'destructive',
        onPress: async () => {
          try {
            await deleteGear(kind);
            setGear((cur) => cur.filter((g) => g.kind !== kind));
          } catch (e) { alertFail('삭제 실패', e); }
        },
      },
      { text: '취소', style: 'cancel' },
    ]);
  };

  const removePhoto = (url: string) => {
    Alert.alert('사진 삭제', '이 사진을 갤러리에서 삭제할까요?', [
      { text: '취소', style: 'cancel' },
      {
        text: '삭제', style: 'destructive',
        onPress: async () => {
          try {
            const photos = await deleteRunnerPhoto(url);
            setP((prev) => (prev ? { ...prev, photos } : prev));
          } catch (e) { alertFail('삭제 실패', e); }
        },
      },
    ]);
  };

  // 장비 스트립의 데이터. 「없는 데이터는 그리지 않는다」는 필터가 예전에는 renderItem 안에
  // 있었는데(`if (!item && !canEdit) return null`), FlatList 에서는 그 자리가 빈 셀을 만든다 —
  // 필터가 데이터 쪽으로 올라온 이유다. 결과 집합은 동일하다.
  const gearSlots = useMemo(
    () => GEAR_KINDS
      .map((kind) => ({ kind, item: gear.find((g) => g.kind === kind) ?? null }))
      .filter((g) => g.item !== null || canEdit),
    [gear, canEdit],
  );

  // ── 세 가로 스트립의 renderItem (react-doctor: rn-no-inline-flatlist-renderitem) ──
  // ⚠ renderGear 는 일부러 useCallback 이 아니다. onGearSlot 은 `gear` 를 읽는 평범한 함수라
  // 매 렌더 새로 만들어지고, 그걸 deps 에서 빼고 메모이제이션하면 셀이 **낡은 gear** 를 보고
  // 「사진 교체」와 「신규 등록」을 갈라버린다 — 눈에 안 보이는 동작 변경이다. 이름 붙은 참조라는
  // 점만으로 규칙은 만족하고, 다시 그리는 빈도는 예전 ScrollView + map 과 정확히 같다.
  const renderGear = ({ item: g }: { item: GearSlotRow }) => (
    <GearCell slot={g} disabled={!canEdit || gearBusy !== null} busy={gearBusy === g.kind} onPress={onGearSlot} />
  );
  // 이 둘은 진짜로 안정적이다 — setState 와 router 는 아이덴티티가 변하지 않는다.
  const onOpenCourse = useCallback((routeId: string) => { router.push(`/course/${routeId}`); }, []);
  const onPickDay = useCallback((i: number) => { setDayIdx(i); setSelected(null); }, []);
  const renderCourse = useCallback(
    ({ item: c }: { item: CoursePatch }) => <PatchCell course={c} onPress={onOpenCourse} />,
    [onOpenCourse],
  );
  const renderDay = useCallback(
    ({ item: d, index: i }: { item: DayCell; index: number }) =>
      <DayChip day={d} index={i} selected={dayIdx === i} onPress={onPickDay} />,
    [dayIdx, onPickDay],
  );

  // 갤러리 탭이 존재하는 조건 = 그 소스가 존재하는 조건. 없는 탭은 안 그린다 (죽은 버튼 금지).
  const hasGallery = !!p && (p.photos.length > 0 || canEdit);
  const activeTab = hasGallery ? tab : 'posts'; // 탭이 사라져도 상태가 유령 탭을 가리키지 않게
  const metaLine = [who?.district, p?.avgRating != null ? `★ ${p.avgRating}` : null].filter(Boolean).join(' · ');

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* ⚠ [react-doctor · dynamic contentContainerStyle] paddingBottom 이 `selected ? 140 : 40`
          이었다 — 새 스타일 오브젝트가 매 렌더 새 아이덴티티로 내려가 ScrollView 의 콘텐츠
          컨테이너가 매번 다시 계산됐다. 패딩은 정적으로 고정하고, 확인 바가 가리는 100pt 는
          **콘텐츠 끝의 스페이서**가 진다. 합은 예전과 같은 140/40 이다. */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={s.scrollPad}>
        {/* ---------- ① 아이디 바 — 인스타의 상단은 이름이 아니라 **계정 아이디**다 ---------- */}
        <Row style={[s.topBar, { paddingTop: insets.top }]}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 21, color: paper.ink }}>‹</Text>
          </Pressable>
          {/* handle이 null이면 이름으로 떨어지되 @를 붙이지 않는다 — 없는 아이디를 있는 척하지 않는다 (0074) */}
          <Text numberOfLines={1} style={s.topName}>
            {who ? (who.handle ? `@${who.handle}` : who.name) : '프로필'}
          </Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.failStrip}><Text style={s.failText}>{err}</Text></View>}
        {!err && !who && <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중…</Text></View>}

        {who && (
          <>
            {/* ---------- ② 머리: 아바타 · 카운트 행 · 소개 · 편집 ---------- */}
            <View style={s.headBlock}>
              <Row style={{ gap: 20 }}>
                <Avatar url={who.avatarUrl} char={who.name.slice(0, 1) || '?'} bg={paper.action} size={84} />
                {/* 카운트는 **실컬럼만**. 팔로워/팔로잉은 이 제품에 존재하지 않으므로 그 자리를 만들지 않는다.
                    반려견 수도 없다: `dogs`는 본인·예약된 러너만 읽는 RLS라 남의 프로필에서 셀 수 없다.
                    ⚠ 러너 두 칸은 runnerState가 'loading'일 때도 **자리를 지키고 '—'를 그린다** —
                    아직 모르는 것과 러너가 아닌 것은 다르고, 나중에 칸이 튀어나오면 앞의 것을 뒤의
                    것으로 보여준 셈이 된다. 'none'(러너 아님)·'error'(못 읽음)일 때만 칸이 없다. */}
                <Row style={{ flex: 1, justifyContent: 'space-around' }}>
                  <Count nf={nf} value={postTotal} label="게시물" />
                  {(runnerState === 'loading' || runnerState === 'ok') && (
                    <>
                      <Count nf={nf} value={p ? p.totalRuns : null} label="러닝" />
                      <Count nf={nf} value={reviewTotal} label="후기" />
                    </>
                  )}
                </Row>
              </Row>

              <Row style={{ gap: 7, marginTop: 14 }}>
                <Text style={s.realName}>{who.name}</Text>
                {p?.online && <View style={s.onlineDot} />}
              </Row>

              {p && (
                <Row style={{ gap: 6, marginTop: 7, flexWrap: 'wrap' }}>
                  <View style={s.pill}><Text style={s.pillTxt}>{p.tier}</Text></View>
                  {p.trainerCertified && <View style={s.pill}><Text style={s.pillTxt}>훈련사</Text></View>}
                </Row>
              )}

              {metaLine ? <Text style={s.metaLine}>{metaLine}</Text>
                : isMe ? <Text style={s.metaLineEmpty}>동네 미설정</Text> : null}

              {p?.bio ? <Text style={s.bio}>{p.bio}</Text>
                : isMe && runnerState === 'ok' ? <Text style={s.metaLineEmpty}>소개가 아직 없어요</Text> : null}

              {p && p.specialties.length > 0 && (
                <Row style={{ gap: 6, marginTop: 9, flexWrap: 'wrap' }}>
                  {p.specialties.map((sp) => (
                    <View key={sp} style={s.specChip}><Text style={s.specChipTxt}>{sp}</Text></View>
                  ))}
                </Row>
              )}

              {/* 본인에게만 뜨는 문. 세컨더리 면(wash + 코랄 라인 + actionInk) — 이 화면의 프라이머리는 예약이다. */}
              {isMe && (
                <PaperBtn label="프로필 편집" variant="secondary" onPress={() => router.push('/profile/edit')} style={{ marginTop: 14 }} />
              )}

              {/* 러너 행을 못 읽었을 때: 침묵하면 '러너가 아닌 사람'과 구별되지 않는다 */}
              {runnerState === 'error' && (
                <Text style={s.metaLineEmpty}>러너 정보를 불러오지 못했어요 — 예약 정보가 비어 있을 수 있어요</Text>
              )}
            </View>

            {/* ---------- ③ 그리드 — 게시물(하이 피드) · 갤러리(러너 사진) ---------- */}
            {hasGallery && (
              <Row style={s.tabs}>
                {(['posts', 'gallery'] as const).map((t) => (
                  <Pressable
                    key={t}
                    onPress={() => setTab(t)}
                    style={[s.tab, activeTab === t && s.tabOn]}
                    accessibilityRole="tab"
                    accessibilityState={{ selected: activeTab === t }}
                  >
                    <Text style={[s.tabTxt, activeTab === t && s.tabTxtOn]}>{t === 'posts' ? '게시물' : '갤러리'}</Text>
                  </Pressable>
                ))}
              </Row>
            )}

            {activeTab === 'posts' && (
              <View style={s.gridBlock}>
                {/* 로딩 ≠ 실패 ≠ 진짜 0 — 세 문장이 서로 다르다 */}
                {posts === 'loading' && <View style={s.gridState}><Text style={s.emptyText}>게시물을 불러오는 중…</Text></View>}
                {posts === 'error' && (
                  <Pressable onPress={loadPosts} style={s.failStrip} accessibilityRole="button">
                    <Text style={s.failText}>게시물을 불러오지 못했어요</Text>
                    <Text style={s.failRetry}>눌러서 다시 시도</Text>
                  </Pressable>
                )}
                {Array.isArray(posts) && posts.length === 0 && (
                  <View style={s.gridState}>
                    <Text style={s.emptyText}>
                      {isMe ? '아직 공유한 게시물이 없어요\n러닝을 마치면 피드에 올릴 수 있어요' : '아직 게시물이 없어요'}
                    </Text>
                  </View>
                )}
                {Array.isArray(posts) && posts.length > 0 && (
                  <>
                    {/* 타일은 누를 수 없다 — 게시물 하나를 여는 라우트가 이 앱에 없다 (죽은 버튼 금지) */}
                    <View style={s.grid}>
                      {posts.map((post) => (
                        post.photoUrl ? (
                          <MediaImage key={post.id} source={post.photoUrl} style={s.tile} />
                        ) : (
                          <View key={post.id} style={[s.tile, s.textTile]}>
                            {post.km != null && <Text style={[s.textTileKm, nf]}>{post.km}km</Text>}
                            {post.body ? <Text numberOfLines={3} style={s.textTileBody}>{post.body}</Text> : null}
                            <Text style={s.textTileWhen}>{post.when}</Text>
                          </View>
                        )
                      ))}
                    </View>
                    {postTotal != null && postTotal > posts.length && (
                      <Text style={s.gridNote}>최근 {posts.length}개만 보여요</Text>
                    )}
                  </>
                )}
              </View>
            )}

            {/* ---------- 갤러리: 엣지-투-엣지 3열 (편집은 러너 모드 + 본인만) ---------- */}
            {activeTab === 'gallery' && p && (
              <View style={s.gridBlock}>
                <View style={s.grid}>
                  {p.photos.map((url) => (
                    <Pressable
                      key={url}
                      onLongPress={canEdit ? () => removePhoto(url) : undefined}
                      // [HIG A6] The hint was already here and was already honest — what was
                      // missing is the ACTION, so the hint described a gesture with no accessible
                      // route to it. `removePhoto` opens its own 사진 삭제 confirm, so the rotor
                      // entry lands on the same two-step path a long press does.
                      onAccessibilityAction={canEdit ? () => removePhoto(url) : undefined}
                      accessibilityActions={canEdit ? PHOTO_A11Y_ACTIONS : undefined}
                      accessibilityRole={canEdit ? 'imagebutton' : 'image'}
                      accessibilityLabel="러너 사진"
                      accessibilityHint={canEdit ? '길게 누르면 삭제해요' : undefined}
                    >
                      <Image source={{ uri: url }} style={[s.tile, { backgroundColor: '#ECEAE2' }]} />
                    </Pressable>
                  ))}
                  {canEdit && (
                    <Pressable onPress={addPhoto} disabled={uploadingPhoto} style={[s.tile, s.addTile]} accessibilityRole="button">
                      <Text style={{ fontSize: 26, color: paper.actionInk }}>{uploadingPhoto ? '…' : '＋'}</Text>
                      <Text style={{ fontSize: 15, color: paper.dim, marginTop: 2 }}>{uploadingPhoto ? '올리는 중' : '사진 추가'}</Text>
                    </Pressable>
                  )}
                </View>
                {canEdit && p.photos.length > 0 && <Text style={s.gridNote}>길게 눌러 삭제</Text>}
              </View>
            )}

            {/* ═══ 여기서부터는 러너 스토어프런트다 — `runners` 행이 있는 사람에게만 존재한다.
                 (자기소개·특기는 인스타 머리로 올라갔다 — 소개가 두 군데 있으면 한 군데는 낡는다.) ═══ */}
            {p && (
              <>
            {/* ---------- 러너 기록 — 카운트 행에 안 들어간 실측치 ---------- */}
            <View style={s.section}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Stat nf={nf} value={`${p.totalKm}km`} label="누적 거리" />
                <View style={s.statDiv} />
                {/* null = 기록 없음 — 지어낸 7'00" 대신 사실을 말한다 (api.ts pace null-honesty) */}
                <Stat nf={nf} value={p.paceLabel ?? '기록 전'} label="평균 페이스" />
                <View style={s.statDiv} />
                {/* ⚠ [2026-09-15] 널 토큰이 「신규」였다. 「신규」는 **없음의 표시가 아니라 그 러너에
                    대한 적극적 주장**이고, `respond_rate_pct` 는 이 제품 어디에서도 쓰이지 않는다 —
                    0001:74 가 선언하고 0061:49 가 insert 마다 null 로 못 박고 0057:501 이 자가 수정을
                    막는데, 값을 넣는 마이그레이션도 엣지 함수도 없다. 즉 **모든 러너가** null 이고,
                    바로 왼쪽 두 칸이 「누적 거리 128km · 러닝 34회」를 말하는 그 화면에서 이 칸만
                    「신규」라고 적고 있었다. 모르는 것은 모른다고 말한다 — 같은 Row 의 평균 페이스가
                    이미 쓰는 어휘('기록 전')를 그대로 쓴다. */}
                <Stat nf={nf} value={p.respondRate != null ? `${p.respondRate}%` : '기록 전'} label="응답률" />
              </Row>
            </View>

            {/* ---------- 러닝 장비 로드아웃 (0019) — 슬롯제, 사진이 곧 인증 ---------- */}
            {(gear.length > 0 || canEdit) && (
              <View style={s.section}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Text style={s.sectionTitle}>러닝 장비</Text>
                  <Text style={{ fontSize: 15, color: colors.dim }}>사진으로 인증된 장비예요</Text>
                </Row>
                {/* [react-doctor · list virtualization] 가로 스트립은 FlatList 다. 필터는 이제
                    **데이터 쪽**에서 한다 (gearSlots) — renderItem 이 null 을 돌려주면 FlatList 는
                    높이 0 짜리 빈 셀을 만들고 gap 은 그대로 먹는다. 그리는 결과는 같다. */}
                <FlatList
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={s.strip8}
                  data={gearSlots}
                  extraData={gearBusy}
                  keyExtractor={gearKey}
                  renderItem={renderGear}
                />
                {canEdit && (
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 8 }}>
                    슬롯을 눌러 장비 사진을 올리면 매칭 카드에 인증 배지로 보여요
                  </Text>
                )}
              </View>
            )}

            {/* ---------- 달린 코스 (0023) — 경험 증명 패치 스트립 (장비 인증 옆 신뢰 신호) ---------- */}
            {courseHist.length > 0 && (
              <View style={s.section}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Text style={s.sectionTitle}>달린 코스</Text>
                  <Text style={{ fontSize: 15, color: colors.dim }}>완주 기록으로 자동 집계돼요</Text>
                </Row>
                {/* [react-doctor · list virtualization] 이 스트립은 길이에 상한이 없다 (완주한
                    코스 수만큼 자란다) — 세 리스트 중 가상화가 실제로 일을 하는 유일한 곳이다. */}
                <FlatList
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={s.strip12}
                  data={courseHist}
                  keyExtractor={courseKey}
                  renderItem={renderCourse}
                />
              </View>
            )}

            {/* ---------- 가능 시간 + 슬롯 예약 ---------- */}
            <View style={s.section}>
              <Text style={s.sectionTitle}>러닝 가능 시간</Text>
              {avail.length === 0 ? (
                <Text style={{ fontSize: 15, color: colors.dim }}>가용 시간 미설정 — 오픈 매칭으로만 예약할 수 있어요</Text>
              ) : !canBook ? (
                <>
                  {avail.map((line) => (
                    <Text key={line} style={{ fontSize: 15, color: '#3d453d', lineHeight: 24 }}>{line}</Text>
                  ))}
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 8 }}>
                    보호자에게는 여기가 시간대 선택 그리드로 보여요 — 예약은 보호자 모드에서
                  </Text>
                </>
              ) : (
                <>
                  <Text style={{ fontSize: 15, color: colors.dim, marginBottom: 10 }}>{avail.join(' · ')}</Text>
                  {/* [react-doctor · list virtualization] extraData={dayIdx} 는 장식이 아니다 —
                      FlatList 의 셀은 props 가 그대로면 다시 그리지 않으므로, 선택 표시가 바뀌는
                      값을 여기로 넘기지 않으면 칩이 예전 선택을 그린 채로 남는다. */}
                  <FlatList
                    horizontal
                    showsHorizontalScrollIndicator={false}
                    contentContainerStyle={s.strip8flat}
                    data={days}
                    extraData={dayIdx}
                    keyExtractor={dayKey}
                    renderItem={renderDay}
                  />
                  {/* [0215] 네 상태를 구별해서 말한다. '확인 중'과 '불러오지 못함'을 '시간이
                      없어요'로 접으면 화면은 멀쩡해 보이고 보호자는 러너가 쉬는 줄 안다. */}
                  {offeredState === 'loading' ? (
                    <Text style={{ fontSize: 15, color: colors.dim, marginTop: 12 }}>가능한 시간을 확인하고 있어요…</Text>
                  ) : offeredState === 'error' ? (
                    <View style={{ marginTop: 12 }}>
                      <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>가능한 시간을 불러오지 못했어요</Text>
                      <Pressable onPress={loadOffered} accessibilityRole="button" style={{ paddingVertical: 8 }}>
                        <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
                      </Pressable>
                    </View>
                  ) : daySlots.length === 0 ? (
                    <Text style={{ fontSize: 15, color: colors.dim, marginTop: 12 }}>이 날은 가능한 시간이 없어요</Text>
                  ) : (
                    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
                      {daySlots.map((sl) => {
                        const ok = slotOk[sl.key];
                        // An unseeded key (undefined) is as unknown as a seeded null: the seeding effect
                        // runs after paint, so a new day's chips render one frame before it. Both read
                        // as 확인 중 — an unknown slot is never painted 가능.
                        const checking = ok === null || ok === undefined;
                        const sel = selected?.key === sl.key;
                        return (
                          <Pressable
                            key={sl.key}
                            disabled={ok === false}
                            onPress={() => {
                              if (ok === 'error') { recheckSlot(sl); return; } // unknown never books — retry the check
                              if (ok !== true) return; // still verifying — selectable only once confirmed
                              setSelected(sel ? null : sl);
                            }}
                            accessibilityRole="radio"
                            accessibilityState={{ selected: sel, disabled: ok === false }}
                            // [ui/paper-polish] State is explicit paint, never an alpha trick (theme.ts button
                            // matrix): closed = the disabled face (disabledFill) with faint words;
                            // checking (null OR not-yet-seeded undefined) = a dim label on the
                            // normal face. The other states' words and tints are unchanged.
                            style={[
                              s.slotChip,
                              ok === false && s.slotChipClosed,
                              sel && { backgroundColor: paper.ink, borderColor: paper.ink },
                            ]}
                          >
                            <Text style={{ fontSize: 15, fontWeight: '800', color: sel ? '#fff' : ok === false ? paper.faint : checking ? paper.dim : paper.ink }}>{sl.label}</Text>
                            <Text style={{ fontSize: 15, marginTop: 1, color: sel ? colors.volt : ok === false ? paper.faint : ok === 'error' ? paper.critical : checking ? paper.dim : '#5a7a3c' }}>
                              {sel ? '선택됨 ✓' : ok === false ? '마감' : ok === 'error' ? '확인 실패 · 다시 시도' : checking ? '확인 중' : '가능'}
                            </Text>
                            {/* [0215→0221] 추가 근무 칩 — 서버가 준 **segments** 에 묶는다,
                                추측하지 않는다. 주간 그리드(합친 것)가 슬롯 전체를 덮지 않을 때만
                                뜬다 (offered-slots.ts 의 라벨 규칙). 0221 이전에는 서버 행의
                                source 를 그대로 썼는데, 합쳐진 span 은 한 낱말로 답할 수 없다. */}
                            {sl.source === 'extra' && (
                              <Text style={{ fontSize: 15, marginTop: 1, fontWeight: '700', color: sel ? colors.volt : paper.ink }}>
                                {EXTRA_CHIP_KO}
                              </Text>
                            )}
                          </Pressable>
                        );
                      })}
                    </View>
                  )}
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 10 }}>
                    시간을 고르면 코스·옵션 선택으로 이어져요
                  </Text>
                </>
              )}
            </View>

            {/* ---------- 후기 ---------- */}
            <View style={s.section}>
              <Text style={s.sectionTitle}>
                보호자 후기{p.avgRating != null ? ` · ★ ${p.avgRating}` : ''}
              </Text>
              {p.reviews.length === 0 && (
                <Text style={{ fontSize: 15, color: colors.dim }}>아직 후기가 없어요 — 첫 러닝의 주인공이 되어보세요</Text>
              )}
              {/* ⚠ [react-doctor · index key] key={i} 였다. 행 ID 를 쓰고 싶지만 이 payload 에는
                  없다 — `fetchRunnerProfile` 의 reviews select 가 `rating, note, tags, created_at`
                  만 읽고 `id` 를 싣지 않는다 (api.ts:2910, 이번 슬라이스의 소유 파일이 아니다).
                  그래서 내용에서 키를 짓는다: 같은 날·같은 별점·같은 본문이면 같은 후기다.
                  ⚠ 이 리스트는 FlatList 로 바꾸지 않는다 — 세로 ScrollView 안의 세로 FlatList 는
                  가상화 중첩 경고를 만들고, 서버가 limit(5) 로 상한을 이미 걸어둔다. */}
              {p.reviews.map((v, i) => (
                <View key={`${v.when}|${v.rating ?? '-'}|${v.note ?? ''}`} style={[s.reviewRow, i > 0 && { borderTopWidth: 1, borderTopColor: '#f0eee3' }]}>
                  <Row style={{ justifyContent: 'space-between' }}>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: '#5a7a3c' }}>
                      {v.rating != null ? '★'.repeat(v.rating) : '후기'}
                    </Text>
                    <Text style={{ fontSize: 15, color: colors.dim }}>{v.when}</Text>
                  </Row>
                  {v.note && <Text style={{ fontSize: 15, color: '#3d453d', marginTop: 4, lineHeight: 20.5 }}>{v.note}</Text>}
                  {v.tags.length > 0 && (
                    <Row style={{ gap: 5, marginTop: 5, flexWrap: 'wrap' }}>
                      {v.tags.map((t) => (
                        <Text key={t} style={{ fontSize: 15, color: colors.dim }}>#{t}</Text>
                      ))}
                    </Row>
                  )}
                </View>
              ))}
            </View>

            {/* ---------- CTA (보호자 모드만) ---------- */}
            <View style={{ paddingHorizontal: 12 }}>
              {canBook ? (
                <>
                  <Pressable
                    /* [Sean 2026-08-26 press behaviour] filled primary = a physical key. This one
                       had no press state at all — a coral plate that never acknowledged a tap. */
                    style={({ pressed }) => [s.cta, pressed ? s.ctaDown : s.ctaLip]}
                    accessibilityRole="button"
                    onPress={() => {
                      draft.preferredRunnerId = p.profileId;
                      draft.preferredRunnerName = p.name;
                      router.push('/owner/request');
                    }}
                  >
                    <Text style={{ fontSize: 17, fontWeight: '800', color: '#fff' }}>{p.name} 러너와 예약하기</Text>
                    {/* [§E.5] 지명은 결제가 아니라 **홀드 직후** 나간다 (request.tsx의 pay()
                        ③번 걸음). "결제 후"는 더 이상 존재하지 않는 단계를 가리켰다. */}
                    <Text style={{ fontSize: 15, color: '#FFE7E0', marginTop: 2 }}>예약하면 이 러너에게 지명 요청이 먼저 전달돼요</Text>
                  </Pressable>
                  {/* [honesty 2026-08-20 · runner journey T4] 여기 '채팅 문의' 고스트 버튼이 있었고,
                      누르면 「러너와의 채팅은 예약 후 열려요 (실시간 채팅 준비 중)」 알럿 하나가
                      전부였다. 두 가지가 틀렸다.
                      ① 실시간 채팅은 **이미 출시돼 있다** — app/chat.tsx가 subscribeMessages로
                         실배달을 받고 사진까지 보낸다 (api.ts:2584). 있는 기능을 없다고 말하면
                         보호자는 예약 후에도 그 문을 찾지 않는다.
                      ② 버튼의 유일한 효과가 '안 된다'는 알럿이었다 — 죽은 버튼 금지법이 이 레포에서
                         이미 같은 이유로 픽업 지도 숏컷을 은퇴시켰다 (runner/home.tsx:92-93).
                      이 자리에서 진짜 채팅을 열 방법은 없다: 스레드는 예약 단위이고, chat_threads
                      INSERT는 러너가 수락하기 전까지 정책에서 막힌다 (0114, chat.tsx:29-33의
                      'preaccept' 상태). 이 화면에는 '이 러너와의 예약' 같은 것이 존재하지 않는다.
                      그래서 없는 라우트를 지어내는 대신, 문을 내리고 **참인 사실 한 줄**만 남긴다 —
                      언제 열리는지 알면 보호자는 그때 문을 찾을 수 있다. */}
                  <Text style={{ fontSize: 15, lineHeight: 19, color: colors.dim, textAlign: 'center', marginTop: 10 }}>
                    채팅은 이 러너가 예약을 수락하면 열려요
                  </Text>
                </>
              ) : (
                <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 14 }}>
                  {isMe ? '내 공개 프로필 — 사진은 갤러리 탭에서, 이름·소개는 프로필 편집에서' : '예약은 보호자 모드에서 가능해요'}
                </Text>
              )}
            </View>
              </>
            )}

            {/* 러너 행이 없는 사람의 프로필은 여기서 끝난다 — 없는 스토어프런트를 만들지 않는다. */}
          </>
        )}
        {/* 확인 바 자리. 바가 떠 있을 때만 높이를 갖는다 — s.scrollPad 의 40 과 합쳐 140. */}
        <View style={{ height: selected ? 100 : 0 }} />
      </ScrollView>

      {/* 스크롤 화면이므로 ScrollView 뒤에 — 그래야 스트립이 콘텐츠 위에 그려진다 (status-bar-cover.tsx 배치법) */}
      <StatusBarCover />

      {/* [2026-08-27] 여기 있던 프로필 편집 모달은 `/profile/edit`로 접혔다 (Sean의 인스타 편집기
          모델: 행 목록, 아바타 행 없음). 같은 필드를 두 화면에서 고칠 수 있으면 규칙도 두 벌이 된다. */}

      {/* ---------- 슬롯 확인 바 — 결제 바와 같은 확인 패턴 ---------- */}
      {selected && p && canBook && (
        <Animated.View style={[s.confirmBar, { paddingBottom: Math.max(insets.bottom, 30), transform: [{ translateY: barY }] }]}>
          <View style={{ flex: 1 }}>
            {/* ⚠ [2026-08-27] KST 로 읽는다. start 는 위에서 kstInstant 로 **옳게** 지어졌는데 이 줄만
                기기 로컬 getter 로 되읽고 있었다 — 예약은 맞고 확인 바의 라벨만 틀리는 모양이라,
                서울이 아닌 기기에서 이 줄과 confirmSlot 이 draft 에 쓰는 라벨이 서로 달랐다.
                두 줄이 이제 같은 kstDateLabel 하나를 쓴다. */}
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>
              {kstDateLabel(kstCal(selected.start.getTime()))} {selected.label}
            </Text>
            <Text style={{ fontSize: 15, color: '#b8c4ae', marginTop: 2 }}>
              {p.name} 러너 · 코스·옵션 선택으로 이어져요
            </Text>
          </View>
          <Pressable onPress={() => confirmSlot(selected)} style={({ pressed }) => [s.confirmBtn, pressed ? s.ctaDown : s.ctaLip]} accessibilityRole="button">
            <Text style={{ fontSize: 16, fontWeight: '800', color: '#fff' }}>이 시간으로 ›</Text>
          </Pressable>
        </Animated.View>
      )}
    </View>
  );
}

// ── 세 가로 스트립의 행 컴포넌트 (react-doctor: rn-list-callback-per-row /
//    rn-no-inline-object-in-list-item) ──
// renderItem **안에서** 만들던 onPress 클로저와 스타일 오브젝트가 여기로 내려왔다. ScrollView +
// map 시절에도 같은 할당이 있었지만(규칙이 리스트 밖에서는 안 켜질 뿐이다), FlatList 의 셀은
// props 아이덴티티로 다시 그릴지를 정하므로 여기서는 실제로 값을 한다. 그리는 결과는 동일 —
// 조건부 스타일은 인라인 오브젝트 대신 **정적 스타일 두 개 중 하나**를 고르는 형태로만 바뀌었다.
const gearKey = (g: GearSlotRow) => g.kind;
const courseKey = (c: CoursePatch) => c.routeId;
const dayKey = (d: DayCell) => kstKey(d.cal);

function GearCell({ slot, disabled, busy, onPress }: {
  slot: GearSlotRow; disabled: boolean; busy: boolean; onPress: (kind: GearKind) => void;
}) {
  const meta = GEAR_META[slot.kind];
  const press = useCallback(() => onPress(slot.kind), [onPress, slot.kind]);
  return (
    <Pressable disabled={disabled} onPress={press} style={[s.gearSlot, !slot.item && s.gearSlotEmpty]} accessibilityRole="button">
      {slot.item?.photoUrl ? (
        /* `source={{ uri }}` 는 그대로 둔다 — Image 의 계약이 오브젝트이고, MediaImage 로
           바꾸는 것은 프레젠테이션이 아니라 로딩 경로를 바꾸는 일이다 */
        <Image source={{ uri: slot.item.photoUrl }} style={s.gearPhoto} />
      ) : (
        <View style={s.gearPhotoEmpty}>
          {busy || !slot.item
            ? <Text style={s.gearGlyph}>{busy ? '…' : '＋'}</Text>
            : <Icon name={meta.icon} glyph="●" size={24} color="#8a8672" />}
        </View>
      )}
      <Text style={[s.gearName, slot.item ? s.gearNameOn : s.gearNameOff]}>{meta.name}</Text>
      {slot.item?.verified ? (
        <View style={s.gearBadge}><Text style={s.gearBadgeText}>✓ 인증</Text></View>
      ) : (
        <Text style={s.gearHint}>{meta.hint}</Text>
      )}
    </Pressable>
  );
}

function PatchCell({ course, onPress }: { course: CoursePatch; onPress: (routeId: string) => void }) {
  const press = useCallback(() => onPress(course.routeId), [onPress, course.routeId]);
  return (
    <Pressable onPress={press} style={s.patchCell} accessibilityRole="button">
      <PatchBadge km={course.km} name={course.name} grade={course.grade} size={64} />
      <Text numberOfLines={1} style={s.patchName}>{course.name}</Text>
      <Text style={s.patchCount}>×{course.count} 완주</Text>
    </Pressable>
  );
}

function DayChip({ day, index, selected, onPress }: {
  day: DayCell; index: number; selected: boolean; onPress: (i: number) => void;
}) {
  const press = useCallback(() => onPress(index), [onPress, index]);
  return (
    <Pressable onPress={press} style={[s.dayChip, selected && s.dayChipOn]}
      accessibilityRole="radio" accessibilityState={selected ? A11Y_SELECTED : A11Y_UNSELECTED}
      accessibilityLabel={`${day.label ? `${day.label} ` : ''}${day.d}일 ${day.w}요일`}>
      <Text style={selected ? s.dayWOn : s.dayW}>{day.w}</Text>
      <Text style={selected ? s.dayDOn : s.dayD}>{day.d}</Text>
      {day.label && <Text style={selected ? s.dayTagOn : s.dayTag}>{day.label}</Text>}
    </Pressable>
  );
}

// 인스타 카운트 한 칸. value가 null = **아직 모른다** — 0을 그리지 않는다 (로딩 ≠ 0 ≠ 빈 값).
function Count({ nf, value, label }: { nf: TextStyle | null; value: number | null; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={[s.countNum, nf]}>{value ?? '—'}</Text>
      <Text style={s.countLabel}>{label}</Text>
    </View>
  );
}

// 러너 실측치 한 칸 (누적 거리·평균 페이스·응답률). 값은 이미 문장으로 지어져 들어온다.
function Stat({ nf, value, label }: { nf: TextStyle | null; value: string; label: string }) {
  return (
    <View style={{ flex: 1, alignItems: 'center' }}>
      <Text style={[s.statVal, nf]}>{value}</Text>
      <Text style={s.countLabel}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  // ── 정적 리스트 스타일 (react-doctor) — 인라인 오브젝트는 매 렌더 새 아이덴티티다 ──
  // scrollPad 의 40 + 확인 바 스페이서 100 = 예전의 140. 값은 바뀌지 않았고 주인만 바뀌었다.
  scrollPad: { paddingBottom: 40 },
  strip8: { gap: 8, paddingTop: 2 },
  strip12: { gap: 12, paddingTop: 2 },
  strip8flat: { gap: 8 },
  patchCell: { alignItems: 'center', width: 76 },
  // ── 페이퍼 월드: 흰 캔버스 · 솔리드 코랄 헤어라인 · 샤프 코너 (DESIGN.md §2/§4) ──
  topBar: { justifyContent: 'space-between', paddingHorizontal: 12, paddingBottom: 12 },
  backBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  topName: { flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '800', color: paper.ink },
  headBlock: { paddingHorizontal: 15, paddingBottom: 18, borderBottomWidth: 1, borderBottomColor: paper.line },
  countNum: { fontSize: 20, lineHeight: 25, fontWeight: '700', color: paper.ink }, // lineHeight ≥1.2× — Oswald BUG A
  statVal: { fontSize: 17, lineHeight: 21, fontWeight: '700', color: paper.ink },
  countLabel: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 2 },
  realName: { fontSize: 18, fontWeight: '800', color: paper.ink },
  onlineDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: paper.ready, alignSelf: 'center' },
  pill: { borderWidth: 1, borderColor: paper.line, paddingVertical: 3, paddingHorizontal: 8 },
  pillTxt: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.actionInk },
  metaLine: { fontSize: 15, lineHeight: 21, color: paper.text, marginTop: 6 },
  metaLineEmpty: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 6 },
  bio: { fontSize: 15.5, lineHeight: 23, color: paper.text, marginTop: 8 },
  // ── 그리드 탭 ──
  tabs: { borderBottomWidth: 1, borderBottomColor: paper.line },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 12, borderBottomWidth: 2, borderBottomColor: 'transparent' },
  tabOn: { borderBottomColor: paper.action },
  tabTxt: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.dim },
  tabTxtOn: { color: paper.ink },
  // ── 그리드 ──
  gridBlock: { borderBottomWidth: 1, borderBottomColor: paper.line },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 2, padding: 1 },
  tile: { width: TILE, height: TILE },
  textTile: { borderWidth: 1, borderColor: paper.line, padding: 8, justifyContent: 'flex-end', gap: 3 },
  textTileKm: { fontSize: 16, lineHeight: 20, fontWeight: '700', color: paper.ink },
  textTileBody: { fontSize: 15, lineHeight: 19, color: paper.text },
  textTileWhen: { fontSize: 15, lineHeight: 19, color: paper.dim },
  gridState: { paddingVertical: 34, paddingHorizontal: 20, alignItems: 'center' },
  gridNote: { fontSize: 15, lineHeight: 19, color: paper.dim, textAlign: 'center', paddingVertical: 10 },
  // ── 라우드 페일 (F1.2) — 조용한 catch → 행복한 UI 금지 ──
  failStrip: { margin: 15, padding: 14, backgroundColor: paper.criticalWash, borderWidth: 1, borderColor: paper.critical },
  failText: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },
  failRetry: { fontSize: 15, lineHeight: 20, color: paper.critical, marginTop: 3 },
  section: { backgroundColor: paper.canvas, paddingHorizontal: 15, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: paper.line },
  // DESIGN.md §3b — the one section-title grammar (theme.secTitle), not a local 15.5/900.
  sectionTitle: { ...secTitle, marginBottom: 8 },
  statDiv: { width: 1, alignSelf: 'stretch', backgroundColor: paper.line },
  // specChip, gearSlot/gearSlotEmpty, gearPhoto/gearPhotoEmpty, dayChip and slotChip moved to paper
  // grammar in ui/paper-polish: radius 0, neutral #EEEEEE borders, canvas faces, disabledFill for
  // empty wells. NOT converted, still open for Sean: gearBadge (#DDF0A6 green pill, radius 99) and
  // the forest-green #3d5a2b of specChipTxt and gearBadgeText.
  specChip: { backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 4, paddingHorizontal: 10 },
  specChipTxt: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: '#3d5a2b' },
  // 장비 로드아웃 슬롯 (0019)
  gearSlot: { width: 104, backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', padding: 8, alignItems: 'center' },
  // 아래 열두 개는 예전에 renderItem 안의 인라인 오브젝트였다 — 값은 한 글자도 바뀌지 않았고
  // 조건부였던 것만 정적 스타일 쌍(On/Off)으로 갈라졌다.
  gearPhotoEmpty: { width: 88, height: 66, borderRadius: 0, alignItems: 'center', justifyContent: 'center', backgroundColor: paper.disabledFill },
  gearGlyph: { fontSize: 27 },
  gearName: { fontSize: 15, fontWeight: '800', marginTop: 6 },
  gearNameOn: { color: paper.ink },
  gearNameOff: { color: colors.dim },
  gearBadgeText: { fontSize: 15, fontWeight: '900', color: '#3d5a2b' },
  gearHint: { fontSize: 15, color: colors.dim, marginTop: 3 },
  patchName: { fontSize: 15, fontWeight: '800', color: paper.ink, marginTop: 6 },
  patchCount: { fontSize: 15, color: colors.dim, marginTop: 1 },
  dayChipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  dayW: { fontSize: 15, color: colors.dim },
  dayWOn: { fontSize: 15, color: '#b8c4ae' },
  dayD: { fontSize: 17, fontWeight: '900', color: paper.ink },
  dayDOn: { fontSize: 17, fontWeight: '900', color: '#fff' },
  // 「오늘」/「내일」 — Korean, so it takes the 15pt floor (DESIGN.md §3); it was 9pt until
  // ui/paper-polish. Dim on the canvas chip, canvas on the ink (selected) chip.
  dayTag: { fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.dim },
  dayTagOn: { fontSize: 15, lineHeight: 18, fontWeight: '700', color: paper.canvas },
  gearSlotEmpty: { borderStyle: 'dashed', backgroundColor: paper.canvas },
  gearPhoto: { width: 88, height: 66, borderRadius: 0, backgroundColor: paper.disabledFill },
  gearBadge: { backgroundColor: '#DDF0A6', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 8, marginTop: 3 },
  reviewRow: { paddingVertical: 10 },
  dayChip: { width: 46, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', backgroundColor: paper.canvas, alignItems: 'center', paddingVertical: 8, gap: 1 },
  slotChip: { width: '22.5%', backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', paddingVertical: 9 },
  slotChipClosed: { backgroundColor: paper.disabledFill },
  addTile: { backgroundColor: paper.wash, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  // 프라이머리 액션 = paper.action (흰 라벨 4.84:1). 볼트 라임 은퇴 — 이 화면은 페이퍼 월드다.
  cta: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  // [Sean 2026-08-26 press behaviour] shared by both action-filled buttons on this screen (the
  // booking CTA and the confirm bar's 이 시간으로). Rest keeps a 4px lip in the pressed fill;
  // press hands 3px of it back and takes the same 3px as translateY, so the bottom edge holds.
  ctaLip: { borderBottomWidth: 4, borderBottomColor: paper.actionPressed },
  ctaDown: {
    backgroundColor: paper.actionPressed, transform: [{ translateY: 3 }],
    borderBottomWidth: 1, borderBottomColor: paper.actionPressed,
  },
  // [2026-08-20 · T4] ghostCta 삭제 — 그 스타일을 쓰던 유일한 소자가 '채팅 문의' 고스트 버튼이었고,
  // 그 버튼은 은퇴했다 (위 CTA 블록의 주석). 주인 없는 스타일을 남겨두면 다음 사람은 화면 어딘가에
  // 세컨더리 버튼이 있다고 읽는다. editChip/editSheet 계열도 같은 이유로 삭제됐다 — 편집기는
  // 이제 `/profile/edit`이고, 이 파일에는 편집 면이 하나도 없다.
  confirmBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: paper.ink, paddingHorizontal: 15, paddingTop: 14,
  },
  confirmBtn: { backgroundColor: paper.action, paddingVertical: 13, paddingHorizontal: 16 },
  emptyBox: { margin: 20, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 },
});
